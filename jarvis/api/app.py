"""Anwendungsfabrik.

`create_app()` liest die Konfiguration beim Aufruf, nicht beim Import. Tests
koennen dadurch eine eigene `Settings` uebergeben, ohne das Modul neu zu laden.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from api.routes import api, router
from api.security import ensure_token
from core.config import PROJECT_ROOT, Settings, get_settings
from core.db import connect, init_db
from core.llm import LLMError, LLMProvider, build_provider

log = logging.getLogger("jarvis")

INDEX_PATH = PROJECT_ROOT / "index.html"

# Ein Einrichtungsfehler ist kein Fehler des Anbieters. Er bekommt einen
# eigenen Status, damit die Oberflaeche "richte das ein" sagen kann statt
# "der Anbieter spinnt".
STATUS_BY_KIND = {
    "missing_api_key": 503,
    "missing_model": 503,
    "unknown_provider": 503,
}


class UnavailableProvider(LLMProvider):
    """Platzhalter, wenn der Anbieter nicht gebaut werden konnte.

    Damit startet JARVIS trotzdem. Ein fehlender Key ist ein
    Einrichtungsfehler - der Nutzer soll die Oberflaeche oeffnen und dort
    lesen koennen, was fehlt, statt einen Stacktrace im Terminal zu bekommen.
    """

    def __init__(self, error: LLMError, *, name: str, model: str) -> None:
        self.error = error
        self.name = name or "nicht eingerichtet"
        self.model = model or "—"

    @property
    def reason(self) -> str:
        return str(self.error)

    async def complete(self, messages, *, system):  # noqa: ANN001, ANN201
        raise self.error


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        conn = connect(settings.db_path)
        try:
            init_db(conn)
        finally:
            conn.close()

        try:
            app.state.provider = build_provider(settings)
        except LLMError as exc:
            log.error("Anbieter nicht verfuegbar - %s", exc)
            app.state.provider = UnavailableProvider(
                exc, name=settings.llm_provider, model=settings.llm_model
            )

        log.info(
            "JARVIS bereit - Anbieter %s, Modell %s, Datenbank %s",
            app.state.provider.name,
            app.state.provider.model,
            settings.db_path,
        )
        if app.state.token_generated:
            log.warning(
                "JARVIS_TOKEN war leer. Fuer diesen Lauf gewuerfelt: %s\n"
                "Trag ihn in die .env ein, sonst aendert er sich bei jedem Start.",
                app.state.token,
            )
        try:
            yield
        finally:
            await app.state.provider.aclose()

    app = FastAPI(
        title="JARVIS",
        description="Persoenliches AI-Operating-System. Phase 1: Walking Skeleton.",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.index_path = INDEX_PATH
    app.state.token, app.state.token_generated = ensure_token(settings.jarvis_token)

    @app.exception_handler(LLMError)
    async def _llm_error(_: Request, exc: LLMError) -> JSONResponse:
        # str(exc) ist bewusst die einzige Quelle: die Meldungen werden in
        # core/llm.py gebaut und enthalten keinen Key.
        return JSONResponse(
            status_code=STATUS_BY_KIND.get(exc.kind, 502),
            content={"detail": str(exc), "kind": exc.kind, "retryable": exc.retryable},
        )

    app.include_router(api)
    app.include_router(router)
    return app
