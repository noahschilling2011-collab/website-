// Befunde der Gegenprüfung von Schritt 2 im Browser: Versionsdialog der Version 5 am Handy (Hauptknopf sichtbar, Anfang des Textes
// sichtbar), Fenster „Stadtregierung“ am Handy (Kartenhöhen, aufklappbarer Teil, Zitat S. 147, Live-Zeile der Kitas), Tag-0-Zeile,
// Hauskarte der Kita (Fachkräfte und Bedarf), Kind am letzten Kita-Tag, Beitragsjahre ab dem Anspruch, Konsole leer. Bilder nach tests/ausgabe/bilder_befunde/.
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const OUT = U.ordner('bilder_befunde');
fs.mkdirSync(OUT, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
const kontext = async (b, w, h, extra = {}) => {
  const ctx = await b.newContext({ viewport: { width: w, height: h }, ...extra });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (r) => r.abort());
  return ctx;
};
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const log = [];
  const horch = (page, n) => {
    page.on('pageerror', e => log.push(n + ' pageerror: ' + e.message));
    page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|ERR_FAILED/.test(m.text())) log.push(n + ' error: ' + m.text()); });
  };
  // 1. Versionsdialog der Version 5 (Git 414ebab per git show unter stadt.orig.html, tests/umgebung.cjs) und der Version 6 (Git bc7247a):
  // Hauptknopf im Bild, Textanfang im Bild (hochkant und quer)
  // Seit der Schlussprüfung von Version 9 ist die Meldung kurz (Stichworte); die Übergangsfrist der Kitas steht in der Zeile im Stadtbuch (buchRe)
  for (const [v, datei, textRe, meldungRe, buchRe] of [['5', 'v5', /arbeitende Alleinerziehende/, /Neu: Mieterkauf, Rente ohne Abschlag, Kitas; wachsende Karte mit Stadtteilen/,
    /bis kein Kind mehr auf einen Platz wartet \(mindestens bis Tag \d+, höchstens bis Tag \d+\), muss niemand wegen eines fehlenden Platzes zu Hause bleiben/],
    ['6', 'v6', /Seit Version 7 wächst die Karte mit der Stadt/, /Neu: wachsende Karte mit Stadtteilen/, null]])
  for (const [w, h, touch] of [[360, 740, true], [568, 320, true], [844, 390, true], [1280, 800, false]]) {
    const ctx = await kontext(b, w, h, { hasTouch: touch, isMobile: touch });
    await U.fassungUnter(ctx, datei);
    const page = await ctx.newPage(); horch(page, `V${v} ${w}×${h}`);
    await page.goto(U.LEER); await page.evaluate(() => localStorage.clear());
    await page.goto(U.HOST + '/stadt.orig.html?debug&seed=3&tage=150&neu'); await page.waitForFunction(() => globalThis.__stadt);
    await page.evaluate(() => { __stadt.setzeTempo(0); __stadt.speichern(); });
    await page.goto(U.HOST + '/stadt.html?debug'); await page.waitForFunction(() => globalThis.__stadt); await page.waitForTimeout(700);
    const d = await page.evaluate(() => {
      const dlg = document.getElementById('version-dialog'), k = document.getElementById('version-uebernehmen').getBoundingClientRect(), t = document.getElementById('version-titel').getBoundingClientRect(), r = dlg.getBoundingClientRect();
      return { offen: dlg.open, knopf: [Math.round(k.top), Math.round(k.bottom)], titel: Math.round(t.top), dlg: [Math.round(r.top), Math.round(r.bottom)], scroll: dlg.scrollTop, hoch: dlg.scrollHeight, h: innerHeight,
        fokus: document.activeElement && document.activeElement.id, text: document.getElementById('version-text').textContent };
    });
    await page.screenshot({ path: OUT + `versionsdialog_v${v}_${w}x${h}.png` });
    ok(d.offen && d.knopf[1] <= Math.min(d.h, d.dlg[1]) && d.knopf[0] >= d.dlg[0] && d.titel >= d.dlg[0] && textRe.test(d.text) && d.text.startsWith(`Dein Spielstand ist von Version ${v}.`),
      `Version ${v}, ${w}×${h}: „Stadt übernehmen“ ${d.knopf[0]}–${d.knopf[1]} px im Bild (Dialog ${d.dlg[0]}–${d.dlg[1]}, Inhalt ${d.hoch} px), Titel bei ${d.titel} px, Fokus ${d.fokus}, gescrollt ${d.scroll}`);
    if (w === 360) {
      await page.click('#version-uebernehmen'); await page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 30000 }); await page.waitForTimeout(500);
      const m = await page.evaluate(() => document.getElementById('meldung').textContent);
      const buch = await page.evaluate(() => __stadt.S().buch.map(e => __stadt.Sim.klartext(e.text)).join(' | '));
      ok(meldungRe.test(m) && m.length <= 400 && (!buchRe || buchRe.test(buch)), `Version ${v}, ${w}×${h}: Meldung nach der Übernahme (${m.length} Zeichen): „${m}“`
        + (buchRe ? `; im Stadtbuch: „${(buch.match(buchRe) || ['–'])[0]}“` : ''));
    }
    await ctx.close();
  }
  // 2. Teststadt (Seed 2, Tag 300) am Handy und breit: Fenster, Karten, Stadtbuch
  for (const [w, h, n] of [[360, 740, 'handy'], [1280, 800, 'breit']]) {
    const ctx = await kontext(b, w, h, n === 'handy' ? { hasTouch: true, isMobile: true } : {});
    const page = await ctx.newPage(); horch(page, n);
    await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=300&neu', { timeout: 600000 });
    await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 600000 });
    const zu = () => page.evaluate(() => { const a = __stadt, S = a.S(); a.setzeTempo(0); while (S.ki.verlust.length) a.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
    await zu(); await page.waitForTimeout(600); await zu();
    // Tag-0-Zeile: kurz, Rente als Angebot
    const t0 = await page.evaluate(() => { const e = __stadt.Sim.neueStadt(2).buch.find(x => x.art === 'regierung' && x.tag === 0); return e ? __stadt.Sim.klartext(e.text) : ''; });   // in der Teststadt schon aus dem Stadtbuch (500 Zeilen)
    ok(t0.length > 0 && t0.length < 950 && /kann man ohne Abschlag in Rente gehen/.test(t0) && /Kitas mit Vorrang für arbeitende Eltern/.test(t0), `${n}: Tag-0-Zeile ${t0.length} Zeichen`);
    // Fenster: Kartenhöhen, aufklappbarer Teil zu, öffnet per Klick
    await page.click('#regierung-knopf'); await page.waitForTimeout(500);
    const f = await page.evaluate(() => {
      const karten = [...document.querySelectorAll('#regierung-inhalt .reg-karte')];
      return { karten: karten.map(k => ({ t: k.querySelector('h4 span').textContent, h: Math.round(k.getBoundingClientRect().height), mehr: !!k.querySelector('details.reg-mehr'), offen: !!(k.querySelector('details.reg-mehr') || {}).open })),
        kita: (karten.find(k => k.querySelector('h4').textContent.startsWith('Kitas')) || {}).textContent || '',
        live: ((karten.find(k => k.querySelector('h4').textContent.startsWith('Kitas')) || document).querySelector('p.reg-live') || {}).textContent || '',
        vollst: document.getElementById('regierung-inhalt').textContent };
    });
    const max = Math.max(...f.karten.map(k => k.h)), lang = f.karten.filter(k => k.mehr);
    // Seit Version 7 hat auch die Karte „Die Stadt wächst“ (Stadt erweitern) einen aufklappbaren Teil, seit Teil 2 (Sicherheit) dazu fünf
    // Karten der inneren Sicherheit, seit Teil 3 (Bund) drei Karten des Bundes, seit Version 8 die Spielregel zu Tech-Firmen und Autos,
    // seit Version 9 die Spielregeln zu Rathaus und Bürgermeister, seit Teil 2 die Karte der Schule: sechzehn statt vier, jede mit Titel erwartet
    const AUFKLAPP = ['Rente ohne Abschlag', 'Kitas in Wohnraumnähe', 'Mieter kaufen', 'Rathaus von Anfang an', 'Bürgermeister: direkt gewählt',
      'Schulpflicht, Schulen in Wohnnähe, Lehrkräfte vom Land', 'Die Stadt wächst', 'Taten, Anzeige und Aufklärung', 'Mehr Polizei',
      'Mehrfachtäter und Wohnungseinbruch', 'Gericht, Strafen und Register', 'Justizvollzugsanstalt für die Region',
      'Kaserne der Bundeswehr', 'Wehrpflicht für alle, die 18 werden', 'Dienststelle des Bundesnachrichtendienstes', 'Tech-Firmen wachsen, Autowerke, Autos'];
    ok(lang.length === AUFKLAPP.length && AUFKLAPP.every(a => lang.some(k => k.t.startsWith(a))) && lang.every(k => !k.offen) && (n !== 'handy' || max <= 1250), `${n}: Karten bis ${max} px hoch; aufklappbar (zu): ${lang.map(k => `${k.t} ${k.h} px`).join(', ')}`);
    ok(/Doppelberufstätigkeit/.test(f.kita) && /örtlichen Träger der öffentlichen Jugendhilfe/.test(f.kita) && /Lohnregel ist eine Annahme der Stadt/.test(f.kita) && /Fachkr(aft|äfte) \(Bedarf \d+\)/.test(f.live)
      && /Kauf von Wohneigentum/.test(f.vollst) && /kommunales Wohngeld/.test(f.vollst) && /ohne Kita-Platz zu Hause bleiben muss/.test(f.vollst),
      `${n}: Kita-Karte mit S. 147, Träger, Lohnregel; live „${f.live.slice(0, 90)}…“; Listen nachgezogen`);
    await page.evaluate(() => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => x.querySelector('h4').textContent.startsWith('Kitas')); k.scrollIntoView({ block: 'start' }); });
    await page.waitForTimeout(300); await page.screenshot({ path: OUT + `${n}_kita_zu.png` });
    await page.evaluate(() => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => x.querySelector('h4').textContent.startsWith('Kitas')); k.querySelector('details.reg-mehr summary').scrollIntoView({ block: 'center' }); });
    await page.click('#regierung-inhalt .reg-karte details.reg-mehr summary >> nth=1');
    await page.waitForTimeout(300);
    const auf = await page.evaluate(() => [...document.querySelectorAll('#regierung-inhalt details.reg-mehr')].map(d => d.open));
    await page.screenshot({ path: OUT + `${n}_kita_auf.png` });
    ok(auf.filter(Boolean).length === 1, `${n}: Tipp auf „Weitere Annahmen und Folgen“ öffnet genau einen Teil (${auf.join(', ')})`);
    await page.keyboard.press('Escape'); await page.waitForTimeout(300); await zu();
    // Hauskarte einer Kita: Fachkräfte und Bedarf getrennt; Kind am letzten Kita-Tag; Beitragsjahre ab dem Anspruch
    const x = await page.evaluate(() => {
      const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, R = Sim.R;
      let kita = -1, kind = -1, besitzer = -1, angestellt = -1;
      for (let t = 0; t < 30 && kind < 0; t++) {
        for (let k = 0; k < S.pMax; k++) if (P.lebt[k] && P.kita[k] && S.tag - P.geb[k] >= R.KITA_ENDE) { kind = k; kita = P.kita[k] - 1; break; }
        if (kind < 0) { const d = S.tag; while (S.tag === d) a.schritt(); a.nachSchritten(); }
      }
      if (kita < 0) for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.KITA) { kita = b; break; }
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p] || S.tag - P.geb[p] >= R.RENTE * R.JAHR || !Sim.anspruch(S, p) || Sim.rentner(S, p)) continue;
        if (besitzer < 0 && P.besitz[p] >= 0) besitzer = p;
        if (angestellt < 0 && P.besitz[p] < 0 && P.arbeit[p] >= 0) angestellt = p;
      }
      return { kita, kind, besitzer, angestellt, tag: S.tag };
    });
    const oeffne = async (p) => { await page.evaluate((p) => { const a = __stadt, S = a.S(); const btn = document.createElement('button'); btn.className = 'name'; btn.dataset.p = p; btn.dataset.g = S.p.gen[p]; btn.dataset.n = a.Sim.name(S, p);
      document.getElementById('buch-liste').append(btn); btn.click(); btn.remove(); }, p); await page.waitForTimeout(400);
      return page.evaluate(() => ({ unter: (document.querySelector('#karte .unter') || {}).textContent || '', fakten: [...document.querySelectorAll('#karte .fakten li')].map(l => l.textContent) })); };
    if (x.kind >= 0) {
      const k = await oeffne(x.kind);
      await page.screenshot({ path: OUT + `${n}_kind_letzter_tag.png` });
      ok(/^6 Jahre · Kind, letzter Tag in der Kita /.test(k.unter) && k.fakten.some(t => /^heute zum letzten Mal in der Kita /.test(t)), `${n}: Kind am letzten Kita-Tag (Tag ${x.tag}): „${k.unter}“`);
    } else ok(true, `${n}: kein Kind am letzten Kita-Tag in 30 Tagen (nicht geprüft)`);
    const hk = await page.evaluate((b) => { const i = __stadt.Sim.gebaeudeInfo(__stadt.S(), b); return { zeile: i.zeile, mehr: i.mehr, kinder: (i.kinder || []).map(k => k.rolle) }; }, x.kita);
    ok(/^gehört der Stadt(, (1 Fachkraft|\d Fachkräfte) \(Bedarf \d\), Lohn \d+ Taler am Tag|; Fachkräfte stellt sie ein, sobald die Kita offen ist)$/.test(hk.zeile)
      && (x.kind < 0 || hk.kinder.some(r => / · letzter Tag$/.test(r))), `${n}: Hauskarte Kita „${hk.zeile}“; ${hk.mehr[0] ? hk.mehr[0].slice(0, 120) : ''}`);
    if (x.besitzer >= 0) { const k = await oeffne(x.besitzer); ok(k.fakten.some(t => /^Beitragsjahre: \d+ \(45 nötig\) · Rente ab 67 oder wenn der Betrieb schließt$/.test(t)), `${n}: Besitzer mit Anspruch: ${k.fakten.filter(t => /Beitrag/.test(t)).join(' | ')}`); }
    else ok(true, `${n}: kein Besitzer mit Anspruch vor 67 (nicht geprüft)`);
    if (x.angestellt >= 0) { const k = await oeffne(x.angestellt); ok(k.fakten.some(t => /^Beitragsjahre: \d+ \(45 nötig\) · darf ohne Abschlag in Rente$/.test(t)), `${n}: Angestellte mit Anspruch: ${k.fakten.filter(t => /Beitrag/.test(t)).join(' | ')}`); }
    else ok(true, `${n}: niemand angestellt mit Anspruch vor 67 (nicht geprüft)`);
    await ctx.close();
  }
  ok(!log.length, `Konsole ${log.join(' | ') || 'leer'}`);
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
