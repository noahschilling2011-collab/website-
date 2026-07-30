/**
 * B.4 — Die Hysterese gegen einen echten Grenzübertritt.
 *
 * Die Tabellentests in gate.test.ts prüfen, WAS in einem Land erlaubt ist.
 * Dieser Test prüft, WANN die App das merkt. Beide Fragen sind verschieden,
 * und nur die zweite lässt sich an einem Track messen.
 *
 * Der Track: fixtures/grenze-kehl-strasbourg.gpx, Europabrücke von Kehl nach
 * Strasbourg, 13,9 m/s, ein Fix je etwa 14 m. Diese Stelle ist ausgesucht,
 * nicht bequem — die Grenze verläuft dort im Rhein, quer zur Fahrtrichtung,
 * und Deutschland verbietet die Warnung, während Frankreich sie in Zonenform
 * erlaubt. Ein Fehler in beide Richtungen hat also Folgen.
 *
 * DIE ANFORDERUNG, wörtlich aus der Spec: genau ein Moduswechsel, genau eine
 * Ansage, kein Flattern, und der Wechsel liegt zwischen 0 und 500 m NACH der
 * tatsächlichen Grenze. Nicht davor. Zu früh in Frankreich zu schalten heisst,
 * in Deutschland zu warnen.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { landwechselText } from '../src/audio/announce';
import type { Warnmodus } from '../src/config';
import {
  LAND_HYSTERESE,
  abstandZurGrenze,
  aktualisiereLand,
  createLandZustand,
  erkenneUmriss,
  leseLand,
  warnmodus,
  type LandGrund,
} from '../src/core/country';
import { TOLERANZ_GRENZE_M } from '../src/core/country-data';
import { haversine } from '../src/core/geo';
import { parseGpx, toFixes } from '../src/replay/gpx';
import type { Fix } from '../src/types';

const HIER = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HIER, '..', 'fixtures');

/**
 * Das geforderte Fenster: der Wechsel darf höchstens so weit hinter der
 * Grenze liegen. Aus der Spec, nicht aus einer Messung — die Messung sagt,
 * ob wir es einhalten.
 */
const FENSTER_M = 500;

function ladeTrack(name: string): Fix[] {
  return toFixes(parseGpx(readFileSync(join(FIXTURES, `${name}.gpx`), 'utf8')));
}

/**
 * Der Punkt, an dem die Umrissdaten von einem Land ins andere wechseln.
 *
 * Das ist die Grenze, wie die App sie kennt. Sie ist nicht die tatsächliche
 * Grenze — dazwischen liegt der Vereinfachungsfehler der Umrisse. Wie mit
 * dieser Differenz umgegangen wird, steht unten im Test.
 */
function datengrenze(fixes: Fix[], von: string, nach: string): number {
  for (let i = 1; i < fixes.length; i++) {
    const vorher = erkenneUmriss(fixes[i - 1]!.lat, fixes[i - 1]!.lon);
    const jetzt = erkenneUmriss(fixes[i]!.lat, fixes[i]!.lon);
    if (vorher === von && jetzt === nach) return i;
  }
  throw new Error(`Der Track wechselt nicht von ${von} nach ${nach}`);
}

type Verlauf = {
  wechsel: { index: number; von: Warnmodus; nach: Warnmodus }[];
  gruende: Map<LandGrund, number>;
};

/** Den Track durch die Hysterese schicken und die Moduswechsel mitschreiben. */
function fahre(fixes: Fix[]): Verlauf {
  const zustand = createLandZustand();
  const wechsel: Verlauf['wechsel'] = [];
  const gruende = new Map<LandGrund, number>();
  // Startwert ist der Modus vor dem ersten Fix, also der unbestimmte Fall.
  let modus = warnmodus(null);

  for (let i = 0; i < fixes.length; i++) {
    const status = aktualisiereLand(zustand, fixes[i]!);
    gruende.set(status.grund, (gruende.get(status.grund) ?? 0) + 1);
    const jetzt = warnmodus(status.land);
    if (jetzt !== modus) {
      wechsel.push({ index: i, von: modus, nach: jetzt });
      modus = jetzt;
    }
  }
  return { wechsel, gruende };
}

// --- Der Schwellwert ------------------------------------------------------

test('MINDESTABSTAND_GRENZE_M ist aus der Güte der Umrisse abgeleitet', () => {
  // Die Zahl darf nicht frei gewählt sein. Zu klein, und sie prüft gegen den
  // eigenen Fehler; zu gross, und die Warnung bleibt kilometerweit hinter der
  // Grenze noch aus. Beides ist in der Vergangenheit passiert: Der frühere
  // Wert 3000 m stammte aus der Zeit der handeingetragenen Linien.
  assert.equal(LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M, 2 * TOLERANZ_GRENZE_M);

  assert.ok(
    LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M > TOLERANZ_GRENZE_M,
    'Ein Schwellwert unterhalb des Vereinfachungsfehlers prüft sich selbst',
  );
  assert.ok(
    LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M <= FENSTER_M,
    `Ein Schwellwert über ${FENSTER_M} m kann das Fenster nicht mehr einhalten, ` +
    'weil der Wechsel frühestens beim Erreichen des Abstands greift',
  );
});

// --- Der Übertritt --------------------------------------------------------

test('Kehl -> Strasbourg: zwei saubere Moduswechsel, kein Flattern', () => {
  // Seit Deutschland warnt, sind es zwei: erst die Bestätigung, dass wir in
  // Deutschland sind (aus -> punkt), dann der Grenzübertritt (punkt -> zone).
  // Vorher war der erste unsichtbar, weil Deutschland auf 'aus' stand.
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const { wechsel } = fahre(fixes);

  assert.equal(
    wechsel.length, 2,
    `${wechsel.length} Moduswechsel: ` +
    wechsel.map((w) => `Fix ${w.index} ${w.von}->${w.nach}`).join(', '),
  );
  assert.deepEqual(
    wechsel.map((w) => `${w.von}->${w.nach}`),
    ['aus->punkt', 'punkt->zone'],
  );

  // Der erste Wechsel ist der Start, nicht die Grenze: Er fällt weit VOR dem
  // Rhein, weil dort Deutschland bestätigt wird.
  assert.ok(wechsel[0]!.index < 20, `Startbestätigung erst bei Fix ${wechsel[0]!.index}`);
});

test('der Wechsel liegt 0 bis 500 m NACH der Grenze, nicht davor', () => {
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const grenzIndex = datengrenze(fixes, 'DE', 'FR');
  const grenze = fixes[grenzIndex]!;
  const { wechsel } = fahre(fixes);
  // Der Grenzübertritt ist der Wechsel NACH 'zone'. Der erste Wechsel des
  // Tracks ist die Startbestätigung in Deutschland und hat mit der Grenze
  // nichts zu tun.
  const uebertritt = wechsel.find((w) => w.nach === 'zone');
  assert.ok(uebertritt !== undefined, 'kein Wechsel in den Zonenmodus');
  const schaltpunkt = fixes[uebertritt.index]!;

  const hinterDerGrenze = haversine(
    schaltpunkt.lat, schaltpunkt.lon, grenze.lat, grenze.lon,
  );

  // DAVOR IST DER GEFÄHRLICHE FEHLER, deshalb zuerst geprüft: Ein Wechsel vor
  // der Grenze heisst, in Deutschland eine Warnfunktion einzuschalten.
  assert.ok(
    uebertritt.index > grenzIndex,
    `Der Wechsel liegt bei Fix ${uebertritt.index}, die Grenze bei ${grenzIndex} — ` +
    'die App schaltet Frankreich frei, während sie noch in Deutschland ist',
  );

  // Und nicht zu spät. Gemessen: 389 m. Der Rest des Fensters ist Luft für
  // den Fixabstand (14 m) und die fünf bestätigenden Fixes (70 m).
  assert.ok(
    hinterDerGrenze <= FENSTER_M,
    `Der Wechsel liegt ${hinterDerGrenze.toFixed(0)} m hinter der Grenze, ` +
    `erlaubt sind ${FENSTER_M} m`,
  );

  // Die Messung selbst festhalten. Wenn sich Umrisse, Schwellwert oder Track
  // ändern, soll der Test die neue Zahl nennen und nicht bloss "irgendwo im
  // Fenster" sagen.
  assert.ok(
    hinterDerGrenze > 300 && hinterDerGrenze < 450,
    `Erwartet wurden die gemessenen 389 m, gemessen ${hinterDerGrenze.toFixed(0)} m — ` +
    'wenn das gewollt ist, gehört die neue Zahl in den Kommentar von ' +
    'LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M',
  );

  // Gegenprobe über den Abstand, nicht über den Trackverlauf: Am Schaltpunkt
  // muss der gemessene Grenzabstand den Schwellwert erreichen. Sonst hätte
  // ihn etwas anderes durchgelassen als die Prüfung, die dafür da ist.
  assert.ok(
    abstandZurGrenze(schaltpunkt.lat, schaltpunkt.lon, 'FR')
      >= LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M,
    'Der Schaltpunkt erfüllt den Grenzabstand nicht — es hat etwas anderes geschaltet',
  );
});

test('der Grenzabstand ist der Grund für die Verzögerung, nicht der Zähler', () => {
  // Nachweis, dass die richtige Bremse greift. Würde nur der Fixzähler
  // bremsen, käme der Wechsel schon 70 m hinter der Grenze — also innerhalb
  // des Vereinfachungsfehlers der Umrisse, und damit möglicherweise davor.
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const { gruende } = fahre(fixes);

  const grenznah = gruende.get('grenznah') ?? 0;
  const wartet = gruende.get('wartet_bestaetigung') ?? 0;

  assert.ok(grenznah > 0, 'kein einziger Fix wurde wegen Grenznähe gehalten');
  assert.ok(
    grenznah > wartet,
    `Grenznähe hielt ${grenznah} Fixes, der Zähler ${wartet} — ` +
    'die Verzögerung soll aus dem Abstand kommen',
  );
  // Der Zähler läuft genau zweimal durch: einmal für die Startbestätigung in
  // Deutschland, einmal für Frankreich. Mehr hiesse, dass er zwischendurch
  // neu gestartet wurde — also Flattern.
  assert.equal(
    wartet, 2 * (LAND_HYSTERESE.BESTAETIGENDE_FIXES - 1),
    'Der Zähler startet mehr als zweimal — das wäre Flattern',
  );
});

test('genau eine Ansage, und sie nennt in Frankreich die Gefahr nicht', () => {
  // Die Ansage hängt am Moduswechsel, nicht am Ja/Nein der Punktwarnung.
  // Genau daran fehlte sie vorher: 'aus' -> 'zone' liess `darfPunktWarnen`
  // unverändert false, der Wechsel wurde also nicht angesagt.
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const { wechsel } = fahre(fixes);

  // Der erste Fix sagt nie an — er ist kein Wechsel, sondern der Anfang.
  // Auf diesem Track beginnt der Modus in Deutschland und bleibt 'aus', der
  // einzige Wechsel ist damit auch die einzige Ansage.
  const ansagen = wechsel.map((w) => landwechselText(w.nach));
  assert.deepEqual(ansagen, ['Blitzerwarnung aktiviert', 'Hinweise aktiviert']);

  // Der Punkt: Die ZWEITE Ansage fällt in Frankreich und darf die Gefahr
  // nicht benennen. Die erste fällt in Deutschland, wo sie es darf und soll.
  const inFrankreich = ansagen[1]!;
  assert.ok(
    !/blitzer|radar/i.test(inFrankreich),
    `Die Ansage beim Übertritt nach Frankreich benennt die Gefahr: "${inFrankreich}"`,
  );
  assert.match(ansagen[0]!, /Blitzer/, 'in Deutschland darf sie es benennen');
});

// --- Die andere Richtung --------------------------------------------------

test('zurück nach Deutschland wechselt in den Punktmodus, nicht in Stille', () => {
  // Der Track wird umgedreht. Beide Seiten warnen inzwischen, nur in
  // verschiedener Form — der Wechsel geht also von 'zone' nach 'punkt' und
  // nimmt deshalb den langsamen Weg mit Grenzabstand. Das ist richtig: Wer
  // nach Deutschland einfährt, soll die Punktwarnung nicht schon auf der
  // Brücke bekommen.
  const hin = ladeTrack('grenze-kehl-strasbourg');
  const zurueck = [...hin].reverse().map((f, i) => ({ ...f, t: hin[0]!.t + i * 1000 }));

  const grenzIndex = datengrenze(zurueck, 'FR', 'DE');
  const { wechsel } = fahre(zurueck);

  assert.deepEqual(
    wechsel.map((w) => `${w.von}->${w.nach}`),
    ['aus->zone', 'zone->punkt'],
    wechsel.map((w) => `${w.index}:${w.von}->${w.nach}`).join(', '),
  );
  assert.ok(
    wechsel[1]!.index > grenzIndex,
    'Der Punktmodus greift, bevor die Daten Deutschland melden',
  );
});

test('DIE UNSYMMETRIE: ein Land ohne Aussage schaltet sofort ab', () => {
  // Das war vorher am Grenztrack zu sehen, weil Deutschland auf 'aus' stand.
  // Jetzt braucht es einen eigenen Fall — und der ist der wichtigere: Ein
  // Land, über dessen Rechtslage nichts bekannt ist, muss die laufende
  // Warnung SOFORT abschalten, ohne Zähler und ohne Grenzabstand.
  //
  // Italien ist so ein Land (status 'unklar') und grenzt an Frankreich.
  const zustand = createLandZustand();

  // Erst Frankreich bestätigen: tief im Land, weit von jeder Grenze.
  const inFrankreich = { lat: 47.0, lon: 2.5, accuracy: 5 };
  for (let i = 0; i < LAND_HYSTERESE.BESTAETIGENDE_FIXES; i++) {
    aktualisiereLand(zustand, inFrankreich);
  }
  assert.equal(warnmodus(leseLand(zustand).land), 'zone', 'Frankreich wurde nicht bestätigt');

  // Ein einziger Fix in Italien reicht.
  const status = aktualisiereLand(zustand, { lat: 43.0, lon: 12.0, accuracy: 5 });
  assert.equal(status.umriss, 'IT');
  assert.equal(
    warnmodus(status.land), 'aus',
    'Ein Land ohne belegte Rechtslage schaltet die Warnung nicht ab',
  );
});
