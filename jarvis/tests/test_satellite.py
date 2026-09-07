"""Tests des Satellite Agents (Phase 8).

Die Spezifikation steht in `docs/satellite.md`. Der groesste Teil davon
laesst sich ohne Zugangsdaten pruefen, weil er aus Regeln besteht und nicht
aus Bildern: Pflichtfelder, Aufloesungsgrenze, Vergleichbarkeit,
Ausgabeformat, Ablehnung von Beobachtungsanfragen.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import time

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


def test_die_endpunkte_haben_die_neue_pfadform():
    """CDSE hat am 09.03.2026 angekuendigt: aus /api/<version>/<service>
    wird /<service>/<version>. Die Altform antwortet noch, ist aber fuer
    die Abkuendigung vorgemerkt.

    Der Test prueft die FORM, nicht die Erreichbarkeit - das Netz ist in
    tests/conftest.py gesperrt, und das ist richtig so. Nachgemessen wurde
    ausserhalb der Suite, am 29.08.2026:

        POST /process/v1     -> 401   (geroutet)
        POST /statistics/v1  -> 401   (geroutet)
        POST /gibtesnicht/v9 -> 503   (nicht geroutet)
    """
    from core.satellite.cdse import PROCESS_URL, STATISTICS_URL

    for url in (PROCESS_URL, STATISTICS_URL):
        pfad = url.split("copernicus.eu", 1)[1]
        assert not pfad.startswith("/api/"), (
            f"{url} benutzt die abgekuendigte Altform /api/<version>/<service>")
        teile = [t for t in pfad.split("/") if t]
        assert len(teile) == 2 and teile[1].startswith("v"), pfad


def test_der_katalog_bekommt_keinen_token():
    """Der OData-Katalog ist offen - und lehnt einen Token ab, den er nicht
    kennt. Gemessen am 29.08.2026 gegen den echten Endpunkt:

        GET .../odata/v1/Products?$top=1  ohne Header       -> HTTP 200
        dieselbe URL mit einem falschen Bearer              -> HTTP 403

    Ein Authorization-Header macht aus einer funktionierenden Suche also
    eine 403 - die sich wie "Kontingent erschoepft" liest, aber
    selbstgemacht ist. Nebenwirkung, die hier mitgeprueft wird: die Suche
    braucht dann ueberhaupt keine Zugangsdaten mehr.
    """
    gesehen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        if "token" in str(request.url):
            raise AssertionError("die Suche hat einen Token geholt")
        gesehen["auth"] = request.headers.get("Authorization")
        return httpx.Response(200, json={"value": []})

    # Bewusst OHNE client_id/secret: die Suche muss trotzdem laufen.
    provider = CDSEProvider(transport=httpx.MockTransport(handler))
    run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT))
    assert gesehen["auth"] is None, gesehen["auth"]


def test_der_token_wird_nicht_ewig_behalten():
    """Frueher stand im Code `if self._token: return self._token`. Ein
    Keycloak-Token lebt nicht ewig - das Beispiel-Token im
    CDSE-Beginners-Guide hat exp minus iat = 600 Sekunden. Ein Server, der
    laenger laeuft, haette ab dann bei jedem Bild eine 401 bekommen.

    Geprueft wird die Ablaufrechnung selbst, ohne echte Uhrzeit: bei
    expires_in=600 muss die Frist 540 Sekunden in der Zukunft liegen (600
    minus 60 Sekunden Sicherheitsabstand).
    """
    rufe = []

    def handler(request: httpx.Request) -> httpx.Response:
        rufe.append(str(request.url))
        return httpx.Response(200, json={"access_token": "t", "expires_in": 600})

    provider = CDSEProvider("id", "secret", transport=httpx.MockTransport(handler))
    run(provider.token())
    assert len(rufe) == 1

    # Noch gueltig -> kein zweiter Aufruf.
    run(provider.token())
    assert len(rufe) == 1, "der Token wurde unnoetig neu geholt"

    # Die Frist liegt 600 - 60 = 540 s in der Zukunft.
    rest = provider._token_bis - time.monotonic()
    assert 530 < rest <= 540, rest

    # Abgelaufen -> neu holen.
    provider._token_bis = time.monotonic() - 1
    run(provider.token())
    assert len(rufe) == 2, "der abgelaufene Token wurde weiterbenutzt"


def test_ohne_expires_in_wird_der_token_nur_kurz_behalten():
    """Fehlt das Feld, wird nicht geraten, sondern kurz gecacht: lieber ein
    Aufruf zu viel als eine Stunde 401.

    Dieser Test hat in seinem ersten Lauf einen echten Fehler gefunden: der
    Ersatzwert war 60 Sekunden, davon 60 Sekunden Sicherheitsabstand
    abgezogen - macht 0. Der Token waere bei JEDEM Aufruf neu geholt
    worden."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"access_token": "t"})

    provider = CDSEProvider("id", "secret", transport=httpx.MockTransport(handler))
    run(provider.token())
    rest = provider._token_bis - time.monotonic()
    assert 25 < rest <= 30, rest


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


# --- beurteilbar() tut endlich Arbeit (Verknuepfungspruefung, 30.08.2026) ---


def test_die_aufloesungsgrenze_wirkt_wirklich_und_nicht_nur_im_prompt():
    """STATUS.md sagte: "Die Aufloesungsgrenze ist Code, keine Bitte."

    Sie war eine Bitte. `beurteilbar()` wurde von NICHTS im Betrieb
    aufgerufen - nur von Tests. Die Grenze stand als Prosa im Systemprompt
    und als Hinweissatz unter dem Ergebnis; wenn das Modell sie ignorierte,
    hinderte es niemand.

    Im Werkzeug selbst kann sie nicht greifen: dort kommt nie eine
    Objektgroesse an. In `Vergleich` schon - die veraenderte Flaeche HAT
    eine Kantenlaenge.
    """
    from core.satellite.analysis import vergleiche_raster

    # 4 von 100 Pixeln bei 10 m/px = 400 m2 = 20 m Kante. Grenze: 30 m.
    klein = vergleiche_raster([0.8] * 100, [0.8] * 96 + [0.1] * 4,
                              aufloesung_m=10.0)
    assert klein.beurteilbar is False, klein.als_dict()
    assert "zu klein" in klein.grenzhinweis()
    assert "20 m" in klein.grenzhinweis() and "30 m" in klein.grenzhinweis()

    # 100 von 100 Pixeln = 10.000 m2 = 100 m Kante. Weit ueber der Grenze.
    gross = vergleiche_raster([0.8] * 100, [0.1] * 100, aufloesung_m=10.0)
    assert gross.beurteilbar is True, gross.als_dict()
    assert gross.grenzhinweis() == ""

    # Und die Zahl bleibt in BEIDEN Faellen erhalten. Ein Abbruch wuerde
    # eine korrekte Messung wegwerfen.
    assert klein.hektar == pytest.approx(0.04)
    assert gross.hektar == pytest.approx(1.0)


def test_der_grenzhinweis_steht_im_werkzeugergebnis():
    """Ein Befund im Objekt, den niemand ausgibt, ist derselbe Fehler noch
    einmal - nur eine Ebene hoeher."""
    tool = registry.get("satellite_compare")

    def lauf(after):
        return run(tool.execute(before=[0.8] * 100, after=after,
                                before_date="2024-07-01",
                                after_date="2024-07-20", resolution_m=10.0))

    klein = lauf([0.8] * 96 + [0.1] * 4)
    assert klein.ok is True
    assert klein.data["beurteilbar"] is False
    assert "zu klein" in klein.display, klein.display

    gross = lauf([0.1] * 100)
    assert gross.data["beurteilbar"] is True
    assert "zu klein" not in gross.display, gross.display
    # Der allgemeine Grenzsatz bleibt in beiden Faellen stehen.
    for r in (klein, gross):
        assert "nicht beurteilbar" in r.display


# ===========================================================================
# FIX-12, Gruppe 4: was passiert, wenn CDSE und CelesTrak fehlen
# ===========================================================================
#
# Der Auftrag: "Features muessen auch dann stabil bleiben, wenn folgende
# Dienste fehlen: echtes LLM, CDSE, externer Kalender, externe APIs.
# Fehlende Dienste duerfen keinen Crash des Gesamtsystems verursachen."
#
# Nachgestellt wird jeder Ausfall mit `httpx.MockTransport` - kein Netz.
# Gemessen VOR der Reparatur (ueber `run_tool`, also auf dem Weg, den das
# Modell wirklich nimmt):
#
#   Katalog-Timeout      -> ReadTimeout flog aus dem Werkzeug,
#                           "satellite_search ist mit einem Fehler ausgestiegen"
#   Katalog kaputtes JSON-> JSONDecodeError, dieselbe Meldung
#   Katalog value=null   -> ok=True, "Kein Sentinel-2-Bild unter 20 % Wolken"
#                           (eine Auskunft, die es so nicht gab)
#   Bilddienst weg       -> ConnectError, die schon gefundene Szene war weg
#   CelesTrak weg        -> ConnectError, "satellite_passes ist mit einem
#                           Fehler ausgestiegen"
#
# Zwei Zusagen laufen mit: kein Wurf schlaegt nach oben durch, und weder
# Secret noch Token stehen jemals in einer Ausgabe.

import json as _json
from unittest import mock as _mock

GEHEIM_ID = "KUNDE-GEHEIM-xyz"
GEHEIM_SECRET = "SECRET-GEHEIM-xyz"
GEHEIM_TOKEN = "TOKEN-GEHEIM-xyz"
CDSE_GEHEIMNISSE = [GEHEIM_ID, GEHEIM_SECRET, GEHEIM_TOKEN]

EIN_TREFFER = {"value": [
    {"Id": "neu", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
     "Attributes": [{"Name": "cloudCover", "Value": 3.0},
                    {"Name": "instrumentShortName", "Value": "MSI"}]},
]}
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 200


def _wirft(klasse, text="kaputt"):
    def handler(request):
        raise klasse(text, request=request)
    return handler


def _cdse(token_h=None, katalog_h=None, bild_h=None):
    """Ein Transport, der die drei CDSE-Endpunkte auseinanderhaelt."""
    def token_standard(r):
        return httpx.Response(200, request=r,
                              json={"access_token": GEHEIM_TOKEN,
                                    "expires_in": 600})

    def katalog_standard(r):
        return httpx.Response(200, request=r, json=EIN_TREFFER)

    def bild_standard(r):
        return httpx.Response(200, request=r, content=PNG,
                              headers={"content-type": "image/png"})

    def handler(request):
        adresse = str(request.url)
        if "token" in adresse:
            return (token_h or token_standard)(request)
        if "sh.dataspace" in adresse:
            return (bild_h or bild_standard)(request)
        return (katalog_h or katalog_standard)(request)

    return httpx.MockTransport(handler)


def _leckt_cdse(ergebnis) -> list[str]:
    text = (f"{ergebnis.display or ''} {ergebnis.error or ''} "
            f"{_json.dumps(ergebnis.data, default=str)}")
    return [g for g in CDSE_GEHEIMNISSE if g in text]


def _suche(satellit, tmp_path, transport, **kw):
    satellit.provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET,
                                     transport=transport)
    satellit.db_path = tmp_path / "jarvis.db"
    return run(run_tool("satellite_search", {"bbox": list(BBOX), **kw}))


# --- Fall 1 und 2: Zeitueberschreitung und Verbindungsfehler --------------


@pytest.mark.parametrize("klasse", [
    httpx.ReadTimeout, httpx.TimeoutException, httpx.ConnectTimeout,
    httpx.ConnectError, httpx.ReadError,
])
def test_ein_katalogausfall_ist_eine_auskunft_und_kein_absturz(
    klasse, satellit_ohne_netz, tmp_path
):
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(katalog_h=_wirft(klasse)))
    assert e.ok is False
    assert "ausgestiegen" not in (e.error or ""), e.error
    assert "CDSE" in (e.error or "")
    assert klasse.__name__ in (e.error or "")
    assert _leckt_cdse(e) == [], _leckt_cdse(e)


def test_ein_timeout_wird_als_zeitueberschreitung_benannt():
    """Ein Dienst, der nicht antwortet, ist etwas anderes als einer, der
    nicht erreichbar ist - beim ersten hilft warten."""
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET,
                            transport=_cdse(katalog_h=_wirft(httpx.ReadTimeout)))
    with pytest.raises(CDSEFehler, match="nicht innerhalb"):
        run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT))


@pytest.mark.parametrize("klasse", [httpx.ReadTimeout, httpx.ConnectError])
def test_ein_ausfall_des_bilddienstes_wirft_die_szene_nicht_weg(
    klasse, satellit_ohne_netz, tmp_path
):
    """Der Code sagt selbst: "Kein Grund, den ganzen Aufruf scheitern zu
    lassen: die Metadaten sind da und sind etwas wert." Fuer CDSEFehler galt
    das auch - fuer einen Netzausfall nicht: der ConnectError lief an dem
    `except` vorbei und riss die schon gefundene Szene mit."""
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(bild_h=_wirft(klasse)))
    assert e.ok is True, e.error
    assert e.data["scenes"][0]["scene_id"] == "neu"
    assert e.data["preview_url"] is None
    assert "Kein Bild gerendert" in e.display
    assert _leckt_cdse(e) == [], _leckt_cdse(e)


# --- Fall 3 und 4: HTTP 500, HTTP 429 mit und ohne Retry-After ------------


@pytest.mark.parametrize("status,kopfzeilen", [
    (500, {}), (502, {}), (429, {}), (429, {"Retry-After": "60"}),
    (403, {}),
])
def test_ein_fehlerstatus_des_katalogs_nennt_die_zahl(
    status, kopfzeilen, satellit_ohne_netz, tmp_path
):
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        katalog_h=lambda r: httpx.Response(status, request=r,
                                           headers=kopfzeilen)))
    assert e.ok is False
    assert f"HTTP {status}" in (e.error or "")
    assert _leckt_cdse(e) == [], _leckt_cdse(e)


@pytest.mark.parametrize("status", [401, 429, 500])
def test_ein_fehlerstatus_beim_token_gilt_nicht_als_erfolg(
    status, satellit_ohne_netz, tmp_path
):
    """Ohne Token gibt es kein Bild - aber die Metadaten bleiben. Wichtig
    ist, dass daraus kein stiller Erfolg wird: `preview_url` bleibt None und
    es steht dabei, dass kein Bild kam."""
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        token_h=lambda r: httpx.Response(status, request=r,
                                         json={"error": "invalid_client"})))
    assert e.ok is True
    assert e.data["preview_url"] is None
    assert "Kein Bild gerendert" in e.display
    assert _leckt_cdse(e) == [], _leckt_cdse(e)


# --- Fall 5: unerwartete Form --------------------------------------------


@pytest.mark.parametrize("antwort", [
    {"text": "{das ist kein json"},
    {"text": "<html>Wartung</html>"},
])
def test_eine_katalogantwort_ohne_json_wird_gemeldet(
    antwort, satellit_ohne_netz, tmp_path
):
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, **antwort)))
    assert e.ok is False
    assert "kein JSON" in (e.error or "")
    assert "ausgestiegen" not in (e.error or "")


@pytest.mark.parametrize("koerper", [
    {"value": None},
    {"value": "keine Liste"},
    {"kein_value": 1},
    [1, 2, 3],
])
def test_eine_kaputte_trefferliste_ist_kein_leeres_ergebnis(
    koerper, satellit_ohne_netz, tmp_path
):
    """Der gefaehrlichste der sechs Faelle: vorher kam bei `value: null`
    ok=True und "Kein Sentinel-2-Bild unter 20 % Wolken in den letzten 30
    Tagen" heraus, samt Rat, das Suchfenster zu vergroessern. Das ist eine
    Auskunft ueber Wolken, die es nie gegeben hat.

    "Nichts gefunden" und "die Antwort war kaputt" sind zwei verschiedene
    Dinge - genauso wie beim Kalender ein leerer und ein nicht eingerichteter
    Kalender."""
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json=koerper)))
    assert e.ok is False, e.display
    assert "Kein Sentinel-2-Bild" not in e.display
    assert "weiss es nur nicht" in (e.error or "") or "Form" in (e.error or "")


@pytest.mark.parametrize("koerper", [
    {"access_token": None},
    {"foo": "bar"},
    {"access_token": ""},
])
def test_eine_tokenantwort_ohne_token_gilt_nicht_als_zugang(koerper):
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        token_h=lambda r: httpx.Response(200, request=r, json=koerper)))
    with pytest.raises(CDSEFehler, match="access_token"):
        run(provider.token())


@pytest.mark.parametrize("antwort", [
    {"text": ""},
    {"text": "{kaputt"},
    {"json": [1, 2, 3]},
])
def test_eine_unlesbare_tokenantwort_wirft_keinen_json_fehler(antwort):
    """Gemessen: `antwort.json()` warf `JSONDecodeError` bei leerem Koerper
    und `.get()` einen `AttributeError`, wenn eine Liste kam. Beides lief
    ungebremst durch das Werkzeug."""
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        token_h=lambda r: httpx.Response(200, request=r, **antwort)))
    with pytest.raises(CDSEFehler):
        run(provider.token())


def test_ein_katalogtreffer_in_falscher_form_kippt_die_suche_nicht():
    """Zeichenketten statt Objekten, `ContentDate` als Liste, `Attributes`
    als Text - alles gemessen und alles vorher ein AttributeError."""
    kaputt = {"value": [
        "nur text", 42, None,
        {"Id": "x", "ContentDate": ["2026-08-20"], "Attributes": []},
        {"Id": "y", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": "keine Liste"},
        {"Id": "gut", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": [{"Name": "cloudCover", "Value": 3.0}]},
    ]}
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json=kaputt)))
    szenen = run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT))
    assert [s.scene_id for s in szenen] == ["gut"]


def test_attribute_die_sich_gar_nicht_durchlaufen_lassen(monkeypatch):
    """Nachgetragen bei der Abnahme. Der Test darueber deckt `Attributes` als
    Text ab - und blieb gruen, als die Formpruefung entfernt wurde: ueber
    eine Zeichenkette laesst sich laufen, jedes Zeichen ist nur kein `dict`.

    Eine Zahl ist der Fall, der wirklich bricht: `for att in 42` wirft
    TypeError, und der kaeme roh aus dem Werkzeug heraus.
    """
    kaputt = {"value": [
        {"Id": "zahl", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": 42},
        {"Id": "null", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": None},
        {"Id": "gut", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": [{"Name": "cloudCover", "Value": 3.0}]},
    ]}
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json=kaputt)))
    szenen = run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT))
    # Ohne Bewoelkungsangabe faellt eine Szene durch den Schwellwert; keine
    # davon darf das Werkzeug zum Absturz bringen.
    assert "gut" in [s.scene_id for s in szenen]


def _top(url: str) -> str | None:
    """Der Wert von `$top` aus einer Katalogadresse, exakt."""
    import urllib.parse

    werte = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
    return (werte.get("$top") or [None])[0]


def test_der_katalog_bestellt_hoechstens_fuenfzig_treffer():
    """`$top` ist die Bestellmenge. Ein Modell, das `limit=5000` schreibt,
    darf nicht 5.000 Produkte anfordern - jedes davon wird ausgepackt und
    bewertet. Die Zahl steht in der Adresse, also wird sie dort gemessen."""
    gesehen: list[str] = []

    def katalog(request: httpx.Request) -> httpx.Response:
        gesehen.append(str(request.url))
        return httpx.Response(200, request=request, json={"value": []})

    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET,
                            transport=_cdse(katalog_h=katalog))
    run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT, limit=5000))
    assert gesehen, "der Katalog wurde gar nicht gefragt"
    # Genau gelesen, nicht als Teilzeichenkette gesucht: "$top=50" steckt
    # auch in "$top=5000", und der Test war damit gruen, obwohl der Deckel
    # weg war.
    assert _top(gesehen[0]) == "50", gesehen[0]


def test_ein_kleiner_wunsch_bleibt_klein():
    """Gegenprobe: der Deckel ist eine Obergrenze, keine Vorgabe."""
    gesehen: list[str] = []

    def katalog(request: httpx.Request) -> httpx.Response:
        gesehen.append(str(request.url))
        return httpx.Response(200, request=request, json={"value": []})

    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET,
                            transport=_cdse(katalog_h=katalog))
    run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT, limit=3))
    assert _top(gesehen[0]) == "3", gesehen[0]


# --- Fall 6: leere und sehr grosse Antwort -------------------------------


def test_eine_leere_trefferliste_bleibt_ein_leeres_ergebnis(
    satellit_ohne_netz, tmp_path
):
    """Gegenprobe zu `test_eine_kaputte_trefferliste_ist_kein_leeres_ergebnis`
    - sonst waere jede Antwort ein Fehler."""
    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json={"value": []})))
    assert e.ok is True
    assert e.data["scenes"] == []
    assert "Kein Sentinel-2-Bild" in e.display


def test_fuenfzigtausend_treffer_werden_nicht_ausgepackt(
    satellit_ohne_netz, tmp_path
):
    """Gemessen: eine Katalogantwort mit 50.000 Treffern (8,9 MB) wurde
    vollstaendig in 50.000 Szenenobjekte verwandelt, obwohl `$top` nach
    zehn gefragt hatte - und der Kopf meldete dann "50000 Szene(n)
    gefunden". Was ueber die eigene Bitte hinausgeht, wird gar nicht erst
    ausgepackt."""
    viele = {"value": [
        {"Id": f"S2A_{i}", "ContentDate": {"Start": "2026-08-20T10:00:00.000Z"},
         "Attributes": [{"Name": "cloudCover", "Value": 3.0}]}
        for i in range(50_000)
    ]}
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json=viele)))
    szenen = run(provider.search(BBOX, JETZT - timedelta(days=30), JETZT,
                                 limit=10))
    assert len(szenen) == 10, len(szenen)

    e = _suche(satellit_ohne_netz, tmp_path, _cdse(
        katalog_h=lambda r: httpx.Response(200, request=r, json=viele)))
    assert e.ok is True
    assert len(e.data["scenes"]) <= 5
    assert len(e.display) < 5000, len(e.display)


# --- Ohne Zugangsdaten, und der Token bleibt drinnen ----------------------


def test_ohne_zugangsdaten_wird_nichts_geraten_und_nichts_geworfen(
    satellit_ohne_netz, tmp_path
):
    """CDSE hat in diesem Projekt keine Zugangsdaten. Das ist der Normalfall
    und muss ein Satz sein, kein Fehlerweg."""
    satellit_ohne_netz.provider = CDSEProvider()
    e = run(run_tool("satellite_search", {"bbox": list(BBOX)}))
    assert e.ok is False
    assert "CDSE_CLIENT_ID" in e.display
    assert "ausgestiegen" not in (e.error or "")

    satellit_ohne_netz.provider = None
    e = run(run_tool("satellite_search", {"bbox": list(BBOX)}))
    assert e.ok is False and "CDSE_CLIENT_ID" in e.display


def test_ein_abgelaufener_token_steht_in_keiner_ausgabe(
    satellit_ohne_netz, tmp_path
):
    """Der Token liegt im Speicher des Providers. Laeuft er ab und lehnt
    CDSE die Erneuerung ab, ist der Weg zum Nutzer der Fehlerweg - und
    genau dort darf er nicht auftauchen."""
    provider = CDSEProvider(GEHEIM_ID, GEHEIM_SECRET, transport=_cdse(
        token_h=lambda r: httpx.Response(401, request=r,
                                         json={"error": "invalid_token"})))
    provider._token = GEHEIM_TOKEN
    provider._token_bis = time.monotonic() - 1          # abgelaufen
    satellit_ohne_netz.provider = provider
    satellit_ohne_netz.db_path = tmp_path / "jarvis.db"

    e = run(run_tool("satellite_search", {"bbox": list(BBOX)}))
    assert _leckt_cdse(e) == [], _leckt_cdse(e)
    with pytest.raises(CDSEFehler) as fehler:
        run(provider.token())
    assert GEHEIM_TOKEN not in str(fehler.value)
    assert GEHEIM_SECRET not in str(fehler.value)


@pytest.mark.parametrize("wo", ["token", "katalog", "bild"])
def test_kein_fehlerweg_verraet_secret_oder_token(wo, satellit_ohne_netz,
                                                  tmp_path):
    """Ueber alle drei Endpunkte, mit einer Ausnahme, die das Geheimnis
    mitbringt - so, wie httpx es in freier Wildbahn tut."""
    def platzt(request):
        raise httpx.ConnectError(
            f"connection failed to {request.url} (secret={GEHEIM_SECRET})",
            request=request)

    transport = _cdse(**{f"{wo}_h": platzt})
    e = _suche(satellit_ohne_netz, tmp_path, transport)
    assert _leckt_cdse(e) == [], _leckt_cdse(e)


# --- satellite_passes: CelesTrak faellt aus ------------------------------


def _passes_werkzeug(tmp_path, cache: str | None = None):
    from core.satellite.ueberflug import cache_datei

    werkzeug = registry.get("satellite_passes")
    werkzeug.db_path = tmp_path / "jarvis.db"
    if cache is not None:
        ziel = cache_datei("visual", db_path=werkzeug.db_path)
        ziel.parent.mkdir(parents=True, exist_ok=True)
        ziel.write_text(cache, encoding="utf-8")
    return werkzeug


ISS_TLE = "\r\n".join([
    "ISS (ZARYA)",
    "1 25544U 98067A   26238.54791667  .00016717  00000-0  10270-3 0  9004",
    "2 25544  51.6392 339.6224 0004612  86.5764 273.5714 15.50017523424692",
]) + "\r\n"


def _ohne_celestrak(handler):
    echt = httpx.AsyncClient

    def fake(*a, **k):
        k["transport"] = httpx.MockTransport(handler)
        return echt(*a, **k)

    return _mock.patch("httpx.AsyncClient", fake)


@pytest.mark.parametrize("klasse", [
    httpx.ReadTimeout, httpx.TimeoutException, httpx.ConnectError,
])
def test_celestrak_weg_und_kein_cache_gibt_einen_satz(klasse, tmp_path):
    """Vorher flog die httpx-Ausnahme aus dem Werkzeug: "satellite_passes ist
    mit einem Fehler ausgestiegen"."""
    _passes_werkzeug(tmp_path)
    with _ohne_celestrak(_wirft(klasse)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is False
    assert "ausgestiegen" not in (e.error or ""), e.error
    assert "CelesTrak" in (e.error or "")
    assert klasse.__name__ in (e.error or "")


@pytest.mark.parametrize("klasse", [httpx.ReadTimeout, httpx.ConnectError])
def test_celestrak_weg_aber_bahndaten_von_gestern_da(klasse, tmp_path):
    """Fuer HTTP 500 stand es schon im Code: ein alter Cachestand ist besser
    als keine Antwort. Fuer den Netzausfall galt es nicht - dabei ist er der
    haeufigere Fall."""
    werkzeug = _passes_werkzeug(tmp_path, cache=ISS_TLE)
    import os
    from core.satellite.ueberflug import cache_datei
    os.utime(cache_datei("visual", db_path=werkzeug.db_path), (0, 0))

    with _ohne_celestrak(_wirft(klasse)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is True, e.error
    assert "Zwischenspeicher" in e.display
    assert e.data["geprueft"] == 1


@pytest.mark.parametrize("status,kopfzeilen", [
    (500, {}), (429, {}), (429, {"Retry-After": "3600"}), (503, {}),
])
def test_ein_fehlerstatus_von_celestrak_wird_benannt(status, kopfzeilen,
                                                     tmp_path):
    _passes_werkzeug(tmp_path)
    with _ohne_celestrak(lambda r: httpx.Response(status, request=r,
                                                  headers=kopfzeilen)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is False
    assert f"HTTP {status}" in (e.error or "")
    assert "nicht erneut" in (e.error or "")


@pytest.mark.parametrize("koerper,erwartet", [
    ("", "leere Antwort"),
    ("Invalid query: unknown group", "abgelehnt"),
    ("<html>Wartung</html>", "kein einziger vollstaendiger TLE-Satz"),
    ("ISS (ZARYA)\r\n1 25544U 98067A...\r\n", "kein einziger vollstaendiger"),
])
def test_eine_unbrauchbare_celestrak_antwort_wird_nicht_als_bahndaten_abgelegt(
    koerper, erwartet, tmp_path
):
    """CelesTrak antwortet auf eine ungueltige Gruppe mit HTTP 200 und dem
    Text "Invalid query" - der Status allein genuegt nicht."""
    werkzeug = _passes_werkzeug(tmp_path)
    with _ohne_celestrak(lambda r: httpx.Response(200, request=r,
                                                  text=koerper)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is False
    assert erwartet in (e.error or ""), e.error

    from core.satellite.ueberflug import cache_datei
    assert not cache_datei("visual", db_path=werkzeug.db_path).exists(), \
        "Muell wurde als Bahndaten zwischengespeichert"


def test_eine_unerwartet_grosse_bahndatenantwort_wird_gedeckelt(tmp_path):
    """Gemessen: 10.000 TLE-Saetze brauchten 10,5 s fuer ein Fenster von
    EINER Stunde; bei 24 h waere die Zeitgrenze des Werkzeugs (60 s)
    gerissen - und `asyncio.to_thread` laesst sich nicht abbrechen, der
    Server haette weitergerechnet.

    Der Deckel muss ausserdem ehrlich sein: die Zahl im Kopf ist die der
    wirklich gerechneten Satelliten, nicht die der gelieferten."""
    from core.satellite.ueberflug import MAX_SATELLITEN

    viele = "".join(
        f"SAT {i}\r\n{ISS_TLE.splitlines()[1]}\r\n{ISS_TLE.splitlines()[2]}\r\n"
        for i in range(MAX_SATELLITEN + 25)
    )
    _passes_werkzeug(tmp_path)
    with _ohne_celestrak(lambda r: httpx.Response(200, request=r, text=viele)):
        e = run(run_tool("satellite_passes",
                         {"lat": 89.9, "lon": 0.0, "hours": 1}))
    assert e.ok is True, e.error
    assert e.data["geprueft"] == MAX_SATELLITEN
    assert f"{MAX_SATELLITEN} Satelliten" in e.display
    assert f"{MAX_SATELLITEN + 25} Saetze" in e.display


def test_der_satellitendeckel_steht_auf_einer_abgesprochenen_zahl():
    """Der Test darueber baut seine Bahndaten AUS `MAX_SATELLITEN` - er
    bleibt deshalb gruen, wenn jemand die Zahl still hochsetzt, und genau
    das ist bei der Abnahme passiert (Probe "Deckel still hochgesetzt").

    Die Zahl ist gemessen und nicht geraten: 6,8 ms je Satellit fuer ein
    24-h-Fenster, macht bei 1.000 Saetzen rund 6,8 s - Platz unter der
    Zeitgrenze des Werkzeugs (60 s), mit Luft fuer eine langsamere
    Maschine. Wer sie aendert, aendert diese Rechnung; diese Zeile macht
    das sichtbar, statt es beim naechsten roten Test nebenbei zu tun.
    """
    from core.satellite.ueberflug import MAX_SATELLITEN

    assert MAX_SATELLITEN == 1000


def test_ohne_deckel_wird_nichts_beschnitten(tmp_path):
    """Gegenprobe: die echten Gruppen (visual 157, stations 21) laufen
    vollstaendig durch, und der Kopf nennt keine Deckelung."""
    _passes_werkzeug(tmp_path, cache=ISS_TLE)
    e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79,
                                          "hours": 1}))
    assert e.ok is True
    assert e.data["geprueft"] == 1
    assert "rechne ich nicht durch" not in e.display


# --- satellite_compare: Werte, die keine Zahlen sind ---------------------


@pytest.mark.parametrize("wert", [float("nan"), float("inf"), float("-inf")])
def test_nan_und_unendlich_sind_keine_ndvi_werte(wert):
    """Der Dispatcher prueft das Schema, aber NaN IST eine Zahl vom Typ
    float und kam durch. Gemessen ueber `run_tool`: ok=True, "Mittlere
    Aenderung +nan" im Chat und `NaN` in `data` - und `NaN` ist kein
    gueltiges JSON, jeder strenge Leser der HTTP-Antwort bricht daran."""
    e = run(run_tool("satellite_compare", {
        "before": [wert] * 100, "after": [0.2] * 100,
        "before_date": "2026-06-15", "after_date": "2026-07-15",
        "resolution_m": 10,
    }))
    assert e.ok is False, e.display
    assert "keine Zahl" in e.display
    assert "nan" not in e.display.lower() or "keine Zahl" in e.display
    _json.dumps(e.data, allow_nan=False)      # wirft, wenn NaN durchkommt


@pytest.mark.parametrize("wert", [float("nan"), float("inf")])
def test_eine_unsinnige_aufloesung_wird_keine_hektarzahl(wert):
    """Dieselbe Luecke wie bei den Rasterwerten, eine Ebene hoeher: aus
    `resolution_m=nan` wird eine Flaeche von `nan` Hektar, und `data` ist
    danach kein gueltiges JSON mehr. Nachgetragen bei der Abnahme - die
    Mutationsprobe "resolution_m ungeprueft" blieb gruen.

    Genau diese beiden Werte sind der Fall: `-inf` faengt schon der
    Schema-Pruefer ab ("kleiner als 0.1"), `nan` und `+inf` nicht - ein
    Vergleich mit `nan` ist immer falsch, und `+inf` ist groesser als jede
    Untergrenze.
    """
    e = run(run_tool("satellite_compare", {
        "before": [0.8] * 100, "after": [0.2] * 100,
        "before_date": "2026-06-15", "after_date": "2026-07-15",
        "resolution_m": wert,
    }))
    assert e.ok is False, e.display
    assert "positive Zahl" in e.display
    _json.dumps(e.data, allow_nan=False)


def test_minus_unendlich_faengt_schon_der_schemapruefer():
    """Die Gegenprobe zur Aufteilung oben - damit sie stimmt und nicht nur
    behauptet ist."""
    e = run(run_tool("satellite_compare", {
        "before": [0.8] * 100, "after": [0.2] * 100,
        "before_date": "2026-06-15", "after_date": "2026-07-15",
        "resolution_m": float("-inf"),
    }))
    assert e.ok is False
    assert "kleiner als" in e.display
    _json.dumps(e.data, allow_nan=False)


def test_eine_aufloesung_von_null_oder_darunter_ergibt_keine_flaeche():
    """Null Meter je Pixel hiesse null Hektar, egal wie viel sich geaendert
    hat; ein negativer Wert ergaebe eine negative Flaeche."""
    for wert in (0, -10):
        e = run(run_tool("satellite_compare", {
            "before": [0.8] * 100, "after": [0.2] * 100,
            "before_date": "2026-06-15", "after_date": "2026-07-15",
            "resolution_m": wert,
        }))
        assert e.ok is False, (wert, e.display)


def test_der_vergleich_rechnet_weiter_wie_bisher():
    """Gegenprobe - die Pruefung darf den Happy Path nicht kosten."""
    e = run(run_tool("satellite_compare", {
        "before": [0.8] * 100, "after": [0.2] * 100,
        "before_date": "2026-06-15", "after_date": "2026-07-15",
        "resolution_m": 10,
    }))
    assert e.ok is True
    assert e.data["changed_ha"] == pytest.approx(1.0)
    _json.dumps(e.data, allow_nan=False)


def test_ganzzahlen_und_ganzzahlige_werte_bleiben_erlaubt():
    """`_endliche_zahlen` darf nicht strenger sein als noetig: ein Modell
    schreibt `0` statt `0.0`."""
    e = run(run_tool("satellite_compare", {
        "before": [1] * 100, "after": [0] * 100,
        "before_date": "2026-06-15", "after_date": "2026-07-15",
        "resolution_m": 10,
    }))
    assert e.ok is True
    assert e.data["changed_pixels"] == 100


def test_der_deckel_rechnet_wirklich_nur_die_ersten_saetze():
    """Die Mutation, die ueberlebt hat.

    Der erste Anlauf prueft nur, was der KOPF sagt ("N von M geprueft") -
    und diese Zahl rechnet das Werkzeug selbst aus. Nimmt man den Deckel in
    `ueberfluege` heraus, bleibt der Test gruen, obwohl der Server wieder
    alle Saetze durchrechnet: die Meldung waere dann sogar eine Luege.

    Also die Wirkung selbst: hinter dem Deckel steht die ISS, davor nur
    Muell-Saetze (die liefern nachweislich null Ereignisse, siehe
    tests/test_ueberflug.py). Wird der Deckel eingehalten, kommt kein
    einziger Ueberflug heraus."""
    from core.satellite.ueberflug import MAX_SATELLITEN, ueberfluege

    muell = ("MUELL", "1 " + "x" * 60, "2 " + "y" * 60)
    iss = tuple(ISS_TLE.strip().splitlines())
    von = datetime(2026, 8, 26, tzinfo=timezone.utc)
    bis = von + timedelta(hours=6)

    hinter_dem_deckel = [muell] * MAX_SATELLITEN + [iss]
    assert ueberfluege(hinter_dem_deckel, lat=48.8, lon=9.79,
                       von=von, bis=bis) == [], \
        "der Satz hinter dem Deckel wurde trotzdem gerechnet"

    # Gegenprobe: derselbe Satz DAVOR wird gerechnet - sonst wuerde der
    # Test auch bei einem Deckel von null gruen.
    davor = [muell] * (MAX_SATELLITEN - 1) + [iss]
    assert ueberfluege(davor, lat=48.8, lon=9.79, von=von, bis=bis), \
        "vor dem Deckel muss die ISS gerechnet werden"


# --- Der Rumpf der CelesTrak-Antwort hat einen Deckel --------------------
#
# Nachgetragen bei der Abnahme (07.09.2026). Der Code kam ohne Tests an;
# beide Mutationsproben - "Bahndaten ungebremst geladen" und "Deckel still
# hochgesetzt" - blieben gruen.


def _celestrak_stroemt(stueck: bytes, wie_oft: int, gezaehlt: dict):
    """Ein CelesTrak, der `wie_oft` Bloecke schickt und mitzaehlt."""
    def handler(request: httpx.Request) -> httpx.Response:
        async def haeppchen():
            for _ in range(wie_oft):
                gezaehlt["bytes"] += len(stueck)
                yield stueck

        return httpx.Response(200, headers={"content-type": "text/plain"},
                              content=haeppchen())

    return handler


def test_eine_endlose_bahndatenantwort_wird_abgebrochen(tmp_path):
    """`MAX_SATELLITEN` deckelt das RECHNEN, nicht das Holen: die Antwort
    wurde bis dahin am Stueck geladen und in voller Laenge auf die Platte
    geschrieben, bevor irgendjemand sie angesehen hat."""
    from core.satellite.ueberflug import MAX_ANTWORT_BYTES

    gezaehlt = {"bytes": 0}
    stueck = b"X" * 1_000_000
    bereit = 40 * len(stueck)          # 40 MB stuenden zur Verfuegung
    werkzeug = _passes_werkzeug(tmp_path)
    with _ohne_celestrak(_celestrak_stroemt(stueck, 40, gezaehlt)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))

    assert e.ok is False
    assert "MB" in (e.error or ""), e.error
    # Nicht "kaputte Bahndaten": der Dienst hat sauber geantwortet, nur zu viel.
    assert "ausgestiegen" not in (e.error or ""), e.error
    # Gegenprobe, dann die Zusage: es wurde gestroemt, aber nicht alles.
    assert gezaehlt["bytes"] > 0, "es wurde gar nicht erst gestroemt"
    assert gezaehlt["bytes"] <= MAX_ANTWORT_BYTES + len(stueck), gezaehlt
    assert gezaehlt["bytes"] < bereit, gezaehlt

    # Und nichts Halbes liegt auf der Platte: ein halber Datensatz waere
    # schlimmer als keiner, weil der naechste Lauf ihn fuer gueltig haelt.
    from core.satellite.ueberflug import cache_datei
    datei = cache_datei("visual", db_path=werkzeug.db_path)
    assert not datei.is_file(), datei.read_text(encoding="utf-8")[:200]


def test_der_bahndatendeckel_steht_auf_einer_abgesprochenen_zahl():
    """Gemessen: 10.000 TLE-Saetze sind 1,5 MB, der ganze CelesTrak-Katalog
    laege bei rund 5 MB - angefragt werden aber nur `visual` (157) und
    `stations` (21), also rund 25 KB. 8 MB sind sehr weit weg vom Normalfall
    und trotzdem eine Grenze. Wer die Zahl aendert, aendert diese Rechnung."""
    from core.satellite.ueberflug import MAX_ANTWORT_BYTES

    assert MAX_ANTWORT_BYTES == 8_000_000


def test_eine_gewoehnliche_antwort_geht_weiterhin_glatt_durch(tmp_path):
    """Gegenprobe - sonst waere jede Antwort ein Fehler."""
    gezaehlt = {"bytes": 0}
    _passes_werkzeug(tmp_path)
    with _ohne_celestrak(_celestrak_stroemt(ISS_TLE.encode(), 1, gezaehlt)):
        e = run(run_tool("satellite_passes",
                         {"lat": 48.8, "lon": 9.79, "hours": 24}))
    assert e.ok is True, e.error


def test_ein_krummes_byte_macht_die_ganze_gruppe_nicht_wertlos(tmp_path):
    """Ein TLE-Satz ist ASCII. Kommt ein einzelnes Byte kaputt an, wird es
    ersetzt statt geworfen - sonst haengt die Bahnrechnung fuer alle
    Satelliten an der Kodierung eines Zeichens."""
    gezaehlt = {"bytes": 0}
    krumm = (ISS_TLE + "\r\n").encode() + b"\xff\xfe"
    _passes_werkzeug(tmp_path)
    with _ohne_celestrak(_celestrak_stroemt(krumm, 1, gezaehlt)):
        e = run(run_tool("satellite_passes",
                         {"lat": 48.8, "lon": 9.79, "hours": 24}))
    assert e.ok is True, e.error


# --- Abnahme FIX-12: was VOR dem Deckel passiert --------------------------
#
# `MAX_SATELLITEN` deckelt das Rechnen. Das Holen war ungedeckelt: die
# Antwort wurde am Stueck geladen und in voller Laenge auf die Platte
# geschrieben, bevor irgendjemand sie angesehen hat. Nachgemessen am
# Kalender, der dieselbe Bauart hatte: 37,7 MB Antwort waren 438 MB
# Speicher. Der Deckel ist derselbe wie in `core/kalender.py`.


def test_eine_masslos_grosse_celestrak_antwort_wird_abgebrochen(tmp_path):
    """Kein Absturz, kein volllaufender Speicher, ein deutscher Satz - und
    nichts davon landet im Zwischenspeicher."""
    from core.satellite.ueberflug import MAX_ANTWORT_BYTES, cache_datei

    zeilen = ISS_TLE.splitlines()
    block = f"SAT\r\n{zeilen[1]}\r\n{zeilen[2]}\r\n"
    zu_gross = block * (MAX_ANTWORT_BYTES // len(block) + 2)
    assert len(zu_gross.encode()) > MAX_ANTWORT_BYTES

    werkzeug = _passes_werkzeug(tmp_path)
    with _ohne_celestrak(lambda r: httpx.Response(200, request=r,
                                                  text=zu_gross)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is False, e.display
    assert "ausgestiegen" not in (e.error or ""), e.error
    assert "CelesTrak" in (e.error or "")
    assert "MB" in (e.error or "")
    assert not cache_datei("visual", db_path=werkzeug.db_path).exists(), \
        "eine abgebrochene Antwort wurde als Bahndaten abgelegt"


def test_der_deckel_laesst_eine_gewoehnliche_antwort_unangetastet(tmp_path):
    """Gegenprobe: `visual` sind rund 25 KB - der Deckel darf im Alltag
    nichts kosten und nichts abschneiden. Verglichen werden die BAHNDATEN,
    nicht die Bytes: `Path.read_text` macht aus CRLF ein LF (universelle
    Zeilenenden), und das war schon vor dem Deckel so."""
    from core.satellite.ueberflug import cache_datei, parse_tle

    werkzeug = _passes_werkzeug(tmp_path)
    with _ohne_celestrak(lambda r: httpx.Response(200, request=r,
                                                  text=ISS_TLE)):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))
    assert e.ok is True, e.error
    assert e.data["geprueft"] == 1
    abgelegt = cache_datei("visual", db_path=werkzeug.db_path)
    assert parse_tle(abgelegt.read_text(encoding="utf-8")) == parse_tle(ISS_TLE)


def test_ein_fehlerstatus_wird_gemeldet_ohne_den_fehlerrumpf_zu_lesen(tmp_path):
    """Die Mutation, die zuerst ueberlebt hat: den Rumpf AUCH bei HTTP 500
    zu lesen, sah folgenlos aus. Ist die Fehlerseite aber groesser als der
    Deckel, meldet das Werkzeug dann "mehr als 8 MB" statt "HTTP 500" - und
    verliert dabei den Rueckfall auf den alten Cachestand, obwohl der da
    ist. Der Status wird deshalb vor dem Rumpf geprueft, und der Rumpf einer
    Fehlerantwort gar nicht erst angefasst."""
    gezaehlt = {"bytes": 0}
    stueck = b"<html>Wartung</html>" * 100_000        # 2 MB Fehlerseite

    def handler(request: httpx.Request) -> httpx.Response:
        async def haeppchen():
            for _ in range(20):                       # 40 MB stuenden bereit
                gezaehlt["bytes"] += len(stueck)
                yield stueck

        return httpx.Response(500, content=haeppchen())

    werkzeug = _passes_werkzeug(tmp_path, cache=ISS_TLE)
    import os
    from core.satellite.ueberflug import cache_datei
    os.utime(cache_datei("visual", db_path=werkzeug.db_path), (0, 0))

    with _ohne_celestrak(handler):
        e = run(run_tool("satellite_passes", {"lat": 48.8, "lon": 9.79}))

    # Der alte Cachestand rettet die Antwort - das ist die Zusage, die die
    # Mutation kaputtmacht.
    assert e.ok is True, e.error
    assert "Zwischenspeicher" in e.display
    assert gezaehlt["bytes"] == 0, "die Fehlerseite wurde geladen"
