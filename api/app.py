"""Anwendungsfabrik.

`create_app()` liest die Konfiguration beim Aufruf - nicht beim Import.
Tests koennen dadurch Umgebungsvariablen setzen, den Cache leeren und eine
frische App bauen, ohne das Modul neu zu laden.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from api.routes import router
from core.config import PROJECT_ROOT, Settings, get_settings
from core.db import connect, init_db
from core.llm import LLMError, UnavailableProvider, build_provider

log = logging.getLogger("jarvis")

WEB_DIR = PROJECT_ROOT / "web"

# Ein Konfigurationsfehler ist kein Fehler des Anbieters. Er bekommt einen
# eigenen Status, damit die Oberflaeche "richte das ein" sagen kann statt
# "der Anbieter spinnt".
STATUS_BY_KIND = {"missing_api_key": 503}


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
            # Kein Grund, den Start abzubrechen: die Oberflaeche soll laden
            # und anzeigen koennen, was einzurichten ist.
            log.error("Anbieter nicht verfuegbar - %s", exc)
            app.state.provider = UnavailableProvider(
                exc, name=settings.provider, model=settings.model
            )

        log.info(
            "JARVIS bereit - Anbieter %s, Modell %s, Datenbank %s",
            app.state.provider.name,
            app.state.provider.model,
            settings.db_path,
        )
        try:
            yield
        finally:
            app.state.provider.close()

    app = FastAPI(
        title="JARVIS",
        description="Persoenliches AI-Operating-System. Phase 1: Fundament.",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.web_dir = WEB_DIR

    @app.exception_handler(LLMError)
    async def _llm_error(_: Request, exc: LLMError) -> JSONResponse:
        # str(exc) ist bewusst die einzige Quelle: die Meldungen werden in
        # core/llm.py gebaut und enthalten keinen Key.
        return JSONResponse(
            status_code=STATUS_BY_KIND.get(exc.kind, 502),
            content={"detail": str(exc), "kind": exc.kind, "retryable": exc.retryable},
        )

    app.include_router(router)
    if WEB_DIR.is_dir():
        app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")
    return app
