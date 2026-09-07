"""Websuche.

Anbieter: **Brave Search API**. Endpunkt, Header und Antwortform sind aus der
offiziellen Dokumentation uebernommen, nicht geraten:

    GET https://api.search.brave.com/res/v1/web/search?q=...
    Header: X-Subscription-Token: <SEARCH_API_KEY>
    Antwort: web.results[] mit .title, .url, .description

Ohne `SEARCH_API_KEY` in der `.env` meldet das Werkzeug das sauber, statt zu
tun als haette es gesucht.
"""

from __future__ import annotations

import asyncio
import ipaddress
import json
import re
import socket
import time
import urllib.parse
from itertools import islice
from typing import Any

import httpx

from core.fehlertexte import ohne_geheimnis
from core.contracts import Permission, Tool, ToolResult
from core.netz import nach_draussen
from core.tools.registry import register

BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"


# Was ein Treffer hoechstens beitragen darf. Titel und Auszug schreibt der
# Seitenbetreiber, und `display` geht unveraendert in den Prompt: ohne Deckel
# genuegt EIN Treffer mit einem Fuenf-Megabyte-Auszug, um das Kontextfenster
# zu fuellen. Gemessen an echten Brave-Antworten sind Auszuege rund 200
# Zeichen lang - diese Deckel schneiden im Alltag nichts ab.
MAX_TITEL = 200
MAX_AUSZUG = 500
# Eine Adresse wird NICHT gekuerzt - eine gekuerzte Adresse ist eine falsche
# Adresse. Ein Treffer mit einer laengeren faellt raus; `fetch_url` wuerde ihn
# ohnehin ablehnen (FetchUrl.MAX_URL_LAENGE, dieselbe Zahl).
MAX_TREFFER_URL = 2048
# Wie viel Antwort hier hoechstens gelesen wird. Wie gross die Antwort ist,
# entscheidet die Gegenseite - wie viel Speicher JARVIS dafuer ausgibt, nicht.
# `client.get` lud den ganzen Koerper, BEVOR irgendein Deckel greifen konnte;
# gemessen am 07.09.2026 gegen MockTransport liess ein 46-MB-Koerper den
# Speicher des Prozesses um 70 MB steigen, und nach oben war nichts offen.
#
# Die Zahl liegt ABSICHTLICH hoch: eine echte Brave-Antwort mit 20 Treffern
# hat einige Zehntel Megabyte, und die Deckel, die den Prompt schuetzen,
# sitzen weiter unten am einzelnen Treffer (MAX_TITEL, MAX_AUSZUG) und an der
# Trefferzahl. Eine grosse, aber brauchbare Antwort soll weiterhin fuenf
# Treffer ergeben und keinen Fehlschlag - das nageln
# `test_fuenfzigtausend_treffer_fluten_den_prompt_nicht` (4,5 MB) und
# `test_ein_einzelner_riesiger_auszug_fuellt_den_prompt_nicht` (5 MB) fest.
# Dieser Deckel beantwortet nur die andere Frage: wie viel Speicher eine
# Gegenseite JARVIS abverlangen kann, die gar nicht mehr aufhoert.
MAX_ANTWORT_BYTES = 16_000_000


def _kurz(wert: Any, deckel: int) -> str:
    text = str(wert).strip()
    return text if len(text) <= deckel else text[:deckel] + "…"


async def brave_suche(
    query: str,
    *,
    api_key: str,
    count: int = 5,
    timeout: float = 15.0,
    transport: httpx.AsyncBaseTransport | None = None,
) -> list[dict[str, str]]:
    """Fragt Brave und gibt Treffer als {title, url, description} zurueck.

    Hoechstens `count` Treffer, auch wenn die Gegenseite mehr schickt: der
    Parameter ist eine Bestellung, keine Zusicherung.
    """
    wieviele = max(1, min(count, 20))
    # Gestroemt und bei MAX_ANTWORT_BYTES abgebrochen - genauso wie
    # `hole_gepruefte_kette` es fuer Webseiten macht. Ein Fehlerstatus wird
    # dabei entschieden, BEVOR der Koerper gelesen wird: eine 200-MB-
    # Fehlerseite laedt niemand, nur um sie wegzuwerfen.
    roh = bytearray()
    async with httpx.AsyncClient(timeout=timeout, transport=transport) as client:
        async with client.stream(
            "GET",
            BRAVE_URL,
            params={"q": query, "count": wieviele},
            headers={
                "Accept": "application/json",
                "X-Subscription-Token": api_key,
            },
        ) as antwort:
            if antwort.status_code == 401:
                raise PermissionError("SEARCH_API_KEY wurde abgelehnt (401).")
            if antwort.status_code == 429:
                raise RuntimeError("Ratenlimit der Such-API erreicht (429).")
            antwort.raise_for_status()
            async for stueck in antwort.aiter_bytes():
                roh += stueck
                if len(roh) > MAX_ANTWORT_BYTES:
                    raise RuntimeError(
                        "Die Antwort der Such-API war unerwartet gross und "
                        "wurde nicht ausgewertet."
                    )

    # Eine Antwort mit Status 200 ist noch keine Antwort in der zugesagten
    # Form. Gemessen am 07.09.2026 gegen MockTransport flogen hier drei
    # Faelle ungebremst nach oben - leerer Koerper und kaputtes JSON als
    # JSONDecodeError, eine JSON-Liste statt eines Objekts als AttributeError.
    # Der Dispatcher hat sie zwar aufgefangen, aber Noah las dann
    # "web_search ist mit einem Fehler ausgestiegen" statt zu erfahren, dass
    # die Such-API Unsinn geschickt hat.
    try:
        daten: Any = json.loads(bytes(roh))
    except ValueError as exc:            # json.JSONDecodeError ist ein ValueError
        raise RuntimeError(
            "Die Such-API hat geantwortet, aber nicht lesbar."
        ) from exc
    if not isinstance(daten, dict):
        raise RuntimeError("Die Such-API hat geantwortet, aber nicht lesbar.")

    web = daten.get("web")
    treffer = (web.get("results") if isinstance(web, dict) else None) or []
    if not isinstance(treffer, list):
        treffer = []
    brauchbar = (
        t for t in treffer
        if isinstance(t, dict)
        and t.get("url")
        and len(str(t["url"]).strip()) <= MAX_TREFFER_URL
    )
    return [
        {
            "title": _kurz(t.get("title", ""), MAX_TITEL),
            "url": str(t["url"]).strip(),
            "description": _kurz(t.get("description", ""), MAX_AUSZUG),
        }
        for t in islice(brauchbar, wieviele)
    ]


@register
class WebSearch(Tool):
    name = "web_search"
    description = (
        "Sucht im Web und liefert je Treffer Titel, URL und Auszug.\n"
        "Nimm es fuer: Aktuelles - Nachrichten, Preise, Termine, Versionen - und alles, was in keiner Wikipedia steht. Dabei fallen die URLs an, die fetch_url danach braucht; jede uebernommene Behauptung belegst du mit der URL.\n"
        "Nimm es NICHT fuer: Stammwissen, das wiki_lokal umsonst hat, nicht fuer einen Enzyklopaedie-Artikel nach dem Snapshot-Datum (den holt wiki_live), nicht fuer etwas, das der Nutzer dir frueher gesagt hat (das findet recall).\n"
        "Beispiel: web_search(query=\"Sentinel-2 Ausfall Maerz 2026\", count=5)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Die Suchanfrage."},
            "count": {
                "type": "integer",
                "description": "Wie viele Treffer, 1 bis 10.",
                "minimum": 1,
                "maximum": 10,
            },
        },
        "required": ["query"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 20
    # Titel und Auszug der Treffer schreibt der jeweilige Seitenbetreiber.
    fremder_text = True

    # Wird beim Start aus den Settings gesetzt. Kein Modul-Import von config,
    # damit das Tool in Tests ohne Umgebung baubar bleibt.
    api_key: str = ""
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, query: str, count: int = 5) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        if not self.api_key:
            return ToolResult(
                ok=False,
                error="Kein SEARCH_API_KEY gesetzt.",
                display=(
                    "Websuche nicht eingerichtet: SEARCH_API_KEY fehlt in der "
                    ".env. Key gibt es bei api-dashboard.search.brave.com."
                ),
                duration_ms=dauer(),
            )

        try:
            treffer = await brave_suche(
                query,
                api_key=self.api_key,
                count=count,
                timeout=float(self.timeout_s),
                transport=self.transport,
            )
        except PermissionError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())
        except httpx.HTTPStatusError as exc:
            # Ein Server, der mit 500 antwortet, ist erreichbar - er ist nur
            # kaputt. Vorher stand hier fuer beide Faelle "war nicht
            # erreichbar"; das schickt Noah auf die Suche nach seinem
            # Anschluss, obwohl das Problem bei Brave liegt.
            satz = (
                f"Die Such-API antwortete mit HTTP {exc.response.status_code}."
            )
            return ToolResult(
                ok=False,
                error=ohne_geheimnis(exc, "Suche fehlgeschlagen", satz),
                display=satz,
                duration_ms=dauer(),
            )
        except httpx.HTTPError as exc:
            return ToolResult(
                ok=False,
                # httpx haengt die volle URL an - und die traegt bei Brave den
            # Suchbegriff in der Abfrage.
            error=ohne_geheimnis(exc, "Suche fehlgeschlagen"),
                display="Die Such-API war nicht erreichbar.",
                duration_ms=dauer(),
            )
        except RuntimeError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        if not treffer:
            return ToolResult(
                ok=True,
                data={"query": query, "results": []},
                display=f"Keine Treffer fuer {query!r}.",
                duration_ms=dauer(),
            )

        zeilen = [
            f"{i}. {t['title']}\n   {t['url']}\n   {t['description']}"
            for i, t in enumerate(treffer, 1)
        ]
        return ToolResult(
            ok=True,
            data={"query": query, "results": treffer},
            display="\n".join(zeilen),
            # Pflicht bei allem, was aus dem Netz kommt.
            sources=[t["url"] for t in treffer],
            duration_ms=dauer(),
        )


# --- Seiten holen ---------------------------------------------------------

# Bewusst klein gehalten: das ist kein HTML-Parser, sondern eine Notloesung,
# um aus einer Seite lesbaren Text zu machen. Ein echter Parser waere eine
# neue Abhaengigkeit, und der Stack ist festgelegt.
_SKRIPT_STIL = re.compile(
    r"<(script|style|noscript|svg|head)\b[^>]*>.*?</\1>",
    re.IGNORECASE | re.DOTALL,
)
_TAG = re.compile(r"<[^>]+>")
_LEERRAUM = re.compile(r"[ \t\r\f\v]+")
_ZEILEN = re.compile(r"\n{3,}")

ENTITAETEN = {
    "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"',
    "&#39;": "'", "&apos;": "'", "&euro;": "€", "&mdash;": "—", "&ndash;": "–",
}


# Woran man sieht, dass eine Antwort HTML ist, obwohl kein Kopf es sagt.
_SIEHT_NACH_HTML_AUS = re.compile(r"<\s*(!doctype\s+html|html|head|body|p|div|a)\b",
                                  re.IGNORECASE)

# Zeichen, die in einem Text nichts verloren haben: das Ersatzzeichen der
# Dekodierung und die Steuerzeichen ausser Tabulator, Zeilenumbruch,
# Wagenruecklauf.
_UNLESBAR = re.compile(r"[�\x00-\x08\x0b\x0c\x0e-\x1f]")

# Ab diesem Anteil ist das kein Text mehr, sondern eine Datei, die als Text
# ausgegeben wird. Gemessen: ein PNG-Rumpf liegt bei rund 50 %, ein deutscher
# Satz, dessen Kodierung falsch angesagt war ("Gruesse aus Muenchen" als
# latin-1 unter charset=utf-8), bei 18 %.
MAX_ANTEIL_UNLESBAR = 0.30


def sieht_lesbar_aus(text: str) -> bool:
    """Ist das Text - oder eine Binaerdatei, die durch die Dekodierung ging?"""
    if not text:
        return True
    probe = text[:4000]
    return len(_UNLESBAR.findall(probe)) / len(probe) <= MAX_ANTEIL_UNLESBAR


def html_zu_text(html: str) -> str:
    text = _SKRIPT_STIL.sub(" ", html)
    text = re.sub(r"<br\s*/?>|</p>|</div>|</li>|</tr>", "\n", text, flags=re.IGNORECASE)
    text = _TAG.sub(" ", text)
    for zeichen, ersatz in ENTITAETEN.items():
        text = text.replace(zeichen, ersatz)
    text = _LEERRAUM.sub(" ", text)
    text = "\n".join(zeile.strip() for zeile in text.split("\n"))
    return _ZEILEN.sub("\n\n", text).strip()


# --- SSRF-Sperre (BUGS-01 Fund 7) -----------------------------------------
#
# Die URL kommt aus dem MODELL. Ohne Sperre liest fetch_url alles, was der
# Server erreicht - localhost, das Heimnetz, die Metadaten-Adresse der Cloud -
# und der Inhalt landet anschliessend im Prompt. Das ist die Netzwerk-Variante
# von "kein eval mit Modelleingaben".
#
# Geprueft wird die aufgeloeste IP, nicht der Name: "meine-domain.de" kann auf
# 127.0.0.1 zeigen.

ERLAUBTE_SCHEMATA = ("http", "https")


def _ist_intern(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """Alles, was nicht oeffentlich routbar ist.

    FIX-03 Schritt 2 Punkt 3 verlangt `is_global`, mit der Begruendung, das
    decke Loopback, privat, Link-Local, reserviert UND Multicast in einer
    Pruefung ab. Nachgemessen mit Pythons `ipaddress` stimmt das so nicht:

        Adresse                 not is_global   is_private
        169.254.169.254                  True         True   <- beide fangen sie
        100.64.0.1                       True        False   <- nur is_global
        224.0.0.1                       False        False   <- KEINE von beiden
        ff02::1                         False        False   <- KEINE von beiden

    Zwei Korrekturen an der Vorlage, beide gemessen:

    * `is_private` allein vergisst die Metadaten-Adresse NICHT - in Python
      gehoert Link-Local zu den privaten Bereichen. Der Warnhinweis aus FIX-03
      trifft andere Sprachen, nicht diese.
    * `is_global` allein laesst dafuer MULTICAST durch. Wer hier nur auf
      `is_global` umstellt, macht die Sperre schwaecher als vorher.

    Deshalb beides: `is_global` bringt die CGNAT-Bereiche dazu, die
    Einzelpruefungen behalten Multicast. Eine Sperre, die man vereinfacht,
    ohne sie zu messen, wird leiser - nicht besser.

    IPv4-in-IPv6 (`::ffff:127.0.0.1`) braucht hier KEIN eigenes Auspacken.
    Nachgemessen auf Python 3.11.15 beantworten alle benutzten Praedikate die
    verpackte Adresse genauso wie die blanke - `::ffff:224.0.0.1` meldet sogar
    `is_multicast=True`. Ein Zweig, der nie ausloest, laesst sich nicht
    pruefen; deshalb steht er nicht hier, sondern als Annahme in
    `test_schritt2_verpackte_und_blanke_adressen_werden_gleich_beurteilt`.
    Faellt der Test auf einer neuen Python-Version, gehoert das Auspacken
    zurueck.
    """
    return bool(
        not ip.is_global
        or ip.is_private or ip.is_loopback or ip.is_link_local
        or ip.is_multicast or ip.is_reserved or ip.is_unspecified
    )


# Ausdrueckliche Ausnahme fuer Tests, die einen eigenen Verlag auf 127.0.0.1
# hochfahren. Im Auslieferungszustand ist sie LEER - ein Test nagelt das fest.
# Sie steht hier und nicht in der Testdatei, damit sie im Produktivcode
# sichtbar bleibt: eine Sperre mit unsichtbarer Hintertuer ist keine Sperre.
ERLAUBT_INTERN: set[str] = set()


def oeffentliches_ziel(url: str) -> str | None:
    """Gibt den Ablehnungsgrund zurueck, oder None wenn die URL nach draussen zeigt.

    BEKANNTE GRENZE, die hier NICHT geschlossen wird (FIX-03 Schritt 2):
    zwischen dem Aufloesen des Namens hier und dem Verbinden gleich danach
    kann derselbe Name auf eine andere Adresse zeigen - DNS rebinding, in der
    Literatur TOCTOU. Vollstaendig schliessen liesse sich das nur, indem man
    direkt auf die gepruefte Adresse verbindet und den Namen nur noch im
    Host-Header fuehrt. Das steht hier bewusst offen und ist kein Versehen:
    wer es schliessen will, faengt an dieser Stelle an.
    """
    try:
        teile = urllib.parse.urlparse(url)
    except ValueError as exc:
        return f"URL nicht lesbar ({exc})."
    if teile.scheme not in ERLAUBTE_SCHEMATA:
        return f"Nur http(s), bekam {teile.scheme or 'nichts'!r}."
    if not teile.hostname:
        return "Kein Hostname in der URL."

    name = teile.hostname
    if f"{name}:{teile.port}" in ERLAUBT_INTERN or name in ERLAUBT_INTERN:
        return None
    try:
        infos = socket.getaddrinfo(name, teile.port or (443 if teile.scheme == "https" else 80),
                                   proto=socket.IPPROTO_TCP)
    except socket.gaierror as exc:
        return f"Name nicht aufloesbar ({exc})."

    for eintrag in infos:
        roh = eintrag[4][0]
        try:
            ip = ipaddress.ip_address(roh)
        except ValueError:
            return f"Adresse nicht lesbar: {roh!r}."
        if _ist_intern(ip):
            return (f"{name} zeigt auf {ip} - das ist das eigene Netz. "
                    f"JARVIS holt nur oeffentliche Adressen.")
    return None


async def ziel_geprueft(url: str) -> str | None:
    """`oeffentliches_ziel`, ohne die Ereignisschleife anzuhalten.

    `socket.getaddrinfo` ist eine BLOCKIERENDE Auskunft. Steht der DNS-Server
    nicht zur Verfuegung - der Fall "ein Dienst fehlt" -, wartet sie mehrere
    Sekunden, und zwar im Faden der Ereignisschleife. Gemessen am 07.09.2026
    mit einer Aufloesung, die drei Sekunden braucht:

        Werkzeug-Timeout 1 s -> Aufruf dauerte 3,00 s
        Ticks einer nebenher laufenden Aufgabe waehrend des Abrufs: 0

    Beides ist schlimm. Der Deckel des Dispatchers (`asyncio.wait_for`) greift
    nicht, weil er nur zwischen zwei await-Punkten schneiden kann - und der
    ganze Server steht so lange still: keine zweite Anfrage, kein
    Lebenszeichen, kein Abbruchknopf. Bei einer Kette aus fuenf Stationen
    fuenfmal hintereinander.

    Im Arbeitsfaden wartet weiterhin jemand - aber nur der Faden. Die Schleife
    laeuft, der Timeout schneidet, und der Faden endet von selbst, wenn der
    Resolver aufgibt.

    Der Name wird ABSICHTLICH erst hier nachgeschlagen: Tests ersetzen
    `oeffentliches_ziel` im Modul, und das soll wirken.
    """
    return await asyncio.to_thread(oeffentliches_ziel, url)


# FIX-03 Schritt 2 Punkt 4. Eine Weiterleitung auf 127.0.0.1 ist der
# Standardweg um eine Eingangspruefung herum: geprueft wird die URL, die das
# Modell nennt - geholt wird, worauf der fremde Server zeigt. Deshalb folgt
# hier niemand automatisch. Jede Station wird einzeln geprueft.
WEITERLEITUNGEN = frozenset({301, 302, 303, 307, 308})
MAX_STATIONEN = 5

# Eine Verlagsseite, aus der nur das og:image gelesen wird, braucht keine
# zwei Megabyte. Der Kopfbereich reicht.
MAX_BILD_BYTES = 500_000


class ZielVerboten(Exception):
    """Eine Station der Kette zeigt nicht nach draussen."""


async def hole_gepruefte_kette(
    client: httpx.AsyncClient,
    url: str,
    *,
    max_bytes: int,
) -> tuple[httpx.Response, bytes, list[str]]:
    """Holt `url` und folgt Weiterleitungen VON HAND, mit Pruefung je Station.

    Gibt (letzte Antwort, Rumpf bis `max_bytes`, alle Stationen) zurueck.
    Wirft `ZielVerboten`, sobald eine Station nicht nach draussen zeigt oder
    die Kette zu lang wird.

    Der Rumpf wird gestroemt und beim Deckel abgebrochen - `antwort.content`
    haette die ganze Datei erst geladen und danach abgeschnitten.
    """
    stationen: list[str] = []
    ziel = url
    for nummer in range(1, MAX_STATIONEN + 2):
        grund = await ziel_geprueft(ziel)
        # Die Adresse einer Station schreibt der fremde Server in seinen
        # location-Kopf, und dieser Text landet als `error` in der Datenbank,
        # in /api/tool-calls und in der Oberflaeche. Gemessen am 07.09.2026:
        # eine Weiterleitung auf eine 60.000 Zeichen lange Adresse ergab eine
        # 60.097 Zeichen lange Fehlermeldung. Dieselbe Grenze wie bei einer
        # Trefferadresse - laenger ist keine Adresse mehr, sondern Fracht.
        if grund is not None:
            raise ZielVerboten(
                f"Station {nummer} ({_kurz(ziel, MAX_TREFFER_URL)}): {grund}"
            )
        if nummer > MAX_STATIONEN:
            raise ZielVerboten(
                f"Mehr als {MAX_STATIONEN} Weiterleitungen ab "
                f"{_kurz(url, MAX_TREFFER_URL)} - Station {nummer} waere "
                f"{_kurz(ziel, MAX_TREFFER_URL)}."
            )
        stationen.append(ziel)

        async with client.stream("GET", ziel) as antwort:
            ort = antwort.headers.get("location")
            if antwort.status_code in WEITERLEITUNGEN and ort:
                # Der Rumpf einer Weiterleitung interessiert niemanden und
                # wird bewusst nicht gelesen.
                ziel = str(antwort.url.join(ort))
                continue
            roh = bytearray()
            async for stueck in antwort.aiter_bytes():
                roh += stueck
                if len(roh) >= max_bytes:
                    break
            return antwort, bytes(roh[:max_bytes]), stationen

    raise ZielVerboten(
        f"Weiterleitungskette ab {_kurz(url, MAX_TREFFER_URL)} endet nicht."
    )


@register
class FetchUrl(Tool):
    name = "fetch_url"
    description = (
        "Holt eine Webseite und gibt ihren Text zurueck.\n"
        "Nimm es fuer: einen Treffer wirklich lesen statt nur den Auszug. Du brauchst dafuer eine volle URL - die liefert dir web_search oder wiki_live, oder der Nutzer nennt sie; rate nie eine URL.\n"
        "Nimm es NICHT fuer: eine Frage, zu der du noch keine URL hast (erst web_search), nicht zum Nachschlagen eines Begriffs (das ist wiki_lokal).\n"
        "Beispiel: fetch_url(url=\"https://www.esa.int/Applications/Observing_the_Earth\", max_chars=6000)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "url": {"type": "string", "description": "Vollstaendige http(s)-URL."},
            "max_chars": {
                "type": "integer",
                "description": "Wie viel Text hoechstens, 500 bis 20000.",
                "minimum": 500,
                "maximum": 20000,
            },
        },
        "required": ["url"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 20
    # Der reine Fall: der Text einer fremden Webseite.
    fremder_text = True

    # Mehr als das laedt niemand, um einen Text zu lesen - und es verhindert,
    # dass ein 200-MB-Download den Task auffrisst.
    MAX_BYTES = 2_000_000

    # FIX-11 Punkt 6. Eine Adresse ist ein Wegweiser, kein Frachtraum. Wer
    # Daten aus dem Rechner schaffen will, haengt sie an die Abfrage
    # ("...?d=<halbe Steuerakte>") - dagegen hilft die Herkunftspruefung in
    # core/tools/loop.py, aber sie greift nur dort, wo eine Schleife laeuft.
    # Diese Grenze steht im Werkzeug selbst und gilt damit auf JEDEM Weg,
    # auch bei einem direkten `run_tool("fetch_url", ...)`. 2.048 Zeichen
    # sind grosszuegig: die laengste Adresse in diesem Projekt hat 76.
    MAX_URL_LAENGE = 2048

    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, url: str, max_chars: int = 6000) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        # Vor der Namensaufloesung: eine 100.000-Zeichen-Adresse soll nicht
        # erst noch durch DNS gehen.
        if len(url) > self.MAX_URL_LAENGE:
            satz = (
                f"Die Adresse ist zu lang: {len(url)} Zeichen, erlaubt sind "
                f"{self.MAX_URL_LAENGE}."
            )
            # Ohne die Adresse selbst - sie IST hier das Problem.
            return ToolResult(ok=False, error=satz, display=satz,
                              duration_ms=dauer())

        grund = await ziel_geprueft(url)
        if grund is not None:
            return ToolResult(
                ok=False,
                error=grund,
                display=grund,
                duration_ms=dauer(),
            )

        if not url.lower().startswith(("http://", "https://")):
            return ToolResult(
                ok=False,
                error=f"Nur http(s)-URLs, bekam {url!r}.",
                display=f"{url!r} ist keine abrufbare Adresse.",
                duration_ms=dauer(),
            )

        try:
            # nach_draussen: dieser Klient darf grundsaetzlich keine
            # Anmeldedaten tragen (FIX-03 Schritt 1b) und folgt keiner
            # Weiterleitung von selbst (Schritt 2 Punkt 4).
            async with nach_draussen(
                timeout=float(self.timeout_s),
                transport=self.transport,
                headers={"user-agent": "JARVIS/0.1 (persoenlicher Assistent)"},
            ) as client:
                antwort, roh, stationen = await hole_gepruefte_kette(
                    client, url, max_bytes=self.MAX_BYTES
                )
        except ZielVerboten as exc:
            return ToolResult(
                ok=False,
                error=str(exc),
                # Die URL bleibt: sie kommt vom Modell, es hat sie selbst
            # genannt. Der Ausnahmetext geht - httpx haengt dort die
            # aufgeloeste Adresse an, samt Weiterleitungszielen.
            display=f"{url}: " + ohne_geheimnis(exc, "wurde nicht geholt"),
                duration_ms=dauer(),
            )
        except httpx.HTTPError as exc:
            return ToolResult(
                ok=False,
                error=ohne_geheimnis(exc, "Abruf fehlgeschlagen"),
                display=f"{url} war nicht erreichbar.",
                duration_ms=dauer(),
            )

        if antwort.status_code >= 400:
            return ToolResult(
                ok=False,
                error=f"HTTP {antwort.status_code} von {url}.",
                display=f"{url} antwortete mit HTTP {antwort.status_code}.",
                duration_ms=dauer(),
            )

        typ = antwort.headers.get("content-type", "")
        try:
            inhalt = roh.decode(antwort.encoding or "utf-8", errors="replace")
        except (LookupError, UnicodeDecodeError):
            inhalt = roh.decode("utf-8", errors="replace")

        # Ohne Content-Type entscheidet der Inhalt. Vorher ging eine Antwort
        # ohne Kopf ungefiltert durch, und der Prompt bekam den rohen
        # HTML-Quelltext samt Skript-Bloecken statt des Seitentextes.
        ist_html = "html" in typ.lower() or (
            not typ.strip() and bool(_SIEHT_NACH_HTML_AUS.search(inhalt[:2000]))
        )
        text = html_zu_text(inhalt) if ist_html else inhalt.strip()

        # Ein Bild, ein PDF, ein Zip: dekodiert wird daraus eine Wand aus
        # Ersatzzeichen, und die ging vorher als ok=True in den Prompt
        # (gemessen: 2.048 Zeichen Muell aus einer 2-KB-PNG-Attrappe). Das
        # ist kein Ergebnis, das ist ein Fehlschlag mit Deckmantel.
        if not sieht_lesbar_aus(text):
            return ToolResult(
                ok=False,
                error="Die Antwort war kein lesbarer Text.",
                display=(
                    f"{url} lieferte keinen lesbaren Text, sondern eine Datei "
                    f"(Content-Type: {typ or 'unbekannt'}). fetch_url liest "
                    "nur Seiten und Textdateien."
                ),
                sources=[str(antwort.url)],
                duration_ms=dauer(),
            )

        gekuerzt = len(text) > max_chars
        if gekuerzt:
            text = text[:max_chars] + "\n\n[…gekuerzt]"

        if not text:
            return ToolResult(
                ok=False,
                error="Die Seite enthielt keinen lesbaren Text.",
                display=f"{url} lieferte keinen Text (Content-Type: {typ or 'unbekannt'}).",
                sources=[str(antwort.url)],
                duration_ms=dauer(),
            )

        return ToolResult(
            ok=True,
            data={"url": str(antwort.url), "content_type": typ,
                  "chars": len(text), "truncated": gekuerzt},
            display=text,
            sources=[str(antwort.url)],
            duration_ms=dauer(),
        )
