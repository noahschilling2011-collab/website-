/**
 * Die Kernauflage aus Phase C.2 als Test.
 *
 * Frankreich erlaubt seit dem 03.01.2012 nur den Hinweis auf einen
 * Gefahrenbereich. Die Zone darf die ART der Gefahr nicht benennen. Verstoss:
 * bis 1500 Euro, Einziehung des Geräts, bei fest eingebauten Geräten bis zur
 * Beschlagnahme des Fahrzeugs.
 *
 * Das ist die Art Test, die noch greift, wenn irgendwann jemand einen
 * Ansagetext ergänzt und die Auflage nicht kennt. Genau dafür steht er hier
 * und nicht als Kommentar im Katalog.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  VERBOTENE_ZONENWOERTER, ZONEN_ANSAGE, enthaeltVerbotenesZonenwort,
  zonenAnsageText, ansageText,
} from '../src/audio/announce';
import { TOENE } from '../src/audio/tone';
import { STRINGS } from '../src/strings';
import type { Camera } from '../src/types';

test('kein Zonen-Ansagetext enthält ein verbotenes Wort', () => {
  for (const [sprache, text] of Object.entries(ZONEN_ANSAGE)) {
    const treffer = enthaeltVerbotenesZonenwort(text);
    assert.equal(treffer, null, `${sprache}: "${text}" enthält "${treffer}"`);
  }
});

test('der Zonentext nennt keine Entfernung und keine Zahl', () => {
  // Kein Countdown, keine Entfernungsansage — die Regelung verlangt einen
  // Bereich, nicht einen Punkt.
  for (const [sprache, text] of Object.entries(ZONEN_ANSAGE)) {
    assert.ok(!/\d/.test(text), `${sprache}: "${text}" enthält eine Zahl`);
    assert.ok(!/meter|mètre|metre|km|yard/i.test(text), `${sprache}: "${text}" nennt eine Einheit`);
  }
});

test('zonenAnsageText nimmt gar keine Distanz an', () => {
  // Was die Funktion nicht kennt, kann sie nicht versehentlich aussprechen.
  // Function.length zählt Parameter mit Standardwert nicht mit, deshalb 0 und
  // nicht 1 — der Sprachparameter hat einen Standardwert.
  assert.ok(
    zonenAnsageText.length <= 1,
    `nimmt ${zonenAnsageText.length} Pflichtparameter, erwartet keinen ausser der Sprache`,
  );
  assert.equal(zonenAnsageText(), ZONEN_ANSAGE.fr);
  assert.equal(zonenAnsageText('de'), ZONEN_ANSAGE.de);
});

test('die Verbotsliste deckt mehrere Sprachen ab', () => {
  // Der Ansagetext folgt der Systemsprache. Eine rein deutsche Liste würde
  // einen französischen oder englischen Katalog ungeprüft durchlassen.
  for (const wort of ['blitzer', 'radar', 'contrôle', 'speed camera', 'police']) {
    assert.ok(
      (VERBOTENE_ZONENWOERTER as readonly string[]).includes(wort),
      `"${wort}" fehlt in der Verbotsliste`,
    );
  }
});

test('enthaeltVerbotenesZonenwort findet Wörter unabhängig von Gross- und Kleinschreibung', () => {
  assert.equal(enthaeltVerbotenesZonenwort('Achtung Blitzer voraus'), 'blitzer');
  assert.equal(enthaeltVerbotenesZonenwort('RADAR'), 'radar');
  assert.equal(enthaeltVerbotenesZonenwort('Zone de vigilance'), null);
  assert.equal(enthaeltVerbotenesZonenwort('Achtungsbereich'), null);
});

test('der PUNKT-Ansagetext verletzt die Liste absichtlich', () => {
  // Gegenprobe: Der normale Ansagetext MUSS "Blitzer" sagen — das ist in den
  // Ländern mit Punktmodus richtig und erlaubt. Fiele dieser Test durch,
  // würde der Wortlisten-Test nichts prüfen, weil er auf jeden Text passt.
  const kamera: Camera = { lat: 48.77, lon: 9.18, dir: null, max: 80, type: 'speed' };
  const text = ansageText(kamera, 400);
  assert.ok(
    enthaeltVerbotenesZonenwort(text) !== null,
    'der Punkttext enthält kein verbotenes Wort — dann trennt die Liste nichts',
  );
});

test('die Punkt-Ansagebausteine bleiben vom Zonenkatalog getrennt', () => {
  // Zwei Kataloge, damit ein neuer Punkttext nicht versehentlich in einer
  // Zone landet. Der Test prüft, dass sie sich nicht überschneiden.
  const zonenTexte = Object.values(ZONEN_ANSAGE) as string[];
  const punktBausteine = Object.values(STRINGS.ansage.art) as string[];
  for (const z of zonenTexte) {
    assert.ok(
      !punktBausteine.includes(z),
      `"${z}" steht in beiden Katalogen — die Trennung ist damit aufgehoben`,
    );
  }
});

test('das Zonenverhalten ist vollständig verdrahtet', () => {
  // Hier stand bis zum Abschluss von Phase C ein Test, der festhielt, dass
  // das Zonenverhalten FEHLT. Er ist gelöscht, weil er nicht mehr stimmt —
  // eine Notiz, die falsch geworden ist, ist schlimmer als keine.
  //
  // Was jetzt geprüft wird: dass die Teile tatsächlich zusammenhängen. Ein
  // Zonenton ohne Textkatalog oder ein Katalog ohne Ton wäre ein halber
  // Zustand, und genau der ist bei dieser Auflage gefährlich.
  assert.ok(Object.keys(ZONEN_ANSAGE).length >= 2, 'Textkatalog vorhanden');
  assert.ok(VERBOTENE_ZONENWOERTER.length >= 10, 'Verbotsliste vorhanden');
  assert.equal(typeof enthaeltVerbotenesZonenwort, 'function', 'Laufzeitprüfung vorhanden');
  assert.ok('zone' in TOENE, 'eigener Zonenton vorhanden');

  // Der Zonenton darf nicht der Blitzerton sein. Doppelt geprüft — hier und
  // in audio.test.ts —, weil das die Stelle ist, an der ein Copy-Paste-Fehler
  // die Auflage unbemerkt aushebeln würde.
  assert.notDeepEqual(TOENE.zone.impulse, TOENE.blitzer.impulse);
});
