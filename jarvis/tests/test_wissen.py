"""Die Wissensquellen aus `docs/wissensquellen.md`.

Kein Test geht ins Netz. `wiki_lokal` laeuft gegen einen echten kleinen
HTTP-Server, der genau das Format spricht, das die kiwix-serve-Doku
beschreibt; `wiki_live` und `wikidata` gegen `httpx.MockTransport`.

Warum ein echter Server fuer kiwix und ein Mock fuer die anderen: kiwix laeuft
per Vertrag auf `127.0.0.1`, das darf die Netzsperre der Tests. Die beiden
anderen gehen nach draussen und muessen deshalb gesperrt bleiben.
"""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

import api.app  # noqa: F401  - registriert die Werkzeuge
from core.db import connect, init_db
from core.tools import registry
from core.tools.dispatch import run_tool
from core.wissen import Wissen, aus_cache, cache_zaehler, in_cache, snapshot_aus_zimname
from tests.conftest import run

ZIM = "wikipedia_de_all_mini_2026-03"

# Genau das Format, das die kiwix-serve-Doku fuer format=xml nennt:
# ein OpenSearch-RSS mit item/link und item/title.
SUCH_XML = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
  <channel>
    <title>Kiwix</title>
    <opensearch:totalResults>1</opensearch:totalResults>
    <item>
      <title>Sonnensynchroner Orbit</title>
      <link>/content/{zim}/A/Sonnensynchroner_Orbit</link>
    </item>
  </channel>
</rss>""".format(zim=ZIM)

ARTIKEL_HTML = (
    "<html><head><style>p{color:red}</style></head><body>"
    "<h1>Sonnensynchroner Orbit</h1>"
    "<p>Ein sonnensynchroner Orbit ist eine Umlaufbahn, bei der der Satellit "
    "einen Ort immer zur selben Ortszeit &uuml;berfliegt.</p>"
    "<script>alert('weg')</script></body></html>"
)


class KiwixAttrappe(BaseHTTPRequestHandler):
    leer = False
    # Verknuepfungspruefung 31.08.2026, Fund 2: /search antwortet mit HTTP 200
    # und diesem Koerper statt mit XML, wenn gesetzt. Genau das liefert ein
    # kiwix-serve mit falschem WIKI_ZIM, eine aeltere Version oder ein Reverse
    # Proxy davor - und `raise_for_status()` sieht davon nichts.
    statt_xml: str | None = None

    def do_GET(self):  # noqa: N802 - von BaseHTTPRequestHandler vorgegeben
        teile = urlparse(self.path)
        if teile.path == "/search":
            felder = parse_qs(teile.query)
            # Die Doku verlangt books.name und pattern - fehlt eins, 400.
            if "pattern" not in felder or "books.name" not in felder:
                self.send_response(400); self.end_headers(); return
            if type(self).statt_xml is not None:
                self._sende(type(self).statt_xml, "text/html")
                return
            koerper = ("<rss version='2.0'><channel></channel></rss>"
                       if type(self).leer else SUCH_XML)
            self._sende(koerper, "application/xml")
        elif teile.path.startswith("/content/"):
            self._sende(ARTIKEL_HTML, "text/html")
        else:
            self.send_response(404); self.end_headers()

    def _sende(self, koerper: str, typ: str) -> None:
        roh = koerper.encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", typ)
        self.send_header("content-length", str(len(roh)))
        self.end_headers()
        self.wfile.write(roh)

    def log_message(self, *_):  # Ruhe im Testprotokoll
        return


@pytest.fixture
def kiwix():
    KiwixAttrappe.leer = False
    KiwixAttrappe.statt_xml = None
    server = HTTPServer(("127.0.0.1", 0), KiwixAttrappe)
    faden = threading.Thread(target=server.serve_forever, daemon=True)
    faden.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()


@pytest.fixture
def db(tmp_path):
    pfad = tmp_path / "w.db"
    conn = connect(pfad)
    init_db(conn)
    conn.close()
    return pfad


@pytest.fixture
def lokal(kiwix, db, monkeypatch):
    werkzeug = registry.get("wiki_lokal")
    monkeypatch.setattr(werkzeug, "basis", kiwix, raising=False)
    monkeypatch.setattr(werkzeug, "zim", ZIM, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    monkeypatch.setattr(werkzeug, "transport", None, raising=False)
    return werkzeug


# --- Snapshot-Datum ---------------------------------------------------------


@pytest.mark.parametrize("name,erwartet", [
    ("wikipedia_de_all_mini_2026-03.zim", "2026-03"),
    ("wikipedia_de_all_mini_2026-03", "2026-03"),
    ("wikipedia_en_all_nopic_2025-11", "2025-11"),
    ("ohne_datum", None),
])
def test_snapshot_kommt_aus_dem_zimnamen(name, erwartet):
    """Das Format _YYYY-MM nennt die kiwix-Doku bei --nodatealiases."""
    assert snapshot_aus_zimname(name) == erwartet


# --- DoD 1-3: wiki_lokal ----------------------------------------------------


def test_dod_1_kiwix_antwortet(kiwix):
    """Ein Artikel kommt ueber HTTP zurueck - der Vertrag mit kiwix-serve."""
    antwort = httpx.get(f"{kiwix}/search",
                        params={"pattern": "Orbit", "books.name": ZIM, "format": "xml"})
    assert antwort.status_code == 200
    assert "<item>" in antwort.text


def test_dod_2_und_3_antwort_kommt_aus_wiki_lokal_mit_titel_und_snapshot(lokal):
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))
    assert ergebnis.ok, ergebnis.error
    assert "Sonnensynchroner Orbit" in ergebnis.display
    assert "Stand 2026-03" in ergebnis.display, "Snapshot-Datum ist Pflicht"
    assert ergebnis.data["snapshot"] == "2026-03"
    assert ergebnis.sources, "Herkunft ist Pflicht, auch bei lokaler Quelle"
    assert "Umlaufbahn" in ergebnis.display
    assert "alert(" not in ergebnis.display, "Skripte gehoeren nicht in den Prompt"
    assert "<p>" not in ergebnis.display, "kein HTML in den Prompt"


def test_wiki_lokal_ohne_treffer_erfindet_nichts(lokal):
    KiwixAttrappe.leer = True
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Gibtesnicht"}))
    assert ergebnis.ok and ergebnis.data["hits"] == 0
    assert "Nichts zu" in ergebnis.display


def test_wiki_lokal_ohne_zim_sagt_das(db, monkeypatch):
    werkzeug = registry.get("wiki_lokal")
    monkeypatch.setattr(werkzeug, "zim", "", raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))
    assert ergebnis.ok is False
    assert "kiwix-serve" in ergebnis.error and "download.kiwix.org" in ergebnis.error


def test_wiki_lokal_ohne_server_stuerzt_nicht_ab(db, monkeypatch):
    werkzeug = registry.get("wiki_lokal")
    monkeypatch.setattr(werkzeug, "basis", "http://127.0.0.1:1", raising=False)
    monkeypatch.setattr(werkzeug, "zim", ZIM, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Orbit"}))
    assert ergebnis.ok is False and "nicht erreichbar" in ergebnis.error


# --- DoD 6: Cache -----------------------------------------------------------


def test_dod_6_zweite_anfrage_trifft_den_cache_ohne_netz(lokal, db):
    erste = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))
    assert erste.data["cache"] is False
    assert cache_zaehler(db) == 1

    # Server abwuergen: was jetzt noch geht, kam aus dem Cache.
    lokal.basis = "http://127.0.0.1:1"
    zweite = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))
    assert zweite.ok, "zweite Anfrage haette aus dem Cache kommen muessen"
    assert zweite.data["cache"] is True
    assert "aus dem Cache" in zweite.display
    assert cache_zaehler(db) == 1, "keine zweite Zeile fuer dieselbe Frage"


def test_cache_haelt_quellen_auseinander(db):
    in_cache(db, Wissen(begriff="orbit", titel="A", text="lokal", quelle="wiki_lokal",
                        snapshot="2026-03"))
    in_cache(db, Wissen(begriff="orbit", titel="B", text="live", quelle="wiki_live"))
    assert aus_cache(db, "orbit", "wiki_lokal").text == "lokal"
    assert aus_cache(db, "orbit", "wiki_live").text == "live"
    assert cache_zaehler(db) == 2


def test_cache_gross_und_kleinschreibung_egal(db):
    in_cache(db, Wissen(begriff="Orbit", titel="A", text="x", quelle="wiki_lokal"))
    assert aus_cache(db, "  ORBIT ", "wiki_lokal") is not None


# --- DoD 5: wiki_live -------------------------------------------------------


def _live_transport(status=200, daten=None, kopf=None):
    def handhabe(anfrage: httpx.Request) -> httpx.Response:
        handhabe.gesehen = anfrage
        return httpx.Response(status, json=daten if daten is not None else {},
                              headers=kopf or {})
    handhabe.gesehen = None
    return httpx.MockTransport(handhabe), handhabe


LIVE_ANTWORT = {"pages": [{
    "id": 1, "key": "Sonnensynchroner_Orbit", "title": "Sonnensynchroner Orbit",
    "excerpt": "Eine <span class=\"searchmatch\">Umlaufbahn</span>.",
    "description": "Erdumlaufbahn",
}]}


def test_dod_5_wiki_live_sendet_konformen_user_agent_mit_kontakt(db, monkeypatch):
    transport, spion = _live_transport(daten=LIVE_ANTWORT)
    werkzeug = registry.get("wiki_live")
    monkeypatch.setattr(werkzeug, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(werkzeug, "transport", transport, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit", "sprache": "de"}))
    assert ergebnis.ok, ergebnis.error

    ua = spion.gesehen.headers["user-agent"]
    assert "JARVIS" in ua and "noah@example.org" in ua, \
        "Wikimedia verlangt einen User-Agent mit Kontaktangabe"
    assert str(spion.gesehen.url).startswith(
        "https://de.wikipedia.org/w/rest.php/v1/search/page"), str(spion.gesehen.url)
    assert "api.wikimedia.org" not in str(spion.gesehen.url), \
        "die Core API ist ab Juli 2026 in der Abkuendigung"
    assert "Umlaufbahn" in ergebnis.display
    assert "<span" not in ergebnis.display, "kein HTML in den Prompt"


def test_wiki_live_ohne_kontakt_fragt_gar_nicht_erst(db, monkeypatch):
    werkzeug = registry.get("wiki_live")
    monkeypatch.setattr(werkzeug, "kontakt", "", raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))
    assert ergebnis.ok is False and "WIKI_KONTAKT" in ergebnis.error


def test_wiki_live_nennt_das_ratenlimit_beim_429(db, monkeypatch):
    transport, _ = _live_transport(status=429, kopf={"retry-after": "120"})
    werkzeug = registry.get("wiki_live")
    monkeypatch.setattr(werkzeug, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(werkzeug, "transport", transport, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    ergebnis = run(run_tool("wiki_live", {"begriff": "Orbit"}))
    assert ergebnis.ok is False
    assert "120" in ergebnis.error and "500 Anfragen" in ergebnis.error


def test_wiki_live_mit_token_setzt_den_header(db, monkeypatch):
    transport, spion = _live_transport(daten=LIVE_ANTWORT)
    werkzeug = registry.get("wiki_live")
    monkeypatch.setattr(werkzeug, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(werkzeug, "token", "geheim", raising=False)
    monkeypatch.setattr(werkzeug, "transport", transport, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    run(run_tool("wiki_live", {"begriff": "Orbit"}))
    assert spion.gesehen.headers["authorization"] == "Bearer geheim"


# --- wikidata ---------------------------------------------------------------


def test_wikidata_fragt_den_dokumentierten_endpunkt(db, monkeypatch):
    antwort = {"head": {"vars": ["ort", "einwohner"]},
               "results": {"bindings": [
                   {"ort": {"value": "Schwäbisch Gmünd"}, "einwohner": {"value": "61216"}}]}}
    transport, spion = _live_transport(daten=antwort)
    werkzeug = registry.get("wikidata")
    monkeypatch.setattr(werkzeug, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(werkzeug, "transport", transport, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)

    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?ort WHERE {}"}))
    assert ergebnis.ok, ergebnis.error
    assert str(spion.gesehen.url) == "https://query.wikidata.org/sparql"
    assert spion.gesehen.method == "POST", "POST erlaubt laengere Abfragen"
    assert spion.gesehen.headers["accept"] == "application/sparql-results+json"
    assert "61216" in ergebnis.display


def test_wikidata_leere_ergebnismenge_ist_kein_fehler(db, monkeypatch):
    transport, _ = _live_transport(daten={"head": {"vars": []}, "results": {"bindings": []}})
    werkzeug = registry.get("wikidata")
    monkeypatch.setattr(werkzeug, "kontakt", "x@example.org", raising=False)
    monkeypatch.setattr(werkzeug, "transport", transport, raising=False)
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    ergebnis = run(run_tool("wikidata", {"sparql": "SELECT ?x WHERE {}"}))
    assert ergebnis.ok and ergebnis.data["hits"] == 0


def test_wikidata_timeout_liegt_unter_der_harten_frist():
    """60 s harte Frist laut Doku - so lange wartet kein Chatzug."""
    assert registry.get("wikidata").timeout_s < 60


# --- DoD 2 und 7: Reihenfolge und Netzunabhaengigkeit ------------------------


def test_dod_2_der_research_agent_kennt_die_reihenfolge():
    from core.agents import RECHERCHE_PROMPT

    assert "wiki_lokal zuerst" in RECHERCHE_PROMPT
    # Billig muss im Prompt vor teuer stehen, nicht nur vorkommen.
    assert (RECHERCHE_PROMPT.index("wiki_lokal")
            < RECHERCHE_PROMPT.index("wiki_live")
            < RECHERCHE_PROMPT.index("web_search"))


def test_dod_2_wiki_lokal_liegt_dem_agenten_vor_web_search():
    from core.agents import baue_agenten
    from core.contracts import Permission
    from core.llm import FakeLLMProvider

    agent = baue_agenten(FakeLLMProvider(), max_permission=Permission.READ)["research"]
    assert agent.tools.index("wiki_lokal") < agent.tools.index("web_search")


def test_dod_7_ohne_netz_antwortet_wiki_lokal_weiter(lokal, db):
    """Der Punkt der lokalen Kopie: sie haengt nicht am Netz."""
    erste = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))
    assert erste.ok
    # wiki_live faellt ohne Netz aus - wiki_lokal nicht.
    ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sonnensynchroner Orbit"}))
    assert ergebnis.ok and ergebnis.data["cache"] is True


def test_alle_drei_sind_read_und_brauchen_keine_bestaetigung():
    """Nachschlagen schreibt nichts - Vertrag 0.4.6."""
    from core.contracts import Permission

    for name in ("wiki_lokal", "wiki_live", "wikidata"):
        werkzeug = registry.get(name)
        assert werkzeug.permission is Permission.READ
        assert werkzeug.requires_confirmation is False


# --- Der Cache verfaellt (Verknuepfungspruefung, 30.08.2026) ---------------


def test_ein_zu_alter_treffer_kommt_nicht_aus_dem_cache(db):
    """`geholt_am` wurde geschrieben und NIE gelesen - der Cache hatte damit
    keine Verfallszeit.

    Das bricht DoD 4 aus docs/wissensquellen.md: "Eine Frage zu einem
    Ereignis nach dem Snapshot-Datum geht nachweislich auf wiki_live ueber,
    statt aus dem veralteten Stand zu antworten." Wenn wiki_live selbst aus
    einem Cache antwortet, der nie ablaeuft, ist der Uebergang wertlos.
    """
    from datetime import datetime, timedelta, timezone

    from core.db import session
    from core.wissen import Wissen, aus_cache, in_cache

    in_cache(db, Wissen(begriff="Bonn", titel="Bonn", text="Stadt am Rhein",
                        quelle="wiki_live", snapshot=None))

    # Frisch: kommt zurueck, egal welche Grenze.
    assert aus_cache(db, "Bonn", "wiki_live", max_alter_stunden=1) is not None
    assert aus_cache(db, "Bonn", "wiki_live") is not None

    # Den Eintrag kuenstlich altern lassen - ueber die Spalte, die frueher
    # nur beschrieben wurde.
    alt = (datetime.now(timezone.utc) - timedelta(hours=30)).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    with session(db) as conn:
        conn.execute("UPDATE lookups SET geholt_am = ? WHERE begriff = ?",
                     (alt, "bonn"))

    assert aus_cache(db, "Bonn", "wiki_live", max_alter_stunden=24) is None
    # Ohne Grenze weiterhin da - das alte Verhalten bleibt erreichbar.
    assert aus_cache(db, "Bonn", "wiki_live") is not None
    # Und mit einer grosszuegigen Grenze auch.
    assert aus_cache(db, "Bonn", "wiki_live", max_alter_stunden=48) is not None


def test_die_zweite_identische_anfrage_trifft_den_cache_trotzdem(db):
    """Gegenprobe: die Verfallszeit darf DoD 6 nicht kaputtmachen ("Zweite
    identische Anfrage trifft den Cache, null neue Netzabfragen")."""
    from core.wissen import Wissen, aus_cache, in_cache

    in_cache(db, Wissen(begriff="Bonn", titel="Bonn", text="x",
                        quelle="wiki_live", snapshot=None))
    assert aus_cache(db, "Bonn", "wiki_live", max_alter_stunden=24) is not None


def test_die_voreinstellung_ist_endlich():
    """Eine Voreinstellung von 0 (nie verfallen) waere genau der Fehler, der
    hier behoben wurde - dann haette das Feld keinen Nutzen."""
    from core.config import Settings

    st = Settings(_env_file=None)
    assert st.wissen_cache_stunden > 0, "der Cache verfiele wieder nie"
    assert st.wissen_cache_stunden <= 24 * 7, st.wissen_cache_stunden


# --- Verknuepfungspruefung 31.08.2026, Fund 2 -------------------------------
#
# `_erster_treffer()` hat einen `ET.ParseError` zu `(None, "")` gemacht - dem
# gleichen Rueckgabewert wie "die Suche hat nichts gefunden". Der Aufrufer
# prueft nur `if pfad is None` und antwortete daraufhin mit `ok=True`,
# `data={'hits': 0}` und "Nichts zu X in der lokalen Kopie" - eine Aussage
# ueber den Inhalt der ZIM-Datei, obwohl die lokale Wikipedia nie befragt
# wurde. Geloggt wurde nichts, und `raise_for_status()` sieht nichts: der Fall
# tritt gerade bei HTTP 200 auf.
#
# Die Tests unten pruefen die URSACHE - dass eine nicht parsbare Antwort im
# Werkzeug als Fehlschlag ankommt und nicht als Leerstand - und halten
# daneben fest, dass ein echter Nulltreffer weiter `ok=True` bleibt.

# Eine Fehlerseite, wie ein Server sie ausliefert: HTML, nicht wohlgeformt
# (`<meta charset="utf-8">` bleibt offen). Genau daran scheitert ET.
KEINE_XML_ANTWORT = (
    '<!DOCTYPE html>\n'
    '<html lang="en"><head><meta charset="utf-8">'
    "<title>Content not found</title></head>"
    "<body><h1>Not Found</h1><p>No such book</p></body></html>"
)


def test_fund2_antwort_ohne_xml_ist_ein_fehlschlag_kein_leerstand(lokal, caplog):
    """kiwix antwortet 200 mit HTML - das darf nicht "steht nicht drin" heissen."""
    import logging

    KiwixAttrappe.statt_xml = KEINE_XML_ANTWORT
    with caplog.at_level(logging.WARNING, logger="jarvis"):
        ergebnis = run(run_tool("wiki_lokal", {"begriff": "Sentinel-2"}))

    assert ergebnis.ok is False, (
        f"wiki_lokal meldet {ergebnis.display!r} als Erfolg, obwohl die lokale "
        f"Kopie gar nicht befragt wurde."
    )
    assert "Nichts zu" not in (ergebnis.display or "")
    assert (ergebnis.data or {}).get("hits") != 0
    assert "WIKI_ZIM" in (ergebnis.error or ""), (
        "Die Meldung muss auf die wahrscheinliche Ursache zeigen - sonst "
        "unterscheidet sie sich fuer den Nutzer nicht von 'kennt den Begriff nicht'."
    )
    assert any("kein XML" in eintrag.message or "kein XML" in eintrag.getMessage()
               for eintrag in caplog.records), (
        "Ohne Log gibt es keinen Hinweis darauf, dass die lokale Wikipedia "
        "nie befragt wurde - weder fuer den Nutzer noch im Serverlog."
    )


def test_fund2_die_drei_lagen_sind_wieder_auseinanderzuhalten(lokal, db, monkeypatch):
    """'kennt den Begriff nicht', 'antwortet falsch', 'nicht erreichbar'.

    Drei verschiedene Lagen, drei verschiedene Antworten. Vorher fielen die
    ersten beiden zusammen.
    """
    KiwixAttrappe.leer = True
    kennt_es_nicht = run(run_tool("wiki_lokal", {"begriff": "Gibtesnicht"}))
    assert kennt_es_nicht.ok is True and kennt_es_nicht.data["hits"] == 0
    assert "Nichts zu" in kennt_es_nicht.display

    KiwixAttrappe.leer = False
    KiwixAttrappe.statt_xml = KEINE_XML_ANTWORT
    antwortet_falsch = run(run_tool("wiki_lokal", {"begriff": "Sentinel-2"}))
    assert antwortet_falsch.ok is False
    assert "kein XML" in antwortet_falsch.error

    KiwixAttrappe.statt_xml = None
    monkeypatch.setattr(lokal, "basis", "http://127.0.0.1:1", raising=False)
    nicht_erreichbar = run(run_tool("wiki_lokal", {"begriff": "Sentinel-2"}))
    assert nicht_erreichbar.ok is False
    assert "nicht erreichbar" in nicht_erreichbar.error

    assert len({kennt_es_nicht.display, antwortet_falsch.display,
                nicht_erreichbar.display}) == 3


def test_fund2_erster_treffer_verschluckt_den_parsefehler_nicht_mehr(lokal):
    """Direkt an der Ursache: die Hilfsfunktion selbst darf nicht schweigen.

    Wenn sie den Fehler wieder zu `(None, "")` macht, wird sie von execute()
    nicht mehr von einem leeren Suchergebnis unterschieden - egal, wie
    execute() danach umgebaut wird.
    """
    import xml.etree.ElementTree as ET

    with pytest.raises(ET.ParseError):
        lokal._erster_treffer(KEINE_XML_ANTWORT)

    # Wohlgeformtes RSS ohne Treffer bleibt ein leeres Ergebnis, kein Fehler.
    assert lokal._erster_treffer(
        "<rss version='2.0'><channel></channel></rss>") == (None, "")
