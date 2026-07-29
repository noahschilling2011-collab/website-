#!/usr/bin/env node
/**
 * Dev-Werkzeug: prüft, ob eine zusätzliche Tagging-Variante wirklich neue
 * Blitzer bringt — und ob sie spezifisch genug ist.
 *
 *   npx tsx scripts/assess-candidates.ts DE-BW
 *
 * explore-tagging.ts sagt nur, WIE VIELE Objekte eine Variante trifft. Das
 * ist die unwichtigere Hälfte: Die meisten Treffer sind Objekte, die über
 * highway=speed_camera oder die Enforcement-Relation ohnehin schon im
 * Datensatz stehen. Entscheidend ist der Rest.
 *
 * Dieses Skript holt die Kandidaten mit Koordinaten, gleicht sie gegen den
 * gebauten Datensatz ab und zeigt für die verbleibenden ihre Tags. Erst
 * daran lässt sich beurteilen, ob es Blitzer sind oder Verkehrskameras.
 */
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { overpassQuery, type OverpassElement } from './lib/overpass.js';
import { haversine, type Camera } from './lib/normalize.js';
import { GERMANY, OPTIONAL_COUNTRIES } from './lib/regions.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CACHE_DIR = join(ROOT, '.overpass-cache');
const DATA_FILE = join(ROOT, 'assets', 'data', 'cameras.json');

/** Ab diesem Abstand gilt ein Kandidat als bereits erfasst. */
const COVERED_RADIUS_M = 30;

const code = (process.argv[2] ?? 'DE-BW').toUpperCase();
const region = [...GERMANY, ...OPTIONAL_COUNTRIES].find((r) => r.code === code);
if (!region) throw new Error(`Unbekanntes Gebiet: ${code}`);

const area = code.includes('-')
  ? `area["ISO3166-2"="${code}"]`
  : `area["ISO3166-1"="${code}"][admin_level=2]`;

type Candidate = { label: string; selector: string; verdachtsmoment: string };

const CANDIDATES: Candidate[] = [
  {
    label: 'node[enforcement]',
    selector: 'node["enforcement"](area.a);',
    verdachtsmoment: 'Node direkt mit enforcement getaggt, ohne Relation drumherum',
  },
  {
    label: 'node[speed_camera]',
    selector: 'node["speed_camera"](area.a);',
    verdachtsmoment: 'abweichendes Tagging, vermutlich Zusatztag auf bekannten Kameras',
  },
  {
    label: 'node[surveillance:type=ALPR]',
    selector: 'node["surveillance:type"="ALPR"](area.a);',
    verdachtsmoment: 'Kennzeichenerfassung — Abschnittskontrolle, Maut oder Polizei?',
  },
  {
    label: 'node[man_made=surveillance][surveillance:zone=traffic]',
    selector: 'node["man_made"="surveillance"]["surveillance:zone"="traffic"](area.a);',
    verdachtsmoment: 'grosser Topf, überwiegend Verkehrsbeobachtung ohne Bussgeld',
  },
];

if (!existsSync(DATA_FILE)) {
  throw new Error(`Kein Datensatz: ${DATA_FILE}. Zuerst build-dataset laufen lassen.`);
}
const dataset = JSON.parse(readFileSync(DATA_FILE, 'utf8')) as {
  grid: Record<string, Camera[]>;
};
const known = Object.values(dataset.grid).flat();
console.log(`Datensatz: ${known.length} Anlagen\n`);

const log = (m: string) => console.log(`     ${m}`);

function nearestKnown(lat: number, lon: number): number {
  let best = Infinity;
  for (const c of known) {
    // Billiger Vorfilter, bevor Haversine gerechnet wird.
    if (Math.abs(c.lat - lat) > 0.01 || Math.abs(c.lon - lon) > 0.02) continue;
    const d = haversine(lat, lon, c.lat, c.lon);
    if (d < best) best = d;
  }
  return best;
}

for (const cand of CANDIDATES) {
  console.log('═'.repeat(76));
  console.log(cand.label);
  console.log(cand.verdachtsmoment);
  console.log('═'.repeat(76));

  const query = `[out:json][timeout:300];
${area}->.a;
(
  ${cand.selector}
);
out body;`;

  let elements: OverpassElement[];
  try {
    const res = await overpassQuery(query, { cacheDir: CACHE_DIR, log });
    elements = res.elements.filter((e) => e.lat != null && e.lon != null);
  } catch (err) {
    console.error(`  FEHLER: ${(err as Error).message}\n`);
    continue;
  }

  const neu: OverpassElement[] = [];
  let erfasst = 0;
  for (const el of elements) {
    if (nearestKnown(el.lat!, el.lon!) <= COVERED_RADIUS_M) erfasst++;
    else neu.push(el);
  }

  console.log(`\n  Treffer gesamt:        ${elements.length}`);
  console.log(`  bereits im Datensatz:  ${erfasst}`);
  console.log(`  NEU:                   ${neu.length}`);

  if (neu.length === 0) {
    console.log('\n  -> bringt nichts, nicht aufnehmen.\n');
    continue;
  }

  // Welche Tags tragen die neuen Kandidaten? Daran entscheidet sich, ob es
  // Blitzer sind oder etwas anderes.
  const tagHaeufigkeit = new Map<string, number>();
  for (const el of neu) {
    for (const [k, v] of Object.entries(el.tags ?? {})) {
      const key = `${k}=${v}`;
      tagHaeufigkeit.set(key, (tagHaeufigkeit.get(key) ?? 0) + 1);
    }
  }
  const top = [...tagHaeufigkeit].sort((a, b) => b[1] - a[1]).slice(0, 18);
  console.log('\n  Häufigste Tags der NEUEN Kandidaten:');
  for (const [tag, n] of top) {
    console.log(`    ${String(n).padStart(5)}x  ${tag}`);
  }

  console.log('\n  Drei Beispiele:');
  for (const el of neu.slice(0, 3)) {
    console.log(`    https://www.openstreetmap.org/node/${el.id}`);
    console.log(`      ${JSON.stringify(el.tags ?? {})}`);
  }
  console.log('');
}

console.log('═'.repeat(76));
console.log(
  'Entscheidungsregel: aufnehmen nur, wenn die neuen Kandidaten eindeutig\n' +
  'Verkehrsüberwachung mit Bussgeld sind. Im Zweifel weglassen — ein\n' +
  'Fehlalarm entwertet auch die richtigen Warnungen.',
);
