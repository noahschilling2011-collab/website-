import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPhoneVerify, isValidPhone, normalizePhone } from '../src/phoneVerify.js';
import { createUserData } from '../src/userData.js';

const NOW = 1_800_000_000_000;
const fixed = (code) => ({ random6: () => code });

test('phone normalisation and validity', () => {
  assert.equal(normalizePhone('+49 170 123-456'), '+49170123456');
  assert.equal(isValidPhone('+49 170 1234567'), true);
  assert.equal(isValidPhone('abc'), false);
});

test('request -> verify happy path, code is single-use', () => {
  const v = createPhoneVerify(fixed('284915'));
  const code = v.requestCode('u1', '+491701234567', NOW);
  assert.equal(code, '284915');
  assert.equal(v.verifyCode('u1', '+491701234567', '284915', NOW + 1000), true);
  // second use fails — consumed
  assert.throws(() => v.verifyCode('u1', '+491701234567', '284915', NOW + 2000), /bereits verwendet|Kein Code/);
});

test('wrong code rejected; too many attempts kills the code', () => {
  const v = createPhoneVerify(fixed('111111'));
  v.requestCode('u1', '+491701234567', NOW);
  for (let i = 0; i < 5; i++) assert.throws(() => v.verifyCode('u1', '+491701234567', '000000', NOW), /Falscher Code/);
  assert.throws(() => v.verifyCode('u1', '+491701234567', '111111', NOW), /Zu viele Fehlversuche/);
});

test('expired code rejected', () => {
  const v = createPhoneVerify(fixed('222222'));
  v.requestCode('u1', '+491701234567', NOW);
  assert.throws(() => v.verifyCode('u1', '+491701234567', '222222', NOW + 11 * 60 * 1000), /abgelaufen/);
});

test('resend cooldown and daily quota', () => {
  const v = createPhoneVerify(fixed('333333'));
  v.requestCode('u1', '+491701234567', NOW);
  assert.throws(() => v.requestCode('u1', '+491701234567', NOW + 10_000), /warten/);
  // spaced-out sends up to the daily cap
  let t = NOW;
  for (let i = 1; i < 5; i++) { t += 2 * 60 * 1000; v.requestCode('u1', '+491701234567', t); }
  assert.throws(() => v.requestCode('u1', '+491701234567', t + 2 * 60 * 1000), /Tageslimit/);
});

test('codes are scoped per user+phone', () => {
  const v = createPhoneVerify(fixed('444444'));
  v.requestCode('u1', '+491701234567', NOW);
  // another user cannot verify u1's phone with the same code
  assert.throws(() => v.verifyCode('u2', '+491701234567', '444444', NOW), /Kein Code/);
});

test('userData: alerts only go to a VERIFIED contact', () => {
  const d = createUserData(null);
  d.setProfile('a', { person: 'Oma', contacts: [{ name: 'T', phone: '+49 170 111' }] });
  assert.equal(d.alertPhone('a'), null); // not verified yet -> nobody gets alerted
  d.markPhoneVerified('a', '+49170111'); // normalised match
  assert.equal(d.alertPhone('a'), '+49 170 111');
  assert.equal(d.isPhoneVerified('a', '+49170111'), true);
  assert.equal(d.isPhoneVerified('b', '+49170111'), false); // per-user
});
