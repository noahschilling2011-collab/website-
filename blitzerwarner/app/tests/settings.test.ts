/**
 * Die Migration der gespeicherten Einstellungen.
 *
 * Anlass: `tempolimitWarnung` ist aus `Settings` verschwunden, weil der
 * Schalter nichts tat. Auf jedem Gerät, das die App vorher benutzt hat, steht
 * das Feld aber noch im Speicher. Es darf weder das Laden verhindern noch als
 * Leiche im Settings-Objekt weiterreisen.
 *
 * Der Test läuft ohne AsyncStorage und ohne react-native: Standardwerte und
 * Migration liegen in core/settings.ts und sind reine Funktionen. Lägen sie
 * weiter im Store, wäre genau dieser Teil ungetestet geblieben — der Store
 * zieht zustand und AsyncStorage herein und ist unter `tsx --test` nicht
 * ladbar.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { STANDARD_SETTINGS, mischeSettings } from '../src/core/settings';

test('ein entferntes Feld wird verworfen und wirft nicht', () => {
  const alt = { ...STANDARD_SETTINGS, tempolimitWarnung: true, warnDistanceFactor: 1.5 };
  const neu = mischeSettings(alt);

  assert.equal(
    'tempolimitWarnung' in neu, false,
    'das entfernte Feld reist als Leiche weiter — der Typcheck sieht es nicht',
  );
  assert.equal(neu.warnDistanceFactor, 1.5, 'die übrigen Werte bleiben erhalten');
});

test('ein fehlendes Feld bekommt den Standardwert, nicht undefined', () => {
  // Der ältere Grund für das Mischen: Käme ein neues Feld dazu, wäre es in
  // gespeicherten Daten nicht enthalten und würde als "aus" gelesen — auch
  // dort, wo "ein" der richtige Standard ist. sprachansage ist so ein Fall.
  const neu = mischeSettings({ warnDistanceFactor: 2 });
  assert.equal(neu.sprachansage, STANDARD_SETTINGS.sprachansage);
  assert.equal(neu.sprachansage, true, 'der Standard ist ein, nicht aus');
  assert.equal(neu.warnDistanceFactor, 2);
});

test('ein Wert mit falschem Typ wird verworfen', () => {
  // Der Speicher enthält, was eine frühere Version geschrieben hat, und der
  // Wert landet ungeprüft im Hintergrund-Task. Ein Text in lautstaerke wäre
  // dort ein stiller Rechenfehler, kein Absturz.
  const neu = mischeSettings({ lautstaerke: 'laut', rotlichtblitzer: 'ja' });
  assert.equal(neu.lautstaerke, STANDARD_SETTINGS.lautstaerke);
  assert.equal(neu.rotlichtblitzer, STANDARD_SETTINGS.rotlichtblitzer);
});

test('kaputte Eingaben führen zu den Standardwerten, nicht zu einem Wurf', () => {
  // Eine App, die wegen alter Einstellungen nicht startet, warnt auch nicht.
  for (const kaputt of [null, undefined, 42, 'text', [], true]) {
    assert.deepEqual(
      mischeSettings(kaputt), STANDARD_SETTINGS,
      `Eingabe ${JSON.stringify(kaputt) ?? 'undefined'} lieferte nicht die Standardwerte`,
    );
  }
});

test('mischeSettings gibt jedes Mal ein neues Objekt zurück', () => {
  // Sonst teilte sich der Hintergrund-Task das Objekt mit dem Store, und eine
  // Änderung im einen wäre stillschweigend eine im anderen.
  const a = mischeSettings({});
  const b = mischeSettings({});
  assert.notEqual(a, b);
  assert.notEqual(a, STANDARD_SETTINGS);
  assert.deepEqual(a, b);
});

test('tempolimitWarnung ist wirklich weg, nicht nur aus der UI genommen', () => {
  assert.equal('tempolimitWarnung' in STANDARD_SETTINGS, false);
});
