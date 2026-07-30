/**
 * Geometrie-Tests. Die Funktionen hier tragen die gesamte Warnlogik —
 * ein Fehler wird nicht sichtbar, sondern führt zu ausbleibenden Warnungen.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  angleDiff,
  bearing,
  cellIndex,
  cellKey,
  distanceToSegment,
  haversine,
  keyFromIndex,
  neighbourhoodCoversRadius,
  neighbourKeys,
  normalizeBearing,
} from '../src/core/geo';

// --- angleDiff ------------------------------------------------------------
// Der wichtigste Test der Datei. Der naive Ausdruck |a - b| rechnet bei
// Peilung 350 und Kurs 10 eine Differenz von 340 statt 20 und verwirft die
// Kamera — jede Warnung an einer nach Norden führenden Strasse fällt
// lautlos aus.

test('angleDiff: Nulldurchgang', () => {
  assert.equal(angleDiff(350, 10), 20);
  assert.equal(angleDiff(10, 350), 20);
  assert.equal(angleDiff(0, 359), 1);
  assert.equal(angleDiff(359, 0), 1);
});

test('angleDiff: Randfälle', () => {
  assert.equal(angleDiff(180, 180), 0);
  assert.equal(angleDiff(90, 270), 180);
  assert.equal(angleDiff(0, 180), 180);
  assert.equal(angleDiff(0, 0), 0);
});

test('angleDiff: Wertebereich und Symmetrie über den ganzen Kreis', () => {
  for (let a = 0; a < 360; a += 7) {
    for (let b = 0; b < 360; b += 11) {
      const d = angleDiff(a, b);
      assert.ok(d >= 0 && d <= 180, `${a}/${b} ergibt ${d}`);
      assert.equal(d, angleDiff(b, a));
    }
  }
});

test('angleDiff: verträgt Winkel ausserhalb 0..360', () => {
  // GPS-Kurse und OSM-Tags kommen nicht normalisiert an.
  assert.equal(angleDiff(370, 10), 0);
  assert.equal(angleDiff(-10, 350), 0);
  assert.equal(angleDiff(720, 0), 0);
});

test('normalizeBearing', () => {
  assert.equal(normalizeBearing(0), 0);
  assert.equal(normalizeBearing(360), 0);
  assert.equal(normalizeBearing(370), 10);
  assert.equal(normalizeBearing(-90), 270);
});

// --- haversine ------------------------------------------------------------

test('haversine: nachgerechnete Referenzwerte', () => {
  // Bei r = 6371 km ist ein Breitengrad 6371000 * pi/180 = 111194,9 m.
  assert.ok(Math.abs(haversine(0, 0, 1, 0) - 111194.9) < 10);
  assert.ok(Math.abs(haversine(48.0, 9.0, 48.01, 9.0) - 1111.9) < 1);
  assert.equal(haversine(48, 9, 48, 9), 0);

  // Ein Längengrad schrumpft mit cos(Breite).
  const erwartet = 111194.9 * Math.cos((48 * Math.PI) / 180);
  assert.ok(Math.abs(haversine(48, 9, 48, 10) - erwartet) < 60);
});

test('haversine: symmetrisch', () => {
  assert.equal(haversine(48.77, 9.18, 48.9, 9.3), haversine(48.9, 9.3, 48.77, 9.18));
});

test('haversine: über Äquator und Nullmeridian', () => {
  assert.ok(Math.abs(haversine(-0.005, 9, 0.005, 9) - 1111.9) < 2);
  const ueberNull = haversine(48, -0.005, 48, 0.005);
  const daneben = haversine(48, 9.995, 48, 10.005);
  assert.ok(Math.abs(ueberNull - daneben) < 1);
});

// --- bearing --------------------------------------------------------------

test('bearing: die vier Himmelsrichtungen', () => {
  assert.ok(Math.abs(bearing(48, 9, 49, 9) - 0) < 0.1, 'Nord');
  assert.ok(Math.abs(bearing(48, 9, 48, 10) - 90) < 0.5, 'Ost');
  assert.ok(Math.abs(bearing(48, 9, 47, 9) - 180) < 0.1, 'Süd');
  assert.ok(Math.abs(bearing(48, 9, 48, 8) - 270) < 0.5, 'West');
});

test('bearing: Ergebnis immer in 0..360', () => {
  for (const [aLat, aLon, bLat, bLon] of [
    [48, 9, 48.1, 8.9], [48, 9, 47.9, 8.9], [0, 0, -1, -1], [48, 9, 48, 9.0001],
  ] as const) {
    const b = bearing(aLat, aLon, bLat, bLon);
    assert.ok(b >= 0 && b < 360, `${b} ausserhalb 0..360`);
  }
});

// --- Gitter ---------------------------------------------------------------

test('cellKey: Zellgrenzen ohne Float-Artefakte', () => {
  assert.equal(cellKey(48.775, 9.8123), '48.75,9.80');
  assert.equal(cellKey(48.75, 9.80), '48.75,9.80');
  // 48.80 / 0.05 ergibt in double 975.9999999999999 — ohne
  // Ganzzahlrechnung landet der Punkt eine Zelle zu weit unten.
  assert.equal(cellKey(48.80, 9.85), '48.80,9.85');
  assert.equal(cellKey(48.7999, 9.8499), '48.75,9.80');
});

test('cellKey: negative Koordinaten runden nach unten', () => {
  // Math.floor, nicht Math.trunc — mit trunc lägen -0,01 und +0,01 in
  // derselben Zelle.
  assert.equal(cellKey(0, 0), '0.00,0.00');
  assert.equal(cellKey(-0.01, -0.01), '-0.05,-0.05');
  assert.notEqual(cellKey(0.01, 0.01), cellKey(-0.01, -0.01));
});

test('cellKey stimmt mit cellIndex und keyFromIndex überein', () => {
  for (const [lat, lon] of [[48.77, 9.18], [-33.9, 151.2], [0, 0], [55.0, -3.5]] as const) {
    const [i, j] = cellIndex(lat, lon);
    assert.equal(keyFromIndex(i, j), cellKey(lat, lon));
  }
});

test('cellKey: jede Zellgrenze über Deutschland ist stabil', () => {
  for (let u = 47_00_000; u <= 55_00_000; u += 5000) {
    const grenze = u / 1e5;
    assert.equal(cellKey(grenze, 9.8), `${grenze.toFixed(2)},9.80`);
  }
});

test('neighbourKeys: neun eindeutige Zellen inklusive der eigenen', () => {
  const keys = neighbourKeys(48.77, 9.82);
  assert.equal(keys.length, 9);
  assert.equal(new Set(keys).size, 9);
  assert.ok(keys.includes(cellKey(48.77, 9.82)));
  assert.ok(keys.includes('48.70,9.75'));
  assert.ok(keys.includes('48.80,9.85'));
});

test('neighbourKeys: findet eine Kamera hinter der Zellgrenze', () => {
  // Fahrer knapp vor der Grenze, Kamera knapp dahinter — ohne die
  // Nachbarschaft würde sie übersehen.
  const kameraZelle = cellKey(48.80001, 9.85001);
  assert.ok(neighbourKeys(48.79995, 9.84995).includes(kameraZelle));
});

test('neighbourhoodCoversRadius: die Annahme wird geprüft, nicht geglaubt', () => {
  // Eine Zelle ist bei 48 Grad rund 3,7 km breit. Warndistanzen bis etwa
  // 530 m (160 km/h) sind damit sicher gedeckt.
  assert.ok(neighbourhoodCoversRadius(48, 533), 'Warndistanz bei 160 km/h');
  assert.ok(neighbourhoodCoversRadius(48, 1000));
  assert.equal(neighbourhoodCoversRadius(48, 5000), false, 'zu grosser Radius muss auffallen');
});

// --- distanceToSegment ----------------------------------------------------

test('distanceToSegment: Punkt neben der Mitte', () => {
  // Segment von (48,9) nach (48,9.01), Punkt 0,001 Grad nördlich der Mitte.
  // 0,001 Grad Breite sind rund 111 m.
  const d = distanceToSegment(48.001, 9.005, 48, 9, 48, 9.01);
  assert.ok(Math.abs(d - 111) < 3, `${d.toFixed(1)} m statt ~111 m`);
});

test('distanceToSegment: Punkt auf dem Segment', () => {
  assert.ok(distanceToSegment(48, 9.005, 48, 9, 48, 9.01) < 1);
});

test('distanceToSegment: hinter dem Segmentende wird zum Endpunkt gemessen', () => {
  // Der entscheidende Fall: Ohne Begrenzung der Projektion auf [0,1] würde
  // hier der Abstand zur VERLÄNGERTEN Geraden gemessen, also fast null —
  // und das Map-Matching würde eine Strasse wählen, die längst zu Ende ist.
  const d = distanceToSegment(48, 9.02, 48, 9, 48, 9.01);
  const zumEndpunkt = haversine(48, 9.02, 48, 9.01);
  assert.ok(Math.abs(d - zumEndpunkt) < 1, `${d.toFixed(1)} statt ${zumEndpunkt.toFixed(1)}`);
});

test('distanceToSegment: entartetes Segment (Start = Ende)', () => {
  const d = distanceToSegment(48.001, 9, 48, 9, 48, 9);
  assert.ok(Math.abs(d - 111) < 3);
});
