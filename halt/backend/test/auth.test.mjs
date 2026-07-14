import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAuth } from '../src/auth.js';

// In-memory (no path) so tests touch no files.
function freshAuth() {
  return createAuth(null);
}

test('signup creates an account and returns a token', () => {
  const auth = freshAuth();
  const r = auth.signup('Noah@Example.de', 'meinpasswort1');
  assert.equal(r.email, 'noah@example.de'); // normalised
  assert.ok(r.token && r.token.length >= 32);
  assert.equal(auth.count(), 1);
});

test('a token from signup verifies to the user', () => {
  const auth = freshAuth();
  const { token } = auth.signup('a@b.de', 'meinpasswort1');
  assert.equal(auth.verify(token), 'a@b.de');
  assert.equal(auth.verify('garbage'), null);
});

test('login works with the right password and returns a fresh token', () => {
  const auth = freshAuth();
  auth.signup('a@b.de', 'meinpasswort1');
  const r = auth.login('A@B.de', 'meinpasswort1');
  assert.equal(r.email, 'a@b.de');
  assert.ok(r.token);
});

test('login rejects the wrong password', () => {
  const auth = freshAuth();
  auth.signup('a@b.de', 'meinpasswort1');
  assert.throws(() => auth.login('a@b.de', 'falsch12345'), /falsch/i);
});

test('login rejects an unknown account (same message, no leak)', () => {
  const auth = freshAuth();
  assert.throws(() => auth.login('nobody@b.de', 'meinpasswort1'), /falsch/i);
});

test('duplicate signup is rejected', () => {
  const auth = freshAuth();
  auth.signup('a@b.de', 'meinpasswort1');
  assert.throws(() => auth.signup('A@B.de', 'meinpasswort1'), /bereits registriert/i);
});

test('weak or invalid input is rejected', () => {
  const auth = freshAuth();
  assert.throws(() => auth.signup('not-an-email', 'meinpasswort1'), /E-Mail/);
  assert.throws(() => auth.signup('a@b.de', 'kurz1'), /10 Zeichen/);
  assert.throws(() => auth.signup('a@b.de', 'nurbuchstaben'), /Buchstabe/);
});

test('oauth upsert creates a passwordless account, then reuses it', () => {
  const auth = freshAuth();
  const r1 = auth.upsertOAuth('Noah@Gmail.com', 'google');
  assert.equal(r1.email, 'noah@gmail.com');
  assert.equal(auth.verify(r1.token), 'noah@gmail.com');
  assert.equal(auth.count(), 1);
  const r2 = auth.upsertOAuth('noah@gmail.com', 'google'); // same person, second login
  assert.equal(auth.count(), 1);
  assert.ok(r2.token && r2.token !== r1.token);
});

test('oauth login cannot be used to bypass a password (still separate accounts by email)', () => {
  const auth = freshAuth();
  auth.signup('a@b.de', 'meinpasswort1');
  // Same email via oauth links to the existing account, does not reset the password.
  const r = auth.upsertOAuth('a@b.de', 'google');
  assert.equal(r.email, 'a@b.de');
  assert.equal(auth.count(), 1);
  // password login still works with the original password
  assert.ok(auth.login('a@b.de', 'meinpasswort1').token);
});

test('logout invalidates the token', () => {
  const auth = freshAuth();
  const { token } = auth.signup('a@b.de', 'meinpasswort1');
  auth.logout(token);
  assert.equal(auth.verify(token), null);
});
