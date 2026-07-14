// Escalation orchestration: assess a feed, find fresh alerts, and reach the
// trusted person. Dedup so a re-scan never re-alerts the same transaction.
//
// Both the sender (Twilio) and the seen-store are injectable, so this is fully
// testable without any network or credentials.

import { assessFeed } from './engine.js';

export function alertSummary(tx, assessment) {
  const top = assessment.signals[0]?.message ?? 'Ungewöhnliche Kontobewegung.';
  return `HALT-Warnung: ${tx.amount.toLocaleString('de-DE')} € an ${tx.payeeName}. ${top}`;
}

/**
 * @param transactions  mapped HALT transactions
 * @param opts.sender   { sms(to,body), call(to,message) } — outbound channels
 * @param opts.seen     { has(key):bool, add(key):void } — dedup store
 * @param opts.to       destination phone number (the trusted person)
 * @param opts.channel  'sms' | 'call' | 'both'
 */
export async function runScan(transactions, opts) {
  const { sender, seen, to, channel = 'both' } = opts;
  const assessments = assessFeed(transactions);
  const byId = new Map(transactions.map((t) => [t.id, t]));

  const escalated = assessments.filter((a) => a.shouldEscalate);
  const fresh = escalated.filter((a) => !seen.has(a.transactionId));

  const delivered = [];
  for (const a of fresh) {
    const tx = byId.get(a.transactionId);
    const summary = alertSummary(tx, a);
    if (to && sender) {
      if (channel === 'sms' || channel === 'both') await sender.sms(to, summary);
      if (channel === 'call' || channel === 'both') await sender.call(to, summary);
    }
    seen.add(a.transactionId);
    delivered.push({ transactionId: a.transactionId, summary, score: a.score });
  }

  return {
    total: transactions.length,
    escalated: escalated.length,
    newlyDelivered: delivered.length,
    delivered,
    alerts: escalated.map((a) => ({ ...a, transaction: byId.get(a.transactionId) })),
    // Full feed so a client can render everything, not just the alerts.
    transactions,
    assessments: assessments.map((a) => ({ ...a, transaction: byId.get(a.transactionId) })),
  };
}
