// VERALTET, nicht in tests/alle.sh: Stand Version 8 (NEU = 8), schon in Version 9 nicht mehr gelaufen; die Übernahme eines V5-Stands prüft p6migration.
// Kopie aus pruefB_technik/tests (zweite Gegenprüfung, Technik); schreibt v5_seed5.json nach tests/ausgabe/pruef_v5/
// Prüfer Technik: echter V5-Stand (Git 414ebab per git show unter stadt.orig.html; Seed 5, Tag 400) → stadt.html (heute Version 8): Dialog, übernehmen, 45 Tage im Browser, Karten, Fenster,
// Speichern/Neuladen; dazu derselbe V5-Stand als Datei über „Import“; Draw Calls; Konsole
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const ADR = U.HOST + '/';
const NEU = 8;                                             // Version von stadt.html
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const neu = async (vp) => {
    const ctx = await b.newContext({ viewport: vp || { width: 1280, height: 800 } });
    await U.three(ctx);
    await ctx.route('http://localhost:11434/**', (r) => r.abort());
    await U.fassungUnter(ctx, 'v5', ADR + 'stadt.orig.html*');
    const page = await ctx.newPage(), log = [];
    page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED|ERR_CONNECTION/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
    page.on('pageerror', e => log.push('pageerror: ' + e.message));
    return { ctx, page, log };
  };
  const ok = (c, t) => console.log((c ? 'OK   ' : 'FEHL ') + t);
  // 1. V5-Stand erzeugen
  const A = await neu();
  await A.page.goto(U.LEER); await A.page.evaluate(() => localStorage.clear());
  await A.page.goto(ADR + 'stadt.orig.html?debug&seed=5&tage=400&neu');
  await A.page.waitForFunction(() => globalThis.__stadt, null, { timeout: 180000 });
  const v5 = await A.page.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); return localStorage.getItem('stadt-save-v1'); });
  const d5 = JSON.parse(v5);
  fs.writeFileSync(U.ordner('pruef_v5') + 'v5_seed5.json', v5);
  ok(d5.version === 5, `V5-Stand: Tag ${d5.werte.tag}, ${d5.werte.einwohner} Einwohner, ${(v5.length / 1e6).toFixed(2)} MB`);
  // 2. im selben Browser stadt.html öffnen → Dialog → übernehmen
  await A.page.goto(ADR + 'stadt.html?debug');
  await A.page.waitForFunction(() => globalThis.__stadt, null, { timeout: 60000 });
  await A.page.waitForTimeout(500);
  const offen = await A.page.evaluate(() => document.getElementById('version-dialog').open);
  ok(offen, 'Versionsdialog offen');
  await A.page.click('#version-uebernehmen');
  await A.page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 60000 });
  const s0 = await A.page.evaluate(() => { const S = __stadt.S(); let eig = 0; for (let x = 0; x < S.pMax; x++) if (S.p.lebt[x] && S.p.eigen[x]) eig++;
    return { version: S.version, tag: S.tag, s2: S.regierung.schritt2, karte: S.karte, stufe: S.erweiterung.stufe, teile: S.erweiterung.teile.length, eig, beitragNull: [...Array(S.pMax).keys()].filter(x => S.p.lebt[x] && S.tag - S.p.geb[x] > 30 * 10 && !S.p.beitrag[x]).length }; });
  ok(s0.karte >= 96 && s0.karte % 8 === 0 && s0.stufe === (d5.werte.einwohner >= 800 ? 3 : d5.werte.einwohner >= 160 ? 2 : d5.werte.einwohner >= 40 ? 1 : 0) && (s0.stufe === 0 || s0.teile >= 4),
    `Stadt erweitern nach der Übernahme: Karte ${s0.karte}, Stufe ${s0.stufe}, ${s0.teile} Stadtteile`);
  ok(s0.version === NEU && s0.s2 === d5.werte.tag && s0.eig === 0 && s0.beitragNull === 0, `übernommen: ${JSON.stringify(s0)}`);
  // 3. 45 Tage rechnen (stündlich über __stadt.schritt), dabei jeden Tag Zahlen, Fenster offen
  const zu = async () => { await A.page.waitForTimeout(1500); await A.page.evaluate(() => { const S = __stadt.S(); for (let i = 0; i < 50 && S.ki.verlust.length; i++) __stadt.Sim.verlustErledigt(S); const d = document.getElementById('nachfolge-dialog'); if (d.open) d.close(); }); };
  await zu();
  await A.page.click('#regierung-knopf'); await A.page.waitForTimeout(300);
  const lauf = await A.page.evaluate(() => { const S = () => __stadt.S(); const t0 = S().tag, luecke = []; let l0 = S().stat.regierung.kitaLuecke;
    while (S().tag < t0 + 45) { const t = S().tag; while (S().tag === t) __stadt.schritt(); __stadt.nachSchritten(); for (let i = 0; i < 50 && S().ki.verlust.length; i++) __stadt.Sim.verlustErledigt(S()); if (document.getElementById('nachfolge-dialog').open) document.getElementById('nachfolge-dialog').close(); luecke.push(S().stat.regierung.kitaLuecke - l0); l0 = S().stat.regierung.kitaLuecke; }
    const i = __stadt.Sim.regierungInfo(S());
    return { tag: S().tag, luecke, kita: i.kita, eig: i.eigentuemer, hh: i.haushalte, vor67: i.vor67, nan: Object.values(S().stat.regierung).some(v => !Number.isFinite(v)) }; });
  ok(!lauf.nan && lauf.kita.offen > 0 && lauf.eig > 0, `45 Tage: Tag ${lauf.tag}, Kitas offen ${lauf.kita.offen}, Eigentum ${lauf.eig}/${lauf.hh}, vor 67 in Rente ${lauf.vor67}; Stellenaufgaben je Nacht: ${lauf.luecke.join(' ')}`);
  const fenster = await A.page.evaluate(() => [...document.querySelectorAll('#regierung-inhalt .reg-live')].map(e => e.textContent).join(' | ').slice(0, 600));
  ok(!/NaN|undefined/.test(fenster), 'Fenster live ohne NaN/undefined: ' + fenster.slice(0, 300));
  await A.page.keyboard.press('Escape'); await zu();
  // Karten: Eigentümer, früher Rentner, Kita, Kind
  const karten = await A.page.evaluate(() => { const S = __stadt.S(), Sim = __stadt.Sim, P = S.p, r = {};
    for (let x = 0; x < S.pMax; x++) { if (!P.lebt[x]) continue;
      if (!r.eig && Sim.eigentuemer(S, x)) r.eig = Sim.personInfo(S, x);
      if (!r.frueh && Sim.rentner(S, x) && S.tag - P.geb[x] < 670) r.frueh = Sim.personInfo(S, x);
      if (!r.geb && Sim.gebunden(S, x)) r.geb = Sim.personInfo(S, x); }
    for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.KITA && S.feld[S.g.y[b] * (S.karte || 96) + S.g.x[b]] === Sim.KITA) { r.kita = Sim.gebaeudeInfo(S, b); break; }
    const t = (i) => i && JSON.stringify({ arbeit: i.arbeit, wohnen: i.wohnen, eigentum: i.eigentum, rente: i.rente, kita: i.kita, gebunden: i.gebunden, titel: i.titel, mehr: i.mehr });
    return { eig: t(r.eig), frueh: t(r.frueh), geb: t(r.geb), kita: t(r.kita) }; });
  for (const [k, v] of Object.entries(karten)) ok(v === undefined || !/NaN|undefined/.test(v), `Karte ${k}: ${(v || '(kein Fall)').slice(0, 260)}`);
  // 4. speichern, neu laden: kein Dialog, gleicher Tag
  await A.page.evaluate(() => __stadt.speichern());
  const tagVor = lauf.tag;
  await A.page.reload(); await A.page.waitForFunction(() => globalThis.__stadt, null, { timeout: 60000 }); await A.page.waitForTimeout(500);
  const nach = await A.page.evaluate(() => ({ dialog: document.getElementById('version-dialog').open, tag: __stadt.S().tag, v: __stadt.S().version }));
  ok(!nach.dialog && nach.v === NEU && nach.tag >= tagVor, `neu geladen: ${JSON.stringify(nach)}`);
  await A.page.waitForTimeout(1500);
  const dbg = await A.page.evaluate(() => globalThis.__stadtDebug && { calls: globalThis.__stadtDebug.calls, dreiecke: globalThis.__stadtDebug.dreiecke, fps: Math.round(globalThis.__stadtDebug.fps) });
  ok(!!dbg && dbg.calls > 0, 'Debug: ' + JSON.stringify(dbg));
  ok(!A.log.length, 'Konsole A: ' + (A.log.join(' / ') || 'leer'));
  await A.ctx.close();
  // 5. V5-Stand als Datei importieren (neue Stadt läuft) → Dialog → übernehmen
  const B = await neu({ width: 844, height: 390 });
  await B.page.goto(U.LEER); await B.page.evaluate(() => localStorage.clear());
  await B.page.goto(ADR + 'stadt.html?debug&seed=2&neu');
  await B.page.waitForFunction(() => globalThis.__stadt, null, { timeout: 60000 }); await B.page.waitForTimeout(500);
  await B.page.evaluate(() => { const d = document.getElementById('einstellungen') || document.querySelector('details'); });
  await B.page.setInputFiles('#import-datei', U.ordner('pruef_v5') + 'v5_seed5.json');
  await B.page.waitForTimeout(1500);
  const s = await B.page.evaluate(() => ({ v: __stadt.S().version, tag: __stadt.S().tag, s2: __stadt.S().regierung.schritt2, einw: __stadt.S().einwohner, meldung: document.getElementById('meldung').textContent.slice(0, 200) }));
  ok(s.v === NEU && s.tag === d5.werte.tag && s.s2 === d5.werte.tag && /Version 5 übernommen/.test(s.meldung), 'Import V5-Datei direkt übernommen: ' + JSON.stringify(s));
  const lauf2 = await B.page.evaluate(() => { const S = () => __stadt.S(); const t0 = S().tag; while (S().tag < t0 + 3) __stadt.schritt(); __stadt.nachSchritten(); return { tag: S().tag, kaeufe: S().stat.regierung.kaeufe, nan: !Number.isFinite(S().budget) }; });
  ok(!lauf2.nan && lauf2.kaeufe > 0, '3 Tage weiter: ' + JSON.stringify(lauf2));
  const kh = await B.page.evaluate(() => Math.round(document.getElementById('kennzahlen').getBoundingClientRect().bottom));
  ok(kh > 0, 'Kennzahlen-Unterkante bei 844 × 390: ' + kh + ' px');
  ok(!B.log.length, 'Konsole B: ' + (B.log.join(' / ') || 'leer'));
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
