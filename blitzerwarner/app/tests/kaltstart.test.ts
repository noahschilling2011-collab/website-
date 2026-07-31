/**
 * Kaltstart und erste Fahrt — der Durchlauf, den es noch nicht gab.
 *
 * WARUM DIESE DATEI
 *
 * Alle übrigen Tests prüfen einzelne Bausteine mit erfundenen Eingaben. Das
 * ist richtig so, hat aber eine Lücke, die zweimal zugeschlagen hat: Erst war
 * der Zonenmodus gebaut, getestet und trotzdem nicht verdrahtet; dann warnte
 * Deutschland nicht, weil zwei Fragen in einem Feld steckten. Beide Male waren
 * die Bausteine grün.
 *
 * Hier läuft deshalb die ganze Kette, mit den ECHTEN Daten aus dem App-Paket:
 *
 *   Datensatz laden -> echte Anlage suchen -> Anfahrt darauf rechnen ->
 *   Landeserkennung -> Gate -> Entscheidung -> Ansagetext
 *
 * Kein erfundenes Gitter, keine erfundene Kamera, keine erfundene Position.
 * Wenn dieser Test grün ist, warnt die App an einer real erfassten Anlage in
 * Deutschland — alles ausser der Plattform selbst.
 *
 * WAS ER NICHT LEISTET: Er sagt nichts über expo-location, expo-av oder die
 * Berechtigungen. Ob das Gerät Positionen liefert und ob ein Ton hörbar wird,
 * lässt sich nur auf dem Gerät prüfen. Dafür gibt es den Fahrtenschreiber.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ansageText } from '../src/audio/announce';
import { warnmodus as modusFuer } from '../src/core/country';
import {
  aktualisiereLand,
  createLandZustand,
  fahrerverbot,
} from '../src/core/country';
import { loadDataset } from '../src/core/dataset';
import { entscheide } from '../src/core/entscheidung';
import { haversine } from '../src/core/geo';
import { STANDARD_SETTINGS } from '../src/core/settings';
import { createTripState } from '../src/core/warn';
import { createZonenZustand } from '../src/core/zone';
import { bannerFuerLand } from '../src/strings';
import type { Camera, Fix } from '../src/types';

// --- Der Kaltstart --------------------------------------------------------

test('der gebündelte Datensatz lädt so, wie App.tsx ihn lädt', () => {
  // Dieselbe Zeile, die im useEffect von App.tsx steht. Wirft sie, zeigt die
  // App einen Fehlerbildschirm statt des Fahrt-Screens.
  const dataset = loadDataset();

  assert.ok(dataset.count > 0, 'der Datensatz ist leer');
  assert.ok(dataset.source.length > 0, 'keine Quellenangabe — Lizenzpflicht');
  assert.ok(dataset.license.length > 0, 'keine Lizenzangabe');
  assert.equal(dataset.count, Object.values(dataset.grid).flat().length);
});

test('zweimal laden liefert dasselbe Objekt', () => {
  // App.tsx ruft loadDataset() im Effect, der Hintergrund-Task greift über
  // datasetOrNull() darauf zu. Würde jeder Aufruf neu parsen, kostete das bei
  // jedem Positionsupdate 6 ms und damit das Akkuziel.
  assert.equal(loadDataset(), loadDataset());
});

// --- Eine echte Anlage ----------------------------------------------------

/**
 * Eine real erfasste Anlage im Landesinneren suchen.
 *
 * Bewusst deterministisch und nicht zufällig: Ein Test, der bei jedem Lauf
 * eine andere Anlage nimmt, schlägt irgendwann fehl und niemand weiss warum.
 *
 * Das Suchfenster liegt um Stuttgart, also weit von jeder Landesgrenze — dort
 * greift die Grenzhysterese nicht in die Messung hinein. Baden-Württemberg ist
 * ausserdem das am dichtesten erfasste Bundesland (siehe DATA.md), eine
 * passende Anlage ist dort sicher zu finden.
 */
function echteAnlage(): Camera {
  const dataset = loadDataset();
  const kandidaten = Object.values(dataset.grid)
    .flat()
    .filter((k) =>
      k.lat > 48.6 && k.lat < 48.9 &&
      k.lon > 9.0 && k.lon < 9.4 &&
      // Ohne Richtungsangabe: Dann hängt der Test nicht daran, aus welcher
      // Himmelsrichtung die Anfahrt gerechnet wird.
      k.dir === null &&
      k.max !== null &&
      k.type === 'speed')
    .sort((a, b) => a.lat - b.lat || a.lon - b.lon);

  const anlage = kandidaten[0];
  assert.ok(
    anlage !== undefined,
    'keine passende Anlage im Suchfenster — hat sich der Datensatz geändert?',
  );
  return anlage;
}

/**
 * Eine Anfahrt aus Süden auf die Anlage rechnen.
 *
 * Fixes im Sekundentakt bei 27,8 m/s (100 km/h), von 800 m davor bis 100 m
 * dahinter. Die Warndistanz liegt dabei bei 334 m, der Track deckt sie also
 * mit Abstand ab.
 */
function anfahrt(ziel: Camera): Fix[] {
  const V = 27.8;
  const START_M = 800;
  const ENDE_M = -100;
  const GRAD_JE_M = 1 / 111_320;

  const fixes: Fix[] = [];
  for (let m = START_M, t = 0; m >= ENDE_M; m -= V, t += 1000) {
    fixes.push({
      lat: ziel.lat - m * GRAD_JE_M,
      lon: ziel.lon,
      course: 0, // nach Norden, also auf die Anlage zu
      speed: V,
      accuracy: 5,
      t,
    });
  }
  return fixes;
}

test('die Suche findet eine echte Anlage mit Tempolimit', () => {
  const anlage = echteAnlage();
  assert.ok(anlage.max !== null && anlage.max > 0);
  assert.equal(anlage.dir, null);
  assert.equal(anlage.type, 'speed');
});

// --- Die ganze Kette ------------------------------------------------------

test('DIE PROBE: Anfahrt auf eine echte Anlage in Deutschland warnt', () => {
  const anlage = echteAnlage();
  const fixes = anfahrt(anlage);
  const dataset = loadDataset();

  const landZustand = createLandZustand();
  const eingang = {
    grid: dataset.grid,
    trip: createTripState(),
    settings: STANDARD_SETTINGS,
    zonen: null,
    zonenZustand: createZonenZustand(),
  };

  const warnungen: { distanz: number; text: string; nachFixes: number }[] = [];
  const modi = new Set<string>();

  for (let i = 0; i < fixes.length; i++) {
    const fix = fixes[i]!;

    // Genau die Reihenfolge aus location/task.ts: erst Land, dann Modus,
    // dann Entscheidung.
    const status = aktualisiereLand(landZustand, fix);
    const modus = modusFuer(status.land);
    modi.add(modus);

    const aktion = entscheide(fix, modus, eingang);
    if (aktion.art === 'punktwarnung') {
      warnungen.push({
        distanz: aktion.distanzM,
        text: ansageText(aktion.camera, aktion.distanzM),
        nachFixes: i,
      });
    }
  }

  // 1. Das Land wurde erkannt.
  assert.equal(landZustand.bestaetigt, 'DE', 'Deutschland wurde nicht erkannt');

  // 2. Der Modus ist Punktwarnung — das ist die Umstellung, um die es ging.
  assert.ok(modi.has('punkt'), `nie im Punktmodus, gesehen: ${[...modi].join(', ')}`);

  // 3. Es wurde gewarnt. Genau das war vorher NICHT der Fall.
  assert.ok(warnungen.length >= 1, 'keine Warnung auf der Anfahrt an eine echte Anlage');

  // 4. Rechtzeitig: Die Warndistanz bei 100 km/h ist 334 m.
  const erste = warnungen[0]!;
  assert.ok(
    erste.distanz > 250 && erste.distanz <= 334,
    `erste Warnung bei ${erste.distanz.toFixed(0)} m — erwartet knapp unter 334 m`,
  );

  // 5. Der Ansagetext ist brauchbar: benennt die Sache und nennt eine Zahl.
  assert.match(erste.text, /Blitzer/);
  assert.match(erste.text, /Meter/);
  assert.match(erste.text, /Tempo/, 'das Tempolimit der Anlage fehlt in der Ansage');
});

test('auf derselben Anfahrt wird nicht doppelt gewarnt', () => {
  // Der Anti-Doppelwarnung-Zustand über eine ganze Fahrt, an echten Daten.
  // In dichten Gegenden liegen mehrere Anlagen in Reichweite; dass daraus
  // kein Dauerfeuer wird, ist der Punkt.
  const anlage = echteAnlage();
  const eingang = {
    grid: loadDataset().grid,
    trip: createTripState(),
    settings: STANDARD_SETTINGS,
    zonen: null,
    zonenZustand: createZonenZustand(),
  };

  let warnungen = 0;
  for (const fix of anfahrt(anlage)) {
    if (entscheide(fix, 'punkt', eingang).art === 'punktwarnung') warnungen++;
  }

  assert.ok(warnungen <= 3, `${warnungen} Warnungen auf 900 m — das ist Dauerfeuer`);
  assert.ok(warnungen >= 1, 'gar keine Warnung');
});

// --- Was der Fahrer dabei sieht -------------------------------------------

test('in Deutschland erscheint der Rechtshinweis-Banner', () => {
  // Die App warnt hier trotz Fahrerverbot. Ohne den Banner wäre das eine
  // Falle — er ist die einzige Stelle, an der der Fahrer erfährt, worüber er
  // gerade entscheidet.
  const zustand = createLandZustand();
  for (const fix of anfahrt(echteAnlage())) aktualisiereLand(zustand, fix);

  const land = 'DE' as const;
  assert.equal(zustand.bestaetigt, land);
  assert.equal(fahrerverbot(land), 'ja');

  const banner = bannerFuerLand(land);
  assert.ok(banner !== null, 'kein Banner für Deutschland');
  assert.match(banner.kurz, /23 Abs\. 1c StVO/);
  assert.match(banner.lang, /75 Euro/);
});

test('die Anlage liegt wirklich dort, wo der Track sie erwartet', () => {
  // Gegenprobe zur Track-Rechnung. Wäre die Anfahrt falsch gerechnet, liefe
  // der Test oben ins Leere und niemand merkte es — er würde einfach keine
  // Warnung finden und das als Fehler melden, ohne den Grund zu nennen.
  const anlage = echteAnlage();
  const fixes = anfahrt(anlage);

  const start = haversine(fixes[0]!.lat, fixes[0]!.lon, anlage.lat, anlage.lon);
  const ende = fixes[fixes.length - 1]!;
  const schluss = haversine(ende.lat, ende.lon, anlage.lat, anlage.lon);

  assert.ok(start > 750 && start < 850, `Startabstand ${start.toFixed(0)} m, erwartet 800`);
  assert.ok(schluss < 130, `Endabstand ${schluss.toFixed(0)} m — die Fahrt kommt nicht vorbei`);
});
