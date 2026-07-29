#!/usr/bin/env node
/**
 * Phase 6, Schritt 1: Mengengerüst für den Tempolimit-Datensatz.
 *
 *   npx tsx scripts/count-speedlimits.ts DE-BW
 *
 * Zählt, wie viele Wege mit gesetztem maxspeed es pro Strassenklasse gibt
 * und wie viele Stützpunkte deren Geometrie hat. Daraus folgt die
 * Grössenordnung — BEVOR mehrere hundert MB Geometrie heruntergeladen
 * werden, die hier weder auf die Platte noch in den Speicher müssen.
 *
 * Die tatsächliche Grösse misst erst der Build. Diese Zahlen sagen nur,
 * ob der Build überhaupt sinnvoll ist und mit welchem Filter.
 */
import { overpassQuery } from './lib/overpass.js';
import { GERMANY, OPTIONAL_COUNTRIES } from './lib/regions.js';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CACHE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '.overpass-cache');

/** Strassenklassen aus Spec 4b, absteigend nach Nutzen für die Anzeige. */
export const ROAD_CLASSES = [
  'motorway',
  'trunk',
  'primary',
  'secondary',
  'tertiary',
  'unclassified',
  'residential',
] as const;

/** Die Rückfallebene aus Spec 4b, falls der volle Satz zu gross wird. */
export const REDUCED_CLASSES = ['motorway', 'trunk', 'primary', 'secondary'] as const;

const code = (process.argv[2] ?? 'DE-BW').toUpperCase();
const region = [...GERMANY, ...OPTIONAL_COUNTRIES].find((r) => r.code === code);
if (!region) throw new Error(`Unbekanntes Gebiet: ${code}`);

const area = code.includes('-')
  ? `area["ISO3166-2"="${code}"]`
  : `area["ISO3166-1"="${code}"][admin_level=2]`;

const log = (m: string) => console.log(`     ${m}`);

type Counts = { ways: number; nodes: number };

/**
 * Wege UND deren Stützpunkte zählen. Die Stützpunktzahl ist die Grösse,
 * an der die Dateigrösse tatsächlich hängt — nicht die Wegzahl.
 */
async function count(highwayFilter: string, withMaxspeed: boolean): Promise<Counts> {
  const maxspeedFilter = withMaxspeed ? '["maxspeed"]' : '';
  const query = `[out:json][timeout:900];
${area}->.a;
way["highway"~"^(${highwayFilter})$"]${maxspeedFilter}(area.a)->.w;
.w out count;
node(w.w)->.n;
.n out count;`;

  const res = await overpassQuery(query, { cacheDir: CACHE_DIR, log });
  const counts = res.elements.filter(
    (e) => (e as unknown as { type: string }).type === 'count',
  ) as unknown as { tags: Record<string, string> }[];

  return {
    ways: Number(counts[0]?.tags?.ways ?? counts[0]?.tags?.total ?? 0),
    nodes: Number(counts[1]?.tags?.nodes ?? counts[1]?.tags?.total ?? 0),
  };
}

console.log(`Mengengerüst Tempolimits — ${region.name} (${code})\n`);

const ergebnisse: { klasse: string; mitMaxspeed: Counts }[] = [];

for (const klasse of ROAD_CLASSES) {
  process.stdout.write(`${klasse}\n`);
  const mitMaxspeed = await count(klasse, true);
  ergebnisse.push({ klasse, mitMaxspeed });
  console.log(`     ${mitMaxspeed.ways} Wege, ${mitMaxspeed.nodes} Stützpunkte\n`);
}

console.log('═'.repeat(70));
console.log('Klasse           Wege    Stützpunkte   Punkte/Weg');
console.log('─'.repeat(70));
let summeWays = 0;
let summeNodes = 0;
for (const e of ergebnisse) {
  const proWeg = e.mitMaxspeed.ways ? (e.mitMaxspeed.nodes / e.mitMaxspeed.ways).toFixed(1) : '—';
  console.log(
    `${e.klasse.padEnd(14)} ${String(e.mitMaxspeed.ways).padStart(7)} ` +
    `${String(e.mitMaxspeed.nodes).padStart(14)} ${proWeg.padStart(12)}`,
  );
  summeWays += e.mitMaxspeed.ways;
  summeNodes += e.mitMaxspeed.nodes;
}
console.log('─'.repeat(70));
console.log(`${'SUMME'.padEnd(14)} ${String(summeWays).padStart(7)} ${String(summeNodes).padStart(14)}`);

const reduziert = ergebnisse.filter((e) => (REDUCED_CLASSES as readonly string[]).includes(e.klasse));
const redWays = reduziert.reduce((n, e) => n + e.mitMaxspeed.ways, 0);
const redNodes = reduziert.reduce((n, e) => n + e.mitMaxspeed.nodes, 0);
console.log(`${'davon reduz.'.padEnd(14)} ${String(redWays).padStart(7)} ${String(redNodes).padStart(14)}   (motorway+trunk+primary+secondary)`);

console.log('\n' + '═'.repeat(70));
console.log('Grobe Grössenabschätzung (die echte Zahl liefert erst der Build):');
console.log('─'.repeat(70));

// Rohe Rechnung ohne Vereinfachung: pro Stützpunkt 2x Float32 = 8 Byte,
// pro Weg ein Kopf mit maxspeed und Punktzahl.
for (const [label, ways, nodes] of [
  ['voller Satz', summeWays, summeNodes],
  ['reduziert', redWays, redNodes],
] as const) {
  const rohBytes = nodes * 8 + ways * 4;
  console.log(
    `${label.padEnd(14)} ohne Vereinfachung: ${(rohBytes / 1024 / 1024).toFixed(1)} MB ` +
    `(${nodes} Punkte x 8 B + ${ways} Köpfe x 4 B)`,
  );
}

console.log(
  '\nDouglas-Peucker (Spec 4b, 10 m Toleranz) entfernt Stützpunkte auf\n' +
  'geraden Abschnitten. Wie viel das bringt, hängt am Strassenverlauf und\n' +
  'ist nicht abschätzbar — das misst der Build.',
);
