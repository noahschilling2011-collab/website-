// Hilfen für die Prüfungen in Paket O (Seitenserver aus tests/alle.sh, Three.js über tests/umgebung.cjs, Ollama abgewiesen)
const U = require('../umgebung.cjs');
const { chromium } = U;
const AUS = process.env.AUS || U.ordner('otest_bilder');   // AUS=ordner/ für eigene Bilder (sonst tests/ausgabe/otest_bilder/)
const start = () => chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
async function seite(b, opt, { datei = 'stadt.html', stunde = 11, extra = '', neu = true, warten = true, ctx: c0 = null } = {}) {
  const ctx = c0 || await b.newContext(opt);
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (r) => r.abort());
  const page = await ctx.newPage(); const log = [];
  page.on('pageerror', e => log.push('pageerror ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/ERR_FAILED/.test(m.text())) log.push('console ' + m.text()); });
  await page.goto(`${U.HOST}/${datei}?debug&seed=2&tage=400${neu ? '&neu' : ''}${extra}`, { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  if (warten) {
    await page.evaluate((z) => { __stadt.setzeTempo(0); let n = 0; while (__stadt.S().stunde !== z && n++ < 30) __stadt.schritt(); __stadt.nachSchritten(); }, stunde);
    await zu(page); await page.waitForTimeout(400); await zu(page);
  }
  return { ctx, page, log };
}
const zu = (page) => page.evaluate(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
// Bildlage aller Gebäude (Mitte, Höhe h)
const lagen = (page, h = 0.4) => page.evaluate((h) => {
  const { G } = __stadt, S = __stadt.S(), v = new G.THREE.Vector3(), r = G.renderer.domElement.getBoundingClientRect(), out = [];
  for (let b = 0; b < S.gAnzahl; b++) {
    v.set(S.g.x[b] - (S.mitte ?? 48) + 0.5, h, S.g.y[b] - (S.mitte ?? 48) + 0.5).project(G.camera);
    out.push({ b, typ: S.g.typ[b], x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top });
  }
  return out;
}, h);
const rechteck = (page, sel) => page.evaluate((sel) => { const e = document.querySelector(sel); if (!e) return null; const q = e.getBoundingClientRect();
  return { l: Math.round(q.left), t: Math.round(q.top), r: Math.round(q.right), u: Math.round(q.bottom), w: Math.round(q.width), h: Math.round(q.height),
    hidden: e.hidden, sicht: getComputedStyle(e).visibility }; }, sel);
// Tippen per CDP-Touch (echte Touch-Ereignisse), Klick per Maus
async function tippen(ctx, page, x, y) {
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
}
async function wischen(ctx, page, x, y, dx, dy) {
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
  for (let s = 1; s <= 10; s++) { await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx * s / 10, y: y + dy * s / 10, id: 1 }] }); await page.waitForTimeout(20); }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
}
// Seitliches Überlaufen: sichtbare Elemente, die über den rechten Rand ragen
const ueberlauf = (page) => page.evaluate(() => {
  const w = document.documentElement.clientWidth, raus = [];
  for (const e of document.querySelectorAll('body *')) {
    if (e.closest('#strassen-namen, .sprite, svg, dialog:not([open])')) continue;
    const q = e.getBoundingClientRect();
    if (!q.width || getComputedStyle(e).visibility === 'hidden') continue;
    if (q.right > w + 0.5 || q.left < -0.5) raus.push((e.id || e.className || e.tagName) + ' ' + Math.round(q.left) + '…' + Math.round(q.right));
  }
  return { scroll: document.documentElement.scrollWidth, breite: w, raus: raus.slice(0, 8) };
});
module.exports = { start, seite, zu, lagen, rechteck, tippen, wischen, ueberlauf, AUS };
