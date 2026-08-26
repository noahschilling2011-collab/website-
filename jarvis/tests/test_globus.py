"""FIX-05 Schritt A: der Globus ist bedienbar.

Sieben Kriterien aus A6, in einem echten Chromium gegen einen echten
uvicorn. Alles davon war vorher kaputt:

* Frankreichs Klickmarke lag bei lon=-10,71 lat=35,40 - im Atlantik.
* Es gab genau einen Zeiger-Handler: `click`. Kein Drehen, kein Zoom,
  kein Touch. Die Rueckseite war nur erreichbar, indem man ein Land
  anklickte, das man nicht sehen konnte.
* Geraycastet wurde gegen die Landesmarken, nicht gegen die Kugel - ein
  Fehlschuss lief weiter und traf ein Land auf der Rueckseite.
* `renderer.render()` lief in jedem Frame, auch im Stillstand.
"""

from __future__ import annotations

import socket
import threading
import time

import pytest

playwright = pytest.importorskip("playwright.sync_api")
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

# Frankreichs Festland, ungefaehr Burgund. Weit weg von jeder Grenze.
FRANKREICH = (3.3, 47.0)
# Mitten im Nordpazifik, tausend Kilometer von allem entfernt.
OZEAN = (-150.0, 30.0)


@pytest.fixture
def server(tmp_path):
    import uvicorn

    from api.app import create_app
    from core.config import Settings

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    st = Settings(_env_file=None, db_path=tmp_path / "globus.db",
                  jarvis_token="globus-token")
    app = create_app(st)
    cfg = uvicorn.Config(app, host="127.0.0.1", port=port, log_level="warning")
    srv = uvicorn.Server(cfg)
    faden = threading.Thread(target=srv.run, daemon=True)
    faden.start()
    frist = time.monotonic() + 20
    while not srv.started and time.monotonic() < frist:
        time.sleep(0.05)
    assert srv.started, "uvicorn ist nicht hochgekommen"
    try:
        yield f"http://127.0.0.1:{port}", app
    finally:
        srv.should_exit = True
        faden.join(timeout=10)


def _browser(pw, reduziert=True):
    """Reduzierte Bewegung: `fliegeZu` springt dann sofort, statt 1,8 s zu
    animieren. Das macht die Tests deterministisch statt langsam."""
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(
        viewport={"width": 1200, "height": 800},
        reduced_motion="reduce" if reduziert else "no-preference")
    return br, seite


def _lade(seite, basis):
    seite.goto(f"{basis}/weltlage", wait_until="networkidle")
    # Die Laendergrenzen kommen per fetch nach; body.dataset.laender wird
    # gesetzt, sobald sie da sind.
    seite.wait_for_function("() => document.body.dataset.laender", timeout=20000)
    return int(seite.evaluate("() => document.body.dataset.laender"))


def _dreh_zu(seite, lon, lat):
    """Den Globus so drehen, dass lon/lat in der Mitte steht."""
    seite.evaluate(f"() => window.zustand && window.zustand.dreheZu({lon}, {lat})")
    seite.wait_for_timeout(250)


def _mitte(seite):
    kasten = seite.locator("#globus").bounding_box()
    return kasten["x"] + kasten["width"] / 2, kasten["y"] + kasten["height"] / 2


# --- Grundlage -------------------------------------------------------------


def _sammle_fehler(seite, fehler):
    """Alles ausser dem Favicon.

    Chromium holt `/favicon.ico` von sich aus, ohne dass die Seite das
    verlangt; JARVIS hat keins und antwortet mit 404. Das ist kein
    Seitenfehler, und ein Favicon nur fuer diesen Test dazuzulegen waere
    eine stille Aenderung ausserhalb des Auftrags.
    """
    seite.on("pageerror", lambda e: fehler.append(str(e)))
    seite.on("console", lambda m: fehler.append(m.text)
             if m.type == "error" and "favicon" not in m.location["url"] else None)


def test_die_seite_laedt_ohne_javascript_fehler(server):
    basis, _ = server
    fehler = []
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        _sammle_fehler(seite, fehler)
        try:
            anzahl = _lade(seite, basis)
            seite.wait_for_timeout(600)
            assert anzahl == 177, f"{anzahl} Laender geladen"
            assert fehler == [], f"JS-Fehler: {fehler}"
        finally:
            br.close()


# --- A6 Kriterium 1: Frankreich ist anklickbar -----------------------------


def test_a6_1_frankreich_ist_anklickbar(server):
    """Das Kriterium, an dem der ganze Auftrag haengt.

    Vorher lag Frankreichs Klickmarke bei lon=-10,71 lat=35,40 - im
    Atlantik suedwestlich von Portugal. Das Land war nicht anwaehlbar.
    """
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        seite.on("request", lambda r: gerufen.append(r.url)
                 if "/api/weltlage/" in r.url else None)
        try:
            _lade(seite, basis)
            _dreh_zu(seite, *FRANKREICH)
            x, y = _mitte(seite)
            seite.mouse.click(x, y)
            seite.wait_for_timeout(800)

            assert "France" in seite.text_content("#land"), \
                f"Kopfzeile zeigt {seite.text_content('#land')!r}"
            assert any("/api/weltlage/FRA" in u for u in gerufen), \
                f"kein FRA-Aufruf, gesehen: {gerufen}"
        finally:
            br.close()


def test_die_marke_liegt_nicht_mehr_im_atlantik(server):
    """Der Pruefstein aus dem Auftrag: zwischen 2 und 4 Grad Ost, 46 und 48
    Grad Nord. Liegt sie im Atlantik, ist der Fix falsch."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            ort = seite.evaluate(
                "() => window.zustand.laender.find(l => l.iso === 'FRA')")
            assert 2 <= ort["lon"] <= 4, f"lon={ort['lon']}"
            assert 46 <= ort["lat"] <= 48, f"lat={ort['lat']}"
        finally:
            br.close()


# --- A6 Kriterium 2: Ziehen dreht, waehlt aber nichts ----------------------


def test_a6_2_ziehen_dreht_und_waehlt_nichts(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        seite.on("request", lambda r: gerufen.append(r.url)
                 if "/api/weltlage/" in r.url else None)
        try:
            _lade(seite, basis)
            _dreh_zu(seite, *FRANKREICH)
            vorher = seite.evaluate("() => window.zustand.drehung()")
            gerufen.clear()

            x, y = _mitte(seite)
            seite.mouse.move(x, y)
            seite.mouse.down()
            for i in range(1, 11):
                seite.mouse.move(x + i * 20, y)
            seite.mouse.up()
            seite.wait_for_timeout(600)

            nachher = seite.evaluate("() => window.zustand.drehung()")
            assert abs(nachher["y"] - vorher["y"]) > 0.5, \
                f"nicht gedreht: {vorher} -> {nachher}"
            assert gerufen == [], f"Ziehen hat etwas ausgewaehlt: {gerufen}"
        finally:
            br.close()


# --- A6 Kriterium 3: die Rueckseite ist erreichbar -------------------------


def test_a6_3_die_rueckseite_ist_erreichbar(server):
    """Vorher gab es keinen Weg dorthin ausser einem Klick auf ein Land,
    das man nicht sehen konnte."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            _dreh_zu(seite, 0, 0)                 # Golf von Guinea
            x, y = _mitte(seite)

            # Eine halbe Umdrehung ziehen.
            seite.mouse.move(x, y)
            seite.mouse.down()
            for i in range(1, 32):
                seite.mouse.move(x + i * 20, y)
            seite.mouse.up()
            seite.wait_for_timeout(400)

            # Was jetzt in der Mitte steht, war vorher hinten.
            mitte = seite.evaluate("() => window.zustand.mitteLonLat()")
            assert mitte is not None, "kein Punkt in der Mitte"
            assert abs(mitte[0]) > 90, \
                f"nur {mitte[0]:.0f} Grad gedreht - die Rueckseite faengt bei 90 an"
        finally:
            br.close()


# --- A6 Kriterium 4: Klick auf Ozean waehlt nichts -------------------------


def test_a6_4_klick_auf_ozean_waehlt_nichts(server):
    """Vorher konnte der Strahl an den Marken vorbei durch die Erde laufen
    und ein Land auf der RUECKSEITE treffen."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        seite.on("request", lambda r: gerufen.append(r.url)
                 if "/api/weltlage/" in r.url else None)
        try:
            _lade(seite, basis)
            _dreh_zu(seite, *OZEAN)
            gerufen.clear()
            vorher = seite.text_content("#land")

            x, y = _mitte(seite)
            seite.mouse.click(x, y)
            seite.wait_for_timeout(800)

            assert gerufen == [], f"Ozeanklick hat etwas geladen: {gerufen}"
            assert seite.text_content("#land") == vorher
        finally:
            br.close()


def test_ein_klick_neben_die_kugel_waehlt_auch_nichts(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        seite.on("request", lambda r: gerufen.append(r.url)
                 if "/api/weltlage/" in r.url else None)
        try:
            _lade(seite, basis)
            gerufen.clear()
            kasten = seite.locator("#globus").bounding_box()
            # Obere linke Ecke: dort ist die Kugel nie.
            seite.mouse.click(kasten["x"] + 12, kasten["y"] + 12)
            seite.wait_for_timeout(500)
            assert gerufen == []
        finally:
            br.close()


# --- A6 Kriterium 5: Ruhelast ist null -------------------------------------


def test_a6_5_im_stillstand_wird_nicht_gezeichnet(server):
    """Vorher lief `renderer.render()` bedingungslos in jedem Frame - 60
    Bilder je Sekunde fuer ein Standbild. Als eingebetteter Tab ist genau
    das der Grund, warum der Chat ruckelt."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            seite.wait_for_timeout(1500)          # alles zur Ruhe kommen lassen
            vorher = seite.evaluate("() => window.__globusBilder")
            seite.wait_for_timeout(3000)
            nachher = seite.evaluate("() => window.__globusBilder")
            assert nachher == vorher, \
                f"{nachher - vorher} Bilder in 3 s Stillstand gezeichnet"
        finally:
            br.close()


def test_nach_einer_drehung_wird_wieder_gezeichnet(server):
    """Die Gegenprobe. Ein Zaehler, der nie steigt, waere auch 'null'."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            seite.wait_for_timeout(1200)
            vorher = seite.evaluate("() => window.__globusBilder")
            x, y = _mitte(seite)
            seite.mouse.move(x, y)
            seite.mouse.down()
            for i in range(1, 6):
                seite.mouse.move(x + i * 20, y)
            seite.mouse.up()
            seite.wait_for_timeout(400)
            assert seite.evaluate("() => window.__globusBilder") > vorher
        finally:
            br.close()


# --- A6 Kriterium 6: Touch dreht -------------------------------------------


def test_a6_6_touch_dreht(server):
    """Ein Satz Zeiger-Handler fuer Maus UND Finger - kein zweiter Pfad."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            vorher = seite.evaluate("() => window.zustand.drehung()")
            seite.evaluate("""() => {
              const c = document.getElementById('globus');
              const r = c.getBoundingClientRect();
              const x = r.left + r.width / 2, y = r.top + r.height / 2;
              const mach = (typ, px) => c.dispatchEvent(new PointerEvent(typ, {
                pointerId: 7, pointerType: 'touch', bubbles: true,
                clientX: px, clientY: y,
              }));
              mach('pointerdown', x);
              for (let i = 1; i <= 10; i++) mach('pointermove', x + i * 20);
              mach('pointerup', x + 200);
            }""")
            seite.wait_for_timeout(400)
            nachher = seite.evaluate("() => window.zustand.drehung()")
            assert abs(nachher["y"] - vorher["y"]) > 0.5, \
                f"Touch hat nicht gedreht: {vorher} -> {nachher}"
        finally:
            br.close()


# --- A6 Kriterium 7: Tastatur dreht ----------------------------------------


def test_a6_7_tastatur_dreht(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            seite.focus("#globus")
            vorher = seite.evaluate("() => window.zustand.drehung()")
            for _ in range(5):
                seite.keyboard.press("ArrowRight")
            seite.wait_for_timeout(300)
            nachher = seite.evaluate("() => window.zustand.drehung()")
            assert nachher["y"] > vorher["y"], \
                f"Pfeiltaste hat nicht gedreht: {vorher} -> {nachher}"
        finally:
            br.close()


def test_die_tastatur_zoomt_auch(server):
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            seite.focus("#globus")
            vorher = seite.evaluate("() => window.zustand.naehe()")
            for _ in range(4):
                seite.keyboard.press("+")
            seite.wait_for_timeout(300)
            nachher = seite.evaluate("() => window.zustand.naehe()")
            assert nachher < vorher, f"nicht herangezoomt: {vorher} -> {nachher}"
            assert nachher >= 1.45, "die vorhandene Nahgrenze muss halten"
        finally:
            br.close()


def test_der_zoom_haelt_die_vorhandenen_grenzen(server):
    """NAH = 1.45 und WEIT = 3.1 standen schon da. Keine neuen Zahlen."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            seite.focus("#globus")
            for _ in range(40):
                seite.keyboard.press("+")
            seite.wait_for_timeout(200)
            assert seite.evaluate("() => window.zustand.naehe()") >= 1.45
            for _ in range(60):
                seite.keyboard.press("-")
            seite.wait_for_timeout(200)
            assert seite.evaluate("() => window.zustand.naehe()") <= 3.1
        finally:
            br.close()


# --- A5: Laender ohne ISO ---------------------------------------------------


def test_a5_ein_land_ohne_iso_wird_nicht_angefragt(server):
    """Drei der 177 Geometrien haben keinen ISO-Code: N. Cyprus, Somaliland,
    Kosovo. Vorher wurde daraus eine Pseudo-Kennung gebastelt, die
    /api/weltlage/<iso> nie kennt."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        seite.on("request", lambda r: gerufen.append(r.url)
                 if "/api/weltlage/" in r.url else None)
        try:
            _lade(seite, basis)
            ohne = seite.evaluate(
                "() => window.zustand.laender.filter(l => l.ohne_iso)"
                ".map(l => l.name)")
            assert len(ohne) == 3, f"erwartet 3, gefunden {ohne}"

            gerufen.clear()
            seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => l.ohne_iso);
              window.zustand.waehle(i);
            }""")
            seite.wait_for_timeout(500)
            assert gerufen == [], f"trotzdem angefragt: {gerufen}"
            assert "Ländercode" in seite.text_content("#gesagt")
        finally:
            br.close()
