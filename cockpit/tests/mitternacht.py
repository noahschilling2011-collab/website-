"""Bloecke ueber Mitternacht, gegen eine gefaelschte Uhr gemessen.

Headless-Pruefung fuer cockpit/index.html. Braucht Playwright mit Chromium:
    pip install playwright && playwright install chromium
Aufruf:  python3 cockpit/tests/mitternacht.py
Exit-Code 1, wenn etwas fehlschlaegt.
"""
import json, pathlib
from playwright.sync_api import sync_playwright
F = pathlib.Path(__file__).resolve().parent.parent / "index.html"
BASE = {"version":1,"name":"T","stundenplan":{k:[] for k in ["mo","di","mi","do","fr","sa","so"]},
        "termine":[],"projekte":[],"ziele":[],"aufgaben":[],"verlauf":[]}
res = []
with sync_playwright() as pw:
    br = pw.chromium.launch()
    for label, iso, tag, erwartet in [
        ("23:30 (laeuft)", "2026-08-24T23:30:00", "mo", "now"),
        ("03:00 Di-Block", "2026-08-25T03:00:00", "di", "neutral"),  # Vortag wird nicht getragen
        ("12:00 (kommt)",  "2026-08-24T12:00:00", "mo", "neutral"),
    ]:
        ctx = br.new_context(viewport={"width":1200,"height":800})
        ctx.add_init_script("""(() => {
          const F = new Date('%s').getTime(); const R = Date;
          class D extends R { constructor(...a){ if(!a.length) super(F); else super(...a);} 
            static now(){ return F } }
          window.Date = D;
        })()""" % iso)
        pg = ctx.new_page(); pg.goto(F.as_uri()); pg.wait_for_timeout(400)
        st = dict(BASE); st["termine"] = [{"tag":tag,"von":"22:00","bis":"02:00","was":"Nacht"}]
        pg.click("#btn-import"); pg.fill("#import-text", json.dumps(st)); pg.click("#btn-load")
        pg.keyboard.press("Escape"); pg.wait_for_timeout(250)
        row = pg.locator("#timeline li").first
        cls = (row.get_attribute("class") or "").replace("tl-row","").strip() or "neutral"
        ok = (cls == erwartet)
        res.append(("ok  " if ok else "FAIL", label, cls, erwartet, row.inner_text().replace("\n"," | ")))
        ctx.close()
    br.close()
for r in res: print("  %s %-16s -> %-8s (erwartet %-8s)  %s" % r)
