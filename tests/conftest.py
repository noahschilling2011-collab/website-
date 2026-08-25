"""Testaufbau.

Zwei Dinge werden hier hart erzwungen:

1. Kein Test macht einen echten Modellaufruf. Nicht "wir passen auf" -
   die echte httpx-Transportschicht wirft. Ein `httpx.MockTransport` geht
   an dieser Sperre vorbei, weil er `HTTPTransport` gar nicht benutzt.
2. Jeder Test bekommt eine eigene Datenbankdatei.
"""

from __future__ import annotations

import os
from pathlib import Path

import httpx
import pytest

from core.config import Settings, get_settings


class NetzwerkImTestVerboten(RuntimeError):
    pass


@pytest.fixture(autouse=True)
def kein_echtes_netz(monkeypatch: pytest.MonkeyPatch) -> None:
    def blocked(self, request, *args, **kwargs):  # noqa: ANN001
        raise NetzwerkImTestVerboten(
            f"Test wollte wirklich ins Netz: {request.method} {request.url}. "
            "Tests laufen gegen FakeLLMProvider oder httpx.MockTransport."
        )

    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", blocked)
    monkeypatch.setattr(httpx.AsyncHTTPTransport, "handle_async_request", blocked)


@pytest.fixture(autouse=True)
def saubere_umgebung(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keine .env und keine Shell-Variable faerbt auf einen Test ab."""
    for name in list(os.environ):
        if name.startswith("JARVIS_") or name == "ANTHROPIC_API_KEY":
            monkeypatch.delenv(name, raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    return tmp_path / "test.db"


@pytest.fixture
def settings(db_path: Path) -> Settings:
    # _env_file=None: die echte .env des Entwicklers bleibt aussen vor.
    return Settings(_env_file=None, db_path=db_path, provider="fake")
