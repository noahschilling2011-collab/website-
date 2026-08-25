"""Tests der Modellanbindung.

Der Anthropic-Anbieter wird gegen einen `httpx.MockTransport` geprueft. Das
ist der einzige Weg, die tatsaechlich gesendete Anfrage zu sehen, ohne einen
Aufruf zu bezahlen.
"""

from __future__ import annotations

import json

import httpx
import pytest

from core.config import Settings
from core.llm import (
    ANTHROPIC_VERSION,
    AnthropicProvider,
    FakeLLMProvider,
    LLMError,
    LLMMessage,
    LLMProvider,
    build_provider,
)
from tests.conftest import run


async def _kein_schlaf(_seconds: float) -> None:
    return None


# --- Fake -----------------------------------------------------------------


def test_llmprovider_ist_abstrakt():
    with pytest.raises(TypeError):
        LLMProvider()  # type: ignore[abstract]


def test_fake_ist_deterministisch():
    a = run(FakeLLMProvider().complete([LLMMessage("user", "Hallo")], system="S"))
    b = run(FakeLLMProvider().complete([LLMMessage("user", "Hallo")], system="S"))
    assert a.text == b.text


def test_fake_enthaelt_die_letzte_nutzernachricht():
    reply = run(FakeLLMProvider().complete(
        [LLMMessage("user", "erste"), LLMMessage("assistant", "ok"),
         LLMMessage("user", "zweite")],
        system="S",
    ))
    assert "zweite" in reply.text and "erste" not in reply.text


def test_fake_spielt_geskriptete_antworten_ab():
    p = FakeLLMProvider(replies=["eins", "zwei"])
    assert run(p.complete([LLMMessage("user", "x")], system="S")).text == "eins"
    assert run(p.complete([LLMMessage("user", "x")], system="S")).text == "zwei"
    # Danach wird der letzte Eintrag wiederholt statt zu krachen.
    assert run(p.complete([LLMMessage("user", "x")], system="S")).text == "zwei"


def test_fake_protokolliert_aufrufe():
    p = FakeLLMProvider()
    run(p.complete([LLMMessage("user", "x")], system="Systemprompt"))
    assert len(p.calls) == 1 and p.calls[0]["system"] == "Systemprompt"


# --- Aufbau ---------------------------------------------------------------


def test_ohne_llm_provider_kommt_der_fake():
    assert isinstance(build_provider(Settings(_env_file=None)), FakeLLMProvider)


def test_unbekannter_provider_wird_gemeldet_statt_geraten():
    s = Settings(_env_file=None, llm_provider="openai", llm_api_key="x", llm_model="y")
    with pytest.raises(LLMError) as exc:
        build_provider(s)
    assert exc.value.kind == "unknown_provider"


def test_ohne_key_klare_meldung():
    with pytest.raises(LLMError) as exc:
        AnthropicProvider("", model="claude-opus-5")
    assert exc.value.kind == "missing_api_key" and "LLM_API_KEY" in str(exc.value)


def test_ohne_modell_id_wird_nicht_geraten():
    with pytest.raises(LLMError) as exc:
        AnthropicProvider("sk-ant-test", model="")
    assert exc.value.kind == "missing_model"


# --- Anfrageform ----------------------------------------------------------


def _antwort(text: str = "Antwort", **extra):
    payload = {
        "id": "msg_01", "type": "message", "role": "assistant",
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
        sleep=_kein_schlaf,
        **kwargs,
    )


def test_anfrage_hat_die_dokumentierten_header_und_felder():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["url"] = str(request.url)
        gesehen["headers"] = dict(request.headers)
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "Hallo")], system="Sei knapp."))

    assert gesehen["url"] == "https://api.anthropic.com/v1/messages"
    assert gesehen["headers"]["x-api-key"] == "sk-ant-test-key"
    assert gesehen["headers"]["anthropic-version"] == ANTHROPIC_VERSION
    body = gesehen["body"]
    assert body["model"] == "claude-opus-5"
    assert body["system"] == "Sei knapp."
    assert body["messages"] == [{"role": "user", "content": "Hallo"}]


@pytest.mark.parametrize("verboten", ["temperature", "top_p", "top_k", "thinking"])
def test_keine_auf_opus5_verbotenen_felder(verboten: str):
    """temperature/top_p/top_k und thinking.budget_tokens sind dort ein 400."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen.update(json.loads(request.content))
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert verboten not in gesehen


def test_leerer_verlauf_wird_gar_nicht_erst_gesendet():
    def handler(request):  # pragma: no cover
        raise AssertionError("haette nicht senden duerfen")

    with pytest.raises(LLMError):
        run(_provider(handler).complete([], system="S"))


def test_verlauf_muss_mit_user_beginnen():
    def handler(request):  # pragma: no cover
        raise AssertionError("haette nicht senden duerfen")

    with pytest.raises(LLMError):
        run(_provider(handler).complete([LLMMessage("assistant", "hm")], system="S"))


# --- Antwortform ----------------------------------------------------------


def test_textbloecke_zusammengesetzt_denkbloecke_nicht():
    def handler(request):
        return httpx.Response(200, json=_antwort(content=[
            {"type": "thinking", "thinking": ""},
            {"type": "text", "text": "Teil eins. "},
            {"type": "text", "text": "Teil zwei."},
        ]))

    reply = run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert reply.text == "Teil eins. Teil zwei."


def test_usage_wird_auf_in_out_tokens_abgebildet():
    def handler(request):
        return httpx.Response(200, json=_antwort(
            usage={"input_tokens": 120, "output_tokens": 34}))

    usage = run(_provider(handler).complete([LLMMessage("user", "x")], system="S")).usage
    assert (usage.in_tokens, usage.out_tokens) == (120, 34)


def test_dauer_wird_gemessen():
    def handler(request):
        return httpx.Response(200, json=_antwort())

    reply = run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert reply.duration_ms >= 0


def test_ablehnung_wird_als_fehler_gemeldet():
    def handler(request):
        return httpx.Response(200, json=_antwort(
            content=[], stop_reason="refusal",
            stop_details={"type": "refusal", "category": "cyber"}))

    with pytest.raises(LLMError) as exc:
        run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert exc.value.kind == "refusal" and "cyber" in str(exc.value)


def test_antwort_ohne_text_ist_ein_fehler():
    def handler(request):
        return httpx.Response(200, json=_antwort(content=[]))

    with pytest.raises(LLMError) as exc:
        run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert exc.value.kind == "empty_response"


# --- Fehler und Wiederholung ----------------------------------------------


@pytest.mark.parametrize("status,teil", [
    (400, "abgelehnt"), (401, "LLM_API_KEY"), (403, "darf dieses Modell nicht"),
    (404, "unbekannt"), (413, "zu gross"),
])
def test_nicht_wiederholbare_fehler_werden_uebersetzt(status: int, teil: str):
    versuche = {"n": 0}

    def handler(request):
        versuche["n"] += 1
        return httpx.Response(status, json={"error": {"message": "Details vom Anbieter"}})

    with pytest.raises(LLMError) as exc:
        run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))

    assert teil in str(exc.value) and "Details vom Anbieter" in str(exc.value)
    assert versuche["n"] == 1, "darf nicht wiederholt werden"


def test_429_wird_wiederholt_und_gelingt_dann():
    versuche = {"n": 0}

    def handler(request):
        versuche["n"] += 1
        if versuche["n"] == 1:
            return httpx.Response(429, headers={"retry-after": "0"},
                                  json={"error": {"message": "slow down"}})
        return httpx.Response(200, json=_antwort("endlich"))

    reply = run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert reply.text == "endlich" and versuche["n"] == 2


def test_529_gibt_nach_der_letzten_wiederholung_auf():
    versuche = {"n": 0}

    def handler(request):
        versuche["n"] += 1
        return httpx.Response(529, json={"error": {"message": "overloaded"}})

    with pytest.raises(LLMError) as exc:
        run(_provider(handler, max_retries=2).complete(
            [LLMMessage("user", "x")], system="S"))
    assert exc.value.retryable is True
    assert versuche["n"] == 3, "ein Versuch plus zwei Wiederholungen"


def test_retry_after_wird_beachtet_und_nicht_umsonst_gewartet():
    gewartet: list[float] = []

    async def merken(seconds: float) -> None:
        gewartet.append(seconds)

    def handler(request):
        return httpx.Response(429, headers={"retry-after": "7"},
                              json={"error": {"message": "nope"}})

    provider = AnthropicProvider(
        "sk-ant-test", model="claude-opus-5", max_retries=1,
        transport=httpx.MockTransport(handler), sleep=merken,
    )
    with pytest.raises(LLMError):
        run(provider.complete([LLMMessage("user", "x")], system="S"))
    # Genau einmal - nach dem letzten Versuch wird nicht mehr geschlafen.
    assert gewartet == [7.0]


def test_zeitueberschreitung_wird_uebersetzt():
    def handler(request):
        raise httpx.ReadTimeout("zu langsam", request=request)

    with pytest.raises(LLMError) as exc:
        run(_provider(handler, max_retries=0).complete(
            [LLMMessage("user", "x")], system="S"))
    assert exc.value.kind == "timeout"


def test_api_key_taucht_in_keiner_fehlermeldung_auf():
    def handler(request):
        return httpx.Response(401, json={"error": {"message": "invalid x-api-key"}})

    provider = AnthropicProvider(
        "sk-ant-streng-geheim-9876", model="claude-opus-5",
        transport=httpx.MockTransport(handler), sleep=_kein_schlaf,
    )
    with pytest.raises(LLMError) as exc:
        run(provider.complete([LLMMessage("user", "x")], system="S"))
    assert "sk-ant-streng-geheim-9876" not in str(exc.value)


# --- Prompt-Hash (0.6) -----------------------------------------------------


def test_gleicher_prompt_gleicher_hash():
    from core.llm import prompt_hash
    a = prompt_hash("S", [LLMMessage("user", "x")])
    b = prompt_hash("S", [LLMMessage("user", "x")])
    assert a == b and len(a) == 16


def test_anderer_prompt_anderer_hash():
    from core.llm import prompt_hash
    assert prompt_hash("S", [LLMMessage("user", "x")]) != prompt_hash(
        "S", [LLMMessage("user", "y")]
    )
    assert prompt_hash("S", [LLMMessage("user", "x")]) != prompt_hash(
        "T", [LLMMessage("user", "x")]
    )


def test_der_prompt_selbst_steckt_nicht_im_hash():
    """Der Hash darf nichts vom Inhalt preisgeben - er landet in der Datenbank."""
    from core.llm import prompt_hash
    h = prompt_hash("System", [LLMMessage("user", "mein Passwort ist Hunter2")])
    assert "Hunter2" not in h and "Passwort" not in h


def test_fake_liefert_einen_hash():
    reply = run(FakeLLMProvider().complete([LLMMessage("user", "x")], system="S"))
    assert len(reply.prompt_hash) == 16


def test_anthropic_liefert_den_hash_mit():
    def handler(request):
        return httpx.Response(200, json=_antwort())

    reply = run(_provider(handler).complete([LLMMessage("user", "x")], system="S"))
    assert len(reply.prompt_hash) == 16
