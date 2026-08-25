"""Datenbankschicht.

SQLite aus der Standardbibliothek, kein ORM. Jede Funktion nimmt eine
Verbindung und macht genau eine Sache.

Die Funktionen sind synchron. Die Endpunkte sind async, deshalb werden sie
dort ueber `asyncio.to_thread` aufgerufen - sonst blockiert ein Schreibvorgang
die Event-Loop.
"""

from __future__ import annotations

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
    in_tokens: int,
    out_tokens: int,
    cost_eur: float,
    duration_ms: int,
    ok: bool,
) -> LLMCall:
    with session(db_path) as conn:
        now = utcnow()
        cur = conn.execute(
            "INSERT INTO llm_calls "
            "(model, in_tokens, out_tokens, cost_eur, duration_ms, ok, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (model, in_tokens, out_tokens, cost_eur, duration_ms, int(ok), now),
        )
        assert cur.lastrowid is not None
        return LLMCall(
            id=cur.lastrowid,
            model=model,
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
