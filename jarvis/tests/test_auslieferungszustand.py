"""Der Zustand, in dem JARVIS ausgeliefert wird.

Alle anderen Task-Tests schieben dem Runner einen skriptierten
`FakeLLMProvider` unter, der schon einen fertigen Plan im Gepaeck hat. Sie
pruefen damit den Runner - zu Recht. Nur pruefen sie nicht, was ein Mensch
bekommt, der die README befolgt und sonst nichts einrichtet.

Genau das steht hier. Kein Provider wird untergeschoben, keine Antwort
vorgegeben: `create_app` baut den Anbieter selbst aus den Settings, so wie
beim echten Start.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.config import Settings
from core.llm import FakeLLMProvider, build_provider

TOKEN = {"X-Jarvis-Token": "test-token-123"}
ENDZUSTAENDE = ("done", "failed", "aborted_budget", "cancelled")


def warte_auf_ende(client: TestClient, task_id: str, sekunden: float = 15.0) -> dict:
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()
        if d["status"] in ENDZUSTAENDE:
            return d
        time.sleep(0.02)
    raise AssertionError(f"Task {task_id} wurde nicht fertig")


@pytest.fixture
def client(settings: Settings):
    with TestClient(create_app(settings)) as c:
        yield c


def test_die_voreinstellung_ist_wirklich_der_fake(settings: Settings):
    """Absicherung: dieser Test prueft den Auslieferungszustand, nicht ein Mock."""
    assert isinstance(build_provider(settings), FakeLLMProvider)


def test_ausgelieferter_zustand_kann_einen_auftrag(client: TestClient):
    antwort = client.post(
        "/api/tasks", json={"goal": "Was ist 2+2"}, headers=TOKEN
    )
    assert antwort.status_code == 200, antwort.text
    task = warte_auf_ende(client, antwort.json()["task_id"])

    assert task["status"] == "done", task["result"]
    assert len(task["steps"]) >= 1, "Plan ohne Schritte"
    assert task["result"], "Auftrag ohne Ergebnis"


def test_ausgelieferter_zustand_schreibt_den_schritt_in_die_datenbank(
    client: TestClient,
):
    """Der Plan darf nicht nur im Speicher existieren."""
    tid = client.post(
        "/api/tasks", json={"goal": "Nenne das heutige Datum"}, headers=TOKEN
    ).json()["task_id"]
    warte_auf_ende(client, tid)

    frisch = client.get(f"/api/tasks/{tid}", headers=TOKEN).json()
    assert frisch["status"] == "done", frisch["result"]
    assert [s["description"] for s in frisch["steps"]], "keine Schritte persistiert"
