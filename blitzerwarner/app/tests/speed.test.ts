/**
 * Tests für den Tacho, Spec Abschnitt 8a.
 *
 * Die Schwellwerte kommen aus config.ts statt als Zahlen im Test zu stehen —
 * sonst prüft der Test irgendwann etwas anderes als die App tut. Nur dort,
 * wo die Zahl selbst die Aussage ist (kmh-Rundung), steht sie ausgeschrieben.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { SPEEDOMETER, SPEEDO_TOLERANCE } from '../src/config.js';
import type { Settings } from '../src/types.js';
import {
  createSpeedState,
  istKalibriert,
  kalibrierfaktor,
  kmhFromMs,
  readSpeed,
  Speedometer,
  TACHO_FAKTOR_NEUTRAL,
  tachoAnzeigePlausibel,
  updateSpeed,
  zulaessigeTachoSpanne,
} from '../src/core/speed.js';

const T0 = 1_700_000_000_000;

/** Einstellungen ohne Kalibrierung. */
const OHNE_KALIBRIERUNG: Pick<Settings, 'tachoFaktor'> = { tachoFaktor: TACHO_FAKTOR_NEUTRAL };

/** Genauigkeit, die sicher als gut gilt. */
const GUT_M = SPEEDOMETER.MAX_ACCURACY_M - 1;
/** Genauigkeit, die sicher als schlecht gilt. */
const SCHLECHT_M = SPEEDOMETER.MAX_ACCURACY_M + 1;

function nahe(ist: number | null, soll: number, toleranz = 1e-9): void {
  assert.notEqual(ist, null, 'Wert fehlt');
  assert.ok(
    ist != null && Math.abs(ist - soll) < toleranz,
    `${String(ist)} weicht von ${soll} ab`,
  );
}

// --- Glättung -------------------------------------------------------------

test('Glättung: der erste Wert wird direkt übernommen, ohne Anlauf von 0', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  nahe(r.ms, 20);
  assert.equal(r.kmh, 72, '20 m/s sind 72 km/h');
  assert.equal(r.quality, 'ok');
  assert.equal(r.gehalten, false);
});

test('Glättung: ein Sprung wird gedämpft, nicht durchgereicht', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  const r = updateSpeed(s, { speed: 30, accuracy: GUT_M, t: T0 + 1000 }, OHNE_KALIBRIERUNG);

  assert.ok(r.ms != null && r.ms > 20, 'bewegt sich in Richtung des neuen Wertes');
  assert.ok(r.ms != null && r.ms < 30, 'erreicht ihn aber nicht in einem Schritt');
  nahe(r.ms, SPEEDOMETER.EMA_ALPHA * 30 + (1 - SPEEDOMETER.EMA_ALPHA) * 20);
});

test('Glättung: konvergiert bei konstanter Eingabe gegen den Messwert', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 0, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  let letzte = 0;
  for (let i = 1; i <= 20; i++) {
    const r = updateSpeed(s, { speed: 25, accuracy: GUT_M, t: T0 + i * 1000 }, OHNE_KALIBRIERUNG);
    assert.ok(r.ms != null && r.ms > letzte, 'nähert sich monoton an');
    letzte = r.ms ?? 0;
  }
  nahe(letzte, 25, 0.01);
});

test('Glättung: Anzeige in ganzen km/h ohne Nachkommastellen', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 13.9, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  assert.equal(r.kmh, 50, '13,9 m/s sind 50,04 km/h');
  assert.equal(Number.isInteger(r.kmh), true);
  assert.equal(kmhFromMs(27.78), 100);
});

test('Glättung: nach einer Lücke länger als die Haltezeit wird neu aufgesetzt', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 36, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  // Erst nach Ablauf der Haltezeit kommt wieder ein Fix. Der alte Wert darf
  // nicht mehr eingerechnet werden — sonst zeigte der Tacho beim Anfahren
  // aus dem Stand plötzlich die Autobahngeschwindigkeit von vorhin.
  const spaeter = T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS + 60_000;
  const r = updateSpeed(s, { speed: 5, accuracy: GUT_M, t: spaeter }, OHNE_KALIBRIERUNG);
  nahe(r.ms, 5);
});

// --- Halten und unbekannt -------------------------------------------------

test('Halten: speed null hält den letzten gültigen Wert', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  const r = updateSpeed(s, { speed: null, accuracy: GUT_M, t: T0 + 1000 }, OHNE_KALIBRIERUNG);

  assert.equal(r.kmh, 72, 'der gehaltene Wert bleibt stehen');
  assert.equal(r.gehalten, true);
  assert.equal(r.quality, 'ok', 'die Güte des letzten gültigen Fixes bleibt erhalten');
  assert.equal(r.alterMs, 1000);
});

test('Halten: ohne je einen gültigen Wert bleibt es unbekannt, nicht 0', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: null, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  assert.equal(r.quality, 'unbekannt');
  assert.equal(r.kmh, null, 'unbekannt wird niemals als 0 angezeigt');
  assert.equal(r.ms, null);
  assert.equal(r.tachoKmh, null);
});

test('Halten: kurz vor Ablauf der Haltezeit steht der Wert noch', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  const r = readSpeed(s, T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS - 1, OHNE_KALIBRIERUNG);
  assert.equal(r.kmh, 72);
  assert.equal(r.quality, 'ok');
});

test('Halten: mit Ablauf der Haltezeit wird auf unbekannt umgeschaltet', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  const r = readSpeed(s, T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS, OHNE_KALIBRIERUNG);
  assert.equal(r.quality, 'unbekannt');
  assert.equal(r.kmh, null, 'nach Ablauf keine Zahl, schon gar nicht 0');
  assert.equal(r.alterMs, null);
});

test('Halten: der Ablauf greift auch ohne neuen Fix', () => {
  // Der wichtige Fall: Das GPS schweigt komplett, es kommt gar kein Update
  // mehr, mit dem man den Ablauf bemerken könnte. Die UI liest im Takt.
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  assert.equal(readSpeed(s, T0 + 500, OHNE_KALIBRIERUNG).kmh, 72);
  assert.equal(
    readSpeed(s, T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS + 1, OHNE_KALIBRIERUNG).quality,
    'unbekannt',
  );
});

test('Halten: ein ungültiger Fix nach Ablauf der Haltezeit meldet unbekannt', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  const r = updateSpeed(
    s,
    { speed: null, accuracy: GUT_M, t: T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS },
    OHNE_KALIBRIERUNG,
  );

  assert.equal(r.quality, 'unbekannt');
  assert.equal(r.kmh, null);
});

test('Halten: nach dem Ablauf setzt der nächste gültige Fix wieder auf', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  readSpeed(s, T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS, OHNE_KALIBRIERUNG);

  const r = updateSpeed(
    s,
    { speed: 10, accuracy: GUT_M, t: T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS + 100 },
    OHNE_KALIBRIERUNG,
  );
  nahe(r.ms, 10, 1e-9);
  assert.equal(r.gehalten, false);
});

test('Halten: ein gemessener Stillstand zeigt 0 und nicht unbekannt', () => {
  // Der Unterschied, um den es geht: 0 ist eine Aussage, unbekannt ist keine.
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 0, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  assert.equal(r.kmh, 0);
  assert.equal(r.quality, 'ok');
});

// --- Negative und kaputte Werte -------------------------------------------

test('Negative Werte: -1 gilt als unbekannt, nicht als Stillstand', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 25, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  const r = updateSpeed(s, { speed: -1, accuracy: GUT_M, t: T0 + 1000 }, OHNE_KALIBRIERUNG);

  assert.equal(r.kmh, 90, 'der letzte gültige Wert wird gehalten');
  assert.equal(r.gehalten, true);
});

test('Negative Werte: fliessen nicht in die Glättung ein', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  updateSpeed(s, { speed: -1, accuracy: GUT_M, t: T0 + 1000 }, OHNE_KALIBRIERUNG);
  const r = updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 + 2000 }, OHNE_KALIBRIERUNG);

  nahe(r.ms, 20, 1e-9);
});

test('Negative Werte: NaN wird wie unbekannt behandelt', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: Number.NaN, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  assert.equal(r.quality, 'unbekannt');
  assert.equal(r.kmh, null);
});

// --- Genauigkeit ----------------------------------------------------------

test('Genauigkeit: über der Schwelle gilt der Wert als unsicher', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 20, accuracy: SCHLECHT_M, t: T0 }, OHNE_KALIBRIERUNG);

  assert.equal(r.quality, 'unsicher');
  assert.equal(r.kmh, 72, 'der Wert wird trotzdem geliefert, nur ausgegraut');
});

test('Genauigkeit: genau auf der Schwelle ist noch in Ordnung', () => {
  const s = createSpeedState();
  const r = updateSpeed(
    s,
    { speed: 20, accuracy: SPEEDOMETER.MAX_ACCURACY_M, t: T0 },
    OHNE_KALIBRIERUNG,
  );
  assert.equal(r.quality, 'ok');
});

test('Genauigkeit: fehlende Angabe gilt als unsicher', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 20, accuracy: null, t: T0 }, OHNE_KALIBRIERUNG);
  assert.equal(r.quality, 'unsicher');
  assert.equal(r.kmh, 72);
});

test('Genauigkeit: die Güte folgt dem jeweils letzten Fix in beide Richtungen', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  const schlecht = updateSpeed(
    s,
    { speed: 20, accuracy: SCHLECHT_M, t: T0 + 1000 },
    OHNE_KALIBRIERUNG,
  );
  assert.equal(schlecht.quality, 'unsicher');

  const wiederGut = updateSpeed(
    s,
    { speed: 20, accuracy: GUT_M, t: T0 + 2000 },
    OHNE_KALIBRIERUNG,
  );
  assert.equal(wiederGut.quality, 'ok');
});

// --- Kalibrierung ---------------------------------------------------------

test('Kalibrierung: der Faktor wird auf die Tacho-Anzeige angewendet', () => {
  const s = createSpeedState();
  // 27,78 m/s sind rund 100 km/h. Ein Tacho mit Faktor 1,05 zeigt 105.
  const r = updateSpeed(s, { speed: 27.78, accuracy: GUT_M, t: T0 }, { tachoFaktor: 1.05 });

  assert.equal(r.kmh, 100, 'die echte Geschwindigkeit bleibt unverändert');
  assert.equal(r.tachoKmh, 105);
});

test('Kalibrierung: ohne Kalibrierung ist die Tacho-Anzeige gleich der echten', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 27.78, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);

  assert.equal(r.tachoKmh, r.kmh);
  assert.equal(istKalibriert(OHNE_KALIBRIERUNG), false);
  assert.equal(istKalibriert({ tachoFaktor: 1.05 }), true);
});

test('Kalibrierung: ein kaputter gespeicherter Faktor legt den Tacho nicht lahm', () => {
  const s = createSpeedState();
  const r = updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, { tachoFaktor: 0 });
  assert.equal(r.kmh, 72);
  assert.equal(r.tachoKmh, 72, 'Faktor 0 fällt auf nicht kalibriert zurück');

  const s2 = createSpeedState();
  const r2 = updateSpeed(s2, { speed: 20, accuracy: GUT_M, t: T0 }, { tachoFaktor: Number.NaN });
  assert.equal(r2.tachoKmh, 72);
  assert.equal(istKalibriert({ tachoFaktor: Number.NaN }), false);
});

test('Kalibrierung: der Faktor entsteht aus echt und abgelesen', () => {
  nahe(kalibrierfaktor(100, 105), 1.05, 1e-12);
  nahe(kalibrierfaktor(50, 50), 1, 1e-12);
  nahe(kalibrierfaktor(80, 88), 1.1, 1e-12);
});

test('Kalibrierung: unbrauchbare Eingaben ergeben null statt einer geratenen Zahl', () => {
  assert.equal(kalibrierfaktor(0, 100), null);
  assert.equal(kalibrierfaktor(100, 0), null);
  assert.equal(kalibrierfaktor(-10, 100), null);
  assert.equal(kalibrierfaktor(100, Number.NaN), null);
});

test('Kalibrierung: gemessener Faktor und Anzeige greifen ineinander', () => {
  const faktor = kalibrierfaktor(100, 105);
  assert.notEqual(faktor, null);

  const s = createSpeedState();
  const r = updateSpeed(
    s,
    { speed: 100 / 3.6, accuracy: GUT_M, t: T0 },
    { tachoFaktor: faktor ?? TACHO_FAKTOR_NEUTRAL },
  );
  assert.equal(r.kmh, 100);
  assert.equal(r.tachoKmh, 105);
});

// --- Erklär-Screen --------------------------------------------------------

test('Toleranz: die zulässige Anzeigespanne folgt der Formel aus config', () => {
  const spanne = zulaessigeTachoSpanne(100);
  assert.notEqual(spanne, null);
  nahe(spanne?.minKmh ?? null, 100);
  nahe(spanne?.maxKmh ?? null, 100 * (1 + SPEEDO_TOLERANCE.FACTOR) + SPEEDO_TOLERANCE.OFFSET_KMH);
});

test('Toleranz: die Untergrenze ist die echte Geschwindigkeit', () => {
  // Ein Tacho darf nach der Regelung nie weniger anzeigen als gefahren wird.
  for (const v of [0, 30, 50, 130]) {
    const spanne = zulaessigeTachoSpanne(v);
    assert.equal(spanne?.minKmh, v);
    assert.ok((spanne?.maxKmh ?? 0) > v || v === 0);
  }
});

test('Toleranz: unbrauchbare Eingabe ergibt null', () => {
  assert.equal(zulaessigeTachoSpanne(-1), null);
  assert.equal(zulaessigeTachoSpanne(Number.NaN), null);
});

test('Toleranz: Plausibilität einer Ablesung', () => {
  assert.equal(tachoAnzeigePlausibel(100, 105), true);
  assert.equal(tachoAnzeigePlausibel(100, 100), true, 'Untergrenze eingeschlossen');
  assert.equal(tachoAnzeigePlausibel(100, 114), true, 'Obergrenze eingeschlossen');
  assert.equal(tachoAnzeigePlausibel(100, 95), false, 'darf nicht weniger anzeigen');
  assert.equal(tachoAnzeigePlausibel(100, 150), false, 'vermutlich ein Tippfehler');
  assert.equal(tachoAnzeigePlausibel(Number.NaN, 100), false);
});

// --- Hülle ----------------------------------------------------------------

test('Speedometer: die Hülle verhält sich wie die Funktionen', () => {
  const tacho = new Speedometer();
  assert.equal(tacho.read(T0).quality, 'unbekannt');

  assert.equal(tacho.update({ speed: 20, accuracy: GUT_M, t: T0 }).kmh, 72);
  assert.equal(tacho.read(T0 + 1000).kmh, 72);
  assert.equal(tacho.read(T0 + SPEEDOMETER.HOLD_LAST_VALUE_MS).kmh, null);
});

test('Speedometer: eine geänderte Kalibrierung wirkt sofort', () => {
  const tacho = new Speedometer();
  tacho.update({ speed: 27.78, accuracy: GUT_M, t: T0 });
  assert.equal(tacho.read(T0).tachoKmh, 100);

  tacho.setSettings({ tachoFaktor: 1.05 });
  assert.equal(tacho.read(T0).tachoKmh, 105, 'ohne dass ein neuer Fix nötig wäre');
});

// --- Zeitsprünge ----------------------------------------------------------

test('Zeit: ein Lesezeitpunkt vor dem Fix ergibt kein negatives Alter', () => {
  const s = createSpeedState();
  updateSpeed(s, { speed: 20, accuracy: GUT_M, t: T0 }, OHNE_KALIBRIERUNG);
  const r = readSpeed(s, T0 - 5000, OHNE_KALIBRIERUNG);

  assert.equal(r.alterMs, 0);
  assert.equal(r.kmh, 72);
});

test('Zustand: ein frischer Zustand meldet unbekannt', () => {
  const r = readSpeed(createSpeedState(), T0, OHNE_KALIBRIERUNG);
  assert.equal(r.quality, 'unbekannt');
  assert.equal(r.kmh, null);
  assert.equal(r.ms, null);
  assert.equal(r.tachoKmh, null);
  assert.equal(r.gehalten, false);
  assert.equal(r.alterMs, null);
});
