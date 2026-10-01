// Speicherformat 10 (Etappe 2, Schritt 2) im echten Browser (Chromium, Playwright), Seitenserver auf PORT (Wurzel: Ordner stadt/):
// 1. Die große Stadt (?debug&umland=300000&tage=750&seed=2, etwa 7.000 Einwohner) schreibt ihren Spielstand (spielstandText, Version 10) in
//    localStorage und liest ihn beim nächsten Aufruf der Seite wieder: dieselbe Stadt (Version, alle Einzelwerte, JSON-Teile und Arrays gleich),
//    kein Versionsdialog, kein Fehler. Größe in Zeichen (Grenze in Chromium laut Messung vom 29.09.: 5.242.867 Zeichen unter einem Schlüssel).
// 2. Ein Stand der Version 9 (git 6c1741e, Seed 1, Tag 150) mit der Policy aus Etappe 1 als Wahl: Versionsdialog nennt Version 9 → 10 und
//    „neu trainieren“; „Stadt übernehmen“ macht Version 10, die Meldung nennt den Rückfall, es entscheiden die Regeln, das Fenster
//    „Entscheidungen der Bewohner“ zeigt die Ablehnung der Policy (… diese Stadt ist Version 10 (neu trainieren)). Seit der Schlussprüfung von
//    Etappe 2 (Befund Bedienung): Die Meldung sagt „stammt aus Version 9 … (neu trainieren)“ und nicht mehr „Liegt sie wieder in ki/ …“ (die
//    Datei liegt dort und wird abgelehnt). 2b. Derselbe Stand per Import (ohne Versionsdialog): dieselbe Meldung.
// 3. Neue Stadt: „Trainierte Policy“ wählen → ki/policy_v9_lokal_1.json sichtbar abgelehnt (neu trainieren), es bleiben die Regeln.
// 4. Der Stand der Version 10 in der Fassung 6c1741e (Version 9, per git show unter stadt.orig.html): abgelehnt, kein „Stadt übernehmen“,
//    der Stand bleibt gespeichert. 5. Ein Stand „Version 11“ in Version 10: Titel „neueren Version“, kein „Stadt übernehmen“.
// Anfragen an localhost:11434 (Ollama) werden im Browser abgebrochen, nie weitergeleitet.
//   PORT=9091 node tests/p10speicher.cjs      (Server vorher starten, wie tests/LIESMICH.md; PLAYWRIGHT, THREE_DIR, STADT_GIT)
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');
const GRENZE = 5242867;                                   // Chromium 141, gemessen (SP/ml/e2/VERGLEICH.md Abschnitt 1.4)

(async () => {
  const t0 = Date.now();
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const b = await chromium.launch({ args: U.ARGS });
  const neuerKontext = async () => {
    const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
    await ctx.route('http://localhost:11434/**', (r) => r.abort());
    await ctx.route('http://127.0.0.1:11434/**', (r) => r.abort());
    await U.three(ctx);
    return ctx;
  };
  const ctx = await neuerKontext();
  const page = await ctx.newPage();
  const konsole = [];
  // Fehler der abgebrochenen Anfragen an Ollama (localhost:11434) sind gewollt (wie in browser_ki), alle anderen zählen
  page.on('console', m => { if (m.type() === 'error' && !/:11434\//.test((m.location() || {}).url || '')) konsole.push(m.text() + ' @ ' + ((m.location() || {}).url || '')); });
  page.on('pageerror', e => konsole.push('pageerror: ' + e.message));
  const ev = (f, a) => page.evaluate(f, a);
  const dialog = () => ev(() => ({ offen: document.getElementById('version-dialog').open, titel: document.getElementById('version-titel').textContent,
    text: document.getElementById('version-text').textContent, hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  // Teile eines Spielstand-Texts, die die Stadt ausmachen (ohne Zeitstempel, Tempo und Oberfläche), unabhängig von der Reihenfolge der Schlüssel
  // und der Arrays (nach dem Laden stehen die Arrays auf oberster Ebene von S in anderer Reihenfolge; so auch simtest: Fingerabdruck sortiert)
  const kanon = (o) => JSON.stringify(o, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map(x => [x, v[x]])) : v));
  const kern = (t) => { const d = JSON.parse(t); return kanon([d.format, d.version, d.werte, d.json, d.arrays.slice().sort((x, y) => (x.name < y.name ? -1 : 1))]); };
  // Was unterscheidet zwei Spielstand-Texte (Einzelwerte, JSON-Teile, Arrays)?
  const unterschied = (x, y) => { const a = JSON.parse(x), b = JSON.parse(y), u = [];
    for (const k of new Set([...Object.keys(a.werte), ...Object.keys(b.werte)])) if (JSON.stringify(a.werte[k]) !== JSON.stringify(b.werte[k])) u.push('werte.' + k);
    for (const k of new Set([...Object.keys(a.json), ...Object.keys(b.json)])) if (JSON.stringify(a.json[k]) !== JSON.stringify(b.json[k])) {
      const ak = a.json[k], bk = b.json[k];
      if (ak && bk && typeof ak === 'object' && !Array.isArray(ak)) { for (const j of new Set([...Object.keys(ak), ...Object.keys(bk)])) if (JSON.stringify(ak[j]) !== JSON.stringify(bk[j])) u.push(`json.${k}.${j}: ${JSON.stringify(ak[j]).slice(0, 60)} / ${JSON.stringify(bk[j]).slice(0, 60)}`); }
      else u.push('json.' + k); }
    const nb = new Map(b.arrays.map(q => [q.name, q.b64]));
    for (const q of a.arrays) if (nb.get(q.name) !== q.b64) u.push('arrays.' + q.name);
    if (a.arrays.length !== b.arrays.length) u.push('Zahl der Arrays');
    return u; };

  // 1. Große Stadt: schreiben, lesen, neu laden
  await page.goto(U.LEER);
  await ev(() => localStorage.clear());
  const r0 = Date.now();
  await page.goto(U.HOST + '/stadt.html?debug&umland=300000&tage=750&seed=2', { timeout: 1200000 });
  await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 1200000 });
  const rechnen = Math.round((Date.now() - r0) / 1000);
  const gross = await ev(() => {
    __stadt.setzeTempo(0);
    const S = __stadt.S(), text = __stadt.spielstandText();
    let fehler = '';
    try { localStorage.setItem('stadt-save-v1', text); } catch (e) { fehler = e.name + ': ' + e.message; }
    const zurueck = localStorage.getItem('stadt-save-v1');
    return { tag: S.tag, stunde: S.stunde, einw: S.einwohner, version: S.version, laenge: text.length, fehler, gleich: zurueck === text, text };
  });
  ok(!gross.fehler && gross.gleich && gross.version === 10 && gross.tag === 750 && gross.laenge <= 4.4e6 && gross.laenge < GRENZE,
    `große Stadt (Tag ${gross.tag}, ${gross.einw} Einwohner, ${rechnen} s gerechnet): Spielstand Version ${gross.version}, ${gross.laenge.toLocaleString('de-DE')} Zeichen `
    + `(≤ 4,4 Mio.; Chromium-Grenze ${GRENZE.toLocaleString('de-DE')}), in localStorage geschrieben ${gross.fehler ? 'NEIN: ' + gross.fehler : 'ja'}, gleich zurückgelesen: ${gross.gleich ? 'ja' : 'NEIN'}`);
  const d0 = JSON.parse(gross.text);
  ok(!d0.arrays.some(a => a.name === 'p.memName') && ['p.memFakt', 'p.memVon', 'p.erf', 'p.offen', 'p.offRest', 'p.planSchritt', 'p.planGrund', 'p.entA', 'p.entArt', 'p.entZeit'].every(n => d0.arrays.some(a => a.name === n))
    && !!d0.json.stat.ged, `Format 10: kein memName, alle Felder von Etappe 2, S.stat.ged (${JSON.stringify(d0.json.stat.ged.gelernt)} gelernt je Handlung)`);
  // Neu laden ohne ?umland: die Seite liest den Stand aus localStorage (spielstandLesen), wie beim nächsten Besuch
  await page.goto(U.HOST + '/stadt.html?debug', { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 600000 });
  const geladen = await ev(() => { const S = __stadt.S(); return { tag: S.tag, stunde: S.stunde, einw: S.einwohner, version: S.version, text: __stadt.spielstandText(),
    dialog: document.getElementById('version-dialog').open, meldung: document.getElementById('meldung').hidden ? '' : document.getElementById('meldung').textContent }; });
  ok(!geladen.dialog && geladen.version === 10 && geladen.tag === gross.tag && geladen.einw === gross.einw && kern(geladen.text) === kern(gross.text) && !/nicht geklappt|beschädigt/.test(geladen.meldung),
    `neu geladen aus localStorage: Tag ${geladen.tag} ${geladen.stunde} Uhr, ${geladen.einw} Einwohner, kein Dialog, Stadt gleich (Version, Einzelwerte, JSON-Teile, `
    + `${d0.arrays.length} Arrays): ${kern(geladen.text) === kern(gross.text) ? 'ja' : 'NEIN: ' + unterschied(gross.text, geladen.text).join(', ')}${geladen.meldung ? '; Meldung „' + geladen.meldung + '“' : ''}`);

  // 2. Stand der Version 9 (git 6c1741e) mit der Policy aus Etappe 1 als Wahl
  const repo = process.env.STADT_GIT || execFileSync('git', ['-C', U.STADT, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const v9html = execFileSync('git', ['-C', repo, 'show', '6c1741e:stadt/stadt.html'], { maxBuffer: 64 << 20 }).toString();
  const vctx = vm.createContext({}); vm.runInContext(v9html.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], vctx);
  const Alt = vctx.StadtSim, A = Alt.neueStadt(1);
  while (A.tag < 150 || A.stunde < 13) Alt.stunde(A);
  const pol = JSON.parse(fs.readFileSync(path.join(U.STADT, 'ki', 'policy_v9_lokal_1.json'), 'utf8'));
  const dA = Alt.exportZustand(A);
  const v9 = JSON.stringify({ ...dA, arrays: dA.arrays.map(a => ({ name: a.name, typ: a.typ, b64: Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength).toString('base64') })),
    zuletztGelaufen: Date.now(), tempo: 1, ui: { entscheidungen: { v: 1, art: 'policy', name: pol.name, hash: pol.hash, schema: pol.schemaHash } } });
  await page.goto(U.LEER);
  await ev((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, v9);
  await page.goto(U.HOST + '/stadt.html?debug');
  await page.waitForFunction(() => globalThis.__stadt);
  await page.waitForTimeout(500);
  const dv = await dialog();
  ok(dv.offen && dv.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && dv.text.startsWith('Dein Spielstand ist von Version 9. Seit Version 10')
    && dv.hinweis.includes('neu trainieren') && dv.hinweis.includes('Beziehung statt des Namens'),
    `Version 9 im Speicher: Dialog „${dv.titel}“, ${dv.knoepfe.join(', ')}; „${dv.text}“ – „${dv.hinweis}“`);
  await page.screenshot({ path: U.ordner('bilder_p10') + 'p10_dialog_v9.png' });
  await page.click('#version-uebernehmen');
  await page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await page.waitForTimeout(800);
  const u = await ev(() => { const S = __stadt.S(); return { version: S.version, tag: S.tag, einw: S.einwohner, ged: !!S.stat.ged,
    gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent, art: document.getElementById('meldung').className,
    policy: !!__stadt.Sim.KI.policyAktiv(), status: document.getElementById('ki-policy-status').textContent, regeln: document.getElementById('ki-entscheid-regeln').checked,
    text10: localStorage.getItem('stadt-save-v1') }; });
  ok(u.version === 10 && u.gespeichert === 10 && u.ged && u.tag === A.tag && u.einw === A.einwohner,
    `übernommen: Version ${u.version} (gespeichert ${u.gespeichert}), Tag ${u.tag}, ${u.einw} Einwohner (vorher ${A.einwohner}), S.stat.ged angelegt`);
  const neuTrainieren = `Die gespeicherte Policy „${pol.name}“ stammt aus Version 9 und gilt in Version 10 nicht mehr (neu trainieren). Es entscheiden die Regeln (Rückfall).`;
  ok(!u.policy && u.regeln && u.meldung.includes('Bewohner mit Erfahrung und Plänen') && u.meldung.includes('Es entscheiden die Regeln (Rückfall)') && u.art === 'warnung'
    && u.meldung.includes(neuTrainieren) && !/Liegt sie wieder/.test(u.meldung + u.status)
    && /policy_v9_lokal_1\.json: Policy ungültig: trainiert auf Stadt-Version 9, diese Stadt ist Version 10 \(neu trainieren\)/.test(u.status),
    `Policy aus Version 9 nach der Übernahme: Regeln; Meldung „${u.meldung}“; Fenster „${u.status}“`);
  // 2b. Derselbe Stand der Version 9 per Import (Einstellungen → Import, kein Versionsdialog): Version 10, dieselbe Meldung zur Policy
  await page.setInputFiles('#import-datei', { name: 'stadt-save.json', mimeType: 'application/json', buffer: Buffer.from(v9) });
  await page.waitForFunction(() => document.getElementById('meldung').textContent.startsWith('Spielstand von Version 9'), null, { timeout: 60000 });
  const im = await ev(() => ({ version: __stadt.S().version, tag: __stadt.S().tag, meldung: document.getElementById('meldung').textContent, art: document.getElementById('meldung').className,
    policy: !!__stadt.Sim.KI.policyAktiv(), regeln: document.getElementById('ki-entscheid-regeln').checked, status: document.getElementById('ki-policy-status').textContent }));
  ok(im.version === 10 && im.tag === A.tag && !im.policy && im.regeln && im.art === 'warnung' && im.meldung.startsWith('Spielstand von Version 9 übernommen')
    && im.meldung.includes(neuTrainieren) && !/Liegt sie wieder/.test(im.meldung + im.status),
    `Import des Stands der Version 9: Version ${im.version}, Tag ${im.tag}, Regeln; Meldung „${im.meldung}“`);

  // 3. Neue Stadt: „Trainierte Policy“ wählen → sichtbar abgelehnt, Regeln bleiben
  const ctx3 = await neuerKontext();
  const p3 = await ctx3.newPage();
  p3.on('pageerror', e => konsole.push('pageerror: ' + e.message));
  await p3.goto(U.HOST + '/stadt.html?neu&seed=1&debug');
  await p3.waitForFunction(() => globalThis.__stadt);
  await p3.evaluate(() => __stadt.setzeTempo(0));
  await p3.click('#einst-knopf'); await p3.click('#ki-knopf');
  await p3.click('#ki-entscheid-policy');
  await p3.waitForFunction(() => !/wird aus dem Ordner ki\/ geladen/.test(document.getElementById('ki-policy-status').textContent), null, { timeout: 15000 });
  const k3 = await p3.evaluate(() => ({ policy: !!__stadt.Sim.KI.policyAktiv(), regeln: document.getElementById('ki-entscheid-regeln').checked,
    status: document.getElementById('ki-policy-status').textContent, meldung: document.getElementById('meldung').textContent, knopf: document.getElementById('ki-knopf').textContent }));
  ok(!k3.policy && k3.regeln && /neu trainieren/.test(k3.status) && /Umschalten auf die Policy nicht möglich/.test(k3.status) && /es entscheiden weiter die Regeln/.test(k3.meldung)
    && k3.knopf.includes('Regeln'), `„Trainierte Policy“ gewählt: Regeln bleiben; Fenster „${k3.status}“; Meldung „${k3.meldung}“`);
  await p3.locator('#ki-dialog').screenshot({ path: U.ordner('bilder_p10') + 'p10_ki_abgelehnt.png' });
  await ctx3.close();

  // 4. Stand der Version 10 in der Fassung 6c1741e (Version 9): abgelehnt, bleibt gespeichert
  const v9datei = path.join(U.tempOrdner(), 'stadt_6c1741e.html');
  fs.writeFileSync(v9datei, v9html);
  const ctx4 = await neuerKontext();
  await ctx4.route(U.HOST + '/stadt.orig.html*', (r) => r.fulfill({ path: v9datei, contentType: 'text/html; charset=utf-8' }));
  const p4 = await ctx4.newPage();
  p4.on('pageerror', e => konsole.push('pageerror (6c1741e): ' + e.message));
  await p4.goto(U.LEER);
  await p4.evaluate((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, u.text10);   // der eben übernommene Stand (Version 10)
  await p4.goto(U.HOST + '/stadt.orig.html?debug');
  await p4.waitForFunction(() => globalThis.__stadt);
  await p4.waitForTimeout(500);
  const d4 = await p4.evaluate(() => ({ offen: document.getElementById('version-dialog').open, titel: document.getElementById('version-titel').textContent,
    text: document.getElementById('version-text').textContent, knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')),
    version: __stadt.Sim.VERSION, gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version }));
  ok(d4.offen && d4.version === 9 && d4.knoepfe.join('|') === 'Export behalten|Neu anfangen*' && d4.text === 'Spielstand ist von Version 10, diese Datei ist Version 9.' && d4.gespeichert === 10,
    `Version 10 in 6c1741e (Version ${d4.version}): abgelehnt, ${d4.knoepfe.join(', ')}, „${d4.titel}“ – „${d4.text}“; der Stand bleibt gespeichert (Version ${d4.gespeichert})`);
  await p4.screenshot({ path: U.ordner('bilder_p10') + 'p10_v10_in_v9.png' });
  await ctx4.close();

  // 5. Stand „Version 11“ in Version 10: neuere Version, nicht übernehmbar
  await page.goto(U.LEER);
  await ev((t) => { const d = JSON.parse(t); d.version = 11; localStorage.clear(); localStorage.setItem('stadt-save-v1', JSON.stringify(d)); }, u.text10);
  await page.goto(U.HOST + '/stadt.html?debug');
  await page.waitForFunction(() => globalThis.__stadt);
  await page.waitForTimeout(300);
  const d5 = await dialog();
  ok(d5.offen && d5.titel === 'Spielstand ist von einer neueren Version' && d5.knoepfe.join('|') === 'Export behalten|Neu anfangen*' && d5.text.startsWith('Dein Spielstand ist von Version 11, diese Datei ist Version 10.'),
    `Version 11 in Version 10: „${d5.titel}“, ${d5.knoepfe.join(', ')} – „${d5.text}“`);
  ok(!konsole.length, `Konsole ohne Fehler (${konsole.length}${konsole.length ? ': ' + konsole.slice(0, 3).join(' | ') : ''})`);
  await b.close();
  console.log(`fertig in ${Math.round((Date.now() - t0) / 1000)} s`);
})().catch(e => { console.log('Testfehler: ' + (e && e.stack || e)); process.exit(1); });
