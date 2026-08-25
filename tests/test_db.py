import sqlite3

import pytest

from core import db


@pytest.fixture
def conn(db_path):
    connection = db.connect(db_path)
    db.init_db(connection)
    yield connection
    connection.close()


def test_konversation_anlegen_und_lesen(conn):
    created = db.create_conversation(conn, "Titel")
    found = db.get_conversation(conn, created.id)
    assert found is not None
    assert found.title == "Titel"
    assert found.message_count == 0


def test_unbekannte_konversation_ist_none(conn):
    assert db.get_conversation(conn, 4711) is None


def test_nachrichten_kommen_in_reihenfolge(conn):
    c = db.create_conversation(conn, "T")
    for i in range(5):
        db.add_message(conn, c.id, "user", f"Nachricht {i}")
    assert [m.content for m in db.list_messages(conn, c.id)] == [
        f"Nachricht {i}" for i in range(5)
    ]


def test_limit_liefert_die_letzten_aufsteigend(conn):
    c = db.create_conversation(conn, "T")
    for i in range(10):
        db.add_message(conn, c.id, "user", str(i))
    assert [m.content for m in db.list_messages(conn, c.id, limit=3)] == ["7", "8", "9"]


def test_loeschen_kaskadiert(conn):
    c = db.create_conversation(conn, "T")
    db.add_message(conn, c.id, "user", "x")
    assert db.delete_conversation(conn, c.id) is True
    assert conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0] == 0


def test_loeschen_von_nichts_meldet_false(conn):
    assert db.delete_conversation(conn, 999) is False


def test_umbenennen(conn):
    c = db.create_conversation(conn, "alt")
    assert db.rename_conversation(conn, c.id, "neu") is True
    found = db.get_conversation(conn, c.id)
    assert found is not None and found.title == "neu"


def test_unerlaubte_rolle_wird_abgelehnt(conn):
    c = db.create_conversation(conn, "T")
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "INSERT INTO messages (conversation_id, role, content, created_at) "
            "VALUES (?, 'system', 'x', '2026-01-01T00:00:00Z')",
            (c.id,),
        )


def test_nachricht_ohne_konversation_wird_abgelehnt(conn):
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "INSERT INTO messages (conversation_id, role, content, created_at) "
            "VALUES (12345, 'user', 'x', '2026-01-01T00:00:00Z')"
        )


def test_zeitstempel_ist_utc_und_sortierbar(conn):
    c = db.create_conversation(conn, "T")
    assert c.created_at.endswith("Z")
    assert c.created_at[4] == "-" and c.created_at[10] == "T"


def test_session_macht_rollback_bei_fehler(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)

    with pytest.raises(RuntimeError):
        with db.session(db_path) as conn:
            db.create_conversation(conn, "verworfen")
            raise RuntimeError("Abbruch")

    with db.session(db_path) as conn:
        assert db.list_conversations(conn) == []
