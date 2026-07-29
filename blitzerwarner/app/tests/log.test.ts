/**
 * Tests für das Fehlerprotokoll, Qualitätsvorgabe 1d.
 *
 * Die Uhr wird eingespeist statt Date.now() zu benutzen: Ein Test, der
 * Reihenfolge prüft und dabei auf echte Zeit angewiesen ist, schlägt
 * irgendwann auf einer schnelleren Maschine grundlos fehl.
 *
 * Der Attrappen-Speicher kann absichtlich scheitern. Das ist der Fall, der
 * sich auf einem Gerät kaum herstellen lässt und trotzdem eintritt: volle
 * Platte.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ERROR_LOG } from '../src/config.js';
import {
  ErrorLog,
  LOG_STORAGE_KEY,
  MAX_TEXT_LAENGE,
  fehlerText,
  type KeyValueStore,
  type LogEntry,
} from '../src/core/log.js';

const T0 = 1_700_000_000_000;

/** Uhr, die bei jedem Ablesen eine Sekunde weiterläuft. */
function uhr(start = T0, schritt = 1000): () => number {
  let jetzt = start;
  return () => {
    const wert = jetzt;
    jetzt += schritt;
    return wert;
  };
}

class Attrappe implements KeyValueStore {
  readonly werte = new Map<string, string>();
  schreibVersuche = 0;
  leseVersuche = 0;
  loeschVersuche = 0;
  /** Ab hier scheitert jeder Zugriff, wie bei vollem Speicher. */
  scheitert = false;

  async getItem(key: string): Promise<string | null> {
    this.leseVersuche++;
    if (this.scheitert) throw new Error('Speicher nicht lesbar');
    return this.werte.get(key) ?? null;
  }

  async setItem(key: string, value: string): Promise<void> {
    this.schreibVersuche++;
    if (this.scheitert) throw new Error('Kein Speicherplatz');
    this.werte.set(key, value);
  }

  async removeItem(key: string): Promise<void> {
    this.loeschVersuche++;
    if (this.scheitert) throw new Error('Kein Speicherplatz');
    this.werte.delete(key);
  }
}

// --- Ringpuffer -----------------------------------------------------------

test('Ringpuffer: unter der Grenze bleibt alles erhalten', () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 5 });
  log.info('start', 'eins');
  log.warn('position', 'zwei');
  log.error('daten', 'drei');

  assert.equal(log.size, 3);
  assert.deepEqual(
    log.entries().map((e) => e.message),
    ['eins', 'zwei', 'drei'],
  );
});

test('Ringpuffer: über der Grenze fallen die ältesten heraus', () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 3 });
  for (const nachricht of ['a', 'b', 'c', 'd', 'e']) log.info('start', nachricht);

  assert.equal(log.size, 3, 'nie mehr als die Grenze');
  assert.deepEqual(
    log.entries().map((e) => e.message),
    ['c', 'd', 'e'],
    'die jüngsten bleiben, die ältesten gehen',
  );
});

test('Ringpuffer: die Grenze aus der config wird eingehalten', () => {
  const log = new ErrorLog({ now: uhr() });
  const ueberzaehlig = 5;
  for (let i = 0; i < ERROR_LOG.MAX_ENTRIES + ueberzaehlig; i++) {
    log.error('daten', `Eintrag ${i}`);
  }

  assert.equal(log.size, ERROR_LOG.MAX_ENTRIES);

  const eintraege = log.entries();
  assert.equal(eintraege[0]?.message, `Eintrag ${ueberzaehlig}`);
  assert.equal(
    eintraege[eintraege.length - 1]?.message,
    `Eintrag ${ERROR_LOG.MAX_ENTRIES + ueberzaehlig - 1}`,
  );
});

test('Ringpuffer: der Überlauf verändert die Reihenfolge nicht', () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 4 });
  for (let i = 0; i < 20; i++) log.info('audio', `nr ${i}`);

  const zeiten = log.entries().map((e) => e.t);
  for (let i = 1; i < zeiten.length; i++) {
    assert.ok((zeiten[i] ?? 0) > (zeiten[i - 1] ?? 0), 'Zeitstempel steigen monoton');
  }
});

test('Ringpuffer: die zurückgegebene Liste ist eine Kopie', () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 3 });
  log.info('start', 'eins');

  const kopie = log.entries() as LogEntry[];
  kopie.push({ t: T0, level: 'error', area: 'daten', message: 'untergeschoben', detail: null });

  assert.equal(log.size, 1, 'von aussen lässt sich der Verlauf nicht verändern');
});

// --- Reihenfolge ----------------------------------------------------------

test('Reihenfolge: ältester zuerst, auch bei gleichem Zeitstempel', () => {
  // Zwei Fehler innerhalb derselben Millisekunde sind auf einem Gerät der
  // Normalfall, nicht die Ausnahme.
  const log = new ErrorLog({ now: () => T0, maxEntries: 10 });
  log.error('position', 'erster');
  log.error('position', 'zweiter');
  log.error('position', 'dritter');

  assert.deepEqual(
    log.entries().map((e) => e.message),
    ['erster', 'zweiter', 'dritter'],
  );
});

test('Reihenfolge: gespeicherte und neue Einträge werden nach Zeit verwoben', async () => {
  const speicher = new Attrappe();
  const alt = new ErrorLog({ store: speicher, now: uhr(T0, 1000), maxEntries: 10 });
  alt.info('start', 'alt eins'); // T0
  alt.info('start', 'alt zwei'); // T0 + 1000
  await alt.flush();

  // Neue Instanz wie nach einem App-Neustart: Sie protokolliert bereits,
  // bevor der Speicher bereitsteht.
  const neu = new ErrorLog({ now: uhr(T0 + 2000, 1000), maxEntries: 10 });
  neu.info('start', 'neu eins'); // T0 + 2000
  await neu.attachStore(speicher);

  assert.deepEqual(
    neu.entries().map((e) => e.message),
    ['alt eins', 'alt zwei', 'neu eins'],
  );
});

// --- Textexport -----------------------------------------------------------

test('Export: eine Zeile je Eintrag, in derselben Reihenfolge', () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 10 });
  log.info('start', 'App gestartet');
  log.warn('position', 'Position ungenau');
  log.error('daten', 'Datensatz nicht lesbar', new RangeError('cell 0.1'));

  const zeilen = log.toText().split('\n');
  assert.equal(zeilen.length, 3);
  assert.ok(zeilen[0]?.includes('App gestartet'));
  assert.ok(zeilen[1]?.includes('Position ungenau'));
  assert.ok(zeilen[2]?.includes('Datensatz nicht lesbar'));
});

test('Export: eine Zeile enthält Zeit, Ebene, Bereich, Nachricht und Fehlertext', () => {
  const log = new ErrorLog({ now: () => T0, maxEntries: 10 });
  log.error('daten', 'Datensatz nicht lesbar', new RangeError('cell 0.1'));

  const zeile = log.toText();
  const gestrafft = zeile.replace(/ +/g, ' ');

  assert.equal(
    gestrafft,
    `${new Date(T0).toISOString()} ERROR daten Datensatz nicht lesbar | RangeError: cell 0.1`,
  );
});

test('Export: die Spalten stehen untereinander', () => {
  // Ausgerichtete Spalten sind der Unterschied zwischen überfliegen und
  // Zeile für Zeile lesen.
  const log = new ErrorLog({ now: () => T0, maxEntries: 10 });
  log.info('start', 'kurz');
  log.error('einstellungen', 'lang');

  const spalten = log
    .toText()
    .split('\n')
    .map((z) => z.indexOf('kurz') + z.indexOf('lang') + 1);

  assert.equal(spalten[0], spalten[1], 'die Nachricht beginnt in beiden Zeilen an derselben Stelle');
});

test('Export: ein leeres Protokoll ergibt einen leeren Text', () => {
  // Die Anzeige setzt an dieser Stelle strings.leer.keineFehlerText ein statt
  // eines erfundenen Platzhalters.
  const log = new ErrorLog({ now: uhr() });
  assert.equal(log.toText(), '');
});

test('Export: mehrzeilige Eingaben werden auf eine Zeile gebracht', () => {
  const log = new ErrorLog({ now: () => T0, maxEntries: 10 });
  const fehler = new Error('erste Zeile\n    zweite Zeile');
  log.error('hintergrund', 'Task\nabgebrochen', fehler);

  const text = log.toText();
  assert.equal(text.split('\n').length, 1, 'ein Eintrag ist genau eine Zeile');
  assert.ok(text.includes('Task abgebrochen'));
  assert.ok(text.includes('erste Zeile zweite Zeile'));
});

test('Export: überlange Texte werden gekürzt', () => {
  const log = new ErrorLog({ now: () => T0, maxEntries: 10 });
  log.error('audio', 'x'.repeat(1000), new Error('y'.repeat(1000)));

  const eintrag = log.entries()[0];
  assert.equal(eintrag?.message.length, MAX_TEXT_LAENGE);
  assert.equal(eintrag?.detail?.length, MAX_TEXT_LAENGE);
});

// --- Fehlertexte ----------------------------------------------------------

test('Fehlertext: ohne Fehler bleibt das Feld leer', () => {
  const log = new ErrorLog({ now: () => T0 });
  assert.equal(log.info('start', 'ohne Anhang').detail, null);
  assert.equal(fehlerText(undefined), null);
  assert.equal(fehlerText(null), null);
});

test('Fehlertext: aus Error, Zeichenkette und fremden Werten', () => {
  assert.equal(fehlerText(new Error('schlicht')), 'schlicht');
  assert.equal(fehlerText(new TypeError('falscher Typ')), 'TypeError: falscher Typ');
  assert.equal(fehlerText('nur Text'), 'nur Text');
  assert.equal(fehlerText(42), '42');
  assert.equal(fehlerText({ code: 7 }), '{"code":7}');
});

test('Fehlertext: ein zirkulärer Wert bringt nichts zum Absturz', () => {
  const zirkulaer: { selbst?: unknown } = {};
  zirkulaer.selbst = zirkulaer;
  assert.equal(typeof fehlerText(zirkulaer), 'string');
});

// --- Persistenz -----------------------------------------------------------

test('Persistenz: Einträge überleben einen Neustart', async () => {
  const speicher = new Attrappe();
  const erste = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 10 });
  erste.error('daten', 'Datensatz nicht lesbar');
  await erste.flush();

  assert.ok(speicher.werte.has(LOG_STORAGE_KEY));

  const zweite = new ErrorLog({ store: speicher, now: uhr(T0 + 60_000), maxEntries: 10 });
  await zweite.load();

  assert.deepEqual(
    zweite.entries().map((e) => e.message),
    ['Datensatz nicht lesbar'],
  );
  assert.equal(zweite.entries()[0]?.area, 'daten');
  assert.equal(zweite.entries()[0]?.level, 'error');
});

test('Persistenz: viele Einträge kurz nacheinander schreiben nicht einzeln', async () => {
  const speicher = new Attrappe();
  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 50 });
  for (let i = 0; i < 20; i++) log.info('position', `nr ${i}`);
  await log.flush();

  assert.ok(
    speicher.schreibVersuche < 20,
    `20 Einträge lösten ${speicher.schreibVersuche} Schreibvorgänge aus`,
  );

  const zweite = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 50 });
  await zweite.load();
  assert.equal(zweite.size, 20, 'trotzdem ist alles gespeichert');
});

test('Persistenz: der Ringpuffer läuft auch im Speicher nicht über', async () => {
  const speicher = new Attrappe();
  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 3 });
  for (let i = 0; i < 10; i++) log.warn('audio', `nr ${i}`);
  await log.flush();

  const zweite = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 3 });
  await zweite.load();
  assert.deepEqual(
    zweite.entries().map((e) => e.message),
    ['nr 7', 'nr 8', 'nr 9'],
  );
});

test('Persistenz: ein kaputter Speicherinhalt wird verworfen und vermerkt', async () => {
  const speicher = new Attrappe();
  speicher.werte.set(LOG_STORAGE_KEY, '[{"t":1,"level":"err');

  const log = new ErrorLog({ store: speicher, now: () => T0, maxEntries: 10 });
  await log.load();

  assert.equal(log.size, 1, 'statt eines leeren Protokolls steht dort ein Hinweis');
  assert.equal(log.entries()[0]?.area, 'speicher');
  assert.equal(log.entries()[0]?.level, 'warn');
});

test('Persistenz: einzelne unbrauchbare Einträge kosten nicht den ganzen Verlauf', async () => {
  const speicher = new Attrappe();
  speicher.werte.set(
    LOG_STORAGE_KEY,
    JSON.stringify([
      { t: T0, level: 'info', area: 'start', message: 'gut', detail: null },
      { t: T0 + 1, level: 'unbekannt', area: 'start', message: 'kaputt', detail: null },
      { t: T0 + 2, level: 'info', area: 'nirgends', message: 'kaputt', detail: null },
      { t: T0 + 3, level: 'warn', area: 'audio', message: 'auch gut', detail: null },
    ]),
  );

  const log = new ErrorLog({ store: speicher, now: () => T0, maxEntries: 10 });
  await log.load();

  assert.deepEqual(
    log.entries().map((e) => e.message),
    ['gut', 'auch gut'],
  );
});

test('Persistenz: Löschen räumt auch den Gerätespeicher', async () => {
  const speicher = new Attrappe();
  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 10 });
  log.error('daten', 'irgendwas');
  await log.flush();

  log.clear();
  await log.flush();

  assert.equal(log.size, 0);
  assert.equal(speicher.werte.has(LOG_STORAGE_KEY), false);
  assert.equal(speicher.loeschVersuche, 1);
});

test('Persistenz: ein voller Speicher legt das Protokoll nicht lahm', async () => {
  const speicher = new Attrappe();
  speicher.scheitert = true;

  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 50 });
  log.error('daten', 'erster Fehler');
  await log.flush();

  assert.equal(log.storageFailed, true, 'die Oberfläche kann darauf hinweisen');
  assert.ok(
    log.entries().some((e) => e.message === 'erster Fehler'),
    'im Arbeitsspeicher läuft das Protokoll weiter',
  );
  assert.equal(
    log.entries().filter((e) => e.area === 'speicher').length,
    1,
    'der Speicherfehler wird einmal vermerkt, nicht bei jedem Versuch',
  );
});

test('Persistenz: der Speicherfehler vermerkt sich nicht endlos selbst', async () => {
  const speicher = new Attrappe();
  speicher.scheitert = true;

  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 50 });
  for (let i = 0; i < 10; i++) log.error('position', `nr ${i}`);
  await log.flush();

  assert.equal(log.size, 11, '10 Einträge und ein einziger Vermerk');
});

test('Persistenz: nach einem gelungenen Schreibvorgang ist die Störung vorbei', async () => {
  const speicher = new Attrappe();
  speicher.scheitert = true;

  const log = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 50 });
  log.error('daten', 'im vollen Speicher');
  await log.flush();
  assert.equal(log.storageFailed, true);

  speicher.scheitert = false;
  log.info('start', 'wieder Platz');
  await log.flush();

  assert.equal(log.storageFailed, false);
  assert.ok(speicher.werte.has(LOG_STORAGE_KEY));
});

test('Persistenz: ohne Speicher läuft alles im Arbeitsspeicher weiter', async () => {
  const log = new ErrorLog({ now: uhr(), maxEntries: 10 });
  log.info('start', 'ohne Speicher');
  await log.flush();

  assert.equal(log.size, 1);
  assert.equal(log.storageFailed, false);
});

test('Persistenz: der nachgereichte Speicher übernimmt die frühen Einträge', async () => {
  // Der eigentliche Grund für attachStore: Beim Start wird protokolliert,
  // bevor AsyncStorage bereitsteht, und gerade die frühen Einträge erklären,
  // warum die App nicht warnt.
  const speicher = new Attrappe();
  const log = new ErrorLog({ now: uhr(), maxEntries: 10 });
  log.error('daten', 'ganz früher Fehler');

  await log.attachStore(speicher);

  const zweite = new ErrorLog({ store: speicher, now: uhr(), maxEntries: 10 });
  await zweite.load();
  assert.deepEqual(
    zweite.entries().map((e) => e.message),
    ['ganz früher Fehler'],
  );
});
