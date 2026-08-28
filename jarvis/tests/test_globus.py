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


def _tle_cache_fuellen(db_path):
    """Zwei echte Bahnsaetze in den TLE-Cache, auf heute datiert.

    Seit FIX-06 Abschnitt 7.3 holt der Globus beim Start
    `GET /api/satelliten/spur`. Ohne Cache und ohne Netz - und
    `tests/conftest.py` sperrt das Netz - antwortet der Endpunkt mit 503,
    und der Browser schreibt das als Konsolenfehler mit. Das ist keine
    Fehlfunktion, sondern die ehrliche Meldung "CelesTrak nicht erreichbar".

    Gefiltert wird sie trotzdem nicht: ein Filter, der einen echten Fehler
    verstecken kann, ist schlimmer als der Fehler. Stattdessen bekommt der
    Test die Daten, die er im Betrieb auch haette - dieselbe Entscheidung
    wie beim Favicon in FIX-05 A6.
    """
    from datetime import datetime, timezone

    from core.satellite.ueberflug import cache_datei

    heute = datetime.now(timezone.utc)
    tag = heute.timetuple().tm_yday + heute.hour / 24
    datei = cache_datei("visual", db_path=db_path)
    datei.parent.mkdir(parents=True, exist_ok=True)
    datei.write_text(
        "ISS (ZARYA)\r\n"
        f"1 25544U 98067A   26{tag:012.8f}  .00005000  00000-0  10000-3 0  9993\r\n"
        "2 25544  51.6400 208.9163 0001000  86.9990 273.1360 15.50377580440135\r\n",
        encoding="utf-8")

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
    _tle_cache_fuellen(st.db_path)
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
    """Jeder Seiten- und Konsolenfehler, ohne Ausnahme.

    Hier stand einmal ein Filter fuer `/favicon.ico`: Chromium holt das von
    sich aus, und weltlage.html hatte keins. Seit die Seite dasselbe
    eingebettete Favicon fuehrt wie index.html, gibt es den 404 nicht mehr -
    und ein Filter, der einen echten Fehler verstecken koennte, ist
    schlechter als kein Filter.
    """
    seite.on("pageerror", lambda e: fehler.append(str(e)))
    seite.on("console", lambda m: fehler.append(m.text)
             if m.type == "error" else None)


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


# --- Entscheidung 6 aus Noahs Bewegtbild-Vorlage: der Ring ------------------

_RING_LESEN = """() => {
  const r = window.zustand && window.zustand.ring;
  if (!r) return null;
  // Die Normale des Rings ist sein lokales +Z, gedreht mit seinem Quaternion.
  const n = new (r.position.constructor)(0, 0, 1).applyQuaternion(r.quaternion);
  const aussen = r.position.clone().normalize();
  return {
    sichtbar: r.visible,
    deckung: r.material.opacity,
    groesse: r.scale.x,
    radius: r.position.length(),
    // 1 = die Ringflaeche liegt flach auf der Kugel, 0 = sie steht senkrecht
    // darauf und waere von vorn nur ein Strich.
    flach: n.dot(aussen),
  };
}"""


def test_der_ring_liegt_flach_auf_der_kugel_beim_gewaehlten_land(server):
    """Die Vorlage (jarvis-scene.jsx:205-215) legt um die Marke einen Ring.

    Auf einer Kugel ist "flach" die eigentliche Arbeit: ein Ring, dessen
    Normale nicht nach aussen zeigt, ist von vorn ein Strich. Geprueft wird
    deshalb nicht, DASS es ein Mesh gibt, sondern wo es liegt und wie es
    liegt - dot(Normale, Ortsvektor) muss 1 sein.
    """
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade(seite, basis)
            vorher = seite.evaluate(_RING_LESEN)
            assert vorher is not None, "zustand.ring fehlt"
            assert vorher["sichtbar"] is False, "der Ring steht vor der Wahl im Bild"

            seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => !l.ohne_iso);
              window.zustand.waehle(i);
            }""")
            r = seite.evaluate(_RING_LESEN)
            assert r["sichtbar"] is True, r
            # Marken liegen auf 1.01, der Saum auf 1.032. Dazwischen.
            assert 1.010 < r["radius"] < 1.032, r["radius"]
            assert r["flach"] > 0.999, f"der Ring steht schraeg: {r['flach']}"
        finally:
            br.close()


def test_der_ring_blendet_weg_und_laesst_nichts_stehen(server):
    """Ohne reduzierte Bewegung geht der Ring auf und verschwindet.

    Der zweite Teil ist der wichtige: ein Mesh, das auf `opacity` 0 steht,
    aber `visible` bleibt, kostet in JEDEM Bild eine Zeichenanweisung - und
    genau davon lebt der Ruhezustand aus FIX-05 A4.
    """
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, reduziert=False)
        try:
            _lade(seite, basis)
            # Der Anfangswert wird im SELBEN evaluate gelesen, in dem
            # `waehle` laeuft. Sonst haengt er daran, wie viele Bilder
            # zwischen dem Aufruf und der naechsten Runde durch den
            # Playwright-Kanal vergehen - und genau so ist dieser Test beim
            # ersten Suitelauf rot geworden (0,667 statt der erwarteten
            # 0,45). Ein Test, dessen Ergebnis von der Maschinenlast
            # abhaengt, misst die Maschine, nicht den Code.
            seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => !l.ohne_iso);
              window.__ringSpur = [];
              window.zustand.waehle(i);
              window.__ringSpur.push(window.zustand.ring.scale.x);
              const nimm = () => {
                window.__ringSpur.push(window.zustand.ring.scale.x);
                if (window.zustand.ring.visible) requestAnimationFrame(nimm);
              };
              requestAnimationFrame(nimm);
            }""")
            assert seite.evaluate("() => window.__ringSpur[0]") == 0.45

            # --dauer-rein ist 380 ms. Nach 900 ms ist er sicher durch.
            seite.wait_for_timeout(900)
            danach = seite.evaluate(_RING_LESEN)
            assert danach["sichtbar"] is False, danach
            assert danach["groesse"] > 0.99, f"nicht ausgewachsen: {danach}"

            spur = seite.evaluate("() => window.__ringSpur")
            # Waechst nur, nie zurueck.
            assert spur == sorted(spur), spur
            # Und er waechst wirklich, statt zu springen: mindestens zwei
            # verschiedene Groessen. Der erste Wert steht garantiert fest
            # (synchron gesetzt), der letzte auch (1.0) - also hat dieser
            # Test keine Zeitabhaengigkeit mehr.
            assert len(set(spur)) >= 2, spur
            assert spur[-1] > 0.99, spur[-1]
        finally:
            br.close()


def test_bei_reduzierter_bewegung_steht_der_ring_still_und_bleibt(server):
    """"prefers-reduced-motion: alles sofort, alles sichtbar" - so steht es
    in der Vorlage selbst (jarvis-scene.jsx:678-680). Ein Ring, der
    wegblendet, waere fuer genau die Menschen nie zu sehen, fuer die die
    Einstellung gedacht ist."""
    basis, _ = server
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)          # reduziert=True ist der Standard
        try:
            _lade(seite, basis)
            seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => !l.ohne_iso);
              window.zustand.waehle(i);
            }""")
            seite.wait_for_timeout(900)
            r = seite.evaluate(_RING_LESEN)
            assert r["sichtbar"] is True, r
            assert r["deckung"] > 0.4, r["deckung"]
            assert r["groesse"] > 0.99, r["groesse"]
        finally:
            br.close()
