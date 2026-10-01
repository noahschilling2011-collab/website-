#!/usr/bin/env node
// Paritätstest, Teil JS: dieselben Fälle (training/paritaet.py) durch Sim.KI.policyRechnen (Browser-Inferenz im sim-Block).
//   node tools/paritaet.mjs ki/policy_<name>.json ki/paritaet_<name>.json [--html stadt.html]
// Toleranzen (vorher festgelegt, ki/LIESMICH.md): normalisierte Eingabe |Δ| ≤ 1e-6, Logits |Δ| ≤ 1e-4 (PyTorch rechnet in float32, JS in
// float64 mit float32-Gewichten und eigener tanh); gleiche Aktion wie MaskablePPO.predict(deterministic) außer bei Gleichstand
// (Abstand der zwei besten erlaubten Logits ≤ 1e-4). Dazu: tanh aus Grundrechenarten gegen Math.tanh.
import { readFileSync } from 'node:fs';
import { ladeSim } from './simkern.mjs';

const TOL_Z = 1e-6, TOL_LOGIT = 1e-4, TOL_GLEICH = 1e-4;
const args = process.argv.slice(2);
const i = args.indexOf('--html');
const [polPfad, fallPfad] = args.filter((a, k) => !a.startsWith('--') && (i < 0 || k !== i + 1));
if (!polPfad || !fallPfad) { console.error('Aufruf: node tools/paritaet.mjs policy.json paritaet.json'); process.exit(2); }
const { Sim } = ladeSim(i >= 0 ? args[i + 1] : undefined);
const d = JSON.parse(readFileSync(polPfad, 'utf8')), F = JSON.parse(readFileSync(fallPfad, 'utf8'));
const pol = Sim.KI.policyPruefen(d);
let fehl = 0;
const ok = (b, t) => { console.log((b ? 'ok   ' : 'FEHL ') + t); if (!b) fehl++; };
ok(F.policyHash === d.hash, `Fälle gehören zur Policy ${d.name} (Hash ${d.hash})`);
let maxZ = 0, maxL = 0, gleich = 0, anders = 0, gleichstand = 0;
const proArt = {};
for (const f of F.faelle) {
  const beob = Float32Array.from(f.beob), maske = Uint8Array.from(f.maske);
  for (let k = 0; k < beob.length; k++) {
    const z0 = (beob[k] - pol.mittel[k]) / pol.streuung[k], z = Math.fround(Math.max(-pol.clip, Math.min(pol.clip, z0)));
    maxZ = Math.max(maxZ, Math.abs(z - f.z[k]));
  }
  const r = Sim.KI.policyRechnen(pol, beob, maske);
  let dl = 0;
  for (let k = 0; k < r.logits.length; k++) dl = Math.max(dl, Math.abs(r.logits[k] - f.logits[k]));
  maxL = Math.max(maxL, dl);
  const erlaubt = [...r.logits].map((v, k) => [v, k]).filter(([, k]) => maske[k]).sort((a, b) => b[0] - a[0]);
  const knapp = erlaubt.length > 1 && erlaubt[0][0] - erlaubt[1][0] <= TOL_GLEICH;
  const a = proArt[f.art] || (proArt[f.art] = { n: 0, gleich: 0 });
  a.n++;
  if (r.aktion === f.aktion) { gleich++; a.gleich++; } else if (knapp) gleichstand++; else anders++;
}
ok(maxZ <= TOL_Z, `normalisierte Eingaben: größte Abweichung ${maxZ.toExponential(2)} (Toleranz ${TOL_Z})`);
ok(maxL <= TOL_LOGIT, `Logits: größte Abweichung ${maxL.toExponential(2)} (Toleranz ${TOL_LOGIT}) über ${F.faelle.length} Fälle`);
ok(anders === 0, `Aktion gleich in ${gleich} von ${F.faelle.length} Fällen, ${gleichstand} Gleichstände (≤ ${TOL_GLEICH}), ${anders} echte Unterschiede; `
  + Object.entries(proArt).map(([k, v]) => `${k} ${v.gleich}/${v.n}`).join(', '));
let maxT = 0;
for (let x = -25; x <= 25; x += 0.001) maxT = Math.max(maxT, Math.abs(Sim.KI.tanh(x) - Math.tanh(x)));
for (const x of [0, -0, 1e-300, -1e-12, 5e-8, 18.99, 19.01, 700, -700, Infinity, -Infinity]) maxT = Math.max(maxT, Math.abs(Sim.KI.tanh(x) - Math.tanh(x)));
ok(maxT <= 1e-15 && Number.isNaN(Sim.KI.tanh(NaN)), `tanh aus Grundrechenarten gegen Math.tanh: größte Abweichung ${maxT.toExponential(2)} (−25…25, Schritt 0,001, Randwerte)`);
console.log(fehl ? `${fehl} FEHL` : 'Parität bestanden');
process.exit(fehl ? 1 : 0);
