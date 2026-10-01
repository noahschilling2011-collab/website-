// Version 10 (Etappe 2, Noahs Entscheidung 5): Eine Policy aus Version 9 gilt nicht mehr; geprüft wird, dass die Seite sie sichtbar ablehnt („neu
// trainieren“, Regeln entscheiden), beim Umschalten (Ordner ki/) und beim Datei-Import. Für den Ablauf der übrigen Prüfungen braucht der Test
// eine Policy dieser Version: Er macht beim Start aus der Testdatei eine Kopie mit Stadt-Version 10 (gleiche Gewichte, Name mit „_test_v10“,
// Hinweis „nur Testdaten“, Inhalts-Hash neu gerechnet) und legt nur diese Kopie in den Temp-Ordner ki/. Sie ist kein Training auf Version 10
// und kein Qualitätsbeleg; die Dateien in tests/ki_testdaten/ bleiben unverändert.
// Browsertest KI-Policy auf Version 9 (Etappe 1, Übertrag): echte Seite über einen eigenen Server mit relativen Pfaden (PORT, Wurzel ist ein
// Temp-Ordner mit einer Kopie von stadt.html und ki/ aus den Testdaten tests/ki_testdaten/ oder KI_ORDNER). Die Policy steckt nicht in
// stadt.html; das Spiel holt sie beim Umschalten aus ki/ (policies.json) oder per Datei-Import. Die Testdaten sind nicht freigegebene
// Smoke-Stände (kein Qualitätsbeleg), hier nur für den Ablauf. Geprüft: Start mit Regeln ohne Anfrage an ki/, Umschalten lädt aus ki/,
// Entscheidungen, Speichern/Laden (nur Verweis Name+Hash), Neuladen holt ki/ wieder, fehlender Ordner ki/ (echte 404), andere Policy
// gleichen Namens (anderer Hash) → Rückfall statt still der anderen, beschädigte Liste und beschädigte Dateien (Hash, NaN, Version 8, Pfad),
// Datei-Import (gültig, beschädigt, Version 8; Ergebnis sichtbar im Fenster), „Geladene Datei entfernen“, Auswertung laut Datei im Fenster,
// Texte ohne Doppelungen, Spielstand-Import mit vorhandener und fehlender Policy, Rückfall zur Laufzeit, file:// ohne Server, Konsole sauber
// außer den gewollten Fehlern.
// Die Testordner liegen im Temp-Ordner unter pruefung/browser/ (gleiche Herkunft → derselbe Spielstand, wie beim Verschieben der Datei).
// Three.js über tests/umgebung.cjs (THREE_DIR), Anfragen an localhost:11434 (Ollama) werden abgebrochen, nie weitergeleitet.
// Der Server läuft nur während dieses Tests; tests/alle.sh startet ihn deshalb erst, wenn der eigene Seitenserver beendet ist.
//   node tests/browser_ki.cjs     (PORT, PLAYWRIGHT, THREE_DIR, KI_ORDNER, BILD=datei.png optional)
const path = require('path');
const fs = require('fs');
const net = require('net');
const { spawn } = require('child_process');
const vm = require('vm');
const { pathToFileURL } = require('url');
const U = require('./umgebung.cjs');
const { chromium } = U;
const STADT_HTML = path.join(U.STADT, 'stadt.html');                                 // die Datei, die geprüft wird
// Ordner mit policies.json und der Policy: Testdaten, oder KI_ORDNER (relativ zum Ordner stadt/, z. B. KI_ORDNER=ki für die echte Policy)
const KI = process.env.KI_ORDNER ? path.resolve(U.STADT, process.env.KI_ORDNER) : path.join(__dirname, 'ki_testdaten');
const V8 = path.join(__dirname, 'ki_testdaten', 'v8', 'policy_lokal_1_bester.json');     // Version-8-Policy: immer aus den Testdaten
const BASIS = path.join(U.tempOrdner(), 'ki_seite');                                  // Wurzel des Servers: Kopie von stadt.html, ki/, pruefung/
const PORT = U.PORT;
const HOST = `http://127.0.0.1:${PORT}`;
const TB = path.join(BASIS, 'pruefung', 'browser');
const EINGEBETTET = /<script type="application\/json" id="ki-policy">/;   // wie policyTextAusHtml in tools/simkern.mjs

const frei = (port) => new Promise((ok) => { const s = net.connect(port, '127.0.0.1'); s.on('connect', () => { s.destroy(); ok(false); }); s.on('error', () => ok(true)); });
const warte = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const t0 = Date.now();
  let server = null, b = null, fehler = 0;
  const ok = (bed, text) => { console.log((bed ? 'ok   ' : 'FEHL ') + text); if (!bed) fehler++; };
  try {
    const altDatei = JSON.parse(fs.readFileSync(path.join(KI, 'policies.json'), 'utf8')).policies[0];
    const altText = fs.readFileSync(path.join(KI, altDatei), 'utf8'), altJson = JSON.parse(altText);
    const html = fs.readFileSync(STADT_HTML, 'utf8');
    // Version 10: Version und Inhalts-Hash rechnet der sim-Block dieser stadt.html (wie im Spiel); Kopie der Testdatei mit dieser Version (siehe oben)
    const sctx = vm.createContext({}); vm.runInContext(html.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], sctx);
    const VERSION = sctx.StadtSim.VERSION;
    let polDatei = altDatei, polJson = altJson;
    if (altJson.simVersion !== VERSION) {
      polDatei = `policy_test_v${VERSION}.json`;
      polJson = { ...JSON.parse(altText), name: `${altJson.name}_test_v${VERSION}`, status: 'test', simVersion: VERSION,
        hinweis: `Nur Testdaten für den Ablauf: Gewichte von ${altJson.name} (Stadt-Version ${altJson.simVersion}), Version umgeschrieben, nicht neu trainiert.` };
      polJson.hash = sctx.StadtSim.KI.policyHash(polJson);
    }
    const polText = JSON.stringify(polJson);
    fs.mkdirSync(path.join(BASIS, 'ki'), { recursive: true });
    fs.copyFileSync(STADT_HTML, path.join(BASIS, 'stadt.html'));
    fs.writeFileSync(path.join(BASIS, 'ki', polDatei), polText);
    fs.writeFileSync(path.join(BASIS, 'ki', 'policies.json'), JSON.stringify({ format: 'stadt-policy-liste', version: 1, policies: [polDatei] }));
    console.log(`stadt.html ${Buffer.byteLength(html)} Byte (Version ${VERSION}), eingebettete Policy: ${EINGEBETTET.test(html) ? 'JA' : 'keine'}; ki/${polDatei} „${polJson.name}“ Hash ${polJson.hash}`
      + (polJson !== altJson ? ` (Kopie von ${altDatei}, Stadt-Version ${altJson.simVersion}, Hash ${altJson.hash})` : ''));
    ok(!EINGEBETTET.test(html), 'stadt.html enthält keine Policy (nicht freigegeben → nur in ki/)');
    // Testordner (gleiche Herkunft): ohne_ki (nur stadt.html), andere (Policy gleichen Namens mit anderem Hash), kaputt (Dateien), kaputt_liste
    fs.rmSync(TB, { recursive: true, force: true });
    for (const d of ['ohne_ki', 'andere/ki', 'kaputt/ki', 'kaputt_liste/ki', 'alt/ki']) fs.mkdirSync(path.join(TB, d), { recursive: true });
    for (const d of ['ohne_ki', 'andere', 'kaputt', 'kaputt_liste', 'alt']) fs.copyFileSync(path.join(BASIS, 'stadt.html'), path.join(TB, d, 'stadt.html'));
    // Version 10: die Testdatei aus Version 9 unverändert in alt/ki/ (Ablehnung beim Umschalten)
    fs.copyFileSync(path.join(KI, altDatei), path.join(TB, 'alt', 'ki', altDatei));
    fs.writeFileSync(path.join(TB, 'alt', 'ki', 'policies.json'), JSON.stringify({ format: 'stadt-policy-liste', version: 1, policies: [altDatei] }));
    fs.writeFileSync(path.join(TB, 'kaputt_liste', 'ki', 'policies.json'), '{ "format": "stadt-policy-liste", kaputt');
    fs.writeFileSync(path.join(TB, 'leer.html'), '<!doctype html><meta charset="utf-8"><title>leer</title><link rel="icon" href="data:,">');   // gleiche Herkunft, ohne Stadt
    if (!(await frei(PORT))) throw new Error(`Port ${PORT} ist belegt – nichts gestartet`);
    server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1', '--directory', BASIS], { stdio: ['ignore', 'ignore', 'pipe'] });
    let serverLog = '';
    server.stderr.on('data', (x) => { serverLog += x; });
    for (let i = 0; i < 50 && (await frei(PORT)); i++) await warte(100);
    console.log(`Server: python3 -m http.server ${PORT} (PID ${server.pid}), Wurzel ${BASIS}`);

    b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
    await ctx.route('http://localhost:11434/**', (r) => r.abort());   // Ollama: nie weiterleiten (der Nachbau auf 11434 bleibt unberührt)
    await ctx.route('http://127.0.0.1:11434/**', (r) => r.abort());
    const mitThree = !!U.THREE;
    await U.three(ctx);
    const page = await ctx.newPage();
    const konsole = [], anfragen = [];
    page.on('console', m => { if (['error', 'warning'].includes(m.type())) konsole.push({ art: m.type(), text: m.text(), url: (m.location() || {}).url || '', seite: page.url() }); });
    page.on('pageerror', e => konsole.push({ art: 'pageerror', text: e.message, url: '', seite: page.url() }));
    page.on('request', r => { const u = r.url(); if (u.includes('/ki/')) anfragen.push(u.replace(HOST, '')); });
    const gescheitert = [];
    page.on('requestfailed', r => gescheitert.push({ host: new URL(r.url()).host, url: r.url().replace(HOST, ''), grund: (r.failure() || {}).errorText || '', seite: page.url().replace(HOST, '') }));
    const bereit = async (url) => { await page.goto(url.startsWith('file:') ? url : HOST + url); await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 60000 }); await page.evaluate(() => __stadt.setzeTempo(0)); };
    const stand = () => page.evaluate(() => ({ aktiv: !!__stadt.Sim.KI.policyAktiv(), name: (__stadt.Sim.KI.policyAktiv() || {}).name || '',
      hash: (__stadt.Sim.KI.policyAktiv() || {}).hash || '', st: __stadt.Sim.KI.policyStand(), regeln: document.getElementById('ki-entscheid-regeln').checked,
      policy: document.getElementById('ki-entscheid-policy').checked, status: document.getElementById('ki-policy-status').textContent,
      optionen: [...document.getElementById('ki-policy-wahl').options].map(o => o.textContent),
      meldung: document.getElementById('meldung').hidden ? '' : document.getElementById('meldung').textContent, meldungArt: document.getElementById('meldung').className,
      auswertung: document.getElementById('ki-policy-auswertung').hidden ? '' : document.getElementById('ki-policy-auswertung').textContent,
      vergessen: !document.getElementById('ki-policy-vergessen').hidden,
      // Status wirklich sichtbar (nicht hinter einem Fenster): das Element in seiner Mitte ist der Status selbst (nur bei offenem Fenster)
      statusSichtbar: (() => { const e = document.getElementById('ki-policy-status'), q = e.getBoundingClientRect(); if (!q.width) return false;
        const x = document.elementFromPoint(q.left + q.width / 2, q.top + q.height / 2); return !!x && (x === e || e.contains(x)); })() }));
    const anzahl = (text, teil) => text.split(teil).length - 1;
    const stunden = (n) => page.evaluate((n) => { for (let i = 0; i < n; i++) __stadt.schritt(); __stadt.nachSchritten(); }, n);
    const spielstand = () => page.evaluate(() => { __stadt.speichern(); return JSON.parse(localStorage.getItem('stadt-save-v1')); });
    const meldungLeeren = () => page.evaluate(() => { document.getElementById('meldung').hidden = true; });
    // Einstellungen → Knopf „Entscheidungen: …“ → eigenes Fenster (die Einstellungen von V9 passen bei 1280 × 800 gerade ohne Scrollen)
    const offen = (id) => page.evaluate((id) => document.getElementById(id).open, id);
    const kiOeffnen = async () => { if (await offen('ki-dialog')) return; if (!(await offen('einst-dialog'))) await page.click('#einst-knopf'); await page.click('#ki-knopf'); };
    const alleZu = async () => { for (let i = 0; i < 3 && await page.evaluate(() => !!document.querySelector('dialog[open]')); i++) await page.keyboard.press('Escape'); };
    const policyWaehlen = async () => {                    // „Trainierte Policy (experimentell)“, warten bis geladen oder abgelehnt
      await kiOeffnen();
      await page.click('#ki-entscheid-policy');
      await page.waitForFunction(() => !/wird aus dem Ordner ki\/ geladen/.test(document.getElementById('ki-policy-status').textContent), null, { timeout: 15000 });
      return stand();
    };

    // 1. Neue Stadt: Regeln, keine Anfrage an ki/ (die Policy wird erst beim Umschalten geholt)
    await bereit('/stadt.html?neu&seed=1&debug');
    let s = await stand();
    ok(!s.aktiv && s.regeln && !s.policy && anfragen.length === 0, `Start: Regeln (Standard), keine Anfrage an ki/ (${anfragen.length}), Auswahl „${s.optionen.join(' | ')}“, 3D ${mitThree ? 'mit lokaler Three.js-Kopie' : 'mit Three.js aus dem Netz'}`);
    // 1b. Version 10 (Entscheidung 5): die Policy aus Version 9 in ki/ wird beim Umschalten sichtbar abgelehnt („neu trainieren“), es entscheiden
    //     die Regeln (Status im Fenster sichtbar, Warnung); die Version steht im Grund
    if (altJson.simVersion !== VERSION) {
      await bereit('/pruefung/browser/alt/stadt.html?neu&seed=7&debug');
      await meldungLeeren();
      s = await policyWaehlen();
      const grundAlt = `${altDatei}: Policy ungültig: trainiert auf Stadt-Version ${altJson.simVersion}, diese Stadt ist Version ${VERSION} (neu trainieren)`;
      ok(!s.aktiv && s.regeln && !s.policy && s.status.includes(grundAlt) && s.statusSichtbar && /Keine gültige Policy/.test(s.meldung + s.status) && s.meldungArt === 'warnung',
        `Policy aus Version ${altJson.simVersion} in ki/: abgelehnt und sichtbar, Regeln: „${s.status.slice(0, 220)}“`);
      await alleZu();
      anfragen.length = 0;
      await bereit('/stadt.html?neu&seed=1&debug');
    } else ok(false, `Testdatei ${altDatei} ist schon von Version ${VERSION}: Ablehnung einer älteren Policy nicht prüfbar`);
    // 2. Umschalten lädt aus ki/ (relative URL) und prüft streng
    s = await policyWaehlen();
    ok(s.aktiv && s.policy && s.hash === polJson.hash && anfragen.includes('/ki/policies.json') && anfragen.includes('/ki/' + polDatei) && /ki\//.test(s.status),
      `umgeschaltet: aus ki/ geladen (${anfragen.join(', ')}), „${s.status.slice(0, 150)}“`);
    const urteil = polJson.auswertung && polJson.auswertung.urteil ? polJson.auswertung.urteil : 'keine angegeben';
    ok(s.auswertung.startsWith('Auswertung laut Datei: ' + urteil) && (!polJson.hinweis || s.auswertung.includes(polJson.hinweis.slice(0, 40))),
      `Auswertung laut Datei im Fenster: „${s.auswertung.slice(0, 140)}“`);
    if (process.env.BILD) await page.locator('#ki-dialog').screenshot({ path: process.env.BILD });
    const lage = await page.evaluate(() => { const k = document.getElementById('ki-dialog'), e = document.getElementById('einst-dialog');
      return { kiSh: k.scrollHeight, kiCh: k.clientHeight, kiSw: k.scrollWidth, kiCw: k.clientWidth, eSh: e.scrollHeight, eCh: e.clientHeight,
        knopf: document.getElementById('ki-knopf').textContent, p3: (document.querySelector('#einst-dialog p.leise:nth-of-type(3)') || {}).textContent || '' }; });
    ok(lage.eSh <= lage.eCh && /^Ollama muss/.test(lage.p3.trim()) && lage.kiSw <= lage.kiCw && lage.kiSh <= lage.kiCh && lage.knopf === 'Entscheidungen: Policy ›',
      `Einstellungen bei 1280 × 800 ohne Scrollen (${lage.eSh}/${lage.eCh} px, 3. Absatz weiter der Ollama-Text), Knopf „${lage.knopf}“, eigenes Fenster ${lage.kiSh}/${lage.kiCh} px, ohne Scrollen und ohne seitliches Überlaufen`);
    await alleZu();
    await stunden(30);
    s = await stand();
    ok(s.aktiv && s.st.entscheidungen > 0 && s.st.rueckfall === 0, `30 Spielstunden mit Policy: ${s.st.entscheidungen} Entscheidungen, ${s.st.ausgefuehrt} ausgeführt, ${s.st.warten}× gewartet, ${s.st.regeln} nach Regeln, kein Rückfall`);
    // 3. Speichern: nur der Verweis (Name + Hash + Schema), keine Gewichte; Spielstand-Version wie die Datei (seit Etappe 2: 10)
    let d = await spielstand();
    ok(d.version === VERSION && d.ui && d.ui.entscheidungen && d.ui.entscheidungen.art === 'policy' && d.ui.entscheidungen.hash === polJson.hash
      && d.ui.entscheidungen.name === polJson.name && !JSON.stringify(d).includes('gewichte'), `Spielstand (Version ${d.version}): ui.entscheidungen = ${JSON.stringify(d.ui.entscheidungen)}, keine Gewichte`);
    // 4. Neu laden: Wahl bleibt, die Policy kommt wieder aus ki/ (nicht aus dem Spielstand)
    anfragen.length = 0;
    await bereit('/stadt.html?debug');
    s = await stand();
    ok(s.aktiv && s.hash === polJson.hash && anfragen.includes('/ki/' + polDatei), `neu geladen: Policy „${s.name}“ wieder aktiv, vor dem Start aus ki/ geholt (${anfragen.length} Anfragen)`);
    // 5. Dieselbe Stadt, Seite ohne Ordner ki/ daneben (echte 404): Regeln, sichtbarer Rückfall, danach gespeichert „regeln“
    await bereit('/pruefung/browser/ohne_ki/stadt.html?debug');
    s = await stand();
    d = await spielstand();
    ok(!s.aktiv && s.regeln && /Rückfall/.test(s.meldung) && /nicht lesbar/.test(s.meldung) && /HTTP 404/.test(s.status) && s.meldungArt === 'warnung' && d.ui.entscheidungen.art === 'regeln',
      `ohne ki/: Regeln, Meldung (${s.meldungArt}) „${s.meldung.slice(0, 170)}“, Stand sagt jetzt regeln`);
    await kiOeffnen();
    s = await stand();
    ok(anzahl(s.status, 'nicht lesbar') === 1 && anzahl(s.meldung, 'nicht lesbar') === 1 && !/– Der/.test(s.status + s.meldung) && /neu wählen/.test(s.status),
      `Rückfall-Text ohne Doppelung (Grund je einmal), mit Hinweis zum neu Wählen: „${s.status.slice(0, 260)}“`);
    await alleZu();
    // 6. Policy gleichen Namens mit anderem Inhalt (anderer Hash) in ki/: nie still die andere
    const andere = await page.evaluate((t) => { const x = JSON.parse(t); x.netz.schichten[0].bias[0] = Math.fround(x.netz.schichten[0].bias[0] + 0.01);
      x.hash = __stadt.Sim.KI.policyHash(x); return x; }, polText);
    fs.writeFileSync(path.join(TB, 'andere', 'ki', polDatei), JSON.stringify(andere));
    fs.writeFileSync(path.join(TB, 'andere', 'ki', 'policies.json'), JSON.stringify({ format: 'stadt-policy-liste', version: 1, policies: [polDatei] }));
    await bereit('/stadt.html?debug');                        // wieder die echte Policy wählen und speichern
    s = await policyWaehlen();
    await alleZu();
    d = await spielstand();
    await bereit('/pruefung/browser/andere/stadt.html?debug');
    s = await stand();
    ok(!s.aktiv && s.regeln && /Rückfall/.test(s.meldung) && s.optionen.some(o => o.includes(andere.name)) && andere.hash !== polJson.hash && d.ui.entscheidungen.hash === polJson.hash,
      `andere Policy gleichen Namens (Hash ${andere.hash} statt ${polJson.hash}): Regeln, Rückfall sichtbar, die andere nur wählbar: „${s.meldung.slice(0, 120)}“`);
    s = await policyWaehlen();                               // ausdrücklich gewählt: dann gilt sie, mit ihrem eigenen Hash
    await alleZu();
    d = await spielstand();
    ok(s.aktiv && s.hash === andere.hash && d.ui.entscheidungen.hash === andere.hash, 'die andere Policy gilt nur nach ausdrücklicher Wahl, der Spielstand verweist dann auf ihren Hash');
    // 7. Beschädigte Dateien in ki/: Gewicht geändert (Hash alt), NaN, Version 8, fehlende Datei, Pfad außerhalb → alle abgelehnt, Regeln
    const geaendert = JSON.parse(polText); geaendert.name = 'gewicht_geaendert'; geaendert.netz.schichten[1].gewichte[0][0] += 0.5;
    const nan = JSON.parse(polText); nan.name = 'nan'; nan.netz.schichten[0].gewichte[3][4] = null;
    fs.writeFileSync(path.join(TB, 'kaputt', 'ki', 'policy_geaendert.json'), JSON.stringify(geaendert));
    fs.writeFileSync(path.join(TB, 'kaputt', 'ki', 'policy_nan.json'), JSON.stringify(nan));
    fs.copyFileSync(V8, path.join(TB, 'kaputt', 'ki', 'policy_v8.json'));
    fs.writeFileSync(path.join(TB, 'kaputt', 'ki', 'policies.json'), JSON.stringify({ format: 'stadt-policy-liste', version: 1,
      policies: ['policy_geaendert.json', 'policy_nan.json', 'policy_v8.json', 'policy_fehlt.json', '../../../stadt.html'] }));
    await bereit('/pruefung/browser/kaputt/stadt.html?neu&seed=2&debug');
    await meldungLeeren();
    s = await policyWaehlen();
    ok(!s.aktiv && s.regeln && /passt nicht zum Inhalt/.test(s.status) && /Schicht 0: Zahl/.test(s.status) && /Stadt-Version 8/.test(s.status) && /policy_fehlt\.json: HTTP 404/.test(s.status)
      && /Dateiname/.test(s.status) && /Keine gültige Policy/.test(s.meldung + s.status) && s.meldungArt === 'warnung',
      `beschädigte Dateien in ki/: alle abgelehnt, Regeln: „${s.status.slice(0, 330)}“`);
    await alleZu();
    // 8. Beschädigte Liste ki/policies.json
    await bereit('/pruefung/browser/kaputt_liste/stadt.html?neu&seed=3&debug');
    s = await policyWaehlen();
    ok(!s.aktiv && s.regeln && /policies\.json: .*JSON/.test(s.status), `beschädigte ki/policies.json: Regeln, „${s.status.slice(0, 160)}“`);
    await alleZu();
    // 9. Datei-Import in den Einstellungen (Seite ohne ki/): beschädigt und Version 8 abgelehnt, gültig angenommen und gewählt, bleibt nach Neuladen
    await bereit('/pruefung/browser/ohne_ki/stadt.html?neu&seed=4&debug');
    await kiOeffnen();
    const laden = async (name, text) => { await meldungLeeren(); await page.setInputFiles('#ki-policy-datei', { name, mimeType: 'application/json', buffer: Buffer.from(text) });
      await page.waitForFunction(() => !document.getElementById('meldung').hidden, null, { timeout: 5000 }).catch(() => {}); return stand(); };
    s = await laden('policy_geaendert.json', JSON.stringify(geaendert));
    ok(/abgelehnt/.test(s.meldung) && /passt nicht zum Inhalt/.test(s.meldung) && !s.aktiv, `Datei-Import beschädigt: „${s.meldung.slice(0, 110)}“`);
    ok(/policy_geaendert\.json“ abgelehnt: .*passt nicht zum Inhalt/.test(s.status) && s.statusSichtbar,
      `Datei-Import beschädigt: Grund im Fenster sichtbar (nicht nur in der Meldung hinter den Fenstern): „${s.status.slice(-120)}“`);
    s = await laden('abgeschnitten.json', polText.slice(0, 5000));
    const englisch = /Unexpected|Expected|position/.test(s.status + s.meldung);
    s = await laden('policy_v8.json', fs.readFileSync(V8, 'utf8'));
    ok(/abgelehnt/.test(s.meldung) && /Stadt-Version 8/.test(s.meldung) && !s.aktiv, `Datei-Import Version-8-Policy: „${s.meldung.slice(0, 120)}“`);
    s = await laden(altDatei, altText);                      // Version 10: die Policy aus Version 9 (Etappe 1), sichtbar im Fenster
    ok(/abgelehnt/.test(s.meldung) && new RegExp(`trainiert auf Stadt-Version ${altJson.simVersion}, diese Stadt ist Version ${VERSION} \\(neu trainieren\\)`).test(s.status) && s.statusSichtbar && !s.aktiv && s.regeln,
      `Datei-Import der Policy aus Version ${altJson.simVersion}: abgelehnt, im Fenster „${s.status.slice(-130)}“`);
    s = await laden(polDatei, polText);
    ok(/geprüft und geladen/.test(s.meldung) && !s.aktiv && s.optionen.some(o => o.includes(polJson.name)), `Datei-Import gültig: „${s.meldung.slice(0, 100)}“ (noch nicht gewählt)`);
    ok(/geprüft und geladen/.test(s.status) && /„Trainierte Policy \(experimentell\)“ wählen/.test(s.status) && s.statusSichtbar && s.vergessen && !englisch
      && !/Keine gültige Policy vorhanden, es entscheiden weiter/.test(s.status),
      `Datei-Import gültig: im Fenster sichtbar, alter Hinweis weg, „Geladene Datei entfernen“ da, abgeschnittene Datei ohne englischen JSON-Fehler: „${s.status.slice(-130)}“`);
    await page.click('#ki-entscheid-policy');
    await page.waitForFunction(() => !/wird aus dem Ordner ki\/ geladen/.test(document.getElementById('ki-policy-status').textContent), null, { timeout: 15000 });
    s = await stand();
    await alleZu();
    ok(s.aktiv && s.hash === polJson.hash && /geladen/.test(s.status), `importierte Policy gewählt (ohne ki/): „${s.status.slice(0, 120)}“`);
    await spielstand();
    await bereit('/pruefung/browser/ohne_ki/stadt.html?debug');
    s = await stand();
    ok(s.aktiv && s.hash === polJson.hash && !/Rückfall/.test(s.meldung), 'neu geladen ohne ki/: die importierte Policy (Speicherplatz stadt-policy-v1) gilt wieder');
    // „Geladene Datei entfernen“: Speicherplatz leer, die Policy war gewählt und liegt nicht in ki/ → Regeln, gespeichert
    await kiOeffnen();
    await page.click('#ki-policy-vergessen');
    s = await stand();
    d = await spielstand();
    const restDatei = await page.evaluate(() => localStorage.getItem('stadt-policy-v1'));
    await alleZu();
    ok(restDatei === null && !s.aktiv && s.regeln && !s.vergessen && /Geladene Datei entfernt/.test(s.status) && !s.optionen.some(o => o.includes(polJson.name)) && d.ui.entscheidungen.art === 'regeln',
      `„Geladene Datei entfernen“: Speicherplatz leer, Regeln, Knopf weg: „${s.status.slice(-90)}“`);
    // 10. Spielstand-Import (Einstellungen → Import): Policy vorhanden → gilt; Policy fehlt → Regeln, Rückfall in derselben Meldung
    await bereit('/stadt.html?neu&seed=5&debug');
    const importText = (hash, name) => page.evaluate(([hash, name, schema]) => { __stadt.speichern(); const t = JSON.parse(localStorage.getItem('stadt-save-v1'));
      t.ui.entscheidungen = { v: 1, art: 'policy', name, hash, schema }; return JSON.stringify(t); }, [hash, name, polJson.schemaHash]);
    const importieren = async (text) => { await meldungLeeren(); await alleZu(); await page.click('#einst-knopf');
      await page.setInputFiles('#import-datei', { name: 'stadt-save.json', mimeType: 'application/json', buffer: Buffer.from(text) });
      await page.waitForFunction(() => /Spielstand geladen/.test(document.getElementById('meldung').textContent) && !document.getElementById('meldung').hidden, null, { timeout: 15000 }).catch(() => {});
      return stand(); };
    anfragen.length = 0;
    s = await importieren(await importText(polJson.hash, polJson.name));
    ok(s.aktiv && s.hash === polJson.hash && /Spielstand geladen/.test(s.meldung) && !/Rückfall/.test(s.meldung) && anfragen.includes('/ki/' + polDatei),
      `Import eines Spielstands mit Policy: aus ki/ geholt und aktiv (${s.meldung.slice(0, 60)})`);
    s = await importieren(await importText('0123456789abcdef', 'gibtsnicht'));
    d = await spielstand();
    ok(!s.aktiv && s.regeln && /Spielstand geladen/.test(s.meldung) && /gibtsnicht/.test(s.meldung) && /Rückfall/.test(s.meldung) && s.meldungArt === 'warnung' && d.ui.entscheidungen.art === 'regeln',
      `Import mit fehlender Policy: Regeln, Meldung (${s.meldungArt}) „${s.meldung.slice(0, 150)}“`);
    await alleZu();
    // 11. Spielstand ohne Modellwahl (09083f5): Regeln, keine Rückfall-Meldung, keine Anfrage an ki/
    const ohneWahl = await page.evaluate(() => { __stadt.speichern(); const t = JSON.parse(localStorage.getItem('stadt-save-v1')); delete t.ui.entscheidungen; return JSON.stringify(t); });
    await page.goto(HOST + '/pruefung/browser/leer.html');     // Stadt-Seite zu (sie speichert beim Verlassen), dann den Stand ändern
    await page.evaluate((t) => localStorage.setItem('stadt-save-v1', t), ohneWahl);
    anfragen.length = 0;
    await bereit('/stadt.html?debug');
    s = await stand();
    ok(!s.aktiv && s.regeln && !/Rückfall/.test(s.meldung + s.status) && anfragen.length === 0, 'Spielstand ohne ui.entscheidungen (wie 09083f5): Regeln, keine Rückfall-Meldung, keine Anfrage an ki/');
    // 12. Rückfall zur Laufzeit: Logits laufen über → Regeln, sichtbar, gespeichert. Seit der float32-Prüfung (Vorarbeit Etappe 2) lehnt
    //     policyPruefen die Datei mit Gewichten 1e308 ab (geprüft), keine geprüfte Datei läuft mehr über; darum wird die letzte Schicht einer
    //     geprüften Policy erst danach im Speicher unendlich (genau die Werte, die Math.fround(1e308) vorher ins Netz brachte)
    const grund12 = await page.evaluate(() => {
      const K = __stadt.Sim.KI, n = K.MERKMALE.length, na = K.AKTIONEN.length;
      const d = { format: 'stadt-policy', formatVersion: K.FORMAT, name: 'ueberlauf', status: 'test', simVersion: __stadt.Sim.VERSION, schemaHash: K.schemaHash(),
        beobachtung: { schemaVersion: K.SCHEMA, laenge: n, merkmale: K.MERKMALE.map(m => m[0]) }, aktionen: { liste: K.AKTIONEN.slice() },
        normalisierung: { mittel: new Array(n).fill(0), streuung: new Array(n).fill(1), clip: 5 },
        netz: { schichten: [{ gewichte: Array.from({ length: 4 }, () => new Array(n).fill(0)), bias: [50, 50, 50, 50], aktivierung: 'tanh' },
          { gewichte: Array.from({ length: na }, () => new Array(4).fill(1e308)), bias: new Array(na).fill(1e308), aktivierung: 'linear' }] } };
      d.hash = K.policyHash(d);
      let grund = '';
      try { K.policyPruefen(d); } catch (e) { grund = e.message; }
      d.netz.schichten[1].gewichte = Array.from({ length: na }, () => new Array(4).fill(1)); d.netz.schichten[1].bias = new Array(na).fill(1);
      d.hash = K.policyHash(d);
      const pol = K.policyPruefen(d);
      pol.schichten[1].w.fill(Infinity); pol.schichten[1].bias.fill(Infinity);
      K.policySetzen(pol);
      return grund;
    });
    await stunden(30);
    await page.waitForTimeout(1500);
    s = await stand();
    d = await spielstand();
    ok(/float32/.test(grund12) && !s.aktiv && s.regeln && /Rückfall/.test(s.meldung) && s.meldungArt === 'fehler' && d.ui.entscheidungen.art === 'regeln',
      `Datei mit Gewichten 1e308 abgelehnt („${grund12}“); Laufzeitfehler: Regeln, Meldung „${s.meldung.slice(0, 120)}“`);
    // 13. Als einzelne Datei (file://, ohne Server): Umschalten zeigt den Grund, Regeln bleiben; keine fetch-Anfrage
    anfragen.length = 0;
    await bereit(pathToFileURL(STADT_HTML).href + '?neu&seed=6&debug');
    s = await policyWaehlen();
    ok(!s.aktiv && s.regeln && /file:\/\//.test(s.status) && /Policy-Datei laden/.test(s.status) && anfragen.length === 0, `file://: Regeln, „${s.status.slice(0, 150)}“`);
    ok(anzahl(s.status, 'Keine gültige Policy') === 1 && anzahl(s.status, 'file://') === 1, `file://: jeder Satz einmal: „${s.status}“`);
    await alleZu();

    // Konsole: erlaubt sind nur die gewollten Fehler (Ollama abgebrochen; 404 der Fälle „ohne ki/“ und „policy_fehlt.json“)
    const gewollt = (k) => /:11434\//.test(k.url) || (/Failed to load resource/.test(k.text) && (/\/pruefung\/browser\/ohne_ki\/ki\/policies\.json$/.test(k.url)
      || /\/pruefung\/browser\/kaputt\/ki\/policy_fehlt\.json$/.test(k.url)));
    const rest = konsole.filter(k => !gewollt(k));
    const n404 = konsole.filter(k => gewollt(k) && !/:11434\//.test(k.url)).length, nOll = konsole.filter(k => /:11434\//.test(k.url)).length;
    ok(rest.length === 0, `Konsole: ${konsole.length} Meldungen error/warning, davon ${nOll} Ollama (abgebrochen, gewollt), ${n404} × 404 der Fälle ohne ki/ und fehlende Datei (gewollt), ${rest.length} andere`);
    for (const k of rest.slice(0, 10)) console.log(`   ${k.art}: ${k.text.slice(0, 200)} [${k.url}] auf ${k.seite}`);
    const hosts = [...new Set(gescheitert.map(g => g.host))], fremd = gescheitert.filter(g => !/:11434$/.test(g.host));
    ok(!fremd.length, `abgebrochene Anfragen: ${gescheitert.length}, an ${hosts.join(', ') || '–'}; außer Ollama (absichtlich): ${fremd.length}`);
    for (const g of fremd) console.log(`   ${g.url} (${g.grund}) auf ${g.seite}`);
    const serverZeilen = serverLog.split('\n').filter(z => /" \d{3} /.test(z));
    console.log(`Server-Log: ${serverZeilen.length} Anfragen, davon 404: ${serverZeilen.filter(z => /" 404 /.test(z)).map(z => z.split('"')[1]).join('; ')}`);
  } catch (e) { console.error(e); fehler++; }
  finally {
    if (b) await b.close().catch(() => {});
    if (server) { server.kill('SIGTERM'); console.log(`Server PID ${server.pid} beendet`); }
  }
  console.log(`Dauer ${((Date.now() - t0) / 1000).toFixed(1)} s, ${fehler ? fehler + ' FEHL' : 'alles ok'}`);
  process.exit(fehler ? 1 : 0);
})();
