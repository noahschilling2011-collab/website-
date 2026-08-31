"""Testaufbau.

Zwei Dinge werden hier hart erzwungen:

1. Kein Test macht einen echten Modellaufruf. Nicht "wir passen auf" - die
   echte httpx-Transportschicht wirft. Ein `httpx.MockTransport` geht an der
   Sperre vorbei, weil er die echten Transporte gar nicht benutzt.
2. Jeder Test bekommt eine eigene Datenbankdatei und eine saubere Umgebung.
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Any, Coroutine, TypeVar

import httpx
import pytest

from core.config import Settings, get_settings

T = TypeVar("T")


def run(coro: Coroutine[Any, Any, T]) -> T:
    """Eine Coroutine in einem Test ausfuehren, ohne pytest-asyncio."""
    return asyncio.run(coro)


class NetzwerkImTestVerboten(RuntimeError):
    pass


# Die eigene Maschine ist erlaubt: der SSE-Test braucht einen echten uvicorn,
# und der laeuft auf 127.0.0.1. Alles andere - insbesondere jeder
# Modellanbieter - bleibt gesperrt.
ERLAUBTE_HOSTS = {"127.0.0.1", "localhost", "::1"}


@pytest.fixture(autouse=True)
def kein_echtes_netz(monkeypatch: pytest.MonkeyPatch) -> None:
    echt_sync = httpx.HTTPTransport.handle_request
    echt_async = httpx.AsyncHTTPTransport.handle_async_request

    def erlaubt(request) -> bool:  # noqa: ANN001
        return (request.url.host or "") in ERLAUBTE_HOSTS

    def blocked(self, request, *args, **kwargs):  # noqa: ANN001
        if erlaubt(request):
            return echt_sync(self, request, *args, **kwargs)
        raise NetzwerkImTestVerboten(
            f"Test wollte wirklich ins Netz: {request.method} {request.url}. "
            "Tests laufen gegen FakeLLMProvider oder httpx.MockTransport."
        )

    async def blocked_async(self, request, *args, **kwargs):  # noqa: ANN001
        if erlaubt(request):
            return await echt_async(self, request, *args, **kwargs)
        raise NetzwerkImTestVerboten(
            f"Test wollte wirklich ins Netz: {request.method} {request.url}. "
            "Tests laufen gegen FakeLLMProvider oder httpx.MockTransport."
        )

    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", blocked)
    monkeypatch.setattr(httpx.AsyncHTTPTransport, "handle_async_request",
                        blocked_async)


@pytest.fixture(autouse=True)
def saubere_umgebung(monkeypatch: pytest.MonkeyPatch):
    """Keine .env und keine Shell-Variable faerbt auf einen Test ab."""
    for name in list(os.environ):
        if name.startswith(("JARVIS_", "LLM_", "BUDGET_")):
            monkeypatch.delenv(name, raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(autouse=True)
def werkzeuge_zuruecksetzen():
    """Werkzeug-Konfiguration je Test isolieren.

    Die Registry haelt Werkzeug-*Instanzen*, und `create_app` schreibt ihnen
    beim Start Pfade und Keys hinein. Laufen in einem Prozess zwei Apps -
    etwa der Live-Server fuer die SSE-Tests neben einem TestClient -, dann
    ueberschreibt der spaetere Start die Konfiguration des frueheren.

    Das ist im Betrieb kein Problem (dort laeuft eine App), aber es macht
    Tests voneinander abhaengig. Hier wird deshalb vor und nach jedem Test
    aufgeraeumt.

    Hier stand eine HANDGEPFLEGTE Liste: ("api_key", "transport", "db_path",
    "outbox"). Sie hat `vault_pfad`, `kalender_quelle`, `datei_wurzeln`,
    `cache_stunden`, `basis`, `zim`, `kontakt`, `token` und `provider` nicht
    erfasst - also genau die Felder, die seit Phase 3 dazugekommen sind.

    Am 31.08.2026 ist das aufgeflogen: ein Test schrieb `vault_pfad` auf die
    globale `recall`-Instanz, und weil pytest die Dateien alphabetisch
    abarbeitet, lief `test_memory.py` VOR `test_vault.py` - die Suite war
    gruen, der Schaden unsichtbar. Er schlaegt zu, sobald jemand Dateien
    einzeln laufen laesst, was hier jeder tut, weil die volle Suite 25
    Minuten braucht.

    Es gab noch einen zweiten, aelteren Weg derselben Bauart
    (test_fix04.py -> test_memory.py). Deshalb wird jetzt nicht die Liste
    ergaenzt, sondern der Grundsatz durchgesetzt: gesichert wird ALLES, was
    auf der Instanz steht.
    """
    from core.tools import registry

    # `vars(tool)` sind genau die Felder, die jemand auf der INSTANZ gesetzt
    # hat. Was nur auf der Klasse steht (name, description, permission),
    # taucht hier nicht auf und soll auch nicht angefasst werden.
    vorher = {tool.name: dict(vars(tool)) for tool in registry.all_tools()}
    yield
    for tool in registry.all_tools():
        alt_stand = vorher.get(tool.name, {})
        jetzt = vars(tool)
        # Was der Test NEU gesetzt hat, muss weg - sonst verdeckt es
        # dauerhaft den Vorgabewert der Klasse. Genau das war der Fall:
        # `vault_pfad` gab es vorher gar nicht auf der Instanz.
        for feld in [f for f in jetzt if f not in alt_stand]:
            delattr(tool, feld)
        for feld, wert in alt_stand.items():
            setattr(tool, feld, wert)


@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    return tmp_path / "test.db"


@pytest.fixture
def settings(db_path: Path) -> Settings:
    # _env_file=None: die echte .env des Entwicklers bleibt aussen vor.
    return Settings(
        _env_file=None,
        db_path=db_path,
        jarvis_token="test-token-123",
        # Kurz, damit ein Test nicht 20 s auf ein Lebenszeichen wartet.
        sse_heartbeat_seconds=0.15,
    )


@pytest.fixture
def live_server(settings):
    """Ein echter uvicorn in einem Thread.

    Fuer Server-Sent Events gibt es keinen Ersatz: Starlettes TestClient
    puffert den Strom und blockiert beim Verlassen des Kontexts. Ein echter
    Server ist hier nicht Luxus, sondern der einzige Weg, das Verhalten zu
    pruefen, das der Nutzer bekommt.
    """
    import socket
    import threading
    import time

    import uvicorn

    from api.app import create_app

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    app = create_app(settings)
    config = uvicorn.Config(
        app, host="127.0.0.1", port=port, log_level="warning",
    )
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    ende = time.monotonic() + 15
    while not server.started and time.monotonic() < ende:
        time.sleep(0.02)
    if not server.started:
        raise RuntimeError("uvicorn ist nicht hochgekommen")

    try:
        class LiveServer(str):
            """Die URL - mit der App daran, damit Tests den Anbieter tauschen."""

        server_url = LiveServer(f"http://127.0.0.1:{port}")
        server_url.app = app
        yield server_url
    finally:
        server.should_exit = True
        thread.join(timeout=10)
