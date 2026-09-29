// Tech-Firmen und Autos (Version 8, Teil 2: Darstellung). Teststadt Seed 2, 730 Tage (und Seed 1 für den Campus; bis Version 9, Teil 2 Seed 3):
// 1. Grundregel im Bild, 24 Stunden, jedes Auto: Eine Fahrt gibt es nur, wenn der Besitzer laut Simulation den Ort wechselt und diesen Weg mit
//    dem Auto fährt: in der Vorstunde beim Auto (Abfahrt), jetzt an dessen Ziel, Sim.mitAuto. Wechselt ein Auto sonst den Ort (Umzug, neue
//    Stelle mitten am Tag), springt es, und der Besitzer hätte diesen Weg nicht mit ihm gemacht. Weg beginnt am alten und endet am neuen Platz,
//    ein stehendes Auto bewegt sich ohne Fahrt nicht, und es steht höchstens ein Straßenfeld von dem Gebäude, bei dem es laut Sim.autoOrt steht.
// 1b. Umzug um 8 Uhr und neue Stelle mitten am Tag (feste Momente der Teststadt, vorher geprüft, dass es sie gibt): Das Auto springt ohne
//    Fahrt, der Besitzer (als Hauptfigur) bleibt zu sehen, seine Raute über ihm, nicht über dem Auto (Befund der Schlussprüfung).
// 2. Fahrer unsichtbar, solange ihr Auto fährt (alle Figuren mit Fahrt, 9 Zeitpunkte je Stunde).
// 3. Rechtsverkehr: fahrende Autos auf geraden Straßenfeldern fahren rechts der Mitte.
// 4. Teststrecke: Der Prototyp bewegt sich nur in einer Teststunde mit dem Testfahrer der Simulation, der dann laut Simulation genau in diesem
//    Werk arbeitet; dessen Figur ist dann nirgends zu sehen. Sonst steht der Prototyp an der Startlinie. Klick auf ihn: der Testfahrer.
// 5. Hauptfigur, die mit dem Auto zur Arbeit fährt: Figur unsichtbar, Raute über dem Auto (20, 50, 80 % der Fahrt).
// 6. Tech-Stufen im Bild: Hochhaus mit vier Leuchtlogos und rotem Licht, Autowerk mit Hallen und Turmebenen je Stufe, Campus (Seed 1);
//    Lichtkegel nur am Abend einer echten Eröffnung der Simulation (g.eroeffnet), auch nach dem Neuladen.
// 7. Klick auf ein parkendes Auto öffnet die Karte seines Besitzers (mit dem Auto); Draw Calls; Konsole leer.
// 8. Karten: Testfahrer erst ab 8 Uhr (dann der, der um 10 Uhr fährt), Werkskarte (Lieferant, Hallen wie im Bild), „fährt um 8 Uhr …“.
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const OUT = U.ordner('bilder_autos');
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function oeffne(b, q) {
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage(), log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  await page.goto(U.HOST + '/stadt.html?debug&' + q);
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 900000 });
  const ev = (f, a) => page.evaluate(f, a);
  const zu = () => ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
  await ev(() => __stadt.setzeTempo(0)); await zu();
  return { ctx, page, log, ev, zu };
}
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const { page, log, ev, zu } = await oeffne(b, 'seed=2&tage=730&neu');

  // 1.–4. 24 Stunden ab 0 Uhr, je Stunde 9 Zeitpunkte
  const r = await ev(() => {
    const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, G = a.G, T = G.test, K = () => S.karte, M = G.M, THREE = G.THREE;
    while (S.stunde !== 23) a.schritt(); a.nachSchritten();
    const m4 = new THREE.Matrix4(), v = new THREE.Vector3(), q = new THREE.Quaternion(), s = new THREE.Vector3(), e = new THREE.Euler();
    const ist = (x, y) => x >= 0 && y >= 0 && x < K() && y < K() && S.feld[y * K() + x] === Sim.STRASSE;
    const gerade = (x, y) => { if (!ist(x, y)) return 0; const lx = ist(x + 1, y) && ist(x - 1, y), lz = ist(x, y + 1) && ist(x, y - 1);
      return lx && !ist(x, y + 1) && !ist(x, y - 1) ? 1 : lz && !ist(x + 1, y) && !ist(x - 1, y) ? 2 : 0; };
    const e0 = { fahrten: 0, mit: 0, ohneOrtswechsel: 0, ohneMitAuto: 0, abfahrtOhneBesitzer: 0, sprungOhneGrund: 0, umzug: 0, sprungWohnung: 0, sprungAnfang: 0, sprungEnde: 0,
      stehendBewegt: 0, stehendWeit: 0, stehendFalscherOrt: 0, stehend: 0, abstand: [0, 0, 0, 0], sichtbar: 0, spruenge: 0, rest: 0,
      figurGeprueft: 0, figurSichtbar: 0, rechts: 0, links: 0, mitte: 0, kreuzung: 0,
      testStunden: [], testBewegt: 0, testOhneFahrer: 0, testFahrerFalsch: 0, testFigurSichtbar: 0, testBewegtAusser: 0, testStart: 0 };
    let vorPose = null, vorWohnung = null, vorOrt = null;
    for (let h = 0; h < 24; h++) {
      a.schritt(); a.nachSchritten(); T.planeAlle();
      const H = S.stunde, jetzt0 = S.tag * 24 + H, tn = T.tripN(), fahrtVon = new Map();
      const i0 = T.autos().zaehl;
      e0.sichtbar += i0.sichtbar; e0.spruenge += i0.sprung; e0.rest += i0.rest;
      for (let i = 0; i < tn; i++) {
        const f = T.fahrt(i); fahrtVon.set(f.p, f); e0.fahrten++;
        const o0 = vorOrt ? vorOrt.get(f.p) : undefined, o1 = Sim.ortZurStunde(S, f.p, H);
        if (!f.mit) {                                // Sprung: der Besitzer macht diesen Weg nicht mit dem Auto (Umzug, neue Stelle)
          e0.umzug++; if (vorWohnung && vorWohnung.get(f.p) !== P.wohnung[f.p]) e0.sprungWohnung++;
          if (o0 === f.von && o1 === f.ziel && Sim.mitAuto(S, f.p, f.von, f.ziel)) e0.sprungOhneGrund++;
          continue;
        }
        e0.mit++;
        if (o0 === o1) e0.ohneOrtswechsel++;
        if (o0 !== f.von) e0.abfahrtOhneBesitzer++;             // Abfahrt: der Besitzer war in der Vorstunde dort, wo das Auto stand
        if (!Sim.mitAuto(S, f.p, f.von, f.ziel) || f.ziel !== o1) e0.ohneMitAuto++;
        if (f.n) {                                   // Weg beginnt am alten Platz und endet am neuen (Lage vorher/nachher aus aPose)
          const pv = vorPose && vorPose.get(f.p);
          if (pv && f.alt >= 0 && Math.hypot(pv[0] - f.pts[0], pv[1] - f.pts[1]) > 0.02) e0.sprungAnfang++;
          if (f.neu >= 0) { const sl = T.spotLage(f.neu), n = f.pts.length; if (Math.hypot(sl[0] - f.pts[n - 2], sl[1] - f.pts[n - 1]) > 0.02) e0.sprungEnde++; }
        }
      }
      // stehende Autos: ohne Fahrt dieselbe Lage wie in der Stunde davor; höchstens ein Straßenfeld vom Gebäude, bei dem das Auto laut Sim steht
      const pose = new Map(), aSpot = T.aSpot(), aOrt = T.aOrt();
      for (let q2 = 0; q2 < T.autoStatisch(); q2++) {
        const p = T.autoPers[q2]; if (p < 0) continue;
        M.auto.getMatrixAt(q2, m4); v.setFromMatrixPosition(m4); pose.set(p, [v.x, v.z]); e0.stehend++;
        const pv = vorPose && vorPose.get(p);
        if (pv && !fahrtVon.has(p) && Math.hypot(pv[0] - v.x, pv[1] - v.z) > 1e-4 && vorWohnung.get(p) === P.wohnung[p]) e0.stehendBewegt++;
        const o = aOrt[p];
        if (o !== Sim.autoOrt(S, p, H)) e0.stehendFalscherOrt++;
        if (o >= 0 && aSpot[p] >= T.LOT_MAX) {
          const c = (aSpot[p] - T.LOT_MAX) >> 2, cx = c % K(), cy = (c / K()) | 0, d = Math.abs(cx - S.g.x[o]) + Math.abs(cy - S.g.y[o]);
          e0.abstand[Math.min(3, d)]++; if (d > 2) e0.stehendWeit++;
        } else if (o >= 0) e0.abstand[0]++;
      }
      for (const [p, f] of fahrtVon) if (f.neu >= 0) { const sl = T.spotLage(f.neu); pose.set(p, [sl[0], sl[1]]); }
      vorPose = pose; vorWohnung = new Map(); vorOrt = new Map();
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.auto[p]) { vorWohnung.set(p, P.wohnung[p]); vorOrt.set(p, Sim.ortZurStunde(S, p, H)); }
      // Werke dieser Stunde: Testfahrer der Simulation
      const werke = T.werke(), protoStart = new Map();
      for (const W of werke) { if (W.proto < 0) continue; M.auto.getMatrixAt(W.proto, m4); v.setFromMatrixPosition(m4); protoStart.set(W.b, [v.x, v.z]);
        if (W.fahrer >= 0) { if (!e0.testStunden.includes(H)) e0.testStunden.push(H);
          if (W.fahrer !== Sim.testfahrtStunde(S, W.b, H) || Sim.ortZurStunde(S, W.fahrer, H) !== W.b || !Sim.R.TEST_STUNDEN.includes(H)) e0.testFahrerFalsch++; } }
      for (let k = 1; k <= 9; k++) {
        const t = jetzt0 + k / 10;
        G.figurenBewegen(t);
        for (let i = 0; i < T.figuren.length; i++) {             // 2. Figur unsichtbar, solange ihr Auto fährt
          const f = T.figuren[i]; if (f.p < 0) continue;
          const fa = fahrtVon.get(f.p);
          if (fa && fa.mit && t >= fa.start && t < fa.start + fa.dauer) { e0.figurGeprueft++; if (T.figIds[i] >= 0) e0.figurSichtbar++; }
          for (const W of werke) if (W.fahrer === f.p && T.figIds[i] >= 0) e0.testFigurSichtbar++;   // 4. Testfahrer nicht zu Fuß zu sehen
        }
        for (let i = 0; i < tn; i++) {                           // 3. Rechtsverkehr
          const f = T.fahrt(i); if (!f.n) continue;
          const u = (t - f.start) / f.dauer; if (u <= 0.02 || u >= 0.98) continue;
          M.auto.getMatrixAt(T.autoStatisch() + i, m4); m4.decompose(v, q, s); if (s.x < 0.5) continue;
          e.setFromQuaternion(q, 'YXZ'); const hx = Math.sin(e.y), hz = Math.cos(e.y);
          const ix = Math.floor(v.x + S.mitte), iz = Math.floor(v.z + S.mitte), ge = gerade(ix, iz);
          if (!ist(ix, iz)) continue;
          if (!ge) { e0.kreuzung++; continue; }
          const cx = ix - S.mitte + 0.5, cz = iz - S.mitte + 0.5;
          let q2;
          if (ge === 1 && Math.abs(hx) > 0.9) q2 = (v.z - cz) * Math.sign(hx);
          else if (ge === 2 && Math.abs(hz) > 0.9) q2 = -(v.x - cx) * Math.sign(hz);
          else { e0.kreuzung++; continue; }
          if (q2 > 0.05) e0.rechts++; else if (q2 < -0.05) e0.links++; else e0.mitte++;
        }
        for (const W of werke) {                                 // 4. Prototyp bewegt sich nur mit Testfahrer
          if (W.proto < 0) continue;
          M.auto.getMatrixAt(W.proto, m4); v.setFromMatrixPosition(m4);
          const st = protoStart.get(W.b), bewegt = Math.hypot(st[0] - v.x, st[1] - v.z) > 1e-3;
          if (bewegt && W.fahrer >= 0) e0.testBewegt++;
          if (bewegt && W.fahrer < 0) e0.testBewegtAusser++;
          if (W.fahrer < 0 && k === 9 && Math.hypot(st[0] - v.x, st[1] - v.z) > 1e-3) e0.testStart++;
        }
      }
    }
    e0.info = T.autos();
    return e0; });
  ok(r.fahrten > 200 && !r.ohneOrtswechsel && !r.ohneMitAuto && !r.abfahrtOhneBesitzer && !r.sprungOhneGrund,
    `Grundregel im Bild, 24 Stunden: ${r.fahrten} Fahrten, davon ${r.mit} mit dem Besitzer (${r.sichtbar} sichtbar gefahren, ${r.spruenge} ohne Weg auf der Straße, ${r.rest} nicht rechtzeitig geplant), `
    + `${r.ohneOrtswechsel} ohne Ortswechsel des Besitzers, ${r.abfahrtOhneBesitzer} mit Abfahrt ohne ihn, ${r.ohneMitAuto} ohne mitAuto oder mit Ziel ohne ihn; `
    + `${r.umzug} Sprünge ohne Fahrt (${r.sprungWohnung} beim Umzug), davon ${r.sprungOhneGrund}, obwohl der Besitzer den Weg mit dem Auto macht`);
  ok(!r.sprungAnfang && !r.sprungEnde && !r.stehendBewegt, `Kein Sprung: Weg beginnt am alten Platz (${r.sprungAnfang} Abweichungen) und endet am neuen (${r.sprungEnde}); stehende Autos ohne Fahrt bewegt: ${r.stehendBewegt}`);
  ok(r.stehend > 1000 && !r.stehendWeit && !r.stehendFalscherOrt, `Stehende Autos (${r.stehend} Auto-Stunden): Abstand Platz–Gebäude 0/1/2/mehr Felder ${r.abstand.join('/')}; `
    + `${r.stehendFalscherOrt}-mal nicht beim Ort der Simulation (Sim.autoOrt); Garage (nicht zu sehen) zuletzt ${r.info.garage} von ${r.info.besitzer}`);
  ok(r.figurGeprueft > 100 && !r.figurSichtbar, `Fahrer unsichtbar: ${r.figurGeprueft} Figur-Zeitpunkte im fahrenden Auto, davon ${r.figurSichtbar} sichtbar`);
  ok(r.rechts > 500 && !r.links, `Rechtsverkehr: ${r.rechts} Proben rechts der Mitte, ${r.links} links, ${r.mitte} Mitte (${r.kreuzung} auf Kreuzungen, Ecken, im Werk)`);
  ok(r.testBewegt > 0 && !r.testBewegtAusser && !r.testFahrerFalsch && !r.testFigurSichtbar && r.testStunden.every(h => [10, 14].includes(h)),
    `Teststrecke: Prototyp bewegt in ${r.testBewegt} Proben, nur in den Stunden ${r.testStunden.join(', ')} mit Testfahrer der Simulation im Werk (${r.testFahrerFalsch} falsch); `
    + `ohne Testfahrer bewegt: ${r.testBewegtAusser}; Testfahrer zugleich zu Fuß zu sehen: ${r.testFigurSichtbar}`);

  // 4b. Klick auf den Prototyp in der Teststunde: Karte des Testfahrers
  const proto = await ev(() => { const a = __stadt, S = a.S(), T = a.G.test; while (S.stunde !== 10) { a.schritt(); a.nachSchritten(); }
    const W = T.werke().find(w => w.fahrer >= 0); if (!W) return null;
    a.G.figurenBewegen(S.tag * 24 + 10 + 0.02);                   // noch an der Startlinie (τ < 0)
    const m = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(); a.G.M.auto.getMatrixAt(W.proto, m); v.setFromMatrixPosition(m);
    const c = a.G.controls; c.target.copy(v); a.G.camera.position.set(v.x + 1.2, v.y + 1.8, v.z + 1.6); c.update();
    return { fahrer: W.fahrer, name: a.Sim.name(S, W.fahrer), x: v.x, y: v.y, z: v.z }; });
  if (proto) {
    await zu(); await page.waitForTimeout(500); await zu();
    const xy = await ev((p) => { const a = __stadt; a.G.figurenBewegen(a.S().tag * 24 + 10.02); const v = new a.G.THREE.Vector3(p.x, p.y + 0.07, p.z); v.project(a.G.camera);
      const r = document.getElementById('szene').getBoundingClientRect(); return { x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top }; }, proto);
    await page.mouse.click(xy.x, xy.y); await page.waitForTimeout(300);
    const karte = await ev(() => document.getElementById('karte-inhalt') ? document.getElementById('karte-inhalt').innerText : '');
    ok(karte.includes(proto.name) && /Testfahrt/.test(karte), `Klick auf den Prototyp um 10 Uhr: Karte von ${proto.name} („${(karte.split('\n').find(z => /Testfahrt/.test(z)) || '–').slice(0, 90)}“)`);
    await page.screenshot({ path: OUT + 'teststrecke_klick.png' });
    await ev(() => { const k = document.getElementById('karte-zu'); if (k) k.click(); });
  } else ok(false, 'Teststrecke: kein Werk mit Testfahrer um 10 Uhr');

  // 5. Hauptfigur fährt mit dem Auto zur Arbeit: Figur unsichtbar, Raute über dem Auto
  // Gewählt wird erst nach der Stunde 7 Uhr: Bis dahin kann jeder noch freinehmen (A.FREI, h ≤ 7), erst dann steht fest, wer heute fährt.
  // Die Hauptfigur wird vor dem Planen der Stunde gesetzt (nachSchritten). Version 9, Teil 2: Bis dahin wurde um 6 Uhr gewählt; in der neuen
  // Teststadt nahm die gewählte Lehrerin um 7 Uhr frei und fuhr nicht (die Prüfung selbst ist unverändert)
  const haupt = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p;
    while (S.stunde !== 7) { a.schritt(); a.nachSchritten(); }
    a.schritt();                                             // die Stunde 7 Uhr: letzte Gelegenheit zum Freinehmen
    const H = S.stunde;
    let p = -1;
    for (let x = 0; x < S.pMax && p < 0; x++) if (P.lebt[x] && P.auto[x] && Sim.pendeltMitAuto(S, x) && Sim.arbeitsOrtHeute(S, x) >= 0 && !Sim.istHaupt(S, x)
      && Sim.autoOrt(S, x, H) !== P.wohnung[x]) p = x;
    if (p >= 0) Sim.hauptSetzen(S, p, P.gen[p], true, 10);
    a.nachSchritten();
    if (p < 0) return null;
    return { p, name: Sim.name(S, p), H, auto: Sim.autoName(S, p) }; });
  if (haupt) {
    const raute = await ev((h) => { const a = __stadt, S = a.S(), G = a.G, T = G.test, THREE = G.THREE;
      const mark = G.scene.children.find(o => o.isInstancedMesh && o.count <= 11 && o.renderOrder === 2);
      let i = -1; for (let k = 0; k < T.tripN(); k++) if (T.fahrt(k).p === h.p) i = k;
      if (i < 0) return [{ fahrt: -1 }];
      const f = T.fahrt(i), fig = T.figuren.findIndex(x => x.p === h.p && x.haupt), m = new THREE.Matrix4(), v = new THREE.Vector3(), c = new THREE.Vector3(), out = [];
      for (const q of [0.2, 0.5, 0.8]) {
        G.figurenBewegen(f.start + f.dauer * q);
        G.M.auto.getMatrixAt(T.autoStatisch() + i, m); c.setFromMatrixPosition(m);
        let best = 1e9, sicht = false;
        for (let k = 0; mark && k < mark.count; k++) { mark.getMatrixAt(k, m); v.setFromMatrixPosition(m); const d = Math.hypot(v.x - c.x, v.z - c.z); if (d < best) { best = d; sicht = Math.hypot(m.elements[0], m.elements[1], m.elements[2]) > 0.01; } }
        out.push({ q, sichtbarGehend: T.figIds.indexOf(h.p) >= 0, abstandRauteAuto: +best.toFixed(3), sicht, gefahren: f.n > 0 });
      }
      return out; }, haupt);
    ok(raute.length === 3 && raute.every(x => x.gefahren && !x.sichtbarGehend && x.sicht && x.abstandRauteAuto < 0.05),
      `Hauptfigur ${haupt.name} fährt um ${haupt.H} Uhr mit dem ${haupt.auto}: Figur unsichtbar, Raute über dem Auto: ${JSON.stringify(raute)}`);
  } else ok(false, 'keine Hauptfigur mit Auto gefunden');

  // 6. Tech-Stufen im Bild: Hochhaus und Autowerk (Teile je Gebäude aus den Klick-Listen)
  const bau = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, g = S.g, G = a.G, T = G.test, M = G.M;
    while (S.stunde !== 11) { a.schritt(); a.nachSchritten(); }
    const r = { hoch: [], werk: [] };
    for (let b = 0; b < S.gAnzahl; b++) {
      if (g.typ[b] !== Sim.TECH || g.leer[b] || S.feld[g.y[b] * S.karte + g.x[b]] !== Sim.TECH) continue;
      if (g.werk[b]) r.werk.push({ b, stufe: g.stufe[b], hoehe: +T.techHoehe(b).toFixed(2) });
      else if (g.stufe[b] === 5) r.hoch.push({ b, hoehe: +T.techHoehe(b).toFixed(2) });
    }
    return { r, w: T.werke() }; });
  // Turmebenen je Stufe für jedes fertige, offene Werk (im Bau oder leer steht es auch in T.werke(), zählt hier nicht)
  const offeneW = bau.w.filter(W => bau.r.werk.some(x => x.b === W.b));
  ok(bau.r.hoch.length > 0 && bau.r.hoch.every(x => x.hoehe > 6.5) && bau.r.werk.length > 0 && offeneW.length === bau.r.werk.length
    && offeneW.every(W => W.ebenen === Math.min(6, Math.max(3, bau.r.werk.find(x => x.b === W.b).stufe))),
    `Hochhäuser ${JSON.stringify(bau.r.hoch)}, Werke ${JSON.stringify(bau.r.werk)}, Turmebenen je Stufe ${offeneW.map(W => W.ebenen).join('/')} (${bau.w.length} Werke im Bild)`);

  // 7. Klick auf ein parkendes Auto: Karte des Besitzers mit dem Auto
  // Version 9: das erste parkende Auto, neben dem keine Figur steht (eine Figur im Umkreis von 16 Pixeln fängt den Klick ab, so will es die
  // Auswahl; in der Teststadt von Version 9 stand beim ersten Auto eine Arbeiterin des Werks)
  // Version 9, Teil 3: Die Figuren nah an der Kamera wählt erst das nächste Bild aus; deshalb je Auto zuerst die Kamera setzen, zwei Bilder
  // abwarten und dann prüfen, dass weder eine Figur noch die Raute einer Hauptfigur noch ein anderes Auto im Umkreis von 24 Pixeln liegt
  // (in der Teststadt traf der Klick sonst eine Handwerkerin, die erst mit dem neuen Blick zu sehen war)
  const autoN = await ev(() => __stadt.G.test.autoStatisch());
  let park = null;
  for (let q = 0; q < autoN && q < 80 && !park; q++) {
    const da = await ev((q) => { const a = __stadt, G = a.G, T = G.test, m = new G.THREE.Matrix4(), v = new G.THREE.Vector3();
      if (T.autoPers[q] < 0) return false;
      G.M.auto.getMatrixAt(q, m); v.setFromMatrixPosition(m);
      const c = G.controls; c.target.copy(v); G.camera.position.set(v.x + 0.05, v.y + 2.2, v.z + 0.35); c.update(); G.camera.updateMatrixWorld(); return true; }, q);
    if (!da) continue;
    await ev(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    park = await ev((q) => { const a = __stadt, S = a.S(), G = a.G, T = G.test, m = new G.THREE.Matrix4(), v = new G.THREE.Vector3(), w = new G.THREE.Vector3();
      const r = document.getElementById('szene').getBoundingClientRect(), bild = (u) => { const x = u.clone().project(G.camera); return [(x.x + 1) / 2 * r.width, (1 - x.y) / 2 * r.height]; };
      const p = T.autoPers[q]; G.M.auto.getMatrixAt(q, m); v.setFromMatrixPosition(m);
      const [ax, ay] = bild(new G.THREE.Vector3(v.x, v.y + 0.08, v.z)), nah = (x, y) => (x - ax) ** 2 + (y - ay) ** 2 < 24 * 24;
      for (let i = 0; i < T.figuren.length; i++) { if (T.figIds[i] < 0) continue; G.figMesh.getMatrixAt(i, m); w.setFromMatrixPosition(m); w.y += 0.15;
        if (nah(...bild(w))) return null; }
      const mark = G.scene.children.find(x => x.isInstancedMesh && x.count <= 11 && x.renderOrder === 2);
      if (mark) for (let j = 0; j < mark.count; j++) { mark.getMatrixAt(j, m); w.setFromMatrixPosition(m); if (nah(...bild(w))) return null; }
      for (let j = 0; j < G.M.auto.count; j++) { if (j === q) continue; G.M.auto.getMatrixAt(j, m); w.setFromMatrixPosition(m);
        if (w.y < -50 || Math.hypot(m.elements[0], m.elements[1], m.elements[2]) < 1e-6) continue; if (nah(...bild(new G.THREE.Vector3(w.x, w.y + 0.08, w.z)))) return null; }
      return { p, q, name: a.Sim.name(S, p), auto: a.Sim.autoName(S, p), x: v.x, y: v.y, z: v.z }; }, q);
  }
  if (park) {
    await zu(); await page.waitForTimeout(500); await zu();
    const xy = await ev((p) => { const a = __stadt, v = new a.G.THREE.Vector3(p.x, p.y + 0.08, p.z); v.project(a.G.camera);
      const r = document.getElementById('szene').getBoundingClientRect(); return { x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top }; }, park);
    await page.mouse.click(xy.x, xy.y); await page.waitForTimeout(300);
    const karte = await ev(() => document.getElementById('karte-inhalt') ? document.getElementById('karte-inhalt').innerText : '');
    ok(karte.includes(park.name) && karte.includes(park.auto), `Klick auf ein parkendes Auto (Blick von oben): Karte „${karte.split('\n')[0]}“, „${(karte.split('\n').find(z => z.includes(park.auto)) || '–').slice(0, 110)}“`);
    await page.screenshot({ path: OUT + 'auto_klick.png' });
    await ev(() => { const k = document.getElementById('karte-zu'); if (k) k.click(); });
  } else ok(false, 'kein parkendes Auto');

  // 6b. Lichtkegel am Abend einer echten Eröffnung (bis zu 60 Tage weiter), nicht am Mittag, nicht in der Nacht danach; bleibt nach dem Neuladen
  const kegel = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, g = S.g, T = a.G.test;
    const tag0 = S.tag;
    while (S.tag < tag0 + 60) {
      a.schritt();
      if (S.stunde !== 12) continue;
      const neu = []; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.TECH && g.eroeffnet[b] === S.tag && !g.leer[b]) neu.push(b);
      if (!neu.length) continue;
      a.nachSchritten(); const mittag = T.beams().n;
      while (S.stunde !== 20) a.schritt(); a.nachSchritten(); a.G.licht(20.5);
      const abend = T.beams(), art = neu.map(b => Sim.EROEFFNUNG[g.eroeffnetArt[b]]);
      return { tag: S.tag, neu, art, mittag, abend: abend.n, beams: abend.b, count: abend.count, statisch: abend.statisch }; }
    return null; });
  ok(!!kegel && kegel.mittag === 0 && kegel.abend >= kegel.neu.length && kegel.neu.every(b => kegel.beams.includes(b)) && kegel.count > kegel.statisch,
    `Lichtkegel am Abend einer Eröffnung: ${JSON.stringify(kegel)}`);
  if (kegel) {
    await ev((b) => { const a = __stadt, S = a.S(), c = a.G.controls, x = S.g.x[b] - S.mitte + 0.5, z = S.g.y[b] - S.mitte + 0.5; c.target.set(x, 1, z); a.G.camera.position.set(x + 7, 8, z + 9); c.update(); }, kegel.neu[0]);
    await zu(); await page.waitForTimeout(500); await ev(() => __stadt.G.licht(20.5));
    await page.screenshot({ path: OUT + 'lichtkegel.png' });
    // Neuaufbau wie nach dem Laden (die Darstellung vergisst alles, liest nur S): Der Kegel steht wieder (g.eroeffnet im Spielstand)
    const nach = await ev(() => { const a = __stadt, S = a.S(); a.G.neueStadt(); a.nachSchritten(); return { n: a.G.test.beams().n, stunde: S.stunde }; });
    const nacht = await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 2) a.schritt(); a.nachSchritten(); return a.G.test.beams().n; });
    ok(nach.n >= 1 && nacht === 0, `Lichtkegel nach erneutem Aufbau um ${nach.stunde} Uhr: ${nach.n}; um 2 Uhr in der Nacht danach: ${nacht}`);
  }

  // Draw Calls um 8 Uhr (ffa1d88 in dieser Teststadt 24–26, neue Meshes: Autos und Leuchtlogos)
  const dbg = await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 8) a.schritt(); a.nachSchritten(); a.setzeTempo(1);
    return new Promise(r => setTimeout(() => { a.setzeTempo(0); r(globalThis.__stadtDebug); }, 1500)); });
  ok(dbg.calls <= 29, `Draw Calls ${dbg.calls} (≤ 29), Dreiecke ${dbg.dreiecke}, Einwohner ${dbg.einwohner}`);

  // 8. Karten (Befunde der Schlussprüfung): Vor 8 Uhr nennt keine Karte einen Testfahrer, ab 8 Uhr der, der um 10 Uhr wirklich fährt;
  // Werkskarte ohne „kamen von die …“ und mit so vielen Hallen wie im Bild; Personenkarte eines Autos, das in dieser Stunde fährt: „fährt um …“
  const karten = await ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, g = S.g, G = a.G, T = G.test;
    const karte = (p) => { const k = document.createElement('button'); k.className = 'name'; k.dataset.p = String(p); k.dataset.g = String(S.p.gen[p]); k.dataset.n = '';
      document.body.appendChild(k); k.click(); k.remove(); const t = document.getElementById('karte-inhalt').innerText; document.getElementById('karte-zu').click(); return t; };
    while (S.stunde !== 5) a.schritt(); a.nachSchritten();
    let w = -1; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.TECH && g.werk[b] && !g.leer[b] && g.produkt[b] === Sim.AUTO && S.feld[g.y[b] * S.karte + g.x[b]] === Sim.TECH) { w = b; break; }
    if (w < 0) return null;
    const frueh = Sim.gebaeudeInfo(S, w), beleg = S.belegschaft[w].slice();
    const fruehPersonen = beleg.filter(p => /Testfahrt|Prototyp/.test(karte(p))).length;
    while (S.stunde !== 8) a.schritt(); a.nachSchritten();
    const acht = Sim.gebaeudeInfo(S, w), t8 = Sim.testfahrer(S, w), name8 = t8 >= 0 ? Sim.name(S, t8) : '';
    const karte8 = t8 >= 0 ? karte(t8) : '';
    // ein Auto, das um 8 Uhr mit seinem Besitzer fährt: Karte „fährt um 8 Uhr …“ (und nicht „steht …“)
    let fp = -1; for (let p = 0; p < S.pMax && fp < 0; p++) if (S.p.lebt[p] && S.p.auto[p] && Sim.autoFaehrtJetzt(S, p, 8)) fp = p;
    const fahrKarte = fp >= 0 ? (karte(fp).split('\n').find(z => z.includes(Sim.autoName(S, fp)) && z.includes('gekauft an Tag')) || '') : '';
    while (S.stunde !== 10) a.schritt(); a.nachSchritten();
    return { w, stufe: g.stufe[w], teile: T.werke().find(W => W.b === w), frueh: frueh.mehr.join(' '), fruehFahrer: frueh.testfahrer, fruehPersonen,
      acht: acht.mehr.join(' '), zeile: acht.zeile, name8, karte8: (karte8.split('\n').find(z => /Testfahrt/.test(z)) || ''), fahrer10: Sim.testfahrtStunde(S, w, 10), t8, fahrKarte };
  });
  ok(!!karten && /steht um 8 Uhr fest/.test(karten.frueh) && karten.fruehFahrer === -1 && !karten.fruehPersonen && karten.acht.includes(karten.name8)
    && /Testfahrt mit dem Prototyp heute um 10 und 14 Uhr/.test(karten.karte8) && karten.fahrer10 === karten.t8,
    `Testfahrer in den Karten: um 5 Uhr „${karten && (karten.frueh.match(/Wer heute[^.]*\./) || [''])[0]}“, keine Personenkarte nennt eine Testfahrt (${karten && karten.fruehPersonen}); `
    + `um 8 Uhr ${karten && karten.name8} („${karten && karten.karte8}“), um 10 Uhr fährt ${karten && karten.fahrer10 === karten.t8 ? 'dieselbe Person' : 'eine andere Person'}`);
  ok(!!karten && !/kamen von|von die|von der Bauhof/.test(karten.acht) && new RegExp('^' + (karten.stufe - 1) + ' Hallen').test(karten.zeile),
    `Werkskarte: „${karten && karten.zeile.slice(0, 40)}“ (Stufe ${karten && karten.stufe}, im Bild ${karten && karten.stufe - 1} Hallenteile), `
    + `Lieferant: „${karten && ((karten.acht.match(/Hauptlieferant[^.]*\./) || ['–'])[0])}“`);
  ok(!!karten && /fährt um 8 Uhr (zur Arbeit|nach Hause|zu Besuch|zum Einkaufen)/.test(karten.fahrKarte) && !/steht /.test(karten.fahrKarte),
    `Personenkarte eines fahrenden Autos um 8 Uhr: „${karten && karten.fahrKarte.slice(0, 140)}“`);
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;

  // Campus (Seed 1 hat an Tag 730 einen; bis Version 9, Teil 2 Seed 3, seit dem Haushalt dort keiner mehr: v9/t4/campus.mjs): gezeichnet mit
  // zwei Leuchtlogos und Dachterrasse
  const s3 = await oeffne(b, 'seed=1&tage=730&neu');
  const campus = await s3.ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim, g = S.g, G = a.G;
    while (S.stunde !== 11) a.schritt(); a.nachSchritten();
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.TECH && !g.werk[b] && !g.leer[b] && g.stufe[b] === 4 && S.feld[g.y[b] * S.karte + g.x[b]] === Sim.TECH) {
      const c = G.controls, x = g.x[b] - S.mitte + 0.5, z = g.y[b] - S.mitte + 0.5; c.target.set(x, 0.8, z); G.camera.position.set(x + 2.4, 3.4, z + 3.2); c.update();
      return { b, hoehe: +G.test.techHoehe(b).toFixed(2), name: Sim.gebaeudeInfo(S, b).stufeName }; }
    return null; });
  ok(!!campus && campus.hoehe > 1.7 && campus.hoehe < 2, `Campus (Seed 1): ${JSON.stringify(campus)}`);
  if (campus) { await s3.zu(); await s3.page.waitForTimeout(600); await s3.page.screenshot({ path: OUT + 'campus.png' }); }
  if (s3.log.length) { console.log('Konsole (Seed 1):', s3.log.join('\n  ')); process.exitCode = 1; }
  await s3.ctx.close();

  // 1b. Sprung statt Fahrt: Umzug um 8 Uhr (das Auto kommt an die neue Wohnung, der Besitzer geht von der alten zur Arbeit) und neue Stelle
  // mitten am Tag: nah an der Wohnung (das Auto kommt nach Hause, der Besitzer geht zur neuen Stelle) oder weit weg (das Auto kommt von zu
  // Hause zur neuen Stelle, der Besitzer von der alten). Feste Momente, gefunden mit einem Suchskript beim Bau von Version 8 (nicht im Repo) (selten: in Seeds
  // 1–14 je 730 Tage fünf Fälle); der Test prüft zuerst, dass es den Fall gibt. Version 9 (Rathaus und Bürgermeister): Die Städte laufen
  // anders, neu gesucht auf den Seeds 1–80 (v9/t2/faelle_neu_*.log; Stellenwechsel ohne Umzug gibt es dort nur dreimal)
  // (Version 8: [2, 305, 8, 310], [14, 137, 9, 72], [8, 690, 9, 442]). Version 9, Teil 2 (Schulen): wieder neu gesucht (v9/t3/faelle/f_*.log,
  // Seeds 1–80): Seed 1 bleibt; neue Stelle nah der Wohnung nur noch in Seed 69, weit weg in sechs Seeds, genommen Seed 80 (kurz)
  // (Teil 1: [64, 523, 9, 1080], [16, 334, 9, 620]). Version 9, Teil 3 (Haushalt): wieder neu gesucht (v9/t4/faelle/f_*.log, Seeds 1–80):
  // 39 Umzüge um 8 Uhr, genommen Seed 23 (kurz); Stellenwechsel ohne Umzug nur noch zweimal, Seed 66 nah der Wohnung, Seed 54 weit weg
  // (Teil 2: [1, 206, 8, 118], [69, 221, 9, 219], [80, 234, 9, 298]). Version 9, Teil 4 (Wachstum): wieder neu gesucht (v9/t5/faelle/f_*.log,
  // Seeds 1–80): 37 Umzüge um 8 Uhr, genommen Seed 37 (Tag 35, kurz); Stellenwechsel ohne Umzug zehnmal (dreimal nah der Wohnung, siebenmal
  // weit weg), genommen nah der Wohnung Seed 28 (Tag 113), weit weg Seed 11 (Tag 268), die kürzesten ihrer Art (Teil 3: [23, 188, 8, 182], [66, 264, 9, 237], [54, 260, 9, 405]).
  // Version 9, Teil 5 (Tech-Firmen früher und mehr): wieder neu gesucht (v9/t6/faelle/f_*.log, Seeds 1–80 bis Tag 400): Umzüge um 8 Uhr
  // 25-mal, genommen Seed 21 (Tag 58, kurz); Stellenwechsel ohne Umzug siebenmal, nah der Wohnung nur Seed 63 (Tag 172), weit weg sechsmal,
  // genommen Seed 16 (Tag 72, der kürzeste) (Teil 4: [37, 35, 8, 4], [28, 113, 9, 191], [11, 268, 9, 892])
  for (const [seed, tag, H, p, was] of [[21, 58, 8, 32, 'Umzug um 8 Uhr'], [63, 172, 9, 145, 'neue Stelle nah der Wohnung'], [16, 72, 9, 56, 'neue Stelle weit weg']]) {
    const o = await oeffne(b, `seed=${seed}&tage=${tag}&neu`);
    const r1 = await o.ev(({ H, p }) => {
      const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, G = a.G, T = G.test, THREE = G.THREE;
      while (S.stunde !== H - 2) a.schritt();
      Sim.hauptSetzen(S, p, P.gen[p], true, 10);
      a.schritt(); a.nachSchritten(); T.planeAlle();          // Vorstunde
      const v = { wohnung: P.wohnung[p], ort: Sim.ortZurStunde(S, p, H - 1), auto: T.aOrt()[p] };
      a.schritt(); a.nachSchritten(); T.planeAlle();          // die Stunde
      const n = { wohnung: P.wohnung[p], ort: Sim.ortZurStunde(S, p, H), auto: Sim.autoOrt(S, p, H) };
      const fall = v.auto >= 0 && n.auto !== v.auto && Sim.mitAuto(S, p, v.auto, n.auto) && (v.ort !== v.auto || n.ort !== n.auto);
      let i = -1; for (let k = 0; k < T.tripN(); k++) if (T.fahrt(k).p === p) i = k;
      const f = i >= 0 ? T.fahrt(i) : null, k = T.figuren.findIndex(x => x.p === p && x.haupt);
      const mark = G.scene.children.find(x => x.isInstancedMesh && x.count <= 11 && x.renderOrder === 2);
      const m = new THREE.Matrix4(), c = new THREE.Vector3(), w = new THREE.Vector3(), out = [];
      for (let u = 0.05; u < 1; u += 0.1) {
        G.figurenBewegen(S.tag * 24 + H + u);
        const sicht = T.figIds.indexOf(p) >= 0;
        let rf = 1e9;
        if (sicht && k >= 0 && mark) {
          G.figMesh.getMatrixAt(k, m); c.setFromMatrixPosition(m);
          for (let j = 0; j < mark.count; j++) { mark.getMatrixAt(j, m); w.setFromMatrixPosition(m); rf = Math.min(rf, Math.hypot(w.x - c.x, w.z - c.z)); }
        }
        let aq = null;
        if (i >= 0) { G.M.auto.getMatrixAt(T.autoStatisch() + i, m); const e = m.elements; aq = e[0] * e[0] + e[1] * e[1] + e[2] * e[2] > 0.25 ? [+e[12].toFixed(2), +e[14].toFixed(2)] : 'weg'; }
        out.push({ u: +u.toFixed(2), sicht, rauteFigur: +rf.toFixed(3), auto: aq });
      }
      return { v, n, fall, fahrt: f && { von: f.von, ziel: f.ziel, mit: f.mit, n: f.n }, proben: out, name: Sim.name(S, p) };
    }, { H, p });
    ok(r1.fall && r1.fahrt && !r1.fahrt.mit && !r1.fahrt.n && r1.proben.every(x => x.sicht && x.rauteFigur < 0.05),
      `${was} (Seed ${seed}, Tag ${tag}, ${H} Uhr, ${r1.name}): Auto ${r1.v.auto} → ${r1.n.auto}, Besitzer ${r1.v.ort} → ${r1.n.ort}, Wohnung ${r1.v.wohnung} → ${r1.n.wohnung}; `
      + `Fahrt ${JSON.stringify(r1.fahrt)} (Sprung, kein Weg); Figur die ganze Stunde zu sehen, Raute über ihr: ${r1.proben.map(x => (x.sicht ? 'F' : '-') + (x.rauteFigur < 0.05 ? 'R' : '-')).join(' ')}`);
    if (o.log.length) { console.log('Konsole:', o.log.join('\n  ')); process.exitCode = 1; }
    await o.ctx.close();
  }
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
