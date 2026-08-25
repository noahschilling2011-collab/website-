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
    HealthOut,
    MessageOut,
    SpendOut,
)
from api.security import require_token
from core import db
from core.llm import LLMError, LLMMessage

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
        phase=1,
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
    return [MessageOut.of(m) for m in messages]


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

    # 2. Modell fragen. Keine Transaktion offen.
    try:
        reply = await provider.complete(
            [LLMMessage(role=m.role, content=m.content) for m in history],
            system=settings.system_prompt,
        )
    except LLMError as exc:
        await asyncio.to_thread(
            db.log_llm_call,
            settings.db_path,
            model=provider.model or "unbekannt",
            in_tokens=0,
            out_tokens=0,
            cost_eur=0.0,
            duration_ms=exc.duration_ms,
            ok=False,
        )
        log.warning("task %s: Modellaufruf fehlgeschlagen - %s", task_id, exc)
        raise

    # 3. Antwort und Aufruf protokollieren.
    kosten = settings.cost_eur(reply.usage.in_tokens, reply.usage.out_tokens)
    await asyncio.to_thread(db.add_message, settings.db_path, "assistant", reply.text)
    await asyncio.to_thread(
        db.log_llm_call,
        settings.db_path,
        model=reply.model,
        in_tokens=reply.usage.in_tokens,
        out_tokens=reply.usage.out_tokens,
        cost_eur=kosten,
        duration_ms=reply.duration_ms,
        ok=True,
    )
    log.info(
        "task %s: %s, %d/%d Token, %d ms, %.6f EUR",
        task_id,
        reply.model,
        reply.usage.in_tokens,
        reply.usage.out_tokens,
        reply.duration_ms,
        kosten,
    )

    return ChatResponse(reply=reply.text, task_id=task_id)


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
