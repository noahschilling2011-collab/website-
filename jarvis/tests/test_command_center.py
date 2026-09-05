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
from tests.conftest import CHROMIUM  # eine Stelle, siehe dort


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


def _browser(pw, breite=1440, hoehe=900, bewegung="reduce"):
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": breite, "height": hoehe},
                        reduced_motion=bewegung)
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


# --- Der Reaktor: acht Zustaende, eine Rangfolge --------------------------


def test_der_reaktor_ist_adressierbar(server):
    """Acht einzelne Strahlen statt zweier Sammelpfade, plus Kern und Ring.

    In einem Sammelpfad ist kein einzelner Strahl ansprechbar - ohne die
    Aufteilung waeren die Zustaende nicht baubar.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            assert seite.eval_on_selector_all(".brand-mark .strahl", "l => l.length") == 8
            assert seite.eval_on_selector_all(".brand-mark .kern", "l => l.length") == 1
            assert seite.eval_on_selector_all(".brand-mark .reaktor-ring", "l => l.length") == 1
            # Ohne Auftrag ist Ruhe.
            assert seite.get_attribute(".brand-mark", "data-zustand") == "ruhe"
            # Und er sagt vorlesbar, was er zeigt.
            assert seite.get_attribute(".brand-mark", "role") == "img"
            assert seite.get_attribute(".brand-mark", "aria-label")
        finally:
            br.close()


def test_der_reaktor_zeigt_den_lauf_und_danach_das_ergebnis(server):
    """Vom Ruhezustand ueber "denkt" zum Ergebnis - am echten Auftrag
    gemessen, nicht am gesetzten Attribut."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw)
        try:
            _oeffne(seite, server)
            seite.click("#tab-chat")
            seite.wait_for_timeout(200)
            assert seite.get_attribute(".brand-mark", "data-zustand") == "ruhe"

            seite.fill("#input", "Wie spaet ist es?")
            seite.press("#input", "Enter")
            # Waehrend der Auftrag laeuft, ist es nicht mehr Ruhe.
            seite.wait_for_function(
                "() => document.querySelector('.brand-mark').dataset.zustand !== 'ruhe'",
                timeout=20000)
            unterwegs = seite.get_attribute(".brand-mark", "data-zustand")
            assert unterwegs in ("denkt", "werkzeug"), unterwegs

            # Und am Ende steht ein Ergebnis, kein Dauerlauf.
            seite.wait_for_function(
                "() => ['fertig','fehl','ruhe'].indexOf("
                "document.querySelector('.brand-mark').dataset.zustand) !== -1",
                timeout=40000)
        finally:
            br.close()


def test_der_reaktor_zeigt_immer_nur_eines(server):
    """Vorher konnten der laufende Schritt und das Mikrofon gleichzeitig
    pulsieren, mit zwei verschiedenen Perioden nebeneinander. Ein Symbol,
    das zwei Sachen gleichzeitig sagt, sagt keine."""
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, bewegung="no-preference")
        try:
            _oeffne(seite, server)
            for zustand in ("ruhe", "wartet", "denkt", "werkzeug",
                            "hoert", "spricht", "fehl", "fertig"):
                seite.evaluate(
                    "(z) => document.querySelector('.brand-mark').dataset.zustand = z",
                    zustand)
                seite.wait_for_timeout(80)
                laufend = seite.evaluate("""() => {
                  var n = 0;
                  document.querySelectorAll('.brand-mark svg *').forEach(function (e) {
                    if (getComputedStyle(e).animationName !== 'none') n++;
                  });
                  return n;
                }""")
                # Hoechstens EIN Element bewegt sich - ausser bei "fehl",
                # wo Kern und Strahlen denselben einmaligen Blitz zeigen.
                grenze = 9 if zustand == "fehl" else 1
                assert laufend <= grenze, (zustand, laufend)
        finally:
            br.close()


def test_bei_reduzierter_bewegung_steht_der_reaktor_still(server):
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, bewegung="reduce")
        try:
            _oeffne(seite, server)
            seite.evaluate(
                "() => document.querySelector('.brand-mark').dataset.zustand = 'denkt'")
            seite.wait_for_timeout(200)
            dauern = seite.eval_on_selector_all(
                ".brand-mark svg *",
                "l => l.map(e => getComputedStyle(e).animationDuration)")
            for d in dauern:
                assert float(d.replace("s", "")) < 0.01, dauern
        finally:
            br.close()


# ===========================================================================
# Verknuepfungspruefung 31.08.2026 - Gruppe frontend
#
# Sieben Funde, sieben Tests. Jeder prueft die URSACHE, nicht die
# Oberflaeche: ob die Fehlerbehandlung wirklich laeuft, nicht ob irgendwo
# ein Text steht.
# ===========================================================================

import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

WURZEL = Path(__file__).resolve().parent.parent


def _browser_roh(pw, **kw):
    """Wie _browser, aber die Seite kommt nackt zurueck - der Aufrufer haengt
    seine `route`-Regeln an, BEVOR die Seite geladen wird."""
    br = pw.chromium.launch(
        executable_path=CHROMIUM,
        args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    seite = br.new_page(viewport={"width": 1440, "height": 900},
                        reduced_motion="reduce", **kw)
    return br, seite


def _warte_auf_cc(seite, basis):
    seite.goto(basis + "/", wait_until="domcontentloaded")
    seite.wait_for_selector("#view-cc .cc", timeout=20000)


# --- Fund 1: Wiederverbindung ---------------------------------------------


def test_fund1_der_strom_verbindet_sich_wieder(server):
    """Der Ereignisstrom hatte keinen Weg zurueck.

    Reproduktion vor der Reparatur: /api/events liefert einen Strom, der
    sofort sauber endet. Gemessen wurden in 6 Sekunden GENAU EINE Anfrage an
    /api/events und eine einzige Protokollzeile ("hello") - das Command
    Center stand still und sagte kein Wort dazu.

    Geprueft wird die Ursache an drei Stellen:
    1. es wird ueberhaupt neu verbunden,
    2. der Nutzer erfaehrt davon,
    3. nach der Wiederverbindung werden die Zonen nachgezogen - die
       Ereignisse aus der Luecke liefert niemand nach.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        gerufen = []
        try:
            seite.on("request", lambda r: gerufen.append(r.url))
            # Ein Strom, der sich sofort wieder verabschiedet. Genau das
            # passiert bei einem Server-Neustart oder einem WLAN-Aussetzer.
            seite.route("**/api/events", lambda r: r.fulfill(
                status=200, content_type="text/event-stream",
                body='event: hello\ndata: {"listeners": 1}\n\n'))
            _warte_auf_cc(seite, basis=server)
            seite.wait_for_timeout(4500)

            stroeme = [u for u in gerufen if "/api/events" in u]
            assert len(stroeme) >= 3, stroeme

            zeilen = seite.eval_on_selector_all(
                "#view-cc .cc-strom div", "l => l.map(e => e.textContent)")
            assert any("wieder verbunden" in z for z in zeilen), zeilen

            # Zone 5 haengt an /api/stats. Wird nach der Wiederverbindung
            # nichts nachgezogen, stehen dort die Zahlen von vor der Luecke.
            stats = [u for u in gerufen if u.endswith("/api/stats")]
            assert len(stats) >= 2, stats
        finally:
            br.close()


# --- Fund 2 und 4: der Fehlerpfad von zeichne() ---------------------------


def _chat_mit_kaputtem_task_abruf(seite, basis):
    """POST /api/tasks geht durch, GET /api/tasks/{id} faellt aus.

    Das ist der Aussetzer aus Fund 2 und 4: ausgeloest von einem Ereignis,
    also mitten im Betrieb, nicht beim Abschicken.
    """
    def weiche(route, request):
        if request.method == "GET" and "/api/tasks/" in request.url:
            route.fulfill(status=500, content_type="application/json",
                          body='{"detail":"Datenbank weg"}')
        else:
            route.continue_()

    seite.route("**/api/tasks/**", weiche)
    _warte_auf_cc(seite, basis)
    seite.click("#tab-chat")
    seite.wait_for_timeout(300)
    seite.fill("#input", "Wie spaet ist es?")
    seite.press("#input", "Enter")
    seite.wait_for_selector("#thread .msg-error", timeout=20000, state="attached")
    seite.wait_for_timeout(600)


def test_fund2_ein_fehlgeschlagener_abruf_sperrt_die_eingabe_nicht(server):
    """Ein einziger fehlgeschlagener GET sperrte die Eingabe fuer immer.

    Reproduktion vor der Reparatur: nach dem 500er standen
    `#input.disabled` und `#btn-send.disabled` beide auf true und blieben
    es - `setBusy(false)` fehlte im catch, und `beenden()` machte die drei
    anderen Stellen mit `setBusy(false)` unerreichbar. Nur ein Neuladen der
    Seite half.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        try:
            _chat_mit_kaputtem_task_abruf(seite, server)
            assert seite.eval_on_selector("#input", "e => e.disabled") is False
            assert seite.eval_on_selector("#btn-send", "e => e.disabled") is False
            # Und die Fehlermeldung steht trotzdem da - sonst waere die
            # Eingabe nur deshalb frei, weil gar nichts passiert ist.
            assert seite.eval_on_selector_all("#thread .msg-error", "l => l.length") >= 1
            # Der Nutzer kann wirklich weitertippen, nicht nur theoretisch.
            seite.fill("#input", "noch etwas")
            assert seite.input_value("#input") == "noch etwas"
        finally:
            br.close()


def test_fund4_der_denk_platzhalter_verschwindet_bei_jedem_abbruch(server):
    """Der Denk-Platzhalter blieb nach einem Abbruch fuer immer stehen.

    Reproduktion vor der Reparatur: unter der Fehlerblase lag weiter genau
    ein `.typing`-Knoten mit aria-label "JARVIS denkt nach" und seiner
    dauerlaufenden Punkte-Animation. Die Oberflaeche behauptete zu arbeiten,
    waehrend sie eine Zeile darueber zugab, dass sie nichts mehr hoert.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        try:
            _chat_mit_kaputtem_task_abruf(seite, server)
            uebrig = seite.eval_on_selector_all(
                "#thread .typing",
                "l => l.map(e => e.getAttribute('aria-label'))")
            assert uebrig == [], uebrig
        finally:
            br.close()


# --- Fund 3: ccStromText kannte den eigenen Abbruchgrund nicht ------------


def _funktion_aus_index(name):
    """Eine Funktionsdeklaration aus index.html herausschneiden.

    Gezaehlt werden geschweifte Klammern - fuer die vier kurzen Funktionen
    hier reicht das, und es ist ehrlicher als eine Kopie im Test, die beim
    naechsten Umbau still veraltet.
    """
    text = (WURZEL / "index.html").read_text(encoding="utf-8")
    anfang = text.index("function " + name + "(")
    tiefe, i = 0, text.index("{", anfang)
    start = i
    while True:
        if text[i] == "{":
            tiefe += 1
        elif text[i] == "}":
            tiefe -= 1
            if tiefe == 0:
                break
        i += 1
    return text[anfang:start] + text[start:i + 1]


def test_fund3_das_ereignisprotokoll_nennt_den_abbruchgrund():
    """Das Command Center warf den Abbruchgrund weg, den es gerade baute.

    Reproduktion vor der Reparatur, mit demselben Befehl wie der Pruefer:

        strom      -> ""
        dropped    -> ""

    Der Aufrufer uebergab `{status: 'abgerissen: ...'}`, `ccStromText` fiel
    fuer den Typ 'strom' auf `return ''` durch. Im Protokoll stand danach
    nur "HH:MM:SS strom" ohne jede Erklaerung. 'dropped' sendet der Server
    bei vollem Puffer wirklich (api/events.py, EventBus._verdraengen).
    """
    node = shutil.which("node")
    assert node, "node fehlt - ohne JS-Laufzeit ist der Fund nicht pruefbar"
    quelle = _funktion_aus_index("ccStromText")
    programm = quelle + """
    var raus = {
      strom: ccStromText('strom', {status: 'abgerissen: Failed to fetch'}),
      dropped: ccStromText('dropped', {}),
      unbekannt: ccStromText('quatsch', {}),
      task: ccStromText('task', {status: 'done', goal: 'Wie spaet ist es?'})
    };
    console.log(JSON.stringify(raus));
    """
    fertig = subprocess.run([node, "-e", programm], capture_output=True,
                            text=True, timeout=60)
    assert fertig.returncode == 0, fertig.stderr
    raus = json.loads(fertig.stdout)
    assert "abgerissen: Failed to fetch" in raus["strom"], raus
    assert raus["dropped"], raus
    assert "Puffer" in raus["dropped"], raus
    # Die Gegenprobe: unbekannte Typen fallen weiter still durch, und die
    # vorhandenen Typen sind unveraendert.
    assert raus["unbekannt"] == "", raus
    assert "Wie spaet ist es?" in raus["task"], raus


# --- Fund 5: die Ursache eines Datenbankfehlers -------------------------


HEALTH_KAPUTT = {
    "status": "degraded", "phase": 2, "provider": "groq", "model": "llama",
    "api_key_configured": True, "api_key_hint": "gsk_...",
    "provider_error": None,
    "database": "fehler: no such table: messages",
    "messages": 0,
    "spend": {"calls": 0, "in_tokens": 0, "out_tokens": 0,
              "cost_eur": 0.0, "prices_configured": False},
}


def test_fund5_ein_datenbankfehler_steht_im_kopf(server):
    """GET /api/health nennt die Ursache - gelesen hat sie niemand.

    Reproduktion vor der Reparatur: bei dieser Antwort wurde der Punkt rot
    und daneben stand "noch kein Modellaufruf". Der Text fiel durch die
    Kette bis `spendText(h.spend)` durch, und weil dieselbe Route bei einem
    Datenbankfehler `totals = {}` setzt, ist `spend.calls` dort 0. Der
    Nutzer bekam eine positive Behauptung ueber den Betriebszustand
    vorgesetzt, waehrend die echte Ursache in derselben HTTP-Antwort
    mitgeliefert wurde.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        try:
            seite.route("**/api/health", lambda r: r.fulfill(
                status=200, content_type="application/json",
                body=json.dumps(HEALTH_KAPUTT)))
            _warte_auf_cc(seite, server)
            seite.wait_for_timeout(1200)
            text = seite.inner_text("#health-text")
            assert "no such table: messages" in text, text
            assert "noch kein Modellaufruf" not in text, text
            assert seite.get_attribute("#health-dot", "class") == "dot is-bad"
        finally:
            br.close()


def test_fund5_bei_gesunder_datenbank_bleibt_der_kopf_wie_er_war(server):
    """Die Gegenprobe zum Zweig: mit `database == "ok"` darf sich nichts
    aendern - sonst haette die Reparatur nur den Fehlerfall gegen den
    Normalfall getauscht."""
    gesund = dict(HEALTH_KAPUTT, status="ok", database="ok", provider="fake")
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        try:
            seite.route("**/api/health", lambda r: r.fulfill(
                status=200, content_type="application/json",
                body=json.dumps(gesund)))
            _warte_auf_cc(seite, server)
            seite.wait_for_timeout(1200)
            text = seite.inner_text("#health-text")
            assert "Datenbank" not in text, text
            assert "Fake-Anbieter" in text, text
        finally:
            br.close()


# --- Fund 6: der verschluckte Fehler von /api/stats ----------------------


def test_fund6_ein_fehler_von_api_stats_ist_sichtbar(server):
    """Von fuenf Abrufen war genau einer stumm.

    Reproduktion vor der Reparatur: bei einem 500er von /api/stats standen
    in allen vier Kacheln Wert "—" und eine LEERE Fussnote - derselbe
    Anblick wie bei einer frischen Datenbank, obwohl daneben im selben
    Raster drei Zonen einen Fehler zeigten. Ein Fehler sah damit aus wie
    "noch nichts gemessen".
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw)
        try:
            seite.route("**/api/stats", lambda r: r.fulfill(
                status=500, content_type="application/json",
                body='{"detail":"Datenbank gesperrt"}'))
            _warte_auf_cc(seite, server)
            seite.wait_for_timeout(1500)
            kacheln = seite.eval_on_selector_all(
                ".cc-kennzahl",
                "l => l.map(e => ({w: e.querySelector('.wert').textContent,"
                " f: e.querySelector('.fussnote').textContent}))")
            assert len(kacheln) == 4, kacheln
            for k in kacheln:
                assert "Datenbank gesperrt" in k["f"], kacheln
                assert k["w"] == "—", kacheln

            # Und die Gegenrichtung: was der Fehlerpfad setzt, muss der
            # Erfolgspfad wieder abraeumen. Sonst bliebe die Kosten-Kachel
            # nach einem einzigen Aussetzer fuer immer grau - DoD 5 sagt
            # ausdruecklich, dass `0,0000 €` eine Messung ist.
            seite.unroute("**/api/stats")
            seite.click("#tab-chat")
            seite.wait_for_timeout(200)
            seite.click("#tab-cc")
            seite.wait_for_timeout(1500)
            erholt = seite.eval_on_selector_all(
                ".cc-kennzahl",
                "l => l.map(e => ({w: e.querySelector('.wert').textContent,"
                " f: e.querySelector('.fussnote').textContent,"
                " leer: e.querySelector('.wert').classList.contains('ist-leer')}))")
            kosten = [k for k in erholt if "€" in k["w"]]
            assert len(kosten) == 1, erholt
            assert kosten[0]["leer"] is False, erholt
            for k in erholt:
                assert "Datenbank gesperrt" not in k["f"], erholt
        finally:
            br.close()


# --- Fund 8: UTC aus der Datenbank, Ortszeit auf dem Schirm --------------


UTC_ZEIT = "2026-08-30T16:26:12Z"
_ORT = datetime(2026, 8, 30, 16, 26, 12, tzinfo=timezone.utc).astimezone(
    ZoneInfo("Europe/Berlin"))
ORTSZEIT = _ORT.strftime("%H:%M:%S")      # 18:26:12 (Sommerzeit, UTC+2)
ORTSDATUM = _ORT.strftime("%d.%m.%Y")     # 30.08.2026
UTC_STUNDE = UTC_ZEIT[11:19]              # 16:26:12 - das stand vorher da

WERKZEUGE = [{"id": 1, "name": "get_time", "arguments": {}, "ok": True,
              "duration_ms": 3, "created_at": UTC_ZEIT, "result": "ok",
              "error": None, "sources": []}]
AUFTRAEGE = [{"id": "t-1", "goal": "Wie spaet ist es?", "status": "done",
              "created_at": UTC_ZEIT, "parent_task_id": None,
              "spent_tokens": 0, "spent_tool_calls": 0, "spent_cost_eur": 0.0,
              "result": "", "steps": []}]
FAKTEN = [{"id": 1, "text": "Noah wohnt in Berlin.", "category": "ort",
           "created_at": UTC_ZEIT, "source_message_id": None}]


def test_fund8_zeitstempel_stehen_in_ortszeit(server):
    """Das Frontend druckte UTC-Zeitstempel roh neben eine Ortszeit-Uhr.

    Reproduktion vor der Reparatur, mit `TZ=Europe/Berlin`:

        db.utcnow()          -> 2026-08-30T16:26:12Z
        index.html:2792/3019 -> 16:26:12      (slice(11, 19))
        index.html:2384      -> 2026-08-30 16:26:12
        index.html:2634 Uhr  -> 18:26:12      (new Date().getHours())

    Zwei Stunden Abstand im selben Bild, ohne eine Beschriftung, die das
    erklaert. Geprueft werden alle vier Stellen, damit auch ein halber
    Rueckbau auffaellt.
    """
    with playwright.sync_playwright() as pw:
        br, seite = _browser_roh(pw, timezone_id="Europe/Berlin")
        try:
            seite.route("**/api/tool-calls*", lambda r: r.fulfill(
                status=200, content_type="application/json",
                body=json.dumps(WERKZEUGE)))
            seite.route("**/api/tasks", lambda r: r.fulfill(
                status=200, content_type="application/json",
                body=json.dumps(AUFTRAEGE)))
            seite.route("**/api/memory", lambda r: r.fulfill(
                status=200, content_type="application/json",
                body=json.dumps(FAKTEN)))
            _warte_auf_cc(seite, server)
            seite.wait_for_timeout(1200)

            # Stelle 1: Zone 6 des Command Centers.
            zone6 = seite.inner_text("#view-cc .cc-tabelle")
            assert ORTSZEIT in zone6, zone6
            assert UTC_STUNDE not in zone6, zone6

            # Stelle 2: die Werkzeugansicht.
            seite.click("#tab-tools")
            seite.wait_for_selector("#view-tools table", timeout=20000)
            werkzeuge = seite.inner_text("#view-tools")
            assert ORTSZEIT in werkzeuge, werkzeuge
            assert UTC_STUNDE not in werkzeuge, werkzeuge

            # Stelle 3: die Auftragskarten.
            seite.click("#tab-tasks")
            seite.wait_for_selector("#view-tasks .karte", timeout=20000)
            auftraege = seite.inner_text("#view-tasks")
            assert ORTSDATUM in auftraege, auftraege
            assert ORTSZEIT in auftraege, auftraege
            assert "2026-08-30" not in auftraege, auftraege

            # Stelle 4: das Gedaechtnis-Panel.
            seite.click("#btn-memory")
            seite.wait_for_selector("#memory-liste .fakt-zeile", timeout=20000)
            gedaechtnis = seite.inner_text("#memory-liste")
            assert ORTSDATUM in gedaechtnis, gedaechtnis
            assert "2026-08-30" not in gedaechtnis, gedaechtnis

            # Und die Uhr in Zone 1 laeuft in derselben Zeitzone - sonst
            # waere der Test nur eine andere Art von Widerspruch.
            seite.click("#tab-cc")
            seite.wait_for_timeout(300)
            uhr = seite.inner_text(".cc-uhr")
            assert re.match(r"^\d{2}:\d{2}:\d{2}", uhr.strip()), uhr
        finally:
            br.close()
