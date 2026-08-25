"""Tool-Dispatcher.

Hier - und nur hier - wird entschieden, ob ein Werkzeugaufruf laufen darf.
0.7: "Die Pruefung passiert im Tool-Dispatcher, nicht im Agent." Ein Agent
kann so nie mehr Rechte haben als seine `max_permission`, auch wenn ihm ein
maechtigeres Werkzeug in die Liste geschrieben wird.

Reihenfolge: gibt es das Tool → darf der Aufrufer → stimmen die Argumente →
ausfuehren mit Timeout. Jeder Fehlschlag ist ein `ToolResult(ok=False)`,
niemals eine Ausnahme nach oben.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Any, Iterable

from core.contracts import Permission, ToolResult
from core.tools import registry
from core.tools.validate import pruefe


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

    try:
        ergebnis = await asyncio.wait_for(
            tool.execute(**argumente), timeout=tool.timeout_s
        )
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
    return ergebnis
