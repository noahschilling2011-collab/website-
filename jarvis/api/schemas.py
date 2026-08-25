"""Formen, die ueber HTTP gehen."""

from __future__ import annotations

from pydantic import BaseModel, Field

from core.db import Message


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=100_000)


class ChatResponse(BaseModel):
    """Genau die Form aus PHASE-01: `{reply, task_id}`. Nicht mehr."""

    reply: str
    task_id: str


class MessageOut(BaseModel):
    id: int
    role: str
    content: str
    created_at: str

    @classmethod
    def of(cls, message: Message) -> "MessageOut":
        return cls(
            id=message.id,
            role=message.role,
            content=message.content,
            created_at=message.created_at,
        )


class SpendOut(BaseModel):
    calls: int = 0
    in_tokens: int = 0
    out_tokens: int = 0
    cost_eur: float = 0.0
    prices_configured: bool = False


class HealthOut(BaseModel):
    status: str
    phase: int
    provider: str
    model: str
    api_key_configured: bool
    api_key_hint: str
    provider_error: str | None = None
    database: str
    messages: int
    spend: SpendOut
