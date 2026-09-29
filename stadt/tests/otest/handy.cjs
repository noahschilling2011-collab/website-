// Handy: Gebäude antippen (echter Touch per CDP), Karte, „Zeigen“ tippen (klappt ein und fährt), Aufklappen, Einklappen, neue Karte
// W, H, RED=1 (reduzierte Bewegung), DATEI (stadt.html), TAG (Bildname)
const H = require('./h.cjs');
const W = +(process.env.W || 400), HH = +(process.env.H || 820), RED = process.env.RED === '1', datei = process.env.DATEI || 'stadt.html';
const tag = (process.env.TAG || 'neu') + `_${W}x${HH}${RED ? '_red' : ''}`;
const fertig = (page) => page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && ['karte', 'karte-inhalt'].includes(a.effect.target.id)).map(a => a.finished.catch(() => 0))));
const ok = (b, t) => console.log((b ? 'OK  ' : 'FEHLER ') + t);
(async () => {
  const b = await H.start();
  const { ctx, page, log } = await H.seite(b, { viewport: { width: W, height: HH }, hasTouch: true, isMobile: true, deviceScaleFactor: 1,
    reducedMotion: RED ? 'reduce' : 'no-preference' }, { datei });
  const hinweis = await page.evaluate(() => { const h = document.getElementById('erster-hinweis'); const q = h.getBoundingClientRect();
    return { hidden: h.hidden, text: h.textContent, l: q.left | 0, r: q.right | 0, t: q.top | 0, u: q.bottom | 0 }; });
  console.log('Hinweis beim Start', JSON.stringify(hinweis), 'Tempo', JSON.stringify(await H.rechteck(page, '#tempo')), 'Spalte', JSON.stringify(await H.rechteck(page, '#rechts')));
  await page.screenshot({ path: H.AUS + `handy_${tag}_0start.png` });
  const alle = await H.lagen(page);
  const kand = alle.filter(l => l.x > 60 && l.x < W - 60 && l.y > HH * 0.5 && l.y < HH * 0.78);
  kand.sort((a, c) => Math.abs(a.x - W / 2) - Math.abs(c.x - W / 2));
  let ziel = null;
  for (const l of kand.slice(0, 20)) {
    await H.tippen(ctx, page, l.x, l.y); await page.waitForTimeout(500);
    const haus = await page.evaluate(() => !document.getElementById('karte').hidden && !!document.querySelector('#karte .typ-marke') && !document.getElementById('karte-zeigen').hidden);
    if (haus) { ziel = l; break; }
    await page.evaluate(() => { if (!document.getElementById('karte').hidden) document.getElementById('karte-zu').click(); }); await page.waitForTimeout(200);
  }
  if (!ziel) { console.log('kein Gebäude getroffen'); await b.close(); return; }
  const hinweisWeg = await page.evaluate(() => document.getElementById('erster-hinweis').hidden || document.getElementById('erster-hinweis').classList.contains('weg'));
  ok(hinweisWeg, 'Hinweis ist nach dem ersten Tippen weg');
  const karte1 = await H.rechteck(page, '#karte'), titel = await page.evaluate(() => document.querySelector('#karte h2').textContent);
  const bild = H.AUS + `handy_${tag}_1karte.png`;
  await page.screenshot({ path: bild });
  const flaeche = (k) => Math.max(0, k.w) * Math.max(0, k.h) / (W * HH);
  console.log('Karte', titel, JSON.stringify(karte1), 'deckt', (100 * flaeche(karte1)).toFixed(0) + ' % des Bildes');
  const vor = (await H.lagen(page)).find(l => l.b === ziel.b);
  console.log('Gebäude vor Zeigen', vor.x | 0, vor.y | 0, 'unter der Karte:', await page.evaluate(([x, y]) => document.elementFromPoint(x, y) !== document.getElementById('szene'), [vor.x, vor.y]));
  const knopf = await H.rechteck(page, '#karte-zeigen'), klapp = await H.rechteck(page, '#karte-klappen'), zuK = await H.rechteck(page, '#karte-zu');
  console.log('Knöpfe: Zeigen', JSON.stringify(knopf), 'Klappen', JSON.stringify(klapp), 'X', JSON.stringify(zuK));
  ok(klapp && klapp.h >= 32 && klapp.w >= 32, 'Klappen-Knopf mindestens 32 × 32');
  // Zeigen antippen
  await page.evaluate(() => { const c = __stadt.G.controls; globalThis.__spur = []; const t0 = performance.now();
    const f = () => { const k = document.getElementById('karte').getBoundingClientRect(); __spur.push([Math.round(performance.now() - t0), +c.target.x.toFixed(3), +c.target.z.toFixed(3), Math.round(k.height)]);
      if (performance.now() - t0 < 1200) requestAnimationFrame(f); }; requestAnimationFrame(f); });
  await H.tippen(ctx, page, knopf.l + knopf.w / 2, knopf.t + knopf.h / 2);
  const gleich = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), anim: document.getAnimations().filter(a => a.constructor.name === 'Animation').length,
    expanded: document.getElementById('karte-klappen').getAttribute('aria-expanded') }));
  console.log('direkt nach Zeigen', JSON.stringify(gleich));
  ok(gleich.ein && gleich.expanded === 'false', 'Zeigen klappt die Karte ein (aria-expanded false)');
  ok(RED ? gleich.anim === 0 : gleich.anim >= 2, RED ? 'reduziert: kein Übergang' : 'Übergang läuft (Web Animations)');
  for (let i = 0; i < 3; i++) { await page.screenshot({ path: H.AUS + `handy_${tag}_2fahrt${i}.png` }); }
  await fertig(page); await page.waitForTimeout(900);
  const spur = await page.evaluate(() => __spur);
  const hoehen = spur.map(s => s[3]), bew = spur.filter((p, i) => i && (p[1] !== spur[i - 1][1] || p[2] !== spur[i - 1][2]));
  console.log('Kartenhöhe je Bild', JSON.stringify(hoehen.slice(0, 30)), 'Kamera bewegt von', bew.length ? bew[0][0] : '-', 'bis', bew.length ? bew[bew.length - 1][0] : '-', 'ms,', bew.length, 'Bilder');
  const karte2 = await H.rechteck(page, '#karte'), zahlen = await H.rechteck(page, '#kennzahlen');
  const nach = (await H.lagen(page, 0.4)).find(l => l.b === (ziel ? ziel.b : -1));
  const rahmen = await page.evaluate(() => { const S = __stadt.S(); return null; });
  console.log('eingeklappt', JSON.stringify(karte2), 'deckt', (100 * flaeche(karte2)).toFixed(1) + ' %', 'Gebäude jetzt', nach.x | 0, nach.y | 0, 'frei zwischen', zahlen.u, 'und', karte2.t);
  ok(karte2.h <= 46, 'eingeklappt nur die Kopfleiste (' + karte2.h + ' px)');
  const frei = await page.evaluate(([x, y]) => document.elementFromPoint(x, y) === document.getElementById('szene'), [nach.x, nach.y]);
  ok(frei, 'Gebäude liegt in der freien Fläche (Mitte nicht unter einem Panel)');
  const kopf = await page.evaluate(() => ({ titel: getComputedStyle(document.getElementById('karte-kopf-titel')).visibility, text: document.getElementById('karte-kopf-titel').textContent,
    inhalt: getComputedStyle(document.getElementById('karte-inhalt')).visibility, zeigen: !document.getElementById('karte-zeigen').hidden, x: !document.getElementById('karte-zu').hidden,
    fokus: document.activeElement && document.activeElement.id }));
  console.log('Kopfleiste', JSON.stringify(kopf));
  ok(kopf.titel === 'visible' && kopf.text === titel && kopf.inhalt === 'hidden' && kopf.zeigen && kopf.x, 'eingeklappt: Titel, Zeigen, X sichtbar, Inhalt verborgen');
  await page.screenshot({ path: H.AUS + `handy_${tag}_3nach.png` });
  // Aufklappen per Tippen
  const k2 = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, k2.l + k2.w / 2, k2.t + k2.h / 2);
  await page.waitForTimeout(50); await fertig(page); await page.waitForTimeout(100);
  const auf = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), exp: document.getElementById('karte-klappen').getAttribute('aria-expanded'),
    inhalt: getComputedStyle(document.getElementById('karte-inhalt')).visibility, op: getComputedStyle(document.getElementById('karte-inhalt')).opacity }));
  const karte3 = await H.rechteck(page, '#karte');
  console.log('aufgeklappt', JSON.stringify(auf), JSON.stringify(karte3));
  ok(!auf.ein && auf.exp === 'true' && auf.inhalt === 'visible' && auf.op === '1' && Math.abs(karte3.h - karte1.h) <= 2, 'Aufklappen: wieder volle Karte');
  await page.screenshot({ path: H.AUS + `handy_${tag}_4auf.png` });
  // Einklappen per Tippen, dann anderes Gebäude antippen: neue Karte ist offen
  const k3 = await H.rechteck(page, '#karte-klappen');
  await H.tippen(ctx, page, k3.l + k3.w / 2, k3.t + k3.h / 2);
  await page.waitForTimeout(50); await fertig(page); await page.waitForTimeout(100);
  ok(await page.evaluate(() => document.getElementById('karte').classList.contains('eingeklappt')), 'Einklappen per Knopf');
  const cam0 = await page.evaluate(() => __stadt.G.controls.target.toArray().map(v => +v.toFixed(4)).join(','));
  await page.waitForTimeout(600);
  const cam1 = await page.evaluate(() => __stadt.G.controls.target.toArray().map(v => +v.toFixed(4)).join(','));
  ok(cam0 === cam1, 'Einklappen bewegt die Kamera nicht');
  const alle2 = (await H.lagen(page)).filter(l => l.b !== ziel.b && l.x > 40 && l.x < W - 40 && l.y > 40 && l.y < HH - 40);
  let neu = false;
  for (const l of alle2.sort((a, c) => Math.hypot(a.x - W / 2, a.y - HH / 2) - Math.hypot(c.x - W / 2, c.y - HH / 2)).slice(0, 25)) {
    if (!await page.evaluate(([x, y]) => document.elementFromPoint(x, y) === document.getElementById('szene'), [l.x, l.y])) continue;
    await page.evaluate(() => { const h = document.querySelector('#karte h2'); if (h) h.__alt = true; });
    await H.tippen(ctx, page, l.x, l.y); await page.waitForTimeout(400);
    if (await page.evaluate(() => { const h = document.querySelector('#karte h2'); return !document.getElementById('karte').hidden && h && !h.__alt; })) { neu = true; break; }
  }
  const neuStand = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), exp: document.getElementById('karte-klappen').getAttribute('aria-expanded') }));
  ok(neu && !neuStand.ein && neuStand.exp === 'true', 'neue Karte öffnet aufgeklappt');
  console.log('Überlauf', JSON.stringify(await H.ueberlauf(page)));
  console.log('Fehler:', log.join(' | ') || 'keine');
  await b.close();
})();
