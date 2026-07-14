import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createOAuth, validateGoogleClaims } from '../src/oauth.js';

const CID = 'client-123.apps.googleusercontent.com';
const cfg = {
  appUrl: 'https://halt.example',
  oauth: { google: { clientId: CID, clientSecret: 'secret' }, apple: {} },
};
const NOW = 1_800_000_000_000;
const future = String(Math.floor(NOW / 1000) + 3600);

test('validateGoogleClaims accepts a good token', () => {
  const r = validateGoogleClaims(
    { aud: CID, iss: 'accounts.google.com', exp: future, email: 'A@B.de', email_verified: true },
    CID, NOW,
  );
  assert.equal(r.email, 'a@b.de');
  assert.equal(r.provider, 'google');
});

test('validateGoogleClaims rejects a token for another app (aud)', () => {
  assert.throws(() => validateGoogleClaims(
    { aud: 'someone-else', iss: 'accounts.google.com', exp: future, email: 'a@b.de', email_verified: true },
    CID, NOW,
  ), /aud/);
});

test('validateGoogleClaims rejects an expired token', () => {
  assert.throws(() => validateGoogleClaims(
    { aud: CID, iss: 'accounts.google.com', exp: '1', email: 'a@b.de', email_verified: true },
    CID, NOW,
  ), /abgelaufen/);
});

test('validateGoogleClaims rejects an unverified email', () => {
  assert.throws(() => validateGoogleClaims(
    { aud: CID, iss: 'accounts.google.com', exp: future, email: 'a@b.de', email_verified: false },
    CID, NOW,
  ), /verifiziert/);
});

test('state is single-use and rejects unknown/expired values', () => {
  const o = createOAuth(cfg);
  const s = o.newState(NOW);
  assert.equal(o.consumeState(s, NOW), true);
  assert.equal(o.consumeState(s, NOW), false); // already consumed
  assert.equal(o.consumeState('never-issued', NOW), false);
  const s2 = o.newState(NOW);
  assert.equal(o.consumeState(s2, NOW + 11 * 60 * 1000), false); // expired
});

test('googleStartUrl carries the right client_id, redirect and state', () => {
  const o = createOAuth(cfg);
  const url = o.googleStartUrl('xyz');
  assert.match(url, /accounts\.google\.com/);
  assert.match(url, new RegExp(`client_id=${CID.replace(/\./g, '\\.')}`));
  assert.match(url, /redirect_uri=https%3A%2F%2Fhalt\.example%2Fauth%2Fgoogle%2Fcallback/);
  assert.match(url, /state=xyz/);
});

test('googleExchange exchanges code -> token -> validated email (injected fetch)', async () => {
  const o = createOAuth(cfg);
  const fakeFetch = async (url) => {
    if (String(url).includes('tokeninfo')) {
      return { ok: true, json: async () => ({ aud: CID, iss: 'accounts.google.com', exp: future, email: 'noah@gmail.com', email_verified: 'true' }) };
    }
    return { ok: true, json: async () => ({ id_token: 'ID' }) };
  };
  const r = await o.googleExchange('the-code', NOW, fakeFetch);
  assert.equal(r.email, 'noah@gmail.com');
});

test('googleExchange rejects a token minted for another client', async () => {
  const o = createOAuth(cfg);
  const fakeFetch = async (url) => String(url).includes('tokeninfo')
    ? { ok: true, json: async () => ({ aud: 'attacker', iss: 'accounts.google.com', exp: future, email: 'x@y.de', email_verified: true }) }
    : { ok: true, json: async () => ({ id_token: 'ID' }) };
  await assert.rejects(() => o.googleExchange('code', NOW, fakeFetch), /aud/);
});
