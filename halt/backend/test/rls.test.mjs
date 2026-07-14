// End-to-end row-level-security test: drives the real Express app over HTTP and
// proves that a token only ever reaches its own user's data.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { rmSync } from 'node:fs';
import { app } from '../src/server.js';

let server;
let base;

before(async () => {
  server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://localhost:${server.address().port}`;
});

after(() => {
  server.close();
  rmSync(new URL('../data/users.json', import.meta.url), { force: true });
  rmSync(new URL('../data/userdata.json', import.meta.url), { force: true });
});

async function call(path, { token, method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

async function signup(email) {
  const r = await call('/auth/signup', { method: 'POST', body: { email, password: 'meinpasswort1' } });
  return r.body.token;
}

test('data endpoints reject requests without a valid token', async () => {
  assert.equal((await call('/me/profile')).status, 401);
  assert.equal((await call('/me/alerts', { token: 'garbage' })).status, 401);
  assert.equal((await call('/demo-scan', { method: 'POST', body: {} })).status, 401);
});

test('two users see only their own profile and alerts', async () => {
  const now = new Date().getTime();
  const tokenA = await signup(`a_${now}@x.de`);
  const tokenB = await signup(`b_${now}@x.de`);

  await call('/me/profile', { token: tokenA, method: 'PUT', body: { person: 'Oma A', contacts: [{ name: 'Tochter', phone: '+49111' }] } });
  await call('/me/profile', { token: tokenB, method: 'PUT', body: { person: 'Opa B', contacts: [{ name: 'Sohn', phone: '+49222' }] } });

  // Each token reads its own profile — never the other's.
  assert.equal((await call('/me/profile', { token: tokenA })).body.person, 'Oma A');
  assert.equal((await call('/me/profile', { token: tokenB })).body.person, 'Opa B');

  // A scans; only A gets alerts.
  const scan = await call('/demo-scan', { token: tokenA, method: 'POST', body: {} });
  assert.equal(scan.body.escalated, 3);

  assert.equal((await call('/me/alerts', { token: tokenA })).body.alerts.length, 3);
  assert.equal((await call('/me/alerts', { token: tokenB })).body.alerts.length, 0);
});

test('a user cannot read a bank requisition they did not create', async () => {
  const token = await signup(`c_${new Date().getTime()}@x.de`);
  // Not the owner's requisition id -> 403 (before any bank call). GoCardless is
  // unconfigured here, so the ownership guard is what must reject it.
  const r = await call('/connect/status/someone-elses-req', { token });
  assert.equal(r.status, 403);
});
