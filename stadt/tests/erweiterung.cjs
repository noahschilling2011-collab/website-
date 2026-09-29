// Stadt erweitern (Version 7) im Browser: Die Karte wächst mitten im Spiel (seit Version 9, Teil 5 Seed 40, Tag 242 → 243, 72 → 80; seit
// Version 9, Teil 4 Seed 5, Tag 114 → 115, 96 → 104; seit
// Version 9, Teil 3 Seed 1, Tag 201 → 202, 80 → 88; seit
// Version 9 Seed 12, Tag 307 → 308, 80 → 88; seit der
// Schlussprüfung von Version 8 Seed 12, Tag 243 → 244,
// 80 → 88; seit Version 8 Seed 9, Tag 235 → 236, 72 → 80; seit Teil 3 Seed 5,
// Tag 313 → 314, 88 → 96; in Teil 2 Seed 2, Tag 229 → 230, 64 → 72; bis Teil 1 Tag 107 → 108, 56 → 64): Kamera, Blickpunkt und Gebäude
// bleiben, wo sie sind; Landschaft, Nebel und Grenzen rücken nach außen; Draw Calls gleich; Zeile im Stadtbuch. Stufe in den Kennzahlen,
// Stadtteil in Haus- und Personenkarte, Namen der Stadtteile nur weit herausgezoomt und nie zugleich mit Straßennamen. Dazu mit
// reduzierter Bewegung. Server: tests/alle.sh (PORT).
const U = require('./umgebung.cjs');
const { chromium } = U;
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const reduziert of [false, true]) {
    const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, reducedMotion: reduziert ? 'reduce' : 'no-preference' });
    await U.three(ctx);
    await ctx.route('http://localhost:11434/**', (route) => route.abort());
    const page = await ctx.newPage(), log = [];
    page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
    page.on('pageerror', e => log.push('pageerror: ' + e.message));
    const ev = (f, a) => page.evaluate(f, a);
    const bilder = () => ev(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    const tag = reduziert ? ' (reduziert)' : '';
    await page.goto(U.HOST + '/stadt.html?debug&seed=40&tage=241&neu', { timeout: 300000 });
    await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 300000 });
    await ev(() => { __stadt.setzeTempo(0); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
    await page.waitForTimeout(1200);
    const zustand = () => ev(() => { const { G, S } = { G: __stadt.G, S: __stadt.S() }, c = G.camera.position, t = G.controls.target, see = G.scene.children.find(o => o.isMesh && o.material && o.material.isMeshBasicMaterial && o.geometry.getAttribute('position') && o.geometry.getAttribute('position').count === 144);
      const boden = G.scene.children.find(o => o.isMesh && o.material && o.material.isMeshLambertMaterial && o.material.vertexColors && !o.isInstancedMesh && o.geometry.getAttribute('position').count > 20000);
      see.geometry.computeBoundingBox();
      return { tag: S.tag, karte: S.karte, cam: [c.x, c.y, c.z], ziel: [t.x, t.y, t.z], geb0: [S.g.x[0] - S.mitte + 0.5, S.g.y[0] - S.mitte + 0.5], maxD: G.controls.maxDistance,
        maxR: G.controls.maxTargetRadius, nebel: [G.scene.fog.near, G.scene.fog.far], far: G.camera.far, seeX: see.geometry.boundingBox.min.x, boden: boden.geometry.getAttribute('position').count,
        calls: globalThis.__stadtDebug.calls, stufe: document.getElementById('k-stufe').textContent, kinder: G.scene.children.length,
        gezeichnet: G.scene.children.filter(o => o.visible && (o.isInstancedMesh ? o.count > 0 : true) && (o.isMesh || o.isPoints)).map(o => Object.keys(G.M).find(k => G.M[k] === o) || o.type) }; });
    // Bis zur letzten Stunde vor dem Wachsen (Tag 242, 23 Uhr) stündlich weiter, die Kamera nicht anfassen; Ereignis-Zeichen vergehen
    // lassen. Seit „Sicherheit“ und „Bund“ läuft die Teststadt anders: Seed 2 wächst nur noch einmal, an Tag 198 von 56 auf 80, in der Nacht,
    // in der Land und Bund am Rand Anstalt und Kaserne bestellen (neue Baustellen). Allein (kein neues Gebäude, nichts fertig, kein Gelände)
    // wächst in der Stufe Stadt Seed 5 an Tag 314 von 88 auf 96 (gesucht mit erw7/mil/mess/wachsen_allein.mjs). Seit den Autos (Version 8)
    // wächst Seed 5 dort nicht mehr; allein in der Stufe Stadt wächst Seed 9 an Tag 236 von 72 auf 80 (v8/mess/wachsen_allein8.mjs, Seeds 1–18).
    // Seit der gemischten Reihenfolge der Käufer (Schlussprüfung) wächst allein in der Stufe Stadt nur noch Seed 12, an Tag 244 von 80 auf 88.
    // Seit Version 9 (Rathaus) wächst Seed 12 allein in der Stufe Stadt an Tag 308 von 80 auf 88 (v9/t2/wachsen_allein9.mjs, Seeds 1–18).
    // Seit dem Haushalt (Version 9, Teil 3) wächst Seed 12 dort nicht mehr; allein in der Stufe Stadt wächst Seed 1 an Tag 202 von 80 auf 88
    // (dasselbe Skript, Seeds 1–18; Protokoll v9/t4/wachsen_a.log)
    // Mit dem Anlauf (Version 9, Teil 4) sind die Städte früher groß; allein in der Stufe Stadt wächst am frühesten Seed 5, an Tag 115 von 96
    // auf 104 (dasselbe Skript, Seeds 1–18; Protokoll v9/t5/wachsen_teil4.log; weitere: Seed 3 Tag 136, Seed 1 Tag 266)
    // Seit Teil 5 (Tech-Firmen früher und mehr) wächst in den Seeds 1–18 keine Karte mehr allein in der Stufe Stadt (Seed 6 an Tag 112 in der
    // Nacht, in der die Stadt Stadt wird); in den Seeds 1–42 (bis Tag 400) allein in der Stufe Stadt nur Seed 40, an Tag 243 von 72 auf 80
    // (v9/t2/wachsen_allein9.mjs und v9/t6/wachsen400.mjs; Protokolle v9/t6/wachsen_teil5*.log)
    await ev(() => { const S = __stadt.S(); let n = 0; while (!(S.tag === 242 && S.stunde === 23) && n++ < 60) { __stadt.schritt(); __stadt.nachSchritten(); } });
    await page.waitForTimeout(3500);
    await page.waitForFunction(() => !__stadt.G.test.zeichen.visible, null, { timeout: 15000 }); await bilder();
    const vor = await zustand();
    ok(vor.karte === 72 && vor.tag === 242, `vorher Tag ${vor.tag}, 23 Uhr: Karte ${vor.karte}, ${vor.stufe}, Draw Calls ${vor.calls}, Nebel ${vor.nebel.join('–')}, Kamera-Abstand bis ${vor.maxD}${tag}`);
    // Eine Stunde weiter: um Mitternacht wächst die Karte. Ereignis-Zeichen (ein Draw Call, kein neues Objekt) erst vergehen lassen
    await ev(() => { __stadt.schritt(); __stadt.nachSchritten(); });
    await page.waitForTimeout(3500);
    await page.waitForFunction(() => !__stadt.G.test.zeichen.visible, null, { timeout: 15000 }); await bilder();
    const nach = await zustand();
    const gleich = (a, c) => a.every((v, i) => Math.abs(v - c[i]) < 1e-9);
    ok(nach.karte === 80 && gleich(nach.cam, vor.cam) && gleich(nach.ziel, vor.ziel) && gleich(nach.geb0, vor.geb0),
      `gewachsen an Tag ${nach.tag}: Karte ${vor.karte} → ${nach.karte}; Kamera, Blickpunkt und Gebäude 0 (Welt ${nach.geb0.join('/')}) unverändert${tag}`);
    ok(nach.maxD > vor.maxD && nach.maxR > vor.maxR && nach.nebel[1] > vor.nebel[1] && nach.far > vor.far && Math.abs((vor.seeX - nach.seeX) - 4) < 1e-4 && nach.boden !== vor.boden,
      `Landschaft und Grenzen rücken nach außen: See 4 weiter westlich (${vor.seeX.toFixed(1)} → ${nach.seeX.toFixed(1)}), Boden ${vor.boden} → ${nach.boden} Ecken, Abstand bis ${nach.maxD}, Nebel ${nach.nebel.join('–')}${tag}`);
    // Wachsen legt kein Objekt an (das Straßen-Mesh wird nur größer ersetzt). Was gezeichnet wird, hängt am Inhalt: Hier fällt oft
    // ein Grasbüschel einer Brache weg, weil die Landstraße zur weiter draußen liegenden Ausfahrt jetzt über das Feld läuft
    const weg = vor.gezeichnet.filter(n => !nach.gezeichnet.includes(n)), dazu = nach.gezeichnet.filter(n => !vor.gezeichnet.includes(n));
    ok(nach.kinder === vor.kinder && !dazu.length && nach.calls <= vor.calls && nach.calls < 100,
      `Objekte in der Szene ${vor.kinder} → ${nach.kinder}; Draw Calls ${vor.calls} → ${nach.calls}${weg.length ? ' (ohne Instanzen jetzt: ' + weg.join(', ') + ')' : ''}${tag}`);
    const zeile = await ev(() => [...document.querySelectorAll('#buch-liste li')].map(li => li.textContent).find(t => t.includes('Die Karte wächst von 72 × 72 auf 80 × 80')));
    ok(!!zeile && zeile.includes('Bauland'), `Stadtbuch: „${zeile}“`);
    const titel = await ev(() => document.getElementById('k-stufe-zeile').title);
    // Die Teststadt ist an diesem Tag eine Stadt: Hinweis auf die nächste Stufe
    ok(vor.stufe === 'Stadt' && /^Großstadt ab 800 Einwohnern \(die Stadt zählt jeden Menschen für 125\)$/.test(titel), `Kennzahl Stufe „${vor.stufe}“, Hinweis „${titel}“${tag}`);
    // Haus- und Personenkarte: Stadtteil
    const karten = await ev(() => { const S = __stadt.S(), b = 0; document.querySelector('#haupt-liste button, #haupt-liste li') ;
      return { b, name: __stadt.Sim.teilName(S, __stadt.Sim.teilVon(S, S.g.x[b], S.g.y[b])) }; });
    await ev((b) => { document.querySelector('#karte-inhalt'); window.dispatchEvent(new Event('x')); }, karten.b);
    await ev((b) => { const k = document.createElement('button'); k.className = 'haus'; k.dataset.b = String(b); document.body.appendChild(k); k.click(); k.remove(); }, karten.b);
    await page.waitForTimeout(300);
    const kicker = await ev(() => (document.querySelector('#karte-inhalt .kicker') || {}).textContent || '');
    // Personenkarte: der Stadtteil der eigenen Wohnung (Version 8: die erste lebende Person mit Wohnung; Person 0 wohnt nicht mehr im
    // Stadtteil von Gebäude 0)
    const person = await ev(() => { const S = __stadt.S(), Sim = __stadt.Sim; let p = 0; while (p < S.pMax && !(S.p.lebt[p] && S.p.wohnung[p] >= 0)) p++;
      const w = S.p.wohnung[p], teil = Sim.teilName(S, Sim.teilVon(S, S.g.x[w], S.g.y[w]));
      const k = document.createElement('button'); k.className = 'name'; k.dataset.p = String(p); k.dataset.g = String(S.p.gen[p]); k.dataset.n = ''; document.body.appendChild(k); k.click(); k.remove();
      return { teil, text: [...document.querySelectorAll('#karte-inhalt .fakten li')].map(li => li.textContent).find(t => t.startsWith('wohnt')) || '' }; });
    ok(kicker === karten.name && !!person.teil && person.text.includes('· ' + person.teil), `Hauskarte: Stadtteil „${kicker}“; Personenkarte: „${person.text}“ (Stadtteil der Wohnung: ${person.teil})${tag}`);
    await ev(() => document.getElementById('karte-zu').click());
    // Namen: nah nur Straßennamen, fern nur Stadtteile; beim Wechsel alle 25 ms prüfen, dass nie beide zu sehen sind (Deckkraft > 0)
    const beide = async (ms) => { let n = 0; for (let t = 0; t < ms; t += 25) { if (await ev(() => { const o = (s) => [...document.querySelectorAll(s)].some(e => parseFloat(getComputedStyle(e).opacity) > 0.01); return o('.str-name') && o('.teil-name'); })) n++; await page.waitForTimeout(25); } return n; };
    const setzeAbstand = (d) => ev((d) => { const G = __stadt.G, c = G.controls, t = c.target, p = G.camera.position, v = p.clone().sub(t).normalize().multiplyScalar(d); p.copy(t).add(v); c.update(); }, d);
    // Unter Last braucht der Aufbau der Namen länger: bis zu 15 s warten, bis nah Straßennamen an sind (die Prüfung selbst bleibt gleich)
    const warteAuf = (nahSoll) => page.waitForFunction((n) => { const s = document.querySelectorAll('.str-name.an').length, t = document.querySelectorAll('.teil-name.an').length;
      return n ? s > 0 && t === 0 : s === 0 && t > 0; }, nahSoll, { timeout: 15000 }).catch(() => {});
    await setzeAbstand(20); await page.waitForTimeout(900); await warteAuf(true);
    const nah = await ev(() => ({ str: document.querySelectorAll('.str-name.an').length, teil: document.querySelectorAll('.teil-name.an').length }));
    await setzeAbstand(60); const w1 = await beide(900); await warteAuf(false);
    const fern = await ev(() => ({ str: document.querySelectorAll('.str-name.an').length, teil: [...document.querySelectorAll('.teil-name.an')].map(e => e.textContent) }));
    await setzeAbstand(20); const w2 = await beide(900); await warteAuf(true);
    const wieder = await ev(() => ({ str: document.querySelectorAll('.str-name.an').length, teil: document.querySelectorAll('.teil-name.an').length }));
    ok(nah.str > 0 && nah.teil === 0 && fern.str === 0 && fern.teil.length > 0 && wieder.str > 0 && wieder.teil === 0 && !w1 && !w2,
      `Namen: nah ${nah.str} Straßen, 0 Stadtteile; fern 0 Straßen, Stadtteile ${fern.teil.join(', ')}; wieder nah ${wieder.str} Straßen; beide zugleich zu sehen ${w1 + w2}-mal${tag}`);
    // Wachsen mitten am Tag (Test: Vorlauf kurz um einen Ring größer, dann karteRand; die Stadt rechnet dabei nicht): Die Stadt selbst sieht
    // danach genau gleich aus, Instanz für Instanz (Häuser, Dächer, Bauteile, Grün, Straßen, Gehwege, Laternen im Fenster-Mesh)
    const deko = () => ev(() => { const M = __stadt.G.M, out = {};
      for (const k of ['haus', 'dach', 'teil', 'park', 'busch', 'gras', 'baum', 'belag', 'strasse', 'gehweg', 'schlot', 'fenster', 'scheiben']) {
        const m = M[k], a = m.instanceMatrix.array; let h = 0;
        for (let i = 0; i < m.count * 16; i++) h = (Math.imul(h, 31) + Math.round(a[i] * 1000)) | 0;
        out[k] = m.count + ':' + h; }
      return out; });
    const d0 = await deko(), k0 = await ev(() => __stadt.S().karte);
    await ev(() => { const Sim = __stadt.Sim, S = __stadt.S(), v = Sim.R.KARTE_VORLAUF; Sim.R.KARTE_VORLAUF = v + Sim.R.KARTE_RING; Sim.karteRand(S); Sim.R.KARTE_VORLAUF = v; __stadt.nachSchritten(); });
    await bilder();
    const d1 = await deko(), k1 = await ev(() => __stadt.S().karte), anders = Object.keys(d0).filter(k => d0[k] !== d1[k]);
    ok(k1 > k0 && !anders.length, `Wachsen mitten am Tag (${k0} → ${k1}): Stadt Instanz für Instanz gleich${anders.length ? ', ANDERS: ' + anders.join(', ') : ''} (${Object.entries(d1).map(([k, v]) => k + ' ' + v.split(':')[0]).join(', ')})${tag}`);
    ok(!log.length, 'Konsole: ' + (log.join(' | ') || 'leer') + tag);
    await ctx.close();
  }
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
