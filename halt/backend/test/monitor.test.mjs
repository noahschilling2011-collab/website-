import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createMonitor } from '../src/monitor.js';
import { createUserData } from '../src/userData.js';
import { runScan } from '../src/notify.js';
import { mapGoCardlessResponse } from '../src/mapTransactions.js';

// A bank feed whose latest movement is a classic scam cash-out.
const FEED = {
  transactions: {
    booked: [
      { transactionId: 'n1', bookingDate: '2026-06-01', transactionAmount: { amount: '-42.50' }, creditorName: 'REWE Markt', creditorAccount: { iban: 'DE11111111111111111111' } },
      { transactionId: 'n2', bookingDate: '2026-06-10', transactionAmount: { amount: '-89.90' }, creditorName: 'Stadtwerke', creditorAccount: { iban: 'DE22222222222222222222' } },
      { transactionId: 's1', bookingDate: '2026-07-13', transactionAmount: { amount: '-2500.00' }, creditorName: 'Binance', creditorAccount: { iban: 'LT991111222233334444' } },
    ],
  },
};

function fakeGc({ failFor = new Set() } = {}) {
  return {
    calls: { req: 0, tx: 0 },
    async getRequisition(id) {
      this.calls.req += 1;
      if (failFor.has(id)) throw new Error('Bank nicht erreichbar');
      return { id, status: 'LN', accounts: ['11111111-2222-3333-4444-555555555555'] };
    },
    async getTransactions() {
      this.calls.tx += 1;
      return FEED;
    },
  };
}

function fakeSender() {
  const sent = [];
  return { sent, sms: async (to, b) => sent.push({ to, b }), call: async (to, m) => sent.push({ to, m }) };
}

function setupUser(d, uid, { reqId, verified = true } = {}) {
  d.setProfile(uid, { person: 'Oma', contacts: [{ name: 'T', phone: '+491701234567' }] });
  if (verified) d.markPhoneVerified(uid, '+491701234567');
  if (reqId) d.setRequisition(uid, reqId);
}

const deps = (d, gc, sender) => ({
  userData: d, gc, sender,
  mapResponse: mapGoCardlessResponse,
  runScan,
  channel: 'sms',
  intervalMs: 3600_000,
});

test('monitor sweeps connected users and escalates to the verified contact', async () => {
  const d = createUserData(null);
  setupUser(d, 'a', { reqId: 'req-a' });
  const gc = fakeGc();
  const sender = fakeSender();
  const m = createMonitor(deps(d, gc, sender));

  const stats = await m.tick();
  assert.equal(stats.users, 1);
  assert.equal(stats.scanned, 1);
  assert.equal(stats.alertsDelivered, 1); // the Binance movement
  assert.equal(sender.sent.length, 1);
  assert.equal(sender.sent[0].to, '+491701234567');
  assert.equal(d.getAlerts('a').length, 1);
});

test('second sweep never re-alerts the same movement (dedupe)', async () => {
  const d = createUserData(null);
  setupUser(d, 'a', { reqId: 'req-a' });
  const sender = fakeSender();
  const m = createMonitor(deps(d, fakeGc(), sender));
  await m.tick();
  const second = await m.tick();
  assert.equal(second.alertsDelivered, 0);
  assert.equal(sender.sent.length, 1); // still just the first alert
});

test('users without a bank connection are skipped', async () => {
  const d = createUserData(null);
  setupUser(d, 'a', { reqId: null });
  const gc = fakeGc();
  const m = createMonitor(deps(d, gc, fakeSender()));
  const stats = await m.tick();
  assert.equal(stats.users, 0);
  assert.equal(gc.calls.req, 0);
});

test('one broken user does not stop the sweep for the others', async () => {
  const d = createUserData(null);
  setupUser(d, 'broken', { reqId: 'req-x' });
  setupUser(d, 'ok', { reqId: 'req-ok' });
  const gc = fakeGc({ failFor: new Set(['req-x']) });
  const sender = fakeSender();
  const m = createMonitor(deps(d, gc, sender));
  const stats = await m.tick();
  assert.equal(stats.errors.length, 1);
  assert.equal(stats.errors[0].uid, 'broken');
  assert.equal(stats.scanned, 1); // 'ok' still scanned
  assert.equal(sender.sent.length, 1);
});

test('unverified contact -> alert is NOT sent but recorded in the app', async () => {
  const d = createUserData(null);
  setupUser(d, 'a', { reqId: 'req-a', verified: false });
  const sender = fakeSender();
  const m = createMonitor(deps(d, fakeGc(), sender));
  const stats = await m.tick();
  assert.equal(sender.sent.length, 0); // nothing outbound — number unverified
  assert.equal(d.getAlerts('a').length, 1); // but visible in the app
  assert.equal(stats.alertsDelivered, 1); // counted as delivered attempt (seen-marked)
});

test('status reflects the last run', async () => {
  const d = createUserData(null);
  setupUser(d, 'a', { reqId: 'req-a' });
  const m = createMonitor(deps(d, fakeGc(), fakeSender()));
  assert.equal(m.status().enabled, false);
  assert.equal(m.status().lastRunAt, null);
  await m.tick(123456);
  assert.equal(m.status().lastRunAt, 123456);
  assert.equal(m.status().lastResult.scanned, 1);
});
