/**
 * Zonenmodus: Erzeugung und Laufzeitverhalten.
 *
 * Der wichtigste Test ist der Rekonstruktionstest aus C.1: Aus der Zonendatei
 * darf sich die Kameraposition nicht ableiten lassen. Ohne den wäre der Radius
 * Dekoration.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import {
  createZonenZustand, pruefeZonen, zonenDatensatzPruefen, type Zone,
} from '../src/core/zone';

const DATA_DIR = join(import.meta.dirname, '..', '..', 'assets', 'data');

/**
 * Alle vorhandenen Zonendateien.
 *
 * Der Generator ist länderunabhängig; geprüft wird sein AUSGABEFORMAT, und das
 * gilt für jedes Land. Frankreich ist das Land, das den Zonenmodus braucht,
 * aber die Zusage "verrät keine Kameraposition" muss für jede erzeugte Datei
 * halten — sonst hängt sie am Zufall, welches Land gerade gebaut wurde.
 */
function zonenDateien(): string[] {
  if (!existsSync(DATA_DIR)) return [];
  return readdirSync(DATA_DIR)
    .filter((f) => /^cameras\.[A-Z]{2}\.zones\.json$/.test(f))
    .map((f) => join(DATA_DIR, f));
}

/** Punkt in Richtung Osten verschieben, in Metern. */
function ostwaerts(lat: number, lon: number, meter: number): [number, number] {
  const lonPerM = 1 / (111_320 * Math.cos((lat * Math.PI) / 180));
  return [lat, lon + meter * lonPerM];
}

// --- Laufzeitverhalten ----------------------------------------------------

const zone = (lat: number, lon: number, r: number): Zone => ({ lat, lon, r });

test('Eintritt in eine Zone wird genau einmal gemeldet', () => {
  const zonen = [zone(48.0, 9.0, 2000)];
  const zustand = createZonenZustand();

  // Weit draussen
  const [lat1, lon1] = ostwaerts(48.0, 9.0, 5000);
  assert.equal(pruefeZonen(lat1, lon1, zonen, zustand).betreten, null);

  // Hineinfahren
  const [lat2, lon2] = ostwaerts(48.0, 9.0, 1500);
  assert.notEqual(pruefeZonen(lat2, lon2, zonen, zustand).betreten, null, 'Eintritt');

  // Weiter drin — keine zweite Ansage, kein Countdown
  for (const d of [1000, 500, 0, -500, -1000]) {
    const [la, lo] = ostwaerts(48.0, 9.0, d);
    assert.equal(
      pruefeZonen(la, lo, zonen, zustand).betreten, null,
      `zweite Ansage bei ${d} m`,
    );
  }
});

test('nach dem Verlassen wird ein erneuter Eintritt wieder gemeldet', () => {
  // Sonst bliebe eine Zone auf einer Rundfahrt beim zweiten Mal stumm.
  const zonen = [zone(48.0, 9.0, 1000)];
  const zustand = createZonenZustand();

  assert.notEqual(pruefeZonen(48.0, 9.0, zonen, zustand).betreten, null);
  const [raus, rausLon] = ostwaerts(48.0, 9.0, 3000);
  assert.equal(pruefeZonen(raus, rausLon, zonen, zustand).betreten, null);
  assert.notEqual(
    pruefeZonen(48.0, 9.0, zonen, zustand).betreten, null,
    'zweiter Eintritt muss ansagen',
  );
});

test('zwei überlappende Zonen ergeben nur eine Ansage', () => {
  // Kommt vor, wenn der Generator nicht alles zusammengefasst hat.
  const [lat2, lon2] = ostwaerts(48.0, 9.0, 500);
  const zonen = [zone(48.0, 9.0, 1000), zone(lat2, lon2, 1000)];
  const zustand = createZonenZustand();

  const erg = pruefeZonen(48.0, 9.0, zonen, zustand);
  assert.notEqual(erg.betreten, null);
  assert.equal(erg.aktiveZonen, 2, 'beide umschliessen die Position');

  // Der zweite Aufruf darf nichts mehr melden, obwohl zwei Zonen aktiv sind.
  assert.equal(pruefeZonen(48.0, 9.0, zonen, zustand).betreten, null);
});

test('das Ergebnis enthält keine Entfernung', () => {
  // Die Regelung erlaubt einen Bereich, keinen Punkt. Was die Funktion nicht
  // zurückgibt, kann die UI nicht anzeigen.
  const erg = pruefeZonen(48.0, 9.0, [zone(48.0, 9.0, 1000)], createZonenZustand());
  assert.deepEqual(Object.keys(erg).sort(), ['aktiveZonen', 'betreten']);
  const felder = Object.keys(erg.betreten ?? {}).sort();
  assert.deepEqual(felder, ['lat', 'lon', 'r'], `Zone hat Zusatzfelder: ${felder.join(', ')}`);
});

test('Richtung spielt keine Rolle', () => {
  // Eine Zone ist rundum. Aus jeder Himmelsrichtung derselbe Eintritt.
  const richtungen: [number, number][] = [[0.005, 0], [-0.005, 0], [0, 0.008], [0, -0.008]];
  for (const [dLat, dLon] of richtungen) {
    const zustand = createZonenZustand();
    const erg = pruefeZonen(48.0 + dLat, 9.0 + dLon, [zone(48.0, 9.0, 1000)], zustand);
    assert.notEqual(erg.betreten, null, `Richtung ${dLat},${dLon}`);
  }
});

// --- Prüfung der Zonendatei ----------------------------------------------

test('zonenDatensatzPruefen weist eine zu kleine Zone ab', () => {
  // Unter 150 m Radius kann nur ein Generatorfehler sein — und eine zu kurze
  // Zone ist der rechtlich problematische Fall.
  assert.throws(
    () => zonenDatensatzPruefen({ version: 1, count: 1, zones: [{ lat: 48, lon: 9, r: 100 }] }),
    /Mindestlänge/,
  );
});

test('zonenDatensatzPruefen weist eine falsche Anzahl ab', () => {
  assert.throws(
    () => zonenDatensatzPruefen({ version: 1, count: 5, zones: [{ lat: 48, lon: 9, r: 200 }] }),
    /count/,
  );
});

test('zonenDatensatzPruefen weist eine unbekannte Version ab', () => {
  assert.throws(() => zonenDatensatzPruefen({ version: 2, count: 0, zones: [] }), /Version/);
});

// --- DER REKONSTRUKTIONSTEST (C.1) ---------------------------------------

test('die Zonendatei verrät keine Kameraposition', () => {
  const dateien = zonenDateien();
  // Kein stilles Bestehen: Ohne Datei ist die Zusage ungeprüft.
  assert.ok(
    dateien.length > 0,
    'keine Zonendatei gefunden. Erzeugen mit: npx tsx scripts/build-zones.ts DE',
  );

  for (const datei of dateien) {
  const roh = readFileSync(datei, 'utf8');
  const daten = zonenDatensatzPruefen(JSON.parse(roh));

  // Felder, die eine Rekonstruktion erlauben würden. Die Suche läuft über den
  // ROHTEXT und nicht über das geparste Objekt: So fällt auch ein Feld auf,
  // das der Typ nicht kennt.
  const verraeterisch = [
    'anzahl', 'count_cameras', 'kameras', 'cameras', 'n_cameras',
    'maxspeed', '"max"', '"dir"', '"type"', 'typ', 'speed',
  ];
  for (const feld of verraeterisch) {
    assert.ok(
      !roh.includes(feld),
      `Zonendatei enthält "${feld}" — daraus liesse sich die Anlage ableiten`,
    );
  }

  // Jede Zone hat genau drei Felder.
  for (const z of daten.zones) {
    assert.deepEqual(
      Object.keys(z).sort(), ['lat', 'lon', 'r'],
      `Zone mit Zusatzfeldern: ${JSON.stringify(z)}`,
    );
  }
  }
});

test('kein Zonenradius ist zu klein oder absurd gross', () => {
  for (const datei of zonenDateien()) {
  const daten = zonenDatensatzPruefen(JSON.parse(readFileSync(datei, 'utf8')));

  // 150 m innerorts, 1000 m Landstrasse, 2000 m Autobahn. Zusammengefasste
  // Zonen sind grösser — kleiner darf keine sein.
  for (const z of daten.zones) {
    assert.ok(z.r >= 150, `Radius ${z.r} m unter 150 m`);
  }
  // Und mindestens eine Zone muss zusammengefasst sein, sonst hat der
  // Generator nichts getan.
  const grundradien = new Set([150, 1000, 2000]);
  const zusammengefasst = daten.zones.filter((z) => !grundradien.has(z.r));
  assert.ok(
    zusammengefasst.length > 0,
    'keine einzige Zone zusammengefasst — das ist bei tausenden Anlagen unplausibel',
  );

  // Obergrenze: Ohne sie kaskadiert das Zusammenfassen. Gemessen an
  // Deutschland entstand vor der Grenze eine Zone mit 85 km Radius — als
  // Hinweis wertlos, und von der Regelung nicht gedeckt.
  const groesster = Math.max(...daten.zones.map((z) => z.r));
  assert.ok(groesster <= 6000, `grösste Zone ${groesster} m — Kaskade nicht begrenzt`);
  }
});
