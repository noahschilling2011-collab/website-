import { test } from 'node:test';
import assert from 'node:assert/strict';

import { WATCHDOG, BATTERY } from '../src/config';
import {
  createWatchdogState, istTaskTot, meldeFix, pruefe, starte, status, statuszeile, stoppe,
} from '../src/location/watchdog';
import {
  aktualisiere, bestimmeModus, createStrategyState, vorgabeFuer,
} from '../src/location/strategy';

const T0 = 1_700_000_000_000;

// --- Watchdog -------------------------------------------------------------

test('bei ausgeschaltetem Tracking gibt es keinen Alarm', () => {
  const s = createWatchdogState();
  assert.equal(istTaskTot(s, T0 + 10 * 60_000), false);
  assert.equal(status(s, T0), 'aus');
});

test('frisch gestartet ist nicht tot, obwohl noch kein Fix da ist', () => {
  // Ein GPS-Fix kann in der Garage Minuten dauern. Würde die Zeit seit dem
  // letzten Fix zählen, schlüge der Alarm sofort beim Losfahren an.
  const s = createWatchdogState();
  starte(s, T0);
  assert.equal(istTaskTot(s, T0 + 1000), false);
  assert.equal(istTaskTot(s, T0 + WATCHDOG.STALE_AFTER_MS - 1), false);
});

test('ohne ersten Fix schlägt der Alarm nach der Frist doch an', () => {
  // Wenn nach 90 s noch kein einziger Fix kam, ist etwas kaputt — dann darf
  // die Anlaufphase nicht ewig entschuldigen.
  const s = createWatchdogState();
  starte(s, T0);
  assert.equal(istTaskTot(s, T0 + WATCHDOG.STALE_AFTER_MS + 1), true);
});

test('nach einem Fix zählt die Zeit ab diesem Fix', () => {
  const s = createWatchdogState();
  starte(s, T0);
  meldeFix(s, T0 + 60_000);
  assert.equal(istTaskTot(s, T0 + 60_000 + WATCHDOG.STALE_AFTER_MS - 1), false);
  assert.equal(istTaskTot(s, T0 + 60_000 + WATCHDOG.STALE_AFTER_MS + 1), true);
});

test('Alarm kommt genau einmal pro Ausfall', () => {
  // Dauerpiepen würde dazu führen, dass der Nutzer die App abschaltet —
  // damit hätte der Watchdog das Gegenteil seines Zwecks erreicht.
  const s = createWatchdogState();
  starte(s, T0);
  const tot = T0 + WATCHDOG.STALE_AFTER_MS + 1;

  assert.equal(pruefe(s, tot).alarmAusloesen, true, 'erster Alarm');
  assert.equal(pruefe(s, tot + 30_000).alarmAusloesen, false, 'kein zweiter');
  assert.equal(pruefe(s, tot + 60_000).alarmAusloesen, false);
});

test('nach Erholung ist der nächste Ausfall wieder ein Alarm', () => {
  const s = createWatchdogState();
  starte(s, T0);
  const tot = T0 + WATCHDOG.STALE_AFTER_MS + 1;
  assert.equal(pruefe(s, tot).alarmAusloesen, true);

  meldeFix(s, tot + 1000);
  assert.equal(pruefe(s, tot + 2000).status, 'lebendig');

  const wiederTot = tot + 1000 + WATCHDOG.STALE_AFTER_MS + 1;
  assert.equal(pruefe(s, wiederTot).alarmAusloesen, true, 'zweiter Ausfall muss alarmieren');
});

test('stoppe setzt zurück und beendet die Überwachung', () => {
  const s = createWatchdogState();
  starte(s, T0);
  meldeFix(s, T0 + 1000);
  stoppe(s);
  assert.equal(status(s, T0 + 10 * 60_000), 'aus');
  assert.equal(pruefe(s, T0 + 10 * 60_000).alarmAusloesen, false);
});

test('Statuszeile liefert die Zahlen für den Fahrt-Screen', () => {
  const s = createWatchdogState();
  starte(s, T0);
  meldeFix(s, T0 + 14 * 60_000);
  const z = statuszeile(s, T0 + 14 * 60_000 + 2000);
  assert.equal(z.aktivSeitMin, 14);
  assert.equal(z.letzterFixVorSek, 2);
  assert.equal(z.status, 'lebendig');
});

// --- Akku-Strategie -------------------------------------------------------

test('ohne Kamera in der Nähe: Leerlauf', () => {
  const s = createStrategyState();
  assert.equal(bestimmeModus(s, 5000, 25, T0), 'leerlauf');
  assert.equal(bestimmeModus(s, null, 25, T0), 'leerlauf');
});

test('Kamera in Reichweite: Annäherung mit hoher Genauigkeit', () => {
  const s = createStrategyState();
  assert.equal(bestimmeModus(s, 1500, 25, T0), 'annaeherung');
  assert.equal(vorgabeFuer('annaeherung').genauigkeit, 'high');
  assert.equal(vorgabeFuer('leerlauf').genauigkeit, 'balanced');
});

test('kurzes Langsamfahren drosselt noch nicht', () => {
  const s = createStrategyState();
  assert.equal(bestimmeModus(s, 5000, 1, T0), 'leerlauf');
  assert.equal(bestimmeModus(s, 5000, 1, T0 + 60_000), 'leerlauf', 'erst nach 3 min');
});

test('langes Stehen drosselt auf geparkt', () => {
  const s = createStrategyState();
  bestimmeModus(s, 5000, 1, T0);
  const modus = bestimmeModus(s, 5000, 1, T0 + BATTERY.PARKED_AFTER_MS + 1000);
  assert.equal(modus, 'geparkt');
  assert.equal(vorgabeFuer('geparkt').distanceIntervalM, BATTERY.PARKED_DISTANCE_INTERVAL_M);
});

test('Stau direkt vor der Kamera drosselt NICHT', () => {
  // Der wichtige Fall: Wer 200 m vor der Kamera im Stau steht, muss die
  // Warnung noch bekommen. Würde hier gedrosselt, käme sie zu spät oder nie.
  const s = createStrategyState();
  bestimmeModus(s, 200, 0, T0);
  const modus = bestimmeModus(s, 200, 0, T0 + BATTERY.PARKED_AFTER_MS + 1000);
  assert.equal(modus, 'annaeherung', 'nahe Kamera schlägt geparkt');
});

test('Weiterfahren beendet den geparkten Zustand', () => {
  const s = createStrategyState();
  bestimmeModus(s, 5000, 0, T0);
  assert.equal(bestimmeModus(s, 5000, 0, T0 + BATTERY.PARKED_AFTER_MS + 1000), 'geparkt');
  assert.equal(bestimmeModus(s, 5000, 20, T0 + BATTERY.PARKED_AFTER_MS + 2000), 'leerlauf');
});

test('aktualisiere meldet nur echte Moduswechsel', () => {
  // Jede Neukonfiguration des Location-Providers kostet Strom, deshalb darf
  // sie nicht bei jedem Update passieren.
  const s = createStrategyState();
  assert.equal(aktualisiere(s, 5000, 25, T0).geaendert, false, 'startet im Leerlauf');
  assert.equal(aktualisiere(s, 1500, 25, T0 + 1000).geaendert, true, 'Wechsel zu Annäherung');
  assert.equal(aktualisiere(s, 1400, 25, T0 + 2000).geaendert, false, 'bleibt Annäherung');
  assert.equal(aktualisiere(s, 1300, 25, T0 + 3000).geaendert, false);
  assert.equal(aktualisiere(s, 9000, 25, T0 + 4000).geaendert, true, 'zurück in den Leerlauf');
});

test('null-Geschwindigkeit wird als Stillstand behandelt', () => {
  const s = createStrategyState();
  bestimmeModus(s, 5000, null, T0);
  assert.equal(bestimmeModus(s, 5000, null, T0 + BATTERY.PARKED_AFTER_MS + 1), 'geparkt');
});
