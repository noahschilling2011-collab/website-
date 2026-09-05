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
from api.zeitplan import zeitplan_router, zeitplan_schleife
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


def diagnose(settings: Settings) -> list[str]:
    """Was von der LLM-Konfiguration wirklich angekommen ist - Zeile fuer Zeile.

    Drei Regeln:

    1. **Der Key steht nie drin.** Logs landen in Terminals, in Dateien und in
       Screenshots. Gemeldet wird nur, wie lang er ist - das reicht, um einen
       halb eingefuegten Key zu erkennen, und verraet nichts.
    2. **Die Datei wird benannt, mit vollem Pfad.** "Trag es in die .env ein"
       hilft nicht, wenn zwei `.env` existieren oder der Server in einem
       anderen Verzeichnis gestartet wurde.
    3. **Auch was da IST, wird gemeldet.** Der Nutzer sieht sonst nur, was
       fehlt, und weiss nicht, ob die Datei ueberhaupt gelesen wurde.
    """
    datei = Path(str(settings.model_config.get("env_file") or ".env")).resolve()
    zeilen = [
        # Nicht "gelesen aus": die Werte koennen auch aus Umgebungsvariablen
        # kommen, und dann waere das gelogen. Gemeldet wird, welche Datei
        # gemeint ist und ob es sie gibt - beides stimmt immer.
        f"Konfigurationsdatei: {datei}"
        + ("" if datei.is_file() else "  -- DIESE DATEI GIBT ES NICHT"),
        f"LLM_PROVIDER={settings.llm_provider}" if settings.llm_provider
        else "LLM_PROVIDER ist leer",
        f"LLM_MODEL={settings.llm_model}" if settings.llm_model
        else "LLM_MODEL ist leer",
    ]
    key = settings.llm_api_key
    zeilen.append(
        f"LLM_API_KEY ist gesetzt ({len(key)} Zeichen)" if key
        else "LLM_API_KEY ist leer  <-- das fehlt"
    )
    return zeilen


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
            # Und jetzt die Zeile, die das Raten erspart.
            #
            # Anlass, 27.08.2026: der Server meldete "Kein LLM_API_KEY
            # gesetzt" und zwei Zeilen weiter "Anbieter groq, Modell
            # openai/gpt-oss-120b". Beides stand in derselben `.env`. Wer das
            # liest, weiss nicht, ob die Datei ueberhaupt gefunden wurde, ob
            # es die richtige war, oder ob nur eine Zeile leer blieb - und
            # faengt an zu raten. Eine Fehlermeldung, die zum Raten zwingt,
            # ist eine halbe Fehlermeldung.
            for zeile in diagnose(settings):
                log.error("  %s", zeile)
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
        # Die Verfallszeit an ALLE drei Nachschlage-Werkzeuge, nicht nur an
        # die zwei mit Kontakt: wiki_lokal cacht genauso, und ein ZIM, das
        # Noah austauscht, wuerde sonst hinter alten Cache-Eintraegen
        # verschwinden.
        for name in ("wiki_lokal", "wiki_live", "wikidata"):
            werkzeug = registry.get(name)
            if werkzeug is not None:
                werkzeug.cache_stunden = settings.wissen_cache_stunden
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
        # FIX-09: der Name des Assistenten in jedem Prompt; Wetter und
        # Erinnerungen bekommen Datenbank und Standardort.
        from core import agents as _agents

        _agents.ASSISTENT_NAME = settings.assistent_name
        wetter = registry.get("wetter")
        if wetter is not None:
            wetter.standard_ort = settings.jarvis_ort
            wetter.db_path = settings.db_path
        erinnerung = registry.get("erinnerung_anlegen")
        if erinnerung is not None:
            erinnerung.db_path = settings.db_path
        if not settings.jarvis_ort:
            log.info("JARVIS_ORT fehlt - wetter fragt nach einem Ort, die Vorlage "
                     "Morgenlage laesst das Wetter weg.")
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
        # FIX-08: die Schleife, die Zeitplaene ausloest. Sie startet NACH
        # dem "bereit", damit ihre erste Runde einen fertigen Zustand sieht.
        # ZEITPLAN_TAKT_S=0 schaltet sie ab - die Plaene bleiben dann
        # anlegbar und von Hand ausloesbar, laufen aber nicht von selbst.
        app.state.zeitplan_task = None
        if settings.zeitplan_takt_s > 0:
            app.state.zeitplan_task = asyncio.create_task(zeitplan_schleife(app))
        else:
            log.info("ZEITPLAN_TAKT_S=0 - Zeitplaene laufen nicht von selbst.")
        try:
            yield
        finally:
            # Erst die Schleife, dann die Tasks: sonst startet sie zwischen
            # stop_alle und dem Ende noch einen neuen.
            schleife = app.state.zeitplan_task
            if schleife is not None:
                schleife.cancel()
                try:
                    await schleife
                except asyncio.CancelledError:
                    pass
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
    app.include_router(zeitplan_router)
    app.include_router(router)
    return app
