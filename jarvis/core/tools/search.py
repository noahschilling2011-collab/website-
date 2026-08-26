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

import ipaddress
import re
import socket
import time
import urllib.parse
from typing import Any

import httpx

from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register

BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"


async def brave_suche(
    query: str,
    *,
    api_key: str,
    count: int = 5,
    timeout: float = 15.0,
    transport: httpx.AsyncBaseTransport | None = None,
) -> list[dict[str, str]]:
    """Fragt Brave und gibt Treffer als {title, url, description} zurueck."""
    async with httpx.AsyncClient(timeout=timeout, transport=transport) as client:
        antwort = await client.get(
            BRAVE_URL,
            params={"q": query, "count": max(1, min(count, 20))},
            headers={
                "Accept": "application/json",
                "X-Subscription-Token": api_key,
            },
        )
    if antwort.status_code == 401:
        raise PermissionError("SEARCH_API_KEY wurde abgelehnt (401).")
    if antwort.status_code == 429:
        raise RuntimeError("Ratenlimit der Such-API erreicht (429).")
    antwort.raise_for_status()

    daten: dict[str, Any] = antwort.json()
    treffer = ((daten.get("web") or {}).get("results")) or []
    return [
        {
            "title": str(t.get("title", "")).strip(),
            "url": str(t.get("url", "")).strip(),
            "description": str(t.get("description", "")).strip(),
        }
        for t in treffer
        if isinstance(t, dict) and t.get("url")
    ]


@register
class WebSearch(Tool):
    name = "web_search"
    description = (
        "Sucht im Web und liefert Titel, URL und einen Auszug je Treffer. "
        "Benutze das fuer alles, was aktuell ist oder was du nicht sicher "
        "weisst. Jede Behauptung, die du daraus uebernimmst, belegst du mit "
        "der URL."
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
        except httpx.HTTPError as exc:
            return ToolResult(
                ok=False,
                error=f"Suche fehlgeschlagen: {exc}",
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
    return bool(
        ip.is_private or ip.is_loopback or ip.is_link_local
        or ip.is_multicast or ip.is_reserved or ip.is_unspecified
    )


# Ausdrueckliche Ausnahme fuer Tests, die einen eigenen Verlag auf 127.0.0.1
# hochfahren. Im Auslieferungszustand ist sie LEER - ein Test nagelt das fest.
# Sie steht hier und nicht in der Testdatei, damit sie im Produktivcode
# sichtbar bleibt: eine Sperre mit unsichtbarer Hintertuer ist keine Sperre.
ERLAUBT_INTERN: set[str] = set()


def oeffentliches_ziel(url: str) -> str | None:
    """Gibt den Ablehnungsgrund zurueck, oder None wenn die URL nach draussen zeigt."""
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


@register
class FetchUrl(Tool):
    name = "fetch_url"
    description = (
        "Holt eine Webseite und gibt ihren Text zurueck. Benutze das, um einen "
        "Suchtreffer wirklich zu lesen, statt dich auf den Auszug zu verlassen. "
        "Die URL muss aus einem Suchergebnis oder vom Nutzer stammen - rate "
        "keine URLs."
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

    # Mehr als das laedt niemand, um einen Text zu lesen - und es verhindert,
    # dass ein 200-MB-Download den Task auffrisst.
    MAX_BYTES = 2_000_000

    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, url: str, max_chars: int = 6000) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        grund = oeffentliches_ziel(url)
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
            async with httpx.AsyncClient(
                timeout=float(self.timeout_s),
                follow_redirects=True,
                max_redirects=5,
                transport=self.transport,
                headers={"user-agent": "JARVIS/0.1 (persoenlicher Assistent)"},
            ) as client:
                antwort = await client.get(url)
        except httpx.HTTPError as exc:
            return ToolResult(
                ok=False,
                error=f"Abruf fehlgeschlagen: {exc}",
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

        roh = antwort.content[: self.MAX_BYTES]
        typ = antwort.headers.get("content-type", "")
        try:
            inhalt = roh.decode(antwort.encoding or "utf-8", errors="replace")
        except (LookupError, UnicodeDecodeError):
            inhalt = roh.decode("utf-8", errors="replace")

        text = html_zu_text(inhalt) if "html" in typ.lower() else inhalt.strip()
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
