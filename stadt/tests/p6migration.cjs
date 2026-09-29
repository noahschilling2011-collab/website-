// Spielstand v2 → „Stadt übernehmen“ im Versionsdialog, Import einer v2-Datei, Stand anderer Version ohne Übernehmen,
// Spielstand v4 (vor der Stadtregierung) → übernehmen, Stadtregierung ab dem Übernahmetag; Spielstand v5 (Stadtregierung ohne
// Schritt 2, Git 414ebab per git show) → übernehmen, Schritt 2 ab dem Übernahmetag; Spielstand v6 (Schritt 2, feste Karte 96 × 96,
// Git bc7247a per git show) → übernehmen, „Stadt erweitern“ ab dem Übernahmetag; dazu Seed 2 an Tag 260 (Wartezeit der Kaserne,
// Nachprüfung); Spielstand v7 (Stadt erweitern, Sicherheit, Bund; Git ffa1d88 per git show) → übernehmen, Autos und
// Tech-Stufen ab dem Übernahmetag; Spielstand v8 (Autos; Git 31ce452 per git show) → übernehmen, Rathaus so nah an der Mitte wie
// frei und Bürgermeisterwahl, sobald es steht. Heute gilt Version 9.
const NEU = 9;
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
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
  // Zeitstempel relativ zu jetzt: „10 Minuten weg“ (fest im File hieße: mit jedem echten Tag mehr Aufholen, bis 90 Tage)
  const alt = JSON.parse(U.v2Spielstand());
  alt.zuletztGelaufen = Date.now() - 10 * 60 * 1000;
  const v2 = JSON.stringify(alt);

  // 1. Alter Stand im Speicher → Dialog mit drei Knöpfen
  await page.goto(U.LEER);
  await ev((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, v2);
  await page.goto(U.HOST + '/stadt.html?debug');
  await page.waitForFunction(() => globalThis.__stadt);
  await page.waitForTimeout(500);
  const d = await ev(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d.offen && d.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*', 'Dialog: ' + d.knoepfe.join(', ') + ' – „' + d.text + '“');
  ok(await ev(() => localStorage.getItem('stadt-save-v1').includes('"version":2')), 'alter Stand bleibt gespeichert, solange der Dialog offen ist');
  await page.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog.png' });
  await page.click('#version-uebernehmen');
  await page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await page.waitForTimeout(1500);
  const s = await ev(() => { const S = __stadt.S(); return { tag: S.tag, stunde: S.stunde, einw: S.einwohner, bauhof: S.bauhof, version: S.version,
    buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute baut der Bauhof'))
      && [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute regiert die AfD')),
    gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent,
    weg: document.getElementById('weg-dialog') ? document.getElementById('weg-dialog').open : null }; });
  ok(s.bauhof === 2 && s.version === NEU && s.gespeichert === NEU, `übernommen: Tag ${s.tag} ${s.stunde} Uhr, ${s.einw} Einwohner (vorher Tag ${alt.werte.tag}), Bauhof ${s.bauhof}, gespeichert als Version ${s.gespeichert}`);
  ok(s.buch, 'Stadtbuch zeigt „Ab heute baut der Bauhof …“ und „Ab heute regiert die AfD …“');
  ok(s.meldung.includes('wachsende Karte mit Stadtteilen') && s.meldung.length <= 400, `Meldung nennt „Stadt erweitern“ (kurz: ${s.meldung.length} Zeichen; Befund Bedienung der Schlussprüfung von Version 9)`);
  ok(s.tag * 24 + s.stunde > alt.werte.tag * 24 + alt.werte.stunde, `10 Minuten weg → aufgeholt (${alt.werte.tag}/${alt.werte.stunde} → ${s.tag}/${s.stunde}); Meldung: „${s.meldung}“`);
  // Neu laden: jetzt ohne Dialog
  await page.reload(); await page.waitForFunction(() => globalThis.__stadt); await page.waitForTimeout(500);
  ok(!(await ev(() => document.getElementById('version-dialog').open)) && (await ev(() => __stadt.S().bauhof)) === 2, 'nach dem Neuladen kein Dialog, Stadt läuft weiter');

  // 2. Import einer v2-Datei über die Einstellungen
  fs.mkdirSync(U.ordner('bilder_p6'), { recursive: true });
  fs.writeFileSync(U.ordner('bilder_p6') + 'v2import.json', v2);
  await ev(() => document.getElementById('einst-dialog').showModal());
  await page.setInputFiles('#import-datei', U.ordner('bilder_p6') + 'v2import.json');
  await page.waitForTimeout(1500);
  const imp = await ev(() => ({ meldung: document.getElementById('meldung').textContent, tag: __stadt.S().tag, bauhof: __stadt.S().bauhof, v: __stadt.S().version }));
  ok(imp.meldung.startsWith('Spielstand von Version 2 übernommen') && imp.meldung.includes('Stadtregierung') && imp.meldung.includes('Kitas') && imp.meldung.includes('Bauhof') && imp.meldung.length <= 400 && imp.v === NEU && imp.bauhof === 2, 'Import v2: „' + imp.meldung + '“');

  // 3. Stand einer anderen Version (hier 1): kein „Stadt übernehmen“, „Neu anfangen“ ist der Hauptknopf
  await ev((t) => { const d = JSON.parse(t); d.version = 1; localStorage.setItem('stadt-save-v1', JSON.stringify(d)); }, v2);
  await page.evaluate(() => { addEventListener('pagehide', (e) => e.stopImmediatePropagation(), true); });
  await ev(() => { window.__stadt.speichern = () => false; });
  await page.goto(U.LEER);
  await ev((t) => { const d = JSON.parse(t); d.version = 1; localStorage.setItem('stadt-save-v1', JSON.stringify(d)); }, v2);
  await page.goto(U.HOST + '/stadt.html?debug');
  await page.waitForFunction(() => globalThis.__stadt); await page.waitForTimeout(300);
  const d1 = await ev(() => [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')));
  ok(d1.join('|') === 'Export behalten|Neu anfangen*', 'Version 1: ' + d1.join(', '));

  // 4. Stand von Version 4 (stadt.orig.html, vor der Stadtregierung): Dialog, übernehmen, Stadtregierung ab dem Übernahmetag
  const ctx4 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx4);
  await ctx4.route('http://localhost:11434/**', (route) => route.abort());
  // Der Stand vor der Stadtregierung (Version 4, Git 96f6dc4) kommt per git show (tests/umgebung.cjs) unter derselben Adresse
  await U.fassungUnter(ctx4, 'v4');
  const p4 = await ctx4.newPage();
  p4.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v4 ' + m.type() + ': ' + m.text()); });
  p4.on('pageerror', e => log.push('v4 pageerror: ' + e.message));
  await p4.goto(U.LEER);
  await p4.evaluate(() => localStorage.clear());
  await p4.goto(U.HOST + '/stadt.orig.html?debug&seed=3&tage=150&neu');
  await p4.waitForFunction(() => globalThis.__stadt);
  const v4 = await p4.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1')); return { version: d.version, tag: d.werte.tag, einw: d.werte.einwohner }; });
  ok(v4.version === 4, `Stand der Version 4 gespeichert: Tag ${v4.tag}, ${v4.einw} Einwohner`);
  await p4.goto(U.HOST + '/stadt.html?debug');
  await p4.waitForFunction(() => globalThis.__stadt);
  await p4.waitForTimeout(500);
  const d4 = await p4.evaluate(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d4.offen && d4.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && d4.text.startsWith('Dein Spielstand ist von Version 4') && d4.text.includes('Stadtregierung'),
    'Dialog Version 4: ' + d4.knoepfe.join(', ') + ' – „' + d4.text + '“ / „' + d4.hinweis + '“');
  await p4.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog_v4.png' });
  await p4.click('#version-uebernehmen');
  await p4.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p4.waitForTimeout(800);
  const s4 = await p4.evaluate(() => { const S = __stadt.S(); return { version: S.version, start: S.regierung.start, schritt2: S.regierung.schritt2, tag: S.tag, einw: S.einwohner,
    gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, knopf: document.getElementById('regierung-knopf').textContent,
    buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute regiert die AfD')), meldung: document.getElementById('meldung').textContent }; });
  ok(s4.version === NEU && s4.gespeichert === NEU && s4.start === v4.tag && s4.schritt2 === v4.tag && s4.einw >= 1 && s4.buch && s4.knopf.includes(`seit Tag ${v4.tag}`) && s4.meldung.includes('Stadtregierung'),
    `übernommen: Version ${s4.version}, Stadtregierung seit Tag ${s4.start}, Knopf „${s4.knopf}“, Meldung „${s4.meldung}“`);
  await p4.click('#regierung-knopf'); await p4.waitForTimeout(300);
  const kopf = await p4.evaluate(() => document.querySelector('#regierung-inhalt .reg-unter').textContent);
  ok(kopf.includes(`seit Tag ${v4.tag}, Spielstand übernommen`), 'Fenster Stadtregierung: „' + kopf + '“');
  await p4.keyboard.press('Escape');
  await p4.reload(); await p4.waitForFunction(() => globalThis.__stadt); await p4.waitForTimeout(500);
  ok(!(await p4.evaluate(() => document.getElementById('version-dialog').open)) && (await p4.evaluate(() => __stadt.S().regierung.start)) === v4.tag, 'nach dem Neuladen kein Dialog, Stadtregierung bleibt');
  await ctx4.close();

  // 5. Stand von Version 5 (Stadtregierung ohne Schritt 2, Git 414ebab = Git 414ebab per git show unter stadt.orig.html): Dialog,
  //    übernehmen, Schritt 2 ab dem Übernahmetag
  const ctx5 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx5);
  await ctx5.route('http://localhost:11434/**', (route) => route.abort());
  await U.fassungUnter(ctx5, 'v5');
  const p5 = await ctx5.newPage();
  p5.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v5 ' + m.type() + ': ' + m.text()); });
  p5.on('pageerror', e => log.push('v5 pageerror: ' + e.message));
  await p5.goto(U.LEER);
  await p5.evaluate(() => localStorage.clear());
  await p5.goto(U.HOST + '/stadt.orig.html?debug&seed=3&tage=150&neu');
  await p5.waitForFunction(() => globalThis.__stadt);
  const v5 = await p5.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1')); return { version: d.version, tag: d.werte.tag, einw: d.werte.einwohner }; });
  ok(v5.version === 5, `Stand der Version 5 gespeichert: Tag ${v5.tag}, ${v5.einw} Einwohner`);
  await p5.goto(U.HOST + '/stadt.html?debug');
  await p5.waitForFunction(() => globalThis.__stadt);
  await p5.waitForTimeout(500);
  const d5 = await p5.evaluate(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d5.offen && d5.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && d5.text.startsWith('Dein Spielstand ist von Version 5') && d5.text.includes('Mieter')
    && d5.hinweis.includes('Beitragsjahre') && d5.text.includes('Die Stadt baut Kitas') && /mindestens \d+ Tage lang und bis kein Kind mehr auf einen Platz wartet \(höchstens \d+ Tage\), muss niemand wegen eines fehlenden Platzes zu Hause bleiben/.test(d5.hinweis), 'Dialog Version 5: ' + d5.knoepfe.join(', ') + ' – „' + d5.text + '“ / „' + d5.hinweis + '“');
  await p5.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog_v5.png' });
  await p5.click('#version-uebernehmen');
  await p5.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p5.waitForTimeout(800);
  const s5 = await p5.evaluate(() => { const S = __stadt.S(); return { version: S.version, start: S.regierung.start, schritt2: S.regierung.schritt2, tag: S.tag,
    gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent,
    buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute können Mieter ihre Wohnung') && li.textContent.includes('Die Stadt baut Kitas; bis kein Kind mehr auf einen Platz wartet')),
    // Sicherheit (Version 7): eine Zeile im Stadtbuch, ab dem Übernahmetag, noch niemand vorbestraft
    sich: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute gibt es in der Stadt Diebstahl, Wohnungseinbruch und Betrug')),
    sichStart: S.sicherheit.start, vorbestraft: __stadt.Sim.sicherheitInfo(S).vorbestraft,
    // Bund (Teil 3): eine Zeile im Stadtbuch, ab dem Übernahmetag, noch niemand im Dienst
    bund: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute baut der Bund in der Stadt: eine Kaserne der Bundeswehr')),
    bundStart: S.bund.start, dienst: S.p.bund.some(v => v > 0) }; });
  // Meldung seit der Schlussprüfung von Version 9 kurz (Stichworte je Version; Einzelheiten im Stadtbuch und im Versionsdialog)
  ok(s5.version === NEU && s5.gespeichert === NEU && s5.start === 0 && s5.schritt2 === v5.tag && s5.buch && s5.meldung.includes('Mieterkauf') && s5.meldung.includes('wachsende Karte mit Stadtteilen')
    && s5.sich && s5.sichStart === v5.tag && s5.vorbestraft === 0 && s5.meldung.includes('Kriminalität mit Polizei und Gericht')
    && s5.bund && s5.bundStart === v5.tag && !s5.dienst && s5.meldung.includes('Kaserne') && s5.meldung.length <= 400,
    `übernommen: Version ${s5.version}, Stadtregierung seit Tag ${s5.start}, Schritt 2 seit Tag ${s5.schritt2}, Sicherheit und Bund seit Tag ${s5.sichStart}/${s5.bundStart}, Meldung „${s5.meldung}“`);
  await p5.click('#regierung-knopf'); await p5.waitForTimeout(300);
  const kopf5 = await p5.evaluate(() => document.querySelector('#regierung-inhalt .reg-unter').textContent);
  ok(kopf5.includes(`Mieterkauf, Renteneintritt und Kitas seit Tag ${v5.tag}`), 'Fenster Stadtregierung: „' + kopf5 + '“');
  await p5.keyboard.press('Escape');
  await p5.reload(); await p5.waitForFunction(() => globalThis.__stadt); await p5.waitForTimeout(500);
  ok(!(await p5.evaluate(() => document.getElementById('version-dialog').open)) && (await p5.evaluate(() => __stadt.S().regierung.schritt2)) === v5.tag, 'nach dem Neuladen kein Dialog, Schritt 2 bleibt');
  await ctx5.close();

  // 6. Stand von Version 6 (Schritt 2, feste Karte 96 × 96; Git bc7247a per git show unter stadt.orig.html): Dialog,
  //    übernehmen, „Stadt erweitern“ ab dem Übernahmetag (Stufe nach den heutigen Einwohnern, Stadtteile, Karte), alles andere bleibt
  const ctx6 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx6);
  await ctx6.route('http://localhost:11434/**', (route) => route.abort());
  await U.fassungUnter(ctx6, 'v6');
  const p6 = await ctx6.newPage();
  p6.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v6 ' + m.type() + ': ' + m.text()); });
  p6.on('pageerror', e => log.push('v6 pageerror: ' + e.message));
  await p6.goto(U.LEER);
  await p6.evaluate(() => localStorage.clear());
  await p6.goto(U.HOST + '/stadt.orig.html?debug&seed=2&tage=300&neu');
  await p6.waitForFunction(() => globalThis.__stadt, null, { timeout: 120000 });
  const v6 = await p6.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1'));
    return { version: d.version, tag: d.werte.tag, einw: d.werte.einwohner, start: d.json.regierung.start, schritt2: d.json.regierung.schritt2, buchNr: d.werte.buchNr }; });
  ok(v6.version === 6, `Stand der Version 6 gespeichert: Tag ${v6.tag}, ${v6.einw} Einwohner (Seed 2 kommt dort bis 15 Felder an den alten Kartenrand)`);
  await p6.goto(U.HOST + '/stadt.html?debug');
  await p6.waitForFunction(() => globalThis.__stadt);
  await p6.waitForTimeout(500);
  const d6 = await p6.evaluate(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d6.offen && d6.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && d6.text.startsWith('Dein Spielstand ist von Version 6') && d6.text.includes('wächst die Karte')
    && d6.text.includes('Wohnungseinbruch') && d6.hinweis.includes('behält alles') && d6.hinweis.includes('niemand ist vorbestraft') && !d6.hinweis.includes('Kitas entstehen danach')
    && d6.text.includes('Kaserne mit Wehrpflicht') && d6.hinweis.includes('Einberufen wird erst ab der Eröffnung der Kaserne'), 'Dialog Version 6: ' + d6.knoepfe.join(', ') + ' – „' + d6.text + '“ / „' + d6.hinweis + '“');
  await p6.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog_v6.png' });
  await p6.click('#version-uebernehmen');
  await p6.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p6.waitForTimeout(1200);
  const s6 = await p6.evaluate(() => { const S = __stadt.S(); return { version: S.version, start: S.regierung.start, schritt2: S.regierung.schritt2, tag: S.tag, einw: S.einwohner,
    karte: S.karte, stufe: S.erweiterung.stufe, teile: S.erweiterung.teile.length, anzeige: document.getElementById('k-stufe').textContent,
    gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent,
    buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute zählt die Stadt ihre Größe') && li.textContent.includes('Die Karte ist von 96 × 96 auf')),
    sich: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute gibt es in der Stadt Diebstahl, Wohnungseinbruch und Betrug')),
    sichStart: S.sicherheit.start, wache: S.sicherheit.wache, bundStart: S.bund.start, kaserne: S.bund.kaserne,
    bund: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute baut der Bund in der Stadt: eine Kaserne der Bundeswehr')) }; });
  ok(s6.version === NEU && s6.gespeichert === NEU && s6.start === v6.start && s6.schritt2 === v6.schritt2 && s6.stufe === 2 && s6.anzeige === 'Stadt' && s6.teile >= 4 && s6.karte > 96 && s6.buch
    && s6.meldung.includes('wachsende Karte mit Stadtteilen') && !s6.meldung.includes('Mieterkauf') && s6.sich && s6.sichStart === v6.tag && s6.wache === -1
    && s6.meldung.includes('Kriminalität mit Polizei und Gericht') && s6.bund && s6.bundStart === v6.tag && s6.kaserne === -1 && s6.meldung.includes('Kaserne') && s6.meldung.length <= 300,
    `übernommen: Version ${s6.version}, Stadtregierung seit Tag ${s6.start}, Schritt 2 seit Tag ${s6.schritt2} (wie vorher), Stufe ${s6.anzeige}, ${s6.teile} Stadtteile, Karte ${s6.karte}; Meldung „${s6.meldung}“`);
  await p6.click('#regierung-knopf'); await p6.waitForTimeout(300);
  const karte6 = await p6.evaluate(() => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => x.textContent.includes('Die Stadt wächst'));
    return k ? { status: k.querySelector('.reg-status').textContent, live: k.querySelector('p.reg-live').textContent, teile: (k.querySelector('details .reg-live') || {}).textContent || '' } : null; });
  // Seit der Schlussprüfung (Befund B7) ist die Zeile kurz (Zahl der Stadtteile), die Liste steht im aufklappbaren Teil
  ok(!!karte6 && karte6.status === 'Spielregel' && karte6.live.includes(`Karte ${s6.karte} × ${s6.karte} Felder`) && /\d+ Stadtteile \(unten\)/.test(karte6.live) && karte6.teile.includes('Altstadt'),
    'Fenster Stadtregierung, Karte „Die Stadt wächst“: ' + (karte6 ? `„${karte6.status}“ – „${karte6.live.slice(0, 160)}…“; Stadtteile „${karte6.teile.slice(0, 60)}…“` : 'fehlt'));
  await p6.keyboard.press('Escape');
  // Sicherheit: In der ersten Nacht bestellt das Land die Anstalt am Stadtrand (die Stadt ist eine Stadt) und die Wache: Seit der
  // Schlussprüfung (Befund B1) findet ein Block auch dort Platz, wo eine Straße auf die Rasterlinie zwischen zwei freien Blöcken zuläuft
  // (vorher nach Übernahmen 1 bis 54 Tage später). Bund (Teil 3): in der ersten Nacht die Kaserne am
  // Stadtrand (die Stadt ist eine Stadt), falls Gelände frei ist; einberufen wird erst ab dem Tag nach der Eröffnung
  const land6 = await p6.evaluate(() => { const a = __stadt, S = a.S(), t = S.tag; while (S.tag === t) a.schritt();
    const jva = S.sicherheit.jva, zJ = S.buch.filter(e => e.art === 'sicherheit' && e.tag === t).map(e => a.Sim.klartext(e.text));
    const kas = S.bund.kaserne, zK = S.buch.filter(e => e.art === 'bund' && e.tag === t).map(e => a.Sim.klartext(e.text)).find(x => /^Der Bund lässt am Stadtrand .*Kaserne/.test(x)) || '';
    let vorher = 0;                                          // Dienst vor dem Tag nach der Eröffnung?
    while ((S.sicherheit.wache < 0 || (kas >= 0 && !S.bund.kOffen)) && S.tag < t + 60) { a.schritt(); if (S.p.bund.some(v => v >= a.Sim.WEHRDIENST) && (!S.bund.kOffen || S.tag < S.bund.kOffen)) vorher++; }
    a.nachSchritten(); a.speichern();
    const zW = S.buch.filter(e => e.art === 'sicherheit' && /^Das Land lässt .*Polizeiwache/.test(e.text)).map(e => e.tag + ': ' + a.Sim.klartext(e.text).slice(0, 60));
    const land = S.erweiterung.gelaende.filter(r => r[4] === S.sicherheit.wache || r[4] === S.sicherheit.jva).length;
    return { jva, wache: S.sicherheit.wache, tage: S.tag - t, gel: land, zJ: zJ.find(x => /^Das Land lässt .*Justizvollzugsanstalt/.test(x)) || '', zW: zW[0] || '',
      kas, zK, kOffen: S.bund.kOffen, vorher, kasGel: kas >= 0 && S.erweiterung.gelaende.some(r => r[4] === kas), t, karte: S.karte,
      ohneGelaende: kas < 0 && !a.Sim.gelaendeSuchen(S, 3, 2, true) && !a.Sim.gelaendeSuchen(S, 2, 3, true) }; });
  ok(land6.jva >= 0 && land6.zJ && land6.wache >= 0 && land6.gel === 2 && land6.zW.startsWith(land6.t + ':'),
    `Land: Anstalt und Wache in der ersten Nacht (Tag ${land6.t}: „${land6.zJ.slice(0, 80)}…“, „${land6.zW}…“), beide auf eigenem Gelände`);
  ok((land6.kas >= 0 ? land6.zK && land6.kasGel && land6.kOffen > land6.t : land6.ohneGelaende) && !land6.vorher,
    land6.kas >= 0 ? `Bund: Kaserne in der ersten Nacht bestellt („${land6.zK.slice(0, 80)}…“), auf eigenem Gelände, offen ab Tag ${land6.kOffen || '–'}; vorher niemand im Dienst`
      : 'Bund: noch kein Gelände für die Kaserne frei (der Bund sucht jede Nacht)');
  await p6.reload(); await p6.waitForFunction(() => globalThis.__stadt); await p6.waitForTimeout(500);
  // Karte wie beim Speichern (seit Teil 3 wächst sie danach oft noch einmal: die Kaserne am Rand, Stadt erweitern)
  const karteNeu = await p6.evaluate(() => __stadt.S().karte);
  ok(!(await p6.evaluate(() => document.getElementById('version-dialog').open)) && karteNeu === land6.karte, `nach dem Neuladen kein Dialog, Karte bleibt (${s6.karte} bei der Übernahme, ${land6.karte} beim Speichern, ${karteNeu} geladen)`);
  await ctx6.close();

  // 5. Version 6 an Tag 260 (Befund der Nachprüfung): Seed 2 hat dann an Straßen nur zwei freie Stellen, beide an einem Straßenende.
  //    Wache (Stufe Kleinstadt) und Anstalt nehmen sie in der ersten Nacht, die Kaserne wartet, bis die Stadt eine Straße weiterbaut
  //    (gemessen 15 Nächte, nb/mess/b1_warten.mjs). Der Test zeigt die Wartezeit; solange sie wartet, sagt das Fenster es und niemand wird
  //    einberufen. Die Kaserne muss innerhalb von 60 Nächten kommen (wie früher die Wache).
  //    Version 9: Beim Übernehmen nimmt zuerst das Rathaus einen der beiden Plätze (es wird beim Import gebaut, vor der ersten Nacht). Dann
  //    bekommt in der ersten Nacht nur die Wache den zweiten; Anstalt und Kaserne warten, das Fenster nennt beide, und beide müssen innerhalb
  //    von 60 Nächten kommen
  const ctx7 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx7);
  await ctx7.route('http://localhost:11434/**', (route) => route.abort());
  await U.fassungUnter(ctx7, 'v6');
  const p7 = await ctx7.newPage();
  p7.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v6/260 ' + m.type() + ': ' + m.text()); });
  p7.on('pageerror', e => log.push('v6/260 pageerror: ' + e.message));
  await p7.goto(U.LEER);
  await p7.evaluate(() => localStorage.clear());
  await p7.goto(U.HOST + '/stadt.orig.html?debug&seed=2&tage=260&neu');
  await p7.waitForFunction(() => globalThis.__stadt, null, { timeout: 120000 });
  const v7 = await p7.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1'));
    return { version: d.version, tag: d.werte.tag, stunde: d.werte.stunde, einw: d.werte.einwohner }; });
  ok(v7.version === 6 && v7.tag === 260, `Stand der Version 6 gespeichert: Seed 2, Tag ${v7.tag}, ${v7.stunde} Uhr, ${v7.einw} Einwohner`);
  await p7.goto(U.HOST + '/stadt.html?debug');
  await p7.waitForFunction(() => globalThis.__stadt);
  await p7.waitForTimeout(500);
  await p7.click('#version-uebernehmen');
  await p7.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p7.waitForTimeout(800);
  await p7.evaluate(() => __stadt.setzeTempo(0));
  const warte = await p7.evaluate(() => { const a = __stadt, S = a.S(), t = S.tag;
    const live = () => { a.nachSchritten(); const d = document.getElementById('regierung-dialog'); if (d.open) d.close();
      document.getElementById('regierung-knopf').click();          // Fenster neu öffnen: Zahlen von heute
      const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => x.textContent.includes('Die Stadt wächst'));
      const z = k ? k.querySelector('p.reg-live').textContent : ''; d.close(); return z; };
    const rathaus = S.rathaus.b;                                     // Version 9: beim Import gebaut
    while (S.tag === t) a.schritt();
    const r = { t, rathaus, stufe: S.erweiterung.stufe, wache: S.sicherheit.wache, jva: S.sicherheit.jva, jva1: S.sicherheit.jva, kaserne1: S.bund.kaserne, zeile: '', vorher: 0, naechte: 0, jvaNaechte: 0 };
    if (S.bund.kaserne < 0 || S.sicherheit.jva < 0) r.zeile = live();
    // Version 9, Teil 2: Kaserne und Anstalt je mit eigener Nacht (kommt die Kaserne vor der Anstalt, zählte die Schleife bis zur Anstalt), und
    // schon hier zählen, ob jemand vor der Eröffnung der Kaserne im Dienst ist
    let kasN = r.kaserne1 >= 0 ? 1 : 0;
    while ((S.bund.kaserne < 0 || S.sicherheit.jva < 0) && S.tag < t + 60) { a.schritt(); if (S.sicherheit.jva >= 0 && !r.jvaNaechte) r.jvaNaechte = S.tag - t;
      if (S.bund.kaserne >= 0 && !kasN) kasN = S.tag - t;
      if (S.bund.kaserne >= 0 && !S.bund.kOffen && S.p.bund.some(v => v >= a.Sim.WEHRDIENST)) r.vorher++; }
    r.jva = S.sicherheit.jva; if (r.jva1 >= 0) r.jvaNaechte = 1;
    r.naechte = S.bund.kaserne >= 0 ? kasN : -1;
    while (S.bund.kaserne >= 0 && !S.bund.kOffen && S.tag < t + 120) { a.schritt(); if (S.p.bund.some(v => v >= a.Sim.WEHRDIENST)) r.vorher++; }
    r.kOffen = S.bund.kOffen; r.zeileDanach = live();
    return r; });
  ok(warte.stufe === 2 && warte.rathaus >= 0 && warte.wache >= 0 && warte.jva >= 0 && warte.jvaNaechte >= 1 && warte.jvaNaechte <= 60
    && (warte.jva1 >= 0 || /kommt, sobald ein Platz frei ist: eine Justizvollzugsanstalt des Landes/.test(warte.zeile)),
    `Tag ${warte.t}: Rathaus beim Import (Gebäude ${warte.rathaus}), Wache in der ersten Nacht, Anstalt in Nacht ${warte.jvaNaechte} (Stufe Stadt)`);
  ok(warte.naechte >= 1 && warte.naechte <= 60 && !warte.vorher && warte.kOffen > warte.t + warte.naechte
    && (warte.kaserne1 >= 0 || /kommt, sobald ein Platz frei ist: (eine Justizvollzugsanstalt des Landes für die Region, )?eine Kaserne der Bundeswehr mit Wehrpflicht/.test(warte.zeile))
    && !warte.zeileDanach.includes('kommt, sobald ein Platz frei ist: eine Kaserne'),
    `Kaserne: bestellt in Nacht ${warte.naechte} nach der Übernahme` + (warte.kaserne1 >= 0 ? ' (erste Nacht)' : ` (wartete ${warte.naechte - 1} Nächte, Fenster: „…${(warte.zeile.match(/Mit der Stufe Stadt kommt, sobald[^.]*\./) || ['–'])[0]}“)`)
      + `, offen ab Tag ${warte.kOffen || '–'}, vorher niemand im Dienst`);
  await ctx7.close();

  // 7. Stand von Version 7 (Git ffa1d88 per git show unter stadt.orig.html): Dialog, übernehmen, Tech-Firmen und Autos ab
  //    dem Übernahmetag (niemand hat ein Auto, kein Werk), alles andere bleibt (Karte, Stufe, Stadtteile, Sicherheit, Bund, Regierung)
  const ctx8 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx8);
  await ctx8.route('http://localhost:11434/**', (route) => route.abort());
  await U.fassungUnter(ctx8, 'v7');
  const p8 = await ctx8.newPage();
  p8.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v7 ' + m.type() + ': ' + m.text()); });
  p8.on('pageerror', e => log.push('v7 pageerror: ' + e.message));
  await p8.goto(U.LEER);
  await p8.evaluate(() => localStorage.clear());
  await p8.goto(U.HOST + '/stadt.orig.html?debug&seed=2&tage=400&neu');
  await p8.waitForFunction(() => globalThis.__stadt, null, { timeout: 180000 });
  const v8a = await p8.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1'));
    return { version: d.version, tag: d.werte.tag, stunde: d.werte.stunde, einw: d.werte.einwohner, karte: d.werte.karte, stufe: d.json.erweiterung.stufe,
      teile: d.json.erweiterung.teile.length, sich: d.json.sicherheit.start, bund: d.json.bund.start, reg: d.json.regierung.start, buchNr: d.werte.buchNr,
      tech: d.arrays.find(a => a.name === 'g.typ') ? 1 : 0 }; });
  ok(v8a.version === 7, `Stand der Version 7 gespeichert: Seed 2, Tag ${v8a.tag}, ${v8a.stunde} Uhr, ${v8a.einw} Einwohner, Karte ${v8a.karte}, Stufe ${v8a.stufe}`);
  await p8.goto(U.HOST + '/stadt.html?debug');
  await p8.waitForFunction(() => globalThis.__stadt);
  await p8.waitForTimeout(500);
  const d8 = await p8.evaluate(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d8.offen && d8.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && d8.text.startsWith('Dein Spielstand ist von Version 7') && d8.text.includes('Autowerk')
    && d8.text.includes('Hochhaus') && d8.text.includes('aus dem Umland') && !d8.text.includes('wächst die Karte') && d8.hinweis.includes('behält alles')
    && d8.hinweis.includes('Autos gibt es ab dem Übernahmetag') && !d8.hinweis.includes('Kitas entstehen danach') && !d8.hinweis.includes('vorbestraft'),
    'Dialog Version 7: ' + d8.knoepfe.join(', ') + ' – „' + d8.text + '“ / „' + d8.hinweis + '“');
  await p8.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog_v7.png' });
  await p8.click('#version-uebernehmen');
  await p8.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p8.waitForTimeout(1200);
  const s8 = await p8.evaluate(() => { const a = __stadt, S = a.S(), k = a.Sim.autoKennzahlen(S); a.setzeTempo(0);
    return { version: S.version, tag: S.tag, einw: S.einwohner, karte: S.karte, stufe: S.erweiterung.stufe, teile: S.erweiterung.teile.length,
      sich: S.sicherheit.start, bund: S.bund.start, reg: S.regierung.start, autos: k.autos, werke: k.autowerke, stufen: k.techStufen.join('/'),
      gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent,
      buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute wachsen Tech-Firmen weiter')) }; });
  ok(s8.version === NEU && s8.gespeichert === NEU && s8.karte >= v8a.karte && s8.stufe === v8a.stufe && s8.teile >= v8a.teile && s8.sich === v8a.sich && s8.bund === v8a.bund
    && s8.reg === v8a.reg && s8.buch && s8.meldung.includes('Autos') && !s8.meldung.includes('wachsende Karte') && !s8.meldung.includes('Mieterkauf') && s8.meldung.length <= 250,
    `übernommen: Version ${s8.version}, Tag ${s8.tag}, Karte ${s8.karte}, Stufe ${s8.stufe}, ${s8.teile} Stadtteile, Sicherheit/Bund/Regierung seit Tag ${s8.sich}/${s8.bund}/${s8.reg} (wie vorher), `
    + `${s8.autos} Autos, ${s8.werke} Werke, Tech-Stufen ${s8.stufen}; Meldung „${s8.meldung}“`);
  // Danach: Autos aus dem Umland kommen (höchstens 30 Tage), das Fenster „Stadtregierung“ zeigt die Karte zu den Autos
  const nach8 = await p8.evaluate(() => { const a = __stadt, S = a.S(), t = S.tag;
    while (a.Sim.autoKennzahlen(S).autos === 0 && S.tag < t + 30) a.schritt();
    a.nachSchritten(); a.speichern();
    const k = a.Sim.autoKennzahlen(S);
    document.getElementById('regierung-knopf').click();
    const karte = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => (x.querySelector('h4') || {}).textContent?.includes('Tech-Firmen wachsen, Autowerke, Autos'));
    const z = karte ? (karte.querySelector('p.reg-live') || {}).textContent || '' : '';
    document.getElementById('regierung-dialog').close();
    return { tage: S.tag - t, autos: k.autos, aussen: k.autosAussen, live: z }; });
  ok(nach8.autos > 0 && nach8.aussen === nach8.autos && nach8.tage <= 30 && nach8.live.length > 0,
    `nach ${nach8.tage} Tagen das erste Auto (${nach8.autos}, alle aus dem Umland); Fenster Stadtregierung: „${nach8.live.slice(0, 140)}…“`);
  await p8.reload(); await p8.waitForFunction(() => globalThis.__stadt); await p8.waitForTimeout(500);
  const neu8 = await p8.evaluate(() => ({ offen: document.getElementById('version-dialog').open, autos: __stadt.Sim.autoKennzahlen(__stadt.S()).autos, v: __stadt.S().version }));
  ok(!neu8.offen && neu8.v === NEU && neu8.autos === nach8.autos, `nach dem Neuladen kein Dialog, ${neu8.autos} Autos bleiben`);
  await ctx8.close();

  // 8. Stand von Version 8 (Git 31ce452 per git show unter stadt.orig.html): Dialog, übernehmen, Rathaus so nah an der Mitte,
  //    wie ein Gelände frei ist (nichts wird abgerissen), Wahl in der ersten Nacht mit offenem Rathaus; Autos und alles andere bleiben
  const ctx9 = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx9);
  await ctx9.route('http://localhost:11434/**', (route) => route.abort());
  await U.fassungUnter(ctx9, 'v8');
  const p9 = await ctx9.newPage();
  p9.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push('v8 ' + m.type() + ': ' + m.text()); });
  p9.on('pageerror', e => log.push('v8 pageerror: ' + e.message));
  await p9.goto(U.LEER);
  await p9.evaluate(() => localStorage.clear());
  await p9.goto(U.HOST + '/stadt.orig.html?debug&seed=2&tage=400&neu');
  await p9.waitForFunction(() => globalThis.__stadt, null, { timeout: 180000 });
  const v9a = await p9.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); const d = JSON.parse(localStorage.getItem('stadt-save-v1')), S = __stadt.S();
    return { version: d.version, tag: d.werte.tag, stunde: d.werte.stunde, einw: d.werte.einwohner, karte: d.werte.karte, stufe: d.json.erweiterung.stufe, gAnzahl: S.gAnzahl,
      autos: __stadt.Sim.autoKennzahlen(S).autos, haupt: S.ki.haupt.length, typen: Array.from(S.g.typ.subarray(0, S.gAnzahl)).join(',') }; });
  ok(v9a.version === 8, `Stand der Version 8 gespeichert: Seed 2, Tag ${v9a.tag}, ${v9a.stunde} Uhr, ${v9a.einw} Einwohner, Karte ${v9a.karte}, Stufe ${v9a.stufe}, ${v9a.autos} Autos`);
  await p9.goto(U.HOST + '/stadt.html?debug');
  await p9.waitForFunction(() => globalThis.__stadt);
  await p9.waitForTimeout(500);
  const d9 = await p9.evaluate(() => ({ offen: document.getElementById('version-dialog').open, text: document.getElementById('version-text').textContent,
    hinweis: document.getElementById('version-hinweis').textContent,
    knoepfe: [...document.querySelectorAll('#version-dialog button')].filter(k => !k.hidden).map(k => k.textContent + (k.classList.contains('haupt') ? '*' : '')) }));
  ok(d9.offen && d9.knoepfe.join('|') === 'Export behalten|Neu anfangen|Stadt übernehmen*' && d9.text.startsWith('Dein Spielstand ist von Version 8') && d9.text.includes('Rathaus')
    && d9.text.includes('Bürgermeister') && !d9.text.includes('Autowerk') && d9.hinweis.includes('behält alles') && d9.hinweis.includes('Autowerke und Autos')
    && d9.hinweis.includes('Wohnhäuser und Betriebe bleiben stehen') && !d9.hinweis.includes('Autos gibt es ab dem Übernahmetag'),
    'Dialog Version 8: ' + d9.knoepfe.join(', ') + ' – „' + d9.text + '“ / „' + d9.hinweis + '“');
  await p9.screenshot({ path: U.ordner('bilder_p6') + 'p6_dialog_v8.png' });
  await p9.click('#version-uebernehmen');
  await p9.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 });
  await p9.waitForTimeout(1200);
  const s9 = await p9.evaluate(() => { const a = __stadt, S = a.S(); a.setzeTempo(0);
    return { version: S.version, tag: S.tag, einw: S.einwohner, karte: S.karte, stufe: S.erweiterung.stufe, autos: a.Sim.autoKennzahlen(S).autos, rathaus: S.rathaus.b,
      typen: Array.from(S.g.typ.subarray(0, S.gAnzahl)).join(','), gAnzahl: S.gAnzahl, bm: S.buergermeister.p, haupt: S.ki.haupt.length,
      gespeichert: JSON.parse(localStorage.getItem('stadt-save-v1')).version, meldung: document.getElementById('meldung').textContent,
      buch: [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute hat die Stadt ein Rathaus')),
      // Version 9, Teil 2: Schule ab dem Übernahmetag (Zeile, Summen 0, noch niemand mit Platz)
      schule: !!S.schule && S.schule.start === S.tag && S.p.schule.every(v => v === 0) && S.stat.schule.gebaut === 0
        && [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute baut die Stadt Schulen')),
      // Version 9, Teil 3: Haushalt ab dem Übernahmetag (Zeile, Satz der Lohnsteuer 10 %, Konten passen zum Budget, Zeile „Budget“ als Knopf)
      haushalt: !!S.haushalt && S.haushalt.start === S.tag && S.haushalt.satz === 10 && S.haushalt.summe.length === 20
        && Math.abs(S.haushalt.summe.reduce((x, v, k) => x + v + S.haushalt.ist[k], 0) - (S.budget - S.haushalt.kasseStart)) < 1
        && [...document.querySelectorAll('#buch-liste li')].some(li => li.textContent.includes('Ab heute führt die Stadt einen Haushalt'))
        && document.getElementById('k-satz').textContent === '10' && /Lohnsteuer 10 %/.test(document.getElementById('haushalt-knopf').getAttribute('aria-label')),
      // Version 9, Teil 4: Schalter „Wachstum“ normal (auch in den Einstellungen gedrückt), KI-Frist 2 Spielstunden, Zähler ganze Zahlen, keine Zeile dazu
      wachstum: S.wachstum === 0 && S.ki.fristStunden === 2 && Number.isInteger(S.ki.abgelaufen) && Number.isInteger(S.ki.angewandt)
        && JSON.parse(localStorage.getItem('stadt-save-v1')).werte.wachstum === 0 && !S.buch.some(e => e.art === 'wachstum')
        && document.querySelector('[data-wachstum="0"]').getAttribute('aria-pressed') === 'true' }; });
  // Alte Gebäude bleiben (gleiche Typen); dazu höchstens eins, das Rathaus (oder ein Park, der ihm weicht, wird es)
  const alteGleich = s9.typen.split(',').slice(0, v9a.gAnzahl).map((t, i) => t === v9a.typen.split(',')[i] || (i === s9.rathaus && v9a.typen.split(',')[i] === '5')).every(Boolean);
  ok(s9.version === NEU && s9.gespeichert === NEU && s9.einw === v9a.einw && s9.autos === v9a.autos && s9.stufe === v9a.stufe && s9.karte >= v9a.karte && alteGleich
    && s9.gAnzahl <= v9a.gAnzahl + 1 && s9.bm === -1 && s9.haupt === v9a.haupt && s9.buch && s9.meldung.includes('Rathaus mit Bürgermeister') && !s9.meldung.includes('Autos')
    && s9.schule && s9.meldung.includes('Schulen') && s9.haushalt && s9.meldung.includes('Haushalt') && s9.meldung.length <= 200 && s9.wachstum,
    `übernommen: Version ${s9.version}, Tag ${s9.tag}, ${s9.einw} Einwohner, ${s9.autos} Autos, Stufe ${s9.stufe}, Rathaus Gebäude ${s9.rathaus} (alte Gebäude gleich: ${alteGleich}), Schule ab heute (${s9.schule}), Haushalt ab heute (${s9.haushalt}), `
    + `Wachstum normal, KI-Frist 2 Spielstunden (${s9.wachstum}), `
    + `noch kein Bürgermeister; Meldung „${s9.meldung}“`);
  // Danach: Rathaus fertig (Bauhof), in der ersten Nacht mit offenem Rathaus die Wahl; der Bürgermeister steht zuerst in der Leiste
  const nach9 = await p9.evaluate(() => { const a = __stadt, S = a.S(), t = S.tag;
    while (S.buergermeister.p < 0 && S.tag < t + 40) a.schritt();
    a.nachSchritten(); a.speichern();
    const i = a.Sim.rathausInfo(S), z = document.querySelector('#haupt-liste .haupt-zeile');
    const si = a.Sim.schuleInfo(S);                        // Version 9, Teil 2: nach der ersten Nacht ohne Schule gehen die Kinder im Nachbarort
    return { tage: S.tag - t, offen: i.offen, name: i.name, bm: i.bm.person && i.bm.person.name, erst: z ? (z.querySelector('.amt-text') || {}).textContent || '' : '',
      schulen: si.offen[1] + si.offen[2] + si.bau[1] + si.bau[2], schueler: si.schueler[1] + si.schueler[2], nachbarort: si.nachbarort,
      zeile: [...document.querySelectorAll('#buch-liste li')].map(li => li.textContent).find(x => x.includes('Bürgermeisterwahl')) || '',
      hh: !!S.haushalt.gestern && a.Sim._hh.haushaltPruefen(S) === undefined && Math.abs(S.haushalt.summe.reduce((x, v, k) => x + v + S.haushalt.ist[k], 0) - (S.budget - S.haushalt.kasseStart)) < 1 }; });
  ok(nach9.offen && nach9.bm && nach9.tage <= 40 && /Bürgermeister/.test(nach9.erst) && /Erste Bürgermeisterwahl/.test(nach9.zeile) && nach9.schueler + nach9.nachbarort > 0 && nach9.hh,
    `nach ${nach9.tage} Tagen ${nach9.name} offen und ${nach9.bm} gewählt (${nach9.erst} zuerst in der Leiste); „${nach9.zeile.slice(0, 120)}…“; `
    + `Schulen offen oder im Bau: ${nach9.schulen}, ${nach9.schueler} Schüler, ${nach9.nachbarort} im Nachbarort; Haushalt geprüft (Konten von gestern, Kasse passt): ${nach9.hh}`);
  await p9.reload(); await p9.waitForFunction(() => globalThis.__stadt); await p9.waitForTimeout(500);
  const neu9 = await p9.evaluate(() => ({ offen: document.getElementById('version-dialog').open, bm: __stadt.S().buergermeister.p >= 0, v: __stadt.S().version }));
  ok(!neu9.offen && neu9.v === NEU && neu9.bm, 'nach dem Neuladen kein Dialog, der Bürgermeister bleibt im Amt');
  await ctx9.close();
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
