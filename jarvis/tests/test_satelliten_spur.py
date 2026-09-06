"""FIX-06 Abschnitt 7.3: GET /api/satelliten/spur.

Der Auftrag ist hier ausdruecklich: **kein zweiter Abrufpfad.** Der
Endpunkt nimmt die schon zwischengespeicherten TLE-Saetze - dieselbe
`hole_tle`, derselbe Zwei-Stunden-Cache, dieselbe `Invalid query`-Pruefung.
CelesTrak sperrt IPs, die dauernd anfragen, und ein Dashboard, das bei
jedem Oeffnen holt, ist genau so ein Fall.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.satellite.ueberflug import cache_datei

TOKEN = {"X-Jarvis-Token": "test-token-123"}

TLE = (
    "ISS (ZARYA)\r\n"
    "1 25544U 98067A   26239.50000000  .00005000  00000-0  10000-3 0  9993\r\n"
    "2 25544  51.6400 208.9163 0001000  86.9990 273.1360 15.50377580440135\r\n"
    "HST\r\n"
    "1 20580U 90037B   26239.50000000  .00001000  00000-0  50000-4 0  9990\r\n"
    "2 20580  28.4700 288.8000 0002500 300.0000  60.0000 15.09000000440130\r\n"
)


@pytest.fixture
def klient(settings):
    """Mit gefuelltem Cache. Ohne den waere der einzige Weg zu echten Daten
    das Netz - und das ist in `tests/conftest.py` gesperrt."""
    datei = cache_datei("visual", db_path=settings.db_path)
    datei.parent.mkdir(parents=True, exist_ok=True)
    datei.write_text(TLE, encoding="utf-8")
    app = create_app(settings)
    with TestClient(app) as c:
        yield c, settings


def test_der_endpunkt_will_den_token(klient):
    c, _ = klient
    assert c.get("/api/satelliten/spur").status_code == 401


def test_die_spuren_kommen_aus_dem_cache(klient):
    c, _ = klient
    d = c.get("/api/satelliten/spur?gruppe=visual&minuten=90", headers=TOKEN).json()
    assert d["aus_cache"] is True, d
    assert d["gruppe"] == "visual"
    assert len(d["spuren"]) == 2
    namen = [s["name"] for s in d["spuren"]]
    assert namen == ["ISS (ZARYA)", "HST"]


def test_eine_spur_traegt_alles_was_der_globus_braucht(klient):
    c, _ = klient
    s = c.get("/api/satelliten/spur?minuten=90", headers=TOKEN).json()["spuren"][0]
    assert s["norad"] == 25544
    assert 380 < s["hoehe_km"] < 460
    assert len(s["punkte"]) == 181
    lat, lon = s["punkte"][0]
    assert -90 <= lat <= 90 and -180 <= lon <= 180


def test_die_sichtbarkeitsgrenze_steht_in_der_antwort(klient):
    """DoD 5 verlangt den Satz in der Oberflaeche. Damit die Oberflaeche
    ihn nicht selbst erfinden muss, kommt er vom Endpunkt."""
    c, _ = klient
    d = c.get("/api/satelliten/spur", headers=TOKEN).json()
    assert "sichtbar" in d["grenze"].lower()
    assert "steht" in d["grenze"].lower()


def test_eine_unbekannte_gruppe_wird_abgelehnt(klient):
    c, _ = klient
    a = c.get("/api/satelliten/spur?gruppe=active", headers=TOKEN)
    assert a.status_code == 422, a.text
    # Die Gruppe mit rund 10.000 Objekten ist bewusst nicht waehlbar.
    assert "active" not in a.json()["detail"].split("Bekannt:")[-1]


def test_das_fenster_hat_grenzen(klient):
    c, _ = klient
    assert c.get("/api/satelliten/spur?minuten=0", headers=TOKEN).status_code == 422
    assert c.get("/api/satelliten/spur?minuten=99999", headers=TOKEN).status_code == 422


def test_ohne_cache_wird_nicht_heimlich_geholt(klient):
    """Wenn nichts im Cache liegt und das Netz nicht geht, kommt eine
    ehrliche Fehlermeldung - kein leeres Ergebnis, das wie "keine
    Satelliten" aussieht."""
    c, settings = klient
    cache_datei("visual", db_path=settings.db_path).unlink()
    a = c.get("/api/satelliten/spur", headers=TOKEN)
    assert a.status_code == 503, a.text
    assert a.json()["detail"]


def test_der_alterhinweis_kommt_durch(klient):
    c, _ = klient
    d = c.get("/api/satelliten/spur?minuten=10", headers=TOKEN).json()
    for s in d["spuren"]:
        assert "tle_alter_tage" in s and "tle_zu_alt" in s
