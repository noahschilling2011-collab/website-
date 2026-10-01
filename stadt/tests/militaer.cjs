// Bund (Version 7, Teil 3) im Browser: Kaserne und Dienststelle auf eigenem Gelände (Klick aufs Gelände öffnet die Hauskarte), Soldaten und
// Wehrdienst zur Arbeitszeit in Oliv auf dem Antreteplatz, nur wer dort arbeitet (Grundregel), Personenkarten (Soldat mit Verpflichtung,
// Wehrdienst, Ersatzdienst), Fenster „Stadtregierung“ (Gruppe Bund, Geld vom Bund), Hilfe, Draw Calls (+1), Warnlichter (nachts im Takt,
// reduziert stetig), nichts bewegt sich von selbst (Puffer ändert sich nur mit dem Schlüssel), Konsole.
// Server: tests/alle.sh (PORT, Wurzel stadt/); Bilder: tests/ausgabe/bilder_befunde/
const U = require('./umgebung.cjs');
const { chromium } = U;
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, reduziert) {
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, reducedMotion: reduziert ? 'reduce' : 'no-preference' });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=400&neu', { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await page.evaluate(() => __stadt.setzeTempo(0));
  return { page, log };
}
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const { page, log } = await seite(b, false);
  const ev = (f, a) => page.evaluate(f, a);
  const zu = async () => { for (let i = 0; i < 30; i++) {
    const o = await ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
      for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
    await page.waitForTimeout(100); if (!o) break; } };
  await zu();
  const s = await ev(() => {
    const S = __stadt.S(), Sim = __stadt.Sim, i = Sim.bundInfo(S), gel = (b) => S.erweiterung.gelaende.find(r => r[4] === b);
    return { k: i.kaserne, d: i.dienst, gk: gel(i.kaserne), gd: gel(i.dienst), offen: [i.kaserneOffen, i.dienstOffen], soldaten: i.soldaten, wehr: i.wehr, ersatz: i.ersatz, verpflichtet: i.verpflichtet };
  });
  const flaeche = (r) => r ? (r[2] - r[0] + 1) * (r[3] - r[1] + 1) : 0;
  ok(s.gk && s.gd && flaeche(s.gk) === 77 && flaeche(s.gd) === 9 && s.offen.every(Boolean),
    `Kaserne (Gelände ${s.gk && s.gk.slice(0, 4)}, ${flaeche(s.gk)} Felder) und Dienststelle (${s.gd && s.gd.slice(0, 4)}, ${flaeche(s.gd)} Felder) offen; ${s.soldaten} Soldaten, ${s.wehr} im Wehr-, ${s.ersatz} im Ersatzdienst`);
  // Kamera auf die Kaserne (Arbeitsplätze werden nach Nähe zur Kamera vergeben), dann Stunde für Stunde 6–18 Uhr: wer auf dem Gelände steht,
  // arbeitet dort (Grundregel); Soldaten und Wehrdienst in Oliv auf dem Antreteplatz, Zivil nicht in Oliv
  await ev((r) => { const { G } = __stadt, S = __stadt.S(), x = (r[0] + r[2]) / 2 - S.mitte + 0.5, z = (r[1] + r[3]) / 2 - S.mitte + 0.5;
    G.controls.target.set(x, 0, z); G.camera.position.set(x + 6, 9, z + 7); G.controls.update(); }, s.gk);
  const je = [], fehl = [];
  for (let H = 6; H <= 18; H += 2) {
    const r = await ev(([H, gk]) => {
      const a = __stadt, S = a.S(), T = a.G.test, Sim = a.Sim, P = S.p;
      while (S.stunde !== H) a.schritt();
      a.nachSchritten();
      a.G.figurenBewegen(S.tag * 24 + H + 0.5);
      const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), c = new a.G.THREE.Color(), oliv = new a.G.THREE.Color('#6f7a45'), fehl = [];
      const x0 = gk[0] - S.mitte, x1 = gk[2] - S.mitte + 1, z0 = gk[1] - S.mitte, z1 = gk[3] - S.mitte + 1;
      let drauf = 0, inOliv = 0;
      for (let i = 0; i < T.figuren.length; i++) {
        const p = T.figIds[i]; if (p < 0) continue;
        a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4);
        const f = T.figuren[i], jetzt = S.tag * 24 + H + 0.5, r = f.route;
        const unterwegs = r && ((jetzt >= f.start && jetzt < f.start + f.dauer && r.len > 0) || (jetzt < f.start && f.start - jetzt < 1));   // geht oder wartet noch am alten Platz
        const steht = f.steht && !unterwegs;
        const aufGelaende = v.x > x0 + 0.05 && v.x < x1 - 0.05 && v.z > z0 + 0.05 && v.z < z1 - 0.05 && v.y > -1;
        a.G.figMesh.getColorAt(i, c);
        const istOliv = Math.abs(c.r - oliv.r) + Math.abs(c.g - oliv.g) + Math.abs(c.b - oliv.b) < 0.02;
        const dort = P.arbeit[p] === S.bund.kaserne, soldat = dort && P.bund[p] !== Sim.ZIVIL;
        if (aufGelaende && steht) { drauf++; if (!dort && !Sim.istHaupt(S, p)) fehl.push(`${H} Uhr: ${Sim.name(S, p)} steht auf dem Gelände, arbeitet aber nicht dort`); }
        if (istOliv) { inOliv++; if (!soldat) fehl.push(`${H} Uhr: ${Sim.name(S, p)} in Oliv, ist aber kein Soldat und nicht im Wehrdienst`); }
        if (soldat && !Sim.istHaupt(S, p) && !istOliv) fehl.push(`${H} Uhr: ${Sim.name(S, p)} (Bundeswehr) nicht in Oliv`);
        if (istOliv && steht && !aufGelaende) fehl.push(`${H} Uhr: ${Sim.name(S, p)} steht in Oliv außerhalb der Kaserne`);
      }
      return { H, drauf, inOliv, fehl };
    }, [H, s.gk]);
    je.push(`${r.H}:${r.drauf}/${r.inOliv}`); fehl.push(...r.fehl);
  }
  ok(!fehl.length && je.some(x => !/:0\//.test(x)), `Kaserne: auf dem Gelände stehen nur Leute, die dort arbeiten; Soldaten und Wehrdienst in Oliv (Stunde:stehend/oliv ${je.join(' ')})`
    + (fehl.length ? '\n  ' + fehl.slice(0, 5).join('\n  ') : ''));
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'militaer_18uhr.png' });
  // Klick aufs Gelände (nicht das Torfeld) öffnet die Hauskarte
  const klick = async (r, h) => {
    await zu();
    const pkt = await ev(([r, h]) => { const { G } = __stadt, S = __stadt.S(), x = (r[0] + r[2]) / 2 - S.mitte + 0.5, z = (r[1] + r[3]) / 2 - S.mitte + 0.5;
      G.controls.target.set(x, 0, z); G.camera.position.set(x + 2, 16, z + 9); G.controls.update(); G.camera.updateMatrixWorld();
      const v = new G.THREE.Vector3(x, h, z).project(G.camera), c = G.renderer.domElement.getBoundingClientRect();
      return { x: c.left + (v.x + 1) / 2 * c.width, y: c.top + (1 - v.y) / 2 * c.height }; }, [r, h]);
    await page.waitForTimeout(300);
    await page.mouse.click(pkt.x, pkt.y);
    await page.waitForTimeout(500);
    return ev(() => ({ offen: !document.getElementById('karte').hidden, text: document.getElementById('karte-inhalt').innerText }));
  };
  const kk = await klick(s.gk, 0.05);
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'militaer_kaserne_karte.png' });
  const kd = await klick(s.gd, 0.3);
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'militaer_dienststelle_karte.png' });
  ok(kk.offen && /Kaserne der Bundeswehr an der/.test(kk.text) && kk.text.includes('gehört dem Bund') && kk.text.includes('Keine Stadt hat eigenes Militär')
    && /Lohn \d+ Taler am Tag vom Bund/.test(kk.text) && kk.text.includes('stehen still'), 'Klick aufs Gelände der Kaserne: „' + kk.text.split('\n').slice(0, 3).join(' | ') + '…“');
  // Ort wie ortVon: „an der …“, „am …weg“ oder „in der …gasse“ (seit Version 9, Teil 5 steht die Dienststelle der Teststadt am Mühlenweg)
  ok(kd.offen && /Dienststelle des Bundesnachrichtendienstes (an der|am|in der) \S/.test(kd.text) && kd.text.includes('überwacht niemand') && kd.text.includes('Ausland'),
    'Klick auf die Dienststelle: „' + kd.text.split('\n').slice(0, 3).join(' | ') + '…“');
  // Personenkarten: Soldat mit Verpflichtung, Wehrdienst, Ersatzdienst (erster Tag ab jetzt, an dem es alle drei um 10 Uhr gibt). Version 10
  // (Etappe 2): Die Teststadt läuft anders; wer am Abend von Tag 400 im Wehrdienst ist, ist am nächsten Morgen fertig (5 Diensttage). Gesucht
  // wird darum um 10 Uhr, der Stunde der Karten (vorher erst am Abend gesucht, dann bis 10 Uhr weiter; in Node mit ml/e2bau/werkzeug/s4_militaer.mjs:
  // um 10 Uhr alle drei zuerst wieder an Tag 407)
  const leute = await ev(() => {
    const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p;
    const such = () => { const w = { soldat: -1, wehr: -1, ersatz: -1 };
      for (let p = 0; p < S.pMax; p++) { if (!P.lebt[p] || Sim.istHaupt(S, p)) continue;
        if (w.soldat < 0 && Sim.verpflichtet(S, p)) w.soldat = p; if (w.wehr < 0 && P.bund[p] === Sim.WEHRDIENST) w.wehr = p; if (w.ersatz < 0 && P.bund[p] === Sim.ERSATZDIENST) w.ersatz = p; }
      return w; };
    let w = { soldat: -1, wehr: -1, ersatz: -1 };
    for (let d = 0; d < 40; d++) {
      while (S.stunde !== 10) a.schritt();
      w = such();
      if (w.soldat >= 0 && w.wehr >= 0 && w.ersatz >= 0) break;
      a.schritt();
    }
    a.nachSchritten();
    return { ...w, tag: S.tag };
  });
  const karte = (id) => ev((id) => { const S = __stadt.S(), k = document.createElement('button');
    k.className = 'name'; k.dataset.p = id; k.dataset.g = S.p.gen[id]; k.dataset.n = __stadt.Sim.name(S, id);
    document.body.append(k); k.click(); k.remove(); return document.getElementById('karte-inhalt').innerText; }, id);
  const ks = leute.soldat >= 0 ? await karte(leute.soldat) : '', kw = leute.wehr >= 0 ? await karte(leute.wehr) : '', ke = leute.ersatz >= 0 ? await karte(leute.ersatz) : '';
  ok(/arbeitet als Soldat(in)? in der Kaserne der Bundeswehr .*verpflichtet bis Tag \d+/.test(ks), `Soldat auf Zeit: „${(ks.match(/arbeitet als Soldat[^\n]*/) || ['–'])[0]}“`);
  ok(/leistet Wehrdienst in der Kaserne der Bundeswehr .* bis Tag \d+ \(60 Taler Sold am Tag vom Bund\)/.test(kw), `Wehrdienst: „${(kw.match(/leistet Wehrdienst[^\n]*/) || ['–'])[0]}“`);
  ok(/leistet Ersatzdienst beim Bauhof .* bis Tag \d+/.test(ke) && /Heute: (keine Baustelle frei, Landschaftspflege für die Stadt|.*Baustelle)/.test(ke) && !/Kisten/.test((ke.match(/Heute:[^\n]*/) || [''])[0]),
    `Ersatzdienst: „${(ke.match(/leistet Ersatzdienst[^\n]*/) || ['–'])[0]}“, „${(ke.match(/Heute:[^\n]*/) || ['–'])[0]}“`);
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'militaer_ersatzdienst_karte.png' });
  await page.keyboard.press('Escape');
  // Fenster „Stadtregierung“: Gruppe „Bund in der Stadt“ mit drei Karten (Zitate, Zahlen), Geld vom Bund
  await zu();
  await page.click('#regierung-knopf'); await page.waitForTimeout(400);
  const f = await ev(() => { const box = document.getElementById('regierung-inhalt'), gs = [...box.querySelectorAll('.reg-gruppe')], g = gs.find(x => x.textContent.includes('Bund in der Stadt')), g2 = gs[gs.indexOf(g) + 1];
    const karten = [...box.querySelectorAll('.reg-karte')].filter(k => g && (g.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_FOLLOWING) && (!g2 || (g2.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_PRECEDING)));
    const dts = [...box.querySelectorAll('dl.zahlen dt')].map(d => d.textContent), dds = [...box.querySelectorAll('dl.zahlen dd')].map(d => d.textContent);
    return { gruppe: !!g, karten: karten.map(k => ({ titel: k.querySelector('h4 span').textContent, zitate: k.querySelectorAll('blockquote, .reg-zitat').length, live: (k.querySelector('p.reg-live') || { textContent: null }).textContent,
      mehr: !!k.querySelector('details.reg-mehr'), text: k.textContent })), bund: dts.map((t, i) => [t, dds[i]]).filter(([t]) => t.startsWith('Bund für Kaserne')), alles: box.textContent }; });
  const [fk, fw, fd] = f.karten;
  ok(f.gruppe && f.karten.length === 3 && f.karten.every(k => k.live && k.live.length > 20 && k.zitate >= 2 && k.mehr) && f.bund.length === 2 && f.bund.every(([, v]) => /Taler|ab morgen/.test(v)),
    `Fenster: Gruppe „Bund in der Stadt“ mit ${f.karten.length} Karten (${f.karten.map(k => k.titel).join('; ')}), alle mit Zitaten und Zahlen; ${f.bund.map(x => x.join(': ')).join(', ')}`);
  ok(fw && /deutsche Staatsbürger/.test(fw.text) && /nur Männer/.test(fw.text) && /Art\. 12a Abs\. 1 GG/.test(fw.text) && /Abweichung/.test(fw.text) && /§ 3 Nr\. 5 Buchst\. a EStG/.test(fw.text)
    && /Programm \(S\. 88\) und geltendes Recht beschränken den Dienst auf Deutsche/.test(fw.text) && /§ 1 Abs\. 1 WPflG/.test(fw.text) && /§ 37 Abs\. 1 Nr\. 1 SG/.test(fw.text)
    && /Deutsche Männer müssen ihn beantworten/.test(fw.text),
    'Wehrpflicht-Karte: beide Abweichungen markiert (Staatsbürger in Programm und Gesetz, § 1 Abs. 1 WPflG, § 37 SG; Geschlecht), heute: deutsche Männer; Sold brutto mit Lohnsteuer (§ 3 Nr. 5 EStG nur als Gegenüberstellung)');
  // Seit der Schlussprüfung (Befunde X4, X8): „im Inland“ ist als Deutung der Stadt gekennzeichnet; Nachrichtendienst „als eigene Behörde“, USA mit Intelligence Bureau
  ok(fd && /Grenze der Stadt, keine Aussage des Programms/.test(fd.text) && /§ 1 Abs\. 2 BNDG/.test(fd.text)
    && /\(S\. 138, im Abschnitt zur Reform des Verfassungsschutzes; dass damit Aufgaben im Inland gemeint sind, ist eine Deutung der Stadt\)/.test(fd.text)
    && /Nachrichtendienst als eigene Behörde/.test(fd.text) && /Intelligence Bureau/.test(fd.text) && /Überwacht: niemand/.test(fd.live),
    `Dienststellen-Karte: keine Überwachung als Grenze der Stadt, S. 138 als Deutung gekennzeichnet, § 1 BNDG, USA; live „${fd ? fd.live : '–'}“`);
  ok(fk && /Vereinfacht:/.test(fk.text) && /Bauverwaltungen von Bund und Ländern/.test(fk.text) && /National Guard/.test(fk.text) && /S\. 91/.test(fk.text) && /S\. 88|88/.test(fk.text),
    'Kasernen-Karte: Bau als Vereinfachung markiert, USA (National Guard), S. 91 nur für US-Waffensysteme');
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'militaer_fenster.png' });
  await page.keyboard.press('Escape');
  const hilfe = await ev(() => document.getElementById('hilfe-dialog').innerText);
  ok(/Oliv:.*Bundeswehr/.test(hilfe), 'Hilfe nennt Oliv für die Bundeswehr');
  // Draw Calls: das Bund-Mesh ist genau einer; der Puffer ändert sich ohne neuen Schlüssel nicht (nichts bewegt sich von selbst)
  await zu();
  const dc = await ev(() => { const G = __stadt.G, m = G.scene.children.find(o => o.isMesh && o.geometry && o.geometry.getAttribute('glut'));
    const mit = G.render().calls; m.visible = false; const ohne = G.render().calls; m.visible = true;
    const v0 = G.test.bund().version; G.render(); G.render(); const v1 = G.test.bund().version;
    return { mit, ohne, v0, v1, info: G.test.bund() }; });
  ok(dc.mit - dc.ohne === 1 && dc.mit <= 30 && dc.v0 === dc.v1 && dc.info.dreiecke > 500, `Draw Calls ${dc.mit} mit Bund-Mesh, ${dc.ohne} ohne (+1), ${dc.info.dreiecke} Dreiecke; ohne Stundenschritt bleibt der Puffer gleich (Version ${dc.v0} → ${dc.v1})`);
  // Warnlichter: nachts im Takt (1 s an, 1 s aus), tagsüber aus
  const glut = async () => { const w = []; for (let i = 0; i < 6; i++) { w.push(await ev(() => { __stadt.G.render(); return __stadt.G.test.bund().glut; })); await page.waitForTimeout(450); } return w; };
  await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 12) a.schritt(); a.nachSchritten(); });
  const tag = await glut();
  await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 23) a.schritt(); a.nachSchritten(); });
  const nacht = await glut();
  ok(tag.every(v => v === 0) && nacht.includes(0) && nacht.includes(1), `Warnlichter: tagsüber aus (${tag.join('')}), nachts im Takt (${nacht.join('')})`);
  const dbg = await ev(() => { __stadt.setzeTempo(1); return new Promise(r => setTimeout(() => r(globalThis.__stadtDebug), 1200)); });
  ok(dbg.calls <= 30, `Draw Calls im Lauf ${dbg.calls} (≤ 30), Dreiecke ${dbg.dreiecke}`);
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  // Reduzierte Bewegung: nachts leuchten die Warnlichter stetig
  const r = await seite(b, true);
  await r.page.evaluate(() => { const a = __stadt, S = a.S(); for (const d of document.querySelectorAll('dialog[open]')) d.close(); while (S.stunde !== 23) a.schritt(); a.nachSchritten(); });
  const w = []; for (let i = 0; i < 6; i++) { w.push(await r.page.evaluate(() => { __stadt.G.render(); return __stadt.G.test.bund().glut; })); await r.page.waitForTimeout(450); }
  ok(w.every(v => v === 1), `reduzierte Bewegung: Warnlichter nachts stetig an (${w.join('')})`);
  console.log('Konsole (reduziert):', r.log.length ? '\n  ' + r.log.join('\n  ') : 'leer');
  if (r.log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
