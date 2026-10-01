// Ereignis-Zeichen (Design-Runde 5, Paket M): Ring am Boden bei fertig gebaut, eröffnet/übernommen, Pleite/Schließung.
// Nicht beim Aufbau, nach Sprüngen, beim Aufholen, nach neuer Stadt; bei 20× höchstens 3 je Stunde; reduziert still;
// Draw Calls +1 nur solange sichtbar, beim Erscheinen kein Programm übersetzt (das eine eigene übersetzt schon der Start).
// Pleite/Schließung zieht sich zusammen, sonst wächst der Ring. Fernblick: Ring im Bild mindestens 20 px Radius (c am Ende 10) und auf dem
// Sehstrahl zur Kamera gerückt (Ort im Bild wie am Boden). Uhr angehalten (performance.now fest), Teststadt Seed 3, Tag 400 (Version 9: Seed 4, Tag 400; Version 9, Teil 4: Seed 5, Tag 400; Teil 2 und 3: Seed 4, Tag 400; Teil 1: Seed 4, Tag 500; bis Version 8: Seed 2, Tag 400)
const U = require('./umgebung.cjs');
const { chromium } = U;
// Momente der Teststadt (Seed 2, Stunde = Tag · 24 + Uhr). Seit den Autos (Version 8) läuft die Stadt wieder anders; nach der Schlussprüfung
// (gemischte Reihenfolge der Käufer) noch einmal, gesucht mit v8/mess2/momente9.mjs bis Tag 830, ohne Stunden mit einem Umbau zur Kita, einer
// gewachsenen Karte oder einem Gebäude auf einem Gelände (Werk, Anstalt, Kaserne): Tag 422, 0 Uhr drei Schließungen allein; Tag 449, 8 Uhr
// vier Übernahmen allein (bei 20× höchstens 3 Zeichen); Tag 452, 0 Uhr ein Bau fertig (in den zwei Stunden davor genau einer); Tag 490,
// 0 Uhr ein Bau fertig und eine Schließung. Erst die Pleiten, dann die Übernahmen bei 20× (wie seit Teil 1 von Version 8)
// (Version 8 bis zur Schlussprüfung: 405, 446, 466, 478; Version 7: 599, 639, 683, 721; Teil 2: 572, 612, 617, 683; bis Teil 1: 560, 600, 634, 717)
// Version 9 (Rathaus und Bürgermeister): In Seed 2 gibt es von Tag 400 bis 1000 keine Stunde mehr mit vier Übernahmen oder Fertigstellungen
// ohne Schließung (v9/t2/momente10.mjs); die Teststadt ist deshalb Seed 4 ab Tag 500: Tag 521, 0 Uhr vier Schließungen allein; Tag 565,
// 8 Uhr vier Übernahmen allein; Tag 567, 0 Uhr ein Bau fertig (in den zwei Stunden davor genau einer); Tag 568, 0 Uhr ein Bau fertig und
// eine Schließung (Version 8, Seed 2: 422, 449, 452, 490)
// Version 9, Teil 2 (Schulen): Die Stadt läuft wieder anders; neu gesucht mit v9/t2/momente10.mjs (Seed 4 ab Tag 400, Protokoll
// v9/t3/momente_neu.log): Tag 440, 0 Uhr vier Schließungen allein; Tag 483, 8 Uhr zwölf Übernahmen allein; Tag 486, 0 Uhr ein Bau fertig
// (in den zwei Stunden davor genau einer); Tag 489, 0 Uhr ein Bau fertig und eine Schließung. Die Teststadt beginnt deshalb an Tag 400
// (Teil 1: Tag 500 mit 521, 565, 567, 568)
// Version 9, Teil 3 (Haushalt): Die Stadt läuft wieder anders; neu gesucht mit v9/t2/momente10.mjs (Seed 4 ab Tag 400, Protokoll
// v9/t4/momente_teil3.log): Tag 407, 0 Uhr vier Schließungen allein; Tag 426, 8 Uhr 23 Übernahmen allein; Tag 428, 0 Uhr ein Bau fertig (in den
// zwei Stunden davor genau einer); Tag 559, 0 Uhr ein Bau fertig und eine Schließung (Teil 2: 440, 483, 486, 489)
// Version 9, Teil 4 (Wachstum): Mit dem Anlauf läuft die Stadt wieder anders. Neu gesucht mit demselben Skript (Seeds 2 bis 6 ab Tag 400,
// Protokolle v9/t5/momente_teil4.log und v9/t5/mom/m*.log): In Seed 4 gäbe es die Stunde mit Bau und Schließung erst an Tag 1066; Seed 5
// hat alle vier dicht beieinander, die Teststadt ist deshalb Seed 5 ab Tag 400: Tag 425, 0 Uhr drei Schließungen allein; Tag 446, 8 Uhr sechs
// Übernahmen allein (bei 20× höchstens 3 Zeichen); Tag 455, 0 Uhr ein Bau fertig (in den zwei Stunden davor genau einer); Tag 456, 0 Uhr ein
// Bau fertig und eine Schließung (Teil 3, Seed 4: 407, 426, 428, 559)
// Version 9, Teil 5 (Tech-Firmen früher und mehr): Die Stadt läuft wieder anders; neu gesucht mit demselben Skript (Seeds 2, 4, 5 ab Tag 400,
// Protokolle v9/t6/mom/m*.log): Seed 5 hat die vier Stunden nicht mehr bis Tag 830, Seed 4 dicht beieinander; die Teststadt ist deshalb wieder
// Seed 4 ab Tag 400: Tag 406, 0 Uhr drei Schließungen allein; Tag 443, 8 Uhr 17 Übernahmen allein (bei 20× höchstens 3 Zeichen); Tag 449, 0 Uhr
// ein Bau fertig (in den zwei Stunden davor genau einer); Tag 457, 0 Uhr ein Bau fertig und eine Schließung (Teil 4, Seed 5: 425, 446, 455, 456)
// Schlussprüfung von Version 9 (Zuzug genau nach R10, Übernahme mit offenem Anbau): Die Stadt läuft wieder anders; neu gesucht mit demselben
// Skript (Seeds 2 bis 5 ab Tag 400, Protokolle v9/t7/mom/m*.log): Seed 4 hat die vier Stunden weiter dicht beieinander: Tag 423, 0 Uhr drei
// Schließungen allein; Tag 457, 8 Uhr 17 Übernahmen allein (bei 20× höchstens 3 Zeichen); Tag 460, 0 Uhr ein Bau fertig (in den zwei Stunden
// davor genau einer); Tag 474, 0 Uhr ein Bau fertig und eine Schließung (Teil 5: 406, 443, 449, 457)
// Version 10 (Etappe 2: Gedächtnis, Erfahrung, Plan): Die Stadt läuft wieder anders; neu gesucht mit demselben Skript (ml/e2bau/werkzeug/
// s4_momente10.mjs, Seeds 4, 2, 3, 5 ab Tag 400 bis 830, Protokoll ml/e2bau/mess/schritt4/momente/ereignis.txt): In Seed 4 und 2 gibt es nach
// den Schließungen keine Stunde mit vier Übernahmen mehr; Seed 3 hat alle vier, die Teststadt ist deshalb Seed 3 ab Tag 400: Tag 401, 0 Uhr drei
// Schließungen allein; Tag 519, 8 Uhr vier Übernahmen allein (bei 20× höchstens 3 Zeichen); Tag 520, 0 Uhr ein Bau fertig (in den zwei Stunden
// davor genau einer); Tag 549, 0 Uhr ein Bau fertig und eine Schließung (Schlussprüfung von Version 9, Seed 4: 423, 457, 460, 474)
const PLEITE_H = 401 * 24, PLEITEN = 3, UEBER_H = 519 * 24 + 8, UEBERNAHMEN = 4, AUFHOL_H = 520 * 24, AUFHOL_FERTIG = 1, FERN_H = 549 * 24, FERN_N = 2;
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, reduziert) {
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, reducedMotion: reduziert ? 'reduce' : 'no-preference' });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (r) => r.abort());
  const page = await ctx.newPage(), log = [];
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) log.push('error: ' + m.text()); });
  await page.goto(U.HOST + '/stadt.html?debug&seed=3&tage=400&neu', { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await page.evaluate(() => { __stadt.setzeTempo(0); const echt = performance.now.bind(performance);
    globalThis.__fest = null; globalThis.__echt = echt; performance.now = () => globalThis.__fest ?? echt(); });
  return { page, log, ctx };
}
// zwei Bilder abwarten (frame() zeichnet vor diesem Rückruf), dann Zustand des Zeichen-Meshes
const bilder = (page) => page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
// Je Zeichen der Ort am Boden (Sehstrahl durch die Mitte bis y 0,052), Seitenlänge am Boden, Höhe der Mitte, Radius im Bild (px)
const lage = (page) => page.evaluate(() => { const { G } = __stadt, z = G.test.zeichen, a = z.geometry.getAttribute('zeichenAlpha').array, K = __stadt.S().karte;
  const c = G.camera.position, V = G.THREE.Vector3, h = G.renderer.domElement.clientHeight, w = G.renderer.domElement.clientWidth;
  const inst = []; for (let i = 0; i < z.count; i++) { const m = z.instanceMatrix.array, px = m[16 * i + 12], py = m[16 * i + 13], pz = m[16 * i + 14];
    const t = (0.052 - c.y) / (py - c.y), gx = c.x + (px - c.x) * t, gz = c.z + (pz - c.z) * t, s = m[16 * i] * t;
    const p0 = new V(gx, 0.052, gz).project(G.camera), p1 = new V();
    let r = 0; for (let k = 0; k < 16; k++) { p1.set(gx + 0.4 * s * Math.cos(k * Math.PI / 8), 0.052, gz + 0.4 * s * Math.sin(k * Math.PI / 8)).project(G.camera);
      r = Math.max(r, Math.hypot((p1.x - p0.x) * w / 2, (p1.y - p0.y) * h / 2)); }   // größter Radius der Ellipse im Bild
    inst.push({ x: gx + K / 2 - 0.5, z: gz + K / 2 - 0.5, s, y: py, px: r, a: a[i], r: z.instanceColor.array[3 * i] }); }
  return { n: z.count, sichtbar: z.visible, calls: G.renderer.info.render.calls, dreiecke: G.renderer.info.render.triangles, programme: G.renderer.info.programs.length, inst }; });
async function zeit(page, ms) { await page.evaluate((ms) => { globalThis.__fest = globalThis.__t0 + ms; }, ms); await bilder(page); return lage(page); }
// bis eine Stunde vor ziel in einem Sprung, dann einen Stundenschritt mit angehaltener Uhr; Rückgabe: geänderte Gebäude
const bisVor = (page, ziel) => page.evaluate((ziel) => { const S = __stadt.S(); let n = 0; while (S.tag * 24 + S.stunde < ziel - 1 && n++ < 20000) __stadt.schritt(); __stadt.nachSchritten(); }, ziel);   // höchstens 20.000 Stunden (vorher 5.000: reichte nur bis Tag 608)
const stunde = (page) => page.evaluate(() => {
  const S = __stadt.S(), g = S.g, K = __stadt.S().karte, v = [];
  for (let b = 0; b < S.gAnzahl; b++) v.push([S.feld[g.y[b] * K + g.x[b]], g.leer[b], g.stufe[b]]);
  globalThis.__t0 = Math.max(__echt(), (globalThis.__fest || 0) + 5000); globalThis.__fest = __t0;
  __stadt.schritt(); __stadt.nachSchritten();
  const bs = [];
  for (let b = 0; b < v.length; b++) if (S.feld[g.y[b] * K + g.x[b]] !== v[b][0] || g.leer[b] !== v[b][1] || g.stufe[b] !== v[b][2]) bs.push([g.x[b], g.y[b]]);
  return bs;
});
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  {
    const { page, log, ctx } = await seite(b, false);
    await bilder(page);
    const start = await lage(page);
    ok(start.n === 0, `erster Aufbau: kein Zeichen (${start.n})`);
    ok(await page.evaluate(() => !Object.values(__stadt.G.M).includes(__stadt.G.test.zeichen) && __stadt.G.test.zeichen.renderOrder !== 2), 'Zeichen nicht in M (nicht klickbar), keine Rauten-Reihenfolge');
    // Pleiten (Stadtbuch), alle als Betrieb offen → leer
    await bisVor(page, PLEITE_H);
    await page.evaluate(() => { globalThis.__t0 = Math.max(__echt(), (globalThis.__fest || 0) + 5000); globalThis.__fest = __t0; });
    const vor = await zeit(page, 0);
    ok(vor.n === 0, `Sprung über viele Stunden: kein Zeichen (${vor.n})`);
    const bs = await stunde(page);
    // Die Zeichen beginnen je 0,2 s versetzt: Das letzte von PLEITEN beginnt bei 0,2 · (PLEITEN − 1) s, gezählt wird 0,1 s danach
    // (Teil 2: sieben Schließungen, 1,3 s; Teil 3 vier, 0,7 s; seit Teil 4 drei, 0,5 s)
    const l1 = await zeit(page, 200 * (PLEITEN - 1) + 100);
    const passt = l1.inst.every(i => bs.some(([x, y]) => Math.abs(x - i.x) < 5e-3 && Math.abs(y - i.z) < 5e-3));
    ok(l1.n === PLEITEN && bs.length === PLEITEN && passt, `Tag ${PLEITE_H / 24} 0 Uhr: ${l1.n} Zeichen für ${bs.length} geänderte Betriebe, Lage passt: ${passt}`);
    ok(l1.inst.every(i => i.r < 0.5), `Pleite/Schließung gedämpft rot (Rotkanal linear ${l1.inst.map(i => i.r.toFixed(2)).join(', ')})`);
    ok(l1.calls === vor.calls + 1, `Draw Calls ${vor.calls} → ${l1.calls} (+1 nur mit Zeichen)`);
    ok(l1.programme === vor.programme, `beim Erscheinen kein Programm übersetzt (${vor.programme} → ${l1.programme})`);
    ok(!vor.sichtbar && l1.sichtbar, `Mesh nur mit Zeichen sichtbar (vorher ${vor.sichtbar}, mit Zeichen ${l1.sichtbar})`);
    const l15 = await zeit(page, 1500);
    ok(l15.inst[0].s < l1.inst[0].s && l15.inst[0].a < l1.inst[0].a, `Pleite/Schließung: Ring zieht sich zusammen (${l1.inst[0].s.toFixed(2)} → ${l15.inst[0].s.toFixed(2)}) und verblasst (${l1.inst[0].a.toFixed(2)} → ${l15.inst[0].a.toFixed(2)})`);
    const l4 = await zeit(page, 4200);
    ok(l4.n === 0 && l4.calls === vor.calls && !l4.sichtbar, `nach 4,2 s: ${l4.n} Zeichen, Draw Calls ${l4.calls}, sichtbar ${l4.sichtbar}`);
    ok(l1.dreiecke - l4.dreiecke === 2 * l1.n, `Dreiecke mit ${l1.n} Zeichen +${l1.dreiecke - l4.dreiecke} (2 je Zeichen)`);
    // Sprung über einen Tag: nichts
    await page.evaluate(() => { for (let i = 0; i < 24; i++) __stadt.schritt(); __stadt.nachSchritten(); });
    ok((await zeit(page, 4300)).n === 0, 'Sprung über 24 Stunden: kein Zeichen');
    // 20×: viele Übernahmen in einer Stunde → höchstens 3 (Version 8: nach den Pleiten, siehe Momente oben)
    await bisVor(page, UEBER_H);
    const bs20 = await page.evaluate(() => { __stadt.setzeTempo(20); globalThis.__t0 = Math.max(__echt(), (globalThis.__fest || 0) + 5000); globalThis.__fest = __t0;
      const S = __stadt.S(); __stadt.schritt(); __stadt.nachSchritten(); __stadt.setzeTempo(0); return S.tag * 24 + S.stunde; });
    const l20 = await zeit(page, 1500), l20b = await zeit(page, 2000);
    ok(bs20 === UEBER_H && l20.n === 3 && l20.inst.every(i => i.r > 0.9), `20×: ${l20.n} von ${UEBERNAHMEN} Zeichen (Akzent)`);
    ok(l20b.inst[0].s > l20.inst[0].s, `eröffnet: Ring wächst (${l20.inst[0].s.toFixed(2)} → ${l20b.inst[0].s.toFixed(2)})`);
    // Aufholen über zwei Stunden mit fertigem Bau (um Mitternacht): keine Zeichen
    await bisVor(page, AUFHOL_H - 1);
    const auf = await page.evaluate(async () => { globalThis.__t0 = Math.max(__echt(), (globalThis.__fest || 0) + 5000); globalThis.__fest = __t0; const S = __stadt.S(), vor = S.stat.bau.fertig;
      await __stadt.aufholen(2 * 60000); return { h: S.tag * 24 + S.stunde, fertig: S.stat.bau.fertig - vor }; });
    const lA = await zeit(page, 1000);
    ok(auf.h === AUFHOL_H && auf.fertig === AUFHOL_FERTIG && lA.n === 0, `Aufholen bis Tag ${AUFHOL_H / 24} 0 Uhr (${auf.fertig} fertig): ${lA.n} Zeichen`);
    // Neue Stadt (Import): laufende Zeichen weg, keine neuen
    // Fernblick (Abstand 120): Ring am Ende mindestens 20 px Radius, zur Kamera gerückt, im Bild am richtigen Gebäude
    await bisVor(page, FERN_H);
    await page.evaluate(() => { const { G } = __stadt, t = G.controls.target; G.camera.position.set(t.x + 0.45 * 119, 0.62 * 119, t.z + 0.65 * 119); G.controls.update(); });
    const bsF = await stunde(page);
    const lN0 = await zeit(page, 1000), lF = await zeit(page, 2500);
    const passtF = lF.inst.every(i => bsF.some(([x, y]) => Math.abs(x - i.x) < 5e-3 && Math.abs(y - i.z) < 5e-3));
    ok(lF.n === FERN_N && passtF && lF.inst.every(i => i.px >= (i.r < 0.5 ? 9.5 : 19.5) && i.y > 1), `Fernblick: ${lF.n} Zeichen, Lage passt: ${passtF}, Radius am Ende ${lF.inst.map(i => i.px.toFixed(1) + (i.r < 0.5 ? ' (c, auf die Hälfte zusammengezogen)' : '')).join(', ')} px, Höhe der Mitte ${lF.inst.map(i => i.y.toFixed(2)).join(', ')}`);
    await page.evaluate(() => { __stadt.G.neueStadt(); __stadt.nachSchritten(); });
    const lN = await zeit(page, 1100);
    ok(lN0.n === FERN_N && lN.n === 0, `neue Stadt: ${lN0.n} → ${lN.n} Zeichen`);
    await page.evaluate(() => { globalThis.__fest = null; });
    ok(!log.length, 'Konsole: ' + (log.join(' | ') || 'leer'));
    await ctx.close();
  }
  {
    const { page, log, ctx } = await seite(b, true);
    await bisVor(page, PLEITE_H);
    await stunde(page);
    const r1 = await zeit(page, 500), r2 = await zeit(page, 2500), r3 = await zeit(page, 3100);
    const still = r1.n === PLEITEN && r2.n === PLEITEN && r1.inst.every((i, k) => i.s === r2.inst[k].s && i.a === r2.inst[k].a);
    ok(still, `reduziert: ${r1.n}/${r2.n} Zeichen, gleich groß (${r1.inst[0] && r1.inst[0].s.toFixed(2)}) und gleich deutlich (${r1.inst[0] && r1.inst[0].a.toFixed(2)}) bei 0,5 und 2,5 s`);
    ok(r3.n === 0, `reduziert: nach 3,1 s weg (${r3.n})`);
    await page.evaluate(() => { globalThis.__fest = null; });
    ok(!log.length, 'Konsole (reduziert): ' + (log.join(' | ') || 'leer'));
    await ctx.close();
  }
  await b.close();
})();
