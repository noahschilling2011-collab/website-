"""Datenbankschicht.

SQLite aus der Standardbibliothek, kein ORM. Jede Funktion nimmt eine
Verbindung und macht genau eine Sache.

Die Funktionen sind synchron. Die Endpunkte sind async, deshalb werden sie
dort ueber `asyncio.to_thread` aufgerufen - sonst blockiert ein Schreibvorgang
die Event-Loop.
"""

from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Literal

SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"

Role = Literal["user", "assistant"]


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class Message:
    id: int
    role: Role
    content: str
    created_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Message":
        return cls(
            id=row["id"],
            role=row["role"],
            content=row["content"],
            created_at=row["created_at"],
        )


@dataclass(frozen=True)
class LLMCall:
    id: int
    model: str
    prompt_hash: str
    in_tokens: int
    out_tokens: int
    cost_eur: float
    duration_ms: int
    ok: bool
    created_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "LLMCall":
        return cls(
            id=row["id"],
            model=row["model"],
            prompt_hash=row["prompt_hash"],
            in_tokens=row["in_tokens"],
            out_tokens=row["out_tokens"],
            cost_eur=row["cost_eur"],
            duration_ms=row["duration_ms"],
            ok=bool(row["ok"]),
            created_at=row["created_at"],
        )


def connect(db_path: Path | str) -> sqlite3.Connection:
    if str(db_path) != ":memory:":
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    if str(db_path) != ":memory:":
        # Lesen blockiert nicht, waehrend geschrieben wird.
        conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    conn.commit()


@contextmanager
def session(db_path: Path | str) -> Iterator[sqlite3.Connection]:
    """Eine Verbindung fuer einen Vorgang. Commit bei Erfolg, Rollback bei Fehler."""
    conn = connect(db_path)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# --- Nachrichten ----------------------------------------------------------


def add_message(db_path: Path | str, role: Role, content: str) -> Message:
    with session(db_path) as conn:
        now = utcnow()
        cur = conn.execute(
            "INSERT INTO messages (role, content, created_at) VALUES (?, ?, ?)",
            (role, content, now),
        )
        assert cur.lastrowid is not None
        return Message(id=cur.lastrowid, role=role, content=content, created_at=now)


def list_messages(db_path: Path | str, limit: int | None = None) -> list[Message]:
    """Verlauf in Reihenfolge. `limit` liefert die *letzten* n, aufsteigend sortiert."""
    with session(db_path) as conn:
        if limit is None:
            rows = conn.execute("SELECT * FROM messages ORDER BY id ASC").fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM (SELECT * FROM messages ORDER BY id DESC LIMIT ?) "
                "ORDER BY id ASC",
                (limit,),
            ).fetchall()
        return [Message.from_row(row) for row in rows]


def count_messages(db_path: Path | str) -> int:
    with session(db_path) as conn:
        return conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]


def clear_messages(db_path: Path | str) -> int:
    with session(db_path) as conn:
        return conn.execute("DELETE FROM messages").rowcount


# --- Modellaufrufe --------------------------------------------------------


def log_llm_call(
    db_path: Path | str,
    *,
    model: str,
    prompt_hash: str = "",
    in_tokens: int,
    out_tokens: int,
    cost_eur: float,
    duration_ms: int,
    ok: bool,
) -> LLMCall:
    with session(db_path) as conn:
        now = utcnow()
        cur = conn.execute(
            "INSERT INTO llm_calls (model, prompt_hash, in_tokens, out_tokens, "
            "cost_eur, duration_ms, ok, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (model, prompt_hash, in_tokens, out_tokens, cost_eur,
             duration_ms, int(ok), now),
        )
        assert cur.lastrowid is not None
        return LLMCall(
            id=cur.lastrowid,
            model=model,
            prompt_hash=prompt_hash,
            in_tokens=in_tokens,
            out_tokens=out_tokens,
            cost_eur=cost_eur,
            duration_ms=duration_ms,
            ok=ok,
            created_at=now,
        )


def list_llm_calls(db_path: Path | str, limit: int = 50) -> list[LLMCall]:
    with session(db_path) as conn:
        rows = conn.execute(
            "SELECT * FROM llm_calls ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [LLMCall.from_row(row) for row in rows]


def llm_call_totals(db_path: Path | str) -> dict[str, float]:
    with session(db_path) as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS n, "
            "       COALESCE(SUM(in_tokens), 0)  AS in_tokens, "
            "       COALESCE(SUM(out_tokens), 0) AS out_tokens, "
            "       COALESCE(SUM(cost_eur), 0.0) AS cost_eur "
            "FROM llm_calls"
        ).fetchone()
        return {
            "calls": row["n"],
            "in_tokens": row["in_tokens"],
            "out_tokens": row["out_tokens"],
            "cost_eur": round(row["cost_eur"], 6),
        }


# --- Werkzeugaufrufe (Phase 2) --------------------------------------------


@dataclass(frozen=True)
class ToolCallRow:
    id: int
    message_id: int | None
    name: str
    arguments: dict
    ok: bool
    display: str
    error: str | None
    sources: list[str]
    duration_ms: int
    created_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "ToolCallRow":
        return cls(
            id=row["id"],
            message_id=row["message_id"],
            name=row["name"],
            arguments=json.loads(row["arguments"] or "{}"),
            ok=bool(row["ok"]),
            display=row["display"],
            error=row["error"],
            sources=json.loads(row["sources"] or "[]"),
            duration_ms=row["duration_ms"],
            created_at=row["created_at"],
        )


def add_tool_call(
    db_path: Path | str,
    *,
    message_id: int | None,
    name: str,
    arguments: dict,
    ok: bool,
    display: str = "",
    error: str | None = None,
    sources: list[str] | None = None,
    duration_ms: int = 0,
) -> ToolCallRow:
    with session(db_path) as conn:
        now = utcnow()
        cur = conn.execute(
            "INSERT INTO tool_calls (message_id, name, arguments, ok, display, "
            "error, sources, duration_ms, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                message_id,
                name,
                json.dumps(arguments, ensure_ascii=False, default=str),
                int(ok),
                display,
                error,
                json.dumps(sources or [], ensure_ascii=False),
                duration_ms,
                now,
            ),
        )
        assert cur.lastrowid is not None
        return ToolCallRow(
            id=cur.lastrowid, message_id=message_id, name=name,
            arguments=arguments, ok=ok, display=display, error=error,
            sources=sources or [], duration_ms=duration_ms, created_at=now,
        )


def attach_tool_calls(db_path: Path | str, ids: list[int], message_id: int) -> None:
    """Haengt vorher geschriebene Aufrufe an die fertige Antwort.

    Die Aufrufe entstehen, bevor die Antwort existiert - deshalb zwei Schritte
    statt einer Zeile mit unbekannter message_id.
    """
    if not ids:
        return
    with session(db_path) as conn:
        conn.executemany(
            "UPDATE tool_calls SET message_id = ? WHERE id = ?",
            [(message_id, i) for i in ids],
        )


def list_tool_calls(db_path: Path | str, message_id: int) -> list[ToolCallRow]:
    with session(db_path) as conn:
        rows = conn.execute(
            "SELECT * FROM tool_calls WHERE message_id = ? ORDER BY id ASC",
            (message_id,),
        ).fetchall()
        return [ToolCallRow.from_row(r) for r in rows]


def tool_calls_by_message(db_path: Path | str) -> dict[int, list[ToolCallRow]]:
    with session(db_path) as conn:
        rows = conn.execute(
            "SELECT * FROM tool_calls WHERE message_id IS NOT NULL ORDER BY id ASC"
        ).fetchall()
    gruppen: dict[int, list[ToolCallRow]] = {}
    for row in rows:
        gruppen.setdefault(row["message_id"], []).append(ToolCallRow.from_row(row))
    return gruppen


# --- Tasks und Schritte (Phase 4) -----------------------------------------


def save_task(db_path: Path | str, task, *, parent_task_id: str | None = None) -> None:
    """Schreibt den Task-Kopf. Wird bei jeder Zustandsaenderung aufgerufen."""
    import dataclasses

    with session(db_path) as conn:
        now = utcnow()
        conn.execute(
            "INSERT INTO tasks (id, goal, status, depth, parent_task_id, budget, "
            "spent_tokens, spent_cost_eur, spent_tool_calls, result, abort_reason, "
            "created_at, finished_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET status = excluded.status, "
            "spent_tokens = excluded.spent_tokens, "
            "spent_cost_eur = excluded.spent_cost_eur, "
            "spent_tool_calls = excluded.spent_tool_calls, "
            "result = excluded.result, abort_reason = excluded.abort_reason, "
            "finished_at = excluded.finished_at",
            (
                task.id, task.goal, task.status, task.depth, parent_task_id,
                json.dumps(dataclasses.asdict(task.budget)),
                task.spent_tokens, task.spent_cost_eur,
                getattr(task, "spent_tool_calls", 0),
                getattr(task, "result", None),
                getattr(task, "abort_reason", None),
                now,
                now if task.status in ("done", "failed", "aborted_budget",
                                       "cancelled") else None,
            ),
        )


def save_step(db_path: Path | str, task_id: str, index: int, step) -> None:
    with session(db_path) as conn:
        now = utcnow()
        conn.execute(
            "INSERT INTO steps (id, task_id, idx, description, agent, status, "
            "result, note, attempts, max_attempts, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET status = excluded.status, "
            "result = excluded.result, note = excluded.note, "
            "attempts = excluded.attempts, updated_at = excluded.updated_at",
            (
                step.id, task_id, index, step.description, step.agent,
                step.status.value if hasattr(step.status, "value") else step.status,
                json.dumps(step.result.to_dict(), ensure_ascii=False, default=str)
                if step.result else None,
                getattr(step, "note", None),
                step.attempts, step.max_attempts, now, now,
            ),
        )


def get_task_row(db_path: Path | str, task_id: str) -> dict | None:
    with session(db_path) as conn:
        row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if row is None:
            return None
        task = dict(row)
        task["budget"] = json.loads(task["budget"] or "{}")
        task["steps"] = [
            {**dict(s), "result": json.loads(s["result"]) if s["result"] else None}
            for s in conn.execute(
                "SELECT * FROM steps WHERE task_id = ? ORDER BY idx ASC", (task_id,)
            )
        ]
        task["children"] = [
            r["id"] for r in conn.execute(
                "SELECT id FROM tasks WHERE parent_task_id = ? ORDER BY created_at",
                (task_id,),
            )
        ]
        return task


def list_task_rows(db_path: Path | str, limit: int = 50) -> list[dict]:
    with session(db_path) as conn:
        rows = conn.execute(
            "SELECT id, goal, status, depth, parent_task_id, spent_tokens, "
            "spent_cost_eur, spent_tool_calls, created_at, finished_at "
            "FROM tasks ORDER BY created_at DESC, rowid DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]


# --- Audit-Log (Phase 5) --------------------------------------------------


@dataclass(frozen=True)
class AuditRow:
    id: int
    task_id: str | None
    step_id: str | None
    tool: str
    arguments: dict
    permission: str
    decision: str
    executed: bool
    ok: bool | None
    detail: str | None
    created_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "AuditRow":
        return cls(
            id=row["id"], task_id=row["task_id"], step_id=row["step_id"],
            tool=row["tool"], arguments=json.loads(row["arguments"] or "{}"),
            permission=row["permission"], decision=row["decision"],
            executed=bool(row["executed"]),
            ok=None if row["ok"] is None else bool(row["ok"]),
            detail=row["detail"], created_at=row["created_at"],
        )


def log_audit(
    db_path: Path | str,
    *,
    tool: str,
    arguments: dict,
    permission: str,
    decision: str,
    task_id: str | None = None,
    step_id: str | None = None,
    executed: bool = False,
    ok: bool | None = None,
    detail: str | None = None,
) -> AuditRow:
    with session(db_path) as conn:
        now = utcnow()
        cur = conn.execute(
            "INSERT INTO audit_log (task_id, step_id, tool, arguments, permission, "
            "decision, executed, ok, detail, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (task_id, step_id, tool,
             json.dumps(arguments, ensure_ascii=False, default=str),
             permission, decision, int(executed),
             None if ok is None else int(ok), detail, now),
        )
        assert cur.lastrowid is not None
        return AuditRow(
            id=cur.lastrowid, task_id=task_id, step_id=step_id, tool=tool,
            arguments=arguments, permission=permission, decision=decision,
            executed=executed, ok=ok, detail=detail, created_at=now,
        )


def list_audit(db_path: Path | str, limit: int = 200) -> list[AuditRow]:
    with session(db_path) as conn:
        rows = conn.execute(
            "SELECT * FROM audit_log ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [AuditRow.from_row(r) for r in rows]
