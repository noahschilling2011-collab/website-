// Befunde der Schlussprüfung von Version 9 (Technik, Texte, Bedienung) im Browser: Leiste mit 6 Zeilen ohne Scrollen (1280 × 800, 1366 × 768),
// Stadtbuch-Zeile der Wahl ohne Umbruch nach „(“, Personenkarte des Bürgermeisters (Amtszeit einmal, gesperrter Knopf mit Grund, Ziel im Amt),
// Leertaste auf einem Tempo-Knopf per Tastatur = Pause, Fokus nach „Haushalt“ und „Stadtregierung“ aus der Rathaus-Karte zurück auf deren Knopf,
// Tagebuch „klappte nicht“ nur, wenn es nicht geklappt hat, keine Allokation je Bild für die KI-Frist, Texte in den Fenstern „Haushalt“ und
// „Stadtregierung“ (Noahs Spielregel, Wahl, R10, 0 %), Übernahme von Version 8 mit kurzer Meldung und der ersten Wahl in „Während du weg warst“.
// Server: tests/alle.sh (PORT, Wurzel stadt/). Bilder: tests/ausgabe/bilder_befunde/v9_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, url, viewport, vorher) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  if (vorher) await vorher(page);
  await page.goto(url, { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  const ev = (f, a) => page.evaluate(f, a);
  return { ctx, page, log, ev };
}
const dialogeZu = (ev) => ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
// Hauskarte öffnen wie ein Knopf im Stadtbuch (button.haus, derselbe Weg wie jeder Hausknopf)
const hauskarte = (ev, b) => ev((b) => { const k = Object.assign(document.createElement('button'), { type: 'button', className: 'haus' }); k.dataset.b = b;
  document.body.append(k); k.click(); k.remove(); }, b);
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  // 1. Neue Stadt (Seed 2, Tag 1) bei 1280 × 800 und 1366 × 768: 5 Hauptfiguren und der Bürgermeister, 6 Zeilen ohne Scrollen
  for (const vp of [{ width: 1280, height: 800 }, { width: 1366, height: 768 }]) {
    const A = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=1&neu', vp);
    await A.ev(() => __stadt.setzeTempo(0)); await dialogeZu(A.ev); await A.page.waitForTimeout(400);
    const l = await A.ev(() => { const L = document.getElementById('haupt-liste'), z = [...L.querySelectorAll('.haupt-zeile')], r = L.getBoundingClientRect();
      const buch = document.getElementById('buch-liste').getBoundingClientRect();
      return { n: z.length, sh: L.scrollHeight, ch: L.clientHeight, unten: Math.round(r.bottom), letzte: z.length ? Math.round(z[z.length - 1].getBoundingClientRect().bottom) : 0,
        buchHoehe: Math.round(buch.height), innerHeight }; });
    ok(l.n === 6 && l.sh <= l.ch && l.letzte <= l.unten && l.buchHoehe >= 150,
      `${vp.width} × ${vp.height}: Leiste ${l.n} Zeilen, scrollHeight ${l.sh} ≤ sichtbar ${l.ch} (letzte Zeile endet bei ${l.letzte}, Liste bei ${l.unten}); Stadtbuch darunter ${l.buchHoehe} px hoch`);
    if (vp.width === 1280) {
      await A.page.screenshot({ path: BILD + 'v9_leiste_1280.png' });
      // 2. Stadtbuch: Die Zeile der ersten Wahl bricht nicht zwischen „(“ und dem ersten Namen um
      const w = await A.ev(() => { const li = [...document.querySelectorAll('#buch-liste li')].find(x => /Erste Bürgermeisterwahl/.test(x.textContent));
        if (!li) return null;
        const sp = [...li.querySelectorAll('span.zusammen')].filter(s => s.textContent.startsWith('('));
        return { text: li.textContent.slice(0, 160), klammer: sp.length, eineZeile: sp.every(s => s.getClientRects().length === 1),
          frei: [...li.childNodes].some(n => n.nodeType === 3 && /\($/.test(n.textContent)) }; });
      ok(!!w && w.klammer >= 1 && w.eineZeile && !w.frei, `Stadtbuch, erste Wahl: „(“ steht mit dem ersten Namen in einer nicht umbrechenden Spanne (${w && w.klammer}), keine „(“ allein am Zeilenende; „${w && w.text}…“`);
      // 3. Personenkarte des Bürgermeisters: Amtszeit einmal, gesperrter Knopf mit Grund, Heute ohne Amtszeit
      await A.page.click('#haupt-liste .haupt-zeile'); await A.page.waitForTimeout(400);
      const k = await A.ev(() => { const t = document.getElementById('karte-inhalt').innerText, kn = [...document.querySelectorAll('#karte [data-haupt]')];
        return { t, amtszeit: (t.match(/Amtszeit bis Tag/g) || []).length, knopf: kn.map(x => x.textContent + (x.disabled ? ' (gesperrt)' : '')), grund: (document.querySelector('#karte .karte-knoepfe .leise') || {}).textContent || '' }; });
      ok(k.amtszeit === 1 && k.knopf.join() === 'Auch nach der Amtszeit Hauptfigur (gesperrt)' && /Mehr als 5 Hauptfiguren erst, wenn die KI im Schnitt unter 5 Sekunden antwortet/.test(k.grund)
        && /Heute: im Rathaus, leitet die Verwaltung, von 8 bis 17 Uhr\./.test(k.t),
        `Karte des Bürgermeisters: „Amtszeit bis“ ${k.amtszeit}-mal, Knopf ${k.knopf.join()}, Grund „${k.grund.slice(0, 140)}“`);
      await A.page.screenshot({ path: BILD + 'v9_bm_karte.png' });
      // Ziel „besserer Job“ im Amt: die Karte sagt, dass er die Stelle nicht wechselt (erzwungen: Ziel setzen)
      const z = await A.ev(() => { const S = __stadt.S(), B = S.buergermeister; S.p.ziel[B.p] = 2; S.p.zielSeit[B.p] = S.tag; return true; });
      await A.page.click('#haupt-liste .haupt-zeile'); await A.page.waitForTimeout(300);
      const zt = await A.ev(() => (document.getElementById('karte-inhalt').innerText.match(/Ziel: [^\n]*/) || [''])[0]);
      ok(z && /Ziel: besserer Job \(noch \d+ Tage?; im Amt kein Stellenwechsel, es zählt nur ein höherer Lohn im Rathaus\)/.test(zt), `Ziel im Amt: „${zt}“`);
      await A.page.keyboard.press('Escape');
    }
    ok(!A.log.length, `${vp.width} × ${vp.height}: Konsole ` + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }

  // 4. Tempo per Tastatur: Tab bis 100×, Enter drückt den Knopf, die Leertaste ist dort Pause und weiter (wie die Hilfe sagt)
  {
    const A = await seite(b, U.HOST + '/stadt.html?debug&seed=3&tage=2&neu');
    await dialogeZu(A.ev); await A.ev(() => __stadt.setzeTempo(1)); await A.page.waitForTimeout(300);
    await A.ev(() => document.activeElement && document.activeElement.blur());
    let fokus = '';
    for (let i = 0; i < 60 && fokus !== '100×'; i++) { await A.page.keyboard.press('Tab'); fokus = await A.ev(() => document.activeElement && document.activeElement.closest('#tempo') ? document.activeElement.textContent.trim() : ''); }
    const tempo = () => A.ev(() => [...document.querySelectorAll('#tempo button')].find(k => k.getAttribute('aria-pressed') === 'true').dataset.tempo);
    await A.page.keyboard.press('Enter'); const t1 = await tempo();
    await A.page.keyboard.press('Space'); const t2 = await tempo();
    await A.page.keyboard.press('Space'); const t3 = await tempo();
    const fokus2 = await A.ev(() => document.activeElement.textContent.trim());
    ok(fokus === '100×' && t1 === '100' && t2 === '0' && t3 === '100' && fokus2 === '100×', `Tastatur: Tab bis „${fokus}“, Enter → ${t1}×, Leertaste → ${t2} (Pause), Leertaste → ${t3}×, Fokus bleibt auf „${fokus2}“`);
    // Mausklick auf 5×, dann Leertaste: Pause (wie vorher)
    await A.page.click('#tempo [data-tempo="5"]'); await A.page.keyboard.press('Space'); const t4 = await tempo();
    await A.page.keyboard.press('Space'); const t5 = await tempo();
    ok(t4 === '0' && t5 === '5', `Maus: Klick auf 5×, Leertaste → ${t4} (Pause), Leertaste → ${t5}×`);
    await A.ev(() => __stadt.setzeTempo(0));
    // 5. Keine neuen Objekte je Bild für die KI-Frist: Sim.hauptListe wird in 3 s bei 1× nicht aufgerufen (vorher 1,1-mal je Bild)
    const n = await A.ev(async () => { const Sim = __stadt.Sim, alt = Sim.hauptListe; let n = 0; Sim.hauptListe = function () { n++; return alt.apply(this, arguments); };
      __stadt.setzeTempo(1); const f0 = __stadtDebug ? performance.now() : 0; await new Promise(r => setTimeout(r, 3000)); __stadt.setzeTempo(0); Sim.hauptListe = alt;
      return { n, zahl: Sim.hauptListeZahl(__stadt.S()), laenge: alt(__stadt.S()).length, ms: Math.round(performance.now() - f0) }; });
    ok(n.n <= 2 && n.zahl === n.laenge, `KI-Frist je Bild: Sim.hauptListe in ${n.ms} ms ${n.n}-mal aufgerufen (nur bei neuen Stunden in der Leiste), hauptListeZahl ${n.zahl} = Länge ${n.laenge}`);
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }

  // 6. Rathaus-Karte → Fenster „Haushalt“ bzw. „Stadtregierung“ per Tastatur, Escape: Fokus zurück auf den Knopf der Karte. Texte der Fenster (Seed 2, Tag 400)
  {
    const A = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=400&neu');
    await A.ev(() => __stadt.setzeTempo(0)); await dialogeZu(A.ev); await A.page.waitForTimeout(300);
    const rb = await A.ev(() => __stadt.S().rathaus.b);
    for (const [knopf, dialog] of [['data-haushalt', 'haushalt-dialog'], ['data-regierung', 'regierung-dialog']]) {
      await hauskarte(A.ev, rb); await A.page.waitForTimeout(400);
      await A.page.focus(`#karte button[${knopf}]`);
      await A.page.keyboard.press('Enter'); await A.page.waitForTimeout(500);
      const offen = await A.ev((d) => document.getElementById(d).open, dialog);
      await A.page.keyboard.press('Escape'); await A.page.waitForTimeout(300);
      const f = await A.ev((k) => ({ zurueck: !!document.activeElement && document.activeElement.matches(`#karte button[${k}]`), text: document.activeElement ? document.activeElement.textContent.trim() : '',
        karte: !document.getElementById('karte').hidden }), knopf);
      ok(offen && f.zurueck && f.karte, `Rathaus-Karte → ${dialog} per Tastatur, Escape: Fokus auf „${f.text}“ in der Karte (Karte offen: ${f.karte})`);
    }
    await A.page.keyboard.press('Escape');
    // Fenster „Haushalt“: Spielregel genannt, keine „-0“, „es fehlt“ klein, bei 0 % der Satz dazu
    await A.page.click('#haushalt-knopf'); await A.page.waitForTimeout(500);
    const h = await A.ev(() => { const d = document.getElementById('haushalt-dialog'), t = d.innerText, karten = [...d.querySelectorAll('.reg-karte')];
      const st = (titel) => { const k = karten.find(x => x.querySelector('h4') && x.querySelector('h4').textContent.startsWith(titel)); return k ? (k.querySelector('.reg-status') || {}).textContent : ''; };
      return { t, satz: __stadt.S().haushalt.satz, erst: st('Erst ausgeben'), dann: st('Dann die Lohnsteuer senken') }; });
    ok(/Die Reihenfolge – erst ausgeben, dann die Lohnsteuer senken – ist eine Spielregel \(Noahs Entscheidung\), keine Forderung des Programms\./.test(h.t)
      && h.erst === 'Spielregel' && h.dann === 'wirkt' && /Bedingung, erst auszugeben, ist Noahs Spielregel/.test(h.t) && /Abschreibungen für „Steuersparmodelle“ \(S\. 56\)/.test(h.t)
      && /bundesweit geregelte Einkommensteuer \(Aufkommen bei Bund, Ländern und Gemeinden\)/.test(h.t) && !/Einkommensteuer des Bundes/.test(h.t)
      && !/(^|[^\d])-0 Taler|−0 Taler/.test(h.t) && !/; Es fehl/.test(h.t) && (h.satz !== 0 || /Die Lohnsteuer ist bei 0 %\. Mehr gibt die Stadt nach ihren Regeln nicht zurück/.test(h.t)),
      `Fenster „Haushalt“ (Satz ${h.satz} %): Spielregel in der Einleitung, Karte „Erst ausgeben“ ${h.erst}, „Dann die Lohnsteuer senken“ ${h.dann} mit Noahs Bedingung, Abschreibungen und Einkommensteuer richtig, keine „-0“, „es fehlt“ klein, Satz bei 0 %`);
    await A.page.screenshot({ path: BILD + 'v9_haushalt.png' });
    await A.page.keyboard.press('Escape');
    // Fenster „Stadtregierung“: Zur Vollständigkeit, R10, Wahl, Bürgermeister, Lohnsteuer-Karte
    await A.page.click('#regierung-knopf'); await A.page.waitForTimeout(500);
    const r = await A.ev(() => { const d = document.getElementById('regierung-dialog'); for (const x of d.querySelectorAll('details')) x.open = true;
      const karte = (titel) => { const k = [...d.querySelectorAll('.reg-karte')].find(x => x.querySelector('h4') && x.querySelector('h4').textContent.startsWith(titel)); return k ? k.innerText.replace(/\s+/g, ' ') : ''; };
      return { alles: d.innerText.replace(/\s+/g, ' '), r10: karte('Zuzug nur für eine freie Stelle'), wahl: karte('Wahl: direkt'), bm: karte('Bürgermeister: direkt gewählt'), steuer: karte('Lohnsteuer sinkt') }; });
    ok(/dazu niedrigere Steuersätze; wann die Stadt senkt \(erst ausgeben, dann senken\), ist eine Spielregel/.test(r.alles) && !/dazu eine Lohnsteuer, die sinkt, wenn/.test(r.alles)
      && /Bedingung, erst auszugeben und dann zu senken, ist Noahs Spielregel/.test(r.steuer) && /bundesweit geregelte Einkommensteuer/.test(r.steuer)
      && /an einem Tag höchstens so viele, wie solche Stellen frei sind/.test(r.r10)
      && /wählen darf, wer 18 ist, gewählt werden kann, wer 18 bis 64 ist und eine Stelle antreten kann/.test(r.wahl)
      && /§ 44a Kommunalwahlgesetz/.test(r.bm) && /Sachsen: ja, § 49 Abs\. 1 SächsGemO/.test(r.bm) && /vorwiegend“ \(S\. 160\) digitalfrei/.test(r.alles),
      'Fenster „Stadtregierung“: Zur Vollständigkeit (Spielregel), Lohnsteuer-Karte, R10 genau, Wahl 18 bis 64, Bürgermeister mit § 44a KomWG und § 49 SächsGemO, „vorwiegend“');
    await A.page.keyboard.press('Escape');
    // 7. Tagebuch: KI-Entscheidung „freinehmen“ um 7 Uhr, ausgeführt → ohne „(klappte nicht)“ (Befund Bedienung: vorher immer)
    const tb = await A.ev(() => { const a = __stadt, S = a.S(), Sim = a.Sim; S.ki.an = true; S.ki.heute = {};
      let x = null;
      for (let i = 0; i < 60 && !x; i++) { a.schritt(); x = S.ki.anfragen.find(q => q.stunde === 7 && q.erlaubt.includes('freinehmen') && Sim.kiErlaubtJetzt(S, q.id, q.gen).includes('freinehmen')); }
      if (!x) { S.ki.an = false; return null; }
      const e = Sim.kiEntscheidung(S, x.id, x.gen, 'freinehmen', null, 'Heute ruhe ich mich aus.', x.nr);
      for (const q of S.ki.anfragen.slice()) Sim.kiVerwerfen(S, q.id, q.gen, q.nr);
      S.ki.an = false; a.nachSchritten();
      return { id: x.id, gen: x.gen, e, name: Sim.name(S, x.id) }; });
    let tbText = '';
    if (tb) {
      await A.ev((t) => { const k = Object.assign(document.createElement('button'), { type: 'button', className: 'name' }); k.dataset.p = t.id; k.dataset.g = t.gen; k.dataset.n = t.name;
        document.body.append(k); k.click(); k.remove(); }, tb);
      await A.page.waitForTimeout(400);
      tbText = await A.ev(() => ([...document.querySelectorAll('#karte .tagebuch li')].map(li => li.innerText).find(x => /Heute ruhe ich mich aus/.test(x)) || ''));
    }
    ok(!!tb && tb.e.ok && tb.e.ausgefuehrt && /nimmt frei/.test(tbText) && !/klappte nicht/.test(tbText), `Tagebuch nach „freinehmen“ (${tb ? tb.name : '–'}): „${tbText.replace(/\s+/g, ' ')}“`);
    await A.page.keyboard.press('Escape');
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }

  // 8. Übernahme eines Stands von Version 8 (tests/basis_v8.json, Tag 420) nach 40 Spieltagen Abwesenheit: kurze Meldung, danach „Während du weg
  //    warst“ mit der ersten Bürgermeisterwahl (Befund Bedienung: sie fehlte in der Übersicht)
  {
    const d = JSON.parse(fs.readFileSync(U.basis('basis_v8.json'), 'utf8'));
    d.zuletztGelaufen = Date.now() - 40 * 24 * 60 * 1000; d.tempo = 1;             // 40 Spieltage weg (bei 1× ist eine Spielstunde eine echte Minute)
    const A = await seite(b, U.HOST + '/stadt.html?debug', { width: 400, height: 820 }, async (page) => {
      await page.goto(U.LEER);
      await page.evaluate((t) => { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); }, JSON.stringify(d));
    });
    await A.page.waitForTimeout(500);
    const v = await A.ev(() => document.getElementById('version-dialog').open);
    await A.page.click('#version-uebernehmen');
    await A.page.waitForFunction(() => document.getElementById('weg-dialog').open || (document.getElementById('aufholen').hidden && !document.getElementById('version-dialog').open && performance.now() > 120000),
      null, { timeout: 600000, polling: 500 });
    const u = await A.ev(() => { const S = __stadt.S(), m = document.getElementById('meldung');
      return { weg: document.getElementById('weg-dialog').open ? document.getElementById('weg-inhalt').innerText : '', meldung: m.textContent, tag: S.tag,
        wahl: S.buch.filter(e => e.art === 'wahl').map(e => 'Tag ' + e.tag + ': ' + __stadt.Sim.klartext(e.text).slice(0, 100)), bm: S.buergermeister.p }; });
    // Version 10 (Etappe 2): die Meldung nennt dazu „Bewohner mit Erfahrung und Plänen“; die Grenze wächst genau um diesen Punkt
    const NEU10 = '; Bewohner mit Erfahrung und Plänen';
    ok(v && u.meldung.startsWith('Deine Stadt ist übernommen') && u.meldung.length <= 200 + NEU10.length && u.meldung.includes(NEU10) && /Rathaus mit Bürgermeister, Schulen, Haushalt/.test(u.meldung) && !/Autos/.test(u.meldung),
      `Meldung nach dem Übernehmen (${u.meldung.length} Zeichen): „${u.meldung}“`);
    ok(u.bm >= 0 && u.wahl.length >= 1 && /Bürgermeister/.test(u.weg), `„Während du weg warst“ bis Tag ${u.tag} nennt die erste Wahl (${u.wahl[0] || '–'}): „${u.weg.replace(/\s+/g, ' ').slice(-400)}“`);
    await A.page.screenshot({ path: BILD + 'v9_weg_nach_uebernahme_400.png' });
    ok(!A.log.length, 'Konsole: ' + (A.log.length ? A.log.join(' | ') : 'leer'));
    await A.ctx.close();
  }
  await b.close();
})().catch((e) => { console.log('Testfehler ' + e.stack); process.exitCode = 1; });
