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
) -> tuple[str, list[ToolCall], list[LLMReply]]:
    """Gibt (Antworttext, ausgefuehrte Aufrufe, alle Modellantworten) zurueck."""
    schemas = registry.schemas_for(erlaubt, max_permission)
    nachrichten = list(verlauf)
    aufrufe: list[ToolCall] = []
    antworten: list[LLMReply] = []
    budget_gemeldet = False

    while True:
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
        for tool_use in reply.tool_uses:
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

        nachrichten.append(LLMMessage(role="user", content=ergebnisbloecke))
