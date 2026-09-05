"""Die drei Nachschlage-Werkzeuge aus `docs/wissensquellen.md`.

Reihenfolge im Research Agent: `wiki_lokal` -> bei Treffer fertig. Kein Treffer
oder Frage betrifft etwas nach dem Snapshot-Datum -> `wiki_live` -> erst dann
`web_search`. Von billig nach teuer, nicht umgekehrt.

**Alle Endpunkte sind nachgeschlagen, keiner geraten.** Woher sie stammen,
steht bei jedem Werkzeug im Docstring - so, wie `docs/wissensquellen.md`
Abschnitt 2 es verlangt.
"""

from __future__ import annotations

import logging
import re
import time
import urllib.parse
import xml.etree.ElementTree as ET
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
        pfad = self._cache_pfad()
        if self.cache_an and pfad:
            in_cache(pfad, treffer)

    @staticmethod
    def _antwort(treffer: Wissen, begonnen: float, aus_cache_: bool) -> ToolResult:
        text = treffer.text
        if len(text) > MAX_ZEICHEN:
            text = text[:MAX_ZEICHEN - 1] + "…"
        hinweis = " (aus dem Cache)" if aus_cache_ else ""
        return ToolResult(
            ok=True,
            data={"titel": treffer.titel, "snapshot": treffer.snapshot,
                  "quelle": treffer.quelle, "cache": aus_cache_},
            display=f"[{treffer.herkunft}]{hinweis}\n{text}",
            sources=[treffer.url or treffer.titel],
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )


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
        try:
            # kiwix-serve laeuft lokal und will keine Anmeldedaten. Der
            # Klient nach draussen stellt sicher, dass auch keine mitgehen.
            async with nach_draussen(timeout=self.timeout_s,
                                     transport=self.transport) as client:
                suche = await client.get(
                    f"{self.basis}/search",
                    params={"pattern": begriff, "books.name": self.zim,
                            "format": "xml", "pageLength": 3},
                )
                suche.raise_for_status()
                pfad, titel = self._erster_treffer(suche.text)
                if pfad is None:
                    return ToolResult(
                        ok=True, data={"hits": 0},
                        display=f"Nichts zu {begriff!r} in der lokalen Kopie"
                                + (f" (Stand {snapshot})." if snapshot else "."),
                        duration_ms=int((time.monotonic() - begonnen) * 1000),
                    )
                artikel = await client.get(f"{self.basis}{pfad}"
                                           if pfad.startswith("/")
                                           else f"{self.basis}/{pfad}")
                artikel.raise_for_status()
                text = self._nur_text(artikel.text)
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
        # `raise_for_status()` faengt das nicht ab, denn der Status ist 200 -
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
                antwort = await client.get(
                    f"{basis}/w/rest.php/v1/search/page",
                    params={"q": begriff, "limit": 3}, headers=kopf,
                )
                if antwort.status_code == 429:
                    warte = antwort.headers.get("retry-after", "?")
                    hinweis = (f"Wikimedia-Ratenlimit erreicht (429). "
                               f"Retry-After: {warte}s. Ohne Token sind es "
                               f"500 Anfragen pro Stunde.")
                    return ToolResult(ok=False, error=hinweis, display=hinweis)
                antwort.raise_for_status()
                daten = antwort.json()
        except httpx.HTTPError as exc:
            fehler = f"Wikipedia nicht erreichbar ({exc.__class__.__name__})."
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except ValueError:
            fehler = "Wikipedia hat kein JSON geliefert."
            return ToolResult(ok=False, error=fehler, display=fehler)

        seiten = daten.get("pages") or []
        if not seiten:
            return ToolResult(ok=True, data={"hits": 0},
                              display=f"Nichts zu {begriff!r} auf {sprache}.wikipedia.org.",
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        erste = seiten[0]
        titel = str(erste.get("title") or begriff)
        rumpf = str(erste.get("description") or "")
        auszug = re.sub(r"<[^>]+>", "", str(erste.get("excerpt") or ""))
        text = " — ".join(t for t in (rumpf, auszug) if t) or titel
        url = f"{basis}/wiki/{urllib.parse.quote(str(erste.get('key') or titel))}"

        treffer = Wissen(begriff=schluessel, titel=titel, text=text,
                         quelle="wiki_live", snapshot=None, url=url)
        self._merken(treffer)
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
                antwort = await client.post(
                    "https://query.wikidata.org/sparql",
                    data={"query": sparql},
                    headers={"accept": "application/sparql-results+json",
                             "user-agent": USER_AGENT_VORLAGE.format(kontakt=self.kontakt)},
                )
                if antwort.status_code == 429:
                    hinweis = "Wikidata drosselt (429). Hoechstens 5 parallele Abfragen je IP."
                    return ToolResult(ok=False, error=hinweis, display=hinweis)
                antwort.raise_for_status()
                daten = antwort.json()
        except httpx.HTTPError as exc:
            fehler = f"Wikidata nicht erreichbar ({exc.__class__.__name__})."
            return ToolResult(ok=False, error=fehler, display=fehler,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except ValueError:
            fehler = "Wikidata hat kein JSON geliefert."
            return ToolResult(ok=False, error=fehler, display=fehler)

        zeilen = (daten.get("results") or {}).get("bindings") or []
        if not zeilen:
            return ToolResult(ok=True, data={"hits": 0},
                              display="Die Abfrage liefert keine Zeilen.",
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        spalten = (daten.get("head") or {}).get("vars") or list(zeilen[0])
        text = "\n".join(
            " · ".join(f"{s}={(z.get(s) or {}).get('value', '')}" for s in spalten)
            for z in zeilen[:10]
        )
        return ToolResult(
            ok=True,
            data={"hits": len(zeilen), "vars": spalten},
            display=f"[wikidata · query.wikidata.org]\n{text}",
            sources=["https://query.wikidata.org/sparql"],
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )

