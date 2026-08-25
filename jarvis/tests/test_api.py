"""Tests der HTTP-Schicht - Ende zu Ende gegen den Fake-Anbieter."""

from __future__ import annotations

import re

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db
from core.llm import FakeLLMProvider, LLMError

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


@pytest.fixture
def fake(client) -> FakeLLMProvider:
    provider = client.app.state.provider
    assert isinstance(provider, FakeLLMProvider)
    return provider


# --- Zugangsschutz (0.4, DoD 6) -------------------------------------------


@pytest.mark.parametrize("methode,pfad", [
    ("get", "/api/health"), ("get", "/api/messages"), ("post", "/api/chat"),
])
def test_ohne_token_gibt_401(client, methode: str, pfad: str):
    antwort = client.request(methode, pfad, json={"message": "x"})
    assert antwort.status_code == 401


def test_falscher_token_gibt_401(client):
    antwort = client.get("/api/health", headers={"X-Jarvis-Token": "falsch"})
    assert antwort.status_code == 401


def test_richtiger_token_kommt_durch(client):
    assert client.get("/api/health", headers=TOKEN).status_code == 200


def test_ohne_token_wird_nichts_gespeichert(client, settings):
    client.post("/api/chat", json={"message": "unerlaubt"})
    assert db.list_messages(settings.db_path) == []


def test_leerer_jarvis_token_wird_gewuerfelt_nicht_abgeschaltet(settings):
    """Ein leerer Wert wuerde sonst jeden Request ohne Header durchlassen."""
    settings.jarvis_token = ""
    app = create_app(settings)
    assert app.state.token_generated is True
    assert len(app.state.token) >= 32
    with TestClient(app) as c:
        assert c.get("/api/health").status_code == 401
        assert c.get("/api/health",
                     headers={"X-Jarvis-Token": app.state.token}).status_code == 200


# --- Oberflaeche ----------------------------------------------------------


def test_wurzel_braucht_keinen_token(client):
    """Sonst koennte die Seite den Token nie bekommen."""
    assert client.get("/").status_code == 200


def test_token_wird_in_die_seite_eingesetzt(client):
    html = client.get("/").text
    assert "__JARVIS_TOKEN__" not in html
    assert "test-token-123" in html


def test_der_llm_key_landet_nie_in_der_seite(client, settings):
    """0.4.1 - und DoD 7."""
    settings.llm_api_key = "sk-ant-darf-nicht-raus-1234"
    html = client.get("/").text
    assert "sk-ant-darf-nicht-raus-1234" not in html
    assert not re.search(r"sk-", html, re.IGNORECASE)


def test_seite_laedt_nichts_aus_dem_netz(client):
    html = client.get("/").text
    urls = set(re.findall(r"https?://[^\s\"'()<>]+", html))
    # Erlaubt sind nur XML-Namensraeume. Die werden nie abgerufen.
    assert {u for u in urls if not u.startswith("http://www.w3.org/")} == set()


def test_seite_setzt_niemals_innerhtml(client):
    html = client.get("/").text
    assert ".innerHTML =" not in html and "insertAdjacentHTML" not in html


# --- Chat -----------------------------------------------------------------


def test_chat_antwortet_mit_reply_und_task_id(client):
    body = client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN).json()
    assert set(body) == {"reply", "task_id", "tool_calls"}
    assert body["reply"]
    assert len(body["task_id"]) == 12


def test_chat_schreibt_zwei_zeilen_in_messages(client, settings):
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    messages = db.list_messages(settings.db_path)
    assert [m.role for m in messages] == ["user", "assistant"]
    assert messages[0].content == "Hallo"


def test_chat_schreibt_genau_eine_zeile_in_llm_calls(client, settings):
    """DoD 5."""
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    calls = db.list_llm_calls(settings.db_path)
    assert len(calls) == 1
    assert calls[0].ok is True
    assert calls[0].in_tokens > 0 and calls[0].out_tokens > 0
    assert calls[0].model == "fake-echo-1"


def test_kosten_werden_aus_den_preisen_der_env_gerechnet(client, settings):
    settings.llm_price_in_per_mtok = 4.6
    settings.llm_price_out_per_mtok = 23.0
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    call = db.list_llm_calls(settings.db_path)[0]
    assert call.cost_eur == pytest.approx(
        settings.cost_eur(call.in_tokens, call.out_tokens)
    )
    assert call.cost_eur > 0


def test_ohne_preise_bleibt_die_kostenspalte_null(client, settings):
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    assert db.list_llm_calls(settings.db_path)[0].cost_eur == 0.0


def test_der_verlauf_geht_wirklich_ans_modell(client, fake):
    client.post("/api/chat", json={"message": "eins"}, headers=TOKEN)
    client.post("/api/chat", json={"message": "zwei"}, headers=TOKEN)
    gesendet = fake.calls[1]["messages"]
    assert [m.role for m in gesendet] == ["user", "assistant", "user"]
    assert gesendet[0].content == "eins" and gesendet[2].content == "zwei"


def test_systemprompt_wird_mitgeschickt(client, fake, settings):
    client.post("/api/chat", json={"message": "x"}, headers=TOKEN)
    assert fake.calls[0]["system"] == settings.system_prompt


def test_verlaufsfenster_wird_eingehalten(client, fake, settings):
    settings.history_limit = 4
    for i in range(5):
        client.post("/api/chat", json={"message": f"m{i}"}, headers=TOKEN)
    assert len(fake.calls[-1]["messages"]) == 4


@pytest.mark.parametrize("nachricht", ["", "   ", "\n\t "])
def test_leere_nachricht_wird_abgelehnt(client, nachricht: str):
    assert client.post(
        "/api/chat", json={"message": nachricht}, headers=TOKEN
    ).status_code == 422


def test_verlauf_ueberlebt_einen_neustart(settings):
    """DoD 4 - auf Datenbankebene."""
    with TestClient(create_app(settings)) as erste:
        erste.post("/api/chat", json={"message": "merk dir das"}, headers=TOKEN)
    with TestClient(create_app(settings)) as zweite:
        messages = zweite.get("/api/messages", headers=TOKEN).json()
    assert [m["role"] for m in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "merk dir das"


# --- Health ---------------------------------------------------------------


def test_health_meldet_anbieter_und_summen(client):
    body = client.get("/api/health", headers=TOKEN).json()
    assert body["status"] == "ok"
    assert body["phase"] == 2
    assert body["provider"] == "fake"
    assert body["database"] == "ok"
    assert body["spend"]["calls"] == 0
    assert body["spend"]["prices_configured"] is False


def test_health_zaehlt_nach_einem_chat_mit(client):
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    spend = client.get("/api/health", headers=TOKEN).json()["spend"]
    assert spend["calls"] == 1 and spend["out_tokens"] > 0


def test_health_gibt_keinen_key_preis(client, settings):
    settings.llm_api_key = "sk-ant-nicht-verraten-1234"
    assert "nicht-verraten" not in client.get("/api/health", headers=TOKEN).text


# --- Fehlerpfad -----------------------------------------------------------


class KaputterProvider:
    name = "kaputt"
    model = "keins"

    def __init__(self, error: LLMError) -> None:
        self.error = error

    async def complete(self, messages, *, system, tools=None):
        raise self.error

    async def aclose(self) -> None:
        return None


def test_modellfehler_wird_zu_502_mit_klartext(client):
    client.app.state.provider = KaputterProvider(
        LLMError("Der Anbieter ist ueberlastet (529).", status=529, retryable=True)
    )
    antwort = client.post("/api/chat", json={"message": "x"}, headers=TOKEN)
    assert antwort.status_code == 502
    assert antwort.json()["retryable"] is True


def test_fehlgeschlagener_aufruf_landet_trotzdem_in_llm_calls(client, settings):
    """Sonst faellt eine Retry-Schleife, die Geld verbrennt, erst auf der Rechnung auf."""
    client.app.state.provider = KaputterProvider(LLMError("kaputt", duration_ms=42))
    client.post("/api/chat", json={"message": "x"}, headers=TOKEN)
    calls = db.list_llm_calls(settings.db_path)
    assert len(calls) == 1 and calls[0].ok is False and calls[0].duration_ms == 42


def test_nutzernachricht_ueberlebt_einen_modellfehler(client, settings):
    client.app.state.provider = KaputterProvider(LLMError("kaputt"))
    client.post("/api/chat", json={"message": "wichtiger Satz"}, headers=TOKEN)
    assert [m.content for m in db.list_messages(settings.db_path)] == ["wichtiger Satz"]


# --- Anbieter nicht einrichtbar -------------------------------------------


@pytest.fixture
def client_ohne_key(settings):
    settings.llm_provider = "anthropic"
    settings.llm_api_key = ""
    settings.llm_model = "claude-opus-5"
    with TestClient(create_app(settings)) as c:
        yield c


def test_fehlender_key_verhindert_den_start_nicht(client_ohne_key):
    """Sonst kaeme der Nutzer nie an die Stelle, die ihm sagt was fehlt."""
    assert client_ohne_key.get("/").status_code == 200


def test_health_nennt_den_grund(client_ohne_key):
    body = client_ohne_key.get("/api/health", headers=TOKEN).json()
    assert body["status"] == "degraded"
    assert "LLM_API_KEY" in body["provider_error"]


def test_chat_ohne_key_gibt_503_statt_absturz(client_ohne_key):
    antwort = client_ohne_key.post("/api/chat", json={"message": "x"}, headers=TOKEN)
    assert antwort.status_code == 503
    assert antwort.json()["kind"] == "missing_api_key"


def test_chat_protokolliert_den_prompt_hash(client, settings):
    client.post("/api/chat", json={"message": "Hallo"}, headers=TOKEN)
    call = db.list_llm_calls(settings.db_path)[0]
    assert len(call.prompt_hash) == 16
