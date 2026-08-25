"""Endpunkte.

Zwei Grundsaetze:

* Der Modellaufruf passiert **ausserhalb** jeder offenen Transaktion. Er
  dauert Sekunden; solange eine Schreibsperre zu halten, blockiert alles.
* Jeder Modellaufruf wird protokolliert - auch der fehlgeschlagene. Sonst
  faellt eine Retry-Schleife, die Geld verbrennt, erst auf der Rechnung auf.
"""

from __future__ import annotations

import asyncio
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse

from api.schemas import (
    ChatRequest,
    ChatResponse,
    FactCreate,
    FactCreated,
    FactOut,
    FactUpdate,
    HealthOut,
    MessageOut,
    SpendOut,
    TaskLogOut,
    ToolCallOut,
)
from api.security import require_token
from core import db, memory
from core.contracts import Permission
from core.llm import LLMError, LLMMessage, LLMReply
from core.tools import registry
from core.tools.dispatch import ToolCall
from core.tools.loop import run_tool_loop

log = logging.getLogger("jarvis")

router = APIRouter()
api = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


def _settings(request: Request):
    return request.app.state.settings


@api.get("/health", response_model=HealthOut)
async def health(request: Request) -> HealthOut:
    settings = _settings(request)
    provider = request.app.state.provider

    try:
        anzahl = await asyncio.to_thread(db.count_messages, settings.db_path)
        totals = await asyncio.to_thread(db.llm_call_totals, settings.db_path)
        database = "ok"
    except Exception as exc:  # die Meldung soll die Ursache zeigen
        anzahl, totals, database = 0, {}, f"fehler: {exc}"

    provider_error = getattr(provider, "reason", None)
    return HealthOut(
        status="ok" if database == "ok" and provider_error is None else "degraded",
        phase=2,
        provider=provider.name,
        model=provider.model,
        api_key_configured=bool(settings.llm_api_key),
        api_key_hint=settings.masked_api_key(),
        provider_error=provider_error,
        database=database,
        messages=anzahl,
        spend=SpendOut(
            calls=int(totals.get("calls", 0)),
            in_tokens=int(totals.get("in_tokens", 0)),
            out_tokens=int(totals.get("out_tokens", 0)),
            cost_eur=float(totals.get("cost_eur", 0.0)),
            prices_configured=settings.prices_configured,
        ),
    )


@api.get("/messages", response_model=list[MessageOut])
async def get_messages(request: Request) -> list[MessageOut]:
    settings = _settings(request)
    messages = await asyncio.to_thread(db.list_messages, settings.db_path)
    gruppen = await asyncio.to_thread(db.tool_calls_by_message, settings.db_path)
    return [MessageOut.of(m, gruppen.get(m.id, [])) for m in messages]


@api.post("/chat", response_model=ChatResponse)
async def post_chat(request: Request, body: ChatRequest) -> ChatResponse:
    settings = _settings(request)
    provider = request.app.state.provider

    text = body.message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Die Nachricht ist leer.")

    task_id = uuid.uuid4().hex[:12]

    # 1. Nutzernachricht festschreiben, Verlauf lesen.
    await asyncio.to_thread(db.add_message, settings.db_path, "user", text)
    history = await asyncio.to_thread(
        db.list_messages, settings.db_path, settings.history_limit
    )

    # Werkzeugaufrufe werden geschrieben, sobald sie passieren - noch ohne
    # message_id, die Antwort gibt es ja noch nicht. Sonst waere nach einem
    # Absturz mitten in der Schleife nicht nachvollziehbar, was schon lief.
    aufruf_ids: list[int] = []
    aufrufe: list[ToolCall] = []

    async def merke_aufruf(aufruf: ToolCall) -> None:
        aufrufe.append(aufruf)
        ergebnis = aufruf.result
        zeile = await asyncio.to_thread(
            db.add_tool_call,
            settings.db_path,
            message_id=None,
            name=aufruf.name,
            arguments=aufruf.arguments,
            ok=bool(ergebnis and ergebnis.ok),
            display=(ergebnis.display if ergebnis else ""),
            error=(ergebnis.error if ergebnis else None),
            sources=(list(ergebnis.sources) if ergebnis else []),
            duration_ms=(ergebnis.duration_ms if ergebnis else 0),
        )
        aufruf_ids.append(zeile.id)
        log.info(
            "task %s: Werkzeug %s(%s) -> ok=%s in %d ms",
            task_id, aufruf.name, aufruf.arguments,
            bool(ergebnis and ergebnis.ok),
            ergebnis.duration_ms if ergebnis else 0,
        )

    async def protokolliere_modellaufruf(reply: LLMReply) -> None:
        kosten = settings.cost_eur(reply.usage.in_tokens, reply.usage.out_tokens)
        await asyncio.to_thread(
            db.log_llm_call,
            settings.db_path,
            model=reply.model,
            prompt_hash=reply.prompt_hash,
            in_tokens=reply.usage.in_tokens,
            out_tokens=reply.usage.out_tokens,
            cost_eur=kosten,
            duration_ms=reply.duration_ms,
            ok=True,
        )

    # Passende Fakten in den Systemprompt heben. Jede Zeile traegt ihre
    # Fakt-ID, damit die Herkunft sichtbar bleibt (Phase 3).
    gedaechtnis = await asyncio.to_thread(
        memory.kontextblock, settings.db_path, text
    )
    systemprompt = (
        f"{settings.system_prompt}\n\n{gedaechtnis}"
        if gedaechtnis
        else settings.system_prompt
    )
    if gedaechtnis:
        log.info("task %s: %d Fakten in den Kontext gehoben",
                 task_id, gedaechtnis.count("\n- "))

    # 2. Modell fragen, Werkzeuge laufen lassen. Keine Transaktion offen.
    try:
        antwort, _, _ = await run_tool_loop(
            provider,
            [LLMMessage(role=m.role, content=m.content) for m in history],
            system=systemprompt,
            max_permission=Permission(settings.max_permission),
            max_tool_calls=settings.budget_max_tool_calls,
            on_call=merke_aufruf,
            on_reply=protokolliere_modellaufruf,
        )
    except LLMError as exc:
        await asyncio.to_thread(
            db.log_llm_call,
            settings.db_path,
            model=provider.model or "unbekannt",
            prompt_hash=exc.prompt_hash,
            in_tokens=0,
            out_tokens=0,
            cost_eur=0.0,
            duration_ms=exc.duration_ms,
            ok=False,
        )
        await asyncio.to_thread(
            memory.log_task, settings.db_path, task_id,
            goal=text, outcome="failed", summary=str(exc)[:500],
        )
        log.warning("task %s: Modellaufruf fehlgeschlagen - %s", task_id, exc)
        raise

    # 3. Antwort festschreiben und die Aufrufe daranhaengen.
    nachricht = await asyncio.to_thread(
        db.add_message, settings.db_path, "assistant", antwort
    )
    await asyncio.to_thread(
        db.attach_tool_calls, settings.db_path, aufruf_ids, nachricht.id
    )

    # Episodisches Gedaechtnis: was war der Auftrag, wie ging er aus.
    await asyncio.to_thread(
        memory.log_task, settings.db_path, task_id,
        goal=text, outcome="done",
        summary=antwort if len(antwort) <= 500 else antwort[:499] + "…",
    )

    return ChatResponse(
        reply=antwort,
        task_id=task_id,
        tool_calls=[
            ToolCallOut(
                name=a.name,
                arguments=a.arguments,
                ok=bool(a.result and a.result.ok),
                display=(a.result.display if a.result else ""),
                error=(a.result.error if a.result else None),
                sources=(list(a.result.sources) if a.result else []),
                duration_ms=(a.result.duration_ms if a.result else 0),
            )
            for a in aufrufe
        ],
    )


@api.get("/memory", response_model=list[FactOut])
async def get_memory(request: Request, q: str = "") -> list[FactOut]:
    """Alles, was JARVIS ueber dich weiss. Mit `q` gefiltert."""
    pfad = _settings(request).db_path
    fakten = await asyncio.to_thread(
        memory.search_facts, pfad, q, 200
    ) if q.strip() else await asyncio.to_thread(memory.list_facts, pfad)
    return [FactOut.of(f) for f in fakten]


@api.post("/memory", response_model=FactCreated, status_code=201)
async def post_memory(request: Request, body: FactCreate) -> FactCreated:
    pfad = _settings(request).db_path
    try:
        neu, konflikt = await asyncio.to_thread(
            memory.add_fact, pfad, body.text, category=body.category
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return FactCreated(
        fact=FactOut.of(neu),
        conflict=FactOut.of(konflikt) if konflikt else None,
    )


@api.patch("/memory/{fact_id}", response_model=FactOut)
async def patch_memory(
    request: Request, fact_id: int, body: FactUpdate
) -> FactOut:
    pfad = _settings(request).db_path
    try:
        geaendert = await asyncio.to_thread(
            memory.update_fact,
            pfad,
            fact_id,
            text=body.text,
            category=body.category,
            confirmed=body.confirmed,
            conflicts_with=None if body.resolve_conflict else -1,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if geaendert is None:
        raise HTTPException(status_code=404, detail="Fakt nicht gefunden.")
    return FactOut.of(geaendert)


@api.delete("/memory/{fact_id}", status_code=204)
async def delete_memory(request: Request, fact_id: int) -> None:
    pfad = _settings(request).db_path
    if not await asyncio.to_thread(memory.delete_fact, pfad, fact_id):
        raise HTTPException(status_code=404, detail="Fakt nicht gefunden.")


@api.get("/tasks", response_model=list[TaskLogOut])
async def get_task_log(request: Request) -> list[TaskLogOut]:
    """Das episodische Gedaechtnis: was wurde wann beauftragt, wie ging es aus."""
    rows = await asyncio.to_thread(memory.list_task_log, _settings(request).db_path)
    return [TaskLogOut.of(r) for r in rows]


@router.get("/", include_in_schema=False)
async def index(request: Request) -> HTMLResponse:
    """Liefert die Oberflaeche.

    Der JARVIS-Token wird beim Ausliefern eingesetzt, damit die Seite die API
    aufrufen kann. Das ist kein Leck: eine fremde Seite kann die Antwort von
    127.0.0.1 wegen CORS nicht lesen, und auf der Platte steht nur der
    Platzhalter. Der **LLM**-Key kommt hier niemals hin (0.4.1).
    """
    html = request.app.state.index_path.read_text(encoding="utf-8")
    return HTMLResponse(html.replace("__JARVIS_TOKEN__", request.app.state.token))
