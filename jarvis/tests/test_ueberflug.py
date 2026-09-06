"""Satellitenüberflüge (PHASE-08 DoD 5).

Gerechnet mit `skyfield` aus echten TLE-Sätzen. Die TLEs hier sind fest
eingetragen, nicht geholt: dann ist jede Zahl unten reproduzierbar, und
der Test kommt ohne Netz aus - `tests/conftest.py` sperrt es ohnehin.

Die beiden Sätze stammen von CelesTrak, geholt am 26.08.2026 über
`GROUP=stations&FORMAT=tle`. Epoche 26238 = Tag 238 des Jahres 2026.

Der Nordpol-Fall ist der interessanteste Test hier: dort kommt **null**
heraus, und das ist keine Panne, sondern Physik. Die ISS-Bahnneigung ist
51,6 Grad - sie erreicht 89,9 Grad Nord nie.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from core.satellite.ueberflug import (
    GRUPPEN,
    TLE_HOECHSTALTER_S,
    UeberflugFehler,
    cache_datei,
    himmelsrichtung,
    parse_tle,
    ueberfluege,
)

ISS = (
    "ISS (ZARYA)",
    "1 25544U 98067A   26238.49891027  .00008646  00000+0  16123-3 0  9990",
    "2 25544  51.6328 312.0820 0007754  85.9348 274.2526 15.49640156582658",
)
CSS = (
    "CSS (TIANHE)",
    "1 48274U 21035A   26238.30990125  .00014464  00000+0  18254-3 0  9997",
    "2 48274  41.4653  25.1042 0006123 336.1178  23.9385 15.62449008289771",
)
TLE_TEXT = "\n".join(z for satz in (ISS, CSS) for z in satz) + "\n"

VON = datetime(2026, 8, 26, 0, 0, tzinfo=timezone.utc)
BIS = VON + timedelta(hours=24)

GMUEND = (48.80, 9.80)
SYDNEY = (-33.87, 151.21)
NORDPOL = (89.9, 0.0)


# --- TLE lesen -------------------------------------------------------------


def test_zwei_saetze_werden_gelesen():
    sats = parse_tle(TLE_TEXT)
    assert [n for n, _, _ in sats] == ["ISS (ZARYA)", "CSS (TIANHE)"]


def test_eine_ungueltige_gruppe_kommt_als_200_und_wird_trotzdem_erkannt():
    """Gemessen am 26.08.2026: CelesTrak antwortet auf eine erfundene Gruppe
    mit HTTP 200 und dem Text unten. Wer nur den Status prueft, legt diesen
    Satz als Bahndaten ab und rechnet damit."""
    with pytest.raises(UeberflugFehler) as fehler:
        parse_tle('Invalid query: "GROUP=gibtesnicht&FORMAT=tle" '
                  "(GROUP=gibtesnicht not found)")
    assert "abgelehnt" in str(fehler.value)


def test_eine_leere_antwort_ist_ein_fehler_kein_leeres_ergebnis():
    with pytest.raises(UeberflugFehler):
        parse_tle("")
    with pytest.raises(UeberflugFehler):
        parse_tle("   \n  \n")


def test_ein_halber_satz_wird_uebersprungen_statt_verwechselt():
    """Ein abgeschnittener Block darf nicht dazu fuehren, dass der Name des
    einen Satelliten an die Bahndaten des naechsten geraet."""
    kaputt = "KAPUTT\n1 nur eine Zeile\n" + TLE_TEXT
    sats = parse_tle(kaputt)
    namen = [n for n, _, _ in sats]
    assert "KAPUTT" not in namen
    assert namen == ["ISS (ZARYA)", "CSS (TIANHE)"]


def test_ohne_einen_einzigen_satz_wird_gemeldet():
    with pytest.raises(UeberflugFehler):
        parse_tle("nur Text\nund noch Text\nund noch mehr\n")


# --- Himmelsrichtung -------------------------------------------------------


@pytest.mark.parametrize("grad,erwartet", [
    (0, "N"), (90, "O"), (180, "S"), (270, "W"),
    (45, "NO"), (237.5, "WSW"), (359.9, "N"), (360, "N"), (-90, "W"),
])
def test_azimut_wird_zur_himmelsrichtung(grad, erwartet):
    """Ein Azimut von 237,5 Grad sagt niemandem, wohin er schauen soll."""
    assert himmelsrichtung(grad) == erwartet


# --- Die Rechnung, weltweit ------------------------------------------------


def test_ueber_deutschland_kommen_ueberfluege_heraus():
    u = ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                    von=VON, bis=BIS)
    assert len(u) >= 5
    erster = u[0]
    assert erster.name == "ISS (ZARYA)"
    assert erster.norad == 25544
    assert erster.aufgang < erster.hoechststand < erster.untergang
    assert erster.max_hoehe_grad >= 10.0
    # Die ISS fliegt rund 400 km hoch; am hoechsten Stand ist sie am naechsten.
    assert 300 < erster.min_entfernung_km < 2000


def test_auch_die_suedhalbkugel(  ):
    """"Fuer die ganze Welt" ist keine Floskel: lat und lon sind frei."""
    u = ueberfluege(parse_tle(TLE_TEXT), lat=SYDNEY[0], lon=SYDNEY[1],
                    von=VON, bis=BIS)
    assert len(u) >= 5
    assert all(x.aufgang.tzinfo is not None for x in u)


def test_am_nordpol_kommt_nichts_und_das_ist_richtig():
    """Kein Bug, sondern Physik. Die ISS-Bahnneigung ist 51,6 Grad - sie
    erreicht 89,9 Grad Nord nie. Ein Ergebnis von 0 ist hier die WAHRHEIT,
    und ein Code, der hier irgendetwas erfindet, waere kaputt."""
    u = ueberfluege(parse_tle(TLE_TEXT), lat=NORDPOL[0], lon=NORDPOL[1],
                    von=VON, bis=BIS)
    assert u == []


def test_die_ueberfluege_kommen_zeitlich_sortiert():
    u = ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                    von=VON, bis=BIS)
    assert [x.aufgang for x in u] == sorted(x.aufgang for x in u)


def test_eine_hoehere_schwelle_liefert_weniger():
    """Bei 10 Grad steht der Satellit knapp ueber den Daechern, bei 40 Grad
    hoch am Himmel. Das muss sich in der Anzahl zeigen."""
    argumente = dict(lat=GMUEND[0], lon=GMUEND[1], von=VON, bis=BIS)
    tief = ueberfluege(parse_tle(TLE_TEXT), mindesthoehe_grad=10.0, **argumente)
    hoch = ueberfluege(parse_tle(TLE_TEXT), mindesthoehe_grad=40.0, **argumente)
    assert len(hoch) < len(tief)
    assert all(x.max_hoehe_grad >= 40.0 for x in hoch)


def test_ein_kuerzeres_fenster_liefert_weniger():
    argumente = dict(lat=GMUEND[0], lon=GMUEND[1], von=VON)
    tag = ueberfluege(parse_tle(TLE_TEXT), bis=VON + timedelta(hours=24),
                      **argumente)
    stunde = ueberfluege(parse_tle(TLE_TEXT), bis=VON + timedelta(hours=3),
                         **argumente)
    assert len(stunde) < len(tag)


def test_die_obergrenze_haelt():
    u = ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                    von=VON, bis=BIS, hoechstens=3)
    assert len(u) == 3


def test_das_alter_der_bahndaten_wird_mitgefuehrt():
    """Ein TLE altert. SGP4 ist um die Epoche herum genau und wird mit den
    Tagen schlechter - wer das verschweigt, verkauft eine Vorhersage als
    Messung."""
    u = ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                    von=VON, bis=BIS)
    # Epoche 26238.49 ist der 26.08.2026 gegen Mittag, Fensterbeginn 00:00.
    assert 0.0 <= u[0].tle_alter_tage < 1.0


def test_alte_bahndaten_stehen_im_steckbrief():
    alt = ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                      von=VON + timedelta(days=30),
                      bis=BIS + timedelta(days=30))
    assert alt, "30 Tage spaeter rechnet SGP4 weiter - nur ungenauer"
    assert "Tage alt" in alt[0].steckbrief()


# --- Unmoegliche Eingaben --------------------------------------------------


@pytest.mark.parametrize("lat,lon", [(91, 0), (-91, 0), (0, 181), (0, -181)])
def test_unmoegliche_koordinaten_werden_abgewiesen(lat, lon):
    with pytest.raises(UeberflugFehler):
        ueberfluege(parse_tle(TLE_TEXT), lat=lat, lon=lon, von=VON, bis=BIS)


def test_ein_rueckwaerts_laufendes_fenster_wird_abgewiesen():
    with pytest.raises(UeberflugFehler):
        ueberfluege(parse_tle(TLE_TEXT), lat=GMUEND[0], lon=GMUEND[1],
                    von=BIS, bis=VON)


def test_ein_kaputter_satz_erfindet_keinen_ueberflug():
    """Gemessen, und es ist unangenehmer als erwartet: skyfield und sgp4
    **werfen nicht** bei kaputten TLE-Daten. Weder `EarthSatellite("1 xxx",
    "2 yyy")` noch das anschliessende `find_events` beschwert sich - es
    kommt ein Satellit mit satnum 640000 heraus, der null Ereignisse
    liefert.

    Das ist die eigentliche Gefahr: nicht ein Absturz, sondern still
    gerechneter Unsinn. Geprueft wird deshalb, dass aus Muell KEIN
    Ueberflug entsteht und die guten Saetze davon unberuehrt bleiben."""
    kaputt = [("MUELL", "1 " + "x" * 60, "2 " + "y" * 60), ISS]
    u = ueberfluege(kaputt, lat=GMUEND[0], lon=GMUEND[1], von=VON, bis=BIS)
    assert u, "Die ISS muss trotzdem gerechnet werden"
    assert all(x.name == "ISS (ZARYA)" for x in u), \
        "Aus dem Muell-Satz darf kein einziger Ueberflug entstehen"
    assert all(x.norad == 25544 for x in u)


def test_ein_fenster_das_mitten_im_ueberflug_beginnt():
    """Die Luecke, die eine ueberlebende Mutation aufgedeckt hat.

    `find_events` liefert normalerweise Dreierbloecke 0,1,2 (Aufgang,
    Hoechststand, Untergang). Beginnt das Fenster MITTEN in einem Ueberflug,
    steht vorne ein einzelner Untergang - gemessen fuer 01:26 UTC ueber
    Gmuend:

        [2, 0, 1, 2]

    Ohne die Pruefung auf die Folge (0,1,2) wuerde der Code `2,0,1` als
    Auf-/Hoechst-/Untergang paaren: ein Ueberflug, der rueckwaerts laeuft
    und dessen Zeiten frei erfunden sind. Der erste Lauf dieses Tests
    fehlte, und die Mutation "Ereignisfolge egal" lief gruen durch."""
    mitten_drin = datetime(2026, 8, 26, 1, 26, tzinfo=timezone.utc)
    u = ueberfluege([ISS], lat=GMUEND[0], lon=GMUEND[1],
                    von=mitten_drin, bis=mitten_drin + timedelta(hours=2))
    assert len(u) == 1, "In zwei Stunden kommt die ISS genau einmal wieder"
    einziger = u[0]

    # Der erste Anlauf dieses Tests pruefte "laeuft nicht rueckwaerts" - und
    # die Mutation ueberlebte trotzdem. Der Grund ist subtil: `find_events`
    # liefert ZEITLICH SORTIERT, also sind auch die Zeiten eines falsch
    # gepaarten Blocks aufsteigend. Aus [2,0,1] wuerde ein "Ueberflug"
    # 01:28 -> 02:58 -> 03:02, und der besteht jede Reihenfolgepruefung.
    #
    # Was ihn entlarvt, sind die WERTE. Der echte Ueberflug beginnt um
    # 02:58:42 und kulminiert bei 59 Grad. Beim falschen Block waere der
    # "Aufgang" der Untergang von 01:28 und der "hoechste Stand" der
    # Aufgang - also exakt die Schwelle von 10 Grad.
    assert einziger.aufgang.strftime("%H:%M:%S") == "02:58:42"
    assert einziger.max_hoehe_grad > 50, (
        "Der hoechste Stand darf nicht die Aufgangsschwelle sein"
    )
    assert einziger.aufgang < einziger.hoechststand < einziger.untergang


# --- Der Cache ist eine Auflage, keine Optimierung -------------------------


def test_celestrak_wird_hoechstens_alle_zwei_stunden_gefragt():
    """CelesTrak schreibt in der eigenen Doku: "CelesTrak only checks for
    new GP data once every 2 hours, so there is no need for you to check
    more often." Wer oefter fragt, wird per IP gesperrt."""
    assert TLE_HOECHSTALTER_S == 2 * 3600


def test_der_cache_liegt_neben_der_datenbank(tmp_path):
    pfad = cache_datei("visual", db_path=tmp_path / "jarvis.db")
    assert pfad == tmp_path / "tle" / "visual.tle"


def test_active_ist_bewusst_nicht_dabei():
    """Rund 10.000 Objekte, und CelesTrak bittet ausdruecklich um
    "one download per update" dafuer. Das ist kein Datensatz fuer eine
    Frage wie "was fliegt heute Abend ueber mich"."""
    assert "active" not in GRUPPEN
    assert set(GRUPPEN) == {"visual", "stations"}


# --- Das Werkzeug ----------------------------------------------------------


def _werkzeug(tmp_path, handler=None):
    import httpx

    from core.tools import registry
    import core.tools.satellite_tools  # noqa: F401

    w = registry.get("satellite_passes")
    w.db_path = tmp_path / "jarvis.db"
    # Bahndaten in den Zwischenspeicher legen, statt CelesTrak zu fragen -
    # im Test gibt es kein Netz, und im Betrieb soll es auch nicht bei
    # jeder Frage gefragt werden.
    ziel = cache_datei("visual", db_path=w.db_path)
    ziel.parent.mkdir(parents=True, exist_ok=True)
    ziel.write_text(TLE_TEXT, encoding="utf-8")
    return w


def test_das_werkzeug_liefert_ueberfluege(tmp_path):
    from tests.conftest import run

    w = _werkzeug(tmp_path)
    ergebnis = run(w.execute(lat=GMUEND[0], lon=GMUEND[1], hours=24))
    assert ergebnis.ok is True
    assert ergebnis.data["passes"], "ueber Mitteleuropa fliegt die ISS taeglich"

    # NICHT passes[0]: welcher Satellit ZUERST kommt, haengt an der Uhrzeit
    # des Testlaufs. Der Satz im TLE-Fixture enthaelt mehrere; ein Pruefer
    # bekam hier 48274 statt 25544, weil er zu einer anderen Stunde lief.
    # Ein Test, der je nach Tageszeit anders ausgeht, misst nichts - er
    # erzeugt nur Misstrauen gegen die ganze Suite.
    #
    # Die Aussage, um die es geht, ist "die ISS fliegt taeglich ueber
    # Mitteleuropa" - also: sie ist DABEI, nicht: sie ist die erste.
    norads = {p["norad"] for p in ergebnis.data["passes"]}
    assert 25544 in norads, sorted(norads)
    for p in ergebnis.data["passes"]:
        assert p["von"] in HIMMELSRICHTUNGEN_ERWARTET, p
    assert "UTC" in ergebnis.display


HIMMELSRICHTUNGEN_ERWARTET = {
    "N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
}


def test_das_werkzeug_behauptet_keine_sichtbarkeit(tmp_path):
    """Ob man den Ueberflug SIEHT, haengt an Sonnenstand und Erdschatten.
    Das wird hier nicht gerechnet - also auch nicht behauptet."""
    from tests.conftest import run

    ergebnis = run(_werkzeug(tmp_path).execute(lat=GMUEND[0], lon=GMUEND[1]))
    assert "NICHT" in ergebnis.display
    assert "blossem Auge" in ergebnis.display


def test_am_nordpol_meldet_das_werkzeug_null_und_erklaert_es(tmp_path):
    from tests.conftest import run

    ergebnis = run(_werkzeug(tmp_path).execute(lat=NORDPOL[0], lon=NORDPOL[1]))
    assert ergebnis.ok is True, "Null Ueberfluege ist kein Fehler"
    assert ergebnis.data["passes"] == []
    assert "51,6" in ergebnis.display


def test_unmoegliche_koordinaten_geben_einen_sauberen_fehler(tmp_path):
    from tests.conftest import run

    ergebnis = run(_werkzeug(tmp_path).execute(lat=91.0, lon=0.0))
    assert ergebnis.ok is False
    assert "90" in ergebnis.error


def test_es_wird_gesagt_ob_die_bahndaten_frisch_sind(tmp_path):
    """Sonst weiss niemand, ob er eine Vorhersage aus zwei Stunden alten
    oder aus zwei Wochen alten Daten liest."""
    from tests.conftest import run

    ergebnis = run(_werkzeug(tmp_path).execute(lat=GMUEND[0], lon=GMUEND[1]))
    assert "Zwischenspeicher" in ergebnis.display


def test_der_satelliten_agent_hat_das_werkzeug():
    from core.agents import baue_agenten
    from core.contracts import Permission
    from core.llm import FakeLLMProvider

    a = baue_agenten(FakeLLMProvider(), max_permission=Permission.READ)
    assert "satellite_passes" in a["satellite"].tools
