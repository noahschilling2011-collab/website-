"""Zugangsschutz (0.4).

Jeder `/api/`-Request braucht `X-Jarvis-Token`. Auch lokal - sonst kann eine
beliebige Seite im Browser deinen Assistenten fernsteuern.

Wenn in der `.env` kein Token steht, wird beim Start einer gewuerfelt und ins
Log geschrieben. Der Schutz ist damit nie aus. Ein leerer Wert wuerde sonst
jeden Request ohne Header durchlassen - genau das Loch, das dieser Abschnitt
schliessen soll.
"""

from __future__ import annotations

import logging
import secrets

from fastapi import Header, HTTPException, Request

log = logging.getLogger("jarvis")


def ensure_token(configured: str) -> tuple[str, bool]:
    """Gibt (Token, wurde_gewuerfelt) zurueck.

    BUGS-01 Fund 3: HTTP-Header sind latin-1. Ein Token mit Zeichen, die
    darin nicht vorkommen, laesst sich per HTTP gar nicht senden - JARVIS
    startete damit klaglos und gab bei jedem Request 500. Besser gleich
    beim Start sagen, was los ist, als den Nutzer suchen zu lassen.
    """
    token = (configured or "").strip()
    if token:
        try:
            token.encode("latin-1")
        except UnicodeEncodeError as exc:
            raise ValueError(
                f"JARVIS_TOKEN enthaelt Zeichen, die in einen HTTP-Header nicht "
                f"hineinpassen ({exc.object[exc.start:exc.end]!r}). "
                f"Nimm Buchstaben, Ziffern und -._~ - zum Beispiel die Ausgabe von "
                f"`python -c \"import secrets; print(secrets.token_urlsafe(32))\"`."
            ) from exc
        if not token.isascii():
            # latin-1 geht durchs Protokoll, aber nicht durch jede Bibliothek:
            # httpx zum Beispiel weigert sich, so einen Header zu bauen.
            log.warning(
                "JARVIS_TOKEN enthaelt Nicht-ASCII-Zeichen. Das Protokoll "
                "vertraegt das, aber nicht jeder Client - httpx weigert sich. "
                "Sicherer sind Buchstaben, Ziffern und -._~"
            )
        return token, False
    return secrets.token_urlsafe(32), True


async def require_token(
    request: Request, x_jarvis_token: str | None = Header(default=None)
) -> None:
    erwartet: str = request.app.state.token
    # compare_digest statt ==: die Laufzeit von == verraet, wie viele Zeichen
    # gestimmt haben.
    # BUGS-01 Fund 3: compare_digest wirft bei einem str mit Nicht-ASCII
    # ("only ASCII strings"). Vorher wurde daraus HTTP 500 - und ein
    # JARVIS_TOKEN mit Umlaut in der .env legte damit JEDEN Request lahm.
    # Ueber Bytes verglichen bleibt der Vergleich zeitkonstant und vertraegt
    # jedes Zeichen.
    if x_jarvis_token is None or not secrets.compare_digest(
        x_jarvis_token.encode("utf-8"), erwartet.encode("utf-8")
    ):
        raise HTTPException(
            status_code=401,
            detail="Header X-Jarvis-Token fehlt oder stimmt nicht.",
        )
