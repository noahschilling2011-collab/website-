// Etappe 2, Schritt 3 (Personenkarte): Erfahrung, Plan, letzte Entscheidung, „Warum?“ und die Liste „Heute anders entschieden“ im echten Browser
// (Chromium, Playwright), Seitenserver auf PORT (Wurzel: Ordner stadt/). Ein echter Fall aus einem gespeicherten Stand:
// 0. In Node (Sim-Block dieser stadt.html) Seed 1 rechnen und ab Tag 300 den ersten Fall suchen, in dem die Regeln ohne Erfahrung gegründet
//    hätten (Sim.warum mit dem Zufallsstand der Meldung: ohneErfahrung = laden_gruenden, gewählt etwas anderes, direkt) und die Person eine
//    Gründen-Erfahrung in ihrer heutigen Lage hat (Stand 30.09.2026: Person 94, Tag 370, 7 Uhr). Stand um 0 Uhr dieses Tages als Spielstand
//    (Version 10) in localStorage.
// 1. Seite laden (Pause), Stunde für Stunde bis nach dem Fall: Knopf „… anders“ im Kopf des Stadtbuchs mit Zahl (Name beginnt mit dem sichtbaren Text).
// 2. Klick: Karte „Heute anders entschieden“ mit dem Eintrag des Falls (Uhrzeit, Name, „statt „einen Betrieb gründen“ → …“, Grund).
// 3. Klick auf den Namen: Karte genau dieser Person (Platz und Generation). 4. Karte: Erfahrung „Gründen: 1-mal, … → zählt −…“, Plan, letzte
//    Entscheidung, Lebenslauf in Langzeit und Kurzzeit; in Erfahrung und Plan kein Name (keiner aus den Namenslisten der Stadt).
// 4b. Karte einer Person mit offener Folge und fehlender Rücklage: „wird noch … beobachtet“, „spart: … von … Talern“, letzte Entscheidung mit Quelle.
// 5. „Warum?“ in der Karte: Summanden und „Ohne diese Erfahrung hätte … einen Betrieb gegründet“; nur der eigene Vorname. 6. „Warum?“ im Eintrag.
// 7. Der Beobachter ändert nichts: derselbe Stand in einer zweiten Seite ohne Beobachter, gleiche Stunden → derselbe Spielstand.
// 8. Handy 390 × 844: Liste und Karte ohne seitliches Scrollen, Knopf im Kopf des Stadtbuchs ohne Umbruch. 9. Tastatur: Tab zum Knopf, Enter,
//    Tab zum Namen, Enter, Tab zu „Warum?“, Enter (aria-expanded), Escape schließt. 10. Konsole ohne Fehler. Bilder in AUSGABE/bilder_gedaechtnis/.
// Seit der Schlussprüfung von Etappe 2 (Befunde Bedienung): 5b. Der Satz „Ohne diese Erfahrung hätte …“ nennt die Rechnung seines Vergleichs, ihre
//    Teile ergeben die Summe, die über der Schwelle liegt (Karte und Eintrag). 11. Die Liste nennt, seit wann sie zählt; ohne Änderung wird sie beim
//    stündlichen Auffrischen nicht neu eingesetzt; der oberste sichtbare Eintrag bleibt an seiner Stelle, wenn neue dazukommen und heute zu gestern wird.
// Anfragen an localhost:11434 (Ollama) werden im Browser abgebrochen, nie weitergeleitet.
//   PORT=9092 node tests/gedaechtnis.cjs      (Server vorher starten, wie tests/LIESMICH.md; PLAYWRIGHT, THREE_DIR)
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const path = require('path');
const vm = require('vm');

(async () => {
  const t0 = Date.now();
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const OUT = U.ordner('bilder_gedaechtnis');

  // 0. Fall suchen und Stand bauen (Node, derselbe Sim-Block)
  const html = fs.readFileSync(path.join(U.STADT, 'stadt.html'), 'utf8');
  const ctxN = vm.createContext({}); vm.runInContext(html.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], ctxN);
  const Sim = ctxN.StadtSim, SEED = 1, AB = 300;
  const A = Sim.neueStadt(SEED);
  let fall = null;
  Sim.beobachter = (p, gen, tag, h, mit, ohne, grund, rsVor) => {
    if (fall || tag < AB) return;
    const w = Sim.warum(A, p, h, rsVor);
    if (w.ohneErfahrung !== 'laden_gruenden' || w.wahl === 'laden_gruenden' || w.art.erfahrung !== 'direkt') return;
    const e = Sim.gedInfo(A, p).erfahrung.find(x => x.aktion === 'laden_gruenden' && x.jetzt);
    if (e) fall = { p, gen, tag, h, wahl: w.wahl, grund, punkte: e.punkte, wert: e.wert, n: e.n };
  };
  while (!fall && A.tag < 900) Sim.stunde(A);
  Sim.beobachter = null;
  ok(!!fall, `echter Fall (Seed ${SEED}, ab Tag ${AB}): ${fall ? `Person ${fall.p} (Generation ${fall.gen}), Tag ${fall.tag}, ${fall.h} Uhr, gewählt „${fall.wahl}“, ohne Erfahrung „laden_gruenden“, `
    + `Grund „${fall.grund}“, Gründen-Erfahrung Wert ${fall.wert} × ${fall.n} → ${fall.punkte}` : 'keiner bis Tag 900'} (Node, ${Math.round((Date.now() - t0) / 1000)} s)`);
  if (!fall) { process.exitCode = 1; return; }
  const B = Sim.neueStadt(SEED);
  while (B.tag < fall.tag) Sim.stunde(B);
  const dB = Sim.exportZustand(B);
  const stand = JSON.stringify({ ...dB, arrays: dB.arrays.map(a => ({ name: a.name, typ: a.typ, b64: Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength).toString('base64') })),
    zuletztGelaufen: Date.now(), tempo: 0, ui: {} });
  const pktSoll = (v) => { const r = Math.round(v * 100) / 100; return (r > 0 ? '+' : r < 0 ? '−' : '') + Math.abs(r).toLocaleString('de-DE', { maximumFractionDigits: 2 }); };   // wie die Karte
  const NAMEN = new Set([...Sim.VORNAMEN_W, ...Sim.VORNAMEN_M, ...Sim.NACHNAMEN].map(String));

  const b = await chromium.launch({ args: U.ARGS });
  const konsole = [];
  const seite = async (viewport, opt = {}) => {
    const ctx = await b.newContext({ viewport, ...opt });
    await ctx.route('http://localhost:11434/**', (r) => r.abort());
    await ctx.route('http://127.0.0.1:11434/**', (r) => r.abort());
    await U.three(ctx);
    const page = await ctx.newPage();
    page.on('console', m => { if (m.type() === 'error' && !/:11434\//.test((m.location() || {}).url || '')) konsole.push(m.text() + ' @ ' + ((m.location() || {}).url || '')); });
    page.on('pageerror', e => konsole.push('pageerror: ' + e.message));
    await page.goto(U.LEER);
    await page.evaluate((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, stand);
    await page.goto(U.HOST + '/stadt.html?debug');
    await page.waitForFunction(() => globalThis.__stadt && __stadt.S());
    await page.evaluate(() => __stadt.setzeTempo(0));
    return { ctx, page };
  };
  // bis nach der Stunde des Falls (h Uhr gerechnet: S.stunde = h + 1), je Stunde wie die Seite (schritt, dann nachSchritten)
  const rechnen = (page, ohneBeobachter) => page.evaluate(([tag, h, ohne]) => {
    const a = __stadt, S = a.S();
    if (ohne) a.Sim.beobachter = null;
    let n = 0;
    while (S.tag < tag || S.stunde <= h) { a.schritt(); a.nachSchritten(); n++; }
    return { n, tag: S.tag, stunde: S.stunde, beob: typeof a.Sim.beobachter, fehler: a.Sim.beobachterFehler };
  }, [fall.tag, fall.h, !!ohneBeobachter]);
  const kanon = (o) => JSON.stringify(o, (k, v) => (v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map(x => [x, v[x]])) : v));
  const kern = (t) => { const d = JSON.parse(t); return kanon([d.format, d.version, d.werte, d.json, d.arrays.slice().sort((x, y) => (x.name < y.name ? -1 : 1))]); };

  // 1. Breit (1280 × 800): Stand laden, rechnen
  const { ctx, page } = await seite({ width: 1280, height: 800 });
  const r1 = await rechnen(page);
  const knopf = await page.evaluate(() => { const k = document.getElementById('erf-knopf'); return { hidden: k.hidden, zahl: document.getElementById('erf-zahl').textContent, label: k.getAttribute('aria-label'), text: k.textContent }; });
  ok(!knopf.hidden && Number(knopf.zahl.replace(/\./g, '')) >= 1 && /^\d+ anders entschieden \(heute\) wegen Erfahrung oder Plan/.test(knopf.label) && knopf.label.startsWith(knopf.text.trim()) && r1.beob === 'function' && !r1.fehler,
    `nach ${r1.n} Stunden (Tag ${r1.tag}, ${r1.stunde} Uhr): Knopf im Stadtbuch „${knopf.text.trim()}“, aria-label „${knopf.label}“, Beobachter gesetzt, kein Fehler`);
  await page.screenshot({ path: OUT + 'g1_knopf.png' });

  // 2. Liste öffnen
  await page.click('#erf-knopf');
  await page.waitForTimeout(300);
  const liste = await page.evaluate(([p, g, h]) => {
    const li = [...document.querySelectorAll('#karte .erf-liste > li')];
    const n = li.find(x => { const b = x.querySelector('button.name'); return b && +b.dataset.p === p && +b.dataset.g === g && x.querySelector('.zeit').textContent === h + ' Uhr'; });
    return { titel: document.querySelector('#karte h2').textContent, zahl: li.length, fall: n ? n.textContent.replace(/\s+/g, ' ').trim() : null,
      zeiten: li.map(x => x.querySelector('.zeit').textContent).slice(0, 8), fokus: document.activeElement.tagName };
  }, [fall.p, fall.gen, fall.h]);
  ok(liste.titel === 'Heute anders entschieden' && liste.zahl >= 1 && !!liste.fall && /statt „einen Betrieb gründen“ → „/.test(liste.fall) && /Erfahrung/.test(liste.fall),
    `Liste „${liste.titel}“: ${liste.zahl} Einträge (Zeiten ${liste.zeiten.join(', ')}); Fall: „${liste.fall}“`);
  // 6. „Warum?“ im Eintrag
  await page.click(`#karte .erf-liste > li:has(button.name[data-p="${fall.p}"][data-g="${fall.gen}"]) button[data-erf-warum]`);
  await page.waitForTimeout(200);
  const lw = await page.evaluate(([p, g]) => {
    const li = document.querySelector(`#karte .erf-liste > li:has(button.name[data-p="${p}"][data-g="${g}"])`), k = li.querySelector('button[data-erf-warum]');
    return { exp: k.getAttribute('aria-expanded'), text: (li.querySelector('.warum') || {}).textContent || '', fokus: document.activeElement === k };
  }, [fall.p, fall.gen]);
  ok(lw.exp === 'true' && /Ohne diese Erfahrung hätte \S+ einen Betrieb gegründet/.test(lw.text) && /einen Betrieb gründen/.test(lw.text) && lw.fokus,
    `„Warum?“ im Eintrag: aufgeklappt, Fokus bleibt auf dem Knopf; „${lw.text.replace(/\s+/g, ' ').slice(0, 260)}…“`);
  await page.screenshot({ path: OUT + 'g2_liste.png' });
  await page.locator('#karte').screenshot({ path: OUT + 'g2_liste_karte.png' });

  // 3. Name → Karte genau dieser Person
  await page.click(`#karte .erf-liste button.name[data-p="${fall.p}"][data-g="${fall.gen}"]`);
  await page.waitForTimeout(300);
  const karte = await page.evaluate(([p]) => {
    const S = __stadt.S(), q = (s) => document.querySelector(s), t = (e) => (e ? e.textContent.replace(/\s+/g, ' ').trim() : '');
    const h3 = [...document.querySelectorAll('#karte h3')].map(h => h.textContent);
    return { name: t(q('#karte h2')), soll: __stadt.Sim.name(S, p), h3, ged: t(q('#karte .ged')), hinweis: t(q('#karte .ged-hinweis')), zurueck: !q('#karte-zurueck').hidden,
      lang: document.querySelectorAll('#karte .lebenslauf.lang li').length, kurz: document.querySelectorAll('#karte .lebenslauf.kurz li').length,
      mem: [...document.querySelectorAll('#karte .lebenslauf li')].map(t), knopf: t(q('#karte button[data-warum]')) };
  }, [fall.p]);
  ok(karte.name === karte.soll && karte.zurueck, `Klick auf den Namen öffnet die Karte von Person ${fall.p}: „${karte.name}“ (Sim.name „${karte.soll}“), „‹ zurück“ führt zur Liste`);
  const gruenden = (karte.ged.match(/Gründen: [^·]*?→ zählt [−+]?[\d,]+[^)]*\)/) || [''])[0];
  ok(/Gründen: \d-mal/.test(gruenden) && gruenden.includes('zählt ' + pktSoll(fall.punkte)) && /Plan: /.test(karte.ged) && /Letzte Entscheidung, etwas zu tun: Tag \d+, \d+ Uhr/.test(karte.ged),
    `Karte, Erfahrung und Plan: „${gruenden}“ (Sim: ${fall.punkte}); ${karte.ged.slice(0, 400)}…`);
  const woerter = new Set((karte.ged + ' ' + karte.hinweis).split(/[^\p{L}-]+/u).filter(Boolean));
  const namenIn = [...woerter].filter(w => NAMEN.has(w) || karte.soll.split(' ').includes(w));
  ok(namenIn.length === 0, `kein Name in Erfahrung und Plan (${woerter.size} Wörter gegen ${NAMEN.size} Namen der Stadt und den eigenen geprüft)${namenIn.length ? ': ' + namenIn.join(', ') : ''}`);
  ok(karte.h3.includes('Erfahrung und Plan') && karte.h3.includes('Lebenslauf') && karte.lang >= 1 && karte.kurz >= 1 && karte.mem.some(m => /weil: Gründung vor \d+ Tagen/.test(m)),
    `Lebenslauf getrennt: ${karte.lang} Langzeit, ${karte.kurz} Kurzzeit; mit Verweis: „${karte.mem.find(m => /weil:/.test(m)) || '–'}“`);
  // 5. „Warum?“ in der Karte (die gemeldete Entscheidung aus der Liste)
  await page.click('#karte button[data-warum]');
  await page.waitForTimeout(200);
  const kw = await page.evaluate(() => { const k = document.querySelector('#karte button[data-warum]'), w = document.querySelector('#karte .warum');
    return { exp: k.getAttribute('aria-expanded'), text: w ? w.textContent.replace(/\s+/g, ' ').trim() : '', zeilen: w ? w.querySelectorAll('.warum-liste li').length : 0, fokus: document.activeElement === k }; });
  const vorname = karte.soll.split(' ')[0];
  const fremd = [...new Set(kw.text.split(/[^\p{L}-]+/u))].filter(w => NAMEN.has(w) && w !== vorname);
  ok(kw.exp === 'true' && kw.zeilen >= 2 && /Lage und Charakter [−+]?[\d,]+/.test(kw.text) && /Erfahrung −[\d,]+/.test(kw.text)
    && new RegExp(`Ohne diese Erfahrung hätte ${vorname} einen Betrieb gegründet`).test(kw.text) && kw.text.includes(`um ${fall.h} Uhr`) && !fremd.length && kw.fokus,
    `„Warum?“ in der Karte: ${kw.zeilen} Handlungen mit Summanden, nennt die Wahl ohne Erfahrung, nur der eigene Vorname${fremd.length ? ' (fremd: ' + fremd.join(', ') + ')' : ''}; „${kw.text.slice(0, 300)}…“`);
  // 5b. Rechnung des Vergleichs „ohne Erfahrung“ hinter dem Satz (eigene Zufallszahl): Teile ergeben die Summe, die Summe liegt über 25
  const rechnung = (t) => {
    const m = t.replace(/\s+/g, ' ').match(/Ohne diese Erfahrung hätte \S+ einen Betrieb gegründet \(in dieser Rechnung: einen Betrieb gründen: ([^=]+)= ([−+]?[\d.,]+)( \(knapp über 25\))?/);
    if (!m) return null;
    const wert = (x) => Number(x.replace('−', '-').replace(/\./g, '').replace(',', '.'));
    const teile = [...m[1].matchAll(/(Lage und Charakter|Plan|Erfahrung|Zufall) ([−+]?[\d.,]+)/g)].map(x => wert(x[2])), summe = wert(m[2]);
    return { text: m[0], summe, passt: teile.length >= 2 && Math.abs(teile.reduce((a, b) => a + b, 0) - summe) <= 0.011 * teile.length && (summe > 25 || (summe === 25 && !!m[3])) };
  };
  const rk = rechnung(kw.text), rl = rechnung(lw.text);
  ok(!!rk && rk.passt && !!rl && rl.passt && rk.text === rl.text,
    `„Ohne diese Erfahrung …“ nachrechenbar (Karte und Eintrag gleich): „${rk ? rk.text : '– fehlt –'}“`);
  await page.locator('#karte').screenshot({ path: OUT + 'g3_karte_warum.png' });
  await page.screenshot({ path: OUT + 'g3_karte_breit.png' });
  // eine Stunde weiter: die Karte zeichnet sich neu, „Warum?“ bleibt offen, der Fokus bleibt auf dem Knopf
  await page.evaluate(() => { __stadt.schritt(); __stadt.nachSchritten(); });
  const kw2 = await page.evaluate(() => { const k = document.querySelector('#karte button[data-warum]'); return { exp: k.getAttribute('aria-expanded'), fokus: document.activeElement === k }; });
  ok(kw2.exp === 'true' && kw2.fokus, 'nach dem stündlichen Auffrischen: „Warum?“ bleibt offen, Fokus bleibt auf dem Knopf');

  // 7. Beobachter ändert nichts: zweite Seite ohne Beobachter, gleiche Stunden
  const mit = await page.evaluate(() => __stadt.spielstandText());
  const { ctx: ctx2, page: p2 } = await seite({ width: 1280, height: 800 });
  const r2 = await rechnen(p2, true);
  await p2.evaluate(() => { __stadt.schritt(); __stadt.nachSchritten(); });   // wie oben die Stunde mit offener Karte
  const ohne = await p2.evaluate(() => __stadt.spielstandText());
  ok(r2.beob === 'object' && kern(mit) === kern(ohne), `Beobachter und Liste ändern nichts: derselbe Stand ohne Beobachter nach ${r2.n + 1} Stunden, Spielstand (Einzelwerte, JSON-Teile, Arrays) gleich: ${kern(mit) === kern(ohne) ? 'ja' : 'NEIN'}`);
  // 4b. Offene Folge und Hindernis „spart“: erste Person mit beidem (Sim.gedInfo dieser Seite), Karte über einen Namen-Knopf wie in befunde_s2;
  //     die Karte nennt Rest der Beobachtung, Geld und Ziel der Rücklage wie gedInfo, die letzte Entscheidung mit Quelle, keinen Namen
  const of = await p2.evaluate(() => {
    const a = __stadt, S = a.S(), zahl = (v) => (Math.round(v) + 0).toLocaleString('de-DE');
    let p = -1, g = null;
    for (let i = 0; i < S.pMax && p < 0; i++) { const x = a.Sim.gedInfo(S, i); if (x && x.offen && x.plan && x.plan.ruecklage && x.plan.ruecklage.geld < x.plan.ruecklage.ziel) { p = i; g = x; } }
    if (p < 0) return null;
    const k = document.createElement('button'); k.className = 'name'; k.dataset.p = p; k.dataset.g = S.p.gen[p]; k.dataset.n = a.Sim.name(S, p);
    document.body.appendChild(k); k.click(); k.remove();
    const ged = document.querySelector('#karte .ged'), r = g.offen.restTage, rl = g.plan.ruecklage;
    if (ged) ged.scrollIntoView({ block: 'start' });
    return { p, name: a.Sim.name(S, p), text: ged ? ged.textContent.replace(/\s+/g, ' ').trim() : '', offen: g.offen.aktion, quelle: g.letzteEntscheidung && g.letzteEntscheidung.quelle,
      sollOffen: `wird noch ${r === 1 ? '1 Tag' : zahl(r) + ' Tage'} beobachtet`, sollSpart: `spart: ${zahl(Math.max(0, rl.geld))} von ${zahl(rl.ziel)} Talern` };
  });
  if (of) await p2.locator('#karte').screenshot({ path: OUT + 'g6_karte_offen.png' });
  const ofNamen = of ? [...new Set(of.text.split(/[^\p{L}-]+/u))].filter(w => NAMEN.has(w) || of.name.split(' ').includes(w)) : [];
  ok(!!of && /Offene Folge: (Gründen|Kündigen|Stelle wechseln|Zusammenziehen) (heute|vor 1 Tag|vor [\d.]+ Tagen) · /.test(of.text) && of.text.includes(of.sollOffen)
    && of.text.includes(of.sollSpart) && /Letzte Entscheidung, etwas zu tun: Tag \d+, \d+ Uhr: .+ · nach den Regeln · (hat geklappt|klappte nicht)/.test(of.text) && of.quelle === 'regeln' && !ofNamen.length,
    of ? `Karte von Person ${of.p} (offene Folge „${of.offen}“, Rücklage fehlt): „${of.sollOffen}“, „${of.sollSpart}“, letzte Entscheidung mit Quelle, kein Name${ofNamen.length ? ' (' + ofNamen.join(', ') + ')' : ''}; „${of.text.slice(0, 330)}…“`
      : 'keine Person mit offener Folge und fehlender Rücklage gefunden');
  await ctx2.close();

  // 9. Tastatur (breit): Escape schließt, Tab zum Knopf, Enter, Tab zum Namen, Enter, Tab zu „Warum?“, Enter
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  const zu = await page.evaluate(() => document.getElementById('karte').hidden);
  await page.focus('#buch-knopf');
  await page.keyboard.press('Tab');
  const aufKnopf = await page.evaluate(() => document.activeElement.id);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  const t1 = await page.evaluate(() => ({ offen: !document.getElementById('karte').hidden, titel: (document.querySelector('#karte h2') || {}).textContent, fokus: document.activeElement.tagName }));
  let schritte = 0, amName = false;
  for (; schritte < 30 && !amName; schritte++) { await page.keyboard.press('Tab'); amName = await page.evaluate(() => document.activeElement.matches('#karte .erf-liste button.name')); }
  const tName = await page.evaluate(() => ({ p: +document.activeElement.dataset.p, g: +document.activeElement.dataset.g, n: document.activeElement.textContent }));
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  const tKarte = await page.evaluate(() => (document.querySelector('#karte h2') || {}).textContent);
  let amWarum = false, s2 = 0;
  for (; s2 < 40 && !amWarum; s2++) { await page.keyboard.press('Tab'); amWarum = await page.evaluate(() => document.activeElement.matches('#karte button[data-warum]')); }
  if (amWarum) await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  const tW = await page.evaluate(() => { const k = document.querySelector('#karte button[data-warum]'); return { exp: k && k.getAttribute('aria-expanded'), fokus: document.activeElement === k }; });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  // Escape gibt den Fokus dem Knopf „anders“ zurück, der die Liste geöffnet hat (Befund Bedienung: vorher body)
  const tZu = await page.evaluate(() => document.getElementById('karte').hidden), tZuFokus = await page.evaluate(() => document.activeElement.id || document.activeElement.tagName);
  ok(zu && aufKnopf === 'erf-knopf' && t1.offen && t1.titel === 'Heute anders entschieden' && t1.fokus === 'H2' && amName && tKarte === tName.n && amWarum && tW.exp === 'true' && tW.fokus && tZu && tZuFokus === 'erf-knopf',
    `Tastatur: Escape schließt; Tab vom Stadtbuch-Kopf auf „${aufKnopf}“, Enter öffnet die Liste (Fokus auf der Überschrift), ${schritte}× Tab zum Namen „${tName.n}“, Enter öffnet die Karte „${tKarte}“, `
    + `${s2}× Tab zu „Warum?“, Enter klappt auf (aria-expanded ${tW.exp}), Escape schließt, Fokus zurück auf „${tZuFokus}“`);
  await ctx.close();

  // 8. Handy 390 × 844 (Touch): Knopf im Stadtbuch-Kopf, Liste, Karte mit „Warum?“, kein seitliches Scrollen
  const { ctx: ctx3, page: p3 } = await seite({ width: 390, height: 844 }, { hasTouch: true, isMobile: true, deviceScaleFactor: 1 });
  await rechnen(p3);
  const breite = () => p3.evaluate(() => {
    const d = document.documentElement, k = document.getElementById('karte'), zuBreit = [];
    for (const e of document.querySelectorAll('#karte *')) { const r = e.getBoundingClientRect(); if (r.width && (r.right > innerWidth + 0.5 || r.left < -0.5)) zuBreit.push(e.tagName + '.' + e.className); }
    const kopf = document.querySelector('.buch-kopf').getBoundingClientRect(), ek = document.getElementById('erf-knopf').getBoundingClientRect(), bk = document.getElementById('buch-knopf').getBoundingClientRect();
    return { seite: d.scrollWidth, breit: innerWidth, karte: k.hidden ? null : [k.scrollWidth, k.clientWidth], zuBreit: zuBreit.slice(0, 5),
      kopf: [Math.round(kopf.height), Math.round(ek.height), Math.round(bk.height), Math.round(ek.right), Math.round(kopf.right)] };
  });
  const h0 = await breite();
  await p3.tap('#erf-knopf');
  await p3.waitForTimeout(400);
  const h1 = await breite();
  await p3.screenshot({ path: OUT + 'g4_handy_liste.png' });
  await p3.tap(`#karte .erf-liste button.name[data-p="${fall.p}"][data-g="${fall.gen}"]`);
  await p3.waitForTimeout(400);
  await p3.tap('#karte button[data-warum]');
  await p3.waitForTimeout(300);
  const h2 = await breite();
  await p3.evaluate(() => document.querySelector('#karte .warum').scrollIntoView({ block: 'center' }));
  await p3.screenshot({ path: OUT + 'g5_handy_karte_warum.png' });
  await p3.evaluate(() => document.querySelector('#karte .ged').scrollIntoView({ block: 'start' }));
  await p3.screenshot({ path: OUT + 'g5_handy_karte_ged.png' });
  const passt = (h) => h.seite <= h.breit && (!h.karte || h.karte[0] <= h.karte[1]) && !h.zuBreit.length;
  ok(passt(h0) && passt(h1) && passt(h2) && h0.kopf[0] <= 44 && h0.kopf[3] <= h0.kopf[4],
    `Handy 390 × 844: Seite ${h0.seite}/${h1.seite}/${h2.seite} ≤ ${h0.breit} px breit, Karte scrollWidth ≤ clientWidth (Liste ${h1.karte}, Karte ${h2.karte}), nichts ragt hinaus`
    + `${h2.zuBreit.length ? ' (' + h2.zuBreit.join(', ') + ')' : ''}; Stadtbuch-Kopf eine Zeile (${h0.kopf[0]} px, Knopf ${h0.kopf[1]} px, endet bei ${h0.kopf[3]} ≤ ${h0.kopf[4]})`);
  await ctx3.close();

  // 11. Liste beim Auffrischen (breit): Zählbeginn, kein Neusetzen ohne Änderung, Eintrag bleibt an seiner Stelle
  const { ctx: ctx4, page: p4 } = await seite({ width: 1280, height: 800 });
  const start4 = await p4.evaluate(([tag]) => { const a = __stadt, S = a.S(), st = { tag: S.tag, stunde: S.stunde };
    while (S.tag < tag || S.stunde < 19) { a.schritt(); a.nachSchritten(); } return st; }, [fall.tag]);
  await p4.click('#erf-knopf');
  await p4.waitForTimeout(300);
  const l4 = await p4.evaluate(() => { const k = document.getElementById('karte'); return { text: k.textContent.replace(/\s+/g, ' '), sh: k.scrollHeight, ch: k.clientHeight }; });
  const seitText = `Gezählt erst, seit die Stadt in diesem Fenster läuft (Tag ${start4.tag}, ${start4.stunde} Uhr)`;
  const a4 = await p4.evaluate(() => { const k = document.getElementById('karte'); k.scrollTop = Math.round((k.scrollHeight - k.clientHeight) / 2);
    const oben = k.getBoundingClientRect().top, li = [...k.querySelectorAll('li[data-nr]')].find(x => x.getBoundingClientRect().bottom > oben);
    if (!li) return null; li.__marke = 1;
    return { nr: li.dataset.nr, y: Math.round(li.getBoundingClientRect().top), scroll: k.scrollTop, zahl: document.getElementById('erf-zahl').textContent }; });
  // eine Stunde (19 → 20 Uhr; entschieden wird um 7 und 18 Uhr und nach einem Ereignis): ohne neue Meldung dasselbe Element an derselben Stelle
  const b4 = a4 && await p4.evaluate((nr) => { __stadt.schritt(); __stadt.nachSchritten(); const li = document.querySelector(`#karte li[data-nr="${nr}"]`);
    return { gleich: !!(li && li.__marke), y: li ? Math.round(li.getBoundingClientRect().top) : null, zahl: document.getElementById('erf-zahl').textContent }; }, a4.nr);
  // bis zum nächsten Morgen nach 7 Uhr: heute wird gestern, oben kommen neue dazu; der gemerkte Eintrag bleibt im Bild, wo er war
  const c4 = a4 && await p4.evaluate(([nr, tag]) => { const a = __stadt, S = a.S(); while (S.tag <= tag || S.stunde < 8) { a.schritt(); a.nachSchritten(); }
    const k = document.getElementById('karte'), li = k.querySelector(`li[data-nr="${nr}"]`);
    return { y: li ? Math.round(li.getBoundingClientRect().top) : null, gestern: [...k.querySelectorAll('h3')].some(h => /^Gestern/.test(h.textContent)), scroll: k.scrollTop, tag: S.tag }; }, [a4.nr, fall.tag]);
  await p4.locator('#karte').screenshot({ path: OUT + 'g7_liste_anker.png' });
  ok(l4.text.includes(seitText) && l4.sh > l4.ch + 100 && !!a4 && (b4.gleich || b4.zahl !== a4.zahl) && b4.y === a4.y && c4.gestern && c4.y !== null && Math.abs(c4.y - a4.y) <= 2,
    `Liste: „${seitText}“ ${l4.text.includes(seitText) ? 'steht da' : 'FEHLT'}; gescrollt (${a4 ? a4.scroll : '–'} px von ${l4.sh - l4.ch}), Eintrag ${a4 ? a4.nr : '–'} bei y ${a4 ? a4.y : '–'}; `
    + `eine Stunde später ${b4 && b4.gleich ? 'dasselbe Element' : 'neu gesetzt'} (Zahl ${a4 ? a4.zahl : '–'} → ${b4 ? b4.zahl : '–'}) bei y ${b4 ? b4.y : '–'}; Tag ${c4 ? c4.tag : '–'}, 8 Uhr, unter „Gestern“: y ${c4 ? c4.y : '–'}, Scroll ${c4 ? c4.scroll : '–'} px`);
  await ctx4.close();

  // 10. Konsole
  ok(konsole.length === 0, `Konsole ohne Fehler${konsole.length ? ': ' + konsole.slice(0, 5).join(' | ') : ''}`);
  await b.close();
  console.log(`fertig in ${Math.round((Date.now() - t0) / 1000)} s`);
})().catch(e => { console.log('Testfehler ' + (e && e.stack || e)); process.exitCode = 1; });
