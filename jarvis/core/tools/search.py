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

import time
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
