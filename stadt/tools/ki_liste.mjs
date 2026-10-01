#!/usr/bin/env node
// Schreibt ki/policies.json: die Liste der Policy-Dateien in ki/ (nur die Ebene ki/, nicht ki/v8/), die die aktuelle stadt.html annimmt
// (Sim.KI.policyPruefen: Format, Stadt-Version, Schema-Hash, Inhalts-Hash, Zahlen). Das Spiel liest diese Liste mit relativer URL, wenn Noah
// „Trainierte Policy (experimentell)“ wählt (Noahs Regel: nicht freigegebene Policies stecken nicht in stadt.html). Entwicklungswerkzeug.
// Achtung seit Version 10 (Etappe 2): ki/policies.json nennt absichtlich noch policy_v9_lokal_1.json (Kopf „simVersion“: 9), damit das Spiel die
// Policy aus Etappe 1 sichtbar ablehnt („neu trainieren“, Noahs Entscheidung 5; tests/browser_ki.cjs, ki/LIESMICH.md). Ein Lauf ohne
// --nur-pruefen schreibt die Liste leer und nimmt diese Ablehnung weg; erst nach einem Training auf Version 10 neu schreiben.
//   node tools/ki_liste.mjs [--html stadt.html] [--nur-pruefen]
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { ladeSim, HIER } from './simkern.mjs';

const args = process.argv.slice(2);
const i = args.indexOf('--html');
const { Sim } = ladeSim(i >= 0 ? args[i + 1] : undefined);
const KI = join(HIER, '..', 'ki');
const dateien = readdirSync(KI).filter(n => /^policy_[A-Za-z0-9_.-]+\.json$/.test(n)).sort();
const liste = [], abgelehnt = [];
for (const n of dateien) {
  try {
    const pol = Sim.KI.policyPruefen(JSON.parse(readFileSync(join(KI, n), 'utf8')));
    liste.push(n);
    console.log(`  ok  ${n}: „${pol.name}“ (${pol.status}), Stadt-Version ${pol.simVersion}, Hash ${pol.hash}`);
  } catch (e) { abgelehnt.push(n); console.log(`  abgelehnt  ${n}: ${e.message}`); }
}
const d = { format: 'stadt-policy-liste', version: 1,
  hinweis: 'Von tools/ki_liste.mjs geschrieben: Policy-Dateien in diesem Ordner, die die stadt.html daneben annimmt. Das Spiel prüft jede Datei beim Laden noch einmal.',
  simVersion: Sim.VERSION, schemaHash: Sim.KI.schemaHash(), policies: liste };
if (!args.includes('--nur-pruefen')) { writeFileSync(join(KI, 'policies.json'), JSON.stringify(d, null, 1) + '\n'); console.log(`geschrieben: ki/policies.json (${liste.length} Policies, ${abgelehnt.length} abgelehnt)`); }
