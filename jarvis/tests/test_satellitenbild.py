"""Der Bildpfad (Inbetriebnahme-Befund, Schritt 5b).

Bis hierher war der Satellit ein Metadatendienst: `preview_url` stand in
`core/satellite/cdse.py` fest auf `None`, `render()` gab es nicht, und
`index.html` hatte null `<img>`. Damit waren DoD 1, 3 und 6 aus
`docs/phases/PHASE-08.md` **strukturell** unerfuellbar.

Alles hier Nachgeschlagene ist gemessen, nicht erinnert:

    POST https://sh.dataspace.copernicus.eu/api/v1/process   -> 401 (existiert)
    POST https://sh.dataspace.copernicus.eu/process/v1       -> 401 (existiert auch)
    POST https://sh.dataspace.copernicus.eu/gibtesnicht/...  -> 503 (existiert nicht)

Die 503 auf einem erfundenen Pfad ist der Beleg, dass die 401 etwas heisst:
die beiden Prozess-Pfade sind wirklich geroutet, es fehlt nur der Token.

Kontingent laut documentation.dataspace.copernicus.eu/Quotas.html fuer ein
normales Konto: 10.000 Processing Units und 50.000 Anfragen im Monat,
300 Anfragen je Minute. Der Bildpfad ist also kostenlos benutzbar.

Der zweite Punkt hier ist die **Aufloesung**. Sentinel-2 liefert 10 m/px -
aber ein 512-Pixel-Bild von ganz Deutschland hat rund 1,5 km je Pixel. Wer
dort die 10 hinschreibt, sagt dem Modell, es koenne Dinge sehen, die zwei
Groessenordnungen zu klein sind. Genau davor warnt `SATELLIT_PROMPT`.
"""

from __future__ import annotations

import json
import math

import httpx
import pytest

from core.satellite.cdse import (
    EVALSCRIPT_ECHTFARBE,
    PROCESS_URL,
    CDSEFehler,
    CDSEProvider,
    effektive_aufloesung_m,
)
from tests.conftest import run

# Ein winziges, gueltiges PNG (1x1, transparent).
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000a49444154789c6360000002000100fd42a0d70000"
    "000049454e44ae426082"
)

DEUTSCHLAND = (5.9, 47.3, 15.0, 55.1)
GMUEND = (9.75, 48.75, 9.85, 48.85)


def _provider(handler):
    return CDSEProvider(
        "kunde", "geheim", transport=httpx.MockTransport(handler)
    )


def _token_oder(handler):
    """Beantwortet den Token-Aufruf und reicht den Rest weiter."""

    def innen(request: httpx.Request) -> httpx.Response:
        if "openid-connect/token" in str(request.url):
            return httpx.Response(200, json={"access_token": "tok-123"})
        return handler(request)

    return innen


# --- Aufloesung: der Fehler, der im Befund stand --------------------------


def test_ganz_deutschland_auf_512_pixeln_sind_keine_10_meter():
    """Der Kern. 9,1 Grad Laenge auf 512 Pixel sind rund 1,3 km je Pixel -
    nicht 10 m. Die Konstante war eine Luege ueber das, was man sieht."""
    m = effektive_aufloesung_m(DEUTSCHLAND, 512, 512)
    assert m > 1000, f"{m} m/px - das kann fuer Deutschland nicht stimmen"
    assert m < 3000


def test_ein_kleiner_ausschnitt_kommt_der_sensorgrenze_nahe():
    """0,1 Grad auf 512 Pixel sind rund 14 m - nahe an den 10 m des Sensors,
    aber eben nicht darunter."""
    m = effektive_aufloesung_m(GMUEND, 512, 512)
    assert 10 < m < 30


def test_unter_die_sensorgrenze_geht_es_nicht():
    """Ein 4096-Pixel-Bild eines winzigen Ausschnitts hat rechnerisch 2 m/px.
    Sentinel-2 liefert 10. Mehr Pixel erfinden keine Aufloesung."""
    m = effektive_aufloesung_m((9.80, 48.80, 9.81, 48.81), 4096, 4096)
    assert m >= 10.0, "Ein Bild kann nicht schaerfer sein als sein Sensor"


def test_die_breitengradstauchung_wird_beruecksichtigt():
    """Ein Grad Laenge ist bei 60 Grad Nord halb so lang wie am Aequator.
    Wer das ignoriert, liegt in Nordeuropa um die Haelfte daneben.

    Gemessen wird an einem BREITEN, flachen Ausschnitt. Bei einem quadratischen
    dominiert die Nord-Sued-Achse, und die ist vom Breitengrad unabhaengig -
    der Test haette dann zwar bestanden, aber nichts geprueft. (Erst so
    gebaut, dann gemerkt: beide Werte waren identisch.)"""
    flach_am_aequator = effektive_aufloesung_m((0.0, 0.0, 1.0, 0.001), 512, 512)
    flach_im_norden = effektive_aufloesung_m((0.0, 60.0, 1.0, 60.001), 512, 512)
    assert flach_im_norden < flach_am_aequator
    assert flach_im_norden == pytest.approx(
        flach_am_aequator * math.cos(math.radians(60.0)), rel=0.02
    )


# --- Die Anfrage an die Process API ---------------------------------------


def test_die_anfrage_geht_an_den_gemessenen_endpunkt():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["url"] = str(request.url)
        gesehen["headers"] = dict(request.headers)
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    run(_provider(_token_oder(handler)).render(
        GMUEND, "2026-08-01T00:00:00Z", "2026-08-26T00:00:00Z"))

    assert gesehen["url"] == PROCESS_URL
    assert gesehen["headers"]["authorization"] == "Bearer tok-123"
    koerper = gesehen["body"]
    assert koerper["input"]["bounds"]["bbox"] == list(GMUEND)
    assert koerper["input"]["bounds"]["properties"]["crs"] == (
        "http://www.opengis.net/def/crs/OGC/1.3/CRS84"
    )
    assert koerper["input"]["data"][0]["type"] == "sentinel-2-l2a"
    assert koerper["input"]["data"][0]["dataFilter"]["timeRange"] == {
        "from": "2026-08-01T00:00:00Z", "to": "2026-08-26T00:00:00Z",
    }
    assert koerper["output"]["responses"][0]["format"]["type"] == "image/png"
    assert koerper["evalscript"] == EVALSCRIPT_ECHTFARBE


def test_breite_und_hoehe_gehen_mit():
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    run(_provider(_token_oder(handler)).render(
        GMUEND, "a", "b", breite=256, hoehe=128))
    assert gesehen["body"]["output"]["width"] == 256
    assert gesehen["body"]["output"]["height"] == 128


def test_die_bildgroesse_ist_gedeckelt():
    """Sentinel Hub rechnet nach Flaeche ab. Ein 8000er-Bild waere ein
    Kontingent-Loch, das niemand bemerkt, bis der Monat leer ist."""
    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        gesehen["body"] = json.loads(request.content)
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    run(_provider(_token_oder(handler)).render(GMUEND, "a", "b",
                                               breite=9000, hoehe=9000))
    assert gesehen["body"]["output"]["width"] <= 2500
    assert gesehen["body"]["output"]["height"] <= 2500


def test_die_bytes_kommen_zurueck():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    bild = run(_provider(_token_oder(handler)).render(GMUEND, "a", "b"))
    assert bild == PNG
    assert bild.startswith(b"\x89PNG")


# --- Wenn es schiefgeht ---------------------------------------------------


def test_ohne_zugangsdaten_wird_gar_nicht_erst_gefragt():
    leer = CDSEProvider("", "")
    with pytest.raises(CDSEFehler) as fehler:
        run(leer.render(GMUEND, "a", "b"))
    assert "CDSE_CLIENT_ID" in str(fehler.value)


def test_ein_fehler_der_process_api_wird_klartext():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            403, json={"error": {"message": "quota exceeded"}})

    with pytest.raises(CDSEFehler) as fehler:
        run(_provider(_token_oder(handler)).render(GMUEND, "a", "b"))
    text = str(fehler.value)
    assert "403" in text
    assert "geheim" not in text, "Das Secret gehoert in keine Fehlermeldung"


def test_eine_antwort_die_kein_bild_ist_wird_gemeldet():
    """Sentinel Hub antwortet bei manchen Fehlern mit 200 und JSON. Wer das
    als Bild speichert, legt eine kaputte Datei ab und zeigt sie an."""
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"error": "keine Daten"},
                              headers={"content-type": "application/json"})

    with pytest.raises(CDSEFehler) as fehler:
        run(_provider(_token_oder(handler)).render(GMUEND, "a", "b"))
    assert "kein Bild" in str(fehler.value)


def test_ein_leeres_bild_gilt_nicht_als_bild():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"",
                              headers={"content-type": "image/png"})

    with pytest.raises(CDSEFehler):
        run(_provider(_token_oder(handler)).render(GMUEND, "a", "b"))


# --- Ablage ----------------------------------------------------------------


def test_dasselbe_bild_landet_nur_einmal_auf_der_platte(tmp_path):
    """Inhaltsadressiert: zweimal derselbe Ausschnitt am selben Tag kostet
    keinen zweiten Platz."""
    from core.satellite.bilder import ordner, speichere

    db = tmp_path / "jarvis.db"
    a = speichere(PNG, db_path=db)
    b = speichere(PNG, db_path=db)
    assert a == b
    assert len(list(ordner(db).glob("*.png"))) == 1


def test_gespeichertes_kommt_unveraendert_zurueck(tmp_path):
    from core.satellite.bilder import lade, speichere

    db = tmp_path / "jarvis.db"
    kennung = speichere(PNG, db_path=db)
    assert lade(kennung, db_path=db) == PNG


def test_eine_unbekannte_id_gibt_none_statt_eines_absturzes(tmp_path):
    from core.satellite.bilder import lade

    assert lade("0" * 32, db_path=tmp_path / "jarvis.db") is None


def test_ein_pfad_als_id_wird_abgewiesen(tmp_path):
    """`../../etc/passwd` waere sonst eine gueltige Bild-ID - und die
    Bild-Route nimmt die ID aus der URL entgegen."""
    from core.satellite.bilder import BildFehler, lade

    for boese in ("../../etc/passwd", "..", "a/b", "0" * 31, "0" * 33, "", "XYZ"):
        with pytest.raises(BildFehler):
            lade(boese, db_path=tmp_path / "jarvis.db")


def test_was_kein_png_ist_wird_nicht_abgelegt(tmp_path):
    """Sonst liegt eine JSON-Fehlermeldung als .png auf der Platte und die
    Oberflaeche zeigt ein kaputtes Bild."""
    from core.satellite.bilder import BildFehler, ordner, speichere

    db = tmp_path / "jarvis.db"
    with pytest.raises(BildFehler):
        speichere(b'{"error": "nix da"}', db_path=db)
    assert not ordner(db).exists() or not list(ordner(db).glob("*.png"))


def test_ein_leeres_bild_wird_nicht_abgelegt(tmp_path):
    from core.satellite.bilder import BildFehler, speichere

    with pytest.raises(BildFehler):
        speichere(b"", db_path=tmp_path / "jarvis.db")


def test_keine_halbe_datei_bleibt_liegen(tmp_path):
    """Geschrieben wird daneben und dann umbenannt. Was liegen bleibt, ist
    entweder vollstaendig oder gar nicht da."""
    from core.satellite.bilder import ordner, speichere

    db = tmp_path / "jarvis.db"
    speichere(PNG, db_path=db)
    assert list(ordner(db).glob("*.teil")) == []


# --- Die Route -------------------------------------------------------------


@pytest.fixture
def client(settings):
    from fastapi.testclient import TestClient

    from api.app import create_app

    with TestClient(create_app(settings)) as c:
        yield c




def test_ein_bild_kommt_als_png_zurueck(client, settings):
    from core.satellite.bilder import speichere

    kennung = speichere(PNG, db_path=settings.db_path)
    antwort = client.get(f"/api/bild/{kennung}",
                         headers={"X-Jarvis-Token": settings.jarvis_token})
    assert antwort.status_code == 200
    assert antwort.headers["content-type"] == "image/png"
    assert antwort.content == PNG


def test_ohne_token_gibt_es_kein_bild(client, settings):
    """Der Zugangsschutz aus 0.4 gilt auch fuer Bilder - ohne Ausnahme.
    Genau deshalb holt das Frontend sie per fetch() und nicht ueber ein
    nacktes <img src>."""
    from core.satellite.bilder import speichere

    kennung = speichere(PNG, db_path=settings.db_path)
    assert client.get(f"/api/bild/{kennung}").status_code == 401


def test_ein_unbekanntes_bild_gibt_404(client, settings):
    antwort = client.get(f"/api/bild/{'a' * 32}",
                         headers={"X-Jarvis-Token": settings.jarvis_token})
    assert antwort.status_code == 404


def test_ein_pfad_in_der_url_gibt_400_und_keinen_dateizugriff(client, settings):
    antwort = client.get(f"/api/bild/{'z' * 32}",
                         headers={"X-Jarvis-Token": settings.jarvis_token})
    assert antwort.status_code == 400


# --- Das Werkzeug als Ganzes ----------------------------------------------


def _katalog_antwort(tag: str = "2026-08-20") -> dict:
    return {"value": [{
        "Id": "abc-123",
        "Name": "S2A_MSIL2A_20260820T101031.SAFE",
        "ContentDate": {"Start": f"{tag}T10:10:31.000Z"},
        "Attributes": [
            {"Name": "cloudCover", "Value": 4.2},
            {"Name": "instrumentShortName", "Value": "MSI"},
        ],
    }]}


def _voller_dienst(tmp_path, bbox):
    """Token, Katalog und Process API - alle drei gefaelscht."""
    from core.satellite.cdse import CDSEProvider
    from core.tools import registry
    import core.tools.satellite_tools  # noqa: F401

    gesehen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "openid-connect/token" in url:
            return httpx.Response(200, json={"access_token": "tok"})
        if "odata/v1/Products" in url:
            return httpx.Response(200, json=_katalog_antwort())
        gesehen["prozess"] = json.loads(request.content)
        return httpx.Response(200, content=PNG,
                              headers={"content-type": "image/png"})

    werkzeug = registry.get("satellite_search")
    werkzeug.provider = CDSEProvider(
        "kunde", "geheim", transport=httpx.MockTransport(handler)
    )
    werkzeug.db_path = tmp_path / "jarvis.db"
    return werkzeug, gesehen


def test_die_suche_liefert_jetzt_ein_bild(tmp_path):
    werkzeug, gesehen = _voller_dienst(tmp_path, DEUTSCHLAND)
    ergebnis = run(werkzeug.execute(list(DEUTSCHLAND)))

    assert ergebnis.ok is True
    assert ergebnis.data["preview_url"], "preview_url stand frueher fest auf None"
    assert ergebnis.data["preview_url"].startswith("/api/bild/")
    assert ergebnis.data["scenes"][0]["preview_url"] == ergebnis.data["preview_url"]


def test_das_bild_liegt_wirklich_auf_der_platte(tmp_path):
    from core.satellite.bilder import lade

    werkzeug, _ = _voller_dienst(tmp_path, DEUTSCHLAND)
    ergebnis = run(werkzeug.execute(list(DEUTSCHLAND)))
    kennung = ergebnis.data["preview_url"].rsplit("/", 1)[-1]
    assert lade(kennung, db_path=tmp_path / "jarvis.db") == PNG


def test_die_gemeldete_aufloesung_ist_die_des_bildes_nicht_die_des_sensors(tmp_path):
    """Der eigentliche Fehler aus dem Befund. Fuer ganz Deutschland auf 512
    Pixeln sind es rund 1700 m je Pixel, nicht 10."""
    werkzeug, _ = _voller_dienst(tmp_path, DEUTSCHLAND)
    ergebnis = run(werkzeug.execute(list(DEUTSCHLAND)))

    assert ergebnis.data["bild_aufloesung_m"] > 1000
    assert "m je Bildpixel" in ergebnis.display
    # Und der Grenzsatz stuetzt sich darauf, nicht auf die 10.
    assert "10 m" not in ergebnis.display.split("Objekte")[-1]


def test_die_attribution_steht_am_ergebnis(tmp_path):
    """Copernicus-Daten duerfen ohne Attribution nicht angezeigt werden."""
    werkzeug, _ = _voller_dienst(tmp_path, DEUTSCHLAND)
    ergebnis = run(werkzeug.execute(list(DEUTSCHLAND)))
    assert "Copernicus" in ergebnis.data["attribution"]
    assert "Copernicus" in ergebnis.display


def test_das_bild_zeigt_genau_den_tag_der_gefundenen_szene(tmp_path):
    """Sonst rendert Sentinel Hub irgendeine Aufnahme aus dem Zeitraum -
    und die Metadaten daneben gehoeren zu einer anderen."""
    werkzeug, gesehen = _voller_dienst(tmp_path, DEUTSCHLAND)
    run(werkzeug.execute(list(DEUTSCHLAND)))
    zeit = gesehen["prozess"]["input"]["data"][0]["dataFilter"]["timeRange"]
    assert zeit["from"] == "2026-08-20T00:00:00Z"
    assert zeit["to"] == "2026-08-21T00:00:00Z"


def test_ohne_bild_bleiben_die_metadaten_trotzdem_da(tmp_path):
    """Ein gescheitertes Rendern darf den ganzen Aufruf nicht wegwerfen -
    die Metadaten sind etwas wert. Aber es wird gesagt."""
    from core.satellite.cdse import CDSEProvider
    from core.tools import registry
    import core.tools.satellite_tools  # noqa: F401

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "openid-connect/token" in url:
            return httpx.Response(200, json={"access_token": "tok"})
        if "odata/v1/Products" in url:
            return httpx.Response(200, json=_katalog_antwort())
        return httpx.Response(403, json={"error": "quota"})

    werkzeug = registry.get("satellite_search")
    werkzeug.provider = CDSEProvider(
        "kunde", "geheim", transport=httpx.MockTransport(handler)
    )
    werkzeug.db_path = tmp_path / "jarvis.db"
    ergebnis = run(werkzeug.execute(list(DEUTSCHLAND)))

    assert ergebnis.ok is True
    assert ergebnis.data["preview_url"] is None
    assert "Szene(n) gefunden" in ergebnis.display
    assert "Kein Bild gerendert" in ergebnis.display
    # Hier stand `assert "403" in ergebnis.display`. Diese Zusicherung
    # verlangte, dass der AUSNAHMETEXT in der sichtbaren Ausgabe steht -
    # und genau das verbietet FIX-07. (31.08.2026: fuenf Lecks derselben
    # Klasse an einem Tag, eines davon httpx, das seine volle URL an die
    # Meldung haengt.) Die Zeile 202 weiter oben bleibt: dort wird die
    # EIGENE Ausnahme geprueft, nicht die sichtbare Ausgabe.
    #
    # Nicht geloescht, sondern umgedreht: der Grund muss weiterhin
    # erkennbar sein - ueber den Ausnahmetyp - und der Text draussen.
    assert "CDSEFehler" in ergebnis.display, ergebnis.display
    assert "403" not in ergebnis.display, (
        "der Ausnahmetext steht wieder in der sichtbaren Ausgabe")


# --- Die Oberflaeche -------------------------------------------------------


def _seite() -> str:
    from pathlib import Path as P
    return (P(__file__).resolve().parent.parent / "index.html").read_text(
        encoding="utf-8"
    )


def test_die_oberflaeche_kann_jetzt_bilder():
    """Der Befund zaehlte: 0x <img>, 0x <canvas>. Damit waren DoD 1, 3 und 6
    aus PHASE-08 strukturell unerfuellbar - es gab kein Element, in dem ein
    Bild haette erscheinen koennen."""
    html = _seite()
    assert "createElement('img')" in html
    assert "zeigeBild(" in html


def test_das_bild_wird_mit_token_geholt_und_nicht_ueber_ein_nacktes_img():
    """Ein <img src="/api/bild/..."> wuerde 401 bekommen - der Browser
    schickt dabei keine eigenen Header. Wer das 'loest', indem er den Token
    in die URL schreibt, hat ihn im Verlauf und in jedem Log."""
    html = _seite()
    assert "'X-Jarvis-Token': TOKEN" in html
    assert "createObjectURL" in html


def test_die_blob_url_wird_wieder_freigegeben():
    """Sonst haelt jede angezeigte Aufnahme ihre Bytes bis zum Neuladen der
    Seite im Speicher."""
    assert "revokeObjectURL" in _seite()


def test_die_bild_adresse_wird_selbst_gebaut_nicht_uebernommen():
    """`preview_url` kommt aus einem Werkzeugergebnis, also mittelbar aus
    einem Modell. Die Seite zieht die ID heraus, prueft die Form und baut
    die Adresse selbst - sie fetcht nie einen Pfad, den ihr jemand gibt.

    Nebenwirkung, die den Ausschlag gab: so steht `/api/bild/` woertlich im
    HTML, und `test_jede_route_hat_einen_nutzer` sieht, dass die Route
    wirklich benutzt wird. Vorher stand dort nur eine Regex mit maskierten
    Schraegstrichen - der Test schlug an, und er hatte recht."""
    html = _seite()
    assert "/^[0-9a-f]{32}$/" in html
    assert "'/api/bild/' + id" in html


def test_die_attribution_steht_unter_dem_bild():
    html = _seite()
    assert "figcaption" in html
    assert "attribution" in html
