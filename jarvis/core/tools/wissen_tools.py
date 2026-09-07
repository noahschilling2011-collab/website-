"""Die drei Nachschlage-Werkzeuge aus `docs/wissensquellen.md`.

Reihenfolge im Research Agent: `wiki_lokal` -> bei Treffer fertig. Kein Treffer
oder Frage betrifft etwas nach dem Snapshot-Datum -> `wiki_live` -> erst dann
`web_search`. Von billig nach teuer, nicht umgekehrt.

**Alle Endpunkte sind nachgeschlagen, keiner geraten.** Woher sie stammen,
steht bei jedem Werkzeug im Docstring - so, wie `docs/wissensquellen.md`
Abschnitt 2 es verlangt.
"""

from __future__ import annotations

import json
import logging
import re
import time
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import replace
from pathlib import Path

import httpx

from core.contracts import Permission, Tool, ToolResult
from core.netz import fuer_dienst, nach_draussen
from core.tools.registry import register
from core.wissen import Wissen, aus_cache, in_cache, snapshot_aus_zimname

log = logging.getLogger("jarvis")

# Wikimedia verlangt einen aussagekraeftigen User-Agent mit Kontakt. Ohne den
# faellt man in die niedrigste Limitklasse.
# https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits
USER_AGENT_VORLAGE = "JARVIS/0.1 (persoenlicher Assistent; {kontakt})"

MAX_ZEICHEN = 1500      # Ein Artikel-Volltext frisst das Tokenbudget.

# Ausfallpruefung 07.09.2026. `MAX_ZEICHEN` deckelte bis dahin GENAU EIN Feld:
# den Fliesstext in `_antwort`. Alles andere, was in `display` landet, war
# offen - und `display` ist das, was core/tools/loop.py als `tool_result` in
# den Prompt zurueckgibt. Gemessen mit httpx.MockTransport:
#
#   wikidata, eine Zeile mit 5 MB Zellwert -> display 5.000.143 Zeichen
#   wiki_live, Treffer mit 100.000-Zeichen-Titel -> display 101.315 Zeichen
#   wiki_lokal, Suchtreffer mit langem <title> -> display 199.862 Zeichen
#
# Der Titel steht ueber `Wissen.herkunft` VOR dem gekappten Text und ging
# deshalb an der einzigen Grenze vorbei, die es gab. Ab jetzt hat jedes Stueck,
# das nach draussen geht, seinen eigenen Deckel - und der Rumpf der Antwort
# einen davor.
MAX_HERKUNFT = 200      # Titel + Snapshot + Quelle, die Zeile vor dem Text
MAX_ZEILEN = 10         # SPARQL-Ergebniszeilen im Prompt
MAX_SPALTEN = 20        # SPARQL-Spalten je Zeile
MAX_ZELLE = 300         # ein einzelner SPARQL-Wert
# Wie search.FetchUrl.MAX_BYTES: mehr laedt niemand, um einen Begriff
# nachzuschlagen. Gestroemt und beim Deckel abgebrochen - `antwort.content`
# haette die ganze Antwort erst in den Speicher geholt und danach gekappt.
MAX_ANTWORT_BYTES = 2_000_000


def _kappe(text: str, deckel: int) -> str:
    """Auf `deckel` Zeichen, mit sichtbarem Auslassungszeichen."""
    if len(text) <= deckel:
        return text
    return text[:deckel - 1] + "…"


async def _hole_begrenzt(
    client: httpx.AsyncClient,
    methode: str,
    url: str,
    **weitere,
) -> tuple[httpx.Response, bytes]:
    """Eine Anfrage, deren Rumpf bei `MAX_ANTWORT_BYTES` endet.

    Gibt (Antwort, Rumpf) zurueck. Bei allem ausser 2xx bleibt der Rumpf leer:
    der Text einer Fehlerseite gehoert weder in den Prompt noch in den
    Speicher. Dasselbe Vorgehen wie in `core/tools/search.hole_gepruefte_kette`.
    """
    async with client.stream(methode, url, **weitere) as antwort:
        if not (200 <= antwort.status_code < 300):
            return antwort, b""
        roh = bytearray()
        async for stueck in antwort.aiter_bytes():
            roh += stueck
            if len(roh) >= MAX_ANTWORT_BYTES:
                break
        return antwort, bytes(roh[:MAX_ANTWORT_BYTES])


def _als_text(antwort: httpx.Response, roh: bytes) -> str:
    """Bytes zu Text - ohne an einer krummen Zeichensatzangabe zu scheitern."""
    zeichensatz = antwort.charset_encoding or "utf-8"
    try:
        return roh.decode(zeichensatz, errors="replace")
    except LookupError:
        return roh.decode("utf-8", errors="replace")


def _zellwert(zeile: dict, spalte: str) -> str:
    """Ein SPARQL-Ergebniswert als Text - gekappt, und ohne Annahmen.

    Das Handbuch beschreibt jede Zelle als Objekt mit `type` und `value`. Hier
    stand deshalb `(z.get(s) or {}).get('value', '')` - und genau das flog mit
    `AttributeError`, sobald eine Zelle keine Zuordnung war. Eine Zahl oder
    eine Zeichenkette ist keine Katastrophe; sie wird genommen, wie sie ist.
    """
    zelle = zeile.get(spalte)
    if isinstance(zelle, dict):
        return _kappe(str(zelle.get("value", "")), MAX_ZELLE)
    if zelle is None:
        return ""
    return _kappe(str(zelle), MAX_ZELLE)


def _status_satz(antwort: httpx.Response, dienst: str, hinweis: str = "") -> str | None:
    """Ein Satz zum HTTP-Status - oder None, wenn die Antwort in Ordnung ist.

    Hier stand `raise_for_status()`. Das war bequem und falsch: httpx wirft
    dabei `HTTPStatusError`, und der Fangzweig darunter schrieb daraus
    "... nicht erreichbar (HTTPStatusError)". Nachgemessen am 07.09.2026 bekam
    Noah damit denselben Satz fuer vier verschiedene Lagen - HTTP 500, HTTP
    404, HTTP 429 und eine Weiterleitung -, und in dem Satz stand als einziges
    Unterscheidungsmerkmal der Klassenname einer fremden Bibliothek.

    Besonders schief war das beim 404: der Dienst LAEUFT, er kennt nur die
    Adresse nicht - bei kiwix-serve ist das der Normalfall eines falsch
    gesetzten WIKI_ZIM. "Nicht erreichbar" schickt Noah dann in die falsche
    Richtung.
    """
    code = antwort.status_code
    if 200 <= code < 300:
        return None
    zusatz = f" {hinweis.strip()}" if hinweis.strip() else ""
    if antwort.has_redirect_location:
        # nach_draussen/fuer_dienst folgen bewusst keiner Weiterleitung
        # (FIX-03 Schritt 2 Punkt 4). Also wird sie gemeldet, nicht verfolgt.
        return (f"{dienst} verweist auf eine andere Adresse (HTTP {code}). "
                "Weiterleitungen werden hier nicht blind verfolgt.")
    # Nur hier hilft `hinweis` wirklich: 404 heisst "das Buch kenne ich
    # nicht", 400 heisst "books.name fehlt oder passt nicht" - beides zeigt
    # auf dieselbe Einstellung. Bei 429 oder 503 waere derselbe Rat eine
    # falsche Faehrte, also steht er dort nicht.
    if code == 404:
        return f"{dienst} kennt diese Adresse nicht (HTTP 404).{zusatz}"
    if code == 400:
        return f"{dienst} hat die Anfrage nicht verstanden (HTTP 400).{zusatz}"
    if code >= 500:
        return f"{dienst} hat einen Serverfehler gemeldet (HTTP {code})."
    return f"{dienst} hat die Anfrage abgelehnt (HTTP {code})."


# FIX-03 Schritt 1a. `sprache` kommt aus dem MODELL. Frueher wurde sie in den
# Hostnamen interpoliert - "evil.com/" genuegte, und die Anfrage ging samt
# Authorization-Header an einen fremden Server.
#
# Die erste Reparatur (BUGS-01 Fund 6) pruefte den Code mit einem regulaeren
# Ausdruck. Das war zu schwach: "xx" besteht jeden BCP-47-Test und ergibt
# trotzdem einen Host, den niemand geprueft hat. Deshalb wird der Host jetzt
# gar nicht mehr zusammengesetzt, sondern nachgeschlagen. Steht der Code hier
# nicht, ist der Aufruf abgelehnt - nicht auf "de" zurueckgefallen. Ein
# unbekannter Sprachcode ist ein fehlgeschlagener Schritt, kein Anlass zum
# Raten.
#
# Die Liste ist absichtlich kurz und wird von Hand erweitert. Jeder Eintrag
# ist eine Wikipedia-Ausgabe, die es wirklich gibt; geraten wird hier nichts.
WIKI_HOSTS = {
    "de": "https://de.wikipedia.org",
    "en": "https://en.wikipedia.org",
    "fr": "https://fr.wikipedia.org",
    "es": "https://es.wikipedia.org",
    "it": "https://it.wikipedia.org",
    "nl": "https://nl.wikipedia.org",
    "pl": "https://pl.wikipedia.org",
    "pt": "https://pt.wikipedia.org",
    "ru": "https://ru.wikipedia.org",
    "sv": "https://sv.wikipedia.org",
    "ja": "https://ja.wikipedia.org",
    "zh": "https://zh.wikipedia.org",
}

# Genau die Hosts aus der Zuordnung - mehr darf der Klient von wiki_live nicht
# ansprechen, auch wenn sich jemand spaeter eine URL zusammenbaut.
WIKI_DIENST_HOSTS = frozenset(
    basis.removeprefix("https://") for basis in WIKI_HOSTS.values()
)


class _MitCache(Tool):
    db_path: Path | str = ""
    cache_an: bool = True
    # Stunden. 0 heisst "nie verfallen" - siehe core/config.py.
    cache_stunden: float = 24.0

    def _cache_pfad(self) -> Path | str | None:
        return self.db_path if str(self.db_path).strip() else None

    def _gecached(self, begriff: str, quelle: str) -> Wissen | None:
        pfad = self._cache_pfad()
        if not (self.cache_an and pfad):
            return None
        grenze = self.cache_stunden if self.cache_stunden > 0 else None
        return aus_cache(pfad, begriff, quelle, max_alter_stunden=grenze)

    def _merken(self, treffer: Wissen) -> None:
        """In den Cache - gekappt, und niemals leer.

        Zwei Regeln, beide an dieser einen Stelle statt in drei Werkzeugen:

        1. Ein Treffer OHNE Text kommt nicht in den Cache. Sonst antwortet
           die Zeile fuer die naechsten `cache_stunden` mit nichts, und zwar
           mit `ok=True` - der Cache haette einen Fehlschlag konserviert.
        2. Was hier hineingeht, ist schon gekappt. Vorher wanderten 5 MB
           Artikeltext in die lookups-Tabelle, obwohl davon nur 1.500 Zeichen
           je wieder herauskamen.
        """
        pfad = self._cache_pfad()
        if not (self.cache_an and pfad):
            return
        if not (treffer.text or "").strip():
            return
        in_cache(pfad, replace(
            treffer,
            titel=_kappe(treffer.titel, MAX_HERKUNFT),
            text=_kappe(treffer.text, MAX_ZEICHEN),
        ))

    @staticmethod
    def _antwort(treffer: Wissen, begonnen: float, aus_cache_: bool) -> ToolResult:
        # Gekappt wird hier NOCH einmal, obwohl `_merken` schon kappt: eine
        # Zeile, die vor dieser Grenze in den Cache geschrieben wurde, ist
        # noch da und ginge sonst ungekappt in den Prompt.
        text = _kappe(treffer.text, MAX_ZEICHEN)
        herkunft = _kappe(treffer.herkunft, MAX_HERKUNFT)
        hinweis = " (aus dem Cache)" if aus_cache_ else ""
        return ToolResult(
            ok=True,
            data={"titel": _kappe(treffer.titel, MAX_HERKUNFT),
                  "snapshot": treffer.snapshot,
                  "quelle": treffer.quelle, "cache": aus_cache_},
            display=f"[{herkunft}]{hinweis}\n{text}",
            sources=[_kappe(treffer.url or treffer.titel, MAX_HERKUNFT)],
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )

    @staticmethod
    def _unerwartet(dienst: str, begonnen: float) -> ToolResult:
        """Wohlgeformtes JSON, aber nicht in der Form, die die Doku nennt.

        Ausfallpruefung 07.09.2026: eine Antwort wie `{"pages": "abc"}` oder
        `{"results": {"bindings": ["x"]}}` lief in ein `.get()` auf einer
        Zeichenkette. Der `AttributeError` schlug bis in den Auffangzweig des
        Dispatchers durch, und Noah las "wiki_live ist mit einem Fehler
        ausgestiegen (AttributeError)". Das ist kein Satz, den er versteht,
        und er nennt eine Ausnahmeklasse statt eines Grundes.

        Der Fall ist kein Fehler DIESES Programms, sondern eine Gegenstelle,
        die sich nicht an ihre eigene Doku haelt - also gehoert er behandelt
        wie ein Timeout: ein Satz, ein Log, `ok=False`.
        """
        log.warning("%s: Antwort hat eine unerwartete Form", dienst)
        satz = (f"{dienst} hat anders geantwortet als erwartet - daraus "
                "laesst sich nichts ablesen.")
        return ToolResult(ok=False, error=satz, display=satz,
                          duration_ms=int((time.monotonic() - begonnen) * 1000))

    @staticmethod
    def _zu_gross(dienst: str, begonnen: float, rat: str) -> ToolResult:
        """Die Antwort hat den Deckel gerissen und ist deshalb unbrauchbar.

        Bei HTML macht ein Schnitt nichts kaputt - der Anfang eines Artikels
        bleibt lesbar. Bei JSON schon: eine in der Mitte abgeschnittene
        Antwort ist kein JSON mehr. Sie als "kein JSON geliefert" zu melden
        waere die falsche Faehrte; die Gegenstelle hat sauber geantwortet,
        nur zu viel.
        """
        grenze = MAX_ANTWORT_BYTES // 1_000_000
        log.warning("%s: Antwort ueber %s MB - abgebrochen", dienst, grenze)
        satz = (f"{dienst} hat mehr als {grenze} MB geschickt; so viel wird "
                f"hier nicht verarbeitet. {rat}")
        return ToolResult(ok=False, error=satz, display=satz,
                          duration_ms=int((time.monotonic() - begonnen) * 1000))


@register
class WikiLokal(_MitCache):
    """Kiwix-ZIM auf der eigenen Platte.

    Endpunkte aus der offiziellen kiwix-serve-Doku
    (https://kiwix-tools.readthedocs.io/en/latest/kiwix-serve.html):

        GET /search?pattern=…&books.name=…&format=xml&pageLength=…
        GET /content/ZIMNAME/PATH/IN/ZIMFILE

    `format` kennt laut Doku genau `html` und `xml` - kein JSON. Deshalb wird
    XML geparst und nicht auf ein JSON gehofft.

    Das Snapshot-Datum kommt aus dem ZIM-Namen (`_YYYY-MM`); dieses Format
    nennt die Doku bei der Option `--nodatealiases`.
    """

    name = "wiki_lokal"
    description = (
        "Schlaegt einen Begriff in der lokalen Wikipedia-Kopie nach - kein Netz, keine Kosten, kein Ratenlimit.\n"
        "Nimm es fuer: Stammwissen zu Begriffen, Personen, Orten; immer als ERSTEN Versuch, und nenne das Snapshot-Datum aus dem Ergebnis.\n"
        "Nimm es NICHT fuer: Ereignisse nach dem Snapshot oder wenn hier nichts steht (dann wiki_live), nicht fuer eine blosse Zahl (das ist wikidata), nicht fuer Tagesaktuelles (das ist web_search).\n"
        "Beispiel: wiki_lokal(begriff=\"Sentinel-2\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "begriff": {"type": "string", "description": "Wonach nachgeschlagen wird."},
        },
        "required": ["begriff"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 5
    # Auch die lokale Kopie ist fremder Text: der Artikel im ZIM-Archiv
    # stammt aus Wikipedia, nicht von Noah.
    fremder_text = True

    basis: str = "http://127.0.0.1:8080"
    zim: str = ""
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, begriff: str) -> ToolResult:
        begonnen = time.monotonic()
        begriff = begriff.strip()
        if not begriff:
            return ToolResult(ok=False, error="Kein Begriff.", display="Kein Begriff.")
        if not self.zim:
            hinweis = ("Keine lokale Wikipedia eingerichtet. ZIM-Datei von "
                       "download.kiwix.org holen, kiwix-serve starten und "
                       "WIKI_ZIM setzen.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)

        gecached = self._gecached(begriff, "wiki_lokal")
        if gecached is not None:
            return self._antwort(gecached, begonnen, True)

        snapshot = snapshot_aus_zimname(self.zim)
        # Fuer beide Ausgaenge derselbe Hinweis: kiwix-serve antwortet, kennt
        # das Buch aber nicht - das ist der Normalfall eines falschen WIKI_ZIM
        # und hat mit "nicht erreichbar" nichts zu tun.
        ZIM_HINWEIS = "Stimmt WIKI_ZIM, und ist die ZIM-Datei geladen?"
        try:
            # kiwix-serve laeuft lokal und will keine Anmeldedaten. Der
            # Klient nach draussen stellt sicher, dass auch keine mitgehen.
            async with nach_draussen(timeout=self.timeout_s,
                                     transport=self.transport) as client:
                suche, roh = await _hole_begrenzt(
                    client, "GET", f"{self.basis}/search",
                    params={"pattern": begriff, "books.name": self.zim,
                            "format": "xml", "pageLength": 3},
                )
                satz = _status_satz(suche, "Die lokale Wikipedia", ZIM_HINWEIS)
                if satz is not None:
                    log.warning("wiki_lokal: Suche -> HTTP %s", suche.status_code)
                    return ToolResult(ok=False, error=satz, display=satz,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                pfad, titel = self._erster_treffer(_als_text(suche, roh))
                if pfad is None:
                    return ToolResult(
                        ok=True, data={"hits": 0},
                        display=f"Nichts zu {begriff!r} in der lokalen Kopie"
                                + (f" (Stand {snapshot})." if snapshot else "."),
                        duration_ms=int((time.monotonic() - begonnen) * 1000),
                    )
                artikel, roh_artikel = await _hole_begrenzt(
                    client, "GET",
                    f"{self.basis}{pfad}" if pfad.startswith("/")
                    else f"{self.basis}/{pfad}",
                )
                satz = _status_satz(artikel, "Die lokale Wikipedia", ZIM_HINWEIS)
                if satz is not None:
                    log.warning("wiki_lokal: Artikel -> HTTP %s", artikel.status_code)
                    return ToolResult(ok=False, error=satz, display=satz,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                text = self._nur_text(_als_text(artikel, roh_artikel))
        except ET.ParseError as exc:
            # Verknuepfungspruefung 31.08.2026, Fund 2. "nicht erreichbar",
            # "antwortet falsch" und "kennt den Begriff nicht" sind drei
            # verschiedene Lagen und muessen drei verschiedene Antworten
            # geben. Vorher war die mittlere von der letzten nicht zu
            # unterscheiden - und stand in keinem Log.
            #
            # `ok=False` wie beim Fall "nicht eingerichtet" weiter oben
            # (fehlendes WIKI_ZIM): das Werkzeug hat nichts nachgeschlagen,
            # also darf es nichts ueber den Inhalt der Kopie behaupten.
            log.warning("wiki_lokal: kiwix-serve hat kein XML geliefert - %s", exc)
            fehler = "kiwix-serve hat kein XML geliefert - stimmt WIKI_ZIM?"
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except httpx.HTTPError as exc:
            fehler = f"kiwix-serve nicht erreichbar ({exc.__class__.__name__})."
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        if not text.strip():
            # Die vierte Lage neben den dreien von Fund 2: die Suche hat einen
            # Treffer, der Artikel dahinter ist leer. Vorher kam dafuer
            # `ok=True` mit einer Herkunftszeile und NICHTS dahinter - und
            # dieses Nichts wanderte in den Cache und wurde von dort fuer
            # Stunden weitergereicht. Eine kaputte oder halb entpackte
            # ZIM-Datei sieht genau so aus.
            log.warning("wiki_lokal: Treffer %r hat keinen Text", titel or begriff)
            satz = (f"Die lokale Kopie hat zu {begriff!r} einen Treffer, aber "
                    "keinen Text dazu. Stimmt WIKI_ZIM, und ist die ZIM-Datei "
                    "vollstaendig?")
            return ToolResult(ok=False, error=satz, display=satz,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        treffer = Wissen(begriff=begriff, titel=titel or begriff, text=text,
                         quelle="wiki_lokal", snapshot=snapshot, url=titel)
        self._merken(treffer)
        return self._antwort(treffer, begonnen, False)

    @staticmethod
    def _erster_treffer(xml_text: str) -> tuple[str | None, str]:
        """Die XML-Antwort ist ein OpenSearch-RSS. Erster `item` gewinnt.

        Wirft `ET.ParseError`, wenn die Antwort kein XML ist. Das ist Absicht -
        siehe den Fangzweig in `execute()`.
        """
        # Verknuepfungspruefung 31.08.2026, Fund 2: hier stand ein
        # `try/except ET.ParseError: return None, ""`.
        #
        # WAS WAR FALSCH: der Parsefehler wurde stillschweigend zum selben
        # Rueckgabewert wie "die Suche hat nichts gefunden".
        #
        # WARUM DAS FALSCH IST: der Aufrufer prueft nur `if pfad is None` und
        # antwortet daraufhin mit `ok=True`, `data={'hits': 0}` und "Nichts zu
        # X in der lokalen Kopie" - eine Aussage ueber den Inhalt der ZIM-Datei,
        # obwohl die lokale Wikipedia gar nicht befragt wurde. Ein falsch
        # gesetztes WIKI_ZIM, eine aeltere kiwix-Version oder ein Reverse Proxy
        # davor liefert genau das: HTTP 200 mit HTML statt XML.
        # Die Statuspruefung (`_status_satz`) faengt das nicht ab, denn der
        # Status ist 200 -
        # derselbe Fallstrick, den `core/kalender.py` (Zeile 394) fuer Abos
        # kennt: "Ein Abo, das eine Anmeldeseite ausliefert, kommt als HTTP
        # 200." Deshalb wird auch hier der Inhalt geprueft, nicht nur der
        # Status.
        baum = ET.fromstring(xml_text)
        for eintrag in baum.iter():
            marke = eintrag.tag.rsplit("}", 1)[-1]
            if marke != "item":
                continue
            link = titel = ""
            for kind in eintrag:
                k = kind.tag.rsplit("}", 1)[-1]
                if k == "link":
                    link = (kind.text or "").strip()
                elif k == "title":
                    titel = (kind.text or "").strip()
            if link:
                return link, titel
        return None, ""

    @staticmethod
    def _nur_text(html: str) -> str:
        ohne_skript = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
        text = re.sub(r"(?s)<[^>]+>", " ", ohne_skript)
        text = (text.replace("&nbsp;", " ").replace("&amp;", "&")
                    .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"'))
        return re.sub(r"\s+", " ", text).strip()


@register
class WikiLive(_MitCache):
    """Wikimedia REST API, fuer alles nach dem Snapshot-Datum.

    Endpunkt aus der MediaWiki-Doku
    (https://www.mediawiki.org/wiki/API:REST_API/Reference):

        GET <wiki-basis>/w/rest.php/v1/search/page?q=…&limit=…

    `<wiki-basis>` ist ein Wert aus `WIKI_HOSTS`, nie ein zusammengesetzter
    String - siehe den Kommentar dort.
        -> {"pages": [{"id", "key", "title", "excerpt", "description", …}]}

    **Nicht** auf `api.wikimedia.org/core/...` gebaut: das ist laut
    https://wikitech.wikimedia.org/wiki/API_Portal/Deprecation ab Juli 2026 in
    der Abkuendigung, und die Ersatzrouten sollen erst in der zweiten
    Jahreshaelfte 2026 angekuendigt werden. Die Abkuendigungstabelle nennt
    den Weg `<wiki-domain>/w/rest.php/v1/search/page` selbst als Entsprechung -
    genau diesen Weg.

    Ratenlimits laut https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits:
    500 Anfragen/Stunde und IP ohne Token, 5.000/Stunde mit persoenlichem
    Token. Ohne konformen User-Agent faellt man in die niedrigste Klasse.
    """

    name = "wiki_live"
    description = (
        "Schlaegt einen Begriff in der Online-Wikipedia nach: kurzer Anriss samt Artikel-URL.\n"
        "Nimm es fuer: was wiki_lokal nicht hatte oder was nach dessen Snapshot-Datum liegt; kostet ein Ratenlimit. Dabei faellt die Artikel-URL an - fuer mehr als den Anriss gib sie an fetch_url.\n"
        "Nimm es NICHT fuer: den ersten Versuch (der geht an wiki_lokal), nicht fuer Nachrichten oder Preise von heute (das ist web_search), nicht fuer einen Zahlenwert (das ist wikidata).\n"
        "Beispiel: wiki_live(begriff=\"Wikidata Query Service\", sprache=\"en\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "begriff": {"type": "string", "description": "Wonach nachgeschlagen wird."},
            "sprache": {"type": "string",
                        "description": "Sprachcode der Wikipedia, z. B. 'de' oder 'en'."},
        },
        "required": ["begriff"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 10
    # Der Auszug kommt woertlich aus dem Artikel.
    fremder_text = True

    kontakt: str = ""       # Pflicht laut User-Agent-Richtlinie
    token: str = ""         # optional, hebt 500/h auf 5.000/h
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, begriff: str, sprache: str = "de") -> ToolResult:
        begonnen = time.monotonic()
        begriff = begriff.strip()
        if not begriff:
            return ToolResult(ok=False, error="Kein Begriff.", display="Kein Begriff.")
        if not self.kontakt:
            hinweis = ("WIKI_KONTAKT fehlt. Die Wikimedia-Richtlinie verlangt "
                       "einen User-Agent mit Kontaktangabe - ohne den nicht "
                       "anfragen.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)

        sprache = (sprache or "de").strip().lower()
        basis = WIKI_HOSTS.get(sprache)
        if basis is None:
            hinweis = (f"{sprache!r} ist keine eingerichtete Wikipedia. "
                       f"Verfuegbar: {', '.join(sorted(WIKI_HOSTS))}.")
            return ToolResult(ok=False, error=hinweis, display=hinweis,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        schluessel = f"{sprache}:{begriff}"
        gecached = self._gecached(schluessel, "wiki_live")
        if gecached is not None:
            return self._antwort(gecached, begonnen, True)

        kopf = {"user-agent": USER_AGENT_VORLAGE.format(kontakt=self.kontakt),
                "accept": "application/json"}
        if self.token:
            kopf["authorization"] = f"Bearer {self.token}"

        try:
            # FIX-03 Schritt 1b: ein Dienst-Klient. Er traegt die Anmeldedaten -
            # und weist jeden Host ab, der nicht zu WIKI_HOSTS gehoert. Selbst
            # wenn hier jemand spaeter wieder eine URL zusammenbaut, geht der
            # Token nicht mit.
            async with fuer_dienst(WIKI_DIENST_HOSTS, timeout=self.timeout_s,
                                   transport=self.transport) as client:
                antwort, roh = await _hole_begrenzt(
                    client, "GET", f"{basis}/w/rest.php/v1/search/page",
                    params={"q": begriff, "limit": 3}, headers=kopf,
                )
                if antwort.status_code == 429:
                    warte = antwort.headers.get("retry-after", "")
                    # Ohne Retry-After stand hier "Retry-After: ?s" - eine
                    # Angabe, die es nicht gibt, in einem Satz, der so tut,
                    # als gaebe es sie. Fehlt sie, wird sie weggelassen.
                    wann = f" Es geht in {warte}s wieder." if warte.strip() else ""
                    hinweis = (f"Wikimedia-Ratenlimit erreicht (429).{wann} "
                               f"Ohne Token sind es 500 Anfragen pro Stunde.")
                    return ToolResult(ok=False, error=hinweis, display=hinweis,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                satz = _status_satz(antwort, "Wikipedia")
                if satz is not None:
                    log.warning("wiki_live: HTTP %s von %s.wikipedia.org",
                                antwort.status_code, sprache)
                    return ToolResult(ok=False, error=satz, display=satz,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                if len(roh) >= MAX_ANTWORT_BYTES:
                    return self._zu_gross("Wikipedia", begonnen,
                                          "Frag einen engeren Begriff ab.")
                daten = json.loads(roh)
        except httpx.HTTPError as exc:
            fehler = f"Wikipedia nicht erreichbar ({exc.__class__.__name__})."
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except ValueError:
            fehler = "Wikipedia hat kein JSON geliefert."
            return ToolResult(ok=False, error=fehler, display=fehler)

        if not isinstance(daten, dict):
            return self._unerwartet("Wikipedia", begonnen)
        seiten = daten.get("pages")
        if seiten is None:
            seiten = []
        if not isinstance(seiten, list):
            return self._unerwartet("Wikipedia", begonnen)
        if not seiten:
            return ToolResult(ok=True, data={"hits": 0},
                              display=f"Nichts zu {begriff!r} auf {sprache}.wikipedia.org.",
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        erste = seiten[0]
        if not isinstance(erste, dict):
            return self._unerwartet("Wikipedia", begonnen)
        # Gekappt wird VOR dem Zusammenbauen, nicht erst in `_antwort`: sonst
        # laeuft der regulaere Ausdruck unten ueber zwei Megabyte Auszug, und
        # der Titel steht ohnehin ausserhalb jeder Textgrenze.
        titel = _kappe(str(erste.get("title") or begriff), MAX_HERKUNFT)
        rumpf = _kappe(str(erste.get("description") or ""), MAX_ZEICHEN)
        auszug = re.sub(r"<[^>]+>", "",
                        _kappe(str(erste.get("excerpt") or ""), MAX_ZEICHEN))
        text = " — ".join(t for t in (rumpf, auszug) if t) or titel
        # NICHT `schluessel` nennen - so heisst oben der Cache-Schluessel
        # ("de:Orbit"). Wer den hier ueberschreibt, legt den Treffer unter dem
        # Wikipedia-Seitennamen ab, waehrend `_gecached` weiter unter
        # "de:Orbit" sucht: der Cache trifft nie mehr, und auffallen wuerde es
        # nur an einer hoeheren Rechnung.
        wegmarke = _kappe(str(erste.get("key") or titel), MAX_HERKUNFT)
        url = f"{basis}/wiki/{urllib.parse.quote(wegmarke)}"

        treffer = Wissen(begriff=schluessel, titel=titel, text=text,
                         quelle="wiki_live", snapshot=None, url=url)
        if rumpf or auszug:
            self._merken(treffer)
        else:
            # Ein Treffer ohne description UND ohne excerpt hat als Text nur
            # seinen eigenen Titel. Zurueckgegeben wird er trotzdem - der
            # Artikel gibt es, und seine URL ist der Anschluss fuer fetch_url.
            # Gemerkt wird er nicht: der Cache speichert `url` nicht, also
            # bliebe davon einen Tag lang der Begriff uebrig, der schon in der
            # Frage stand. Dasselbe Muster wie beim leeren ZIM-Artikel.
            log.info("wiki_live: %r hat weder description noch excerpt - "
                     "nicht gecacht", titel)
        return self._antwort(treffer, begonnen, False)


@register
class WikidataFrage(_MitCache):
    """Wikidata SPARQL - fuer eine Zahl statt eines Absatzes.

    Endpunkt aus dem Wikidata Query Service User Manual
    (https://www.mediawiki.org/wiki/Wikidata_Query_Service/User_Manual):

        POST https://query.wikidata.org/sparql
        Accept: application/sparql-results+json

    Dort dokumentierte Grenzen: harte Frist von 60 s je Abfrage, hoechstens
    5 parallele Abfragen je IP. Unser Timeout liegt darunter - eine Abfrage,
    die 60 s braucht, gehoert nicht in einen Chatzug.
    """

    name = "wikidata"
    description = (
        "Stellt eine SPARQL-Abfrage an Wikidata und gibt Ergebniszeilen zurueck, keinen Fliesstext.\n"
        "Nimm es fuer: einen harten Einzelwert - Einwohnerzahl, Gruendungsjahr, Hoehe, Datum; ist die Q-Nummer unbekannt, im SPARQL ueber rdfs:label filtern. Dabei faellt die blanke Zahl an; weitergerechnet wird damit in calculator, nie im Kopf.\n"
        "Nimm es NICHT fuer: Erklaerungen in Saetzen (das ist wiki_lokal), nicht fuer Koordinaten zu einem Satellitenbild (das macht find_place samt fertiger bbox).\n"
        "Beispiel: wikidata(sparql=\"SELECT ?e WHERE { wd:Q1055 wdt:P1082 ?e }\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "sparql": {"type": "string", "description": "Die vollstaendige SPARQL-Abfrage."},
        },
        "required": ["sparql"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 20
    # Labels und Beschreibungen aus Wikidata schreibt die Allgemeinheit.
    fremder_text = True

    kontakt: str = ""
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, sparql: str) -> ToolResult:
        begonnen = time.monotonic()
        sparql = sparql.strip()
        if not sparql:
            return ToolResult(ok=False, error="Keine Abfrage.", display="Keine Abfrage.")
        if not self.kontakt:
            hinweis = ("WIKI_KONTAKT fehlt. Der Query Service will einen "
                       "User-Agent mit Kontakt.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)

        try:
            async with fuer_dienst({"query.wikidata.org"}, timeout=self.timeout_s,
                                   transport=self.transport) as client:
                antwort, roh = await _hole_begrenzt(
                    client, "POST", "https://query.wikidata.org/sparql",
                    data={"query": sparql},
                    headers={"accept": "application/sparql-results+json",
                             "user-agent": USER_AGENT_VORLAGE.format(kontakt=self.kontakt)},
                )
                if antwort.status_code == 429:
                    warte = antwort.headers.get("retry-after", "")
                    wann = f" Es geht in {warte}s wieder." if warte.strip() else ""
                    hinweis = ("Wikidata drosselt (429)." + wann
                               + " Hoechstens 5 parallele Abfragen je IP.")
                    return ToolResult(ok=False, error=hinweis, display=hinweis,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                satz = _status_satz(antwort, "Wikidata")
                if satz is not None:
                    log.warning("wikidata: HTTP %s vom Query Service",
                                antwort.status_code)
                    return ToolResult(ok=False, error=satz, display=satz,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                if len(roh) >= MAX_ANTWORT_BYTES:
                    return self._zu_gross(
                        "Wikidata", begonnen,
                        "Schraenke die Abfrage ein, zum Beispiel mit LIMIT.")
                daten = json.loads(roh)
        except httpx.HTTPError as exc:
            fehler = f"Wikidata nicht erreichbar ({exc.__class__.__name__})."
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except ValueError:
            fehler = "Wikidata hat kein JSON geliefert."
            return ToolResult(ok=False, error=fehler, display=fehler)

        if not isinstance(daten, dict):
            return self._unerwartet("Wikidata", begonnen)
        ergebnisse = daten.get("results")
        if ergebnisse is not None and not isinstance(ergebnisse, dict):
            return self._unerwartet("Wikidata", begonnen)
        zeilen = (ergebnisse or {}).get("bindings") or []
        if not isinstance(zeilen, list):
            return self._unerwartet("Wikidata", begonnen)
        if not zeilen:
            return ToolResult(ok=True, data={"hits": 0},
                              display="Die Abfrage liefert keine Zeilen.",
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        gezeigt = [z for z in zeilen[:MAX_ZEILEN] if isinstance(z, dict)]
        if not gezeigt:
            return self._unerwartet("Wikidata", begonnen)

        kopf = daten.get("head")
        spalten = kopf.get("vars") if isinstance(kopf, dict) else None
        if not isinstance(spalten, list) or not spalten:
            spalten = list(gezeigt[0])
        spalten = [str(s) for s in spalten[:MAX_SPALTEN]]

        text = "\n".join(
            " · ".join(f"{s}={_zellwert(z, s)}" for s in spalten)
            for z in gezeigt
        )
        if len(zeilen) > len(gezeigt):
            # Ohne diesen Satz sieht das Modell zehn Zeilen und haelt sie fuer
            # alle. Bei 50.000 Treffern ist das der Unterschied zwischen einer
            # Antwort und einer falschen Antwort.
            text += (f"\n… {len(zeilen)} Zeilen insgesamt, "
                     f"{len(gezeigt)} davon gezeigt.")
        return ToolResult(
            ok=True,
            data={"hits": len(zeilen), "vars": spalten},
            display=f"[wikidata · query.wikidata.org]\n{_kappe(text, MAX_ZEICHEN)}",
            sources=["https://query.wikidata.org/sparql"],
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )

