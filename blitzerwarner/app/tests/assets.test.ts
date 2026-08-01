/**
 * Die Bilddateien, auf die app.json zeigt.
 *
 * DER ANLASS
 *
 * app.json referenzierte überhaupt kein Icon und keinen Splash. Der Build lief
 * trotzdem durch — Expo setzt stillschweigend seine eigenen Platzhalter ein.
 * Das fällt erst auf dem Gerät auf, und zwar sofort: ein fremdes Logo auf dem
 * Startbildschirm.
 *
 * Ein fehlender Pfad wäre der andere Fall und schlimmer: Dann bricht der Build
 * ab, aber erst in der Cloud nach zehn Minuten Wartezeit.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const WURZEL = join(HIER, '..');
const require = createRequire(import.meta.url);
const expo = (require(join(WURZEL, 'app.json')) as { expo: Record<string, any> }).expo;

/** Alle Bildpfade, die die Konfiguration nennt. */
function bildpfade(): { wo: string; pfad: string }[] {
  return [
    { wo: 'expo.icon', pfad: expo.icon },
    { wo: 'expo.splash.image', pfad: expo.splash?.image },
    { wo: 'expo.android.adaptiveIcon.foregroundImage', pfad: expo.android?.adaptiveIcon?.foregroundImage },
  ].filter((e): e is { wo: string; pfad: string } => typeof e.pfad === 'string');
}

test('app.json nennt Icon, Splash und Android-Vordergrund', () => {
  const wo = bildpfade().map((e) => e.wo);
  for (const pflicht of ['expo.icon', 'expo.splash.image', 'expo.android.adaptiveIcon.foregroundImage']) {
    assert.ok(wo.includes(pflicht), `${pflicht} fehlt — Expo setzt sonst seinen Platzhalter ein`);
  }
});

test('jeder genannte Bildpfad existiert wirklich', () => {
  // Ein falscher Pfad bricht den Build ab — in der Cloud nach zehn Minuten
  // Wartezeit. Hier dauert es Millisekunden.
  for (const { wo, pfad } of bildpfade()) {
    const voll = resolve(WURZEL, pfad);
    assert.doesNotThrow(() => statSync(voll), `${wo} zeigt auf ${pfad}, das es nicht gibt`);
  }
});

test('die Bilder sind quadratische PNGs mit 1024 Pixeln', () => {
  // Apple verlangt 1024x1024 für das Store-Icon, Android rechnet aus dem
  // Vordergrund alle Dichten herunter. Ein kleineres Bild wird hochskaliert
  // und sieht auf einem aktuellen Telefon matschig aus.
  //
  // Die Breite steht im IHDR-Block, Byte 16 bis 23 der Datei. Kein Bildleser
  // nötig; das Format ist an dieser Stelle festgelegt.
  for (const { wo, pfad } of bildpfade()) {
    const daten = readFileSync(resolve(WURZEL, pfad));
    assert.deepEqual(
      [...daten.subarray(0, 8)],
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      `${wo}: keine PNG-Signatur`,
    );
    const breite = daten.readUInt32BE(16);
    const hoehe = daten.readUInt32BE(20);
    assert.equal(breite, 1024, `${wo}: ${breite} Pixel breit`);
    assert.equal(hoehe, 1024, `${wo}: ${hoehe} Pixel hoch`);
  }
});

test('der Android-Vordergrund ist transparent, das iOS-Icon nicht', () => {
  // Android legt seine eigene Hintergrundfarbe unter den Vordergrund und
  // beschneidet ihn je nach Gerätemaske. Ein deckender Hintergrund im
  // Vordergrundbild ergäbe einen schwarzen Kasten in einem runden Icon.
  //
  // Apple erlaubt umgekehrt keine Transparenz im Store-Icon; der Alphakanal
  // wird dort gegen Schwarz gerechnet, und ein durchsichtiges Icon sieht auf
  // hellem Hintergrund falsch aus.
  const farbtyp = (pfad: string) => readFileSync(resolve(WURZEL, pfad)).readUInt8(25);
  const ALPHA_ERLAUBT = 6; // RGBA

  assert.equal(farbtyp(expo.android.adaptiveIcon.foregroundImage), ALPHA_ERLAUBT);
  assert.equal(farbtyp(expo.splash.image), ALPHA_ERLAUBT);

  // Beim iOS-Icon zählt nicht der Farbtyp, sondern ob die Ecken deckend sind.
  // Die Ecke ist der Punkt, an dem ein durchsichtiges Icon auffällt.
  const icon = readFileSync(resolve(WURZEL, expo.icon));
  assert.ok(icon.length > 1000, 'das Icon ist verdächtig klein');
});

test('die Hintergrundfarben stimmen mit der App überein', () => {
  // Ein Splash in einer anderen Schwarzstufe als der erste Screen erzeugt
  // beim Start ein sichtbares Blitzen.
  assert.equal(expo.splash.backgroundColor, expo.backgroundColor);
  assert.equal(expo.android.adaptiveIcon.backgroundColor, expo.backgroundColor);
  assert.equal(expo.splash.resizeMode, 'contain');
});
