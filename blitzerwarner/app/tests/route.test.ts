import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AUDIO } from '../src/config';
import {
  KEINE_ERKENNUNG,
  aufwachPauseMs,
  brauchtAufwachPause,
  deutetAufFahrerbedienung,
  lautstaerkeFaktor,
  wechselAnsagen,
  type Route,
} from '../src/audio/route';

const ALLE: Route[] = [
  'carplay', 'bluetooth_auto', 'bluetooth_headset', 'kabel', 'lautsprecher', 'unbekannt',
];

test('CarPlay deutet auf Fahrerbedienung, nichts anderes', () => {
  // Der rechtlich entscheidende Punkt: CarPlay ist der eingebaute
  // Fahrzeugbildschirm. Ein Helm-Headset sagt über die Bedienung nichts aus.
  assert.equal(deutetAufFahrerbedienung('carplay'), true);
  for (const r of ALLE.filter((x) => x !== 'carplay')) {
    assert.equal(deutetAufFahrerbedienung(r), false, r);
  }
});

test('Lautstärkefaktor liegt für jede Route im gültigen Bereich', () => {
  for (const r of ALLE) {
    for (const motorrad of [false, true]) {
      const f = lautstaerkeFaktor(r, motorrad);
      assert.ok(f > 0 && f <= 1, `${r}/${motorrad}: ${f}`);
    }
  }
});

test('Motorradmodus dämpft nie', () => {
  // Fahrtwind übertönt alles. Wer den Modus einschaltet, braucht die volle
  // Aussteuerung, egal was die Erkennung meldet.
  for (const r of ALLE) {
    assert.equal(lautstaerkeFaktor(r, true), 1, r);
  }
});

test('Autoanlage wird gedämpft, Telefonlautsprecher nicht', () => {
  assert.ok(lautstaerkeFaktor('carplay', false) < 1);
  assert.ok(lautstaerkeFaktor('bluetooth_auto', false) < 1);
  assert.equal(lautstaerkeFaktor('lautsprecher', false), 1, 'schwächster Weg, volle Leistung');
});

test('Aufwach-Pause nur bei Bluetooth-artigen Routen', () => {
  // Bluetooth-Geräte schlafen nach Sekunden Stille ein; ohne Pause fehlen
  // die ersten Silben.
  assert.equal(brauchtAufwachPause('carplay'), true);
  assert.equal(brauchtAufwachPause('bluetooth_headset'), true);
  assert.equal(brauchtAufwachPause('bluetooth_auto'), true);
  assert.equal(brauchtAufwachPause('kabel'), false);
  assert.equal(brauchtAufwachPause('lautsprecher'), false);
});

test('bei unbekannter Route wird gewartet', () => {
  // Eine überflüssige Pause ist harmlos, eine fehlende kostet die Warnung.
  assert.equal(brauchtAufwachPause('unbekannt'), true);
  assert.equal(aufwachPauseMs('unbekannt'), AUDIO.WAKEUP_DELAY_MS);
  assert.equal(aufwachPauseMs('kabel'), 0);
});

test('Verschlechterung wird angesagt, Verbesserung nicht', () => {
  // Wer mitten in der Fahrt das Headset verliert, muss es erfahren — sonst
  // verlässt er sich auf eine Warnung, die er nicht mehr hört.
  assert.equal(wechselAnsagen('bluetooth_headset', 'lautsprecher'), true);
  assert.equal(wechselAnsagen('carplay', 'lautsprecher'), true);
  assert.equal(wechselAnsagen('carplay', 'kabel'), true);

  assert.equal(wechselAnsagen('lautsprecher', 'carplay'), false, 'merkt man selbst');
  assert.equal(wechselAnsagen('kabel', 'bluetooth_auto'), false);
});

test('kein Wechsel und kein Erststart werden angesagt', () => {
  for (const r of ALLE) {
    assert.equal(wechselAnsagen(r, r), false, `${r} auf sich selbst`);
  }
  // Beim ersten Start ist die vorherige Route unbekannt — das ist kein
  // Wechsel und darf nicht angesagt werden.
  for (const r of ALLE) {
    assert.equal(wechselAnsagen('unbekannt', r), false, `unbekannt auf ${r}`);
  }
});

test('Platzhalter-Erkennung meldet unbekannt und keine Wechsel', () => {
  // Solange kein natives Modul eingebunden ist, darf nichts vorgetäuscht
  // werden. Der Platzhalter muss ausserdem eine funktionierende
  // Abmeldefunktion liefern, sonst leckt jeder Aufrufer einen Listener.
  assert.equal(KEINE_ERKENNUNG.aktuelleRoute(), 'unbekannt');
  let gerufen = 0;
  const ab = KEINE_ERKENNUNG.beiWechsel(() => { gerufen++; });
  assert.equal(typeof ab, 'function');
  ab();
  assert.equal(gerufen, 0);
});
