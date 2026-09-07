"""Was passiert, wenn der Modellanbieter sich danebenbenimmt (FIX-12, Gruppe 5).

`tests/test_llm.py` und `tests/test_groq.py` pruefen den guten Fall und die
haeufigen Fehler. Hier steht daneben, was ein Anbieter sonst noch schickt,
wenn er kaputt, ueberlastet oder gar nicht da ist:

  Zeitueberschreitung, Verbindungsfehler, 5xx, 429 mit und ohne Retry-After,
  kaputtes JSON, eine Antwort in falscher Form (Liste statt Objekt, `null`
  statt Zahl, Zeichenkette statt Nachricht), eine leere Antwort und eine
  masslos grosse.

Zwei Dinge sind dabei wichtiger als der Fehlertext selbst:

1. **Nichts schlaegt durch.** Aus jedem dieser Faelle kommt ein `LLMError`
   mit einem deutschen Satz - kein `AttributeError`, kein `TypeError`, kein
   `AssertionError`. Ein durchschlagender Wurf reisst in `api/tasks.py` den
   ganzen Auftrag ab und landet als "Der Auftrag ist abgebrochen" im Chat.
2. **`retryable` stimmt.** `api/tasks.py` unterscheidet daran Stoerung
   (Anbieter war nicht erreichbar - der Zeitplan zaehlt das nicht als
   Fehlschlag) von Fehlschlag (die Anfrage war falsch). Steht das Flag
   falsch, schaltet sich ein Zeitplan nach drei Netzausfaellen selbst ab.

Kein Byte verlaesst das Geraet: alles laeuft ueber `httpx.MockTransport`.
"""

from __future__ import annotations

import json
import logging

import httpx
import pytest

from core.llm import (
    MAX_ANTWORT_BYTES,
    AnthropicProvider,
    FakeLLMProvider,
    GroqProvider,
    LLMError,
    LLMMessage,
)
from tests.conftest import run

# Ein Key, den man in jedem Text sofort wiedererkennt.
ANTHROPIC_KEY = "sk-ant-api03-streng-geheim-9876543210"
GROQ_KEY = "gsk_streng_geheim_9876543210"

BEIDE = ["anthropic", "groq"]


async def _kein_schlaf(_seconds: float) -> None:
    return None


def _baue(anbieter: str, handler, **kwargs):
    """Der Anbieter unter Test - mit Mock-Transport und ohne echtes Warten."""
    kwargs.setdefault("max_retries", 0)
    kwargs.setdefault("sleep", _kein_schlaf)
    if anbieter == "anthropic":
        return AnthropicProvider(
            ANTHROPIC_KEY, model="claude-opus-5",
            transport=httpx.MockTransport(handler), **kwargs,
        )
    return GroqProvider(
        GROQ_KEY, model="llama-3.3-70b-versatile",
        transport=httpx.MockTransport(handler), **kwargs,
    )


def _schluessel(anbieter: str) -> str:
    return ANTHROPIC_KEY if anbieter == "anthropic" else GROQ_KEY


def _gute_antwort(anbieter: str, text: str = "Antwort", **extra) -> dict:
    """Ein Rumpf in der Form, die der jeweilige Anbieter dokumentiert."""
    if anbieter == "anthropic":
        rumpf = {
            "id": "msg_01", "type": "message", "role": "assistant",
            "model": "claude-opus-5",
            "content": [{"type": "text", "text": text}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 11, "output_tokens": 7},
        }
    else:
        rumpf = {
            "id": "chatcmpl-1", "model": "llama-3.3-70b-versatile",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 11, "completion_tokens": 7},
        }
    rumpf.update(extra)
    return rumpf


def _frage(anbieter: str, handler, **kwargs):
    """Einen Zug fahren und den Anbieter danach wieder zumachen."""
    provider = _baue(anbieter, handler, **kwargs)
    try:
        return run(provider.complete([LLMMessage("user", "Hallo")], system="Sei knapp."))
    finally:
        run(provider.aclose())


def _fehler(anbieter: str, handler, **kwargs) -> LLMError:
    """Wie `_frage`, aber es MUSS ein LLMError herauskommen.

    Faellt hier etwas anderes heraus - AttributeError, TypeError,
    AssertionError -, dann ist genau das der Fehler, den dieser Test sucht:
    ein Wurf, der bis in den Aufrufer durchschlaegt.
    """
    with pytest.raises(LLMError) as gefangen:
        _frage(anbieter, handler, **kwargs)
    return gefangen.value


# --- Happy Path und ungueltige Eingaben -----------------------------------


@pytest.mark.parametrize("anbieter", BEIDE)
def test_happy_path_liefert_text_tokens_und_hash(anbieter: str):
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, "Alles gut.")))
    assert antwort.text == "Alles gut."
    assert (antwort.usage.in_tokens, antwort.usage.out_tokens) == (11, 7)
    assert len(antwort.prompt_hash) == 16
    assert antwort.content_blocks == ({"type": "text", "text": "Alles gut."},)


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("verlauf", [
    pytest.param([], id="leer"),
    pytest.param([LLMMessage("assistant", "hm")], id="beginnt-mit-assistant"),
])
def test_ungueltige_eingabe_wird_gar_nicht_erst_gesendet(anbieter: str, verlauf):
    def handler(_request):  # pragma: no cover - darf nie laufen
        raise AssertionError("haette nicht senden duerfen")

    provider = _baue(anbieter, handler)
    try:
        with pytest.raises(LLMError) as gefangen:
            run(provider.complete(verlauf, system="S"))
    finally:
        run(provider.aclose())
    assert gefangen.value.kind == "invalid_request"
    assert gefangen.value.retryable is False


# --- Fall 1 und 2: Zeitueberschreitung und Verbindungsfehler ---------------


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("wurf,erwartet", [
    pytest.param(httpx.ReadTimeout, "timeout", id="read-timeout"),
    pytest.param(httpx.TimeoutException, "timeout", id="timeout"),
    pytest.param(httpx.ConnectTimeout, "timeout", id="connect-timeout"),
    pytest.param(httpx.ConnectError, "connection", id="connect-error"),
    pytest.param(httpx.ReadError, "connection", id="read-error"),
])
def test_kein_netz_ist_eine_stoerung_und_kein_absturz(
    anbieter: str, wurf, erwartet: str
):
    """Kein Anbieter da: ein Satz, `retryable=True` - und kein Durchschlag.

    `retryable` ist hier keine Kosmetik: `api/tasks.py` macht daraus die
    Stoerung, die der Zeitplan nicht als Fehlschlag zaehlt.
    """
    def handler(request):
        raise wurf("kaputt", request=request)

    fehler = _fehler(anbieter, handler)
    assert fehler.kind == erwartet
    assert fehler.retryable is True
    assert fehler.status is None


@pytest.mark.parametrize("anbieter", BEIDE)
def test_zeitueberschreitung_wird_genau_so_oft_wiederholt_wie_erlaubt(anbieter: str):
    versuche = {"n": 0}

    def handler(request):
        versuche["n"] += 1
        raise httpx.ReadTimeout("zu langsam", request=request)

    fehler = _fehler(anbieter, handler, max_retries=2)
    assert fehler.kind == "timeout"
    assert versuche["n"] == 3, "ein Versuch plus zwei Wiederholungen"


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_fehler_traegt_hash_und_dauer_fuer_das_kostenprotokoll(anbieter: str):
    """Auch ein gescheiterter Aufruf gehoert nach `llm_calls`.

    `api/routes.py` schreibt ihn mit `ok=False` und braucht dafuer beides:
    `prompt_hash` (welcher Prompt war es) und `duration_ms` (wie lange hat er
    gewartet). Ohne sie waere die Kostentabelle blind fuer Fehlschlaege.
    """
    def handler(request):
        raise httpx.ConnectError("kein Netz", request=request)

    fehler = _fehler(anbieter, handler)
    assert len(fehler.prompt_hash) == 16
    assert fehler.duration_ms >= 0


# --- Fall 3 und 4: HTTP-Fehler und ihre Einstufung -------------------------


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("status,retryable", [
    (400, False), (401, False), (403, False), (404, False), (413, False),
    (429, True), (500, True), (502, True), (503, True), (529, True),
])
def test_einstufung_stoerung_gegen_fehlschlag(
    anbieter: str, status: int, retryable: bool
):
    """Die Tabelle, auf die sich `api/tasks.py` verlaesst.

    Wiederholbar sind nur die Faelle, bei denen ein zweiter Versuch wirklich
    etwas aendern kann. 401/403/404 gehen auch beim zehnten Mal nicht - sie
    sind ein Fehlschlag, den Noah lesen soll.
    """
    versuche = {"n": 0}

    def handler(_request):
        versuche["n"] += 1
        return httpx.Response(status, json={"error": {"message": "Details vom Anbieter"}})

    fehler = _fehler(anbieter, handler, max_retries=1)
    assert fehler.status == status
    assert fehler.retryable is retryable
    assert versuche["n"] == (2 if retryable else 1)
    assert str(fehler).strip() and "Traceback" not in str(fehler)


@pytest.mark.parametrize("anbieter", BEIDE)
def test_429_mit_retry_after_wartet_genau_so_lange(anbieter: str):
    gewartet: list[float] = []

    async def merken(sekunden: float) -> None:
        gewartet.append(sekunden)

    provider = _baue(
        anbieter,
        lambda _: httpx.Response(429, headers={"retry-after": "5"},
                                 json={"error": {"message": "langsamer"}}),
        max_retries=1, sleep=merken,
    )
    try:
        with pytest.raises(LLMError):
            run(provider.complete([LLMMessage("user", "x")], system="S"))
    finally:
        run(provider.aclose())
    assert gewartet == [5.0], "Retry-After des Anbieters, nicht die eigene Kurve"


@pytest.mark.parametrize("anbieter", BEIDE)
def test_429_ohne_retry_after_wartet_wachsend_aber_endlich(anbieter: str):
    gewartet: list[float] = []

    async def merken(sekunden: float) -> None:
        gewartet.append(sekunden)

    provider = _baue(
        anbieter,
        lambda _: httpx.Response(429, json={"error": {"message": "langsamer"}}),
        max_retries=2, sleep=merken,
    )
    try:
        with pytest.raises(LLMError):
            run(provider.complete([LLMMessage("user", "x")], system="S"))
    finally:
        run(provider.aclose())
    assert gewartet == [1.0, 2.0], "ohne Kopfzeile die eigene Kurve, zweimal"


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("kopfzeile,erwartet", [
    pytest.param("Wed, 21 Oct 2015 07:28:00 GMT", 1.0, id="http-datum"),
    pytest.param("keine-zahl", 1.0, id="unsinn"),
    pytest.param("-9", 0.0, id="negativ"),
    pytest.param("999999", 60.0, id="absurd-lang-wird-gedeckelt"),
])
def test_kaputtes_retry_after_haengt_nicht_und_stuerzt_nicht(
    anbieter: str, kopfzeile: str, erwartet: float
):
    """Retry-After darf laut RFC auch ein Datum sein - dann rechnet niemand.

    Wichtig ist nur: keine Ausnahme, und keine Wartezeit, die den Aufruf
    faktisch haengen laesst. Deshalb der Deckel bei 60 Sekunden.
    """
    gewartet: list[float] = []

    async def merken(sekunden: float) -> None:
        gewartet.append(sekunden)

    provider = _baue(
        anbieter,
        lambda _: httpx.Response(429, headers={"retry-after": kopfzeile},
                                 json={"error": {"message": "langsamer"}}),
        max_retries=1, sleep=merken,
    )
    try:
        with pytest.raises(LLMError):
            run(provider.complete([LLMMessage("user", "x")], system="S"))
    finally:
        run(provider.aclose())
    assert gewartet == [erwartet]


@pytest.mark.parametrize("anbieter", BEIDE)
def test_fehlerrumpf_in_fremder_form_wird_gemeldet_statt_zu_krachen(anbieter: str):
    """`{"error": "text"}` statt `{"error": {"message": ...}}`.

    Ein Gateway zwischen JARVIS und dem Anbieter haelt sich nicht an dessen
    Doku. Vorher rief der Code `.get` auf einer Zeichenkette - mitten in der
    Fehlerbehandlung, also genau dann, wenn nichts mehr auffangen kann.
    """
    fehler = _fehler(anbieter, lambda _: httpx.Response(500, json={"error": "nur Text"}))
    assert fehler.kind == "api_error"
    assert fehler.retryable is True
    assert "nur Text" in str(fehler)


@pytest.mark.parametrize("anbieter", BEIDE)
def test_negative_wiederholungszahl_ist_kein_absturz(anbieter: str):
    """`LLM_MAX_RETRIES=-1` in der .env.

    Vorher lief die Schleife kein einziges Mal und der `assert` am Ende flog
    als AssertionError durch JEDEN Modellaufruf - eine fehlerhafte
    Einstellung legte damit alles lahm, auch den guten Fall.
    """
    gut = _frage(anbieter, lambda _: httpx.Response(200, json=_gute_antwort(anbieter)),
                 max_retries=-1)
    assert gut.text == "Antwort"

    fehler = _fehler(anbieter, lambda _: httpx.Response(500, json={}), max_retries=-1)
    assert fehler.kind == "api_error" and fehler.retryable is True


# --- Fall 5: kaputte oder unerwartete Form ---------------------------------


@pytest.mark.parametrize("anbieter", BEIDE)
def test_kaputtes_json_wird_gemeldet_ohne_innenleben(anbieter: str):
    """Der Satz geht in den Chat und im naechsten Zug zurueck zum Anbieter.

    Deshalb steht die Meldung von `json` (Zeile, Spalte, ein Stueck des
    Rumpfs) im Serverlog und nicht im Text.
    """
    fehler = _fehler(anbieter, lambda _: httpx.Response(200, text="{das ist kein JSON"))
    assert fehler.kind == "bad_response"
    assert fehler.retryable is False
    text = str(fehler)
    for verraeter in ("Expecting", "column", "char", "line", "das ist kein JSON"):
        assert verraeter not in text, text


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("rumpf", [
    pytest.param([1, 2, 3], id="liste-statt-objekt"),
    pytest.param("nur ein Text", id="zeichenkette-statt-objekt"),
    pytest.param(42, id="zahl-statt-objekt"),
])
def test_antwort_die_kein_objekt_ist_wird_gemeldet(anbieter: str, rumpf):
    """Vorher: `AttributeError: 'list' object has no attribute 'get'`."""
    fehler = _fehler(anbieter, lambda _: httpx.Response(200, json=rumpf))
    assert fehler.kind == "bad_response"


@pytest.mark.parametrize("anbieter", BEIDE)
@pytest.mark.parametrize("kaputt", [
    pytest.param(None, id="null"),
    pytest.param("viel", id="zeichenkette"),
    pytest.param({"a": 1}, id="objekt"),
])
def test_unbrauchbare_tokenzahl_kostet_die_antwort_nicht(anbieter: str, kaputt):
    """`usage: {"input_tokens": null}` - vorher ein TypeError mitten im Zug.

    Der Text war schon da und ging trotzdem verloren. Eine kaputte Zaehlung
    zaehlt jetzt wie eine fehlende: 0, und die Antwort bleibt.
    """
    feld = "input_tokens" if anbieter == "anthropic" else "prompt_tokens"
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, "trotzdem da", usage={feld: kaputt})))
    assert antwort.text == "trotzdem da"
    assert antwort.usage.in_tokens == 0


@pytest.mark.parametrize("anbieter", BEIDE)
def test_usage_das_gar_kein_objekt_ist(anbieter: str):
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, "trotzdem da", usage="viel")))
    assert antwort.text == "trotzdem da"
    assert (antwort.usage.in_tokens, antwort.usage.out_tokens) == (0, 0)


@pytest.mark.parametrize("anbieter", BEIDE)
def test_unbekanntes_feld_wird_ueberlesen(anbieter: str):
    """Ein neues Feld beim Anbieter darf JARVIS nicht anhalten."""
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, "geht weiter", brandneues_feld={"x": [1]})))
    assert antwort.text == "geht weiter"


@pytest.mark.parametrize("anbieter,abbruch", [
    ("anthropic", "max_tokens"),
    ("groq", "length"),
])
def test_abgeschnittene_antwort_kommt_durch_und_sagt_es(anbieter: str, abbruch: str):
    """Ein halber Satz ist mehr wert als gar keiner - aber der Grund muss mit.

    `stop_reason` wandert in `LLMReply` und von dort in die Werkzeugschleife;
    wer wissen will, ob das Modell mitten im Wort aufgehoert hat, sieht es
    dort.
    """
    if anbieter == "anthropic":
        rumpf = _gute_antwort(anbieter, "Der halbe Satz geht noch", stop_reason=abbruch)
    else:
        rumpf = _gute_antwort(anbieter, "Der halbe Satz geht noch")
        rumpf["choices"][0]["finish_reason"] = abbruch
    antwort = _frage(anbieter, lambda _: httpx.Response(200, json=rumpf))
    assert antwort.text == "Der halbe Satz geht noch"
    assert antwort.stop_reason == abbruch


def test_groq_choices_in_falscher_form():
    """`choices` als Objekt war vorher ein KeyError, als Text ein Zeichensalat."""
    for kaputt in ({"a": 1}, "text", 7):
        fehler = _fehler("groq", lambda _, k=kaputt: httpx.Response(
            200, json={"id": "x", "model": "m", "choices": k}))
        assert fehler.kind == "bad_response"


def test_groq_nachricht_in_falscher_form():
    fehler = _fehler("groq", lambda _: httpx.Response(200, json={
        "choices": [{"index": 0, "message": "nur Text", "finish_reason": "stop"}]}))
    assert fehler.kind == "empty_response"


def test_groq_werkzeugaufruf_in_falscher_form():
    """`tool_calls: ["x"]` - vorher ein AttributeError je Eintrag."""
    fehler = _fehler("groq", lambda _: httpx.Response(200, json={
        "choices": [{"index": 0, "finish_reason": "tool_calls",
                     "message": {"content": "", "tool_calls": ["nur Text"]}}]}))
    assert fehler.kind == "bad_response"


def test_anthropic_stop_details_in_falscher_form():
    """Eine Ablehnung ohne Kategorie bleibt eine Ablehnung."""
    fehler = _fehler("anthropic", lambda _: httpx.Response(200, json={
        "content": [], "stop_reason": "refusal", "stop_details": "nope"}))
    assert fehler.kind == "refusal"
    assert "abgelehnt" in str(fehler)


# --- Fall 6: leer und masslos gross ----------------------------------------


@pytest.mark.parametrize("anbieter", BEIDE)
def test_leerer_koerper_mit_200(anbieter: str):
    fehler = _fehler(anbieter, lambda _: httpx.Response(200, content=b""))
    assert fehler.kind == "bad_response"


@pytest.mark.parametrize("anbieter", BEIDE)
def test_leere_ergebnisliste(anbieter: str):
    """Anthropic: `content: []`. Groq: `choices: []`. Beides ist nichts."""
    leer = {"content": []} if anbieter == "anthropic" else {"choices": []}
    fehler = _fehler(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, **leer)))
    assert fehler.kind in ("empty_response", "bad_response")
    assert fehler.retryable is False


@pytest.mark.parametrize("anbieter", BEIDE)
def test_masslos_grosse_antwort_wird_verworfen(anbieter: str):
    """5 MB Text aus dem Anbieter.

    Ohne Deckel landete das in `LLMReply.text`, von dort in der Datenbank,
    im naechsten Prompt und damit wieder beim Anbieter - eine einzige kaputte
    Antwort haette so jeden weiteren Zug vergiftet und teuer gemacht.
    """
    riesig = json.dumps(_gute_antwort(anbieter, "x" * (5 * 1024 * 1024)))
    assert len(riesig) > MAX_ANTWORT_BYTES

    fehler = _fehler(anbieter, lambda _: httpx.Response(
        200, content=riesig.encode("utf-8"),
        headers={"content-type": "application/json"}))
    assert fehler.kind == "bad_response"
    assert fehler.retryable is False
    assert "gross" in str(fehler)
    assert "x" * 100 not in str(fehler), "der Rumpf selbst darf nicht in die Meldung"


def test_fuenfzigtausend_bloecke_werden_verworfen():
    """50.000 Textbloecke in einer Antwort - zusammen weit ueber dem Deckel."""
    viele = [{"type": "text", "text": "a" * 100} for _ in range(50_000)]
    rumpf = json.dumps(_gute_antwort("anthropic", content=viele))

    fehler = _fehler("anthropic", lambda _: httpx.Response(
        200, content=rumpf.encode("utf-8"),
        headers={"content-type": "application/json"}))
    assert fehler.kind == "bad_response"


def test_fuenfzigtausend_choices_werden_verworfen():
    viele = [
        {"index": i, "message": {"role": "assistant", "content": "a" * 100},
         "finish_reason": "stop"}
        for i in range(50_000)
    ]
    rumpf = json.dumps(_gute_antwort("groq", choices=viele))

    fehler = _fehler("groq", lambda _: httpx.Response(
        200, content=rumpf.encode("utf-8"),
        headers={"content-type": "application/json"}))
    assert fehler.kind == "bad_response"


@pytest.mark.parametrize("anbieter", BEIDE)
def test_eine_normal_grosse_antwort_geht_weiterhin_durch(anbieter: str):
    """Der Deckel darf keinen ehrlichen langen Text erschlagen.

    Ein Zug mit `max_tokens=4096` sind rund 16 KB; 200 KB sind also schon
    weit mehr, als je legitim ankommt - und muessen trotzdem durchgehen.
    """
    lang = "Satz. " * 34_000
    assert 200_000 < len(lang) < MAX_ANTWORT_BYTES
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter, lang)))
    assert antwort.text.startswith("Satz.")


# --- Der Key: nicht im Text, nicht im Log, nicht im Hash -------------------


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_key_faellt_aus_der_fehlermeldung_des_anbieters(anbieter: str):
    """OpenAI-kompatible Dienste schicken den Key im 401 woertlich zurueck.

    Der Text geht von dort in `tasks.result`, in die Datenbank, in den Chat
    und im naechsten Zug als Verlauf ZURUECK zum Anbieter. Ein Key, der so
    reist, ist verbrannt.
    """
    key = _schluessel(anbieter)
    fehler = _fehler(anbieter, lambda _: httpx.Response(401, json={
        "error": {"message": f"Incorrect API key provided: {key}. Check your keys."}}))
    assert key not in str(fehler)
    assert "***" in str(fehler)
    assert "401" in str(fehler)


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_key_faellt_auch_aus_einem_rumpf_ohne_json(anbieter: str):
    """Ein Proxy davor zitiert im 502er gern die ganze Anfrage, Kopfzeilen inklusive."""
    key = _schluessel(anbieter)
    fehler = _fehler(anbieter, lambda _: httpx.Response(
        502, text=f"<html>upstream error, sent authorization: Bearer {key}</html>"))
    assert key not in str(fehler)


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_key_steht_auch_nicht_im_serverlog(anbieter: str, caplog):
    """Das Log landet in Terminals, Dateien und Screenshots."""
    key = _schluessel(anbieter)
    with caplog.at_level(logging.DEBUG, logger="jarvis"):
        _fehler(anbieter, lambda _: httpx.Response(401, json={
            "error": {"message": f"bad key {key}"}}))
    assert key not in caplog.text


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_key_steht_nicht_im_prompt_hash(anbieter: str):
    """Der Hash geht in die Kostentabelle - er darf nichts tragen."""
    antwort = _frage(anbieter, lambda _: httpx.Response(
        200, json=_gute_antwort(anbieter)))
    assert _schluessel(anbieter) not in antwort.prompt_hash
    assert len(antwort.prompt_hash) == 16


@pytest.mark.parametrize("anbieter", BEIDE)
def test_der_key_steht_im_kopf_und_nur_dort(anbieter: str):
    """Gegenprobe: gesendet wird er sehr wohl - sonst waere der Test blind."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["kopf"] = dict(request.headers)
        gesehen["rumpf"] = request.content.decode("utf-8")
        return httpx.Response(200, json=_gute_antwort(anbieter))

    _frage(anbieter, handler)
    key = _schluessel(anbieter)
    if anbieter == "anthropic":
        assert gesehen["kopf"]["x-api-key"] == key
    else:
        assert gesehen["kopf"]["authorization"] == f"Bearer {key}"
    assert key not in gesehen["rumpf"], "der Key gehoert nicht in den Prompt"


# --- Der Fake bleibt der Fake ----------------------------------------------


def test_fake_antwortet_weiterhin_ohne_netz():
    """Ohne eingerichteten Anbieter laeuft JARVIS gegen den Fake weiter."""
    antwort = run(FakeLLMProvider().complete([LLMMessage("user", "Hallo")], system="S"))
    assert "Hallo" in antwort.text and antwort.stop_reason == "end_turn"


def test_fake_kann_einen_ausfall_nachstellen():
    """Additiv: ein geskripteter `LLMError` wird geworfen statt geantwortet.

    Damit kann jeder andere Test einen Anbieterausfall bis in `api/tasks.py`
    durchspielen, ohne HTTP nachzubauen. Der Aufruf steht trotzdem in
    `calls` - der Fake verschluckt ihn nicht.
    """
    ausfall = LLMError("Anbieter weg.", kind="connection", retryable=True)
    provider = FakeLLMProvider(replies=[ausfall])
    with pytest.raises(LLMError) as gefangen:
        run(provider.complete([LLMMessage("user", "x")], system="S"))
    assert gefangen.value.retryable is True
    assert len(provider.calls) == 1


def test_fake_spielt_erst_den_ausfall_und_dann_die_antwort():
    provider = FakeLLMProvider(replies=[LLMError("kurz weg."), "wieder da"])
    with pytest.raises(LLMError):
        run(provider.complete([LLMMessage("user", "x")], system="S"))
    assert run(provider.complete([LLMMessage("user", "x")], system="S")).text == "wieder da"


@pytest.mark.parametrize("anbieter", BEIDE)
def test_auch_ein_formfehler_traegt_den_hash_fuers_kostenprotokoll(anbieter: str):
    """Ein Zug, der bezahlt wurde, aber unbrauchbar zurueckkam.

    Der Aufruf hat den Anbieter erreicht und kostet Geld - er gehoert also
    mit `ok=False` nach `llm_calls`. Ohne `prompt_hash` weiss die Zeile
    dort nicht, zu welchem Prompt sie gehoert.
    """
    fehler = _fehler(anbieter, lambda _: httpx.Response(200, text="{kein JSON"))
    assert fehler.kind == "bad_response"
    assert len(fehler.prompt_hash) == 16
