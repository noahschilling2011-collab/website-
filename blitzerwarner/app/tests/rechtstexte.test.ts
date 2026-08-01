/**
 * Die Rechtstexte.
 *
 * Zwei Sorten Fehler sollen hier auffallen, und beide sind teuer:
 *
 *  1. Die Markdown-Dateien im Repo laufen von der App weg. Dann gibt es zwei
 *     Datenschutzerklärungen, und mindestens eine ist falsch — ausgerechnet
 *     die, die unter einer Adresse steht und auf die sich jemand beruft.
 *  2. Ein Dokument gilt als fertig, obwohl noch [AUSZUFÜLLEN] darin steht.
 *     Beide App-Stores lehnen das ab, und im Fall des Impressums fehlt dann
 *     eine gesetzlich vorgeschriebene Angabe.
 *
 * Was diese Datei NICHT prüft: ob die Texte inhaltlich genügen. Das kann kein
 * Test, das muss jemand mit einschlägiger Qualifikation lesen.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  AUSZUFUELLEN,
  DATEINAME,
  DATENSCHUTZ,
  DOKUMENTE,
  IMPRESSUM,
  NACH_SCHLUESSEL,
  NUTZUNGSBEDINGUNGEN,
  QUELLEN,
  RECHTSSTAND,
  hatLuecken,
  type DokumentSchluessel,
} from '../src/rechtstexte';
import { alsMarkdown } from '../../scripts/make-legal-docs';

const HIER = dirname(fileURLToPath(import.meta.url));
const RECHTLICHES = join(HIER, '..', '..', 'rechtliches');

// --- Der Abgleich mit den erzeugten Dateien -------------------------------

test('die Markdown-Dateien passen zum Stand der App', () => {
  // DER wichtigste Test dieser Datei. Wer den Text in rechtstexte.ts ändert
  // und `npx tsx scripts/make-legal-docs.ts` vergisst, bekommt hier ein Rot
  // statt einer veralteten Erklärung im Netz.
  for (const schluessel of Object.keys(NACH_SCHLUESSEL) as DokumentSchluessel[]) {
    const pfad = join(RECHTLICHES, DATEINAME[schluessel]);
    assert.ok(existsSync(pfad), `${DATEINAME[schluessel]} fehlt — Generator laufen lassen`);

    assert.equal(
      readFileSync(pfad, 'utf8'),
      alsMarkdown(NACH_SCHLUESSEL[schluessel]),
      `${DATEINAME[schluessel]} weicht ab. ` +
      'Erzeugen mit: npx tsx scripts/make-legal-docs.ts',
    );
  }
});

test('alle vier Dokumente existieren und tragen denselben Stand', () => {
  // Getrennte Daten erwecken den Eindruck, eines sei aktueller als das
  // andere. Sie beschreiben aber denselben Softwarestand.
  assert.equal(DOKUMENTE.length, 4);
  for (const d of DOKUMENTE) {
    assert.equal(d.stand, RECHTSSTAND, `${d.titel} hat einen abweichenden Stand`);
    assert.match(d.stand, /^\d{4}-\d{2}-\d{2}$/);
  }
});

test('jedes Dokument hat Titel, Vorspann und Abschnitte mit Inhalt', () => {
  for (const d of DOKUMENTE) {
    assert.ok(d.titel.length > 3, `${d.titel}: Titel zu kurz`);
    assert.ok(d.vorspann.length > 20, `${d.titel}: kein Vorspann`);
    assert.ok(d.abschnitte.length >= 3, `${d.titel}: zu wenige Abschnitte`);
    for (const a of d.abschnitte) {
      assert.ok(a.titel.length > 3, `${d.titel} / ${a.titel}: Titel zu kurz`);
      assert.ok(a.absaetze.length > 0, `${d.titel} / ${a.titel}: leer`);
      for (const p of a.absaetze) {
        assert.ok(p.length > 10, `${d.titel} / ${a.titel}: Absatz zu kurz: "${p}"`);
      }
    }
  }
});

// --- Die Lücken -----------------------------------------------------------

test('offene Stellen sind als solche erkennbar', () => {
  // Impressum und Datenschutzerklärung brauchen Name und Anschrift des
  // Betreibers. Die lassen sich nicht erfinden — aber sie dürfen auch nicht
  // stillschweigend fehlen.
  assert.equal(hatLuecken(IMPRESSUM), true, 'das Impressum hat keine Lücken mehr — wirklich?');
  assert.equal(hatLuecken(DATENSCHUTZ), true, 'die Datenschutzerklärung nennt den Verantwortlichen');

  // Diese beiden brauchen keine Angaben vom Betreiber und müssen fertig sein.
  assert.equal(hatLuecken(NUTZUNGSBEDINGUNGEN), false, 'Nutzungsbedingungen unvollständig');
  assert.equal(hatLuecken(QUELLEN), false, 'Quellen unvollständig');
});

test('die erzeugte Datei warnt sichtbar vor ihren Lücken', () => {
  // Sonst wandert eine unfertige Datei ins Netz und sieht dort fertig aus.
  for (const schluessel of Object.keys(NACH_SCHLUESSEL) as DokumentSchluessel[]) {
    const dokument = NACH_SCHLUESSEL[schluessel];
    const text = readFileSync(join(RECHTLICHES, DATEINAME[schluessel]), 'utf8');
    if (hatLuecken(dokument)) {
      assert.match(text, /Noch nicht vollständig/, `${DATEINAME[schluessel]}: keine Warnung`);
      assert.ok(text.includes(AUSZUFUELLEN), `${DATEINAME[schluessel]}: Marker fehlt`);
    } else {
      assert.ok(
        !text.includes(AUSZUFUELLEN),
        `${DATEINAME[schluessel]} gilt als fertig, enthält aber ${AUSZUFUELLEN}`,
      );
    }
  }
});

// --- Inhaltliche Zusagen, die am Code hängen ------------------------------

test('die Datenschutzerklärung nennt genau die drei Speicherorte', () => {
  // Belegt in src/state/store.ts (Einstellungen, Bestätigung) und
  // src/core/log.ts (Fehlerprotokoll). Es gibt keine weiteren setItem-Aufrufe
  // im Projekt. Käme einer dazu, ohne dass dieser Text mitwächst, wäre die
  // Erklärung unvollständig — und das ist der Fehler, der zählt.
  const text = DATENSCHUTZ.abschnitte
    .flatMap((a) => a.absaetze).join(' ');

  assert.match(text, /Einstellungen/);
  assert.match(text, /rechtlichen Hinweis bestätigt/);
  assert.match(text, /Fehlerprotokoll/);
  assert.match(text, /200 Einträge/);
});

test('die Datenschutzerklärung behauptet nicht, das Fehlerprotokoll sei ortsfrei', () => {
  // Es kann einen Ländercode enthalten (task.ts protokolliert landStatus.umriss).
  // Das ist die gröbste denkbare Ortsangabe, aber es ist eine — und sie zu
  // verschweigen wäre genau die Art Ungenauigkeit, die eine Erklärung
  // angreifbar macht.
  const text = DATENSCHUTZ.abschnitte.flatMap((a) => a.absaetze).join(' ');
  assert.match(text, /Ländercode/, 'der Ländercode im Protokoll ist verschwiegen');
});

test('die Nutzungsbedingungen benennen die Grenzen der Daten', () => {
  const text = NUTZUNGSBEDINGUNGEN.abschnitte.flatMap((a) => a.absaetze).join(' ');
  for (const zusage of ['mobilen', 'Vollständigkeit', 'Aktualität', 'Beschilderung']) {
    assert.ok(text.includes(zusage), `Die Grenze "${zusage}" fehlt`);
  }
});

test('die Quellen nennen jede Datengrundlage mit Lizenz', () => {
  const text = QUELLEN.abschnitte.flatMap((a) => a.absaetze).join(' ');
  for (const quelle of ['OpenStreetMap', 'ODbL', 'Natural Earth', 'Public Domain', 'ADAC']) {
    assert.ok(text.includes(quelle), `Die Quelle "${quelle}" fehlt`);
  }
  // Und die Normen, auf die sich die App beruft.
  for (const norm of ['23 Abs. 1c StVO', '98a KFG', '57b SVG', '2 ORbs 35 Ss 9/23']) {
    assert.ok(text.includes(norm), `Die Norm "${norm}" fehlt in den Quellen`);
  }
});

test('kein Dokument verspricht Rechtsberatung', () => {
  // Der Projektgrundsatz: keine Rechtsaussagen erfinden. Jedes Dokument
  // bekommt beim Erzeugen den Hinweis angehängt; hier wird geprüft, dass er
  // wirklich dransteht.
  for (const schluessel of Object.keys(NACH_SCHLUESSEL) as DokumentSchluessel[]) {
    const text = readFileSync(join(RECHTLICHES, DATEINAME[schluessel]), 'utf8');
    assert.match(text, /Keine Rechtsberatung/, `${DATEINAME[schluessel]}`);
  }
});

test('die Datenschutzerklärung deckt sich mit dem Berechtigungs-Entzug', () => {
  // Sie behauptet, die Internet-Berechtigung sei im ausgelieferten Build
  // entzogen. Das ist eine überprüfbare Aussage — und sie wird hier gegen
  // dieselbe Konfiguration geprüft, die tests/berechtigungen.test.ts prüft.
  const text = DATENSCHUTZ.abschnitte.flatMap((a) => a.absaetze).join(' ');
  assert.match(text, /Internet-Berechtigung\s+entzogen/);

  // UND sie sagt dazu, für welches System das gilt.
  //
  // Vorher stand die Zusage plattformlos da, samt der Einladung, sie in den
  // App-Informationen nachzusehen. Auf einem iPhone ist beides falsch: iOS
  // kennt keine Internet-Berechtigung, also ist dort nichts entzogen und
  // nichts nachzusehen. Wer eine Datenschutzerklärung zur Überprüfung an eine
  // Stelle schickt, an der nichts zu finden ist, beschädigt genau das
  // Vertrauen, das sie herstellen soll.
  assert.match(text, /Auf Android/, 'die Zusage nennt das System nicht, für das sie gilt');
  assert.match(text, /Auf iOS gibt es keine Internet-Berechtigung/,
    'die iOS-Einschränkung fehlt — dort wäre die Aussage falsch');
  assert.match(text, /am Quelltext/, 'für iOS fehlt der Ersatzbeleg');

  const vorher = process.env.EAS_BUILD_PROFILE;
  process.env.EAS_BUILD_PROFILE = 'production';
  try {
    // Der Import muss hier stehen: app.config.js liest die Umgebung beim
    // Aufruf, nicht beim Laden.
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const config = require('../app.config.js') as {
      (a: { config: Record<string, unknown> }): { android: { blockedPermissions: string[] } };
    };
    const appJson = require('../app.json') as { expo: Record<string, unknown> };
    assert.ok(
      config({ config: appJson.expo }).android.blockedPermissions
        .includes('android.permission.INTERNET'),
      'die Erklärung behauptet den Entzug, die Konfiguration liefert ihn nicht',
    );
  } finally {
    if (vorher === undefined) delete process.env.EAS_BUILD_PROFILE;
    else process.env.EAS_BUILD_PROFILE = vorher;
  }
});
