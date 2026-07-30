/**
 * Der Phase-3-DoD als Test.
 *
 * Jeder Referenz-Track wird abgespielt und gegen seine Erwartung geprüft.
 * Läuft ohne Gerät, ohne Netz, in CI.
 *
 * Wenn ein Fehlalarm gemeldet wird: neuen Track in fixtures/ ablegen, hier
 * wird er automatisch mitgeprüft — BEVOR der Fehler gefixt wird.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { alleFixtures, ladeFixture, replay } from '../src/replay/replay';

const fixtures = alleFixtures();

test('es gibt überhaupt Referenz-Tracks', () => {
  assert.ok(
    fixtures.length >= 5,
    `nur ${fixtures.length} Tracks gefunden — make-fixtures.ts ausführen`,
  );
});

for (const name of fixtures) {
  test(`Replay: ${name}`, () => {
    const { fixes, erwartung } = ladeFixture(name);
    assert.ok(fixes.length > 0, 'Track ist leer');

    const erg = replay(fixes, erwartung.kameras, erwartung.settings);

    assert.equal(
      erg.warnungen.length,
      erwartung.erwarteteWarnungen,
      `${erwartung.beschreibung}\n` +
      `  erwartet ${erwartung.erwarteteWarnungen}, ausgelöst ${erg.warnungen.length}\n` +
      `  Verwerfungsgründe: ${JSON.stringify(erg.gruende)}`,
    );
  });
}

test('Warnung kommt nicht erst kurz vor der Kamera', () => {
  // Eine Warnung 50 m vorher ist wertlos. Bei 100 km/h liegt die
  // Warndistanz bei 334 m; der erste Punkt innerhalb dieser Distanz muss
  // auslösen, nicht ein späterer.
  const { fixes, erwartung } = ladeFixture('kamera-in-fahrtrichtung');
  const erg = replay(fixes, erwartung.kameras, erwartung.settings);

  assert.equal(erg.warnungen.length, 1);
  const w = erg.warnungen[0]!;
  assert.ok(
    w.distance > 280,
    `Warnung erst bei ${w.distance.toFixed(0)} m — zu spät`,
  );
});

test('Stillstand an der Kamera erzeugt kein Dauerfeuer', () => {
  const { fixes, erwartung } = ladeFixture('kamera-stau');
  const erg = replay(fixes, erwartung.kameras, erwartung.settings);
  assert.equal(erg.warnungen.length, 1, 'genau eine Warnung, egal wie lange man steht');
});

test('die Gegenfahrbahn wird über die Kamerarichtung verworfen, nicht zufällig', () => {
  // Der Test wäre wertlos, wenn die Kamera aus einem anderen Grund
  // (zu weit, nicht voraus) durchfiele — dann würde er auch bei kaputtem
  // Richtungsfilter grün sein.
  const { fixes, erwartung } = ladeFixture('kamera-gegenfahrbahn');
  const erg = replay(fixes, erwartung.kameras, erwartung.settings);

  assert.equal(erg.warnungen.length, 0);
  assert.ok(
    (erg.gruende['gegenrichtung'] ?? 0) > 0,
    'Kamera wurde nie wegen Gegenrichtung verworfen — der Filter greift nicht',
  );
});

test('die Parallelstrasse wird über die Peilung verworfen', () => {
  const { fixes, erwartung } = ladeFixture('kamera-parallelstrasse');
  const erg = replay(fixes, erwartung.kameras, erwartung.settings);

  assert.equal(erg.warnungen.length, 0);
  assert.ok(
    (erg.gruende['nicht_voraus'] ?? 0) > 0,
    'Kamera wurde nie wegen Peilung verworfen — Schritt d greift nicht',
  );
});
