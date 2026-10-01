// Tech-Firmen im Browser: Glasbau, Bildschirme, Programmierer-Figuren, Handys, Karten, Code-Tagebuch (Ollama-Attrappe
// über Playwright-Route, der Test-Server auf 11434 wird nicht benutzt), Draw Calls, Konsole. Server: tests/alle.sh (PORT).
const U = require('./umgebung.cjs');
const { chromium } = U;
const OUT = U.ordner('bilder_p8');   // Bilder nach tests/ausgabe/ (per .gitignore ausgeschlossen)
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } });
  await U.three(ctx);
  const chat = [];
  await ctx.route('http://localhost:11434/**', async (route) => {
    const req = route.request(), url = req.url(), h = { 'Access-Control-Allow-Origin': req.headers()['origin'] || '*', 'Content-Type': 'application/json' };
    if (url.endsWith('/api/tags')) return route.fulfill({ status: 200, headers: h, body: JSON.stringify({ models: [{ name: 'attrappe:latest' }] }) });
    if (url.endsWith('/api/chat')) {
      const body = JSON.parse(req.postData()), sys = body.messages[0].content;
      chat.push({ sys, user: body.messages[1].content, format: body.format, stream: body.stream, think: body.think });
      let content;
      if (sys.includes('Stück Code')) content = JSON.stringify({ titel: 'Akku-Anzeige', sprache: 'JavaScript',
        code: "function akku(prozent) {\n  if (prozent < 20) return 'Bitte laden';\n  return prozent + ' %';\n}\n// <script>alert(1)</script>", gedanke: 'Die Anzeige muss auch bei wenig Akku gut lesbar sein.' });
      else if (sys.includes('Wähle genau eine')) { const e = [...sys.matchAll(/^- ([a-z_]+): /gm)].map(m => m[1]); content = JSON.stringify({ aktion: e[0], gedanke: 'Ich mache erst mal weiter.', neues_ziel: null }); }
      else content = JSON.stringify({ antwort: 'Hallo.', neues_ziel: null, eintrag: 'Nichts Besonderes.' });
      return route.fulfill({ status: 200, headers: h, body: JSON.stringify({ model: 'attrappe:latest', message: { role: 'assistant', content }, done: true }) });
    }
    return route.fulfill({ status: 404, headers: h, body: '{"error":"nicht gefunden"}' });
  });
  const page = await ctx.newPage();
  const log = [], dialoge = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  page.on('dialog', d => { dialoge.push(d.message()); d.dismiss(); });
  const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
  const ev = (f, a) => page.evaluate(f, a);
  const seed = process.argv[2] || '2', tage = process.argv[3] || '420';
  await page.goto(`${U.HOST}/stadt.html?debug&seed=${seed}&tage=${tage}&neu`);
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await ev(() => __stadt.setzeTempo(0));
  // Die Tech-Firma mit den meisten Leuten, 11 Uhr, Kamera davor
  const firma = await ev(() => {
    // Die Figuren bei der Arbeit wählt die Oberfläche um 8 Uhr nach Nähe zum Blickpunkt (Annahme 62): Kamera schon um 7 Uhr auf die Firma
    // (seit der zweiten Gegenprüfung von Schritt 2 liegt die größte Firma der Teststadt weiter vom Startblick weg)
    const a = __stadt; while (a.S().stunde !== 7) a.schritt(); a.nachSchritten();
    // Version 10 (Etappe 2): Die Teststadt läuft anders; die größte Tech-Firma an Tag 420 ist jetzt ein Autowerk (Vega Autos, Stufe 3), dessen
    // Leute auf dem Werksgelände stehen und dessen Karte „Baut …“ statt „Arbeitet an der Software …“ sagt. Geprüft wird hier, wofür der Test
    // gebaut ist: die größte Tech-Firma ohne Autowerk (Glasbau, Programmierer, Bildschirme, Handys); Autowerke prüft tests/autos_bild.cjs
    const S = a.S(), Sim = a.Sim; let best = -1;
    for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.TECH && !S.g.werk[b] && !S.g.leer[b] && S.feld[S.g.y[b] * S.karte + S.g.x[b]] === Sim.TECH && (best < 0 || S.belegschaft[b].length > S.belegschaft[best].length)) best = b;
    if (best < 0) return null;
    // Kamera steil von oben (seit den Kitas steht in der Teststadt ein Wohnturm vor der Firma, flach traf der Klick ihn)
    const c = a.G.controls, x = S.g.x[best] - (S.mitte ?? 48) + 0.5, z = S.g.y[best] - (S.mitte ?? 48) + 0.5; c.target.set(x, 0.5, z); a.G.camera.position.set(x + 2.0, 8.5, z + 2.6); c.update();
    while (a.S().stunde !== 11) a.schritt(); a.nachSchritten();
    a.G.figurenBewegen(S.tag * 24 + 11.5);
    const T = a.G.test, P = S.p;
    let prog = 0, progAmOrt = 0, farbeOk = 0; const m4 = new a.G.THREE.Matrix4(), v = new a.G.THREE.Vector3(), c3 = new a.G.THREE.Color();
    for (let i = 0; i < T.figuren.length; i++) {
      const p = T.figIds[i]; if (p < 0 || P.arbeit[p] < 0 || S.g.typ[P.arbeit[p]] !== Sim.TECH) continue;
      const f = T.figuren[i], jetzt = S.tag * 24 + 11.5;
      if (f.route && jetzt >= f.start && jetzt < f.start + f.dauer) continue;        // läuft gerade: wie in p7figuren nicht prüfen
      prog++;
      a.G.figMesh.getMatrixAt(i, m4); v.setFromMatrixPosition(m4);
      const o = T.simOrt(p, 11);
      if (Math.hypot(v.x - (S.g.x[o] - (S.mitte ?? 48) + 0.5), v.z - (S.g.y[o] - (S.mitte ?? 48) + 0.5)) <= 0.9) progAmOrt++;
      a.G.figMesh.getColorAt(i, c3); if (T.figuren[i].haupt || c3.getHexString() === 'a78cf2') farbeOk++;
    }
    const fi = T.fenster();
    return { b: best, name: Sim.gebaeudeInfo(S, best).titel, leute: S.belegschaft[best].length, stufe: S.g.stufe[best], produkt: S.g.produkt[best],
      prog, progAmOrt, farbeOk, schirme: fi.schirme, handys: fi.count - fi.statisch - fi.schirme, tag: S.tag };
  });
  ok(!!firma, 'Tech-Firma gefunden: ' + JSON.stringify(firma));
  ok(firma.prog > 0 && firma.progAmOrt === firma.prog && firma.farbeOk === firma.prog, `Programmierer-Figuren, die stehen: ${firma.prog}, davon dort, wo die Simulation sie hat: ${firma.progAmOrt}, in Lila (oder Gold als Hauptfigur): ${firma.farbeOk}`);
  ok(firma.schirme > 0, `leuchtende Bildschirme vor den Programmierern: ${firma.schirme}`);
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUT + 'p8_tech_tag.png' });
  // Verluste als erledigt markieren, sonst öffnet der KI-Takt den Nachfolge-Dialog später erneut über dem Klickpunkt (den Dialog prüft p4test)
  const zu = () => ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S); for (const d of document.querySelectorAll('dialog[open]')) d.close(); });
  await zu(); await page.waitForTimeout(500); await zu();
  // Klick auf die Firma → Hauskarte (Version 8: Geschosse wie TECH_GESCHOSSE der Darstellung, Stufe 4 Campus, 5 Hochhaus)
  // Version 9, Teil 4: Mit dem Anlauf ist die Teststadt an Tag 420 eine andere; die größte Firma ist wieder ein Campus, dessen Mitte
  // der Hof ist (Rasen und Baum, nicht klickbar), und ein fester Punkt knapp unter der Oberkante traf daneben. Deshalb sucht der Test
  // über dem Gelände (Raster 0,1 Felder, Höhe 75 %, 50 %, 90 %, 30 % der Oberkante aus techHoehe) den ersten Bildpunkt, dessen Strahl
  // zuerst (vor allen anderen sichtbaren Meshes der Szene) das Glas genau dieser Firma trifft, und klickt dort wie ein Mensch
  const xy = await ev((b) => { const a = __stadt, S = a.S(), G = a.G, T = G.THREE, r = document.getElementById('szene').getBoundingClientRect();
    const cx = S.g.x[b] - (S.mitte ?? 48) + 0.5, cz = S.g.y[b] - (S.mitte ?? 48) + 0.5, h = G.test.techHoehe(b);
    G.camera.updateMatrixWorld();
    const ray = new T.Raycaster(), ms = Object.values(G.M).filter(m => m.visible && m.count > 0), p = new T.Vector2(), v = new T.Vector3();
    for (const f of [0.75, 0.5, 0.9, 0.3]) for (let i = -3; i <= 3; i++) for (let j = -3; j <= 3; j++) {
      v.set(cx + i * 0.1, f * h, cz + j * 0.1).project(G.camera);
      p.set(v.x, v.y); ray.setFromCamera(p, G.camera);
      const t = ray.intersectObjects(ms, false)[0];
      if (t && t.object === G.M.tech && Math.abs(t.point.x - cx) < 0.5 && Math.abs(t.point.z - cz) < 0.5)
        return { x: (v.x + 1) / 2 * r.width + r.left, y: (1 - v.y) / 2 * r.height + r.top, hoehe: +(f * h).toFixed(2), di: i, dj: j };
    }
    return null; }, firma.b);
  ok(!!xy, 'Bildpunkt, dessen Strahl zuerst das Glas der Firma trifft: ' + JSON.stringify(xy));
  await page.mouse.move(xy.x, xy.y); await page.mouse.down(); await page.mouse.up();
  console.log('     Klickpunkt', JSON.stringify(xy), await ev(({x, y}) => { const e = document.elementFromPoint(x, y); return e ? e.tagName + '#' + e.id : null; }, xy));
  await page.waitForTimeout(200);
  const haus = await ev(() => document.getElementById('karte-inhalt').innerText);
  ok(haus.includes(firma.name) && /Arbeitet (an der Software|am Handy|am Computer)/.test(haus) && /Stufe/.test(haus) && /Programmierer/.test(haus), 'Hauskarte nach Klick: ' + haus.split('\n').slice(0, 7).join(' | '));
  await page.screenshot({ path: OUT + 'p8_hauskarte.png' });
  // Eine Programmiererin aus der Liste öffnen → Personenkarte (die erste, die heute programmiert: nicht wer frei hat, nicht die Besitzerin)
  await page.locator('#karte-inhalt .personenliste li').filter({ hasText: /Programmierer(in)?\s*$/ }).first().locator('button.name').click();
  await page.waitForTimeout(150);
  const person = await ev(() => document.getElementById('karte-inhalt').innerText);
  ok(/arbeitet als Programmierer(in)? bei /.test(person) && /Heute: schreibt Code für/.test(person) && /von \d+ Arbeitstagen/.test(person), 'Personenkarte: ' + person.split('\n').slice(0, 5).join(' | '));
  await page.screenshot({ path: OUT + 'p8_person.png' });
  // Hauptfigur, die programmiert → schreibt Code ins Tagebuch (Attrappe), wird nur angezeigt
  // (Version 8, Schlussprüfung: im neuen Verlauf ist die erste Kraft schon Hauptfigur; genommen wird die erste, die es noch nicht ist)
  const haupt = await ev((b) => { const a = __stadt, S = a.S(); const p = S.belegschaft[b].find(x => !S.p.frei[x] && !a.Sim.istHaupt(S, x));
    const ok = a.Sim.hauptSetzen(S, p, S.p.gen[p], true, 10); a.nachSchritten(); return { p, gen: S.p.gen[p], ok, name: a.Sim.name(S, p) }; }, firma.b);
  ok(haupt.ok, 'Hauptfigur gesetzt: ' + haupt.name);
  await page.waitForFunction((h) => (__stadt.S().ki.tagebuch[h.p + '/' + h.gen] || []).some(e => e.art === 'code'), haupt, { timeout: 30000 }).catch(() => {});
  const code = await ev((h) => { const a = __stadt; return { code: a.ki.stat.code, status: a.ki.status, fehler: a.ki.letzterFehler,
    eintrag: (a.S().ki.tagebuch[h.p + '/' + h.gen] || []).filter(e => e.art === 'code').at(-1) || null }; }, haupt);
  ok(code.code >= 1 && code.eintrag && code.eintrag.code.includes('akku'), `Code im Tagebuch: ${code.code} (${code.status}${code.fehler ? ', ' + code.fehler : ''})`);
  const req = chat.find(c => c.sys.includes('Stück Code'));
  if (req) require('fs').writeFileSync(OUT + 'p8_code_anfrage.txt', 'SYSTEM:\n' + req.sys + '\n\nUSER:\n' + req.user + '\n');
  ok(req && req.format === 'json' && req.stream === false && req.think === false && /arbeitest gerade als Programmierer/.test(req.sys) && /Arbeitstagen/.test(req.sys),
    'Anfrage an /api/chat: format json, stream false, think false; Anweisung nennt Beruf, Firma, Version, Arbeitstage');
  await ev((h) => { document.querySelector(`#haupt-liste .haupt-zeile[data-p="${h.p}"]`).click(); }, haupt);
  await page.waitForTimeout(200);
  const tb = await ev(() => { const pre = document.querySelector('#karte pre.code'); return { pre: !!pre, text: pre ? pre.textContent : '', scripts: document.querySelectorAll('#karte script').length,
    meta: [...document.querySelectorAll('#karte .tagebuch .meta')].map(m => m.textContent).at(-1), leiste: document.getElementById('haupt-liste').innerText }; });
  ok(tb.pre && tb.text.includes('<script>alert(1)</script>') && tb.scripts === 0 && dialoge.length === 0, `Code als Text angezeigt (auch „<script>“), nichts ausgeführt; Kopf: ${tb.meta}`);
  ok(/schreibt Code: Akku-Anzeige/.test(tb.leiste), 'Leiste oben rechts zeigt „schreibt Code: …“');
  await page.evaluate(() => { const t = document.querySelector('#karte .tagebuch'); if (t) { t.scrollTop = t.scrollHeight; t.scrollIntoView({ block: 'start' }); } });
  await page.waitForTimeout(150);
  await page.screenshot({ path: OUT + 'p8_code.png' });
  // Käufe: jemand mit Handy → Personenkarte zeigt es; Handys in der Hand, wenn Leute gehen (8 Uhr)
  const kauf = await ev(() => { const a = __stadt, S = a.S(); let p = -1; for (let i = 0; i < S.pMax; i++) if (S.p.lebt[i] && S.p.geraet[i] === a.Sim.HANDY) { p = i; break; }
    const i = p >= 0 ? a.Sim.personInfo(S, p) : null; return i ? { p, gen: i.gen, technik: i.technik } : null; });
  ok(kauf && kauf.technik.length > 0, 'Jemand mit Handy: ' + JSON.stringify(kauf && kauf.technik));
  const hand = await ev(() => { const a = __stadt, S = a.S(); let max = 0, mitHandy = 0;
    while (S.stunde !== 17) a.schritt(); a.nachSchritten();
    for (const t of [17.1, 17.3, 17.5, 17.7]) { a.G.figurenBewegen(S.tag * 24 + t); const fi = a.G.test.fenster(); max = Math.max(max, fi.count - fi.statisch - fi.schirme); }
    for (const f of a.G.test.figuren) if (f.p >= 0 && S.p.geraet[f.p] === a.Sim.HANDY) mitHandy++;
    return { max, mitHandy }; });
  ok(hand.max > 0, `Handys in der Hand um 17 Uhr: bis ${hand.max} (Figuren mit Handy: ${hand.mitHandy})`);
  // Draw Calls
  await ev(() => { document.getElementById('karte-zu').click(); });
  const dbg = await ev(() => { __stadt.setzeTempo(1); return new Promise(r => setTimeout(() => r(globalThis.__stadtDebug), 1300)); });
  ok(dbg.calls <= 30, `Draw Calls ${dbg.calls} (≤ 30), Dreiecke ${dbg.dreiecke}, Einwohner ${dbg.einwohner}`);
  await ev(() => __stadt.setzeTempo(0));
  // Nacht: Serverraum leuchtet oben
  await ev((b) => { const a = __stadt, S = a.S(); while (S.stunde !== 22) a.schritt(); a.nachSchritten();
    const c = a.G.controls, x = S.g.x[b] - (S.mitte ?? 48) + 0.5, z = S.g.y[b] - (S.mitte ?? 48) + 0.5; c.target.set(x, 0.5, z); a.G.camera.position.set(x + 4, 4.5, z + 5.5); c.update(); a.G.figurenBewegen(S.tag * 24 + 22.2); }, firma.b);
  await page.waitForTimeout(300);
  await page.evaluate(() => { for (const id of ['rechts', 'kennzahlen', 'debug', 'debug-knoepfe']) { const e = document.getElementById(id); if (e) e.style.visibility = 'hidden'; } });
  await page.screenshot({ path: OUT + 'p8_nacht.png' });
  await page.evaluate(() => { for (const id of ['rechts', 'kennzahlen', 'debug', 'debug-knoepfe']) { const e = document.getElementById(id); if (e) e.style.visibility = ''; } });
  // Anbau: bis eine Firma beim Bauhof bestellt; Baustelle mit Bauarbeitern, Rohbau oben, Gerüst
  const anbau = await ev(() => { const a = __stadt, S = a.S(), g = S.g, T = a.Sim.TECH; const vor = S.stat.tech.anbauten; let b = -1;
    for (let n = 0; n < 24 * 300 && b < 0; n++) { a.schritt(); if (S.stunde === 11 && S.stat.tech.anbauten > vor) for (const x of S.baustellen) if (g.typ[x] === T && g.auf[x] && g.bauLeute[x] > 0) b = x; }
    a.nachSchritten(); if (b < 0) return { b };
    const c = a.G.controls, x = g.x[b] - (S.mitte ?? 48) + 0.5, z = g.y[b] - (S.mitte ?? 48) + 0.5; c.target.set(x, 0.6, z); a.G.camera.position.set(x + 3.5, 4, z + 4.5); c.update(); a.G.figurenBewegen(S.tag * 24 + 11.5);
    const buch = S.buch.filter(e => e.art === 'auftrag').at(-1);
    return { b, tag: S.tag, stufe: g.stufe[b], auf: g.auf[b], leute: g.bauLeute[b], rest: g.bauRest[b], buch: buch ? a.Sim.klartext(buch.text) : '' }; });
  ok(anbau.b >= 0 && anbau.leute > 0 && /gibt dem Bauhof einen Auftrag/.test(anbau.buch), 'Anbau: ' + JSON.stringify(anbau));
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUT + 'p8_anbau.png' });
  console.log('Konsole:', log.length ? '\n  ' + log.join('\n  ') : 'leer');
  if (log.length) process.exitCode = 1;
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
