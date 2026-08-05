import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AusgangsEintrag, Termin, Vorgang } from '../../db/schema';
import { platzierung, sortiere, stelleDar, tageSeit } from './darstellung';

const ZONE = 'Europe/Berlin';
const JETZT = new Date('2026-08-05T10:00:00Z');

function vorgang(teile: Partial<Vorgang> = {}): Vorgang {
  return {
    id: 'v1',
    nutzerId: 'n1',
    art: 'termin',
    zustand: 'neu',
    titel: 'Termin mit Frau Berger',
    gegenueberEmail: 'berger@example.de',
    gegenueberName: 'Frau Berger',
    threadKey: 't1',
    faelligAm: null,
    naechsteErinnerung: null,
    erinnerungenGesendet: 0,
    erstelltAm: JETZT,
    geaendertAm: JETZT,
    ...teile,
  } as Vorgang;
}

function ausgang(teile: Partial<AusgangsEintrag> = {}): AusgangsEintrag {
  return {
    id: 'a1',
    vorgangId: 'v1',
    an: 'berger@example.de',
    betreff: 'Re: Termin',
    text: '...',
    icalMethode: null,
    icalInhalt: null,
    inReplyTo: null,
    referenzen: null,
    haltenBis: JETZT,
    status: 'entwurf',
    gesendetAm: null,
    messageId: null,
    fehler: null,
    erstelltAm: JETZT,
    ...teile,
  } as AusgangsEintrag;
}

function termin(teile: Partial<Termin> = {}): Termin {
  return {
    id: 't1',
    vorgangId: 'v1',
    uid: 'x@y.de',
    sequence: 0,
    titel: 'Termin',
    von: new Date('2026-08-18T12:00:00Z'),
    bis: new Date('2026-08-18T12:45:00Z'),
    zeitzone: ZONE,
    ort: null,
    platzierungsStatus: 'placed',
    platzierungsArt: 'google_event_id',
    platzierungsWert: 'abc',
    erstelltAm: JETZT,
    ...teile,
  } as Termin;
}

test('Ein fertiger Entwurf steht oben und traegt den Senden-Knopf', () => {
  const d = stelleDar(vorgang({ zustand: 'warte_auf_mich' }), ausgang(), null, ZONE, JETZT);
  assert.equal(d.stand, 'Entwurf fertig');
  assert.equal(d.dringend, true);
  assert.equal(d.knopf, 'senden');
});

test('Waehrend der Haltezeit zaehlt die Zeile herunter und bietet Abbrechen', () => {
  const d = stelleDar(
    vorgang({ zustand: 'gehalten' }),
    ausgang({ status: 'gehalten', haltenBis: new Date(JETZT.getTime() + 42_000) }),
    null,
    ZONE,
    JETZT,
  );
  assert.match(d.stand, /42 Sekunden/);
  assert.match(d.stand, /abbrechbar/);
  assert.equal(d.knopf, 'abbrechen');
  assert.equal(d.laeuft, true);
  // Waehrend die Haltezeit laeuft, ist nichts zu entscheiden.
  assert.equal(d.dringend, false);
});

test('Nach Ablauf der Haltezeit gibt es nichts mehr abzubrechen', () => {
  const d = stelleDar(
    vorgang({ zustand: 'gehalten' }),
    ausgang({ status: 'gehalten', haltenBis: new Date(JETZT.getTime() - 1000) }),
    null,
    ZONE,
    JETZT,
  );
  assert.equal(d.knopf, 'ansehen');
  assert.match(d.stand, /gesendet/);
});

test('Wartende Vorgaenge zeigen Dauer und naechste Erinnerung', () => {
  const d = stelleDar(
    vorgang({
      zustand: 'warte_auf_andere',
      geaendertAm: new Date(JETZT.getTime() - 2 * 86_400_000),
      naechsteErinnerung: new Date('2026-08-06T07:00:00Z'),
    }),
    null,
    null,
    ZONE,
    JETZT,
  );
  assert.match(d.stand, /Warte auf Antwort seit 2 Tagen/);
  assert.match(d.stand, /6\. August/);
  assert.equal(d.dringend, false);
});

test('Eine erledigte Frist nennt Datum und Kalenderstatus', () => {
  const d = stelleDar(
    vorgang({
      zustand: 'erledigt',
      art: 'frist',
      faelligAm: new Date('2026-08-18T07:00:00Z'),
    }),
    null,
    null,
    ZONE,
    JETZT,
  );
  assert.match(d.stand, /Frist 18\. August/);
  assert.match(d.stand, /im Kalender/);
});

test('Der Unterschied zwischen bestaetigt und unterwegs ist sichtbar', () => {
  // Die Nutzerin darf nicht glauben, ein Termin stehe fest, wenn er nur
  // verschickt wurde. Das ist der ganze Grund fuer drei Platzierungszustaende.
  assert.equal(platzierung(termin({ platzierungsStatus: 'placed' })), 'im Kalender');
  assert.match(
    platzierung(termin({ platzierungsStatus: 'dispatched' })),
    /unbestätigt/,
  );
  assert.match(platzierung(termin({ platzierungsStatus: 'published' })), /Abo/);
  assert.equal(platzierung(termin({ platzierungsStatus: 'offen' })), 'vorgeschlagen');
});

test('Fehler stehen oben', () => {
  const d = stelleDar(vorgang({ zustand: 'fehler' }), null, null, ZONE, JETZT);
  assert.equal(d.dringend, true);
});

test('Dauerangaben sind in Alltagssprache', () => {
  assert.equal(tageSeit(new Date(JETZT.getTime() - 60_000), JETZT), 'wenigen Minuten');
  assert.equal(tageSeit(new Date(JETZT.getTime() - 3_600_000), JETZT), '1 Stunde');
  assert.equal(tageSeit(new Date(JETZT.getTime() - 5 * 3_600_000), JETZT), '5 Stunden');
  assert.equal(tageSeit(new Date(JETZT.getTime() - 86_400_000), JETZT), '1 Tag');
  assert.equal(tageSeit(new Date(JETZT.getTime() - 3 * 86_400_000), JETZT), '3 Tagen');
});

test('Die Sortierung stellt Wartendes nach oben, dann Laufendes', () => {
  const eintraege = [
    { vorgang: vorgang({ id: 'alt', zustand: 'erledigt' }), darstellung: stelleDar(vorgang({ zustand: 'erledigt' }), null, null, ZONE, JETZT) },
    { vorgang: vorgang({ id: 'laeuft', zustand: 'gehalten' }), darstellung: stelleDar(vorgang({ zustand: 'gehalten' }), ausgang({ status: 'gehalten', haltenBis: new Date(JETZT.getTime() + 30_000) }), null, ZONE, JETZT) },
    { vorgang: vorgang({ id: 'wartet', zustand: 'warte_auf_mich' }), darstellung: stelleDar(vorgang({ zustand: 'warte_auf_mich' }), ausgang(), null, ZONE, JETZT) },
  ];

  const sortiert = sortiere(eintraege);
  assert.deepEqual(
    sortiert.map((e) => e.vorgang.id),
    ['wartet', 'laeuft', 'alt'],
  );
});
