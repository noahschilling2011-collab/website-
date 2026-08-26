"""Task-Runner (Phase 4).

Die Reihenfolge ist Absicht und steht so im Auftrag:

* Jede Budgetgrenze wird **vor** jedem Schritt geprueft, nicht danach (0.5).
* Ein Schritt wird persistiert, **bevor** er laeuft - sonst ist nach einem
  Absturz nicht nachvollziehbar, was gerade passierte.
* Verifikation ist ein eigener, billiger Schritt aus `core/verify.py` -
  Code, kein Modell, das sich selbst benotet.
* Bei Ueberschreitung: `aborted_budget`, Teilergebnis zurueck, Begruendung
  benennen. **Nicht** stillschweigend weiterlaufen und nicht selbst erhoehen.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Awaitable, Callable

from core.agents import ToolAgent, baue_agenten
from core.delegation import DelegationsKontext, kontext as delegationskontext
from core.contracts import (
    Permission,
    Step,
    StepStatus,
    Task,
    TaskBudget,
    ToolResult,
)
from core.llm import LLMMessage, LLMProvider, LLMReply
from core.planner import PlanungFehlgeschlagen, erstelle_plan
from core.tools.dispatch import Audit, Bestaetigung, ToolCall
from core.verify import verifiziere

log = logging.getLogger("jarvis")

# Strukturelle Obergrenze fuer den Plan - bewusst NICHT das Budget. Wuerde der
# Plan aufs Budget gekuerzt, koennte max_steps nie greifen, und der Nutzer
# saehe nie, dass sein Ziel groesser war als das Budget. Der Plan darf also
# zu gross sein; das Budget stoppt ihn dann waehrend der Ausfuehrung, mit
# Teilergebnis.
PLAN_MAX_STEPS = 12


class gebucht:
    """Huellt einen Provider so ein, dass jeder Zug gebucht wird.

    Der Planner ruft `complete` direkt, nicht ueber den Tool-Loop - ohne
    diese Huelle waere sein Verbrauch unsichtbar.
    """

    def __init__(self, provider: LLMProvider, buche) -> None:  # noqa: ANN001
        self._provider = provider
        self._buche = buche
        self.name = getattr(provider, "name", "?")
        self.model = getattr(provider, "model", "")

    async def complete(self, messages, *, system, tools=None):  # noqa: ANN001, ANN201
        reply = await self._provider.complete(messages, system=system, tools=tools)
        await self._buche(reply)
        return reply

    async def aclose(self) -> None:
        return None

ABSCHLUSS_PROMPT = """Du bist JARVIS und fasst die Ergebnisse eines Auftrags
fuer den Nutzer zusammen.

REGELN:
1. Antworte nur mit dem, was in den Schritt-Ergebnissen steht. Ergaenze nichts
   aus dem Gedaechtnis.
2. Jede Zahl und jede Tatsachenbehauptung bekommt die Quelle in Klammern
   dahinter, als vollstaendige URL.
3. Wenn ein Schritt fehlgeschlagen ist, sag welcher und was dadurch offen
   bleibt. Tu nicht so, als waere alles beantwortet.
4. Knapp. Keine Einleitung, kein "Gerne!"."""


@dataclass
class Laufzeit:
    """Was der Runner nach aussen meldet, waehrend er laeuft."""

    on_task: Callable[[Task], Awaitable[None]] | None = None
    on_step: Callable[[Task, int, Step], Awaitable[None]] | None = None
    on_call: Callable[[ToolCall], Awaitable[None]] | None = None
    on_subtask: Callable[[Task, str | None], Awaitable[None]] | None = None
    # Jeder Modellzug - fuer das Kostenprotokoll in llm_calls.
    on_reply: Callable[[LLMReply], Awaitable[None]] | None = None
    bestaetigung: Bestaetigung | None = None
    audit: Audit | None = None
    abbruch: asyncio.Event | None = None

    async def task(self, t: Task) -> None:
        if self.on_task:
            await self.on_task(t)

    async def step(self, t: Task, i: int, s: Step) -> None:
        if self.on_step:
            await self.on_step(t, i, s)

    def abgebrochen(self) -> bool:
        return self.abbruch is not None and self.abbruch.is_set()


async def fuehre_task_aus(
    provider: LLMProvider,
    ziel: str,
    *,
    budget: TaskBudget,
    kosten: Callable[[int, int], float],
    max_permission: Permission = Permission.LOCAL,
    agenten: dict[str, ToolAgent] | None = None,
    task: Task | None = None,
    laufzeit: Laufzeit | None = None,
    antwortstil: str = "",
) -> Task:
    laufzeit = laufzeit or Laufzeit()
    task = task or Task(goal=ziel, budget=budget)
    task.goal = ziel
    task.budget = budget
    task.status = "running"

    async def buche(reply: LLMReply) -> None:
        """Jeder Modellzug zaehlt aufs Budget - auch der des Planners."""
        task.spent_tokens += reply.usage.in_tokens + reply.usage.out_tokens
        task.spent_cost_eur += kosten(reply.usage.in_tokens, reply.usage.out_tokens)
        # ...und landet im Kostenprotokoll. Ohne das waere llm_calls seit
        # Phase 4 unvollstaendig gewesen: der Task-Pfad haette nichts
        # geschrieben, und jede Kostenanzeige waere zu niedrig.
        if laufzeit.on_reply is not None:
            await laufzeit.on_reply(reply)

    async def buche_werkzeug(aufruf: ToolCall) -> None:
        task.spent_tool_calls += 1
        if laufzeit.on_call:
            await laufzeit.on_call(aufruf)

    def verbrauchsgrenze() -> str | None:
        """Waehrend eines Schritts zaehlt nur der Verbrauch (BUGS-01 Fund 4).

        `max_steps` und `max_depth` zaehlen den laufenden Schritt schon mit -
        die wuerden hier immer reissen und ihn toeten, bevor er etwas tut.
        """
        return task.budget_verletzung(nur_verbrauch=True)

    verfuegbar = agenten or baue_agenten(
        provider, max_permission=max_permission, antwortstil=antwortstil,
        on_reply=buche, on_call=buche_werkzeug,
        bestaetigung=laufzeit.bestaetigung, audit=laufzeit.audit,
        # BUGS-01 Fund 4: damit das Budget auch INNERHALB eines Schritts gilt.
        budget_pruefung=verbrauchsgrenze,
    )

    # Der Delegationskontext gilt fuer den ganzen Lauf: er sagt ask_agent,
    # in welchem Task es sich befindet und wie tief es noch gehen darf.
    ctx = DelegationsKontext(
        task=task, agenten=verfuegbar, max_depth=budget.max_depth,
        on_subtask=laufzeit.on_subtask,
    )
    marke = delegationskontext.set(ctx)

    try:
        return await _lauf(
            provider, task, budget, kosten, verfuegbar, laufzeit, buche, ctx,
            antwortstil,
        )
    finally:
        delegationskontext.reset(marke)


async def _lauf(
    provider: LLMProvider,
    task: Task,
    budget: TaskBudget,
    kosten: Callable[[int, int], float],
    verfuegbar: dict[str, ToolAgent],
    laufzeit: Laufzeit,
    buche: Callable[[LLMReply], Awaitable[None]],
    ctx: DelegationsKontext,
    antwortstil: str = "",
) -> Task:
    ziel = task.goal
    await laufzeit.task(task)

    # --- Plan --------------------------------------------------------------
    try:
        task.steps = await erstelle_plan(
            gebucht(provider, buche),
            ziel,
            agenten={n: a.description for n, a in verfuegbar.items()
                     if n != "jarvis"},
            max_steps=PLAN_MAX_STEPS,
        )
    except PlanungFehlgeschlagen as exc:
        task.status = "failed"
        task.result = str(exc)
        await laufzeit.task(task)
        return task

    for i, schritt in enumerate(task.steps):
        await laufzeit.step(task, i, schritt)
    await laufzeit.task(task)

    async def budget_reissleine(ab: int, *, nur_verbrauch: bool = False) -> str | None:
        """0.5: Grenze gerissen -> Task beenden, Rest ueberspringen.

        Gibt die Begruendung zurueck, oder None, wenn noch Luft ist.
        `nur_verbrauch` siehe `Task.budget_verletzung`.
        """
        verletzung = task.budget_verletzung(nur_verbrauch=nur_verbrauch)
        if not verletzung:
            return None
        task.status = "aborted_budget"
        task.abort_reason = verletzung
        log.warning("task %s: Budget - %s", task.id, verletzung)
        for rest in task.steps[ab:]:
            if rest.status is StepStatus.PENDING:
                rest.status = StepStatus.SKIPPED
                await laufzeit.step(task, task.steps.index(rest), rest)
        return verletzung

    # --- Schritte ----------------------------------------------------------
    for i, schritt in enumerate(task.steps):
        if laufzeit.abgebrochen():
            task.status = "cancelled"
            task.abort_reason = "Vom Nutzer abgebrochen."
            for rest in task.steps[i:]:
                if rest.status is StepStatus.PENDING:
                    rest.status = StepStatus.SKIPPED
                    await laufzeit.step(task, task.steps.index(rest), rest)
            await laufzeit.task(task)
            return task

        # 0.5: VOR dem Schritt, nicht danach.
        if await budget_reissleine(i):
            break

        agent = verfuegbar.get(schritt.agent or "jarvis") or verfuegbar["jarvis"]

        gerissen = False
        while True:
            # BUGS-01 Fund 4: auch vor jedem WIEDERHOLVERSUCH. Ein Schritt, der
            # die Verifikation nicht besteht, wurde sonst noch einmal gestartet,
            # obwohl das Budget beim ersten Versuch schon weg war. Ein zweiter
            # Versuch ist kein zweiter Schritt - deshalb nur der Verbrauch.
            if await budget_reissleine(i, nur_verbrauch=True):
                gerissen = True
                break

            schritt.attempts += 1
            schritt.status = StepStatus.RUNNING
            await laufzeit.step(task, i, schritt)

            ergebnis = await agent.run(task, schritt)
            bestanden, begruendung = verifiziere(schritt, ergebnis)
            schritt.result = ergebnis
            schritt.note = begruendung

            if bestanden:
                schritt.status = StepStatus.DONE
                await laufzeit.step(task, i, schritt)
                break

            log.info(
                "task %s Schritt %d: Versuch %d/%d nicht bestanden - %s",
                task.id, i + 1, schritt.attempts, schritt.max_attempts, begruendung,
            )

            if schritt.attempts >= schritt.max_attempts:
                schritt.status = StepStatus.FAILED
                await laufzeit.step(task, i, schritt)
                break

            # Der naechste Versuch bekommt gesagt, was gefehlt hat - sonst
            # macht er denselben Fehler nochmal.
            schritt.description = (
                f"{schritt.description}\n\n[Vorheriger Versuch nicht bestanden: "
                f"{begruendung}]"
            )
            schritt.status = StepStatus.PENDING
            await laufzeit.step(task, i, schritt)

        if gerissen:
            break

        # BUGS-01 Fund 4: NACH dem Schritt, nicht erst vor dem naechsten.
        # Sonst endet ein Ein-Schritt-Plan auf "done", obwohl er das Budget
        # ueberzogen hat.
        if await budget_reissleine(i + 1):
            break

        # BUGS-01 Fund 1b: NACH dem Schritt noch einmal pruefen. Vorher lag
        # die Pruefung nur VOR dem naechsten - bei einem Ein-Schritt-Plan
        # (und darauf ist der Planner getrimmt) war der Abbrechen-Knopf damit
        # wirkungslos: der Auftrag lief zu Ende, verbrauchte noch zwei
        # Modellaufrufe und meldete sich als "done".
        if laufzeit.abgebrochen():
            task.status = "cancelled"
            task.abort_reason = "Vom Nutzer abgebrochen."
            for rest in task.steps[i + 1:]:
                if rest.status is StepStatus.PENDING:
                    rest.status = StepStatus.SKIPPED
                    await laufzeit.step(task, task.steps.index(rest), rest)
            await laufzeit.task(task)
            break

    # --- Abschluss ---------------------------------------------------------
    erledigt = [s for s in task.steps if s.status is StepStatus.DONE]
    gescheitert = [s for s in task.steps if s.status is StepStatus.FAILED]

    # Ein abgebrochener Auftrag bekommt KEINE Zusammenfassung mehr - die waere
    # ein weiterer bezahlter Modellaufruf nach dem Abbruch. Was fertig wurde,
    # steht als Teilergebnis da; das verlangt 0.5 ausdruecklich.
    if task.status == "cancelled":
        teile = [f"### {s.description}\n{(s.result.display if s.result else '')}"
                 for s in erledigt]
        task.result = (
            ("Abgebrochen. Was bis dahin fertig wurde:\n\n" + "\n\n".join(teile))
            if teile else "Abgebrochen, bevor ein Schritt fertig war."
        )
        await laufzeit.task(task)
        return task

    if not erledigt:
        task.status = task.status if task.status == "aborted_budget" else "failed"
        task.result = (
            "Kein Schritt ist durchgelaufen. "
            + (task.abort_reason or "")
            + (f" Zuletzt: {gescheitert[-1].note}" if gescheitert else "")
        ).strip()
        await laufzeit.task(task)
        return task

    task.result = await _fasse_zusammen(
        provider, task, erledigt, gescheitert, buche, antwortstil
    )
    if task.status == "running":
        task.status = "done" if not gescheitert else "failed"
    await laufzeit.task(task)
    return task


async def _fasse_zusammen(
    provider: LLMProvider,
    task: Task,
    erledigt: list[Step],
    gescheitert: list[Step],
    buche: Callable[[LLMReply], Awaitable[None]],
    antwortstil: str = "",
) -> str:
    teile = [f"Ziel: {task.goal}", "", "Ergebnisse der Schritte:"]
    quellen: list[str] = []
    for s in erledigt:
        teile.append(f"\n### {s.description}\n{(s.result.display if s.result else '')}")
        for url in (s.result.sources if s.result else []):
            if url not in quellen:
                quellen.append(url)
    for s in gescheitert:
        teile.append(f"\n### FEHLGESCHLAGEN: {s.description}\nGrund: {s.note}")
    if task.abort_reason:
        teile.append(f"\nHINWEIS: Der Auftrag wurde abgebrochen - {task.abort_reason}")

    try:
        reply = await provider.complete(
            [LLMMessage("user", "\n".join(teile))],
            system=ABSCHLUSS_PROMPT + antwortstil,
        )
        await buche(reply)
        text = reply.text.strip()
    except Exception as exc:  # noqa: BLE001 - lieber roh als gar nichts
        log.warning("task %s: Zusammenfassung fehlgeschlagen - %s", task.id, exc)
        text = "\n\n".join(
            (s.result.display if s.result else "") for s in erledigt
        ).strip()

    # Die Quellen haengen wir selbst an. Ob das Modell sie im Text zitiert, ist
    # eine Bitte; dass sie unter der Antwort stehen, ist eine Tatsache.
    #
    # Das Abrufdatum ist der heutige Tag: die Seiten wurden in diesem Lauf
    # geholt. Es steht dran, weil ein Preis ohne Datum in drei Wochen falsch
    # ist, ohne dass man es merkt.
    if quellen and not antwortstil:
        heute = time.strftime("%Y-%m-%d", time.gmtime())
        text += "\n\nQuellen:\n" + "\n".join(
            f"- {u} (abgerufen am {heute})" for u in quellen
        )
    return text
