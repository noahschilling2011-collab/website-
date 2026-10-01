// Figuren bei der Arbeit: stündlich 8–17 Uhr steht jede sichtbare Figur dort, wo die Simulation die Person hat
const U = require('./umgebung.cjs');
const { chromium } = U;
const OUT = U.ordner('bilder_p7');   // Bilder nach tests/ausgabe/ (per .gitignore ausgeschlossen)
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
  const seed = process.argv[2] || '2', tage = process.argv[3] || '200';
  await page.goto(`${U.HOST}/stadt.html?debug&seed=${seed}&tage=${tage}&neu`);
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await ev(() => __stadt.setzeTempo(0));
  // bis 7 Uhr, Kamera auf eine Baustelle (damit Bauarbeiter unter den 120 sind)
  const bs = await ev(() => { const a = __stadt; for (let n = 0; n < 24 * 30; n++) { a.schritt(); if (a.S().stunde === 7 && a.S().baustellen.length) break; } a.nachSchritten();
    const S = a.S(), b = S.baustellen[0]; if (b === undefined) return null;
    const c = a.G.controls, x = S.g.x[b] - S.mitte + 0.5, z = S.g.y[b] - S.mitte + 0.5; c.target.set(x, 0, z); a.G.camera.position.set(x + 6, 9, z + 9); c.update(); return b; });
  ok(bs !== null, 'Baustelle im Blick: Gebäude ' + bs);
  let fehler = 0, geprueft = 0, gehen = 0, maxWerk = 0, maxSicht = 0, bauSicht = 0, traegerKisten = 0, doppelt = 0;
  for (let H = 8; H <= 17; H++) {
    const r = await ev((H) => {
      const a = __stadt, S = a.S(), T = a.G.test;
      while (S.stunde !== H) a.schritt();
      a.nachSchritten();
      const erg = { fehler: [], geprueft: 0, gehen: 0, werk: 0, sicht: 0, bau: 0, kisten: 0, doppelt: 0 };
      for (const zeit of [0.5, 0.999]) {
        a.G.figurenBewegen(S.tag * 24 + H + zeit);
        const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), gesehen = new Set();
        let sicht = 0;
        for (let i = 0; i < T.figuren.length; i++) {
          const f = T.figuren[i], p = T.figIds[i];
          if (p < 0) continue;
          sicht++;
          if (gesehen.has(p)) erg.doppelt++; gesehen.add(p);
          const jetzt = S.tag * 24 + H + zeit, laeuft = f.route && jetzt >= f.start && jetzt < f.start + f.dauer;
          if (laeuft) { erg.gehen++; continue; }
          a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4);
          const soll = T.simOrt(p, H), wartet = f.route && jetzt < f.start;
          const ort = wartet ? null : soll;                 // wartet: steht noch am alten Platz (vorige Stunde)
          const alt = T.simOrt(p, H - 1);
          const bx = (o) => S.g.x[o] - S.mitte + 0.5, bz = (o) => S.g.y[o] - S.mitte + 0.5;
          // Gebäude auf eigenem Gelände (Sicherheit: Wache, Anstalt; Bund: Kaserne, Dienststelle): auf dem Gelände oder bis 0,9 davor (Gefangene im Hof,
          // Soldaten auf dem Antreteplatz, Personal vor der Pforte)
          const gel = (o) => S.erweiterung.gelaende.find(r => r[4] === o);
          const nah = (o) => { if (o < 0) return false; const r = gel(o);
            if (!r) return Math.hypot(v.x - bx(o), v.z - bz(o)) <= 0.9;
            return v.x >= r[0] - S.mitte - 0.9 && v.x <= r[2] - S.mitte + 1.9 && v.z >= r[1] - S.mitte - 0.9 && v.z <= r[3] - S.mitte + 1.9; };
          erg.geprueft++;
          if (!(ort !== null ? nah(ort) : nah(alt))) erg.fehler.push(`${H}:${zeit} Person ${p} steht bei (${v.x.toFixed(2)}, ${v.z.toFixed(2)}), Simulation: Gebäude ${soll} (${bx(soll)}, ${bz(soll)})${wartet ? ' (wartet, vorher ' + alt + ')' : ''}`);
          if (S.p.einsatz[p] && ort === S.p.einsatz[p] - 1) erg.bau++;
        }
        erg.sicht = Math.max(erg.sicht, sicht);
        erg.kisten = Math.max(erg.kisten, a.G.M.kiste.count);
      }
      erg.werk = T.figuren.slice(0, T.FIG_MAX).filter(f => f.werk && f.p >= 0).length;
      return erg;
    }, H);
    fehler += r.fehler.length; geprueft += r.geprueft; gehen += r.gehen; maxWerk = Math.max(maxWerk, r.werk); maxSicht = Math.max(maxSicht, r.sicht); bauSicht += r.bau; doppelt += r.doppelt;
    if (H === 9 || H === 13) traegerKisten = Math.max(traegerKisten, r.kisten);
    if (r.fehler.length) console.log('  ' + r.fehler.slice(0, 3).join('\n  '));
    if (H === 12) {
      await ev(() => { __stadt.G.figurenBewegen(__stadt.S().tag * 24 + 12.5); });
      await page.waitForTimeout(300);
      await page.screenshot({ path: OUT + 'p7_baustelle.png' });
    }
  }
  ok(fehler === 0, `Grundregel 8–17 Uhr: ${geprueft} stehende Figuren geprüft, ${gehen} gingen gerade, ${fehler} am falschen Ort`);
  ok(doppelt === 0, `keine Person doppelt (${doppelt})`);
  ok(maxWerk > 0 && maxWerk <= 120 && maxSicht <= 310, `Arbeitsplätze bis ${maxWerk} (≤ 120), sichtbar bis ${maxSicht} (≤ 300 + Hauptfiguren)`);
  ok(bauSicht > 0, `Bauarbeiter auf der Baustelle zu sehen (${bauSicht} Figur-Stunden)`);
  const dbg = await ev(() => { __stadt.setzeTempo(1); return new Promise(r => setTimeout(() => r(globalThis.__stadtDebug), 1200)); });
  ok(dbg.calls <= 30, `Draw Calls ${dbg.calls} (≤ 30), Dreiecke ${dbg.dreiecke}`);
  console.log('     Kisten-Instanzen um 9/13 Uhr bis', traegerKisten);
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
