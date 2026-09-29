// Sicherheit (Version 7) im Browser: Wache und Anstalt (Klick aufs Gelände öffnet die Hauskarte), Gefangene nur zur Hofzeit im Hof ihrer
// Abteilung (Grundregel), Polizei um 10 Uhr zum Tatort und zurück, Personen- und Hauskarten (Haft, U-Haft, Obhut), Fenster „Stadtregierung“
// (Gruppe Innere Sicherheit, Geld vom Land), Hilfe, Draw Calls. Gefangene und Obhut setzt der Test selbst (Testhilfen der Simulation).
// Server: tests/alle.sh (PORT, Wurzel stadt/); Bilder: tests/ausgabe/bilder_befunde/
const U = require('./umgebung.cjs');
const { chromium } = U;
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const ev = (f, a) => page.evaluate(f, a);
  await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=400&neu', { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await ev(() => __stadt.setzeTempo(0));
  const zu = async () => { for (let i = 0; i < 30; i++) {
    const o = await ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
      for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
    await page.waitForTimeout(100); if (!o) break; } };
  // Wache und Anstalt auf eigenem Gelände; drei Gefangene (je Abteilung einer), zwei ganze Haushalte mit Kind in Strafhaft (Obhut)
  const s = await ev(() => {
    const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, X = Sim._sich, erw = S.tag - Sim.R.ERWACHSEN * Sim.R.JAHR, i = Sim.sicherheitInfo(S);
    const frei = []; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && P.geb[p] <= erw && !P.haftBis[p] && P.besitz[p] < 0 && !Sim.istHaupt(S, p)) frei.push(p);
    const g = [frei[2], frei[6], frei[10]];
    X.haftAntritt(S, g[0], 20, Sim.HAFT_STRAF); X.haftAntritt(S, g[1], 20, Sim.HAFT_KURZ); X.haftAntritt(S, g[2], 20, Sim.HAFT_U);
    const v = { id: g[2], gen: P.gen[g[2]], typ: Sim.EINBRUCH, beute: 0, opfer: frei[20], opferGen: P.gen[frei[20]], urteil: S.tag + 30, uhaft: S.tag }; S.sicherheit.verfahren.push(v);
    let kinder = [];
    for (let k = 0; k < S.pMax && !kinder.length; k++) {
      if (!P.lebt[k] || P.hh[k] !== k || !S.hhKinder[k] || P.wohnung[k] < 0) continue;
      const e = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === k && P.geb[m] <= erw);
      if (!e.every(m => P.besitz[m] < 0 && !P.haftBis[m] && !Sim.istHaupt(S, m))) continue;
      for (const m of e) X.haftAntritt(S, m, 20, Sim.HAFT_STRAF);
      X.obhutPruefen(S);
      kinder = S.bewohner[P.wohnung[k]].filter(m => P.hh[m] === k && P.geb[m] > erw);
    }
    a.nachSchritten();
    const gel = (b) => S.erweiterung.gelaende.find(r => r[4] === b);
    return { wache: i.wache, jva: i.jva, gw: gel(i.wache), gj: gel(i.jva), g, kinder, hier: X.insassen(S), wohnung: P.wohnung[g[0]] };
  });
  ok(s.wache >= 0 && s.jva >= 0 && s.gw && s.gj && s.hier >= 3, `Wache (Gelände ${s.gw && s.gw.slice(0, 4)}) und Anstalt (Gelände ${s.gj && s.gj.slice(0, 4)}), ${s.hier} Gefangene in der Anstalt`);
  // Kamera auf die Wache (Arbeitsplätze werden nach Nähe zur Kamera vergeben), dann Stunde für Stunde 8–17 Uhr
  await ev((r) => { const { G } = __stadt, S = __stadt.S(), x = (r[0] + r[2]) / 2 - S.mitte + 0.5, z = (r[1] + r[3]) / 2 - S.mitte + 0.5;
    G.controls.target.set(x, 0, z); G.camera.position.set(x + 8, 11, z + 8); G.controls.update(); }, s.gw);
  // Anzeigen der letzten Nacht: zwei Wohnhäuser weiter weg (nur für die Figuren; die Simulation liest tatorte nicht)
  await ev(() => { const S = __stadt.S(); const L = []; for (let b = 0; b < S.gAnzahl && L.length < 2; b++) if (S.g.typ[b] === __stadt.Sim.WOHNHAUS && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === __stadt.Sim.WOHNHAUS) L.push(b); S.sicherheit.tatorte = L; });
  const hof = [], fehlHof = [], polizeiWege = [];
  for (let H = 8; H <= 17; H++) {
    const r = await ev(([H, gj]) => {
      const a = __stadt, S = a.S(), T = a.G.test, Sim = a.Sim, P = S.p;
      while (S.stunde !== H) a.schritt();
      if (H === 8) S.sicherheit.tatorte = S.sicherheit.tatorte.length ? S.sicherheit.tatorte : [];
      a.nachSchritten();
      a.G.figurenBewegen(S.tag * 24 + H + 0.5);
      const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), sichtbar = new Set(), fehl = [];
      const x0 = gj[0] - S.mitte, x1 = gj[2] - S.mitte + 1, z0 = gj[1] - S.mitte, z1 = gj[3] - S.mitte + 1;
      for (let i = 0; i < T.figuren.length; i++) {
        const p = T.figIds[i]; if (p < 0 || !P.haftBis[p]) continue;
        a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4); sichtbar.add(p);
        const drin = v.x > x0 + 0.1 && v.x < x1 - 0.1 && v.z > z0 + 0.1 && v.z < z1 - 0.1;
        if (!Sim.imHof(S, p, H) || !Sim.HOFZEITEN[Sim.abteilung(S, p)].includes(H) || !drin) fehl.push(`${H} Uhr: Person ${p} bei (${v.x.toFixed(2)}, ${v.z.toFixed(2)}), im Hof ${Sim.imHof(S, p, H)}, auf dem Gelände ${drin}`);
      }
      let imHof = 0; for (let p = 0; p < S.pMax; p++) if (P.lebt[p] && Sim.imHof(S, p, H)) { imHof++; if (!sichtbar.has(p)) fehl.push(`${H} Uhr: Person ${p} ist im Hof, aber nicht zu sehen`); }
      // Polizei um 10 Uhr: wer eine Anzeige aufnimmt und als Figur da ist, hat einen Weg Wache → Tatort → Wache
      const wege = [];
      if (H === 10) { const e = Sim.polizeiEinsatz(S); for (const f of T.figuren) if (f.p >= 0 && e.has(f.p) && f.route) wege.push(Sim.name(S, f.p) + ' ' + f.route.len.toFixed(1)); }
      return { H, imHof, sichtbar: sichtbar.size, fehl, wege, einsatz: H === 10 ? Sim.polizeiEinsatz(S).size : 0 };
    }, [H, s.gj]);
    hof.push(`${H}:${r.sichtbar}/${r.imHof}`); fehlHof.push(...r.fehl);
    if (H === 10) { polizeiWege.push(...r.wege); console.log(`     10 Uhr: ${r.einsatz} Anzeigen aufzunehmen, Wege: ${r.wege.join(', ') || '–'}`); }
  }
  ok(!fehlHof.length && hof.some(x => !x.endsWith('/0')), `Gefangene nur zur Hofzeit im Hof der Anstalt, alle im Hof zu sehen (sichtbar/im Hof je Stunde: ${hof.join(' ')})` + (fehlHof.length ? '\n  ' + fehlHof.slice(0, 4).join('\n  ') : ''));
  ok(polizeiWege.length > 0, `Polizei um 10 Uhr zum Tatort und zurück: ${polizeiWege.length} Figuren mit Weg`);
  // Klick aufs Gelände (Hafthaus, nicht das Torfeld) öffnet die Hauskarte der Anstalt, Klick auf die Wache ihre
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
  const kj = await klick(s.gj, 0.3), kw = await klick(s.gw, 0.5);
  ok(kj.offen && /Justizvollzugsanstalt an der/.test(kj.text) && kj.text.includes('gehört dem Land') && kj.text.includes('nur als Zahl') && kj.text.includes('Drei Abteilungen'),
    'Klick aufs Gelände: Hauskarte „' + kj.text.split('\n').slice(0, 3).join(' | ') + '…“');
  ok(kw.offen && /Polizeiwache an der/.test(kw.text) && kw.text.includes('Landespolizei') && /Lohn 105 Taler am Tag vom Land/.test(kw.text), 'Klick auf die Wache: „' + kw.text.split('\n').slice(0, 3).join(' | ') + '…“');
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'sicherheit_wache_karte.png' });
  // Personenkarten: Strafhaft, U-Haft (mit Verfahren), Kind in Obhut; Hauskarte des Wohnhauses: „in Haft“
  const karte = (art, id) => ev(([art, id]) => { const S = __stadt.S(), k = document.createElement('button');
    if (art === 'p') { k.className = 'name'; k.dataset.p = id; k.dataset.g = S.p.gen[id]; k.dataset.n = __stadt.Sim.name(S, id); } else { k.className = 'haus'; k.dataset.b = id; }
    document.body.append(k); k.click(); k.remove(); return document.getElementById('karte-inhalt').innerText; }, [art, id]);
  const ps = await karte('p', s.g[0]), pu = await karte('p', s.g[2]), hk = await karte('h', s.wohnung), pk = s.kinder.length ? await karte('p', s.kinder[0]) : '';
  ok(/In Strafhaft bis Tag \d+/.test(ps) && ps.includes('Justizvollzugsanstalt') && /Hofgang 10 und 15 Uhr/.test(ps), 'Personenkarte Strafhaft: „' + (ps.match(/In Strafhaft[^\n]*/) || ['–'])[0] + '“');
  ok(/In Untersuchungshaft, bis das Gericht urteilt/.test(pu) && /Strafverfahren \(Wohnungseinbruch\): Urteil am Tag \d+/.test(pu) && /Hofgang 9 und 14 Uhr/.test(pu), 'Personenkarte U-Haft: „' + (pu.match(/In Untersuchungshaft[^\n]*/) || ['–'])[0] + '“');
  ok(hk.includes('in Haft'), 'Hauskarte des Wohnhauses: Bewohner „in Haft“');
  ok(s.kinder.length > 0 && /lebt bei|Jugendamt/.test(pk), `Kind in Obhut: „${(pk.match(/Kind, [^\n]*/) || ['–'])[0]}“`);
  await page.keyboard.press('Escape');
  // Fenster „Stadtregierung“: Gruppe mit Karten, Zitaten und Zahlen; Geld vom Land
  await zu();
  await page.click('#regierung-knopf'); await page.waitForTimeout(400);
  // Karten der Gruppe: nach ihrer Überschrift und vor der nächsten Gruppe (seit Teil 3 folgt „Bund in der Stadt“)
  const f = await ev(() => { const box = document.getElementById('regierung-inhalt'), gs = [...box.querySelectorAll('.reg-gruppe')], g = gs.find(x => x.textContent.includes('Innere Sicherheit')), g2 = gs[gs.indexOf(g) + 1];
    const karten = [...box.querySelectorAll('.reg-karte')].filter(k => g && (g.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_FOLLOWING) && (!g2 || (g2.compareDocumentPosition(k) & Node.DOCUMENT_POSITION_PRECEDING)));
    const dts = [...box.querySelectorAll('dl.zahlen dt')].map(d => d.textContent), dds = [...box.querySelectorAll('dl.zahlen dd')].map(d => d.textContent);
    return { gruppe: !!g, karten: karten.map(k => ({ titel: k.querySelector('h4 span').textContent, zitate: k.querySelectorAll('blockquote, .reg-zitat').length, live: (k.querySelector('p.reg-live') || { textContent: null }).textContent })),
      land: dts.map((t, i) => [t, dds[i]]).filter(([t]) => t.startsWith('Land')), hinweis: [...box.querySelectorAll('.reg-hinweis')].some(h => h.textContent.includes('elektronischer Überwachungssysteme')) }; });
  const mitLive = f.karten.filter(k => k.live !== null);
  ok(f.gruppe && f.karten.length === 11 && mitLive.length === 6 && mitLive.every(k => k.live.length > 20) && f.land.length === 2 && f.land.every(([, v]) => /Taler|ab morgen/.test(v)) && f.hinweis,
    `Fenster: Gruppe „Innere Sicherheit“ mit ${f.karten.length} Karten (${f.karten.map(k => k.titel).join('; ')}), ${mitLive.length} mit Zahlen; ${f.land.map(x => x.join(': ')).join(', ')}; Hinweis mit S. 125 und S. 122`);
  await page.screenshot({ path: U.ordner('bilder_befunde') + 'sicherheit_fenster.png' });
  await page.keyboard.press('Escape');
  const hilfe = await ev(() => document.getElementById('hilfe-dialog').innerText);
  ok(/Dunkelblau:.*Polizei/.test(hilfe) && /Graugrün:.*Justizvollzug/.test(hilfe) && /Hofzeit/.test(hilfe), 'Hilfe nennt Polizei, Justizvollzug und die Hofzeit');
  const dbg = await ev(() => { __stadt.setzeTempo(1); return new Promise(r => setTimeout(() => r(globalThis.__stadtDebug), 1200)); });
  ok(dbg.calls <= 30, `Draw Calls ${dbg.calls} (≤ 30), Dreiecke ${dbg.dreiecke}`);
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
