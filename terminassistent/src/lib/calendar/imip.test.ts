import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ImipMailSink } from './imip';
import type { EventDraft } from './types';

function entwurf(teile: Partial<EventDraft> = {}): EventDraft {
  return {
    uid: 'abc-123@assistent.test',
    sequence: 0,
    titel: 'Ergotherapie Jonas',
    start: new Date('2026-08-18T12:00:00Z'),
    end: new Date('2026-08-18T12:45:00Z'),
    zeitzone: 'Europe/Berlin',
    teilnehmer: 'berger@example.test',
    organisator: { name: 'Katrin Weber', email: 'assistenz@assistent.test' },
    ...teile,
  };
}

function sammler() {
  const auftraege: {
    an: string;
    betreff: string;
    text: string;
    methode: string;
    ical: string;
    uid: string;
  }[] = [];
  return {
    auftraege,
    kanal: async (auftrag: (typeof auftraege)[number]) => {
      auftraege.push(auftrag);
    },
  };
}

test('Eine Einladung geht als METHOD:REQUEST in den Kanal', async () => {
  const { auftraege, kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);

  const ergebnis = await sink.create(entwurf());

  assert.equal(auftraege.length, 1);
  assert.equal(auftraege[0]!.an, 'berger@example.test');
  assert.equal(auftraege[0]!.methode, 'REQUEST');
  assert.match(auftraege[0]!.ical, /METHOD:REQUEST/);
  assert.match(auftraege[0]!.ical, /BEGIN:VEVENT/);
  assert.match(auftraege[0]!.ical, /UID:abc-123@assistent\.test/);
  assert.match(auftraege[0]!.ical, /ORGANIZER/);

  // Niemals 'placed': ob die Einladung im Kalender landet, entscheidet
  // der Empfaenger, und das ist nicht auslesbar.
  assert.equal(ergebnis.status, 'dispatched');
  assert.deepEqual(ergebnis.ref, { kind: 'icalendar_uid', value: 'abc-123@assistent.test' });
});

test('Der Sink verschickt nicht selbst, sondern nur ueber den Kanal', async () => {
  // Sonst haette dieser eine Sink die Faehigkeit, an der Haltezeit vorbei
  // Post an einen echten Menschen zu schicken.
  const { auftraege, kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);
  await sink.create(entwurf());
  assert.equal(auftraege.length, 1, 'genau ein Auftrag, kein Direktversand');
});

test('Eine Aenderung behaelt die UID und traegt die hoehere SEQUENCE', async () => {
  const { auftraege, kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);

  await sink.update(
    { kind: 'icalendar_uid', value: 'abc-123@assistent.test' },
    entwurf({ sequence: 3, start: new Date('2026-08-19T12:00:00Z') }),
  );

  assert.match(auftraege[0]!.ical, /UID:abc-123@assistent\.test/);
  assert.match(auftraege[0]!.ical, /SEQUENCE:3/);
  assert.match(auftraege[0]!.ical, /METHOD:REQUEST/);
});

test('Eine Absage ist METHOD:CANCEL mit STATUS:CANCELLED', async () => {
  const { auftraege, kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);

  await sink.cancel(
    { kind: 'icalendar_uid', value: 'abc-123@assistent.test' },
    entwurf({ sequence: 1 }),
    'Der Termin war schon vergeben.',
  );

  assert.equal(auftraege[0]!.methode, 'CANCEL');
  assert.match(auftraege[0]!.ical, /METHOD:CANCEL/);
  assert.match(auftraege[0]!.ical, /STATUS:CANCELLED/);
  assert.match(auftraege[0]!.ical, /SEQUENCE:1/);
  assert.match(auftraege[0]!.betreff, /^Abgesagt:/);
  assert.match(auftraege[0]!.text, /schon vergeben/);
});

test('Ohne Empfaenger oder Organisator wird abgebrochen statt Unsinn verschickt', async () => {
  const { kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);

  await assert.rejects(
    () => sink.create(entwurf({ teilnehmer: undefined })),
    /teilnehmer fehlt/,
  );
  // Die ORGANIZER-Adresse muss zur Absenderdomain passen; ohne Organisator
  // ist die Einladung formal unvollstaendig.
  await assert.rejects(
    () => sink.create(entwurf({ organisator: undefined })),
    /organisator fehlt/,
  );
});

test('Der Sink meldet ehrlich, was er kann', async () => {
  const { kanal } = sammler();
  const sink = new ImipMailSink('v1', kanal);
  assert.equal(sink.capabilities.confirmsPlacement, false);
  assert.equal(sink.capabilities.deliversToThirdParties, true);
});
