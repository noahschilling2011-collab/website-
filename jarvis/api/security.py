"""Zugangsschutz (0.4).

Jeder `/api/`-Request braucht `X-Jarvis-Token`. Auch lokal - sonst kann eine
beliebige Seite im Browser deinen Assistenten fernsteuern.

Wenn in der `.env` kein Token steht, wird beim Start einer gewuerfelt und ins
Log geschrieben. Der Schutz ist damit nie aus. Ein leerer Wert wuerde sonst
jeden Request ohne Header durchlassen - genau das Loch, das dieser Abschnitt
schliessen soll.
"""

from __future__ import annotations

import secrets

from fastapi import Header, HTTPException, Request


def ensure_token(configured: str) -> tuple[str, bool]:
    """Gibt (Token, wurde_gewuerfelt) zurueck."""
    token = (configured or "").strip()
    if token:
        return token, False
    return secrets.token_urlsafe(32), True


async def require_token(
    request: Request, x_jarvis_token: str | None = Header(default=None)
) -> None:
    erwartet: str = request.app.state.token
    # compare_digest statt ==: die Laufzeit von == verraet, wie viele Zeichen
    # gestimmt haben.
    if x_jarvis_token is None or not secrets.compare_digest(x_jarvis_token, erwartet):
        raise HTTPException(
            status_code=401,
            detail="Header X-Jarvis-Token fehlt oder stimmt nicht.",
        )
