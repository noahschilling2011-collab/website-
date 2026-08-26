"""Der Groq-Anbieter.

Groq spricht das OpenAI-Format, JARVIS spricht intern das von Anthropic.
Diese Tests halten die Uebersetzung in beide Richtungen fest - sie ist die
einzige Stelle, an der ein zweiter Anbieter wirklich Arbeit macht.

Die Form stammt aus Groqs Dokumentation (console.groq.com/docs/api-reference
und /docs/tool-use), nicht aus dem Gedaechtnis:

    POST https://api.groq.com/openai/v1/chat/completions
    Authorization: Bearer <key>
    {"model": ..., "messages": [...], "tools": [{"type": "function",
     "function": {"name", "description", "parameters"}}],
     "max_completion_tokens": N}

    -> {"choices": [{"message": {"role": "assistant", "content": ...,
        "tool_calls": [{"id", "type": "function",
        "function": {"name", "arguments": "<JSON-STRING>"}}]},
        "finish_reason": ...}],
        "usage": {"prompt_tokens", "completion_tokens"}}

Das Werkzeugergebnis geht als eigene Nachricht zurueck:

    {"role": "tool", "tool_call_id": ..., "name": ..., "content": ...}

Kein Byte verlaesst das Geraet: alles laeuft ueber httpx.MockTransport,
und tests/conftest.py sperrt die echte Transportschicht ohnehin.
"""

from __future__ import annotations

import json

import httpx
import pytest

from core.config import Settings
from core.llm import (
    GROQ_BASIS,
    GroqProvider,
    LLMError,
    LLMMessage,
    build_provider,
)
from tests.conftest import run


def _kein_schlaf(_: float):
    async def nichts():
        return None

    return nichts()


def _antwort(text: str | None = "Antwort", tool_calls=None, **extra):
    nachricht: dict = {"role": "assistant", "content": text}
    if tool_calls is not None:
        nachricht["tool_calls"] = tool_calls
    payload = {
        "id": "chatcmpl-1",
        "object": "chat.completion",
        "model": "openai/gpt-oss-120b",
        "choices": [
            {"index": 0, "message": nachricht,
             "finish_reason": "tool_calls" if tool_calls else "stop"}
        ],
        "usage": {"prompt_tokens": 11, "completion_tokens": 7, "total_tokens": 18},
    }
    payload.update(extra)
    return payload


def _provider(handler, **kwargs):
    return GroqProvider(
        "gsk-test-key",
        model=kwargs.pop("model", "openai/gpt-oss-120b"),
        transport=httpx.MockTransport(handler),
        sleep=_kein_schlaf,
        **kwargs,
    )


WETTER = {
    "name": "wetter",
    "description": "Sagt das Wetter.",
    "input_schema": {
        "type": "object",
        "properties": {"ort": {"type": "string"}},
        "required": ["ort"],
    },
}


# --- Anfrageform ----------------------------------------------------------


def test_die_anfrage_geht_an_den_dokumentierten_endpunkt():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["url"] = str(request.url)
        gesehen["method"] = request.method
        gesehen["headers"] = dict(request.headers)
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "Hallo")], system="Sei knapp."))

    assert gesehen["url"] == f"{GROQ_BASIS}/openai/v1/chat/completions"
    assert gesehen["method"] == "POST"
    # Bearer, nicht x-api-key. Das ist der Unterschied zu Anthropic.
    assert gesehen["headers"]["authorization"] == "Bearer gsk-test-key"
    assert gesehen["body"]["model"] == "openai/gpt-oss-120b"


def test_der_systemprompt_wird_zur_ersten_systemnachricht():
    """Anthropic hat ein eigenes `system`-Feld, Groq nicht - dort ist es
    eine Nachricht mit `role: system` ganz vorne."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "Hallo")], system="Sei knapp."))

    nachrichten = gesehen["body"]["messages"]
    assert nachrichten[0] == {"role": "system", "content": "Sei knapp."}
    assert nachrichten[1] == {"role": "user", "content": "Hallo"}
    assert "system" not in gesehen["body"]


def test_die_ausgabegrenze_heisst_max_completion_tokens():
    """`max_tokens` ist bei Groq veraltet. Wer es sendet, bekommt im besten
    Fall eine Warnung und im schlechtesten eine ignorierte Grenze."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler, max_tokens=1234).complete(
        [LLMMessage("user", "Hallo")], system="s"))

    assert gesehen["body"]["max_completion_tokens"] == 1234
    assert "max_tokens" not in gesehen["body"]


def test_es_werden_keine_sampling_parameter_gesendet():
    """Dieselbe Zurueckhaltung wie beim Anthropic-Anbieter: temperature,
    top_p und top_k sind Knoepfe, die niemand bewusst gedreht hat."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "Hallo")], system="s"))

    for knopf in ("temperature", "top_p", "top_k"):
        assert knopf not in gesehen["body"], f"{knopf} hat hier nichts zu suchen"


# --- Werkzeuge hin --------------------------------------------------------


def test_werkzeuge_werden_ins_function_format_uebersetzt():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete(
        [LLMMessage("user", "Wetter?")], system="s", tools=[WETTER]))

    assert gesehen["body"]["tools"] == [{
        "type": "function",
        "function": {
            "name": "wetter",
            "description": "Sagt das Wetter.",
            "parameters": WETTER["input_schema"],
        },
    }]


def test_ohne_werkzeuge_steht_kein_leeres_tools_feld_drin():
    """Ein leeres `tools: []` ist bei manchen Anbietern ein 400. Weglassen."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    run(_provider(handler).complete([LLMMessage("user", "Hallo")], system="s"))
    assert "tools" not in gesehen["body"]


# --- Werkzeuge zurueck ----------------------------------------------------


def test_ein_werkzeugaufruf_wird_zu_tooluse_mit_geparsten_argumenten():
    """`arguments` ist ein JSON-STRING. Wer ihn durchreicht, gibt dem
    Dispatcher einen String, wo er ein dict erwartet."""
    aufrufe = [{
        "id": "call_abc123",
        "type": "function",
        "function": {"name": "wetter", "arguments": '{"ort": "Berlin"}'},
    }]

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(text=None, tool_calls=aufrufe))

    reply = run(_provider(handler).complete(
        [LLMMessage("user", "Wetter?")], system="s", tools=[WETTER]))

    assert len(reply.tool_uses) == 1
    benutzung = reply.tool_uses[0]
    assert benutzung.id == "call_abc123"
    assert benutzung.name == "wetter"
    assert benutzung.input == {"ort": "Berlin"}     # dict, nicht String


def test_kaputte_argumente_werden_gemeldet_statt_still_verschluckt():
    aufrufe = [{
        "id": "call_1", "type": "function",
        "function": {"name": "wetter", "arguments": "{das ist kein JSON"},
    }]

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(text=None, tool_calls=aufrufe))

    with pytest.raises(LLMError) as fehler:
        run(_provider(handler).complete(
            [LLMMessage("user", "Wetter?")], system="s", tools=[WETTER]))
    assert fehler.value.kind == "bad_response"
    assert "wetter" in str(fehler.value)


def test_die_bloecke_kommen_in_anthropic_form_zurueck():
    """Der Werkzeug-Loop schickt `content_blocks` unveraendert zurueck und
    baut `tool_result`-Bloecke in Anthropic-Form. Damit `loop.py`,
    `agents.py` und `runner.py` einen zweiten Anbieter gar nicht bemerken,
    spricht auch dieser Anbieter nach innen Anthropic - uebersetzt wird
    ausschliesslich an der Leitung."""
    aufrufe = [{
        "id": "call_1", "type": "function",
        "function": {"name": "wetter", "arguments": '{"ort": "Berlin"}'},
    }]

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(text="Moment", tool_calls=aufrufe))

    reply = run(_provider(handler).complete(
        [LLMMessage("user", "Wetter?")], system="s", tools=[WETTER]))

    assert list(reply.content_blocks) == [
        {"type": "text", "text": "Moment"},
        {"type": "tool_use", "id": "call_1", "name": "wetter",
         "input": {"ort": "Berlin"}},
    ]


def test_ein_tool_result_block_wird_zur_tool_nachricht():
    """Die Rueckrichtung: was `loop.py` in Anthropic-Form baut, muss hier
    als eigene `role: tool`-Nachricht rausgehen."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    verlauf = [
        LLMMessage("user", "Wetter?"),
        LLMMessage("assistant", [
            {"type": "text", "text": "Moment"},
            {"type": "tool_use", "id": "call_1", "name": "wetter",
             "input": {"ort": "Berlin"}},
        ]),
        LLMMessage("user", [
            {"type": "tool_result", "tool_use_id": "call_1",
             "content": "18 Grad", "is_error": False},
        ]),
    ]
    run(_provider(handler).complete(verlauf, system="s", tools=[WETTER]))

    nachrichten = gesehen["body"]["messages"]
    # system, user, assistant(mit tool_calls), tool
    assert [n["role"] for n in nachrichten] == ["system", "user", "assistant", "tool"]

    assistent = nachrichten[2]
    assert assistent["content"] == "Moment"
    assert assistent["tool_calls"] == [{
        "id": "call_1", "type": "function",
        "function": {"name": "wetter", "arguments": '{"ort": "Berlin"}'},
    }]

    werkzeug = nachrichten[3]
    assert werkzeug == {
        "role": "tool", "tool_call_id": "call_1",
        "name": "wetter", "content": "18 Grad",
    }


def test_zwei_werkzeuge_in_einem_zug_werden_zu_zwei_tool_nachrichten():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    verlauf = [
        LLMMessage("user", "Zwei Staedte"),
        LLMMessage("assistant", [
            {"type": "tool_use", "id": "a", "name": "wetter", "input": {"ort": "B"}},
            {"type": "tool_use", "id": "b", "name": "wetter", "input": {"ort": "M"}},
        ]),
        LLMMessage("user", [
            {"type": "tool_result", "tool_use_id": "a", "content": "18"},
            {"type": "tool_result", "tool_use_id": "b", "content": "21"},
        ]),
    ]
    run(_provider(handler).complete(verlauf, system="s", tools=[WETTER]))

    rollen = [n["role"] for n in gesehen["body"]["messages"]]
    assert rollen == ["system", "user", "assistant", "tool", "tool"]
    assert len(gesehen["body"]["messages"][2]["tool_calls"]) == 2


def test_ein_fehlerhaftes_werkzeugergebnis_geht_als_text_mit_hinweis_raus():
    """OpenAI-Form kennt kein `is_error`. Die Information darf trotzdem
    nicht verschwinden, sonst haelt das Modell einen Fehlschlag fuer ein
    Ergebnis."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, json=_antwort())

    verlauf = [
        LLMMessage("user", "Wetter?"),
        LLMMessage("assistant", [
            {"type": "tool_use", "id": "call_1", "name": "wetter", "input": {}},
        ]),
        LLMMessage("user", [
            {"type": "tool_result", "tool_use_id": "call_1",
             "content": "Ort fehlt", "is_error": True},
        ]),
    ]
    run(_provider(handler).complete(verlauf, system="s", tools=[WETTER]))

    werkzeug = gesehen["body"]["messages"][-1]
    assert "Ort fehlt" in werkzeug["content"]
    assert "FEHLER" in werkzeug["content"]


# --- Antwort und Zaehlwerk ------------------------------------------------


def test_usage_wird_aus_den_openai_feldern_gelesen():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort())

    reply = run(_provider(handler).complete([LLMMessage("user", "Hi")], system="s"))
    assert reply.usage.in_tokens == 11      # prompt_tokens
    assert reply.usage.out_tokens == 7      # completion_tokens
    assert reply.model == "openai/gpt-oss-120b"
    assert reply.stop_reason == "stop"


def test_eine_antwort_ohne_text_und_ohne_werkzeug_ist_ein_fehler():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(text=""))

    with pytest.raises(LLMError) as fehler:
        run(_provider(handler).complete([LLMMessage("user", "Hi")], system="s"))
    assert fehler.value.kind == "empty_response"


def test_kein_choices_ist_ein_fehler_kein_absturz():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"id": "x", "choices": []})

    with pytest.raises(LLMError) as fehler:
        run(_provider(handler).complete([LLMMessage("user", "Hi")], system="s"))
    assert fehler.value.kind == "bad_response"


# --- Fehler und Wiederholung ----------------------------------------------


def test_ohne_key_wird_gar_nicht_erst_gebaut():
    with pytest.raises(LLMError) as fehler:
        GroqProvider("", model="openai/gpt-oss-120b")
    assert fehler.value.kind == "missing_api_key"


def test_ohne_modell_wird_gar_nicht_erst_gebaut():
    with pytest.raises(LLMError) as fehler:
        GroqProvider("gsk-test", model="")
    assert fehler.value.kind == "missing_model"


def test_401_wird_klar_gemeldet_und_verraet_den_key_nicht():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": {"message": "Invalid API Key"}})

    with pytest.raises(LLMError) as fehler:
        run(_provider(handler).complete([LLMMessage("user", "Hi")], system="s"))
    text = str(fehler.value)
    assert "401" in text
    assert "LLM_API_KEY" in text
    assert "gsk-test-key" not in text


def test_429_wird_wiederholt_und_beachtet_retry_after():
    versuche: list[float] = []
    zaehler = {"n": 0}

    def schlaf(sekunden: float):
        versuche.append(sekunden)

        async def nichts():
            return None

        return nichts()

    def handler(_: httpx.Request) -> httpx.Response:
        zaehler["n"] += 1
        if zaehler["n"] == 1:
            return httpx.Response(429, headers={"retry-after": "3"},
                                  json={"error": {"message": "Rate limit"}})
        return httpx.Response(200, json=_antwort())

    provider = GroqProvider(
        "gsk-test-key", model="openai/gpt-oss-120b",
        transport=httpx.MockTransport(handler), sleep=schlaf,
    )
    reply = run(provider.complete([LLMMessage("user", "Hi")], system="s"))

    assert reply.text == "Antwort"
    assert zaehler["n"] == 2
    assert versuche == [3.0]


def test_400_wird_nicht_wiederholt():
    zaehler = {"n": 0}

    def handler(_: httpx.Request) -> httpx.Response:
        zaehler["n"] += 1
        return httpx.Response(400, json={"error": {"message": "kaputt"}})

    with pytest.raises(LLMError):
        run(_provider(handler).complete([LLMMessage("user", "Hi")], system="s"))
    assert zaehler["n"] == 1, "ein 400 wird durch Wiederholen nicht besser"


# --- Verdrahtung ----------------------------------------------------------


def test_build_provider_baut_wirklich_groq():
    """Bis hierher stand in `build_provider` eine feste Zeile
    `return AnthropicProvider(...)` - der Blick in PROVIDERS war Zierde.
    Ein zweiter Eintrag waere still als Anthropic gelaufen."""
    provider = build_provider(Settings(
        _env_file=None,
        llm_provider="groq",
        llm_api_key="gsk-test",
        llm_model="openai/gpt-oss-120b",
    ))
    assert type(provider).__name__ == "GroqProvider"
    assert provider.name == "groq"


def test_anthropic_baut_weiterhin_anthropic():
    provider = build_provider(Settings(
        _env_file=None,
        llm_provider="anthropic",
        llm_api_key="sk-ant-test",
        llm_model="claude-opus-5",
    ))
    assert type(provider).__name__ == "AnthropicProvider"


def test_ein_unbekannter_anbieter_nennt_die_bekannten():
    with pytest.raises(LLMError) as fehler:
        build_provider(Settings(
            _env_file=None, llm_provider="openai",
            llm_api_key="k", llm_model="m",
        ))
    text = str(fehler.value)
    assert fehler.value.kind == "unknown_provider"
    assert "anthropic" in text and "groq" in text and "fake" in text


# --- Der ganze Weg: Werkzeugschleife gegen einen gefaelschten Groq --------


def test_die_werkzeugschleife_laeuft_komplett_durch():
    """Der Test, auf den es ankommt.

    Alles davor prueft eine Uebersetzungsrichtung einzeln. Hier laeuft der
    echte `run_tool_loop` mit dem echten Registry-Dispatcher gegen einen
    GroqProvider, dessen Transportschicht gefaelscht ist: erster Zug ein
    Werkzeugaufruf, zweiter Zug die Antwort. Damit ist belegt, dass die
    Uebersetzung in BEIDE Richtungen zusammenpasst - der zweite Zug enthaelt
    das Ergebnis des ersten, sonst haette das Modell es nie gesehen.

    Das ist der Punkt, an dem JARVIS bisher nie war: der FakeLLMProvider
    schlaegt nie einen Werkzeugaufruf vor, also kehrte `run_tool_loop` immer
    beim ersten Zug zurueck, ohne je ein Werkzeug anzufassen.
    """
    from core.contracts import Permission
    from core.tools.loop import run_tool_loop
    import core.tools.builtin  # noqa: F401  - registriert calculator

    zuege: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        koerper = json.loads(request.content)
        zuege.append(koerper)
        if len(zuege) == 1:
            return httpx.Response(200, json=_antwort(text=None, tool_calls=[{
                "id": "call_rechne",
                "type": "function",
                "function": {"name": "calculator",
                             "arguments": '{"expression": "21*2"}'},
            }]))
        return httpx.Response(200, json=_antwort(text="Das sind 42."))

    text, aufrufe, antworten = run(run_tool_loop(
        _provider(handler),
        [LLMMessage("user", "Was ist 21 mal 2?")],
        system="Sei knapp.",
        erlaubt=["calculator"],
        max_permission=Permission.READ,
    ))

    # 1. Das Werkzeug ist wirklich gelaufen.
    assert len(aufrufe) == 1
    assert aufrufe[0].name == "calculator"
    assert aufrufe[0].result.ok is True
    assert "42" in (aufrufe[0].result.display or "")

    # 2. Zwei Modellzuege, die Antwort kommt aus dem zweiten.
    assert len(antworten) == 2
    assert text == "Das sind 42."

    # 3. Der zweite Zug hat das Ergebnis wirklich mitbekommen.
    zweiter = zuege[1]["messages"]
    rollen = [n["role"] for n in zweiter]
    assert rollen == ["system", "user", "assistant", "tool"]
    assert zweiter[2]["tool_calls"][0]["id"] == "call_rechne"
    assert zweiter[3]["tool_call_id"] == "call_rechne"
    assert "42" in zweiter[3]["content"]

    # 4. Die Werkzeugliste ging im OpenAI-Format raus.
    assert zuege[0]["tools"][0]["type"] == "function"
    assert zuege[0]["tools"][0]["function"]["name"] == "calculator"
