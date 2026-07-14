// ─────────────────────────────────────────────────────────────────────────────
// Mock PSD2 / Open-Banking connection.
//
// In production this is replaced by a licensed Account-Information-Service
// provider (TPP) — e.g. Tink, finAPI or GoCardless. HALT never holds its own
// banking licence; it acts as an agent of an existing TPP. See README.
//
// The shape of `fetchTransactions` mirrors what such a provider returns, so the
// swap is a one-file change: keep the signature, replace the body with a real
// API call using the user's consent token.
// ─────────────────────────────────────────────────────────────────────────────

import type { Transaction } from '../types';

// A realistic 6-week history for one protected person, plus a few recent
// movements that a scam would produce. Newest last.
const SEED: Transaction[] = [
  { id: 'h1', date: '2026-06-01T08:12:00Z', amount: 42.5, payeeName: 'REWE Markt', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' },
  { id: 'h2', date: '2026-06-02T07:00:00Z', amount: 89.9, payeeName: 'Stadtwerke', payeeIban: 'DE22222222222222222222', category: 'utilities', channel: 'standing_order' },
  { id: 'h3', date: '2026-06-05T14:30:00Z', amount: 31.2, payeeName: 'Apotheke Sonne', payeeIban: 'DE33333333333333333333', category: 'retail', channel: 'card' },
  { id: 'h4', date: '2026-06-09T10:05:00Z', amount: 200.0, payeeName: 'Enkel Max', payeeIban: 'DE44444444444444444444', category: 'transfer', channel: 'sepa' },
  { id: 'h5', date: '2026-06-12T16:20:00Z', amount: 60.0, payeeName: 'ATM Sparkasse', payeeIban: 'DE55555555555555555555', category: 'cash_withdrawal', channel: 'atm' },
  { id: 'h6', date: '2026-06-18T09:45:00Z', amount: 54.1, payeeName: 'REWE Markt', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' },
  { id: 'h7', date: '2026-06-25T11:00:00Z', amount: 75.0, payeeName: 'Friseur Schmidt', payeeIban: 'DE66666666666666666666', category: 'retail', channel: 'card' },
  // ── The pattern of an ongoing scam: first crypto payment, then escalating ──
  { id: 's1', date: '2026-07-11T13:10:00Z', amount: 480.0, payeeName: 'BitTrade Ltd', payeeIban: 'LT991111222233334444', category: 'crypto', channel: 'instant' },
  { id: 's2', date: '2026-07-12T15:40:00Z', amount: 1500.0, payeeName: 'BitTrade Ltd', payeeIban: 'LT991111222233334444', category: 'crypto', channel: 'instant' },
  { id: 's3', date: '2026-07-13T09:20:00Z', amount: 3200.0, payeeName: 'Secure Wallet SA', payeeIban: 'ES881111222233334444', category: 'crypto', channel: 'instant' },
];

export interface BankConnection {
  provider: string;
  consentValidUntil: string;
}

/** Simulates the consent + connection handshake of a real TPP. */
export async function connectBank(): Promise<BankConnection> {
  await new Promise((r) => setTimeout(r, 900));
  return { provider: 'HALT-Demo-Bank (Mock TPP)', consentValidUntil: '2026-10-14' };
}

/**
 * Fetch the account's transactions.
 * PRODUCTION: replace body with a call to your TPP using the consent token.
 */
export async function fetchTransactions(): Promise<Transaction[]> {
  await new Promise((r) => setTimeout(r, 600));
  return [...SEED];
}
