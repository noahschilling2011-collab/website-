"""FIX-05 Schritt B: der Globus als fuenfter Tab, ohne den Chat zu bremsen.

Die fuenf Kriterien aus B6. Der Kern ist nicht "der Globus erscheint" -
das waere leicht. Der Kern ist, dass er **nichts kostet**, solange man ihn
nicht ansieht:

* Three.js sind 2,0 MB (`three.module.js` 635 kB + `three.core.js` 1409 kB).
  Statisch importiert waeren sie in JEDEM Seitenaufruf drin.
* `zeigeAnsicht()` schaltet nur Klassen um. Ein Renderloop laeuft davon
  unbeeindruckt weiter - und genau das war das Ruckeln.
"""

from __future__ import annotations

import socket
import threading
import time

import pytest

playwright = pytest.importorskip("playwright.sync_api")
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

FRANKREICH = (3.3, 47.0)
OZEAN = (-150.0, 30.0)
BREITEN = (360, 768, 1440)


@pytest.fixture
def server(tmp_path):
    import uvicorn

    from api.app import create_app
    from core.config import Settings

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    st = Settings(_env_file=None, db_path=tmp_path / "tab.db",
                  jarvis_token="tab-token")
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
        yield f"http://127.0.0.1:{port}"
    finally:
        srv.should_exit = True
        faden.join(timeout=10)


def _browser(pw, breite=1440):
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": breite, "height": 900},
                        reduced_motion="reduce")
    return br, seite


def _lade_chat(seite, basis, gerufen=None):
    if gerufen is not None:
        seite.on("request", lambda r: gerufen.append(r.url))
    seite.goto(basis + "/", wait_until="networkidle")
    seite.wait_for_selector("#tab-welt")
    return seite


def _oeffne_welt(seite):
    seite.click("#tab-welt")
    # Erst wenn die Grenzen da sind, ist der Globus fertig - starte()
    # loest genau dann auf, und dann steht der Zaehler im body.
    seite.wait_for_function("() => document.body.dataset.laender", timeout=40000)
    seite.wait_for_timeout(400)


def _dreh_zu(seite, lon, lat):
    seite.evaluate(f"() => window.zustand.dreheZu({lon}, {lat})")
    seite.wait_for_timeout(250)


def _mitte(seite):
    k = seite.locator("#globus").bounding_box()
    return k["x"] + k["width"] / 2, k["y"] + k["height"] / 2


def _drei(liste, teil):
    return [u for u in liste if teil in u]


# --- B6 Kriterium 1: ohne Weltansicht keine 2 MB ---------------------------


def test_b6_1_ohne_weltansicht_kommt_three_nicht(server):
    """Der ganze Anti-Lag-Trick. Wer den Tab nie oeffnet, laedt nie 2 MB."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _lade_chat(seite, server, gerufen)
            # Durch die anderen Tabs klicken - auch die duerfen es nicht holen.
            for tab in ("#tab-tasks", "#tab-tools", "#tab-kosten", "#tab-chat"):
                seite.click(tab)
                seite.wait_for_timeout(250)

            assert _drei(gerufen, "three.core.js") == [], "2 MB ungefragt geladen"
            assert _drei(gerufen, "three.module.js") == []
            assert _drei(gerufen, "globus.js") == []
            assert _drei(gerufen, "countries-110m.json") == []
        finally:
            br.close()


# --- B6 Kriterium 2: beim Oeffnen einmal, und nur einmal -------------------


def test_b6_2_beim_oeffnen_kommt_es_genau_einmal(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _lade_chat(seite, server, gerufen)
            _oeffne_welt(seite)

            assert len(_drei(gerufen, "three.core.js")) == 1, \
                _drei(gerufen, "three.core.js")
            assert len(_drei(gerufen, "globus.js")) == 1

            # Zweites Oeffnen: kein weiterer Abruf. Der Browser-Cache waere
            # kein Beleg - hier darf die Anfrage gar nicht erst rausgehen.
            seite.click("#tab-chat")
            seite.wait_for_timeout(300)
            seite.click("#tab-welt")
            seite.wait_for_timeout(800)

            assert len(_drei(gerufen, "three.core.js")) == 1, "zweimal geladen"
            assert len(_drei(gerufen, "globus.js")) == 1
        finally:
            br.close()


# --- B6 Kriterium 3: der Chat bleibt fluessig ------------------------------


def test_b6_3_nach_dem_zurueckschalten_wird_nicht_mehr_gezeichnet(server):
    """`zeigeAnsicht()` schaltet nur Klassen um - der Renderloop lief weiter.

    Der IntersectionObserver reicht dafuer nicht: ob er bei `display:none`
    feuert, haengt am Browser. Deshalb schaltet `pausiere()` ausdruecklich ab.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            # Etwas bewegen, damit sicher gezeichnet wird.
            _dreh_zu(seite, *FRANKREICH)
            seite.wait_for_timeout(600)

            seite.click("#tab-chat")
            seite.wait_for_timeout(500)
            vorher = seite.evaluate("() => window.__globusBilder")
            seite.wait_for_timeout(3000)
            nachher = seite.evaluate("() => window.__globusBilder")

            assert nachher == vorher, \
                f"{nachher - vorher} Bilder gezeichnet, waehrend der Chat offen war"

            # Und die Schleife selbst muss aus sein, nicht nur early-return.
            # Gemessen am 26.08.2026: der IntersectionObserver reagiert in
            # diesem Chromium sehr wohl auf `display:none`, `sichtbar` wird
            # also false und `schleife()` steigt sofort aus. Der Zaehler der
            # BILDER steht damit auch ohne `pausiere()` still - der Zaehler
            # der AUFRUFE nicht. Ohne diese zwei Zeilen prueft der Test
            # nicht, was B-4 verlangt. (Mutation M1, siehe docs/FIX-05.md.)
            s_vorher = seite.evaluate("() => window.__globusSchleife")
            seite.wait_for_timeout(1500)
            s_nachher = seite.evaluate("() => window.__globusSchleife")
            assert s_nachher == s_vorher, \
                f"{s_nachher - s_vorher} Schleifendurchlaeufe trotz pausiere()"
        finally:
            br.close()


def test_nach_dem_zurueckwechseln_lebt_der_globus_wieder(server):
    """Die Gegenprobe. Ein Globus, der nach dem Pausieren tot bleibt, waere
    auch 'null Bilder'."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            seite.click("#tab-chat")
            seite.wait_for_timeout(400)
            vorher = seite.evaluate("() => window.__globusBilder")

            seite.click("#tab-welt")
            seite.wait_for_timeout(300)
            _dreh_zu(seite, 20, 10)
            seite.wait_for_timeout(400)

            assert seite.evaluate("() => window.__globusBilder") > vorher
        finally:
            br.close()


# --- B6 Kriterium 4: das Layout haelt --------------------------------------


@pytest.mark.parametrize("breite", BREITEN)
def test_b6_4_kein_seitliches_scrollen_in_beiden_tabs(server, breite):
    """Der Globus hing frueher per `position:fixed` am Fenster und mit
    `42vw` an der Fensterbreite. Im Behaelter ist beides falsch."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, breite)
        try:
            _lade_chat(seite, server)
            ueber = seite.evaluate(
                "() => document.documentElement.scrollWidth > window.innerWidth")
            assert not ueber, f"Chat scrollt seitwaerts bei {breite} px"

            _oeffne_welt(seite)
            ueber = seite.evaluate(
                "() => document.documentElement.scrollWidth > window.innerWidth")
            assert not ueber, f"Weltansicht scrollt seitwaerts bei {breite} px"

            # Und der Globus muss wirklich im Behaelter sitzen, nicht darueber.
            masse = seite.evaluate("""() => {
              const v = document.getElementById('view-welt').getBoundingClientRect();
              const c = document.getElementById('globus').getBoundingClientRect();
              return {v: [v.x, v.y, v.width, v.height], c: [c.x, c.y, c.width, c.height]};
            }""")
            v, c = masse["v"], masse["c"]
            assert c[2] > 100 and c[3] > 100, f"Canvas ist {c[2]}x{c[3]}"
            assert abs(c[0] - v[0]) < 2 and abs(c[1] - v[1]) < 2, masse
            assert abs(c[2] - v[2]) < 2 and abs(c[3] - v[3]) < 2, masse
        finally:
            br.close()


def test_nach_einer_groessenaenderung_im_hintergrund_stimmt_das_canvas(server):
    """B-5, der Fall, um den es wirklich geht.

    In einer Ansicht mit `display:none` sind clientWidth und clientHeight 0,
    und `resize()` steigt frueh aus. Wer das Fenster zieht, waehrend der
    Chat offen ist, bekommt beim Zurueckschalten ein Canvas in der alten
    Groesse - verzerrt oder mit Rand. `weiter()` misst deshalb neu.

    Ehrlich dazu: gemessen ist das ERGEBNIS, nicht der Weg. Nimmt man nur
    das `resizeFn()` aus `weiter()` heraus, bleibt der Test gruen - der
    `ResizeObserver` faengt es dann ab (Mutation M3). Erst ohne beide faellt
    er (M3b). Der Auftrag will sich auf den Observer ausdruecklich nicht
    verlassen; deshalb steht die Zeile trotzdem da.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, 1440)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            seite.click("#tab-chat")
            seite.wait_for_timeout(300)

            # Fenster kleiner ziehen, WAEHREND die Weltansicht versteckt ist.
            seite.set_viewport_size({"width": 700, "height": 620})
            seite.wait_for_timeout(300)

            seite.click("#tab-welt")
            seite.wait_for_timeout(500)
            masse = seite.evaluate("""() => {
              const v = document.getElementById('view-welt').getBoundingClientRect();
              const c = document.getElementById('globus');
              const r = c.getBoundingClientRect();
              return {breite: r.width, hoehe: r.height, vb: v.width, vh: v.height,
                      puffer: [c.width, c.height]};
            }""")
            assert abs(masse["breite"] - masse["vb"]) < 2, masse
            assert abs(masse["hoehe"] - masse["vh"]) < 2, masse
            # Der ZEICHENPUFFER muss mitgezogen sein, nicht nur das Element.
            # Das Element folgt schon der CSS (`inset:0`), der Puffer nicht -
            # der haengt an `renderer.setSize()`. Steht er noch auf der alten
            # Fensterbreite, ist das Bild verzerrt.
            # Die Seite laeuft mit device_scale_factor 1, also ist
            # `setPixelRatio(min(1,2))` gleich 1: Puffer == CSS-Breite.
            # Eine weichere Schranke haette den stehengebliebenen Puffer
            # (1440 zu 700, Verhaeltnis 2,06) durchgelassen - gemessen.
            verhaeltnis = masse["puffer"][0] / max(masse["breite"], 1)
            assert 0.95 <= verhaeltnis <= 1.05, masse
        finally:
            br.close()


def test_die_ansicht_ueberdeckt_den_kopf_nicht(server):
    """`position:fixed;inset:0` haette den Globus ueber die Tableiste gelegt -
    man kaeme nicht mehr zurueck."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            kopf = seite.locator("#tab-chat").bounding_box()
            welt = seite.locator("#view-welt").bounding_box()
            assert welt["y"] >= kopf["y"] + kopf["height"] - 1, (kopf, welt)
            # Und der Weg zurueck geht wirklich.
            seite.click("#tab-chat")
            seite.wait_for_timeout(200)
            assert seite.get_attribute("#tab-chat", "aria-selected") == "true"
        finally:
            br.close()


# --- B6 Kriterium 5: die sieben A-Kriterien gelten im Tab genauso ----------


def test_b6_5_a1_frankreich_ist_auch_im_tab_anklickbar(server):
    """Und dabei gleich der Token.

    `#land` zeigt "France" schon, BEVOR die Antwort da ist - `ladeLand()`
    schreibt den Namen sofort hin. Diese Zusage allein belegt also nichts
    ueber den Aufruf. Der Token wandert im Tab einen anderen Weg als auf der
    eigenen Seite: `starte(ziel, TOKEN)` reicht ihn aus `index.html` herein,
    statt dass er wie frueher im Modul selbst stuende. Waere dabei etwas
    schiefgegangen, kaeme 401 zurueck - deshalb wird hier die ANTWORT
    geprueft, nicht nur die Anfrage.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen, antworten = [], []
        try:
            _lade_chat(seite, server)
            seite.on("request", lambda r: gerufen.append(r.url)
                     if "/api/weltlage/" in r.url else None)
            seite.on("response", lambda r: antworten.append((r.url, r.status))
                     if "/api/weltlage/" in r.url else None)
            _oeffne_welt(seite)
            _dreh_zu(seite, *FRANKREICH)
            x, y = _mitte(seite)
            seite.mouse.click(x, y)
            seite.wait_for_timeout(900)

            assert "France" in seite.text_content("#land")
            assert any("/api/weltlage/FRA" in u for u in gerufen), gerufen
            abgelehnt = [(u, c) for u, c in antworten if c in (401, 403)]
            assert abgelehnt == [], f"Token kam nicht an: {abgelehnt}"
            assert any(c == 200 for _, c in antworten), antworten
        finally:
            br.close()


def test_b6_5_a2_ziehen_dreht_und_waehlt_nichts(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _lade_chat(seite, server)
            seite.on("request", lambda r: gerufen.append(r.url)
                     if "/api/weltlage/" in r.url else None)
            _oeffne_welt(seite)
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
            assert abs(nachher["y"] - vorher["y"]) > 0.5, (vorher, nachher)
            assert gerufen == [], gerufen
        finally:
            br.close()


def test_b6_5_a3_die_rueckseite_ist_erreichbar(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            _dreh_zu(seite, 0, 0)
            x, y = _mitte(seite)
            seite.mouse.move(x, y)
            seite.mouse.down()
            for i in range(1, 32):
                seite.mouse.move(x + i * 20, y)
            seite.mouse.up()
            seite.wait_for_timeout(400)

            mitte = seite.evaluate("() => window.zustand.mitteLonLat()")
            assert mitte is not None
            assert abs(mitte[0]) > 90, mitte
        finally:
            br.close()


def test_b6_5_a4_klick_auf_ozean_waehlt_nichts(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _lade_chat(seite, server)
            seite.on("request", lambda r: gerufen.append(r.url)
                     if "/api/weltlage/" in r.url else None)
            _oeffne_welt(seite)
            _dreh_zu(seite, *OZEAN)
            gerufen.clear()
            vorher = seite.text_content("#land")
            x, y = _mitte(seite)
            seite.mouse.click(x, y)
            seite.wait_for_timeout(800)
            assert gerufen == [], gerufen
            assert seite.text_content("#land") == vorher
        finally:
            br.close()


def test_b6_5_a5_im_stillstand_wird_nicht_gezeichnet(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            seite.wait_for_timeout(1500)
            vorher = seite.evaluate("() => window.__globusBilder")
            seite.wait_for_timeout(3000)
            nachher = seite.evaluate("() => window.__globusBilder")
            assert nachher == vorher, f"{nachher - vorher} Bilder im Stillstand"
        finally:
            br.close()


def test_b6_5_a6_touch_dreht(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
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
            assert abs(nachher["y"] - vorher["y"]) > 0.5, (vorher, nachher)
        finally:
            br.close()


def test_b6_5_a7_tastatur_dreht_und_zoomt(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            seite.focus("#globus")
            vorher = seite.evaluate("() => window.zustand.drehung()")
            for _ in range(5):
                seite.keyboard.press("ArrowRight")
            seite.wait_for_timeout(300)
            assert seite.evaluate("() => window.zustand.drehung()")["y"] > vorher["y"]

            nah_vorher = seite.evaluate("() => window.zustand.naehe()")
            for _ in range(4):
                seite.keyboard.press("+")
            seite.wait_for_timeout(300)
            nah = seite.evaluate("() => window.zustand.naehe()")
            assert nah < nah_vorher and nah >= 1.45, (nah_vorher, nah)
        finally:
            br.close()


# --- Was der Einbau NICHT kaputtmachen darf --------------------------------


def test_die_leertaste_im_chat_startet_nicht_den_globus(server):
    """Der Globus hoert auf die Leertaste (Push-to-Talk). Im eigenen Tab war
    das harmlos; im Chat haengt derselbe Handler am selben Fenster.

    Geprueft wird das Sichtbare: nach dem Tippen steht das Leerzeichen im
    Eingabefeld, und die Statuszeile des Globus hat sich nicht geruehrt.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            seite.click("#tab-chat")
            seite.wait_for_timeout(300)

            seite.click("#input")
            seite.keyboard.type("hallo welt")
            assert seite.input_value("#input") == "hallo welt"

            # Und ohne Fokus im Feld ebenfalls nicht - die Ansicht ist aus.
            # Gemessen wird `defaultPrevented`: der Globus ruft als Erstes
            # `preventDefault()`. Ueber den Mikrofonknopf zu gehen taugt
            # nicht - `onerror` setzt `aria-pressed` binnen Millisekunden
            # zurueck, und der Test waere blind. (Mutation M4.)
            seite.evaluate("() => document.getElementById('input').blur()")
            geschluckt = seite.evaluate("""() => {
              const ev = new KeyboardEvent('keydown', {
                key: ' ', code: 'Space', bubbles: true, cancelable: true});
              document.body.dispatchEvent(ev);
              return ev.defaultPrevented;
            }""")
            assert geschluckt is False, \
                "die Leertaste wurde im Chat vom Globus abgefangen"
        finally:
            br.close()


def test_wer_waehrend_des_ladens_wegklickt_laesst_nichts_laufen(server):
    """Der Fehler, den erst eine gedrosselte Leitung sichtbar macht.

    `globusModul` wurde frueher erst gesetzt, wenn `starte()` durch war -
    also nach den 2,0 MB Three.js UND den beiden Geometrie-Abrufen. Die
    Pause-Zeile in `zeigeAnsicht()` prueft aber genau darauf. Wer waehrend
    des Ladens zurueck auf "Chat" ging, hatte den Renderloop danach
    dauerhaft im Chat laufen, und die Leertaste blieb beim Globus haengen.

    Gemessen bei 250 kB/s vor dem Fix: 114 Schleifendurchlaeufe in zwei
    Sekunden bei sichtbarem Chat, `defaultPrevented` auf der Leertaste true.
    Ohne Drosselung ist das Fenster zu schmal - der Test braucht sie.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            cdp = seite.context.new_cdp_session(seite)
            cdp.send("Network.enable")
            cdp.send("Network.emulateNetworkConditions", {
                "offline": False, "latency": 60,
                "downloadThroughput": 250 * 1024, "uploadThroughput": 250 * 1024})

            _lade_chat(seite, server)
            seite.click("#tab-welt")
            seite.wait_for_timeout(2500)          # mitten in den 2 MB
            seite.click("#tab-chat")
            seite.wait_for_timeout(8000)          # dem Globus Zeit zum Fertigwerden

            vorher = seite.evaluate("() => window.__globusSchleife || 0")
            seite.wait_for_timeout(2000)
            nachher = seite.evaluate("() => window.__globusSchleife || 0")
            assert nachher == vorher, \
                f"{nachher - vorher} Schleifendurchlaeufe im Chat"

            geschluckt = seite.evaluate("""() => {
              if (document.activeElement) document.activeElement.blur();
              const ev = new KeyboardEvent('keydown', {
                key: ' ', code: 'Space', bubbles: true, cancelable: true});
              document.body.dispatchEvent(ev);
              return ev.defaultPrevented;
            }""")
            assert geschluckt is False, "die Leertaste blieb beim Globus"
        finally:
            br.close()


def test_und_danach_geht_der_globus_trotzdem_noch(server):
    """Die Gegenprobe: ein Globus, der nach dem Rennen tot bleibt, waere
    auch 'null Schleifendurchlaeufe'."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            cdp = seite.context.new_cdp_session(seite)
            cdp.send("Network.enable")
            cdp.send("Network.emulateNetworkConditions", {
                "offline": False, "latency": 60,
                "downloadThroughput": 250 * 1024, "uploadThroughput": 250 * 1024})

            _lade_chat(seite, server)
            seite.click("#tab-welt")
            seite.wait_for_timeout(2500)
            seite.click("#tab-chat")
            seite.wait_for_timeout(8000)

            seite.click("#tab-welt")
            seite.wait_for_function("() => document.body.dataset.laender", timeout=40000)
            seite.wait_for_timeout(300)
            vorher = seite.evaluate("() => window.__globusSchleife")
            _dreh_zu(seite, 20, 10)
            seite.wait_for_timeout(400)
            assert seite.evaluate("() => window.__globusSchleife") > vorher
            assert seite.evaluate("() => window.__globusBilder") > 0
        finally:
            br.close()


def test_in_der_weltansicht_gehoert_die_leertaste_dem_globus(server):
    """Die Gegenprobe zum Test darueber.

    Ohne sie waere "die Leertaste startet den Globus nicht" auch dann gruen,
    wenn man den Leertasten-Handler ersatzlos loescht - das Feature waere weg
    und der Test zufrieden. Hier muss sie greifen: in der Weltansicht, ohne
    Fokus in einem Eingabefeld, nimmt der Globus die Taste an.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            geschluckt = seite.evaluate("""() => {
              if (document.activeElement) document.activeElement.blur();
              const ev = new KeyboardEvent('keydown', {
                key: ' ', code: 'Space', bubbles: true, cancelable: true});
              document.body.dispatchEvent(ev);
              return ev.defaultPrevented;
            }""")
            assert geschluckt is True, \
                "der Globus nimmt die Leertaste nicht mehr an"

            # Aus einem Eingabefeld heraus aber nie - dort ist sie ein
            # Leerzeichen. (Der Globus hat selbst eins: die Ortssuche.)
            im_feld = seite.evaluate("""() => {
              const feld = document.getElementById('ort-eingabe');
              feld.focus();
              const ev = new KeyboardEvent('keydown', {
                key: ' ', code: 'Space', bubbles: true, cancelable: true});
              feld.dispatchEvent(ev);
              return ev.defaultPrevented;
            }""")
            assert im_feld is False, "die Ortssuche kann kein Leerzeichen mehr"
        finally:
            br.close()


def test_der_tab_laedt_ohne_javascript_fehler(server):
    """`tests/test_globus.py` prueft das fuer die eigene Seite. Im Tab ist
    es eine andere Umgebung: fremdes CSS, fremde ids, ein dynamischer
    Import. Also hier noch einmal, ueber beide Ansichten."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        fehler = []
        try:
            seite.on("pageerror", lambda e: fehler.append("pageerror: " + str(e)))
            seite.on("console", lambda m: fehler.append("konsole: " + m.text)
                     if m.type == "error" else None)
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            _dreh_zu(seite, *FRANKREICH)
            seite.wait_for_timeout(500)
            seite.click("#tab-chat")
            seite.wait_for_timeout(500)
            seite.click("#tab-welt")
            seite.wait_for_timeout(800)
            assert fehler == [], fehler
        finally:
            br.close()


def test_keine_doppelten_ids_auf_der_seite(server):
    """`btn-mic` gibt es im Chat schon. Zwei gleiche ids in einem Dokument
    sind ungueltig, und `getElementById` trifft dann die falsche."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            doppelt = seite.evaluate("""() => {
              const gesehen = {}, doppelt = [];
              document.querySelectorAll('[id]').forEach(n => {
                if (gesehen[n.id]) doppelt.push(n.id);
                gesehen[n.id] = true;
              });
              return doppelt;
            }""")
            assert doppelt == [], doppelt
        finally:
            br.close()


def test_die_karten_des_chats_bleiben_wie_sie_waren(server):
    """`.karte` gibt es in beiden Welten (index.html:450 und im Globus-Stil).

    Gemessen wird an einer eigens eingehaengten `.karte` im Auftragstab -
    so haengt der Test nicht daran, ob gerade Auftraege da sind. Vorher und
    nachher muss derselbe Innenabstand herauskommen; sonst hat der
    Globus-Stil in den Chat hineingefaerbt.
    """
    MESSEN = """() => {
      const box = document.getElementById('view-tasks');
      let probe = box.querySelector('.karte.probe');
      if (!probe){
        probe = document.createElement('div');
        probe.className = 'karte probe';
        box.appendChild(probe);
      }
      const s = getComputedStyle(probe);
      return {padding: s.padding, rand: s.marginBottom, grund: s.backgroundColor};
    }"""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            vorher = seite.evaluate(MESSEN)
            assert vorher["padding"] != "0px", \
                "der Chat hat Innenabstand - sonst misst dieser Test nichts"

            _oeffne_welt(seite)
            seite.click("#tab-tasks")
            seite.wait_for_timeout(400)
            nachher = seite.evaluate(MESSEN)
            assert nachher == vorher, (vorher, nachher)
        finally:
            br.close()


def test_und_umgekehrt_bekommt_die_globus_karte_keinen_chat_abstand(server):
    """Die Gegenrichtung: `index.html:454` setzt `padding` auf `.karte`.
    Ohne die zwei Gegenzeilen im Globus-Stil saesse im Tab Luft um jede
    Meldungskarte.

    Ehrlich dazu: nimmt man nur die zwei Zeilen weg, bleibt der Test gruen -
    dann greift der Stern-Reset `.globus-wurzel *{...padding:0}`, der
    dieselbe Spezifitaet hat und spaeter im Dokument steht (Mutation M6).
    Erst ohne beide faellt er (M6b). Die zwei Zeilen sind die
    reihenfolgeunabhaengige Ansage; der Test misst, dass am Ende null
    herauskommt.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _lade_chat(seite, server)
            _oeffne_welt(seite)
            werte = seite.evaluate("""() => {
              const box = document.querySelector('#view-welt .karten');
              const probe = document.createElement('article');
              probe.className = 'karte';
              box.appendChild(probe);
              const s = getComputedStyle(probe);
              const r = {padding: s.padding, rand: s.marginBottom};
              probe.remove();
              return r;
            }""")
            assert werte == {"padding": "0px", "rand": "0px"}, werte
        finally:
            br.close()
