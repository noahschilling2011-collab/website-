#!/usr/bin/env node
/**
 * Dev-Werkzeug: seziert die gecachte Overpass-Antwort eines Gebiets.
 *
 *   npx tsx scripts/analyze-raw.ts DE-BW
 *
 * Beantwortet die Frage, die die blossen Kamerazahlen offen lassen:
 * Wo kommen die Einträge her, und was genau fasst der Dedupe zusammen?
 */
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { OverpassResponse } from './lib/overpass.js';
import { normalize, haversine, bearingDelta, DEDUPE_RADIUS_M } from './lib/normalize.js';
import { queryFor, GERMANY, OPTIONAL_COUNTRIES } from './lib/regions.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const CACHE_DIR = join(HERE, '..', '.overpass-cache');

const code = (process.argv[2] ?? 'DE-BW').toUpperCase();
const region = [...GERMANY, ...OPTIONAL_COUNTRIES].find((r) => r.code === code);
if (!region) throw new Error(`Unbekanntes Gebiet: ${code}`);

const hash = createHash('sha1').update(queryFor(region)).digest('hex').slice(0, 16);
const file = join(CACHE_DIR, `${hash}.json`);
if (!existsSync(file)) {
  throw new Error(`Keine gecachte Antwort für ${code}. Zuerst build-dataset ausführen.`);
}

const res = JSON.parse(readFileSync(file, 'utf8')) as OverpassResponse;

console.log(`Gebiet: ${region.name} (${code})`);
console.log(`Elemente gesamt: ${res.elements.length}\n`);

const byType = new Map<string, number>();
for (const el of res.elements) byType.set(el.type, (byType.get(el.type) ?? 0) + 1);
console.log('Nach OSM-Typ:');
for (const [t, n] of byType) console.log(`  ${t.padEnd(10)} ${n}`);

const enforcement = new Map<string, number>();
for (const el of res.elements) {
  if (el.type !== 'relation') continue;
  const v = el.tags?.enforcement ?? '(kein enforcement-Tag)';
  enforcement.set(v, (enforcement.get(v) ?? 0) + 1);
}
console.log('\nEnforcement-Relationen nach Wert:');
for (const [v, n] of [...enforcement].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${v.padEnd(28)} ${n}`);
}

const relationsWithoutCenter = res.elements.filter(
  (el) => el.type === 'relation' && el.lat == null && el.center == null,
).length;
console.log(`\nRelationen ohne Mittelpunkt (verworfen): ${relationsWithoutCenter}`);

// --- Was fasst der Dedupe zusammen? ---
const cams = normalize(res.elements);
console.log(`\nNormalisiert: ${cams.length}`);

type Pair = { d: number; nodeAndRelation: boolean; dirConflict: boolean };
const pairs: Pair[] = [];

// Die Herkunft steht direkt am normalisierten Eintrag (src) — sie hier noch
// einmal aus den Rohelementen zu rekonstruieren ginge schief, seit eine
// Relation je device-Node einen eigenen Eintrag erzeugt.
for (let i = 0; i < cams.length; i++) {
  for (let j = i + 1; j < cams.length; j++) {
    const a = cams[i], b = cams[j];
    const d = haversine(a.lat, a.lon, b.lat, b.lon);
    if (d > DEDUPE_RADIUS_M) continue;
    pairs.push({
      d,
      nodeAndRelation: a.src !== b.src,
      dirConflict: a.dir != null && b.dir != null && bearingDelta(a.dir, b.dir) > 45,
    });
  }
}

console.log(`\nPaare innerhalb ${DEDUPE_RADIUS_M} m: ${pairs.length}`);
console.log(`  davon Node+Relation (echte Dubletten):  ${pairs.filter((p) => p.nodeAndRelation).length}`);
console.log(`  davon gleicher Herkunftstyp:            ${pairs.filter((p) => !p.nodeAndRelation).length}`);
console.log(`  davon mit Richtungskonflikt (bleiben):  ${pairs.filter((p) => p.dirConflict).length}`);

const buckets = [1, 5, 10, 20, 30];
console.log('\nAbstandsverteilung dieser Paare:');
let prev = 0;
for (const b of buckets) {
  const n = pairs.filter((p) => p.d > prev && p.d <= b).length;
  console.log(`  ${String(prev).padStart(3)}–${String(b).padStart(3)} m: ${n}`);
  prev = b;
}

// Kameras ohne jede Richtungsangabe, die sich einen Standort teilen: das
// sind die Fälle, in denen der Dedupe potenziell zwei Fahrtrichtungen
// zusammenwirft.
const riskyPairs = pairs.filter((p) => !p.nodeAndRelation && !p.dirConflict);
console.log(`\nPotenziell zu aggressiv zusammengefasst: ${riskyPairs.length}`);
console.log('(gleicher Herkunftstyp, kein Richtungskonflikt — kann eine Gegenrichtung sein)');
