// Kitas (Schritt 2) im Browser: Kita gezeichnet (+1 Draw Call), Erzieherinnen und Erzieher auf dem Spielplatz, Klick aufs Dach öffnet die
// Hauskarte (Symbol, Plätze, Personal, Kinder in eigenem Abschnitt), Personenkarte eines Kindes und eines Elternteils ohne Platz,
// Fenster „Stadtregierung“ (Karte mit Zitaten und Live-Zahlen), Konsole leer. Teststadt Seed 2, Tag 300. Bilder nach tests/ausgabe/bilder_kita/.
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const OUT = U.ordner('bilder_kita');
fs.mkdirSync(OUT, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [w, h, n] of [[1280, 800, 'breit'], [400, 820, 'handy']]) {
    const ctx = await b.newContext({ viewport: { width: w, height: h } });
    await U.three(ctx);
    await ctx.route('http://localhost:11434/**', (r) => r.abort());
    const page = await ctx.newPage(), log = [];
    page.on('pageerror', e => log.push('pageerror: ' + e.message));
    page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/Failed to load resource/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
    await page.goto(U.HOST + '/stadt.html?debug&seed=2&tage=300&neu', { timeout: 600000 });
    await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
    const zu = () => page.evaluate(() => { const a = __stadt, S = a.S(); a.setzeTempo(0); while (S.ki.verlust.length) a.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
    await zu(); await page.waitForTimeout(600); await zu();
    // 10 Uhr, Kamera auf die Kita mit dem meisten Personal. Die Kamera steht dort, bevor die Figuren der Stunde geplant werden: Die
    // Arbeitsplätze vergibt die Darstellung einmal am Tag nach Nähe zur Kamera (höchstens 120). Seit „Sicherheit“ läuft die Teststadt
    // anders, und vom Startblick aus liegt die Kita bei 1280 × 800 knapp hinter den 120 nächsten Arbeitsplätzen
    const k = await page.evaluate(() => {
      const a = __stadt, S = a.S(), Sim = a.Sim, g = S.g;
      while (S.stunde !== 10) a.schritt();
      let kb = -1, best = -1;
      for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.KITA && S.feld[g.y[b] * S.karte + g.x[b]] === Sim.KITA && S.belegschaft[b].length > best) { best = S.belegschaft[b].length; kb = b; }
      if (kb < 0) { a.nachSchritten(); return null; }
      const c = a.G.controls, x = g.x[kb] - S.mitte + 0.5, z = g.y[kb] - S.mitte + 0.5;
      c.minDistance = 2; c.target.set(x, 0, z); a.G.camera.position.set(x + 2.2, 2.4, z + 2.6); c.update();
      a.nachSchritten();
      return { kb, x, z, personal: S.belegschaft[kb].length, kinder: [...Array(S.pMax).keys()].filter(p => S.p.lebt[p] && S.p.kita[p] === kb + 1).length, count: a.G.M.kita.count };
    });
    ok(k && k.count > 0, `${n}: Kita ${k && k.kb} gezeichnet (${k && k.count} Kita-Instanzen), ${k && k.personal} Leute Personal, ${k && k.kinder} Kinder`);
    if (!k) { await ctx.close(); continue; }
    await page.waitForTimeout(900); await zu();
    await page.screenshot({ path: OUT + `${n}_nah.png` });
    // Erzieherinnen und Erzieher stehen auf dem Spielplatz (auf dem Grundstück, nicht auf dem Gehweg)
    const fig = await page.evaluate((k) => {
      const a = __stadt, S = a.S(), T = a.G.test, m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3();
      a.G.figurenBewegen(S.tag * 24 + 10.99);
      let da = 0, grund = 0, weg = [];
      for (let i = 0; i < T.figuren.length; i++) {
        const p = T.figIds[i];
        if (p < 0 || S.p.arbeit[p] !== k.kb || S.p.frei[p]) continue;
        const f = T.figuren[i];
        if (f.route && S.tag * 24 + 10.99 < f.start + f.dauer) continue;
        a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4);
        da++;
        const d = Math.max(Math.abs(v.x - k.x), Math.abs(v.z - k.z));
        if (d <= 0.5) grund++; else weg.push(d.toFixed(2));
      }
      return { da, grund, weg };
    }, k);
    ok(fig.da > 0 && fig.grund === fig.da, `${n}: ${fig.grund} von ${fig.da} sichtbaren Erzieherinnen und Erziehern stehen auf dem Spielplatz ${fig.weg.length ? '(daneben: ' + fig.weg.join(', ') + ')' : ''}`);
    // Draw Calls mit und ohne Kita-Mesh
    // Version 9: direkt mit G.render() gezählt (wie tests/militaer.cjs); über __stadtDebug nach 700 ms war es unter Last (3 Bilder je Sekunde)
    // zweimal ein altes Bild
    const calls = await page.evaluate(async () => {
      const a = __stadt, warte = () => new Promise(r => setTimeout(r, 700));
      await warte(); const mit = a.G.render().calls;
      a.G.M.kita.visible = false; const ohne = a.G.render().calls; a.G.M.kita.visible = true; await warte();
      return { mit, ohne };
    });
    ok(calls.mit - calls.ohne === 1, `${n}: Draw Calls mit Kita-Mesh ${calls.mit}, ohne ${calls.ohne} (genau +1)`);
    // Klick aufs Dach → Hauskarte. Version 9, Teil 4: Seit dem Anlauf steht in der Teststadt bei 1280 × 800 eine Tech-Firma zwischen der
    // Kamera und dem festen Punkt auf dem Kita-Dach (der Klick öffnete sie). Deshalb sucht der Test über dem Grundstück (Raster 0,1 Felder,
    // Höhe 0,36 und 0,2) den ersten Bildpunkt, der frei auf der Szene liegt und dessen Strahl zuerst (vor allen sichtbaren Meshes der Szene)
    // das Kita-Mesh auf diesem Grundstück trifft
    const dachPunkt = () => page.evaluate((k) => { const a = __stadt, G = a.G, T = G.THREE, M = G.M;
      G.camera.updateMatrixWorld();
      const ray = new T.Raycaster(), ms = Object.values(M).filter(m => m.visible && m.count > 0), p = new T.Vector2(), v = new T.Vector3();
      for (const y of [0.36, 0.2]) for (let i = -3; i <= 3; i++) for (let j = -3; j <= 3; j++) {
        v.set(k.x + i * 0.1, y, k.z + j * 0.1).project(G.camera);
        const pos = { x: (v.x + 1) / 2 * innerWidth, y: (1 - v.y) / 2 * innerHeight }, e = document.elementFromPoint(pos.x, pos.y);
        if (!e || e.id !== 'szene') continue;
        p.set(v.x, v.y); ray.setFromCamera(p, G.camera);
        const t = ray.intersectObjects(ms, false)[0];
        if (t && t.object === M.kita && Math.abs(t.point.x - k.x) < 0.5 && Math.abs(t.point.z - k.z) < 0.5) return { ...pos, frei: true };
      }
      return { x: 0, y: 0, frei: false }; }, k);
    let pos = await dachPunkt();
    if (!pos.frei) { await page.evaluate((k) => __stadt.G.zeigen(k.kb), k); await page.waitForTimeout(1500); pos = await dachPunkt(); }   // Handy: Kita in die freie Fläche rücken
    console.log('     Klick bei', Math.round(pos.x), Math.round(pos.y), pos.frei ? 'auf die Szene' : 'NICHT auf die Szene');
    await page.mouse.click(pos.x, pos.y);
    await page.waitForTimeout(800);
    const hk = await page.evaluate(() => ({ offen: !document.getElementById('karte').hidden, titel: (document.querySelector('#karte h2') || {}).textContent || '',
      symbol: (document.querySelector('#karte .typ-marke use') || { getAttribute: () => '' }).getAttribute('href'), unter: (document.querySelector('#karte .unter') || {}).textContent || '',
      mehr: [...document.querySelectorAll('#karte .mehr p')].map(p => p.textContent), h3: [...document.querySelectorAll('#karte h3')].map(x => x.textContent),
      kinder: [...document.querySelectorAll('#karte .personenliste')].map(u => [...u.querySelectorAll('li')].map(l => l.textContent)) }));
    await page.screenshot({ path: OUT + `${n}_hauskarte.png` });
    ok(hk.offen && hk.titel.startsWith('Kita ') && hk.symbol === '#s-kita' && /^gehört der Stadt, (1 Fachkraft|\d Fachkräfte) \(Bedarf \d\), Lohn \d+ Taler am Tag$/.test(hk.unter),
      `${n}: Klick aufs Dach: „${hk.titel}“, Symbol ${hk.symbol}, „${hk.unter}“`);
    const hKinder = hk.h3.find(t => /^Kinder \(\d+\)$/.test(t)), hArbeit = hk.h3.find(t => /^Hier arbeiten \(\d+\)$/.test(t));
    ok(!!hKinder && !!hArbeit && hk.mehr.some(t => /Platzeinheiten belegt/.test(t)) && hk.mehr.some(t => /Vorrang haben Familien, in denen beide Eltern arbeiten/.test(t))
      && hk.kinder.length === 2 && hk.kinder[1].every(l => /Kind, \d+ Jahre?( · letzter Tag)?$/.test(l)) && hk.kinder[0].every(l => /Erzieher(in)?$|hat heute frei$/.test(l)),
      `${n}: Hauskarte: ${hk.h3.join(' / ')}; ${hk.mehr[0] || ''}`);
    // Personenkarte eines Kindes der Kita (Knopf in der Kinderliste): das erste Kind, das nicht gerade seinen letzten Kita-Tag hat (das
    // prüft befunde_s2); seit „Sicherheit“ läuft die Teststadt anders, und das erste Kind der Liste ist an Tag 300 an seinem letzten Tag
    const kinderKnopf = await page.$$('#karte .personenliste:last-of-type button.name');
    const nichtLetzter = await page.evaluate(() => [...document.querySelectorAll('#karte .personenliste:last-of-type button.name')].findIndex(k => !/letzter Tag/.test(k.closest('li').textContent)));
    if (kinderKnopf.length && nichtLetzter >= 0) {
      await kinderKnopf[nichtLetzter].click(); await page.waitForTimeout(500);
      const pk = await page.evaluate(() => ({ unter: (document.querySelector('#karte .unter') || {}).textContent || '', fakten: [...document.querySelectorAll('#karte .fakten li')].map(l => l.textContent),
        knoepfe: [...document.querySelectorAll('#karte .fakten button.haus')].map(x => x.textContent) }));
      await page.screenshot({ path: OUT + `${n}_kind.png` });
      ok(/Kind, geht in die Kita /.test(pk.unter) && pk.fakten.some(f => /^geht in die Kita /.test(f)) && /^wohnt /.test(pk.knoepfe.at(-1) || ''),
        `${n}: Kind: „${pk.unter}“ | ${pk.fakten.filter(f => /Kita/.test(f)).join(' | ')}; letzter Hausknopf „${pk.knoepfe.at(-1)}“`);
    } else ok(false, `${n}: keine Kinder in der Kita`);
    // Elternteil ohne Platz (erzwungen wie in simtest --kitest): Grund auf der Personenkarte
    const geb = await page.evaluate((k) => {
      const a = __stadt, S = a.S(), Sim = a.Sim, P = S.p, R = Sim.R, g = S.g, erw = S.tag - R.ERWACHSEN * R.JAHR;
      const dist = (x, y) => Math.abs(g.x[x] - g.x[y]) + Math.abs(g.y[x] - g.y[y]);
      for (let c = 0; c < S.pMax; c++) {
        if (!P.lebt[c] || !P.kita[c] || S.tag - P.geb[c] < R.KRIPPE_BIS || S.tag - P.geb[c] >= R.KITA_ENDE) continue;   // nicht am letzten Kita-Tag
        const v = P.hh[c], pa = v >= 0 ? P.partner[v] : -1;
        if (v < 0 || pa < 0 || P.hh[pa] !== v || P.arbeit[v] < 0 || P.besitz[pa] >= 0 || Sim.anspruch(S, pa)) continue;
        if (S.bewohner[P.wohnung[c]].some(m => m !== v && m !== pa && P.hh[m] === v && P.geb[m] <= erw)) continue;
        // Version 9, Teil 4: auch kein Kind unter 3 ohne Platz im Haushalt, sonst bekommt der Elternteil Betreuungsgehalt und die Karte sagt
        // richtig „bleibt beim Kind zu Hause“ (kleinkind/betreuer der Simulation); gesucht ist der Fall „kein Kita-Platz frei“
        if (S.bewohner[P.wohnung[c]].some(m => P.hh[m] === v && P.geb[m] > S.tag - R.BETREUUNG_ALTER && !P.kita[m])) continue;
        if (P.arbeit[pa] >= 0) { const L = S.belegschaft[P.arbeit[pa]]; L.splice(L.indexOf(pa), 1); P.arbeit[pa] = -1; P.einsatz[pa] = 0; }
        P.kita[c] = 0;
        for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.KITA && dist(b, P.wohnung[c]) <= R.REICH_KITA) g.bedient[b] = g.kapaz[b];
        return Sim.gebunden(S, pa) ? { p: pa, gen: P.gen[pa], name: Sim.name(S, pa), kind: Sim.name(S, c) } : null;
      }
      return null;
    }, k);
    if (geb) {
      await page.evaluate((x) => { const btn = document.createElement('button'); btn.className = 'name'; btn.dataset.p = x.p; btn.dataset.g = x.gen; btn.dataset.n = x.name;
        document.getElementById('buch-liste').append(btn); btn.click(); btn.remove(); }, geb);
      await page.waitForTimeout(500);
      const pk = await page.evaluate(() => ({ unter: (document.querySelector('#karte .unter') || {}).textContent || '', fakten: [...document.querySelectorAll('#karte .fakten li')].map(l => l.textContent) }));
      await page.screenshot({ path: OUT + `${n}_gebunden.png` });
      ok(pk.unter.includes(`bleibt bei ${geb.kind} zu Hause, kein Kita-Platz frei`) && pk.fakten.some(f => f.startsWith(`Kann gerade keine Stelle antreten: Für ${geb.kind} ist in der Nähe kein Kita-Platz frei`)),
        `${n}: ohne Platz: „${pk.unter}“ | ${pk.fakten.filter(f => /Kita/.test(f)).join(' | ')}`);
    } else ok(false, `${n}: kein Elternteil zum Erzwingen gefunden`);
    await page.evaluate(() => document.getElementById('karte-zu').click());
    await page.waitForTimeout(300); await zu();
    // Fenster „Stadtregierung“: Karte Kitas mit zwei Zitaten und Live-Zahlen, Betreuungsgehalt mit Eigenbetreuung, Listen ohne alte Sätze
    await page.click('#regierung-knopf'); await page.waitForTimeout(500);
    const r = await page.evaluate(() => {
      const karten = [...document.querySelectorAll('#regierung-inhalt .reg-karte')];
      const kk = (t) => karten.find(x => x.querySelector('h4').textContent.startsWith(t));
      const info = (t) => { const x = kk(t); return x ? { zitate: [...x.querySelectorAll('.reg-zitat')].map(q => q.textContent), live: (x.querySelector('p.reg-live') || {}).textContent || '', text: x.textContent,
        mehr: (x.querySelector('details.reg-mehr summary') || {}).textContent, offen: !!(x.querySelector('details.reg-mehr') || {}).open } : null; };
      return { kita: info('Kitas in Wohnraumnähe'), betr: info('Betreuungsgehalt'), text: document.getElementById('regierung-inhalt').textContent, kopf: (document.querySelector('#regierung-inhalt .reg-unter') || {}).textContent };
    });
    ok(r.kita && r.kita.zitate.length === 2 && /S\. 20$/.test(r.kita.zitate[0]) && /S\. 152$/.test(r.kita.zitate[1]) && /^\d+ Kitas? offen, \d+ Fachkr(aft|äfte) \(Bedarf \d+\)/.test(r.kita.live) && /Annahme:/.test(r.kita.text)
      && /Doppelberufstätigkeit/.test(r.kita.text) && r.kita.mehr === 'Weitere Annahmen und Folgen' && !r.kita.offen,
      `${n}: Karte Kitas, live „${r.kita && r.kita.live.slice(0, 160)}…“`);
    ok(r.betr && r.betr.zitate.length === 3 && /Eigenbetreuung/.test(r.betr.text) && /keinen Kita-Platz hat/.test(r.betr.text), `${n}: Betreuungsgehalt nennt die Eigenbetreuung (S. 20)`);
    ok(!/Kinder hindern in der Stadt niemanden an der Arbeit/.test(r.text) && !/keine Kitas in der Stadt/.test(r.text) && /Vorschule/.test(r.text) && /Fachaufsichten/.test(r.text),
      `${n}: Listen nachgezogen (keine alten Kita-Sätze, Vorschule und Fachaufsichten stehen unter „nicht übernommen“)`);
    await page.evaluate(() => { const x = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(k => k.querySelector('h4').textContent.startsWith('Kitas')); x.scrollIntoView({ block: 'start' }); });
    await page.waitForTimeout(300);
    await page.screenshot({ path: OUT + `${n}_fenster.png` });
    await page.keyboard.press('Escape'); await page.waitForTimeout(300);
    ok(!log.length, `${n}: Konsole ${log.join(' | ') || 'leer'}`);
    await ctx.close();
  }
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
