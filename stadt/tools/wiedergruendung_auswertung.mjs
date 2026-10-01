#!/usr/bin/env node
// Etappe 2 (berichte/etappe2/VERBLASSEN.md A.3): wertet tools/wiedergruendung.mjs aus. Je Variante W(X) = Personen mit Pleite bis Tag X, die
// nach der ersten Pleite bis Tag X wieder gegründet haben / Personen mit Pleite bis Tag X (alle Seeds zusammen), X = 730 und 1.460; Ziel
// aus VERBLASSEN.md: W(1.460) ≥ ½ · W des Bezugs (Variante mit dem Namen „ged0“). Wartezeit nach Charakter: mittlere Tage erste Pleite →
// nächste Gründung (nur wer bis 1.460 wieder gründet), Sparsame (≥ 50) minus Verschwender (< 50); dazu Median, Zahl und W je Gruppe.
// Übernommen aus dem Messwerkzeug der Phase „Verblassen“ (vb_wieder_auswertung.mjs), unverändert bis auf diesen Kopf. Entwicklungswerkzeug.
//   node tools/wiedergruendung_auswertung.mjs name=datei.json … [--json]
//   z. B. ged0=berichte/etappe2/mess/verblassen/kand/wieder_ged0.json h180=berichte/etappe2/mess/verblassen/kand/wieder_h180.json
import { readFileSync } from 'node:fs';
const argv = process.argv.slice(2), alsJson = argv.includes('--json');
const V = argv.filter(a => !a.startsWith('--')).map(a => { const [n, f] = a.split('='); return [n, JSON.parse(readFileSync(f, 'utf8'))]; });
const mittel = (x) => x.reduce((a, b) => a + b, 0) / x.length, median = (x) => { const s = [...x].sort((a, b) => a - b); return s.length ? s[s.length >> 1] : null; };
function w(d, X, nur = () => true) {
  let n = 0, wieder = 0; const tage = [];
  for (const z of Object.values(d.seeds)) for (const [t0, sp, g] of z.personen) {
    if (t0 > X || !nur(sp)) continue;
    n++; if (g >= 0 && g <= X) { wieder++; tage.push(g - t0); }
  }
  return { n, wieder, anteil: n ? 100 * wieder / n : null, tage };
}
const erg = {};
for (const [name, d] of V) {
  const e = { sim: d.simHash, ged: d.ged, erfHalb: d.erfHalb, sofort: d.sofort, seeds: Object.keys(d.seeds).length, tage: d.tage };
  for (const X of [730, 1460]) { const r = w(d, X); e['W' + X] = { n: r.n, wieder: r.wieder, anteil: r.anteil, tageMedian: median(r.tage) }; }
  const sp = w(d, 1460, s => s >= 50), vs = w(d, 1460, s => s < 50);
  e.charakter = { sparsam: { n: sp.n, wieder: sp.wieder, anteil: sp.anteil, tageMittel: sp.tage.length ? mittel(sp.tage) : null, tageMedian: median(sp.tage) },
    verschwender: { n: vs.n, wieder: vs.wieder, anteil: vs.anteil, tageMittel: vs.tage.length ? mittel(vs.tage) : null, tageMedian: median(vs.tage) } };
  e.charakter.differenz = sp.tage.length && vs.tage.length ? mittel(sp.tage) - mittel(vs.tage) : null;
  e.charakter.genug = sp.wieder >= 10 && vs.wieder >= 10;
  e.einwohner1460 = Object.values(d.seeds).reduce((a, z) => a + (z.stand[1460]?.einwohner || 0), 0);
  erg[name] = e;
}
if (erg.ged0) for (const e of Object.values(erg)) { e.ziel = erg.ged0.W1460.anteil / 2; e.zielErreicht = e.W1460.anteil >= e.ziel; }
if (alsJson) { console.log(JSON.stringify(erg, null, 1)); process.exit(0); }
const p = (x) => (x === null || x === undefined ? '–' : x.toFixed(1));
for (const [name, e] of Object.entries(erg)) {
  console.log(`${name.padEnd(8)} sim ${e.sim} GED ${e.ged} ERF_HALB ${e.erfHalb}${e.sofort ? ' (sofort vergessen)' : ''}, ${e.seeds} Seeds × ${e.tage} Tage: `
    + `W(730) ${e.W730.wieder}/${e.W730.n} = ${p(e.W730.anteil)} %; W(1460) ${e.W1460.wieder}/${e.W1460.n} = ${p(e.W1460.anteil)} % (Median ${e.W1460.tageMedian} Tage)`
    + (e.ziel !== undefined ? `; Ziel ≥ ${p(e.ziel)} %: ${e.zielErreicht ? 'erreicht' : 'nicht erreicht'}` : ''));
  const c = e.charakter;
  console.log(`         Sparsame (≥ 50): ${c.sparsam.wieder}/${c.sparsam.n} = ${p(c.sparsam.anteil)} %, Wartezeit Ø ${p(c.sparsam.tageMittel)} (Median ${c.sparsam.tageMedian}); `
    + `Verschwender (< 50): ${c.verschwender.wieder}/${c.verschwender.n} = ${p(c.verschwender.anteil)} %, Ø ${p(c.verschwender.tageMittel)} (Median ${c.verschwender.tageMedian}); `
    + `Differenz ${p(c.differenz)} Tage → ${c.differenz === null ? '–' : c.differenz > 0 ? 'Sparsame später' : 'Sparsame NICHT später'}${c.genug ? '' : ' (weniger als 10 Wiedergründer in einer Gruppe)'}`);
}
