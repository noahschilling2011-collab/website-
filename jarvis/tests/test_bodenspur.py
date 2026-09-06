"""FIX-06 Abschnitt 7.3: die Bodenspur.

`Ueberflug` beantwortet "wann sehe ich ihn von hier" - das ist etwas
anderes als "wo steht er gerade". Fuer eine Bahn auf dem Globus braucht es
lat/lon direkt unter dem Satelliten, und zwar fuer viele Zeitpunkte.

Die skyfield-Aufrufe sind **nachgeschlagen**, nicht erinnert:
`wgs84.latlon_of(position)` und `wgs84.height_of(position)`, beide
dokumentiert in `documentation/earth-satellites.rst` und gegen die
installierte Fassung 1.55 geprueft (`inspect.signature`).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from core.satellite.ueberflug import UeberflugFehler, bodenspuren

# Ein echter TLE-Satz der ISS. Keine Netzabfrage: die Zahlen stehen hier,
# damit der Test ohne CelesTrak laeuft (tests/conftest.py sperrt das Netz).
ISS = (
    "ISS (ZARYA)",
    "1 25544U 98067A   26239.50000000  .00005000  00000-0  10000-3 0  9993",
    "2 25544  51.6400 208.9163 0001000  86.9990 273.1360 15.50377580440135",
)
# Ein zweiter, damit "mehrere Satelliten" wirklich mehrere sind.
HST = (
    "HST",
    "1 20580U 90037B   26239.50000000  .00001000  00000-0  50000-4 0  9990",
    "2 20580  28.4700 288.8000 0002500 300.0000  60.0000 15.09000000440130",
)

VON = datetime(2026, 8, 27, 12, 0, 0, tzinfo=timezone.utc)


def test_eine_spur_hat_punkte_und_nennt_den_satelliten():
    spuren = bodenspuren([ISS], von=VON, minuten=90, schritt_s=30)
    assert len(spuren) == 1
    s = spuren[0]
    assert s.name == "ISS (ZARYA)"
    assert s.norad == 25544
    # 90 Minuten in 30-Sekunden-Schritten sind 180 Intervalle, 181 Punkte.
    assert len(s.punkte) == 181, len(s.punkte)
    assert s.tle_alter_tage == pytest.approx(0.0, abs=0.01)


def test_die_punkte_liegen_wirklich_auf_der_erde():
    s = bodenspuren([ISS], von=VON, minuten=30, schritt_s=60)[0]
    for lat, lon in s.punkte:
        assert -90.0 <= lat <= 90.0, lat
        assert -180.0 <= lon <= 180.0, lon


def test_die_iss_bleibt_in_ihrer_bahnneigung():
    """51,64 Grad stehen im TLE. Eine Bodenspur, die darueber hinausgeht,
    ist falsch gerechnet - das faengt kein Bereichstest ab."""
    s = bodenspuren([ISS], von=VON, minuten=95, schritt_s=30)[0]
    hoechste = max(abs(lat) for lat, _ in s.punkte)
    assert 50.0 < hoechste <= 52.0, hoechste


def test_die_hoehe_ist_plausibel():
    s = bodenspuren([ISS], von=VON, minuten=90, schritt_s=60)[0]
    assert 380.0 < s.hoehe_km < 460.0, s.hoehe_km


def test_eine_umlaufbahn_umrundet_die_erde_einmal():
    """Die ISS braucht rund 93 Minuten. In 90 Minuten muss die Laenge
    einmal komplett durchlaufen - erkennbar am Sprung von +180 auf -180."""
    s = bodenspuren([ISS], von=VON, minuten=93, schritt_s=30)[0]
    spruenge = 0
    for (_, a), (_, b) in zip(s.punkte, s.punkte[1:]):
        if abs(b - a) > 180.0:
            spruenge += 1
    assert spruenge >= 1, spruenge


def test_mehrere_satelliten_kommen_einzeln_zurueck():
    spuren = bodenspuren([ISS, HST], von=VON, minuten=20, schritt_s=60)
    assert [s.name for s in spuren] == ["ISS (ZARYA)", "HST"]
    assert spuren[0].punkte != spuren[1].punkte


def test_als_dict_ist_json_faehig():
    import json
    s = bodenspuren([ISS], von=VON, minuten=10, schritt_s=60)[0]
    d = s.als_dict()
    json.dumps(d)
    assert set(d) >= {"name", "norad", "hoehe_km", "punkte", "tle_alter_tage"}
    # Auf drei Nachkommastellen gerundet: das sind rund 111 m auf der Erde
    # und damit weit genauer, als eine Linie auf einem Globus je zeigt.
    # Ungerundet waere die Antwort bei 157 Satelliten unnoetig gross.
    assert d["punkte"][0] == [round(s.punkte[0][0], 3), round(s.punkte[0][1], 3)]
    assert all(len(str(x).split(".")[-1]) <= 3 for p_ in d["punkte"] for x in p_)


def test_ein_kaputter_satz_kippt_nicht_die_ganze_antwort():
    kaputt = ("MUELL", "1 abc", "2 def")
    spuren = bodenspuren([ISS, kaputt], von=VON, minuten=10, schritt_s=60)
    assert [s.name for s in spuren] == ["ISS (ZARYA)"]


def test_die_grenzen_werden_eingehalten():
    with pytest.raises(UeberflugFehler):
        bodenspuren([ISS], von=VON, minuten=0, schritt_s=30)
    with pytest.raises(UeberflugFehler):
        bodenspuren([ISS], von=VON, minuten=90, schritt_s=0)
    # Nach oben gedeckelt, damit niemand 10.000 Punkte je Satellit bestellt.
    with pytest.raises(UeberflugFehler):
        bodenspuren([ISS], von=VON, minuten=10000, schritt_s=1)


def test_der_alterhinweis_kommt_mit():
    """Ein TLE altert. Sieben Tage sind die Schwelle, die das Modul schon
    kennt - die Spur muss ihn weiterreichen, sonst zeichnet der Globus eine
    Bahn, die es so nicht mehr gibt."""
    spaeter = VON + timedelta(days=10)
    s = bodenspuren([ISS], von=spaeter, minuten=10, schritt_s=60)[0]
    assert s.tle_alter_tage > 9.0
    assert s.tle_zu_alt is True
