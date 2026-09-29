// Schmal mit Tastatur (400 × 820, Maus): Karte per Mausklick öffnen, mit Tab zum Einklappen, Enter, Fokusring, Tab-Folge eingeklappt
const H = require('./h.cjs');
const W = +(process.env.W || 400), HH = +(process.env.H || 820);
const ok = (b, t) => console.log((b ? 'OK  ' : 'FEHLER ') + t);
(async () => {
  const b = await H.start();
  const { ctx, page, log } = await H.seite(b, { viewport: { width: W, height: HH } });
  const alle = (await H.lagen(page)).filter(l => l.x > 60 && l.x < W - 60 && l.y > HH * 0.45 && l.y < HH * 0.75);
  let offen = false;
  for (const l of alle.slice(0, 20)) {
    await page.mouse.click(l.x, l.y); await page.waitForTimeout(400);
    if (await page.evaluate(() => !document.getElementById('karte').hidden && !document.getElementById('karte-zeigen').hidden)) { offen = true; break; }
    await page.keyboard.press('Escape'); await page.waitForTimeout(150);
  }
  ok(offen, 'Hauskarte per Mausklick offen');
  // Fokus liegt auf der Überschrift; Shift+Tab rückwärts in den Kopf
  const folge = [];
  for (let i = 0; i < 4; i++) { await page.keyboard.press('Shift+Tab'); folge.push(await page.evaluate(() => document.activeElement.id || document.activeElement.className)); }
  console.log('Shift+Tab ab Überschrift:', folge.join(' ← '));
  await page.focus('#karte-klappen'); await page.keyboard.press('Enter');
  await page.waitForTimeout(50);
  await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && /karte/.test(a.effect.target.id)).map(a => a.finished.catch(() => 0))));
  const st = await page.evaluate(() => ({ ein: document.getElementById('karte').classList.contains('eingeklappt'), fokus: document.activeElement.id,
    ring: getComputedStyle(document.activeElement).outlineStyle + ' ' + getComputedStyle(document.activeElement).outlineWidth, fv: document.activeElement.matches(':focus-visible') }));
  console.log('nach Enter', JSON.stringify(st));
  ok(st.ein && st.fokus === 'karte-klappen' && st.fv && st.ring.startsWith('solid 2px'), 'Enter klappt ein, Fokus bleibt mit Ring auf dem Knopf');
  const k = await H.rechteck(page, '#karte');
  await page.screenshot({ path: H.AUS + `tastatur_${W}_ein.png`, clip: { x: 0, y: k.t - 12, width: W, height: k.h + 24 } });
  const f2 = [];
  for (let i = 0; i < 4; i++) { await page.keyboard.press('Tab'); f2.push(await page.evaluate(() => document.activeElement.id || document.activeElement.className || document.activeElement.tagName)); }
  console.log('Tab eingeklappt ab Klappen:', f2.join(' → '));
  ok(!f2.some(x => /name|haus/.test(x)), 'eingeklappt: kein Tab-Halt im verborgenen Inhalt');
  await page.focus('#karte-klappen'); await page.keyboard.press('Space');
  await page.waitForTimeout(50);
  await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.effect && a.effect.target && /karte/.test(a.effect.target.id)).map(a => a.finished.catch(() => 0))));
  ok(await page.evaluate(() => !document.getElementById('karte').classList.contains('eingeklappt')), 'Leertaste klappt wieder auf');
  console.log('Fehler:', log.join(' | ') || 'keine');
  await b.close();
})();
