"""Tests der HTTP-Schicht - Ende zu Ende gegen den Fake-Anbieter."""

from __future__ import annotations

import re

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.routes import derive_title
from core.llm import FakeLLMProvider, LLMError


@pytest.fixture
def client(settings):
    app = create_app(settings)
    with TestClient(app) as c:
        yield c


@pytest.fixture
def fake(client) -> FakeLLMProvider:
    """Der Anbieter, den die laufende App tatsaechlich benutzt."""
    provider = client.app.state.provider
    assert isinstance(provider, FakeLLMProvider)
    return provider


# --- Health ---------------------------------------------------------------


def test_health_meldet_anbieter_modell_und_datenbank(client):
    body = client.get("/api/health").json()
    assert body["status"] == "ok"
    assert body["phase"] == 1
    assert body["provider"] == "fake"
    assert body["database"] == "ok"
    assert body["api_key_configured"] is False
    assert body["conversations"] == 0


def test_health_gibt_keinen_key_preis(client, settings):
    settings.anthropic_api_key = "sk-ant-nicht-verraten-1234"
    body = client.get("/api/health").text
    assert "nicht-verraten" not in body


# --- Konversationen -------------------------------------------------------


def test_konversationen_sind_anfangs_leer(client):
    assert client.get("/api/conversations").json() == []


def test_anlegen_lesen_umbenennen_loeschen(client):
    created = client.post("/api/conversations", json={"title": "Test"})
    assert created.status_code == 201
    cid = created.json()["id"]

    assert client.get(f"/api/conversations/{cid}").json()["messages"] == []

    renamed = client.patch(f"/api/conversations/{cid}", json={"title": "Neu"})
    assert renamed.json()["title"] == "Neu"

    assert client.delete(f"/api/conversations/{cid}").status_code == 204
    assert client.get(f"/api/conversations/{cid}").status_code == 404


def test_unbekannte_konversation_gibt_404(client):
    assert client.get("/api/conversations/999").status_code == 404
    assert client.delete("/api/conversations/999").status_code == 404
    assert client.patch("/api/conversations/999", json={"title": "x"}).status_code == 404


# --- Chat -----------------------------------------------------------------


def test_chat_legt_konversation_an_und_speichert_beide_zeilen(client):
    body = client.post("/api/chat", json={"message": "Hallo JARVIS"}).json()

    assert body["user_message"]["content"] == "Hallo JARVIS"
    assert body["reply"]["role"] == "assistant"
    assert body["conversation"]["title"] == "Hallo JARVIS"

    detail = client.get(f"/api/conversations/{body['conversation']['id']}").json()
    assert [m["role"] for m in detail["messages"]] == ["user", "assistant"]
    assert detail["message_count"] == 2


def test_zweite_nachricht_bleibt_in_derselben_konversation(client):
    first = client.post("/api/chat", json={"message": "eins"}).json()
    cid = first["conversation"]["id"]

    second = client.post(
        "/api/chat", json={"message": "zwei", "conversation_id": cid}
    ).json()
    assert second["conversation"]["id"] == cid

    detail = client.get(f"/api/conversations/{cid}").json()
    assert [m["role"] for m in detail["messages"]] == [
        "user", "assistant", "user", "assistant",
    ]
    assert detail["messages"][0]["content"] == "eins"
    assert detail["messages"][2]["content"] == "zwei"
    assert len(client.get("/api/conversations").json()) == 1


def test_der_verlauf_geht_wirklich_ans_modell(client, fake):
    """Beim zweiten Aufruf sieht das Modell den ganzen bisherigen Verlauf."""
    cid = client.post("/api/chat", json={"message": "eins"}).json()["conversation"]["id"]
    erste_antwort = client.get(f"/api/conversations/{cid}").json()["messages"][1]["content"]

    client.post("/api/chat", json={"message": "zwei", "conversation_id": cid})

    gesendet = fake.calls[1]["messages"]
    assert [m.role for m in gesendet] == ["user", "assistant", "user"]
    assert [m.content for m in gesendet] == ["eins", erste_antwort, "zwei"]


def test_systemprompt_wird_mitgeschickt(client, fake, settings):
    client.post("/api/chat", json={"message": "x"})
    assert fake.calls[0]["system"] == settings.system_prompt


def test_verlaufsfenster_wird_eingehalten(client, fake, settings):
    settings.history_limit = 4
    cid = client.post("/api/chat", json={"message": "m0"}).json()["conversation"]["id"]
    for i in range(1, 5):
        client.post("/api/chat", json={"message": f"m{i}", "conversation_id": cid})
    assert len(fake.calls[-1]["messages"]) == 4


def test_tokenzahlen_werden_gespeichert(client):
    body = client.post("/api/chat", json={"message": "Hallo"}).json()
    assert body["reply"]["output_tokens"] > 0
    assert body["usage"]["output_tokens"] == body["reply"]["output_tokens"]
    assert body["reply"]["model"] == "fake-echo-1"


def test_chat_in_unbekannter_konversation_gibt_404(client):
    assert client.post(
        "/api/chat", json={"message": "x", "conversation_id": 999}
    ).status_code == 404


@pytest.mark.parametrize("nachricht", ["", "   ", "\n\t "])
def test_leere_nachricht_wird_abgelehnt(client, nachricht: str):
    assert client.post("/api/chat", json={"message": nachricht}).status_code == 422


def test_titel_wird_aus_der_ersten_zeile_gekuerzt():
    assert derive_title("Kurz") == "Kurz"
    assert derive_title("Zeile eins\nZeile zwei") == "Zeile eins"
    lang = derive_title("A" * 200)
    assert len(lang) == 48 and lang.endswith("…")
    assert derive_title("   ") == "Neue Konversation"


# --- Fehlerpfad -----------------------------------------------------------


class KaputterProvider:
    name = "kaputt"
    model = "keins"

    def __init__(self, error: LLMError) -> None:
        self.error = error

    def complete(self, messages, *, system, max_tokens=None):
        raise self.error

    def close(self) -> None:
        return None


def test_modellfehler_wird_zu_502_mit_klartext(client):
    client.app.state.provider = KaputterProvider(
        LLMError("Der Anbieter ist ueberlastet (529).", status=529, retryable=True)
    )
    response = client.post("/api/chat", json={"message": "x"})
    assert response.status_code == 502
    assert response.json()["retryable"] is True
    assert "ueberlastet" in response.json()["detail"]


def test_fehlender_key_wird_zu_503(client):
    client.app.state.provider = KaputterProvider(
        LLMError("Kein API-Key gesetzt.", kind="missing_api_key")
    )
    response = client.post("/api/chat", json={"message": "x"})
    assert response.status_code == 503
    assert response.json()["kind"] == "missing_api_key"


def test_nutzernachricht_ueberlebt_einen_modellfehler(client):
    """Was der Nutzer getippt hat, darf nicht verloren gehen."""
    client.app.state.provider = KaputterProvider(LLMError("kaputt"))
    client.post("/api/chat", json={"message": "wichtiger Satz"})

    conversations = client.get("/api/conversations").json()
    assert len(conversations) == 1
    detail = client.get(f"/api/conversations/{conversations[0]['id']}").json()
    assert [m["content"] for m in detail["messages"]] == ["wichtiger Satz"]


# --- Oberflaeche ----------------------------------------------------------


def test_wurzel_liefert_die_oberflaeche(client):
    response = client.get("/")
    assert response.status_code == 200
    assert "JARVIS" in response.text
    assert "<!doctype html>" in response.text.lower()


def test_oberflaeche_laedt_nichts_aus_dem_netz(client):
    """Kein CDN, keine Webfont, kein Tracker - die Datei ist eigenstaendig."""
    html = client.get("/").text
    urls = set(re.findall(r"https?://[^\s\"'()<>]+", html))
    # Die einzige erlaubte Ausnahme sind XML-Namensraeume. Die werden nie
    # abgerufen, sie identifizieren nur das SVG-Vokabular.
    echte_abrufe = {u for u in urls if not u.startswith("http://www.w3.org/")}
    assert echte_abrufe == set(), echte_abrufe


def test_oberflaeche_setzt_niemals_innerhtml(client):
    """Modellausgabe darf nie als HTML interpretiert werden."""
    html = client.get("/").text
    assert ".innerHTML =" not in html
    assert "insertAdjacentHTML" not in html


# --- Anbieter nicht einrichtbar -------------------------------------------


@pytest.fixture
def client_ohne_key(settings):
    """App mit anthropic-Anbieter, aber ohne API-Key."""
    settings.provider = "anthropic"
    settings.anthropic_api_key = ""
    app = create_app(settings)
    with TestClient(app) as c:
        yield c


def test_fehlender_key_verhindert_den_start_nicht(client_ohne_key):
    """Sonst kaeme der Nutzer nie an die Stelle, die ihm sagt was fehlt."""
    assert client_ohne_key.get("/").status_code == 200


def test_health_nennt_den_grund(client_ohne_key):
    body = client_ohne_key.get("/api/health").json()
    assert body["status"] == "degraded"
    assert "ANTHROPIC_API_KEY" in body["provider_error"]


def test_chat_ohne_key_gibt_503_statt_absturz(client_ohne_key):
    response = client_ohne_key.post("/api/chat", json={"message": "Hallo"})
    assert response.status_code == 503
    assert response.json()["kind"] == "missing_api_key"


def test_health_ist_ok_wenn_alles_steht(client):
    body = client.get("/api/health").json()
    assert body["status"] == "ok"
    assert body["provider_error"] is None
