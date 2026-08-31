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

from core.abbruch import LaufBeendet
from core.contracts import Permission, Step, StepStatus, Task, Tool, ToolResult
from core.tools.registry import register
from core.verify import verifiziere

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
    # BUGS-01 Fund 15: WER ruft. Ohne diese Angabe laesst sich
    # `can_call_agents` nicht durchsetzen - und die Liste war genau deshalb
    # bis hierher reine Deko. `ToolAgent.run` setzt sie fuer die Dauer seines
    # Laufs; None heisst "kein Agent ruft" (Direktaufruf im Test).
    rufer: str | None = None


kontext: ContextVar[DelegationsKontext | None] = ContextVar(
    "delegationskontext", default=None
)


@register
class AskAgent(Tool):
    name = "ask_agent"
    description = (
        "Gibt einen Teilauftrag an einen anderen Agenten - research (Web, Wikipedia, Wikidata) oder satellite (Erdbeobachtung).\n"
        "Nimm es fuer: einen Schritt, der Faehigkeiten braucht, die du nicht hast; formuliere ihn allein verstaendlich, der Agent sieht dein Gespraech nicht. Andere Agentennamen als research und satellite werden abgelehnt.\n"
        "Nimm es NICHT fuer: eine Zeit- oder Rechenfrage, die du selbst mit clock oder calculator erledigst.\n"
        "Beispiel: ask_agent(agent=\"research\", task=\"Was kostet ein Santa Cruz V10 aktuell neu? Nenne Haendler und Quelle.\")"
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

        # BUGS-01 Fund 15: die Liste des Rufers ist eine Grenze, keine Deko.
        # hermes (LOCAL, ['research','satellite']) erreichte darueber auch
        # jarvis - und jarvis hat send_email in den Werkzeugen.
        rufender = ctx.agenten.get(ctx.rufer) if ctx.rufer else None
        if rufender is not None and agent not in rufender.can_call_agents:
            erlaubt = ", ".join(rufender.can_call_agents) or "keinen"
            grund = (
                f"{rufender.name} darf {agent!r} nicht rufen. "
                f"Erlaubt sind: {erlaubt}."
            )
            ctx.abgelehnt.append({"agent": agent, "task": task,
                                  "depth": ctx.task.depth, "reason": grund})
            log.warning("task %s: %s darf %s nicht rufen (erlaubt: %s)",
                        ctx.task.id, rufender.name, agent, erlaubt)
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
            # Der gerufene Agent setzt sich in `run` selbst als Rufer ein.
            rufer=None,
        ))
        try:
            try:
                ergebnis = await ziel_agent.run(unterauftrag, schritt)
            finally:
                kontext.reset(eigener)
        except LaufBeendet as ende:
            # Verknuepfungspruefung 31.08.2026, Fund 2, zweiter Teil.
            # `LaufBeendet` laeuft ab hier nach oben durch (der Dispatcher
            # gibt sie jetzt weiter, siehe core/tools/dispatch.py) - damit
            # wurde aber alles unterhalb uebersprungen, auch der zweite
            # `on_subtask`-Ruf. Der Unterauftrag und sein Schritt blieben
            # deshalb in der tasks- und steps-Tabelle fuer immer auf
            # "running": `api/tasks.py` persistiert beides nur ueber diesen
            # Rueckruf, und einen dritten gibt es nicht.
            #
            # Also hier abschliessen, bevor die Ausnahme weiterlaeuft. Der
            # Endzustand ist der der Ausnahme ("cancelled" oder
            # "aborted_budget"), nicht "failed" - der Unterauftrag ist nicht
            # gescheitert, er wurde beendet. Der Teiltext bleibt als
            # Ergebnis stehen, damit ein Teilergebnis moeglich bleibt (0.5).
            unterauftrag.status = ende.status
            unterauftrag.result = ende.teiltext
            schritt.status = StepStatus.FAILED
            schritt.note = ende.grund
            # Verbraucht ist verbraucht - auch ein abgebrochener
            # Unterauftrag hat das Budget des Hauptauftrags belastet.
            ctx.task.spent_tokens += unterauftrag.spent_tokens
            ctx.task.spent_cost_eur += unterauftrag.spent_cost_eur
            if ctx.on_subtask:
                await ctx.on_subtask(unterauftrag, ctx.task.id)
            raise

        # Verknuepfungspruefung 31.08.2026, Fund 1: hier stand
        #     schritt.status = DONE if ergebnis.ok else FAILED
        # und sonst nichts. Das war falsch, weil `ergebnis.ok` gar keine
        # Verifikation ist: `ToolAgent._run` setzt es auf `bool(text.strip())`
        # (core/agents.py) - jede nichtleere Antwort war damit "ok".
        #
        # `verifiziere()` (core/verify.py) wurde im Produktivcode an genau
        # EINER Stelle gerufen, in der Schrittschleife des Runners
        # (core/runner.py). Ein Unterauftrag ueber `ask_agent` laeuft aber
        # nicht durch diese Schleife, sondern ruft `ziel_agent.run` direkt.
        # Folge: fuer delegierte Schritte fielen ALLE drei Regeln aus -
        # die Quellenpflicht fuer `research`, die Preisregel und die
        # Aufgegeben-Regel. Dieselbe quellenlose Antwort desselben
        # research-Agenten war als Planschritt FAILED, als Unterauftrag von
        # hermes aber DONE. Wer `research` ueber hermes rief statt direkt,
        # umging die Quellenpflicht vollstaendig.
        #
        # Deshalb dieselbe Pruefung wie im Runner, an derselben Stelle im
        # Ablauf: erst verifizieren, dann Status und note daraus setzen.
        bestanden, begruendung = verifiziere(schritt, ergebnis)
        schritt.result = ergebnis
        schritt.note = begruendung
        schritt.status = StepStatus.DONE if bestanden else StepStatus.FAILED
        unterauftrag.status = "done" if bestanden else "failed"
        unterauftrag.result = ergebnis.display
        # Was der Unterauftrag verbraucht hat, gehoert dem Hauptauftrag.
        ctx.task.spent_tokens += unterauftrag.spent_tokens
        ctx.task.spent_cost_eur += unterauftrag.spent_cost_eur
        if ctx.on_subtask:
            await ctx.on_subtask(unterauftrag, ctx.task.id)

        # Die Begruendung muss beim Rufer ankommen, sonst hat die Pruefung
        # keine Wirkung: hermes verarbeitet das Teilergebnis weiter, ohne zu
        # merken, dass es die Quellenpflicht gerissen hat. `run_tool_loop`
        # (core/tools/loop.py) reicht `display` an das Modell und faellt nur
        # auf `error` zurueck, wenn `display` leer ist - deshalb steht die
        # Begruendung in BEIDEN Feldern. `ok=False` setzt zusaetzlich
        # `is_error` im tool_result-Block.
        #
        # Herkunft ist Pflicht: kennzeichnen, welcher Teil von wem kam.
        anzeige = f"[{agent}] {ergebnis.display}"
        if not bestanden:
            anzeige = f"{anzeige}\n\n[Nicht bestanden: {begruendung}]".strip()
        return ToolResult(
            ok=bestanden,
            data={"agent": agent, "subtask_id": unterauftrag.id,
                  "sources": list(ergebnis.sources)},
            error=ergebnis.error if bestanden else begruendung,
            display=anzeige,
            sources=list(ergebnis.sources),
            duration_ms=dauer(),
        )
