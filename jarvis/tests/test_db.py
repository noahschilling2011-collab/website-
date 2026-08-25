import sqlite3

import pytest

from core import db


@pytest.fixture
def path(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    return db_path


def test_schema_hat_genau_die_tabellen_aus_phase_1(path):
    with db.session(path) as conn:
        tabellen = {
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%'"
            )
        }
    assert tabellen == {"messages", "llm_calls"}


def test_llm_calls_hat_genau_die_spalten_aus_phase_1(path):
    with db.session(path) as conn:
        spalten = [r[1] for r in conn.execute("PRAGMA table_info(llm_calls)")]
    assert spalten == [
        "id", "model", "in_tokens", "out_tokens",
        "cost_eur", "duration_ms", "ok", "created_at",
    ]


def test_messages_hat_genau_die_spalten_aus_phase_1(path):
    with db.session(path) as conn:
        spalten = [r[1] for r in conn.execute("PRAGMA table_info(messages)")]
    assert spalten == ["id", "role", "content", "created_at"]


def test_nachrichten_kommen_in_reihenfolge(path):
    for i in range(5):
        db.add_message(path, "user", f"Nachricht {i}")
    assert [m.content for m in db.list_messages(path)] == [
        f"Nachricht {i}" for i in range(5)
    ]


def test_limit_liefert_die_letzten_aufsteigend(path):
    for i in range(10):
        db.add_message(path, "user", str(i))
    assert [m.content for m in db.list_messages(path, limit=3)] == ["7", "8", "9"]


def test_unerlaubte_rolle_wird_abgelehnt(path):
    with db.session(path) as conn:
        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                "INSERT INTO messages (role, content, created_at) "
                "VALUES ('system', 'x', '2026-01-01T00:00:00Z')"
            )


def test_llm_call_wird_protokolliert(path):
    call = db.log_llm_call(
        path, model="m-1", in_tokens=120, out_tokens=34,
        cost_eur=0.0013, duration_ms=812, ok=True,
    )
    assert call.id == 1
    gespeichert = db.list_llm_calls(path)[0]
    assert (gespeichert.in_tokens, gespeichert.out_tokens) == (120, 34)
    assert gespeichert.ok is True


def test_fehlgeschlagener_aufruf_wird_auch_protokolliert(path):
    db.log_llm_call(
        path, model="m-1", in_tokens=0, out_tokens=0,
        cost_eur=0.0, duration_ms=90, ok=False,
    )
    assert db.list_llm_calls(path)[0].ok is False


def test_summen_ueber_alle_aufrufe(path):
    db.log_llm_call(path, model="m", in_tokens=10, out_tokens=5,
                    cost_eur=0.001, duration_ms=1, ok=True)
    db.log_llm_call(path, model="m", in_tokens=20, out_tokens=7,
                    cost_eur=0.002, duration_ms=1, ok=True)
    assert db.llm_call_totals(path) == {
        "calls": 2, "in_tokens": 30, "out_tokens": 12, "cost_eur": 0.003,
    }


def test_zeitstempel_ist_utc_und_sortierbar(path):
    m = db.add_message(path, "user", "x")
    assert m.created_at.endswith("Z")
    assert m.created_at[4] == "-" and m.created_at[10] == "T"


def test_session_macht_rollback_bei_fehler(path):
    with pytest.raises(RuntimeError):
        with db.session(path) as conn:
            conn.execute(
                "INSERT INTO messages (role, content, created_at) "
                "VALUES ('user', 'verworfen', '2026-01-01T00:00:00Z')"
            )
            raise RuntimeError("Abbruch")
    assert db.list_messages(path) == []
