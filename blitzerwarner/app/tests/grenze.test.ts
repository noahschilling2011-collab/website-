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

test('Kehl -> Strasbourg: genau ein Moduswechsel, kein Flattern', () => {
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const { wechsel } = fahre(fixes);

  assert.equal(
    wechsel.length, 1,
    `${wechsel.length} Moduswechsel: ` +
    wechsel.map((w) => `Fix ${w.index} ${w.von}->${w.nach}`).join(', '),
  );
  assert.equal(wechsel[0]!.von, 'aus', 'in Deutschland muss der Modus aus sein');
  assert.equal(wechsel[0]!.nach, 'zone', 'in Frankreich gilt der Zonenmodus');
});

test('der Wechsel liegt 0 bis 500 m NACH der Grenze, nicht davor', () => {
  const fixes = ladeTrack('grenze-kehl-strasbourg');
  const grenzIndex = datengrenze(fixes, 'DE', 'FR');
  const grenze = fixes[grenzIndex]!;
  const { wechsel } = fahre(fixes);
  const schaltpunkt = fixes[wechsel[0]!.index]!;

  const hinterDerGrenze = haversine(
    schaltpunkt.lat, schaltpunkt.lon, grenze.lat, grenze.lon,
  );

  // DAVOR IST DER GEFÄHRLICHE FEHLER, deshalb zuerst geprüft: Ein Wechsel vor
  // der Grenze heisst, in Deutschland eine Warnfunktion einzuschalten.
  assert.ok(
    wechsel[0]!.index > grenzIndex,
    `Der Wechsel liegt bei Fix ${wechsel[0]!.index}, die Grenze bei ${grenzIndex} — ` +
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
  assert.equal(
    wartet, LAND_HYSTERESE.BESTAETIGENDE_FIXES - 1,
    'Der Zähler soll genau einmal durchlaufen, nicht mehrfach neu starten',
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
  assert.equal(ansagen.length, 1, `${ansagen.length} Ansagen: ${ansagen.join(' | ')}`);
  assert.equal(ansagen[0], 'Hinweise aktiviert');
  assert.ok(
    !/blitzer|radar/i.test(ansagen[0]!),
    'Die Ansage beim Übertritt nach Frankreich benennt die Gefahr',
  );
});

// --- Die andere Richtung --------------------------------------------------

test('zurück nach Deutschland schaltet sofort ab, ohne Grenzabstand', () => {
  // Der Track wird umgedreht. Die Hysterese ist unsymmetrisch, und das muss
  // sich hier zeigen: Der Weg nach Frankreich braucht 389 m, der Weg zurück
  // keinen Meter. Anders herum hielte die App die Warnung in Deutschland noch
  // Hunderte Meter lang scharf.
  const hin = ladeTrack('grenze-kehl-strasbourg');
  const zurueck = [...hin].reverse().map((f, i) => ({ ...f, t: hin[0]!.t + i * 1000 }));

  const grenzIndex = datengrenze(zurueck, 'FR', 'DE');
  const { wechsel } = fahre(zurueck);

  // Startet in Frankreich: erst der Wechsel auf 'zone', dann zurück auf 'aus'.
  assert.equal(wechsel.length, 2, wechsel.map((w) => `${w.index}:${w.von}->${w.nach}`).join(', '));
  assert.equal(wechsel[1]!.nach, 'aus');
  assert.equal(
    wechsel[1]!.index, grenzIndex,
    'Das Abschalten muss auf demselben Fix greifen, auf dem die Daten Deutschland melden',
  );
});
