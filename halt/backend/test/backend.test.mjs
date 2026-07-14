import { test } from 'node:test';
import assert from 'node:assert/strict';

import { assessFeed, assess, buildBaseline } from '../src/engine.js';
import { mapGoCardlessTransaction, mapGoCardlessResponse, inferCategory } from '../src/mapTransactions.js';
import { runScan, alertSummary } from '../src/notify.js';
import { memorySeenStore } from '../src/store.js';
import { SEED } from '../src/seed.js';

// ── engine parity ─────────────────────────────────────────────────────────────
test('engine escalates the three crypto scam payments in the seed', () => {
  const feed = assessFeed(SEED);
  const escalated = feed.filter((a) => a.shouldEscalate).map((a) => a.transactionId).sort();
  assert.deepEqual(escalated, ['s1', 's2', 's3']);
});

test('a known payee, normal amount does not escalate', () => {
  const b = buildBaseline(SEED);
  const a = assess({ id: 'x', date: '2026-07-20T09:00:00Z', amount: 44, payeeName: 'REWE Markt', payeeIban: 'DE11111111111111111111', category: 'groceries' }, b);
  assert.equal(a.shouldEscalate, false);
});

// ── GoCardless mapping ────────────────────────────────────────────────────────
test('maps a GoCardless debit to a positive outgoing HALT transaction', () => {
  const tx = mapGoCardlessTransaction({
    transactionId: 'gc1',
    bookingDate: '2026-07-13',
    transactionAmount: { amount: '-3200.00', currency: 'EUR' },
    creditorName: 'Secure Wallet SA',
    creditorAccount: { iban: 'ES881111222233334444' },
  });
  assert.equal(tx.amount, 3200); // sign flipped: debit -> outgoing positive
  assert.equal(tx.payeeName, 'Secure Wallet SA');
  assert.equal(tx.payeeIban, 'ES881111222233334444');
});

test('incoming credit maps to a negative amount (ignored by the engine)', () => {
  const tx = mapGoCardlessTransaction({
    transactionId: 'gc2',
    bookingDate: '2026-07-01',
    transactionAmount: { amount: '1500.00', currency: 'EUR' },
    debtorName: 'Rentenkasse',
  });
  assert.equal(tx.amount, -1500);
  assert.equal(assess(tx, buildBaseline(SEED)).shouldEscalate, false);
});

test('category inference detects high-risk merchants', () => {
  assert.equal(inferCategory('Binance', 'purchase'), 'crypto');
  assert.equal(inferCategory('Western Union', ''), 'money_remittance');
  assert.equal(inferCategory('REWE Markt', ''), 'groceries');
  assert.equal(inferCategory('Random Person', ''), 'transfer');
});

test('a crypto payment fetched via GoCardless escalates end-to-end', () => {
  const mapped = mapGoCardlessResponse({
    transactions: {
      booked: [
        { transactionId: 'g1', bookingDate: '2026-07-13', transactionAmount: { amount: '-2500.00' }, creditorName: 'Binance', creditorAccount: { iban: 'MT84MALT011000012345MTLCAST001S' } },
      ],
    },
  });
  const feed = assessFeed([...SEED, ...mapped]);
  const a = feed.find((x) => x.transactionId === 'g1');
  assert.equal(a.shouldEscalate, true);
});

// ── notify + dedup ────────────────────────────────────────────────────────────
function fakeSender() {
  const sent = [];
  return {
    sent,
    sms: async (to, body) => sent.push({ ch: 'sms', to, body }),
    call: async (to, msg) => sent.push({ ch: 'call', to, msg }),
  };
}

test('runScan alerts each escalated tx once and dedupes on re-scan', async () => {
  const seen = memorySeenStore();
  const sender = fakeSender();
  const first = await runScan(SEED, { sender, seen, to: '+490000', channel: 'both' });
  assert.equal(first.escalated, 3);
  assert.equal(first.newlyDelivered, 3);
  // both channels per alert -> 6 outbound messages
  assert.equal(sender.sent.length, 6);

  const second = await runScan(SEED, { sender, seen, to: '+490000', channel: 'both' });
  assert.equal(second.escalated, 3);
  assert.equal(second.newlyDelivered, 0); // deduped
  assert.equal(sender.sent.length, 6); // nothing new sent
});

test('alertSummary includes amount, payee and reason', () => {
  const feed = assessFeed(SEED);
  const a = feed.find((x) => x.transactionId === 's3');
  const s = alertSummary(SEED.find((t) => t.id === 's3'), a);
  assert.match(s, /3\.200/);
  assert.match(s, /Secure Wallet SA/);
});
