// Befunde der Prüfer nachgemessen (400 × 820 u. a.): Fokusring eingeklappt, Abbruch laufender Übergänge, Wechsel ins breite
// Stand vor den Befund-Korrekturen (Bauer, Paket O): DATEI=fix/stadt_vorfix.html
// Layout, Legende (Text, reduzierte Bewegung), Dialog bei 320 px. DATEI (stadt.html), RED=1
const H = require('./h.cjs');
const W = +(process.env.W || 400), HH = +(process.env.H || 820), datei = process.env.DATEI || 'stadt.html', vor = datei.replace('.html', '').replace('fix/', '') + '_';
const ok = (b, t) => console.log((b ? 'OK  ' : 'FEHLER ') + t);
const fertig = (page) => page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && /karte/.test(a.effect.target.id)).map(a => a.finished.catch(() => 0))));
async function hausOeffnen(ctx, page, ohne = -1) {
  const alle = (await H.lagen(page)).filter(l => l.b !== ohne && l.x > 50 && l.x < W - 50 && l.y > 180 && l.y < HH - 120);
  alle.sort((a, c) => Math.hypot(a.x - W / 2, a.y - HH * 0.6) - Math.hypot(c.x - W / 2, c.y - HH * 0.6));
  for (const l of alle.slice(0, 30)) {
    if (!await page.evaluate(([x, y]) => document.elementFromPoint(x, y) === document.getElementById('szene'), [l.x, l.y])) continue;
    await page.evaluate(() => { const h = document.querySelector('#karte h2'); if (h) h.__alt = true; });
    await H.tippen(ctx, page, l.x, l.y); await page.waitForTimeout(350);
    if (await page.evaluate(() => { const h = document.querySelector('#karte h2'); return !document.getElementById('karte').hidden && h && !h.__alt && !!document.querySelector('#karte .typ-marke'); })) return l;
    // Version 10 (Etappe 2): In der Teststadt steht vor dem ersten Gebäude jetzt eine Figur; das Tippen öffnet ihre Personenkarte (richtig so),
    // und die Karte deckt am Handy die nächsten Ziele zu. Eine Karte, die keine Hauskarte ist, wird darum vor dem nächsten Versuch geschlossen
    if (await page.evaluate(() => { const k = document.getElementById('karte'); if (k.hidden) return false; document.getElementById('karte-zu').click(); return true; })) {
      await page.waitForFunction(() => document.getElementById('karte').hidden, null, { timeout: 5000 }).catch(() => {}); await page.waitForTimeout(150);
    }
  }
  return null;
}
(async () => {
  const b = await H.start();
  // --- Handy: Fokusring eingeklappt ---
  const { ctx, page, log } = await H.seite(b, { viewport: { width: W, height: HH }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 }, { datei });
  const l1 = await hausOeffnen(ctx, page);
  ok(!!l1, 'Hauskarte per Tippen offen');
  const voll = await H.rechteck(page, '#karte');
  let q = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, q.l + q.w / 2, q.t + q.h / 2); await page.waitForTimeout(40); await fertig(page); await page.waitForTimeout(80);
  const zu = await H.rechteck(page, '#karte');
  console.log('Karte voll', JSON.stringify(voll), 'eingeklappt', JSON.stringify(zu), 'deckt', (100 * zu.w * zu.h / (W * HH)).toFixed(1) + ' %');
  // Tastatur-Fokus (für :focus-visible): Fokus vor den Kopf, dann Tab bis Klappen bzw. Zeigen
  const ringe = {};
  for (const id of ['karte-zeigen', 'karte-klappen', 'karte-zu']) {
    await page.evaluate(() => document.getElementById('karte-kopf-titel').setAttribute('tabindex', '-1'));
    await page.focus('#karte-kopf-titel');
    for (let i = 0; i < 5; i++) { await page.keyboard.press('Tab'); if (await page.evaluate((id) => document.activeElement.id === id, id)) break; }
    const r = await page.evaluate(() => { const e = document.activeElement, s = getComputedStyle(e), q = e.getBoundingClientRect(), k = document.getElementById('karte'), kq = k.getBoundingClientRect();
      const off = parseFloat(s.outlineOffset), bw = parseFloat(s.outlineWidth);
      return { id: e.id, fv: e.matches(':focus-visible'), knopf: [q.top, q.bottom], ring: [q.top - off - bw, q.bottom + off + bw], innen: [kq.top + k.clientTop, kq.top + k.clientTop + k.clientHeight] }; });
    ringe[id] = r;
    ok(r.id === id && r.fv && r.ring[0] >= r.innen[0] && r.ring[1] <= r.innen[1], `eingeklappt: Fokusring von ${id} ganz sichtbar ${JSON.stringify(r)}`);
    await page.screenshot({ path: H.AUS + vor + `ring_${id}_${W}.png`, clip: { x: 0, y: zu.t - 10, width: W, height: zu.h + 20 } });
  }
  await page.evaluate(() => document.getElementById('karte-kopf-titel').removeAttribute('tabindex'));
  // --- Abbruch: einklappen, nach 60 ms neue Karte öffnen (Tippen auf ein anderes Gebäude) ---
  q = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, q.l + q.w / 2, q.t + q.h / 2); await page.waitForTimeout(40); await fertig(page); await page.waitForTimeout(80);   // wieder auf
  await page.evaluate(() => { globalThis.__hoehen = []; const k = document.getElementById('karte'), t0 = globalThis.__t0 = performance.now();
    const f = () => { __hoehen.push([Math.round(performance.now() - t0), Math.round(k.getBoundingClientRect().height), k.classList.contains('eingeklappt') ? 1 : 0,
      +getComputedStyle(document.getElementById('karte-inhalt')).opacity]); if (performance.now() - t0 < 900) requestAnimationFrame(f); }; requestAnimationFrame(f); });
  q = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, q.l + q.w / 2, q.t + q.h / 2);   // einklappen, Übergang läuft 250 ms
  await page.waitForTimeout(60);
  const laufen = await page.evaluate(() => document.getAnimations().filter(a => a.effect && a.effect.target && /karte/.test(a.effect.target.id) && a.playState === 'running').length);
  // neue Karte über die Such-Logik wie ein Klick (echtes Tippen braucht länger als der Übergang): Hauptfigur-/Hausknopf nachbilden
  const zweit = await page.evaluate((b0) => { const z = b0 === 40 ? 41 : 40;
    globalThis.__tOffen = performance.now() - __t0;   // ab hier zählt „danach“ (das Tippen kann in langsamer Umgebung lange dauern)
    const k = document.createElement('button'); k.className = 'haus'; k.dataset.b = String(z); document.body.appendChild(k); k.click(); k.remove(); return z; }, l1 ? l1.b : -1);
  const messen = () => page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'),
    anim: document.getAnimations().filter(a => a.constructor.name === 'Animation' && a.playState === 'running').map(a => a.effect.target.id).join(','),
    maxH: getComputedStyle(document.getElementById('karte')).maxHeight, h: Math.round(document.getElementById('karte').getBoundingClientRect().height),
    op: getComputedStyle(document.getElementById('karte-inhalt')).opacity, titelOp: getComputedStyle(document.getElementById('karte-kopf-titel')).opacity }));
  const direkt = await messen();
  await page.waitForTimeout(100); const spaeter = await messen();
  console.log('direkt nach dem Öffnen', JSON.stringify(direkt), '100 ms später', JSON.stringify(spaeter));
  await page.waitForTimeout(700);
  const hoehen = await page.evaluate(() => __hoehen);
  console.log('Übergänge beim Öffnen der neuen Karte:', laufen, 'laufend vorher; danach', JSON.stringify(direkt), 'Gebäude', zweit);
  console.log('Höhe je Bild [ms, px, eingeklappt, Deckkraft Inhalt]', JSON.stringify(hoehen.slice(0, 40)));
  const tOffen = await page.evaluate(() => __tOffen);
  const nachOeffnen = hoehen.filter(h => h[2] === 0 && h[0] > tOffen + 80);
  const endH = (await H.rechteck(page, '#karte')).h;
  ok(laufen >= 2 && !direkt.ein && !direkt.anim && !spaeter.anim && direkt.op === '1' && spaeter.op === '1' && spaeter.h === endH, 'neue Karte während des Einklappens: Übergang abgebrochen, Karte gleich offen und deckend');
  ok(nachOeffnen.every(h => h[3] === 1 && Math.abs(h[1] - endH) <= 2), `danach kein Schrumpfen und Verblassen mehr (Endhöhe ${endH})`);
  // --- Wechsel ins breite Layout ---
  q = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, q.l + q.w / 2, q.t + q.h / 2); await page.waitForTimeout(40); await fertig(page);
  ok(await page.evaluate(() => document.getElementById('karte').classList.contains('eingeklappt')), 'eingeklappt vor dem Wechsel');
  // Medienabfragen melden ihre Änderung erst beim nächsten Bild (vor den requestAnimationFrame-Rückrufen); unter Last kommt das
  // später als 300 ms. Deshalb auf zwei Bilder warten statt nur auf die Zeit
  const zweiBilder = () => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  await page.setViewportSize({ width: 1280, height: 800 }); await page.waitForTimeout(300); await zweiBilder();
  const breit = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), exp: document.getElementById('karte-klappen').getAttribute('aria-expanded'),
    h: Math.round(document.getElementById('karte').getBoundingClientRect().height), inhalt: getComputedStyle(document.getElementById('karte-inhalt')).visibility }));
  ok(!breit.ein && breit.exp === 'true' && breit.inhalt === 'visible', 'breit: Karte aufgeklappt, aria-expanded true ' + JSON.stringify(breit));
  await page.setViewportSize({ width: W, height: HH }); await page.waitForTimeout(300); await zweiBilder();
  const wieder = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), exp: document.getElementById('karte-klappen').getAttribute('aria-expanded') }));
  ok(!wieder.ein && wieder.exp === 'true', 'zurück am Handy: aufgeklappt, eindeutig');
  // --- Legende ---
  const leg = await page.evaluate(() => [...document.querySelectorAll('#hilfe-dialog .legende li')].map(li => li.innerText.replace(/\s+/g, ' ').trim()));
  console.log('Legende:\n  ' + leg.join('\n  '));
  ok(leg.some(t => /Offene Läden leuchten von 17 bis 22 Uhr/.test(t)) && !leg.some(t => /Licht in den Fenstern/.test(t)), 'Legende: Licht nur für Wohnhäuser, Läden eigens');
  console.log('Fehler:', log.join(' | ') || 'keine');
  await ctx.close();
  // --- Reduziert: Ringe ohne Bewegungswörter; 320 px: kein seitliches Scrollen im Dialog ---
  for (const [w, h, red] of [[400, 820, true], [400, 820, false], [320, 640, false], [360, 740, false], [1280, 800, false]]) {
    const s = await H.seite(b, { viewport: { width: w, height: h }, reducedMotion: red ? 'reduce' : 'no-preference' }, { datei, warten: false });
    const r = await s.page.evaluate(() => { const d = document.getElementById('hilfe-dialog'); d.showModal(); const q = d.getBoundingClientRect();
      const ringe = [...d.querySelectorAll('.legende li')].map(li => li.innerText.replace(/\s+/g, ' ')).filter(t => /Ring/.test(t));
      const r = { sw: d.scrollWidth, cw: d.clientWidth, sh: d.scrollHeight, ch: d.clientHeight, h: Math.round(q.height), w: Math.round(q.width), ringe }; return r; });
    await s.page.screenshot({ path: H.AUS + vor + `hilfe_${w}x${h}${red ? '_red' : ''}.png` });
    console.log(`${w}×${h}${red ? ' reduziert' : ''}:`, JSON.stringify(r));
    ok(r.sw <= r.cw, `${w}: Dialog ohne seitliches Scrollen`);
    ok(red ? r.ringe.every(t => !/weiter wird|zusammenzieht/.test(t)) : r.ringe.some(t => /weiter wird/.test(t)) && r.ringe.some(t => /zusammenzieht/.test(t)), red ? 'reduziert: Ringe ohne Bewegungswörter' : 'Ringe mit Bewegung beschrieben');
    if (w === 1280) ok(r.sh <= r.ch, '1280 × 800: Hilfe ohne Scrollen (' + r.h + ' px)');
    if (s.log.length) console.log('Fehler:', s.log.join(' | '));
    await s.ctx.close();
  }
  await b.close();
})();
