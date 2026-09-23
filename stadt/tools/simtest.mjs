#!/usr/bin/env node
// Entwicklungswerkzeug, nicht Teil des Produkts.
// Zieht den <script id="sim">-Block aus stadt.html, führt ihn in einem leeren Kontext aus
// (kein window, kein document, kein fetch, kein THREE; Math.random, Date und Intl gesperrt;
// vorher eine statische Suche nach verbotenen Namen)
// und simuliert N Spieltage. Nur Node-Standardbibliothek.
//
//   node tools/simtest.mjs --seed 1 --tage 365      Tabelle alle 30 Tage + Charakter-Auswertung
//   node tools/simtest.mjs --gate                   Phase-0-Gate mit Seeds 1, 2, 3 (je 730 Tage)
//   node tools/simtest.mjs --speichertest           Speichern/Laden mitten am Tag: läuft danach bitgleich weiter?
//   node tools/simtest.mjs --aufholtest             90 Tage stündlich gegen 90 Tagesschritte
//   node tools/simtest.mjs --kitest                 Hauptfiguren: erlaubte Aktionen, Anfragen, Fristen, Tagebuch (ohne echtes Modell)
//   node tools/simtest.mjs --bau                    Bauhof: Einteilung, Fortschritt je Person, jede Baustelle wird fertig (Seeds 1–3)
//   node tools/simtest.mjs --waren                  Kisten: geliefert ≤ gemacht, Werkstatt-Einnahmen wie vorher (Seeds 1–3)
//   node tools/simtest.mjs --tech                   Tech-Firmen: Arbeitstage an der Version, Käufe im Laden, Anbau (Seeds 1–3, 730 Tage)
//   node tools/simtest.mjs --migrationstest         Spielstand von Version 2 oder 3 übernehmen (alte stadt.html aus git 39c405b
//                                                   oder --alt pfad/zur/alten/stadt.html), 60 Tage weiter, keine NaN
//   Optionen: --alle 30 (Zeilenabstand), --buch 20 (letzte Stadtbuch-Zeilen), --aktionen

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { performance } from 'node:perf_hooks';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const hier = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(hier, '..', 'stadt.html'), 'utf8');
const treffer = html.match(/<script id="sim">([\s\S]*?)<\/script>/);
if (!treffer) { console.error('Kein <script id="sim"> in stadt.html gefunden.'); process.exit(2); }
const SIM_CODE = treffer[1];

// Statische Prüfung: Kommentare entfernen, dann nach Namen suchen, die im sim-Block nichts zu suchen haben.
// Fängt auch Zugriffe, die im Lauf nie ausgeführt würden (z. B. hinter einem typeof-Test).
const VERBOTEN = /\b(window|document|fetch|THREE|localStorage|sessionStorage|indexedDB|performance|requestAnimationFrame|setTimeout|setInterval|XMLHttpRequest|Intl|Date|crypto|navigator|location|console)\b|Math\.random/;
function statischPruefen(code) {
  const ohneKommentare = code.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:\\])\/\/.*$/gm, '$1');
  const zeilen = ohneKommentare.split('\n');
  const treffer = [];
  zeilen.forEach((z, i) => { const m = z.match(VERBOTEN); if (m) treffer.push(`  Zeile ${i + 1} im sim-Block: ${m[0]} → ${z.trim().slice(0, 100)}`); });
  if (treffer.length) { console.error('Der sim-Block benutzt Verbotenes:\n' + treffer.join('\n')); process.exit(3); }
}
statischPruefen(SIM_CODE);

function ladeSim() {
  const ctx = vm.createContext({});
  vm.runInContext(`
    Math.random = function () { throw new Error('Math.random ist in der Simulation verboten'); };
    globalThis.Date = undefined;
    globalThis.Intl = undefined;
  `, ctx);
  vm.runInContext(SIM_CODE, ctx, { filename: 'stadt.html#sim' });
  if (!ctx.StadtSim) throw new Error('Der sim-Block hat kein StadtSim angelegt.');
  return ctx.StadtSim;
}

// ─── Argumente ───
const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const flag = (n) => args.includes('--' + n);

const f0 = (v) => Math.round(v).toString();
const pad = (s, n) => String(s).padStart(n);

// Simuliert einen Seed. Ruft proTag(S, k, ms) nach jedem Spieltag auf.
function lauf(Sim, seed, tage, proTag) {
  const S = Sim.neueStadt(seed);
  const t0 = performance.now();
  for (let d = 0; d < tage; d++) {
    const ziel = S.tag + 1;
    while (S.tag < ziel) Sim.stunde(S);
    proTag(S, Sim.kennzahlen(S), performance.now() - t0);
  }
  return S;
}

function charakter(S) {
  const st = S.stat;
  const erwE = st.erwEhrgeiz / st.erwachsene, erwH = st.erwHeimat / st.erwachsene;
  const grE = st.gruendungen ? st.gruenderEhrgeiz / st.gruendungen : NaN;
  const wzH = st.wegzuege ? st.wegzugHeimat / st.wegzuege : NaN;
  // Zusätzlich: heutige Erwachsene (strengere Vergleichsgruppe ist die obige: alle, die je erwachsen hier waren)
  const P = S.p;
  let n = 0, sE = 0, sH = 0;
  for (let p = 0; p < S.pMax; p++) {
    if (!P.lebt[p] || S.tag - P.geb[p] < 18 * Sim.R.JAHR) continue;
    n++; sE += P.ehrgeiz[p]; sH += P.heimat[p];
  }
  return { erwN: st.erwachsene, erwE, erwH, grN: st.gruendungen, grE, wzN: st.wegzuege, wzH,
    jetztN: n, jetztE: n ? sE / n : NaN, jetztH: n ? sH / n : NaN };
}

function tabelleKopf() {
  return '   Tag  Einw.  Geb.  Gründ.  Pleiten  frW  frSt  Zufr.  Budget   Laufzeit';
}
function tabelleZeile(k, ms) {
  return `${pad(k.tag, 6)} ${pad(k.einwohner, 6)} ${pad(k.gebaeude, 5)} ${pad(k.gruendungen, 7)} ${pad(k.pleiten, 8)} `
    + `${pad(k.freieWohnungen, 4)} ${pad(k.freieStellen, 5)} ${pad(f0(k.zufriedenheit), 6)} ${pad(f0(k.budget), 7)} `
    + `${pad(f0(ms), 7)} ms`;
}

function charakterText(c) {
  const dE = c.grE - c.erwE, dH = c.wzH - c.erwH;
  return [
    `  Gründer:      n=${c.grN}, Ehrgeiz Ø ${c.grE.toFixed(1)}  |  alle je Erwachsenen n=${c.erwN}, Ø ${c.erwE.toFixed(1)}  →  ${dE >= 0 ? '+' : ''}${dE.toFixed(1)}  (Gate ≥ +15)`,
    `  Weggezogene:  n=${c.wzN}, Heimatliebe Ø ${c.wzH.toFixed(1)}  |  alle je Erwachsenen Ø ${c.erwH.toFixed(1)}  →  ${dH >= 0 ? '+' : ''}${dH.toFixed(1)}  (Gate ≤ −15)`,
    `  (heutige Erwachsene n=${c.jetztN}: Ehrgeiz Ø ${c.jetztE.toFixed(1)}, Heimatliebe Ø ${c.jetztH.toFixed(1)})`,
  ].join('\n');
}

const Sim = ladeSim();

// Wie der Browser speichert: typisierte Arrays als Base64 in JSON (hier mit Buffer statt btoa/atob)
function speichernAlsText(Sim, S) {
  const d = Sim.exportZustand(S);
  return JSON.stringify({ ...d, arrays: d.arrays.map(a => ({ name: a.name, typ: a.typ,
    b64: Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength).toString('base64') })) });
}
const TYPEN = { Uint8Array, Uint16Array, Int16Array, Int32Array, Uint32Array, Float32Array, Float64Array };
function ladenAusText(Sim, text) {
  const d = JSON.parse(text);
  d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); const buf = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
    return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](buf) }; });
  return Sim.importZustand(d);
}
function fingerabdruck(Sim, S) {
  const h = createHash('sha256');
  const arrays = Sim.exportZustand(S).arrays.sort((x, y) => (x.name < y.name ? -1 : 1));   // Schlüsselreihenfolge egal
  for (const a of arrays) { h.update(a.name); h.update(Buffer.from(a.daten.buffer, a.daten.byteOffset, a.daten.byteLength)); }
  h.update(JSON.stringify(S.buch)); h.update(JSON.stringify(S.stat)); h.update(JSON.stringify(S.ki)); h.update(String(S.budget) + '/' + S.rs + '/' + S.tag + '/' + S.stunde);
  return h.digest('hex').slice(0, 16);
}

if (flag('speichertest')) {
  const seed = Number(arg('seed', '1')), tage = Number(arg('tage', '150'));
  const bis = (S, tag, stunde) => { while (S.tag < tag || (S.tag === tag && S.stunde < stunde)) Sim.stunde(S); };
  const A = Sim.neueStadt(seed); bis(A, tage, 13);
  const text = speichernAlsText(Sim, A);
  const B = ladenAusText(Sim, text);
  console.log(`Seed ${seed}: gespeichert an Tag ${A.tag}, ${A.stunde} Uhr; Spielstand ${(text.length / 1e6).toFixed(2)} MB (${A.einwohner} Einwohner)`);
  console.log(`  direkt nach dem Laden gleich: ${fingerabdruck(Sim, A) === fingerabdruck(Sim, B) ? 'ja' : 'NEIN'}`);
  bis(A, tage + 60, 13); bis(B, tage + 60, 13);
  const fa = fingerabdruck(Sim, A), fb = fingerabdruck(Sim, B);
  console.log(`  60 Tage weiter: ununterbrochen ${fa} (${A.einwohner} Einw.), geladen ${fb} (${B.einwohner} Einw.) → ${fa === fb ? 'bitgleich' : 'UNTERSCHIEDLICH'}`);
  process.exit(fa === fb ? 0 : 1);
}
if (flag('kitest')) {
  // Ohne Sprachmodell: ein Test-Beantworter mit eigenem Zufall antwortet gültig, ungültig oder gar nicht.
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  let t = 12345;
  const tz = () => { t = (t + 0x6D2B79F5) | 0; let x = Math.imul(t ^ (t >>> 15), 1 | t); x ^= x + Math.imul(x ^ (x >>> 7), 61 | x); return ((x ^ (x >>> 14)) >>> 0) / 4294967296; };
  for (const seed of [1, 2, 3]) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed);
    pruef(S.ki.haupt.length === Sim.R.HAUPT_START, `${S.ki.haupt.length} Hauptfiguren beim Start`);
    // 1. Das normale Gehirn wählt nie etwas, das erlaubteAktionen nicht kennt
    let geprueft = 0, abweichend = 0;
    while (S.tag < 200) {
      if (S.stunde === 7 || S.stunde === 18) {
        for (let p = 0; p < S.pMax; p += 3) {
          if (!S.p.lebt[p] || S.tag - S.p.geb[p] < Sim.R.ERWACHSEN * Sim.R.JAHR) continue;
          const erlaubt = Sim.erlaubteAktionen(S, p, S.stunde);
          const a = Sim.entscheide(S, p, S.stunde);
          geprueft++;
          if (a && !erlaubt.includes(Sim.AKTIONSNAMEN[a])) { abweichend++; if (abweichend < 4) console.log(`    Gehirn wählt ${Sim.AKTIONSNAMEN[a]}, erlaubt: ${erlaubt.join(', ')}`); }
        }
      }
      Sim.stunde(S);
    }
    pruef(abweichend === 0, `Gehirn ⊆ erlaubte Aktionen (${geprueft} Entscheidungen geprüft, ${abweichend} abweichend)`);
    // 1b. Der Lagesatz fürs Sprachmodell erkennt Arbeit nur an „arbeitet …“ / „besitzt …“ am Anfang
    {
      let n = 0, falsch = 0, bau = 0, bauFalsch = 0, tech = 0, techFalsch = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p] || S.tag - S.p.geb[p] < Sim.R.ERWACHSEN * Sim.R.JAHR || (S.p.arbeit[p] < 0 && S.p.besitz[p] < 0)) continue;
        const i = Sim.personInfo(S, p);
        n++; if (!/^(arbeitet als |besitzt )/.test(i.arbeit)) { falsch++; if (falsch < 3) console.log('    ' + i.arbeit); }
        // Wer schon einen eigenen Betrieb hat, der noch gebaut wird, arbeitet bis dahin weiter im Bauhof: Text „besitzt …“
        if (S.p.arbeit[p] === S.bauhof && S.p.besitz[p] < 0) { bau++; if (!/^arbeitet als Bauarbeiter(in)? beim Bauhof /.test(i.arbeit)) bauFalsch++; }
        if (S.p.arbeit[p] >= 0 && S.g.typ[S.p.arbeit[p]] === Sim.TECH && S.p.besitz[p] < 0) { tech++; if (!/^arbeitet als Programmierer(in)? bei /.test(i.arbeit)) techFalsch++; }
      }
      pruef(n > 50 && falsch === 0 && bau > 0 && bauFalsch === 0 && techFalsch === 0, `Arbeitstext beginnt mit „arbeitet als“ oder „besitzt“ (${n} Leute mit Arbeit, davon ${bau} im Bauhof, ${tech} in Tech-Firmen, ${falsch + bauFalsch + techFalsch} falsch)`);
    }
    // 2. 60 Tage mit Test-Beantworter
    S.ki.an = true;
    let anfragen = 0, gueltig = 0, ungueltig = 0, ohne = 0, maxProTag = 0, zuSpaet = 0;
    const gesehen = new Set(), proTag = {};
    while (S.tag < 260) {
      for (const a of S.ki.anfragen.slice()) {
        if (gesehen.has(a.nr)) continue;
        gesehen.add(a.nr); anfragen++;
        const k = a.id + '/' + a.gen + '/' + a.tag;
        proTag[k] = (proTag[k] || 0) + 1; maxProTag = Math.max(maxProTag, proTag[k]);
        const r = tz();
        if (r < 0.7) {
          const aktion = a.erlaubt[(tz() * a.erlaubt.length) | 0];
          const ziel = tz() < 0.2 ? Sim.ZIELNAMEN[1 + ((tz() * 6) | 0)] : null;
          const e = Sim.kiEntscheidung(S, a.id, a.gen, aktion, ziel, 'Ich nehme ' + aktion + '.');
          if (e.ok) gueltig++; else zuSpaet++;
        } else if (r < 0.8) { Sim.kiVerwerfen(S, a.id, a.gen); ungueltig++; }
        else ohne++;                                          // keine Antwort: Frist läuft ab
      }
      Sim.stunde(S);
    }
    S.ki.an = false;
    pruef(anfragen > 50, `${anfragen} Anfragen in 60 Tagen (gültig ${gueltig}, ungültig ${ungueltig}, ohne Antwort ${ohne}, abgelaufen ${S.ki.abgelaufen})`);
    pruef(maxProTag <= Sim.R.KI_PRO_TAG, `höchstens ${maxProTag} Anfragen je Figur und Tag`);
    pruef(zuSpaet === 0, `keine Antwort auf eine nicht mehr offene Anfrage (${zuSpaet})`);
    const buecher = Object.values(S.ki.tagebuch);
    pruef(buecher.every(b => b.length <= Sim.R.TAGEBUCH), `Tagebücher höchstens ${Sim.R.TAGEBUCH} Einträge (${buecher.map(b => b.length).join(', ')})`);
    // 2b. Eine späte Antwort (Anfrage schon abgelaufen) darf keine neuere Anfrage derselben Figur beantworten
    {
      S.ki.an = true;
      while (S.stunde !== 18) Sim.stunde(S);
      Sim.stunde(S);
      const alt = S.ki.anfragen[0];
      if (alt) {
        Sim.stunde(S); Sim.stunde(S);                                  // Frist abgelaufen
        S.p.jetzt[alt.id] = 1; Sim.stunde(S);                          // Ereignis → neue Anfrage derselben Figur
        const neu = S.ki.anfragen.find(x => x.id === alt.id);
        const e = Sim.kiEntscheidung(S, alt.id, alt.gen, alt.erlaubt[0], null, 'spät', alt.nr);
        pruef(!e.ok && (!neu || S.ki.anfragen.includes(neu)), `späte Antwort auf Anfrage ${alt.nr} verworfen, neue Anfrage ${neu ? neu.nr : '–'} bleibt offen`);
        if (neu) Sim.kiVerwerfen(S, neu.id, neu.gen, neu.nr);
      }
      S.ki.an = false;
    }
    // 3. Hauptfiguren setzen und Grenzen
    const erw = []; for (let p = 0; p < S.pMax && erw.length < 20; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] >= 18 * Sim.R.JAHR && !Sim.istHaupt(S, p)) erw.push(p);
    for (const p of erw) if (S.ki.haupt.length < Sim.R.HAUPT_MAX) Sim.hauptSetzen(S, p, S.p.gen[p], true);
    const elf = erw.find(p => !Sim.istHaupt(S, p));
    pruef(!Sim.hauptSetzen(S, elf, S.p.gen[elf], true) && S.ki.haupt.length === Sim.R.HAUPT_MAX, `11. Hauptfigur wird abgelehnt (${S.ki.haupt.length} Hauptfiguren)`);
    // 4. Gespräch: Erinnerung, neues Ziel, Tagebuch
    const h = S.ki.haupt[0];
    const zielVor = S.p.ziel[h.id];
    const neuZiel = Sim.ZIELNAMEN[zielVor === 5 ? 2 : 5];          // freunde bzw. besserer_job: nie „schon erreicht“
    Sim.kiGespraech(S, h.id, h.gen, 'Wie geht es dir?', 'Gut, danke.', neuZiel);
    const info = Sim.personInfo(S, h.id, h.gen);
    pruef(Sim.ZIELNAMEN[S.p.ziel[h.id]] === neuZiel && info.gedaechtnis.at(-1).text === 'mit Noah geredet' && info.tagebuch.at(-1).art === 'gespraech',
      `Gespräch: Ziel ${Sim.ZIELNAMEN[zielVor]} → ${neuZiel}, Erinnerung „${info.gedaechtnis.at(-1).text}“, Tagebuch „${info.tagebuch.at(-1).noah}“`);
    // 4b. Ein Ziel, das schon erreicht ist, übernimmt die Figur nicht (sonst sofort „Ziel erreicht“)
    const erreicht = S.ki.haupt.map(x => x.id).find(p => S.p.bFreizeit[p] >= 70 && S.p.zuf[p] >= 55 && S.p.ziel[p] !== 6);
    if (erreicht !== undefined) {
      const zv = S.p.ziel[erreicht];
      Sim.kiGespraech(S, erreicht, S.p.gen[erreicht], 'Ruh dich aus.', 'Mach ich doch schon.', 'ruhe');
      pruef(S.p.ziel[erreicht] === zv, `schon erreichtes Ziel „ruhe“ abgelehnt (Ziel bleibt ${Sim.ZIELNAMEN[zv]})`);
    }
    // 4c. Code ins Tagebuch: nur wer in einer Tech-Firma arbeitet oder eine besitzt; bleibt nach Speichern/Laden erhalten
    {
      let prog = -1, anders = -1;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p] || S.tag - S.p.geb[p] < 18 * Sim.R.JAHR) continue;
        if (prog < 0 && Sim.techFirmaVon(S, p) >= 0) prog = p;
        if (anders < 0 && Sim.techFirmaVon(S, p) < 0) anders = p;
      }
      if (prog >= 0) {
        const nein = Sim.kiCode(S, anders, S.p.gen[anders], 'Test', 'JavaScript', 'let a = 1;', 'Ich teste.');
        const ja = Sim.kiCode(S, prog, S.p.gen[prog], 'Warenkorb zählen', 'JavaScript', 'const summe = preise.reduce((a, b) => a + b, 0);\nconsole.log(summe);', 'Das klappt.');
        const e = (S.ki.tagebuch[prog + '/' + S.p.gen[prog]] || []).at(-1);
        const B2 = ladenAusText(Sim, speichernAlsText(Sim, S));
        const e2 = (B2.ki.tagebuch[prog + '/' + B2.p.gen[prog]] || []).at(-1);
        pruef(!nein && ja && e.art === 'code' && e.code.includes('reduce') && e2 && e2.code === e.code, `Code nur für Programmierende (${Sim.name(S, prog)}), bleibt nach Speichern/Laden`);
      } else pruef(false, 'niemand arbeitet in einer Tech-Firma');
    }
    // 5. Tod einer Hauptfigur: Verlust mit Vorschlägen; Speichern und Laden behält alles
    while (S.tag < 900 && S.ki.verlust.length === 0) Sim.stunde(S);
    const v = S.ki.verlust[0];
    pruef(!!v, v ? `Verlust gemeldet: ${v.name} (${v.grund}), Vorschläge: ${v.vorschlaege.map(x => x.name + ' (' + x.rolle + ')').join(', ') || 'keine'}` : 'kein Verlust bis Tag 900');
    const B = ladenAusText(Sim, speichernAlsText(Sim, S));
    pruef(JSON.stringify(B.ki) === JSON.stringify(S.ki) && fingerabdruck(Sim, B) === fingerabdruck(Sim, S), 'Speichern/Laden behält Hauptfiguren, Tagebücher, Anfragen');
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle KI-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('migrationstest')) {
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const altHtml = arg('alt') ? readFileSync(arg('alt'), 'utf8')
    : execFileSync('git', ['show', '39c405b:stadt/stadt.html'], { cwd: hier, encoding: 'utf8', maxBuffer: 1 << 26 });
  const ctx = vm.createContext({});
  vm.runInContext(altHtml.match(/<script id="sim">([\s\S]*?)<\/script>/)[1], ctx);
  const Alt = ctx.StadtSim;
  pruef((Alt.VERSION === 2 || Alt.VERSION === 3) && Alt.VERSION < Sim.VERSION, `alte Simulation hat Version ${Alt.VERSION}, neue ${Sim.VERSION}`);
  for (const [seed, tage, stunde] of [[1, 150, 13], [2, 300, 5], [3, 400, 20]]) {
    const A = Alt.neueStadt(seed);
    while (A.tag < tage || A.stunde < stunde || !A.baustellen.length) Alt.stunde(A);   // ein Moment mit laufenden Baustellen
    const text = speichernAlsText(Alt, A);
    let abgelehnt = null;
    try { ladenAusText(Sim, text); } catch (e) { abgelehnt = e; }
    pruef(abgelehnt && abgelehnt.andereVersion && abgelehnt.migrierbar, `Seed ${seed}, Tag ${A.tag} ${A.stunde} Uhr (${A.einwohner} Einw., ${A.baustellen.length} Baustellen): ohne Übernehmen abgelehnt, als übernehmbar markiert`);
    const d = JSON.parse(text);
    d.arrays = d.arrays.map(a => { const u8 = Buffer.from(a.b64, 'base64'); return { name: a.name, typ: a.typ, daten: new TYPEN[a.typ](u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)) }; });
    const S = Sim.importZustand(d, true);
    const B = S.bauhof, g = S.g;
    pruef(B === 2 && g.typ[B] === Sim.WERKSTATT && g.besitzer[B] < 0, `Bauhof = Gebäude ${B} (die Werkstatt der Stadt vom Start)`);
    pruef(S.baustellen.every(b => g.bauRest[b] > 0 && g.bauRest[b] <= Sim.bauGesamt(S, b)), `Baustellen mit Arbeitstagen: ${S.baustellen.map(b => g.bauRest[b] + '/' + Sim.bauGesamt(S, b)).join(', ') || 'keine'}`);
    pruef(S.einwohner === A.einwohner && S.buchNr === A.buchNr + 1, `Einwohner (${S.einwohner}) und Stadtbuch bleiben, eine Zeile dazu: „${Sim.klartext(S.buch.at(-1).text)}“`);
    const offen = new Set(S.baustellen);
    const ziel = S.tag + 60;
    while (S.tag < ziel) Sim.stunde(S);
    let nan = 0;
    for (const [n, a] of Object.entries(S.p)) if (a instanceof Float32Array || a instanceof Float64Array) for (let i = 0; i < S.pMax; i++) if (!Number.isFinite(a[i])) nan++;
    for (const k of ['budget', 'exportPreis', 'kistenpreis', 'zufMittel']) if (!Number.isFinite(S[k])) nan++;
    const k = Sim.kennzahlen(S);
    pruef(nan === 0 && Object.values(k).every(v => typeof v !== 'number' || Number.isFinite(v)), `60 Tage weiter (Tag ${S.tag}, ${S.einwohner} Einw.): keine NaN/Infinity`);
    pruef([...offen].every(b => !S.baustellen.includes(b) || S.g.auf[b]), `alle übernommenen Baustellen fertig (${offen.size})`);
    if (S.stat.tech) pruef(S.version === Sim.VERSION && Array.isArray(S.angebot), `Version ${S.version}, Tech-Firmen danach: ${S.stat.tech.gruendungen} gegründet, ${S.stat.tech.kaeufe.reduce((a, b) => a + b, 0)} Käufe`);
    const L = ladenAusText(Sim, speichernAlsText(Sim, S));
    const z = S.tag + 20; while (S.tag < z) Sim.stunde(S); while (L.tag < z) Sim.stunde(L);
    pruef(fingerabdruck(Sim, S) === fingerabdruck(Sim, L), `danach als Version ${Sim.VERSION} gespeichert und geladen: läuft bitgleich weiter`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Migrations-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('bau')) {
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), P = () => S.p, B = S.bauhof;
    const start = new Map(), dauer = [];
    let einteilFehl = 0, fortschrittFehl = 0, fertigFehl = 0, stillFehl = 0, geprueft = 0, uebersprungen = 0;
    let maxStellen = 0, maxLeute = 0, lohnMin = 999, lohnMax = 0;
    while (S.tag < 365) {
      for (const b of start.keys()) if (!S.baustellen.includes(b)) start.delete(b);   // fertig (auch in übersprungenen Nächten)
      for (const b of S.baustellen) if (!start.has(b)) start.set(b, S.tag);
      if (S.stunde === 8) {                                     // Einteilung von 7 Uhr
        const je = new Map();
        for (let p = 0; p < S.pMax; p++) {
          const e = P().einsatz[p];
          if (!P().lebt[p] || !e) continue;
          if (P().arbeit[p] !== B || !S.baustellen.includes(e - 1)) einteilFehl++;
          je.set(e - 1, (je.get(e - 1) || 0) + 1);
        }
        for (const [b, n] of je) if (n > R.BAU_PRO_STELLE || n > S.g.bauRest[b]) einteilFehl++;
        // niemand bleibt im Bauhof übrig, solange eine Baustelle noch Leute braucht
        const frei = S.belegschaft[B].filter(p => !P().einsatz[p] && !P().frei[p]).length;
        const braucht = S.baustellen.some(b => (je.get(b) || 0) < Math.min(R.BAU_PRO_STELLE, S.g.bauRest[b]));
        if (frei > 0 && braucht) einteilFehl++;
      }
      if (S.stunde === 23) {                                    // Fortschritt um Mitternacht = Leute, die heute da waren
        const vor = new Map(), erwartet = new Map(), stillVor = new Map(), aufVor = new Map();
        for (const b of S.baustellen) { vor.set(b, S.g.bauRest[b]); erwartet.set(b, 0); stillVor.set(b, S.g.still[b]); aufVor.set(b, S.g.auf[b]); }
        for (const p of S.belegschaft[B]) { const e = P().einsatz[p]; if (e && !P().frei[p]) erwartet.set(e - 1, erwartet.get(e - 1) + 1); }
        const beleg = S.belegschaft[B].slice();
        const tag = S.tag;
        Sim.stunde(S);
        // Nur vergleichen, wenn sich im Bauhof in der letzten Stunde nichts geändert hat (Kündigung, Tod, Freinehmen)
        const gleich = beleg.length === S.belegschaft[B].length && beleg.every((p, i) => S.belegschaft[B][i] === p);
        if (!gleich) { uebersprungen++; continue; }
        for (const [b, r] of vor) {
          geprueft++;
          const n = erwartet.get(b);
          // Noch dieselbe Baustelle? (Ein gerade fertiges Haus kann in derselben Nacht gleich wieder aufgestockt werden.)
          if (S.baustellen.includes(b) && S.g.auf[b] === aufVor.get(b)) {
            if (S.g.bauRest[b] !== r - n) { fortschrittFehl++; if (flag("v")) console.log("   Fortschritt", tag, b, r, n, S.g.bauRest[b], S.g.typ[b], S.g.auf[b], S.g.bauLeute[b]); }
            if (n === 0 && S.g.still[b] !== Math.min(255, stillVor.get(b) + 1)) { stillFehl++; if (flag("v")) console.log("   still", tag, b); }
          } else {
            if (r > n) { fertigFehl++; if (flag("v")) console.log("   fertig", tag, b, r, n); }
            dauer.push(tag + 1 - start.get(b));
            if (S.baustellen.includes(b)) start.set(b, tag + 1);   // gleich wieder aufgestockt: neue Baustelle
          }
        }
        maxStellen = Math.max(maxStellen, R.STELLEN_STADT + S.bauZuschlag);
        maxLeute = Math.max(maxLeute, S.belegschaft[B].length);
        lohnMin = Math.min(lohnMin, S.g.lohn[B]); lohnMax = Math.max(lohnMax, S.g.lohn[B]);
        continue;
      }
      Sim.stunde(S);
    }
    const alt = [...start].filter(([b, t]) => t <= 300 && S.baustellen.includes(b));
    const st = S.stat.bau;
    pruef(einteilFehl === 0, `Einteilung um 7 Uhr: nur Leute aus dem Bauhof, höchstens ${R.BAU_PRO_STELLE} je Baustelle, keiner übrig wenn Bedarf (${einteilFehl} Fehler)`);
    pruef(fortschrittFehl === 0 && stillFehl === 0 && fertigFehl === 0, `Fortschritt = Leute, die da waren: ${geprueft} Baustellentage geprüft (${uebersprungen} Nächte mit Wechsel im Bauhof übersprungen), ${fortschrittFehl + stillFehl + fertigFehl} Fehler`);
    pruef(alt.length === 0, `jede Baustelle bis Tag 300 ist an Tag 365 fertig (${st.fertig} fertig, offen seit ≤ Tag 300: ${alt.length})`);
    pruef(maxStellen <= R.BAU_MAX && maxLeute <= R.BAU_MAX, `Bauhof höchstens ${R.BAU_MAX}: Stellen bis ${maxStellen}, Leute bis ${maxLeute}`);
    pruef(lohnMin >= R.LOHN_STADT && lohnMax <= R.BAU_LOHN_MAX, `Lohn ${lohnMin}–${lohnMax} (Ø ${(st.lohnSumme / S.tag).toFixed(1)})`);
    dauer.sort((a, b) => a - b);
    console.log(`       Bauzeit Ø ${(dauer.reduce((a, b) => a + b, 0) / dauer.length).toFixed(1)} Tage, Median ${dauer[dauer.length >> 1]}, längste ${dauer.at(-1)}; ohne Bauarbeiter ${(st.still / st.tage * 100).toFixed(1)} % der Baustellentage`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Bau-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('waren')) {
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), g = S.g;
    while (S.tag < 100) Sim.stunde(S);
    let mehrAlsGemacht = 0, summeFehl = 0, weitFehl = 0, aussenFehl = 0, kistenFehl = 0, einnahmenFehl = 0, einnahmenGeprueft = 0, tage = 0;
    let gemacht = 0, anLaeden = 0, ladenStadt = 0, ladenAussen = 0;
    while (S.tag < 300) {
      if (S.stunde !== 23) { Sim.stunde(S); continue; }
      const P = S.p, vor = [];
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] !== Sim.WERKSTATT || S.feld[g.y[b] * Sim.KARTE + g.x[b]] !== Sim.WERKSTATT || g.leer[b]) continue;
        const L = S.belegschaft[b];
        vor.push({ b, o: g.besitzer[b], kasse: g.kasse[b], lohn: g.lohn[b], L: L.slice(),
          n: L.filter(w => !P.frei[w]).length, da: L.filter(w => !P.frei[w] && !P.einsatz[w]).length });
      }
      Sim.stunde(S);
      tage++;
      let sw = 0, sl = 0;
      for (let b = 0; b < S.gAnzahl; b++) {
        if (g.typ[b] === Sim.WERKSTATT) {
          if (g.kistenStadt[b] > g.kisten[b]) mehrAlsGemacht++;
          sw += g.kistenStadt[b]; gemacht += g.kisten[b]; anLaeden += g.kistenStadt[b];
        } else if (g.typ[b] === Sim.LADEN) {
          sl += g.kistenStadt[b]; ladenStadt += g.kistenStadt[b]; ladenAussen += g.kistenAussen[b];
          const l = g.lieferant[b] - 1;
          if (l >= 0 && Math.abs(g.x[l] - g.x[b]) + Math.abs(g.y[l] - g.y[b]) > R.REICH_LIEFER) weitFehl++;
          // Von außerhalb nur, wenn keine Werkstatt in Reichweite noch Kisten übrig hatte
          if (g.kistenAussen[b] > 0) for (let w = 0; w < S.gAnzahl; w++) {
            if (g.typ[w] === Sim.WERKSTATT && g.kisten[w] > g.kistenStadt[w] && Math.abs(g.x[w] - g.x[b]) + Math.abs(g.y[w] - g.y[b]) <= R.REICH_LIEFER) { aussenFehl++; break; }
          }
        }
      }
      if (sw !== sl) summeFehl++;
      for (const v of vor) {
        const L = S.belegschaft[v.b];
        if (L.length !== v.L.length || !L.every((w, i) => w === v.L[i])) continue;   // Wechsel in der letzten Stunde
        if (g.kisten[v.b] !== Math.min(65535, v.da * R.KISTEN_PRO_TAG)) kistenFehl++;
        // Einnahmen wie vor den Kisten: Arbeitstage × Umlandpreis. Nachrechnen über die Kasse, solange nichts ausgezahlt wurde.
        if (v.o < 0 || g.besitzer[v.b] !== v.o || g.kasse[v.b] >= R.POLSTER || g.leer[v.b]) continue;
        const einnahmen = g.kasse[v.b] - v.kasse + R.FIX_WERKSTATT + v.lohn * v.n;
        einnahmenGeprueft++;
        if (einnahmen !== Math.round(v.da * S.exportPreis)) einnahmenFehl++;
      }
    }
    pruef(mehrAlsGemacht === 0, `keine Werkstatt liefert mehr Kisten, als sie gemacht hat (${tage} Tage)`);
    pruef(summeFehl === 0, `geliefert = bekommen (Werkstätten und Läden, ${summeFehl} Abweichungen)`);
    pruef(weitFehl === 0 && aussenFehl === 0, `Lieferant höchstens ${R.REICH_LIEFER} Felder weit; von außen nur, wenn in Reichweite nichts übrig war (${weitFehl + aussenFehl} Fehler)`);
    pruef(kistenFehl === 0, `je anwesender Kraft ${R.KISTEN_PRO_TAG} Kisten, Bauarbeiter auf der Baustelle nicht (${kistenFehl} Fehler)`);
    pruef(einnahmenGeprueft > 100 && einnahmenFehl === 0, `Werkstatt-Einnahmen = Arbeitstage × Umlandpreis wie vorher (${einnahmenGeprueft} Werkstatt-Tage nachgerechnet, ${einnahmenFehl} Fehler)`);
    console.log(`       Tag 100–300: ${(anLaeden / gemacht * 100).toFixed(0)} % der Kisten gehen an Läden der Stadt, Läden bekommen ${(ladenStadt / (ladenStadt + ladenAussen) * 100).toFixed(0)} % aus der Stadt`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Kisten-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('tech')) {
  // Tech-Firmen: Arbeitstage an der Version, Käufe im Laden, Anbau über den Bauhof (Seeds 1–3, 730 Tage)
  let fehler = 0;
  const pruef = (ok, text) => { console.log((ok ? '  ok   ' : '  FEHL ') + text); if (!ok) fehler++; };
  const R = Sim.R, T = Sim.TECH;
  for (const seed of arg('seeds', '1,2,3').split(',').map(Number)) {
    console.log(`Seed ${seed}`);
    const S = Sim.neueStadt(seed), g = S.g;
    const offenT = (b) => g.typ[b] === T && !g.leer[b] && S.feld[g.y[b] * Sim.KARTE + g.x[b]] === T;
    let arbeitGeprueft = 0, arbeitFehl = 0, uebersprungen = 0, versionen = 0, produktFehl = 0;
    let kaufTage = 0, kaufFehl = 0, angebotFehl = 0, reserveFehl = 0, umsatzFehl = 0, kaeufe = 0;
    let anbauBestellt = 0, anbauFehl = 0, anbauFertig = 0, stellenFehl = 0, rueckFehl = 0, anbauOhneSuchende = 0;
    const zaehl = () => S.stat.tech.kaeufe.reduce((a, b) => a + b, 0);
    while (S.tag < 730) {
      if (S.stunde !== 23) { Sim.stunde(S); continue; }
      // vor Mitternacht: wer ist heute in welcher Tech-Firma da (Belegschaft ohne frei, Besitzer wenn er dort arbeitet)?
      const P = S.p, vor = [];
      for (let b = 0; b < S.gAnzahl; b++) {
        if (!offenT(b)) continue;
        const o = g.besitzer[b];
        const n = S.belegschaft[b].filter(w => !P.frei[w]).length + (o >= 0 && P.arbeit[o] === b && !P.frei[o] ? 1 : 0);
        vor.push({ b, n, projekt: g.projekt[b], version: g.version[b], L: S.belegschaft[b].slice(), stufe: g.stufe[b], auf: g.auf[b], rueck: g.ruecklage[b] });
      }
      const k0 = zaehl(), u0 = S.stat.tech.umsatz, arbl = S.arbeitslose, weg0 = S.stat.tode + S.stat.wegzuegePersonen;
      const geldVor = new Map();
      for (let p = 0; p < S.pMax; p++) if (P.lebt[p]) geldVor.set(p, P.geld[p]);
      Sim.stunde(S);                                         // Mitternacht: Tagesabschluss
      const tag = S.tag - 1;                                 // der Tag, der gerade abgeschlossen wurde
      for (const v of vor) {
        const b = v.b;
        if (!offenT(b) || S.belegschaft[b].length !== v.L.length || !S.belegschaft[b].every((w, i) => w === v.L[i])) { uebersprungen++; continue; }
        arbeitGeprueft++;
        const soll = R.VERSION_TAGE[g.produkt[b]];
        const erwartet = v.projekt + v.n;
        const ok = erwartet < soll ? g.projekt[b] === erwartet && g.version[b] === v.version
          : g.version[b] === v.version + 1 && g.projekt[b] === Math.min(erwartet - soll, soll - 1) && g.neuTag[b] === tag;
        if (!ok) { arbeitFehl++; if (flag('v')) console.log('   Arbeit', tag, b, v, g.projekt[b], g.version[b]); }
        if (g.version[b] > v.version) versionen++;
        if (!(g.produkt[b] >= 1 && g.produkt[b] <= 3)) produktFehl++;
        if (g.ruecklage[b] < 0) rueckFehl++;
        if (g.besitzer[b] >= 0 && g.kasse[b] > R.POLSTER) rueckFehl++;
        // Anbau bestellt: Stufe + 1 als Baustelle, Rücklage bezahlt, genug Leute suchten Arbeit
        if (!v.auf && g.auf[b]) {
          anbauBestellt++;
          if (g.auf[b] !== v.stufe + 1 || !S.baustellen.includes(b) || g.bauRest[b] !== R.BAU_ANBAU[g.auf[b]]) anbauFehl++;
          if (arbl < R.STELLEN_TECH) anbauOhneSuchende++;
        }
        if (v.auf && !g.auf[b]) {                            // Anbau fertig: mehr Stufe, mehr Stellen, freie Stellen stimmen
          anbauFertig++;
          if (g.stufe[b] !== v.auf) anbauFehl++;
        }
        if (g.offeneStellen[b] !== R.STELLEN_TECH * g.stufe[b] - S.belegschaft[b].length) stellenFehl++;
      }
      // Käufe: nur, was angeboten wurde (neueste Version je Produkt); niemand unter der Reserve; Geld = Umsatz der Firmen + Läden
      const neu = zaehl() - k0;
      kaeufe += neu; kaufTage++;
      let verkauftLaden = 0, verkauftFirma = 0;
      for (let b = 0; b < S.gAnzahl; b++) { if (g.typ[b] === Sim.LADEN) verkauftLaden += g.verkauft[b]; if (g.typ[b] === T) verkauftFirma += g.verkauft[b]; }
      if (verkauftLaden !== neu || verkauftFirma !== neu) { kaufFehl++; if (flag("v")) console.log("   verkauft", tag, neu, verkauftLaden, verkauftFirma); }
      let summe = 0;
      for (let p = 0; p < S.pMax; p++) {
        if (!S.p.lebt[p]) continue;
        for (const [art, tagF, marke, ver] of [['g', 'geraetTag', 'geraetMarke', 'geraetVersion'], ['a', 'appTag', 'appMarke', 'appVersion']]) {
          const hat = art === 'g' ? S.p.geraet[p] : S.p.app[p];
          if (!hat || S.p[tagF][p] !== tag) continue;
          const was = art === 'g' ? S.p.geraet[p] : Sim.SOFTWARE, f = S.angebot[was];
          summe += R.PREIS[was];
          if (f < 0 || g.marke[f] !== S.p[marke][p] || g.version[f] !== S.p[ver][p]) angebotFehl++;
          if (geldVor.has(p) && geldVor.get(p) - R.PREIS[was] < R.KAUF_RESERVE) reserveFehl++;   // gekauft wird nach dem Einkauf: vorher war mindestens Preis + Reserve da
        }
      }
      // Wer in derselben Nacht stirbt oder wegzieht, ist danach nicht mehr zu sehen: dann nur „nicht mehr als bezahlt“
      const wegHeute = S.stat.tode + S.stat.wegzuegePersonen > weg0;
      if (wegHeute ? summe > S.stat.tech.umsatz - u0 : summe !== S.stat.tech.umsatz - u0) { umsatzFehl++; if (flag("v")) console.log("   Umsatz", tag, summe, S.stat.tech.umsatz - u0); }
    }
    const t = S.stat.tech;
    pruef(t.gruendungen > 0 && produktFehl === 0, `${t.gruendungen} Tech-Firmen gegründet, jede macht Software, Handys oder Computer (${produktFehl} Fehler)`);
    pruef(arbeitGeprueft > 1000 && arbeitFehl === 0, `Arbeitstage = Leute, die da waren (Besitzer zählt mit): ${arbeitGeprueft} Firmentage geprüft (${uebersprungen} mit Wechsel übersprungen), ${versionen} Versionen erschienen, ${arbeitFehl} Fehler`);
    pruef(kaeufe > 0 && kaufFehl === 0 && umsatzFehl === 0, `Käufe: ${kaeufe} in ${kaufTage} Tagen (${(kaeufe / kaufTage).toFixed(1)} am Tag), verkauft in Läden = verkauft von Firmen = Käufe, bezahlt = Preise (${kaufFehl + umsatzFehl} Fehler)`);
    pruef(angebotFehl === 0 && reserveFehl === 0, `gekauft wird nur die neueste Version im Angebot, niemand zahlt sich unter die Reserve (${angebotFehl + reserveFehl} Fehler)`);
    pruef(anbauFehl === 0 && stellenFehl === 0 && rueckFehl === 0 && anbauOhneSuchende === 0,
      `Anbau: ${anbauBestellt} bestellt, ${anbauFertig} fertig; Stufe und freie Stellen stimmen, Rücklage ≥ 0, Kasse ≤ Polster, nur wenn ≥ ${R.STELLEN_TECH} Leute Arbeit suchten (${anbauFehl + stellenFehl + rueckFehl + anbauOhneSuchende} Fehler)`);
  }
  // Speichern und Laden mit Tech-Firmen: bitgleich (Seed 1, Tag 500)
  {
    const A = Sim.neueStadt(1); while (A.tag < 500 || A.stunde !== 11) Sim.stunde(A);
    const B = ladenAusText(Sim, speichernAlsText(Sim, A));
    for (let i = 0; i < 24 * 30; i++) { Sim.stunde(A); Sim.stunde(B); }
    pruef(fingerabdruck(Sim, A) === fingerabdruck(Sim, B) && A.stat.tech.gruendungen > 0, `Speichern/Laden an Tag 500, 11 Uhr, mit ${A.stat.tech.gruendungen} Tech-Gründungen: 30 Tage weiter bitgleich`);
  }
  console.log(fehler ? `${fehler} Prüfungen fehlgeschlagen` : 'Alle Tech-Prüfungen bestanden');
  process.exit(fehler ? 1 : 0);
}
if (flag('aufholtest')) {
  const seed = Number(arg('seed', '1')), start = Number(arg('tage', '200')), n = Number(arg('aufholen', '90'));
  const S0 = Sim.neueStadt(seed); while (S0.tag < start) Sim.stunde(S0);
  const text = speichernAlsText(Sim, S0);
  const A = ladenAusText(Sim, text), B = ladenAusText(Sim, text);
  let t0 = performance.now(); while (A.tag < start + n) Sim.stunde(A); const msStd = performance.now() - t0;
  t0 = performance.now(); while (B.tag < start + n) Sim.tagSchritt(B); const msTag = performance.now() - t0;
  const ka = Sim.kennzahlen(A), kb = Sim.kennzahlen(B);
  console.log(`Seed ${seed}, Tag ${start} → ${start + n}:   stündlich ${f0(msStd)} ms   in Tagesschritten ${f0(msTag)} ms (${(msStd / msTag).toFixed(1)}× schneller)`);
  for (const k of ['einwohner', 'gebaeude', 'gruendungen', 'pleiten', 'freieStellen', 'zufriedenheit', 'arbeitslosenquote']) {
    console.log(`  ${k.padEnd(18)} stündlich ${pad(typeof ka[k] === 'number' && ka[k] % 1 ? ka[k].toFixed(2) : ka[k], 9)}   Tagesschritte ${pad(typeof kb[k] === 'number' && kb[k] % 1 ? kb[k].toFixed(2) : kb[k], 9)}`);
  }
  process.exit(0);
}

if (flag('gate')) {
  const seeds = arg('seeds', '1,2,3').split(',').map(Number);
  let alleOk = true;
  for (const seed of seeds) {
    const reihe = [], budgets = [];
    let ms365 = 0, c365 = null, k365 = null, fehler = null, S = null, buchNr = 0, arbeitZeilen = 0, kauf365 = 0, techZeilen = 0;
    const zeilen = [];
    try {
      S = lauf(Sim, seed, 730, (S, k, ms) => {
        reihe.push(k.einwohner); budgets.push(k.budget);
        for (const e of S.buch) if (e.nr > buchNr && (e.art === 'fertig' || e.art === 'stillstand' || e.art === 'bauhof')) arbeitZeilen++;
        for (const e of S.buch) if (e.nr > buchNr && (e.art === 'version' || e.art === 'auftrag')) techZeilen++;
        buchNr = S.buchNr;
        if (k.tag % 30 === 0 || k.tag === 365 || k.tag === 730) zeilen.push(tabelleZeile(k, ms));
        if (k.tag === 365) { ms365 = ms; c365 = charakter(S); k365 = k; kauf365 = S.stat.tech ? S.stat.tech.kaeufe.reduce((a, b) => a + b, 0) : 0; }
      });
    } catch (e) { fehler = e; }
    console.log(`\n═══ Seed ${seed} ═══`);
    console.log(tabelleKopf());
    console.log(zeilen.join('\n'));
    if (fehler) { console.log('  FEHLER:', fehler.stack); alleOk = false; continue; }
    // 2: nie 0, nie > 30 % Einbruch in 30 Tagen
    let minPop = Infinity, schlimmsterEinbruch = 0, einbruchTag = 0;
    for (let d = 0; d < reihe.length; d++) {
      minPop = Math.min(minPop, reihe[d]);
      let max = 0; for (let e = Math.max(0, d - 30); e <= d; e++) max = Math.max(max, reihe[e]);
      const drop = max ? 1 - reihe[d] / max : 0;
      if (drop > schlimmsterEinbruch) { schlimmsterEinbruch = drop; einbruchTag = d + 1; }
    }
    const minBudget = Math.min(...budgets);
    // Gate 4 „pendelt sich ein“: Schwankungsband der Einwohner über die letzten 180 Tage (Tag 551–730).
    const band = reihe.slice(550, 730), bandMax = Math.max(...band), bandMin = Math.min(...band);
    const bandFaktor = bandMax / bandMin;
    // „unterhalb der Kartengrenze“: Straßen dürfen bis zur äußersten Rasterlinie im Rand. Hat eine sie erreicht,
    // stößt die Stadt an die Karte. Abstand = Felder zwischen äußerster Straße und dieser Grenze.
    const G0 = Math.ceil(Sim.RAND / Sim.RASTER) * Sim.RASTER, G1 = Math.floor((Sim.KARTE - 1 - Sim.RAND) / Sim.RASTER) * Sim.RASTER;
    let x0 = 99, y0 = 99, x1 = -1, y1 = -1;
    for (let c = 0; c < Sim.KARTE * Sim.KARTE; c++) {
      if (S.feld[c] !== Sim.STRASSE) continue;
      const x = c % Sim.KARTE, y = (c / Sim.KARTE) | 0;
      x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y);
    }
    const grenzAbstand = Math.min(x0 - G0, y0 - G0, G1 - x1, G1 - y1);
    const c730 = charakter(S);
    const g = [
      [k365.einwohner >= 300, `1  Einwohner an Tag 365: ${k365.einwohner} (≥ 300)`],
      [minPop > 0 && schlimmsterEinbruch <= 0.3, `2  Minimum ${minPop}, schlimmster 30-Tage-Einbruch ${(schlimmsterEinbruch * 100).toFixed(1)} % (Tag ${einbruchTag}) (nie 0, ≤ 30 %)`],
      [minBudget >= 0, `3  kleinstes Budget ${f0(minBudget)} (≥ 0)`],
      [bandFaktor <= 1.15 && grenzAbstand > 0, `4  läuft 730 Tage; Einwohner Tag 551–730 zwischen ${bandMin} und ${bandMax} (Faktor ${bandFaktor.toFixed(2)}, ≤ 1,15); Straßen x ${x0}–${x1}, y ${y0}–${y1}, Abstand zur Baugrenze ${grenzAbstand} (> 0)`],
      [c365.grN >= 5, `5  Gründungen durch Bewohner bis Tag 365: ${c365.grN} (≥ 5)`],
      [c365.grE - c365.erwE >= 15, `6  Gründer-Ehrgeiz ${c365.grE.toFixed(1)} vs. alle ${c365.erwE.toFixed(1)}: ${(c365.grE - c365.erwE).toFixed(1)} (≥ +15)`],
      [c365.erwH - c365.wzH >= 15, `7  Wegzieher-Heimatliebe ${c365.wzH.toFixed(1)} vs. alle ${c365.erwH.toFixed(1)}: −${(c365.erwH - c365.wzH).toFixed(1)} (n=${c365.wzN}) (≥ 15 weniger)`],
      [ms365 < 5000, `T  365 Tage in ${f0(ms365)} ms (< 5000)`],
      [arbeitZeilen / S.tag <= 0.5, `B  Stadtbuch ${(S.buchNr / S.tag).toFixed(2)} Zeilen am Tag, davon Bauhof ${(arbeitZeilen / S.tag).toFixed(2)} (≤ 0,5; kein Spec-Gate)`],
    ];
    for (const [ok, t] of g) { console.log(`  ${ok ? '✓' : '✗'} ${t}`); if (!ok) alleOk = false; }
    if (S.stat.tech) {                                        // Tech-Firmen (kein Gate): wie viele, wie groß, was die Leute kaufen
      const t = S.stat.tech, st = [0, 0, 0, 0];
      let erw = 0, mitGeraet = 0;
      for (let b = 0; b < S.gAnzahl; b++) if (S.g.typ[b] === Sim.TECH && !S.g.leer[b] && S.feld[S.g.y[b] * Sim.KARTE + S.g.x[b]] === Sim.TECH) st[S.g.stufe[b]]++;
      for (let p = 0; p < S.pMax; p++) if (S.p.lebt[p] && S.tag - S.p.geb[p] >= 18 * Sim.R.JAHR) { erw++; if (S.p.geraet[p]) mitGeraet++; }
      const kaeufe = t.kaeufe.reduce((a, b) => a + b, 0);
      console.log(`  Tech: gegründet ${t.gruendungen}, offen an Tag 730 ${st[1] + st[2] + st[3]} (Stufe 2: ${st[2]}, Stufe 3: ${st[3]}), Anteil an den Umland-Stellen ${(S.techPlaetze / Math.max(1, S.werkstattPlaetze) * 100).toFixed(1)} %,`
        + ` Versionen ${t.versionen}, Käufe je Tag ${((kaeufe - kauf365) / 365).toFixed(1)} (Tag 366–730), Anbauten ${t.anbauten}, Tech-Pleiten ${t.pleiten}, Erwachsene mit Gerät ${(mitGeraet / Math.max(1, erw) * 100).toFixed(0)} %, Tech-Zeilen im Stadtbuch ${(techZeilen / S.tag).toFixed(2)} am Tag`);
    }
    console.log('  Tag 730:\n' + charakterText(c730));
  }
  console.log(`\nGate Phase 0: ${alleOk ? 'BESTANDEN' : 'NICHT BESTANDEN'}`);
  process.exit(alleOk ? 0 : 1);
} else {
  const seed = Number(arg('seed', '1')), tage = Number(arg('tage', '365')), alle = Number(arg('alle', '30'));
  console.log(`Seed ${seed}, ${tage} Spieltage`);
  console.log(tabelleKopf());
  let vor = null;
  const S = lauf(Sim, seed, tage, (S, k, ms) => {
    if (k.tag % alle === 0 || k.tag === tage) {
      let z = tabelleZeile(k, ms);
      if (flag('fluss')) {
        const st = S.stat, jetzt = { zu: st.zuzuege, weg: st.wegzuegePersonen, geb: st.geburten, tod: st.tode, gr: st.gruendungen, pl: st.pleiten };
        if (vor) z += `   | zu ${jetzt.zu - vor.zu}, weg ${jetzt.weg - vor.weg}, geb ${jetzt.geb - vor.geb}, tod ${jetzt.tod - vor.tod}, arbl ${(k.arbeitslosenquote * 100).toFixed(0)}%, ohneEK ${(k.unversorgt * 100).toFixed(0)}%, Läden ${k.laeden} Werkst ${k.werkstaetten} leer ${k.leerstand}`;
        vor = jetzt;
      }
      console.log(z);
    }
  });
  const k = Sim.kennzahlen(S), st = S.stat;
  console.log(`\nCharakter-Auswertung (Tag ${S.tag}):\n` + charakterText(charakter(S)));
  console.log(`\nStadt an Tag ${S.tag}: ${k.haeuser} Wohnhäuser, ${k.werkstaetten} Werkstätten, ${k.laeden} Läden (davon ${k.leerstand} leer, ${k.stadtBetriebe} städtisch), ${k.parks} Parks, ${k.baustellen} Baustellen`);
  console.log(`  Arbeitslos ${k.arbeitslose} (${(k.arbeitslosenquote * 100).toFixed(1)} %), Umlandpreis ${k.exportPreis.toFixed(1)}, ohne Einkauf ${(k.unversorgt * 100).toFixed(1)} %`);
  console.log(`  Zuzüge ${st.zuzuege}, Wegzüge ${st.wegzuege} (Personen ${st.wegzuegePersonen}), Geburten ${st.geburten}, Tode ${st.tode}`);
  console.log(`  Paare ${st.paare}, Hochzeiten ${st.hochzeiten}, Trennungen ${st.trennungen}, Freundschaften ${st.freundschaften}`);
  console.log(`  Ziele erreicht ${st.zieleErreicht}, aufgegeben ${st.zieleAufgegeben}; Übernahmen ${st.uebernahmen}`);
  console.log(`  Bauamt: ${JSON.stringify(st.bauamt)}`);
  if (flag('diag')) {
    const P = S.p, J = Sim.R.JAHR, hist = [0, 0, 0, 0, 0], bed = [0, 0, 0, 0];
    let n = 0, elend = 0, kinder = 0, rentner = 0, obdach = 0, beiEltern = 0, schulden = 0;
    for (let p = 0; p < S.pMax; p++) {
      if (!P.lebt[p]) continue;
      const a = S.tag - P.geb[p];
      if (a < 18 * J) { kinder++; continue; }
      if (a >= 67 * J) rentner++;
      n++; hist[Math.min(4, Math.floor(P.zuf[p] / 20))]++;
      bed[0] += P.bGeld[p]; bed[1] += P.bWohnen[p]; bed[2] += P.bKontakt[p]; bed[3] += P.bFreizeit[p];
      if (P.elend[p] >= 7) elend++;
      if (P.wohnung[p] < 0) obdach++; else if (P.hh[p] !== p && P.hh[p] !== P.partner[p]) beiEltern++;
      if (P.geld[p] < 0) schulden++;
    }
    console.log(`  Zufriedenheit <20/<40/<60/<80/≥80: ${hist.join(' / ')}   (≥7 Tage elend: ${elend})`);
    console.log(`  Bedürfnisse Ø Geld ${(bed[0] / n).toFixed(0)}, Wohnen ${(bed[1] / n).toFixed(0)}, Kontakt ${(bed[2] / n).toFixed(0)}, Freizeit ${(bed[3] / n).toFixed(0)}`);
    console.log(`  Kinder ${kinder}, Rentner ${rentner}, ohne Wohnung ${obdach}, wohnt bei anderen ${beiEltern}, Schulden ${schulden}`);
  }
  if (flag('aktionen')) {
    console.log('  Aktionen (gewählt / ausgeführt):');
    for (let a = 1; a < Sim.AKTIONSNAMEN.length; a++) console.log(`    ${Sim.AKTIONSNAMEN[a].padEnd(16)} ${pad(st.gewaehlt[a], 8)} ${pad(st.ausgefuehrt[a], 8)}`);
  }
  const nb = Number(arg('buch', '0'));
  if (nb) { console.log(`\nStadtbuch (letzte ${nb}):`); for (const e of S.buch.slice(-nb)) console.log(`  Tag ${e.tag} — ${Sim.klartext(e.text)}`); }
}
