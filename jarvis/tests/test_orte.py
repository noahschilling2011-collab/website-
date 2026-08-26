"""Ortsname → Koordinate, weltweit.

Kein neuer Dienst: Wikidata spricht JARVIS schon. Gemessen am 26.08.2026
gegen den echten Endpunkt, hier als feste Antworten nachgestellt, damit
die Tests ohne Netz laufen.

    Tokio          -> Point(139.691666666 35.689444444)   EW 14.264.798
    New York City  -> Point(-74.006111111 40.712777777)   EW  8.804.190
    Gibtesnichtstadt123 -> nichts gefunden
"""

from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest

from core.orte import (
    Ort,
    OrtFehler,
    baue_frage,
    bbox_um,
    finde_ort,
    lies_punkt,
    maskiere,
)
from tests.conftest import run


def _antwort(*orte: dict) -> dict:
    return {
        "head": {"vars": ["ort", "ortLabel", "koord", "einwohner"]},
        "results": {"bindings": list(orte)},
    }


def _zeile(qid: str, label: str, lon: float, lat: float, ew: str | None = None):
    z = {
        "ort": {"type": "uri", "value": f"http://www.wikidata.org/entity/{qid}"},
        "ortLabel": {"type": "literal", "value": label},
        "koord": {"type": "literal", "value": f"Point({lon} {lat})"},
    }
    if ew is not None:
        z["einwohner"] = {"type": "literal", "value": ew}
    return z


GMUEND = _zeile("Q4037", "Schwäbisch Gmünd", 9.8, 48.8, "62726")


def _client(handler, kontakt="kontakt@example.org"):
    return dict(kontakt=kontakt, transport=httpx.MockTransport(handler))


# --- Die Koordinate lesen --------------------------------------------------


def test_wkt_nennt_die_laenge_zuerst():
    """Wer das dreht, landet im Indischen Ozean statt in Schwaebisch Gmuend."""
    lat, lon = lies_punkt("Point(9.8 48.8)")
    assert (lat, lon) == (48.8, 9.8)


def test_negative_koordinaten_gehen():
    lat, lon = lies_punkt("Point(-74.006111111 40.712777777)")
    assert lat == pytest.approx(40.7127, abs=1e-3)
    assert lon == pytest.approx(-74.0061, abs=1e-3)


@pytest.mark.parametrize("kaputt", ["", "Polygon(1 2)", "Point()", "nix", "Point(9.8)"])
def test_was_keine_koordinate_ist_wird_gemeldet(kaputt):
    with pytest.raises(OrtFehler):
        lies_punkt(kaputt)


def test_eine_koordinate_ausserhalb_der_erde_wird_abgewiesen():
    with pytest.raises(OrtFehler):
        lies_punkt("Point(9.8 200.0)")


# --- SPARQL-Injektion ------------------------------------------------------


def test_ein_anfuehrungszeichen_bricht_die_abfrage_nicht_auf():
    """Der Name kommt vom Nutzer und wandert in ein String-Literal."""
    boese = 'x" } ?s ?p ?o . #'
    frage = baue_frage(boese)
    assert '\\"' in frage
    # Nach dem Maskieren darf kein unmaskiertes Anfuehrungszeichen mehr
    # zwischen den Namensgrenzen stehen.
    assert frage.count('"') % 2 == 0


def test_ein_backslash_wird_maskiert():
    assert maskiere("a\\b") == "a\\\\b"


@pytest.mark.parametrize("boese", ["a\nb", "a\rb", "a\tb"])
def test_zeilenumbrueche_werden_abgewiesen_statt_maskiert(boese):
    """Ein Ortsname hat keine. Was hier ankommt, kommt vom Nutzer."""
    with pytest.raises(OrtFehler):
        maskiere(boese)


def test_ein_leerer_name_wird_abgewiesen():
    with pytest.raises(OrtFehler):
        maskiere("   ")


def test_ein_unsinnig_langer_name_wird_abgewiesen():
    with pytest.raises(OrtFehler):
        maskiere("x" * 500)


# --- Der Abruf -------------------------------------------------------------


def test_der_beste_treffer_kommt_zurueck():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(GMUEND))

    ort = run(finde_ort("Schwäbisch Gmünd", **_client(handler)))
    assert isinstance(ort, Ort)
    assert ort.qid == "Q4037"
    assert (ort.lat, ort.lon) == (48.8, 9.8)
    assert ort.einwohner == 62726
    assert ort.weitere_treffer == 0


def test_derselbe_ort_mehrfach_zaehlt_einmal():
    """Wikidata liefert einen Ort so oft, wie er Einwohner-Angaben hat -
    verschiedene Stichjahre. Entdoppelt wird ueber die Entitaets-URI, nicht
    ueber den Namen: zwei Orte duerfen gleich heissen."""
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(
            _zeile("Q4037", "Schwäbisch Gmünd", 9.8, 48.8, "62726"),
            _zeile("Q4037", "Schwäbisch Gmünd", 9.8, 48.8, "61216"),
            _zeile("Q4037", "Schwäbisch Gmünd", 9.8, 48.8, "59538"),
        ))

    ort = run(finde_ort("Schwäbisch Gmünd", **_client(handler)))
    assert ort.weitere_treffer == 0
    assert ort.einwohner == 62726, "die erste Zeile ist die groesste"


def test_mehrdeutigkeit_wird_gemeldet_nicht_versteckt():
    """Gemessen: "São Paulo" liefert nach Einwohnern sortiert den STAAT,
    nicht die Stadt. Das ist keine Panne, sondern eine echte
    Mehrdeutigkeit - und der Nutzer soll sie sehen koennen."""
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort(
            _zeile("Q175", "São Paulo (Staat)", -48.43, -22.07, "45595497"),
            _zeile("Q174", "São Paulo", -46.63, -23.55, "12325232"),
        ))

    ort = run(finde_ort("São Paulo", **_client(handler)))
    assert ort.qid == "Q175"
    assert ort.weitere_treffer == 1


def test_nichts_gefunden_ist_none_kein_fehler():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_antwort())

    assert run(finde_ort("Gibtesnichtstadt123", **_client(handler))) is None


def test_ohne_kontakt_wird_gar_nicht_erst_gefragt():
    """Wikimedia verlangt einen User-Agent mit Kontaktangabe. Ohne den wird
    nicht angefragt - nicht 'mal probieren'."""
    def handler(_: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("Es haette gar nicht gefragt werden duerfen")

    # NICHT "Berlin": das steht seit der eingebauten Tabelle drin und
    # wuerde gar nicht mehr live gefragt. Ein Berg tut es.
    with pytest.raises(OrtFehler) as fehler:
        run(finde_ort("Kilimandscharo", **_client(handler, kontakt="  ")))
    assert "WIKI_KONTAKT" in str(fehler.value)


def test_der_user_agent_traegt_den_kontakt():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["ua"] = request.headers.get("user-agent", "")
        gesehen["url"] = str(request.url)
        return httpx.Response(200, json=_antwort(GMUEND))

    run(finde_ort("Schwäbisch Gmünd", **_client(handler, kontakt="noah@example.org")))
    assert "noah@example.org" in gesehen["ua"]
    assert "JARVIS" in gesehen["ua"]
    assert gesehen["url"].startswith("https://query.wikidata.org/sparql")


def test_ein_serverfehler_wird_gemeldet():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="wartung")

    with pytest.raises(OrtFehler) as fehler:
        run(finde_ort("Kilimandscharo", **_client(handler)))
    assert "503" in str(fehler.value)


def test_kein_json_ist_ein_fehler():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="<html>wartung</html>")

    with pytest.raises(OrtFehler):
        run(finde_ort("Kilimandscharo", **_client(handler)))


# --- Der Ausschnitt --------------------------------------------------------


def test_die_bbox_umschliesst_den_punkt():
    min_lon, min_lat, max_lon, max_lat = bbox_um(48.8, 9.8, kante_km=12.0)
    assert min_lat < 48.8 < max_lat
    assert min_lon < 9.8 < max_lon


def test_zwoelf_kilometer_ergeben_gut_zwanzig_meter_je_pixel():
    """Der Grund fuer die Vorgabe: 12 km auf 512 Bildpixeln sind rund 23 m -
    nahe an der Sentinel-2-Sensorgrenze und damit das Schaerfste, was
    ueberhaupt zu holen ist."""
    from core.satellite.cdse import effektive_aufloesung_m

    m = effektive_aufloesung_m(bbox_um(48.8, 9.8, kante_km=12.0), 512, 512)
    assert 20 < m < 30


def test_nahe_am_pol_laeuft_der_ausschnitt_nicht_um_die_erde():
    """Der Kosinus der Breite wird dort winzig. Ohne Untergrenze waere der
    Ausschnitt in Laengenrichtung breiter als ein Kontinent."""
    min_lon, _, max_lon, _ = bbox_um(89.5, 0.0, kante_km=12.0)
    assert (max_lon - min_lon) < 5.0


def test_eine_bbox_verlaesst_die_erde_nicht():
    min_lon, min_lat, max_lon, max_lat = bbox_um(89.99, 179.99, kante_km=50.0)
    assert -180.0 <= min_lon and max_lon <= 180.0
    assert -90.0 <= min_lat and max_lat <= 90.0


def test_eine_kantenlaenge_von_null_wird_abgewiesen():
    with pytest.raises(OrtFehler):
        bbox_um(48.8, 9.8, kante_km=0)


# --- Die eingebaute Tabelle: jedes Land, jede Hauptstadt ------------------


def test_die_tabelle_kennt_die_ganze_welt():
    """Erzeugt von scripts/orte_tabelle.py aus Wikidata. Wenn hier etwas
    fehlt, ist die Datei kaputt - nicht der Test."""
    from core.orte import tabelle

    roh = json.loads(
        (Path(__file__).resolve().parent.parent / "core" / "daten" / "orte.json")
        .read_text(encoding="utf-8")
    )
    assert roh["laender"] >= 190, f"nur {roh['laender']} Laender"
    assert roh["hauptstaedte"] >= 190, f"nur {roh['hauptstaedte']} Hauptstaedte"
    assert len(tabelle()) > 500, "zu wenig Namen im Index"


@pytest.mark.parametrize("eingabe,erwartet_iso", [
    ("Deutschland", "DEU"), ("Germany", "DEU"), ("Berlin", "DEU"),
    ("Japan", "JPN"), ("Tokyo", "JPN"), ("Tokio", "JPN"),
    ("Vereinigte Staaten", "USA"), ("United States", "USA"),
    ("Washington, D.C.", "USA"),
    ("Schweiz", "CHE"), ("Bern", "CHE"),
    ("Brasilien", "BRA"), ("Brasília", "BRA"),
    ("Kigali", "RWA"), ("Suva", "FJI"), ("Palikir", "FSM"),
    ("Nuku'alofa", "TON"),
])
def test_laender_und_hauptstaedte_weltweit(eingabe, erwartet_iso):
    from core.orte import aus_tabelle

    ort = aus_tabelle(eingabe)
    assert ort is not None, f"{eingabe!r} nicht gefunden"
    assert ort.iso3 == erwartet_iso


@pytest.mark.parametrize("kuerzel,iso3", [
    ("DE", "DEU"), ("DEU", "DEU"), ("de", "DEU"),
    ("US", "USA"), ("USA", "USA"),
    ("JP", "JPN"), ("CH", "CHE"), ("GB", "GBR"),
])
def test_auch_die_kuerzel_treffen(kuerzel, iso3):
    from core.orte import aus_tabelle

    assert aus_tabelle(kuerzel).iso3 == iso3


def test_ein_kuerzel_trifft_nur_exakt_und_nie_ueber_eine_faltung():
    """Der Falschtreffer, der beim Bauen auffiel: mit ISO-Codes im selben
    Index wie die Namen fand "Poel" (eine Insel in der Ostsee) das Land
    POLEN - "poel" wird durch die oe-Ersatzschreibung zu "pol", und das ist
    Polens ISO-Code. Kuerzel stehen deshalb in einem eigenen Index."""
    from core.orte import aus_tabelle

    assert aus_tabelle("Poel") is None, "Poel ist nicht Polen"
    assert aus_tabelle("Polen").iso3 == "POL"
    assert aus_tabelle("POL").iso3 == "POL"


@pytest.mark.parametrize("ohne_umlaut,mit_umlaut", [
    ("Aegypten", "Ägypten"), ("Tuerkei", "Türkei"),
    ("Vereinigtes Koenigreich", "Vereinigtes Königreich"),
])
def test_wer_keine_umlaute_tippt_findet_trotzdem(ohne_umlaut, mit_umlaut):
    from core.orte import aus_tabelle

    a, b = aus_tabelle(ohne_umlaut), aus_tabelle(mit_umlaut)
    assert a is not None and b is not None
    assert a.qid == b.qid


def test_gross_und_kleinschreibung_ist_egal():
    from core.orte import aus_tabelle

    assert aus_tabelle("SCHWEIZ").iso3 == aus_tabelle("schweiz").iso3 == "CHE"


def test_ein_land_gewinnt_gegen_die_gleichnamige_hauptstadt():
    """Luxemburg, Singapur, Monaco, Dschibuti, Guatemala: wer den Namen
    sagt, meint fast immer den Staat."""
    from core.orte import aus_tabelle

    for name in ("Monaco", "Luxemburg", "Singapur"):
        ort = aus_tabelle(name)
        assert ort is not None, name
        assert ort.art == "land", f"{name} sollte das Land sein"


def test_die_tabelle_kommt_ohne_netz_und_ohne_kontakt_aus():
    """Der Punkt der ganzen Datei. `finde_ort` wuerde ohne WIKI_KONTAKT
    werfen - fuer Laender und Hauptstaedte darf es das nicht."""
    from core.orte import finde_ort

    ort = run(finde_ort("Deutschland", kontakt=""))
    assert ort is not None
    assert ort.iso3 == "DEU"
    assert ort.als_dict()["quelle"] == "Tabelle"


def test_was_nicht_in_der_tabelle_steht_geht_live():
    """Berge, Kleinstaedte, Stadtteile - dafuer ist die Live-Abfrage da."""
    gefragt = {"ja": False}

    def handler(request: httpx.Request) -> httpx.Response:
        gefragt["ja"] = True
        return httpx.Response(200, json=_antwort(
            _zeile("Q7420", "Kilimandscharo", 37.3268, -3.3376)))

    ort = run(finde_ort("Kilimandscharo", kontakt="k@example.org",
                        transport=httpx.MockTransport(handler)))
    assert gefragt["ja"], "haette live fragen muessen"
    assert ort.name == "Kilimandscharo"
    assert ort.als_dict()["quelle"] == "Wikidata"


def test_ein_land_fragt_gar_nicht_erst_live():
    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("Fuer ein Land darf nicht gefragt werden")

    ort = run(finde_ort("Frankreich", kontakt="k@example.org",
                        transport=httpx.MockTransport(handler)))
    assert ort.iso3 == "FRA"


# --- Das Werkzeug: was der normale Chat benutzt ---------------------------


def _werkzeug(kontakt=""):
    from core.tools import registry
    import core.tools.satellite_tools  # noqa: F401

    w = registry.get("find_place")
    w.kontakt = kontakt
    return w


def test_das_werkzeug_findet_ein_land_ohne_netz_und_ohne_kontakt():
    """Der Fall, der Noah betrifft: kein WIKI_KONTAKT in der .env. Laender
    und Hauptstaedte muessen trotzdem gehen."""
    ergebnis = run(_werkzeug(kontakt="").execute(name="Japan"))
    assert ergebnis.ok is True
    assert ergebnis.data["ort"]["iso3"] == "JPN"
    assert ergebnis.data["ort"]["quelle"] == "Tabelle"
    assert len(ergebnis.data["bbox"]) == 4


def test_das_werkzeug_liefert_eine_fertige_bbox():
    """Der ganze Zweck: das Modell soll keine Koordinaten raten. In Noahs
    erstem echten Lauf schickte es bbox=[5.9,47.3,15,55.1] - fuer
    Deutschland zufaellig richtig, fuer eine Stadt waere es Unsinn."""
    ergebnis = run(_werkzeug().execute(name="Tokyo"))
    min_lon, min_lat, max_lon, max_lat = ergebnis.data["bbox"]
    ort = ergebnis.data["ort"]
    assert min_lat < ort["lat"] < max_lat
    assert min_lon < ort["lon"] < max_lon


def test_das_werkzeug_sagt_gleich_wie_scharf_das_bild_waere():
    klein = run(_werkzeug().execute(name="Bern", kante_km=12))
    gross = run(_werkzeug().execute(name="Bern", kante_km=400))
    assert klein.data["bild_aufloesung_m"] < 30
    assert gross.data["bild_aufloesung_m"] > 500
    assert "m je Bildpixel" in klein.display


def test_ein_unbekannter_ort_ist_ein_sauberer_fehler():
    ergebnis = run(_werkzeug(kontakt="").execute(name="Gibtesnichtstadt123"))
    assert ergebnis.ok is False
    assert "Hauptstadt" in ergebnis.display


def test_der_satelliten_agent_hat_das_werkzeug_und_die_regel():
    from core.agents import baue_agenten
    from core.contracts import Permission
    from core.llm import FakeLLMProvider

    a = baue_agenten(FakeLLMProvider(), max_permission=Permission.READ)["satellite"]
    assert "find_place" in a.tools
    assert "Rate NIE Koordinaten" in a.system_prompt
    # Und die Aufloesungsregel nennt nicht mehr die 10 m des Sensors als
    # das, was man sieht.
    assert "bild_aufloesung_m" in a.system_prompt
