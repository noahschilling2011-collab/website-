#!/usr/bin/env node
/**
 * Replay-Harness — das Werkzeug, ohne das Phase 3 stirbt.
 *
 * Spielt einen GPX-Track gegen ein Kameragitter ab und liefert genau die
 * Warnungen, die die App ausgelöst hätte, plus die Begründung für jede
 * verworfene Kamera. Damit lässt sich die Warnlogik am Schreibtisch
 * debuggen statt im Auto.
 *
 *   npx tsx src/replay/replay.ts fixtures/kamera-in-fahrtrichtung.gpx
 *   npx tsx src/replay/replay.ts --all
 *   npx tsx src/replay/replay.ts fahrt.gpx --dataset   # echter Datensatz
 *
 * Jeder gemeldete Fehlalarm wird als neuer Track hier abgelegt, BEVOR er
 * gefixt wird. Sonst kommt er zurück.
 */
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, join, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseGpx, toFixes } from './gpx';
import { cellKey } from '../core/geo';
import { createZonenZustand, pruefeZonen, type Zone as ZoneFixture } from '../core/zone';
import { createTripState, evaluate, warnDistance } from '../core/warn';
import type { Camera, Evaluation, Fix, Settings, SkipReason } from '../types';

const HERE = dirname(fileURLToPath(import.meta.url));
const APP_ROOT = join(HERE, '..', '..');
const FIXTURES = join(APP_ROOT, 'fixtures');

export type ReplayErwartung = {
  beschreibung: string;
  kameras: Camera[];
  /**
   * Zonen statt Kameras — für Tracks im Zonenmodus (Frankreich).
   *
   * Ist das Feld gesetzt, läuft der Track durch pruefeZonen() statt durch
   * evaluate(). Beides in einem Track zu mischen wäre falsch: Ein Land hat
   * genau einen Modus, und ein Track, der beides prüft, prüft keinen von
   * beiden richtig.
   */
  zonen?: ZoneFixture[];
  /** Wie viele Warnungen der Track auslösen MUSS. */
  erwarteteWarnungen: number;
  /** Optional: Einstellungen, falls abweichend. */
  settings?: Partial<Settings>;
};

export type ReplayErgebnis = {
  name: string;
  punkte: number;
  warnungen: { distance: number; t: number; lat: number; lon: number; max: number | null }[];
  /** Wie oft welcher Grund zum Verwerfen führte. */
  gruende: Record<string, number>;
  /** Grösste Distanz, bei der gewarnt wurde. */
  maxWarndistanz: number | null;
};

const STANDARD_SETTINGS: Pick<Settings, 'rotlichtblitzer' | 'warnDistanceFactor'> = {
  rotlichtblitzer: true,
  warnDistanceFactor: 1,
};

/**
 * Kameras in das Gitter einsortieren, wie es die Pipeline tut.
 *
 * Bewusst über dieselbe cellKey-Funktion wie die Laufzeit: Ein Fehler in der
 * Zellzuordnung soll im Test auffallen und nicht durch eine eigene Testhilfe
 * verdeckt werden.
 */
export function gridFrom(kameras: Camera[]): Record<string, Camera[]> {
  const grid: Record<string, Camera[]> = {};
  for (const k of kameras) {
    const key = cellKey(k.lat, k.lon);
    (grid[key] ??= []).push(k);
  }
  return grid;
}

/**
 * Einen Zonen-Track abspielen.
 *
 * Gibt zurück, wie viele Zonen-Ansagen ausgelöst wurden und bei welchem
 * Punktindex — daraus lässt sich prüfen, ob der Eintritt früh genug kam.
 */
export function replayZonen(
  fixes: Fix[],
  zonen: readonly ZoneFixture[],
): { ansagen: number; ersterEintrittIndex: number | null } {
  const zustand = createZonenZustand();
  let ansagen = 0;
  let ersterEintrittIndex: number | null = null;

  for (let i = 0; i < fixes.length; i++) {
    const fix = fixes[i]!;
    const erg = pruefeZonen(fix.lat, fix.lon, zonen, zustand);
    if (erg.betreten) {
      ansagen++;
      if (ersterEintrittIndex === null) ersterEintrittIndex = i;
    }
  }
  return { ansagen, ersterEintrittIndex };
}

/** Einen Track abspielen. */
export function replay(
  fixes: Fix[],
  kameras: Camera[],
  settings: Partial<Settings> = {},
): ReplayErgebnis & { evaluations: Evaluation[] } {
  const grid = gridFrom(kameras);
  const state = createTripState();
  const conf = { ...STANDARD_SETTINGS, ...settings };

  const warnungen: ReplayErgebnis['warnungen'] = [];
  const gruende: Record<string, number> = {};
  const evaluations: Evaluation[] = [];

  for (const fix of fixes) {
    const ergebnis = evaluate(fix, grid, state, conf, true);
    evaluations.push(ergebnis);

    if (ergebnis.warning) {
      warnungen.push({
        distance: ergebnis.warning.distance,
        t: ergebnis.warning.t,
        lat: ergebnis.warning.camera.lat,
        lon: ergebnis.warning.camera.lon,
        max: ergebnis.warning.camera.max,
      });
    }
    for (const s of ergebnis.skipped ?? []) {
      gruende[s.reason] = (gruende[s.reason] ?? 0) + 1;
    }
  }

  return {
    name: '',
    punkte: fixes.length,
    warnungen,
    gruende,
    maxWarndistanz: warnungen.length ? Math.max(...warnungen.map((w) => w.distance)) : null,
    evaluations,
  };
}

/** Track samt Erwartungsdatei laden. */
export function ladeFixture(name: string): { fixes: Fix[]; erwartung: ReplayErwartung } {
  const gpxPfad = name.endsWith('.gpx') ? name : join(FIXTURES, `${name}.gpx`);
  const erwartungPfad = gpxPfad.replace(/\.gpx$/, '.expect.json');

  if (!existsSync(gpxPfad)) throw new Error(`Track nicht gefunden: ${gpxPfad}`);
  if (!existsSync(erwartungPfad)) {
    throw new Error(
      `Erwartungsdatei fehlt: ${erwartungPfad}\n` +
      'Ein Track ohne Erwartung testet nichts.',
    );
  }

  const fixes = toFixes(parseGpx(readFileSync(gpxPfad, 'utf8')));
  const erwartung = JSON.parse(readFileSync(erwartungPfad, 'utf8')) as ReplayErwartung;
  return { fixes, erwartung };
}

/** Alle Fixture-Namen im Verzeichnis. */
export function alleFixtures(): string[] {
  if (!existsSync(FIXTURES)) return [];
  return readdirSync(FIXTURES)
    .filter((f) => f.endsWith('.gpx'))
    .map((f) => basename(f, '.gpx'))
    .sort();
}

// --- CLI ------------------------------------------------------------------

/**
 * Läuft dieses Modul als Programm oder wurde es importiert?
 *
 * Der naive Test `process.argv[1].includes('replay')` greift auch, wenn
 * replay.test.ts das Modul importiert — dann startet die CLI mitten im
 * Testlauf und beendet den Prozess. Verglichen wird deshalb der auflösbare
 * Pfad des Einstiegsmoduls mit dem eigenen.
 */
function istHauptmodul(): boolean {
  const einstieg = process.argv[1];
  if (!einstieg) return false;
  try {
    return fileURLToPath(import.meta.url) === resolve(einstieg);
  } catch {
    return false;
  }
}

function berichte(name: string, erg: ReplayErgebnis, erwartet: number | null): boolean {
  const ok = erwartet == null || erg.warnungen.length === erwartet;
  console.log('─'.repeat(70));
  console.log(`${name}`);
  console.log(`  Punkte:            ${erg.punkte}`);
  console.log(
    `  Warnungen:         ${erg.warnungen.length}` +
    (erwartet != null ? `  (erwartet ${erwartet})  ${ok ? 'OK' : 'ABWEICHUNG'}` : ''),
  );
  for (const w of erg.warnungen) {
    console.log(`    bei ${w.distance.toFixed(0)} m, Tempo ${w.max ?? 'unbekannt'}`);
  }
  const gruende = Object.entries(erg.gruende).sort((a, b) => b[1] - a[1]);
  if (gruende.length) {
    console.log('  verworfen:');
    for (const [grund, n] of gruende) console.log(`    ${grund.padEnd(20)} ${n}x`);
  }
  return ok;
}

if (istHauptmodul()) {
  const args = process.argv.slice(2);
  const namen = args.includes('--all') ? alleFixtures() : args.filter((a) => !a.startsWith('--'));

  if (namen.length === 0) {
    console.error('Kein Track angegeben. Nutzung:\n' +
      '  npx tsx src/replay/replay.ts <track.gpx|fixture-name>\n' +
      '  npx tsx src/replay/replay.ts --all');
    process.exit(1);
  }

  console.log(`Replay von ${namen.length} Track(s)\n`);
  let alleOk = true;

  for (const name of namen) {
    try {
      const { fixes, erwartung } = ladeFixture(name);
      const erg = replay(fixes, erwartung.kameras, erwartung.settings);
      const ok = berichte(`${name} — ${erwartung.beschreibung}`, erg, erwartung.erwarteteWarnungen);
      if (!ok) alleOk = false;
    } catch (err) {
      console.error(`${name}: FEHLER — ${(err as Error).message}`);
      alleOk = false;
    }
  }

  console.log('─'.repeat(70));
  console.log(alleOk ? 'Alle Tracks wie erwartet.' : 'ABWEICHUNGEN — siehe oben.');
  console.log(`\nWarndistanz zur Einordnung: bei 100 km/h ${warnDistance(27.8).toFixed(0)} m, ` +
    `bei 160 km/h ${warnDistance(44.4).toFixed(0)} m`);
  process.exit(alleOk ? 0 : 1);
}
