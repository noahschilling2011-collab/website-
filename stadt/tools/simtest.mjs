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
//   Optionen: --alle 30 (Zeilenabstand), --buch 20 (letzte Stadtbuch-Zeilen), --aktionen

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { performance } from 'node:perf_hooks';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

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
  h.update(JSON.stringify(S.buch)); h.update(JSON.stringify(S.stat)); h.update(String(S.budget) + '/' + S.rs + '/' + S.tag + '/' + S.stunde);
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
    let ms365 = 0, c365 = null, k365 = null, fehler = null, S = null;
    const zeilen = [];
    try {
      S = lauf(Sim, seed, 730, (S, k, ms) => {
        reihe.push(k.einwohner); budgets.push(k.budget);
        if (k.tag % 30 === 0 || k.tag === 365 || k.tag === 730) zeilen.push(tabelleZeile(k, ms));
        if (k.tag === 365) { ms365 = ms; c365 = charakter(S); k365 = k; }
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
    ];
    for (const [ok, t] of g) { console.log(`  ${ok ? '✓' : '✗'} ${t}`); if (!ok) alleOk = false; }
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
