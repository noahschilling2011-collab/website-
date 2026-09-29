#!/usr/bin/env node
// Tag-für-Tag-Vergleich gepatcht (Policy aus) gegen ungepatcht: je Seed und Spieltag der Fingerabdruck des ganzen Zustands (SHA-256 über alle
// Arrays, Einzelwerte und JSON-Teile wie simtest), dazu dieselben Schlüssel in S. Zwei Wege: stündlich (Sim.stunde, wie im Spiel) und in
// Tagesschritten (Sim.tagSchritt, wie beim Aufholen). Entwicklungswerkzeug.
//   node tools/tagvergleich.mjs --a stadt.orig.html --b stadt.html [--seeds 1,2,3] [--tage 120] [--tagschritt 60] [--aus ausgaben/tage.tsv]
import { readFileSync, writeFileSync } from 'node:fs';
import { ladeSimAusHtml, fingerabdruck } from './simkern.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const A = ladeSimAusHtml(readFileSync(arg('a', 'stadt.orig.html'), 'utf8')), B = ladeSimAusHtml(readFileSync(arg('b', 'stadt.html'), 'utf8'));
const seeds = arg('seeds', '1,2,3').split(',').map(Number), tage = Number(arg('tage', '120')), ts = Number(arg('tagschritt', '60'));
console.log(`a ${arg('a', 'stadt.orig.html')} (sim ${A.simHash}, Version ${A.Sim.VERSION}), b ${arg('b', 'stadt.html')} (sim ${B.simHash}, Version ${B.Sim.VERSION}), `
  + `Policy in b: ${B.Sim.KI ? (B.Sim.KI.policyAktiv() ? 'AN' : 'aus') : 'kein KI-Teil'}`);
const zeilen = ['weg\tseed\ttag\teinwohner\tfingerabdruck_a\tfingerabdruck_b\tgleich'];
let fehl = 0;
for (const weg of ['stunde', 'tagSchritt']) {
  const n = weg === 'stunde' ? tage : ts;
  if (!n) continue;
  for (const seed of seeds) {
    const Sa = A.Sim.neueStadt(seed), Sb = B.Sim.neueStadt(seed);
    let erster = -1, gleichZahl = 0;
    for (let d = 0; d < n; d++) {
      if (weg === 'stunde') { const z = Sa.tag + 1; while (Sa.tag < z) A.Sim.stunde(Sa); while (Sb.tag < z) B.Sim.stunde(Sb); }
      else { A.Sim.tagSchritt(Sa); B.Sim.tagSchritt(Sb); }
      const fa = fingerabdruck(A.Sim, Sa), fb = fingerabdruck(B.Sim, Sb), gl = fa === fb && Object.keys(Sa).join() === Object.keys(Sb).join();
      zeilen.push(`${weg}\t${seed}\t${Sa.tag}\t${Sa.einwohner}\t${fa}\t${fb}\t${gl ? 1 : 0}`);
      if (gl) gleichZahl++; else if (erster < 0) erster = Sa.tag;
    }
    const ok = erster < 0;
    if (!ok) fehl++;
    console.log(`${ok ? 'ok  ' : 'FEHL'} ${weg}, Seed ${seed}: ${gleichZahl} von ${n} Tagen bitgleich (Tag ${Sa.tag}, ${Sa.einwohner} Einwohner, `
      + `Fingerabdruck ${fingerabdruck(B.Sim, Sb)})${ok ? '' : `, verschieden ab Tag ${erster}`}`);
  }
}
if (arg('aus')) { writeFileSync(arg('aus'), zeilen.join('\n') + '\n'); console.log(`je Tag: ${arg('aus')} (${zeilen.length - 1} Zeilen)`); }
console.log(fehl ? `${fehl} FEHL` : 'Tag für Tag bitgleich');
process.exit(fehl ? 1 : 0);
