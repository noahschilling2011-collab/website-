"""Endpunkte.

Ein Grundsatz zieht sich durch: der Modellaufruf passiert **ausserhalb**
jeder offenen Datenbanktransaktion. Ein Aufruf dauert Sekunden; solange eine
Schreibsperre zu halten, wuerde die Oberflaeche blockieren, sobald zwei
Anfragen zusammenkommen.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

from api.schemas import (
    ChatRequest,
    ChatResponse,
    ConversationCreate,
    ConversationDetailOut,
    ConversationOut,
    ConversationRename,
    HealthOut,
    MessageOut,
    UsageOut,
)
from core import db
from core.llm import LLMMessage

router = APIRouter()

TITLE_MAX = 48


def derive_title(message: str) -> str:
    """Titel aus der ersten Nutzernachricht. Erste Zeile, gekuerzt."""
    first_line = message.strip().splitlines()[0].strip() if message.strip() else ""
    if not first_line:
        return "Neue Konversation"
    if len(first_line) <= TITLE_MAX:
        return first_line
    return first_line[: TITLE_MAX - 1].rstrip() + "…"


def _settings(request: Request):
    return request.app.state.settings


def _provider(request: Request):
    return request.app.state.provider


@router.get("/api/health", response_model=HealthOut)
def health(request: Request) -> HealthOut:
    settings = _settings(request)
    provider = _provider(request)

    try:
        with db.session(settings.db_path) as conn:
            count = conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
        database = "ok"
    except Exception as exc:  # die Meldung soll den Pfad zeigen, nicht den Fehlertyp
        count = 0
        database = f"fehler: {exc}"

    pair = settings.price_per_mtok
    price = {"input": pair[0], "output": pair[1]} if pair else None

    provider_error = getattr(provider, "reason", None)

    return HealthOut(
        status="ok" if database == "ok" and provider_error is None else "degraded",
        phase=1,
        provider=provider.name,
        model=provider.model,
        api_key_configured=bool(settings.anthropic_api_key),
        api_key_hint=settings.masked_api_key(),
        provider_error=provider_error,
        database=database,
        conversations=count,
        price_usd_per_mtok=price,
    )


@router.get("/api/conversations", response_model=list[ConversationOut])
def get_conversations(request: Request) -> list[ConversationOut]:
    with db.session(_settings(request).db_path) as conn:
        return [ConversationOut.of(c) for c in db.list_conversations(conn)]


@router.post("/api/conversations", response_model=ConversationOut, status_code=201)
def post_conversation(request: Request, body: ConversationCreate) -> ConversationOut:
    with db.session(_settings(request).db_path) as conn:
        return ConversationOut.of(db.create_conversation(conn, body.title))


@router.get("/api/conversations/{conversation_id}", response_model=ConversationDetailOut)
def get_conversation(request: Request, conversation_id: int) -> ConversationDetailOut:
    with db.session(_settings(request).db_path) as conn:
        conversation = db.get_conversation(conn, conversation_id)
        if conversation is None:
            raise HTTPException(status_code=404, detail="Konversation nicht gefunden.")
        messages = db.list_messages(conn, conversation_id)

    return ConversationDetailOut(
        **ConversationOut.of(conversation).model_dump(),
        messages=[MessageOut.of(m) for m in messages],
    )


@router.patch("/api/conversations/{conversation_id}", response_model=ConversationOut)
def patch_conversation(
    request: Request, conversation_id: int, body: ConversationRename
) -> ConversationOut:
    with db.session(_settings(request).db_path) as conn:
        if not db.rename_conversation(conn, conversation_id, body.title):
            raise HTTPException(status_code=404, detail="Konversation nicht gefunden.")
        conversation = db.get_conversation(conn, conversation_id)
    assert conversation is not None
    return ConversationOut.of(conversation)


@router.delete("/api/conversations/{conversation_id}", status_code=204)
def delete_conversation(request: Request, conversation_id: int) -> None:
    with db.session(_settings(request).db_path) as conn:
        if not db.delete_conversation(conn, conversation_id):
            raise HTTPException(status_code=404, detail="Konversation nicht gefunden.")


@router.post("/api/chat", response_model=ChatResponse)
def post_chat(request: Request, body: ChatRequest) -> ChatResponse:
    settings = _settings(request)
    provider = _provider(request)

    text = body.message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Die Nachricht ist leer.")

    # Schritt 1: Nutzernachricht festschreiben und Verlauf lesen.
    with db.session(settings.db_path) as conn:
        if body.conversation_id is None:
            conversation = db.create_conversation(conn, derive_title(text))
        else:
            found = db.get_conversation(conn, body.conversation_id)
            if found is None:
                raise HTTPException(
                    status_code=404, detail="Konversation nicht gefunden."
                )
            conversation = found

        user_message = db.add_message(conn, conversation.id, "user", text)
        history = db.list_messages(conn, conversation.id, limit=settings.history_limit)

    # Schritt 2: Modell fragen. Keine Transaktion offen.
    reply = provider.complete(
        [LLMMessage(role=m.role, content=m.content) for m in history],
        system=settings.system_prompt,
        max_tokens=settings.max_tokens,
    )

    # Schritt 3: Antwort festschreiben.
    with db.session(settings.db_path) as conn:
        assistant_message = db.add_message(
            conn,
            conversation.id,
            "assistant",
            reply.text,
            model=reply.model,
            input_tokens=reply.usage.input_tokens,
            output_tokens=reply.usage.output_tokens,
        )
        refreshed = db.get_conversation(conn, conversation.id)

    assert refreshed is not None
    return ChatResponse(
        conversation=ConversationOut.of(refreshed),
        user_message=MessageOut.of(user_message),
        reply=MessageOut.of(assistant_message),
        usage=UsageOut(
            input_tokens=reply.usage.input_tokens,
            output_tokens=reply.usage.output_tokens,
        ),
    )


@router.get("/", include_in_schema=False)
def index(request: Request) -> FileResponse:
    return FileResponse(request.app.state.web_dir / "index.html")
