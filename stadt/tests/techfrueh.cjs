// Tech-Firmen früher und mehr (Version 9, Teil 5) im Browser: Teststadt Seed 1 an Tag 420 mit Tech-Firmen im Umland und in der Welt;
// Hauskarte einer Firma in der Welt und einer im Umland (Markt und Preis je Arbeitstag wie Sim, „Ein Anbau … kommt“ im Nominativ), Fenster
// „Stadtregierung“ (Karte „Weltmarkt …“ mit Live-Zeile wie Sim.techInfo, R-A5 als Auslegung mit den Sätzen je Arbeitstag, Spielregel-Karte,
// S. 16 unter „Keine Zahl“, Stufen mit „Tech-Firmen, sobald Tüftler sie gründen“), Fenster „Haushalt“ (Computer der Schulen als Bedarf vor
// den drei Vorhaben), Stadtbuch (neue Zeile „Aufgegeben“ für einen Betrieb, der nie jemanden fand), Übernahme eines Stands der Version 8
// (Text im Versionsdialog, alle Firmen im Umland, freie Tech-Stellen nachgezählt; Dialog am Handy ohne Scrollen), Handy 400 × 820 ohne
// seitliches Überlaufen, Draw Calls gegen stadt.orig.html (höchstens +3), Konsole.
// Server: tests/alle.sh (PORT, Wurzel stadt/). Bilder: tests/ausgabe/bilder_befunde/techfrueh_*.png
const U = require('./umgebung.cjs');
const { chromium } = U;
const fs = require('fs');
const BILD = U.ordner('bilder_befunde');
fs.mkdirSync(BILD, { recursive: true });
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
async function seite(b, url, viewport, stand) {
  const ctx = await b.newContext({ viewport: viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  await U.fassungUnter(ctx, 'v8');   // stadt.orig.html = Version 8 (Git 31ce452) per git show, Vergleichsstand wie im Bau von Version 9
  await ctx.route('http://localhost:11434/**', (route) => route.abort());
  if (stand) await ctx.addInitScript((t) => { try { if (!sessionStorage.getItem('gesetzt')) { localStorage.clear(); localStorage.setItem('stadt-save-v1', t); sessionStorage.setItem('gesetzt', '1'); } } catch {} }, stand);
  const page = await ctx.newPage();
  const log = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type()) && !/ERR_FAILED|GPU stall|GroupMarkerNotSet|software WebGL/.test(m.text())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  await page.goto(url, { timeout: 600000 });
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug, null, { timeout: 600000 });
  await page.evaluate(() => __stadt.setzeTempo(0));
  const ev = (f, a) => page.evaluate(f, a);
  const zu = async () => { for (let i = 0; i < 30; i++) {
    const o = await ev(() => { const S = __stadt.S(); while (S.ki.verlust.length) __stadt.Sim.verlustErledigt(S);
      for (const d of document.querySelectorAll('dialog[open]')) d.close(); return document.querySelectorAll('dialog[open]').length; });
    await page.waitForTimeout(100); if (!o) break; } };
  return { ctx, page, log, ev, zu };
}
// Hauskarte von Gebäude b öffnen (wie ein Klick auf einen Hausnamen) und Titel, Text, Überlaufen lesen
const hauskarte = (ev, b) => ev((b) => { const k = document.createElement('button'); k.className = 'haus'; k.dataset.b = b; document.body.append(k); k.click(); k.remove();
  const karte = document.getElementById('karte'), el = [...karte.querySelectorAll('*')];
  return { offen: !karte.hidden, titel: (karte.querySelector('h2') || {}).textContent || '', text: document.getElementById('karte-inhalt').innerText,
    breit: document.documentElement.scrollWidth, fenster: innerWidth,
    zuBreit: el.filter(e => e.scrollWidth > e.clientWidth + 1 && !['visible', 'hidden'].includes(getComputedStyle(e).overflowX)).length }; }, b);
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

  // 1. Teststadt Seed 1, Tag 420 (breit)
  const A = await seite(b, U.HOST + '/stadt.html?debug&seed=1&tage=420&neu');
  await A.zu();
  const s = await A.ev(() => { const S = __stadt.S(), Sim = __stadt.Sim, g = S.g, i = Sim.techInfo(S), welt = [], umland = [], n = [0, 0];
    for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === Sim.TECH && !g.leer[b] && g.besitzer[b] >= 0 && S.feld[g.y[b] * S.karte + g.x[b]] === Sim.TECH) {
      n[g.markt[b]]++; if (!g.werk[b]) (g.markt[b] ? welt : umland).push(b); }   // gezählt wie techInfo (mit Autowerken), Hauskarten ohne Werke
    return { i, welt, umland, n, weltPreis: Math.round(S.weltPreis), umlandPreis: Math.round(S.exportPreis), stufe: S.erweiterung.stufe, tag: S.tag }; });
  ok(s.i.an && s.i.welt === 12000 && s.i.weltFirmen > 0 && s.i.umlandFirmen > 0 && s.n[1] === s.i.weltFirmen && s.n[0] === s.i.umlandFirmen && s.welt.length > 0 && s.umland.length > 0
    && s.i.techPlaetze <= 0.4 * s.i.umlandPlaetze + 1e-9 && s.i.weltPreis >= s.i.lohn + 8 - 1e-9,
    `Seed 1, Tag ${s.tag}: ${s.i.umlandFirmen} Tech-Firmen im Umland, ${s.i.weltFirmen} in der Welt (${s.i.weltPlaetze} Stellen, ${s.weltPreis} Taler je Arbeitstag); `
    + `Tech-Anteil im Umland ${Math.round(100 * s.i.techPlaetze / s.i.umlandPlaetze)} % (Grenze 40 %)`);
  // Hauskarte: Markt und Preis wie die Simulation
  const kw = await hauskarte(A.ev, s.welt[0]), ku = await hauskarte(A.ev, s.umland[0]);
  ok(kw.offen && new RegExp(`Verkauft in die Welt \\(Weltmarkt\\): Die Welt zahlt ${s.weltPreis} Taler je Arbeitstag, weniger, je mehr die Stadt dorthin liefert\\.`).test(kw.text)
    && !/Das Umland zahlt/.test(kw.text), `Hauskarte „${kw.titel}“ (Welt): „Verkauft in die Welt (Weltmarkt): Die Welt zahlt ${s.weltPreis} Taler je Arbeitstag …“`);
  await A.page.waitForTimeout(300);
  await A.page.screenshot({ path: BILD + 'techfrueh_karte_welt.png' });
  ok(ku.offen && new RegExp(`Das Umland zahlt ${s.umlandPreis} Taler je Arbeitstag\\.`).test(ku.text) && !/Verkauft in die Welt/.test(ku.text),
    `Hauskarte „${ku.titel}“ (Umland): „Das Umland zahlt ${s.umlandPreis} Taler je Arbeitstag.“`);
  // „… kommt, wenn …“ im Nominativ (Nebenbefund des Entwurfs): in allen Firmen der Stadt
  let kommt = 0, akk = 0;
  for (const x of s.welt.concat(s.umland)) { const k = await hauskarte(A.ev, x); if (/\(\d[\d.]* Taler\) kommt, wenn/.test(k.text)) kommt++; if (/Einen (Anbau|Campus|Hochhaus)[^.]*\) kommt, wenn/.test(k.text)) akk++; }
  ok(kommt > 0 && akk === 0, `„Ein Anbau / Ein Campus / Ein Hochhaus (… Taler) kommt, wenn …“: ${kommt} Karten, ${akk} mit „Einen …“`);
  await A.zu();

  // Fenster „Stadtregierung“
  await A.page.click('#regierung-knopf'); await A.page.waitForTimeout(500);
  const r = await A.ev(() => { const box = document.getElementById('regierung-inhalt'), karten = [...box.querySelectorAll('.reg-karte')];
    // textContent: auch der aufklappbare Teil (dort stehen seit Teil 5 die Preise der Tech-Firmen)
    const karte = (re) => { const k = karten.find(x => re.test(x.querySelector('h4 span').textContent)); return k ? { text: k.textContent, status: (k.querySelector('.reg-status') || {}).textContent || '',
      live: (k.querySelector('p.reg-live') || { textContent: '' }).textContent, zitate: [...k.querySelectorAll('blockquote cite')].map(c => c.textContent) } : null; };
    const auf = box.textContent;                               // auch zugeklappte Teile (innerText liest sie nicht)
    return { welt: karte(/^Weltmarkt für Software, Handys und Computer$/), a5: karte(/^R-A5 /), regel: karte(/^Tech-Firmen wachsen, Autowerke, Autos$/),
      stufen: karte(/Stadt erweitern|Die Karte wächst|Stufen/), auf, alles: box.innerText, i: __stadt.Sim.techInfo(__stadt.S()) }; });
  const i = r.i;
  const liveSoll = `Heute ${i.umlandFirmen === 1 ? '1 Tech-Firma verkauft' : `${i.umlandFirmen} Tech-Firmen verkaufen`} ans Umland und ${i.weltFirmen} in die Welt`;
  ok(!!r.welt && /Spielregel/.test(r.welt.status) && r.welt.zitate.join() === 'S. 11' && r.welt.live.startsWith(liveSoll) && /Die 40-%-Grenze gilt nur fürs Umland/.test(r.welt.text)
    && /Kein Geld der Stadt/.test(r.welt.text) && /R10/.test(r.welt.text),
    `Karte „Weltmarkt …“ (${r.welt ? r.welt.status : '–'}, Zitat ${r.welt ? r.welt.zitate.join() : '–'}): live „${r.welt ? r.welt.live.slice(0, 120) : '–'}…“`);
  ok(!!r.a5 && /Auslegung/.test(r.a5.status) && /166⅔ Taler je Arbeitstag/.test(r.a5.text) && /133⅓ Taler/.test(r.a5.text) && /200 Taler je Arbeitstag/.test(r.a5.text)
    && /Campus kostet damit 3\.333 statt 5\.000 Taler, das Hochhaus 4\.000 statt 8\.000/.test(r.a5.text) && /Alle Sätze sind Spielannahmen ohne Quelle/.test(r.a5.text),
    `Karte R-A5 (${r.a5 ? r.a5.status : '–'}): drei Sätze je Arbeitstag offen genannt (133⅓, 166⅔, 200), Campus 3.333 und Hochhaus 4.000 Taler (Befund „selektiv“)`);
  ok(!!r.regel && /ab der Kleinstadt/.test(r.regel.text) && /spart so jemand weiter/.test(r.regel.text) && /12 oder mehr Stellen nicht besetzt bekommen/.test(r.regel.text)
    && /Campus 3\.333, Hochhaus 4\.000 Taler/.test(r.regel.text), 'Spielregel-Karte „Tech-Firmen wachsen, Autowerke, Autos“: ab der Kleinstadt, Tüftler sparen, 12 freie Stellen, Preise');
  ok(/Gründungen hängen in der Stadt an Umland und Weltmarkt, nicht an Vorschriften der Stadt/.test(r.auf) && /Spielregeln für Gründer, keine Vorschriften/.test(r.auf),
    'S. 16 unter „Keine Zahl …“: Kleinstadt und Bremse als Spielregeln für Gründer, keine Vorschriften der Stadt (Befund der Gegenprüfung)');
  ok(/Mit der Stufe Kleinstadt kam: [^.]*Tech-Firmen, sobald Tüftler sie gründen/.test(r.alles) && /Autowerke, sobald eine große Tech-Firma eins baut/.test(r.alles),
    'Stufen im Fenster: Kleinstadt „Tech-Firmen, sobald Tüftler sie gründen“, Stadt „Autowerke, sobald eine große Tech-Firma eins baut“');
  await A.ev(() => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => /^Weltmarkt/.test(x.querySelector('h4 span').textContent)); k.scrollIntoView({ block: 'start' }); });
  await A.page.waitForTimeout(300);
  await A.page.screenshot({ path: BILD + 'techfrueh_regierung.png' });
  await A.zu();

  // Fenster „Haushalt“: Computer der Schulen als Bedarf vor den drei Vorhaben
  await A.page.click('#haushalt-knopf'); await A.page.waitForTimeout(500);
  const h = await A.ev(() => { const box = document.getElementById('haushalt-inhalt'), karten = [...box.querySelectorAll('section.reg-karte')];
    const bed = karten.find(k => /vor allen Vorhaben$/.test(k.querySelector('h4').textContent)), hi = __stadt.Sim.haushaltInfo(__stadt.S());
    return { bed: bed ? { h4: bed.querySelector('h4').textContent, text: bed.innerText } : null, rang: [...box.querySelectorAll('.hh-rang > li h4')].map(x => x.textContent),
      regal: hi.bedarf.itRegal, aussen: hi.bedarf.itAussen, einl: box.innerText }; });
  ok(!!h.bed && /^Computer für die Schulen/.test(h.bed.h4) && /Das ist Bedarf, keine Frage der Rangfolge/.test(h.bed.text)
    && (h.regal ? new RegExp(`Im Regal der Läden liegt der neueste Computer von ${h.regal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`).test(h.bed.text) : /Im Regal liegt kein Computer einer Firma der Stadt/.test(h.bed.text))
    && new RegExp(`davon ${h.aussen} von außerhalb`).test(h.bed.text) && h.rang.length === 3 && !h.rang.some(x => /Computer/.test(x)),
    `Fenster „Haushalt“: „${h.bed ? h.bed.h4 : '–'}“ als Bedarf (${h.regal ? 'im Regal: ' + h.regal : 'kein Computer der Stadt im Regal'}, ${h.aussen} von außerhalb); Rangfolge: ${h.rang.join(', ')}`);
  await A.ev(() => { const k = [...document.querySelectorAll('#haushalt-inhalt section.reg-karte')].find(x => /vor allen Vorhaben$/.test(x.querySelector('h4').textContent)); if (k) k.scrollIntoView({ block: 'start' }); });
  await A.page.waitForTimeout(300);
  await A.page.screenshot({ path: BILD + 'techfrueh_haushalt.png' });
  await A.zu();

  // Draw Calls um 11 Uhr gegen stadt.orig.html (derselbe Seed und Tag; der Baustein zeichnet nichts Neues, die Stadt ist aber eine andere)
  // Draw Calls hängen daran, welche Meshes gerade Instanzen haben (ein leeres Instanz-Mesh zeichnet nichts): Die Städte der beiden Fassungen sind
  // an Tag 420 verschieden groß und verschieden weit (Schule, Rathausdach, Leuchtlogo eines Hochhauses). Geprüft wird deshalb: gezeichnet höchstens
  // 32, und die Szene hat höchstens 3 Meshes mehr als 31ce452 (so viele Draw Calls kann es höchstens mehr geben); Teil 5 bringt keins dazu
  const dc = async (X) => { await X.ev(() => { const a = __stadt, S = a.S(); let n = 0; while (S.stunde !== 11 && n++ < 30) a.schritt(); a.nachSchritten(); a.G.controls.target.set(0, 0, 0); a.G.camera.position.set(8, 30, 34); a.G.controls.update(); });
    await X.page.waitForTimeout(500);
    return X.ev(() => { const G = __stadt.G, calls = G.render().calls, alle = G.scene.children.filter(o => o.visible && (o.isMesh || o.isPoints));
      return { calls, szene: alle.length, gez: alle.filter(o => !o.isInstancedMesh || o.count > 0).map(o => Object.keys(G.M).find(k => G.M[k] === o) || o.type) }; }); };
  const cNeu = await dc(A);
  await A.page.screenshot({ path: BILD + 'techfrueh_stadt.png' });
  if (A.log.length) { console.log('Konsole (breit):\n  ' + A.log.join('\n  ')); process.exitCode = 1; } else console.log('Konsole (breit): leer');
  await A.ctx.close();
  const O = await seite(b, U.HOST + '/stadt.orig.html?debug&seed=1&tage=420&neu');
  await O.zu();
  const cOrig = await dc(O);
  await O.ctx.close();
  const anders = [...new Set(cNeu.gez.concat(cOrig.gez))].map(k => [k, cNeu.gez.filter(x => x === k).length, cOrig.gez.filter(x => x === k).length]).filter(([, x, y]) => x !== y);
  ok(cNeu.calls <= 32 && cNeu.szene <= cOrig.szene + 3, `Draw Calls Seed 1, Tag 420, 11 Uhr: ${cNeu.calls} (stadt.orig.html ${cOrig.calls}; höchstens 32); Meshes in der Szene ${cNeu.szene} gegen ${cOrig.szene} (höchstens +3); `
    + `anders gezeichnet: ${anders.map(([k, x, y]) => `${k} ${y}→${x}`).join(', ') || '–'}`);

  // Stadtbuch (Seed 1 ab Tag 140; aufgegeben wird vor allem zwischen Tag 100 und 270): weiter, bis ein Betrieb aufgibt, der nie jemanden fand;
  // die Zeile heißt „Aufgegeben“, nicht „Pleite“
  const B = await seite(b, U.HOST + '/stadt.html?debug&seed=1&tage=140&neu');
  await B.zu();
  const bu = await B.ev(() => { const a = __stadt, S = a.S(), n0 = S.buchNr; let e = null, n = 0;
    while (!e && n++ < 24 * 60) { a.schritt(); e = S.buch.find(x => x.nr > n0 && x.art === 'aufgabe'); }
    a.nachSchritten();
    const li = e ? [...document.querySelectorAll('#buch-liste li')].find(x => x.innerText.includes('fand keine Leute')) : null;
    return { e: e ? { tag: e.tag, text: a.Sim.klartext(e.text) } : null, li: li ? li.innerText.replace(/\s+/g, ' ') : '', sym: li && li.querySelector('use') ? li.querySelector('use').getAttribute('href') : '',
      pleiteOhne: S.buch.filter(x => x.nr > n0 && x.art === 'pleite' && /keine der \d+ Stellen war je besetzt/.test(x.text)).length }; });
  ok(!!bu.e && /gibt nach \d+ Tagen im Minus auf: (Sie|Er) fand keine Leute, keine der \d+ Stellen war je besetzt\./.test(bu.e.text) && /Aufgegeben/.test(bu.li) && !/Pleite/.test(bu.li)
    && bu.sym === '#s-schloss' && bu.pleiteOhne === 0, `Stadtbuch an Tag ${bu.e ? bu.e.tag : '–'}: „${bu.li.slice(0, 170)}…“ (Symbol ${bu.sym})`);
  await B.page.screenshot({ path: BILD + 'techfrueh_buch.png' });

  if (B.log.length) { console.log('Konsole (Stadtbuch):\n  ' + B.log.join('\n  ')); process.exitCode = 1; }
  await B.ctx.close();

  // 2. Handy 400 × 820: Hauskarte einer Firma in der Welt, Fenster „Stadtregierung“ bei der Karte „Weltmarkt“, ohne seitliches Überlaufen
  const H = await seite(b, U.HOST + '/stadt.html?debug&seed=1&tage=420&neu', { width: 400, height: 820 });
  await H.zu();
  const hw = await H.ev(() => { const S = __stadt.S(), g = S.g; for (let b = 0; b < S.gAnzahl; b++) if (g.typ[b] === __stadt.Sim.TECH && !g.leer[b] && g.markt[b] && !g.werk[b]) return b; return -1; });
  const hk = await hauskarte(H.ev, hw);
  await H.page.waitForTimeout(300);
  await H.page.screenshot({ path: BILD + 'techfrueh_karte_handy.png' });
  ok(hk.offen && /Verkauft in die Welt/.test(hk.text) && hk.breit <= hk.fenster && !hk.zuBreit, `Handy: Hauskarte „${hk.titel}“, Seite ${hk.breit} px breit (Fenster ${hk.fenster}), ${hk.zuBreit} Elemente mit seitlichem Scrollen`);
  await H.zu();
  await H.page.click('#regierung-knopf'); await H.page.waitForTimeout(500);
  const hr = await H.ev(() => { const k = [...document.querySelectorAll('#regierung-inhalt .reg-karte')].find(x => /^Weltmarkt/.test(x.querySelector('h4 span').textContent)); k.scrollIntoView({ block: 'start' });
    const d = document.getElementById('regierung-dialog'), el = [...d.querySelectorAll('*')];
    return { breit: document.documentElement.scrollWidth, fenster: innerWidth, dialog: Math.round(d.getBoundingClientRect().width), karte: Math.round(k.getBoundingClientRect().right),
      zuBreit: el.filter(e => e.scrollWidth > e.clientWidth + 1 && !['visible', 'hidden'].includes(getComputedStyle(e).overflowX)).length }; });
  await H.page.waitForTimeout(300);
  await H.page.screenshot({ path: BILD + 'techfrueh_regierung_handy.png' });
  ok(hr.breit <= hr.fenster && hr.karte <= hr.fenster && !hr.zuBreit, `Handy: Fenster „Stadtregierung“ bei „Weltmarkt“, Seite ${hr.breit} px (Fenster ${hr.fenster}), Karte bis ${hr.karte} px, ${hr.zuBreit} Elemente mit seitlichem Scrollen`);
  if (H.log.length) { console.log('Konsole (Handy):\n  ' + H.log.join('\n  ')); process.exitCode = 1; }
  await H.ctx.close();

  // 3. Stand der Version 8 übernehmen (tests/basis_v8.json): Satz im Versionsdialog, alle Firmen im Umland, freie Tech-Stellen nachgezählt;
  //    am Handy passt der Dialog ohne Scrollen
  const d8 = JSON.parse(fs.readFileSync(U.basis('basis_v8.json'), 'utf8')); d8.zuletztGelaufen = Date.now(); d8.tempo = 0;
  for (const [vp, name] of [[{ width: 1280, height: 800 }, 'breit'], [{ width: 400, height: 820 }, 'handy']]) {
    const V = await seite(b, U.HOST + '/stadt.html?debug', vp, JSON.stringify(d8));
    await V.page.waitForTimeout(500);
    const dlg = await V.ev(() => { const d = document.getElementById('version-dialog'), r = d.getBoundingClientRect();
      return { offen: d.open, text: document.getElementById('version-text').textContent, unten: Math.round(r.bottom), hoch: innerHeight, scroll: d.scrollHeight > d.clientHeight + 1 }; });
    await V.page.screenshot({ path: BILD + `techfrueh_version_${name}.png` });
    ok(dlg.offen && /Tech-Firmen gibt es ab der Kleinstadt, und sie verkaufen auch in die Welt\./.test(dlg.text) && dlg.unten <= dlg.hoch && !dlg.scroll,
      `Versionsdialog (${name}, Stand der Version 8): „…Tech-Firmen gibt es ab der Kleinstadt, und sie verkaufen auch in die Welt.“; unten bei ${dlg.unten} von ${dlg.hoch} px, ohne Scrollen`);
    if (name === 'breit') {
      await V.page.click('#version-uebernehmen');
      await V.page.waitForFunction(() => !document.getElementById('version-dialog').open, null, { timeout: 60000 });
      const u = await V.ev(() => { const S = __stadt.S(), g = S.g, i = __stadt.Sim.techInfo(S); let tf = 0, markt = 0;
        for (let b = 0; b < S.gAnzahl; b++) { if (g.markt[b]) markt++; if (g.typ[b] === __stadt.Sim.TECH && !g.leer[b] && g.besitzer[b] >= 0) tf += Math.max(0, __stadt.Sim.stellen(S, b) - S.belegschaft[b].length); }
        return { v: S.version, markt, tf, techFrei: S.techFrei, welt: i.weltFirmen, umland: i.umlandFirmen, weltPlaetze: S.weltPlaetze }; });
      ok(u.v === 9 && u.markt === 0 && u.welt === 0 && u.weltPlaetze === 0 && u.techFrei === u.tf, `übernommen: Version ${u.v}, ${u.umland} Tech-Firmen im Umland, ${u.welt} in der Welt, freie Tech-Stellen ${u.techFrei} (nachgezählt ${u.tf})`);
    }
    if (V.log.length) { console.log(`Konsole (Übernahme, ${name}):\n  ` + V.log.join('\n  ')); process.exitCode = 1; }
    await V.ctx.close();
  }
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
