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
import {
  baueKarte, massstab, massstabsbalken, projiziere, punktBeiTipp, ringe,
  umrissAbRadiusM, umrissLinien, verschiebe,
} from '../src/core/karte';
import { TOLERANZ_GRENZE_M } from '../src/core/country-data';
import { TOUCH } from '../src/ui/theme';
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

// --- Landesumrisse --------------------------------------------------------

test('die Umrissgrenze wird aus der Vereinfachung gerechnet, nicht gewählt', () => {
  // 200 m Vereinfachungstoleranz, höchstens 5 % Fehler im Bild -> ab 4 km.
  // Der Test hält die Rechnung, nicht die Zahl: Wer die Toleranz in der
  // Pipeline ändert, bekommt hier keine Überraschung, sondern einen
  // mitgewanderten Wert.
  assert.equal(umrissAbRadiusM(), TOLERANZ_GRENZE_M / KARTE.UMRISS_MAX_FEHLER_ANTEIL);
  assert.equal(umrissAbRadiusM(), 4000);
});

test('unter der Grenze wird kein Umriss gezeichnet', () => {
  // Bei 500 m Umkreis wären 200 m Vereinfachung ein Fünftel des halben
  // Bildes. Eine Grenze, die dort so weit daneben liegt, ist keine
  // Orientierungshilfe, sondern eine Falschaussage.
  const basel: [number, number] = [47.56, 7.59];
  assert.deepEqual(umrissLinien(basel[0], basel[1], 350, 500), []);
  assert.deepEqual(umrissLinien(basel[0], basel[1], 350, 2000), []);
  assert.ok(umrissLinien(basel[0], basel[1], 350, 5000).length > 0);
});

test('am Dreiländereck und an der Küste kommen Linien, mitten im Land nicht', () => {
  // Die Probe darauf, dass der Zuschnitt wirklich zuschneidet — und nicht
  // etwa alles oder nichts liefert.
  const zuege = (lat: number, lon: number) => umrissLinien(lat, lon, 350, 20_000).length;

  assert.ok(zuege(47.56, 7.59) > 0, 'Basel: keine Grenze gefunden');
  assert.ok(zuege(54.9, 8.3) > 0, 'Sylt: keine Küste gefunden');
  assert.equal(zuege(52.52, 13.40), 0, 'Berlin: eine Grenze, die es dort nicht gibt');
  assert.equal(zuege(48.78, 9.18), 0, 'Stuttgart: eine Grenze, die es dort nicht gibt');
});

test('der Zuschnitt zeichnet nur einen Bruchteil der 39 219 Punkte', () => {
  // Ohne Zuschnitt wäre jede Aktualisierung eine spürbare Pause. Die
  // Obergrenze hier ist grosszügig gesetzt; sie soll eine Grössenordnung
  // absichern, keine Zahl festschreiben.
  const zuege = umrissLinien(47.56, 7.59, 350, 20_000);
  const punkte = zuege.reduce((n, z) => n + z.length, 0);
  assert.ok(punkte > 0 && punkte < 1000, `${punkte} Punkte gezeichnet`);
});

test('ein Linienzug hat mindestens zwei Punkte — ein einzelner ist keine Linie', () => {
  for (const zug of umrissLinien(47.56, 7.59, 350, 20_000)) {
    assert.ok(zug.length >= 2, `Zug mit ${zug.length} Punkt(en)`);
  }
});

// --- Massstabsbalken ------------------------------------------------------

test('der Massstabsbalken ist rund und passt ins Bild', () => {
  // Ohne Balken hat eine Karte ohne Strassen keinen Bezug: Die Ringe sagen
  // "gleich weit", nicht "wie weit".
  const RUND = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000, 50_000, 100_000];
  for (const radius of KARTE.RADIEN_M) {
    const b = massstabsbalken(350, radius);
    assert.ok(RUND.includes(b.meter), `${b.meter} m ist kein runder Wert`);
    assert.ok(b.laengeDp <= 350 / 3 + 0.001, `Balken ${b.laengeDp} dp ist zu lang`);
    assert.ok(b.laengeDp > 350 / 8, `Balken ${b.laengeDp} dp ist zu kurz zum Ablesen`);
  }
});

// --- Tippen ---------------------------------------------------------------

test('ein Tipp wählt die nächstgelegene Anlage, nicht irgendeine', () => {
  const nah = anlage(MITTE_LAT + 0.001, MITTE_LON);
  const fern = anlage(MITTE_LAT + 0.003, MITTE_LON);
  const k = baueKarte(MITTE_LAT, MITTE_LON, [fern, nah], GROESSE, 1000);

  const zielNah = k.punkte.find((p) => p.camera === nah)!;
  const treffer = punktBeiTipp(k, zielNah.x + 3, zielNah.y + 3);
  assert.equal(treffer?.camera, nah);
});

test('ein Tipp ins Leere hebt die Auswahl auf, statt danebenzugreifen', () => {
  // null und nicht "die nächste, egal wie weit": Sonst wählt ein Tipp am
  // Bildrand eine Anlage in der Mitte aus, und der Nutzer sucht danach den
  // Zusammenhang.
  const k = baueKarte(MITTE_LAT, MITTE_LON, [anlage(MITTE_LAT, MITTE_LON)], GROESSE, 1000);
  assert.equal(punktBeiTipp(k, 5, 5), null);
});

test('der Tipp-Radius ist grösser als der Punkt und kleiner als das Ziel-Minimum', () => {
  assert.ok(KARTE.TIPP_RADIUS_DP > 8, 'kleiner als der Punkt selbst — nicht treffbar');
  assert.ok(KARTE.TIPP_RADIUS_DP <= TOUCH.MIN, 'grösser als eine Berührungsfläche');
});

// --- Verschieben ----------------------------------------------------------

test('nach rechts ziehen zeigt weiter nach Westen', () => {
  // Das Vorzeichen, das man bei einer verschiebbaren Karte falsch macht:
  // Der Finger bewegt die KARTE, nicht den Mittelpunkt.
  const v = verschiebe(MITTE_LAT, MITTE_LON, 50, 0, GROESSE, 2000);
  assert.ok(v.lon < MITTE_LON, 'nach rechts ziehen bewegte den Blick nach Osten');

  const w = verschiebe(MITTE_LAT, MITTE_LON, 0, 50, GROESSE, 2000);
  assert.ok(w.lat > MITTE_LAT, 'nach unten ziehen bewegte den Blick nach Süden');
});

test('verschieben und zurückverschieben landet wieder am Anfang', () => {
  const hin = verschiebe(MITTE_LAT, MITTE_LON, 40, -25, GROESSE, 2000);
  const zurueck = verschiebe(hin.lat, hin.lon, -40, 25, GROESSE, 2000);
  // Nicht exakt: cos(Breite) wird am neuen Mittelpunkt neu gerechnet. Der
  // Rückweg muss aber weit unter einem Meter danebenliegen.
  assert.ok(Math.abs(zurueck.lat - MITTE_LAT) * 111_320 < 0.01);
  assert.ok(Math.abs(zurueck.lon - MITTE_LON) * 111_320 < 1);
});

test('über den Pol hinaus lässt sich nicht schieben', () => {
  const v = verschiebe(84, 9, 0, -100_000, GROESSE, 20_000);
  assert.ok(v.lat <= 85, `lat ${v.lat} liegt jenseits des Pols`);
});
