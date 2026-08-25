"""Delegation (Phase 6).

Hermes ist kein Magie-Agent. Hermes ist ein Agent, der andere Agenten als
Werkzeuge benutzt - mehr steht nicht dahinter.

Der Kontext (welcher Task, welche Agenten, welche Tiefe) haengt an einem
`ContextVar` statt an einem Modulglobal: mehrere Tasks koennen gleichzeitig
laufen, und jeder braucht seinen eigenen.
"""

from __future__ import annotations

import logging
import time
import uuid
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Awaitable, Callable

from core.contracts import Permission, Step, StepStatus, Task, Tool, ToolResult
from core.tools.registry import register

if TYPE_CHECKING:
    from core.agents import ToolAgent

log = logging.getLogger("jarvis")


@dataclass
class DelegationsKontext:
    task: Task
    agenten: dict[str, "ToolAgent"]
    max_depth: int
    # Wird fuer jeden Unterauftrag aufgerufen: der Baum in DoD 3 entsteht daraus.
    on_subtask: Callable[[Task, str | None], Awaitable[None]] | None = None
    abgelehnt: list[dict[str, Any]] = field(default_factory=list)


kontext: ContextVar[DelegationsKontext | None] = ContextVar(
    "delegationskontext", default=None
)


@register
class AskAgent(Tool):
    name = "ask_agent"
    description = (
        "Gibt einen Teilauftrag an einen anderen Agenten. Benutze das, wenn "
        "ein Schritt Faehigkeiten braucht, die du nicht hast - zum Beispiel "
        "Recherche im Web. Formuliere den Teilauftrag so, dass er allein "
        "verstaendlich ist; der Agent sieht dein Gespraech nicht."
    )
    parameters = {
        "type": "object",
        "properties": {
            "agent": {"type": "string", "description": "Name des Agenten."},
            "task": {
                "type": "string",
                "description": "Der Teilauftrag, vollstaendig ausformuliert.",
            },
        },
        "required": ["agent", "task"],
        "additionalProperties": False,
    }
    # Delegieren selbst hat keine Aussenwirkung. Was der gerufene Agent darf,
    # entscheidet dessen eigene max_permission - geprueft im Dispatcher.
    permission = Permission.INFO
    timeout_s = 300

    async def execute(self, agent: str, task: str) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        ctx = kontext.get()
        if ctx is None:
            return ToolResult(
                ok=False,
                error="Delegation ist hier nicht eingerichtet.",
                display="ask_agent kann ausserhalb eines Auftrags nichts tun.",
                duration_ms=dauer(),
            )

        if ctx.task.depth >= ctx.max_depth:
            # DoD 5: abgelehnt UND geloggt.
            grund = (
                f"Tiefe {ctx.task.depth} erreicht die Grenze max_depth="
                f"{ctx.max_depth}. Aus dieser Tiefe darf kein weiterer Agent "
                "gerufen werden - erledige den Rest selbst."
            )
            ctx.abgelehnt.append({"agent": agent, "task": task,
                                  "depth": ctx.task.depth, "reason": grund})
            log.warning(
                "task %s: Delegation an %s aus Tiefe %d abgelehnt (max_depth=%d)",
                ctx.task.id, agent, ctx.task.depth, ctx.max_depth,
            )
            return ToolResult(ok=False, error=grund, display=grund,
                              duration_ms=dauer())

        ziel_agent = ctx.agenten.get(agent)
        if ziel_agent is None:
            bekannt = ", ".join(sorted(n for n in ctx.agenten if n != "hermes"))
            return ToolResult(
                ok=False,
                error=f"Unbekannter Agent {agent!r}.",
                display=f"Es gibt keinen Agenten {agent!r}. Bekannt: {bekannt}.",
                duration_ms=dauer(),
            )

        # Der Unterauftrag bekommt KEIN eigenes Budget. Er zaehlt auf dasselbe -
        # sonst waere max_cost_eur eine Zahl ohne Bedeutung.
        unterauftrag = Task(goal=task, budget=ctx.task.budget,
                            depth=ctx.task.depth + 1)
        unterauftrag.status = "running"
        if ctx.on_subtask:
            await ctx.on_subtask(unterauftrag, ctx.task.id)

        schritt = Step(id=uuid.uuid4().hex[:12], description=task, agent=agent)
        schritt.status = StepStatus.RUNNING
        unterauftrag.steps = [schritt]

        eigener = kontext.set(DelegationsKontext(
            task=unterauftrag, agenten=ctx.agenten, max_depth=ctx.max_depth,
            on_subtask=ctx.on_subtask, abgelehnt=ctx.abgelehnt,
        ))
        try:
            ergebnis = await ziel_agent.run(unterauftrag, schritt)
        finally:
            kontext.reset(eigener)

        schritt.result = ergebnis
        schritt.status = StepStatus.DONE if ergebnis.ok else StepStatus.FAILED
        unterauftrag.status = "done" if ergebnis.ok else "failed"
        unterauftrag.result = ergebnis.display
        # Was der Unterauftrag verbraucht hat, gehoert dem Hauptauftrag.
        ctx.task.spent_tokens += unterauftrag.spent_tokens
        ctx.task.spent_cost_eur += unterauftrag.spent_cost_eur
        if ctx.on_subtask:
            await ctx.on_subtask(unterauftrag, ctx.task.id)

        # Herkunft ist Pflicht: kennzeichnen, welcher Teil von wem kam.
        return ToolResult(
            ok=ergebnis.ok,
            data={"agent": agent, "subtask_id": unterauftrag.id,
                  "sources": list(ergebnis.sources)},
            error=ergebnis.error,
            display=f"[{agent}] {ergebnis.display}",
            sources=list(ergebnis.sources),
            duration_ms=dauer(),
        )
