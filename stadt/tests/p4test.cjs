// Phase-4-Test gegen den Test-Ollama (tests/mockollama.mjs auf Port 11434, startet tests/alle.sh bei Bedarf)
const U = require('./umgebung.cjs');
const { chromium } = U;
const http = require('http');
const OUT = U.ordner('bilder_p4');   // Bilder nach tests/ausgabe/ (per .gitignore ausgeschlossen)
const modus = (m) => new Promise((ok) => { const r = http.request({ host: 'localhost', port: 11434, path: '/modus', method: 'POST' }, (res) => { res.resume(); res.on('end', ok); }); r.end(m); });
(async () => {
  await modus('gut');
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text() + ' @ ' + (m.location().url || '?')); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const ev = (f, a) => page.evaluate(f, a);
  const bisStunde = (h) => ev((h) => { const a = __stadt; while (a.S().stunde !== h) a.schritt(); a.nachSchritten(); }, h);
  const kiStat = () => ev(() => Object.assign({ status: __stadt.ki.status, offen: __stadt.S().ki.anfragen.length, fehler: __stadt.ki.letzterFehler }, __stadt.ki.stat));

  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=120&neu');
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await ev(() => __stadt.setzeTempo(0));
  await page.waitForFunction(() => __stadt.ki.status !== 'suche', null, { timeout: 10000 });
  ok(await ev(() => __stadt.ki.status) === 'bereit', 'Ollama gefunden, Status ' + await ev(() => __stadt.ki.status + ' / ' + __stadt.ki.modell));
  const leiste = await ev(() => [...document.querySelectorAll('#haupt-liste .haupt-zeile')].map(z => z.textContent.replace(/\s+/g, ' ').trim()));
  console.log('     Leiste:', JSON.stringify(leiste));
  // Version 9: dazu der Bürgermeister auf eigenem Platz (höchstens 10 + 1); die Leiste zeigt genau Sim.hauptListe
  const soll = await ev(() => __stadt.Sim.hauptListe(__stadt.S()).length);
  ok(leiste.length >= 1 && leiste.length === soll && leiste.length <= 11, `${leiste.length} Hauptfiguren in der Leiste (mit dem Bürgermeister; Sim: ${soll})`);
  ok(await ev(() => document.getElementById('ki-status').textContent) === 'KI: test-modell:latest', 'Status oben rechts: ' + await ev(() => document.getElementById('ki-status').textContent));

  // 1. Entscheidung um 7 Uhr: Anfragen entstehen, werden nacheinander beantwortet, Tagebuch füllt sich
  await ev(() => __stadt.setzeTempo(1));
  // KI an/aus setzt erst das nächste Bild (simTakt); ohne Warten stellte die Stunde 7 manchmal keine Anfragen (Wettlauf im Test)
  await page.waitForFunction(() => __stadt.S().ki.an, null, { timeout: 10000 });
  await bisStunde(7); await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });   // Stunde 7 rechnen → Anfragen
  const offen = await ev(() => __stadt.S().ki.anfragen.length);
  ok(offen > 0, `${offen} Anfragen um 7 Uhr`);
  await page.waitForTimeout(250);
  const denkt = await ev(() => document.querySelectorAll('#haupt-liste .ueberlegt').length);
  ok(denkt > 0, `${denkt} Figuren „überlegt …“ in der Leiste`);
  await page.screenshot({ path: OUT + 'p4_ueberlegt.png' });
  await page.waitForFunction(() => __stadt.S().ki.anfragen.length === 0, null, { timeout: 20000 });
  let st = await kiStat();
  console.log('     KI:', JSON.stringify(st));
  ok(st.gueltig >= offen - 1, `Antworten angewandt: gültig ${st.gueltig}, ungültig ${st.ungueltig}`);
  const tb = await ev(() => __stadt.S().ki.haupt.map(h => (__stadt.S().ki.tagebuch[h.id + '/' + h.gen] || []).length));
  ok(tb.some(n => n > 0), 'Tagebücher: ' + tb.join(', '));

  // 2. Personenkarte einer Hauptfigur: Tagebuch oben, Eingabefeld darunter, reden
  // Hinweise zur Nachfolge (Hauptfigur zieht weg) liegen sonst über der Leiste; der Dialog selbst wird in Schritt 7 geprüft
  // Der Dialog geht erst im nächsten Bild auf: warten, solange ein Verlust gemeldet ist
  const nachfolgeZu = async () => {
    for (let i = 0; i < 30; i++) {
      const z = await ev(() => ({ auf: document.getElementById('nachfolge-dialog').open, v: __stadt.S().ki.verlust.length }));
      if (!z.auf && !z.v) break;
      if (z.auf) await page.click('#nachfolge-knoepfe button:last-child');
      await page.waitForTimeout(200);
    }
  };
  await nachfolgeZu();
  // Version 9: die erste von Noahs Hauptfiguren (der Bürgermeister steht davor, sein Knopf heißt anders; geprüft in tests/rathaus.cjs)
  await page.click('#haupt-liste .haupt-zeile:not(:has(.kreis.amt))');
  await page.waitForTimeout(200);
  const karte = await ev(() => ({ h3: [...document.querySelectorAll('#karte h3')].map(e => e.textContent), eintraege: document.querySelectorAll('#karte .tagebuch li').length,
    feld: !!document.getElementById('sagen-text') && !document.getElementById('sagen-text').disabled, knopf: document.querySelector('#karte [data-haupt]')?.textContent }));
  console.log('     Karte:', JSON.stringify(karte));
  ok(karte.h3[0] === 'Tagebuch' && karte.feld, 'Karte: Tagebuch zuerst, Eingabefeld aktiv');
  ok(karte.knopf === 'Keine Hauptfigur mehr', 'Knopf „Keine Hauptfigur mehr“');
  await page.fill('#sagen-text', 'Willst du nicht einen eigenen Laden aufmachen?');
  await page.click('#karte form.sagen button');
  await page.waitForTimeout(150);
  ok(await ev(() => document.querySelector('#karte .tagebuch')?.textContent.includes('denkt nach')), 'Während der Antwort: „… denkt nach“');
  await page.waitForFunction(() => __stadt.ki.gespraech === null, null, { timeout: 15000 });
  await page.waitForTimeout(200);
  const gespr = await ev(() => { const li = [...document.querySelectorAll('#karte .tagebuch li')].pop(); return li ? li.textContent.replace(/\s+/g, ' ') : null; });
  console.log('     Gespräch:', gespr);
  ok(gespr && gespr.includes('Laden'), 'Antwort steht im Tagebuch');
  const mem = await ev(() => [...document.querySelectorAll('#karte .lebenslauf li')].pop()?.textContent);
  ok(mem && mem.includes('mit Noah geredet'), 'Lebenslauf: ' + mem);
  await page.screenshot({ path: OUT + 'p4_gespraech.png' });
  console.log('     DUMP:', JSON.stringify(await ev(() => ({ stat: __stadt.ki.stat, fehler: __stadt.ki.letzterFehler, tb: __stadt.S().ki.haupt.map(h => [h.id, (__stadt.S().ki.tagebuch[h.id + '/' + h.gen] || []).map(e => e.art + ':' + e.text.slice(0, 20))]) }))));
  if (process.env.NUR_BIS_GESPRAECH) { await b.close(); return; }
  // Eingabe überlebt das stündliche Auffrischen
  await page.fill('#sagen-text', 'Halbfertiger Satz');
  await page.focus('#sagen-text');
  await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });
  ok(await ev(() => document.getElementById('sagen-text').value === 'Halbfertiger Satz' && document.activeElement.id === 'sagen-text'), 'Eingabe und Fokus bleiben beim Auffrischen');
  await page.fill('#sagen-text', '');
  await page.keyboard.press('Escape');

  // 3. Nicht-Hauptfigur zur Hauptfigur machen, zurücknehmen
  const anderer = await ev(() => { const S = __stadt.S(); for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && !__stadt.Sim.istHaupt(S, p) && S.tag - S.p.geb[p] > 200) return [p, S.p.gen[p]]; });
  await ev(([p, g]) => document.dispatchEvent(new Event('x')) || (window.__z = [p, g]), anderer);
  await ev(([p, g]) => { const b = document.createElement('button'); b.className = 'name'; b.dataset.p = p; b.dataset.g = g; document.body.append(b); b.click(); b.remove(); }, anderer);
  await page.waitForTimeout(100);
  await ev(() => { __stadt.ki.messung = { n: 6, ms: 6000 }; __stadt.nachSchritten(); });   // gemessen schnell: mehr als 5 erlaubt (nur Entscheidungen zählen)
  const vorher = await ev(() => __stadt.S().ki.haupt.length);
  await page.click('#karte [data-haupt="an"]');
  ok(await ev(() => __stadt.S().ki.haupt.length) === vorher + 1, `„Zur Hauptfigur machen“: ${vorher} → ${vorher + 1}`);
  ok(await ev(() => document.querySelector('#karte h3')?.textContent.startsWith('Tagebuch')), 'Karte zeigt danach Tagebuch');
  await page.click('#karte [data-haupt="aus"]');
  ok(await ev(() => __stadt.S().ki.haupt.length) === vorher, '„Keine Hauptfigur mehr“ nimmt zurück');
  await page.keyboard.press('Escape');

  // 4. Version 9, Teil 4 (Noahs Auftrag): Die KI entscheidet bei jedem Tempo, vorher „KI pausiert bei 20×“ (Spec, Zeile 381). Der Status bleibt
  //    „KI: Modell“, die Frist wächst mit dem Tempo (mindestens 20 echte Sekunden: 20× 7, 100× 34 Spielstunden). Um 18 Uhr entstehen Anfragen mit
  //    dieser Frist und werden beantwortet, keine zu spät
  for (const [t, frist] of [[20, 7], [100, 34]]) {
    await ev((t) => __stadt.setzeTempo(t), t);
    await page.waitForFunction((f) => __stadt.S().ki.an && __stadt.S().ki.fristStunden === f, frist, { timeout: 10000 });
    const status = await ev(() => document.getElementById('ki-status').textContent);
    ok(status === 'KI: test-modell:latest', `Status bei ${t}×: ${status}`);
    await ev(() => __stadt.setzeTempo(0));
    await page.waitForTimeout(100);
    await bisStunde(18);
    const g0 = await kiStat(), ab0 = await ev(() => __stadt.S().ki.abgelaufen);
    await ev((f) => { __stadt.Sim.kiSchalten(__stadt.S(), true, f); __stadt.schritt(); __stadt.nachSchritten(); }, frist);   // wie simTakt bei t×
    const fristen = await ev(() => __stadt.S().ki.anfragen.map(a => a.frist - a.tag * 24 - a.stunde));
    ok(fristen.length > 0 && fristen.every(x => x === frist), `bei ${t}× Anfragen um 18 Uhr mit ${frist} Spielstunden Frist: ${fristen.join(', ')}`);
    await page.waitForFunction(() => __stadt.S().ki.anfragen.length === 0, null, { timeout: 30000 });
    const st4 = await kiStat(), ab1 = await ev(() => __stadt.S().ki.abgelaufen);
    ok(st4.gueltig > g0.gueltig && st4.zuSpaet === g0.zuSpaet && ab1 === ab0 && st4.verworfen20 === undefined,
      `bei ${t}× beantwortet: gültig ${g0.gueltig} → ${st4.gueltig}, keine zu spät (${ab1 - ab0}), nichts wegen des Tempos verworfen (Zähler dafür gibt es nicht mehr)`);
  }
  await ev(() => __stadt.setzeTempo(1));
  await page.waitForTimeout(500);                        // ein paar Bilder: simTakt setzt die Frist wieder auf 2

  // 5. Kaputte Antworten: verworfen, gezählt, normales Gehirn entscheidet
  await modus('kaputt');
  const u0 = (await kiStat()).ungueltig;
  await bisStunde(7); await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });
  await page.waitForFunction(() => __stadt.S().ki.anfragen.length === 0, null, { timeout: 20000 });
  st = await kiStat();
  ok(st.ungueltig > u0, `ungültige Antworten gezählt: ${u0} → ${st.ungueltig} (letzter Fehler: ${st.fehler})`);
  await modus('falsch');
  const u1 = st.ungueltig;
  await bisStunde(18); await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });
  await page.waitForFunction(() => __stadt.S().ki.anfragen.length === 0, null, { timeout: 20000 });
  st = await kiStat();
  ok(st.ungueltig > u1, `Aktion außerhalb der Liste verworfen: ${u1} → ${st.ungueltig}`);

  // 6. Ollama aus: „KI nicht erreichbar“, kein Absturz, Eingabe gesperrt
  await modus('aus');
  await page.waitForTimeout(300);
  await bisStunde(7); await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });
  await page.waitForFunction(() => __stadt.S().ki.anfragen.length === 0, null, { timeout: 20000 });
  await ev(() => { __stadt.ki.geprueft = -1e9; });
  await page.waitForTimeout(1500);
  st = await kiStat();
  console.log('     KI aus:', JSON.stringify(st));
  ok(await ev(() => document.getElementById('ki-status').textContent) === 'KI nicht erreichbar', 'Status: ' + await ev(() => document.getElementById('ki-status').textContent));
  await nachfolgeZu();
  await page.click('#haupt-liste .haupt-zeile');
  await page.waitForTimeout(150);
  ok(await ev(() => document.getElementById('sagen-text').disabled), 'Eingabefeld gesperrt, solange die KI fehlt');
  await page.screenshot({ path: OUT + 'p4_aus.png' });
  await page.keyboard.press('Escape');
  await modus('gut');
  await ev(() => { __stadt.ki.geprueft = -1e9; });
  await page.waitForFunction(() => __stadt.ki.status === 'bereit', null, { timeout: 10000 });
  ok(true, 'Ollama wieder da → Status bereit');

  // 7. Hauptfigur stirbt: Dialog „wer übernimmt?“
  const opfer = await ev(() => { const S = __stadt.S(), h = S.ki.haupt[0]; S.p.geb[h.id] = S.tag - 110 * __stadt.Sim.R.JAHR; return __stadt.Sim.name(S, h.id); });
  await bisStunde(0);
  await page.waitForTimeout(800);
  const dlg = await ev(() => ({ offen: document.getElementById('nachfolge-dialog').open, titel: document.getElementById('nachfolge-titel').textContent,
    knoepfe: [...document.querySelectorAll('#nachfolge-knoepfe button')].map(b => b.textContent) }));
  console.log('     Nachfolge:', JSON.stringify(dlg));
  ok(dlg.offen && dlg.titel.startsWith(opfer), `Dialog nach dem Tod von ${opfer}`);
  await page.screenshot({ path: OUT + 'p4_nachfolge.png' });
  const h0 = await ev(() => __stadt.S().ki.haupt.length);
  await page.click('#nachfolge-knoepfe button');
  const h1 = await ev(() => __stadt.S().ki.haupt.length);
  ok(!await ev(() => document.getElementById('nachfolge-dialog').open) && (dlg.knoepfe.length === 1 ? h1 === h0 : h1 === h0 + 1), `Auswahl übernommen (${h0} → ${h1})`);

  // 8. Frame-Zeit mit und ohne KI (SwiftShader, nur als Vergleich)
  await ev(() => __stadt.setzeTempo(5));
  await page.waitForTimeout(6000);
  const mit = await ev(() => globalThis.__stadtDebug.frameMs);
  await modus('aus'); await ev(() => { __stadt.ki.geprueft = -1e9; });
  await page.waitForTimeout(6000);
  const ohne = await ev(() => globalThis.__stadtDebug.frameMs);
  console.log(`     Frame Ø mit KI ${mit.toFixed(1)} ms, ohne KI ${ohne.toFixed(1)} ms`);
  await modus('gut');

  const dbg = await ev(() => document.getElementById('debug').textContent);
  console.log('     Debug-Ecke:\n' + dbg.split('\n').map(z => '       ' + z).join('\n'));
  await page.screenshot({ path: OUT + 'p4_ende.png' });
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.filter(l => !l.includes('11434')).length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
