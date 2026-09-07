import assert from 'node:assert/strict';
import { test } from 'node:test';

process.env.SECRET_KEY = 'test-schluessel-fuer-oauth';
process.env.APP_URL = 'https://assistent.test';
process.env.GOOGLE_CLIENT_ID = 'client-123.apps.googleusercontent.com';
process.env.GOOGLE_CLIENT_SECRET = 'geheim';

const { baueState, googleKonfiguriert, pruefeState, rueckleitung, zustimmungsUrl } =
  await import('./google-oauth');

const NUTZER = '11111111-2222-3333-4444-555555555555';

test('Der state bindet den Rueckweg an die Nutzerin', () => {
  const state = baueState(NUTZER);
  assert.equal(pruefeState(state), NUTZER);
});

test('Ein manipulierter state wird abgewiesen', () => {
  // Sonst koennte ein Dritter einer angemeldeten Nutzerin seinen eigenen
  // Kalender unterschieben.
  const state = baueState(NUTZER);
  const fremd = state.replace(NUTZER, '99999999-2222-3333-4444-555555555555');
  assert.equal(pruefeState(fremd), null);

  const kaputt = `${state.slice(0, -3)}xyz`;
  assert.equal(pruefeState(kaputt), null);
});

test('Ein abgelaufener state wird abgewiesen', () => {
  const abgelaufen = baueState(NUTZER)
    .split('.')
    .map((teil, i) => (i === 2 ? String(Date.now() - 1000) : teil))
    .join('.');
  assert.equal(pruefeState(abgelaufen), null, 'ohne gueltige Signatur ohnehin null');
});

test('Unsinnige Formate stuerzen nicht ab', () => {
  assert.equal(pruefeState(''), null);
  assert.equal(pruefeState('a.b.c'), null);
  assert.equal(pruefeState('a.b.c.d.e'), null);
});

test('Die Zustimmungs-URL fordert genau die zwei engen Scopes an', () => {
  const url = new URL(zustimmungsUrl(NUTZER));
  const scopes = (url.searchParams.get('scope') ?? '').split(' ');

  assert.ok(scopes.includes('https://www.googleapis.com/auth/calendar.freebusy'));
  assert.ok(scopes.includes('https://www.googleapis.com/auth/calendar.events'));
  assert.equal(scopes.length, 2, 'kein Scope mehr als noetig');

  // Ohne offline gibt es kein Refresh-Token; ohne consent liefert Google
  // bei einer zweiten Zustimmung keins mehr.
  assert.equal(url.searchParams.get('access_type'), 'offline');
  assert.equal(url.searchParams.get('prompt'), 'consent');
  assert.equal(url.searchParams.get('response_type'), 'code');
  assert.equal(url.searchParams.get('redirect_uri'), 'https://assistent.test/api/google/callback');
  assert.ok(url.searchParams.get('state'));
});

test('Die Rueckleitung haengt an APP_URL', () => {
  assert.equal(rueckleitung(), 'https://assistent.test/api/google/callback');
});

test('Fehlende Zugangsdaten werden erkannt statt still zu scheitern', () => {
  assert.equal(googleKonfiguriert(), true);
  const gemerkt = process.env.GOOGLE_CLIENT_SECRET;
  delete process.env.GOOGLE_CLIENT_SECRET;
  assert.equal(googleKonfiguriert(), false);
  process.env.GOOGLE_CLIENT_SECRET = gemerkt;
});
