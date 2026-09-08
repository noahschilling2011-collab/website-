"""Oeffentlicher Katalog -> Dispatcher -> Ortsansicht, ohne Bild-Credentials."""

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.satellite.cdse import CDSEProvider, KATALOG_URL
from core.tools import registry
from core.tools.dispatch import run_tool
from tests.conftest import run


@pytest.mark.parametrize("mit_szene", [True, False])
def test_katalog_ohne_credentials_ruft_nie_token_oder_process_api(settings, mit_szene):
    requests = []

    def antwort(request):
        requests.append(request)
        assert request.method == "GET"
        assert str(request.url).startswith(KATALOG_URL)
        assert "authorization" not in request.headers
        return httpx.Response(200, json={"value": [{
            "Id": "KATALOG-TESTSZENE", "ContentDate": {"Start": "2026-09-06T10:00:00.000Z"},
            "Attributes": [{"Name": "cloudCover", "Value": 3.0}],
        }] if mit_szene else []})

    with TestClient(create_app(settings)):
        registry.get("satellite_search").provider = CDSEProvider(transport=httpx.MockTransport(antwort))
        ergebnis = run(run_tool("satellite_search", {"bbox": [9.75, 48.76, 9.85, 48.83]}))
    assert ergebnis.ok
    assert len(requests) == 1
    assert bool(ergebnis.data["scenes"]) == mit_szene
    assert not ergebnis.data.get("preview_url")
    assert "CDSE-Zugangsdaten fehlen" in ergebnis.display
    assert "CDSE_CLIENT_SECRET" in ergebnis.data["bild_hinweis"]


def test_ortsansicht_erklaert_fehlendes_llm_und_cdse(settings):
    settings.llm_provider = ""
    settings.llm_api_key = ""
    settings.cdse_client_id = settings.cdse_client_secret = ""
    with TestClient(create_app(settings)) as client:
        registry.get("satellite_search").provider = CDSEProvider(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"value": []})))
        antwort = client.post("/api/ort", headers={"X-Jarvis-Token": settings.jarvis_token},
                              json={"name": "Berlin"})
        assert antwort.status_code == 200
        daten = antwort.json()
        assert daten["ort"]["name"] == "Berlin"
        assert daten["bild"] is None
        assert daten["text"] == ""
        assert "CDSE-Zugangsdaten fehlen" in daten["hinweis"]
        assert "LLM nicht eingerichtet" in daten["hinweis"]
