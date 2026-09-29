// Breiten 360 / 400 / 768 / 1280 (und quer 844 × 390): Hinweis, Hilfe-Dialog, seitliches Überlaufen, Knöpfe oben/unten rechts
const H = require('./h.cjs');
const ok = (b, t) => console.log((b ? 'OK  ' : 'FEHLER ') + t);
const FORMATE = [[360, 740, true], [400, 820, true], [768, 1024, true], [844, 390, true], [1280, 800, false]];
(async () => {
  const b = await H.start();
  for (const [W, HH, touch] of FORMATE) {
    const { ctx, page, log } = await H.seite(b, { viewport: { width: W, height: HH }, hasTouch: touch, isMobile: touch, deviceScaleFactor: 1 }, { warten: false });
    await page.evaluate(() => __stadt.setzeTempo(0)); await H.zu(page); await page.waitForTimeout(300); await H.zu(page);
    const hin = await page.evaluate(() => { const h = document.getElementById('erster-hinweis'), q = h.getBoundingClientRect(); return { an: !h.hidden, text: h.textContent.replace(/ /g, ' '), l: q.left | 0, r: q.right | 0, t: q.top | 0, u: q.bottom | 0, hoehe: Math.round(q.height) }; });
    const knoepfe = await page.evaluate(() => ['hilfe-knopf', 'einst-knopf', 'tempo', 'kennzahlen'].map(id => { const q = document.getElementById(id).getBoundingClientRect(); return id + ' ' + [q.left, q.top, q.right, q.bottom].map(Math.round).join(','); }).join(' | '));
    console.log(`== ${W}×${HH}`, 'Hinweis', JSON.stringify(hin), '|', knoepfe);
    const ueber = await H.ueberlauf(page);
    ok(ueber.scroll <= W && !ueber.raus.length, `${W}: kein seitliches Überlaufen ${JSON.stringify(ueber)}`);
    // Überschneidungen: Hilfe-Knopf mit Tempo, Kennzahlen, Einstellungen
    const schnitt = await page.evaluate(() => { const r = (id) => document.getElementById(id).getBoundingClientRect(), a = r('hilfe-knopf');
      return ['tempo', 'kennzahlen', 'einst-knopf', 'rechts'].filter(id => { const q = r(id); return q.width && a.left < q.right && a.right > q.left && a.top < q.bottom && a.bottom > q.top; }); });
    ok(!schnitt.length, `${W}: Hilfe-Knopf überdeckt nichts ${schnitt.join(',')}`);
    await page.screenshot({ path: H.AUS + `breiten_${W}x${HH}_0.png` });
    const q = await H.rechteck(page, '#hilfe-knopf');
    if (touch) await H.tippen(ctx, page, q.l + q.w / 2, q.t + q.h / 2); else await page.mouse.click(q.l + q.w / 2, q.t + q.h / 2);
    await page.waitForTimeout(200);
    await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && a.effect.target.id === 'hilfe-dialog').map(a => a.finished)));
    const d = await page.evaluate(() => { const e = document.getElementById('hilfe-dialog'), q = e.getBoundingClientRect(); return { offen: e.open, l: q.left | 0, r: q.right | 0, t: q.top | 0, u: q.bottom | 0, sh: e.scrollHeight, ch: e.clientHeight,
      spalten: getComputedStyle(document.querySelector('.hilfe-spalten')).gridTemplateColumns }; });
    console.log('Dialog', JSON.stringify(d));
    ok(d.offen && d.l >= 0 && d.r <= W && d.t >= 0 && d.u <= HH, `${W}: Hilfe offen und ganz im Bild`);
    await page.screenshot({ path: H.AUS + `breiten_${W}x${HH}_hilfe.png` });
    if (d.sh > d.ch) { await page.evaluate(() => { const e = document.getElementById('hilfe-dialog'); e.scrollTop = e.scrollHeight; }); await page.screenshot({ path: H.AUS + `breiten_${W}x${HH}_hilfe_unten.png` }); }
    await page.keyboard.press('Escape'); await page.waitForTimeout(200);
    ok(await page.evaluate(() => !document.getElementById('hilfe-dialog').open && document.activeElement.id === 'hilfe-knopf'), `${W}: Escape schließt, Fokus zurück`);
    console.log('Fehler:', log.join(' | ') || 'keine');
    await ctx.close();
  }
  await b.close();
})();
