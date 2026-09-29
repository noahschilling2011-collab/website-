// Rathaus und Bürgermeister (Version 9) im Browser: Rathaus ab Tag 0 an der Mitte, kein Geister-Würfel (Befund der Gegenprüfung: Wände im
// Teil-Mesh, das Tech-Mesh bleibt leer), echter Klick (Raycast) auf Haus und Platz öffnet die Hauskarte (Bürgermeisteramt, Stadtregierung
// mit Knopf ins Fenster, Haushalt aus Sim.haushaltKurz), Leiste mit dem Bürgermeister zuerst (eigener Platz, Raute), Personenkarte,
// Stadtbuch an Tag 0, Fenster „Stadtregierung“ (Gruppe „Rathaus und Verwaltung“), Figuren nur zur Arbeitszeit auf dem Rathausplatz
// (Grundregel), Ausbaustufen im Bild, Draw Calls gegen stadt.orig.html (höchstens +3), Handy ohne seitliches Überlaufen, Konsole.
// Server: tests/alle.sh (PORT, Wurzel stadt/). Bilder: tests/ausgabe/bilder_befunde/rathaus_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, url, viewport) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  await U.fassungUnter(ctx, 'v8');   // stadt.orig.html = Version 8 (Git 31ce452) per git show, Vergleichsstand wie im Bau von Version 9
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
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
// Punkt (Feld x, y der Karte, Höhe h) auf den Bildschirm; die Kamera schaut von schräg vorn (Süden) aufs Gelände
async function blickAufs(ev, r) {
  await ev((r) => { const { G } = __stadt, S = __stadt.S(), x = (r[0] + r[2]) / 2 - S.mitte + 0.5, z = (r[1] + r[3]) / 2 - S.mitte + 0.5;
    G.controls.target.set(x, 0, z); G.camera.position.set(x + 1.5, 7, z + 6); G.controls.update(); G.camera.updateMatrixWorld(); }, r);
}
const aufSchirm = (ev, x, h, z) => ev(([x, h, z]) => { const { G } = __stadt, S = __stadt.S();
  const v = new G.THREE.Vector3(x - S.mitte + 0.5, h, z - S.mitte + 0.5).project(G.camera), c = G.renderer.domElement.getBoundingClientRect();
  return { x: c.left + (v.x + 1) / 2 * c.width, y: c.top + (1 - v.y) / 2 * c.height }; }, [x, h, z]);
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  // 1. Neue Stadt, Tag 1 (Seed 2): Rathaus an der Mitte, Bürgermeister gewählt
  const A = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=1&neu');
  const s = await A.ev(() => { const S = __stadt.S(), Sim = __stadt.Sim, i = Sim.rathausInfo(S), r = S.erweiterung.gelaende.find(q => q[4] === i.b);
    // Geister-Würfel: Instanzen des Tech-Meshes (Glasbau, Rohbau) mit der Einheitsmatrix bei (0, 0, 0), die niemand gesetzt hat
    const M = __stadt.G.M.tech, m4 = new __stadt.G.THREE.Matrix4(), eins = new __stadt.G.THREE.Matrix4();
    let geist = 0; for (let k = 0; k < M.count; k++) { M.getMatrixAt(k, m4); if (m4.equals(eins)) geist++; }
    return { geist, i: { b: i.b, stufe: i.stufe, offen: i.offen, name: i.name, bm: i.bm && i.bm.person && i.bm.person.name, wort: i.bm && i.bm.wort }, r, mitte: S.mitte,
      tor: [S.g.x[i.b], S.g.y[i.b]], techCount: M.count, buch: S.buch.filter(e => e.tag === 0).map(e => [e.art, Sim.klartext(e.text)]) }; });
  ok(s.i.b === 4 && s.i.offen && s.i.stufe === 1 && s.r && s.r[0] === s.mitte - 3 && s.r[2] === s.mitte + 3 && s.r[1] === s.mitte - 3 && s.r[3] === s.mitte - 1 && s.tor[0] === s.mitte && s.tor[1] === s.mitte - 1,
    `Rathaus (Gebäude ${s.i.b}, ${s.i.name}) auf 7 × 3 Feldern nördlich der Hauptstraße, Tor an der Mitte; ${s.i.wort}: ${s.i.bm}`);
  ok(s.geist === 0, `kein Geister-Würfel: ${s.geist} von ${s.techCount} Instanzen des Tech-Meshes mit der Einheitsmatrix (Befund der Gegenprüfung)`);
  ok(s.buch.some(([a, t]) => a === 'rathaus' && /Das Rathaus steht in der Mitte/.test(t)) && s.buch.some(([a, t]) => a === 'wahl' && /Erste Bürgermeisterwahl/.test(t) && /Amtsantritt heute/.test(t) && /parteilos/.test(t)),
    `Stadtbuch an Tag 0: ${s.buch.map(([a]) => a).join(', ')}; „${(s.buch.find(([a]) => a === 'wahl') || ['', '–'])[1].slice(0, 140)}…“`);
  await blickAufs(A.ev, s.r);
  await A.page.waitForTimeout(700);
  await A.page.screenshot({ path: BILD + 'rathaus_dorf_tag1.png' });
  // Echter Klick (Raycast) aufs Haus (hinten auf dem Gelände) und auf den Platz vor dem Tor (dort stand der Geister-Würfel)
  const klick = async (x, h, z) => {
    await A.page.keyboard.press('Escape'); await A.zu();
    const p = await aufSchirm(A.ev, x, h, z);
    await A.page.mouse.click(p.x, p.y); await A.page.waitForTimeout(500);
    return A.ev(() => ({ offen: !document.getElementById('karte').hidden, titel: (document.querySelector('#karte h2') || {}).textContent || '', text: document.getElementById('karte-inhalt').innerText }));
  };
  const kHaus = await klick(s.mitte, 0.4, s.mitte - 2.6), kPlatz = await klick(s.mitte + 0.3, 0.02, s.mitte - 1.2);
  ok(kHaus.offen && /^Rathaus /.test(kHaus.titel) && kPlatz.offen && /^Rathaus /.test(kPlatz.titel), `Klick aufs Haus: „${kHaus.titel}“; Klick auf den Platz vor dem Tor: „${kPlatz.titel}“`);
  const k = kPlatz.text;
  // Überschriften stehen in innerText in Großbuchstaben (text-transform): deshalb ohne Groß- und Kleinschreibung
  ok(/^bürgermeisteramt$/im.test(k) && /direkt gewählt und parteilos/.test(k) && /^stadtregierung$/im.test(k) && /Fenster „Stadtregierung“ ›/.test(k) && /^haushalt$/im.test(k) && /Budget heute/.test(k)
    && /Stellen der Verwaltung: 1\d Einwohner mal 4,7 je 1\.000/.test(k) && /die nächste freie oder eine besser bezahlte/.test(k) && /Hier arbeiten|Verwaltungsangestellte|Bürgermeister/.test(k),
    'Hauskarte: Bürgermeisteramt (direkt gewählt, parteilos), Stadtregierung mit Knopf, Haushalt, Rechnung der Stellen, Stellenvergabe wie im Fenster'
    + (/direkt gewählt und parteilos/.test(k) && /Budget heute/.test(k) ? '' : '\n  ' + k.slice(0, 900).replace(/\n+/g, ' | ')));
  await A.page.screenshot({ path: BILD + 'rathaus_karte_breit.png' });
  // Seit Version 9, Teil 3 gibt es das Fenster „Haushalt“ (fenster true, Satz der Lohnsteuer; die Zeilen ergeben zusammen den Saldo von gestern)
  const hh = await A.ev(() => { const h = __stadt.Sim.haushaltKurz(__stadt.S()); return { ...h, knopf: !!document.querySelector('#karte-inhalt button[data-haushalt]') }; });
  ok(hh && typeof hh.budget === 'number' && hh.stand === 'gestern' && Array.isArray(hh.zeilen) && hh.fenster === true && typeof hh.satz === 'number' && hh.knopf
    && Math.abs(hh.zeilen.reduce((x, z) => x + z[1], 0) - hh.saldo) < 1,
    `Schnittstelle haushaltKurz: { budget ${Math.round(hh.budget)}, stand ${hh.stand}, ${hh.zeilen.length} Zeile(n), saldo ${Math.round(hh.saldo)}, fenster ${hh.fenster}, satz ${hh.satz} }, Knopf ins Fenster „Haushalt“ ${hh.knopf}`);
  // Knopf in der Hauskarte öffnet das Fenster „Stadtregierung“; dort die Gruppe „Rathaus und Verwaltung“
  await A.page.click('#karte-inhalt button[data-regierung]'); await A.page.waitForTimeout(500);
  const f = await A.ev(() => { const d = document.getElementById('regierung-dialog') || document.querySelector('dialog[open]'), box = document.getElementById('regierung-inhalt');
    const gs = [...box.querySelectorAll('.reg-gruppe')], g = gs.find(x => x.textContent.includes('Rathaus und Verwaltung')), g2 = gs[gs.indexOf(g) + 1];
    const karten = [...box.querySelectorAll('.reg-karte')].filter(k => g && (g.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_FOLLOWING) && (!g2 || (g2.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_PRECEDING)));
    const dr = d ? d.getBoundingClientRect() : null, gr = g ? g.getBoundingClientRect() : null;
    return { offen: !!(d && d.open), gruppe: !!g, sichtbar: !!(dr && gr && gr.top >= dr.top && gr.bottom <= dr.bottom), fokus: document.activeElement === g, karten: karten.map(k => ({ titel: k.querySelector('h4 span').textContent, live: (k.querySelector('p.reg-live') || { textContent: '' }).textContent, text: k.textContent })) }; });
  const bmK = f.karten.find(x => /Bürgermeister/.test(x.titel));
  ok(f.offen && f.gruppe && f.sichtbar && f.fokus && f.karten.length === 6 && bmK && /parteilos|ohne Partei/.test(bmK.text) && /Regeln der Stadtregierung/.test(bmK.text) && /Im Amt:/.test(bmK.live)
    && f.karten.some(x => /keine Stellenzahl im Programm/.test(x.titel)),
    `Knopf öffnet das Fenster bei der Gruppe (sichtbar ${f.sichtbar}, Fokus ${f.fokus}); „Rathaus und Verwaltung“ mit ${f.karten.length} Karten (${f.karten.map(x => x.titel).join('; ')}); live: „${bmK ? bmK.live.slice(0, 90) : '–'}“`);
  await A.page.screenshot({ path: BILD + 'rathaus_fenster.png' });
  await A.page.keyboard.press('Escape'); await A.zu();
  // Leiste: zuerst der Bürgermeister (eigener Platz), dann die 5 Hauptfiguren; Personenkarte
  const l = await A.ev(() => { const z = [...document.querySelectorAll('#haupt-liste .haupt-zeile')];
    return { n: z.length, erst: z[0] ? { amt: !!z[0].querySelector('.kreis.amt'), text: (z[0].querySelector('.amt-text') || {}).textContent || '', p: +z[0].dataset.p } : null,
      bm: __stadt.S().buergermeister.p, haupt: __stadt.S().ki.haupt.length }; });
  ok(l.n === 6 && l.haupt === 5 && l.erst && l.erst.amt && /Bürgermeister/.test(l.erst.text) && l.erst.p === l.bm, `Leiste: ${l.n} Zeilen, zuerst ${l.erst && l.erst.text} (doppelter Rand), dazu ${l.haupt} Hauptfiguren`);
  await A.page.click('#haupt-liste .haupt-zeile'); await A.page.waitForTimeout(400);
  const pk = await A.ev(() => document.getElementById('karte-inhalt').innerText);
  // wie jede Hauptfigur: Tagebuch zuerst und das Feld fürs Gespräch mit Noah (hier gesperrt: die KI ist im Test nicht erreichbar)
  const tb = await A.ev(() => ({ h3: (document.querySelector('#karte h3') || {}).textContent || '', feld: !!document.getElementById('sagen-text') }));
  ok(tb.h3 === 'Tagebuch' && tb.feld, `Karte des Bürgermeisters: Tagebuch zuerst, Gesprächsfeld da (${JSON.stringify(tb)})`);
  ok(/Bürgermeister(in)? · Hauptfigur/.test(pk) && /seit Tag 0, gewählt mit \d+ von \d+ Stimmen, parteilos; Amtszeit bis Tag 70/.test(pk) && /im Rathaus/.test(pk) && /Auch nach der Amtszeit Hauptfigur/.test(pk),
    `Personenkarte: „${(pk.match(/Bürgermeister(in)? seit[^\n]*/) || ['–'])[0]}“`);
  await A.page.screenshot({ path: BILD + 'rathaus_bm_karte.png' });
  await A.page.keyboard.press('Escape'); await A.zu();
  // Figuren (Grundregel): Wer zur Arbeitszeit auf dem Gelände steht, arbeitet im Rathaus; abends und nachts steht dort niemand
  const fig = [], fehl = [];
  for (const H of [8, 10, 12, 16, 20, 23, 3]) {
    const r = await A.ev(([H, g]) => {
      const a = __stadt, S = a.S(), T = a.G.test, P = S.p, Sim = a.Sim, fehl = [];
      let n = 0; while (S.stunde !== H && n++ < 30) a.schritt();
      a.nachSchritten(); a.G.figurenBewegen(S.tag * 24 + H + 0.5);
      const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), x0 = g[0] - S.mitte, x1 = g[2] - S.mitte + 1, z0 = g[1] - S.mitte, z1 = g[3] - S.mitte + 1;
      let drauf = 0;
      for (let i = 0; i < T.figuren.length; i++) {
        const p = T.figIds[i]; if (p < 0) continue;
        a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4);
        const f = T.figuren[i], jetzt = S.tag * 24 + H + 0.5, ro = f.route;
        const unterwegs = ro && ((jetzt >= f.start && jetzt < f.start + f.dauer && ro.len > 0) || (jetzt < f.start && f.start - jetzt < 1));
        const auf = v.x > x0 + 0.05 && v.x < x1 - 0.05 && v.z > z0 + 0.05 && v.z < z1 - 0.8 && v.y > -1;   // ohne die Reihe am Tor (Gehweg davor)
        if (auf && f.steht && !unterwegs) { drauf++; if (P.arbeit[p] !== S.rathaus.b || H < 8 || H >= 17) fehl.push(`${H} Uhr: ${Sim.name(S, p)} steht auf dem Rathausplatz`); }
      }
      return { H, drauf, da: S.belegschaft[S.rathaus.b].length, fehl };
    }, [H, s.r]);
    fig.push(`${r.H}:${r.drauf}/${r.da}`); fehl.push(...r.fehl);
  }
  ok(!fehl.length && fig.some(x => /^(8|10|12|16):[1-9]/.test(x)) && fig.filter(x => /^(20|23|3):/.test(x)).every(x => /:0\//.test(x)),
    `Figuren auf dem Rathausplatz (Stunde:stehend/Belegschaft) ${fig.join(' ')}` + (fehl.length ? '\n  ' + fehl.slice(0, 5).join('\n  ') : ''));
  await A.ev(() => { const a = __stadt, S = a.S(); let n = 0; while (S.stunde !== 22 && n++ < 30) a.schritt(); a.nachSchritten(); });
  await blickAufs(A.ev, s.r); await A.page.waitForTimeout(700);
  await A.page.screenshot({ path: BILD + 'rathaus_dorf_nacht.png' });
  console.log('Konsole (Tag 1):', A.log.length ? '\n  ' + A.log.join('\n  ') : 'leer');
  if (A.log.length) process.exitCode = 1;
  await A.ctx.close();

  // 2. Ausbaustufen im Bild und Draw Calls gegen stadt.orig.html (Seed 2, Tag 1, 200 und 400)
  const dc = [];
  for (const tage of [1, 200, 400]) {
    const werte = {};
    for (const [n, datei] of [['neu', 'stadt.html'], ['orig', 'stadt.orig.html']]) {
      const X = await seite(b, `${U.HOST}/${datei}?debug&seed=2&tage=${tage}&neu`);
      await X.ev(() => { const a = __stadt, S = a.S(); let n = 0; while (S.stunde !== 11 && n++ < 30) a.schritt(); a.nachSchritten(); a.G.ausrichten(); });
      await X.page.waitForTimeout(600); await X.zu();
      werte[n] = await X.ev(() => { const G = __stadt.G, c = G.render().calls, M = G.M.tech, m4 = new G.THREE.Matrix4(), eins = new G.THREE.Matrix4();
        let geist = 0; for (let k = 0; k < M.count; k++) { M.getMatrixAt(k, m4); if (m4.equals(eins)) geist++; }
        return { c, geist, st: __stadt.S().rathaus ? __stadt.Sim.rathausInfo(__stadt.S()) : null }; });
      if (n === 'neu') {
        const r = await X.ev(() => { const S = __stadt.S(); return S.erweiterung.gelaende.find(q => q[4] === S.rathaus.b); });
        await blickAufs(X.ev, r); await X.page.waitForTimeout(600); await X.zu();
        await X.page.screenshot({ path: BILD + `rathaus_tag${tage}.png` });
        werte.name = werte.neu.st.name; werte.stufe = werte.neu.st.stufe;
      }
      if (X.log.length) { console.log(`Konsole (${datei}, Tag ${tage}):\n  ` + X.log.join('\n  ')); process.exitCode = 1; }
      await X.ctx.close();
    }
    dc.push(`Tag ${tage}: ${werte.neu.c} statt ${werte.orig.c} (${werte.name})`);
    ok(werte.neu.c <= werte.orig.c + 3 && werte.neu.c <= 32 && werte.neu.geist === 0, `Draw Calls Tag ${tage}: ${werte.neu.c} (stadt.orig.html ${werte.orig.c}, höchstens +3 und ≤ 32); ${werte.name}, Ausbaustufe ${werte.stufe}; Geister-Würfel ${werte.neu.geist}`);
  }

  // 3. Handy 400 × 820: Hauskarte ohne seitliches Überlaufen
  const H = await seite(b, U.HOST + '/stadt.html?debug&seed=2&tage=200&neu', { width: 400, height: 820 });
  const hk = await H.ev(() => { const S = __stadt.S(), k = document.createElement('button'); k.className = 'haus'; k.dataset.b = S.rathaus.b; document.body.append(k); k.click(); k.remove();
    const karte = document.getElementById('karte'), el = [...karte.querySelectorAll('*')];
    return { offen: !karte.hidden, breit: document.documentElement.scrollWidth, fenster: innerWidth, zuBreit: el.filter(e => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflowX !== 'visible' && getComputedStyle(e).overflowX !== 'hidden').length,
      titel: (karte.querySelector('h2') || {}).textContent }; });
  await H.page.waitForTimeout(400);
  await H.page.screenshot({ path: BILD + 'rathaus_karte_handy.png' });
  ok(hk.offen && /^Rathaus /.test(hk.titel) && hk.breit <= hk.fenster && !hk.zuBreit, `Handy 400 × 820: „${hk.titel}“, Seite ${hk.breit} px breit (Fenster ${hk.fenster}), ${hk.zuBreit} Elemente mit seitlichem Scrollen`);
  if (H.log.length) { console.log('Konsole (Handy):\n  ' + H.log.join('\n  ')); process.exitCode = 1; }
  await H.ctx.close();
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
