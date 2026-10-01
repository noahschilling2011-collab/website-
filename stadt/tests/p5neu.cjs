// Tests für die Fixes aus dem Spec-Abgleich (23.09.)
const U = require('./umgebung.cjs');
const { chromium } = U;
const OUT = U.ordner('bilder_p5');   // Bilder nach tests/ausgabe/ (per .gitignore ausgeschlossen)
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const ev = (f, a) => page.evaluate(f, a);
  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=650&neu');
  await page.waitForFunction(() => globalThis.__stadt && __stadt.ki.status === 'bereit', null, { timeout: 30000 });
  await ev(() => __stadt.setzeTempo(0));
  // bis Tag 650 sind die ersten Hauptfiguren gestorben: Nachfolge-Dialoge wegklicken („Niemand“/„Verstanden“)
  for (let i = 0; i < 12; i++) {
    await page.waitForTimeout(500);
    if (!(await ev(() => document.getElementById('nachfolge-dialog').open))) break;
    await page.click('#nachfolge-knoepfe button:last-child');
  }

  // (a) Name einer Person, die nicht mehr in der Stadt ist: anklickbar, Karte mit Namen
  const weg = await ev(() => {
    const S = __stadt.S(), Sim = __stadt.Sim;
    for (let p = 0; p < S.pMax; p++) {
      if (!S.p.lebt[p]) continue;
      const i = Sim.personInfo(S, p);
      if (i && i.eltern.some(e => !e.lebt && e.id >= 0)) return [p, S.p.gen[p]];
    }
    return null;
  });
  ok(weg, 'Person mit Elternteil, das nicht mehr in der Stadt ist: ' + JSON.stringify(weg));
  if (weg) {
    await ev(([p, g]) => { const k = document.createElement('button'); k.className = 'name'; k.dataset.p = p; k.dataset.g = g; document.body.append(k); k.click(); k.remove(); }, weg);
    await page.waitForTimeout(150);
    const knopf = await page.$('#karte .familie button.name.weg');
    ok(!!knopf, 'Elternteil steht als anklickbarer Name (ohne †) auf der Karte');
    const name = await knopf.textContent();
    await knopf.click(); await page.waitForTimeout(150);
    const karte = await ev(() => ({ h2: document.querySelector('#karte h2').textContent, p: document.querySelector('#karte p').textContent }));
    ok(karte.h2 === name && karte.p.includes('Nicht mehr in der Stadt'), `Karte: „${karte.h2}“ – ${karte.p}`);
    ok(!(await ev(() => document.getElementById('karte').textContent.includes('†'))), 'kein † mehr');
    await page.keyboard.press('Escape');
  }

  // (b) Obergrenze: ohne Messung höchstens 5 Hauptfiguren
  const grenze = await ev(() => { __stadt.ki.messung = { n: 0, ms: 0 }; const S = __stadt.S(); while (S.ki.haupt.length > 5) S.ki.haupt.pop();
    for (let p = 0; p < S.pMax && S.ki.haupt.length < 5; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] > 200) __stadt.Sim.hauptSetzen(S, p, S.p.gen[p], true);
    for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] > 200 && !__stadt.Sim.istHaupt(S, p)) return [p, S.p.gen[p], S.ki.haupt.length]; });
  await ev(([p, g]) => { const k = document.createElement('button'); k.className = 'name'; k.dataset.p = p; k.dataset.g = g; document.body.append(k); k.click(); k.remove(); }, grenze);
  await page.waitForTimeout(150);
  const b5 = await ev(() => { const k = document.querySelector('#karte [data-haupt="an"]'); return { disabled: k.disabled, text: k.parentElement.textContent.replace(/\s+/g, ' ') }; });
  ok(grenze[2] === 5 && b5.disabled && b5.text.includes('unter 5 Sekunden'), `5 Hauptfiguren, ungemessen: Knopf gesperrt – „${b5.text}“`);
  await ev(() => { __stadt.ki.messung = { n: 6, ms: 6 * 1200 }; __stadt.nachSchritten(); });
  await page.waitForTimeout(150);
  ok(await ev(() => !document.querySelector('#karte [data-haupt="an"]').disabled), 'gemessen 1,2 s im Schnitt: Knopf frei (bis 10)');
  await ev(() => { __stadt.ki.messung = { n: 6, ms: 6 * 7000 }; __stadt.nachSchritten(); });
  await page.waitForTimeout(150);
  const b7 = await ev(() => document.querySelector('#karte .karte-knoepfe').textContent.replace(/\s+/g, ' '));
  ok(b7.includes('bisher 7,0 s'), 'gemessen 7 s: gesperrt mit Messwert – „' + b7 + '“');
  const gespeichert = await ev(() => { __stadt.speichern(); return JSON.parse(localStorage.getItem('stadt-save-v1')).ui.kiMessung; });
  ok(gespeichert && gespeichert.n === 6, 'Messung wird mitgespeichert: ' + JSON.stringify(gespeichert));
  await page.keyboard.press('Escape');

  // (c) Versteckter Tab: zuletztGelaufen bleibt beim Moment des Versteckens
  const t = await ev(async () => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
    const t0 = Date.now();
    await new Promise(r => setTimeout(r, 2500));
    __stadt.speichern();
    const z = JSON.parse(localStorage.getItem('stadt-save-v1')).zuletztGelaufen;
    delete document.hidden;
    return { versteckt: t0, gespeichert: z, jetzt: Date.now() };
  });
  ok(Math.abs(t.gespeichert - t.versteckt) < 200 && t.jetzt - t.gespeichert > 2000, `versteckt gespeichert: ${t.jetzt - t.gespeichert} ms vor „jetzt“ (Moment des Versteckens)`);

  // (d) Kontrast: Mittag, Kamera flach und weit (heller Himmel hinter dem Panel)
  await ev(() => { const a = __stadt; while (a.S().stunde !== 12) a.schritt(); a.nachSchritten();
    const c = a.G.controls; c.maxDistance = 160; a.G.camera.position.set(c.target.x + 150, 40, c.target.z + 40); c.update(); });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + 'p5_mittag.png' });
  const r = await page.evaluate(() => document.querySelector('#kennzahlen dt').getBoundingClientRect());
  const buf = await page.screenshot();
  const p2 = await ctx.newPage();
  const px = await p2.evaluate(async ({ b64, x, y, w }) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    // Hintergrund: hellstes Pixel rechts neben der Beschriftung (zwischen dt und dd, kein Text)
    let best = [0, 0, 0];
    for (let dx = 0; dx < 40; dx++) { const d = g.getImageData(Math.round(x + w + 6 + dx), Math.round(y + 4), 1, 1).data; if (d[0] + d[1] + d[2] > best[0] + best[1] + best[2]) best = [d[0], d[1], d[2]]; }
    return best;
  }, { b64: buf.toString('base64'), x: r.left, y: r.top, w: r.width });
  await p2.close();
  const lin = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  const L = ([r, g, b]) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  const kontrast = (L([0xa3, 0xa3, 0xae]) + 0.05) / (L(px) + 0.05);
  ok(kontrast >= 4.5, `Kontrast leiser Text zu hellstem Panel-Hintergrund vor Taghimmel: ${kontrast.toFixed(2)}:1 (Hintergrund ${px})`);

  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
