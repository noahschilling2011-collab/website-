#!/usr/bin/env node
/**
 * Dev-Werkzeug: misst, welche OSM-Taggings in einem Gebiet überhaupt
 * vorkommen und wie viel jede zusätzliche Variante bringen würde.
 *
 *   npx tsx scripts/explore-tagging.ts DE-BW
 *
 * Hintergrund: Die Pipeline erfasst `highway=speed_camera` und
 * `type=enforcement`. Blitzer werden in OSM aber nicht einheitlich getaggt.
 * Bevor eine Variante in die Produktivabfrage wandert, muss klar sein, wie
 * viel sie bringt UND wie viele Fehltreffer sie einschleppt — eine App, die
 * vor jeder Verkehrskamera warnt, ist wertlos.
 *
 * Reine Zählabfragen, entsprechend billig.
 */
import { overpassQuery } from './lib/overpass.js';
import { GERMANY, OPTIONAL_COUNTRIES } from './lib/regions.js';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CACHE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '.overpass-cache');

const code = (process.argv[2] ?? 'DE-BW').toUpperCase();
const region = [...GERMANY, ...OPTIONAL_COUNTRIES].find((r) => r.code === code);
if (!region) throw new Error(`Unbekanntes Gebiet: ${code}`);

const area = code.includes('-')
  ? `area["ISO3166-2"="${code}"]`
  : `area["ISO3166-1"="${code}"][admin_level=2]`;

type Probe = { label: string; selector: string; note: string };

const PROBES: Probe[] = [
  {
    label: 'node[highway=speed_camera]',
    selector: 'node["highway"="speed_camera"](area.a);',
    note: 'Basis, bereits erfasst',
  },
  {
    label: 'relation[type=enforcement]',
    selector: 'relation["type"="enforcement"](area.a);',
    note: 'Basis, bereits erfasst (inkl. Maut/Höhe, wird gefiltert)',
  },
  {
    label: 'node[enforcement=maxspeed]',
    selector: 'node["enforcement"="maxspeed"](area.a);',
    note: 'Node direkt mit enforcement getaggt, ohne Relation',
  },
  {
    label: 'node[enforcement] (alle Werte)',
    selector: 'node["enforcement"](area.a);',
    note: 'wie oben, alle enforcement-Werte',
  },
  {
    label: 'way[highway=speed_camera]',
    selector: 'way["highway"="speed_camera"](area.a);',
    note: 'Kamera als Way erfasst (selten)',
  },
  {
    label: 'node[man_made=surveillance][surveillance:zone=traffic]',
    selector: 'node["man_made"="surveillance"]["surveillance:zone"="traffic"](area.a);',
    note: 'ACHTUNG: enthält Verkehrsbeobachtung, nicht nur Blitzer',
  },
  {
    label: 'node[man_made=surveillance][enforcement]',
    selector: 'node["man_made"="surveillance"]["enforcement"](area.a);',
    note: 'Überwachung MIT enforcement — deutlich spezifischer',
  },
  {
    label: 'node[surveillance:type=ALPR]',
    selector: 'node["surveillance:type"="ALPR"](area.a);',
    note: 'Kennzeichenerfassung, meist Abschnittskontrolle/Maut',
  },
  {
    label: 'node[highway=speed_display]',
    selector: 'node["highway"="speed_display"](area.a);',
    note: 'KEIN Blitzer — Dialog-Display. Nur zur Kontrolle gezählt.',
  },
  {
    label: 'node[speed_camera]',
    selector: 'node["speed_camera"](area.a);',
    note: 'abweichendes Tagging',
  },
  {
    label: 'node[device=speed_camera]',
    selector: 'node["device"="speed_camera"](area.a);',
    note: 'abweichendes Tagging',
  },
];

const log = (m: string) => console.log(`   ${m}`);

async function count(selector: string): Promise<number> {
  const query = `[out:json][timeout:300];
${area}->.a;
(
  ${selector}
);
out count;`;
  const res = await overpassQuery(query, { cacheDir: CACHE_DIR, log });
  const el = res.elements.find((e) => (e as { type: string }).type === 'count');
  const tags = (el as unknown as { tags?: Record<string, string> })?.tags;
  return Number(tags?.total ?? 0);
}

console.log(`Tagging-Erhebung für ${region.name} (${code})\n`);
console.log('Anzahl  Selektor');
console.log('─'.repeat(78));

for (const probe of PROBES) {
  let n: number | string;
  try {
    n = await count(probe.selector);
  } catch (err) {
    n = 'FEHLER';
    console.error(`  ${(err as Error).message}`);
  }
  console.log(`${String(n).padStart(6)}  ${probe.label}`);
  console.log(`        ${probe.note}`);
}

console.log('─'.repeat(78));
console.log(
  '\nEine Variante gehört nur dann in die Produktivabfrage, wenn sie\n' +
  'nennenswert viel bringt UND spezifisch genug ist. Verkehrsbeobachtungs-\n' +
  'kameras als Blitzer zu melden macht die App unbrauchbar.',
);
