// Tests for the HALT risk engine.
// Runs with zero dependencies via Node's built-in runner:
//   node --experimental-strip-types --test __tests__/ruleEngine.test.ts
//
// The engine is the product, so it is the thing that gets tested.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assess,
  assessFeed,
  buildBaseline,
} from '../src/lib/ruleEngine.ts';
import type { Transaction } from '../src/types.ts';

// A boring, realistic history for an elderly person in Germany.
const HISTORY: Transaction[] = [
  { id: 'h1', date: '2026-06-01T09:00:00Z', amount: 42.5, payeeName: 'REWE', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' },
  { id: 'h2', date: '2026-06-03T09:00:00Z', amount: 89.9, payeeName: 'Stadtwerke', payeeIban: 'DE22222222222222222222', category: 'utilities', channel: 'standing_order' },
  { id: 'h3', date: '2026-06-10T09:00:00Z', amount: 120.0, payeeName: 'Apotheke Sonne', payeeIban: 'DE33333333333333333333', category: 'retail', channel: 'card' },
  { id: 'h4', date: '2026-06-15T09:00:00Z', amount: 200.0, payeeName: 'Enkel Max', payeeIban: 'DE44444444444444444444', category: 'transfer', channel: 'sepa' },
  { id: 'h5', date: '2026-06-20T09:00:00Z', amount: 60.0, payeeName: 'ATM Sparkasse', payeeIban: 'DE55555555555555555555', category: 'cash_withdrawal', channel: 'atm' },
];

test('baseline captures known payees, max and median', () => {
  const b = buildBaseline(HISTORY);
  assert.equal(b.knownPayees.has('DE11111111111111111111'), true);
  assert.equal(b.maxOutgoing, 200);
  assert.equal(b.hasHighRiskHistory, false);
  assert.equal(b.homeCountries.has('DE'), true);
});

test('a normal payment to a known payee is OK and does not escalate', () => {
  const b = buildBaseline(HISTORY);
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 47.3, payeeName: 'REWE', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' };
  const a = assess(tx, b);
  assert.equal(a.level, 'ok');
  assert.equal(a.shouldEscalate, false);
});

test('first-ever crypto payment escalates', () => {
  const b = buildBaseline(HISTORY);
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 480, payeeName: 'CoinExchange', payeeIban: 'LT99999999999999999999', category: 'crypto', channel: 'instant' };
  const a = assess(tx, b);
  assert.equal(a.level, 'alert');
  assert.equal(a.shouldEscalate, true);
  assert.ok(a.signals.some((s) => s.rule === 'high_risk_category'));
});

test('large payment to a brand-new payee escalates', () => {
  const b = buildBaseline(HISTORY);
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 4800, payeeName: 'Unbekannt GmbH', payeeIban: 'DE98989898989898989898', category: 'transfer', channel: 'instant' };
  const a = assess(tx, b);
  assert.equal(a.shouldEscalate, true);
  assert.ok(a.signals.some((s) => s.rule === 'unusual_amount' || s.rule === 'new_payee'));
});

test('a modest payment to a new payee is at most a quiet watch, never a call', () => {
  const b = buildBaseline(HISTORY);
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 35, payeeName: 'Blumen Meier', payeeIban: 'DE71717171717171717171', category: 'retail', channel: 'card' };
  const a = assess(tx, b);
  assert.equal(a.shouldEscalate, false);
  assert.notEqual(a.level, 'alert');
});

test('velocity: several new payees in a short window escalates', () => {
  const b = buildBaseline(HISTORY);
  const recent: Transaction[] = [
    { id: 'r1', date: '2026-07-01T08:00:00Z', amount: 90, payeeName: 'Neu 1', payeeIban: 'DE60606060606060606060', category: 'transfer', channel: 'instant' },
    { id: 'r2', date: '2026-07-01T08:30:00Z', amount: 90, payeeName: 'Neu 2', payeeIban: 'DE61616161616161616161', category: 'transfer', channel: 'instant' },
  ];
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 90, payeeName: 'Neu 3', payeeIban: 'DE62626262626262626262', category: 'transfer', channel: 'instant' };
  const a = assess(tx, b, recent);
  assert.ok(a.signals.some((s) => s.rule === 'velocity'));
  assert.equal(a.shouldEscalate, true);
});

test('cash spike: large cash withdrawals in a short window escalates', () => {
  const b = buildBaseline(HISTORY);
  const recent: Transaction[] = [
    { id: 'r1', date: '2026-07-01T08:00:00Z', amount: 500, payeeName: 'ATM', payeeIban: 'DE55555555555555555555', category: 'cash_withdrawal', channel: 'atm' },
  ];
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: 700, payeeName: 'ATM', payeeIban: 'DE55555555555555555555', category: 'cash_withdrawal', channel: 'atm' };
  const a = assess(tx, b, recent);
  assert.ok(a.signals.some((s) => s.rule === 'cash_spike'));
  assert.equal(a.shouldEscalate, true);
});

test('incoming money is never a risk', () => {
  const b = buildBaseline(HISTORY);
  const tx: Transaction = { id: 't', date: '2026-07-01T09:00:00Z', amount: -1500, payeeName: 'Rente', payeeIban: 'DE12121212121212121212', category: 'other', channel: 'sepa' };
  const a = assess(tx, b);
  assert.equal(a.score, 0);
  assert.equal(a.shouldEscalate, false);
});

test('assessFeed returns one assessment per transaction, newest first', () => {
  const feed = assessFeed(HISTORY);
  assert.equal(feed.length, HISTORY.length);
  // newest-first ordering: first element corresponds to the latest date
  assert.equal(feed[0].transactionId, 'h5');
});
