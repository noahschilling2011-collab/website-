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


def test_kein_undefiniertes_custom_property():
    """Ein `var(--gibt-es-nicht)` faellt still auf den Anfangswert zurueck.

    Gefunden in FIX-06 Abschnitt 7 beim Gegenlesen: `--dauer-normal` stand in
    `index.html:521` am Fortschrittsbalken des COMMAND CENTER und ist NIRGENDS
    definiert. Die ganze `transition` war damit ungueltig, und der Balken
    sprang hart - ausgerechnet in der Zone, die Fortschritt zeigen soll.

    Kein Fehler im Browser, keine Warnung, kein roter Test. Genau deshalb
    dieser hier.
    """
    quellen = [WURZEL / "index.html", WURZEL / "weltlage.html",
               *sorted((WURZEL / "static").glob("*.css")),
               *sorted((WURZEL / "static").glob("*.js"))]
    # `vendor/` bleibt draussen: fremder Code, nicht unsere Palette.
    definiert: set[str] = set()
    benutzt: dict[str, str] = {}
    for pfad in quellen:
        text = pfad.read_text(encoding="utf-8")
        definiert |= set(re.findall(r"(--[a-z0-9-]+)\s*:", text))
        # Blockkommentare raus, aber ZEILENWEISE ersetzt statt geloescht,
        # damit die Zeilennummern stimmen. Ohne das schlaegt der Test bei
        # `index.html:830` an - dort steht in einem Kommentar, dass es
        # `--dim` NICHT gibt. Ein Test, der ueber die Erklaerung stolpert,
        # warum etwas fehlt, ist eine Falle.
        ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                      text, flags=re.DOTALL)
        for nr, zeile in enumerate(ohne.splitlines(), 1):
            for name in re.findall(r"var\(\s*(--[a-z0-9-]+)", zeile):
                benutzt.setdefault(name, f"{pfad.name}:{nr}")

    fehlt = sorted(n for n in benutzt if n not in definiert)
    assert fehlt == [], "benutzt, aber nirgends definiert:\n" + "\n".join(
        f"  {n}  ({benutzt[n]})" for n in fehlt)


def test_nur_die_eine_akzentfarbe_und_die_zwei_signalfarben():
    """Drei Fremdfarben, die keiner Palette angehoeren - gefunden beim
    Abgleich mit Noahs Bewegtbild-Vorlage.

    `rgb(242,181,68)` liegt um 2/1/24 neben `--akzent #f0b45c` und ist
    nirgends definiert: ein vierter Bernstein, den niemand gewaehlt hat.
    `rgb(86,132,214)` ist genau das zweite Blau, das der Kopfkommentar von
    `static/system.css` fuer abgeschafft erklaert - der Waechter suchte
    bisher nur nach `4da3ff` und hat es durchgelassen.
    `#ffb9b4` ist ein zweites Rot neben `--ab #f6836f`.
    """
    verboten = {
        r"242,\s*181,\s*68": "vierter Bernstein statt --akzent",
        r"86,\s*132,\s*214": "zweites Blau - system.css erklaert es fuer abgeschafft",
        r"ffb9b4": "zweites Rot statt --ab",
    }
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "weltlage.html",
                 *sorted((WURZEL / "static").glob("*.css")),
                 *sorted((WURZEL / "static").glob("*.js"))):
        for nr, zeile in enumerate(pfad.read_text(encoding="utf-8").splitlines(), 1):
            for muster, grund in verboten.items():
                if re.search(muster, zeile, re.I):
                    treffer.append(f"{pfad.name}:{nr}: {grund} -> {zeile.strip()[:70]}")
    assert treffer == [], "Fremdfarbe gefunden:\n" + "\n".join(treffer)


def test_nur_die_vier_dauern_aus_dem_design_system():
    """Vier Zeiten, nicht neun.

    `static/system.css` legt sie fest: 140 ms Hover/Fokus/Farbe, 380 ms
    erscheinen, 220 ms verschwinden, 600 ms Zahl zaehlt hoch. Daneben standen
    im Projekt neun handgeschriebene `200ms`, ein `300ms` und fuenf
    verschiedene Erscheinungsdauern (320/300/300/380/280 ms) - gefunden beim
    Abgleich mit Noahs Bewegtbild-Vorlage.

    Der Test verbietet nicht jede Zahl: Endlospulse haben bewusst eigene
    Perioden (2,4 s / 1,1 s), und die sind hier ausgenommen. Verboten sind
    Zeiten in `transition` und in einmaligen `animation`-Deklarationen -
    genau dort, wo ein Token stehen muesste.
    """
    # NUR die Kurzformen `transition:` und `animation:`. Nicht
    # `animation-delay` - die 45-ms-Staffelung in system.css IST die Regel,
    # kein Verstoss gegen sie. Und nicht `!important`, das sind die
    # Barrierefreiheits- und Druck-Ueberschreibungen.
    # Auch die Langformen `transition-duration` und `animation-duration`.
    # Ohne sie rutschte `#view-cc.is-active { animation-duration: 1000ms }`
    # durch - eine fuenfte Dauer, die der Test uebersehen hat. NICHT
    # `-delay`: die 45-ms-Staffelung IST die Regel.
    verdaechtig = re.compile(
        r"(?:transition|animation)(?:-duration)?\s*:[^;{}]*?(\d+(?:\.\d+)?m?s)\b",
        re.IGNORECASE)
    erlaubt_endlos = re.compile(r"infinite|!important")
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "weltlage.html",
                 *sorted((WURZEL / "static").glob("*.css")),
                 *sorted((WURZEL / "static").glob("*.js"))):
        text = pfad.read_text(encoding="utf-8")
        ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                      text, flags=re.DOTALL)
        for nr, zeile in enumerate(ohne.splitlines(), 1):
            if erlaubt_endlos.search(zeile):
                continue
            for wert in verdaechtig.findall(zeile):
                treffer.append(f"{pfad.name}:{nr}: {wert} statt eines Tokens"
                               f" -> {zeile.strip()[:64]}")
    assert treffer == [], ("harte Zeit statt --dauer-*:\n" + "\n".join(treffer))


def test_es_gibt_genau_ein_glasrezept():
    """Ein `backdrop-filter` ausserhalb von `.glas` ist ein zweites Glas.

    Gefunden beim Abgleich mit Noahs Bewegtbild-Vorlage: `static/globus.js`
    hatte zwei eigene Rezepte neben dem der `.glas`-Klasse -
    `blur(18px) saturate(140%)` fuer die Karten und `blur(14px)` ganz ohne
    `saturate` fuer das Ortpanel, dessen Flaeche mit `rgba(14,18,26,.82)`
    nicht einmal aus der Palette kam. Die Vorlage sagt dasselbe wie
    `static/system.css`: 20px und 150%.

    Der Test verbietet `backdrop-filter` nicht - er verlangt, dass es nur an
    einer Stelle im Projekt steht. Wer ein zweites Glas braucht, gibt ihm
    einen Namen in `static/system.css`, statt es irgendwo hinzuschreiben.

    Ausgenommen ist `backdrop-filter: none` - das SCHALTET Glas ab und ist
    genau das, was die Barrierefreiheits- und Druckregeln tun muessen.
    """
    muster = re.compile(r"(?:-webkit-)?backdrop-filter\s*:\s*([^;{}]+)")
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "weltlage.html",
                 *sorted((WURZEL / "static").glob("*.css")),
                 *sorted((WURZEL / "static").glob("*.js"))):
        text = pfad.read_text(encoding="utf-8")
        ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                      text, flags=re.DOTALL)
        for nr, zeile in enumerate(ohne.splitlines(), 1):
            # `@supports not (backdrop-filter: blur(1px))` fragt nach der
            # Faehigkeit, es erklaert kein Glas.
            if "@supports" in zeile:
                continue
            for wert in muster.findall(zeile):
                w = wert.strip().rstrip("!important").strip()
                if w == "none":
                    continue
                treffer.append((pfad.name, nr, w))
    rezepte = sorted({w for _, _, w in treffer})
    assert rezepte == ["blur(20px) saturate(150%)"], (
        "mehr als ein Glasrezept:\n"
        + "\n".join(f"{d}:{n}: {w}" for d, n, w in treffer))


def test_die_dauer_token_haben_auch_benutzer():
    """Ein Token ohne Nutzer ist kein Design-System, sondern eine Absichts-
    erklaerung. Vor dem Abgleich hatten `--dauer-tupf`, `--dauer-raus` und
    `--dauer-zahl` null Treffer im ganzen Projekt."""
    text = "".join(
        pfad.read_text(encoding="utf-8")
        for pfad in (WURZEL / "index.html", WURZEL / "weltlage.html",
                     *sorted((WURZEL / "static").glob("*.css")),
                     *sorted((WURZEL / "static").glob("*.js")))
    )
    ohne_leer = []
    for token in ("--dauer-tupf", "--dauer-rein", "--dauer-raus", "--dauer-zahl"):
        if text.count(f"var({token})") == 0:
            ohne_leer.append(token)
    assert ohne_leer == [], f"definiert, aber nirgends benutzt: {ohne_leer}"


def test_hover_bewegt_nichts():
    """Die Vorlage sagt woertlich: nur Flaeche und Textfarbe, kein Versatz,
    kein Skalieren. `.btn-send:hover` war der einzige Verstoss."""
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "static" / "globus.js"):
        text = pfad.read_text(encoding="utf-8")
        ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                      text, flags=re.DOTALL)
        for nr, zeile in enumerate(ohne.splitlines(), 1):
            if ":hover" in zeile and re.search(r"transform\s*:", zeile):
                treffer.append(f"{pfad.name}:{nr}: {zeile.strip()[:70]}")
    assert treffer == [], "Hover verschiebt etwas:\n" + "\n".join(treffer)


def test_endlosanimationen_malen_nicht_neu():
    """Eine Endlosanimation auf `box-shadow` malt in jedem Bild neu.
    `transform` und `opacity` laufen auf dem Compositor. Bei etwas, das
    dauerhaft laeuft, ist das der ganze Unterschied."""
    treffer = []
    for pfad in (WURZEL / "index.html", WURZEL / "static" / "globus.js",
                 WURZEL / "static" / "system.css"):
        text = pfad.read_text(encoding="utf-8")
        ohne = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)),
                      text, flags=re.DOTALL)
        # Welche Keyframes laufen endlos?
        endlos = set(re.findall(r"animation:\s*([\w-]+)[^;]*infinite", ohne))
        for name in endlos:
            block = re.search(r"@keyframes\s+" + re.escape(name) + r"\s*\{(.*?)\n\}",
                              ohne, re.DOTALL)
            if not block:
                continue
            for teuer in ("box-shadow", "width", "height", "top", "left", "filter"):
                if teuer + ":" in block.group(1).replace(" ", ""):
                    treffer.append(f"{pfad.name}: @keyframes {name} aendert {teuer}")
    assert treffer == [], "teure Endlosanimation:\n" + "\n".join(treffer)


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
            # `/` haelt seit FIX-06 Abschnitt 6 eine SSE-Verbindung offen -
            # "Netzwerk still" tritt dort nie ein.
            seite.goto(server + route, wait_until="domcontentloaded")
            seite.wait_for_timeout(1200)
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
            seite.goto(server + "/", wait_until="domcontentloaded")
            # Kein `networkidle`: die Startansicht haelt seit
            # FIX-06 Abschnitt 6 eine SSE-Verbindung offen.
            seite.wait_for_selector("#view-cc .cc")
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


# --- Verknuepfungspruefung 31.08.2026, Fund 3 -------------------------------
#
# Die Kommentare in static/globus.js und weltlage.html sind die einzige
# Dokumentation der Naht zwischen den beiden Seiten: warum der Token ein
# Parameter ist, warum alles unter .globus-wurzel haengt, welche zwei
# Klassennamen sich mit index.html ueberschneiden. Acht davon zeigten mit
# einer Zeilennummer ins Leere.
#
# Gemessen vor der Reparatur:
#   static/globus.js:12  nannte api/app.py:205 fuer den StaticFiles-Mount
#                        -> dort steht ein Absatz ueber Copernicus-Konten,
#                           app.mount("/static", ...) steht in Zeile 270
#   static/globus.js:13  nannte api/routes.py:515 und :533 fuer die Routen
#                        -> die stehen in 690 und 703
#   static/globus.js:25  nannte index.html:446 fuer .view
#                        -> .view steht in 503, 446 ist eine .brand-mark-Regel
#   static/globus.js:37  nannte index.html:450 und :129 fuer .karte/.status
#                        -> die stehen in 740 und 170
#   static/globus.js:179 nannte index.html:454-455 -> .karte steht in 740-746
#   static/globus.js:242 nannte index.html:130     -> .status steht in 170-171
#   weltlage.html:57/:59 wiederholten die beiden Backend-Nummern
#
# Eine Nummer verrutscht bei jeder Aenderung ueber ihr. Ein Symbolname nicht.
# Die zwei Tests hier halten beides fest.

# Nur die zwei Dateien der Naht - der Rest des Projekts ist nicht Gegenstand
# dieses Fundes und gehoert anderen.
_NAHT = ("static/globus.js", "weltlage.html")

# `pfad.endung:zahl`, mit oder ohne Bereich. Der Pfad muss eine Endung haben,
# damit "127.0.0.1:8000" und CSS-Pseudoklassen nicht hineinfallen.
_ZEILENVERWEIS = re.compile(
    r"[A-Za-z0-9_/.-]+\.(?:py|js|jsx|html|css|md|json|txt):\d+")


def test_die_naht_kommentiert_ohne_zeilennummern():
    """Fund 3. Ein Verweis auf eine Datei DIESES Projekts darf keine
    Zeilennummer tragen.

    Geprueft wird die Ursache und nicht die acht Einzelstellen: solange
    ueberhaupt eine Nummer dasteht, wandert sie bei der naechsten Aenderung
    darueber weg, ohne dass irgendetwas rot wird. Verweise auf Dateien, die
    es hier gar nicht gibt - die eingefrorene Vorlage jarvis-scene.jsx zum
    Beispiel - bleiben erlaubt: die aendert dieses Projekt nicht.
    """
    treffer = []
    for name in _NAHT:
        pfad = WURZEL / name
        for nr, zeile in enumerate(pfad.read_text(encoding="utf-8").splitlines(), 1):
            for verweis in _ZEILENVERWEIS.findall(zeile):
                datei = verweis.rsplit(":", 1)[0]
                if (WURZEL / datei).is_file():
                    treffer.append(f"{name}:{nr}: {verweis}")
    assert treffer == [], (
        "Zeilenverweis in einem Kommentar der Naht - nimm den Symbolnamen:\n"
        + "\n".join(treffer))


def test_die_symbole_aus_den_nahtkommentaren_gibt_es_wirklich():
    """Die zweite Haelfte: Namen statt Nummern nuetzt nur, wenn die Namen
    stimmen. Jede Behauptung der Kommentare wird hier nachgeschlagen.

    Der Ankertext ist absichtlich der, der auch im Kommentar steht - wer
    eine der Regeln umbenennt, macht diesen Test rot und findet ueber ihn
    die Kommentare, die dann nachzuziehen sind.
    """
    app_py = (WURZEL / "api" / "app.py").read_text(encoding="utf-8")
    routes_py = (WURZEL / "api" / "routes.py").read_text(encoding="utf-8")
    index = (WURZEL / "index.html").read_text(encoding="utf-8")
    globus = (WURZEL / "static" / "globus.js").read_text(encoding="utf-8")
    weltlage = (WURZEL / "weltlage.html").read_text(encoding="utf-8")

    # Der Mount, der /static roh ausliefert - der Grund, warum der Token ein
    # Parameter ist und nicht in globus.js steht.
    assert 'app.mount("/static"' in app_py
    assert 'app.mount("/static", ...)' in globus
    assert 'app.mount("/static", ...)' in weltlage

    # Die beiden HTML-Routen, die den Platzhalter ersetzen.
    for symbol in ("async def index(", "async def weltlage_seite("):
        assert symbol in routes_py, symbol
    assert "index() und weltlage_seite()" in globus
    assert "weltlage_seite()" in weltlage
    assert "__JARVIS_TOKEN__" in routes_py or "__JARVIS_TOKEN__" in app_py

    # Die drei Regeln aus index.html, auf die sich der Globus stuetzt - und
    # jeweils die Eigenschaft, die der Kommentar von ihnen behauptet.
    def regel(text, selektor):
        treffer = re.search(re.escape(selektor) + r"\s*\{([^}]*)\}", text)
        assert treffer, f"{selektor} gibt es in index.html nicht mehr"
        return treffer.group(1).replace(" ", "")

    assert "display:none" in regel(index, ".view"), \
        ".view blendet nicht mehr mit display:none um"
    karte = regel(index, ".karte")
    assert "padding:" in karte and "margin-bottom:" in karte, \
        ".karte hat keinen Innen- und Aussenabstand mehr"
    assert "margin-left:auto" in regel(index, ".status"), \
        ".status schiebt sich nicht mehr mit margin-left:auto"

    # Und der Globus haelt genau dagegen - sonst waere der Kommentar wahr
    # und der Code trotzdem falsch.
    assert "padding:0;margin-bottom:0;" in globus
    assert "margin-left:0;" in globus


def test_genau_zwei_klassennamen_ueberschneiden_sich_mit_index_html():
    """Die Behauptung im STIL-Block von globus.js, nachgerechnet statt
    erzaehlt: 'karte' und 'status' gibt es in index.html schon, und nur
    die zwei.

    Genau das ist der Grund, warum alles unter '.globus-wurzel' geschachtelt
    ist. Kommt ein dritter gemeinsamer Name dazu, faerbt der Globus wieder
    etwas im Chat um - und dieser Test sagt es, bevor es jemand sieht.
    """
    globus = (WURZEL / "static" / "globus.js").read_text(encoding="utf-8")
    stil = globus[globus.index("const STIL = `"):globus.index("const MARKUP = `")]
    index = (WURZEL / "index.html").read_text(encoding="utf-8")
    # Nur der <style>-Teil von index.html; im Skript stehen Klassennamen als
    # Zeichenketten, die hier nichts zu suchen haben.
    stil_index = "\n".join(re.findall(r"<style>(.*?)</style>", index, re.S))

    def klassen(text):
        # Kommentare raus, sonst zaehlen erklaerende Beispiele mit.
        ohne = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        return set(re.findall(r"\.([a-z][a-z0-9-]*)", ohne))

    globus_klassen = {k for k in klassen(stil) if k != "globus-wurzel"}
    gemeinsam = globus_klassen & klassen(stil_index)
    assert gemeinsam == {"karte", "status"}, (
        "die Ueberschneidung ist nicht mehr genau {'karte','status'}: "
        f"{sorted(gemeinsam)}")
