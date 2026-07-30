/**
 * Die Verdrahtung, nicht die Bausteine.
 *
 * `evaluate()` und `pruefeZonen()` sind einzeln getestet und waren es auch,
 * als Frankreich stumm blieb. Der Fehler sass dazwischen: WELCHE der beiden
 * bei welchem Warnmodus überhaupt zum Zug kommt. Diese Datei prüft genau das.
 *
 * Die schärfste Zusage hier ist die erste: Im Zonenmodus darf niemals eine
 * Entfernung ausgegeben werden. Frankreich untersagt sie seit 03.01.2012 —
 * bis 1500 Euro, Einziehung des Geräts.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { Warnmodus } from '../src/config';
import { entscheide, type Aktion, type Eingang } from '../src/core/entscheidung';
import { cellKey } from '../src/core/geo';
import { createTripState } from '../src/core/warn';
import { createZonenZustand, type Zone } from '../src/core/zone';
import type { Camera, Fix, Settings } from '../src/types';

const SETTINGS: Settings = {
  warnDistanceFactor: 1,
  sprachansage: true,
  lautstaerke: 1,
  rotlichtblitzer: true,
  motorradModus: false,
  haptik: false,
  tachoFaktor: 1,
};

const MODI: Warnmodus[] = ['punkt', 'zone', 'aus'];

function gitter(kameras: Camera[]): Record<string, Camera[]> {
  const grid: Record<string, Camera[]> = {};
  for (const k of kameras) (grid[cellKey(k.lat, k.lon)] ??= []).push(k);
  return grid;
}

/** Fahrt nach Osten auf der Höhe von Strasbourg, 100 km/h. */
function fix(lat: number, lon: number, extra: Partial<Fix> = {}): Fix {
  return { lat, lon, course: 90, speed: 27.8, accuracy: 5, t: 0, ...extra };
}

function eingang(teil: Partial<Eingang> = {}): Eingang {
  return {
    grid: {},
    trip: createTripState(),
    settings: SETTINGS,
    zonen: null,
    zonenZustand: createZonenZustand(),
    ...teil,
  };
}

/*
 * Eine Kamera rund 295 m östlich, also in Fahrtrichtung voraus und innerhalb
 * der Warndistanz: Bei 27,8 m/s sind das nach WARN.DISTANCE_PER_SPEED 334 m.
 * 0,004 Grad Länge entsprechen auf 48,5 Grad Breite 0,004 * 111320 * cos(48,5)
 * = 295 m.
 */
const KAMERA: Camera = { lat: 48.5, lon: 7.754, dir: null, max: 90, type: 'speed' };
const START = { lat: 48.5, lon: 7.75 };

// Eine Zone, in der der Startpunkt liegt.
const ZONE: Zone = { lat: 48.5, lon: 7.75, r: 2000 };

// --- Die Kernauflage ------------------------------------------------------

test('im Zonenmodus gibt es NIE eine Entfernung', () => {
  // Strukturell und nicht bloss beobachtet: Der Fall 'zonenhinweis' hat keine
  // Felder. Der Test prüft den Typ am lebenden Objekt — auch ein späterer
  // Umbau, der eine Distanz einschmuggelt, fällt hier durch.
  const aktion = entscheide(
    fix(START.lat, START.lon), 'zone',
    eingang({ grid: gitter([KAMERA]), zonen: [ZONE] }),
  );

  assert.equal(aktion.art, 'zonenhinweis');
  assert.deepEqual(
    Object.keys(aktion), ['art'],
    `die Zonenaktion trägt zusätzliche Felder: ${Object.keys(aktion).join(', ')}`,
  );
});

test('im Zonenmodus kommt NIE eine Punktwarnung, auch mit Kamera direkt voraus', () => {
  // Der gefährliche Rückfall: "lieber irgendetwas warnen als gar nichts".
  // In Frankreich ist das genau falsch herum — die Punktwarnung ist dort die
  // verbotene, nicht die fehlende.
  const grid = gitter([KAMERA]);

  for (const zonen of [[ZONE], [] as Zone[], null]) {
    const aktion = entscheide(
      fix(START.lat, START.lon), 'zone',
      eingang({ grid, zonen }),
    );
    assert.notEqual(
      aktion.art, 'punktwarnung',
      `zonen=${zonen === null ? 'null' : `${zonen.length} Stück`} führte zur Punktwarnung`,
    );
  }
});

test('keine Aktion irgendeines Modus trägt eine Distanz ausser der Punktwarnung', () => {
  // Die Verallgemeinerung: Egal welcher Modus, egal welche Eingabe — sobald
  // eine Zahl in der Aktion steht, muss es eine Punktwarnung sein.
  const faelle: Eingang[] = [
    eingang({ grid: gitter([KAMERA]) }),
    eingang({ grid: gitter([KAMERA]), zonen: [ZONE] }),
    eingang({ zonen: [] }),
    eingang(),
  ];

  for (const modus of MODI) {
    for (const e of faelle) {
      const aktion: Aktion = entscheide(fix(START.lat, START.lon), modus, e);
      const hatZahl = Object.values(aktion).some((v) => typeof v === 'number');
      if (hatZahl) {
        assert.equal(aktion.art, 'punktwarnung', `${modus} gab eine Zahl aus`);
        assert.equal(modus, 'punkt', `Modus ${modus} erzeugte eine Punktwarnung`);
      }
    }
  }
});

// --- Der stille Ausfall ---------------------------------------------------

test('fehlende Zonendaten sind ein eigener Grund, kein "keine Zone"', () => {
  // Der Unterschied ist der ganze Punkt. "Hier ist keine Zone" ist
  // Normalbetrieb, "wir haben die Daten nicht" ein Ausfall — und nur der
  // zweite gehört ins Fehlerprotokoll. Ein gemeinsamer Grund hätte den
  // Ausfall unsichtbar gemacht.
  const ohne = entscheide(fix(START.lat, START.lon), 'zone', eingang({ zonen: null }));
  assert.deepEqual(ohne, { art: 'nichts', grund: 'zonendaten_fehlen' });

  const leer = entscheide(fix(START.lat, START.lon), 'zone', eingang({ zonen: [] }));
  assert.deepEqual(leer, { art: 'nichts', grund: 'keine_zone' });
});

test('eine leere Zonenliste ist etwas anderes als keine Zonenliste', () => {
  // Gegenprobe zum vorigen Test, formuliert über den Typ: Wer `zonen` auf
  // `readonly Zone[]` verengt und null wegoptimiert, nimmt der App die
  // Fähigkeit, den Ausfall zu bemerken.
  const gruende = new Set(
    [null, [] as Zone[]].map((zonen) => {
      const a = entscheide(fix(START.lat, START.lon), 'zone', eingang({ zonen }));
      return a.art === 'nichts' ? a.grund : a.art;
    }),
  );
  assert.equal(gruende.size, 2, 'beide Fälle liefern denselben Grund');
});

// --- Genau eine Ansage pro Zone -------------------------------------------

test('eine Zone sagt genau einmal an, auch über viele Fixes', () => {
  const e = eingang({ zonen: [ZONE] });
  let ansagen = 0;
  for (let i = 0; i < 20; i++) {
    // Langsam durch die Zone, bleibt die ganze Zeit drin.
    const a = entscheide(fix(START.lat, START.lon + i * 0.0001), 'zone', e);
    if (a.art === 'zonenhinweis') ansagen++;
  }
  assert.equal(ansagen, 1, `${ansagen} Ansagen für eine Zone`);
});

test('verlassen und wieder betreten sagt erneut an', () => {
  const e = eingang({ zonen: [ZONE] });
  const drin = () => entscheide(fix(ZONE.lat, ZONE.lon), 'zone', e);
  // Weit genug weg: 2000 m Radius, 0.1 Grad Länge sind hier rund 7 km.
  const draussen = () => entscheide(fix(ZONE.lat, ZONE.lon + 0.1), 'zone', e);

  assert.equal(drin().art, 'zonenhinweis');
  assert.equal(drin().art, 'nichts');
  assert.equal(draussen().art, 'nichts');
  assert.equal(drin().art, 'zonenhinweis', 'nach dem Verlassen wird nicht neu scharf');
});

// --- Die anderen Modi -----------------------------------------------------

test("Modus 'aus' tut nichts, egal was vorliegt", () => {
  const a = entscheide(
    fix(START.lat, START.lon), 'aus',
    eingang({ grid: gitter([KAMERA]), zonen: [ZONE] }),
  );
  assert.deepEqual(a, { art: 'nichts', grund: 'land_gesperrt' });
});

test('der Punktmodus warnt mit Entfernung — sonst prüften die Tests oben nichts', () => {
  // Gegenprobe. Fiele dieser Test durch, wäre "keine Distanz im Zonenmodus"
  // trivial erfüllt, weil überhaupt nie eine Distanz entsteht.
  const a = entscheide(
    fix(START.lat, START.lon), 'punkt',
    eingang({ grid: gitter([KAMERA]) }),
  );
  assert.equal(a.art, 'punktwarnung');
  if (a.art !== 'punktwarnung') return;
  assert.ok(a.distanzM > 250 && a.distanzM < 334, `Distanz ${a.distanzM.toFixed(0)} m`);
  assert.equal(a.camera.max, 90);
});

test('der Punktmodus rührt die Zonen nicht an', () => {
  // Sonst verbrauchte eine Fahrt durch Spanien den Zonenzustand und die
  // erste Zone hinter der französischen Grenze bliebe stumm.
  const zonenZustand = createZonenZustand();
  entscheide(
    fix(ZONE.lat, ZONE.lon), 'punkt',
    eingang({ grid: gitter([KAMERA]), zonen: [ZONE], zonenZustand }),
  );
  assert.equal(zonenZustand.drin.size, 0, 'der Punktmodus hat den Zonenzustand verändert');
});
