// Desktop (Maus und Tastatur): erster Hinweis, Hilfe-Dialog, Tab-Reihenfolge, Fokusringe, Kontrast des Hinweises, Überlauf,
// kein Hinweis nach dem Laden eines Spielstands. W, H (Standard 1280 × 800)
const H = require('./h.cjs');
const U = require('../umgebung.cjs');
const W = +(process.env.W || 1280), HH = +(process.env.H || 800);
const ok = (b, t) => console.log((b ? 'OK  ' : 'FEHLER ') + t);
const lum = (r, g, b) => { const f = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
const kontrast = (a, b) => { const x = lum(...a), y = lum(...b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
// PNG → Pixel [r, g, b] in Node (8 Bit, RGB oder RGBA, ohne Interlace – so schreibt Chromium Bildschirmfotos). Ersetzt Pillow: Mit aktiver
// Trainings-venv hieß python3 dort ohne Pillow, und der Test wurde rot (Prüfung vom 29.09.2026)
function pngPixel(buf) {
  let o = 8, w = 0, h = 0, typ = 0;
  const idat = [];
  while (o < buf.length) {
    const n = buf.readUInt32BE(o), art = buf.toString('ascii', o + 4, o + 8), d = buf.subarray(o + 8, o + 8 + n);
    if (art === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); typ = d[9]; if (d[8] !== 8 || d[12] !== 0) throw new Error('PNG: nur 8 Bit ohne Interlace'); }
    else if (art === 'IDAT') idat.push(d);
    else if (art === 'IEND') break;
    o += 12 + n;
  }
  const bpp = { 2: 3, 6: 4 }[typ];
  if (!bpp) throw new Error('PNG: Farbtyp ' + typ + ' nicht unterstützt');
  const roh = require('zlib').inflateSync(Buffer.concat(idat)), breite = w * bpp, px = [];
  let vor = Buffer.alloc(breite);
  for (let y = 0; y < h; y++) {
    const filter = roh[y * (breite + 1)], z = Buffer.from(roh.subarray(y * (breite + 1) + 1, (y + 1) * (breite + 1)));
    for (let i = 0; i < breite; i++) {                      // Filter 0–4 der PNG-Norm (keiner, Sub, Up, Average, Paeth)
      const a = i >= bpp ? z[i - bpp] : 0, b = vor[i], c = i >= bpp ? vor[i - bpp] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      z[i] = (z[i] + [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][filter]) & 255;
    }
    for (let x = 0; x < w; x++) px.push([z[x * bpp], z[x * bpp + 1], z[x * bpp + 2]]);
    vor = z;
  }
  return px;
}
(async () => {
  const b = await H.start();
  const { ctx, page, log } = await H.seite(b, { viewport: { width: W, height: HH } });
  const h0 = await page.evaluate(() => { const h = document.getElementById('erster-hinweis'), q = h.getBoundingClientRect();
    return { hidden: h.hidden, text: h.textContent, l: q.left, t: q.top, r: q.right, u: q.bottom, farbe: getComputedStyle(h).color }; });
  const tempo = await H.rechteck(page, '#tempo');
  console.log('Hinweis', JSON.stringify(h0), 'Tempo', JSON.stringify(tempo));
  ok(!h0.hidden && h0.text.replace(/\u00a0/g, ' ') === 'Ziehen dreht · Rad zoomt · Klick öffnet', 'neue Stadt: Hinweis mit Maus-Text');
  ok(h0.u <= tempo.t - 7 && Math.abs((h0.l + h0.r) / 2 - (tempo.l + tempo.r) / 2) < 2, 'Hinweis mittig über dem Tempo');
  const bild = H.AUS + `breit_${W}x${HH}_0start.png`;
  await page.screenshot({ path: bild });
  // Kontrast: Hintergrund der Pille (Innenrand links, 3 px neben dem Rand) gegen die Textfarbe
  const shot = await page.screenshot({ clip: { x: Math.round(h0.l) + 3, y: Math.round(h0.t) + 3, width: 4, height: Math.round(h0.u - h0.t) - 6 } });
  const clip = H.AUS + 'hinweis_grund.png';
  require('fs').writeFileSync(clip, shot);
  let best = null;                                          // ungünstigster Pixel des Grunds gegen die Textfarbe (163, 163, 174)
  for (const px of pngPixel(shot)) { const k = kontrast([163, 163, 174], px); if (!best || k < best[3]) best = [...px, k]; }
  const [hr, hg, hb, k] = best;
  console.log('Hinweis: ungünstigster Grund', hr, hg, hb, 'Kontrast', k.toFixed(2));
  ok(k >= 4.5, 'Hinweis-Text ≥ 4,5:1 vor dem gemessenen Grund');
  // Echte Maus: Ziehen auf der Leinwand → Hinweis weg
  await page.mouse.move(W / 2, HH / 2); await page.mouse.down(); await page.mouse.move(W / 2 + 60, HH / 2, { steps: 6 }); await page.mouse.up();
  await page.waitForTimeout(700);
  ok(await page.evaluate(() => document.getElementById('erster-hinweis').hidden), 'Ziehen: Hinweis verschwindet');
  // Tab-Reihenfolge von vorn
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  const folge = [];
  for (let i = 0; i < 400; i++) {
    await page.keyboard.press('Tab');
    const f = await page.evaluate(() => { const e = document.activeElement; const s = getComputedStyle(e);
      return (e.id || (e.dataset && e.dataset.tempo !== undefined ? 'tempo' + e.dataset.tempo : e.className || e.tagName)) + (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) >= 2 ? '' : '(ohne Ring)'); });
    if (!folge.length || folge[folge.length - 1].split('×')[0] !== f) folge.push(f); else { const [n, z] = folge[folge.length - 1].split('×'); folge[folge.length - 1] = n + '×' + ((+z || 1) + 1); }
    if (f.startsWith('einst-knopf')) break;
  }
  console.log('Tab-Folge', folge.join(' → '));
  // Das Stadtbuch hat Hunderte Namen: ab dem letzten Knopf davor (Debug „5 Tage“) weiter
  await page.focus('[data-vorspulen="120"]');
  const ende = [];
  for (let i = 0; i < 3; i++) { await page.keyboard.press('Tab'); ende.push(await page.evaluate(() => document.activeElement.id || document.activeElement.tagName)); }
  await page.keyboard.press('Shift+Tab'); ende.push('⇧' + await page.evaluate(() => document.activeElement.id));
  console.log('Tab ab „5 Tage“:', ende.join(' → '));
  ok(ende[0] === 'hilfe-knopf' && ende[1] === 'einst-knopf', 'Tab: Hilfe direkt vor Einstellungen');
  await page.focus('#hilfe-knopf');
  const ring = await page.evaluate(() => { const s = getComputedStyle(document.getElementById('hilfe-knopf')); return s.outlineStyle + ' ' + s.outlineWidth + ' ' + s.outlineColor; });
  console.log('Fokusring Hilfe-Knopf:', ring);
  await page.screenshot({ path: H.AUS + `breit_${W}x${HH}_fokus.png`, clip: { x: W - 140, y: HH - 80, width: 140, height: 80 } });
  ok(!folge.some(f => f.includes('ohne Ring')), 'jeder Tab-Halt mit Fokusring (outline ≥ 2 px)');
  // Hilfe per Tastatur öffnen: Fokus auf hilfe-knopf, Enter
  await page.focus('#hilfe-knopf'); await page.keyboard.press('Enter'); await page.waitForTimeout(300);
  await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && a.effect.target.id === 'hilfe-dialog').map(a => a.finished)));
  const d1 = await page.evaluate(() => ({ offen: document.getElementById('hilfe-dialog').open, fokus: document.activeElement.id, titel: document.getElementById('hilfe-titel').textContent }));
  console.log('Hilfe per Enter', JSON.stringify(d1));
  ok(d1.offen && d1.fokus === 'hilfe-titel' && d1.titel === 'So liest du die Stadt', 'Enter öffnet die Hilfe, Fokus auf der Überschrift');
  await page.screenshot({ path: H.AUS + `breit_${W}x${HH}_1hilfe.png` });
  await page.keyboard.press('Tab');
  const t1 = await page.evaluate(() => ({ text: document.activeElement.textContent, im: !!document.activeElement.closest('#hilfe-dialog') }));
  ok(t1.im && t1.text === 'Schließen', 'Tab im Dialog: Schließen');
  await page.keyboard.press('Space');                     // Leertaste auf dem Knopf schließt, pausiert nicht
  await page.waitForTimeout(300);
  const d2 = await page.evaluate(() => ({ offen: document.getElementById('hilfe-dialog').open, fokus: document.activeElement.id }));
  ok(!d2.offen && d2.fokus === 'hilfe-knopf', 'Schließen-Knopf: zu, Fokus zurück auf „?“ (' + d2.fokus + ')');
  // Maus: Klick auf „?“, Escape
  await page.mouse.click(...await page.evaluate(() => { const q = document.getElementById('hilfe-knopf').getBoundingClientRect(); return [q.left + q.width / 2, q.top + q.height / 2]; }));
  await page.waitForTimeout(400);
  const tempoVor = await page.evaluate(() => __stadt.S && document.querySelector('#tempo [aria-pressed="true"]').dataset.tempo);
  await page.keyboard.press('Space');                     // Fokus auf der Überschrift: Leertaste pausiert nicht
  const tempoNach = await page.evaluate(() => document.querySelector('#tempo [aria-pressed="true"]').dataset.tempo);
  ok(tempoVor === tempoNach, 'Leertaste im Hilfe-Dialog ändert das Tempo nicht');
  await page.keyboard.press('Escape'); await page.waitForTimeout(300);
  const d3 = await page.evaluate(() => ({ offen: document.getElementById('hilfe-dialog').open, fokus: document.activeElement.id }));
  ok(!d3.offen && d3.fokus === 'hilfe-knopf', 'Escape: zu, Fokus zurück auf „?“');
  const dlg = await page.evaluate(() => { const d = document.getElementById('hilfe-dialog'); d.showModal(); const q = d.getBoundingClientRect(); const r = { h: q.height, w: q.width, sh: d.scrollHeight, ch: d.clientHeight }; d.close(); return r; });
  console.log('Dialog', JSON.stringify(dlg));
  console.log('Überlauf', JSON.stringify(await H.ueberlauf(page)));
  // Kein Hinweis nach Laden: speichern, ohne &neu neu laden
  await page.evaluate(() => __stadt.speichern());
  await page.goto(`${U.HOST}/stadt.html?debug`, { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await page.waitForTimeout(300);
  ok(await page.evaluate(() => document.getElementById('erster-hinweis').hidden), 'geladener Spielstand: kein Hinweis');
  await page.evaluate(() => localStorage.clear());
  console.log('Fehler:', log.join(' | ') || 'keine');
  // 12 s ohne Eingabe
  const ctx2 = await b.newContext({ viewport: { width: W, height: HH } });
  await ctx2.addInitScript(() => { document.addEventListener('DOMContentLoaded', () => { const h = document.getElementById('erster-hinweis'); globalThis.__hz = [];
    new MutationObserver(() => __hz.push([h.hidden ? 'zu' : 'auf', h.className, Math.round(performance.now())])).observe(h, { attributes: true }); }); });
  const p2 = await H.seite(b, { viewport: { width: W, height: HH } }, { warten: false, ctx: ctx2 });
  await p2.page.waitForFunction(() => document.getElementById('erster-hinweis').hidden, null, { timeout: 40000 });
  console.log('Hinweis ohne Eingabe (auf/weg/zu, ms):', JSON.stringify(await p2.page.evaluate(() => __hz)));
  await b.close();
})();
