"""`POST /api/ort` - schreib einen Ort, flieg hin, sieh nach.

Der Endpunkt setzt drei Dinge zusammen, die es einzeln schon gab:
Wikidata als Geocoder (`core/orte.py`), `satellite_search` fuer das Bild,
und den normalen Runner fuer die zwei, drei Saetze.

Der wichtigste Test hier ist `test_der_text_laeuft_ueber_den_runner`: die
Weltlage ist genau daran schon einmal gescheitert (FIX-02 Schritt 2), weil
sie `provider.complete()` direkt rief und damit an Budget, Audit und
`db.log_llm_call` vorbeilief. Das Ergebnis war die Kachel "heute
0,0000 EUR" bei laufenden Kosten.
"""

from __future__ import annotations

import json

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db
from core.llm import FakeLLMProvider
from core.orte import Ort

PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000a49444154789c6360000002000100fd42a0d70000"
    "000049454e44ae426082"
)

GMUEND = Ort(qid="Q4037", name="Schwäbisch Gmünd", lat=48.8, lon=9.8,
             einwohner=62726)


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


@pytest.fixture
def kopf(settings):
    return {"X-Jarvis-Token": settings.jarvis_token}


@pytest.fixture
def ort_gefunden(monkeypatch):
    """Wikidata antwortet - der Geocoder selbst hat eigene Tests."""
    async def stub(name, **_):
        return None if "gibtesnicht" in name.lower() else GMUEND

    import api.ort
    monkeypatch.setattr(api.ort, "finde_ort", stub)


def _cdse(tmp_path, mit_bild: bool):
    """satellite_search mit gefaelschtem Dienst bestuecken."""
    from core.satellite.cdse import CDSEProvider
    from core.tools import registry
    import core.tools.satellite_tools  # noqa: F401

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "openid-connect/token" in url:
            return httpx.Response(200, json={"access_token": "tok"})
        if "odata/v1/Products" in url:
            return httpx.Response(200, json={"value": [{
                "Id": "abc-123",
                "Name": "S2A_MSIL2A_20260820T101031.SAFE",
                "ContentDate": {"Start": "2026-08-20T10:10:31.000Z"},
                "Attributes": [
                    {"Name": "cloudCover", "Value": 4.2},
                    {"Name": "instrumentShortName", "Value": "MSI"},
                ],
            }]})
        if not mit_bild:
            return httpx.Response(403, json={"error": "quota"})
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    w = registry.get("satellite_search")
    w.provider = CDSEProvider("kunde", "geheim",
                              transport=httpx.MockTransport(handler))
    w.db_path = tmp_path / "jarvis.db"
    return w


# --- Zugang ---------------------------------------------------------------


def test_ohne_token_kein_ort(client):
    assert client.post("/api/ort", json={"name": "Berlin"}).status_code == 401


# --- Der Ort --------------------------------------------------------------


def test_ein_ort_wird_gefunden_und_geliefert(client, kopf, ort_gefunden):
    antwort = client.post("/api/ort", json={"name": "Schwäbisch Gmünd"},
                          headers=kopf)
    assert antwort.status_code == 200, antwort.text
    daten = antwort.json()
    assert daten["ort"]["name"] == "Schwäbisch Gmünd"
    assert daten["ort"]["lat"] == 48.8
    assert daten["ort"]["lon"] == 9.8
    assert daten["ort"]["einwohner"] == 62726


def test_ein_unbekannter_ort_gibt_404(client, kopf, ort_gefunden):
    antwort = client.post("/api/ort", json={"name": "Gibtesnichtstadt123"},
                          headers=kopf)
    assert antwort.status_code == 404
    assert "Wikidata" in antwort.json()["detail"]


def test_ein_leerer_name_wird_abgewiesen(client, kopf):
    assert client.post("/api/ort", json={"name": ""},
                       headers=kopf).status_code == 422


def test_die_bbox_umschliesst_den_ort(client, kopf, ort_gefunden):
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    min_lon, min_lat, max_lon, max_lat = daten["bbox"]
    assert min_lat < 48.8 < max_lat
    assert min_lon < 9.8 < max_lon


# --- Das Bild -------------------------------------------------------------


def test_ohne_cdse_kommt_kein_bild_aber_ein_grund(client, kopf, ort_gefunden):
    """Der Normalfall bei Noah, solange keine Zugangsdaten drin sind: der
    Ort wird trotzdem geliefert, das Bild fehlt mit Begruendung."""
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    assert daten["bild"] is None
    assert "CDSE_CLIENT_ID" in daten["hinweis"]
    assert daten["ort"]["name"] == "Schwäbisch Gmünd", "der Ort bleibt trotzdem"


def test_mit_cdse_kommt_ein_bild(client, kopf, ort_gefunden, settings, tmp_path):
    _cdse(settings.db_path.parent, mit_bild=True)
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    assert daten["bild"] is not None
    assert daten["bild"]["url"].startswith("/api/bild/")
    assert daten["bild"]["attribution"], "Copernicus verlangt die Attribution"
    assert daten["szene"]["wolken_pct"] == 4.2


def test_das_gelieferte_bild_ist_wirklich_abrufbar(client, kopf, ort_gefunden,
                                                   settings):
    _cdse(settings.db_path.parent, mit_bild=True)
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    bild = client.get(daten["bild"]["url"], headers=kopf)
    assert bild.status_code == 200
    assert bild.headers["content-type"] == "image/png"


def test_die_aufloesung_ist_die_des_bildes(client, kopf, ort_gefunden, settings):
    """12 km Kante auf 512 Pixeln sind rund 23 m - nicht die 10 m des
    Sensors."""
    _cdse(settings.db_path.parent, mit_bild=True)
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    assert 20 < daten["bild"]["aufloesung_m"] < 30


def test_ein_grosser_ausschnitt_ist_grob(client, kopf, ort_gefunden, settings):
    _cdse(settings.db_path.parent, mit_bild=True)
    daten = client.post("/api/ort", json={"name": "x", "kante_km": 400},
                        headers=kopf).json()
    assert daten["bild"]["aufloesung_m"] > 500


def test_ein_gescheitertes_bild_kippt_den_ort_nicht(client, kopf, ort_gefunden,
                                                    settings):
    _cdse(settings.db_path.parent, mit_bild=False)
    daten = client.post("/api/ort", json={"name": "x"}, headers=kopf).json()
    assert daten["bild"] is None
    assert daten["ort"]["name"] == "Schwäbisch Gmünd"
    assert "403" in daten["hinweis"] or "Bild" in daten["hinweis"]


# --- Der Text laeuft ueber den Runner -------------------------------------


def test_der_text_laeuft_ueber_den_runner(client, kopf, ort_gefunden, settings):
    """Der wichtigste Test hier.

    Die Weltlage rief frueher `provider.complete()` direkt - vorbei am
    Runner und damit an Budget, Audit UND an `db.log_llm_call`. Daher kam
    die Kachel "heute 0,0000 EUR" bei laufenden Kosten (FIX-02 Schritt 2).
    Hier wird geprueft, dass es diesmal anders ist: der Aufruf steht
    hinterher in `llm_calls`, und der Auftrag in `tasks`.
    """
    vorher = len(db.list_llm_calls(settings.db_path))
    antwort = client.post("/api/ort", json={"name": "x"}, headers=kopf)
    assert antwort.status_code == 200

    nachher = db.list_llm_calls(settings.db_path)
    assert len(nachher) > vorher, "kein Modellaufruf protokolliert"
    assert antwort.json()["text"], "der Fake antwortet immer etwas"

    auftraege = db.list_task_rows(settings.db_path)
    assert auftraege, "der Auftrag muss gespeichert sein"


def test_der_auftrag_ist_nach_dem_lauf_nicht_mehr_als_laufend_registriert(
    client, kopf, ort_gefunden
):
    """Sonst waechst die Liste der laufenden Auftraege mit jedem Klick."""
    client.post("/api/ort", json={"name": "x"}, headers=kopf)
    assert client.app.state.tasks._laufend == {}
