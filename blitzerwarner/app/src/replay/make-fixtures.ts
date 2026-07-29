#!/usr/bin/env node
/**
 * Erzeugt die Referenz-Tracks für den Replay-Test.
 *
 *   npx tsx src/replay/make-fixtures.ts
 *
 * Die Tracks werden gerechnet, nicht von Hand geschrieben: Nur so lässt sich
 * eine Kamera exakt 400 m voraus oder exakt 250 m seitlich platzieren, und
 * nur so ist nachvollziehbar, warum ein Test genau eine Warnung erwartet.
 *
 * Zu jedem .gpx entsteht ein .expect.json mit den Kameras und der erwarteten
 * Warnungszahl. Ein Track ohne Erwartung testet nichts.
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { writeGpx, type GpxPoint } from './gpx';
import type { Camera } from '../types';
import type { ReplayErwartung } from './replay';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, '..', '..', 'fixtures');

const EARTH_RADIUS_M = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;
const toDeg = (r: number) => (r * 180) / Math.PI;

/** Zielpunkt aus Startpunkt, Peilung und Distanz. */
function ziel(lat: number, lon: number, bearingDeg: number, distanceM: number): [number, number] {
  const d = distanceM / EARTH_RADIUS_M;
  const b = toRad(bearingDeg);
  const l1 = toRad(lat);
  const o1 = toRad(lon);

  const l2 = Math.asin(Math.sin(l1) * Math.cos(d) + Math.cos(l1) * Math.sin(d) * Math.cos(b));
  const o2 = o1 + Math.atan2(
    Math.sin(b) * Math.sin(d) * Math.cos(l1),
    Math.cos(d) - Math.sin(l1) * Math.sin(l2),
  );
  return [toDeg(l2), toDeg(o2)];
}

/**
 * Gerade Fahrt: Punkte im Abstand von speed * 1 s entlang einer Peilung.
 * Kurs und Geschwindigkeit werden mitgeschrieben, damit der Test nicht von
 * der Ableitung im Parser abhängt.
 */
function fahrt(
  startLat: number, startLon: number,
  bearingDeg: number, speedMs: number, sekunden: number,
  startzeit = Date.UTC(2026, 6, 29, 10, 0, 0),
): GpxPoint[] {
  const punkte: GpxPoint[] = [];
  for (let s = 0; s <= sekunden; s++) {
    const [lat, lon] = ziel(startLat, startLon, bearingDeg, speedMs * s);
    punkte.push({ lat, lon, t: startzeit + s * 1000, speed: speedMs, course: bearingDeg });
  }
  return punkte;
}

const kamera = (lat: number, lon: number, extra: Partial<Camera> = {}): Camera => ({
  lat: Math.round(lat * 1e5) / 1e5,
  lon: Math.round(lon * 1e5) / 1e5,
  dir: null, max: null, type: 'speed', ...extra,
});

type Fixture = { name: string; punkte: GpxPoint[]; erwartung: ReplayErwartung };

const fixtures: Fixture[] = [];

// Ausgangspunkt: irgendwo in Baden-Württemberg, weit weg von Zellgrenzen,
// damit der Test nicht versehentlich die Gitterlogik mitprüft.
const START_LAT = 48.7712;
const START_LON = 9.1834;

// 100 km/h = 27,8 m/s. Warndistanz damit max(300, 27.8*12) = 333 m.
const V = 27.8;

// --- 1. Kamera in Fahrtrichtung -------------------------------------------
{
  const punkte = fahrt(START_LAT, START_LON, 90, V, 30);
  // Kamera 600 m östlich des Starts: zu Beginn ausserhalb der Warndistanz
  // (333 m), wird nach rund 10 s erreicht. So prüft der Track auch, dass
  // nicht sofort beim ersten Punkt gewarnt wird.
  const [kLat, kLon] = ziel(START_LAT, START_LON, 90, 600);
  fixtures.push({
    name: 'kamera-in-fahrtrichtung',
    punkte,
    erwartung: {
      beschreibung: 'Fahrt nach Osten, Kamera 600 m voraus auf der Strecke, Tempo 80 getaggt',
      kameras: [kamera(kLat, kLon, { dir: 90, max: 80 })],
      erwarteteWarnungen: 1,
    },
  });
}

// --- 2. Kamera auf der Gegenfahrbahn --------------------------------------
{
  const punkte = fahrt(START_LAT, START_LON, 90, V, 30);
  // Dieselbe Position wie oben, aber die Kamera blickt nach Westen. Sie
  // überwacht damit den Gegenverkehr. Schritt (e) muss sie verwerfen.
  const [kLat, kLon] = ziel(START_LAT, START_LON, 90, 600);
  fixtures.push({
    name: 'kamera-gegenfahrbahn',
    punkte,
    erwartung: {
      beschreibung: 'Fahrt nach Osten, Kamera am Weg blickt nach Westen (dir 270) — Gegenverkehr',
      kameras: [kamera(kLat, kLon, { dir: 270, max: 80 })],
      erwarteteWarnungen: 0,
    },
  });
}

// --- 3. Kamera auf einer Parallelstrasse ----------------------------------
{
  const punkte = fahrt(START_LAT, START_LON, 90, V, 30);
  // 400 m voraus, aber 250 m nach Norden versetzt. Die Peilung zur Kamera
  // beträgt damit rund 32 Grad, der Kurs 90 — Differenz etwa 58 Grad und
  // damit über der Schwelle von 45. Ohne Richtungsangabe an der Kamera,
  // damit ausschliesslich der Peilungsfilter (Schritt d) greift.
  const [mitteLat, mitteLon] = ziel(START_LAT, START_LON, 90, 400);
  const [kLat, kLon] = ziel(mitteLat, mitteLon, 0, 250);
  fixtures.push({
    name: 'kamera-parallelstrasse',
    punkte,
    erwartung: {
      beschreibung: 'Fahrt nach Osten, Kamera 250 m seitlich auf einer Parallelstrasse, ohne Richtungsangabe',
      kameras: [kamera(kLat, kLon, { dir: null, max: 50 })],
      erwarteteWarnungen: 0,
    },
  });
}

// --- 4. Fahrt nach Norden (Winkel-Nulldurchgang) --------------------------
{
  // Dieser Track existiert wegen eines konkreten Bugs: Der naive Ausdruck
  // |Peilung - Kurs| rechnet bei Peilung 359 und Kurs 1 eine Differenz von
  // 358 statt 2 und verwirft die Kamera. Jede Warnung auf einer nach Norden
  // führenden Strasse würde lautlos ausfallen. Der Kurs liegt hier
  // absichtlich bei 359 Grad, also knapp unter dem Nulldurchgang.
  const punkte = fahrt(START_LAT, START_LON, 359, V, 30);
  const [kLat, kLon] = ziel(START_LAT, START_LON, 359, 600);
  fixtures.push({
    name: 'kamera-nordfahrt',
    punkte,
    erwartung: {
      beschreibung: 'Fahrt nach Norden mit Kurs 359 Grad, Kamera voraus — prüft den Winkel-Nulldurchgang',
      kameras: [kamera(kLat, kLon, { dir: 359, max: 100 })],
      erwarteteWarnungen: 1,
    },
  });
}

// --- 5. Stau an der Kamera ------------------------------------------------
{
  // Langsame Annäherung (3 m/s, also unter der Schwelle von 5 m/s), dann
  // Stillstand direkt an der Kamera. Bei unzuverlässigem Kurs ist der
  // Richtungsfilter aus und die Warndistanz auf 150 m verkürzt. Erwartet
  // wird genau eine Warnung — kein Dauerfeuer, solange man davorsteht.
  const punkte = fahrt(START_LAT, START_LON, 90, 3, 40);
  const letzter = punkte[punkte.length - 1]!;
  for (let s = 1; s <= 60; s++) {
    punkte.push({ ...letzter, t: letzter.t! + s * 1000, speed: 0, course: 90 });
  }
  const [kLat, kLon] = ziel(START_LAT, START_LON, 90, 130);
  fixtures.push({
    name: 'kamera-stau',
    punkte,
    erwartung: {
      beschreibung: 'Langsame Annäherung unter 5 m/s und 60 s Stillstand an der Kamera — kein Dauerfeuer',
      kameras: [kamera(kLat, kLon, { dir: 90, max: 30 })],
      erwarteteWarnungen: 1,
    },
  });
}

// --- schreiben ------------------------------------------------------------

mkdirSync(FIXTURES, { recursive: true });

for (const f of fixtures) {
  const gpx = writeGpx(f.punkte, f.erwartung.beschreibung);
  writeFileSync(join(FIXTURES, `${f.name}.gpx`), gpx);
  writeFileSync(
    join(FIXTURES, `${f.name}.expect.json`),
    JSON.stringify(f.erwartung, null, 2) + '\n',
  );
  console.log(
    `${f.name.padEnd(28)} ${String(f.punkte.length).padStart(4)} Punkte, ` +
    `${f.erwartung.kameras.length} Kamera(s), erwartet ${f.erwartung.erwarteteWarnungen} Warnung(en)`,
  );
}

console.log(`\n${fixtures.length} Fixtures in ${FIXTURES}`);
