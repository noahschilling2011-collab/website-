"""Formen, die ueber HTTP gehen.

Getrennt von den Datenbank-Datenklassen, damit ein Schema-Umbau nicht
automatisch die API bricht und umgekehrt.
"""

from __future__ import annotations

from pydantic import BaseModel, Field

from core.db import Conversation, Message


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=100_000)
    conversation_id: int | None = None


class UsageOut(BaseModel):
    input_tokens: int = 0
    output_tokens: int = 0


class MessageOut(BaseModel):
    id: int
    role: str
    content: str
    model: str | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    created_at: str

    @classmethod
    def of(cls, message: Message) -> "MessageOut":
        return cls(
            id=message.id,
            role=message.role,
            content=message.content,
            model=message.model,
            input_tokens=message.input_tokens,
            output_tokens=message.output_tokens,
            created_at=message.created_at,
        )


class ConversationOut(BaseModel):
    id: int
    title: str
    created_at: str
    updated_at: str
    message_count: int = 0

    @classmethod
    def of(cls, conversation: Conversation) -> "ConversationOut":
        return cls(
            id=conversation.id,
            title=conversation.title,
            created_at=conversation.created_at,
            updated_at=conversation.updated_at,
            message_count=conversation.message_count,
        )


class ConversationDetailOut(ConversationOut):
    messages: list[MessageOut] = []


class ConversationCreate(BaseModel):
    title: str = Field(default="Neue Konversation", min_length=1, max_length=200)


class ConversationRename(BaseModel):
    title: str = Field(min_length=1, max_length=200)


class ChatResponse(BaseModel):
    conversation: ConversationOut
    user_message: MessageOut
    reply: MessageOut
    usage: UsageOut


class HealthOut(BaseModel):
    status: str
    phase: int
    provider: str
    model: str
    api_key_configured: bool
    api_key_hint: str
    provider_error: str | None = None
    database: str
    conversations: int
    price_usd_per_mtok: dict[str, float] | None = None
