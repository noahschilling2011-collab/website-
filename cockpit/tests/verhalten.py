"""Verhaltenstests: Aufgaben, Chat, Import/Export, Zeitleiste, Fokus, Reduced Motion.

Headless-Pruefung fuer cockpit/index.html. Braucht Playwright mit Chromium:
    pip install playwright && playwright install chromium
Aufruf:  python3 cockpit/tests/verhalten.py
Exit-Code 1, wenn etwas fehlschlaegt.
"""
import json, pathlib, re, sys
from datetime import datetime, timedelta
from playwright.sync_api import sync_playwright

FILE = pathlib.Path(__file__).resolve().parent.parent / "index.html"
URL  = FILE.as_uri()
ok, bad = [], []
def check(name, cond, extra=""):
    (ok if cond else bad).append(name + (" — " + str(extra) if extra else ""))

src = FILE.read_text(encoding="utf-8")

# ── statisch ───────────────────────────────────────────────────────────
check("kein Storage-Aufruf im Code",
      not re.search(r"(window\\.)?(local|session)Storage\\s*[\\.\\[]", src),
      re.findall(r".{0,40}(?:local|session)Storage\\s*[\\.\\[].{0,20}", src))
check("kein type=\"module\"", 'type="module"' not in src)
check("keine externen Requests ausser der Anthropic-API",
      sorted(set(re.findall(r'(?:src|href)="(https?://[^"]+)', src))) == [],
      sorted(set(re.findall(r'(?:src|href)="(https?://[^"]+)', src))))
check("unter 150 KB", len(src.encode()) < 150_000, f"{len(src.encode())/1024:.1f} KB")
check("keine Emoji als Icons", not re.search(r"[\U0001F300-\U0001FAFF☀-➿]", src))
check("kein Indigo/Violett", not re.search(r"#6366f1|#8b5cf6", src, re.I))

now = datetime.now()
DAY_KEY = ["so","mo","di","mi","do","fr","sa"][(now.weekday()+1) % 7]
def hhmm(dt): return dt.strftime("%H:%M")

FIX = {
  "version": 1, "name": "Testperson",
  "stundenplan": {
    "mo": [], "di": [], "mi": [], "do": [], "fr": [], "sa": [], "so": []
  },
  "termine": [
    {"tag": ["so","mo","di","mi","do","fr","sa"][(now.weekday()+1) % 7],
     "von": hhmm(now - timedelta(hours=3)), "bis": hhmm(now - timedelta(hours=2)), "was": "Vergangener Block"},
    {"tag": ["so","mo","di","mi","do","fr","sa"][(now.weekday()+1) % 7],
     "von": hhmm(now - timedelta(minutes=20)), "bis": hhmm(now + timedelta(minutes=40)), "was": "Laufender Block"},
    {"tag": ["so","mo","di","mi","do","fr","sa"][(now.weekday()+1) % 7],
     "von": hhmm(now + timedelta(hours=3)), "bis": hhmm(now + timedelta(hours=4)), "was": "Kommender Block"},
    {"tag": ["so","mo","di","mi","do","fr","sa"][(now.weekday()+1) % 7],
     "was": "Ohne Uhrzeit", "notiz": "nach Wetter"}
  ],
  "projekte": [
    {"name": "Frisch",  "notiz": "vor drei Tagen angefasst", "status": "aktiv",
     "datum": (now - timedelta(days=3)).strftime("%Y-%m-%d")},
    {"name": "Uralt",   "notiz": "liegt lange",              "status": "liegt",
     "datum": (now - timedelta(days=47)).strftime("%Y-%m-%d")},
    {"name": "Erledigt","notiz": "durch",                    "status": "fertig",
     "datum": (now - timedelta(days=2)).strftime("%Y-%m-%d")}
  ],
  "ziele": [
    {"titel": "Halbzeit-Ziel", "angelegt": (now - timedelta(days=50)).strftime("%Y-%m-%d"),
     "faellig": (now + timedelta(days=50)).strftime("%Y-%m-%d")}
  ],
  "aufgaben": [{"id": 1, "text": "Importierte Aufgabe", "erledigt": False}],
  "verlauf": [{"frage": "alte Frage", "antwort": "alte Antwort"}]
}

with sync_playwright() as pw:
    br = pw.chromium.launch()
    ctx = br.new_context(viewport={"width": 1440, "height": 900})
    page = ctx.new_page()
    errs = []
    page.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errs.append("pageerror: " + str(e)))

    # Chat-Request abfangen — wir wollen die echte Request-Form sehen.
    seen = {}
    def route(r):
        seen["url"] = r.request.url
        seen["method"] = r.request.method
        seen["headers"] = r.request.headers
        seen["body"] = json.loads(r.request.post_data)
        r.fulfill(status=200, content_type="application/json",
                  body=json.dumps({"content": [{"type": "text", "text": "Antwort aus dem Test."},
                                               {"type": "thinking", "text": "ignorieren"}]}))
    page.route("**/api.anthropic.com/**", route)

    page.goto(URL); page.wait_for_timeout(600)

    check("laedt per file:// ohne Fehler", not errs, errs[:3])
    check("Uhr laeuft", page.inner_text("#clock") != "--:--:--", page.inner_text("#clock"))

    # ── Aufgaben ───────────────────────────────────────────────────────
    page.fill("#task-input", "Erste Aufgabe"); page.press("#task-input", "Enter")
    page.fill("#task-input", "Zweite Aufgabe"); page.press("#task-input", "Enter")
    check("Aufgabe per Enter angelegt", page.locator("#tasks li").count() == 2,
          page.locator("#tasks li").count())
    page.fill("#task-input", "Dritte Aufgabe"); page.press("#task-input", "Enter")
    # Abhaken per Tastatur: der Fokus muss auf der Checkbox stehen bleiben.
    cb0 = page.locator("#tasks li").first.locator("input[type=checkbox]")
    cb0.focus(); page.keyboard.press("Space")
    check("Abhaken setzt Klasse", "is-done" in page.locator("#tasks li").first.get_attribute("class"))
    check("Fokus ueberlebt das Abhaken",
          page.evaluate("() => document.activeElement && document.activeElement.type") == "checkbox",
          page.evaluate("() => document.activeElement && document.activeElement.tagName"))
    check("Abhaken haelt die Checkbox angehakt",
          page.evaluate("() => document.activeElement.checked") is True)

    # Loeschen: Fokus muss auf die nachrueckende Zeile wandern.
    page.locator("#tasks li").nth(1).locator("button.task-x").click(force=True)
    check("Loeschen per X", page.locator("#tasks li").count() == 2,
          page.locator("#tasks li").count())
    check("Fokus wandert nach dem Loeschen auf die naechste Zeile",
          page.evaluate("() => document.activeElement && document.activeElement.className") == "task-x",
          page.evaluate("() => document.activeElement && document.activeElement.className"))
    while page.locator("#tasks li").count() > 1:
        page.locator("#tasks li").last.locator("button.task-x").click(force=True)
    page.locator("#tasks li").first.locator("button.task-x").click(force=True)
    check("Loeschen der letzten Zeile setzt den Fokus ins Eingabefeld",
          page.locator("#tasks li").count() == 0 and
          page.evaluate("() => document.activeElement && document.activeElement.id") == "task-input",
          page.evaluate("() => document.activeElement && document.activeElement.id"))
    page.fill("#task-input", "Erste Aufgabe"); page.press("#task-input", "Enter")

    # ── Chat ───────────────────────────────────────────────────────────
    page.fill("#chat-input", "Was soll ich heute machen?")
    page.press("#chat-input", "Enter")
    page.wait_for_selector(".qa-a", timeout=8000)
    check("Chat feuert POST an die Anthropic-API",
          seen.get("url") == "https://api.anthropic.com/v1/messages" and seen.get("method") == "POST",
          seen.get("url"))
    check("kein API-Key im Request",
          not any(k.lower() in ("x-api-key", "authorization") for k in seen.get("headers", {})),
          [k for k in seen.get("headers", {})])
    b = seen.get("body", {})
    check("Body hat model/max_tokens/messages",
          b.get("model") and b.get("max_tokens") == 1000 and isinstance(b.get("messages"), list))
    prompt = b["messages"][0]["content"]
    check("Anweisung woertlich im Prompt", "Du bist mein Tagesplaner" in prompt and
          "Erfinde keine Termine, keine Projekte" in prompt)
    check("State im Prompt serialisiert",
          all(k in prompt for k in ("tagesplan_heute", "aufgaben_offen", "projekte",
                                    "ziele", "tage_seit_letztem_update")))
    check("offene Aufgabe steckt im Prompt", "Erste Aufgabe" in prompt)
    check("Name steckt im Prompt", '"name": "Noah"' in prompt, prompt[:120])
    check("Verlauf-Feld im Prompt vorhanden", "bisheriger_verlauf" in prompt)
    check("Antwort gerendert", "Antwort aus dem Test." in page.inner_text("#chat-log"))
    check("thinking-Bloecke rausgefiltert", "ignorieren" not in page.inner_text("#chat-log"))

    # Fehlerzustand
    page.unroute("**/api.anthropic.com/**")
    page.route("**/api.anthropic.com/**", lambda r: r.fulfill(status=500, body="kaputt"))
    page.fill("#chat-input", "zweite Frage"); page.press("#chat-input", "Enter")
    page.wait_for_selector("#chat-state.bad", timeout=8000)
    check("HTTP-Fehler landet lesbar im Panel", "500" in page.inner_text("#chat-state"),
          page.inner_text("#chat-state"))

    # Rueckfrage: die erste Runde muss im Prompt der zweiten stehen.
    page.unroute("**/api.anthropic.com/**")
    zweit = {}
    def route2(r):
        zweit["prompt"] = json.loads(r.request.post_data)["messages"][0]["content"]
        r.fulfill(status=200, content_type="application/json",
                  body=json.dumps({"content": [{"type": "text", "text": "zweite Antwort"}]}))
    page.route("**/api.anthropic.com/**", route2)
    page.fill("#chat-input", "und dann?"); page.press("#chat-input", "Enter")
    page.wait_for_timeout(900)
    check("Rueckfrage traegt den bisherigen Verlauf mit",
          "Antwort aus dem Test." in zweit.get("prompt", "") and
          "Was soll ich heute machen?" in zweit.get("prompt", ""),
          "verlauf fehlt")
    check("Verlauf zeigt beide Runden", page.locator("#chat-log .qa").count() == 2,
          page.locator("#chat-log .qa").count())

    # ── Export -> Import -> Export ─────────────────────────────────────
    page.click("#btn-import")
    page.fill("#import-text", json.dumps(FIX))
    page.click("#btn-load")
    page.wait_for_timeout(300)
    check("Import meldet Erfolg", "Geladen:" in page.inner_text("#import-msg"),
          page.inner_text("#import-msg"))
    check("Name aus Import uebernommen", "Testperson" in page.inner_text("#greet-name"))

    # Kaputtes JSON
    page.fill("#import-text", "{ das ist kein json")
    page.click("#btn-load")
    check("kaputtes JSON meldet Fehler im UI", "Kein gültiges JSON" in page.inner_text("#import-msg"),
          page.inner_text("#import-msg"))
    # Schema-Fehler
    page.fill("#import-text", json.dumps({**FIX, "projekte": [{"name": "X", "datum": "31.12.2026"}]}))
    page.click("#btn-load")
    check("falsches Datumsformat wird abgefangen",
          "JJJJ-MM-TT" in page.inner_text("#import-msg"), page.inner_text("#import-msg"))

    # Rundlauf: importierten State erneut exportieren und vergleichen
    page.fill("#import-text", json.dumps(FIX)); page.click("#btn-load"); page.wait_for_timeout(200)
    ctx.grant_permissions(["clipboard-read", "clipboard-write"])
    page.click("#btn-export"); page.wait_for_timeout(400)
    clip = page.evaluate("() => navigator.clipboard.readText()")
    try:
        again = json.loads(clip)
        check("Export -> Import -> Export identisch",
              json.dumps(again, sort_keys=True) == json.dumps(FIX, sort_keys=True),
              "diff" if again != FIX else "")
        check("Export-Knopf quittiert", "Kopiert" in page.inner_text("#btn-export"),
              page.inner_text("#btn-export"))
    except Exception as e:
        check("Export -> Import -> Export identisch", False, "Zwischenablage: %r / %s" % (clip[:80], e))

    # ── Zeitleiste + Projekte mit echten Daten ─────────────────────────
    rows = page.locator("#timeline li")
    check("Zeitleiste zeigt vier Bloecke", rows.count() == 4, rows.count())
    check("vergangener Block gedimmt", "past" in rows.nth(0).get_attribute("class"),
          rows.nth(0).get_attribute("class"))
    check("laufender Block hervorgehoben", "now" in rows.nth(1).get_attribute("class"),
          rows.nth(1).get_attribute("class"))
    check("Restzeit am laufenden Block", "noch" in rows.nth(1).inner_text(), rows.nth(1).inner_text())
    check("kommender Block neutral", rows.nth(2).get_attribute("class").strip() == "tl-row",
          rows.nth(2).get_attribute("class"))
    check("Block ohne Uhrzeit ganz unten", "Ohne Uhrzeit" in rows.nth(3).inner_text(),
          rows.nth(3).inner_text())

    cards = page.locator("#projects li")
    alt = cards.filter(has_text="Uralt")
    check("Projekt >30 Tage bekommt .rest", "rest" in alt.first.get_attribute("class"),
          alt.first.get_attribute("class"))
    check("Label 'liegt seit 47 Tagen'", "liegt seit 47 Tagen" in alt.first.inner_text(),
          alt.first.inner_text())
    check("frisches Projekt ohne .rest", "rest" not in cards.filter(has_text="Frisch").first.get_attribute("class"))
    check("Fusszeile zaehlt richtig", page.inner_text("#proj-count") == "1 aktiv · 1 liegen · 1 fertig",
          page.inner_text("#proj-count"))

    bar = page.locator("#goals .rail span")
    w = page.evaluate("() => { const r=document.querySelector('#goals .rail span'); return r ? r.style.width : null }")
    check("Zielbalken ~50 % (50 von 100 Tagen)", w and 49.0 <= float(w.rstrip("%")) <= 51.0, w)

    # ── kein horizontaler Ueberlauf bei 360 ────────────────────────────
    page.set_viewport_size({"width": 360, "height": 780}); page.wait_for_timeout(300)
    sw = page.evaluate("() => document.documentElement.scrollWidth")
    check("360px ohne horizontales Scrollen", sw <= 360, sw)
    page.click("#btn-import"); page.wait_for_timeout(300)
    sw2 = page.evaluate("() => document.documentElement.scrollWidth")
    check("360px auch mit offenem Popover", sw2 <= 360, sw2)
    page.keyboard.press("Escape")
    check("Escape startet die Schliessanimation",
          "zu" in (page.locator("#pop-import").get_attribute("class") or ""),
          page.locator("#pop-import").get_attribute("class"))
    page.wait_for_timeout(400)
    check("Popover ist danach wirklich zu", page.locator("#pop-import").is_hidden())
    check("Fokus zurueck auf dem Import-Knopf",
          page.evaluate("() => document.activeElement && document.activeElement.id") == "btn-import",
          page.evaluate("() => document.activeElement && document.activeElement.id"))

    # ── Spalten per Tastatur scrollbar ─────────────────────────────────
    check("360px: kein ueberfluessiger Tabstop auf den Spalten",
          page.evaluate("() => document.getElementById('pane-proj').hasAttribute('tabindex')") is False)
    page.set_viewport_size({"width": 1440, "height": 900}); page.wait_for_timeout(300)
    check("Desktop: Projektspalte ist per Tastatur fokussierbar",
          page.evaluate("() => document.getElementById('pane-proj').getAttribute('tabindex')") == "0")
    check("Desktop: Zielspalte ist per Tastatur fokussierbar",
          page.evaluate("() => document.getElementById('pane-goals').getAttribute('tabindex')") == "0")
    # Frische Seite: die ausgelieferten 15 Projekte laufen ueber die Spaltenhoehe.
    pg4 = ctx.new_page()
    pg4.set_viewport_size({"width": 1440, "height": 900})
    pg4.goto(URL); pg4.wait_for_timeout(500)
    scrolled = pg4.evaluate("""() => {
      const p = document.getElementById('pane-proj');
      if (p.scrollHeight <= p.clientHeight) return 'kein Ueberlauf (' + p.scrollHeight + '/' + p.clientHeight + ')';
      p.focus();
      if (document.activeElement !== p) return 'nicht fokussierbar';
      const vorher = p.scrollTop;
      p.scrollTop = 200;
      return p.scrollTop > vorher ? 'scrollt' : 'scrollt nicht';
    }""")
    check("Projektspalte laeuft ueber und scrollt per Fokus", scrolled == "scrollt", scrolled)
    pg4.close()

    # ── Fokus sichtbar ─────────────────────────────────────────────────
    page.wait_for_timeout(200)
    ring = page.evaluate("""() => {
      const el = document.getElementById('chat-input');
      el.focus();
      const cs = getComputedStyle(el);
      return {w: cs.outlineWidth, s: cs.outlineStyle, c: cs.outlineColor};
    }""")
    check("Chat-Eingabe hat Fokusring", ring["s"] != "none" and ring["w"] not in ("0px", ""), ring)

    tabbed = page.evaluate("""() => {
      const sel = 'a[href],button:not([disabled]),input,textarea,[tabindex]:not([tabindex="-1"])';
      return [...document.querySelectorAll(sel)].filter(e => e.offsetParent !== null || e === document.activeElement).length;
    }""")
    check("fokussierbare Elemente vorhanden", tabbed >= 6, tabbed)

    # ── reduced motion ─────────────────────────────────────────────────
    page2 = ctx.new_page()
    page2.emulate_media(reduced_motion="reduce")
    page2.goto(URL); page2.wait_for_timeout(500)
    still = page2.evaluate("""() => {
      const runners = [...document.querySelectorAll('*')].filter(e => {
        const a = getComputedStyle(e).animationName;
        const d = parseFloat(getComputedStyle(e).animationDuration);
        return a && a !== 'none' && d > 0.05;
      });
      return runners.map(e => e.className + ':' + getComputedStyle(e).animationName);
    }""")
    check("prefers-reduced-motion stoppt alles", still == [], still)

    # ── Bloecke ueber Mitternacht + einstellige Stunde ─────────────────
    MID = {**FIX, "termine": [
        {"tag": DAY_KEY, "von": "22:00", "bis": "02:00", "was": "Ueber Mitternacht"},
        {"tag": DAY_KEY, "von": "7:45",  "bis": "13:00", "was": "Einstellige Stunde"},
    ]}
    page.click("#btn-import"); page.fill("#import-text", json.dumps(MID)); page.click("#btn-load")
    page.keyboard.press("Escape"); page.wait_for_timeout(250)
    tl = page.locator("#timeline li")
    texts = [tl.nth(i).inner_text() for i in range(tl.count())]
    check("einstellige Stunde wird als Uhrzeit gelesen",
          any("7:45" in t and "—" not in t.split("\n")[0] for t in texts), texts)
    h = datetime.now().hour
    mid_row = [t for t in texts if "Ueber Mitternacht" in t]
    mid_cls = [tl.nth(i).get_attribute("class") for i in range(tl.count())
               if "Ueber Mitternacht" in tl.nth(i).inner_text()][0]
    # "future" ist der neutrale Default und traegt keine Klasse.
    laeuft = (h >= 22 or h < 2)
    check("Block ueber Mitternacht nie faelschlich 'past'",
          "past" not in mid_cls and (("now" in mid_cls) == laeuft), f"{h} Uhr -> {mid_cls!r}")

    # ── Laufzeitbeweis: Storage komplett vergiftet ─────────────────────
    ctx2 = br.new_context(viewport={"width": 1280, "height": 900})
    ctx2.add_init_script("""
      for (const k of ['localStorage','sessionStorage']) {
        Object.defineProperty(window, k, {
          configurable: false,
          get() { throw new DOMException('Zugriff verweigert', 'SecurityError'); }
        });
      }
    """)
    page3 = ctx2.new_page()
    e3 = []
    page3.on("pageerror", lambda e: e3.append(str(e)))
    page3.on("console", lambda m: e3.append(m.text) if m.type == "error" else None)
    page3.goto(URL); page3.wait_for_timeout(700)
    page3.fill("#task-input", "laeuft auch ohne Storage"); page3.press("#task-input", "Enter")
    check("laeuft mit vergiftetem Storage weiter",
          not e3 and page3.locator("#tasks li").count() == 1 and page3.locator("#projects li").count() == 15,
          e3[:2])

    br.close()

print("\n".join("  ok   " + x for x in ok))
print()
print("\n".join("  FAIL " + x for x in bad) if bad else "  keine Fehlschlaege")
print("\n%d ok, %d Fehlschlaege" % (len(ok), len(bad)))
sys.exit(1 if bad else 0)
