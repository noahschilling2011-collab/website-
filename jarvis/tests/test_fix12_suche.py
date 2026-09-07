"""FIX-12, Gruppe 3: was `web_search` und `fetch_url` tun, wenn draussen etwas fehlt.

Der Auftrag lautet: ein fehlender Dienst darf JARVIS nicht umreissen. Fuer
diese beiden Werkzeuge heisst das sechs Faelle - Timeout, Verbindungsfehler,
HTTP 500, HTTP 429, unerwartete Antwort, leere und sehr grosse Antwort -,
dazu die Faelle, die nur `fetch_url` hat: keine oder falsche Angabe zum
Inhaltstyp, eine Weiterleitung ins eigene Netz, eine Kette ohne Ende.

Kein Netz, kein DNS, kein Modell: jeder Ausfall wird mit `httpx.MockTransport`
nachgestellt, die Namensaufloesung mit einer Tabelle (`falscher_resolver`).
Die Vorbilder sind `tests/test_kalender.py` und `tests/test_fix09.py`.

Gemessen am 07.09.2026, VOR den Reparaturen dieser Runde:

  * `web_search`, leerer Koerper / kaputtes JSON / JSON-Liste statt Objekt
    -> JSONDecodeError bzw. AttributeError flogen aus dem Werkzeug heraus;
       Noah las "web_search ist mit einem Fehler ausgestiegen".
  * `web_search`, 50.000 Treffer bei count=5 -> 7.766.673 Zeichen `display`
       und 50.000 Quellen, alles auf dem Weg in den Prompt.
  * `fetch_url`, Antwort ohne Content-Type -> roher HTML-Quelltext im Prompt.
  * `fetch_url`, Content-Type image/png -> 2.048 Zeichen Ersatzzeichen, und
       zwar als ok=True.
  * `fetch_url`, haengende Namensaufloesung -> der Werkzeug-Timeout von 1 s
       griff nicht (3,00 s), und die Ereignisschleife stand still.

Die Datei traegt ZWEI Durchgaenge, die am 07.09.2026 zeitgleich an derselben
Stelle gearbeitet haben. Der erste prueft die Werkzeuge von aussen, der
zweite (ab "Zweiter Durchgang") dieselben Reparaturen an den Bausteinen und
nagelt die Deckel als Zahlen fest. Zusammengelegt statt ausgesucht: doppelte
Deckung schadet nicht, ein geloeschter Test faellt niemandem mehr auf.
"""

from __future__ import annotations

import asyncio
import ipaddress
import socket
import time

import httpx
import pytest

from core.fehlertexte import ist_verdaechtig
from core.tools import registry, search
from core.tools.dispatch import run_tool
from core.tools.search import (
    MAX_ANTEIL_UNLESBAR,
    MAX_AUSZUG,
    MAX_TITEL,
    MAX_TREFFER_URL,
    FetchUrl,
    WebSearch,
    brave_suche,
    sieht_lesbar_aus,
)
from tests.conftest import run

KEY = "brave-key-geheim-4711"
FRAGE = "sentinel ausfall maerz 2026"


# --- Werkzeug bauen -------------------------------------------------------


class Netz:
    """Ein MockTransport, der mitschreibt, was wirklich abgeschickt wurde.

    Die Liste ist der eigentliche Beweis: bei einer abgewiesenen Station darf
    nicht nur das Ergebnis stimmen - die Anfrage darf gar nicht erst
    stattfinden.
    """

    def __init__(self, antwort) -> None:
        self.angekommen: list[str] = []
        self._antwort = antwort

    def transport(self) -> httpx.MockTransport:
        def behandeln(request: httpx.Request) -> httpx.Response:
            self.angekommen.append(str(request.url))
            if callable(self._antwort):
                return self._antwort(request)
            return self._antwort

        return httpx.MockTransport(behandeln)


def _suche(antwort, *, api_key: str = KEY, **felder):
    """`web_search` gegen eine geskriptete Antwort. Gibt (Ergebnis, Netz)."""
    netz = Netz(antwort)
    werkzeug = WebSearch()
    werkzeug.api_key = api_key
    werkzeug.transport = netz.transport()
    ergebnis = run(werkzeug.execute(**({"query": FRAGE} | felder)))
    return ergebnis, netz


def _holen(antwort, *, url: str = "https://beispiel.example/seite", **felder):
    """`fetch_url` gegen eine geskriptete Antwort. Gibt (Ergebnis, Netz)."""
    netz = Netz(antwort)
    werkzeug = FetchUrl()
    werkzeug.transport = netz.transport()
    ergebnis = run(werkzeug.execute(**({"url": url} | felder)))
    return ergebnis, netz


def _wirft(exc: Exception):
    def behandeln(request: httpx.Request) -> httpx.Response:
        raise exc

    return behandeln


def _treffer(anzahl: int, auszug: str = "Ein Auszug."):
    return {"web": {"results": [
        {"title": f"Treffer {i}", "url": f"https://beispiel.example/{i}",
         "description": auszug}
        for i in range(anzahl)
    ]}}


@pytest.fixture
def ohne_dns(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keine Namensaufloesung fuer die Faelle, in denen sie nicht der Punkt ist.

    Ohne die Ueberbrueckung waeren die Tests unten aus dem falschen Grund
    gruen - `beispiel.example` loest nirgends auf, und geprueft wuerde dann
    die Zielpruefung statt der Umgang mit der Antwort.
    """
    monkeypatch.setattr(search, "oeffentliches_ziel", lambda url: None)


@pytest.fixture
def falscher_resolver(monkeypatch: pytest.MonkeyPatch) -> None:
    """Eine Namenstabelle statt eines DNS-Servers.

    Damit laeuft die ECHTE Zielpruefung (`oeffentliches_ziel`, `_ist_intern`)
    ohne einen einzigen Netzzugriff: `aussen.example` zeigt nach draussen,
    `innen.example` auf 127.0.0.1, alles andere gibt es nicht. Nackte
    IP-Adressen reicht die Tabelle durch, wie getaddrinfo es auch tut.
    """
    tabelle = {
        "aussen.example": "93.184.216.34",
        "zweiter.example": "93.184.216.35",
        "innen.example": "127.0.0.1",
        "metadaten.example": "169.254.169.254",
    }

    def auskunft(host, port, *rest, **felder):
        try:
            adresse = str(ipaddress.ip_address(host))
        except ValueError:
            adresse = tabelle.get(host, "")
            if not adresse:
                raise socket.gaierror(-2, "Name or service not known")
        return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "",
                 (adresse, port or 80))]

    monkeypatch.setattr(socket, "getaddrinfo", auskunft)


# =========================================================================
# web_search
# =========================================================================


def test_happy_path_liefert_treffer_und_quellen():
    ergebnis, netz = _suche(httpx.Response(200, json=_treffer(2)))

    assert ergebnis.ok is True
    assert ergebnis.sources == ["https://beispiel.example/0",
                                "https://beispiel.example/1"]
    assert "Treffer 0" in ergebnis.display
    assert len(netz.angekommen) == 1
    assert "api.search.brave.com" in netz.angekommen[0]


def test_ohne_key_geht_keine_einzige_anfrage_raus():
    """Der Weg, den Noah heute wirklich hat: er besitzt keinen Brave-Key.

    Die bestehende Pruefung sieht nur die Meldung an. Hier zaehlt der
    Transport mit - ein Werkzeug, das ohne Key trotzdem anfragt, verraet die
    Suchanfrage an einen Dienst, der sie sowieso ablehnt.
    """
    ergebnis, netz = _suche(httpx.Response(200, json=_treffer(1)), api_key="")

    assert ergebnis.ok is False
    assert "SEARCH_API_KEY" in ergebnis.display
    assert netz.angekommen == []


def test_timeout_ist_ein_ergebnis_kein_absturz():
    ergebnis, _ = _suche(_wirft(httpx.ReadTimeout("zu langsam")))

    assert ergebnis.ok is False
    assert "Such-API" in ergebnis.display
    assert "zu langsam" not in (ergebnis.error or "")


def test_verbindungsfehler_ist_ein_ergebnis_kein_absturz():
    ergebnis, _ = _suche(_wirft(httpx.ConnectError("kein Weg dorthin")))

    assert ergebnis.ok is False
    assert ergebnis.display.strip().endswith(".")
    assert "kein Weg dorthin" not in (ergebnis.error or "")


def test_http_500_wird_als_serverfehler_benannt_nicht_als_leitungsproblem():
    """Vorher stand hier fuer beides "Die Such-API war nicht erreichbar."

    Ein Server, der 500 antwortet, IST erreichbar. Wer das verwechselt,
    sucht den Fehler bei sich."""
    ergebnis, _ = _suche(httpx.Response(500, text="Server Error"))

    assert ergebnis.ok is False
    assert "500" in ergebnis.display
    assert "nicht erreichbar" not in ergebnis.display


@pytest.mark.parametrize("koepfe", [{}, {"retry-after": "120"}])
def test_ratenlimit_mit_und_ohne_retry_after(koepfe):
    """429 ist der Fall, der Noah im Alltag trifft (Freikontingent).

    Mit oder ohne `Retry-After`: die Antwort muss dieselbe sein - ein
    verstaendlicher Satz, kein Wurf."""
    ergebnis, _ = _suche(httpx.Response(429, headers=koepfe, json={"e": "rate"}))

    assert ergebnis.ok is False
    assert "429" in ergebnis.display
    assert "Ratenlimit" in ergebnis.display


def test_abgelehnter_key_wird_nicht_mit_einem_ausfall_verwechselt():
    ergebnis, _ = _suche(httpx.Response(401, json={"error": "nope"}))

    assert ergebnis.ok is False
    assert "401" in (ergebnis.error or "")


@pytest.mark.parametrize("antwort", [
    pytest.param(httpx.Response(200, content=b"<html>kein json",
                                headers={"content-type": "application/json"}),
                 id="kaputtes-json"),
    pytest.param(httpx.Response(200, content=b""), id="leerer-koerper"),
    pytest.param(httpx.Response(200, json=[1, 2, 3]), id="liste-statt-objekt"),
    pytest.param(httpx.Response(200, content=b"null",
                                headers={"content-type": "application/json"}),
                 id="json-null"),
])
def test_eine_unlesbare_antwort_ist_ein_ergebnis_kein_wurf(antwort):
    """Der Fund dieser Runde: hier flog eine Ausnahme aus dem Werkzeug.

    Aufgefangen hat sie der Dispatcher - aber Noah las "web_search ist mit
    einem Fehler ausgestiegen", und das sagt ihm nichts ueber die Such-API.
    """
    ergebnis, _ = _suche(antwort)

    assert ergebnis.ok is False
    assert "Such-API" in ergebnis.display
    assert "ausgestiegen" not in ergebnis.display


@pytest.mark.parametrize("koerper", [
    pytest.param({"web": None}, id="web-ist-null"),
    pytest.param({"web": {"results": None}}, id="results-ist-null"),
    pytest.param({"web": {"results": "kaputt"}}, id="results-ist-ein-string"),
    pytest.param({"web": {"results": [{"title": "ohne Adresse"}]}}, id="ohne-url"),
    pytest.param({"web": {"results": []}}, id="leere-liste"),
    pytest.param({}, id="ganz-ohne-web"),
])
def test_eine_antwort_in_falscher_form_wird_zu_null_treffern(koerper):
    """Fehlende Felder, falscher Typ, null statt Liste: keine Treffer ist die
    ehrliche Antwort darauf - und ok bleibt True, weil die Suche gelaufen ist.
    """
    ergebnis, _ = _suche(httpx.Response(200, json=koerper))

    assert ergebnis.ok is True
    assert ergebnis.data["results"] == []
    assert "Keine Treffer" in ergebnis.display
    assert ergebnis.sources == []


def test_ein_treffer_mit_falschen_typen_wirft_nicht():
    """Zahl statt Titel, Objekt statt Auszug - das darf hoechstens haesslich
    aussehen, aber nichts umreissen."""
    ergebnis, _ = _suche(httpx.Response(200, json={"web": {"results": [
        {"title": 42, "url": "https://beispiel.example/x",
         "description": {"a": 1}},
    ]}}))

    assert ergebnis.ok is True
    assert ergebnis.sources == ["https://beispiel.example/x"]


def test_fuenfzigtausend_treffer_fluten_den_prompt_nicht():
    """Gemessen vorher: 7.766.673 Zeichen display und 50.000 Quellen.

    `count` ist eine Bestellung, keine Zusicherung: was die Gegenseite
    darueber hinaus schickt, geht nicht in den Prompt. Das ist kein Budget,
    das man anheben koennte - es ist der Deckel selbst.
    """
    ergebnis, _ = _suche(httpx.Response(200, json=_treffer(50_000)), count=5)

    assert ergebnis.ok is True
    assert len(ergebnis.data["results"]) == 5
    assert len(ergebnis.sources) == 5
    assert len(ergebnis.display) < 5_000, len(ergebnis.display)


def test_ein_einzelner_riesiger_auszug_fuellt_den_prompt_nicht():
    """Der Deckel auf die Trefferzahl allein genuegt nicht: EIN Treffer mit
    fuenf Megabyte Auszug reicht auch."""
    ergebnis, _ = _suche(httpx.Response(200, json=_treffer(1, auszug="A" * 5_000_000)))

    assert ergebnis.ok is True
    assert len(ergebnis.display) < 5_000, len(ergebnis.display)
    assert ergebnis.data["results"][0]["url"] == "https://beispiel.example/0"


def test_ein_treffer_mit_unbrauchbar_langer_adresse_faellt_raus():
    """Eine gekuerzte Adresse waere eine falsche Adresse - also fliegt der
    Treffer raus statt beschnitten zu werden. `fetch_url` wuerde ihn ohnehin
    ablehnen."""
    lang = "https://beispiel.example/?d=" + "x" * 3000
    ergebnis, _ = _suche(httpx.Response(200, json={"web": {"results": [
        {"title": "zu lang", "url": lang, "description": "x"},
        {"title": "geht", "url": "https://beispiel.example/gut",
         "description": "x"},
    ]}}))

    assert ergebnis.sources == ["https://beispiel.example/gut"]


@pytest.mark.parametrize("argumente,erwartet", [
    ({"query": "x", "count": 99}, "groesser"),
    ({"query": "x", "count": 0}, "kleiner"),
    ({"query": "x", "count": "fuenf"}, "integer"),
    ({"count": 5}, "query"),
    ({"query": 5}, "string"),
    ({"query": "x", "unbekannt": 1}, "unbekannt"),
])
def test_ungueltige_argumente_kommen_gar_nicht_erst_beim_werkzeug_an(argumente, erwartet):
    """Die Schemapruefung des Dispatchers - hier fuer web_search festgenagelt,
    damit ein spaeterer Umbau des Schemas nicht unbemerkt Argumente durchlaesst.
    """
    ergebnis = run(run_tool("web_search", argumente))

    assert ergebnis.ok is False
    assert erwartet in (ergebnis.error or ""), ergebnis.error


def test_eine_leere_suchanfrage_wird_trotzdem_sauber_beantwortet():
    ergebnis, _ = _suche(httpx.Response(200, json={"web": {"results": []}}),
                         query="")

    assert ergebnis.ok is True
    assert "Keine Treffer" in ergebnis.display


@pytest.mark.parametrize("antwort", [
    httpx.Response(500, text="Server Error"),
    httpx.Response(429, json={"e": "rate"}),
    httpx.Response(401, json={"e": "nope"}),
    httpx.Response(200, content=b"kein json"),
])
def test_kein_fehlerweg_traegt_den_key_oder_die_anfrage_nach_draussen(antwort):
    """httpx haengt die volle URL an seine Ausnahmen - und in der URL steht
    die Suchanfrage. Der Key steht im Kopf, aber ein Repr des Requests wuerde
    ihn mitnehmen. Deshalb hier beides zusammen geprueft."""
    ergebnis, _ = _suche(antwort, query="mein privates thema")

    verraten = ist_verdaechtig(
        (ergebnis.display or "") + (ergebnis.error or ""),
        [KEY, "mein privates thema", "api.search.brave.com"],
    )
    assert verraten == [], verraten


# =========================================================================
# fetch_url
# =========================================================================

SEITE = (b"<html><head><title>T</title><script>var a=1;</script></head>"
         b"<body><h1>Ueberschrift</h1><p>Ein Satz.</p></body></html>")


def test_fetch_happy_path_gibt_text_statt_html(ohne_dns):
    ergebnis, netz = _holen(httpx.Response(
        200, content=SEITE, headers={"content-type": "text/html; charset=utf-8"}))

    assert ergebnis.ok is True
    assert ergebnis.display == "Ueberschrift Ein Satz."
    assert "<h1>" not in ergebnis.display
    assert "var a=1" not in ergebnis.display, "Skript im Prompt"
    assert ergebnis.sources == ["https://beispiel.example/seite"]


@pytest.mark.parametrize("ausfall", [
    pytest.param(httpx.ReadTimeout("zu langsam"), id="lesetimeout"),
    pytest.param(httpx.ConnectTimeout("zu langsam"), id="verbindungstimeout"),
    pytest.param(httpx.ConnectError("kein Weg dorthin"), id="verbindungsfehler"),
    pytest.param(httpx.RemoteProtocolError("Server legte auf"), id="abbruch"),
])
def test_ein_ausfall_beim_abruf_ist_ein_ergebnis_kein_absturz(ausfall, ohne_dns):
    ergebnis, _ = _holen(_wirft(ausfall))

    assert ergebnis.ok is False
    assert "nicht erreichbar" in ergebnis.display
    # Der Ausnahmetext bleibt draussen, die genannte Adresse darf bleiben.
    assert "zu langsam" not in (ergebnis.error or "")
    assert "kein Weg dorthin" not in (ergebnis.error or "")


@pytest.mark.parametrize("status", [400, 404, 429, 500, 503])
def test_ein_fehlerstatus_wird_genannt_und_der_koerper_nicht_gelesen(status, ohne_dns):
    """Die Fehlerseite eines Servers ist Werbung oder eine Stacktrace - beides
    hat im Prompt nichts verloren."""
    ergebnis, _ = _holen(httpx.Response(
        status, content=b"<html><p>Interner Fehler in /srv/app/db.py</p></html>",
        headers={"content-type": "text/html"}))

    assert ergebnis.ok is False
    assert str(status) in ergebnis.display
    assert "db.py" not in ergebnis.display
    assert "db.py" not in (ergebnis.error or "")


def test_429_mit_retry_after_verhaelt_sich_wie_ohne(ohne_dns):
    mit, _ = _holen(httpx.Response(429, content=b"warte",
                                   headers={"content-type": "text/plain",
                                            "retry-after": "60"}))
    ohne, _ = _holen(httpx.Response(429, content=b"warte",
                                    headers={"content-type": "text/plain"}))

    assert mit.ok is ohne.ok is False
    assert mit.display == ohne.display


def test_eine_leere_antwort_ist_kein_erfolg(ohne_dns):
    ergebnis, _ = _holen(httpx.Response(200, content=b"",
                                        headers={"content-type": "text/html"}))

    assert ergebnis.ok is False
    assert "keinen Text" in ergebnis.display


def test_eine_seite_die_nur_aus_skript_besteht_ist_kein_erfolg(ohne_dns):
    """Die haeufigste Enttaeuschung im Alltag: eine Seite, die ihren Inhalt
    erst im Browser nachlaedt. Ohne Meldung haelt das Modell die leere
    Antwort fuer den Seiteninhalt."""
    ergebnis, _ = _holen(httpx.Response(
        200,
        content=b"<html><head><script>laden()</script></head>"
                b"<body><script>mehr()</script></body></html>",
        headers={"content-type": "text/html"}))

    assert ergebnis.ok is False
    assert "keinen Text" in ergebnis.display
    assert "laden()" not in ergebnis.display


def test_ohne_content_type_wird_html_trotzdem_als_html_gelesen(ohne_dns):
    """Vorher ging der rohe Quelltext in den Prompt - Tags, Skripte und alles.

    Ein Kopf, den ein Server vergisst, darf nicht dazu fuehren, dass das
    Modell HTML lesen muss.
    """
    ergebnis, _ = _holen(httpx.Response(200, content=SEITE, headers={}))

    assert ergebnis.ok is True
    assert ergebnis.display == "Ueberschrift Ein Satz."
    assert "<html>" not in ergebnis.display
    assert "var a=1" not in ergebnis.display


def test_ohne_content_type_bleibt_reiner_text_reiner_text(ohne_dns):
    """Gegenprobe: die Erkennung darf nicht jede Datei fuer HTML halten."""
    ergebnis, _ = _holen(httpx.Response(
        200, content=b"Zeile eins\nZeile zwei < drei\n", headers={}))

    assert ergebnis.ok is True
    assert "Zeile eins" in ergebnis.display
    assert "Zeile zwei < drei" in ergebnis.display


def test_ein_bild_statt_einer_seite_ist_ein_fehlschlag_kein_zeichenmuell(ohne_dns):
    """Gemessen vorher: 2.048 Zeichen Ersatzzeichen, als ok=True, direkt in
    den Prompt. Ein falsch verlinktes Bild kostete damit ein Vielfaches
    dessen, was die Seite gekostet haette - und sagte nichts."""
    ergebnis, _ = _holen(httpx.Response(
        200, content=bytes(range(256)) * 8,
        headers={"content-type": "image/png"}))

    assert ergebnis.ok is False
    assert "kein" in ergebnis.display.lower()
    assert "image/png" in ergebnis.display
    assert "�" not in ergebnis.display, "Zeichenmuell im Prompt"


def test_eine_binaerdatei_unter_falschem_content_type_faellt_auch_auf(ohne_dns):
    """Der Kopf sagt text/plain, der Inhalt ist ein Zip. Wer nur dem Kopf
    glaubt, schiebt den Muell trotzdem ins Modell."""
    ergebnis, _ = _holen(httpx.Response(
        200, content=b"PK\x03\x04" + bytes(range(200, 256)) * 40,
        headers={"content-type": "text/plain"}))

    assert ergebnis.ok is False
    assert "�" not in ergebnis.display


def test_eine_falsch_angesagte_kodierung_bleibt_lesbar(ohne_dns):
    """Die Gegenprobe zur Muell-Erkennung, und der haeufigere Fall: eine
    deutsche Seite in latin-1, die utf-8 behauptet. Ein paar Ersatzzeichen
    duerfen einen Text nicht wertlos machen."""
    ergebnis, _ = _holen(httpx.Response(
        200, content="<p>Gruesse aus München, es regnet</p>".encode("latin-1"),
        headers={"content-type": "text/html; charset=utf-8"}))

    assert ergebnis.ok is True
    assert "Gruesse aus M" in ergebnis.display
    assert "es regnet" in ergebnis.display


def test_eine_unbekannte_kodierung_im_kopf_wirft_nicht(ohne_dns):
    ergebnis, _ = _holen(httpx.Response(
        200, content=b"<p>Hallo</p>",
        headers={"content-type": "text/html; charset=erfunden-9"}))

    assert ergebnis.ok is True
    assert "Hallo" in ergebnis.display


def test_eine_sehr_grosse_seite_wird_begrenzt_gelesen(ohne_dns):
    """Fuenf Megabyte am Stueck. Weder der Speicher noch der Prompt duerfen
    das ganz zu sehen bekommen."""
    ergebnis, _ = _holen(
        httpx.Response(200, content=b"A" * 5_000_000,
                       headers={"content-type": "text/plain"}),
        max_chars=6000)

    assert ergebnis.ok is True
    assert ergebnis.data["truncated"] is True
    assert len(ergebnis.display) < 6100, len(ergebnis.display)


# --- Weiterleitungen ------------------------------------------------------


def _kette(ziel: str):
    """Station /um leitet auf `ziel`; alles andere ist das Endziel."""
    def behandeln(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/um":
            return httpx.Response(302, headers={"location": ziel})
        return httpx.Response(200, content=b"<p>Endziel erreicht.</p>",
                              headers={"content-type": "text/html"})

    return behandeln


@pytest.mark.parametrize("ziel,marke", [
    pytest.param("http://127.0.0.1:8080/admin", "127.0.0.1", id="loopback"),
    pytest.param("http://169.254.169.254/latest/meta-data/", "169.254.169.254",
                 id="metadaten-der-cloud"),
    pytest.param("http://innen.example/admin", "innen.example",
                 id="name-der-intern-aufloest"),
    pytest.param("http://metadaten.example/", "metadaten.example",
                 id="name-der-auf-die-metadaten-zeigt"),
])
def test_eine_weiterleitung_ins_eigene_netz_wird_gestoppt(ziel, marke, falscher_resolver):
    """Der Standardweg um eine Eingangspruefung herum: geprueft wird, was das
    Modell nennt - geholt, worauf der fremde Server zeigt.

    Geprueft wird nicht nur das Ergebnis, sondern dass die zweite Station gar
    nicht erst abgefragt wurde.
    """
    ergebnis, netz = _holen(_kette(ziel), url="http://aussen.example/um")

    assert ergebnis.ok is False
    assert "Station 2" in (ergebnis.error or ""), ergebnis.error
    assert marke in (ergebnis.error or "")
    assert netz.angekommen == ["http://aussen.example/um"], netz.angekommen
    assert "Endziel" not in (ergebnis.display or "")


def test_eine_weiterleitung_nach_draussen_wird_verfolgt(falscher_resolver):
    """Gegenprobe: die Sperre darf nicht jede Weiterleitung abwuergen -
    sonst ist die Haelfte des Netzes unerreichbar."""
    ergebnis, netz = _holen(_kette("http://zweiter.example/artikel"),
                            url="http://aussen.example/um")

    assert ergebnis.ok is True, ergebnis.error
    assert "Endziel erreicht." in ergebnis.display
    assert netz.angekommen == ["http://aussen.example/um",
                               "http://zweiter.example/artikel"]


def test_eine_endlose_weiterleitung_endet(falscher_resolver):
    ergebnis, netz = _holen(_kette("http://aussen.example/um"),
                            url="http://aussen.example/um")

    assert ergebnis.ok is False
    assert "eiterleitung" in (ergebnis.error or ""), ergebnis.error
    assert len(netz.angekommen) <= 6, netz.angekommen


def test_eine_weiterleitung_auf_ein_fremdes_schema_wird_gestoppt(falscher_resolver):
    """file:// als Weiterleitungsziel - der Weg zur Passwortdatei, wenn
    jemand nur die erste Adresse prueft."""
    ergebnis, netz = _holen(_kette("file:///etc/passwd"),
                            url="http://aussen.example/um")

    assert ergebnis.ok is False
    assert "Nur http(s)" in (ergebnis.error or ""), ergebnis.error
    assert netz.angekommen == ["http://aussen.example/um"]


def test_eine_weiterleitung_auf_einen_namen_den_es_nicht_gibt(falscher_resolver):
    ergebnis, netz = _holen(_kette("http://gibtsnicht.example/x"),
                            url="http://aussen.example/um")

    assert ergebnis.ok is False
    assert "Station 2" in (ergebnis.error or "")
    assert netz.angekommen == ["http://aussen.example/um"]


def test_ein_302_ohne_ziel_wird_nicht_zur_endlosschleife(falscher_resolver):
    ergebnis, netz = _holen(
        lambda request: httpx.Response(302, content=b"weg hier",
                                       headers={"content-type": "text/plain"}),
        url="http://aussen.example/um")

    assert len(netz.angekommen) == 1
    assert ergebnis.ok is True


# --- Ungueltige Eingaben --------------------------------------------------


@pytest.mark.parametrize("url,erwartet", [
    ("", "Nur http(s)"),
    ("nicht mal eine adresse", "Nur http(s)"),
    ("javascript:alert(1)", "Nur http(s)"),
    ("file:///etc/passwd", "Nur http(s)"),
    ("data:text/plain;base64,aGFsbG8=", "Nur http(s)"),
    ("https://", "Kein Hostname"),
    ("http://127.0.0.1/x", "eigene Netz"),
    ("http://169.254.169.254/", "eigene Netz"),
    ("http://[::1]/", "eigene Netz"),
    ("http://10.0.0.1/", "eigene Netz"),
])
def test_eine_unbrauchbare_adresse_wird_abgewiesen_bevor_jemand_anfragt(
        url, erwartet, falscher_resolver):
    ergebnis, netz = _holen(httpx.Response(200, content=b"<p>x</p>"), url=url)

    assert ergebnis.ok is False
    assert erwartet in (ergebnis.error or ""), ergebnis.error
    assert netz.angekommen == []


def test_eine_zu_lange_adresse_wird_abgewiesen_ohne_sie_zu_wiederholen():
    """Die Adresse IST hier das Problem - sie gehoert nicht in die Meldung,
    sonst steht die angehaengte Nutzlast doppelt im Prompt."""
    lang = "https://beispiel.example/?d=" + "x" * 3000
    ergebnis, netz = _holen(httpx.Response(200, content=b"x"), url=lang)

    assert ergebnis.ok is False
    assert "2048" in (ergebnis.error or "")
    assert "xxxxxxxxxx" not in (ergebnis.display or "")
    assert netz.angekommen == []


# --- Der Haenger ----------------------------------------------------------


def test_eine_haengende_namensaufloesung_haelt_weder_werkzeug_noch_server_an(
        monkeypatch: pytest.MonkeyPatch):
    """Der schwerste Fund dieser Runde, und genau der Auftragsfall: ein
    Dienst - hier DNS - antwortet nicht.

    `socket.getaddrinfo` blockiert. Lief sie im Faden der Ereignisschleife,
    dann griff der Deckel des Dispatchers nicht (gemessen: 3,00 s bei einem
    Timeout von 1 s) und der ganze Server stand so lange still: keine zweite
    Anfrage, kein Lebenszeichen, kein Abbruchknopf.

    Gemessen wird deshalb beides - dass der Abbruch kommt, und dass die
    Schleife waehrenddessen weiterlaeuft.
    """
    def haengt(*rest, **felder):
        time.sleep(1.0)
        raise socket.gaierror(-2, "Name or service not known")

    monkeypatch.setattr(socket, "getaddrinfo", haengt)
    werkzeug = registry.get("fetch_url")
    werkzeug.transport = httpx.MockTransport(
        lambda request: httpx.Response(200, content=b"<p>x</p>",
                                       headers={"content-type": "text/html"}))
    werkzeug.timeout_s = 0.3

    async def messen():
        ticks: list[float] = []

        async def nebenher():
            while True:
                await asyncio.sleep(0.02)
                ticks.append(time.monotonic())

        uhr = asyncio.create_task(nebenher())
        begonnen = time.monotonic()
        ergebnis = await run_tool("fetch_url", {"url": "https://langsam.example/x"})
        gebraucht = time.monotonic() - begonnen
        uhr.cancel()
        return ergebnis, gebraucht, len(ticks)

    ergebnis, gebraucht, ticks = run(messen())

    assert ergebnis.ok is False
    assert "Zeitueberschreitung" in (ergebnis.error or ""), ergebnis.error
    assert gebraucht < 0.9, f"der Timeout griff nicht: {gebraucht:.2f} s"
    assert ticks >= 5, (
        f"nur {ticks} Ticks in {gebraucht:.2f} s - die Ereignisschleife stand still")


# =========================================================================
# Zweiter Durchgang: dieselben Reparaturen, an den Bausteinen gemessen
# =========================================================================
#
# Der zweite Durchgang greift eine Ebene tiefer an - direkt an `brave_suche`
# und `sieht_lesbar_aus` statt am Werkzeug - und nagelt die Deckel als Zahlen
# fest. Seine Hilfsfunktion hiess ebenfalls `_suche`; sie heisst hier
# `_brave`, weil zwei Funktionen gleichen Namens in einer Datei die zweite
# stillschweigend verschlucken.

def _antwortet(antwort: httpx.Response) -> httpx.MockTransport:
    return httpx.MockTransport(lambda request: antwort)


def _brave(antwort: httpx.Response, **felder):
    return run(brave_suche("egal", api_key="k", transport=_antwortet(antwort),
                           **felder))


# --- 200 heisst noch nicht "brauchbar" -------------------------------------


@pytest.mark.parametrize("koerper", [
    b"",                       # leerer Koerper
    b"<html>Wartung</html>",   # eine Fehlerseite mit Status 200
    b"{kaputt",                # halbes JSON
])
def test_ein_unlesbarer_koerper_wird_ein_satz_und_kein_absturz(koerper):
    """Vorher flog hier ein JSONDecodeError nach oben. Der Dispatcher fing ihn
    auf, aber der Nutzer las "web_search ist mit einem Fehler ausgestiegen"
    statt zu erfahren, dass die Such-API Unsinn geschickt hat."""
    with pytest.raises(RuntimeError) as fehler:
        _brave(httpx.Response(200, content=koerper))
    assert "nicht lesbar" in str(fehler.value)


def test_eine_liste_statt_eines_objekts_ist_auch_unlesbar():
    """Gueltiges JSON, falsche Form - vorher ein AttributeError."""
    with pytest.raises(RuntimeError) as fehler:
        _brave(httpx.Response(200, json=[{"url": "https://a.example"}]))
    assert "nicht lesbar" in str(fehler.value)


@pytest.mark.parametrize("daten", [
    {},                                   # gar kein "web"
    {"web": None},                        # web ist null
    {"web": "kaputt"},                    # web ist keine Abbildung
    {"web": {}},                          # keine results
    {"web": {"results": None}},           # results ist null
    {"web": {"results": "kaputt"}},       # results ist keine Liste
    {"web": {"results": []}},             # ehrlich leer
])
def test_eine_antwort_ohne_treffer_ist_leer_und_kein_fehler(daten):
    """Kein Treffer ist ein Ergebnis, kein Ausfall - die Form muss nur
    stimmen. Vorher warf `{"web": "kaputt"}` einen AttributeError."""
    assert _brave(httpx.Response(200, json=daten)) == []


def test_unbrauchbare_treffer_fallen_raus_die_brauchbaren_bleiben():
    """Ein Treffer ohne URL ist als Beleg wertlos; er darf aber nicht die
    ganze Antwort mitnehmen."""
    treffer = _brave(httpx.Response(200, json={"web": {"results": [
        "kein Objekt",
        {"title": "ohne URL"},
        {"url": "", "title": "leere URL"},
        {"url": "https://gut.example", "title": "Gut", "description": "Text"},
    ]}}))
    assert treffer == [{"title": "Gut", "url": "https://gut.example",
                        "description": "Text"}]


# --- Deckel: ein Treffer darf den Prompt nicht auffressen -------------------


def test_die_gegenseite_bestimmt_nicht_wie_viele_treffer_kommen():
    """`count` ist eine Bestellung, keine Zusicherung. Schickt Brave 50
    Treffer auf eine Bestellung von 3, kommen 3 an."""
    viele = [{"url": f"https://t{i}.example", "title": f"T{i}"} for i in range(50)]
    assert len(_brave(httpx.Response(200, json={"web": {"results": viele}}),
                      count=3)) == 3


def test_titel_und_auszug_werden_gedeckelt_die_adresse_nicht():
    """Titel und Auszug schreibt der Seitenbetreiber und `display` geht
    unveraendert in den Prompt - ohne Deckel genuegt EIN Treffer."""
    treffer = _brave(httpx.Response(200, json={"web": {"results": [{
        "url": "https://lang.example",
        "title": "T" * (MAX_TITEL + 500),
        "description": "A" * (MAX_AUSZUG + 5000),
    }]}}))
    assert len(treffer[0]["title"]) == MAX_TITEL + 1        # + das Kuerzungszeichen
    assert treffer[0]["title"].endswith("…")
    assert len(treffer[0]["description"]) == MAX_AUSZUG + 1
    assert treffer[0]["url"] == "https://lang.example"      # ungekuerzt


def test_eine_ueberlange_adresse_faellt_raus_statt_gekuerzt_zu_werden():
    """Eine gekuerzte Adresse ist eine falsche Adresse. `fetch_url` wuerde sie
    ohnehin ablehnen (MAX_URL_LAENGE, dieselbe Zahl)."""
    lang = "https://lang.example/" + "x" * MAX_TREFFER_URL
    treffer = _brave(httpx.Response(200, json={"web": {"results": [
        {"url": lang, "title": "Zu lang"},
        {"url": "https://kurz.example", "title": "Kurz"},
    ]}}))
    assert [t["url"] for t in treffer] == ["https://kurz.example"]


def test_die_zahl_stimmt_mit_fetch_url_ueberein():
    """Wenn jemand eine der beiden Zahlen aendert, faellt es hier auf."""
    assert MAX_TREFFER_URL == registry.get("fetch_url").MAX_URL_LAENGE


# --- Kaputt ist nicht dasselbe wie unerreichbar ----------------------------


def test_ein_serverfehler_wird_nicht_als_anschlussproblem_gemeldet():
    """Vorher stand fuer beide Faelle "war nicht erreichbar" - das schickt
    den Nutzer auf die Suche nach seinem Anschluss, obwohl die Gegenseite
    kaputt ist."""
    werkzeug = registry.get("web_search")
    werkzeug.api_key, alt = "k", werkzeug.transport
    werkzeug.transport = _antwortet(httpx.Response(500, text="oops"))
    try:
        ergebnis = run(werkzeug.execute(query="egal"))
    finally:
        werkzeug.transport = alt
    assert ergebnis.ok is False
    assert "HTTP 500" in ergebnis.display
    assert "erreichbar" not in ergebnis.display
    # Und der Koerper der Fehlerseite steht nicht drin.
    assert "oops" not in ergebnis.display
    assert "oops" not in (ergebnis.error or "")


def test_ein_ratenlimit_bleibt_ein_ratenlimit():
    """429 hat seinen eigenen Satz und darf nicht im HTTP-Zweig landen."""
    werkzeug = registry.get("web_search")
    werkzeug.api_key, alt = "k", werkzeug.transport
    werkzeug.transport = _antwortet(httpx.Response(429))
    try:
        ergebnis = run(werkzeug.execute(query="egal"))
    finally:
        werkzeug.transport = alt
    assert ergebnis.ok is False
    assert "Ratenlimit" in ergebnis.display or "Ratenlimit" in (ergebnis.error or "")
    assert "HTTP 429" not in ergebnis.display


# --- Text oder Datei? ------------------------------------------------------


@pytest.mark.parametrize("text,lesbar", [
    ("", True),                                   # nichts ist nicht unlesbar
    ("Ein ganz normaler deutscher Satz.", True),
    ("Gr�sse aus M�nchen, sagte er.", True),   # falsche Kodierung, noch Text
    ("�" * 100, False),                      # eine Wand aus Ersatzzeichen
    ("\x00\x01\x02" * 50, False),                 # Steuerzeichen
    ("Text\tmit\nUmbruch\r\n", True),             # die drei erlaubten
])
def test_sieht_lesbar_aus_trennt_text_von_datei(text, lesbar):
    assert sieht_lesbar_aus(text) is lesbar


def test_die_grenze_liegt_wirklich_bei_dreissig_prozent():
    """Direkt an der Kante gemessen, damit eine stille Verschiebung auffaellt."""
    assert MAX_ANTEIL_UNLESBAR == 0.30
    assert sieht_lesbar_aus("�" * 30 + "a" * 70) is True     # genau 30 %
    assert sieht_lesbar_aus("�" * 31 + "a" * 69) is False    # 31 %


def _holt(koerper: bytes, typ: str | None, monkeypatch) -> object:
    """`fetch_url` gegen eine feste Antwort, ohne Netz und ohne DNS."""
    monkeypatch.setattr(search, "oeffentliches_ziel", lambda url: None)
    kopf = {} if typ is None else {"content-type": typ}
    werkzeug = registry.get("fetch_url")
    alt = werkzeug.transport
    werkzeug.transport = _antwortet(httpx.Response(200, content=koerper, headers=kopf))
    try:
        return run(werkzeug.execute(url="https://seite.example"))
    finally:
        werkzeug.transport = alt


def test_ohne_content_type_entscheidet_der_inhalt(monkeypatch):
    """Vorher ging eine Antwort ohne Kopf ungefiltert durch, und der Prompt
    bekam den rohen Quelltext samt Skript-Bloecken."""
    seite = (b"<html><head><script>var geheim = 1;</script></head>"
             b"<body><p>Der Seitentext.</p></body></html>")
    ergebnis = _holt(seite, None, monkeypatch)
    assert ergebnis.ok is True
    assert "Der Seitentext." in ergebnis.display
    assert "<script>" not in ergebnis.display
    assert "var geheim" not in ergebnis.display


def test_eine_textdatei_ohne_content_type_bleibt_text(monkeypatch):
    """Die Inhaltsprobe darf nicht jede Datei fuer HTML halten."""
    ergebnis = _holt(b"Spalte,Wert\na,1\nb,2\n", None, monkeypatch)
    assert ergebnis.ok is True
    assert "Spalte,Wert" in ergebnis.display


def test_eine_binaerdatei_ist_ein_fehlschlag_und_kein_ergebnis(monkeypatch):
    """Dekodiert wird daraus eine Wand aus Ersatzzeichen - vorher ging die als
    ok=True in den Prompt."""
    png = b"\x89PNG\r\n\x1a\n" + bytes(range(256)) * 8
    ergebnis = _holt(png, "image/png", monkeypatch)
    assert ergebnis.ok is False
    assert "lesbaren Text" in ergebnis.display
    assert "�" not in ergebnis.display          # der Muell selbst nicht
    assert ergebnis.sources == ["https://seite.example"]


def test_der_content_type_steht_im_satz_aber_kein_innenleben(monkeypatch):
    ergebnis = _holt(b"\xff\xfe\x00\x01" * 500, "application/zip", monkeypatch)
    assert ergebnis.ok is False
    assert "application/zip" in ergebnis.display
    for verraeter in ("/home/", "Traceback", ".py"):
        assert verraeter not in ergebnis.display


# --- Der DNS haelt die Ereignisschleife nicht mehr an ----------------------


def test_ein_langsamer_dns_laesst_die_schleife_weiterlaufen(monkeypatch):
    """`socket.getaddrinfo` ist eine BLOCKIERENDE Auskunft. Steht der
    DNS-Server nicht zur Verfuegung, wartete sie im Faden der
    Ereignisschleife: kein Timeout griff, keine zweite Anfrage kam durch,
    der ganze Server stand still.

    Gemessen wird nicht die Dauer (die haengt am Rechner), sondern ob eine
    NEBENHER laufende Aufgabe waehrenddessen ihre Runden dreht. Vorher: 0.
    """
    def langsam(url):
        time.sleep(0.4)
        return None

    monkeypatch.setattr(search, "oeffentliches_ziel", langsam)

    async def messen():
        ticks = 0

        async def nebenher():
            nonlocal ticks
            while True:
                await asyncio.sleep(0.01)
                ticks += 1

        mit = asyncio.create_task(nebenher())
        await search.ziel_geprueft("https://seite.example")
        mit.cancel()
        return ticks

    ticks = run(messen())
    assert ticks > 5, f"die Schleife stand still: {ticks} Ticks"


def test_die_pruefung_selbst_bleibt_dieselbe(monkeypatch):
    """`ziel_geprueft` ist nur der Faden drumherum - das Urteil kommt
    unveraendert von `oeffentliches_ziel`, samt Ueberbrueckung im Test."""
    monkeypatch.setattr(search, "oeffentliches_ziel",
                        lambda url: "Ziel ist intern." if "intern" in url else None)
    assert run(search.ziel_geprueft("https://intern.example")) == "Ziel ist intern."
    assert run(search.ziel_geprueft("https://aussen.example")) is None
