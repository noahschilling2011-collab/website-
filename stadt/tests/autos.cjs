// Tech-Firmen und Autos (Version 8). Teststadt Seed 2, 730 Tage:
// 1. Tech-Stufen: Hochhaus (Stufe 5) und Autowerk werden gezeichnet (Klick aufs Dach trifft sie, Hauskarte), Eröffnung in den Daten, Bilder.
// 2. Grundregel an der Schnittstelle, die die Darstellung nutzt (Sim.ortZurStunde, Sim.autoOrt, Sim.mitAuto): 24 Stunden lang jedes Auto;
//    ein Auto wechselt den Ort nur, wenn sein Besitzer in dieser Stunde den Ort wechselt und mit dem Auto fährt (0 Fahrten ohne Ortswechsel),
//    sonst steht es dort, wo der Besitzer ist, oder zu Hause.
// 3. Teststrecke: Sim.testfahrer nennt nur in den Teststunden jemanden, und nur wer laut Simulation in dieser Stunde genau in diesem Werk arbeitet.
// 4. Hauptfigur mit Auto: Während sie zur Arbeit fährt, ist ihre Figur nicht zu sehen und die Raute bleibt sichtbar, über ihrem Auto
//    (Teil 2: vorher lief die Figur, jetzt fährt das Auto). Personenkarte nennt das Auto.
// 5. Draw Calls (Budget: ffa1d88 + 3), Konsole leer.
// Die Darstellung der Autos im Einzelnen (Fahrer unsichtbar, Rechtsverkehr, Prototyp, Lichtkegel, Campus) prüft tests/autos_bild.cjs.
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const OUT = U.ordner('bilder_autos');
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const ev = (f, a) => page.evaluate(f, a);
  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=730&neu');
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await ev(() => { __stadt.setzeTempo(0); while (__stadt.S().stunde !== 7) __stadt.schritt(); __stadt.nachSchritten(); });
  const zu = () => ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
  await page.waitForTimeout(600); await zu();

  // 1. Tech-Stufen und Autowerk
  const bauten = await ev(() => { const a = __stadt, S = a.S(), g = S.g, Sim = a.Sim, L = [];
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.TECH && !g.leer[b] && S.feld[g.y[b] * S.karte + g.x[b]] === Sim.TECH && (g.stufe[b] >= 4 || g.werk[b])) {
      const i = Sim.gebaeudeInfo(S, b); L.push({ b, stufe: g.stufe[b], werk: !!g.werk[b], name: i.stufeName, titel: i.titel, zeile: i.zeile, eroeffnet: i.eroeffnet, art: i.eroeffnetArt }); }
    return L; });
  const hoch = bauten.find(x => !x.werk && x.stufe === 5), werk = bauten.find(x => x.werk);
  ok(!!hoch && !!werk && bauten.every(x => x.eroeffnet >= 0 && x.art && x.name),
    `Teststadt: ${bauten.filter(x => !x.werk).length} Tech-Firmen ab Stufe 4 (${bauten.filter(x => !x.werk).map(x => x.name).join(', ')}), ${bauten.filter(x => x.werk).length} Autowerke; alle mit Eröffnung (${bauten.map(x => x.art + ' Tag ' + x.eroeffnet).join(', ')})`);
  for (const [was, x, geschosse] of [['Hochhaus', hoch, 9], ['Autowerk', werk, 2]]) {
    if (!x) continue;
    await zu();
    // Werk steil von oben (Schlussprüfung: im neuen Verlauf steht in der Teststadt ein Hochhaus schräg vor dem Werk)
    await ev(({ b, geschosse, steil }) => { const a = __stadt, S = a.S(), mx = S.g.x[b] - S.mitte + 0.5, mz = S.g.y[b] - S.mitte + 0.5, c = a.G.controls;
      c.target.set(mx, geschosse * 0.21, mz); if (steil) a.G.camera.position.set(mx + 1.0, 8.5, mz + 1.4); else a.G.camera.position.set(mx + 3.2, geschosse * 0.42 + 4.5, mz + 4.2); c.update(); },
      { b: x.b, geschosse, steil: was === 'Autowerk' });
    // Der KI-Takt öffnet den Nachfolge-Dialog wieder (Hauptfiguren der Teststadt sterben): direkt vor dem Klick schließen. Den Klickpunkt
    // erst danach rechnen (eine eben geschlossene Karte verschiebt den Blick noch)
    await page.waitForTimeout(800); await zu(); await page.waitForTimeout(300); await zu();
    await page.screenshot({ path: OUT + (was === 'Hochhaus' ? 'hochhaus.png' : 'werk.png') });
    const xy = await ev(({ b, geschosse }) => { const a = __stadt, S = a.S(), mx = S.g.x[b] - S.mitte + 0.5, mz = S.g.y[b] - S.mitte + 0.5;
      const v = new a.G.THREE.Vector3(mx, geschosse * 0.42 - 0.15, mz); v.project(a.G.camera);
      const r = document.getElementById('szene').getBoundingClientRect(); return { x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top }; }, { b: x.b, geschosse });
    await zu();
    await page.mouse.click(xy.x, xy.y); await page.waitForTimeout(300);
    const haus = await ev(() => document.getElementById('karte-inhalt') ? document.getElementById('karte-inhalt').innerText : '');
    ok(was === 'Hochhaus' ? /Tech-Firma/.test(haus) && /Stufe 5 \(Hochhaus\)/.test(haus) : /Autowerk/.test(haus) && /Hallen?/.test(haus) && /Autobauer/.test(haus),
      `${was}: Klick aufs Dach öffnet die Hauskarte: ${haus.split('\n').slice(0, 3).join(' | ')}`);
    await ev(() => { const k = document.getElementById('karte-zu'); if (k) k.click(); }); await page.waitForTimeout(300);   // Karte zu: sonst rückt der Blick
  }

  // 2. Grundregel über 24 Stunden (ab 0 Uhr), jedes Auto; 3. Teststrecke in denselben Stunden
  const regel = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p;
    while (S.stunde !== 0) a.schritt();
    const werke = []; for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.TECH && S.g.werk[b] && !S.g.leer[b]) werke.push(b);
    const r = { fahrten: 0, ohneOrt: 0, falscherOrt: 0, ohneMitAuto: 0, umzug: 0, autos: 0, stunden: 0, test: 0, testFalsch: 0, testStunden: [], beispiel: '' };
    let vor = null;
    for (let h = 0; h < 24; h++) {
      const H = S.stunde, jetzt = new Map();
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.auto[p]) {
        const o = Sim.ortZurStunde(S, p, H), ao = Sim.autoOrt(S, p, H);
        jetzt.set(p, { o, ao, w: P.wohnung[p] });
        if (ao !== o && ao !== P.wohnung[p]) r.falscherOrt++;          // steht dort, wo der Besitzer ist, oder zu Hause
        const v = vor && vor.get(p);
        if (!v) continue;
        if (v.w !== P.wohnung[p]) { r.umzug++; continue; }             // Umzug: das Auto zieht mit dem Haushalt um
        if (v.ao === ao) continue;
        r.fahrten++;
        if (v.o === o) r.ohneOrt++;                                    // Fahrt ohne Ortswechsel des Besitzers
        else if (!Sim.mitAuto(S, p, v.o, o)) r.ohneMitAuto++;          // Fahrt, obwohl die Sim nicht mit dem Auto fährt
        else if (!r.beispiel) r.beispiel = `${Sim.name(S, p)}: ${H} Uhr von ${v.o} nach ${o}`;
      }
      for (const w of werke) {                                         // wer in dieser Stunde den Prototyp fährt (−1: niemand)
        const t = Sim.testfahrtStunde(S, w, H);
        if (t < 0) continue;
        r.test++; if (!r.testStunden.includes(H)) r.testStunden.push(H);
        if (t !== Sim.testfahrer(S, w) || Sim.ortZurStunde(S, t, H) !== w || Sim.arbeitsOrtHeute(S, t) !== w || P.frei[t] || P.haftBis[t]) r.testFalsch++;
      }
      r.autos = Math.max(r.autos, jetzt.size); r.stunden++;
      vor = jetzt; a.schritt();
    }
    r.teststunden = Sim.R.TEST_STUNDEN.join(', ');
    return r; });
  ok(regel.stunden === 24 && regel.autos > 100 && regel.fahrten > 100 && !regel.ohneOrt && !regel.ohneMitAuto && !regel.falscherOrt,
    `Grundregel, 24 Stunden, ${regel.autos} Autos: ${regel.fahrten} Fahrten, davon ${regel.ohneOrt} ohne Ortswechsel und ${regel.ohneMitAuto} ohne mitAuto; `
    + `${regel.falscherOrt}-mal stand ein Auto weder beim Besitzer noch zu Hause; ${regel.umzug} Umzüge mit Auto (z. B. ${regel.beispiel})`);
  ok(regel.test > 0 && !regel.testFalsch && regel.testStunden.every(h => regel.teststunden.split(', ').map(Number).includes(h)),
    `Teststrecke: ${regel.test} Testfahrten in den Stunden ${regel.testStunden.join(', ')} (erlaubt ${regel.teststunden}), ${regel.testFalsch} ohne Testfahrer im Werk`);

  // 4. Hauptfigur, die mit dem Auto zur Arbeit fährt: Raute sichtbar während der Fahrt; Personenkarte nennt das Auto
  const haupt = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p;
    while (S.stunde !== 6) a.schritt();
    let p = -1;
    for (let x = 0; x < S.pMax && p < 0; x++) if (P.lebt[x] && P.auto[x] && Sim.pendeltMitAuto(S, x) && Sim.arbeitsOrtHeute(S, x) >= 0) p = x;
    if (p < 0) return null;
    const ok = Sim.hauptSetzen(S, p, P.gen[p], true, 10);
    a.nachSchritten();                                                 // die Figur entsteht zu Hause
    // die Stunde, in der p zur Arbeit fährt; Stunde für Stunde (die Darstellung plant die Wege je Stunde)
    let H = -1; for (let h = 6; h < 12 && H < 0; h++) if (Sim.ortZurStunde(S, p, h) !== P.wohnung[p] && Sim.mitAuto(S, p, P.wohnung[p], Sim.ortZurStunde(S, p, h))) H = h;
    while (S.stunde !== H) { a.schritt(); a.nachSchritten(); }
    return { p, gen: P.gen[p], ok, H, name: Sim.name(S, p), auto: Sim.autoName(S, p), wohnung: P.wohnung[p], ziel: Sim.ortZurStunde(S, p, H) }; });
  ok(!!haupt && haupt.ok && haupt.H >= 0, 'Hauptfigur mit Auto: ' + JSON.stringify(haupt));
  if (haupt) {
    const raute = await ev((h) => { const a = __stadt, S = a.S(), G = a.G, T = G.test;
      const m = G.scene.children.find(o => o.isInstancedMesh && o.count <= 11 && o.renderOrder === 2);
      const M4 = new G.THREE.Matrix4(), v = new G.THREE.Vector3(), c = new G.THREE.Vector3();
      // ihre Fahrt in dieser Stunde (Darstellung): gemessen auf dem Weg (20, 50, 80 %): Figur weg, Raute über dem Auto
      let i = -1; for (let k = 0; k < T.tripN(); k++) if (T.fahrt(k).p === h.p) i = k;
      if (i < 0) return [{ fahrt: -1 }];
      const f = T.fahrt(i), out = [];
      for (const q of [0.2, 0.5, 0.8]) {
        G.figurenBewegen(f.start + f.dauer * q);
        G.M.auto.getMatrixAt(T.autoStatisch() + i, M4); c.setFromMatrixPosition(M4);
        let best = 1e9, sicht = false;
        for (let k = 0; m && k < m.count; k++) { m.getMatrixAt(k, M4); v.setFromMatrixPosition(M4); const e = M4.elements, sx = Math.hypot(e[0], e[1], e[2]);   // Maßstab aus der ersten Spalte
          const d = Math.hypot(v.x - c.x, v.z - c.z); if (d < best) { best = d; sicht = sx > 0.01 && m.visible; } }
        out.push({ q, fig: T.figIds.indexOf(h.p), d: +best.toFixed(2), sicht, gefahren: f.n > 0 });
      }
      return out; }, haupt);
    ok(raute.length === 3 && raute.every(r => r.fig < 0 && r.gefahren && r.sicht && r.d < 0.05), `Raute der Hauptfigur ${haupt.name} sichtbar über ihrem Auto, während sie um ${haupt.H} Uhr mit dem ${haupt.auto} zur Arbeit fährt (Figur unsichtbar): ${JSON.stringify(raute)}`);
    await zu();
    await ev((h) => { const z = document.querySelector(`#haupt-liste .haupt-zeile[data-p="${h.p}"]`); if (z) z.click(); }, haupt);
    await page.waitForTimeout(250);
    const karte = await ev(() => document.getElementById('karte-inhalt') ? document.getElementById('karte-inhalt').innerText : '');
    ok(karte.includes(`mit dem ${haupt.auto} zur Arbeit`), `Personenkarte: „${(karte.split('\n').find(z => z.includes('Heute')) || '–').slice(0, 140)}“`);
    await page.screenshot({ path: OUT + 'personenkarte.png' });
    await page.keyboard.press('Escape');
  }

  // 5. Draw Calls um 8 Uhr (ffa1d88 in dieser Teststadt 26–29, Budget +3), Konsole
  const dbg = await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 8) a.schritt(); a.nachSchritten(); a.setzeTempo(1);
    return new Promise(r => setTimeout(() => { a.setzeTempo(0); r(globalThis.__stadtDebug); }, 1500)); });
  ok(dbg.calls <= 32, `Draw Calls ${dbg.calls} (≤ 32), Dreiecke ${dbg.dreiecke}, Einwohner ${dbg.einwohner}`);
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
