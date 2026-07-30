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

import { haversine } from '../src/core/geo';

import { alleFixtures, ladeFixture, replay, replayZonen } from '../src/replay/replay';

const fixtures = alleFixtures();

test('es gibt überhaupt Referenz-Tracks', () => {
  assert.ok(
    fixtures.length >= 8,
    `nur ${fixtures.length} Tracks gefunden — make-fixtures.ts ausführen`,
  );
});

for (const name of fixtures) {
  test(`Replay: ${name}`, () => {
    const { fixes, erwartung } = ladeFixture(name);
    assert.ok(fixes.length > 0, 'Track ist leer');

    // Zonen-Tracks laufen durch pruefeZonen(), nicht durch evaluate(). Ein
    // Land hat genau einen Modus; beides zu mischen prüfte keinen von beiden.
    if (erwartung.zonen) {
      const zErg = replayZonen(fixes, erwartung.zonen);
      assert.equal(
        zErg.ansagen, erwartung.erwarteteWarnungen,
        `${erwartung.beschreibung}\n  erwartet ${erwartung.erwarteteWarnungen} Ansagen, ` +
        `ausgelöst ${zErg.ansagen}`,
      );
      return;
    }

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

// --- Zonenmodus, Phase C.4 -----------------------------------------------

test('fr-zone-autobahn: Eintritt mindestens 1800 m vor der Anlage', () => {
  // Die Zone hat 2000 m Radius, die Anlage sitzt 3000 m nach dem Start. Der
  // Eintritt muss also spätestens bei 1000 m Fahrstrecke liegen — dann sind
  // es noch 2000 m bis zur Anlage. Bei 36,1 m/s ist das Punkt 28.
  const { fixes, erwartung } = ladeFixture('fr-zone-autobahn');
  const erg = replayZonen(fixes, erwartung.zonen!);

  assert.equal(erg.ansagen, 1);
  assert.notEqual(erg.ersterEintrittIndex, null);

  const zone = erwartung.zonen![0]!;
  const eintritt = fixes[erg.ersterEintrittIndex!]!;
  const abstandZurAnlage = haversine(eintritt.lat, eintritt.lon, zone.lat, zone.lon);
  assert.ok(
    abstandZurAnlage >= 1800,
    `Eintritt erst ${abstandZurAnlage.toFixed(0)} m vor der Anlage, erwartet mindestens 1800 m`,
  );
});

test('fr-zone-innerorts: Eintritt mindestens 130 m vor der Anlage', () => {
  const { fixes, erwartung } = ladeFixture('fr-zone-innerorts');
  const erg = replayZonen(fixes, erwartung.zonen!);

  assert.equal(erg.ansagen, 1);
  const zone = erwartung.zonen![0]!;
  const eintritt = fixes[erg.ersterEintrittIndex!]!;
  const abstand = haversine(eintritt.lat, eintritt.lon, zone.lat, zone.lon);
  assert.ok(abstand >= 130, `Eintritt erst ${abstand.toFixed(0)} m vorher`);
});

test('fr-zwei-kameras-eine-zone: genau eine Ansage für zwei Anlagen', () => {
  // Der Fall, den die Regelung ausdrücklich zulässt: Zwei dicht
  // aufeinanderfolgende Zonen werden zu einer zusammengefasst. Zwei Ansagen
  // wären zwei Hinweise auf einen Bereich.
  const { fixes, erwartung } = ladeFixture('fr-zwei-kameras-eine-zone');
  assert.equal(replayZonen(fixes, erwartung.zonen!).ansagen, 1);
});

test('kein Zonen-Track löst eine Punktwarnung aus', () => {
  // Gegenprobe: Die Zonen-Tracks enthalten absichtlich KEINE Kameras. Liefe
  // einer davon versehentlich durch evaluate(), käme null heraus — und der
  // Test oben wäre wertlos, weil er dann immer bestehen würde.
  for (const name of fixtures) {
    const { fixes, erwartung } = ladeFixture(name);
    if (!erwartung.zonen) continue;
    assert.equal(erwartung.kameras.length, 0, `${name} hat Kameras UND Zonen`);
    assert.equal(
      replay(fixes, erwartung.kameras).warnungen.length, 0,
      `${name} löst eine Punktwarnung aus`,
    );
  }
});
