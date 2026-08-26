"""Die Runde Modell → Werkzeug → Modell.

Laeuft hoechstens `max_tool_calls` Runden. Wird die Grenze erreicht, bekommt
das Modell das gesagt und muss mit dem antworten, was es hat - der Loop
bricht nicht stumm ab und erhoeht die Grenze auch nicht selbst (0.5).
"""

from __future__ import annotations

import logging
from typing import Any, Awaitable, Callable, Iterable

from core.contracts import Permission
from core.llm import LLMMessage, LLMProvider, LLMReply
from core.tools import registry
from core.tools.dispatch import Audit, Bestaetigung, ToolCall, run_tool

log = logging.getLogger("jarvis")

BUDGET_HINWEIS = (
    "Du hast das Werkzeug-Budget dieses Auftrags aufgebraucht. Antworte jetzt "
    "mit dem, was du hast, und sag klar, was dadurch offen bleibt. Ruf kein "
    "weiteres Werkzeug."
)


def _mit_budgetnotiz(text: str, grund: str) -> str:
    """Haengt an, warum hier Schluss ist - statt stumm abzubrechen (0.5)."""
    notiz = f"[Budget des Auftrags aufgebraucht: {grund}]"
    return f"{text.strip()}\n\n{notiz}" if text.strip() else notiz


async def run_tool_loop(
    provider: LLMProvider,
    verlauf: list[LLMMessage],
    *,
    system: str,
    erlaubt: Iterable[str] | None = None,
    max_permission: Permission = Permission.SENSITIVE,
    max_tool_calls: int = 20,
    on_call: Callable[[ToolCall], Awaitable[None]] | None = None,
    on_reply: Callable[[LLMReply], Awaitable[None]] | None = None,
    bestaetigung: Bestaetigung | None = None,
    audit: Audit | None = None,
    budget: Callable[[], str | None] | None = None,
) -> tuple[str, list[ToolCall], list[LLMReply]]:
    """Gibt (Antworttext, ausgefuehrte Aufrufe, alle Modellantworten) zurueck.

    `budget` ist die Budgetpruefung des Auftrags. Sie gibt die Begruendung
    zurueck, wenn eine Grenze gerissen ist, sonst None.

    BUGS-01 Fund 4: `max_tool_calls` hier ist die Grenze des *Agenten*, nicht
    die des Auftrags. Die des Auftrags wurde frueher nur zwischen den
    Schritten geprueft - innerhalb eines Schritts waren `max_tokens`,
    `max_cost_eur`, `max_tool_calls` und `max_seconds` beliebig
    ueberschreitbar. Bei einem Ein-Schritt-Plan hatte der Auftrag damit
    praktisch kein Budget.
    """
    schemas = registry.schemas_for(erlaubt, max_permission)
    nachrichten = list(verlauf)
    aufrufe: list[ToolCall] = []
    antworten: list[LLMReply] = []
    budget_gemeldet = False

    while True:
        # Vor jedem bezahlten Zug. Der Zug, der die Grenze reisst, laeuft zu
        # Ende - danach wird hier nichts mehr ausgegeben.
        grund = budget() if budget is not None else None
        if grund is not None:
            log.warning("Auftragsbudget erreicht (%s) - Werkzeugrunde endet", grund)
            letzter = antworten[-1].text if antworten else ""
            return _mit_budgetnotiz(letzter, grund), aufrufe, antworten

        reply = await provider.complete(
            nachrichten,
            system=system,
            tools=schemas if schemas and not budget_gemeldet else None,
        )
        antworten.append(reply)
        if on_reply is not None:
            await on_reply(reply)

        if not reply.tool_uses:
            return reply.text, aufrufe, antworten

        # Die Assistenten-Bloecke muessen unveraendert zurueck, sonst kann das
        # Modell die tool_result-Zeile nicht zuordnen.
        nachrichten.append(
            LLMMessage(role="assistant", content=list(reply.content_blocks))
        )

        ergebnisbloecke: list[dict[str, Any]] = []
        gerissen: str | None = None
        for tool_use in reply.tool_uses:
            # Auch zwischen zwei Werkzeugen desselben Zuges. Ein Modell darf
            # mehrere auf einmal anfordern; die duerfen nicht alle noch
            # durchlaufen, nachdem die Grenze weg ist.
            gerissen = budget() if budget is not None else None
            if gerissen is not None:
                log.warning("Auftragsbudget erreicht (%s) - %s laeuft nicht mehr",
                            gerissen, tool_use.name)
                break

            if len(aufrufe) >= max_tool_calls:
                ergebnisbloecke.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use.id,
                    "content": BUDGET_HINWEIS,
                    "is_error": True,
                })
                budget_gemeldet = True
                log.warning(
                    "Werkzeug-Budget erreicht (%d), %s wird nicht ausgefuehrt",
                    max_tool_calls, tool_use.name,
                )
                continue

            ergebnis = await run_tool(
                tool_use.name,
                tool_use.input,
                max_permission=max_permission,
                erlaubt=erlaubt,
                bestaetigung=bestaetigung,
                audit=audit,
            )
            aufruf = ToolCall(
                name=tool_use.name, arguments=tool_use.input, result=ergebnis
            )
            aufrufe.append(aufruf)
            if on_call is not None:
                await on_call(aufruf)

            inhalt = ergebnis.display or ergebnis.error or (
                "ok" if ergebnis.ok else "fehlgeschlagen"
            )
            if ergebnis.ok and ergebnis.sources:
                inhalt += "\n\nQuellen:\n" + "\n".join(ergebnis.sources)

            ergebnisbloecke.append({
                "type": "tool_result",
                "tool_use_id": tool_use.id,
                "content": inhalt,
                **({"is_error": True} if not ergebnis.ok else {}),
            })

        if gerissen is not None:
            return _mit_budgetnotiz(reply.text, gerissen), aufrufe, antworten

        nachrichten.append(LLMMessage(role="user", content=ergebnisbloecke))
