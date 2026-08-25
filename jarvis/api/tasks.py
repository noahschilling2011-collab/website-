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
from dataclasses import dataclass, field
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from api.security import require_token
from core import db, memory
from core.contracts import Permission, Step, StepStatus, Task, TaskBudget
from core.llm import LLMReply
from core.runner import Laufzeit, fuehre_task_aus
from core.tools.dispatch import ToolCall

log = logging.getLogger("jarvis")

tasks_router = APIRouter(prefix="/api/tasks", dependencies=[Depends(require_token)])


class TaskCreate(BaseModel):
    goal: str = Field(min_length=1, max_length=10_000)


@dataclass
class LaufenderTask:
    task: Task
    abbruch: asyncio.Event = field(default_factory=asyncio.Event)
    future: asyncio.Task | None = None
    # Werkzeugaufrufe entstehen, bevor die Antwort existiert. Sie werden
    # sofort geschrieben und am Ende an die Antwort gehaengt.
    aufruf_ids: list[int] = field(default_factory=list)


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


def baue_laufzeit(request: Request, eintrag: "LaufenderTask") -> Laufzeit:
    """Verdrahtet die Fortschrittsmeldungen des Runners mit der Datenbank."""
    pfad = request.app.state.settings.db_path
    task, abbruch = eintrag.task, eintrag.abbruch

    async def on_task(t: Task) -> None:
        await asyncio.to_thread(db.save_task, pfad, t)

    async def on_step(t: Task, i: int, s: Step) -> None:
        await asyncio.to_thread(db.save_step, pfad, t.id, i, s)

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

    return Laufzeit(on_task=on_task, on_step=on_step, on_call=on_call,
                    abbruch=abbruch)


async def starte_task(request: Request, ziel: str) -> Task:
    """Legt einen Task an und startet ihn im Hintergrund."""
    settings = request.app.state.settings
    registry: TaskRegistry = request.app.state.tasks

    task = Task(goal=ziel, budget=TaskBudget.from_settings(settings))
    eintrag = LaufenderTask(task=task)
    registry.add(eintrag)

    await asyncio.to_thread(db.save_task, settings.db_path, task)
    # Der Verlauf ist unabhaengig vom Task: was der Nutzer getippt hat, darf
    # auch dann nicht verloren gehen, wenn der Task scheitert.
    await asyncio.to_thread(db.add_message, settings.db_path, "user", ziel)

    async def lauf() -> None:
        try:
            await fuehre_task_aus(
                request.app.state.provider,
                ziel,
                budget=task.budget,
                kosten=settings.cost_eur,
                max_permission=Permission(settings.max_permission),
                task=task,
                laufzeit=baue_laufzeit(request, eintrag),
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
            registry.remove(task.id)

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
        "steps": [
            {
                "id": s["id"],
                "index": s["idx"],
                "description": s["description"],
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
    task = await starte_task(request, ziel)
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
    return task_als_dict(row)


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
