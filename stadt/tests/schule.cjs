// Schule (Version 9, Teil 2) im Browser: Schulhaus und Schulhof im Bild, echter Klick (Raycast) aufs Schulhaus öffnet die Hauskarte
// (Lehrkräfte vom Land, Plätze, Lehrkraft je 13,6 Kinder, Computer, Liste „Schülerinnen und Schüler“), Personenkarte eines Schulkinds (Klasse,
// Knopf zur Schule), Figuren Stunde für Stunde (Grundregel: Schulkinder nur auf dem Schulweg um 8 und 13 und um 10 in der Pause auf dem Hof
// ihrer Schule, auf festen Plätzen ohne Überschneidung, nicht auf den Plätzen der Lehrkräfte; nachmittags und nachts keine), Autos der
// Lehrkräfte vor der Schule, Fenster „Stadtregierung“ (Gruppe „Schule“, drei Karten, Zahlen ohne NaN), Draw Calls gegen stadt.orig.html
// (höchstens +3), Handy 400 × 820 ohne seitliches Überlaufen, Konsole leer.
// Server: tests/alle.sh (PORT, Wurzel stadt/). Bilder: tests/ausgabe/bilder_befunde/schule_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, url, viewport) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  await U.fassungUnter(ctx, 'v8');   // stadt.orig.html = Version 8 (Git 31ce452) per git show, Vergleichsstand wie im Bau von Version 9
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  await page.goto(url, { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await page.evaluate(() => __stadt.setzeTempo(0));
  const ev = (f, a) => page.evaluate(f, a);
  const zu = async () => { for (let i = 0; i < 30; i++) {
    const o = await ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
      for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
    await page.waitForTimeout(100); if (!o) break; } };
  await zu();
  return { ctx, page, log, ev, zu };
}
// Die Schule einer Art mit den meisten Schülern; Richtung zur Straße (wie strassenSeite in der Darstellung)
const schuleSuchen = (ev, art) => ev((art) => { const S = __stadt.S(), Sim = __stadt.Sim, g = S.g, K = S.karte;
  let best = -1, n = -1;
  for (let x = 0; x < S.gAnzahl; x++) if (g.typ[x] === Sim.SCHULE && g.stufe[x] === art && S.feld[g.y[x] * K + g.x[x]] === Sim.SCHULE && g.bedient[x] > n) { n = g.bedient[x]; best = x; }
  if (best < 0) return null;
  const x = g.x[best], y = g.y[best]; let dx = 0, dz = 1;
  for (const [a, c] of [[0, 1], [1, 0], [0, -1], [-1, 0]]) if (S.feld[(y + c) * K + (x + a)] === Sim.STRASSE) { dx = a; dz = c; break; }
  return { b: best, x, y, dx, dz, n, px: x - S.mitte + 0.5, pz: y - S.mitte + 0.5 }; }, art);
// Blick schräg von der Straßenseite auf Haus und Hof (nur im Test; die Seite bewegt die Kamera nie von selbst)
const blick = (ev, s, abst, hoch) => ev(([s, abst, hoch]) => { const { G } = __stadt, c = G.controls, cam = G.camera; c.minDistance = 1;
  c.target.set(s.px, 0.15, s.pz); cam.position.set(s.px + s.dx * abst + s.dz * abst * 0.45, hoch, s.pz + s.dz * abst - s.dx * abst * 0.45); c.update(); cam.updateMatrixWorld(); }, [s, abst, hoch]);
const stunde = (ev, H) => ev((H) => { const a = __stadt, S = a.S(); let n = 0; while (S.stunde !== H && n++ < 48) a.schritt(); a.nachSchritten(); a.G.figurenBewegen(S.tag * 24 + H + 0.5); }, H);

(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const TAGE = 330;
  const A = await seite(b, `${U.HOST}/stadt.html?debug&seed=2&tage=${TAGE}&neu`);
  const gs = await schuleSuchen(A.ev, 1), ws = await schuleSuchen(A.ev, 2);
  ok(gs && ws && gs.n > 0 && ws.n > 0, `Seed 2, Tag ${TAGE}: Grundschule (Gebäude ${gs && gs.b}, ${gs && gs.n} Kinder) und weiterführende Schule (Gebäude ${ws && ws.b}, ${ws && ws.n} Kinder) offen`);

  // 1. Figuren Stunde für Stunde (Grundregel)
  const erg = [], fehl = [];
  for (const H of [7, 8, 9, 10, 11, 13, 14, 17, 21, 3]) {
    const r = await A.ev((H) => {
      const a = __stadt, S = a.S(), T = a.G.test, P = S.p, g = S.g, Sim = a.Sim, fehl = [];
      let n = 0; while (S.stunde !== H && n++ < 48) a.schritt();
      a.nachSchritten(); const jetzt = S.tag * 24 + H + 0.5; a.G.figurenBewegen(jetzt);
      const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), k0 = T.FIG_MAX + T.HAUPT_MAX;
      const pos = (i) => { a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4); return [v.x, v.z]; };
      let kinder = 0, gehen = 0, stehen = 0, hofFremd = 0;
      const hof = new Map();                                   // Schule → Punkte stehender Figuren [x, z, kind]
      for (let i = 0; i < T.figuren.length; i++) {
        const p = T.figIds[i]; if (p < 0) continue;
        const f = T.figuren[i], ro = f.route, unterwegs = ro && jetzt >= f.start && jetzt < f.start + f.dauer && ro.len > 0;
        const [x, z] = pos(i);
        if (i >= k0) {                                         // Platz eines Schulkinds
          kinder++;
          const s = P.schule[p] - 1;
          if (s < 0 || !f.kind) { fehl.push(`${H} Uhr: Figur ${i} ohne Schulplatz`); continue; }
          if (H < 8 || H > 13) fehl.push(`${H} Uhr: Schulkind ${Sim.name(S, p)} zu sehen`);
          if (unterwegs) { gehen++; if (H !== 8 && H !== 13) fehl.push(`${H} Uhr: Schulkind unterwegs`); }
          else if (f.steht) {
            stehen++;
            const sx = g.x[s] - S.mitte + 0.5, sz = g.y[s] - S.mitte + 0.5;
            if (H !== 10 || Math.abs(x - sx) > 0.5 || Math.abs(z - sz) > 0.5 || Sim.ortZurStunde(S, p, H) !== s) fehl.push(`${H} Uhr: Schulkind steht nicht auf dem Hof seiner Schule`);
            (hof.get(s) || hof.set(s, []).get(s)).push([x, z, f.skala, 'k']);
          } else if (Sim.ortZurStunde(S, p, H) < 0) fehl.push(`${H} Uhr: Schulkind zu sehen, ohne Ort`);
        } else if (f.steht && !unterwegs) {                   // Erwachsene, die auf einem Schulhof stehen: nur Lehrkräfte dieser Schule
          for (let s = 0; s < S.gAnzahl; s++) {
            if (g.typ[s] !== Sim.SCHULE) continue;
            const sx = g.x[s] - S.mitte + 0.5, sz = g.y[s] - S.mitte + 0.5;
            if (Math.abs(x - sx) < 0.47 && Math.abs(z - sz) < 0.47) {
              if (P.arbeit[p] !== s || !T.beiDerArbeit(p, H, s)) hofFremd++;
              (hof.get(s) || hof.set(s, []).get(s)).push([x, z, 1, 'l']);
            }
          }
        }
      }
      // Abstand: niemand steht im anderen (Radius einer Figur 0,055 × Größe)
      let eng = 0, engLehr = 0;
      for (const L of hof.values()) for (let i = 0; i < L.length; i++) for (let j = i + 1; j < L.length; j++) {
        const d = Math.hypot(L[i][0] - L[j][0], L[i][1] - L[j][1]);
        if (d < 0.055 * (L[i][2] + L[j][2]) * 0.8) { if (L[i][3] !== L[j][3]) engLehr++; else eng++; }
      }
      if (hofFremd) fehl.push(`${H} Uhr: ${hofFremd} Erwachsene ohne Stelle dort auf einem Schulhof`);
      return { H, kinder, gehen, stehen, eng, engLehr, fehl, schulen: hof.size };
    }, H);
    erg.push(`${r.H}:${r.kinder}/${r.gehen}/${r.stehen}`); fehl.push(...r.fehl);
    if (r.eng || r.engLehr) fehl.push(`${r.H} Uhr: ${r.eng} Kinder ineinander, ${r.engLehr} Kinder auf Lehrkräften`);
    if (H === 8) { await blick(A.ev, gs, 2.2, 1.6); await A.page.waitForTimeout(700); await A.zu(); await A.page.screenshot({ path: BILD + 'schule_8uhr.png' }); }
    if (H === 10) {
      await blick(A.ev, gs, 1.3, 1.05); await A.page.waitForTimeout(700); await A.zu(); await A.page.screenshot({ path: BILD + 'schule_nah_pause.png' });
      await blick(A.ev, ws, 1.5, 1.25); await A.page.waitForTimeout(700); await A.zu(); await A.page.screenshot({ path: BILD + 'schule_nah_weiter.png' });
    }
    if (H === 21) { await blick(A.ev, gs, 1.6, 1.4); await A.page.waitForTimeout(700); await A.zu(); await A.page.screenshot({ path: BILD + 'schule_nacht.png' }); }
  }
  const z = (h) => erg.find(x => x.startsWith(h + ':'));
  ok(!fehl.length && /:[1-9]\d*\/[1-9]/.test(z(8)) && /\/[1-9]\d*$/.test(z(10)) && ['7', '14', '17', '21', '3'].every(h => z(h) === h + ':0/0/0'),
    `Schulkinder (Stunde:Figuren/gehen/stehen) ${erg.join(' ')}: um 8 und 13 auf dem Schulweg, um 10 auf dem Hof ihrer Schule, sonst drinnen; nachmittags, abends und nachts keine; niemand steht im anderen`
    + (fehl.length ? '\n  ' + [...new Set(fehl)].slice(0, 8).join('\n  ') : ''));

  // 2. Autos der Lehrkräfte vor der Schule (Grundregel: nur, wer selbst mit dem Auto zur Schule fährt)
  await stunde(A.ev, 10);
  const au = await A.ev(() => { const S = __stadt.S(), Sim = __stadt.Sim, P = S.p, g = S.g, L = [];
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.SCHULE) for (const w of S.belegschaft[b]) if (P.auto[w]) L.push({ w, b, ort: Sim.autoOrt(S, w, 10), da: Sim.ortZurStunde(S, w, 10), mit: Sim.pendeltMitAuto(S, w) });
    let kind = 0; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && S.tag - P.geb[p] < 180 && P.auto[p]) kind++;
    return { L, kind }; });
  const vorSchule = au.L.filter(x => x.ort === x.b), falsch = au.L.filter(x => (x.ort === x.b) !== (x.mit && x.da === x.b));
  ok(!falsch.length && !au.kind, `Autos: ${au.L.length} Lehrkräfte haben eins, ${vorSchule.length} parken um 10 Uhr an ihrer Schule (nur wer selbst damit hingefahren ist); Kinder haben keine Autos`);
  if (vorSchule.length) { const s = await A.ev((b) => { const S = __stadt.S(), g = S.g, K = S.karte; let dx = 0, dz = 1;
      for (const [a, c] of [[0, 1], [1, 0], [0, -1], [-1, 0]]) if (S.feld[(g.y[b] + c) * K + (g.x[b] + a)] === __stadt.Sim.STRASSE) { dx = a; dz = c; break; }
      return { b, dx, dz, px: g.x[b] - S.mitte + 0.5, pz: g.y[b] - S.mitte + 0.5 }; }, vorSchule[0].b);
    await blick(A.ev, s, 1.8, 1.3); await A.page.waitForTimeout(700); await A.zu(); await A.page.screenshot({ path: BILD + 'schule_autos.png' }); }

  // 3. Echter Klick aufs Schulhaus (Raycast) öffnet die Hauskarte
  await stunde(A.ev, 11);
  await blick(A.ev, gs, 0.7, 3.2); await A.page.waitForTimeout(600); await A.zu();   // steil von oben: kein Haus davor
  const p = await A.ev((s) => { const { G } = __stadt, x = s.px - s.dx * 0.27, zz = s.pz - s.dz * 0.27;
    const v = new G.THREE.Vector3(x, 0.5, zz).project(G.camera), c = G.renderer.domElement.getBoundingClientRect();
    return { x: c.left + (v.x + 1) / 2 * c.width, y: c.top + (1 - v.y) / 2 * c.height }; }, gs);
  await A.page.mouse.click(p.x, p.y); await A.page.waitForTimeout(600);
  const k = await A.ev(() => ({ offen: !document.getElementById('karte').hidden, titel: (document.querySelector('#karte h2') || {}).textContent || '', text: document.getElementById('karte-inhalt').innerText }));
  ok(k.offen && /^Grundschule /.test(k.titel) && /Gebäude der Stadt, \d+ Lehrkr(aft|äfte) vom Land \(Bedarf \d+\), Lohn 103 Taler am Tag vom Land/.test(k.text)
    && /Platz für 152 \(8 Klassenräume für Klassen bis 19 Kinder\)/.test(k.text) && /eine Lehrkraft je 13,6 Kinder/.test(k.text) && /Computer: \d+ von \d+/.test(k.text)
    && /^schülerinnen und schüler \(\d+\)$/im.test(k.text) && /Klasse [1-4]/.test(k.text) && !/NaN|undefined/.test(k.text),
    `Klick aufs Schulhaus: „${k.titel}“; Lehrkräfte vom Land, Plätze, Lehrkraft je 13,6 Kinder, Computer, Schülerliste` + (k.offen ? '' : ' (Karte zu)')
    + (/13,6/.test(k.text) ? '' : '\n  ' + k.text.slice(0, 700).replace(/\n+/g, ' | ')));
  await A.page.screenshot({ path: BILD + 'schule_hauskarte.png' });
  // Personenkarte eines Schulkinds aus der Liste; Knopf zurück zur Schule
  const kn = await A.ev(() => { const L = [...document.querySelectorAll('#karte-inhalt ul.personenliste')].pop(); const btn = L && L.querySelector('button.name'); if (btn) btn.click(); return !!btn; });
  await A.page.waitForTimeout(500);
  const pk = await A.ev(() => ({ text: document.getElementById('karte-inhalt').innerText, schulKnopf: !!document.querySelector('#karte-inhalt button.haus') }));
  ok(kn && /Schulkind, Klasse [1-4]/.test(pk.text) && /(Klasse [1-4] in der|letzte Schultag in der) Grundschule/.test(pk.text) && /Unterricht 8 bis 13 Uhr/.test(pk.text) && pk.schulKnopf && /eingeschult/.test(pk.text),
    `Personenkarte: „${(pk.text.match(/Schulkind, Klasse \d+[^\n]*/) || ['–'])[0]}“, „${(pk.text.match(/Klasse \d+ in der [^\n]*/) || ['–'])[0]}“, Lebenslauf „${(pk.text.match(/eingeschult[^\n]*/) || ['–'])[0]}“`);
  await A.page.screenshot({ path: BILD + 'schule_personenkarte.png' });
  await A.page.keyboard.press('Escape'); await A.zu();

  // 4. Fenster „Stadtregierung“: Gruppe „Schule“ mit drei Karten, Zahlen ohne NaN, Zeilen „Lehrkräfte vom Land“
  await A.page.click('#regierung-knopf'); await A.page.waitForTimeout(700);
  const f = await A.ev(() => { const box = document.getElementById('regierung-inhalt'), gr = [...box.querySelectorAll('.reg-gruppe')].find(x => /^Schule \(/.test(x.textContent));
    const karten = []; let e = gr && gr.nextElementSibling;
    while (e && !e.classList.contains('reg-gruppe')) { const t = e.querySelector('.reg-kopf span, summary span, h3'); karten.push((e.textContent || '').slice(0, 80)); e = e.nextElementSibling; }
    return { gruppe: gr && gr.textContent, karten, text: box.innerText, nan: /NaN|undefined/.test(box.innerText) }; });
  ok(f.gruppe === 'Schule (Gebäude der Stadt, Lehrkräfte vom Land)' && /Kleinere Klassen/.test(f.text) && /Schulpflicht, Schulen in Wohnnähe, Lehrkräfte vom Land/.test(f.text)
    && /Computer für die Schulen, gekauft in der Stadt/.test(f.text) && /Heute \d+ Grundschulen? und \d+ weiterführende/.test(f.text) && /Heute haben die Schulen \d+ Computer/.test(f.text)
    && /Lehrkräfte vom Land, gestern/.test(f.text) && /Lehrkräfte vom Land seit dem Start/.test(f.text) && !f.nan,
    `Fenster: Gruppe „${f.gruppe}“ mit den Karten „Kleinere Klassen“, „Schulpflicht …“, „Computer für die Schulen …“, Live-Zeilen und „Lehrkräfte vom Land“, kein NaN`);
  await A.page.evaluate(() => { const gr = [...document.querySelectorAll('#regierung-inhalt .reg-gruppe')].find(x => /^Schule \(/.test(x.textContent)); if (gr) gr.scrollIntoView(); });
  await A.page.waitForTimeout(300); await A.page.screenshot({ path: BILD + 'schule_fenster.png' });
  await A.zu();
  console.log('Konsole (breit):', A.log.length ? '\n  ' + A.log.join('\n  ') : 'leer');
  if (A.log.length) process.exitCode = 1;
  await A.ctx.close();

  // 5. Draw Calls gegen stadt.orig.html (Seed 2, Tag 330, 10 Uhr, Blick auf die Stadtmitte und auf die Grundschule)
  const dc = {};
  for (const [n, datei] of [['neu', 'stadt.html'], ['orig', 'stadt.orig.html']]) {
    const X = await seite(b, `${U.HOST}/${datei}?debug&seed=2&tage=${TAGE}&neu`);
    await stunde(X.ev, 10);
    await X.ev(() => __stadt.G.ausrichten()); await X.page.waitForTimeout(500); await X.zu();
    const mitte = await X.ev(() => __stadt.G.render().calls);
    await blick(X.ev, gs, 2.4, 2.0); await X.page.waitForTimeout(400);
    const nah = await X.ev(() => __stadt.G.render().calls);
    dc[n] = [mitte, nah];
    if (X.log.length) { console.log(`Konsole (${datei}):\n  ` + X.log.join('\n  ')); process.exitCode = 1; }
    await X.ctx.close();
  }
  ok(dc.neu[0] <= dc.orig[0] + 3 && dc.neu[1] <= dc.orig[1] + 3 && dc.neu[0] <= 32, `Draw Calls Tag ${TAGE}, 10 Uhr: Stadtmitte ${dc.neu[0]} (stadt.orig.html ${dc.orig[0]}), an der Grundschule ${dc.neu[1]} (${dc.orig[1]}); höchstens +3`);

  // 6. Handy 400 × 820: Hauskarte der Schule ohne seitliches Überlaufen
  const H = await seite(b, `${U.HOST}/stadt.html?debug&seed=2&tage=${TAGE}&neu`, { width: 400, height: 820 });
  await stunde(H.ev, 10);
  await blick(H.ev, gs, 1.6, 1.4); await H.page.waitForTimeout(600); await H.zu();
  await H.page.screenshot({ path: BILD + 'schule_handy_pause.png' });
  // Karte über einen Hausknopf (wie ein Knopf in einer Karte; den echten Klick ins Bild prüft Abschnitt 3 breit)
  const hk = await H.ev((b) => { const k = document.createElement('button'); k.className = 'haus'; k.dataset.b = b; document.body.append(k); k.click(); k.remove();
    const karte = document.getElementById('karte'), el = [...karte.querySelectorAll('*')];
    return { offen: !karte.hidden, titel: (karte.querySelector('h2') || {}).textContent || '', breit: document.documentElement.scrollWidth, fenster: innerWidth,
      zuBreit: el.filter(e => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflowX !== 'visible' && getComputedStyle(e).overflowX !== 'hidden').length }; }, gs.b);
  await H.page.waitForTimeout(400);
  ok(hk.offen && /^Grundschule /.test(hk.titel) && hk.breit <= hk.fenster && !hk.zuBreit, `Handy 400 × 820: „${hk.titel}“, Seite ${hk.breit} px breit (Fenster ${hk.fenster}), ${hk.zuBreit} Elemente mit seitlichem Scrollen`);
  await H.page.screenshot({ path: BILD + 'schule_handy_karte.png' });
  console.log('Konsole (Handy):', H.log.length ? '\n  ' + H.log.join('\n  ') : 'leer');
  if (H.log.length) process.exitCode = 1;
  await H.ctx.close();
  await b.close();
})().catch(e => { console.error('Testfehler', e); process.exit(1); });
