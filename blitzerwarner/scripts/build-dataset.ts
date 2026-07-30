#!/usr/bin/env node
/**
 * Baut den Blitzer-Datensatz aus OpenStreetMap.
 *
 * Läuft VOR dem App-Build, nie zur Laufzeit. Ergebnis ist ein einziges JSON,
 * das als Asset gebündelt und beim App-Start einmal geparst wird.
 *
 *   npm run build-dataset                     # nur Deutschland
 *   npm run build-dataset -- --countries DE,AT,CH
 *   npm run build-dataset -- --regions DE-BW  # einzelnes Gebiet nachziehen
 *   npm run build-dataset -- --no-cache       # Overpass frisch abfragen
 *
 * Datenquelle: OpenStreetMap contributors, ODbL 1.0.
 */
import { mkdirSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { overpassQuery, isCached } from './lib/overpass.js';
import {
  normalize,
  dedupe,
  buildGrid,
  boundingBox,
  CELL_SIZE,
  type RawCamera,
} from './lib/normalize.js';
import { regionsFor, queryFor, type Region } from './lib/regions.js';

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const OUT_FILE = join(ROOT, 'assets', 'data', 'cameras.json');
const STATS_FILE = join(ROOT, 'assets', 'data', 'cameras.stats.json');
const CACHE_DIR = join(ROOT, '.overpass-cache');

type Args = { countries: string[]; regions: string[] | null; noCache: boolean; out: string };

function parseArgs(argv: string[]): Args {
  const args: Args = { countries: ['DE'], regions: null, noCache: false, out: OUT_FILE };
  let explicitOut = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--countries') args.countries = argv[++i].split(',').map((s) => s.trim().toUpperCase());
    // Einzelne Gebiete nachziehen, ohne alles neu zu bauen:
    //   --regions DE-BW,DE-BY
    else if (argv[i] === '--regions') args.regions = argv[++i].split(',').map((s) => s.trim().toUpperCase());
    else if (argv[i] === '--no-cache') args.noCache = true;
    else if (argv[i] === '--out') { args.out = argv[++i]; explicitOut = true; }
  }
  // Ein Teillauf darf den vollständigen Datensatz nicht überschreiben.
  if (args.regions && !explicitOut) {
    args.out = join(dirname(OUT_FILE), 'cameras.partial.json');
  }
  return args;
}

type RegionResult = {
  region: Region;
  raw: number;
  cameras: RawCamera[];
  timestamp?: string;
  error?: string;
};

async function main() {
  const args = parseArgs(process.argv.slice(2));
  let regions = regionsFor(args.countries);
  if (args.regions) {
    const wanted = new Set(args.regions);
    regions = regions.filter((r) => wanted.has(r.code));
    const unknown = args.regions.filter((c) => !regions.some((r) => r.code === c));
    if (unknown.length) throw new Error(`Unbekannte Gebiete: ${unknown.join(', ')}`);
  }

  console.log(`Blitzer-Datensatz bauen für: ${args.countries.join(', ')}`);
  console.log(`${regions.length} Gebiete, Cache: ${CACHE_DIR}\n`);

  const results: RegionResult[] = [];
  let osmTimestamp: string | undefined;
  let queriedSomething = false;

  for (const region of regions) {
    const query = queryFor(region);
    // Kurze Pause zwischen echten Abfragen. Overpass ist eine kostenlose,
    // gespendete Ressource; 16 Bundesländer am Stück ohne Pause führen
    // zuverlässig zu HTTP 429. Cache-Treffer warten nicht.
    const fromCache = !args.noCache && isCached(query, CACHE_DIR);
    if (queriedSomething && !fromCache) await sleep(3000);
    if (!fromCache) queriedSomething = true;

    process.stdout.write(`${region.code.padEnd(6)} ${region.name}\n`);
    try {
      const res = await overpassQuery(query, {
        cacheDir: CACHE_DIR,
        noCache: args.noCache,
        log: (m) => console.log(m),
      });
      const cameras = normalize(res.elements);
      osmTimestamp ??= res.osm3s?.timestamp_osm_base;
      results.push({
        region,
        raw: res.elements.length,
        cameras,
        timestamp: res.osm3s?.timestamp_osm_base,
      });
      console.log(`     ${res.elements.length} Elemente -> ${cameras.length} Kameras\n`);
    } catch (err) {
      console.error(`     FEHLER: ${(err as Error).message}\n`);
      results.push({ region, raw: 0, cameras: [], error: (err as Error).message });
    }
  }

  const failed = results.filter((r) => r.error);
  if (failed.length === results.length) {
    console.error('Kein einziges Gebiet konnte abgefragt werden. Abbruch.');
    process.exit(1);
  }

  // Deduplizierung global, nicht pro Gebiet: Anlagen direkt auf einer
  // Landesgrenze tauchen sonst zweimal auf.
  const all = results.flatMap((r) => r.cameras);
  const deduped = dedupe(all);
  const grid = buildGrid(deduped);

  // Pro Gebiet ebenfalls deduplizieren. Die Rohzahl zu berichten wäre
  // irreführend — sie zählt jede doppelt erfasste Anlage mit und liegt in
  // der Grössenordnung 70 % zu hoch. Die Summe der Gebietszahlen kann
  // minimal über der globalen Zahl liegen: Anlagen direkt auf einer
  // Landesgrenze werden global noch einmal zusammengefasst.
  const perRegion = results.map((r) => {
    const cams = dedupe(r.cameras);
    return {
      code: r.region.code,
      name: r.region.name,
      country: r.region.country,
      cameras: cams.length,
      raw: r.cameras.length,
      withDirection: cams.filter((c) => c.dir != null).length,
      withMaxspeed: cams.filter((c) => c.max != null).length,
      redLight: cams.filter((c) => c.type !== 'speed').length,
      error: r.error ?? null,
    };
  });

  const countries: Record<string, { bbox: [number, number, number, number] | null; count: number }> = {};
  for (const country of args.countries) {
    const cams = results.filter((r) => r.region.country === country).flatMap((r) => r.cameras);
    countries[country] = { bbox: boundingBox(cams), count: cams.length };
  }

  const dataset = {
    version: 1 as const,
    // OSM-Datenstand, nicht Build-Zeit: das ist die Zahl, die im
    // Einstellungs-Screen ehrlich als "Stand der Daten" steht.
    osmTimestamp: osmTimestamp ?? null,
    source: 'OpenStreetMap contributors',
    license: 'ODbL 1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    cell: CELL_SIZE,
    countries,
    count: deduped.length,
    grid,
  };

  mkdirSync(dirname(args.out), { recursive: true });
  writeFileSync(args.out, JSON.stringify(dataset));

  const stats = {
    generatedFrom: osmTimestamp ?? null,
    countries: args.countries,
    totalBeforeDedupe: all.length,
    totalAfterDedupe: deduped.length,
    removedByDedupe: all.length - deduped.length,
    cells: Object.keys(grid).length,
    withDirection: deduped.filter((c) => c.dir != null).length,
    withMaxspeed: deduped.filter((c) => c.max != null).length,
    byType: {
      speed: deduped.filter((c) => c.type === 'speed').length,
      red_light: deduped.filter((c) => c.type === 'red_light').length,
      both: deduped.filter((c) => c.type === 'both').length,
    },
    perRegion,
    failedRegions: failed.map((f) => ({ code: f.region.code, error: f.error })),
  };
  writeFileSync(STATS_FILE, JSON.stringify(stats, null, 2));

  const bytes = statSync(args.out).size;

  console.log('─'.repeat(64));
  console.log(`Kameras roh:        ${all.length}`);
  console.log(`nach Dedupe:        ${deduped.length}  (-${all.length - deduped.length})`);
  console.log(`Gitterzellen:       ${Object.keys(grid).length}`);
  console.log(`mit Richtung:       ${stats.withDirection} (${pct(stats.withDirection, deduped.length)})`);
  console.log(`mit maxspeed:       ${stats.withMaxspeed} (${pct(stats.withMaxspeed, deduped.length)})`);
  console.log(`Rotlicht/kombi:     ${stats.byType.red_light + stats.byType.both}`);
  console.log(`OSM-Datenstand:     ${osmTimestamp ?? 'unbekannt'}`);
  console.log(`Dateigrösse:        ${(bytes / 1024).toFixed(0)} KB -> ${args.out}`);
  if (failed.length) {
    console.log(`\nFehlgeschlagene Gebiete: ${failed.map((f) => f.region.code).join(', ')}`);
    console.log('Erneut ausführen — bereits geladene Gebiete kommen aus dem Cache.');
  }
  console.log('─'.repeat(64));
  console.log('\nKameras pro Bundesland/Land:');
  for (const r of [...perRegion].sort((a, b) => b.cameras - a.cameras)) {
    const flag = r.error ? '  FEHLER' : '';
    console.log(`  ${r.code.padEnd(6)} ${r.name.padEnd(24)} ${String(r.cameras).padStart(5)}${flag}`);
  }
}

function pct(n: number, total: number): string {
  return total === 0 ? '0 %' : `${((n / total) * 100).toFixed(1)} %`;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
