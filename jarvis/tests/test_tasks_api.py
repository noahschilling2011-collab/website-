"""Tests der Task-Endpunkte (Phase 4)."""

from __future__ import annotations

import time

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db, memory
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.tools import registry

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def suche_ohne_netz():
    suche = registry.get("web_search")
    alt = (suche.api_key, suche.transport)
    suche.api_key = "test-key"
    suche.transport = httpx.MockTransport(lambda r: httpx.Response(200, json={
        "web": {"results": [{"title": "Quelle", "url": "https://example.org/q",
                             "description": "Ein Auszug."}]}}))
    yield
    suche.api_key, suche.transport = alt


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def warte_auf_ende(client, task_id: str, sekunden: float = 10.0) -> dict:
    """Der Task laeuft im Hintergrund - hier wird auf sein Ende gewartet."""
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        time.sleep(0.02)
    raise AssertionError(f"Task {task_id} wurde nicht fertig")


def test_tasks_brauchen_den_token(client):
    assert client.post("/api/tasks", json={"goal": "x"}).status_code == 401
    assert client.get("/api/tasks").status_code == 401
    assert client.get("/api/tasks/abc").status_code == 401


def test_task_startet_und_liefert_sofort_eine_id(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    antwort = client.post("/api/tasks", json={"goal": "Etwas tun"}, headers=TOKEN)
    assert antwort.status_code == 202
    assert len(antwort.json()["task_id"]) == 12


def test_dod_1_der_plan_ist_ueber_die_api_sichtbar(client, suche_ohne_netz):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Hebesatz suchen","agent":"research"},'
        '{"description":"Einordnen"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "web_search", {"query": "Hebesatz"}),)),
        "Gefunden: 400 %.", "Eingeordnet.", "Der Hebesatz liegt bei 400 %.",
    ])
    tid = client.post("/api/tasks", json={
        "goal": "Wie hoch ist die aktuelle Grundsteuer in Baden-Württemberg?"
    }, headers=TOKEN).json()["task_id"]

    fertig = warte_auf_ende(client, tid)
    assert [s["description"] for s in fertig["steps"]] == [
        "Hebesatz suchen", "Einordnen",
    ]
    assert fertig["steps"][0]["agent"] == "research"
    assert all(s["status"] == "done" for s in fertig["steps"])
    assert fertig["result"]


def test_unbekannter_task_gibt_404(client):
    assert client.get("/api/tasks/gibtsnicht", headers=TOKEN).status_code == 404


def test_task_taucht_in_der_liste_auf(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Ziel"}, headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)
    liste = client.get("/api/tasks", headers=TOKEN).json()
    assert [t["id"] for t in liste] == [tid]


def test_der_verlauf_bekommt_frage_und_antwort(client, settings):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A.", "Die Antwort.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Die Frage"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)

    messages = client.get("/api/messages", headers=TOKEN).json()
    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "Die Frage"
    assert messages[1]["content"] == "Die Antwort."


def test_werkzeugaufrufe_haengen_an_der_antwort(client, settings):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Uhrzeit"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
        "Es ist spät.", "Es ist spät.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Wie spät?"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)

    messages = client.get("/api/messages", headers=TOKEN).json()
    assert [t["name"] for t in messages[1]["tool_calls"]] == ["clock"]


def test_nutzernachricht_ueberlebt_einen_gescheiterten_task(client, settings):
    client.app.state.provider = FakeLLMProvider(replies=["kaputt", "kaputt", "kaputt"])
    tid = client.post("/api/tasks", json={"goal": "Die Frage"},
                      headers=TOKEN).json()["task_id"]
    fertig = warte_auf_ende(client, tid)
    assert fertig["status"] == "failed"
    messages = client.get("/api/messages", headers=TOKEN).json()
    assert messages[0]["content"] == "Die Frage"


def test_task_landet_im_episodischen_gedaechtnis(client, settings):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Ziel"}, headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)
    log = client.get("/api/task-log", headers=TOKEN).json()
    assert len(log) == 1 and log[0]["task_id"] == tid and log[0]["outcome"] == "done"


def test_abbruch_eines_fertigen_tasks_meldet_das_freundlich(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Ziel"}, headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)
    antwort = client.post(f"/api/tasks/{tid}/cancel", headers=TOKEN).json()
    assert antwort["status"] == "done" and "lief nicht mehr" in antwort["note"]


def test_abbruch_eines_unbekannten_tasks_gibt_404(client):
    assert client.post("/api/tasks/gibtsnicht/cancel",
                       headers=TOKEN).status_code == 404


def test_budgetabbruch_ist_ueber_die_api_sichtbar(client, settings):
    settings.budget_max_steps = 2
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"A"},{"description":"B"},'
            '{"description":"C"}]}',
            "Teil A erledigt.", "Teil B erledigt.", "Teilergebnis.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Großes Ziel"},
                     headers=TOKEN).json()["task_id"]
        fertig = warte_auf_ende(c, tid)
    assert fertig["status"] == "aborted_budget"
    assert "max_steps" in fertig["abort_reason"]
    assert [s["status"] for s in fertig["steps"]] == ["done", "done", "skipped"]
    assert fertig["result"]


def test_kosten_und_token_werden_mitgefuehrt(client, settings):
    settings.llm_price_in_per_mtok = 4.6
    settings.llm_price_out_per_mtok = 23.0
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Ziel"}, headers=TOKEN).json()["task_id"]
        fertig = warte_auf_ende(c, tid)
    assert fertig["spent_tokens"] > 0
    assert fertig["spent_cost_eur"] > 0
