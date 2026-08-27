"""FIX-06 Abschnitt 5: eine Palette, in beiden Seiten und im Globus.

Die vier DoD-Kriterien aus dem Auftrag, plus die zwei Fallen, die beim
Bauen aufgefallen sind:

* Ein `.globus-wurzel{--akzent:...}` haette den von `:root` geerbten Wert
  verdraengt - ohne Spezifitaetsstreit, einfach weil eine Deklaration AUF
  dem Element gewinnt. Die App waere umgefaerbt worden und der Globus
  blau geblieben.
* `web-selfcheck` misst den Fokusring als "vorhanden", sobald ein Element
  IRGENDEINEN Rahmen oder Schatten hat - auch im Ruhezustand. Hier wird
  deshalb die Umrandung selbst gemessen, samt Farbe.
"""

from __future__ import annotations

import re
import socket
import threading
import time
from pathlib import Path

import pytest

WURZEL = Path(__file__).resolve().parent.parent
AKZENT = "#f0b45c"
AKZENT_RGB = (240, 180, 92)

playwright = pytest.importorskip("playwright.sync_api")
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"


# --- Ohne Browser -----------------------------------------------------------


def test_dod_1_kein_blau_mehr_im_projekt():
    """Der Befehl aus dem Auftrag, als Test. Auch Kommentare zaehlen: ein
    Kommentar, der den Waechter rot macht, ist eine Falle."""
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "weltlage.html",
                 *sorted((WURZEL / "static").glob("*.css")),
                 *sorted((WURZEL / "static").glob("*.js"))):
        for nr, zeile in enumerate(pfad.read_text(encoding="utf-8").splitlines(), 1):
            if re.search("4da3ff", zeile, re.I):
                treffer.append(f"{pfad.name}:{nr}: {zeile.strip()[:80]}")
    assert treffer == [], "altes Blau gefunden:\n" + "\n".join(treffer)


def test_beide_seiten_binden_dieselbe_palette_ein():
    for name in ("index.html", "weltlage.html"):
        text = (WURZEL / name).read_text(encoding="utf-8")
        assert '<link rel="stylesheet" href="/static/system.css">' in text, name
    assert (WURZEL / "static" / "system.css").is_file()


def test_der_globus_deklariert_keine_eigene_palette():
    """Die Falle, an der der ganze Abschnitt haengen wuerde.

    `.globus-wurzel{--akzent:...}` wuerde den geerbten Wert aus system.css
    verdraengen - nicht wegen Spezifitaet, sondern weil `:root` (html) und
    `.globus-wurzel` (ein div) verschiedene Elemente sind. Der Globus bliebe
    dann fuer immer bei seiner eigenen Farbe, egal was system.css sagt.
    """
    text = (WURZEL / "static" / "globus.js").read_text(encoding="utf-8")
    stil = text[text.index("const STIL = `"):text.index("const MARKUP = `")]
    eigene = re.findall(r"^\s*(--[a-z0-9-]+)\s*:", stil, re.M)
    assert eigene == [], f"globus.js deklariert eigene Variablen: {eigene}"
    # Und er benutzt sie trotzdem - sonst waere der Test wertlos.
    assert "var(--akzent)" in stil


def test_kein_backtick_in_den_eingebetteten_bloecken():
    """Die Falle, die den Globus schon zweimal still zerlegt hat.

    `STIL` und `MARKUP` in globus.js sind Template-Zeichenketten. Ein
    Backtick in einem CSS- oder HTML-Kommentar darin schliesst die
    Zeichenkette mittendrin. Das Tueckische: `node --check` meldet nichts,
    weil der Rest zufaellig wieder als gueltiger Ausdruck durchgeht - die
    Seite laedt dann einfach nicht mehr fertig.
    """
    text = (WURZEL / "static" / "globus.js").read_text(encoding="utf-8")
    for name, ende in (("STIL", "const MARKUP = `"), ("MARKUP", "/* Modulweiter")):
        a = text.index(f"const {name} = `") + len(f"const {name} = `")
        b = text.index(ende, a)
        block = text[a:b].rsplit("`;", 1)[0]
        assert "`" not in block, f"Backtick im {name}-Block"
        assert "${" not in block, f"Interpolation im {name}-Block"


def test_die_palette_steht_nur_einmal():
    """Kein zweiter :root-Block mit Farbwerten in den Seiten."""
    for name in ("index.html", "weltlage.html"):
        text = (WURZEL / name).read_text(encoding="utf-8")
        for block in re.findall(r":root\s*\{([^}]*)\}", text):
            werte = re.findall(r"--[a-z0-9-]+\s*:\s*(#[0-9a-fA-F]{3,8})", block)
            assert werte == [], f"{name} setzt eigene Farbwerte: {werte}"


# --- Mit Browser ------------------------------------------------------------


@pytest.fixture
def server(tmp_path):
    import uvicorn

    from api.app import create_app
    from core.config import Settings

    with socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]
    st = Settings(_env_file=None, db_path=tmp_path / "ds.db", jarvis_token="ds")
    srv = uvicorn.Server(uvicorn.Config(create_app(st), host="127.0.0.1",
                                        port=port, log_level="warning"))
    faden = threading.Thread(target=srv.run, daemon=True)
    faden.start()
    frist = time.monotonic() + 20
    while not srv.started and time.monotonic() < frist:
        time.sleep(0.05)
    assert srv.started
    try:
        yield f"http://127.0.0.1:{port}"
    finally:
        srv.should_exit = True
        faden.join(timeout=10)


def _browser(pw, **kw):
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    return br, br.new_page(viewport={"width": 1440, "height": 900}, **kw)


RINGE_JS = """(n) => {
  const ringe = [];
  const gesehen = new Set();
  for (let i = 0; i < n; i++) {
    const el = document.activeElement;
    if (!el || el === document.body) break;
    const kennung = el.tagName + '#' + (el.id || '') + '.' + (el.className || '');
    if (gesehen.has(kennung)) break;
    gesehen.add(kennung);
    const cs = getComputedStyle(el);
    ringe.push({
      el: kennung.slice(0, 60),
      stil: cs.outlineStyle,
      breite: parseFloat(cs.outlineWidth) || 0,
      farbe: cs.outlineColor,
    });
  }
  return ringe;
}"""


@pytest.mark.parametrize("route", ["/", "/weltlage"])
def test_dod_3_jedes_bedienbare_element_zeigt_einen_ring_im_akzent(server, route):
    """`web-selfcheck` sagt hier zu schnell ja: es zaehlt JEDEN Rahmen und
    JEDEN Schatten als Fokusring, auch einen, den das Element im Ruhezustand
    ohnehin traegt. Hier wird die Umrandung selbst gemessen - Breite, Stil
    und Farbe."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            seite.goto(server + route, wait_until="networkidle")
            seite.wait_for_timeout(800)
            ringe = []
            for _ in range(20):
                seite.keyboard.press("Tab")
                r = seite.evaluate("""() => {
                  const el = document.activeElement;
                  if (!el || el === document.body) return null;
                  const cs = getComputedStyle(el);
                  return {
                    el: el.tagName + (el.id ? '#' + el.id : ''),
                    stil: cs.outlineStyle,
                    breite: parseFloat(cs.outlineWidth) || 0,
                    farbe: cs.outlineColor,
                  };
                }""")
                if r is None:
                    break
                if any(x["el"] == r["el"] for x in ringe):
                    break
                ringe.append(r)

            assert len(ringe) >= 3, f"nur {len(ringe)} Elemente erreichbar: {ringe}"
            ohne = [r for r in ringe
                    if r["stil"] == "none" or r["breite"] <= 0]
            assert ohne == [], f"ohne sichtbaren Ring: {ohne}"
            falsch = [r for r in ringe
                      if r["farbe"].replace(" ", "")
                      != "rgb(%d,%d,%d)" % AKZENT_RGB]
            assert falsch == [], f"Ring nicht in --akzent: {falsch}"
        finally:
            br.close()


def test_dod_4_bei_reduzierter_bewegung_laeuft_nichts(server):
    """Gezaehlt wird, was `prefers-reduced-motion` ueberlebt: eine Animation
    mit unendlicher Wiederholung und messbarer Dauer."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, reduced_motion="reduce")
        try:
            seite.goto(server + "/", wait_until="networkidle")
            seite.wait_for_timeout(1200)
            laeuft = seite.evaluate("""() => {
              const out = [];
              for (const el of document.querySelectorAll('body *')) {
                const cs = getComputedStyle(el);
                const dauer = (cs.animationDuration || '').split(',')
                  .map(v => parseFloat(v) || 0);
                const endlos = (cs.animationIterationCount || '').split(',')
                  .some(v => v.trim() === 'infinite');
                if (endlos && dauer.some(d => d > 0.05)) {
                  out.push(el.tagName + (el.id ? '#' + el.id : '') +
                           ' ' + cs.animationName + ' ' + cs.animationDuration);
                }
              }
              return out;
            }""")
            assert laeuft == [], f"laeuft trotz reduzierter Bewegung: {laeuft}"
        finally:
            br.close()


def test_die_akzentfarbe_erreicht_wirklich_die_dreidimensionale_szene(server):
    """Three.js liest kein CSS. Die Farben werden deshalb zur Laufzeit aus
    den Custom Properties gelesen - dieser Test prueft, dass dabei wirklich
    Bernstein und nicht mehr Blau in der Szene landet.

    Gemessen wird die Instanzfarbe der ausgewaehlten Landesmarke: warm heisst
    rot > gruen > blau, das alte Blau war genau andersherum.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, reduced_motion="reduce")
        fehler = []
        try:
            # Nur die eine Meldung, auf die es hier ankommt: `farbe()`
            # schreibt sie, wenn eine Custom Property leer ankommt - also
            # wenn system.css nicht geladen hat. Alles andere in dieser
            # Umgebung sind Folgen des fehlenden Modellanbieters (502) und
            # gehoert nicht zu diesem Test.
            seite.on("console", lambda m: fehler.append(m.text)
                     if m.type == "error" and "globus.js:" in m.text else None)
            seite.goto(server + "/weltlage", wait_until="networkidle")
            seite.wait_for_function("() => document.body.dataset.laender",
                                    timeout=40000)
            wurzel_akzent = seite.evaluate(
                "() => getComputedStyle(document.querySelector('.globus-wurzel'))"
                ".getPropertyValue('--akzent').trim()")
            assert wurzel_akzent == AKZENT, wurzel_akzent

            seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => l.iso === 'FRA');
              window.zustand.waehle(i);
            }""")
            seite.wait_for_timeout(400)
            rgb = seite.evaluate("""() => {
              const i = window.zustand.laender.findIndex(l => l.iso === 'FRA');
              const a = window.zustand.marken.instanceColor.array;
              return [a[i*3], a[i*3+1], a[i*3+2]];
            }""")
            r, g, b = rgb
            assert r > g > b, f"nicht warm: {rgb}"
            assert fehler == [], fehler
        finally:
            br.close()
