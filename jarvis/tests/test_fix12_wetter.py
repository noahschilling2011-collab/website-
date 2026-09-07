"""FIX-12, Gruppe 1: Wetter und Orte, wenn der Dienst nicht mitspielt.

`wetter` ist das Werkzeug, das Noah taeglich benutzt, und `find_place` das,
das jedem Satellitenbild vorausgeht. Beide sprechen mit einem fremden
Dienst ohne Key - Open-Meteo bzw. Wikidata -, und beide muessen einen
Ausfall dieses Dienstes aushalten, ohne den Lauf mitzureissen.

Nachgestellt wird jeder Ausfall mit `httpx.MockTransport`, so wie in
tests/test_kalender.py und tests/test_fix09.py. Kein Test geht ins Netz;
die Sperre dafuer steht in tests/conftest.py.

Gemessen am 07.09.2026, VOR den Reparaturen dieser Runde - das ist der
Grund, warum es diese Datei gibt:

  wetter, Antwort ist eine JSON-Liste statt eines Objekts
      -> AttributeError: 'list' object has no attribute 'get', roh nach oben
  wetter, Antwort mit 50.000 Tagen
      -> `display` mit 5.900.074 Zeichen in 50.002 Zeilen, woertlich in den
         Prompt
  wetter, Ortsname der fremden Antwort mit 200.000 Zeichen
      -> ungekuerzt in `display`
  wetter, Antwort ohne `current` UND ohne `daily`
      -> ok=True mit "Berlin (DE, Berlin):" und sonst nichts
  find_place, Zeitueberschreitung und Verbindungsfehler
      -> httpx.ReadTimeout / httpx.ConnectError roh nach oben, durch das
         Werkzeug hindurch (es faengt nur OrtFehler) bis in POST /api/ort,
         und httpx haengt die volle URL an seinen Text
  find_place, Antwort ist eine JSON-Liste
      -> AttributeError, roh nach oben
  find_place, unlesbare Koordinate
      -> "Keine lesbare Koordinate: 'GEHEIMER-MUELL'" - fremder Text
         woertlich in `error`

Was schon vorher sauber war und hier nur festgehalten wird: HTTP 500, HTTP
429 (mit und ohne Retry-After), kaputtes JSON, leerer Koerper, leere
Ergebnisliste, unbekannter Wettercode - und dass der Cache einen Fehler
NICHT behaelt.
"""

from __future__ import annotations

import asyncio
import json
import re

import httpx
import pytest

import core.tools  # noqa: F401 - registriert alle Werkzeuge
from core import db
from core.contracts import Permission
from core.db import session
from core.orte import NAME_MAX, OrtFehler, finde_ort
from core.tools import registry
from core.tools.dispatch import run_tool
from core.tools.wetter import ORT_MAX, TAGE_MAX
from tests.conftest import run

# --- Was in keiner Meldung stehen darf ------------------------------------
#
# Nicht nur Geheimnisse: auch das Innenleben. Der Nutzer und das Modell
# lesen `display` und `error` - Hostnamen, Endpunkte, Modulnamen und
# Dateipfade gehoeren dort nicht hin (core/fehlertexte.py).
INNENLEBEN = [
    "open-meteo.com", "geocoding-api", "api.open-meteo",
    "query.wikidata.org", "sparql", "SELECT ?ort",
    "httpx", "core/", "core.orte", "core.tools", "/home/", "Traceback",
    "GEHEIM",
]


def _verraet(ergebnis) -> list[str]:
    """Beide Felder, nicht nur display - siehe tests/test_fehlertexte.py."""
    treffer = []
    for feld in ("display", "error"):
        text = str(getattr(ergebnis, feld, "") or "")
        treffer += [f"{feld}: {w}" for w in INNENLEBEN if w.lower() in text.lower()]
    return treffer


def _ist_ein_satz_fuer_noah(ergebnis) -> None:
    """Ein Satz auf Deutsch, den Noah versteht - und nichts darunter."""
    assert ergebnis.ok is False
    assert ergebnis.display and ergebnis.error, "ohne Text ist ein Fehler wertlos"
    assert _verraet(ergebnis) == [], f"verraet Innenleben: {_verraet(ergebnis)}"
    assert len(ergebnis.display) < 400, "eine Fehlermeldung ist kein Aufsatz"


# ==========================================================================
# wetter (Open-Meteo, ohne Key)
# ==========================================================================

GEO = {"results": [{"id": 2950159, "name": "Berlin", "latitude": 52.52437,
                    "longitude": 13.41053, "country": "Deutschland",
                    "country_code": "DE", "admin1": "Berlin",
                    "timezone": "Europe/Berlin"}]}
VORHERSAGE = {
    "timezone": "Europe/Berlin",
    "current": {"time": "2026-09-05T18:00", "temperature_2m": 18.4, "weather_code": 3},
    "daily": {
        "time": ["2026-09-05", "2026-09-06"],
        "temperature_2m_max": [22.1, 19.0], "temperature_2m_min": [13.6, 11.2],
        "precipitation_sum": [0.2, 4.5], "precipitation_probability_max": [20, 80],
        "weather_code": [3, 61], "wind_speed_10m_max": [25.3, 31.0],
        "sunrise": ["2026-09-05T06:31", "2026-09-06T06:33"],
        "sunset": ["2026-09-05T19:45", "2026-09-06T19:43"],
    },
}


def _antwort(payload, status: int = 200, headers: dict | None = None):
    def machen(_: httpx.Request) -> httpx.Response:
        return httpx.Response(status, json=payload, headers=headers or {})
    return machen


def _roh(text: str, status: int = 200, headers: dict | None = None):
    def machen(_: httpx.Request) -> httpx.Response:
        return httpx.Response(status, text=text, headers=headers or {})
    return machen


def _wetter_transport(geo=None, vorhersage=None, aufrufe: list | None = None):
    """Zwei Hosts, zwei Antworten. Was fehlt, ist die heile Vorgabe."""
    geo = geo or _antwort(GEO)
    vorhersage = vorhersage or _antwort(VORHERSAGE)

    def handler(request: httpx.Request) -> httpx.Response:
        if aufrufe is not None:
            aufrufe.append(request)
        assert "authorization" not in {k.lower() for k in request.headers}
        if request.url.host == "geocoding-api.open-meteo.com":
            return geo(request)
        if request.url.host == "api.open-meteo.com":
            return vorhersage(request)
        raise AssertionError(f"unerwarteter Host: {request.url.host}")
    return httpx.MockTransport(handler)


@pytest.fixture
def wetter():
    """Das registrierte Werkzeug, ohne Cache und ohne Standardort.

    Aufraeumen uebernimmt die Fixture `werkzeuge_zuruecksetzen` in
    tests/conftest.py - sie sichert alles, was auf der Instanz steht.
    """
    w = registry.get("wetter")
    w.db_path = ""
    w.standard_ort = ""
    return w


def _fuehre_aus(werkzeug, **argumente):
    return asyncio.run(werkzeug.execute(**argumente))


# --- Happy Path -----------------------------------------------------------


def test_happy_path_liefert_jetzt_und_die_angefragten_tage(wetter):
    aufrufe: list = []
    wetter.transport = _wetter_transport(aufrufe=aufrufe)
    e = _fuehre_aus(wetter, ort="Berlin", tage=2)
    assert e.ok, e.error
    assert e.display.startswith("Berlin (DE, Berlin): jetzt 18 °C, bedeckt.")
    assert "Heute (05.09.)" in e.display and "Morgen (06.09.)" in e.display
    assert e.sources == ["https://open-meteo.com/"]
    assert len(aufrufe) == 2, "erst geokodieren, dann vorhersagen"
    assert aufrufe[1].url.params["forecast_days"] == "2"


def test_der_klient_haengt_nicht_ewig(wetter):
    """Kein Haenger ohne Zeitgrenze: die Frist steht an der Anfrage selbst."""
    gesehen: dict = {}

    def geo(request: httpx.Request) -> httpx.Response:
        gesehen["timeout"] = request.extensions.get("timeout")
        return httpx.Response(200, json=GEO)

    wetter.transport = _wetter_transport(geo=geo)
    _fuehre_aus(wetter, ort="Berlin")
    assert gesehen["timeout"], "ohne Zeitgrenze wartet der Aufruf endlos"
    for art, sekunden in gesehen["timeout"].items():
        assert sekunden is not None, f"{art} ohne Grenze"
        assert sekunden <= 30, f"{art}={sekunden}s ist keine Grenze"


# --- Die sechs Faelle -----------------------------------------------------


@pytest.mark.parametrize("fehler", [
    httpx.ReadTimeout("timeout beim GET https://api.open-meteo.com/v1/forecast"),
    httpx.ConnectTimeout("connect timeout"),
    httpx.ConnectError("[Errno -2] Name or service not known"),
    httpx.ReadError("kaputte Leitung"),
])
def test_fall_1_und_2_zeitueberschreitung_und_verbindungsfehler(wetter, fehler):
    """Kein Wurf nach oben, ein Satz fuer Noah, kein Hostname darin."""
    def bricht(_: httpx.Request) -> httpx.Response:
        raise fehler

    wetter.transport = httpx.MockTransport(bricht)
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)
    assert "Wetterdienst nicht erreichbar" in e.display
    assert type(fehler).__name__ in e.display, "der Typ hilft beim Suchen"


@pytest.mark.parametrize("wo", ["geo", "vorhersage"])
@pytest.mark.parametrize("status", [500, 502, 503])
def test_fall_3_serverfehler_an_beiden_endpunkten(wetter, wo, status):
    kaputt = _roh("Internal Server Error", status=status)
    wetter.transport = _wetter_transport(**{wo: kaputt})
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)
    assert "Wetterdienst nicht erreichbar" in e.display
    assert str(status) not in e.display, "die Zahl sagt Noah nichts"


@pytest.mark.parametrize("kopf", [None, {"Retry-After": "120"}])
def test_fall_4_zu_viele_anfragen_mit_und_ohne_retry_after(wetter, kopf):
    """Open-Meteo drosselt die freie Nutzung. Beide Formen sind derselbe
    saubere Fehlschlag - das war schon vorher so und bleibt so."""
    wetter.transport = _wetter_transport(geo=_roh("slow down", status=429, headers=kopf))
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)
    assert "Wetterdienst nicht erreichbar" in e.display
    assert "Spaeter noch einmal versuchen" in e.display


@pytest.mark.parametrize("wo", ["geo", "vorhersage"])
@pytest.mark.parametrize("koerper", ["<html>Wartung</html>", "{unvollstaendig", "null"])
def test_fall_5_kaputtes_json(wetter, wo, koerper):
    wetter.transport = _wetter_transport(**{wo: _roh(koerper)})
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)


@pytest.mark.parametrize("wo,unfug", [
    ("geo", [1, 2, 3]),
    ("geo", "eine Zeichenkette"),
    ("vorhersage", [{"a": 1}]),
    ("vorhersage", "auch eine Zeichenkette"),
])
def test_fall_5_eine_liste_statt_eines_objekts_reisst_nichts_um(wetter, wo, unfug):
    """VORHER: AttributeError: 'list' object has no attribute 'get' - roh
    nach oben, weil AttributeError in keinem der beiden Auffangzweige steht.
    Ein fremder Dienst haelt sich nicht deshalb an seine Form, weil wir es
    annehmen."""
    wetter.transport = _wetter_transport(**{wo: _antwort(unfug)})
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)


def test_fall_5_treffer_ohne_koordinate(wetter):
    wetter.transport = _wetter_transport(geo=_antwort({"results": [{"name": "Berlin"}]}))
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)
    assert "unerwartet" in e.display


def test_fall_5_daily_ist_null_oder_zu_kurz(wetter):
    """Verschieden lange Listen in `daily` - eine Reihe fehlt ganz."""
    for feld, wert in (("temperature_2m_min", None), ("sunset", []),
                       ("weather_code", "kein Feld")):
        kaputt = json.loads(json.dumps(VORHERSAGE))
        kaputt["daily"][feld] = wert
        wetter.transport = _wetter_transport(vorhersage=_antwort(kaputt))
        e = _fuehre_aus(wetter, ort="Berlin")
        _ist_ein_satz_fuer_noah(e)
        assert "Wetterdaten unvollstaendig" in e.display, feld


def test_fall_5_unbekannter_wettercode_ist_kein_fehler(wetter):
    """Die WMO-Tabelle kann waxen. Ein unbekannter Code wird benannt, nicht
    verschwiegen - und er wirft nicht."""
    nur_jetzt = {"current": {"temperature_2m": 3.0, "weather_code": 999}}
    wetter.transport = _wetter_transport(vorhersage=_antwort(nur_jetzt))
    e = _fuehre_aus(wetter, ort="Berlin")
    assert e.ok and "Wettercode 999" in e.display


@pytest.mark.parametrize("wo", ["geo", "vorhersage"])
def test_fall_6_leerer_koerper(wetter, wo):
    wetter.transport = _wetter_transport(**{wo: _roh("")})
    e = _fuehre_aus(wetter, ort="Berlin")
    _ist_ein_satz_fuer_noah(e)


def test_fall_6_leere_ergebnisliste_heisst_ort_unbekannt(wetter):
    """Open-Meteo laesst `results` weg, wenn nichts gefunden wurde."""
    wetter.transport = _wetter_transport(geo=_antwort({"generationtime_ms": 0.1}))
    e = _fuehre_aus(wetter, ort="Nirgendwo-Xyz")
    assert e.ok is False
    assert "kennt der Wetterdienst nicht" in e.display
    assert _verraet(e) == []


def test_fall_6_eine_antwort_ohne_wetter_ist_kein_erfolg(wetter):
    """VORHER: ok=True mit 'Berlin (DE, Berlin):' und sonst nichts. Eine
    leere Antwort als Erfolg auszugeben ist schlimmer als ein Fehlschlag -
    das Modell haelt sie fuer einen Wetterbericht."""
    for leer in ({"timezone": "Europe/Berlin"}, {"current": {}, "daily": {}},
                 {"current": "kaputt", "daily": "auch kaputt"}):
        wetter.transport = _wetter_transport(vorhersage=_antwort(leer))
        e = _fuehre_aus(wetter, ort="Berlin")
        assert e.ok is False, leer
        assert "keine Wetterdaten" in e.display


def test_fall_6_eine_riesige_antwort_kommt_nicht_in_den_prompt(wetter):
    """VORHER gemessen: 50.000 Tage ergaben 5.900.074 Zeichen in 50.002
    Zeilen - und `display` ist genau der Text, der ins Modell geht.
    Angefragt waren zwei Tage."""
    n = 50_000
    riesig = {"current": {"temperature_2m": 1.0, "weather_code": 0},
              "daily": {"time": [f"2026-01-{(i % 28) + 1:02d}" for i in range(n)],
                        "temperature_2m_max": [1.0] * n, "temperature_2m_min": [0.0] * n,
                        "precipitation_sum": [0.0] * n,
                        "precipitation_probability_max": [0] * n,
                        "weather_code": [0] * n, "wind_speed_10m_max": [1.0] * n,
                        "sunrise": ["2026-01-01T06:00"] * n,
                        "sunset": ["2026-01-01T18:00"] * n}}
    wetter.transport = _wetter_transport(vorhersage=_antwort(riesig))
    e = _fuehre_aus(wetter, ort="Berlin", tage=2)
    assert e.ok, e.error
    tageszeilen = [z for z in e.display.splitlines()
                   if z.startswith(("Heute", "Morgen", "Uebermorgen"))]
    assert len(tageszeilen) == 2, f"{len(tageszeilen)} Tage statt der zwei bestellten"
    assert len(e.display) < 1000, f"display hat {len(e.display)} Zeichen"
    # Und auch nicht ueber `data` in die Datenbank.
    assert len(e.data["tage"]["time"]) == 2


def test_fall_6_ein_riesiger_ortsname_wird_gekuerzt(wetter):
    """Der Name kommt aus der fremden Antwort und steht in `display`.
    VORHER: 200.328 Zeichen, ungekuerzt."""
    gross = {"results": [dict(GEO["results"][0], name="B" * 200_000)]}
    wetter.transport = _wetter_transport(geo=_antwort(gross))
    e = _fuehre_aus(wetter, ort="Berlin")
    assert e.ok
    # Nicht zaehlen, sondern messen: "Berlin" in der Region liefert selbst
    # ein B. Gesucht ist die laengste Kette am Stueck.
    laengste = max(len(kette) for kette in re.findall("B+", e.display))
    assert laengste <= ORT_MAX, f"{laengste} Zeichen Ortsname im Bericht"
    assert len(e.data["ort"]) <= ORT_MAX


# --- Ungueltige Eingaben und fehlende Konfiguration ------------------------


def test_ohne_ort_und_ohne_jarvis_ort_wird_gefragt_nicht_geraten(wetter):
    e = _fuehre_aus(wetter)
    assert e.ok is False and "JARVIS_ORT" in e.display
    e = _fuehre_aus(wetter, ort="   ")
    assert e.ok is False and "JARVIS_ORT" in e.display


def test_der_standardort_springt_ein(wetter):
    aufrufe: list = []
    wetter.transport = _wetter_transport(aufrufe=aufrufe)
    wetter.standard_ort = "Hamburg"
    assert _fuehre_aus(wetter).ok
    assert aufrufe[0].url.params["name"] == "Hamburg"


def test_ein_unsinnig_langer_ortsname_geht_gar_nicht_erst_raus(wetter):
    """Sonst wandern 5.000 Zeichen aus dem Modell in die Abfrage - und in
    den Cache-Schluessel."""
    def darf_nicht(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("haette gar nicht gefragt werden duerfen")

    wetter.transport = httpx.MockTransport(darf_nicht)
    e = _fuehre_aus(wetter, ort="x" * (ORT_MAX + 1))
    assert e.ok is False and "unsinnig lang" in e.display
    assert _verraet(e) == []


def test_eine_zahl_statt_eines_ortsnamens_platzt_nicht(wetter):
    """VORHER: AttributeError: 'int' object has no attribute 'strip'. Der
    Dispatcher weist das zwar am Schema ab - aber das Werkzeug soll auch
    ohne ihn nicht platzen."""
    wetter.transport = _wetter_transport()
    e = _fuehre_aus(wetter, ort=123)
    assert e.ok in (True, False)  # Hauptsache: kein Wurf


def test_der_dispatcher_weist_falsche_argumente_ab(wetter):
    wetter.transport = _wetter_transport()
    e = run(run_tool("wetter", {"ort": 123}, max_permission=Permission.READ))
    assert e.ok is False and "Ungueltige Argumente" in e.error
    e = run(run_tool("wetter", {"ort": "Berlin", "unbekannt": 1},
                     max_permission=Permission.READ))
    assert e.ok is False and "unbekanntes Feld" in e.error


@pytest.mark.parametrize("tage,erwartet", [
    (None, "2"), ("zwei", "2"), (0, "1"), (-5, "1"), (9, str(TAGE_MAX)),
    (True, "1"),
])
def test_tage_werden_gebaendigt(wetter, tage, erwartet):
    aufrufe: list = []
    wetter.transport = _wetter_transport(aufrufe=aufrufe)
    assert _fuehre_aus(wetter, ort="Berlin", tage=tage).ok
    assert aufrufe[-1].url.params["forecast_days"] == erwartet


def test_ein_ort_mit_sonderzeichen_geht_unveraendert_raus(wetter):
    aufrufe: list = []
    wetter.transport = _wetter_transport(aufrufe=aufrufe)
    name = "Sankt Pölten/Ötztal 東京"
    assert _fuehre_aus(wetter, ort=name).ok
    assert aufrufe[0].url.params["name"] == name


# --- Der Cache ------------------------------------------------------------


def test_der_cache_behaelt_keinen_fehler(wetter, db_path):
    """Eine Stunde lang den falschen Satz auszuliefern waere schlimmer als
    gar keiner: Noah fragt nach dem Wetter, weil er gleich losfaehrt."""
    with session(db_path) as conn:
        db.init_db(conn)
    wetter.db_path = db_path

    wetter.transport = _wetter_transport(geo=_roh("kaputt", status=500))
    kaputt = _fuehre_aus(wetter, ort="Cachestadt")
    assert kaputt.ok is False

    wetter.transport = _wetter_transport()
    heil = _fuehre_aus(wetter, ort="Cachestadt")
    assert heil.ok, "der Fehlschlag wurde zwischengespeichert"
    assert heil.data["cache"] is False

    # Der ERFOLG dagegen bleibt liegen - und traegt sogar ueber einen
    # spaeteren Ausfall hinweg.
    wetter.transport = _wetter_transport(geo=_roh("kaputt", status=500))
    aus_dem_cache = _fuehre_aus(wetter, ort="cachestadt")
    assert aus_dem_cache.ok and aus_dem_cache.data["cache"] is True
    assert aus_dem_cache.display == heil.display


def test_der_cache_behaelt_auch_kein_ort_unbekannt(wetter, db_path):
    with session(db_path) as conn:
        db.init_db(conn)
    wetter.db_path = db_path
    wetter.transport = _wetter_transport(geo=_antwort({"generationtime_ms": 0.1}))
    assert _fuehre_aus(wetter, ort="Nixstadt").ok is False
    wetter.transport = _wetter_transport()
    assert _fuehre_aus(wetter, ort="Nixstadt").ok is True


def test_ohne_datenbank_geht_es_auch(wetter):
    """Fehlende Konfiguration: db_path ist leer, der Cache faellt weg -
    das Werkzeug arbeitet trotzdem."""
    wetter.db_path = ""
    wetter.transport = _wetter_transport()
    assert _fuehre_aus(wetter, ort="Berlin").ok


def test_kein_ausfall_reisst_den_lauf_um(wetter):
    """Die Sammelprobe: jeder Ausfall aus dieser Datei, ueber den
    Dispatcher, und keiner davon darf eine Ausnahme sein."""
    faelle = {
        "Zeitueberschreitung": httpx.MockTransport(
            lambda r: (_ for _ in ()).throw(httpx.ReadTimeout("x"))),
        "Verbindung": httpx.MockTransport(
            lambda r: (_ for _ in ()).throw(httpx.ConnectError("x"))),
        "500": _wetter_transport(geo=_roh("x", status=500)),
        "429": _wetter_transport(geo=_roh("x", status=429)),
        "kaputtes JSON": _wetter_transport(geo=_roh("<html>")),
        "Liste statt Objekt": _wetter_transport(geo=_antwort([1, 2])),
        "leer": _wetter_transport(geo=_roh("")),
        "keine Ergebnisse": _wetter_transport(geo=_antwort({})),
        "kein Wetter": _wetter_transport(vorhersage=_antwort({})),
    }
    for name, transport in faelle.items():
        wetter.transport = transport
        e = run(run_tool("wetter", {"ort": "Berlin"}, max_permission=Permission.READ))
        assert e.ok is False, name
        assert "ist mit einem Fehler ausgestiegen" not in (e.error or ""), (
            f"{name}: das Werkzeug ist geflogen statt zu antworten")
        assert _verraet(e) == [], f"{name}: {_verraet(e)}"


# ==========================================================================
# find_place / core.orte (Wikidata, ohne Key)
# ==========================================================================


def _sparql(*zeilen):
    return {"head": {"vars": ["ort", "ortLabel", "koord", "einwohner"]},
            "results": {"bindings": list(zeilen)}}


def _zeile(qid: str, label: str, lon: float, lat: float, ew: str | None = None):
    z = {"ort": {"type": "uri", "value": f"http://www.wikidata.org/entity/{qid}"},
         "ortLabel": {"type": "literal", "value": label},
         "koord": {"type": "literal", "value": f"Point({lon} {lat})"}}
    if ew is not None:
        z["einwohner"] = {"type": "literal", "value": ew}
    return z


KILI = _sparql(_zeile("Q7420", "Kilimandscharo", 37.3268, -3.3376))

# Ein Berg steht NICHT in der eingebauten Tabelle (nur Laender und
# Hauptstaedte) - er ist deshalb der einzige Weg, die Live-Abfrage zu
# treffen. "Berlin" wuerde aus der Tabelle beantwortet.
LIVE = "Kilimandscharo"


@pytest.fixture
def ortsuche():
    w = registry.get("find_place")
    w.kontakt = "noah@example.org"
    return w


def _ort_transport(handler):
    return httpx.MockTransport(handler)


# --- Happy Path -----------------------------------------------------------


def test_ort_happy_path_live_und_aus_der_tabelle(ortsuche):
    ortsuche.transport = _ort_transport(_antwort(KILI))
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok, e.error
    assert e.data["ort"]["name"] == "Kilimandscharo"
    assert len(e.data["bbox"]) == 4

    def darf_nicht(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("fuer ein Land darf nicht gefragt werden")

    ortsuche.transport = _ort_transport(darf_nicht)
    e = _fuehre_aus(ortsuche, name="Deutschland")
    assert e.ok and e.data["ort"]["quelle"] == "Tabelle"


# --- Die sechs Faelle -----------------------------------------------------


@pytest.mark.parametrize("fehler", [
    httpx.ReadTimeout("timeout beim GET https://query.wikidata.org/sparql?query=GEHEIM"),
    httpx.ConnectTimeout("connect timeout"),
    httpx.ConnectError("[Errno -2] Name or service not known"),
])
def test_ort_fall_1_und_2_kein_wurf_mehr_nach_oben(ortsuche, fehler):
    """VORHER flogen beide roh durch `find_place` hindurch - das Werkzeug
    faengt nur OrtFehler - und weiter bis in POST /api/ort. httpx haengt
    dabei die volle URL an seinen Text."""
    def bricht(_: httpx.Request) -> httpx.Response:
        raise fehler

    # Erst die Quelle: `finde_ort` macht daraus einen OrtFehler mit einem
    # Satz, der nichts verraet.
    with pytest.raises(OrtFehler) as gefangen:
        run(finde_ort(LIVE, kontakt="noah@example.org",
                      transport=_ort_transport(bricht)))
    assert "nicht erreichbar" in str(gefangen.value)
    assert "query.wikidata.org" not in str(gefangen.value)
    assert "GEHEIM" not in str(gefangen.value)

    # Und dann das Werkzeug.
    ortsuche.transport = _ort_transport(bricht)
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


@pytest.mark.parametrize("status", [500, 503])
def test_ort_fall_3_serverfehler(ortsuche, status):
    ortsuche.transport = _ort_transport(_roh("boom", status=status))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


@pytest.mark.parametrize("kopf", [None, {"Retry-After": "60"}])
def test_ort_fall_4_zu_viele_anfragen(ortsuche, kopf):
    ortsuche.transport = _ort_transport(_roh("slow down", status=429, headers=kopf))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


@pytest.mark.parametrize("payload", [
    [1, 2, 3],                                   # Liste statt Objekt
    "eine Zeichenkette",
    {"results": "kein Objekt"},
    {"results": {"bindings": None}},
    {"results": {"bindings": ["kein Objekt"]}},
    {"head": {}},
])
def test_ort_fall_5_unerwartete_form(ortsuche, payload):
    """VORHER: AttributeError bei einer Liste - roh nach oben."""
    ortsuche.transport = _ort_transport(_antwort(payload))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


def test_ort_fall_5_kaputtes_json(ortsuche):
    ortsuche.transport = _ort_transport(_roh("<html>Wartung</html>"))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


def test_ort_fall_5_unlesbare_koordinate_wird_nicht_zitiert(ortsuche):
    """VORHER stand der Rohwert woertlich in `error`:
    "Keine lesbare Koordinate: 'GEHEIMER-MUELL'". Das ist fremder Text, und
    fremder Text gehoert nicht in eine Fehlermeldung (core/fehlertexte.py)."""
    for koord in ("GEHEIM-MUELL-xyz", "", "Polygon(1 2)", 42, None):
        zeile = {"ort": {"value": "http://x/Q1"}, "ortLabel": {"value": "X"}}
        if koord is not None:
            zeile["koord"] = {"value": koord}
        ortsuche.transport = _ort_transport(_antwort(_sparql(zeile)))
        e = _fuehre_aus(ortsuche, name=LIVE)
        _ist_ein_satz_fuer_noah(e)
        assert "keine lesbare Koordinate" in e.display


def test_ort_fall_5_koordinate_ausserhalb_der_erde(ortsuche):
    ortsuche.transport = _ort_transport(_antwort(_sparql(_zeile("Q1", "X", 9.8, 200.0))))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


def test_ort_fall_5_einwohnerzahl_ist_text(ortsuche):
    """Eine unbrauchbare Zahl macht den Ort nicht unbrauchbar."""
    ortsuche.transport = _ort_transport(
        _antwort(_sparql(_zeile("Q1", "X", 9.8, 48.8, "viele"))))
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok and e.data["ort"]["einwohner"] is None


@pytest.mark.parametrize("koerper", ["", "   "])
def test_ort_fall_6_leerer_koerper(ortsuche, koerper):
    ortsuche.transport = _ort_transport(_roh(koerper))
    e = _fuehre_aus(ortsuche, name=LIVE)
    _ist_ein_satz_fuer_noah(e)


def test_ort_fall_6_nichts_gefunden_ist_ein_sauberer_fehler(ortsuche):
    ortsuche.transport = _ort_transport(_antwort(_sparql()))
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok is False
    assert "Kein Ort namens" in e.display and "Hauptstadt" in e.display
    assert _verraet(e) == []


def test_ort_fall_6_eine_riesige_antwort_bleibt_ein_kurzer_satz(ortsuche):
    """50.000 Treffer, rund 9,5 MB. Nur der erste zaehlt - und nur der
    darf im Prompt landen."""
    n = 50_000
    riesig = _sparql(*[_zeile(f"Q{i}", "X" * 40, 9.8, 48.8, str(n - i))
                       for i in range(n)])
    ortsuche.transport = _ort_transport(_antwort(riesig))
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok, e.error
    assert len(e.display) < 1000, f"display hat {len(e.display)} Zeichen"
    assert e.data["ort"]["weitere_treffer"] == n - 1


def test_ort_fall_6_ein_riesiger_name_wird_gekuerzt(ortsuche):
    ortsuche.transport = _ort_transport(
        _antwort(_sparql(_zeile("Q1", "N" * 200_000, 9.8, 48.8))))
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok
    assert len(e.data["ort"]["name"]) <= NAME_MAX
    assert len(e.display) < 1000


# --- Fehlende Konfiguration, ungueltige Eingaben, Mehrdeutigkeit ----------


def test_ort_ohne_wiki_kontakt_bleibt_die_tabelle(ortsuche):
    """Fehlende Konfiguration: ohne WIKI_KONTAKT wird nicht live gefragt -
    jedes Land und jede Hauptstadt geht trotzdem."""
    def darf_nicht(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("ohne Kontakt darf nicht gefragt werden")

    ortsuche.kontakt = ""
    ortsuche.transport = _ort_transport(darf_nicht)
    assert _fuehre_aus(ortsuche, name="Japan").ok is True
    e = _fuehre_aus(ortsuche, name=LIVE)
    assert e.ok is False
    assert "WIKI_KONTAKT" in e.display, "Noah soll wissen, was ihm fehlt"
    assert "Tabelle" in e.display, "und dass es nicht nur daran liegt"


@pytest.mark.parametrize("name", ["", "   ", "Berlin\nDROP", "a\tb", "x" * 500])
def test_ort_ungueltige_namen_werden_abgewiesen(ortsuche, name):
    def darf_nicht(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("das haette gar nicht gefragt werden duerfen")

    ortsuche.transport = _ort_transport(darf_nicht)
    e = _fuehre_aus(ortsuche, name=name)
    assert e.ok is False
    assert _verraet(e) == []


def test_ort_sonderzeichen_gehen_durch(ortsuche):
    """Nukuʻalofa mit ʻOkina, Anfuehrungszeichen, Backslash - der Name wird
    maskiert, nicht abgewiesen."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["query"] = request.url.params.get("query", "")
        return httpx.Response(200, json=KILI)

    ortsuche.transport = _ort_transport(handler)
    e = _fuehre_aus(ortsuche, name='Nukuʻalofa "x" \\ y')
    assert e.ok, e.error
    assert '\\"' in gesehen["query"], "Anfuehrungszeichen muss maskiert sein"
    assert gesehen["query"].count('"') % 2 == 0


def test_ort_mehrdeutigkeit_steht_im_bericht(ortsuche):
    """Gemessen (core/orte.py): "São Paulo" liefert nach Einwohnern sortiert
    den STAAT, nicht die Stadt. Das stand bisher nur in `data` - und `data`
    sieht das Modell nicht."""
    ortsuche.transport = _ort_transport(_antwort(_sparql(
        _zeile("Q175", "São Paulo (Staat)", -48.43, -22.07, "45595497"),
        _zeile("Q174", "São Paulo", -46.63, -23.55, "12325232"))))
    e = _fuehre_aus(ortsuche, name="São Paulo")
    assert e.ok
    assert e.data["ort"]["weitere_treffer"] == 1
    assert "weitere" in e.display and "genauer benennen" in e.display


def test_ort_eine_kante_von_null_kommt_gar_nicht_erst_an(ortsuche):
    """Das Schema haelt sie auf, bevor `bbox_um` sie zu Gesicht bekommt."""
    ortsuche.transport = _ort_transport(_antwort(KILI))
    e = run(run_tool("find_place", {"name": LIVE, "kante_km": 0},
                     max_permission=Permission.READ))
    assert e.ok is False and "Ungueltige Argumente" in e.error


def test_ort_kein_ausfall_reisst_den_lauf_um(ortsuche):
    """Dieselbe Sammelprobe wie beim Wetter, ueber den Dispatcher."""
    faelle = {
        "Zeitueberschreitung": _ort_transport(
            lambda r: (_ for _ in ()).throw(httpx.ReadTimeout("x"))),
        "Verbindung": _ort_transport(
            lambda r: (_ for _ in ()).throw(httpx.ConnectError("x"))),
        "500": _ort_transport(_roh("x", status=500)),
        "429": _ort_transport(_roh("x", status=429)),
        "kaputtes JSON": _ort_transport(_roh("<html>")),
        "Liste statt Objekt": _ort_transport(_antwort([1, 2])),
        "leer": _ort_transport(_roh("")),
        "nichts gefunden": _ort_transport(_antwort(_sparql())),
        "keine Koordinate": _ort_transport(_antwort(_sparql(
            {"ort": {"value": "http://x/Q1"}, "ortLabel": {"value": "X"}}))),
    }
    for name, transport in faelle.items():
        ortsuche.transport = transport
        e = run(run_tool("find_place", {"name": LIVE},
                         max_permission=Permission.READ))
        assert e.ok is False, name
        assert "ist mit einem Fehler ausgestiegen" not in (e.error or ""), (
            f"{name}: das Werkzeug ist geflogen statt zu antworten")
        assert _verraet(e) == [], f"{name}: {_verraet(e)}"


def test_beide_werkzeuge_tragen_keine_anmeldedaten_nach_draussen():
    """core/netz.py: der Klient fuer fremde Ziele verweigert jede Anfrage
    mit Anmeldedaten. Wikidata war bis heute die einzige Ausgangsstelle
    ohne diese Sperre."""
    import inspect

    import core.orte as orte
    import core.tools.wetter as wetter_modul

    for modul in (orte, wetter_modul):
        quelle = inspect.getsource(modul)
        assert "nach_draussen(" in quelle, modul.__name__
        assert "httpx.AsyncClient(" not in quelle, (
            f"{modul.__name__} baut wieder einen eigenen Klienten")


def test_die_route_ort_ueberlebt_einen_ausfall_von_wikidata(settings, monkeypatch):
    """Der Beweis, dass ein fehlender Dienst nicht das Ganze umreisst.

    `POST /api/ort` faengt nur `OrtFehler`. VORHER lief eine
    Zeitueberschreitung als httpx.ReadTimeout daran vorbei und wurde zum
    Serverfehler 500 - mit der vollen URL im Text, den httpx anhaengt.
    Jetzt ist es eine Antwort, die Noah lesen kann.
    """
    from fastapi.testclient import TestClient

    import api.ort
    from api.app import create_app
    from core.orte import finde_ort as echt

    settings.wiki_kontakt = "noah@example.org"

    def bricht(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout(
            "timeout beim GET https://query.wikidata.org/sparql?query=GEHEIM")

    async def mit_kaputter_leitung(name, **rest):
        rest["transport"] = httpx.MockTransport(bricht)
        return await echt(name, **rest)

    monkeypatch.setattr(api.ort, "finde_ort", mit_kaputter_leitung)

    with TestClient(create_app(settings)) as client:
        antwort = client.post("/api/ort", json={"name": LIVE},
                              headers={"X-Jarvis-Token": settings.jarvis_token})
    assert antwort.status_code == 400, f"HTTP {antwort.status_code}"
    text = antwort.json()["detail"]
    assert "nicht erreichbar" in text
    assert [w for w in INNENLEBEN if w.lower() in text.lower()] == [], text


@pytest.mark.parametrize("pfad", ["/gibt/es/nicht/x.db", "/proc/kaputt.db"])
def test_ein_kaputter_cache_kostet_nicht_den_wetterbericht(wetter, pfad, tmp_path):
    """Fehlende Konfiguration: JARVIS_DB zeigt ins Leere, oder die Tabelle
    `lookups` fehlt (eine nicht migrierte Datenbank).

    VORHER flog sqlite3.OperationalError roh nach oben - "no such table:
    lookups" - und der Bericht fiel aus, obwohl die Antwort aus dem Netz in
    Ordnung war. Beim SCHREIBEN des Caches war das laengst abgefangen, beim
    LESEN nicht.
    """
    wetter.db_path = pfad
    wetter.transport = _wetter_transport()
    e = _fuehre_aus(wetter, ort="Berlin")
    assert e.ok, e.error
    assert "jetzt 18 °C" in e.display

    # Und dieselbe Lage ueber den Dispatcher, damit auch dort nichts leckt.
    wetter.db_path = tmp_path / "nie-angelegt.db"
    ergebnis = run(run_tool("wetter", {"ort": "Berlin"},
                            max_permission=Permission.READ))
    assert ergebnis.ok, ergebnis.error
    assert _verraet(ergebnis) == []
    assert "lookups" not in (ergebnis.error or "")


# ==========================================================================
# Abnahme 07.09.2026: zwei Luecken, die die Bau-Runde offen gelassen hat
# ==========================================================================


@pytest.mark.parametrize("kante", [
    float("nan"),      # kommt durch das Schema: jeder Vergleich mit NaN ist False
    float("inf"),
    -3.0,
    0.0,
    "viel",            # ueber execute() direkt, ohne Dispatcher
    None,
])
def test_ort_eine_unbrauchbare_kante_ist_ein_satz_kein_wurf(ortsuche, kante):
    """Ungueltige Eingabe: `kante_km` ergibt keinen Ausschnitt.

    VORHER (gemessen am 07.09.2026 ueber execute()):
      kante_km=-3      -> WURF OrtFehler
      kante_km="viel"  -> WURF ValueError
      kante_km=None    -> WURF TypeError
      kante_km=NaN     -> ok=TRUE, "Ausschnitt nan km",
                          bbox=[-180.0000, -90.0000, 180.0000, 90.0000]
      kante_km=inf     -> dasselbe

    Der NaN-Fall ist der schlimme: er kommt AUCH durch den Dispatcher, weil
    `NaN < 0.5` und `NaN > 2000` beide False sind - und `json.loads` liest
    `NaN` klaglos. Das Modell haette die ganze Erde fuer einen 12-km-
    Ausschnitt gehalten und damit `satellite_search` gefuettert.
    """
    ortsuche.transport = _ort_transport(_antwort(KILI))
    e = _fuehre_aus(ortsuche, name=LIVE, kante_km=kante)
    assert e.ok is False, f"{kante!r} ergab ok=True: {e.display}"
    assert "Kantenlaenge" in e.display
    assert "nan" not in e.display.lower(), "kein NaN im Text"
    assert _verraet(e) == []


def test_ort_nan_kommt_auch_durch_den_dispatcher_nicht_durch(ortsuche):
    """Derselbe Fall ueber `run_tool` - da, wo das Modell wirklich anklopft."""
    ortsuche.transport = _ort_transport(_antwort(KILI))
    e = run(run_tool("find_place", {"name": LIVE, "kante_km": float("nan")},
                     max_permission=Permission.READ))
    assert e.ok is False, e.display
    assert "ist mit einem Fehler ausgestiegen" not in (e.error or "")
    assert "-180" not in (e.display or ""), "die ganze Erde als Ausschnitt"
    assert _verraet(e) == []


def test_ort_bbox_um_weist_nan_ab():
    """Die Sperre sitzt in `bbox_um` und nicht am Aufrufer - `POST /api/ort`
    ruft dieselbe Funktion."""
    from core.orte import bbox_um

    assert len(bbox_um(48.8, 9.8, kante_km=12.0)) == 4
    for kaputt in (float("nan"), float("inf"), float("-inf"), 0.0, -1.0):
        with pytest.raises(OrtFehler):
            bbox_um(48.8, 9.8, kante_km=kaputt)


def test_ort_ein_riesiger_gefragter_name_kommt_nicht_zurueck_in_den_prompt(ortsuche):
    """Sehr grosse EINGABE: der Name aus dem Modell steht in jeder Meldung.

    VORHER (gemessen ueber run_tool, Name mit 200.000 Zeichen):
      len(display) = 200.468 - woertlich zurueck in den Prompt.
    `wetter` deckelt an derselben Stelle laengst (ORT_MAX); hier fehlte es.
    """
    def darf_nicht(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("ein unsinnig langer Name geht nicht raus")

    ortsuche.transport = _ort_transport(darf_nicht)
    e = _fuehre_aus(ortsuche, name="N" * 200_000)
    assert e.ok is False
    assert len(e.display) < 1000, f"{len(e.display)} Zeichen gehen ins Modell"
    assert e.display.count("N") <= NAME_MAX
    assert _verraet(e) == []

    # Und der Zweig "nichts gefunden" - der zweite Ort, an dem der Name steht.
    ortsuche.transport = _ort_transport(_antwort(_sparql()))
    e = _fuehre_aus(ortsuche, name="N" * 150)
    assert e.ok is False and e.display.count("N") <= NAME_MAX
