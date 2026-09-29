// Wachstum, Tempo und KI (Version 9, Teil 4) im Browser. Server: tests/alle.sh (PORT, Wurzel stadt/).
// Ollama wird NICHT über Port 11434 angesprochen: Playwright beantwortet http://localhost:11434 im Browser (ctx.route) im Format der Ollama-Doku
// (/api/tags, /api/chat), mit einstellbarer Verzögerung je Antwort.
//   node tests/wachstum.cjs [teil …]   Teile: tempo, ki, schalter, regierung, leistung (ohne Angabe: alle)
// tempo: fünf Knöpfe (Pause, 1×, 5×, 20×, 100×), aria-pressed, Leertaste, gespeichertes Tempo ohne Knopf → 1×, alle Größen ohne Überlappung
// und ohne seitliches Scrollen (acht Größen), „Pause“ am Handy nur als Symbol (Name bleibt). ki: KI bei 20× und 100× (Status ohne „pausiert“, Frist in
// Spielstunden aus Tempo und Warteschlange, Entscheidungen angewandt), langsame Antworten → „zu spät“, die Stadt läuft weiter; Einstellungen
// und Debug-Ecke zeigen es. schalter: „Wachstum: normal / schnell“ (Einstellungen, aria-pressed, Stadtbuch, gespeichert, Text „keine Regel der
// Stadtregierung“). regierung: Karte R10 im Fenster „Stadtregierung“ (S. 109, Anlauf, Schalter, Live-Zeile). leistung: 20× gegen 100×
// (Teststadt Tag 400 und große Stadt Tag 750, SwiftShader, nur zum Vergleich): Bilder je Sekunde, Spielstunden je Sekunde, Kosten je
// Spielstunde, Autos, die springen statt zu fahren. Bilder: tests/ausgabe/bilder_befunde/wachstum_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const teile = process.argv.slice(2);
const mit = (t) => !teile.length || teile.includes(t);
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
const warte = (ms) => new Promise(r => setTimeout(r, ms));

const mock = { verzoegerung: 300, n: 0, chat: [] };
const erlaubtAus = (sys) => [...sys.matchAll(/^- ([a-z_]+): /gm)].map(m => m[1]);
function antwort(sys) {
  mock.n++;
  if (sys.includes('Noah spricht mit dir')) return JSON.stringify({ antwort: 'Danke der Nachfrage.', neues_ziel: null });
  if (sys.includes('Tagebucheintrag')) return JSON.stringify({ eintrag: 'Nicht viel passiert.' });
  if (sys.includes('Stück Code')) return JSON.stringify({ titel: 'Test', sprache: 'JavaScript', code: 'let a = 1;', gedanke: 'Passt.' });
  if (sys.includes('Vorhaben')) return JSON.stringify({ rangfolge: ['wohnungen', 'parks', 'rathaus'], gedanke: 'Erst Wohnungen.' });   // Teil 5: drei Vorhaben
  const erlaubt = erlaubtAus(sys);
  const aktion = erlaubt.includes('freunde_treffen') ? 'freunde_treffen' : erlaubt[mock.n % Math.max(1, erlaubt.length)];
  return JSON.stringify({ aktion, gedanke: `Ich nehme ${aktion}.`, neues_ziel: null });
}
async function seite(b, url, viewport, mitKi = true) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  if (!mitKi) await ctx.route('http://localhost:11434/**', (route) => route.abort());
  else await ctx.route('http://localhost:11434/**', async (route) => {
    const r = route.request(), kopf = { 'Access-Control-Allow-Origin': U.HOST, 'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Content-Type': 'application/json' };
    if (r.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: kopf, body: '' });
    if (r.url().endsWith('/api/tags')) return route.fulfill({ status: 200, headers: kopf, body: JSON.stringify({ models: [{ name: 'test-modell:latest' }] }) });
    if (r.url().endsWith('/api/chat')) {
      const body = JSON.parse(r.postData() || '{}'), sys = (body.messages || []).find(m => m.role === 'system') || { content: '' };
      mock.chat.push({ zeit: Date.now(), code: sys.content.includes('Stück Code') });
      await warte(mock.verzoegerung);
      try { return await route.fulfill({ status: 200, headers: kopf, body: JSON.stringify({ model: body.model, message: { role: 'assistant', content: antwort(sys.content) }, done: true }) }); }
      catch (e) { return; }                                  // die Seite hat abgebrochen (AbortController)
    }
    return route.fulfill({ status: 404, headers: kopf, body: '{}' });
  });
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED|GPU stall|GroupMarkerNotSet|software WebGL|11434/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  await page.goto(url, { timeout: 900000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 900000 });
  const ev = (f, a) => page.evaluate(f, a);
  // Nachfolge-Dialoge (stirbt eine Hauptfigur) und offene Dialoge schließen
  const zu = async () => { for (let i = 0; i < 30; i++) {
    const o = await ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
      for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
    await page.waitForTimeout(100); if (!o) break; } };
  await zu();
  return { ctx, page, log, ev, zu };
}

(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  if (mit('tempo')) {
    console.log('== Tempo-Leiste');
    const A = await seite(b, `${U.HOST}/stadt.html?debug&seed=2&tage=20&neu`, null, false);
    const kn = await A.ev(() => [...document.querySelectorAll('#tempo button')].map(k => `${k.dataset.tempo}:${k.textContent.trim()}:${k.getAttribute('aria-pressed')}`));
    ok(kn.join() === '0:Pause:false,1:1×:true,5:5×:false,20:20×:false,100:100×:false', 'Knöpfe: ' + kn.join(' | '));
    await A.page.click('#tempo button[data-tempo="100"]');
    const t1 = await A.ev(() => ({ gedrueckt: [...document.querySelectorAll('#tempo button[aria-pressed="true"]')].map(k => k.dataset.tempo).join(), titel: document.querySelector('#tempo button[data-tempo="100"]').title }));
    await A.page.keyboard.press('Space');                   // der Knopf hat nach dem Mausklick den Fokus: Leertaste = Pause (wie die Hilfe sagt)
    const t2 = await A.ev(() => [...document.querySelectorAll('#tempo button[aria-pressed="true"]')].map(k => k.dataset.tempo).join());
    await A.page.keyboard.press('Space');
    const t3 = await A.ev(() => [...document.querySelectorAll('#tempo button[aria-pressed="true"]')].map(k => k.dataset.tempo).join());
    ok(t1.gedrueckt === '100' && t1.titel === 'Eine Spielstunde in 0,6 Sekunden' && t2 === '0' && t3 === '100', `100× gedrückt („${t1.titel}“), Leertaste: Pause (${t2}), weiter (${t3})`);
    // Gespeichertes Tempo, das es nicht als Knopf gibt (etwa 50 aus einem Entwurf): 1×
    await A.ev(() => { __stadt.setzeTempo(50); });
    const t4 = await A.ev(() => [...document.querySelectorAll('#tempo button[aria-pressed="true"]')].map(k => k.dataset.tempo).join());
    await A.ev(() => { __stadt.setzeTempo(100); __stadt.speichern(); });
    const roh = await A.ev(() => localStorage.getItem('stadt-save-v1'));
    const d = JSON.parse(roh); d.tempo = 50; d.zuletztGelaufen = Date.now();
    await A.page.goto(U.LEER);    // erst weg von der Stadt (sie speichert beim Verlassen), dann den Stand ändern
    await A.ev((t) => localStorage.setItem('stadt-save-v1', t), JSON.stringify(d));
    await A.page.goto(`${U.HOST}/stadt.html?debug`);
    await A.page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 60000 });
    const t5 = await A.ev(() => [...document.querySelectorAll('#tempo button[aria-pressed="true"]')].map(k => k.dataset.tempo).join());
    ok(t4 === '1' && t5 === '1', `Tempo ohne Knopf → 1× (gesetzt: ${t4}, aus dem Spielstand geladen: ${t5})`);
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
    for (const [w, h] of [[1280, 800], [1000, 700], [400, 820], [390, 844], [360, 740], [680, 345], [568, 320], [844, 390]]) {
      const B = await seite(b, `${U.HOST}/stadt.html?seed=2&neu&debug`, { width: w, height: h }, false);
      await B.ev(() => __stadt.setzeTempo(100));
      await warte(800);
      const r = await B.ev(() => {
        const rect = (e) => { if (!e || e.hidden || getComputedStyle(e).display === 'none' || getComputedStyle(e).visibility === 'hidden') return null; const q = e.getBoundingClientRect(); return { l: q.left, r: q.right, t: q.top, b: q.bottom }; };
        const t = rect(document.getElementById('tempo'));
        const andere = { rechts: 'rechts', hilfe: 'hilfe-knopf', einst: 'einst-knopf', kennzahlen: 'kennzahlen', stadtbuch: 'stadtbuch', haupt: 'haupt', hinweis: 'erster-hinweis',
          debug: 'debug', 'debug-knoepfe': 'debug-knoepfe' };   // Debug-Ecke (?debug): seit 100× ist das Tempo breiter
        const ueber = [], luft = [];
        for (const [n, id] of Object.entries(andere)) { const q = rect(document.getElementById(id)); if (!q || !t) continue;
          if (q.l < t.r - 0.5 && q.r > t.l + 0.5 && q.t < t.b - 0.5 && q.b > t.t + 0.5) ueber.push(n);
          else if (q.t < t.b && q.b > t.t) luft.push(`${n} ${Math.round(Math.max(q.l - t.r, t.l - q.r))} px`); }
        const pause = document.querySelector('#tempo button[data-tempo="0"]'), wort = pause.querySelector('.tempo-wort');
        const kn = [...document.querySelectorAll('#tempo button')].map(k => Math.round(k.getBoundingClientRect().width));
        const d = rect(document.getElementById('debug')), dk = rect(document.getElementById('debug-knoepfe'));
        const dbgUeber = !!(d && dk && dk.l < d.r && dk.r > d.l && dk.t < d.b - 0.5 && dk.b > d.t + 0.5);
        return { t, ueber, luft, kn, dbgUeber, vw: innerWidth, vh: innerHeight, sw: document.documentElement.scrollWidth, wortBreite: Math.round(wort.getBoundingClientRect().width), name: pause.textContent.trim() };
      });
      const drin = r.t.l >= 0 && r.t.r <= r.vw && r.t.b <= r.vh;
      const schmal = w <= 720 || h <= 500;
      ok(drin && !r.ueber.length && !r.dbgUeber && r.sw <= r.vw && r.name === 'Pause' && (schmal ? r.wortBreite <= 1 : r.wortBreite > 20),
        `${w}×${h}: Tempo ${Math.round(r.t.l)}–${Math.round(r.t.r)} px (Knöpfe ${r.kn.join('/')}), überlappt ${r.ueber.join(', ') || 'nichts'}; Luft daneben: ${r.luft.join(', ') || '–'}; `
        + `„Pause“ ${schmal ? 'nur als Symbol' : 'mit Wort'} (Name „${r.name}“); Debug-Knöpfe über der Ecke: ${r.dbgUeber ? 'JA' : 'nein'}; Seite ${r.sw} px breit`);
      if (w === 400 || w === 568 || w === 1280) await B.page.screenshot({ path: BILD + `wachstum_tempo_${w}x${h}.png` });
      if (B.log.length) ok(false, 'Konsole: ' + B.log.join(' | '));
      await B.ctx.close();
    }
  }

  if (mit('ki')) {
    console.log('== KI bei 20× und 100×');
    mock.verzoegerung = 300;
    const A = await seite(b, `${U.HOST}/stadt.html?debug&seed=2&tage=40&neu`);
    const { ev, page } = A;
    await page.waitForFunction(() => __stadt.ki.status === 'bereit', null, { timeout: 20000 });
    const n = await ev(() => __stadt.Sim.hauptListe(__stadt.S()).length);
    for (const [tempo, soll] of [[20, 7], [100, 34]]) {
      await ev((t) => __stadt.setzeTempo(t), tempo);
      await page.waitForFunction((s) => __stadt.S().ki.fristStunden === s, soll, { timeout: 15000 }).catch(() => {});
      const a0 = await ev(() => __stadt.S().ki.angewandt), t0 = await ev(() => __stadt.S().tag * 24 + __stadt.S().stunde);
      await page.waitForFunction((a0) => __stadt.S().ki.angewandt >= a0 + 3, a0, { timeout: 180000 }).catch(() => {});
      const k = await ev(() => ({ angewandt: __stadt.S().ki.angewandt, abgelaufen: __stadt.S().ki.abgelaufen, frist: __stadt.S().ki.fristStunden, an: __stadt.S().ki.an,
        status: document.getElementById('ki-status').textContent, titel: document.getElementById('ki-status').title, t: __stadt.S().tag * 24 + __stadt.S().stunde,
        gedanken: __stadt.Sim.hauptListe(__stadt.S()).map(h => __stadt.Sim.personInfo(__stadt.S(), h.id, h.gen)).filter(i => i && i.tagebuch.some(e => e.art === 'gedanke')).length }));
      ok(k.an && k.frist === soll && k.status === 'KI: test-modell:latest' && !/pausiert/.test(k.status + k.titel) && k.angewandt >= a0 + 3 && k.t > t0 && k.gedanken > 0,
        `${tempo}×: KI an, Status „${k.status}“, Frist ${k.frist} Spielstunden (${n} Hauptfiguren samt Bürgermeister), ${k.angewandt - a0} KI-Entscheidungen angewandt, `
        + `${k.gedanken} Tagebücher mit Gedanken, ${k.abgelaufen} zu spät insgesamt, ${k.t - t0} Spielstunden vergangen`);
      if (tempo === 100) await page.screenshot({ path: BILD + 'wachstum_ki_100x.png' });
    }
    // Code-Stücke bei 100×, aber nie, solange eine Anfrage wartet (Befund 3): Beim Start jedes Code-Aufrufs (fetch) ist die Warteschlange leer.
    // Eine Hauptfigur, die in einer Tech-Firma arbeitet, dazu (Tag 40 gibt es noch keine: vorher 110 Tage im Hintergrund weiterrechnen)
    const tech = await ev(() => { const a = __stadt, S = a.S(); a.setzeTempo(0);
      a.Sim.kiSchalten(S, false);                           // die Tage im Hintergrund ohne Anfragen (simTakt schaltet danach wieder ein)
      let p = -1;
      for (let d = 0; d < 110 && p < 0; d++) { const z = S.tag + 1; while (S.tag < z) a.schritt();
        for (let q = 0; q < S.pMax && p < 0; q++) if (S.p.lebt[q] && S.p.arbeit[q] >= 0 && a.Sim.techFirmaVon(S, q) === S.p.arbeit[q] && !a.Sim.istHaupt(S, q)) p = q; }
      a.nachSchritten();
      if (p < 0) return null;
      a.Sim.hauptSetzen(S, p, S.p.gen[p], true, 99);
      const roh = globalThis.fetch; globalThis.__codeStart = [];
      globalThis.fetch = function (url, o) { if (o && typeof o.body === 'string' && o.body.includes('Stück Code')) globalThis.__codeStart.push({ offen: S.ki.anfragen.length + (S.buergermeister.anfrage ? 1 : 0), stunde: S.stunde }); return roh.apply(this, arguments); };
      a.setzeTempo(100); return { p, tag: S.tag }; });
    if (tech) {
      await page.waitForFunction(() => globalThis.__codeStart.length >= 2, null, { timeout: 120000 }).catch(() => {});
      const cs = await ev(() => globalThis.__codeStart);
      ok(cs.length >= 1 && cs.every(c => c.offen === 0 && c.stunde >= 9 && c.stunde <= 16), `100×: ${cs.length} Code-Aufrufe (Hauptfigur in einer Tech-Firma ab Tag ${tech.tag}), jeder mit leerer Warteschlange begonnen, zwischen 9 und 16 Uhr`);
    } else ok(false, '100×: keine Hauptfigur in einer Tech-Firma gefunden');
    // Langsame Antworten (25 s, länger als die Frist bei 100×: höchstens 36 Spielstunden = 21,6 s): Anfragen laufen ab („zu spät“), die Stadt läuft weiter.
    // Die Frist folgt der Warteschlange: Hauptfiguren × mittlere Antwortzeit × 1,2, mindestens 20 s, in Spielstunden 2 bis 36
    mock.verzoegerung = 25000;
    const z0 = await ev(() => ({ ab: __stadt.S().ki.abgelaufen, t: __stadt.S().tag * 24 + __stadt.S().stunde, spaet: __stadt.ki.stat.zuSpaet, ng: __stadt.ki.stat.nichtGesendet }));
    await page.waitForFunction((z0) => __stadt.S().ki.abgelaufen > z0.ab + 2, z0, { timeout: 240000 }).catch(() => {});
    await warte(30000);
    const z1 = await ev(() => ({ ab: __stadt.S().ki.abgelaufen, t: __stadt.S().tag * 24 + __stadt.S().stunde, spaet: __stadt.ki.stat.zuSpaet, ng: __stadt.ki.stat.nichtGesendet,
      frist: __stadt.S().ki.fristStunden, mittel: __stadt.ki.messung.ms / Math.max(1, __stadt.ki.messung.n), n: __stadt.Sim.hauptListe(__stadt.S()).length }));
    const fristSoll = Math.min(36, Math.max(2, Math.ceil(Math.max(20, z1.n * z1.mittel / 1000 * 1.2) * 100 / 60)));
    ok(z1.ab > z0.ab + 2 && z1.t - z0.t >= 36 && z1.frist === fristSoll && z1.spaet > z0.spaet,
      `100×, Antwort nach 25 s: ${z1.ab - z0.ab} Anfragen zu spät (davon ${z1.ng - z0.ng} gar nicht mehr gesendet, ${z1.spaet - z0.spaet} Antworten kamen nach der Frist), `
      + `Frist ${z1.frist} Spielstunden = max(20 s, ${z1.n} × ${(z1.mittel / 1000).toFixed(1)} s × 1,2) bei 100×, Stadt lief ${z1.t - z0.t} Spielstunden weiter`);
    await page.click('#einst-knopf'); await warte(500);
    const einst = await ev(() => document.getElementById('ki-einst-status').textContent + ' || ' + document.querySelector('#einst-dialog p.leise:nth-of-type(3)')?.textContent);
    ok(/in dieser Stadt \d+ KI-Entscheidungen, \d+ zu spät/.test(einst) && /bei jedem Tempo/.test(einst) && /mindestens 20 Sekunden \(bei 1× zwei Minuten\)/.test(einst.replace(/\s+/g, ' ')) && /„zu spät“/.test(einst),
      'Einstellungen: ' + einst.replace(/\s+/g, ' ').slice(0, 260));
    await page.screenshot({ path: BILD + 'wachstum_einst_ki.png' });
    await page.keyboard.press('Escape');
    const dbg = await ev(() => document.getElementById('debug').textContent);
    ok(/offen \d+\n/.test(dbg) && /Code \d+\n/.test(dbg) && /zu spät \d+ \(ungesendet \d+, danach \d+\)\s+Frist \d+ h = \d+ s$/.test(dbg) && !/verworfen/.test(dbg)
      && dbg.split('\n').length === 6 && Math.max(...dbg.split('\n').map(z => z.length)) <= 60,
      `Debug-Ecke (6 Zeilen, längste ${Math.max(...dbg.split('\n').map(z => z.length))} Zeichen): ` + dbg.split('\n').slice(-3).join(' / '));
    mock.verzoegerung = 300;
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }

  if (mit('schalter')) {
    console.log('== Schalter „Wachstum“');
    const A = await seite(b, `${U.HOST}/stadt.html?debug&seed=3&tage=20&neu`, null, false);
    const { ev, page } = A;
    await ev(() => __stadt.setzeTempo(0));
    await page.click('#einst-knopf'); await warte(400);
    const vor = await ev(() => ({ w: __stadt.S().wachstum, n: document.querySelector('[data-wachstum="0"]').getAttribute('aria-pressed'), s: document.querySelector('[data-wachstum="1"]').getAttribute('aria-pressed'),
      text: document.getElementById('wachstum-text').textContent, gruppe: document.querySelector('[data-wachstum="0"]').closest('[role="group"]')?.getAttribute('aria-labelledby') }));
    ok(vor.w === 0 && vor.n === 'true' && vor.s === 'false' && vor.gruppe === 'wachstum-h' && /^Normal: /.test(vor.text) && /Anlauf bis 160 Einwohner: am Tag bis zu 2 mehr, im Dorf auch für Stellen im Laden und im Bauhof \(läuft noch\)/.test(vor.text) && /Nur für eine freie Stelle/.test(vor.text) && /keine Regel der Stadtregierung/.test(vor.text),
      `vorher: normal gedrückt, Gruppe mit Überschrift; „${vor.text}“`);
    await page.click('[data-wachstum="1"]'); await warte(500);
    const nach = await ev(() => ({ w: __stadt.S().wachstum, s: document.querySelector('[data-wachstum="1"]').getAttribute('aria-pressed'), text: document.getElementById('wachstum-text').textContent,
      buch: __stadt.S().buch.filter(e => e.art === 'wachstum').map(e => e.text), li: document.querySelector('#buch-liste li')?.textContent || '' }));
    ok(nach.w === 1 && nach.s === 'true' && /^Schnell: /.test(nach.text) && nach.buch.length === 1 && /Wachstum/.test(nach.li) && /schneller/.test(nach.li),
      `nachher: schnell gedrückt; Stadtbuch „${nach.li.replace(/\s+/g, ' ').slice(0, 90)}…“`);
    await warte(400);                                        // nach dem Übergang der Knöpfe (Befund 10 der Gegenprüfung)
    await page.screenshot({ path: BILD + 'wachstum_einst_schalter.png' });
    const hoehe = await ev(() => { const d = document.getElementById('einst-dialog'); return { sh: d.scrollHeight, ch: d.clientHeight }; });
    ok(hoehe.sh <= hoehe.ch, `Einstellungen bei 1280 × 800 ohne Scrollen: Inhalt ${hoehe.sh} px, sichtbar ${hoehe.ch} px`);
    // Tastatur: Tab erreicht beide Knöpfe, Enter schaltet
    await ev(() => document.querySelector('[data-wachstum="0"]').focus());
    await page.keyboard.press('Enter'); await warte(200);
    ok(await ev(() => __stadt.S().wachstum === 0 && document.activeElement.dataset.wachstum === '0' && __stadt.S().buch.filter(e => e.art === 'wachstum').length === 2), 'Tastatur: Enter auf „normal“ schaltet zurück (zweite Zeile im Stadtbuch)');
    await page.click('[data-wachstum="1"]'); await warte(200);
    await page.keyboard.press('Escape');
    await ev(() => __stadt.speichern());
    await page.goto(`${U.HOST}/stadt.html?debug`);
    await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 60000 });
    await ev(() => __stadt.setzeTempo(0));
    await page.click('#einst-knopf'); await warte(400);
    const geladen = await ev(() => ({ w: __stadt.S().wachstum, s: document.querySelector('[data-wachstum="1"]').getAttribute('aria-pressed') }));
    ok(geladen.w === 1 && geladen.s === 'true', `nach dem Neuladen: Schalter ${geladen.w}, „schnell“ gedrückt ${geladen.s}`);
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
    // Handy: Einstellungen mit dem Schalter, kein seitliches Überlaufen
    const H = await seite(b, `${U.HOST}/stadt.html?debug&seed=3&tage=20&neu`, { width: 400, height: 820 }, false);
    await H.ev(() => __stadt.setzeTempo(0));
    await H.page.click('#einst-knopf'); await warte(500);
    await H.ev(() => document.getElementById('wachstum-h').scrollIntoView());
    await warte(300);
    const hr = await H.ev(() => ({ sw: document.getElementById('einst-dialog').scrollWidth, cw: document.getElementById('einst-dialog').clientWidth,
      kn: [...document.querySelectorAll('[data-wachstum]')].map(k => Math.round(k.getBoundingClientRect().height)) }));
    ok(hr.sw <= hr.cw && hr.kn.every(x => x >= 36), `Handy 400 × 820: Einstellungen ${hr.sw}/${hr.cw} px breit, Knöpfe ${hr.kn.join('/')} px hoch`);
    await H.page.screenshot({ path: BILD + 'wachstum_einst_400.png' });
    await H.ctx.close();
  }

  if (mit('regierung')) {
    console.log('== Fenster „Stadtregierung“, Karte R10');
    const A = await seite(b, `${U.HOST}/stadt.html?debug&seed=2&tage=30&neu`, null, false);
    await A.ev(() => __stadt.setzeTempo(0));
    await A.page.click('#regierung-knopf'); await warte(500);
    const k = await A.ev(() => { const karten = [...document.querySelectorAll('#regierung-dialog .reg-karte')];
      const c = karten.find(x => /Zuzug nur für eine freie Stelle/.test(x.textContent)); return c ? c.innerText.replace(/\s+/g, ' ') : ''; });
    ok(/„strikte Begrenzung des Zuzugsgeschehens“ \(S\. 109\) meint Zuwanderung nach Deutschland/.test(k) && /Bis die Stadt 160 Einwohner hat, dürfen am Tag bis zu 2 mehr kommen/.test(k) && /Noahs Spielschalter in den Einstellungen, keine Maßnahme der Stadtregierung/.test(k) && /Heute dürfen bis zu \d+ (Person|Leute) zuziehen/.test(k),
      'Karte R10: ' + k.slice(0, 200) + ' …');
    // Nicht übernommen: Rückgewinnung (Staatsangehörigkeit) unter „Grenze der Stadt“, KI und Robotik unter „Keine Zahl …“, S. 109 dort mit Anlauf und Schalter
    const n = await A.ev(() => { const d = document.getElementById('regierung-dialog'); for (const x of d.querySelectorAll('details')) x.open = true;
      const t = (titel) => { const k = [...d.querySelectorAll('details')].find(x => (x.querySelector('summary') || { textContent: '' }).textContent.startsWith('Nicht übernommen – ' + titel)); return k ? k.innerText.replace(/\s+/g, ' ') : ''; };
      return { grenze: t('Grenze der Stadt'), zahl: t('Keine Zahl, keine Mechanik oder kein Fall') }; });
    ok(/Rückgewinnungsprogramme für abgewanderte Leistungsträger/.test(n.grenze) && /Staatsangehörigkeit/.test(n.grenze)
      && /Robotik und Digitalisierung/.test(n.zahl) && /ersetzt keine Stelle/.test(n.zahl) && /Zuzugsgeschehens[^]*Der Anlauf bis zur Stadt und Noahs Schalter „Wachstum“ sind Spielregeln/.test(n.zahl),
      `Nicht übernommen: Rückgewinnung (S. 113) unter „Grenze der Stadt“, KI und Robotik (S. 113) und S. 109 mit Anlauf und Schalter unter „Keine Zahl“`);
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }

  if (mit('leistung')) {
    console.log('== Leistung 20× gegen 100× (SwiftShader, nur zum Vergleich)');
    for (const [name, url] of [['Teststadt Tag 400', '?debug&seed=2&tage=400&neu'], ['große Stadt (Umland 300000, Tag 750)', '?debug&umland=300000&tage=750&seed=2&neu']]) {
      const t0 = Date.now();
      const A = await seite(b, `${U.HOST}/stadt.html${url}`, null, false);
      const { ev, page } = A;
      console.log(`     ${name}: vorab gerechnet in ${((Date.now() - t0) / 1000).toFixed(0)} s, ${await ev(() => __stadt.S().einwohner)} Einwohner`);
      const k = await ev(() => {                                // Kosten je Spielstunde samt Oberfläche (Pause, 48 Schritte ab Mitternacht)
        const a = __stadt; a.setzeTempo(0);
        while (a.S().stunde !== 0) a.schritt();
        const z = [];
        for (let i = 0; i < 48; i++) { const t = performance.now(); a.schritt(); a.nachSchritten(); z.push(performance.now() - t); }
        const nacht = [z[23], z[47]], rest = z.filter((_, i) => i !== 23 && i !== 47);
        return { mittel: rest.reduce((x, y) => x + y, 0) / rest.length, max: Math.max(...rest), nacht };
      });
      console.log(`     je Spielstunde samt Oberfläche: Ø ${k.mittel.toFixed(1)} ms, höchstens ${k.max.toFixed(1)} ms, Mitternacht ${k.nacht.map(x => x.toFixed(0)).join(' / ')} ms`);
      for (const tempo of [20, 100]) {
        // beide Tempi ab 7 Uhr (in der Pause vorgerechnet): sonst fielen die Stichproben bei 20× in die Nacht, ohne Autos
        await ev(() => { const a = __stadt; a.setzeTempo(0); while (a.S().stunde !== 7) a.schritt(); a.nachSchritten(); });
        await ev((t) => __stadt.setzeTempo(t), tempo);
        await warte(2500);
        const s0 = await ev(() => ({ st: __stadt.S().tag * 24 + __stadt.S().stunde, z: performance.now() }));
        // Autos: Zähler der laufenden Stunde alle 250 ms abfragen, je Spielstunde der größte Stand, über alle Stunden summiert (bei 100× dauert
        // eine Stunde 0,6 s; eine Stichprobe alle 1,5 s traf je nach Lage nur Stunden ohne Berufsverkehr)
        const proben = [], jeStunde = new Map();
        for (let i = 0; i < 8; i++) {
          for (let j = 0; j < 6; j++) {
            await warte(250);
            const a = await ev(() => ({ h: __stadt.S().tag * 24 + __stadt.S().stunde, ...__stadt.G.test.autos().zaehl }));
            const m = jeStunde.get(a.h) || { spaet: 0, rest: 0, sichtbar: 0, fahrten: 0 };
            for (const k of Object.keys(m)) m[k] = Math.max(m[k], a[k]);
            jeStunde.set(a.h, m);
          }
          proben.push(await ev(() => ({ ...globalThis.__stadtDebug })));
        }
        const autos = { spaet: 0, rest: 0, sichtbar: 0, fahrten: 0 };
        for (const m of jeStunde.values()) for (const k of Object.keys(autos)) autos[k] += m[k];
        const s1 = await ev(() => ({ st: __stadt.S().tag * 24 + __stadt.S().stunde, z: performance.now() }));
        const fps = proben.map(p => p.fps), fmax = Math.max(...proben.map(p => p.frameMax)), sek = (s1.z - s0.z) / 1000, std = s1.st - s0.st;
        const fpsM = fps.reduce((x, y) => x + y, 0) / fps.length;
        console.log(`     ${tempo}×: fps Ø ${fpsM.toFixed(1)} (${Math.min(...fps).toFixed(0)}–${Math.max(...fps).toFixed(0)}), Frame Ø ${(proben.reduce((x, p) => x + p.frameMs, 0) / proben.length).toFixed(1)} ms, `
          + `längster ${fmax.toFixed(0)} ms, Draw Calls ${proben[proben.length - 1].calls}; ${std} Spielstunden in ${sek.toFixed(1)} s (Soll ${(sek * tempo / 60).toFixed(1)}), `
          + `Bilder je Spielstunde ${(fpsM * 60 / tempo).toFixed(1)}; Autos in ${jeStunde.size} Spielstunden: ${autos.fahrten} Fahrten, ${autos.sichtbar} sichtbar geplant, ${autos.spaet} zu spät gesprungen, ${autos.rest} am Stundenende versetzt`);
        await page.screenshot({ path: BILD + `wachstum_leistung_${name.startsWith('große') ? 'gross' : 'mittel'}_${tempo}x.png` });
      }
      if (A.log.length) ok(false, 'Konsole: ' + A.log.join(' | '));
      await A.ctx.close();
    }
  }
  await b.close();
  console.log(process.exitCode ? 'Prüfungen fehlgeschlagen' : 'Alle Prüfungen bestanden');
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
