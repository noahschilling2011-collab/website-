/**
 * Der Zonendatensatz — und vor allem: was passiert, wenn er fehlt.
 *
 * Der Ausfall, gegen den diese Tests stehen, ist der lautlose: Die App meldet
 * den Zonenmodus, sagt "Hinweise aktiviert" und schweigt danach die ganze
 * Fahrt. Von aussen ist das nicht von einer Strecke ohne Zonen zu
 * unterscheiden. Deshalb wird hier nicht nur geprüft, dass das Laden klappt,
 * sondern auch, dass das Scheitern eine Spur hinterlässt.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { LAENDER_GATE, type LandCode } from '../src/config';
import {
  ZonenFehler,
  brauchtZonen,
  ladeZonen,
  sindZonenGeladen,
  vergisseZonen,
  zonenFehler,
  zonenOderNull,
} from '../src/core/zonendaten';

// --- Wer braucht überhaupt Zonen? -----------------------------------------

test('brauchtZonen folgt der Gate-Tabelle, nicht der Dateilage', () => {
  // Die Richtung ist entscheidend: Das Gate sagt, was gebraucht wird. Wäre es
  // umgekehrt — "wir haben eine Datei, also warnen wir" —, entschiede die
  // Anwesenheit einer Datei über die Rechtslage.
  for (const [code, eintrag] of Object.entries(LAENDER_GATE.LAENDER)) {
    const erwartet = eintrag.status === 'belegt' && eintrag.modus === 'zone';
    assert.equal(brauchtZonen(code as LandCode), erwartet, code);
  }
});

test('ohne bestimmtes Land werden keine Zonen gebraucht', () => {
  assert.equal(brauchtZonen(null), false);
});

test('Deutschland braucht keine Zonen, obwohl eine Datei existiert', () => {
  // scripts/build-zones.ts erzeugt auch cameras.DE.zones.json — als Prüfstück
  // für den Generator, nicht als Betriebsmittel. § 23 Abs. 1c StVO schaltet
  // Deutschland ab, und daran ändert eine vorhandene Datei nichts.
  assert.equal(brauchtZonen('DE'), false);
  assert.equal(LAENDER_GATE.LAENDER.DE.modus, 'aus');
});

// --- Laden ----------------------------------------------------------------

test('Frankreich lädt und ist plausibel', () => {
  vergisseZonen();
  const datensatz = ladeZonen('FR');

  assert.equal(datensatz.land, 'FR');
  assert.ok(datensatz.zones.length > 0, 'keine Zonen');
  assert.equal(datensatz.zones.length, datensatz.count);

  // Die Mindestlänge der französischen Regelung: 300 m innerorts, also 150 m
  // Radius. Alles darunter kann nur ein Fehler im Generator sein.
  for (const z of datensatz.zones) {
    assert.ok(z.r >= 150, `Radius ${z.r} m unter der Mindestlänge`);
  }
});

test('die Zonendatei verrät weiterhin keine Kameraposition', () => {
  // Doppelt geprüft — hier und in zone.test.ts. Diese Datei liegt jetzt im
  // App-Paket, also gilt die Auflage auch für das, was ausgeliefert wird.
  vergisseZonen();
  const datensatz = ladeZonen('FR');
  for (const z of datensatz.zones.slice(0, 50)) {
    const felder = Object.keys(z);
    assert.deepEqual(
      felder.sort(), ['lat', 'lon', 'r'],
      `Zone trägt zusätzliche Felder: ${felder.join(', ')}`,
    );
  }
});

test('zweimal laden liefert dasselbe Objekt, ohne erneut zu parsen', () => {
  vergisseZonen();
  const a = ladeZonen('FR');
  const b = ladeZonen('FR');
  assert.equal(a, b, 'jeder Aufruf parst neu — im Hintergrund-Task pro Fix');
});

// --- Das Scheitern --------------------------------------------------------

test('ein Land ohne Datei scheitert laut, nicht still', () => {
  vergisseZonen();
  // Spanien warnt im Punktmodus und hat deshalb keine Zonendatei. Würde
  // jemand den Gate-Eintrag auf 'zone' stellen, ohne die Datei zu bauen,
  // ist genau das der Fall, der hier auffallen muss.
  assert.throws(
    () => ladeZonen('ES'),
    (fehler: unknown) => {
      assert.ok(fehler instanceof ZonenFehler, 'kein ZonenFehler');
      assert.equal(fehler.grund, 'keine_datei');
      assert.equal(fehler.land, 'ES');
      return true;
    },
  );
});

test('zonenOderNull schluckt den Fehler, zonenFehler hebt ihn auf', () => {
  // Die Arbeitsteilung, auf die sich der Hintergrund-Task stützt: Er will
  // pro Fix keinen Wurf, aber er will den Grund genau einmal protokollieren
  // können.
  vergisseZonen();
  assert.equal(zonenFehler('ES'), null, 'vor dem ersten Versuch gibt es nichts zu melden');

  assert.equal(zonenOderNull('ES'), null);

  const fehler = zonenFehler('ES');
  assert.ok(fehler instanceof ZonenFehler, 'der Fehler wurde nicht gemerkt');
  assert.equal(fehler.grund, 'keine_datei');
});

test('ein gescheitertes Laden wird nicht wiederholt', () => {
  vergisseZonen();
  const erster = zonenOderNull('ES');
  assert.equal(erster, null);
  const gemerkt = zonenFehler('ES');

  zonenOderNull('ES');
  assert.equal(
    zonenFehler('ES'), gemerkt,
    'der zweite Versuch erzeugt einen neuen Fehler — das App-Paket ändert sich nicht',
  );
});

test('sindZonenGeladen unterscheidet die drei Zustände', () => {
  vergisseZonen();
  assert.equal(sindZonenGeladen('FR'), false, 'vor dem Laden');
  ladeZonen('FR');
  assert.equal(sindZonenGeladen('FR'), true, 'nach dem Laden');

  zonenOderNull('ES');
  assert.equal(sindZonenGeladen('ES'), false, 'nach einem Fehler');
});

// --- Die Kopplung an das Gate ---------------------------------------------

test('für JEDES Land im Zonenmodus liegen Zonendaten vor', () => {
  // Der Test, der die eigentliche Zusage hält. Ein Gate-Eintrag mit
  // modus 'zone' ohne Datei wäre eine App, die in diesem Land behauptet zu
  // warnen und es nicht tut. Kommt später Belgien oder Italien in den
  // Zonenmodus, schlägt dieser Test an, bevor jemand dort fährt.
  vergisseZonen();
  const fehlend: string[] = [];
  for (const code of Object.keys(LAENDER_GATE.LAENDER) as LandCode[]) {
    if (!brauchtZonen(code)) continue;
    if (zonenOderNull(code) === null) fehlend.push(code);
  }
  assert.deepEqual(
    fehlend, [],
    `Zonenmodus ohne Zonendaten: ${fehlend.join(', ')} — ` +
    'entweder die Datei bauen und in ROHDATEN eintragen, oder den Gate-Eintrag ändern',
  );
});
