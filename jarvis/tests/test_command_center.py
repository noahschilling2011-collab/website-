"""FIX-06 Abschnitt 6: die Ansicht COMMAND CENTER.

Die sechs Kriterien aus der DoD, plus die Gegenprobe, die dabei am
leichtesten kaputtgeht: **die Startansicht darf Three.js nicht laden.**
Zone 2 zeigt einen Globus - wenn sie ihn beim Start holt, sind die 2,0 MB
aus FIX-05 B-2 wieder da, und zwar in jedem Seitenaufruf.
"""

from __future__ import annotations

import socket
import threading
import time

import pytest

playwright = pytest.importorskip("playwright.sync_api")
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"


@pytest.fixture
def server(tmp_path):
    import uvicorn

    from api.app import create_app
    from core.config import Settings

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    st = Settings(_env_file=None, db_path=tmp_path / "cc.db",
                  jarvis_token="cc-token")
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


def _browser(pw, breite=1440, hoehe=900):
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": breite, "height": hoehe},
                        reduced_motion="reduce")
    return br, seite


def _oeffne(seite, basis, gerufen=None, fehler=None):
    if gerufen is not None:
        seite.on("request", lambda r: gerufen.append(r.url))
    if fehler is not None:
        seite.on("pageerror", lambda e: fehler.append(str(e)))
        seite.on("console", lambda m: fehler.append(m.text) if m.type == "error" else None)
    seite.goto(basis + "/", wait_until="domcontentloaded")
    seite.wait_for_selector("#view-cc .cc", timeout=20000)
    # Die Sammelabfrage laeuft nach dem Aufbau; ihr Ergebnis steht in den Zonen.
    seite.wait_for_timeout(900)
    return seite


# --- Die Ansicht ist die Startansicht -------------------------------------


def test_das_command_center_ist_die_startansicht(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            assert seite.get_attribute("#tab-cc", "aria-selected") == "true"
            assert seite.eval_on_selector("#view-cc", "e => e.classList.contains('is-active')")
            assert not seite.eval_on_selector("#thread", "e => e.classList.contains('is-active')")
            # Die Eingabe gehoert zum Chat.
            assert seite.eval_on_selector(".composer-wrap", "e => e.hidden") is True
        finally:
            br.close()


def test_die_startansicht_laedt_three_js_nicht(server):
    """Die wichtigste Gegenprobe. Zone 2 zeigt einen Globus - aber erst auf
    Wunsch. Sonst haengen 2,0 MB an jedem Seitenaufruf."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _oeffne(seite, server, gerufen)
            seite.wait_for_timeout(600)
            three = [u for u in gerufen if "three" in u or "globus.js" in u]
            assert three == [], three
            # Und der Nutzer erfaehrt, warum da kein Globus ist.
            hinweis = seite.inner_text(".cc-globus-hinweis")
            assert "2,0 MB" in hinweis
        finally:
            br.close()


# --- DoD 1 -----------------------------------------------------------------


def test_dod_1_kein_scrollen_bei_1440x900(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, 1440, 900)
        try:
            _oeffne(seite, server)
            mass = seite.evaluate(
                "() => ({hoch: document.body.scrollHeight, sicht: innerHeight,"
                " breit: document.documentElement.scrollWidth, quer: innerWidth})")
            assert mass["hoch"] <= mass["sicht"], mass
            assert mass["breit"] <= mass["quer"], mass
            # Auch die Ansicht selbst scrollt nicht in sich.
            innen = seite.eval_on_selector(
                "#view-cc", "e => e.scrollHeight - e.clientHeight")
            assert innen <= 1, innen
        finally:
            br.close()


# --- DoD 2 -----------------------------------------------------------------


def test_dod_2_jede_zone_hat_eine_echte_quelle(server):
    """Netzmitschnitt: acht Zonen, und jede Zahl darin kommt aus einem
    Endpunkt, den es gibt."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _oeffne(seite, server, gerufen)
            pfade = {u.split("127.0.0.1:")[-1].split("/", 1)[-1].split("?")[0]
                     for u in gerufen if "/api/" in u}
            for noetig in ("api/health", "api/tasks", "api/stats",
                           "api/stats/verlauf", "api/tool-calls",
                           "api/events", "api/weltlage/WELT"):
                assert noetig in pfade, (noetig, sorted(pfade))
            # Acht Zonen, nicht sieben und nicht neun.
            assert seite.eval_on_selector_all("#view-cc .cc > .zone", "l => l.length") == 8
        finally:
            br.close()


def test_der_endpunkt_fuer_zone_7_antwortet_wirklich(server):
    """Zone 7 haengt an einem Endpunkt, den es vor diesem Abschnitt nicht
    gab. Wenn der 404 gibt, sieht man in der Zone trotzdem etwas - deshalb
    hier direkt gemessen."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        antworten = []
        try:
            seite.on("response", lambda r: antworten.append((r.url, r.status)))
            _oeffne(seite, server)
            verlauf = [a for a in antworten if "stats/verlauf" in a[0]]
            assert verlauf, "der Endpunkt wurde gar nicht gerufen"
            assert all(s == 200 for _, s in verlauf), verlauf
        finally:
            br.close()


# --- DoD 3 -----------------------------------------------------------------


def test_dod_3_leerer_zustand_ist_sauber(server):
    """Frische Datenbank. Striche und Saetze, keine Nullen, die wie Daten
    aussehen."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            leere = seite.eval_on_selector_all(
                "#view-cc .zone-leer", "l => l.map(e => e.textContent)")
            # Auftraege, Werkzeuge, Verlauf, Meldungen - vier Zonen sind leer.
            assert len(leere) >= 4, leere
            for text in leere:
                assert len(text.strip()) > 10, text
            # Kein Skelett-Flimmern: nichts, was unendlich animiert.
            unendlich = seite.evaluate("""() => {
              var n = 0;
              document.querySelectorAll('#view-cc *').forEach(function (e) {
                var s = getComputedStyle(e);
                if (s.animationName !== 'none' && s.animationIterationCount === 'infinite') n++;
              });
              return n;
            }""")
            assert unendlich == 0, unendlich
            # Die Zonen stehen trotzdem: jede hat ihre Ueberschrift behalten.
            koepfe = seite.eval_on_selector_all(
                "#view-cc .zone-kopf", "l => l.length")
            assert koepfe >= 6, koepfe

            # "Keine Nullen, die wie Daten aussehen": bei frischer Datenbank
            # steht in den Kennzahlen ein Strich. Ausnahme sind die Kosten -
            # DoD 5 verlangt dort ausdruecklich die 0,0000 mit dem Hinweis.
            werte = seite.eval_on_selector_all(
                ".cc-kennzahl", "l => l.map(e => ({w: e.querySelector('.wert').textContent,"
                " f: e.querySelector('.fussnote').textContent}))")
            for k in werte:
                if "€" in k["w"]:
                    continue
                assert k["w"] == "—", werte
                assert k["f"].strip(), werte
        finally:
            br.close()


# --- DoD 4 -----------------------------------------------------------------


def test_dod_4_kein_polling_im_leerlauf(server):
    """Der Strom ersetzt den Timer. Im Leerlauf darf nichts nachgefragt
    werden - ausser der Uhr, und die geht nicht ins Netz."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _oeffne(seite, server, gerufen)
            seite.wait_for_timeout(500)
            vorher = len([u for u in gerufen if "/api/" in u])
            seite.wait_for_timeout(5000)
            nachher = len([u for u in gerufen if "/api/" in u])
            assert nachher == vorher, [u for u in gerufen[vorher:] if "/api/" in u]
            # Die Uhr laeuft trotzdem - sonst waere der Test wertlos.
            a = seite.inner_text(".cc-uhr")
            seite.wait_for_timeout(1200)
            assert seite.inner_text(".cc-uhr") != a
        finally:
            br.close()


def test_dod_4_ein_ereignis_bewegt_zone_3_und_4(server):
    """Die andere Haelfte: ohne Timer muss der Strom wirklich etwas
    ausloesen."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            # Der Strom meldet sich beim Verbinden selbst ("hello"), das ist
            # schon eine Zeile. Gemessen wird deshalb der Zuwachs.
            vorher = seite.eval_on_selector_all("#view-cc .cc-strom div", "l => l.length")
            # Auftrag ueber die API anstossen, nicht ueber die Oberflaeche -
            # sonst misst der Test den Chat mit.
            seite.evaluate("""(t) => fetch('/api/tasks', {
                method: 'POST',
                headers: {'X-Jarvis-Token': t, 'Content-Type': 'application/json'},
                body: JSON.stringify({goal: 'Wie spaet ist es?'})
            })""", "cc-token")
            seite.wait_for_function(
                "(n) => document.querySelectorAll('#view-cc .cc-strom div').length > n",
                arg=vorher, timeout=30000)
            zeilen = seite.eval_on_selector_all(
                "#view-cc .cc-strom div", "l => l.map(e => e.textContent)")
            assert any("task" in z for z in zeilen), zeilen
        finally:
            br.close()


# --- DoD 5 -----------------------------------------------------------------


def test_dod_5_kosten_sagen_die_wahrheit(server):
    """Ohne Preise in der .env steht 0,0000 EUR - mit dem Satz daneben,
    warum. Eine geschaetzte Zahl waere schlimmer als gar keine."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            kacheln = seite.eval_on_selector_all(
                ".cc-kennzahl", "l => l.map(e => e.textContent)")
            kosten = [k for k in kacheln if "€" in k]
            assert len(kosten) == 1, kacheln
            assert "0,0000 €" in kosten[0], kosten
            assert "Preise nicht in .env eingetragen" in kosten[0], kosten
        finally:
            br.close()


# --- DoD 6 -----------------------------------------------------------------


def test_dod_6_mobil_stapeln_sich_die_zonen(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, 360, 780)
        try:
            _oeffne(seite, server)
            quer = seite.evaluate(
                "() => document.documentElement.scrollWidth - innerWidth")
            assert quer <= 0, quer
            # Jede Zone nimmt die volle Breite - keine 3-Spalten-Zone auf 360 px.
            breiten = seite.eval_on_selector_all(
                "#view-cc .cc > .zone", "l => l.map(e => Math.round(e.getBoundingClientRect().width))")
            assert len(set(breiten)) == 1, breiten
            assert breiten[0] > 300, breiten
        finally:
            br.close()


# --- Aufraeumen beim Tabwechsel -------------------------------------------


def test_beim_verlassen_gehen_uhr_und_strom_aus(server):
    """Ein Timer, der im Chat weiterlaeuft, ist genau das Ruckeln, das
    FIX-05 B-4 abgestellt hat - nur an einer anderen Stelle."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        gerufen = []
        try:
            _oeffne(seite, server, gerufen)
            seite.click("#tab-chat")
            seite.wait_for_timeout(400)
            a = seite.inner_text(".cc-uhr")
            seite.wait_for_timeout(1600)
            assert seite.inner_text(".cc-uhr") == a, "die Uhr laeuft im Chat weiter"

            vorher = len([u for u in gerufen if "/api/events" in u])
            seite.click("#tab-cc")
            seite.wait_for_timeout(700)
            nachher = len([u for u in gerufen if "/api/events" in u])
            assert nachher == vorher + 1, "der Strom wird beim Zurueckkommen nicht neu geoeffnet"
        finally:
            br.close()


def test_ohne_js_fehler(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        fehler = []
        try:
            _oeffne(seite, server, None, fehler)
            for tab in ("#tab-chat", "#tab-tasks", "#tab-tools", "#tab-kosten", "#tab-cc"):
                seite.click(tab)
                seite.wait_for_timeout(300)
            assert fehler == [], fehler
        finally:
            br.close()
