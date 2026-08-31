"""Tool-Dispatcher.

Hier - und nur hier - wird entschieden, ob ein Werkzeugaufruf laufen darf.
0.7: "Die Pruefung passiert im Tool-Dispatcher, nicht im Agent." Ein Agent
kann so nie mehr Rechte haben als seine `max_permission`, auch wenn ihm ein
maechtigeres Werkzeug in die Liste geschrieben wird.

Reihenfolge: gibt es das Tool → darf der Aufrufer → stimmen die Argumente →
ausfuehren mit Timeout. Jeder Fehlschlag ist ein `ToolResult(ok=False)`,
niemals eine Ausnahme nach oben.

Genau EINE Ausnahme davon: `LaufBeendet`. Das ist kein Fehlschlag des
Werkzeugs, sondern das Ende des Laufs - siehe die Begruendung unten am
`except LaufBeendet` (Verknuepfungspruefung 31.08.2026, Fund 2).
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Iterable

from core.abbruch import LaufBeendet
from core.contracts import Permission, Tool, ToolResult
from core.tools import registry
from core.tools.validate import pruefe

# Eine Bestaetigung beantwortet genau eine Frage: darf dieser Aufruf mit diesen
# Argumenten laufen? Sie bekommt das Tool und die Argumente, damit der
# Aufrufer dem Nutzer zeigen kann, was passieren wuerde.
Bestaetigung = Callable[[Tool, dict[str, Any], str], Awaitable[bool]]
Audit = Callable[..., Awaitable[None]]


def beschreibe_aufruf(tool: Tool, argumente: dict[str, Any]) -> str:
    """Was wuerde passieren - im Klartext, fuer die Rueckfrage.

    Ein Tool darf `vorschau()` anbieten und dann selbst erklaeren, was es tut.
    Ohne das bleibt es bei Name und Argumenten; das ist wenig, aber ehrlich.
    """
    vorschau = getattr(tool, "vorschau", None)
    if callable(vorschau):
        try:
            text = vorschau(**argumente)
            if text:
                return str(text)
        except Exception:  # noqa: BLE001 - eine kaputte Vorschau blockiert nichts
            pass
    argtext = ", ".join(f"{k}={v!r}" for k, v in argumente.items())
    return f"{tool.name}({argtext})"


@dataclass
class ToolCall:
    """Ein ausgefuehrter Aufruf - fuer Log und Oberflaeche."""

    name: str
    arguments: dict[str, Any] = field(default_factory=dict)
    result: ToolResult | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "arguments": self.arguments,
            "result": self.result.to_dict() if self.result else None,
        }


async def run_tool(
    name: str,
    arguments: dict[str, Any] | None = None,
    *,
    max_permission: Permission = Permission.SENSITIVE,
    erlaubt: Iterable[str] | None = None,
    bestaetigung: Bestaetigung | None = None,
    audit: Audit | None = None,
) -> ToolResult:
    begonnen = time.monotonic()

    def dauer() -> int:
        return int((time.monotonic() - begonnen) * 1000)

    argumente = arguments or {}

    tool = registry.get(name)
    if tool is None:
        bekannt = ", ".join(registry.names()) or "keine"
        return ToolResult(
            ok=False,
            error=f"Unbekanntes Werkzeug {name!r}.",
            display=f"Werkzeug {name!r} gibt es nicht. Bekannt: {bekannt}.",
            duration_ms=dauer(),
        )

    if erlaubt is not None and name not in set(erlaubt):
        return ToolResult(
            ok=False,
            error=f"Werkzeug {name!r} ist fuer diesen Agenten nicht freigegeben.",
            display=f"{name} steht diesem Agenten nicht zur Verfuegung.",
            duration_ms=dauer(),
        )

    if tool.permission > max_permission:
        return ToolResult(
            ok=False,
            error=(
                f"Werkzeug {name!r} braucht {tool.permission.name}, erlaubt ist "
                f"hoechstens {max_permission.name}."
            ),
            display=(
                f"{name} verlangt die Stufe {tool.permission.name}. "
                f"Dieser Aufrufer darf hoechstens {max_permission.name}."
            ),
            duration_ms=dauer(),
        )

    fehler = pruefe(tool.parameters, argumente)
    if fehler:
        return ToolResult(
            ok=False,
            error=f"Ungueltige Argumente: {fehler}",
            display=f"{name} bekam ungueltige Argumente: {fehler}",
            duration_ms=dauer(),
        )

    # --- Bestaetigung (0.4.6, Phase 5) ---------------------------------
    # Alles ab EXTERNAL wird protokolliert, egal wie es ausgeht.
    protokollieren = tool.permission >= Permission.EXTERNAL
    vorschau = beschreibe_aufruf(tool, argumente)

    if tool.requires_confirmation:
        if bestaetigung is None:
            if protokollieren and audit is not None:
                await audit(tool=tool.name, arguments=argumente,
                            permission=tool.permission.name, decision="denied",
                            executed=False, detail="Niemand konnte bestaetigen.")
            return ToolResult(
                ok=False,
                error=(
                    f"{name} braucht eine Bestaetigung, aber in diesem Zusammenhang "
                    "kann niemand bestaetigen."
                ),
                display=vorschau,
                duration_ms=dauer(),
            )

        erlaubt_vom_nutzer = await bestaetigung(tool, argumente, vorschau)
        if not erlaubt_vom_nutzer:
            if protokollieren and audit is not None:
                await audit(tool=tool.name, arguments=argumente,
                            permission=tool.permission.name, decision="denied",
                            executed=False, detail=vorschau)
            return ToolResult(
                ok=False,
                error="Nicht bestaetigt.",
                display=f"Nicht ausgefuehrt: {vorschau}",
                duration_ms=dauer(),
            )

    try:
        ergebnis = await asyncio.wait_for(
            tool.execute(**argumente), timeout=tool.timeout_s
        )
    except LaufBeendet:
        # Verknuepfungspruefung 31.08.2026, Fund 2: dieser Zweig fehlte, und
        # das allgemeine `except Exception` weiter unten hat den Abbruch
        # gefressen. `LaufBeendet` (core/abbruch.py) ist eine gewoehnliche
        # Exception - genau deshalb faengt `ToolAgent._run` sie ausdruecklich
        # ab und wirft sie weiter, mit dem Kommentar: "Wer das hier in ein
        # ToolResult verwandelt, macht aus dem Abbruch einen misslungenen
        # Schritt."
        #
        # Ueber `ask_agent` lief sie aber durch den Dispatcher: bricht der
        # Nutzer waehrend eines Unterauftrags ab, wirft der Pruefpunkt des
        # Unteragenten (core/tools/loop.py) `LaufBeendet`, die Ausnahme laeuft
        # durch `AskAgent.execute` nach oben - und wurde hier zu
        # "ask_agent ist mit einem Fehler ausgestiegen" degradiert. Dabei ging
        # dreierlei verloren: der Teiltext des Unteragenten (die Ausnahme mit
        # `teiltext` wurde verworfen), der zweite `on_subtask`-Ruf (der
        # Unterauftrag blieb in der tasks-Tabelle fuer immer auf "running"),
        # und im Werkzeugprotokoll stand ein Fehler, den niemand verursacht
        # hat.
        #
        # Der Dispatcher darf jeden Werkzeugfehler abfangen - aber nicht das
        # Ende des Laufs. Diese eine Ausnahme geht durch.
        raise
    except asyncio.TimeoutError:
        return ToolResult(
            ok=False,
            error=f"Zeitueberschreitung nach {tool.timeout_s} s.",
            display=f"{name} hat laenger als {tool.timeout_s} s gebraucht und "
                    "wurde abgebrochen.",
            duration_ms=dauer(),
        )
    except TypeError as exc:
        # Falsche Signatur - das Schema und execute() passen nicht zusammen.
        return ToolResult(
            ok=False,
            error=f"Aufruf passt nicht zur Signatur: {exc}",
            display=f"{name} konnte mit diesen Argumenten nicht aufgerufen werden.",
            duration_ms=dauer(),
        )
    except Exception as exc:  # noqa: BLE001 - ein Tool reisst nie den Task um
        return ToolResult(
            ok=False,
            error=f"{type(exc).__name__}: {exc}",
            display=f"{name} ist mit einem Fehler ausgestiegen.",
            duration_ms=dauer(),
        )

    if not isinstance(ergebnis, ToolResult):
        return ToolResult(
            ok=False,
            error=f"{name} hat {type(ergebnis).__name__} statt ToolResult geliefert.",
            display=f"{name} haelt sich nicht an den Vertrag.",
            duration_ms=dauer(),
        )

    if not ergebnis.duration_ms:
        ergebnis.duration_ms = dauer()

    if protokollieren and audit is not None:
        await audit(
            tool=tool.name, arguments=argumente,
            permission=tool.permission.name,
            decision="approved" if tool.requires_confirmation else "auto",
            executed=True, ok=ergebnis.ok, detail=vorschau,
        )
    return ergebnis
