#!/usr/bin/env node
// Stadtwirkung der Policy für alle (Master-Prompt 8: „Stadtwirkung“): dieselbe Stadt mit Regeln und mit der Policy für alle Bewohner im
// Trainingsbereich (Erwachsene unter R.RENTE, keine Hauptfiguren, nie der Bürgermeister – wie im Spiel).
// (a) neue Stadt ab Tag 0 bis Tag --neu, (b) gewachsene Stadt (Regeln bis Tag --ab), dann umgeschaltet für --tage Tage. Nur Messung.
//   node tools/ki_stadtwirkung.mjs [--policy ki/policy_x.json] [--seeds 1,2,3 | --seedliste validierung|abschluss [--versatz 16] --anzahl 4]
//        [--neu 90] [--ab 200] [--tage 60] [--aus datei.json]
// Kennzahlen am Ende: Einwohner, Kasse (S.budget), Gründungen im Zeitraum (S.stat.gruendungen; bei (a) seit Tag 0), Pleiten, Zufriedenheit.
// Summen über die Seeds stehen unter „summen“ (Toleranzen: training/AUSWERTUNG_V9.md).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { ladeSim, policyTextAusHtml, zustandKopie, zustandLaden, HIER } from './simkern.mjs';

const args = process.argv.slice(2);
const arg = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const { Sim, html, simHash } = ladeSim();
const polText = arg('policy') ? readFileSync(arg('policy'), 'utf8') : policyTextAusHtml(html);
const polD = JSON.parse(polText), pol = Sim.KI.policyPruefen(polD);
const seeds = arg('seedliste')
  ? JSON.parse(readFileSync(join(HIER, '..', 'training', 'seeds.json'), 'utf8'))[arg('seedliste')].slice(Number(arg('versatz', '0'))).slice(0, Number(arg('anzahl', '3')))
  : arg('seeds', '1,2,3').split(',').map(Number);
const neuTage = Number(arg('neu', '90')), ab = Number(arg('ab', '200')), tage = Number(arg('tage', '60'));
const kz = (S, g0 = 0) => { const k = Sim.kennzahlen(S), st = S.stat;
  return { tag: S.tag, einwohner: k.einwohner, erwachsene: k.erwachsene, zufriedenheit: +k.zufriedenheit.toFixed(1), arbeitslose: k.arbeitslose,
    freieStellen: k.freieStellen, kasse: Math.round(S.budget), lohnsteuer: S.haushalt ? S.haushalt.satz : null, gruendungen: st.gruendungen - g0,
    pleiten: st.pleiten, geburten: st.geburten, wegzuege: st.wegzuege, zuzuege: st.zuzuege }; };
const bis = (S, t) => { while (S.tag < t) Sim.stunde(S); };
const aus = { policy: polD.name, policyHash: pol.hash, status: pol.status, simHash, seeds, neuTage, ab, tage, je: [], summen: null };
console.log(`Policy „${pol.name}“ (${pol.status}, Hash ${pol.hash}); Seeds ${seeds.join(', ')}; Sim ${simHash}`);
for (const seed of seeds) {
  Sim.KI.policySetzen(null);
  const R = Sim.neueStadt(seed); bis(R, neuTage);
  Sim.KI.policySetzen(pol);
  const P = Sim.neueStadt(seed); bis(P, neuTage);
  const stA = Sim.KI.policyStand();
  Sim.KI.policySetzen(null);
  const G = Sim.neueStadt(seed); bis(G, ab);
  const g0 = G.stat.gruendungen, k = zustandKopie(Sim, G);
  const A = zustandLaden(Sim, k); bis(A, ab + tage);
  Sim.KI.policySetzen(pol);
  const B = zustandLaden(Sim, k); bis(B, ab + tage);
  const stB = Sim.KI.policyStand();
  Sim.KI.policySetzen(null);
  const z = { seed, neu: { regeln: kz(R), policy: kz(P), stand: stA }, gewachsen: { start: { tag: ab, einwohner: G.einwohner, kasse: Math.round(G.budget) },
    regeln: kz(A, g0), policy: kz(B, g0), stand: stB } };
  aus.je.push(z);
  console.log(`Seed ${seed} (a) neue Stadt bis Tag ${neuTage}:  Regeln ${JSON.stringify(z.neu.regeln)}`);
  console.log(`                                 Policy ${JSON.stringify(z.neu.policy)}  (${stA.entscheidungen} Entscheidungen, ${stA.warten}× gewartet, ${stA.regeln} nach Regeln, Rückfall ${stA.rueckfall})`);
  console.log(`Seed ${seed} (b) Tag ${ab} (${G.einwohner} Einw.) + ${tage} Tage: Regeln ${JSON.stringify(z.gewachsen.regeln)}`);
  console.log(`                                 Policy ${JSON.stringify(z.gewachsen.policy)}  (${stB.entscheidungen} Entscheidungen, Rückfall ${stB.rueckfall})`);
}
const summe = (teil, arm, key) => aus.je.reduce((s, z) => s + z[teil][arm][key], 0);
aus.summen = {};
for (const teil of ['neu', 'gewachsen']) {
  aus.summen[teil] = {};
  for (const arm of ['regeln', 'policy']) aus.summen[teil][arm] = { einwohner: summe(teil, arm, 'einwohner'), kasse: summe(teil, arm, 'kasse'),
    gruendungen: summe(teil, arm, 'gruendungen'), pleiten: summe(teil, arm, 'pleiten'), zufriedenheit: +(summe(teil, arm, 'zufriedenheit') / seeds.length).toFixed(1) };
  aus.summen[teil].rueckfall = aus.je.reduce((s, z) => s + z[teil].stand.rueckfall, 0);
}
console.log('Summen über die Seeds:', JSON.stringify(aus.summen));
if (arg('aus')) { mkdirSync(dirname(arg('aus')), { recursive: true }); writeFileSync(arg('aus'), JSON.stringify(aus, null, 1)); }
