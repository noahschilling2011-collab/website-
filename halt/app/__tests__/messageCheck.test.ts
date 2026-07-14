import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkMessage } from '../src/lib/messageCheck.ts';

test('a plain friendly message is OK', () => {
  const r = checkMessage('Hallo Oma, wir sehen uns am Sonntag zum Kaffee. Liebe Grüße!');
  assert.equal(r.level, 'ok');
  assert.equal(r.reasons.length, 0);
});

test('the grandchild scam is flagged as alert', () => {
  const r = checkMessage(
    'Hallo Oma, ich bin es, dein Enkel. Mein Handy ist kaputt, das ist meine neue Nummer. ' +
      'Ich hatte einen Unfall und brauche dringend Geld. Bitte sag niemandem etwas.',
  );
  assert.equal(r.level, 'alert');
  assert.ok(r.reasons.length >= 2);
});

test('a fake-bank verification message is flagged', () => {
  const r = checkMessage(
    'Ihr PayPal Konto wurde gesperrt. Bitte verifizieren Sie sofort unter https://paypa1-secure.example',
  );
  assert.equal(r.level, 'alert');
});

test('a single mild pattern is a watch, not an alert', () => {
  const r = checkMessage('Bitte antworte umgehend, es ist wichtig.');
  assert.equal(r.level, 'watch');
  assert.equal(r.reasons.length, 1);
});
