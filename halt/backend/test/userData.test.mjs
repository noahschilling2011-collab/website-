import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createUserData } from '../src/userData.js';

test('two users have fully isolated profiles', () => {
  const d = createUserData(null);
  d.setProfile('a@x', { person: 'Oma A', contacts: [{ name: 'Tochter', phone: '+49111' }] });
  d.setProfile('b@x', { person: 'Opa B', contacts: [] });
  assert.equal(d.getProfile('a@x').person, 'Oma A');
  assert.equal(d.getProfile('b@x').person, 'Opa B');
});

test('alert destination is this user\'s own first VERIFIED contact', () => {
  const d = createUserData(null);
  d.setProfile('a@x', { person: 'Oma A', contacts: [{ name: 'T', phone: '+49111' }] });
  d.setProfile('b@x', { person: 'Opa B', contacts: [] });
  assert.equal(d.alertPhone('a@x'), null); // exists but unverified -> no alerts
  d.markPhoneVerified('a@x', '+49111');
  assert.equal(d.alertPhone('a@x'), '+49111');
  assert.equal(d.alertPhone('b@x'), null);
});

test('seen-store is per-user', () => {
  const d = createUserData(null);
  const a = d.seenStore('a');
  const b = d.seenStore('b');
  a.add('t1');
  assert.equal(a.has('t1'), true);
  assert.equal(b.has('t1'), false); // B never marked it
});

test('alerts are per-user', () => {
  const d = createUserData(null);
  d.setAlerts('a', [{ transactionId: 's1' }, { transactionId: 's2' }]);
  assert.equal(d.getAlerts('a').length, 2);
  assert.equal(d.getAlerts('b').length, 0);
});

test('an unknown user reads empty defaults, never another user\'s data', () => {
  const d = createUserData(null);
  d.setProfile('a@x', { person: 'Secret' });
  assert.equal(d.getProfile('stranger@x').person, null);
  assert.deepEqual(d.getProfile('stranger@x').contacts, []);
});
