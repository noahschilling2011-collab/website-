// Erzeugt den Teststand der KI-Code- und Übernahme-Tests (ersetzt die früher eingecheckten basis_v6…v9.json, je über 1 MB):
// Seed 2, 420 Tage, 8 Uhr, eine Programmierkraft der größten Tech-Firma als Hauptfigur (wie damals pruef2/kicode/basis.cjs mit der Fassung
// 797107a, Spielstand-Version 4), dann Schritt für Schritt „Stadt übernehmen“ mit jeder späteren Fassung aus der Git-Geschichte (414ebab → 5,
// bc7247a → 6, ffa1d88 → 7, 31ce452 → 8, 6c1741e → 9) und zuletzt mit stadt.html dieses Ordners (→ 10), wie die früheren tests/basis_v6.cjs …
// basis_v9.cjs. Version 10 (Etappe 2): basis_v9.json kommt seitdem aus der Fassung 6c1741e, basis_v10.json ist der Teststand dieser Datei.
// Die alten Fassungen kommen per Route unter stadt.orig.html (gleiche Herkunft, derselbe Speicherplatz). Nachgeprüft: bis auf den Zeitstempel
// zuletztGelaufen gleich den früher eingecheckten Dateien (Vergleich mit --vergleich).
// Ausgabe: AUSGABE/basis/basis_v4.json … basis_v10.json und basis_info.json (Hauptfigur). Braucht den Seitenserver (tests/alle.sh).
//   node tests/basis.cjs [--vergleich <ordner mit basis.json, basis_v4.json, basis_v6.json …>]
const U = require('./umgebung.cjs');
const fs = require('fs');
const path = require('path');
const AUS = U.ordner('basis');
const stand = (name, text) => fs.writeFileSync(AUS + name, text);

async function kontext(b) {
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (r) => r.abort('connectionrefused'));   // KI aus (wie die Attrappe „aus“ damals)
  return ctx;
}
// Stand der Version n-1 in den Speicher, Fassung v öffnen, „Stadt übernehmen“, speichern (wie tests/basis_v6.cjs … basis_v9.cjs)
async function uebernehmen(b, text, v) {
  const ctx = await kontext(b);
  if (v) await U.fassungUnter(ctx, v);
  const page = await ctx.newPage();
  const d = JSON.parse(text); d.zuletztGelaufen = Date.now(); d.tempo = 0;
  await page.goto(U.LEER);
  await page.evaluate((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, JSON.stringify(d));
  await page.goto(U.HOST + (v ? '/stadt.orig.html?debug' : '/stadt.html?debug'));
  await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 120000 });
  await page.waitForTimeout(500);
  const offen = await page.evaluate(() => document.getElementById('version-dialog').open);
  if (offen) { await page.click('#version-uebernehmen'); await page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 60000 }); }
  await page.waitForTimeout(800);
  const neu = await page.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); return localStorage.getItem('stadt-save-v1'); });
  await ctx.close();
  return { offen, neu };
}

(async () => {
  const t0 = Date.now();
  const b = await U.chromium.launch({ args: U.ARGS });
  // 1. Grundstand mit der Fassung 797107a
  const ctx = await kontext(b);
  await U.fassungUnter(ctx, 'v4tech');
  const page = await ctx.newPage();
  await page.goto(U.LEER); await page.evaluate(() => localStorage.clear());
  await page.goto(U.HOST + '/stadt.orig.html?debug&seed=2&tage=420&neu');
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  const info = await page.evaluate(() => {
    const a = __stadt; a.setzeTempo(0);
    const S = a.S(), Sim = a.Sim;
    while (S.stunde !== 8) a.schritt();
    let best = -1;
    for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.TECH && !S.g.leer[b] && S.feld[S.g.y[b] * Sim.KARTE + S.g.x[b]] === Sim.TECH && (best < 0 || S.belegschaft[b].length > S.belegschaft[best].length)) best = b;
    const leute = S.belegschaft[best].filter(x => !S.p.frei[x] && S.p.arbeit[x] === best);
    const p = leute[0];
    const ok = Sim.hauptSetzen(S, p, S.p.gen[p], true, 10);
    a.nachSchritten(); a.speichern();
    return { best, p, gen: S.p.gen[p], ok, haupt: S.ki.haupt.map(h => h.id + '/' + h.gen), tag: S.tag, stunde: S.stunde, name: Sim.name(S, p), leute: leute.length };
  });
  let text = await page.evaluate(() => localStorage.getItem('stadt-save-v1'));
  await ctx.close();
  stand('basis_v4.json', text); stand('basis_info.json', JSON.stringify(info));
  console.log(`v4tech (${U.FASSUNGEN.v4tech[0].slice(0, 7)}): Version ${JSON.parse(text).version}, Tag ${JSON.parse(text).werte.tag}, Hauptfigur ${JSON.stringify(info)}`);
  if (JSON.parse(text).version !== 4 || !info.ok) { console.log('FEHL Grundstand'); process.exitCode = 1; }
  // 2. Übernahmen bis Version 10 (Version 9 aus 6c1741e)
  for (const [v, n] of [['v5', 5], ['v6', 6], ['v7', 7], ['v8', 8], ['v9', 9], [null, 10]]) {
    const r = await uebernehmen(b, text, v);
    const d = JSON.parse(r.neu);
    console.log(`${v ? v + ' (' + U.FASSUNGEN[v][0].slice(0, 7) + ')' : 'stadt.html'}: Dialog ${r.offen}, Version ${d.version}, Tag ${d.werte.tag} ${d.werte.stunde} Uhr, ${d.werte.einwohner} Einwohner`);
    if (d.version !== n || !r.offen) { console.log(`FEHL Übernahme nach Version ${n} gescheitert`); process.exitCode = 1; break; }
    text = r.neu; stand(`basis_v${n}.json`, text);
  }
  await b.close();
  // Optional: Vergleich mit früher erzeugten Dateien (ohne den Zeitstempel zuletztGelaufen)
  const i = process.argv.indexOf('--vergleich');
  if (i > 0) {
    const dir = process.argv[i + 1];
    for (const [alt, neu] of [['basis_v4.json', 'basis_v4.json'], ['basis.json', 'basis_v5.json'], ['basis_v6.json', 'basis_v6.json'], ['basis_v7.json', 'basis_v7.json'], ['basis_v8.json', 'basis_v8.json'], ['basis_v9.json', 'basis_v9.json']]) {
      const f = path.join(dir, alt); if (!fs.existsSync(f)) continue;
      const a = JSON.parse(fs.readFileSync(f, 'utf8')), n = JSON.parse(fs.readFileSync(AUS + neu, 'utf8'));
      delete a.zuletztGelaufen; delete n.zuletztGelaufen;
      const unterschied = [];
      for (const k of new Set([...Object.keys(a), ...Object.keys(n)])) {
        if (JSON.stringify(a[k]) === JSON.stringify(n[k])) continue;
        if (a[k] && n[k] && typeof a[k] === 'object' && !Array.isArray(a[k])) {
          for (const k2 of new Set([...Object.keys(a[k]), ...Object.keys(n[k])])) if (JSON.stringify(a[k][k2]) !== JSON.stringify(n[k][k2])) unterschied.push(k + '.' + k2);
        } else if (Array.isArray(a[k]) && Array.isArray(n[k])) {
          for (let j = 0; j < Math.max(a[k].length, n[k].length); j++) if (JSON.stringify(a[k][j]) !== JSON.stringify(n[k][j])) unterschied.push(k + '[' + j + (a[k][j] && a[k][j].name ? ' ' + a[k][j].name : '') + ']');
        } else unterschied.push(k);
      }
      console.log(`Vergleich ${alt} ↔ ${neu}: ${unterschied.length ? 'Unterschiede in ' + unterschied.slice(0, 20).join(', ') : 'gleich (ohne zuletztGelaufen)'}`);
    }
  }
  console.log(`Dauer ${((Date.now() - t0) / 1000).toFixed(0)} s, Ausgabe ${AUS}`);
})().catch((e) => { console.log('Testfehler ' + (e.stack || e)); process.exit(1); });
