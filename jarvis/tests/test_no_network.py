"""Beweist, dass die Netzsperre der Testsitzung wirklich greift.

Ohne diesen Test waere "pytest macht keine echten Modellaufrufe" eine
Behauptung. Mit ihm ist es geprueft.
"""

from __future__ import annotations

import httpx
import pytest

from core.config import Settings
from core.llm import FakeLLMProvider, build_provider
from tests.conftest import NetzwerkImTestVerboten, run


def test_echte_http_anfrage_wird_geblockt():
    with pytest.raises(NetzwerkImTestVerboten):
        httpx.get("https://api.anthropic.com/v1/messages")


def test_auch_async_ist_gesperrt():
    async def versuch():
        async with httpx.AsyncClient() as client:
            await client.post("https://api.anthropic.com/v1/messages", json={})

    with pytest.raises(NetzwerkImTestVerboten):
        run(versuch())


def test_mock_transport_geht_an_der_sperre_vorbei():
    """Sonst waeren die Provider-Tests nicht mehr moeglich."""
    transport = httpx.MockTransport(lambda r: httpx.Response(200, json={"ok": True}))

    async def versuch():
        async with httpx.AsyncClient(transport=transport) as client:
            return (await client.get("https://api.anthropic.com/v1/messages")).json()

    assert run(versuch()) == {"ok": True}


def test_die_voreinstellung_kostet_nichts():
    assert isinstance(build_provider(Settings(_env_file=None)), FakeLLMProvider)
