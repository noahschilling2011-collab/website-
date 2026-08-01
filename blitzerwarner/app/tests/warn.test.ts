/**
 * Unit-Tests der Warnlogik.
 *
 * Der Replay-Test prüft ganze Fahrten. Hier stehen die Einzelentscheidungen,
 * damit bei einem Fehlschlag klar ist, WELCHE Regel gebrochen ist.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { WARN } from '../src/config';
import { cellKey } from '../src/core/geo';
import {
  cameraKey,
  courseIsReliable,
  createTripState,
  distanceToNearest,
  evaluate,
  warnDistance,
} from '../src/core/warn';
import type { Camera, Fix } from '../src/types';

const kamera = (lat: number, lon: number, extra: Partial<Camera> = {}): Camera => ({
  lat, lon, dir: null, max: null, type: 'speed', ...extra,
});

const grid = (...kameras: Camera[]): Record<string, Camera[]> => {
  const g: Record<string, Camera[]> = {};
  for (const k of kameras) (g[cellKey(k.lat, k.lon)] ??= []).push(k);
  return g;
};

const fix = (extra: Partial<Fix> = {}): Fix => ({
  lat: 48.7712, lon: 9.1834, course: 90, speed: 27.8, accuracy: 5, t: 1_000_000, ...extra,
});

const SETTINGS = { rotlichtblitzer: true, warnDistanceFactor: 1 };

// --- Warndistanz ----------------------------------------------------------

test('warnDistance: Untergrenze greift bei niedrigem Tempo', () => {
  // 20 m/s * 12 = 240, liegt unter dem Minimum von 300.
  assert.equal(warnDistance(20), WARN.MIN_DISTANCE_M);
});

test('warnDistance: linear oberhalb der Untergrenze', () => {
  assert.ok(Math.abs(warnDistance(27.8) - 333.6) < 1, '100 km/h');
  assert.ok(Math.abs(warnDistance(44.4) - 532.8) < 1, '160 km/h');
});

test('warnDistance: bei unzuverlässigem Kurs verkürzt', () => {
  // Unter 5 m/s ist der GPS-Kurs unbrauchbar. Dann wird der
  // Richtungsfilter abgeschaltet — deshalb darf nur noch auf kurze
  // Distanz gewarnt werden, sonst warnt die App im Stand in alle Richtungen.
  assert.equal(warnDistance(2), WARN.SLOW_SPEED_DISTANCE_M);
  assert.ok(warnDistance(2) < warnDistance(27.8));
});

test('warnDistance: Nutzerfaktor wirkt', () => {
  assert.equal(warnDistance(27.8, 2), warnDistance(27.8) * 2);
});

test('warnDistance: null-Geschwindigkeit gilt als langsam', () => {
  assert.equal(warnDistance(null), WARN.SLOW_SPEED_DISTANCE_M);
});

// --- Kursgüte -------------------------------------------------------------

test('courseIsReliable', () => {
  assert.equal(courseIsReliable(27.8, 90), true);
  assert.equal(courseIsReliable(2, 90), false, 'zu langsam');
  assert.equal(courseIsReliable(27.8, null), false, 'kein Kurs');
  assert.equal(courseIsReliable(null, 90), false);
});

// --- Filter ---------------------------------------------------------------

test('Kamera voraus löst aus', () => {
  const k = kamera(48.7712, 9.1874); // rund 294 m östlich
  const erg = evaluate(fix(), grid(k), createTripState(), SETTINGS, true);
  assert.ok(erg.warning, 'hätte warnen müssen');
  assert.ok(erg.warning!.distance < 340);
});

test('Kamera hinter uns wird verworfen', () => {
  const k = kamera(48.7712, 9.1794); // westlich, wir fahren nach Osten
  const erg = evaluate(fix(), grid(k), createTripState(), SETTINGS, true);
  assert.equal(erg.warning, null);
  assert.ok(erg.skipped!.some((s) => s.reason === 'nicht_voraus'));
});

test('Kamera der Gegenrichtung wird verworfen', () => {
  const k = kamera(48.7712, 9.1874, { dir: 270 });
  const erg = evaluate(fix(), grid(k), createTripState(), SETTINGS, true);
  assert.equal(erg.warning, null);
  assert.ok(erg.skipped!.some((s) => s.reason === 'gegenrichtung'));
});

test('Kamera OHNE Richtungsangabe warnt — das ist der häufige Fall', () => {
  // 64 % der Anlagen im Datensatz haben keine Richtung. Würden die
  // verworfen, wäre die App fast nutzlos. Im Zweifel warnen.
  const k = kamera(48.7712, 9.1874, { dir: null });
  const erg = evaluate(fix(), grid(k), createTripState(), SETTINGS);
  assert.ok(erg.warning, 'Kamera ohne Richtung darf nicht verworfen werden');
});

test('Richtungsfilter ist bei langsamer Fahrt abgeschaltet', () => {
  // Kamera zeigt nach Westen, wir stehen fast. Der GPS-Kurs ist dann
  // unbrauchbar, also darf die Richtung nicht zum Verwerfen führen.
  const k = kamera(48.7712, 9.1841, { dir: 270 }); // rund 51 m entfernt
  const erg = evaluate(fix({ speed: 1 }), grid(k), createTripState(), SETTINGS, true);
  assert.ok(erg.warning, 'bei unzuverlässigem Kurs darf nicht gefiltert werden');
});

test('zu weit entfernte Kamera wird verworfen', () => {
  const k = kamera(48.7712, 9.1934); // rund 735 m
  const erg = evaluate(fix(), grid(k), createTripState(), SETTINGS, true);
  assert.equal(erg.warning, null);
  assert.ok(erg.skipped!.some((s) => s.reason === 'zu_weit'));
});

test('Rotlichtblitzer abschaltbar, Tempoblitzer nicht betroffen', () => {
  const rot = kamera(48.7712, 9.1874, { type: 'red_light' });
  const aus = { rotlichtblitzer: false, warnDistanceFactor: 1 };

  const erg1 = evaluate(fix(), grid(rot), createTripState(), aus, true);
  assert.equal(erg1.warning, null);
  assert.ok(erg1.skipped!.some((s) => s.reason === 'typ_abgeschaltet'));

  const tempo = kamera(48.7712, 9.1874, { type: 'speed' });
  const erg2 = evaluate(fix(), grid(tempo), createTripState(), aus);
  assert.ok(erg2.warning, 'Tempoblitzer muss weiter warnen');
});

test('kombinierte Anlage warnt auch bei abgeschaltetem Rotlicht', () => {
  // type=both ist auch ein Tempoblitzer. Wer Rotlicht abschaltet, will
  // trotzdem vor der Geschwindigkeitsmessung gewarnt werden.
  const k = kamera(48.7712, 9.1874, { type: 'both' });
  const erg = evaluate(fix(), grid(k), createTripState(), { rotlichtblitzer: false, warnDistanceFactor: 1 });
  assert.ok(erg.warning);
});

// --- Anti-Doppelwarnung ---------------------------------------------------

test('dieselbe Kamera warnt nicht zweimal', () => {
  const k = kamera(48.7712, 9.1874);
  const g = grid(k);
  const state = createTripState();

  assert.ok(evaluate(fix(), g, state, SETTINGS).warning, 'erste Warnung');
  assert.equal(evaluate(fix(), g, state, SETTINGS).warning, null, 'keine zweite');
});

test('Kamera wird nach ausreichender Entfernung wieder scharf', () => {
  // Sonst würde eine Kamera, an der man zweimal vorbeifährt (Rundfahrt,
  // Wendemanöver), beim zweiten Mal stumm bleiben.
  const k = kamera(48.7712, 9.1874);
  const g = grid(k);
  const state = createTripState();

  assert.ok(evaluate(fix(), g, state, SETTINGS).warning);

  // Weit weg fahren: über 2x Warndistanz, damit die Kamera wieder scharf wird.
  // Der Zwischenschritt ist nötig, weil die Scharfschaltung beim Auswerten
  // einer Position passiert.
  //
  // Die Zeit läuft dabei mit. Sie tat es früher nicht — alle drei Positionen
  // trugen denselben Zeitstempel, obwohl zwischen ihnen 1,6 km liegen. Das
  // fiel erst auf, als WARN.MIN_ANSAGE_ABSTAND_MS dazukam: Eine Rundfahrt in
  // null Sekunden gibt es nicht, und ein Test, der sie unterstellt, prüft
  // nebenbei etwas Falsches mit.
  const T0 = 1_000_000;
  const weit = fix({ lon: 9.2034, t: T0 + 60_000 });
  evaluate(weit, g, state, SETTINGS);
  assert.equal(state.gewarnt.get(cameraKey(k))?.wiederScharf, true);

  assert.ok(
    evaluate(fix({ t: T0 + 120_000 }), g, state, SETTINGS).warning,
    'zweite Vorbeifahrt muss warnen',
  );
});

// --- Nächste Kamera für die Akku-Strategie --------------------------------

test('distanceToNearest ignoriert Richtung und Warnstatus', () => {
  const k = kamera(48.7712, 9.1794, { dir: 270 }); // hinter uns, Gegenrichtung
  const d = distanceToNearest({ lat: 48.7712, lon: 9.1834 }, grid(k));
  assert.ok(d != null && d > 250 && d < 350, `unerwartete Distanz: ${d}`);
});

test('distanceToNearest liefert null ohne Kameras', () => {
  assert.equal(distanceToNearest({ lat: 48.7712, lon: 9.1834 }, {}), null);
});

// --- mehrere Kameras ------------------------------------------------------

test('von zwei Kandidaten gewinnt der nähere', () => {
  const nah = kamera(48.7712, 9.1854, { max: 50 });
  const fern = kamera(48.7712, 9.1874, { max: 80 });
  const erg = evaluate(fix(), grid(nah, fern), createTripState(), SETTINGS);
  assert.equal(erg.warning?.camera.max, 50);
});
