"""Formen, die ueber HTTP gehen."""

from __future__ import annotations

from pydantic import BaseModel, Field

from core.db import Message, ToolCallRow
from core.memory import Fact, TaskLogRow


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=100_000)


class ChatResponse(BaseModel):
    """Die Form aus PHASE-01 (`{reply, task_id}`), plus die Werkzeugaufrufe.

    Phase 2 verlangt, dass im UI je Antwort sichtbar ist, welche Werkzeuge mit
    welchen Argumenten liefen. Ohne dieses Feld muesste die Oberflaeche direkt
    nach dem Senden noch einmal den ganzen Verlauf holen.
    """

    reply: str
    task_id: str
    tool_calls: list[ToolCallOut] = []


class ToolCallOut(BaseModel):
    name: str
    arguments: dict = {}
    ok: bool = True
    display: str = ""
    error: str | None = None
    sources: list[str] = []
    duration_ms: int = 0

    @classmethod
    def of(cls, row: ToolCallRow) -> "ToolCallOut":
        return cls(
            name=row.name, arguments=row.arguments, ok=row.ok,
            display=row.display, error=row.error, sources=row.sources,
            duration_ms=row.duration_ms,
        )


class MessageOut(BaseModel):
    id: int
    role: str
    content: str
    created_at: str
    tool_calls: list[ToolCallOut] = []

    @classmethod
    def of(
        cls, message: Message, tool_calls: list[ToolCallRow] | None = None
    ) -> "MessageOut":
        return cls(
            id=message.id,
            role=message.role,
            content=message.content,
            created_at=message.created_at,
            tool_calls=[ToolCallOut.of(t) for t in (tool_calls or [])],
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


class FactOut(BaseModel):
    id: int
    text: str
    category: str
    source_message_id: int | None = None
    created_at: str
    confirmed: bool = False
    conflicts_with: int | None = None

    @classmethod
    def of(cls, fact: Fact) -> "FactOut":
        return cls(
            id=fact.id, text=fact.text, category=fact.category,
            source_message_id=fact.source_message_id,
            created_at=fact.created_at, confirmed=fact.confirmed,
            conflicts_with=fact.conflicts_with,
        )


class FactCreate(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    category: str = Field(default="allgemein", max_length=64)


class FactUpdate(BaseModel):
    text: str | None = Field(default=None, min_length=1, max_length=2000)
    category: str | None = Field(default=None, max_length=64)
    confirmed: bool | None = None
    # true loest den Widerspruch auf: der Verweis wird geloescht.
    resolve_conflict: bool = False


class FactCreated(BaseModel):
    fact: FactOut
    conflict: FactOut | None = None


class TaskLogOut(BaseModel):
    task_id: str
    goal: str
    outcome: str
    summary: str = ""
    created_at: str

    @classmethod
    def of(cls, row: TaskLogRow) -> "TaskLogOut":
        return cls(
            task_id=row.task_id, goal=row.goal, outcome=row.outcome,
            summary=row.summary, created_at=row.created_at,
        )
