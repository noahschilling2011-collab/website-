// Phase-3-Test: Hausklick → Bewohner, Personenkarte, Namen durchklicken, Zurück, Enkel über das Stadtbuch finden
const U = require('./umgebung.cjs');
const { chromium } = U;
const OUT = U.ordner('bilder_p3');   // Bilder nach tests/ausgabe/ (per .gitignore ausgeschlossen)
const url = process.argv[2] || U.HOST + '/stadt.html?debug&tage=400&seed=2&neu';
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  await page.goto(url);
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await page.evaluate(() => __stadt.setzeTempo(0));
  await page.waitForTimeout(500);
  // Hinweise zur Nachfolge (Hauptfigur weg) schließen, sonst liegen sie über dem Klickpunkt
  // Verluste als erledigt markieren, sonst öffnet der KI-Takt den Dialog später erneut über der Karte (den Dialog prüft p4test)
  const zu = () => page.evaluate(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
    for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
  await zu(); await page.waitForTimeout(500); await zu();

  // 1. Ein Wohnhaus anklicken: Bildschirmposition aus der Instanz-Matrix
  const punkt = await page.evaluate(() => {
    const { G } = __stadt, m = G.M.haus, M4 = new G.THREE.Matrix4(), v = new G.THREE.Vector3();
    const c = G.renderer.domElement.getBoundingClientRect();
    for (let i = Math.floor(m.count / 2); i < m.count; i++) {
      m.getMatrixAt(i, M4); v.setFromMatrixPosition(M4); v.project(G.camera);
      const x = (v.x + 1) / 2 * c.width + c.left, y = (1 - v.y) / 2 * c.height + c.top;
      if (x > 300 && x < 850 && y > 250 && y < 650) return { x, y };
    }
    return null;
  });
  ok(punkt, 'Wohnhaus auf dem Bildschirm gefunden ' + JSON.stringify(punkt));
  // Figuren dürfen den Klick nicht abfangen: kurz alle ausblenden (Test gilt dem Haus)
  await page.mouse.click(punkt.x, punkt.y);
  await page.waitForTimeout(300);
  const haus = await page.evaluate(() => ({ offen: !document.getElementById('karte').hidden, titel: document.querySelector('#karte h2')?.textContent,
    h3: [...document.querySelectorAll('#karte h3')].map(e => e.textContent), namen: document.querySelectorAll('#karte button.name').length }));
  console.log('     Hauskarte:', JSON.stringify(haus));
  ok(haus.offen && haus.titel, 'Klick öffnet eine Karte');
  await page.screenshot({ path: OUT + 'p3_haus.png' });

  // 2. Wenn es eine Personenkarte war (Figur getroffen) oder ein Haus: bis zu einer Person durchklicken
  if (haus.namen) {
    await zu();
    await page.click('#karte button.name');
    await page.waitForTimeout(300);
  }
  const person = await page.evaluate(() => ({ titel: document.querySelector('#karte h2')?.textContent,
    h3: [...document.querySelectorAll('#karte h3')].map(e => e.textContent), balken: document.querySelectorAll('#karte .balken').length,
    zurueck: !document.getElementById('karte-zurueck').hidden }));
  console.log('     Personenkarte:', JSON.stringify(person));
  ok(person.h3.includes('Charakter') && person.h3.includes('Lebenslauf') && person.h3.includes('Familie'), 'Personenkarte hat Charakter, Lebenslauf, Familie');
  ok(person.balken >= 5, 'Charakterbalken da');
  await page.screenshot({ path: OUT + 'p3_person.png' });
  if (person.zurueck) {
    await page.click('#karte-zurueck'); await page.waitForTimeout(200);
    const t = await page.evaluate(() => document.querySelector('#karte h2')?.textContent);
    ok(t === haus.titel, 'Zurück führt zur Hauskarte (' + t + ')');
  }
  // Wohnhaus-Karte über „wohnt an …“ in der Personenkarte
  await zu();
  await page.click('#karte button.name'); await page.waitForTimeout(200);
  if (await page.$('#karte button.haus:not([data-b=""])')) {
    const knoepfe = await page.$$('#karte button.haus');
    await knoepfe[knoepfe.length - 1].click(); await page.waitForTimeout(200);
    const w = await page.evaluate(() => ({ titel: document.querySelector('#karte h2')?.textContent, h3: document.querySelector('#karte h3')?.textContent,
      zeilen: [...document.querySelectorAll('#karte .personenliste li')].slice(0, 4).map(l => l.textContent) }));
    console.log('     Wohnhaus:', JSON.stringify(w));
    ok(w.h3 && w.h3.startsWith('Hier wohnen'), 'Wohnhaus-Karte listet Bewohner');
    await page.screenshot({ path: OUT + 'p3_wohnhaus.png' });
  }
  await page.keyboard.press('Escape'); await page.waitForTimeout(200);
  ok(await page.evaluate(() => document.getElementById('karte').hidden), 'Escape schließt die Karte');

  // 3. Enkel finden wie Noah: im Stadtbuch „Die Großeltern … freuen sich“ suchen, Großelternteil anklicken
  const t0 = Date.now();
  const gefunden = await page.evaluate(() => {
    for (const li of document.querySelectorAll('#buch-liste li')) {
      if (!li.textContent.includes('Großeltern')) continue;
      const knoepfe = [...li.querySelectorAll('button.name')];
      const g = knoepfe[knoepfe.length - 1];            // der letzte Name ist ein Großelternteil
      if (g) { g.scrollIntoView(); return { text: li.textContent.slice(0, 160), name: g.textContent, p: g.dataset.p }; }
    }
    return null;
  });
  ok(gefunden, 'Geburt mit Großeltern im Stadtbuch: ' + (gefunden && gefunden.text));
  if (gefunden) {
    await page.click(`#buch-liste button.name[data-p="${gefunden.p}"]`);
    await page.waitForTimeout(300);
    const enkel = await page.evaluate(() => {
      const dt = [...document.querySelectorAll('#karte .familie dt')].find(d => d.textContent === 'Enkel');
      return dt ? dt.nextElementSibling.textContent : null;
    });
    ok(enkel && enkel !== '–', `Karte von ${gefunden.name} zeigt Enkel: ${enkel} (${Date.now() - t0} ms)`);
    await page.screenshot({ path: OUT + 'p3_enkel.png' });
  }

  // 4. Figuren: laufen um 8 Uhr welche, und trifft ein Klick darauf eine Person?
  await page.keyboard.press('Escape');
  await page.evaluate(() => { const a = __stadt; while (a.S().stunde !== 8) a.schritt(); a.nachSchritten(); a.setzeTempo(20); });
  await page.waitForTimeout(1000);                     // ~20 Spielminuten laufen lassen, dann anhalten
  await page.evaluate(() => __stadt.setzeTempo(0));
  await page.waitForTimeout(300);
  const fig = await page.evaluate(() => {
    const { G } = __stadt, m = G.figMesh, M4 = new G.THREE.Matrix4(), v = new G.THREE.Vector3(), c = G.renderer.domElement.getBoundingClientRect();
    // Nur eine Figur, die nicht hinter einem Gebäude steht (sonst gilt der Klick nach der Klick-Regel dem Gebäude)
    const ray = new G.THREE.Raycaster(), w = new G.THREE.Vector3(), gebaeude = Object.values(G.M);
    let sichtbar = 0, punkt = null;
    for (let i = 0; i < m.count; i++) {
      m.getMatrixAt(i, M4); if (M4.elements[0] === 0) continue;
      sichtbar++; v.setFromMatrixPosition(M4); v.y += 0.15; w.copy(v); v.project(G.camera);
      const x = (v.x + 1) / 2 * c.width + c.left, y = (1 - v.y) / 2 * c.height + c.top;
      if (punkt || !(x > 420 && x < 880 && y > 200 && y < 650)) continue;
      const d = G.camera.position.distanceTo(w);
      ray.set(G.camera.position, w.clone().sub(G.camera.position).normalize());
      const hit = ray.intersectObjects(gebaeude, false)[0];
      if (!hit || hit.distance > d - 0.2) punkt = { x, y };
    }
    return { sichtbar, punkt };
  });
  console.log('     Figuren um 8 Uhr:', JSON.stringify(fig));
  ok(fig.sichtbar > 20, 'Figuren laufen (' + fig.sichtbar + ')');
  if (fig.punkt) {
    await page.evaluate(() => __stadt.setzeTempo(0));
    await page.mouse.click(fig.punkt.x, fig.punkt.y); await page.waitForTimeout(300);
    const t = await page.evaluate(() => [...document.querySelectorAll('#karte h3')].map(e => e.textContent).join('|'));
    ok(t.includes('Charakter'), 'Klick auf Figur öffnet Personenkarte');
  }
  const dbg = await page.evaluate(() => globalThis.__stadtDebug);
  console.log('     Debug:', JSON.stringify(dbg));
  ok(dbg.calls < 100, 'Draw Calls < 100');
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
