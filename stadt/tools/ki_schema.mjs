#!/usr/bin/env node
// Schreibt das Beobachtungs- und Aktionsschema der aktuellen stadt.html nach ki/schema_v<Version>.json (Doku, Vergleich zwischen Fassungen).
//   node tools/ki_schema.mjs [--html stadt.html]
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { ladeSim, HIER } from './simkern.mjs';

const i = process.argv.indexOf('--html');
const { Sim, simHash } = ladeSim(i >= 0 ? process.argv[i + 1] : undefined);
const K = Sim.KI;
const d = { schemaVersion: K.SCHEMA, schemaHash: K.schemaHash(), hashVerfahren: 'FNV-1a 32 Bit über schemaText (UTF-16-Codeeinheiten)', schemaText: K.schemaText(),
  simHash, laenge: K.MERKMALE.length, merkmale: K.MERKMALE.map(([name, skala, bedeutung], index) => ({ index, name, skala, bedeutung })),
  aktionen: K.AKTIONEN.map((name, index) => ({ index, name, hinweis: index === 0 ? 'warten: bewusst nichts tun (immer erlaubt)' : 'aus erlaubteAktionen (dieselben Voraussetzungen wie das Gehirn)' })) };
const aus = join(HIER, '..', 'ki', `schema_v${K.SCHEMA}.json`);
writeFileSync(aus, JSON.stringify(d, null, 1));
console.log(`geschrieben: ${aus} (Schema ${d.schemaHash}, ${d.laenge} Merkmale, ${d.aktionen.length} Aktionen)`);
