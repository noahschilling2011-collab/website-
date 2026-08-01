/**
 * Die Umgebungskarte.
 *
 * Was hier prüfbar ist: die Rechnung. Ob Norden oben liegt, ob der Massstab
 * stimmt, ob nichts stillschweigend abgeschnitten wird.
 *
 * Was hier NICHT prüfbar ist: ob die Karte etwas nützt. Eine Karte ohne
 * Strassen zeigt Punkte im Verhältnis zueinander und sonst nichts — ob das
 * jemandem hilft, zeigt sich am Gerät und nicht in einem Test.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { KARTE } from '../src/config';
import { baueKarte, massstab, projiziere, ringe } from '../src/core/karte';
import { camerasInRadius, camerasWithinRadius } from '../src/core/dataset';
import type { Camera } from '../src/types';

/** Eine Anlage an einer Stelle. Nur Position und Typ zählen für die Karte. */
function anlage(lat: number, lon: number): Camera {
  return { lat, lon, dir: null, max: null, type: 'speed' };
}

const MITTE_LAT = 48.6;
const MITTE_LON = 9.1;
const GROESSE = 300;

// --- Die Projektion -------------------------------------------------------

test('der Mittelpunkt liegt in der Bildmitte', () => {
  const p = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT, MITTE_LON, GROESSE, 1000);
  assert.equal(p.x, GROESSE / 2);
  assert.equal(p.y, GROESSE / 2);
});

test('Norden liegt oben, Osten rechts', () => {
  // Die eine Sache, die man bei einer Projektion falsch macht: das
  // Vorzeichen der Y-Achse. Bildkoordinaten wachsen nach unten, geografische
  // Breite nach oben.
  const nord = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT + 0.01, MITTE_LON, GROESSE, 5000);
  const sued = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT - 0.01, MITTE_LON, GROESSE, 5000);
  const ost = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT, MITTE_LON + 0.01, GROESSE, 5000);
  const west = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT, MITTE_LON - 0.01, GROESSE, 5000);

  assert.ok(nord.y < GROESSE / 2, 'Norden liegt nicht oben');
  assert.ok(sued.y > GROESSE / 2, 'Süden liegt nicht unten');
  assert.ok(ost.x > GROESSE / 2, 'Osten liegt nicht rechts');
  assert.ok(west.x < GROESSE / 2, 'Westen liegt nicht links');
});

test('ein Grad Länge ist bei 48 Grad Breite kürzer als ein Grad Breite', () => {
  // Die cos(Breite)-Stauchung. Ohne sie wäre die Karte in Ost-West-Richtung
  // um ein Drittel zu breit — Mitteleuropa liegt bei cos(48°) = 0,669.
  const nord = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT + 1, MITTE_LON, GROESSE, 200_000);
  const ost = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT, MITTE_LON + 1, GROESSE, 200_000);

  const nordDp = GROESSE / 2 - nord.y;
  const ostDp = ost.x - GROESSE / 2;
  const verhaeltnis = ostDp / nordDp;
  const erwartet = Math.cos((MITTE_LAT * Math.PI) / 180);

  assert.ok(
    Math.abs(verhaeltnis - erwartet) < 0.001,
    `Verhältnis ${verhaeltnis.toFixed(4)}, erwartet ${erwartet.toFixed(4)}`,
  );
});

test('der Massstab bringt den Radius genau an den Bildrand', () => {
  const radius = 2000;
  const s = massstab(GROESSE, radius);
  assert.equal(radius * s, GROESSE / 2);

  // Eine Anlage genau im Norden auf Radiusentfernung landet am oberen Rand.
  const gradNord = radius / 111_320;
  const p = projiziere(MITTE_LAT, MITTE_LON, MITTE_LAT + gradNord, MITTE_LON, GROESSE, radius);
  assert.ok(Math.abs(p.y) < 0.5, `y = ${p.y}, erwartet ~0 (oberer Rand)`);
});

// --- Die Ringe ------------------------------------------------------------

test('der äusserste Ring ist der Radius selbst', () => {
  // Sonst hat der Bildrand keine Bedeutung, und die Karte suggeriert einen
  // Ausschnitt, den sie nicht hat.
  const r = ringe(3000);
  assert.equal(r.length, KARTE.RINGE);
  assert.equal(r[r.length - 1], 3000);
  assert.deepEqual(r, [1000, 2000, 3000]);
});

// --- Die Auswahl ----------------------------------------------------------

test('was ausserhalb des Radius liegt, wird nicht gezeichnet', () => {
  const drin = anlage(MITTE_LAT + 0.005, MITTE_LON);        // rund 557 m
  const draussen = anlage(MITTE_LAT + 0.05, MITTE_LON);     // rund 5566 m
  const k = baueKarte(MITTE_LAT, MITTE_LON, [drin, draussen], GROESSE, 1000);

  assert.equal(k.punkte.length, 1);
  assert.equal(k.punkte[0]!.camera, drin);
});

test('die Punkte sind nach Entfernung sortiert', () => {
  // Damit die Obergrenze die NÄCHSTEN Anlagen behält und nicht die, die im
  // Gitter zufällig zuerst standen.
  const cams = [
    anlage(MITTE_LAT + 0.008, MITTE_LON),
    anlage(MITTE_LAT + 0.001, MITTE_LON),
    anlage(MITTE_LAT + 0.004, MITTE_LON),
  ];
  const k = baueKarte(MITTE_LAT, MITTE_LON, cams, GROESSE, 5000);
  const distanzen = k.punkte.map((p) => p.distanzM);
  assert.deepEqual(distanzen, [...distanzen].sort((a, b) => a - b));
});

test('zu viele Anlagen werden gemeldet, nicht verschwiegen', () => {
  // Der Fehler, den eine Karte nicht machen darf: unvollständig aussehen wie
  // vollständig. Wer 500 Anlagen im Radius hat und 400 sieht, muss das
  // erfahren.
  const cams: Camera[] = [];
  for (let i = 0; i < KARTE.MAX_PUNKTE + 37; i++) {
    cams.push(anlage(MITTE_LAT + i * 0.00002, MITTE_LON));
  }
  const k = baueKarte(MITTE_LAT, MITTE_LON, cams, GROESSE, 5000);

  assert.equal(k.punkte.length, KARTE.MAX_PUNKTE);
  assert.equal(k.nichtGezeichnet, 37);
});

test('ohne Position eine leere Karte statt eines Fehlers', () => {
  // Der Zustand beim Start, bevor der erste Fix da ist. Ein Absturz wäre
  // hier die schlechteste Antwort.
  for (const [lat, lon] of [[NaN, 9], [48, NaN], [Infinity, 9]]) {
    const k = baueKarte(lat!, lon!, [anlage(48.6, 9.1)], GROESSE, 1000);
    assert.equal(k.punkte.length, 0);
    assert.deepEqual(k.ringeM, [], 'ohne Bezug darf kein Massstab behauptet werden');
  }
});

test('unsinnige Bildgrösse oder Radius liefern eine leere Karte', () => {
  for (const [g, r] of [[0, 1000], [-10, 1000], [300, 0], [300, -5], [300, NaN]]) {
    const k = baueKarte(MITTE_LAT, MITTE_LON, [anlage(48.6, 9.1)], g!, r!);
    assert.equal(k.punkte.length, 0, `groesse=${g} radius=${r}`);
  }
});

test('eine Anlage ohne gültige Koordinaten wird übersprungen', () => {
  const kaputt = { lat: NaN, lon: 9.1, dir: null, max: null, type: 'speed' } as Camera;
  const k = baueKarte(MITTE_LAT, MITTE_LON, [kaputt, anlage(MITTE_LAT, MITTE_LON)], GROESSE, 1000);
  assert.equal(k.punkte.length, 1);
});

// --- Der Zugriff auf den Datensatz ----------------------------------------

test('camerasInRadius und camerasWithinRadius sind dieselbe Auswahl', () => {
  // Vorher liefen zwei fast gleiche Schleifen nebeneinander. Jetzt ist die
  // Zählung die Länge der Liste — und dieser Test hält das so.
  const grid = {
    '48.60,9.10': [anlage(48.601, 9.101), anlage(48.605, 9.105)],
    '48.65,9.10': [anlage(48.66, 9.10)],
  };
  for (const radius of [100, 1000, 10_000]) {
    const liste = camerasInRadius({ grid }, 48.6, 9.1, radius);
    const zahl = camerasWithinRadius({ grid }, 48.6, 9.1, radius);
    assert.equal(liste!.length, zahl, `Radius ${radius}`);
  }
});

test('ungültige Eingaben liefern null, nicht eine leere Liste', () => {
  // Der Unterschied ist die Aussage: [] heisst "hier ist nichts erfasst",
  // null heisst "dazu lässt sich nichts sagen". Das eine ist eine Angabe
  // über die Datenlage, das andere das Eingeständnis, keine zu haben.
  const grid = { '48.60,9.10': [anlage(48.601, 9.101)] };
  assert.equal(camerasInRadius({ grid }, NaN, 9.1, 1000), null);
  assert.equal(camerasInRadius({ grid }, 48.6, 9.1, 0), null);
  assert.deepEqual(camerasInRadius({ grid }, 0, 0, 1000), []);
});

// --- Die Konfiguration ----------------------------------------------------

test('die Radien sind aufsteigend und der Startwert steht in der Liste', () => {
  const r = [...KARTE.RADIEN_M];
  assert.deepEqual(r, [...r].sort((a, b) => a - b));
  assert.ok(
    r.includes(KARTE.START_RADIUS_M),
    'der Startradius ist nicht wählbar — dann steht die Karte auf einer Stufe, die es nicht gibt',
  );
});
