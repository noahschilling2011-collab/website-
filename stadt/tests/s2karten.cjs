// Schritt 2 im Browser: Fenster „Stadtregierung“ (neue Karten mit Zitaten als Text, Live-Zahlen), Personenkarte (gekaufte Wohnung,
// Rente bzw. Beitragsjahre, Frührentner „in Rente“), Hauskarte (Eigentum), Konsole leer. Teststadt Seed 2, Tag 420. Bilder nach tests/ausgabe/bilder_s2/.
const U = require('./umgebung.cjs');
const { chromium } = U;
const OUT = U.ordner('bilder_s2');
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [w, h, n] of [[1280, 800, 'breit'], [400, 820, 'handy']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h } });
    await U.three(ctx);
    await ctx.route('http://localhost:11434/**', (r) => r.abort());
    const page = await ctx.newPage(), log = [];
    page.on('pageerror', e => log.push('pageerror: ' + e.message));
    page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) log.push('error: ' + m.text()); });
    await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=420&neu', { timeout: 600000 });
    await page.waitForFunction(() => globalThis.__stadt, null, { timeout: 600000 });
    const zu = () => page.evaluate(() => { const a = __stadt, S = a.S(); a.setzeTempo(0); while (S.ki.verlust.length) a.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
    await zu(); await page.waitForTimeout(800); await zu();
    // Fenster Stadtregierung: neue Karten da, Zitate als Text, Live-Zahlen mit Zahlen
    await page.click('#regierung-knopf'); await page.waitForTimeout(500);
    const r = await page.evaluate(() => {
      const karten = [...document.querySelectorAll('#regierung-inhalt .reg-karte')];
      const k = (t) => karten.find(x => x.querySelector('h4').textContent.startsWith(t));
      const info = (t) => { const x = k(t); return x ? { zitate: [...x.querySelectorAll('.reg-zitat')].map(q => q.textContent), live: (x.querySelector('p.reg-live') || {}).textContent || '', html: x.querySelectorAll('img,script,iframe').length } : null; };
      return { mk: info('Mieter kaufen ihre Wohnung'), re: info('Rente ohne Abschlag'), fb: info('23 Taler mehr steuerfrei'), rk: info('Rente aus der Rentenkasse'),
        nicht: [...document.querySelectorAll('#regierung-inhalt .reg-auf summary')].map(s => s.textContent),
        text: document.getElementById('regierung-inhalt').textContent };
    });
    ok(r.mk && r.mk.zitate.length === 2 && /S\. 37$/.test(r.mk.zitate[0]) && /^\d[\d.]* von [\d.]+ Haushalten wohnen in der eigenen Wohnung/.test(r.mk.live),
      `${n}: Karte Mieterkauf, Zitate ${r.mk && r.mk.zitate.length}, live „${r.mk && r.mk.live.slice(0, 120)}…“`);
    ok(r.re && r.re.zitate.length === 2 && /^Heute \d+ vor 67 in Rente/.test(r.re.live), `${n}: Karte Rente nach 45 Beitragsjahren, live „${r.re && r.re.live}“`);
    ok(r.fb && r.fb.zitate.length === 2 && /Rentner/.test(r.fb.live), `${n}: Karte Rentner-Freibetrag, live „${r.fb && r.fb.live}“`);
    ok(r.rk && /bekommen Rente/.test(r.rk.live), `${n}: Rentenkasse „${r.rk && r.rk.live}“`);
    ok(!/folgt in einem zweiten Schritt/.test(r.text) && !/Ab 67 ist in der Stadt niemand mehr angestellt/.test(r.text), `${n}: keine veralteten Sätze (zweiter Schritt, niemand ab 67 angestellt)`);
    await page.screenshot({ path: OUT + `${n}_panel_oben.png` });
    for (const [t, datei] of [['Rente ohne Abschlag', 'rente'], ['Mieter kaufen ihre Wohnung', 'kauf']]) {
      await page.evaluate((t) => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => x.querySelector('h4').textContent.startsWith(t)); k.scrollIntoView({ block: 'start' }); }, t);
      await page.waitForTimeout(300);
      await page.screenshot({ path: OUT + `${n}_panel_${datei}.png` });
    }
    await page.keyboard.press('Escape'); await page.waitForTimeout(300); await zu();
    // Personenkarten: Eigentümer mit Rest, Frührentner (vor 67 in Rente), Rentner mit Stelle; Hauskarte mit Eigentum
    const wer = await page.evaluate(() => {
      const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, J = Sim.R.JAHR;
      let eig = -1, frueh = -1, arbR = -1, jung = -1;
      for (let p = 0; p < S.pMax; p++) {
        if (!P.lebt[p]) continue; const al = S.tag - P.geb[p];
        if (eig < 0 && Sim.eigentuemer(S, p) && P.schuld[p] > 0) eig = p;
        if (frueh < 0 && al < 670 && Sim.rentner(S, p)) frueh = p;
        if (arbR < 0 && al >= 670 && P.arbeit[p] >= 0 && P.besitz[p] < 0) arbR = p;
        if (jung < 0 && al >= 250 && al < 400 && P.arbeit[p] >= 0) jung = p;
      }
      return { eig, frueh, arbR, jung };
    });
    const karte = async (p, datei) => {
      if (p < 0) return null;
      await page.evaluate((p) => { const a = __stadt, S = a.S(); document.dispatchEvent(new CustomEvent('x')); }, p);
      await page.evaluate((p) => { const a = __stadt, S = a.S(); const btn = document.createElement('button'); btn.className = 'name'; btn.dataset.p = p; btn.dataset.g = S.p.gen[p]; btn.dataset.n = a.Sim.name(S, p);
        document.getElementById('buch-liste').append(btn); btn.click(); btn.remove(); }, p);
      await page.waitForTimeout(400);
      const t = await page.evaluate(() => ({ unter: (document.querySelector('#karte .unter') || {}).textContent, fakten: [...document.querySelectorAll('#karte .fakten li')].map(l => l.textContent), leben: [...document.querySelectorAll('#karte .lebenslauf li')].map(l => l.textContent).slice(-2) }));
      await page.screenshot({ path: OUT + `${n}_karte_${datei}.png` });
      return t;
    };
    const e = await karte(wer.eig, 'eigentum');
    ok(e && e.fakten.some(f => /^wohnt in der eigenen Wohnung .*\(gekauft für [\d.]+ Taler, noch [\d.]+ abzuzahlen\)/.test(f)) && e.fakten.some(f => /^Beitragsjahre: \d+ (von 45|\(45 nötig\))|^Rente: /.test(f)),
      `${n}: Personenkarte Eigentum: ${e && e.fakten.filter(f => /wohnt|Beitrags|Rente/.test(f)).join(' | ')}`);
    const f = await karte(wer.frueh, 'fruehrente');
    ok(!f || (/· in Rente/.test(f.unter) && f.fakten.some(x => /^Rente: \d+ Taler am Tag \(\d+ Beitragsjahre\)/.test(x))), `${n}: Frührentner: ${f ? f.unter + ' | ' + f.fakten.filter(x => /Rente/.test(x)).join(' | ') + ' | ' + f.leben.join(' / ') : 'keiner gefunden'}`);
    const r2 = await karte(wer.arbR, 'rentner_mit_stelle');
    ok(!r2 || (/arbeitet als/.test(r2.unter) && r2.fakten.some(x => /^Rente: /.test(x))), `${n}: Rentner mit Stelle: ${r2 ? r2.unter + ' | ' + r2.fakten.filter(x => /Rente/.test(x)).join(' | ') : 'keiner gefunden'}`);
    const j = await karte(wer.jung, 'jung');
    ok(j && j.fakten.some(x => /^Beitragsjahre: \d+ von 45$/.test(x)), `${n}: Jüngere Angestellte: ${j && j.fakten.filter(x => /Beitrags/.test(x)).join(' | ')}`);
    // Hauskarte über den Wohnungsknopf der Eigentümer-Karte
    await karte(wer.eig, 'eigentum');
    const knoepfe = await page.$$('#karte button.haus'); await knoepfe[knoepfe.length - 1].click(); await page.waitForTimeout(400);
    const hk = await page.evaluate(() => ({ unter: (document.querySelector('#karte .unter') || {}).textContent, liste: [...document.querySelectorAll('#karte .personenliste li')].map(l => l.textContent) }));
    await page.screenshot({ path: OUT + `${n}_hauskarte.png` });
    ok(/gehör(t|en) ihren Bewohnern\. Kaufpreis je Wohnung \d\.\d{3} Taler/.test(hk.unter) && hk.liste.some(l => /· Eigentum$/.test(l)), `${n}: Hauskarte „${hk.unter}“, ${hk.liste.filter(l => /Eigentum/.test(l)).length} mit „· Eigentum“`);
    ok(!log.length, `${n}: Konsole ${log.join(' | ') || 'leer'}`);
    await ctx.close();
  }
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
