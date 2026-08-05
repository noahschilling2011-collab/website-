import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  antwortBetreff,
  antwortHeader,
  formatiereReferenzen,
  normalisiereMessageId,
  parseReferenzen,
  threadSchluessel,
} from './threading';

test('Message-IDs werden von spitzen Klammern befreit', () => {
  assert.equal(normalisiereMessageId('<abc@example.de>'), 'abc@example.de');
  assert.equal(normalisiereMessageId('  <abc@example.de>  '), 'abc@example.de');
  assert.equal(normalisiereMessageId('abc@example.de'), 'abc@example.de');
  assert.equal(normalisiereMessageId(null), null);
  assert.equal(normalisiereMessageId(''), null);
});

test('References wird als Liste gelesen und geschrieben', () => {
  const roh = '<a@x.de> <b@x.de>\r\n <c@x.de>';
  assert.deepEqual(parseReferenzen(roh), ['a@x.de', 'b@x.de', 'c@x.de']);
  assert.equal(formatiereReferenzen(['a@x.de', 'b@x.de']), '<a@x.de> <b@x.de>');
  assert.deepEqual(parseReferenzen(null), []);
});

test('Thread-Schluessel ist die Wurzel der Kette, nicht die letzte Nachricht', () => {
  const schluessel = threadSchluessel({
    messageId: '<c@x.de>',
    inReplyTo: '<b@x.de>',
    referenzen: '<a@x.de> <b@x.de>',
  });
  assert.equal(schluessel, 'a@x.de');
});

test('Ohne Kette ist die eigene Message-ID die Wurzel', () => {
  assert.equal(threadSchluessel({ messageId: '<neu@x.de>' }), 'neu@x.de');
});

test('Der Schluessel bleibt ueber den ganzen Thread stabil', () => {
  // Drei Nachrichten desselben Threads muessen denselben Schluessel liefern,
  // sonst zerfaellt ein Vorgang in mehrere Zeilen auf dem Bildschirm.
  const erste = threadSchluessel({ messageId: '<a@x.de>' });
  const zweite = threadSchluessel({
    messageId: '<b@x.de>',
    inReplyTo: '<a@x.de>',
    referenzen: '<a@x.de>',
  });
  const dritte = threadSchluessel({
    messageId: '<c@x.de>',
    inReplyTo: '<b@x.de>',
    referenzen: '<a@x.de> <b@x.de>',
  });
  assert.equal(erste, 'a@x.de');
  assert.equal(zweite, 'a@x.de');
  assert.equal(dritte, 'a@x.de');
});

test('Antwortheader haengt die beantwortete Nachricht an die Kette', () => {
  const header = antwortHeader({ messageId: '<b@x.de>', referenzen: '<a@x.de>' });
  assert.equal(header.inReplyTo, 'b@x.de');
  assert.equal(header.referenzen, '<a@x.de> <b@x.de>');
});

test('Lange Ketten behalten die Wurzel und die letzten Glieder', () => {
  const viele = Array.from({ length: 80 }, (_, i) => `<m${i}@x.de>`).join(' ');
  const header = antwortHeader({ messageId: '<letzte@x.de>', referenzen: viele }, 50);
  const kette = parseReferenzen(header.referenzen);
  assert.equal(kette.length, 50, 'die Kette muss auf 50 gekuerzt werden');
  assert.equal(kette[0], 'm0@x.de', 'die Wurzel muss erhalten bleiben');
  assert.equal(kette.at(-1), 'letzte@x.de', 'die neueste muss am Ende stehen');
});

test('Betreff stapelt keine Praefixe', () => {
  assert.equal(antwortBetreff('Termin Jonas'), 'Re: Termin Jonas');
  assert.equal(antwortBetreff('Re: Termin Jonas'), 'Re: Termin Jonas');
  assert.equal(antwortBetreff('AW: Re: Termin Jonas'), 'Re: Termin Jonas');
  assert.equal(antwortBetreff('WG: Verordnung'), 'Re: Verordnung');
});
