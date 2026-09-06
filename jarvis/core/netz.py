"""Zwei HTTP-Klienten, damit Anmeldedaten nicht ins Freie geraten.

FIX-03 Schritt 1b. Vorher baute jedes Werkzeug seinen eigenen
`httpx.AsyncClient` und setzte die Kopfzeilen von Hand. Das ging so lange gut,
wie niemand einen Fehler machte - und genau ein Fehler genuegte: `wiki_live`
setzte den Zielhost aus einem Modellparameter zusammen und schickte den
`Authorization`-Header damit an einen fremden Server (BUGS-01, `docs/FIX-03.md`
Schritt 0).

Die Sperre kann deshalb nicht an der einen Stelle sitzen, an der es passiert
ist. Sie sitzt am Klienten:

* `nach_draussen()` - fuer alles, dessen Ziel aus einem Modell, aus einem
  Suchtreffer oder aus fremdem Inhalt stammt. Dieser Klient **verweigert**
  jede Anfrage, die Anmeldedaten traegt. Nicht "entfernt sie stillschweigend":
  ein stiller Filter versteckt den Programmierfehler, statt ihn zu zeigen.
* `fuer_dienst(hosts)` - fuer einen festen Dienst, dem die Anmeldedaten
  gehoeren. Dieser Klient **verweigert** jede Anfrage an einen Host, der nicht
  in `hosts` steht. Ein Dienst-Klient, der ueberallhin darf, ist kein
  Dienst-Klient.

Beide Pruefungen laufen als `event_hook` und damit VOR dem Transport - auch
gegen einen `httpx.MockTransport` im Test. Was hier durchfaellt, hat das
Geraet nie verlassen.
"""

from __future__ import annotations

from typing import Any, Iterable

import httpx

# Kopfzeilen, die Anmeldedaten tragen koennen. Die Liste ist bewusst breiter
# als "Authorization": ein Cookie ist genauso ein Ausweis.
GEHEIME_KOEPFE = frozenset({
    "authorization",
    "proxy-authorization",
    "cookie",
    "x-api-key",
    "x-jarvis-token",
})


class AnmeldedatenNachDraussen(RuntimeError):
    """Ein Klient fuer fremde Ziele sollte Anmeldedaten mitschicken."""


class FalscherDienst(RuntimeError):
    """Ein Dienst-Klient sollte einen Host ansprechen, der ihm nicht gehoert."""


async def _keine_anmeldedaten(request: httpx.Request) -> None:
    verraten = sorted({
        name.lower() for name in request.headers.keys()
        if name.lower() in GEHEIME_KOEPFE
    })
    if verraten:
        raise AnmeldedatenNachDraussen(
            f"Anfrage an {request.url.host} traegt {', '.join(verraten)}. "
            "Dieser Klient geht nach draussen und darf keine Anmeldedaten "
            "mitschicken - benutze core.netz.fuer_dienst, wenn das Ziel "
            "wirklich der Dienst ist, dem sie gehoeren."
        )


def _nur_diese_hosts(erlaubt: frozenset[str]):
    async def pruefen(request: httpx.Request) -> None:
        host = (request.url.host or "").lower()
        if host not in erlaubt:
            raise FalscherDienst(
                f"Anfrage an {host!r}, erlaubt sind nur "
                f"{', '.join(sorted(erlaubt)) or 'keine'}. "
                "Ein Dienst-Klient spricht nur seinen eigenen Dienst an."
            )
    return pruefen


def nach_draussen(
    *,
    timeout: float,
    transport: httpx.AsyncBaseTransport | None = None,
    follow_redirects: bool = False,
    **weitere: Any,
) -> httpx.AsyncClient:
    """Klient fuer fremde Ziele. Traegt niemals Anmeldedaten.

    `follow_redirects` steht absichtlich auf False: wer einer Weiterleitung
    folgen will, prueft jede Station selbst (FIX-03 Schritt 2 Punkt 4).
    """
    return httpx.AsyncClient(
        timeout=timeout,
        transport=transport,
        follow_redirects=follow_redirects,
        event_hooks={"request": [_keine_anmeldedaten]},
        **weitere,
    )


def fuer_dienst(
    hosts: Iterable[str],
    *,
    timeout: float,
    transport: httpx.AsyncBaseTransport | None = None,
    follow_redirects: bool = False,
    **weitere: Any,
) -> httpx.AsyncClient:
    """Klient fuer einen festen Dienst. Darf Anmeldedaten tragen - aber nur dorthin.

    `hosts` sind Hostnamen ohne Schema und ohne Pfad, klein geschrieben.
    """
    erlaubt = frozenset(h.lower() for h in hosts)
    if not erlaubt:
        raise ValueError("Ein Dienst-Klient ohne erlaubte Hosts ergibt keinen Sinn.")
    return httpx.AsyncClient(
        timeout=timeout,
        transport=transport,
        follow_redirects=follow_redirects,
        event_hooks={"request": [_nur_diese_hosts(erlaubt)]},
        **weitere,
    )
