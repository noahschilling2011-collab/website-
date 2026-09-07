"""Was die Wissensquellen tun, wenn der Dienst dahinter nicht mitspielt.

Auftrag: "Features muessen auch dann stabil bleiben, wenn folgende Dienste
fehlen: echtes LLM, CDSE, externer Kalender, externe APIs. Fehlende Dienste
duerfen keinen Crash des Gesamtsystems verursachen."

Geprueft wird deshalb je Werkzeug dieselbe Reihe von Ausfaellen - Timeout,
Verbindungsfehler, HTTP 500, HTTP 429 mit und ohne `Retry-After`, kaputte oder
unerwartete Antwortform, leere Antwort, sehr grosse Antwort, dazu HTTP 404 und
eine Weiterleitung. Kein Test geht ins Netz: jeder Ausfall wird mit
`httpx.MockTransport` nachgestellt, so wie in `tests/test_fix09.py`.

Der Massstab steht in vier Punkten:

1. `ok=False` und EIN Satz auf Deutsch, den Noah versteht.
2. Kein Wurf, der nach oben durchschlaegt. Geprueft wird direkt an
   `execute()`, nicht nur ueber `run_tool` - der Dispatcher hat einen
   Auffangzweig, und ein Werkzeug, das sich darauf verlaesst, liefert am Ende
   "... ist mit einem Fehler ausgestiegen (AttributeError)". Genau das war
   der Befund vom 07.09.2026.
3. Keine unbegrenzte Antwort im Prompt. `display` ist das, was
   `core/tools/loop.py` als `tool_result` an das Modell zurueckgibt.
4. Der Cache in `lookups` speichert keinen Fehlschlag - sonst wird aus einer
   Stoerung von einer Minute eine Falschauskunft von 24 Stunden.
"""

from __future__ import annotations

import json

import httpx
import pytest

import api.app  # noqa: F401  - registriert die Werkzeuge
from core.db import connect, init_db
from core.rahmen import RAHMEN_AUF, RAHMEN_ZU
from core.tools import registry
from core.tools.dispatch import run_tool
from core.tools.wissen_tools import (
    MAX_ANTWORT_BYTES,
    MAX_HERKUNFT,
    MAX_ZEICHEN,
    MAX_ZEILEN,
)
from core.wissen import Wissen, cache_zaehler
from tests.conftest import run

# Was `display` hoechstens haben darf: der gekappte Text, die gekappte
# Herkunftszeile und die paar Zeichen drumherum ("[", "]", Zeilenumbruch,
# " (aus dem Cache)"). Bewusst grosszuegig - der Deckel soll Ausreisser
# fangen, nicht die Formulierung diktieren.
PROMPT_DECKEL = MAX_ZEICHEN + MAX_HERKUNFT + 32

ZIM = "wikipedia_de_all_mini_2026-03"

SUCH_XML = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><item>
  <title>Sonnensynchroner Orbit</title>
  <link>/content/{ZIM}/A/Sonnensynchroner_Orbit</link>
</item></channel></rss>"""

ARTIKEL_HTML = ("<html><body><p>Ein sonnensynchroner Orbit ist eine "
                "Umlaufbahn.</p></body></html>")

LIVE_TREFFER = {"pages": [{
    "id": 1, "key": "Sonnensynchroner_Orbit", "title": "Sonnensynchroner Orbit",
    "excerpt": "Eine <span>Umlaufbahn</span>.", "description": "Erdumlaufbahn",
}]}

WD_TREFFER = {"head": {"vars": ["ort", "einwohner"]},
              "results": {"bindings": [{"ort": {"value": "Bonn"},
                                        "einwohner": {"value": "336465"}}]}}


# --- Werkzeug fuer die Tests ------------------------------------------------


def kern(ergebnis) -> str:
    """`display` ohne den Rahmen aus core/rahmen.py.

    Alle drei Werkzeuge tragen `fremder_text = True`, der Dispatcher legt
    also 325 Zeichen um jedes Ergebnis. Fuer eine Laengenmessung muessen die
    weg, sonst misst man den Rahmen mit.
    """
    text = ergebnis.display or ""
    if text.startswith(RAHMEN_AUF):
        text = text[len(RAHMEN_AUF):]
        if text.endswith(RAHMEN_ZU):
            text = text[:-len(RAHMEN_ZU)]
    return text


def wirft(exc: BaseException) -> httpx.MockTransport:
    def behandeln(_anfrage: httpx.Request) -> httpx.Response:
        raise exc
    return httpx.MockTransport(behandeln)


def antwortet(*antworten: httpx.Response) -> httpx.MockTransport:
    """Der Reihe nach; die letzte Antwort wiederholt sich.

    `wiki_lokal` stellt ZWEI Anfragen (Suche, dann Artikel) - deshalb muss
    ein Transport hier mehr als eine Antwort kennen.
    """
    folge = list(antworten)

    def behandeln(_anfrage: httpx.Request) -> httpx.Response:
        return folge.pop(0) if len(folge) > 1 else folge[0]
    return httpx.MockTransport(behandeln)


def json_antwort(daten, status: int = 200, **kopf) -> httpx.Response:
    return httpx.Response(status, json=daten, headers=kopf or None)


@pytest.fixture
def db(tmp_path):
    pfad = tmp_path / "wissen.db"
    conn = connect(pfad)
    init_db(conn)
    conn.close()
    return pfad


@pytest.fixture
def lokal(db, monkeypatch):
    w = registry.get("wiki_lokal")
    monkeypatch.setattr(w, "basis", "http://127.0.0.1:8080", raising=False)
    monkeypatch.setattr(w, "zim", ZIM, raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "cache_an", True, raising=False)
    monkeypatch.setattr(w, "cache_stunden", 24.0, raising=False)
    return w


@pytest.fixture
def live(db, monkeypatch):
    w = registry.get("wiki_live")
    monkeypatch.setattr(w, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(w, "token", "", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "cache_an", True, raising=False)
    monkeypatch.setattr(w, "cache_stunden", 24.0, raising=False)
    return w


@pytest.fixture
def wd(db, monkeypatch):
    w = registry.get("wikidata")
    monkeypatch.setattr(w, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "cache_an", True, raising=False)
    return w


# ===========================================================================
# Querschnitt: die Regeln, die fuer alle drei gelten
# ===========================================================================

# Jeder Ausfall aus dem Auftrag, einmal als Transport. Was hier steht, wird
# fuer JEDES der drei Werkzeuge durchgespielt - eine Reparatur an einem
# Werkzeug allein reicht nicht.
AUSFAELLE = {
    "timeout": lambda: wirft(httpx.ReadTimeout("zu langsam")),
    "timeout_allgemein": lambda: wirft(httpx.TimeoutException("zu langsam")),
    "verbindung": lambda: wirft(httpx.ConnectError("kein Weg dorthin")),
    "http_500": lambda: antwortet(httpx.Response(500, text="Internal Error")),
    "http_503": lambda: antwortet(httpx.Response(503, text="Wartung")),
    "http_429_mit_ra": lambda: antwortet(
        httpx.Response(429, headers={"retry-after": "42"}, text="")),
    "http_429_ohne_ra": lambda: antwortet(httpx.Response(429, text="")),
    "http_404": lambda: antwortet(httpx.Response(404, text="Not Found")),
    "http_400": lambda: antwortet(httpx.Response(400, text="Bad Request")),
    "weiterleitung": lambda: antwortet(
        httpx.Response(302, headers={"location": "https://anderswo.test/x"})),
    "kaputtes_json": lambda: antwortet(httpx.Response(200, text="{ das ist kein JSON")),
    "leerer_koerper": lambda: antwortet(httpx.Response(200, text="")),
    "null_statt_liste": lambda: antwortet(json_antwort({"pages": None, "results": None})),
    "falscher_typ": lambda: antwortet(json_antwort({"pages": "abc",
                                                    "results": {"bindings": "abc"}})),
    "liste_statt_objekt": lambda: antwortet(json_antwort([1, 2, 3])),
    "felder_fehlen": lambda: antwortet(json_antwort({"pages": [{}],
                                                     "results": {"bindings": [{}]}})),
}

WERKZEUGE = {
    "wiki_lokal": ("lokal", {"begriff": "Orbit"}),
    "wiki_live": ("live", {"begriff": "Orbit", "sprache": "de"}),
    "wikidata": ("wikidata", {"sparql": "SELECT ?a WHERE {}"}),
}


def _werkzeug(name: str, request):
    return request.getfixturevalue({"wiki_lokal": "lokal", "wiki_live": "live",
                                    "wikidata": "wd"}[name])


@pytest.mark.parametrize("werkzeugname", sorted(WERKZEUGE))
@pytest.mark.parametrize("fall", sorted(AUSFAELLE))
def test_kein_ausfall_wirft_aus_dem_werkzeug_heraus(werkzeugname, fall, request,
                                                    monkeypatch):
    """Punkt 2 des Massstabs, und zwar an `execute()` statt an `run_tool`.

    Der Dispatcher faengt jede Ausnahme ab - ein Test ueber `run_tool` wuerde
    also auch dann gruen sein, wenn das Werkzeug selbst nichts abfaengt. Er
    misst dann nur noch den Dispatcher. Genau so ist der `AttributeError` bei
    einer unerwarteten Antwortform unbemerkt geblieben: `ok` war False, der
    Satz dazu unbrauchbar.
    """
    werkzeug = _werkzeug(werkzeugname, request)
    _, argumente = WERKZEUGE[werkzeugname]
    monkeypatch.setattr(werkzeug, "transport", AUSFAELLE[fall](), raising=False)

    ergebnis = run(werkzeug.execute(**argumente))

    assert ergebnis is not None
    assert isinstance(ergebnis.ok, bool)
    # Kein Fall darf mit einer leeren Auskunft enden.
    assert (ergebnis.display or "").strip(), f"{werkzeugname}/{fall} sagt nichts"


@pytest.mark.parametrize("werkzeugname", sorted(WERKZEUGE))
@pytest.mark.parametrize("fall", sorted(AUSFAELLE))
def test_jeder_ausfall_bleibt_ein_satz_ohne_innenleben(werkzeugname, fall, request,
                                                       monkeypatch):
    """Punkt 1: ein Satz, den Noah versteht - nicht der Name einer Klasse.

    `HTTPStatusError` steht ausdruecklich auf der Verbotsliste: das ist der
    Klassenname einer fremden Bibliothek, und er sagt nichts darueber, ob es
    ein 404, ein 500 oder eine Weiterleitung war. Bei einem Transportfehler
    (Timeout, Verbindung) bleibt der Typ dagegen erlaubt und erwuenscht - dort
    gibt es keinen Status, und `core/fehlertexte.ohne_geheimnis` macht es
    genauso.
    """
    werkzeug = _werkzeug(werkzeugname, request)
    _, argumente = WERKZEUGE[werkzeugname]
    monkeypatch.setattr(werkzeug, "transport", AUSFAELLE[fall](), raising=False)

    ergebnis = run(run_tool(werkzeugname, argumente))
    text = (ergebnis.error or "") + " " + kern(ergebnis)

    assert "HTTPStatusError" not in text, text
    assert "Traceback" not in text
    assert "AttributeError" not in text, (
        f"{werkzeugname}/{fall}: der Auffangzweig des Dispatchers hat "
        f"uebernommen - das Werkzeug selbst hat den Fall nicht behandelt: {text}"
    )
    # Kein Pfad, kein Modulname, keine Zeilennummer.
    for verboten in ("core/", "core.tools", ".py", "/home/", "self."):
        assert verboten not in text, f"{werkzeugname}/{fall}: {verboten!r} in {text!r}"


@pytest.mark.parametrize("werkzeugname", sorted(WERKZEUGE))
@pytest.mark.parametrize("fall", sorted(AUSFAELLE))
def test_kein_ausfall_landet_im_cache(werkzeugname, fall, request, monkeypatch, db):
    """Punkt 4. Ein Fehlschlag im Cache waere die teuerste Art zu scheitern.

    Der Cache in `lookups` haelt bis zu `cache_stunden` (Vorgabe 24). Landet
    dort das Ergebnis einer Stoerung, dann antwortet JARVIS einen Tag lang
    falsch, obwohl der Dienst nach einer Minute wieder da ist - und niemand
    merkt es, weil gar keine Anfrage mehr rausgeht.
    """
    werkzeug = _werkzeug(werkzeugname, request)
    _, argumente = WERKZEUGE[werkzeugname]
    monkeypatch.setattr(werkzeug, "transport", AUSFAELLE[fall](), raising=False)

    run(run_tool(werkzeugname, argumente))
    assert cache_zaehler(db) == 0, f"{werkzeugname}/{fall} hat etwas gecacht"


@pytest.mark.parametrize("werkzeugname", sorted(WERKZEUGE))
@pytest.mark.parametrize("fall", sorted(AUSFAELLE))
def test_keine_antwort_sprengt_den_prompt(werkzeugname, fall, request, monkeypatch):
    """Punkt 3, hier fuer die Fehlerzweige.

    Auch eine Fehlermeldung geht als `tool_result` in den Prompt. Der
    grosszuegige Deckel steht bewusst ueber `MAX_ZEICHEN` - er soll nur
    Ausreisser fangen, nicht die Formulierung diktieren.
    """
    werkzeug = _werkzeug(werkzeugname, request)
    _, argumente = WERKZEUGE[werkzeugname]
    monkeypatch.setattr(werkzeug, "transport", AUSFAELLE[fall](), raising=False)

    ergebnis = run(run_tool(werkzeugname, argumente))
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))
    assert len(ergebnis.error or "") <= PROMPT_DECKEL


# ===========================================================================
# wiki_lokal - die ZIM-Datei
# ===========================================================================


def test_lokal_happy_path(lokal, monkeypatch, db):
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text=SUCH_XML),
        httpx.Response(200, text=ARTIKEL_HTML)), raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))

    assert ergebnis.ok, ergebnis.error
    assert "Umlaufbahn" in ergebnis.display
    assert "Stand 2026-03" in ergebnis.display
    assert cache_zaehler(db) == 1, "der Gutfall gehoert sehr wohl in den Cache"


def test_lokal_ungueltige_eingabe(lokal, monkeypatch):
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text=SUCH_XML)), raising=False)

    leer = run(run_tool("wiki_lokal", {"begriff": "   "}))
    assert leer.ok is False and "Kein Begriff" in leer.error

    falsch = run(run_tool("wiki_lokal", {"begriff": 42}))
    assert falsch.ok is False and "erwartet string" in falsch.error


def test_lokal_fehlende_zim_datei_meldet_das_und_fragt_nicht(db, monkeypatch):
    """Fehlende Konfiguration: ohne WIKI_ZIM geht gar keine Anfrage raus."""
    gesehen = []

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen.append(anfrage.url)
        return httpx.Response(200, text=SUCH_XML)

    w = registry.get("wiki_lokal")
    monkeypatch.setattr(w, "zim", "", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))
    assert ergebnis.ok is False
    assert "WIKI_ZIM" in ergebnis.error
    assert gesehen == [], "ohne eingerichtete Kopie darf nichts rausgehen"


def test_lokal_unbekanntes_buch_ist_kein_erreichbarkeitsproblem(lokal, monkeypatch):
    """HTTP 404: kiwix-serve LAEUFT, es kennt das Buch nicht.

    Vorher stand hier "kiwix-serve nicht erreichbar (HTTPStatusError)" - und
    damit derselbe Satz wie bei einem abgestuerzten Server. Noah haette den
    Dienst neu gestartet, statt WIKI_ZIM zu pruefen.
    """
    monkeypatch.setattr(lokal, "transport",
                        antwortet(httpx.Response(404, text="No such book")),
                        raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    assert ergebnis.ok is False
    assert "404" in ergebnis.error
    assert "WIKI_ZIM" in ergebnis.error, ergebnis.error
    assert "nicht erreichbar" not in ergebnis.error, (
        "der Dienst hat geantwortet - er kennt nur das Buch nicht"
    )


def test_lokal_kaputte_datei_haelt_der_serverfehler_auseinander(lokal, monkeypatch):
    """HTTP 500 heisst etwas anderes als HTTP 404 und als 'nicht erreichbar'."""
    monkeypatch.setattr(lokal, "transport",
                        antwortet(httpx.Response(500, text="boom")), raising=False)
    fuenfhundert = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    monkeypatch.setattr(lokal, "transport",
                        antwortet(httpx.Response(404, text="nope")), raising=False)
    vierhundertvier = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    monkeypatch.setattr(lokal, "transport", wirft(httpx.ConnectError("x")),
                        raising=False)
    weg = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    assert all(e.ok is False for e in (fuenfhundert, vierhundertvier, weg))
    assert len({fuenfhundert.error, vierhundertvier.error, weg.error}) == 3
    assert "500" in fuenfhundert.error
    assert "nicht erreichbar" in weg.error


def test_lokal_weiterleitung_wird_gemeldet_nicht_verfolgt(lokal, monkeypatch):
    """FIX-03 Schritt 2 Punkt 4: niemand folgt hier blind einer Weiterleitung.

    Der Klient hat `follow_redirects=False`. Frueher wurde daraus ueber
    `raise_for_status()` ein `HTTPStatusError` und damit "nicht erreichbar" -
    also die Meldung, die am wenigsten mit dem zu tun hatte, was passiert ist.
    """
    gesehen = []

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen.append(str(anfrage.url))
        return httpx.Response(302, headers={"location": "http://anderswo.test/x"})

    monkeypatch.setattr(lokal, "transport", httpx.MockTransport(spion),
                        raising=False)
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    assert ergebnis.ok is False
    assert "302" in ergebnis.error and "Weiterleitung" in ergebnis.error
    assert len(gesehen) == 1, f"der Weiterleitung wurde gefolgt: {gesehen}"
    assert "anderswo.test" not in " ".join(gesehen)


def test_lokal_datei_ohne_treffer_bleibt_ein_ehrliches_nichts(lokal, monkeypatch, db):
    """Leeres Ergebnis: kein Fehler, keine Erfindung, kein Cache-Eintrag."""
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text="<rss version='2.0'><channel></channel></rss>")),
        raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Gibtesnicht"}))

    assert ergebnis.ok is True and ergebnis.data["hits"] == 0
    assert "Nichts zu" in ergebnis.display
    assert cache_zaehler(db) == 0, "ein Nulltreffer ist nichts zum Merken"


def test_lokal_treffer_ohne_text_ist_ein_fehlschlag_und_bleibt_es(lokal, monkeypatch, db):
    """Kaputte ZIM-Datei: die Suche findet etwas, der Artikel ist leer.

    Vorher kam dafuer `ok=True` mit einer Herkunftszeile und NICHTS dahinter -
    und dieses Nichts wanderte in den Cache. Ab dann beantwortete JARVIS die
    Frage 24 Stunden lang mit einer leeren, aber erfolgreich aussehenden
    Auskunft, ohne noch einmal nachzusehen.
    """
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text=SUCH_XML),
        httpx.Response(200, text="<html><body></body></html>")), raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))

    assert ergebnis.ok is False, kern(ergebnis)
    assert "keinen Text" in ergebnis.error
    assert cache_zaehler(db) == 0, "eine leere Auskunft darf nicht gecacht werden"


def test_lokal_sehr_grosser_artikel_kommt_gekappt_in_den_prompt(lokal, monkeypatch, db):
    """5 MB Artikeltext. Der Prompt bekommt MAX_ZEICHEN, der Cache auch."""
    riesig = "<html><body><p>" + ("A" * 5_000_000) + "</p></body></html>"
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text=SUCH_XML),
        httpx.Response(200, text=riesig)), raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))

    assert ergebnis.ok, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))

    # Und die Zeile im Cache ist genauso klein - sonst waechst die Datenbank
    # mit jedem langen Artikel, ohne dass je mehr davon herauskommt.
    from core.db import session
    with session(db) as conn:
        laenge = conn.execute("SELECT length(text) FROM lookups").fetchone()[0]
    assert laenge <= MAX_ZEICHEN, laenge


def test_lokal_sehr_langer_titel_sprengt_den_prompt_nicht(lokal, monkeypatch):
    """Der Titel steht in der Herkunftszeile - also VOR dem gekappten Text.

    Genau daran ging der einzige Deckel vorbei, den es gab: gemessen wurden
    199.862 Zeichen `display` bei einem 200.000 Zeichen langen `<title>`.
    """
    langer_titel = "T" * 200_000
    monkeypatch.setattr(lokal, "transport", antwortet(
        httpx.Response(200, text=(
            "<rss version='2.0'><channel><item>"
            f"<title>{langer_titel}</title><link>/content/x</link>"
            "</item></channel></rss>")),
        httpx.Response(200, text=ARTIKEL_HTML)), raising=False)

    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    assert ergebnis.ok, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))
    assert all(len(q) <= MAX_HERKUNFT for q in ergebnis.sources), ergebnis.sources
    assert len(ergebnis.data["titel"]) <= MAX_HERKUNFT


# ===========================================================================
# wiki_live - Wikipedia ueber das Netz
# ===========================================================================


def test_live_happy_path(live, monkeypatch, db):
    monkeypatch.setattr(live, "transport", antwortet(json_antwort(LIVE_TREFFER)),
                        raising=False)
    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": "de"}))

    assert ergebnis.ok, ergebnis.error
    assert "Umlaufbahn" in ergebnis.display
    assert cache_zaehler(db) == 1


def test_live_ungueltige_eingaben(live, monkeypatch):
    monkeypatch.setattr(live, "transport", antwortet(json_antwort(LIVE_TREFFER)),
                        raising=False)

    leer = run(run_tool("wiki_live", {"begriff": ""}))
    assert leer.ok is False and "Kein Begriff" in leer.error

    falsch = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": 7}))
    assert falsch.ok is False and "erwartet string" in falsch.error


def test_live_fehlende_credentials_fragen_nicht_erst(db, monkeypatch):
    """Fehlende Konfiguration: ohne WIKI_KONTAKT geht nichts raus."""
    gesehen = []

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen.append(anfrage.url)
        return json_antwort(LIVE_TREFFER)

    w = registry.get("wiki_live")
    monkeypatch.setattr(w, "kontakt", "", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))
    assert ergebnis.ok is False and "WIKI_KONTAKT" in ergebnis.error
    assert gesehen == []


def test_live_429_ohne_retry_after_erfindet_keine_wartezeit(live, monkeypatch):
    """Vorher stand dort "Retry-After: ?s" - eine Angabe, die es nicht gibt."""
    monkeypatch.setattr(live, "transport",
                        antwortet(httpx.Response(429, text="")), raising=False)
    ohne = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    monkeypatch.setattr(live, "transport",
                        antwortet(httpx.Response(429, headers={"retry-after": "120"},
                                                 text="")), raising=False)
    mit = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ohne.ok is False and mit.ok is False
    assert "429" in ohne.error and "429" in mit.error
    assert "?" not in ohne.error, ohne.error
    assert "120" in mit.error, mit.error
    # Der Rat bleibt in beiden Faellen stehen.
    assert "500 Anfragen" in ohne.error and "500 Anfragen" in mit.error


def test_live_kaputtes_json_und_leerer_koerper_sagen_dasselbe_ehrliche(live, monkeypatch):
    for koerper in ("{ kaputt", "", "<html>Fehlerseite</html>"):
        monkeypatch.setattr(live, "transport",
                            antwortet(httpx.Response(200, text=koerper)),
                            raising=False)
        ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))
        assert ergebnis.ok is False, koerper
        assert "kein JSON" in ergebnis.error, (koerper, ergebnis.error)


@pytest.mark.parametrize("daten", [
    {"pages": "abc"},                 # Zeichenkette statt Liste
    {"pages": ["abc"]},               # Liste von Zeichenketten statt Objekten
    {"pages": [42]},
    [1, 2, 3],                        # Liste statt Objekt
    "nur ein Wort",
    42,
])
def test_live_unerwartete_form_ist_ein_satz_kein_attributeerror(live, monkeypatch, daten):
    """Wohlgeformtes JSON in einer Form, die die REST-Doku nicht kennt.

    Bis zum 07.09.2026 lief das in `.get()` auf einer Zeichenkette. Der
    `AttributeError` schlug bis in den Auffangzweig des Dispatchers durch, und
    Noah las "wiki_live ist mit einem Fehler ausgestiegen (AttributeError)".
    """
    monkeypatch.setattr(live, "transport", antwortet(json_antwort(daten)),
                        raising=False)
    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ergebnis.ok is False, ergebnis.display
    assert "anders geantwortet" in ergebnis.error, ergebnis.error
    assert "AttributeError" not in ergebnis.error


def test_live_null_und_leere_liste_sind_kein_fehler(live, monkeypatch, db):
    """`null` statt Liste und `[]`: beides heisst 'nichts gefunden'."""
    for daten in ({"pages": None}, {"pages": []}, {}):
        monkeypatch.setattr(live, "transport", antwortet(json_antwort(daten)),
                            raising=False)
        ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))
        assert ergebnis.ok is True and ergebnis.data["hits"] == 0, daten
        assert "Nichts zu" in ergebnis.display
    assert cache_zaehler(db) == 0


def test_live_fehlende_felder_erfinden_nichts(live, monkeypatch):
    """Ein Treffer ohne title, key, excerpt und description."""
    monkeypatch.setattr(live, "transport", antwortet(json_antwort({"pages": [{}]})),
                        raising=False)
    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ergebnis.ok, ergebnis.error
    # Der Begriff selbst ist das Einzige, was hier sicher stimmt.
    assert "Orbit" in ergebnis.display


def test_live_404_und_weiterleitung_sind_unterscheidbar(live, monkeypatch):
    monkeypatch.setattr(live, "transport",
                        antwortet(httpx.Response(404, text="nf")), raising=False)
    vierhundertvier = run(run_tool("wiki_live", {"begriff": "Gibtesnicht"}))

    monkeypatch.setattr(live, "transport", antwortet(
        httpx.Response(301, headers={"location": "https://de.wikipedia.org/neu"})),
        raising=False)
    umzug = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert vierhundertvier.ok is False and umzug.ok is False
    assert "404" in vierhundertvier.error
    assert "301" in umzug.error and "Weiterleitung" in umzug.error
    assert vierhundertvier.error != umzug.error


def test_live_riesige_antwort_wird_abgebrochen_statt_geladen(live, monkeypatch):
    """Mehr als MAX_ANTWORT_BYTES: abbrechen und das auch sagen.

    Eine in der Mitte abgeschnittene JSON-Antwort ist kein JSON mehr. Sie als
    "kein JSON geliefert" zu melden waere die falsche Faehrte - die
    Gegenstelle hat sauber geantwortet, nur zu viel.
    """
    riesig = json.dumps({"pages": [{"title": "T", "key": "K", "description": "D",
                                    "excerpt": "E" * (MAX_ANTWORT_BYTES + 10_000)}]})
    assert len(riesig) > MAX_ANTWORT_BYTES
    monkeypatch.setattr(live, "transport", antwortet(
        httpx.Response(200, text=riesig,
                       headers={"content-type": "application/json"})), raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ergebnis.ok is False
    assert "MB" in ergebnis.error, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL


def test_live_langer_titel_und_auszug_kommen_gekappt_an(live, monkeypatch):
    monkeypatch.setattr(live, "transport", antwortet(json_antwort({"pages": [{
        "title": "T" * 100_000, "key": "K" * 100_000,
        "description": "D" * 100_000, "excerpt": "E" * 100_000}]})), raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ergebnis.ok, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))
    assert all(len(q) <= MAX_HERKUNFT for q in ergebnis.sources)


# ===========================================================================
# wikidata - SPARQL
# ===========================================================================


def test_wikidata_happy_path(wd, monkeypatch):
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(WD_TREFFER)),
                        raising=False)
    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?ort WHERE {}"}))

    assert ergebnis.ok, ergebnis.error
    assert "336465" in ergebnis.display and "Bonn" in ergebnis.display


def test_wikidata_ungueltige_eingaben(wd, monkeypatch):
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(WD_TREFFER)),
                        raising=False)

    leer = run(run_tool("wikidata", {"sparql": "  "}))
    assert leer.ok is False and "Keine Abfrage" in leer.error

    falsch = run(run_tool("wikidata", {"sparql": ["SELECT"]}))
    assert falsch.ok is False and "erwartet string" in falsch.error


def test_wikidata_fehlende_credentials(db, monkeypatch):
    gesehen = []

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen.append(anfrage.url)
        return json_antwort(WD_TREFFER)

    w = registry.get("wikidata")
    monkeypatch.setattr(w, "kontakt", "", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))
    assert ergebnis.ok is False and "WIKI_KONTAKT" in ergebnis.error
    assert gesehen == []


def test_wikidata_429_nennt_die_wartezeit_wenn_es_eine_gibt(wd, monkeypatch):
    monkeypatch.setattr(wd, "transport", antwortet(
        httpx.Response(429, headers={"retry-after": "30"}, text="")), raising=False)
    mit = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))

    monkeypatch.setattr(wd, "transport", antwortet(httpx.Response(429, text="")),
                        raising=False)
    ohne = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))

    assert mit.ok is False and ohne.ok is False
    assert "30" in mit.error, mit.error
    assert "?" not in ohne.error, ohne.error
    assert "5 parallele" in mit.error and "5 parallele" in ohne.error


@pytest.mark.parametrize("daten", [
    {"results": {"bindings": "abc"}},
    {"results": "abc"},
    {"results": {"bindings": ["x"]}},
    {"results": {"bindings": [1, 2]}},
    [1, 2, 3],
])
def test_wikidata_unerwartete_form_ist_ein_satz(wd, monkeypatch, daten):
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(daten)),
                        raising=False)
    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))

    assert ergebnis.ok is False, ergebnis.display
    assert "anders geantwortet" in ergebnis.error
    assert "AttributeError" not in ergebnis.error


def test_wikidata_leere_ergebnismenge_bleibt_ok(wd, monkeypatch):
    for daten in ({"head": {"vars": []}, "results": {"bindings": []}},
                  {"results": None}, {"results": {"bindings": None}}, {}):
        monkeypatch.setattr(wd, "transport", antwortet(json_antwort(daten)),
                            raising=False)
        ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))
        assert ergebnis.ok is True and ergebnis.data["hits"] == 0, daten
        assert "keine Zeilen" in ergebnis.display


def test_wikidata_zelle_ohne_value_kippt_nicht_um(wd, monkeypatch):
    """Das Handbuch verspricht je Zelle ein Objekt mit `value`.

    Kommt stattdessen eine blanke Zeichenkette oder eine Zahl, ist das kein
    Grund auszusteigen - hier flog vorher ein `AttributeError`.
    """
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(
        {"head": {"vars": ["a", "b"]},
         "results": {"bindings": [{"a": "roh", "b": 7}]}})), raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?a ?b WHERE {}"}))

    assert ergebnis.ok, ergebnis.error
    assert "a=roh" in ergebnis.display and "b=7" in ergebnis.display


def test_wikidata_50000_zeilen_sagen_dass_es_50000_sind(wd, monkeypatch):
    """Sonst haelt das Modell die zehn gezeigten Zeilen fuer alle."""
    viele = {"head": {"vars": ["a"]},
             "results": {"bindings": [{"a": {"value": str(i)}} for i in range(50_000)]}}
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(viele)),
                        raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?a WHERE {}"}))

    assert ergebnis.ok, ergebnis.error
    assert ergebnis.data["hits"] == 50_000
    assert "50000" in ergebnis.display, kern(ergebnis)
    assert kern(ergebnis).count("\n") <= MAX_ZEILEN + 2
    assert len(kern(ergebnis)) <= PROMPT_DECKEL


def test_wikidata_eine_riesige_zelle_kommt_nicht_in_den_prompt(wd, monkeypatch):
    """Der schlimmste gemessene Fall: display hatte 5.000.143 Zeichen."""
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(
        {"head": {"vars": ["a"]},
         "results": {"bindings": [{"a": {"value": "Z" * 1_000_000}}]}})),
        raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?a WHERE {}"}))

    assert ergebnis.ok, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))


def test_wikidata_viele_spalten_sprengen_die_zeile_nicht(wd, monkeypatch):
    spalten = [f"s{i}" for i in range(5_000)]
    zeile = {s: {"value": "x" * 50} for s in spalten}
    monkeypatch.setattr(wd, "transport", antwortet(json_antwort(
        {"head": {"vars": spalten}, "results": {"bindings": [zeile]}})),
        raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT * WHERE {}"}))

    assert ergebnis.ok, ergebnis.error
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))


def test_wikidata_riesige_antwort_wird_abgebrochen(wd, monkeypatch):
    riesig = json.dumps({"head": {"vars": ["a"]}, "results": {"bindings": [
        {"a": {"value": "Z" * (MAX_ANTWORT_BYTES + 10_000)}}]}})
    monkeypatch.setattr(wd, "transport", antwortet(
        httpx.Response(200, text=riesig,
                       headers={"content-type": "application/json"})), raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?a WHERE {}"}))

    assert ergebnis.ok is False
    assert "MB" in ergebnis.error and "LIMIT" in ergebnis.error


# ===========================================================================
# Der Cache: die Regel selbst, nicht nur ihre Wirkung
# ===========================================================================


def test_der_cache_nimmt_keinen_leeren_treffer_an(lokal, db):
    """Direkt an der Ursache, damit die Regel nicht nur ueber einen Umweg
    geprueft ist: `_merken` selbst lehnt einen Treffer ohne Text ab."""
    lokal._merken(Wissen(begriff="Leer", titel="Leer", text="   ",
                         quelle="wiki_lokal", snapshot="2026-03"))
    assert cache_zaehler(db) == 0

    lokal._merken(Wissen(begriff="Voll", titel="Voll", text="etwas",
                         quelle="wiki_lokal", snapshot="2026-03"))
    assert cache_zaehler(db) == 1, "der Gutfall muss weiterhin durchgehen"


def test_der_cache_kappt_beim_schreiben(lokal, db):
    lokal._merken(Wissen(begriff="Lang", titel="T" * 10_000, text="X" * 100_000,
                         quelle="wiki_lokal", snapshot="2026-03"))
    from core.db import session
    with session(db) as conn:
        titel, text = conn.execute(
            "SELECT length(titel), length(text) FROM lookups").fetchone()
    assert titel <= MAX_HERKUNFT and text <= MAX_ZEICHEN, (titel, text)


def test_eine_alte_ueberlange_cachezeile_kommt_trotzdem_gekappt_heraus(lokal, db,
                                                                      monkeypatch):
    """Zeilen, die VOR dieser Grenze geschrieben wurden, sind noch da.

    Deshalb kappt `_antwort` ein zweites Mal. Ohne das haette die Reparatur
    fuer jeden Bestandseintrag keine Wirkung.
    """
    from core.db import session
    from core.wissen import _jetzt

    with session(db) as conn:
        conn.execute(
            "INSERT INTO lookups (begriff, quelle, text, titel, snapshot, geholt_am)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            ("orbit", "wiki_lokal", "X" * 500_000, "T" * 500_000, "2026-03",
             _jetzt()))

    # Kein Transport noetig: die Antwort kommt aus dem Cache.
    monkeypatch.setattr(lokal, "transport", wirft(httpx.ConnectError("aus")),
                        raising=False)
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))

    assert ergebnis.ok and ergebnis.data["cache"] is True
    assert len(kern(ergebnis)) <= PROMPT_DECKEL, len(kern(ergebnis))


def test_gegenprobe_die_laengenpruefung_wuerde_ueberhaupt_anschlagen():
    """Ein Waechter, der nichts fangen kann, ist der gefaehrlichste Test.

    Also die Gegenprobe zu allen Laengenzusicherungen oben: ein `display`, das
    zu lang IST, muss durch dieselbe Messung durchfallen.
    """
    from core.contracts import ToolResult

    zu_lang = ToolResult(ok=True, display=RAHMEN_AUF + "A" * 100_000 + RAHMEN_ZU)
    assert len(kern(zu_lang)) > PROMPT_DECKEL

    gerade_noch = ToolResult(ok=True, display=RAHMEN_AUF + "A" * 100 + RAHMEN_ZU)
    assert len(kern(gerade_noch)) <= PROMPT_DECKEL


def test_live_treffer_ohne_inhalt_kommt_zurueck_aber_nicht_in_den_cache(live,
                                                                       monkeypatch,
                                                                       db):
    """Ein Treffer ohne description und ohne excerpt.

    Zurueckgegeben wird er - den Artikel gibt es, und seine URL ist der
    Anschluss fuer `fetch_url`. Gemerkt wird er nicht: die Tabelle `lookups`
    hat keine Spalte fuer die URL, aus dem Cache kaeme also einen Tag lang nur
    der Begriff zurueck, der schon in der Frage stand.
    """
    monkeypatch.setattr(live, "transport", antwortet(json_antwort(
        {"pages": [{"title": "Orbit", "key": "Orbit"}]})), raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))

    assert ergebnis.ok, ergebnis.error
    assert "Orbit" in ergebnis.display
    assert any("wikipedia.org/wiki/Orbit" in q for q in ergebnis.sources), \
        ergebnis.sources
    assert cache_zaehler(db) == 0

    # Gegenprobe: mit Inhalt wird sehr wohl gemerkt.
    monkeypatch.setattr(live, "transport", antwortet(json_antwort(LIVE_TREFFER)),
                        raising=False)
    assert run(run_tool("wiki_live", {"begriff": "Sonnensynchroner Orbit"})).ok
    assert cache_zaehler(db) == 1


def test_gegenprobe_die_cachepruefung_wuerde_einen_eintrag_bemerken(lokal, db):
    """Zu jedem `cache_zaehler(db) == 0` oben gehoert der Nachweis, dass diese
    Messung ueberhaupt etwas sieht - sonst prueft sie nur, dass die Tabelle
    existiert."""
    assert cache_zaehler(db) == 0
    lokal._merken(Wissen(begriff="Orbit", titel="Orbit", text="etwas",
                         quelle="wiki_lokal", snapshot="2026-03"))
    assert cache_zaehler(db) == 1


def test_live_zweite_anfrage_kommt_aus_dem_cache(live, monkeypatch, db):
    """Der Gegenpol zu allen Tests oben: der Cache muss auch TREFFEN.

    Der Schluessel ist "<sprache>:<begriff>". Wird er beim Schreiben durch
    etwas anderes ersetzt - etwa durch den Wikipedia-Seitennamen -, dann
    steht die Zeile zwar in `lookups`, aber `_gecached` findet sie nie
    wieder. Auffallen wuerde das sonst nur an der Anzahl der Netzanfragen,
    also erst auf der Rechnung.
    """
    anfragen = []

    def spion(anfrage: httpx.Request) -> httpx.Response:
        anfragen.append(str(anfrage.url))
        return json_antwort(LIVE_TREFFER)

    monkeypatch.setattr(live, "transport", httpx.MockTransport(spion),
                        raising=False)

    erste = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": "de"}))
    assert erste.ok and erste.data["cache"] is False
    assert cache_zaehler(db) == 1

    zweite = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": "de"}))
    assert zweite.ok, zweite.error
    assert zweite.data["cache"] is True, "die zweite Anfrage ging noch mal raus"
    assert len(anfragen) == 1, anfragen

    # Andere Sprache, andere Zeile - der Schluessel traegt sie mit.
    dritte = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": "en"}))
    assert dritte.ok and dritte.data["cache"] is False
    assert len(anfragen) == 2 and cache_zaehler(db) == 2


# ===========================================================================
# Die inneren Deckel: dass es sie WIRKLICH gibt, nicht nur den aeusseren
# ===========================================================================
#
# Nachgetragen bei der Abnahme (07.09.2026). Die Tests oben messen `display`
# gegen `PROMPT_DECKEL` - und der aeussere Deckel `MAX_ZEICHEN` haelt das
# Ergebnis auch dann klein, wenn `MAX_ZELLE` und `MAX_ANTWORT_BYTES` nicht
# mehr greifen. Zwei Mutationsproben blieben deshalb gruen:
#
#     MAX_ZELLE = 10_000_000          -> kein Test rot
#     MAX_ANTWORT_BYTES ohne Wirkung  -> kein Test rot
#
# Beide Deckel sind gestaffelte Verteidigung: sie sollen greifen, BEVOR der
# aeussere greifen muss - der eine, damit eine Zelle nicht die ganze Tabelle
# verdraengt, der andere, damit die Antwort gar nicht erst in den Speicher
# kommt. Ohne eigene Tests ist gestaffelte Verteidigung nur ein Wort.


def test_eine_riesige_zelle_verdraengt_nicht_die_ganze_tabelle():
    """Der aeussere Deckel wuerde hier einfach hinten abschneiden - und damit
    saemtliche weiteren Spalten und Zeilen mitnehmen. `MAX_ZELLE` sorgt
    dafuer, dass eine ausufernde Zelle nur sich selbst kostet."""
    from core.tools.wissen_tools import MAX_ZELLE, _zellwert

    wert = _zellwert({"a": {"value": "Z" * 1_000_000}}, "a")
    assert len(wert) == MAX_ZELLE, len(wert)
    assert wert.endswith("…")


@pytest.mark.parametrize("zelle,erwartet", [
    ({"value": "kurz"}, "kurz"),      # der Normalfall aus dem Handbuch
    ({"value": 42}, "42"),            # eine Zahl statt einer Zeichenkette
    ({}, ""),                         # Objekt ohne value
    (None, ""),                       # Spalte fehlt in dieser Zeile
    ("roher Text", "roher Text"),     # gar kein Objekt - vorher AttributeError
    (["a", "b"], "['a', 'b']"),       # eine Liste, so wie sie ist
])
def test_zellwert_nimmt_jede_form_ohne_attributeerror(zelle, erwartet):
    from core.tools.wissen_tools import _zellwert

    assert _zellwert({"a": zelle}, "a") == erwartet


def test_der_zellendeckel_steht_auf_einer_abgesprochenen_zahl():
    """Ein Deckel, den man beim naechsten roten Test still hochsetzt, ist
    kein Deckel. Diese Zeile macht das Hochsetzen sichtbar."""
    from core.tools.wissen_tools import MAX_ZELLE

    assert MAX_ZELLE == 300


def test_eine_riesige_antwort_kommt_gar_nicht_erst_in_den_speicher(wd, monkeypatch):
    """`MAX_ANTWORT_BYTES` soll den Rumpf beim Stroemen abbrechen. Gemessen
    wird deshalb, wie viel der Transport ueberhaupt liefern MUSSTE - nicht,
    wie gross `display` am Ende war. Ohne den Abbruch laedt eine Gegenstelle,
    die einfach weitersendet, den Speicher voll.
    """
    geliefert = {"bytes": 0}
    stueck = b"Z" * 100_000
    BEREIT = 60 * len(stueck)          # 6 MB stuenden zur Verfuegung

    def stroemt(request: httpx.Request) -> httpx.Response:
        # ASYNCHRON: httpx nimmt fuer eine gestroemte Antwort nur einen
        # AsyncByteStream an. Ein gewoehnlicher Generator gibt einen
        # SyncByteStream, und httpx bricht mit einem nackten `assert` ab -
        # der Test war damit gruen, ohne je ein Byte geliefert zu haben.
        async def haeppchen():
            for _ in range(60):
                geliefert["bytes"] += len(stueck)
                yield stueck

        return httpx.Response(
            200, headers={"content-type": "application/json"},
            content=haeppchen())

    monkeypatch.setattr(wd, "transport", httpx.MockTransport(stroemt),
                        raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?a WHERE {}"}))

    assert ergebnis.ok is False
    # Zuerst die Gegenprobe: es wurde ueberhaupt gestroemt. Ohne sie waere
    # jeder Fehlschlag vor der ersten Anfrage ein gruener Test.
    assert geliefert["bytes"] > 0, "es wurde gar nicht erst gestroemt"
    # Und dann die eigentliche Zusage: hoechstens der Deckel plus ein
    # Haeppchen, nicht die vollen 6 MB.
    assert geliefert["bytes"] <= MAX_ANTWORT_BYTES + len(stueck), geliefert
    assert geliefert["bytes"] < BEREIT, geliefert


def test_der_antwortdeckel_steht_auf_einer_abgesprochenen_zahl():
    assert MAX_ANTWORT_BYTES == 2_000_000
