// node blick.cjs <url-basis> <ausgabeordner> — Screenshots: Tag, Abend, Nacht; fern und nah; Handy
const U = require('./umgebung.cjs');
const { chromium } = U;
const basis = process.argv[2] || U.HOST + '/stadt.html', aus = process.argv[3] || U.ordner('blick');
const seed = process.argv[4] || '2', tage = process.argv[5] || '400', extra = process.argv[6] || '';
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [w, h, name] of [[1280, 800, 'breit'], [400, 820, 'handy']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h } });
    await U.three(ctx);
    await ctx.route('http://localhost:11434/**', (route) => route.abort());
    const page = await ctx.newPage();
    const log = [];
    page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text()); });
    page.on('pageerror', e => log.push('pageerror: ' + e.message));
    await page.goto(`${basis}?debug&seed=${seed}&tage=${tage}&neu${extra}`, { timeout: 600000 });
    await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
    await page.evaluate(() => __stadt.setzeTempo(0));
    // Dialoge (Nachfolge einer Hauptfigur) verdecken sonst die Szene: Verluste als erledigt markieren, offene Dialoge schließen
    const zu = async () => { for (let i = 0; i < 30; i++) {
      const o = await page.evaluate(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
        for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
      await page.waitForTimeout(150); if (!o) break; } };
    const stunden = name === 'breit' ? [11, 19, 23] : [11, 22];
    for (const ziel of stunden) {
      await page.evaluate((z) => { let n = 0; while (__stadt.S().stunde !== z && n++ < 30) __stadt.schritt(); __stadt.nachSchritten(); }, ziel);
      await page.waitForTimeout(700); await zu(); await page.waitForTimeout(300);
      await page.screenshot({ path: `${aus}${name}_${ziel}h_fern.png` });
      if (name === 'breit') {
        await page.evaluate(() => { const { G } = __stadt, c = G.controls, t = c.target; G.camera.position.set(t.x + 7, 6, t.z + 9); c.update(); });
        await page.waitForTimeout(500); await zu();
        await page.screenshot({ path: `${aus}${name}_${ziel}h_nah.png` });
        await page.evaluate(() => { const { G } = __stadt, c = G.controls, t = c.target; G.camera.position.set(t.x + 3.2, 1.8, t.z + 4.2); c.update(); });
        await page.waitForTimeout(500); await zu();
        await page.screenshot({ path: `${aus}${name}_${ziel}h_strasse.png` });
        await page.evaluate(() => __stadt.G.ausrichten());
      }
    }
    const d = await page.evaluate(() => globalThis.__stadtDebug);
    console.log(name, JSON.stringify({ calls: d.calls, dreiecke: d.dreiecke, frameMs: +d.frameMs.toFixed(1), einwohner: d.einwohner }), 'Konsole:', log.join(' | ') || 'leer');
    await ctx.close();
  }
  await b.close();
})();
