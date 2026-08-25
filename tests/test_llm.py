"""Tests der Modellanbindung.

Der Anthropic-Anbieter wird gegen einen `httpx.MockTransport` geprueft. Das
ist der einzige Weg, die tatsaechlich gesendete Anfrage zu sehen, ohne einen
Aufruf zu bezahlen.
"""

from __future__ import annotations

import json

import httpx
import pytest

from core.llm import (
    ANTHROPIC_VERSION,
    AnthropicProvider,
    FakeLLMProvider,
    LLMError,
    LLMMessage,
    build_provider,
)
from core.config import Settings


# --- Fake -----------------------------------------------------------------


def test_fake_ist_deterministisch():
    a = FakeLLMProvider().complete([LLMMessage("user", "Hallo")], system="S")
    b = FakeLLMProvider().complete([LLMMessage("user", "Hallo")], system="S")
    assert a.text == b.text


def test_fake_enthaelt_die_letzte_nutzernachricht():
    reply = FakeLLMProvider().complete(
        [LLMMessage("user", "erste"), LLMMessage("assistant", "ok"),
         LLMMessage("user", "zweite")],
        system="S",
    )
    assert "zweite" in reply.text
    assert "erste" not in reply.text


def test_fake_spielt_geskriptete_antworten_ab():
    p = FakeLLMProvider(replies=["eins", "zwei"])
    assert p.complete([LLMMessage("user", "x")], system="S").text == "eins"
    assert p.complete([LLMMessage("user", "x")], system="S").text == "zwei"
    # Danach wird der letzte Eintrag wiederholt statt zu krachen.
    assert p.complete([LLMMessage("user", "x")], system="S").text == "zwei"


def test_fake_protokolliert_aufrufe():
    p = FakeLLMProvider()
    p.complete([LLMMessage("user", "x")], system="Systemprompt", max_tokens=99)
    assert len(p.calls) == 1
    assert p.calls[0]["system"] == "Systemprompt"
    assert p.calls[0]["max_tokens"] == 99


# --- Aufbau ---------------------------------------------------------------


def test_build_provider_liefert_fake_als_voreinstellung():
    provider = build_provider(Settings(_env_file=None))
    assert isinstance(provider, FakeLLMProvider)


def test_anthropic_ohne_key_meldet_klar():
    with pytest.raises(LLMError) as exc:
        AnthropicProvider("", model="claude-opus-5")
    assert exc.value.kind == "missing_api_key"
    assert "ANTHROPIC_API_KEY" in str(exc.value)


# --- Anfrageform ----------------------------------------------------------


def _antwort(text: str = "Antwort", **extra):
    payload = {
        "id": "msg_01",
        "type": "message",
        "role": "assistant",
        "model": "claude-opus-5",
        "content": [{"type": "text", "text": text}],
        "stop_reason": "end_turn",
        "usage": {"input_tokens": 11, "output_tokens": 7},
    }
    payload.update(extra)
    return payload


def _provider(handler, **kwargs):
    return AnthropicProvider(
        "sk-ant-test-key",
        model=kwargs.pop("model", "claude-opus-5"),
        transport=httpx.MockTransport(handler),
        sleep=lambda _seconds: None,
        **kwargs,
    )


def test_anfrage_hat_die_dokumentierten_header_und_felder():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["url"] = str(request.url)
        gesehen["headers"] = dict(request.headers)
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    provider = _provider(handler)
    provider.complete([LLMMessage("user", "Hallo")], system="Sei knapp.")

    assert gesehen["url"] == "https://api.anthropic.com/v1/messages"
    assert gesehen["headers"]["x-api-key"] == "sk-ant-test-key"
    assert gesehen["headers"]["anthropic-version"] == ANTHROPIC_VERSION
    assert gesehen["headers"]["content-type"] == "application/json"

    body = gesehen["body"]
    assert body["model"] == "claude-opus-5"
    assert body["max_tokens"] == 16000
    assert body["system"] == "Sei knapp."
    assert body["messages"] == [{"role": "user", "content": "Hallo"}]
    assert body["output_config"] == {"effort": "high"}


@pytest.mark.parametrize("verboten", ["temperature", "top_p", "top_k", "thinking"])
def test_anfrage_sendet_keine_auf_opus5_verbotenen_felder(verboten: str):
    """temperature/top_p/top_k und thinking.budget_tokens sind dort ein 400."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen.update(json.loads(request.content))
        return httpx.Response(200, json=_antwort())

    _provider(handler).complete([LLMMessage("user", "x")], system="S")
    assert verboten not in gesehen


def test_max_tokens_kann_je_aufruf_ueberschrieben_werden():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen.update(json.loads(request.content))
        return httpx.Response(200, json=_antwort())

    _provider(handler).complete([LLMMessage("user", "x")], system="S", max_tokens=512)
    assert gesehen["max_tokens"] == 512


def test_leerer_verlauf_wird_gar_nicht_erst_gesendet():
    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("haette nicht senden duerfen")

    with pytest.raises(LLMError):
        _provider(handler).complete([], system="S")


def test_verlauf_muss_mit_user_beginnen():
    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("haette nicht senden duerfen")

    with pytest.raises(LLMError):
        _provider(handler).complete([LLMMessage("assistant", "hm")], system="S")


# --- Antwortform ----------------------------------------------------------


def test_textbloecke_werden_zusammengesetzt_denkbloecke_nicht():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=_antwort(
                content=[
                    {"type": "thinking", "thinking": ""},
                    {"type": "text", "text": "Teil eins. "},
                    {"type": "text", "text": "Teil zwei."},
                ]
            ),
        )

    reply = _provider(handler).complete([LLMMessage("user", "x")], system="S")
    assert reply.text == "Teil eins. Teil zwei."


def test_usage_wird_uebernommen():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=_antwort(
                usage={
                    "input_tokens": 120,
                    "output_tokens": 34,
                    "cache_read_input_tokens": 90,
                    "cache_creation_input_tokens": 5,
                }
            ),
        )

    usage = _provider(handler).complete([LLMMessage("user", "x")], system="S").usage
    assert (usage.input_tokens, usage.output_tokens) == (120, 34)
    assert usage.cache_read_input_tokens == 90
    assert usage.cache_creation_input_tokens == 5


def test_ablehnung_wird_als_fehler_gemeldet():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=_antwort(
                content=[],
                stop_reason="refusal",
                stop_details={"type": "refusal", "category": "cyber"},
            ),
        )

    with pytest.raises(LLMError) as exc:
        _provider(handler).complete([LLMMessage("user", "x")], system="S")
    assert exc.value.kind == "refusal"
    assert "cyber" in str(exc.value)


def test_antwort_ohne_text_ist_ein_fehler():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(content=[]))

    with pytest.raises(LLMError) as exc:
        _provider(handler).complete([LLMMessage("user", "x")], system="S")
    assert exc.value.kind == "empty_response"


# --- Fehler und Wiederholung ----------------------------------------------


@pytest.mark.parametrize(
    "status,text_teil",
    [
        (400, "abgelehnt"),
        (401, "API-Key"),
        (403, "darf dieses Modell nicht"),
        (404, "unbekannt"),
        (413, "zu gross"),
    ],
)
def test_nicht_wiederholbare_fehler_werden_uebersetzt(status: int, text_teil: str):
    versuche = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        versuche["n"] += 1
        return httpx.Response(status, json={"error": {"message": "Details vom Anbieter"}})

    with pytest.raises(LLMError) as exc:
        _provider(handler).complete([LLMMessage("user", "x")], system="S")

    assert text_teil in str(exc.value)
    assert "Details vom Anbieter" in str(exc.value)
    assert exc.value.status == status
    assert versuche["n"] == 1, "darf nicht wiederholt werden"


def test_429_wird_wiederholt_und_gelingt_dann():
    versuche = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        versuche["n"] += 1
        if versuche["n"] == 1:
            return httpx.Response(429, headers={"retry-after": "0"},
                                  json={"error": {"message": "slow down"}})
        return httpx.Response(200, json=_antwort("endlich"))

    reply = _provider(handler).complete([LLMMessage("user", "x")], system="S")
    assert reply.text == "endlich"
    assert versuche["n"] == 2


def test_529_gibt_nach_der_letzten_wiederholung_auf():
    versuche = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        versuche["n"] += 1
        return httpx.Response(529, json={"error": {"message": "overloaded"}})

    with pytest.raises(LLMError) as exc:
        _provider(handler, max_retries=2).complete([LLMMessage("user", "x")], system="S")

    assert exc.value.retryable is True
    assert versuche["n"] == 3, "ein Versuch plus zwei Wiederholungen"


def test_retry_after_wird_beachtet():
    gewartet: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, headers={"retry-after": "7"},
                              json={"error": {"message": "nope"}})

    provider = AnthropicProvider(
        "sk-ant-test",
        model="claude-opus-5",
        max_retries=1,
        transport=httpx.MockTransport(handler),
        sleep=gewartet.append,
    )
    with pytest.raises(LLMError):
        provider.complete([LLMMessage("user", "x")], system="S")
    assert gewartet == [7.0]


def test_zeitueberschreitung_wird_uebersetzt():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("zu langsam", request=request)

    with pytest.raises(LLMError) as exc:
        _provider(handler, max_retries=0).complete([LLMMessage("user", "x")], system="S")
    assert exc.value.kind == "timeout"


def test_api_key_taucht_in_keiner_fehlermeldung_auf():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": {"message": "invalid x-api-key"}})

    provider = AnthropicProvider(
        "sk-ant-streng-geheim-9876",
        model="claude-opus-5",
        transport=httpx.MockTransport(handler),
        sleep=lambda _s: None,
    )
    with pytest.raises(LLMError) as exc:
        provider.complete([LLMMessage("user", "x")], system="S")
    assert "sk-ant-streng-geheim-9876" not in str(exc.value)
