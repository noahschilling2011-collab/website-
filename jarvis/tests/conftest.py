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
def saubere_umgebung(monkeypatch: pytest.MonkeyPatch):
    """Keine .env und keine Shell-Variable faerbt auf einen Test ab."""
    for name in list(os.environ):
        if name.startswith(("JARVIS_", "LLM_", "BUDGET_")):
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
    return Settings(_env_file=None, db_path=db_path, jarvis_token="test-token-123")
