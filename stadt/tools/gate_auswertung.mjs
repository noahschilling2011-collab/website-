#!/usr/bin/env node
// Wertet Ausgaben von simtest --gate aus (eine oder mehrere Dateien, z. B. Seeds 1–80 in zwei Prozessen): je Gate, wie viele Seeds bestanden,
// rote Seeds, dazu die Werte je Seed (Einwohner 365, Budget, Faktor Gate 4, Gründungen, Abstände Gate 6/7, T). Mit --tabelle eine Zeile je Seed.
// Gate 7 nach Noahs Entscheidung 8: unter G7_MIN_N Wegziehern bis Tag 365 „nicht gewertet“ (–), getrennt gezählt; „Gate 7: min …“ dann nur
// über gewertete Seeds. Liest beide Schreibweisen von Gate 7 (vor und nach Entscheidung 8); --g7min 0 wertet wie vor Entscheidung 8.
// Übernommen aus den Messwerkzeugen der Etappe 2 (gate_auswertung.mjs mit dem Leser aus kal_lese.mjs), gleiche Ausgabe. Entwicklungswerkzeug.
//   node tools/simtest.mjs --gate --seeds 1,3,5,…,79 > a.txt; node tools/simtest.mjs --gate --seeds 2,4,…,80 > b.txt
//   node tools/gate_auswertung.mjs a.txt b.txt [--tabelle] [--g7min 15]
import { readFileSync, existsSync } from 'node:fs';
const G7_MIN_N = 15;                                         // Noahs Entscheidung 8, wie tools/simtest.mjs
const GATES = ['1', '2', '3', '4', '5', '6', '7', 'T', 'B'];
// Je Seed: bestanden je Gate (true/false; Gate 7 null = nicht gewertet), Werte der Gates. Alte Ausgaben (✓/✗ 7 … (n=N)) mit n ≥ g7min behalten
// ihr ✓/✗ (nicht aus der gerundeten Zahl neu gerechnet); g7min unter der Schwelle von simtest wertet „–“-Zeilen aus der gerundeten Zahl
function leseGates(dateien, g7min) {
  const seeds = new Map();
  for (const f of dateien) {
    if (!existsSync(f)) continue;
    let seed = null;
    for (const z of readFileSync(f, 'utf8').split('\n')) {
      const m = z.match(/═══ Seed (\d+) ═══/); if (m) { seed = Number(m[1]); seeds.set(seed, { datei: f, gates: {} }); continue; }
      if (seed === null) continue;
      const s = seeds.get(seed);
      const g = z.match(/^  ([✓✗–]) (\w)  (.*)$/); if (!g) { if (/FEHLER/.test(z)) s.fehler = true; continue; }
      const x = g[3];
      s.gates[g[2]] = g[1] === '–' ? null : g[1] === '✓';
      const zahl = (re) => { const y = x.match(re); return y ? Number(y[1].replace(/\./g, '').replace(',', '.')) : null; };
      if (g[2] === '1') s.einwohner365 = zahl(/Tag 365: (\d+)/);
      if (g[2] === '3') { const y = x.match(/Budget ([-−]?[\d.]+)/); s.budget = y ? Number(y[1].replace('−', '-').replace(/\./g, '')) : null; }
      if (g[2] === '4') s.faktor4 = Number((x.match(/Faktor ([\d.]+)/) || [])[1]);
      if (g[2] === '5') s.gruendungen365 = zahl(/Tag 365: (\d+)/);
      if (g[2] === '6') s.abstand6 = Number((x.match(/: (-?[\d.]+) \(≥ \+15\)/) || [])[1]);
      if (g[2] === '7') {
        const offen = x.match(/^nicht gewertet: nur (\d+) Wegzieher/);
        s.abstand7 = Number((x.match(/: −(-?[\d.]+) \((?:n=|nur gemeldet)/) || [])[1]);
        s.n7 = Number(offen ? offen[1] : (x.match(/\(n=(\d+)\)/) || [])[1]);
        if (s.n7 < g7min) s.gates['7'] = null;                                   // Entscheidung 8: nicht gewertet
        else if (g[1] === '–') s.gates['7'] = s.abstand7 >= 15;
      }
      if (g[2] === 'T') s.T = Number((x.match(/in ([\d.]+) ms/) || [])[1]?.replace(/\./g, ''));
    }
  }
  return new Map([...seeds.entries()].sort((a, b) => a[0] - b[0]));
}
const argv = process.argv.slice(2), gi = argv.indexOf('--g7min'), G7MIN = gi >= 0 ? Number(argv[gi + 1]) : G7_MIN_N;
const dateien = argv.filter((a, i) => !a.startsWith('--') && !(gi >= 0 && i === gi + 1)), tabelle = argv.includes('--tabelle');
const liste = [...leseGates(dateien, G7MIN).entries()];
const offen = liste.filter(([, s]) => s.gates['7'] === null).map(([k]) => k);
const zeile = GATES.map(g => `Gate ${g}: ${liste.filter(([, s]) => s.gates[g]).length}/${liste.length}`
  + (g === '7' && G7MIN > 0 ? ` (nicht gewertet ${offen.length})` : '')).join(', ');
console.log(`${liste.length} Seeds (${liste.length ? liste[0][0] + '–' + liste[liste.length - 1][0] : '–'}); ${zeile}; Abstürze: ${liste.filter(([, s]) => s.fehler).length}`);
for (const g of GATES) { const rot = liste.filter(([, s]) => s.gates[g] === false).map(([k]) => k); if (rot.length) console.log(`  rot in Gate ${g}: Seeds ${rot.join(', ')}`); }
if (G7MIN > 0) console.log(`  Gate 7 nicht gewertet (weniger als ${G7MIN} Wegzieher bis Tag 365, Entscheidung 8): ${offen.length} von ${liste.length}${offen.length ? ' (Seeds ' + offen.join(', ') + ')' : ''}`);
const werte = (k, nur = () => true) => liste.filter(([, s]) => nur(s)).map(([, s]) => s[k]).filter(x => Number.isFinite(x));
const kurz = (k, nur) => { const w = werte(k, nur).sort((a, b) => a - b); return w.length ? `min ${w[0]}, Median ${w[w.length >> 1]}, max ${w[w.length - 1]}` : '–'; };
console.log(`  Faktor Gate 4: ${kurz('faktor4')}; kleinstes Budget: ${kurz('budget')}; Gate 6: ${kurz('abstand6')}; Gate 7: ${kurz('abstand7', s => s.gates['7'] !== null)}`
  + `${G7MIN > 0 ? ' (nur gewertete)' : ''}; T: ${kurz('T')}`);
const zeichen = (s, g) => (s.gates[g] === null ? '–' : s.gates[g] ? '✓' : '✗');
if (tabelle) for (const [k, s] of liste) console.log(`  Seed ${k}: ${GATES.map(g => g + zeichen(s, g)).join(' ')} | Einw ${s.einwohner365} Budget ${s.budget} F4 ${s.faktor4} Gr ${s.gruendungen365} G6 ${s.abstand6} G7 −${s.abstand7} (n ${s.n7}) T ${s.T}`);
