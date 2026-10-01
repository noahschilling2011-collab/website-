// Haushalt (Version 9, Teil 3) im Browser: Zeile „Budget“ als Knopf (so hoch wie die anderen Zeilen, Satz der Lohnsteuer breit sichtbar und im
// Namen), echter Klick und Tastatur öffnen das Fenster „Haushalt“, Escape schließt, Fokus zurück; Inhalt wie Sim.haushaltInfo (Kasse, Rücklage,
// Satz, Vorhaben in der Rangfolge, 20 Konten mit Summen, Jahre, Programm, Annahmen, Nicht übernommen); Kasse jede Spielstunde nachgeführt;
// Stadtbuch; Hauskarte des Rathauses (Konten von gestern, Satz, Knopf ins Fenster); Fenster „Stadtregierung“ (Karte zur Lohnsteuer, R01);
// Rangfolge vom Bürgermeisteramt über die KI (Antworten hier im Test nachgebaut, nicht über den Test-Ollama) bis in den Plan; Handy 400 × 820
// (nicht breiter und nicht höher als stadt.orig.html, kein seitliches Überlaufen); Draw Calls gegen stadt.orig.html (höchstens +3); Konsole.
// Server: tests/alle.sh (PORT, Wurzel stadt/). Bilder: tests/ausgabe/bilder_befunde/haushalt_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
// ki: null = KI nicht erreichbar; sonst eine Funktion (System-Anweisung) → Antworttext (JSON), die Anfragen an Ollama beantwortet
async function seite(b, url, viewport, ki) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  await U.fassungUnter(ctx, 'v8');   // stadt.orig.html = Version 8 (Git 31ce452) per git show, Vergleichsstand wie im Bau von Version 9
  if (!ki) await ctx.route('http://localhost:11434/**', (route) => route.abort());
  else await ctx.route('http://localhost:11434/**', (route) => {
    const r = route.request(), cors = { 'Access-Control-Allow-Origin': U.HOST, 'Content-Type': 'application/json' };
    if (r.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET,POST', 'Access-Control-Allow-Headers': 'Content-Type' } });
    if (r.url().endsWith('/api/tags')) return route.fulfill({ status: 200, headers: cors, body: JSON.stringify({ models: [{ name: 'test-modell:latest', model: 'test-modell:latest', size: 1 }] }) });
    const body = JSON.parse(r.postData() || '{}'), sys = (body.messages || []).find(m => m.role === 'system') || { content: '' };
    return route.fulfill({ status: 200, headers: cors, body: JSON.stringify({ model: body.model, message: { role: 'assistant', content: ki(sys.content) }, done: true }) });
  });
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED|GPU stall|GroupMarkerNotSet|software WebGL/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
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
const fertig = (ev) => ev(() => Promise.all([...document.querySelectorAll('dialog[open]')].flatMap(d => d.getAnimations()).map(a => a.finished.catch(() => 0))));
const blickAufs = (ev, r) => ev((r) => { const { G } = __stadt, S = __stadt.S(), x = (r[0] + r[2]) / 2 - S.mitte + 0.5, z = (r[1] + r[3]) / 2 - S.mitte + 0.5;
  G.controls.target.set(x, 0, z); G.camera.position.set(x + 1.5, 7, z + 6); G.controls.update(); G.camera.updateMatrixWorld(); }, r);
const aufSchirm = (ev, x, h, z) => ev(([x, h, z]) => { const { G } = __stadt, S = __stadt.S();
  const v = new G.THREE.Vector3(x - S.mitte + 0.5, h, z - S.mitte + 0.5).project(G.camera), c = G.renderer.domElement.getBoundingClientRect();
  return { x: c.left + (v.x + 1) / 2 * c.width, y: c.top + (1 - v.y) / 2 * c.height }; }, [x, h, z]);
const fensterText = (ev) => ev(() => ({ offen: document.getElementById('haushalt-dialog').open, text: document.getElementById('haushalt-inhalt').innerText,
  fokus: document.activeElement ? document.activeElement.id || document.activeElement.tagName : '' }));
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  // 1. Teststadt Seed 2, Tag 250 (breit)
  const A = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=250&neu');
  const k = await A.ev(() => { const S = __stadt.S(), kn = document.getElementById('haushalt-knopf'), zeilen = [...document.querySelectorAll('#kennzahlen dl > div')];
    return { satz: S.haushalt.satz, text: kn.innerText.replace(/\s+/g, ' ').trim(), label: kn.getAttribute('aria-label'), inKennzahlen: !!kn.closest('#kennzahlen'),
      hoehen: zeilen.map(z => Math.round(z.getBoundingClientRect().height)), budget: document.getElementById('k-budget').textContent, sim: Math.round(S.budget).toLocaleString('de-DE') }; });
  ok(k.inKennzahlen && k.text === `Budget · Steuer ${k.satz} % ›` && k.label === `Budget: Haushalt der Stadt öffnen, Lohnsteuer ${k.satz} %` && new Set(k.hoehen).size === 1 && k.budget === k.sim,
    `Zeile „${k.text}“ ist ein Knopf (Name „${k.label}“), Budget ${k.budget}; alle ${k.hoehen.length} Zeilen gleich hoch (${[...new Set(k.hoehen)].join('/')} px)`);
  // Echter Klick auf die Zahl der Zeile (die ganze Zeile nimmt den Klick)
  const dd = await A.page.locator('#k-budget').boundingBox();
  await A.page.mouse.click(dd.x + dd.width / 2, dd.y + dd.height / 2); await A.page.waitForTimeout(400);
  let f = await fensterText(A.ev);
  ok(f.offen, 'Klick auf die Zahl „Budget“ öffnet das Fenster „Haushalt“');
  const i = await A.ev(() => { const i = __stadt.Sim.haushaltInfo(__stadt.S()); return { plan: i.plan, satz: i.satz, budget: i.budget, jahre: i.jahre.length, vorjahr: i.vorjahr, summe: i.summe, vorhaben: i.vorhaben }; });
  const tz = (v) => `${Math.round(v).toLocaleString('de-DE')} Taler`;
  const inhalt = await A.ev(() => { const box = document.getElementById('haushalt-inhalt'), tabs = [...box.querySelectorAll('table.hh-tab')];
    // Teil 5: die Computer der Schulen stehen als Bedarf vor der Liste der Vorhaben (eigene Karte, nicht in der Rangfolge)
    const bedarf = [...box.querySelectorAll(':scope > div > section.reg-karte h4, :scope section.reg-karte h4')].map(h => h.textContent).filter(t => /vor allen Vorhaben$/.test(t));
    return { bedarf, rang: [...box.querySelectorAll('.hh-rang > li h4')].map(h => h.textContent), konten: tabs[0] ? [...tabs[0].querySelectorAll('tbody tr')].map(r => [...r.children].map(c => c.textContent)) : [],
      jahre: tabs[1] ? tabs[1].querySelectorAll('tbody tr').length : 0, karten: [...box.querySelectorAll(':scope > section.reg-karte h4')].map(h => h.textContent),
      auf: [...box.querySelectorAll('details.reg-auf summary')].map(s => s.textContent), kasse: [...box.querySelectorAll('dl.zahlen dd')].map(d => d.textContent) }; });
  const namen = i.plan.rang.map(id => i.vorhaben.find(v => v.id === id).name);
  const kontoZeile = (n) => inhalt.konten.find(z => z[0] === n) || [];
  const vj = (k) => (i.vorjahr ? Math.round(i.vorjahr[k]).toLocaleString('de-DE') : '–'), vjA = (k) => (i.vorjahr ? Math.round(-i.vorjahr[k] + 0).toLocaleString('de-DE') : '–');
  ok(/^Haushaltsjahr 25 · Tag 250 bis 259/.test(f.text) && inhalt.kasse[0] === tz(i.budget) && inhalt.kasse[1] === tz(i.plan.ruecklage) && inhalt.kasse[5] === `${i.satz}\u00a0%` + (i.satz < 10 ? ' (Start 10\u00a0%)' : '')
    && /nicht verplant/i.test(f.text), `Kopf und „Heute“: Kasse ${inhalt.kasse[0]}, Rücklage ${inhalt.kasse[1]}, Lohnsteuer „${inhalt.kasse[5]}“ (wie Sim.haushaltInfo)`);
  ok(inhalt.rang.length === 3 && inhalt.rang.join('|') === namen.join('|') && inhalt.bedarf.length === 1 && /^Computer für die Schulen/.test(inhalt.bedarf[0]),
    `Vorhaben in der Rangfolge des Jahres (${i.plan.von}): ${inhalt.rang.join(', ')}; davor als Bedarf „${inhalt.bedarf[0] || '–'}“ (Teil 5)`);
  ok(inhalt.konten.length === 23 && kontoZeile('Lohnsteuer')[1] === vj(0) && kontoZeile('Mieten')[1] === vj(1) && kontoZeile('Rathaus: Löhne und laufende Kosten')[1] === vjA(9)
    && kontoZeile('Computer für die Schulen')[1] === vjA(19) && ['Einnahmen', 'Ausgaben', 'Überschuss'].every(n => kontoZeile(n).length === 3),
    `Konten: ${inhalt.konten.length} Zeilen (20 Konten und 3 Summen), Vorjahr wie Sim: Lohnsteuer ${kontoZeile('Lohnsteuer')[1]}, Rathaus ${kontoZeile('Rathaus: Löhne und laufende Kosten')[1]}, Computer ${kontoZeile('Computer für die Schulen')[1]}`);
  ok(inhalt.jahre === Math.min(10, i.jahre) && inhalt.karten.length === 6 && inhalt.karten.some(t => /Dann die Lohnsteuer senken/.test(t)) && inhalt.karten.some(t => /Spannung zu S\. 37/.test(t))
    && inhalt.auf.join('|') === 'Annahmen der Stadt (8)|Nicht übernommen (8)' && !/NaN|undefined|null/.test(f.text) && /Wofür das Geld ging/.test(f.text),
    `${inhalt.jahre} Jahre in der Tabelle, ${inhalt.karten.length} Karten zum Programm (${inhalt.karten.map(t => t.replace(/(Auslegung|wirkt|galt schon)$/, '')).join('; ')}), ${inhalt.auf.join(', ')}; kein NaN`);
  await fertig(A.ev); await A.page.screenshot({ path: BILD + 'haushalt_fenster_breit.png' });
  // Kasse jede Spielstunde nachgeführt, solange das Fenster offen ist
  await A.ev(() => { __stadt.schritt(); __stadt.schritt(); __stadt.nachSchritten(); });
  await A.page.waitForTimeout(200);
  const live = await A.ev(() => ({ dd: document.querySelector('#haushalt-inhalt dl.zahlen dd').textContent, b: Math.round(__stadt.S().budget).toLocaleString('de-DE') + ' Taler' }));
  ok(live.dd === live.b, `nach zwei Spielstunden: Kasse im Fenster ${live.dd} = Budget ${live.b}`);
  await A.page.keyboard.press('Escape'); await A.page.waitForTimeout(300);
  f = await fensterText(A.ev);
  ok(!f.offen, 'Escape schließt das Fenster');
  // Tastatur: Fokus auf den Knopf, Enter öffnet, Escape schließt, der Fokus steht wieder auf dem Knopf (mit Ring)
  await A.ev(() => document.getElementById('haushalt-knopf').focus());
  await A.page.keyboard.press('Enter'); await A.page.waitForTimeout(400);
  const t1 = await fensterText(A.ev);
  await A.page.keyboard.press('Escape'); await A.page.waitForTimeout(400);
  const t2 = await A.ev(() => { const a = document.activeElement, cs = a && getComputedStyle(a);
    return { offen: document.getElementById('haushalt-dialog').open, fokus: a && a.id, ring: !!a && a.matches(':focus-visible') && cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) >= 2 }; });
  ok(t1.offen && t1.fokus === 'haushalt-titel' && !t2.offen && t2.fokus === 'haushalt-knopf' && t2.ring, `Tastatur: Enter öffnet (Fokus auf der Überschrift), Escape schließt, Fokus zurück auf dem Knopf mit Ring (${JSON.stringify(t2)})`);
  // Stadtbuch
  const zeilen = await A.ev(() => [...document.querySelectorAll('#buch-liste li')].filter(li => li.querySelector('use') && li.querySelector('use').getAttribute('href') === '#s-muenzen').map(li => li.innerText.replace(/\s+/g, ' ')));
  ok(zeilen.length >= 1 && zeilen.every(z => /Haushaltsjahr \d+: /.test(z) && /Rücklage für Jahr \d+/.test(z) && /Lohnsteuer (bleibt|sinkt|steigt)/.test(z)),
    `Stadtbuch: ${zeilen.length} Zeilen zum Haushalt mit Münzen, zuletzt „${(zeilen[0] || '').slice(0, 160)}…“`);
  // Hauskarte des Rathauses: Konten von gestern, Satz, Knopf ins Fenster
  const r = await A.ev(() => { const S = __stadt.S(); return S.erweiterung.gelaende.find(q => q[4] === S.rathaus.b); });
  await blickAufs(A.ev, r); await A.page.waitForTimeout(500);
  const mi = await A.ev(() => __stadt.S().mitte), gr = [r[0], r[1], r[2], r[3]];
  const p = await aufSchirm(A.ev, (gr[0] + gr[2]) / 2 + 0.3, 0.02, gr[3] - 0.2);
  await A.page.mouse.click(p.x, p.y); await A.page.waitForTimeout(500);
  const hk = await A.ev(() => ({ titel: (document.querySelector('#karte h2') || {}).textContent || '', text: document.getElementById('karte-inhalt').innerText, knopf: !!document.querySelector('#karte-inhalt button[data-haushalt]'),
    kurz: __stadt.Sim.haushaltKurz(__stadt.S()) }));
  ok(/^Rathaus /.test(hk.titel) && hk.knopf && hk.kurz.fenster && new RegExp(`Lohnsteuer\\s+${hk.kurz.satz} %`).test(hk.text) && hk.kurz.zeilen.every(([t]) => hk.text.includes(t + ', gestern'))
    && /Budget gestern insgesamt/.test(hk.text), `Hauskarte „${hk.titel}“: ${hk.kurz.zeilen.length} Zeilen von gestern (${hk.kurz.zeilen.map(z => z[0]).join('; ')}), Lohnsteuer ${hk.kurz.satz} %, Knopf „Fenster „Haushalt“ ›“`);
  await A.page.screenshot({ path: BILD + 'haushalt_rathauskarte.png' });
  await A.page.click('#karte-inhalt button[data-haushalt]'); await A.page.waitForTimeout(400);
  f = await fensterText(A.ev);
  ok(f.offen && /^Haushaltsjahr/.test(f.text), 'Knopf in der Hauskarte öffnet das Fenster „Haushalt“');
  await A.zu(); void mi;
  // Fenster „Stadtregierung“: Karte zur Lohnsteuer mit dem heutigen Satz; R01; „Die Steuersätze werden wir senken“ nicht mehr unter „Keine Zahl“
  await A.page.click('#regierung-knopf'); await A.page.waitForTimeout(400);
  const rg = await A.ev(() => { const box = document.getElementById('regierung-inhalt'), karten = [...box.querySelectorAll('.reg-karte')];
    const kk = karten.find(x => /Lohnsteuer sinkt, wenn Geld übrig bleibt/.test(x.querySelector('h4').textContent)), r01 = karten.find(x => /Grundfreibetrag/.test(x.querySelector('h4').textContent));
    const keine = [...box.querySelectorAll('details.reg-auf')].find(d => /Keine Zahl/.test(d.querySelector('summary').textContent));
    return { karte: kk ? kk.innerText : '', live: kk ? kk.querySelector('p.reg-live').textContent : '', r01: r01 ? r01.innerText : '', r01live: r01 ? r01.querySelector('p.reg-live').textContent : '',
      keine: keine ? keine.innerText : '' }; });
  ok(/S\. 56/.test(rg.karte) && /S\. 54/.test(rg.karte) && new RegExp(`^Heute ${k.satz} %`).test(rg.live) && /am Anfang wie bisher 10 %/.test(rg.r01) && new RegExp(`^Heute ${k.satz} % über dem Freibetrag`).test(rg.r01live)
    && !/Die Steuersätze werden wir senken/.test(rg.keine), `Fenster „Stadtregierung“: Karte „Lohnsteuer sinkt …“ („${rg.live.slice(0, 100)}…“), R01 „${rg.r01live.slice(0, 60)}…“`);
  await A.zu();
  // Draw Calls um 11 Uhr gegen stadt.orig.html (derselbe Seed und Tag; der Haushalt zeichnet nichts, die Stadt ist aber eine andere)
  const dc = async (X) => { await X.ev(() => { const a = __stadt, S = a.S(); let n = 0; while (S.stunde !== 11 && n++ < 30) a.schritt(); a.nachSchritten(); a.G.controls.target.set(0, 0, 0); a.G.camera.position.set(8, 30, 34); a.G.controls.update(); });
    await X.page.waitForTimeout(500); return X.ev(() => __stadt.G.render().calls); };
  const cNeu = await dc(A);
  console.log('Konsole (breit):', A.log.length ? '\n  ' + A.log.join('\n  ') : 'leer');
  if (A.log.length) process.exitCode = 1;
  await A.ctx.close();
  const O = await seite(b, U.HOST + '/stadt.orig.html?debug&seed=2&tage=250&neu');
  const cOrig = await dc(O);
  await O.ctx.close();
  ok(cNeu <= cOrig + 3, `Draw Calls Tag 250, 11 Uhr: ${cNeu} (stadt.orig.html ${cOrig}, höchstens +3)`);

  // 2. Rangfolge vom Bürgermeisteramt über die KI (nachgebaute Antworten): Anfrage am letzten Tag des Jahres 0, gilt im Plan fürs Jahr 1
  const RANG = ['parks', 'rathaus', 'wohnungen'];   // Teil 5: drei Vorhaben (die Computer der Schulen sind Bedarf, nicht in der Rangfolge)
  const K = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=8&neu', null, (sys) => {
    if (/Reihenfolge die Stadt ihre Vorhaben angeht/.test(sys)) return JSON.stringify({ rangfolge: RANG, gedanke: 'Zuerst Parks für alle, dann das Rathaus.' });
    const erlaubt = [...sys.matchAll(/^- ([a-z_]+): /gm)].map(m => m[1]);
    return JSON.stringify({ aktion: erlaubt[0] || 'freinehmen', gedanke: 'Ich mache weiter wie bisher.', neues_ziel: null });
  });
  await K.page.waitForFunction(() => __stadt.ki.status !== 'suche', null, { timeout: 20000 });
  await K.ev(() => __stadt.setzeTempo(1));
  await K.page.waitForFunction(() => __stadt.S().ki.an, null, { timeout: 20000 });
  await K.ev(() => { __stadt.setzeTempo(0); const a = __stadt, S = a.S(); let n = 0; while (!(S.tag === 9 && S.stunde === 8) && n++ < 100) a.schritt(); a.nachSchritten(); });
  const anfrage = await K.ev(() => __stadt.Sim.bmAnfrage(__stadt.S()));
  await K.ev(() => __stadt.setzeTempo(1));
  await K.page.waitForFunction(() => { const B = __stadt.S().buergermeister; return B.rangfolge && B.rangfolge.jahr === 1; }, null, { timeout: 30000 }).catch(() => {});
  await K.ev(() => { __stadt.setzeTempo(0); const a = __stadt, S = a.S(); let n = 0; while (S.tag < 10 && n++ < 60) a.schritt(); a.nachSchritten(); });
  const kr = await K.ev(() => { const S = __stadt.S(), B = S.buergermeister, tb = (S.ki.tagebuch[B.p + '/' + B.gen] || []).filter(e => e.art === 'amt');
    return { rangfolge: B.rangfolge, plan: S.haushalt.plan.rang, von: S.haushalt.plan.von, tb: tb.map(e => e.text), stat: __stadt.ki.stat, zeile: __stadt.Sim.klartext((S.buch.filter(e => e.art === 'haushalt').pop() || { text: '' }).text) }; });
  ok(anfrage && anfrage.vorhaben.length === 3 && kr.rangfolge && kr.rangfolge.von === 'ki' && kr.rangfolge.liste.join() === RANG.join() && kr.plan.join() === RANG.join() && kr.von === 'ki'
    && kr.tb.length === 1 && /Bürgermeisteramt festgelegt/.test(kr.zeile),
    `KI: Anfrage an Tag 9 mit ${anfrage ? anfrage.vorhaben.length : 0} Vorhaben, Antwort geprüft und übernommen (${kr.rangfolge ? kr.rangfolge.von : '–'}); Plan fürs Jahr 1: ${kr.plan.join(', ')}; Tagebuch „${kr.tb[0] || '–'}“`);
  await K.page.click('#haushalt-knopf'); await K.page.waitForTimeout(400);
  const kf = await fensterText(K.ev);
  ok(/Vorhaben im Jahr 1: Rangfolge vom Bürgermeisteramt/i.test(kf.text) && kf.text.indexOf('Parks in Wohnnähe') < kf.text.indexOf('Wohnungen auf Vorrat'), 'Fenster: „Rangfolge vom Bürgermeisteramt“, Parks vor Wohnungen');
  await fertig(K.ev); await K.page.screenshot({ path: BILD + 'haushalt_rangfolge_ki.png' });
  console.log('Konsole (KI):', K.log.length ? '\n  ' + K.log.join('\n  ') : 'leer');
  if (K.log.length) process.exitCode = 1;
  await K.ctx.close();

  // 3. Handy 400 × 820: Zahlen so breit und so hoch wie stadt.orig.html, Fenster ohne seitliches Überlaufen, Tipp auf die Zeile öffnet es
  const masse = async (datei) => { const X = await seite(b, `${U.HOST}/${datei}?debug&seed=2&tage=250&neu`, { width: 400, height: 820 });
    const m = await X.ev(() => { const r = document.getElementById('kennzahlen').getBoundingClientRect(); return { rechts: Math.round(r.right * 10) / 10, unten: Math.round(r.bottom * 10) / 10 }; });
    return { X, m }; };
  const alt = await masse('stadt.orig.html'); await alt.X.ctx.close();
  const H = await masse('stadt.html');
  const zeile = await H.X.page.locator('#k-budget').boundingBox();
  await H.X.page.mouse.click(zeile.x + 2, zeile.y + zeile.height / 2); await H.X.page.waitForTimeout(400);
  const hf = await H.X.ev(() => { const d = document.getElementById('haushalt-dialog'); return { offen: d.open, doc: document.documentElement.scrollWidth, dlg: d.scrollWidth, dlgw: d.clientWidth,
    tab: Math.max(...[...d.querySelectorAll('table')].map(t => t.getBoundingClientRect().right)) }; });
  ok(H.m.rechts <= alt.m.rechts + 0.5 && H.m.unten <= alt.m.unten + 0.5, `Handy: Zahlen bis ${H.m.rechts} px breit und ${H.m.unten} px hoch (stadt.orig.html ${alt.m.rechts} / ${alt.m.unten})`);
  ok(hf.offen && hf.doc <= 400 && hf.dlg <= hf.dlgw && hf.tab <= 400, `Handy: Tipp auf die Zeile öffnet das Fenster; kein seitliches Überlaufen (Seite ${hf.doc}, Fenster ${hf.dlg}/${hf.dlgw}, Tabellen bis ${Math.round(hf.tab)} px)`);
  await fertig(H.X.ev); await H.X.page.screenshot({ path: BILD + 'haushalt_handy.png' });
  await H.X.ev(() => { const d = document.getElementById('haushalt-dialog'); d.scrollTop = d.scrollHeight * 0.45; });
  await H.X.page.screenshot({ path: BILD + 'haushalt_handy_mitte.png' });
  console.log('Konsole (Handy):', H.X.log.length ? '\n  ' + H.X.log.join('\n  ') : 'leer');
  if (H.X.log.length) process.exitCode = 1;
  await H.X.ctx.close();
  await b.close();
})();
