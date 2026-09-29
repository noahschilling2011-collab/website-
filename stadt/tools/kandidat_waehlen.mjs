#!/usr/bin/env node
// Kandidatenwahl nach Validierung (training/AUSWERTUNG_V9.md, Abschnitt „Kandidatenwahl“, vorab festgelegt). Liest die Ergebnisse von
// tools/werte_aus.mjs (JSON, Validierungsseeds, mit --stadtwirkung) je Kandidat, in der Reihenfolge der Vorliebe bei Gleichstand.
//   node tools/kandidat_waehlen.mjs name1=datei1.json name2=datei2.json
// Regel: (1) nur Kandidaten ohne verletzte Invariante; (2) mehr Gruppen mit gezählter Verbesserung; (3) mehr Nebenprüfungen in Toleranz;
// (4) kleineres mittleres Defizit über alle Paare; (5) Reihenfolge der Angabe (bester vor letzter).
// Prüft außerdem, dass alle Kandidaten dieselben Paare (Seed, Nummer, Fokusperson) und denselben Regelarm hatten.
import { readFileSync } from 'node:fs';

const K = process.argv.slice(2).map((a, rang) => { const [name, datei] = a.split('='); return { name, datei, rang, d: JSON.parse(readFileSync(datei, 'utf8')) }; });
if (K.length < 1) { console.error('Aufruf: node tools/kandidat_waehlen.mjs name=datei.json …'); process.exit(2); }
const schluessel = (d) => d.episoden.map(e => `${e.gruppe}/${e.seed}/${e.nr}/${e.fokus.id}/${e.fokus.gen}/${e.regeln.defizitMittel}`).join('|');
const s0 = schluessel(K[0].d);
for (const k of K) {
  if (k.d.seeds !== (process.env.KANDIDAT_SEEDS || 'validierung')) throw new Error(`${k.name}: nicht auf Validierungsseeds (${k.d.seeds})`);   // KANDIDAT_SEEDS nur für den Werkzeugtest
  if (schluessel(k.d) !== s0) throw new Error(`${k.name}: andere Paare oder anderer Regelarm als ${K[0].name}`);
  if (!k.d.freigabe || !k.d.freigabe.stadtwirkungGemessen) throw new Error(`${k.name}: ohne Stadtwirkung ausgewertet`);
  const E = k.d.episoden.map(e => e.policy.defizitMittel);
  k.werte = { invarianten: k.d.freigabe.invarianten, gruppen: k.d.freigabe.gruppenMitVerbesserung, neben: k.d.freigabe.nebenBestanden,
    nebenGesamt: k.d.freigabe.nebenGesamt, defizit: E.reduce((s, v) => s + v, 0) / E.length, paare: E.length, hash: k.d.policy.hash };
}
const ok = K.filter(k => k.werte.invarianten);
ok.sort((a, b) => (b.werte.gruppen - a.werte.gruppen) || (b.werte.neben - a.werte.neben) || (a.werte.defizit - b.werte.defizit) || (a.rang - b.rang));
for (const k of K) console.log(`${k.name}: Hash ${k.werte.hash}, Invarianten ${k.werte.invarianten ? 'ok' : 'VERLETZT'}, Gruppen ${k.werte.gruppen}/5, `
  + `Nebenprüfungen ${k.werte.neben}/${k.werte.nebenGesamt}, Defizit Ø ${k.werte.defizit.toFixed(3)} über ${k.werte.paare} Paare`);
console.log(`Paare und Regelarm bei allen Kandidaten gleich (${K[0].d.episoden.length} Paare).`);
console.log(ok.length ? `Gewählt: ${ok[0].name} (${ok[0].datei})` : 'Kein Kandidat ohne verletzte Invariante.');
