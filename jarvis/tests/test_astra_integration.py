"""Auslieferungszustand: echte lokale Daten, klare fehlende Integrationen.

Kein geskripteter Modellanbieter in diesen Tests. Die App muss ohne ihn
starten; sie darf einen unerledigten Auftrag nicht als Erfolg verbuchen.
"""

import time
from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db
from core.contracts import Permission
from core.tools.dispatch import run_tool
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}
FRAGEN = [
    "Was steht heute an?",
    "Wie wird das Wetter?",
    "Erinnere mich morgen an X.",
    "Suche Datei X.",
    "Was weißt du über X?",
    "Zeig mir die aktuelle Weltlage.",
]


@pytest.fixture
def ohne_llm(settings):
    settings.llm_provider = ""
    settings.llm_api_key = ""
    settings.llm_model = ""
    settings.zeitplan_takt_s = 0
    with TestClient(create_app(settings)) as client:
        yield client


def test_fehlendes_llm_steht_im_health(ohne_llm):
    health = ohne_llm.get("/api/health", headers=TOKEN).json()
    assert health["status"] == "degraded"
    assert "LLM nicht eingerichtet" in health["provider_error"]
    assert health["database"] == "ok"


@pytest.mark.parametrize("frage", FRAGEN)
def test_chat_erfindet_ohne_llm_keine_antwort(ohne_llm, frage):
    antwort = ohne_llm.post("/api/chat", json={"message": frage}, headers=TOKEN)
    assert antwort.status_code == 503
    assert "LLM nicht eingerichtet" in antwort.json()["detail"]


@pytest.mark.parametrize("frage", FRAGEN)
def test_oberflaechen_auftrag_ist_ohne_llm_nie_erledigt(ohne_llm, settings, frage):
    antwort = ohne_llm.post("/api/tasks", json={"goal": frage}, headers=TOKEN)
    assert antwort.status_code == 202
    tid = antwort.json()["task_id"]
    ende = time.monotonic() + 5
    while time.monotonic() < ende:
        task = ohne_llm.get(f"/api/tasks/{tid}", headers=TOKEN).json()
        if task["status"] not in ("pending", "running"):
            break
        time.sleep(0.01)
    assert task["status"] == "failed"
    assert "LLM nicht eingerichtet" in task["result"]
    assert task["spent_tokens"] == 0
    assert not any(call.ok for call in db.list_llm_calls(settings.db_path))
    assert "[fake]" not in str(task)


def test_zugangstoken_steht_nie_im_startlog(settings, caplog, monkeypatch):
    monkeypatch.setattr("api.security.secrets.token_urlsafe", lambda _: "GENERATED_TEST_ONLY")
    settings.jarvis_token = ""
    app = create_app(settings)
    with TestClient(app) as client:
        assert client.get("/api/health").status_code == 401
        assert client.get("/api/health", headers={
            "X-Jarvis-Token": app.state.token,
        }).status_code == 200
    assert "GENERATED_TEST_ONLY" not in caplog.text
    assert "JARVIS_TOKEN" in caplog.text


def test_weltlage_meldet_den_fehlenden_anbieter(ohne_llm):
    antwort = ohne_llm.post("/api/weltlage/DE", headers=TOKEN)
    assert antwort.status_code == 503
    assert "LLM nicht eingerichtet" in antwort.json()["detail"]


def test_erinnerung_fuer_morgen_wird_ohne_llm_einmal_zugestellt(ohne_llm, settings):
    from api.zeitplan import pruefe_einmal

    morgen = datetime.now().astimezone() + timedelta(days=1)
    antwort = ohne_llm.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "Integrationstest", "ziel": "Unterlagen mitnehmen",
        "art": "erinnerung", "regel": morgen.strftime("einmal %Y-%m-%d 12:00"),
    })
    assert antwort.status_code == 201
    faellig = datetime.fromisoformat(antwort.json()["naechster_lauf"].replace("Z", "+00:00"))
    # Derselbe Schleifendurchlauf wie im Betrieb, mit kontrollierter Uhrzeit.
    run(pruefe_einmal(ohne_llm.app, jetzt=faellig))
    run(pruefe_einmal(ohne_llm.app, jetzt=faellig + timedelta(seconds=1)))
    nachrichten = ohne_llm.get("/api/messages", headers=TOKEN).json()
    erinnerungen = [m for m in nachrichten if "Unterlagen mitnehmen" in m["content"]]
    assert len(erinnerungen) == 1
    assert erinnerungen[0]["herkunft"]["art"] == "erinnerung"
    assert db.list_llm_calls(settings.db_path) == []


def test_lokale_dateien_kalender_und_memory_teilen_die_app_konfiguration(settings, tmp_path):
    settings.llm_provider = ""
    settings.llm_api_key = ""
    settings.zeitplan_takt_s = 0
    freigabe = tmp_path / "freigabe"
    freigabe.mkdir()
    (freigabe / "unterlagen.txt").write_text("Unterlagen zum Integrationstest.")
    (freigabe / ".env").write_text("TESTDATEI_DARF_NICHT_GELESEN_WERDEN")
    settings.datei_wurzeln = str(freigabe)
    kalender = tmp_path / "kalender.ics"
    heute = date.today().strftime("%Y%m%d")
    kalender.write_text(
        "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:astra-test\n"
        f"DTSTART;VALUE=DATE:{heute}\nSUMMARY:Prueftermin\nEND:VEVENT\nEND:VCALENDAR\n")
    settings.kalender_quelle = str(kalender)
    with TestClient(create_app(settings)) as client:
        suche = run(run_tool("datei_suchen", {"muster": "unterlagen"}, max_permission=Permission.READ))
        assert suche.ok and suche.data["anzahl"] == 1
        assert str(freigabe) not in suche.display
        geheim = run(run_tool("datei_lesen", {"pfad": ".env"}, max_permission=Permission.READ))
        assert not geheim.ok
        termine = run(run_tool("kalender", {"von": date.today().isoformat(),
                                               "bis": date.today().isoformat()}, max_permission=Permission.READ))
        assert termine.ok and "Prueftermin" in termine.display
        assert client.post("/api/memory", headers=TOKEN, json={
            "text": "Die Pruefmappe heisst ASTRA.", "category": "allgemein",
        }).status_code == 201
        fund = run(run_tool("recall", {"query": "Pruefmappe"}, max_permission=Permission.READ))
        assert fund.ok and "ASTRA" in fund.display
        assert db.list_llm_calls(settings.db_path) == []


def test_unbekannter_kalender_und_fehlender_ort_sind_keine_leeren_ergebnisse(ohne_llm):
    kalender = run(run_tool("kalender", max_permission=Permission.READ))
    wetter = run(run_tool("wetter", max_permission=Permission.READ))
    assert not kalender.ok and "KALENDER_QUELLE" in kalender.display
    assert not wetter.ok and "JARVIS_ORT" in wetter.display
