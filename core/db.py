"""Datenbankschicht.

SQLite aus der Standardbibliothek, kein ORM. Jede Funktion nimmt eine
Verbindung entgegen und macht genau eine Sache. Wer eine Verbindung braucht,
holt sie ueber `connect()` oder - fuer einen abgeschlossenen Vorgang - ueber
`session()`.

Verbindungen werden nicht ueber Threads geteilt. FastAPI fuehrt synchrone
Endpunkte in einem Threadpool aus, deshalb oeffnet jeder Vorgang seine
eigene Verbindung. Bei einer lokalen SQLite-Datei kostet das nichts.
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
    """UTC in ISO-8601 mit 'Z'. Sortierbar als Text."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class Conversation:
    id: int
    title: str
    created_at: str
    updated_at: str
    message_count: int = 0

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Conversation":
        keys = row.keys()
        return cls(
            id=row["id"],
            title=row["title"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            message_count=row["message_count"] if "message_count" in keys else 0,
        )


@dataclass(frozen=True)
class Message:
    id: int
    conversation_id: int
    role: Role
    content: str
    model: str | None
    input_tokens: int
    output_tokens: int
    created_at: str

    @classmethod
    def from_row(cls, row: sqlite3.Row) -> "Message":
        return cls(
            id=row["id"],
            conversation_id=row["conversation_id"],
            role=row["role"],
            content=row["content"],
            model=row["model"],
            input_tokens=row["input_tokens"],
            output_tokens=row["output_tokens"],
            created_at=row["created_at"],
        )


def connect(db_path: Path | str) -> sqlite3.Connection:
    """Oeffnet die Datenbank und legt Verzeichnis und Schema an, falls noetig."""
    if str(db_path) != ":memory:":
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.row_factory = sqlite3.Row
    # Ohne dieses PRAGMA ignoriert SQLite Fremdschluessel stillschweigend -
    # das Kaskadieren beim Loeschen wuerde einfach nicht passieren.
    conn.execute("PRAGMA foreign_keys = ON")
    # WAL: Lesen blockiert nicht, waehrend geschrieben wird. Bei :memory:
    # nicht unterstuetzt, deshalb ohne Aufhebens uebersprungen.
    if str(db_path) != ":memory:":
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


# --- Konversationen -------------------------------------------------------


def create_conversation(conn: sqlite3.Connection, title: str) -> Conversation:
    now = utcnow()
    cur = conn.execute(
        "INSERT INTO conversations (title, created_at, updated_at) VALUES (?, ?, ?)",
        (title, now, now),
    )
    assert cur.lastrowid is not None
    return Conversation(id=cur.lastrowid, title=title, created_at=now, updated_at=now)


def get_conversation(conn: sqlite3.Connection, conversation_id: int) -> Conversation | None:
    row = conn.execute(
        """
        SELECT c.*, (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
                    AS message_count
        FROM conversations c WHERE c.id = ?
        """,
        (conversation_id,),
    ).fetchone()
    return Conversation.from_row(row) if row else None


def list_conversations(conn: sqlite3.Connection, limit: int = 100) -> list[Conversation]:
    rows = conn.execute(
        """
        SELECT c.*, (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id)
                    AS message_count
        FROM conversations c
        ORDER BY c.updated_at DESC, c.id DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [Conversation.from_row(row) for row in rows]


def rename_conversation(conn: sqlite3.Connection, conversation_id: int, title: str) -> bool:
    cur = conn.execute(
        "UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?",
        (title, utcnow(), conversation_id),
    )
    return cur.rowcount > 0


def delete_conversation(conn: sqlite3.Connection, conversation_id: int) -> bool:
    cur = conn.execute("DELETE FROM conversations WHERE id = ?", (conversation_id,))
    return cur.rowcount > 0


def touch_conversation(conn: sqlite3.Connection, conversation_id: int) -> None:
    conn.execute(
        "UPDATE conversations SET updated_at = ? WHERE id = ?",
        (utcnow(), conversation_id),
    )


# --- Nachrichten ----------------------------------------------------------


def add_message(
    conn: sqlite3.Connection,
    conversation_id: int,
    role: Role,
    content: str,
    *,
    model: str | None = None,
    input_tokens: int = 0,
    output_tokens: int = 0,
) -> Message:
    now = utcnow()
    cur = conn.execute(
        """
        INSERT INTO messages
            (conversation_id, role, content, model, input_tokens, output_tokens, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (conversation_id, role, content, model, input_tokens, output_tokens, now),
    )
    touch_conversation(conn, conversation_id)
    assert cur.lastrowid is not None
    return Message(
        id=cur.lastrowid,
        conversation_id=conversation_id,
        role=role,
        content=content,
        model=model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        created_at=now,
    )


def list_messages(
    conn: sqlite3.Connection, conversation_id: int, limit: int | None = None
) -> list[Message]:
    """Nachrichten in Reihenfolge. `limit` liefert die *letzten* n, aufsteigend sortiert."""
    if limit is None:
        rows = conn.execute(
            "SELECT * FROM messages WHERE conversation_id = ? ORDER BY id ASC",
            (conversation_id,),
        ).fetchall()
    else:
        rows = conn.execute(
            """
            SELECT * FROM (
                SELECT * FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ?
            ) ORDER BY id ASC
            """,
            (conversation_id, limit),
        ).fetchall()
    return [Message.from_row(row) for row in rows]
