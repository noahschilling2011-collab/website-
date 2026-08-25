"""Tests von Permissions, Bestaetigung und Audit-Log (Phase 5)."""

from __future__ import annotations

import sqlite3
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db
from core.contracts import Permission, Tool, ToolResult
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.tools import registry
from core.tools.dispatch import beschreibe_aufruf, run_tool
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def postausgang(tmp_path, settings) -> Path:
    pfad = tmp_path / "outbox.jsonl"
    settings.outbox_path = pfad
    registry.get("send_email").outbox = pfad
    return pfad


@pytest.fixture
def client(settings, postausgang):
    with TestClient(create_app(settings)) as c:
        yield c


def warte_auf(client, task_id: str, pruefung, sekunden: float = 10.0) -> dict:
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()
        if pruefung(d):
            return d
        time.sleep(0.02)
    raise AssertionError(f"Bedingung nie erfuellt, zuletzt: {d}")


def fertig(d: dict) -> bool:
    return d["status"] in ("done", "failed", "aborted_budget", "cancelled")


# --- Durchsetzung ---------------------------------------------------------


def test_dod_4_ein_read_agent_kann_send_email_nicht_aufrufen():
    """Auch wenn das Werkzeug ausdruecklich in seiner Liste steht."""
    ergebnis = run(run_tool(
        "send_email", {"to": "a@b.de", "subject": "s", "body": "b"},
        max_permission=Permission.READ,
        erlaubt=["send_email"],
    ))
    assert ergebnis.ok is False
    assert "EXTERNAL" in (ergebnis.error or "") and "READ" in (ergebnis.error or "")


def test_der_dispatcher_setzt_die_grenze_nicht_der_agent():
    from core.agents import baue_agenten

    agent = baue_agenten(FakeLLMProvider(), max_permission=Permission.SENSITIVE)["research"]
    agent.tools.append("send_email")  # absichtlich hineingeschmuggelt
    ergebnis = run(run_tool("send_email", {"to": "a", "subject": "s", "body": "b"},
                            max_permission=agent.max_permission,
                            erlaubt=agent.tools))
    assert ergebnis.ok is False


@pytest.mark.parametrize("stufe,erlaubt", [
    (Permission.INFO, False), (Permission.READ, False), (Permission.LOCAL, False),
    (Permission.EXTERNAL, True), (Permission.SENSITIVE, True),
])
def test_die_stufen_sind_geordnet(stufe: Permission, erlaubt: bool):
    """Nur ab EXTERNAL kommt send_email ueberhaupt bis zur Rueckfrage."""
    ergebnis = run(run_tool("send_email", {"to": "a", "subject": "s", "body": "b"},
                            max_permission=stufe))
    if erlaubt:
        assert "braucht eine Bestaetigung" in (ergebnis.error or "")
    else:
        assert "braucht EXTERNAL" in (ergebnis.error or "")


def test_ein_tool_ab_external_ohne_bestaetigungspflicht_wird_gar_nicht_erst_registriert():
    with pytest.raises(ValueError, match="requires_confirmation"):
        @registry.register
        class Heimlich(Tool):
            name = "heimlich_ueberweisen"
            description = "ueberweist Geld"
            parameters = {"type": "object"}
            permission = Permission.SENSITIVE
            requires_confirmation = False


# --- Vorschau (DoD 2) -----------------------------------------------------


def test_dod_2_die_vorschau_zeigt_empfaenger_betreff_und_text():
    vorschau = beschreibe_aufruf(registry.get("send_email"), {
        "to": "chef@firma.de", "subject": "Krankmeldung",
        "body": "Ich bin heute nicht da.",
    })
    assert "chef@firma.de" in vorschau
    assert "Krankmeldung" in vorschau
    assert "Ich bin heute nicht da." in vorschau


def test_die_vorschau_kuerzt_einen_riesigen_text():
    vorschau = beschreibe_aufruf(registry.get("send_email"), {
        "to": "a@b.de", "subject": "s", "body": "x" * 5000,
    })
    assert len(vorschau) < 1200 and "…" in vorschau


# --- Ohne Bestaetiger -----------------------------------------------------


def test_dod_3_ohne_bestaetigung_passiert_nichts(postausgang: Path):
    ergebnis = run(run_tool("send_email", {
        "to": "a@b.de", "subject": "s", "body": "b"}))
    assert ergebnis.ok is False
    assert not postausgang.exists(), "die Datei haette nicht entstehen duerfen"


def test_abgelehnte_bestaetigung_schreibt_nichts(postausgang: Path):
    async def nein(tool, argumente, vorschau):
        return False

    ergebnis = run(run_tool("send_email", {"to": "a@b.de", "subject": "s",
                                           "body": "b"}, bestaetigung=nein))
    assert ergebnis.ok is False and "Nicht bestaetigt" in (ergebnis.error or "")
    assert not postausgang.exists()


def test_bestaetigte_aktion_wird_ausgefuehrt(postausgang: Path):
    async def ja(tool, argumente, vorschau):
        return True

    ergebnis = run(run_tool("send_email", {"to": "a@b.de", "subject": "Hallo",
                                           "body": "Text"}, bestaetigung=ja))
    assert ergebnis.ok is True
    assert "Hallo" in postausgang.read_text(encoding="utf-8")


# --- Audit-Log (DoD 5) ----------------------------------------------------


def test_dod_5_bestaetigte_aktion_steht_mit_zeitstempel_im_audit(db_path, postausgang):
    with db.session(db_path) as conn:
        db.init_db(conn)

    async def ja(tool, argumente, vorschau):
        return True

    async def audit(**felder):
        db.log_audit(db_path, **felder)

    run(run_tool("send_email", {"to": "a@b.de", "subject": "s", "body": "b"},
                 bestaetigung=ja, audit=audit))

    eintraege = db.list_audit(db_path)
    assert len(eintraege) == 1
    assert eintraege[0].tool == "send_email"
    assert eintraege[0].decision == "approved"
    assert eintraege[0].executed is True
    assert eintraege[0].created_at.endswith("Z")


def test_auch_die_ablehnung_steht_im_audit(db_path, postausgang):
    with db.session(db_path) as conn:
        db.init_db(conn)

    async def nein(tool, argumente, vorschau):
        return False

    async def audit(**felder):
        db.log_audit(db_path, **felder)

    run(run_tool("send_email", {"to": "a@b.de", "subject": "s", "body": "b"},
                 bestaetigung=nein, audit=audit))
    eintraege = db.list_audit(db_path)
    assert len(eintraege) == 1 and eintraege[0].decision == "denied"
    assert eintraege[0].executed is False


def test_unterhalb_von_external_wird_nichts_protokolliert(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)

    async def audit(**felder):
        db.log_audit(db_path, **felder)

    run(run_tool("clock", audit=audit))
    assert db.list_audit(db_path) == []


def test_das_audit_log_laesst_sich_nicht_aendern(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    db.log_audit(db_path, tool="send_email", arguments={}, permission="EXTERNAL",
                 decision="approved", executed=True)

    for sql in ("UPDATE audit_log SET decision = 'denied'",
                "DELETE FROM audit_log"):
        with pytest.raises(sqlite3.IntegrityError, match="unveraenderlich"):
            with db.session(db_path) as conn:
                conn.execute(sql)
    assert len(db.list_audit(db_path)) == 1


# --- Ende zu Ende ueber die API -------------------------------------------


def test_dod_1_und_3_der_task_haelt_an_und_fragt_nach(client, postausgang: Path):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Krankmeldung schicken"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "send_email", {
            "to": "chef@firma.de", "subject": "Krankmeldung",
            "body": "Ich bin heute nicht da.",
        }),)),
        "Erledigt.", "Erledigt.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Melde mich krank"},
                      headers=TOKEN).json()["task_id"]

    offen = warte_auf(client, tid, lambda d: d.get("confirmation"))
    frage = offen["confirmation"]

    assert frage["tool"] == "send_email"
    assert frage["permission"] == "EXTERNAL"
    assert "chef@firma.de" in frage["preview"]
    assert "Krankmeldung" in frage["preview"]
    assert "Ich bin heute nicht da." in frage["preview"]
    assert any(s["status"] == "needs_confirmation" for s in offen["steps"])

    # DoD 3: solange nichts bestaetigt ist, passiert nichts.
    assert not postausgang.exists()

    client.post(f"/api/tasks/{tid}/confirm", json={"approve": True}, headers=TOKEN)
    warte_auf(client, tid, fertig)
    assert "chef@firma.de" in postausgang.read_text(encoding="utf-8")


def test_ablehnung_ueber_die_api_schreibt_nichts(client, postausgang: Path):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Mail schicken"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "send_email", {
            "to": "a@b.de", "subject": "s", "body": "b"}),)),
        "Nicht gesendet.", "Nicht gesendet.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Mail"},
                      headers=TOKEN).json()["task_id"]
    warte_auf(client, tid, lambda d: d.get("confirmation"))
    client.post(f"/api/tasks/{tid}/confirm", json={"approve": False}, headers=TOKEN)
    warte_auf(client, tid, fertig)

    assert not postausgang.exists()
    audit = client.get("/api/audit", headers=TOKEN).json()
    assert len(audit) == 1 and audit[0]["decision"] == "denied"


def test_bestaetigung_ohne_offene_frage_gibt_409(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Ziel"},
                      headers=TOKEN).json()["task_id"]
    warte_auf(client, tid, fertig)
    antwort = client.post(f"/api/tasks/{tid}/confirm", json={"approve": True},
                          headers=TOKEN)
    assert antwort.status_code in (404, 409)


def test_audit_endpunkt_braucht_den_token(client):
    assert client.get("/api/audit").status_code == 401
