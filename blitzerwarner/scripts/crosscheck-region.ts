#!/usr/bin/env node
/**
 * Dev-Werkzeug: prüft eine auffällige Gebietszahl gegen eine unabhängig
 * formulierte Abfrage.
 *
 *   npx tsx scripts/crosscheck-region.ts DE-BY
 *
 * Hintergrund: die Pipeline wählt das Gebiet über `area["ISO3166-2"=...]`.
 * Wenn dieses Tag an der falschen Relation hängt, fehlt oder mehrfach
 * vergeben ist, kommt eine plausibel aussehende, aber falsche Zahl heraus.
 * Dieses Skript zählt dasselbe Gebiet noch einmal über den Namen und über
 * eine reine Bounding-Box und stellt die drei Zahlen nebeneinander.
 *
 * Die Bounding-Box-Zahl ist immer grösser (sie greift über die Landesgrenze
 * hinaus) — sie ist eine Obergrenze, keine Sollzahl. Interessant ist der
 * Vergleich der beiden Gebietszahlen: die müssen übereinstimmen.
 */
import { overpassQuery } from './lib/overpass.js';
import { GERMANY, OPTIONAL_COUNTRIES } from './lib/regions.js';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CACHE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '.overpass-cache');

/** Bounding-Boxen zum Gegenzählen: [süd, west, nord, ost]. */
const BBOX: Record<string, [number, number, number, number]> = {
  'DE-BW': [47.53, 7.51, 49.79, 10.50],
  'DE-BY': [47.27, 8.98, 50.56, 13.84],
  'DE-NW': [50.32, 5.87, 52.53, 9.46],
  'DE-NI': [51.29, 6.65, 53.89, 11.60],
  'DE-HE': [49.39, 7.77, 51.65, 10.24],
};

const code = (process.argv[2] ?? 'DE-BY').toUpperCase();
const region = [...GERMANY, ...OPTIONAL_COUNTRIES].find((r) => r.code === code);
if (!region) throw new Error(`Unbekanntes Gebiet: ${code}`);

const body = `(
  node["highway"="speed_camera"](area.a);
  relation["type"="enforcement"](area.a);
);
out count;`;

const byIso = `[out:json][timeout:300];
area["ISO3166-2"="${code}"]->.a;
${body}`;

const byName = `[out:json][timeout:300];
area["boundary"="administrative"]["admin_level"="4"]["name"="${region.name}"]->.a;
${body}`;

const log = (m: string) => console.log(m);

async function count(query: string): Promise<number> {
  const res = await overpassQuery(query, { cacheDir: CACHE_DIR, log });
  const el = res.elements.find((e) => (e as { type: string }).type === 'count');
  const tags = (el as unknown as { tags?: Record<string, string> })?.tags;
  return Number(tags?.total ?? 0);
}

console.log(`Gegenprobe für ${region.name} (${code})\n`);

const iso = await count(byIso);
console.log(`über ISO3166-2:      ${iso}`);

const name = await count(byName);
console.log(`über Name+Level 4:   ${name}`);

const box = BBOX[code];
if (box) {
  const byBox = `[out:json][timeout:300];
(
  node["highway"="speed_camera"](${box.join(',')});
  relation["type"="enforcement"](${box.join(',')});
);
out count;`;
  const bbox = await count(byBox);
  console.log(`über Bounding-Box:   ${bbox}   (Obergrenze, greift über die Grenze hinaus)`);
}

console.log(
  iso === name
    ? '\nBeide Gebietsabfragen stimmen überein — die Zahl ist echt.'
    : `\nABWEICHUNG: ${iso} vs. ${name}. Die Gebietsauswahl stimmt nicht.`,
);
