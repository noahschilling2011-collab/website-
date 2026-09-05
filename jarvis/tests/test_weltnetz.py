"""FIX-06 Abschnitt 7: die Ansicht WELT-NETZ.

Sechs Kriterien. Das sechste ist der Grund, warum diese Datei existiert:
*„Alle sieben FIX-05-Kriterien gelten weiter."* Ein Atmosphaerensaum, der
den Klick verschluckt, oder eine Satellitenbahn, die die Zeichenschleife
wieder dauerhaft anwirft, waere ein Rueckschritt - und beides waere ohne
Test nicht aufgefallen.
"""

from __future__ import annotations

import socket
import threading
import time
from datetime import datetime, timezone

import pytest

playwright = pytest.importorskip("playwright.sync_api")
from tests.conftest import CHROMIUM  # eine Stelle, siehe dort


def _tle_text() -> str:
    """Zwei echte Bahnsaetze, auf heute datiert.

    Kein Netz: `tests/conftest.py` sperrt es, und CelesTrak soll von einem
    Testlauf auch gar nichts merken.
    """
    heute = datetime.now(timezone.utc)
    tag = heute.timetuple().tm_yday + heute.hour / 24
    return (
        "ISS (ZARYA)\r\n"
        f"1 25544U 98067A   26{tag:012.8f}  .00005000  00000-0  10000-3 0  9993\r\n"
        "2 25544  51.6400 208.9163 0001000  86.9990 273.1360 15.50377580440135\r\n"
        "HST\r\n"
        f"1 20580U 90037B   26{tag:012.8f}  .00001000  00000-0  50000-4 0  9990\r\n"
        "2 20580  28.4700 288.8000 0002500 300.0000  60.0000 15.09000000440130\r\n"
    )


@pytest.fixture
def server(tmp_path):
    import uvicorn

    from api.app import create_app
    from core.config import Settings
    from core.satellite.ueberflug import cache_datei

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    st = Settings(_env_file=None, db_path=tmp_path / "netz.db",
                  jarvis_token="netz-token")
    datei = cache_datei("visual", db_path=st.db_path)
    datei.parent.mkdir(parents=True, exist_ok=True)
    datei.write_text(_tle_text(), encoding="utf-8")

    cfg = uvicorn.Config(create_app(st), host="127.0.0.1", port=port,
                         log_level="warning")
    srv = uvicorn.Server(cfg)
    faden = threading.Thread(target=srv.run, daemon=True)
    faden.start()
    frist = time.monotonic() + 20
    while not srv.started and time.monotonic() < frist:
        time.sleep(0.05)
    assert srv.started, "uvicorn ist nicht hochgekommen"
    try:
        yield f"http://127.0.0.1:{port}", st
    finally:
        srv.should_exit = True
        faden.join(timeout=10)


def _browser(pw, breite=1280, hoehe=860, bewegung="reduce"):
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": breite, "height": hoehe},
                        reduced_motion=bewegung)
    return br, seite


def _welt(seite, basis, fehler=None):
    if fehler is not None:
        seite.on("pageerror", lambda e: fehler.append(str(e)))
        seite.on("console", lambda m: fehler.append(m.text) if m.type == "error" else None)
    seite.goto(basis + "/weltlage", wait_until="domcontentloaded")
    seite.wait_for_function("() => document.body.dataset.laender", timeout=60000)
    seite.wait_for_function("() => document.body.dataset.bahnen", timeout=60000)
    seite.wait_for_timeout(500)
    return seite


def _bild(seite):
    """Das gerenderte Canvas als Pixelraster.

    NICHT ueber `gl.readPixels`: der Kontext laeuft ohne
    `preserveDrawingBuffer`, und nach dem Compositing ist der Puffer leer -
    gemessen, es kamen lauter Nullen zurueck. Der Screenshot zeigt, was
    wirklich auf dem Schirm steht.
    """
    import io

    from PIL import Image

    roh = seite.locator("#globus").screenshot()
    return Image.open(io.BytesIO(roh)).convert("RGB")


# --- DoD 1: der Atmosphaerensaum ------------------------------------------


def test_dod_1_der_saum_ist_da_und_haengt_an_der_welt(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            d = seite.evaluate("""() => {
              const s = window.zustand.saum;
              return {da: !!s, radius: s.geometry.parameters.radius,
                      elternIstWelt: s.parent === s.parent.parent.children[0].parent,
                      seite: s.material.side, tiefe: s.material.depthWrite,
                      durchsichtig: s.material.transparent};
            }""")
            assert d["da"] is True
            # Aussen um alles herum: Erde 1.0, Grenzen 1.002, Marken 1.01.
            assert d["radius"] > 1.01, d
            # THREE.BackSide ist 1 - von innen gerendert wird der Rand zum Saum.
            assert d["seite"] == 1, d
            # Sonst verdeckt der Saum die Satellitenbahnen.
            assert d["tiefe"] is False, d
            assert d["durchsichtig"] is True, d
        finally:
            br.close()


def test_dod_1_der_saum_dreht_mit(server):
    """Haengt er an der Szene statt an `welt`, sieht man beim Drehen, dass er
    nicht rund ist. Gemessen wird deshalb nicht "ist er da", sondern ob er
    nach 90 Grad Drehung noch rundum gleich ist."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)

            import math

            def saumprobe():
                """Vier Punkte auf dem Saum, im Uhrzeigersinn.

                Gesucht wird auf einem Strahl von der Mitte nach aussen der
                WAERMSTE Punkt, also der mit dem groessten Abstand rot minus
                blau - nicht der hellste. Der hellste war zweimal eine weisse
                Kuestenlinie (gemessen: 232,232,236 statt 101,55,18), und
                eine weisse Linie sagt ueber den Saum nichts aus.
                """
                bild = _bild(seite)
                b, h = bild.size
                mx, my = b / 2, h / 2
                werte = []
                for grad in (0, 90, 180, 270):
                    bester = (0, (0, 0, 0))
                    for schritt in range(int(h * 0.42), int(h * 0.5)):
                        x = int(mx + schritt * math.cos(math.radians(grad)))
                        y = int(my + schritt * math.sin(math.radians(grad)))
                        if not (0 <= x < b and 0 <= y < h):
                            continue
                        px = bild.getpixel((x, y))
                        waerme = px[0] - px[2]
                        if waerme > bester[0]:
                            bester = (waerme, px)
                    werte.append(bester[1])
                return werte

            vorher = saumprobe()
            seite.evaluate("() => window.zustand.dreheZu(90, 0)")
            seite.wait_for_timeout(1500)
            nachher = saumprobe()

            # Rundum warm: rot > blau an jedem der vier Punkte, vorher wie
            # nachher. Ein Saum an der Szene statt an `welt` wuerde beim
            # Drehen an einzelnen Stellen wegkippen.
            for satz, wann in ((vorher, "vorher"), (nachher, "nachher")):
                for r_, g_, b_ in satz:
                    assert r_ - b_ > 15, (wann, satz)
                    assert r_ > 40, (wann, satz)
        finally:
            br.close()


# --- DoD 2: echte TLE-Daten ------------------------------------------------


def test_dod_2_die_bahnen_kommen_aus_echten_tle_daten(server):
    basis, einstellungen = server
    from core.satellite.ueberflug import cache_datei

    datei = cache_datei("visual", db_path=einstellungen.db_path)
    assert datei.is_file(), "Cachedatei fehlt"
    inhalt = datei.read_text(encoding="utf-8")
    # Der Fall, der als HTTP 200 kommt und trotzdem nichts taugt.
    assert "Invalid query" not in inhalt
    assert inhalt.lstrip().startswith("ISS")

    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            assert seite.evaluate("() => document.body.dataset.bahnen") == "2"
            # Die Linien liegen ueber der Erde, nicht darauf.
            hoch = seite.evaluate("""() => {
              const g = window.zustand.bahnen.geometry.attributes.position;
              let min = 9, max = 0;
              for (let i = 0; i < g.count; i++){
                const r = Math.hypot(g.getX(i), g.getY(i), g.getZ(i));
                if (r < min) min = r;
                if (r > max) max = r;
              }
              return [min, max];
            }""")
            assert hoch[0] > 1.03, hoch      # ausserhalb des Saums
            assert hoch[1] < 1.12, hoch      # aber nicht im Nirgendwo
        finally:
            br.close()


def test_es_gibt_keinen_zweiten_abrufpfad(server):
    """Der Auftrag ist hier ausdruecklich. Der Globus fragt den eigenen
    Endpunkt, nicht CelesTrak."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            seite.on("request", lambda r: gerufen.append(r.url))
            _welt(seite, basis)
            assert not [u for u in gerufen if "celestrak" in u.lower()], gerufen
            assert [u for u in gerufen if "/api/satelliten/spur" in u], gerufen
        finally:
            br.close()


# --- DoD 3: die Bahnen kosten keine Bildrate ------------------------------


def test_dod_3_bei_stillstand_wird_nicht_gezeichnet(server):
    """Das Kriterium aus FIX-05 A6/5 gilt weiter. Eine Bahn, die jeden Frame
    neu gezeichnet wird, waere 60 Bilder je Sekunde fuer ein Standbild."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            seite.wait_for_timeout(800)
            vorher = seite.evaluate("() => window.__globusBilder")
            seite.wait_for_timeout(2500)
            nachher = seite.evaluate("() => window.__globusBilder")
            assert nachher == vorher, (vorher, nachher)
            # Und die Schleife laeuft trotzdem - sonst misst der Test nichts.
            assert seite.evaluate("() => window.__globusSchleife") > vorher
        finally:
            br.close()


# --- DoD 4: der Laendername wechselt animiert ------------------------------


def test_dod_4_der_name_wechselt_ohne_sprung(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        # Ohne reduced-motion, sonst ist die Animation abgeschaltet.
        br, seite = _browser(pw, bewegung="no-preference")
        try:
            _welt(seite, basis)
            assert seite.inner_text("#landtafel-name") == "WELTWEIT"
            hoch_vorher = seite.eval_on_selector(
                ".landtafel", "e => Math.round(e.getBoundingClientRect().height)")

            seite.evaluate("""() => window.zustand.waehle(
                window.zustand.laender.findIndex(l => l.iso === 'DEU'))""")
            # Mitten im Wechsel: beide Saetze da, der alte auf dem Weg raus.
            seite.wait_for_timeout(90)
            waehrend = seite.evaluate("""() => {
              const s = document.querySelectorAll('.landtafel-satz');
              return {anzahl: s.length,
                      geht: !!document.querySelector('.landtafel-satz.geht'),
                      hoch: Math.round(document.querySelector('.landtafel')
                              .getBoundingClientRect().height)};
            }""")
            assert waehrend["anzahl"] == 2, waehrend
            assert waehrend["geht"] is True, waehrend
            # "ohne Sprung": die Tafel darf waehrend des Wechsels nicht
            # aufklappen. Der alte Satz liegt absolut, der neue traegt.
            assert abs(waehrend["hoch"] - hoch_vorher) <= 6, (hoch_vorher, waehrend)

            seite.wait_for_timeout(800)
            assert seite.eval_on_selector_all(".landtafel-satz", "l => l.length") == 1
            # `iso3166.json` fuehrt das Land als "Germany" - der Name kommt
            # aus den Daten, nicht aus einer Uebersetzungstabelle.
            assert seite.inner_text("#landtafel-name").upper() == "GERMANY"
            assert "DEU" in seite.inner_text("#landtafel-wo")
        finally:
            br.close()


def test_nur_transform_und_opacity_werden_animiert(server):
    """Alles andere loest ein Layout aus - neben einer WebGL-Schleife ist das
    genau das Ruckeln, das FIX-05 A4 abgestellt hat."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, bewegung="no-preference")
        try:
            _welt(seite, basis)
            eigenschaften = seite.eval_on_selector(
                ".landtafel-satz",
                "e => getComputedStyle(e).transitionProperty")
            teile = {t.strip() for t in eigenschaften.split(",")}
            assert teile <= {"transform", "opacity"}, eigenschaften
        finally:
            br.close()


# --- DoD 5: die Sichtbarkeitsgrenze steht in der Ansicht -------------------


def test_dod_5_die_grenze_steht_im_ui(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            text = seite.inner_text("#sat-hinweis")
            assert "steht" in text and "sichtbar" in text, text
            # Und sie ist wirklich sichtbar, nicht nur im DOM.
            assert seite.is_visible("#sat-hinweis")
            kasten = seite.eval_on_selector(
                "#sat-hinweis", "e => e.getBoundingClientRect().height")
            assert kasten > 8, kasten
        finally:
            br.close()


# --- DoD 6: die FIX-05-Kriterien gelten weiter ----------------------------


def test_dod_6_der_saum_verschluckt_den_klick_nicht(server):
    """Die naheliegendste Art, FIX-05 A1 kaputtzumachen: eine neue Kugel
    zwischen Zeiger und Erde. Der Saum liegt weiter aussen als alles andere -
    wenn der Strahl gegen IHN gerechnet wuerde, waere jede Auswahl daneben."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            seite.evaluate("() => window.zustand.dreheZu(10.0, 51.0)")
            seite.wait_for_timeout(1400)
            kasten = seite.locator("#globus").bounding_box()
            seite.mouse.click(kasten["x"] + kasten["width"] / 2,
                              kasten["y"] + kasten["height"] / 2)
            seite.wait_for_timeout(700)
            aktiv = seite.evaluate("() => window.zustand.aktiv")
            assert aktiv, "Klick in die Mitte hat gar nichts getroffen"
            assert aktiv["iso"] == "DEU", aktiv
        finally:
            br.close()


def test_dod_6_drehen_und_zoomen_gehen_weiter(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _welt(seite, basis)
            kasten = seite.locator("#globus").bounding_box()
            mx = kasten["x"] + kasten["width"] / 2
            my = kasten["y"] + kasten["height"] / 2
            # `zustand.drehung()` ist der Griff, den FIX-05 A6 benutzt -
            # `dataset.drehung` setzt nur der Flug, nicht das Ziehen.
            vorher = seite.evaluate("() => window.zustand.drehung()")
            seite.mouse.move(mx, my)
            seite.mouse.down()
            seite.mouse.move(mx + 140, my, steps=8)
            seite.mouse.up()
            seite.wait_for_timeout(300)
            nachher = seite.evaluate("() => window.zustand.drehung()")
            assert abs(nachher["y"] - vorher["y"]) > 0.1, (vorher, nachher)

            naehe = seite.evaluate("() => window.zustand.naehe()")
            seite.eval_on_selector("#globus", "c => c.focus()")
            seite.keyboard.press("+")
            seite.wait_for_timeout(600)
            assert seite.evaluate("() => window.zustand.naehe()") < naehe
        finally:
            br.close()


def test_ohne_js_fehler(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        fehler = []
        try:
            _welt(seite, basis, fehler)
            seite.evaluate("""() => window.zustand.waehle(
                window.zustand.laender.findIndex(l => l.iso === 'DEU'))""")
            seite.wait_for_timeout(900)
            # Ohne LLM-Schluessel antwortet `POST /api/weltlage/DEU` mit 502.
            # Das ist der ehrliche Weg und kein JS-Fehler - die Oberflaeche
            # zeigt die Begruendung an, das wird gleich mitgeprueft. Alles
            # andere in der Konsole waere ein echter Fund.
            echte = [f for f in fehler if "Failed to load resource" not in f]
            assert echte == [], echte
            assert seite.inner_text("#landtafel-tut").strip(), "kein Grund im UI"
        finally:
            br.close()
