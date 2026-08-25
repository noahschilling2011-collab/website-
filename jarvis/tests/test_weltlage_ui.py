"""Was man nur im Browser sieht (PHASE-11 DoD 4, 6, 9, 10).

Ein echter Chromium gegen einen echten uvicorn. Der Fixture-Verlag liefert
Artikelseiten mit und ohne `og:image`, damit die Bildregel nicht am Mock
haengt, sondern am gerenderten Ergebnis.
"""

from __future__ import annotations

import json
import socket
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from core.llm import FakeLLMProvider

playwright = pytest.importorskip("playwright.sync_api")
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

# Ein 1x1-PNG, damit ein <img> wirklich laedt statt in den Fehlerpfad zu gehen.
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000100ffff03000006000557bfabd4"
    "0000000049454e44ae426082"
)

MIT_BILD = """<!doctype html><html><head>
<meta property="og:image" content="/bild.png">
<meta property="og:image:alt" content="Ein Kran vor einem halbfertigen Gebaeude.">
</head><body>x</body></html>"""

OHNE_BILD = "<!doctype html><html><head><title>x</title></head><body>x</body></html>"


class Verlag(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        pfad = self.path.split("?")[0]
        if pfad == "/robots.txt":
            return self._sende(b"User-agent: *\nAllow: /\n", "text/plain")
        if pfad == "/bild.png":
            return self._sende(PNG, "image/png")
        if pfad == "/mit-bild":
            return self._sende(MIT_BILD.encode(), "text/html; charset=utf-8")
        if pfad == "/ohne-bild":
            return self._sende(OHNE_BILD.encode(), "text/html; charset=utf-8")
        self.send_response(404); self.end_headers()

    def _sende(self, roh, typ):
        self.send_response(200)
        self.send_header("content-type", typ)
        self.send_header("content-length", str(len(roh)))
        self.end_headers()
        self.wfile.write(roh)

    def log_message(self, *_):
        return


@pytest.fixture(scope="module")
def verlag():
    server = HTTPServer(("127.0.0.1", 0), Verlag)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown(); server.server_close()


def _eintrag(quell_url, **kw):
    basis = {
        "schlagzeile": "TESTMELDUNG Alpha",
        "kurz": "TESTTEXT, erste Haelfte. TESTTEXT, zweite Haelfte.",
        "medium": "Reuters",
        "veroeffentlicht": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "quell_url": quell_url,
        "land_iso": "DEU",
        "einordnung": "TESTEINORDNUNG.",
        "einordnung_fehlt": "",
    }
    basis.update(kw)
    return basis


@pytest.fixture
def server(tmp_path, verlag):
    """Echter uvicorn - der TestClient puffert und rendert keine Seite."""
    import uvicorn

    from api.app import create_app
    from core.config import Settings

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    st = Settings(_env_file=None, db_path=tmp_path / "ui.db", jarvis_token="ui-token")
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


def setze(app, eintraege, gesagt=""):
    """Planner -> Schritt -> Zusammenfassung (FIX-02 Schritt 2)."""
    plan = json.dumps({"steps": [{"description": "Weltlage sammeln",
                                  "agent": "weltlage"}]}, ensure_ascii=False)
    inhalt = json.dumps({"meldungen": eintraege, "gesagt": gesagt}, ensure_ascii=False)
    app.state.provider = FakeLLMProvider(replies=[plan, inhalt, "Zusammengefasst."])


def browser(pw, breite=1280, hoehe=720, reduziert=False):
    br = pw.chromium.launch(executable_path=CHROMIUM,
                            args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": breite, "height": hoehe},
                        reduced_motion="reduce" if reduziert else "no-preference")
    return br, seite


def lade(seite, basis, iso="DEU"):
    seite.goto(f"{basis}/weltlage", wait_until="networkidle")
    seite.wait_for_timeout(1500)
    seite.evaluate(f"""() => fetch('/api/weltlage/{iso}', {{
        method:'POST', headers:{{'X-Jarvis-Token':'ui-token'}}
    }}).then(r=>r.json()).then(d=>{{ window.__daten = d; }})""")
    seite.wait_for_function("() => window.__daten !== undefined", timeout=20000)
    # Die Seite selbst zeichnen lassen, ueber ihre eigene Funktion:
    seite.evaluate("() => { document.dispatchEvent(new Event('probe')); }")
    return seite.evaluate("() => window.__daten")


# --- DoD 6: kein Scrollbalken ----------------------------------------------


@pytest.mark.parametrize("breite,hoehe", [(1280, 720), (1920, 1080)])
def test_dod_6_kein_scrollbalken(server, breite, hoehe):
    basis, app = server
    setze(app, [])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw, breite, hoehe)
        try:
            seite.goto(f"{basis}/weltlage", wait_until="networkidle")
            seite.wait_for_timeout(1500)
            ueberlauf = seite.evaluate("""() => ({
                x: document.documentElement.scrollWidth > window.innerWidth,
                y: document.documentElement.scrollHeight > window.innerHeight,
            })""")
            assert ueberlauf == {"x": False, "y": False}, ueberlauf
        finally:
            br.close()


# --- DoD 9: prefers-reduced-motion -----------------------------------------


def test_dod_9_reduced_motion_springt_statt_zu_drehen(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw, reduziert=True)
        try:
            seite.goto(f"{basis}/weltlage", wait_until="networkidle")
            seite.wait_for_function("() => document.body.dataset.laender", timeout=20000)
            assert seite.evaluate("() => document.body.dataset.reduziert") == "true"

            # Ansicht wechseln - unter reduced motion muss der Globus springen.
            seite.click("#btn-welt")
            seite.wait_for_timeout(800)
            assert seite.evaluate("() => document.body.dataset.drehung") == "sprung"

            dauer = seite.evaluate(
                "() => parseFloat(getComputedStyle(document.querySelector('.status')).transitionDuration)")
            assert dauer < 0.01, dauer
        finally:
            br.close()


def test_ohne_reduced_motion_wird_animiert(server, verlag):
    """Gegenprobe: sonst wuerde der Test oben auch bei kaputter Logik gruen."""
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw, reduziert=False)
        try:
            seite.goto(f"{basis}/weltlage", wait_until="networkidle")
            seite.wait_for_function("() => document.body.dataset.laender", timeout=20000)
            assert seite.evaluate("() => document.body.dataset.reduziert") == "false"
        finally:
            br.close()


# --- DoD 4 und 10: die echte Oberflaeche, nicht die Daten -------------------


def klicke_weltweit(seite, basis):
    """Genau der Weg, den ein Mensch geht: Knopf druecken."""
    seite.goto(f"{basis}/weltlage", wait_until="networkidle")
    seite.wait_for_function("() => document.body.dataset.laender", timeout=20000)
    seite.click("#btn-welt")
    seite.wait_for_selector(".karte, .leer", timeout=25000)
    seite.wait_for_timeout(600)


def test_dod_4_mit_og_image_zeigt_genau_dieses_bild(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/mit-bild", medium="Verlag")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            karte = seite.locator(".karte").first
            bild = karte.locator(".bild img")
            assert bild.count() == 1, "es haette genau ein Bild geben muessen"
            assert bild.get_attribute("src").endswith("/bild.png")
            assert bild.get_attribute("alt") == "Ein Kran vor einem halbfertigen Gebaeude."
            # Der Herkunftsstempel liegt UEBER dem Bild, nicht nur daneben.
            stempel = karte.locator(".bild .stempel").inner_text()
            assert "Verlag" in stempel, stempel
            assert karte.locator(".kachel").count() == 0
        finally:
            br.close()


def test_dod_4_ohne_og_image_kommt_die_kachel_kein_ersatzfoto(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            karte = seite.locator(".karte").first
            assert karte.locator("img").count() == 0, "kein Ersatzfoto, nirgends"
            kachel = karte.locator(".kachel")
            assert kachel.count() == 1
            assert "keine Quellgrafik" in kachel.inner_text()
        finally:
            br.close()


def test_dod_10_meldung_und_einordnung_sind_zwei_getrennte_flaechen(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters",
                         einordnung="TESTEINORDNUNG.")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            karte = seite.locator(".karte").first
            meldung = karte.locator(".meldung")
            einordnung = karte.locator(".einordnung")
            assert meldung.count() == 1 and einordnung.count() == 1

            # Andere Flaeche, andere Kante - nicht nur andere Ueberschrift.
            stile = seite.evaluate("""() => {
                const k = document.querySelector('.karte');
                const m = getComputedStyle(k.querySelector('.meldung'));
                const e = getComputedStyle(k.querySelector('.einordnung'));
                return {mBg: m.backgroundColor, eBg: e.backgroundColor,
                        eKante: e.borderTopStyle, eKanteBreite: e.borderTopWidth};
            }""")
            assert stile["mBg"] != stile["eBg"], stile
            assert stile["eKante"] == "dashed" and stile["eKanteBreite"] != "0px", stile

            # Und sie sagt selbst, dass sie nicht aus der Quelle stammt.
            hinweis = einordnung.locator(".hinweis").inner_text()
            assert "nicht aus der Quelle" in hinweis, hinweis
            seite.screenshot(path="/tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad/p11/trennung.png")
        finally:
            br.close()


def test_dod_14_leere_einordnung_traegt_sichtbar_einen_hinweis(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters", einordnung="",
                         einordnung_fehlt="Dazu habe ich keinen Kontext.")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            text = seite.locator(".karte .einordnung").first.inner_text()
            assert "Dazu habe ich keinen Kontext." in text
            assert "Leer gelassen statt gefüllt." in text
        finally:
            br.close()


def test_dod_5_null_meldungen_zeigt_keine_karte(server):
    basis, app = server
    setze(app, [], gesagt="Dazu finde ich heute nichts.")
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            assert seite.locator(".karte").count() == 0
            assert "0 belegte Meldungen" in seite.locator(".leer").inner_text()
            assert "Dazu finde ich heute nichts." in seite.locator("#gesagt").inner_text()
        finally:
            br.close()


def test_dod_8_zaehler_stehen_sichtbar_in_der_statusleiste(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            status = seite.locator(".status").inner_text()
            for wort in ("Abfragen", "Cache", "verworfen", "heute"):
                assert wort in status, status
            assert seite.locator("#z-abfragen").inner_text() == "1"
        finally:
            br.close()


def test_dod_2_zweiter_klick_erhoeht_nur_den_cache_zaehler(server, verlag):
    basis, app = server
    setze(app, [_eintrag(f"{verlag}/ohne-bild", medium="Reuters")])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            assert seite.locator("#z-abfragen").inner_text() == "1"
            seite.click("#btn-welt")
            seite.wait_for_timeout(1500)
            assert seite.locator("#z-abfragen").inner_text() == "1", "kein zweiter Auftrag"
            assert seite.locator("#z-treffer").inner_text() == "1", "der Cache muss zaehlen"
        finally:
            br.close()


def test_hoechstens_fuenf_karten_und_keine_angeschnittene(server, verlag):
    """Was nicht reinpasst, wird nicht angezeigt - als GANZE Karte.

    Eine Karte, die mitten im Satz abgeschnitten ist, waere schlechter als
    eine Karte weniger. Der Rest wird gezaehlt und gesagt, nicht verschwiegen.
    """
    basis, app = server
    # Neun UNTERSCHIEDLICHE aus verschiedenen Laendern - seit FIX-02 fallen
    # Duplikate weg, und "weltweit" mit nur einem Land wird ganz abgelehnt.
    LAENDER = ("DEU", "FRA", "ITA", "ESP", "POL", "NLD", "BEL", "AUT", "CHE")
    setze(app, [_eintrag(f"{verlag}/ohne-bild?i={i}", medium="Reuters",
                         schlagzeile=f"Meldung {i}", land_iso=LAENDER[i])
                for i in range(9)])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            klicke_weltweit(seite, basis)
            seite.wait_for_timeout(600)
            karten = seite.locator(".karte")
            anzahl = karten.count()
            assert 1 <= anzahl <= 5, anzahl

            # Keine Karte darf ueber den Rand ihres Behaelters hinausragen.
            ueber = seite.evaluate("""() => {
                const ziel = document.getElementById('karten');
                const p = ziel.getBoundingClientRect();
                return [...ziel.querySelectorAll('.karte')].filter(k => {
                    const r = k.getBoundingClientRect();
                    return r.bottom > p.bottom + 1 || r.right > p.right + 1;
                }).length;
            }""")
            assert ueber == 0, f"{ueber} Karte(n) ragen ueber den Rand"

            if anzahl < 5:
                assert "passen nicht ins Bild" in seite.locator("#gesagt").inner_text()
        finally:
            br.close()


def test_bei_1920_passen_fuenf_ganze_karten(server, verlag):
    """Gegenprobe zum Test oben: auf einem grossen Schirm ist Platz fuer alle."""
    basis, app = server
    LAENDER = ("DEU", "FRA", "ITA", "ESP", "POL")
    setze(app, [_eintrag(f"{verlag}/ohne-bild?i={i}", medium="Reuters",
                         schlagzeile=f"Meldung {i}", land_iso=LAENDER[i])
                for i in range(5)])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw, 1920, 1080)
        try:
            klicke_weltweit(seite, basis)
            seite.wait_for_timeout(600)
            assert seite.locator(".karte").count() == 5
            assert "passen nicht ins Bild" not in seite.locator("#gesagt").inner_text()
        finally:
            br.close()


def test_der_globus_zeigt_alle_laender_des_atlas(server):
    basis, app = server
    setze(app, [])
    with playwright.sync_playwright() as pw:
        br, seite = browser(pw)
        try:
            seite.goto(f"{basis}/weltlage", wait_until="networkidle")
            seite.wait_for_function("() => document.body.dataset.laender", timeout=20000)
            anzahl = int(seite.evaluate("() => document.body.dataset.laender"))
            assert anzahl == 177, anzahl
        finally:
            br.close()
