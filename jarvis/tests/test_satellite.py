"""Tests des Satellite Agents (Phase 8).

Die Spezifikation steht in `docs/satellite.md`. Der groesste Teil davon
laesst sich ohne Zugangsdaten pruefen, weil er aus Regeln besteht und nicht
aus Bildern: Pflichtfelder, Aufloesungsgrenze, Vergleichbarkeit,
Ausgabeformat, Ablehnung von Beobachtungsanfragen.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import httpx
import pytest

from core.contracts import Permission
from core.llm import FakeLLMProvider
from core.satellite.analysis import (
    GRENZE_FAKTOR,
    bericht,
    beurteilbar,
    grenzsatz,
    nbr,
    ndvi,
    ndwi,
    vergleichbar,
    vergleiche_raster,
)
from core.satellite.cdse import (
    CDSEFehler,
    CDSEProvider,
    als_szene,
    baue_filter,
    bbox_als_polygon,
)
from core.satellite.contracts import Scene, SzeneUngueltig
from core.satellite.policy import UeberwachungAbgelehnt, pruefe_anfrage
from core.tools import registry
from core.tools.dispatch import run_tool
from tests.conftest import run

BBOX = (9.75, 48.76, 9.85, 48.83)
JETZT = datetime.now(timezone.utc)


def szene(**felder) -> Scene:
    standard = dict(
        scene_id="S2A_1", provider="cdse", sensor="Sentinel-2 MSI L2A",
        acquired_at=JETZT - timedelta(days=3), cloud_cover_pct=4.0,
        resolution_m=10.0, bbox=BBOX, preview_url=None,
        attribution="Enthaelt modifizierte Copernicus-Sentinel-Daten",
        license="Copernicus Sentinel Data Terms and Conditions",
    )
    standard.update(felder)
    return Scene(**standard)


# --- Pflichtfelder (A.4) --------------------------------------------------


def test_eine_szene_ohne_bodenaufloesung_ist_ungueltig():
    with pytest.raises(SzeneUngueltig, match="Bodenaufloesung"):
        szene(resolution_m=0)


def test_eine_szene_ohne_attribution_ist_ungueltig():
    """Copernicus-Daten haben Attributionspflichten."""
    with pytest.raises(SzeneUngueltig, match="Attribution"):
        szene(attribution="   ")


def test_eine_szene_ohne_zeitzone_ist_ungueltig():
    with pytest.raises(SzeneUngueltig, match="Zeitzone"):
        szene(acquired_at=datetime(2026, 1, 1))


@pytest.mark.parametrize("wolken", [-1.0, 101.0])
def test_unmoeglicher_wolkenanteil_wird_abgelehnt(wolken: float):
    with pytest.raises(SzeneUngueltig):
        szene(cloud_cover_pct=wolken)


def test_der_steckbrief_nennt_sensor_aufloesung_datum_und_wolken():
    """Genau das, was DoD 1 unter jedem Bild verlangt."""
    text = szene().steckbrief()
    assert "Sentinel-2 MSI L2A" in text
    assert "10 m/px" in text
    assert "4 % Wolken" in text
    assert "Copernicus" in text


# --- Aufloesungsgrenze (A.1) ----------------------------------------------


def test_ein_einfamilienhaus_ist_bei_10m_nicht_beurteilbar():
    """Der Kern des ganzen Anhangs: bei 10 m/px ist ein Haus ein Pixel."""
    assert beurteilbar(10, 10.0) is False


def test_ein_tagebau_ist_bei_10m_beurteilbar():
    assert beurteilbar(300, 10.0) is True


def test_die_grenze_liegt_beim_dreifachen_der_aufloesung():
    assert beurteilbar(GRENZE_FAKTOR * 10, 10.0) is True
    assert beurteilbar(GRENZE_FAKTOR * 10 - 0.1, 10.0) is False


def test_der_grenzsatz_nennt_konkrete_meter():
    assert "30 m" in grenzsatz(10.0)
    assert "90 m" in grenzsatz(30.0)   # Landsat


# --- Ausgabeformat (A.5) --------------------------------------------------


def test_der_bericht_hat_die_pflichtzeile_grenze():
    text = bericht("x", "y", "mittel", "z", 10.0)
    assert text.splitlines()[-1].startswith("GRENZE")
    for kopf in ("BEOBACHTET", "INTERPRETATION", "KONFIDENZ", "GRUNDLAGE"):
        assert kopf in text


def test_eine_erfundene_konfidenzstufe_wird_abgelehnt():
    with pytest.raises(ValueError):
        bericht("x", "y", "sehr sicher", "z", 10.0)


# --- Indizes und Vergleich (A.5) ------------------------------------------


def test_ndvi_rechnet_die_normalisierte_differenz():
    assert ndvi([0.6], [0.2]) == [pytest.approx(0.5)]
    assert ndwi([0.2], [0.6]) == [pytest.approx(-0.5)]
    assert nbr([0.5], [0.5]) == [0.0]


def test_division_durch_null_ergibt_null_statt_absturz():
    assert ndvi([0.0], [0.0]) == [0.0]


def test_unterschiedlich_grosse_raster_werden_abgelehnt():
    """Ohne Ko-Registrierung vergleicht man Versatz, nicht Veraenderung."""
    with pytest.raises(ValueError, match="Groesse"):
        vergleiche_raster([0.1, 0.2], [0.1], aufloesung_m=10)


def test_zu_grosse_raster_werden_abgelehnt_statt_minutenlang_gerechnet():
    with pytest.raises(ValueError, match="reinem Python"):
        vergleiche_raster([0.1] * 300_000, [0.1] * 300_000, aufloesung_m=10)


def test_die_veraenderte_flaeche_wird_in_hektar_gerechnet():
    # 100 Pixel a 10 x 10 m = 10 000 m2 = 1 ha
    v = vergleiche_raster([0.8] * 100, [0.2] * 100, aufloesung_m=10)
    assert v.veraendert_pixel == 100
    assert v.hektar == pytest.approx(1.0)
    assert v.mittlere_aenderung == pytest.approx(-0.6)


def test_kleine_schwankungen_gelten_nicht_als_veraenderung():
    v = vergleiche_raster([0.50] * 50, [0.55] * 50, aufloesung_m=10)
    assert v.veraendert_pixel == 0


# --- Vergleichbarkeit (A.5, Schritt 2) ------------------------------------


def test_sommer_gegen_winter_wird_abgelehnt_nicht_gerechnet():
    passt, grund = vergleichbar(
        datetime(2026, 1, 15, tzinfo=timezone.utc),
        datetime(2026, 7, 15, tzinfo=timezone.utc), 2, 3,
    )
    assert passt is False and "Jahreszeit" in grund


def test_aehnliche_jahreszeit_ist_vergleichbar():
    passt, _ = vergleichbar(
        datetime(2025, 6, 10, tzinfo=timezone.utc),
        datetime(2026, 7, 12, tzinfo=timezone.utc), 2, 3,
    )
    assert passt is True


def test_der_jahreswechsel_wird_richtig_gerechnet():
    """Dezember und Januar sind einen Monat auseinander, nicht elf."""
    passt, _ = vergleichbar(
        datetime(2025, 12, 20, tzinfo=timezone.utc),
        datetime(2026, 1, 18, tzinfo=timezone.utc), 2, 3,
    )
    assert passt is True


def test_zu_bewoelkt_wird_abgelehnt():
    passt, grund = vergleichbar(
        datetime(2026, 6, 10, tzinfo=timezone.utc),
        datetime(2026, 7, 12, tzinfo=timezone.utc), 2, 80,
    )
    assert passt is False and "bewoelkt" in grund.lower()


# --- Ueberwachung (A.6) ---------------------------------------------------


@pytest.mark.parametrize("anfrage", [
    "Beobachte das Grundstück von meinem Nachbarn",
    "Kannst du meinen Nachbarn überwachen?",
    "Zeig mir jeden Tag das Gelände und kontrollier, wer da ist",
    "Wo wohnt die Person mit dieser Privatadresse?",
])
def test_beobachtungsanfragen_werden_abgelehnt(anfrage: str):
    with pytest.raises(UeberwachungAbgelehnt):
        pruefe_anfrage(anfrage)


@pytest.mark.parametrize("anfrage", [
    "Zeig mir Abholzung im Amazonasbecken",
    "Wie groß war die Überschwemmungsfläche an der Ahr 2021?",
    "Hat sich der Tagebau Hambach im letzten Jahr ausgedehnt?",
    "Brandflächen in Griechenland im August",
])
def test_legitime_anfragen_kommen_durch(anfrage: str):
    pruefe_anfrage(anfrage)


def test_die_ablehnung_erklaert_warum_und_nennt_die_alternative():
    with pytest.raises(UeberwachungAbgelehnt) as exc:
        pruefe_anfrage("Beobachte das Grundstück von meinem Nachbarn")
    text = str(exc.value)
    assert "Umweltmonitoring" in text
    assert "ein einziges Pixel" in text


# --- CDSE (A.3) -----------------------------------------------------------


def test_der_odata_filter_schliesst_wolken_serverseitig_aus():
    """Erst 200 Szenen holen und lokal filtern ist die falsche Reihenfolge."""
    f = baue_filter(BBOX, datetime(2026, 7, 1, tzinfo=timezone.utc),
                    datetime(2026, 8, 1, tzinfo=timezone.utc), 20.0)
    assert "cloudCover" in f
    assert "le 20.00" in f
    assert "Collection/Name eq 'SENTINEL-2'" in f
    assert "OData.CSC.Intersects" in f
    assert "ContentDate/Start gt 2026-07-01T00:00:00.000Z" in f


def test_das_polygon_ist_geschlossen():
    wkt = bbox_als_polygon(BBOX)
    punkte = wkt[len("POLYGON(("):-2].split(", ")
    assert len(punkte) == 5 and punkte[0] == punkte[-1]


def test_ein_treffer_ohne_wolkenangabe_wird_verworfen():
    """Ohne Wolkenanteil laesst sich nicht sagen, ob das Bild brauchbar ist."""
    assert als_szene({"Id": "x", "ContentDate": {"Start": "2026-08-20T10:15:00.000Z"},
                      "Attributes": []}, BBOX) is None


def test_ein_gueltiger_treffer_wird_zur_szene():
    s = als_szene({
        "Id": "abc", "ContentDate": {"Start": "2026-08-20T10:15:00.000Z"},
        "Attributes": [{"Name": "cloudCover", "Value": 3.4},
                       {"Name": "instrumentShortName", "Value": "MSI"}],
    }, BBOX)
    assert s is not None
    assert s.resolution_m == 10.0
    assert s.cloud_cover_pct == pytest.approx(3.4)
    assert "Copernicus" in s.attribution


def test_ohne_zugangsdaten_wird_das_gesagt_statt_geraten():
    provider = CDSEProvider()
    assert provider.eingerichtet is False
    with pytest.raises(CDSEFehler, match="CDSE_CLIENT_ID"):
        run(provider.token())


def test_die_suche_sortiert_das_juengste_bild_nach_vorn():
    def handler(request: httpx.Request) -> httpx.Response:
        if "token" in str(request.url):
            return httpx.Response(200, json={"access_token": "t"})
        return httpx.Response(200, json={"value": [
            {"Id": "alt", "ContentDate": {"Start": "2026-08-01T10:00:00.000Z"},
             "Attributes": [{"Name": "cloudCover", "Value": 2.0}]},
            {"Id": "neu", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
             "Attributes": [{"Name": "cloudCover", "Value": 8.0}]},
        ]})

    provider = CDSEProvider("id", "secret", transport=httpx.MockTransport(handler))
    szenen = run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT))
    assert [s.scene_id for s in szenen] == ["neu", "alt"]


def test_abgelehnte_zugangsdaten_werden_gemeldet():
    def handler(request):
        return httpx.Response(401, json={"error": "invalid_client"})

    provider = CDSEProvider("id", "falsch", transport=httpx.MockTransport(handler))
    with pytest.raises(CDSEFehler, match="abgelehnt"):
        run(provider.token())


# --- Werkzeuge ------------------------------------------------------------


@pytest.fixture
def satellit_ohne_netz():
    tool = registry.get("satellite_search")
    alt = tool.provider
    yield tool
    tool.provider = alt


def test_dod_2_kein_bild_unter_dem_schwellwert_wird_gesagt(satellit_ohne_netz):
    """Und nicht ersatzweise ein wolkiges Bild ohne Hinweis geliefert."""
    def handler(request):
        if "token" in str(request.url):
            return httpx.Response(200, json={"access_token": "t"})
        return httpx.Response(200, json={"value": []})

    satellit_ohne_netz.provider = CDSEProvider(
        "id", "secret", transport=httpx.MockTransport(handler)
    )
    ergebnis = run(run_tool("satellite_search",
                            {"bbox": list(BBOX), "max_cloud_pct": 10}))
    assert ergebnis.ok is True
    assert ergebnis.data["scenes"] == []
    assert "Kein Sentinel-2-Bild unter 10 % Wolken" in ergebnis.display
    assert "3 bis 5 Tage" in ergebnis.display


def test_die_suche_liefert_datum_sensor_aufloesung_und_wolken(satellit_ohne_netz):
    """DoD 1, soweit ohne Zugangsdaten pruefbar."""
    def handler(request):
        if "token" in str(request.url):
            return httpx.Response(200, json={"access_token": "t"})
        return httpx.Response(200, json={"value": [
            {"Id": "neu", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
             "Attributes": [{"Name": "cloudCover", "Value": 3.0},
                            {"Name": "instrumentShortName", "Value": "MSI"}]},
        ]})

    satellit_ohne_netz.provider = CDSEProvider(
        "id", "secret", transport=httpx.MockTransport(handler)
    )
    ergebnis = run(run_tool("satellite_search", {"bbox": list(BBOX)}))
    assert ergebnis.ok is True
    szene_daten = ergebnis.data["scenes"][0]
    assert szene_daten["resolution_m"] == 10.0
    assert szene_daten["cloud_cover_pct"] == 3.0
    assert "2026-08-20" in szene_daten["acquired_at"]
    assert "10 m/px" in ergebnis.display
    assert "Objekte unter 30 m" in ergebnis.display


def test_ohne_zugangsdaten_sagt_das_werkzeug_was_fehlt(satellit_ohne_netz):
    satellit_ohne_netz.provider = CDSEProvider()
    ergebnis = run(run_tool("satellite_search", {"bbox": list(BBOX)}))
    assert ergebnis.ok is False and "CDSE_CLIENT_ID" in ergebnis.display


def test_eine_kaputte_bbox_wird_abgelehnt():
    ergebnis = run(run_tool("satellite_search", {"bbox": [10, 50, 9, 49]}))
    assert ergebnis.ok is False and "min < max" in (ergebnis.error or "")


def test_der_vergleich_lehnt_unterschiedliche_jahreszeiten_ab():
    ergebnis = run(run_tool("satellite_compare", {
        "before": [0.8] * 10, "after": [0.2] * 10,
        "before_date": "2026-01-15T00:00:00Z", "after_date": "2026-07-15T00:00:00Z",
    }))
    assert ergebnis.ok is False and "Jahreszeit" in (ergebnis.error or "")


def test_der_vergleich_rechnet_und_nennt_die_grenze():
    ergebnis = run(run_tool("satellite_compare", {
        "before": [0.8] * 100, "after": [0.2] * 100,
        "before_date": "2026-06-15T00:00:00Z", "after_date": "2026-07-15T00:00:00Z",
        "resolution_m": 10,
    }))
    assert ergebnis.ok is True
    assert ergebnis.data["changed_ha"] == pytest.approx(1.0)
    assert "Objekte unter 30 m" in ergebnis.display


def test_die_werkzeuge_sind_read():
    for name in ("satellite_search", "satellite_compare"):
        assert registry.get(name).permission is Permission.READ


def test_der_satellite_agent_ist_auf_read_gedeckelt():
    from core.agents import baue_agenten

    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.SENSITIVE)
    assert agenten["satellite"].max_permission is Permission.READ


def test_der_prompt_verbietet_aussagen_unter_der_aufloesung():
    """Die Regel selbst, nicht ihr Wortlaut.

    Hier stand `assert "EIN Pixel" in prompt` - ein Satz aus der alten
    Fassung ("Ein Einfamilienhaus ist damit EIN Pixel"). Der ist am
    26.08.2026 weggefallen, weil er eine falsche Zahl festschrieb: er
    rechnete mit den 10 m des SENSORS, waehrend das gelieferte Bild bei
    einem Stadtausschnitt 23 m und bei einem ganzen Land ueber 1000 m je
    Pixel hat. Der Test prueft jetzt, was die Regel leisten soll, statt wie
    sie formuliert ist - und ist damit strenger als vorher: er verlangt,
    dass der Prompt auf die BILDaufloesung verweist.
    """
    from core.agents import baue_agenten

    prompt = baue_agenten(FakeLLMProvider(),
                          max_permission=Permission.READ)["satellite"].system_prompt
    # Auf die wahre Zahl verweisen, nicht auf die des Sensors.
    assert "bild_aufloesung_m" in prompt
    # Und sagen, was daraus folgt.
    assert "halluziniert" in prompt
    assert "Benenne kein Objekt" in prompt
    assert "keine Live-Bilder" in prompt.replace("Es gibt keine Live-Bilder", "keine Live-Bilder")
    assert "GRENZE" in prompt


def test_der_agent_lehnt_beobachtungsauftraege_ab_bevor_ein_modell_laeuft():
    """Eine Ablehnung, die vom Tagesform eines Modells abhaengt, ist keine Regel."""
    from core.agents import baue_agenten
    from core.contracts import Step, Task, TaskBudget

    provider = FakeLLMProvider(replies=["ich würde jetzt suchen"])
    agent = baue_agenten(provider, max_permission=Permission.READ)["satellite"]
    task = Task(goal="Beobachte das Grundstück von meinem Nachbarn",
                budget=TaskBudget())
    ergebnis = run(agent.run(task, Step(id="s1", description="Bilder holen")))

    assert ergebnis.ok is False
    assert "Umweltmonitoring" in ergebnis.display
    assert provider.calls == [], "es haette kein Modell laufen duerfen"


def test_der_agent_arbeitet_legitime_auftraege_normal_ab():
    from core.agents import baue_agenten
    from core.contracts import Step, Task, TaskBudget

    provider = FakeLLMProvider(replies=["Ich schaue nach Abholzung."])
    agent = baue_agenten(provider, max_permission=Permission.READ)["satellite"]
    task = Task(goal="Zeig mir Abholzung im Amazonasbecken", budget=TaskBudget())
    ergebnis = run(agent.run(task, Step(id="s1", description="Szenen suchen")))
    assert ergebnis.ok is True and len(provider.calls) == 1
