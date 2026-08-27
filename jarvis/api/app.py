"""Anwendungsfabrik.

`create_app()` liest die Konfiguration beim Aufruf, nicht beim Import. Tests
koennen dadurch eine eigene `Settings` uebergeben, ohne das Modul neu zu laden.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from api.events import EventBus
from api.routes import api, router
from api.tasks import TaskRegistry, tasks_router
from api.security import ensure_token
from core.config import PROJECT_ROOT, Settings, get_settings
from core.db import connect, init_db
from core.llm import LLMError, LLMProvider, build_provider
from api.ort import ort_router
from api.weltlage import weltlage_router
from core.tools import registry

log = logging.getLogger("jarvis")

INDEX_PATH = PROJECT_ROOT / "index.html"
WELTLAGE_PATH = PROJECT_ROOT / "weltlage.html"
STATIC_PATH = PROJECT_ROOT / "static"

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

    async def complete(self, messages, *, system, tools=None):  # noqa: ANN001, ANN201
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

        # Der Such-Key wird hier gesetzt und nicht im Tool importiert -
        # so bleibt das Tool ohne Umgebung baubar und testbar.
        suche = registry.get("web_search")
        if suche is not None:
            suche.api_key = settings.search_api_key
        for name in ("remember", "recall"):
            werkzeug = registry.get(name)
            if werkzeug is not None:
                werkzeug.db_path = settings.db_path
                werkzeug.vault_pfad = settings.vault_pfad
        # FIX-07: die freigegebenen Ordner und die Kalenderquelle. Leer
        # heisst aus - dann meldet das Werkzeug das sauber, statt so zu tun,
        # als haette es nachgesehen.
        for name in ("datei_suchen", "datei_lesen"):
            werkzeug = registry.get(name)
            if werkzeug is not None:
                werkzeug.datei_wurzeln = settings.datei_wurzeln
                werkzeug.datei_max_kb = settings.datei_max_kb
        kal = registry.get("kalender")
        if kal is not None:
            kal.kalender_quelle = settings.kalender_quelle
            kal.db_path = settings.db_path
        lokal = registry.get("wiki_lokal")
        if lokal is not None:
            lokal.basis = settings.wiki_kiwix_basis
            lokal.zim = settings.wiki_zim
            lokal.db_path = settings.db_path
        for name in ("wiki_live", "wikidata"):
            werkzeug = registry.get(name)
            if werkzeug is not None:
                werkzeug.kontakt = settings.wiki_kontakt
                werkzeug.db_path = settings.db_path
        live = registry.get("wiki_live")
        if live is not None:
            live.token = settings.wiki_token
        if not settings.wiki_zim:
            log.info("WIKI_ZIM fehlt - wiki_lokal meldet das beim Aufruf.")
        if not settings.wiki_kontakt:
            log.info("WIKI_KONTAKT fehlt - wiki_live und wikidata melden das "
                     "beim Aufruf (User-Agent-Richtlinie).")

        post = registry.get("send_email")
        if post is not None:
            post.outbox = settings.outbox_path
        satellit = registry.get("satellite_search")
        if satellit is not None:
            from core.satellite.cdse import CDSEProvider

            satellit.provider = CDSEProvider(
                settings.cdse_client_id, settings.cdse_client_secret
            )
            # Wohin das gerenderte Bild geschrieben wird - neben die
            # Datenbank, nicht hinein.
            satellit.db_path = settings.db_path
        ortsuche = registry.get("find_place")
        if ortsuche is not None:
            # Fuer die Live-Abfrage. Ohne Kontakt geht immer noch die
            # eingebaute Tabelle: jedes Land, jede Hauptstadt.
            ortsuche.kontakt = settings.wiki_kontakt
        ueberflug = registry.get("satellite_passes")
        if ueberflug is not None:
            # Braucht keinen Key - CelesTrak ist offen. Nur den Pfad
            # fuer den TLE-Zwischenspeicher.
            ueberflug.db_path = settings.db_path
        if not settings.cdse_client_id:
            log.info("CDSE_CLIENT_ID fehlt - satellite_search meldet das beim "
                     "Aufruf. Ein Konto gibt es kostenlos auf "
                     "dataspace.copernicus.eu.")
        # --- Vault (docs/MIGRATION-VAULT.md) ---
        # Der Index ist abgeleitet: beim Start einmal neu bauen kostet nichts
        # und macht ihn verlaesslich, egal was zwischendurch in Obsidian
        # passiert ist.
        # FIX-04 Schritt 3: reindex beim Start, und sonst nichts. Keine
        # Dateiueberwachung, kein Hintergrund-Dienst, keine Polling-Schleife.
        # Was zwischendurch in Obsidian passiert, holt
        # `core.gedaechtnis.frisch_halten` beim naechsten Lesen nach - es
        # prueft die Zeitstempel und wirft geloeschte Dateien aus dem Index.
        if settings.vault_pfad:
            from core.vault_index import reindex

            anzahl = await asyncio.to_thread(
                reindex, settings.db_path, settings.vault_pfad
            )
            log.info("Vault %s - %d Notizen indexiert.", settings.vault_pfad, anzahl)

        if not settings.search_api_key:
            log.info("SEARCH_API_KEY fehlt - web_search meldet das beim Aufruf.")

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
            # Laufende Tasks beenden, bevor der Prozess geht - sonst haengen
            # Modellaufrufe in der Luft, die schon Geld gekostet haben.
            await app.state.tasks.stop_alle()
            await app.state.provider.aclose()

    app = FastAPI(
        title="JARVIS",
        description="Persoenliches AI-Operating-System.",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.index_path = INDEX_PATH
    app.state.weltlage_path = WELTLAGE_PATH
    app.state.tasks = TaskRegistry()
    app.state.events = EventBus()
    app.state.token, app.state.token_generated = ensure_token(settings.jarvis_token)

    @app.exception_handler(LLMError)
    async def _llm_error(_: Request, exc: LLMError) -> JSONResponse:
        # str(exc) ist bewusst die einzige Quelle: die Meldungen werden in
        # core/llm.py gebaut und enthalten keinen Key.
        return JSONResponse(
            status_code=STATUS_BY_KIND.get(exc.kind, 502),
            content={"detail": str(exc), "kind": exc.kind, "retryable": exc.retryable},
        )

    if STATIC_PATH.exists():
        from fastapi.staticfiles import StaticFiles

        app.mount("/static", StaticFiles(directory=STATIC_PATH), name="static")
    app.include_router(ort_router)
    app.include_router(weltlage_router)
    app.include_router(api)
    app.include_router(tasks_router)
    app.include_router(router)
    return app
