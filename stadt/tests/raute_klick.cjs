// Klick auf die Raute einer Hauptfigur öffnet diese Hauptfigur (Teststadt, Tag 400, 11 Uhr)
const U = require('./umgebung.cjs');
const { chromium } = U;
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (r) => r.abort());
  const page = await ctx.newPage(); const log = [];
  page.on('pageerror', e => log.push(e.message));
  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=400&neu');
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await page.evaluate(() => { __stadt.setzeTempo(0); let n = 0; while (__stadt.S().stunde !== 11 && n++ < 30) __stadt.schritt(); __stadt.nachSchritten(); });
  const zu = () => page.evaluate(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
  await page.waitForTimeout(800); await zu();
  let ok = 0, fehl = 0;
  for (const dist of [10, 25]) {
    // Blick setzen, warten, dann noch einmal setzen (Schlussprüfung V8: einmal lag der Blick nach dem Warten woanders, vermutlich richtete der
    // Startblick ihn nach dem Laden noch einmal aus; dann trafen die Klicks Häuser neben den Rauten)
    const blick = () => page.evaluate((dist) => { const { G } = __stadt, S = __stadt.S(); const h = S.ki.haupt[0]; if (!h) return;
      const c = G.controls; c.target.set(S.g.x[S.p.wohnung[h.id]] - (S.mitte ?? 48) + 0.5, 0, S.g.y[S.p.wohnung[h.id]] - (S.mitte ?? 48) + 0.5); G.camera.position.set(c.target.x + dist * 0.5, dist * 0.7, c.target.z + dist * 0.5); c.update(); }, dist);
    await blick(); await page.waitForTimeout(700); await zu(); await blick(); await page.waitForTimeout(300);
    const ziele = await page.evaluate(() => { const { G } = __stadt, S = __stadt.S(), m = G.scene.children.find(o => o.isInstancedMesh && o.count <= 10 && o.material && o.material.depthTest !== undefined && o.renderOrder === 2);
      const out = []; if (!m) return out; const M4 = new G.THREE.Matrix4(), v = new G.THREE.Vector3(), r = G.renderer.domElement.getBoundingClientRect();
      for (let k = 0; k < m.count; k++) { m.getMatrixAt(k, M4); v.setFromMatrixPosition(M4).project(G.camera); if (v.z < 1) out.push({ x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top }); }
      return out; });
    for (const z of ziele) {
      if (z.x < 260 || z.x > 900 || z.y < 200 || z.y > 700) continue;
      await page.keyboard.press('Escape'); await page.waitForTimeout(150); await zu();
      await page.mouse.click(z.x, z.y); await page.waitForTimeout(400);
      const r = await page.evaluate(() => ({ titel: document.querySelector('#karte h2')?.textContent || '', haupt: __stadt.Sim.hauptListe(__stadt.S()).map(h => __stadt.Sim.name(__stadt.S(), h.id)) }));   // Version 9: mit dem Bürgermeister (eigene Raute)
      const treffer = r.haupt.some(n => r.titel.includes(n));
      console.log(`${treffer ? 'OK' : 'FEHL'} Abstand ${dist}: Klick (${z.x | 0},${z.y | 0}) → „${r.titel}“`);
      treffer ? ok++ : fehl++;
    }
  }
  // Mindestens 4 Klicks (Teststadt: 6 bis 10), keiner daneben, keine Fehler auf der Seite; sonst exit 1 (tests/alle.sh zählt die OK-Zeilen)
  const MIN = 4, gut = !fehl && ok >= MIN && !log.length;
  console.log(`${gut ? 'OK' : 'FEHL'} Rauten-Klicks: ${ok} OK, ${fehl} FEHL (mindestens ${MIN}); Fehler: ${log.join(' | ') || 'keine'}`);
  await b.close();
  process.exit(gut ? 0 : 1);
})();
