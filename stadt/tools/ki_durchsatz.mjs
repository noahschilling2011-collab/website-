#!/usr/bin/env node
// Durchsatz der Trainingsumgebung im Prozess (ohne Protokoll): Episoden mit zufälligen erlaubten Aktionen (fester Strom) oder 'regel'.
//   node tools/ki_durchsatz.mjs [--seeds 10000,10001] [--episoden 6] [--arm zufall|regel] [--tage 30]
import { performance } from 'node:perf_hooks';
import { ladeSim } from './simkern.mjs';
import { Umgebung, mische } from './kiepisode.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const seeds = arg('seeds', '10000,10001,10002').split(',').map(Number), epis = Number(arg('episoden', '6')), arm = arg('arm', 'zufall');
const tage = Number(arg('tage', '30'));
const { Sim, simHash } = ladeSim();
const U = new Umgebung(Sim);
let schritte = 0, stunden = 0, tWarm = 0, tLauf = 0, ret = 0, ende = {};
for (let k = 0; k < epis; k++) {
  const seed = seeds[k % seeds.length];
  const t0 = performance.now();
  U.startZustand(seed, { name: 'stabil', startTag: (s) => 150 + (s % 5) * 20, startStunde: 6 });
  const t1 = performance.now(); tWarm += t1 - t0;
  let r = U.reset({ seed, nr: k, tage }), z = mische(seed, k + 99);
  while (!r.beendet && !r.abgeschnitten) {
    let a = 0;
    if (arm === 'regel') a = 'regel';
    else { const erlaubt = r.maske.map((v, i) => (v ? i : -1)).filter(i => i >= 0); z = mische(z, 1); a = erlaubt[z % erlaubt.length]; }
    r = U.step(a); schritte++; ret += r.belohnung;
  }
  stunden += U.epi.stunden; tLauf += performance.now() - t1;
  const m = r.info.metrik; ende[m.ende] = (ende[m.ende] || 0) + 1;
  console.log(`Seed ${seed} nr ${k}: ${U.epi.einwohner} Einw., ${m.entscheidungen} Entscheidungen (${m.autoWarten} ohne Wahl), ${U.epi.stunden} h, Ende ${m.ende}, Defizit Ø ${m.defizitMittel.toFixed(1)}, `
    + `Summe ${Object.entries(U.epi.summe).map(([a, b]) => a + ' ' + b.toFixed(2)).join(', ')}`);
}
// Schnappschuss und Wiederherstellen an einem Haltepunkt (Kopie über export/import)
let tS = 0, tR = 0;
U.reset({ seed: seeds[0], nr: 0, tage });
for (let k = 0; k < 20; k++) { const a0 = performance.now(), s = U.snapshot(), a1 = performance.now(); U.restore(s); tS += a1 - a0; tR += performance.now() - a1; }
console.log(`Schnappschuss Ø ${(tS / 20).toFixed(1)} ms, Wiederherstellen Ø ${(tR / 20).toFixed(1)} ms (Seed ${seeds[0]}, ${U.S.einwohner} Einwohner)`);
console.log(`sim ${simHash}, Arm ${arm}: ${schritte} Schritte, ${stunden} Spielstunden in ${(tLauf / 1000).toFixed(2)} s → ${(schritte / tLauf * 1000).toFixed(0)} Schritte/s, `
  + `${(stunden / tLauf * 1000).toFixed(0)} Spielstunden/s; Ausgangslagen gerechnet in ${(tWarm / 1000).toFixed(1)} s; Enden ${JSON.stringify(ende)}; Belohnung Ø ${(ret / epis).toFixed(2)}`);
