"""Task-Endpunkte (Phase 4) und die Verwaltung laufender Auftraege.

Ein Task laeuft im Hintergrund, damit die Oberflaeche zusehen kann, wie der
Plan fortschreitet - `POST /api/tasks` gibt sofort eine ID zurueck, nicht erst
das Ergebnis.

`POST /api/tasks/{id}/cancel` gibt es, weil 0.5 es verlangt: ein laufender
Task muss sich abbrechen lassen.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field, fields
from typing import Any, Awaitable, Callable

from fastapi import FastAPI, APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from api.security import require_token
from core import db, memory
from core.contracts import Permission, Step, StepStatus, Task, TaskBudget, Tool
from core.llm import LLMReply
from core.agents import SPRACHSTIL
from core.runner import Laufzeit, fuehre_task_aus
from core.tools.dispatch import ToolCall

log = logging.getLogger("jarvis")

tasks_router = APIRouter(prefix="/api/tasks", dependencies=[Depends(require_token)])


class TaskCreate(BaseModel):
    goal: str = Field(min_length=1, max_length=10_000)
    # Phase 9: im Sprachmodus muss die Antwort kuerzer sein - ein vorgelesener
    # Absatz mit 500 Woertern ist unbrauchbar.
    voice: bool = False


class Bestaetigen(BaseModel):
    approve: bool


# 0.5 / Phase 5: unbeantwortete Rueckfragen laufen nach zehn Minuten ab.
# Danach gilt der Task als abgebrochen - nicht als bestaetigt.
BESTAETIGUNG_TIMEOUT_S = 600


@dataclass
class LaufenderTask:
    task: Task
    abbruch: asyncio.Event = field(default_factory=asyncio.Event)
    future: asyncio.Task | None = None
    # Werkzeugaufrufe entstehen, bevor die Antwort existiert. Sie werden
    # sofort geschrieben und am Ende an die Antwort gehaengt.
    aufruf_ids: list[int] = field(default_factory=list)
    # Die offene Rueckfrage, falls gerade eine ansteht (Phase 5).
    offene_frage: dict[str, Any] | None = None
    antwort: asyncio.Future | None = None


class TaskRegistry:
    """Die Tasks, die gerade laufen. Fertige leben nur noch in der Datenbank."""

    def __init__(self) -> None:
        self._laufend: dict[str, LaufenderTask] = {}

    def add(self, eintrag: LaufenderTask) -> None:
        self._laufend[eintrag.task.id] = eintrag

    def get(self, task_id: str) -> LaufenderTask | None:
        return self._laufend.get(task_id)

    def remove(self, task_id: str) -> None:
        self._laufend.pop(task_id, None)

    async def stop_alle(self) -> None:
        for eintrag in list(self._laufend.values()):
            eintrag.abbruch.set()
            if eintrag.future is not None and not eintrag.future.done():
                eintrag.future.cancel()
        self._laufend.clear()


def baue_laufzeit(app: FastAPI, eintrag: "LaufenderTask") -> Laufzeit:
    """Verdrahtet die Fortschrittsmeldungen des Runners mit der Datenbank.

    Nimmt die App, nicht den Request: bis FIX-08 stand hier `request`, und
    alle drei Aufrufer reichten ihn nur durch, um an `request.app.state` zu
    kommen. Ein Zeitplan (core/zeitplan.py) startet Auftraege OHNE Request -
    um 07:00, ohne dass jemand tippt. Wer einen Request hat, gibt
    `request.app`.
    """
    settings = app.state.settings
    pfad = settings.db_path
    bus = app.state.events
    task, abbruch = eintrag.task, eintrag.abbruch

    ENDZUSTAENDE = ("done", "failed", "aborted_budget", "cancelled")

    async def on_task(t: Task) -> None:
        # Der Endzustand wird hier bewusst NICHT geschrieben. Sonst meldet
        # GET /api/tasks/{id} "done", bevor die Antwort im Verlauf steht - und
        # ein Client, der daraufhin sofort /api/messages holt, sieht sie nicht.
        # Geschrieben wird er ganz am Ende, wenn alles andere steht.
        if t.status in ENDZUSTAENDE:
            return
        await asyncio.to_thread(db.save_task, pfad, t)
        bus.publish("task", {"id": t.id, "goal": t.goal, "status": t.status,
                             "depth": t.depth, "spent_tokens": t.spent_tokens,
                             "spent_cost_eur": round(t.spent_cost_eur, 6),
                             "spent_tool_calls": t.spent_tool_calls})

    async def on_step(t: Task, i: int, s: Step) -> None:
        await asyncio.to_thread(db.save_step, pfad, t.id, i, s)
        bus.publish("step", {"task_id": t.id, "index": i, "id": s.id,
                             "description": s.description.split("\n")[0],
                             "agent": s.agent, "status": s.status.value,
                             "attempts": s.attempts, "note": s.note})

    async def on_call(aufruf: ToolCall) -> None:
        ergebnis = aufruf.result
        zeile = await asyncio.to_thread(
            db.add_tool_call, pfad,
            message_id=None, name=aufruf.name, arguments=aufruf.arguments,
            ok=bool(ergebnis and ergebnis.ok),
            display=(ergebnis.display if ergebnis else ""),
            error=(ergebnis.error if ergebnis else None),
            sources=(list(ergebnis.sources) if ergebnis else []),
            duration_ms=(ergebnis.duration_ms if ergebnis else 0),
        )
        eintrag.aufruf_ids.append(zeile.id)
        bus.publish("tool", {"task_id": task.id, "name": aufruf.name,
                             "arguments": aufruf.arguments,
                             "ok": bool(ergebnis and ergebnis.ok),
                             "duration_ms": ergebnis.duration_ms if ergebnis else 0})

    async def on_reply(reply: LLMReply) -> None:
        """Jeder Modellzug in llm_calls - die Kostentabelle ist die Wahrheit."""
        await asyncio.to_thread(
            db.log_llm_call, pfad,
            model=reply.model, prompt_hash=reply.prompt_hash,
            in_tokens=reply.usage.in_tokens, out_tokens=reply.usage.out_tokens,
            cost_eur=settings.cost_eur(reply.usage.in_tokens,
                                       reply.usage.out_tokens),
            duration_ms=reply.duration_ms, ok=True,
        )

    async def on_subtask(unterauftrag: Task, parent_id: str | None) -> None:
        """Jeder Unterauftrag wird eigenstaendig persistiert.

        Daraus entsteht der Baum aus DoD 3: Hermes -> research -> Werkzeuge.
        """
        await asyncio.to_thread(
            db.save_task, pfad, unterauftrag, parent_task_id=parent_id
        )
        for i, schritt in enumerate(unterauftrag.steps):
            await asyncio.to_thread(db.save_step, pfad, unterauftrag.id, i, schritt)

    async def audit(**felder: Any) -> None:
        await asyncio.to_thread(
            db.log_audit, pfad, task_id=task.id, **felder
        )

    async def bestaetigung(
        tool: Tool, argumente: dict[str, Any], vorschau: str
    ) -> bool:
        """Haelt den Task an und wartet auf den Menschen.

        Der Schritt geht auf NEEDS_CONFIRMATION, die Vorschau steht in `note`
        und ist damit ueber `GET /api/tasks/{id}` sichtbar - das UI zeigt
        exakt, was passieren wuerde.
        """
        schritt = next(
            (s for s in task.steps if s.status is StepStatus.RUNNING), None
        )
        zukunft: asyncio.Future = asyncio.get_running_loop().create_future()
        frage = {
            "tool": tool.name,
            "permission": tool.permission.name,
            "arguments": argumente,
            "preview": vorschau,
            "step_id": schritt.id if schritt else None,
            "timeout_s": BESTAETIGUNG_TIMEOUT_S,
        }

        # Erst den Schritt festschreiben, dann die Frage sichtbar machen.
        # Andersherum sieht ein Client kurz eine offene Rueckfrage zu einem
        # Schritt, der laut Datenbank noch laeuft - ein Zustand, den es nicht
        # gibt.
        if schritt is not None:
            schritt.status = StepStatus.NEEDS_CONFIRMATION
            schritt.note = vorschau
            await on_step(task, task.steps.index(schritt), schritt)
        await on_task(task)

        eintrag.antwort = zukunft
        eintrag.offene_frage = frage
        bus.publish("confirmation", {"task_id": task.id, **frage})

        # BUGS-01 Fund 1a: der Abbruch muss die Rueckfrage WECKEN. Vorher
        # setzte /cancel nur `eintrag.abbruch` - hier hing der Task
        # unbeeindruckt in wait_for, die Rueckfrage blieb anklickbar, und wer
        # danach "Ausfuehren" drueckte, loeste das EXTERNAL-Werkzeug trotz
        # Abbruch aus.
        async def auf_abbruch_hoeren() -> None:
            await abbruch.wait()
            if not zukunft.done():
                zukunft.set_result(False)

        waechter = asyncio.create_task(auf_abbruch_hoeren())
        try:
            entschieden = await asyncio.wait_for(
                zukunft, timeout=BESTAETIGUNG_TIMEOUT_S
            )
        except asyncio.TimeoutError:
            log.warning("task %s: Rueckfrage zu %s lief ab", task.id, tool.name)
            await audit(tool=tool.name, arguments=argumente,
                        permission=tool.permission.name, decision="timeout",
                        executed=False, detail=vorschau)
            # Der Auftrag ist eindeutig: danach cancelled, nicht bestaetigt.
            abbruch.set()
            entschieden = False
        finally:
            waechter.cancel()
            eintrag.offene_frage = None
            eintrag.antwort = None
            if schritt is not None and schritt.status is StepStatus.NEEDS_CONFIRMATION:
                schritt.status = StepStatus.RUNNING
                await on_step(task, task.steps.index(schritt), schritt)

        # Abgebrochen heisst abgebrochen - auch wenn gleichzeitig jemand
        # "Ausfuehren" gedrueckt hat.
        if abbruch.is_set():
            return False

        return bool(entschieden)

    return Laufzeit(on_task=on_task, on_step=on_step, on_call=on_call,
                    on_subtask=on_subtask, on_reply=on_reply,
                    bestaetigung=bestaetigung,
                    audit=audit, abbruch=abbruch)


async def starte_task(app: FastAPI, ziel: str, *, voice: bool = False,
                      max_permission: Permission | None = None,
                      am_ende: Callable[[Task], Awaitable[None]] | None = None,
                      budget: TaskBudget | None = None,
                      ) -> Task:
    """Legt einen Task an und startet ihn im Hintergrund.

    `max_permission` ueberschreibt die Obergrenze aus der .env nach UNTEN -
    nie nach oben. Ein Zeitplan gibt hier LOCAL mit, weil um 07:00 niemand
    da ist, der eine E-Mail bestaetigen koennte (core/zeitplan.py, Regel 1).

    `am_ende` wird EINMAL gerufen, wenn der Task fertig ist und alles
    geschrieben wurde - egal wie er endete. Ein Zeitplan traegt damit den
    Ausgang an sich selbst nach. Ein Fehler darin bleibt im Log; der Task
    ist zu dem Zeitpunkt schon abgeschlossen.

    `budget` kann die Vorgaben aus der .env nur UNTERSCHREITEN. Jedes Feld,
    das hoeher waere, wird auf die Vorgabe gedrueckt - CLAUDE.md Regel 6
    gilt auch fuer Aufrufer im eigenen Haus.
    """
    settings = app.state.settings
    registry: TaskRegistry = app.state.tasks
    obergrenze = Permission(settings.max_permission)
    if max_permission is not None and max_permission < obergrenze:
        obergrenze = max_permission

    vorgabe = TaskBudget.from_settings(settings)
    if budget is not None:
        for feld in fields(TaskBudget):
            wert, grenze = getattr(budget, feld.name), getattr(vorgabe, feld.name)
            setattr(vorgabe, feld.name, min(wert, grenze))
    task = Task(goal=ziel, budget=vorgabe)
    eintrag = LaufenderTask(task=task)
    registry.add(eintrag)

    await asyncio.to_thread(db.save_task, settings.db_path, task)
    # Der Verlauf ist unabhaengig vom Task: was der Nutzer getippt hat, darf
    # auch dann nicht verloren gehen, wenn der Task scheitert.
    await asyncio.to_thread(db.add_message, settings.db_path, "user", ziel)

    async def lauf() -> None:
        try:
            await fuehre_task_aus(
                app.state.provider,
                ziel,
                budget=task.budget,
                kosten=settings.cost_eur,
                max_permission=obergrenze,
                task=task,
                laufzeit=baue_laufzeit(app, eintrag),
                antwortstil=SPRACHSTIL if voice else "",
            )
        except asyncio.CancelledError:
            task.status = "cancelled"
            task.abort_reason = "Abgebrochen."
            await asyncio.to_thread(db.save_task, settings.db_path, task)
            raise
        except Exception as exc:  # noqa: BLE001 - der Task darf den Server nicht mitreissen
            log.exception("task %s ist ausgestiegen", task.id)
            task.status = "failed"
            task.result = f"{type(exc).__name__}: {exc}"
            await asyncio.to_thread(db.save_task, settings.db_path, task)
        finally:
            antwort = (task.result or task.abort_reason or "Kein Ergebnis.").strip()
            nachricht = await asyncio.to_thread(
                db.add_message, settings.db_path, "assistant", antwort
            )
            await asyncio.to_thread(
                db.attach_tool_calls, settings.db_path,
                list(eintrag.aufruf_ids), nachricht.id,
            )
            await asyncio.to_thread(
                memory.log_task, settings.db_path, task.id,
                goal=ziel,
                outcome=task.status,
                summary=(task.result or task.abort_reason or "")[:500],
            )
            # Jetzt erst: der Task ist fertig UND alles ist geschrieben.
            await asyncio.to_thread(db.save_task, settings.db_path, task)
            app.state.events.publish("task", {
                "id": task.id, "goal": task.goal, "status": task.status,
                "depth": task.depth, "spent_tokens": task.spent_tokens,
                "spent_cost_eur": round(task.spent_cost_eur, 6),
                "spent_tool_calls": task.spent_tool_calls,
                "result": task.result, "abort_reason": task.abort_reason,
                "final": True,
            })
            registry.remove(task.id)
            if am_ende is not None:
                try:
                    await am_ende(task)
                except Exception:  # noqa: BLE001 - der Task ist schon fertig
                    log.exception("task %s: am_ende ist ausgestiegen", task.id)

    eintrag.future = asyncio.create_task(lauf())
    return task


def task_als_dict(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "goal": row["goal"],
        "status": row["status"],
        "depth": row["depth"],
        "parent_task_id": row["parent_task_id"],
        "budget": row["budget"],
        "spent_tokens": row["spent_tokens"],
        "spent_cost_eur": round(row["spent_cost_eur"], 6),
        "spent_tool_calls": row["spent_tool_calls"],
        "result": row["result"],
        "abort_reason": row["abort_reason"],
        "created_at": row["created_at"],
        "finished_at": row["finished_at"],
        "children": row.get("children", []),
        # Wird vom Endpunkt gesetzt, wenn gerade eine Rueckfrage offensteht.
        "confirmation": None,
        "steps": [
            {
                "id": s["id"],
                "index": s["idx"],
                "description": s["description"],
                "prompt": s["prompt"],
                "agent": s["agent"],
                "status": s["status"],
                "note": s["note"],
                "attempts": s["attempts"],
                "max_attempts": s["max_attempts"],
                "result": s["result"],
            }
            for s in row.get("steps", [])
        ],
    }


@tasks_router.post("", status_code=202)
async def post_task(request: Request, body: TaskCreate) -> dict[str, str]:
    ziel = body.goal.strip()
    if not ziel:
        raise HTTPException(status_code=422, detail="Das Ziel ist leer.")
    task = await starte_task(request.app, ziel, voice=body.voice)
    return {"task_id": task.id, "status": task.status}


@tasks_router.get("")
async def get_tasks(request: Request) -> list[dict[str, Any]]:
    pfad = request.app.state.settings.db_path
    return await asyncio.to_thread(db.list_task_rows, pfad)


@tasks_router.get("/{task_id}")
async def get_task(request: Request, task_id: str) -> dict[str, Any]:
    pfad = request.app.state.settings.db_path
    row = await asyncio.to_thread(db.get_task_row, pfad, task_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Task nicht gefunden.")
    daten = task_als_dict(row)
    eintrag = request.app.state.tasks.get(task_id)
    if eintrag is not None and eintrag.offene_frage is not None:
        daten["confirmation"] = eintrag.offene_frage
    return daten


@tasks_router.post("/{task_id}/confirm")
async def confirm_task(
    request: Request, task_id: str, body: Bestaetigen
) -> dict[str, Any]:
    """Beantwortet die offene Rueckfrage eines Tasks (Phase 5)."""
    registry: TaskRegistry = request.app.state.tasks
    eintrag = registry.get(task_id)
    # BUGS-01 Fund 1a: nach einem Abbruch darf die Rueckfrage nicht mehr
    # beantwortbar sein. Sonst kann der Nutzer sie bestaetigen, nachdem er
    # sie abgebrochen hat - und das Werkzeug laeuft.
    if eintrag is not None and eintrag.abbruch.is_set():
        raise HTTPException(
            status_code=409,
            detail="Der Auftrag wurde abgebrochen. Die Rueckfrage gilt nicht mehr.",
        )

    if eintrag is None:
        raise HTTPException(status_code=404, detail="Task laeuft nicht.")
    if eintrag.antwort is None or eintrag.antwort.done():
        raise HTTPException(
            status_code=409, detail="Zu diesem Task steht keine Frage offen."
        )
    eintrag.antwort.set_result(body.approve)
    return {"task_id": task_id, "approved": body.approve}


@tasks_router.post("/{task_id}/cancel")
async def cancel_task(request: Request, task_id: str) -> dict[str, Any]:
    """0.5: Ein laufender Task muss sich abbrechen lassen."""
    registry: TaskRegistry = request.app.state.tasks
    eintrag = registry.get(task_id)

    # Ein Task kann fertig sein und trotzdem noch kurz in der Registry
    # stehen - das Aufraeumen passiert im finally des Hintergrundlaufs. Ohne
    # diese Pruefung meldet der Endpunkt "cancelling" fuer etwas, das laengst
    # durch ist.
    ENDZUSTAENDE = ("done", "failed", "aborted_budget", "cancelled")
    if eintrag is None or eintrag.task.status in ENDZUSTAENDE:
        pfad = request.app.state.settings.db_path
        row = await asyncio.to_thread(db.get_task_row, pfad, task_id)
        if row is None:
            raise HTTPException(status_code=404, detail="Task nicht gefunden.")
        return {"task_id": task_id, "status": row["status"],
                "note": "Der Task lief nicht mehr."}

    eintrag.abbruch.set()
    return {"task_id": task_id, "status": "cancelling"}
