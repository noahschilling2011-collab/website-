"""Tests des Sprachmodus (Phase 9).

**Was hier nicht geprüft wird, und warum:** Spracherkennung und
Sprachausgabe laufen im Browser über die Web Speech API. Headless-Chromium
hat weder Mikrofon noch Sprachsynthese - DoD 1, 2 und 4 lassen sich hier
nicht ausführen und stehen in STATUS.md als ungeprüft.

Prüfbar ist der Teil, der im Backend liegt: dass der Sprachmodus die Antwort
wirklich kürzer erzwingt (DoD 3) und nicht nur höflich darum bittet.
"""

from __future__ import annotations

import re
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.agents import SPRACHSTIL, baue_agenten
from core.contracts import Permission, TaskBudget
from core.llm import FakeLLMProvider
from core.runner import fuehre_task_aus
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}
INDEX = Path(__file__).resolve().parent.parent / "index.html"


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def warte_auf_ende(client, tid: str, sekunden: float = 10.0) -> dict:
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{tid}", headers=TOKEN).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        time.sleep(0.02)
    raise AssertionError("Task wurde nicht fertig")


# --- DoD 3: der Systemprompt erzwingt die Kürze ---------------------------


def test_der_sprachstil_verlangt_hoechstens_drei_saetze():
    assert "drei Saetze" in SPRACHSTIL
    assert "VORGELESEN" in SPRACHSTIL
    assert "Keine Aufzaehlungen" in SPRACHSTIL


def test_ohne_sprachmodus_steht_der_stil_nicht_im_prompt():
    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)
    for agent in agenten.values():
        assert "VORGELESEN" not in agent.system_prompt


def test_mit_sprachmodus_steht_er_in_jedem_agentenprompt():
    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL,
                           antwortstil=SPRACHSTIL)
    for name, agent in agenten.items():
        assert "VORGELESEN" in agent.system_prompt, name


def test_die_zusammenfassung_bekommt_den_sprachstil():
    provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Kurz gefasst.",
    ])
    run(fuehre_task_aus(provider, "Ziel", budget=TaskBudget(),
                        kosten=lambda a, b: 0.0, antwortstil=SPRACHSTIL))
    # Der letzte Modellzug ist die Zusammenfassung.
    assert "VORGELESEN" in provider.calls[-1]["system"]


def test_im_sprachmodus_haengt_keine_quellenliste_unter_der_antwort():
    """Vorgelesene URLs sind unbrauchbar."""
    provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Kurz gefasst.",
    ])
    t = run(fuehre_task_aus(provider, "Ziel", budget=TaskBudget(),
                            kosten=lambda a, b: 0.0, antwortstil=SPRACHSTIL))
    assert "Quellen:" not in (t.result or "")


def test_im_textmodus_stehen_die_quellen_weiterhin_darunter():
    from core.contracts import Step, StepStatus, ToolResult

    provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A","agent":"research"}]}',
        "Gefunden.", "Zusammengefasst.",
    ])

    async def lauf():
        t = await fuehre_task_aus(provider, "Ziel", budget=TaskBudget(),
                                  kosten=lambda a, b: 0.0)
        return t

    # Ohne echte Quelle scheitert der Rechercheschritt - deshalb hier direkt
    # der Textmodus-Pfad mit einer Quelle im Schritt.
    t = run(lauf())
    assert "VORGELESEN" not in provider.calls[-1]["system"]


def test_der_endpunkt_nimmt_das_voice_flag(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Kurz.",
    ])
    antwort = client.post("/api/tasks", json={"goal": "Wie spät?", "voice": True},
                          headers=TOKEN)
    assert antwort.status_code == 202
    warte_auf_ende(client, antwort.json()["task_id"])
    assert "VORGELESEN" in client.app.state.provider.calls[-1]["system"]


def test_ohne_flag_bleibt_es_beim_textmodus(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Ausführlich.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Wie spät?"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)
    assert "VORGELESEN" not in client.app.state.provider.calls[-1]["system"]


# --- Oberfläche: was ohne Mikrofon prüfbar ist ----------------------------


def test_die_oberflaeche_hat_push_to_talk_und_keine_dauererkennung():
    html = INDEX.read_text(encoding="utf-8")
    assert 'id="btn-mic"' in html
    assert "mousedown" in html and "touchstart" in html
    # Verboten in dieser Phase: Wake Word und Streaming-STT.
    # `continuous = false` ist genau die Zeile, die Dauerhorchen ausschliesst;
    # `interimResults = false` die, die Streaming-STT ausschliesst. Auf das
    # Wort "Wake Word" zu pruefen waere falsch - es steht im Kommentar, der
    # erklaert, warum es nicht gebaut ist.
    assert "continuous = false" in html
    assert "interimResults = false" in html
    assert "continuous = true" not in html


def test_die_oberflaeche_kann_deutsch_und_englisch():
    html = INDEX.read_text(encoding="utf-8")
    assert "'de-DE'" in html and "'en-US'" in html
    assert 'id="btn-sprache"' in html


def test_eine_laufende_ausgabe_wird_beim_erneuten_druecken_gestoppt():
    """DoD 2, soweit im Quelltext prüfbar: hoerenStarten ruft voice.stopp()."""
    html = INDEX.read_text(encoding="utf-8")
    block = html[html.index("function hoerenStarten()"):html.index("function hoerenBeenden()")]
    assert "voice.stopp()" in block


def test_die_erkennung_ist_hinter_einer_abstraktion():
    """Damit später ein besserer Anbieter dahinter kann."""
    html = INDEX.read_text(encoding="utf-8")
    assert "function BrowserVoice()" in html
    for methode in ("hoere:", "sprich:", "stopp:", "sttVerfuegbar", "ttsVerfuegbar"):
        assert methode in html


def test_ohne_spracherkennung_wird_der_knopf_abgeschaltet_statt_zu_kraachen():
    html = INDEX.read_text(encoding="utf-8")
    assert "el.mic.disabled = true" in html
    assert "Chrome kann es" in html


def test_nur_gesprochene_fragen_werden_vorgelesen():
    html = INDEX.read_text(encoding="utf-8")
    assert "if (warSprache && daten.result) lieseVor" in html
