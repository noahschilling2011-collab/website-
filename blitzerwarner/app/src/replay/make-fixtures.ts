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

// --- Zonen-Tracks (Phase C.4, Frankreich) --------------------------------
//
// Die Zonen werden hier so gerechnet, wie build-zones.ts sie erzeugen würde:
// Radius = halbe Mindestlänge. Bewusst NICHT aus dem echten FR-Datensatz —
// ein Test, dessen Erwartung von fremden Daten abhängt, ändert sein Ergebnis,
// wenn OSM sich ändert.

// Irgendwo in Frankreich, weit weg von Zellgrenzen.
const FR_LAT = 48.5734;
const FR_LON = 7.7521;

// --- 6. Autobahnzone ------------------------------------------------------
{
  // 130 km/h = 36,1 m/s. Autobahn: Mindestlänge 4000 m, Radius 2000 m.
  // Die Kamera sitzt 3000 m voraus; die Zone beginnt damit 1000 m nach dem
  // Start und der Eintritt liegt 2000 m vor der Anlage.
  const V_AUTOBAHN = 36.1;
  const punkte = fahrt(FR_LAT, FR_LON, 90, V_AUTOBAHN, 110);
  const [kLat, kLon] = ziel(FR_LAT, FR_LON, 90, 3000);
  fixtures.push({
    name: 'fr-zone-autobahn',
    punkte,
    erwartung: {
      beschreibung:
        'Frankreich, Autobahn: eine Zone mit 2000 m Radius um eine Anlage 3000 m ' +
        'voraus. Erwartet genau eine Ansage, Eintritt mindestens 1800 m vor der Anlage.',
      kameras: [],
      zonen: [{ lat: Math.round(kLat * 1e5) / 1e5, lon: Math.round(kLon * 1e5) / 1e5, r: 2000 }],
      erwarteteWarnungen: 1,
    },
  });
}

// --- 7. Innerortszone -----------------------------------------------------
{
  // 50 km/h = 13,9 m/s. Innerorts: Mindestlänge 300 m, Radius 150 m.
  const V_STADT = 13.9;
  const punkte = fahrt(FR_LAT, FR_LON, 90, V_STADT, 60);
  const [kLat, kLon] = ziel(FR_LAT, FR_LON, 90, 500);
  fixtures.push({
    name: 'fr-zone-innerorts',
    punkte,
    erwartung: {
      beschreibung:
        'Frankreich, innerorts: eine Zone mit 150 m Radius um eine Anlage 500 m ' +
        'voraus. Erwartet genau eine Ansage, Eintritt mindestens 130 m vor der Anlage.',
      kameras: [],
      zonen: [{ lat: Math.round(kLat * 1e5) / 1e5, lon: Math.round(kLon * 1e5) / 1e5, r: 150 }],
      erwarteteWarnungen: 1,
    },
  });
}

// --- 8. Zwei Anlagen, eine Zone -------------------------------------------
{
  // Zwei Anlagen 600 m auseinander auf einer Landstrasse. Einzeln hätte jede
  // 1000 m Radius; die Zonen überlappen deutlich und werden von build-zones.ts
  // zu einer zusammengefasst. Erwartet wird EINE Ansage für beide — das ist
  // der Fall, den die Regelung ausdrücklich zulässt.
  const V_LAND = 25;
  const punkte = fahrt(FR_LAT, FR_LON, 90, V_LAND, 120);
  const [a1, o1] = ziel(FR_LAT, FR_LON, 90, 2000);
  const [a2, o2] = ziel(FR_LAT, FR_LON, 90, 2600);
  // Zusammengefasst: Mittelpunkt zwischen beiden, Radius deckt beide ab.
  const [mLat, mLon] = ziel(FR_LAT, FR_LON, 90, 2300);
  fixtures.push({
    name: 'fr-zwei-kameras-eine-zone',
    punkte,
    erwartung: {
      beschreibung:
        'Frankreich, Landstrasse: zwei Anlagen 600 m auseinander, deren Zonen zu ' +
        'einer zusammengefasst sind. Erwartet genau EINE Ansage für beide.',
      kameras: [],
      zonen: [{
        lat: Math.round(mLat * 1e5) / 1e5,
        lon: Math.round(mLon * 1e5) / 1e5,
        r: 1300,
      }],
      erwarteteWarnungen: 1,
    },
  });
  // Die beiden Einzelpositionen stehen nur im Kommentar, nicht in der
  // Erwartungsdatei — dieselbe Regel wie bei der Zonendatei selbst.
  void a1; void o1; void a2; void o2;
}

// --- 9. Grenzfahrt Kehl nach Strasbourg (B.4) -----------------------------
{
  // Über die Europabrücke, Deutschland nach Frankreich. Der Track prüft nicht
  // die Warnlogik, sondern die LANDESERKENNUNG samt Hysterese — deshalb keine
  // Kameras und keine Zonen in der Erwartung.
  //
  // Die Fahrt beginnt gut 2 km östlich des Rheins in Kehl und endet 3 km
  // westlich in Strasbourg. 50 km/h, 1 s Abstand, also rund 14 m je Punkt —
  // fein genug, um den Umschaltpunkt auf wenige Meter zu bestimmen.
  const KEHL_LAT = 48.5745;
  const KEHL_LON = 7.8150;
  const punkte = fahrt(KEHL_LAT, KEHL_LON, 270, 13.9, 380);
  fixtures.push({
    name: 'grenze-kehl-strasbourg',
    punkte,
    erwartung: {
      beschreibung:
        'Fahrt über die Europabrücke, Deutschland nach Frankreich. Prüft die ' +
        'Landeserkennung: genau ein Moduswechsel, kein Flattern, und der ' +
        'Wechsel liegt NACH der Grenze, nicht davor.',
      kameras: [],
      erwarteteWarnungen: 0,
      // Ohne dieses Feld schickt die CLI den Track durch die Punktlogik,
      // findet dort null Kameras und meldet "0 von 0 erwartet, OK" — ein
      // grünes Ergebnis für eine Prüfung, die nicht gelaufen ist.
      landwechsel: {
        // Deutschland ist 'aus', Frankreich 'zone'. Genau ein Wechsel.
        modi: ['zone'],
        // Aus der Spec: der Wechsel liegt zwischen 0 und 500 m hinter der
        // Grenze. Gemessen werden 389 m.
        maxHinterGrenzeM: 500,
      },
    },
  });
}

// --- 10./11. Zwei Anlagen hintereinander ----------------------------------
{
  /*
   * Die Vermutung, die dahinterstand: evaluate() vermerkt nur die
   * NÄCHSTGELEGENE Anlage als gewarnt. Liegen zwei gleichzeitig in
   * Reichweite, bleibt die zweite unvermerkt und löst beim nächsten Fix eine
   * eigene Warnung aus — werden daraus zwei Ansagen in kurzem Abstand?
   *
   * Nachgemessen bei 100 km/h. Beide Tracks fahren dieselbe Strecke, sie
   * unterscheiden sich nur im Abstand der beiden Anlagen:
   *
   *   250 m Abstand -> zwei Ansagen, 9,0 s auseinander.  RICHTIG SO.
   *    30 m Abstand -> zwei Ansagen, 0,9 s auseinander.  ZU DICHT.
   *
   * Die Vermutung stimmt also, aber nicht in der vermuteten Ausprägung: Bei
   * 250 m ist das Verhalten korrekt — zwei Anlagen, zwei Warnungen, jede bei
   * ihrer eigenen Entfernung. Erst unter rund 100 m schneidet die zweite
   * Ansage in die erste.
   *
   * Beide Fälle stehen deshalb als Track hier: einer, der zwei Warnungen
   * verlangt, und einer, der eine verlangt. Ein Track allein liesse offen,
   * ob die Regel zu scharf oder zu lasch ist.
   */
  const START_LAT = 48.6;
  const START_LON = 9.0;
  const V = 27.8;
  const punkte = fahrt(START_LAT, START_LON, 90, V, 60);
  const [ersteLat, ersteLon] = ziel(START_LAT, START_LON, 90, 900);

  /*
   * BEIDE Tracks erwarten ZWEI Warnungen. Der Unterschied liegt im Abstand,
   * und deshalb ist die Warnungszahl hier nicht der Prüfpunkt.
   *
   * Die zweite Anlage wird nicht verschluckt, sondern verschoben, bis
   * WARN.MIN_ANSAGE_ABSTAND_MS eingehalten ist — sie kommt dann bei kürzerer
   * Entfernung. Sie zu unterdrücken wäre die falsche Antwort: Bei 250 m sind
   * zwei getrennte Warnungen richtig, und eine Regel, die das nicht
   * unterscheidet, verschluckt eine echte Anlage.
   */
  for (const [name, abstandM, erwartet, was] of [
    ['zwei-anlagen-weit', 250, 2, 'weit genug auseinander für zwei Ansagen'],
    ['zwei-anlagen-dicht', 30, 2, 'zu dicht — die zweite Ansage wird verschoben'],
  ] as const) {
    const [zweiteLat, zweiteLon] = ziel(ersteLat, ersteLon, 90, abstandM);
    fixtures.push({
      name,
      punkte,
      erwartung: {
        beschreibung:
          `Zwei Anlagen ${abstandM} m hintereinander in Fahrtrichtung, ` +
          `${(V * 3.6).toFixed(0)} km/h — ${was}`,
        kameras: [
          { lat: ersteLat, lon: ersteLon, dir: null, max: 100, type: 'speed' },
          { lat: zweiteLat, lon: zweiteLon, dir: null, max: 100, type: 'speed' },
        ],
        erwarteteWarnungen: erwartet,
        // Der eigentliche Prüfpunkt. 4 s ist WARN.MIN_ANSAGE_ABSTAND_MS;
        // gemessen wurden vor der Regel 0,9 s beim dichten Paar.
        minAnsageAbstandS: 4,
      },
    });
  }
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
