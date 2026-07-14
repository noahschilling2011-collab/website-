// ─────────────────────────────────────────────────────────────────────────────
// HALT risk engine — the actual product.
//
// This is deliberately self-contained (no runtime imports) so it can be tested
// in isolation and reused on a server, in a function, or on-device.
//
// Design principle from the strategy: the engine NEVER concludes "this is fraud".
// It only scores how far a movement departs from the person's own normal
// behaviour, and decides one thing: whether to wake up a human. A false alarm is
// a briefly annoyed daughter. A missed one can be a life's savings.
// ─────────────────────────────────────────────────────────────────────────────

import type {
  Transaction,
  Baseline,
  RiskSignal,
  Assessment,
  RiskLevel,
  Severity,
} from '../types';

const HIGH_RISK_CATEGORIES = new Set([
  'crypto',
  'precious_metals',
  'gift_card',
  'money_remittance',
]);

const SEVERITY_WEIGHT: Record<Severity, number> = {
  low: 15,
  medium: 35,
  high: 60,
};

/** Score at/above which a human is called. Tunable — set to catch, not to be quiet. */
export const ESCALATION_THRESHOLD = 60;
/** Score at/above which we keep a quiet eye on it but do not call. */
export const WATCH_THRESHOLD = 30;

function ibanCountry(iban: string): string {
  return (iban || '').trim().slice(0, 2).toUpperCase();
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

/**
 * Derive a behavioural baseline from a person's own history.
 * Only outgoing (debit) transactions shape the baseline.
 */
export function buildBaseline(history: Transaction[]): Baseline {
  const outgoing = history.filter((t) => t.amount > 0);
  const amounts = outgoing.map((t) => t.amount);
  const knownPayees = new Set(outgoing.map((t) => t.payeeIban).filter(Boolean));
  const homeCountries = new Set(outgoing.map((t) => ibanCountry(t.payeeIban)).filter(Boolean));
  const hasHighRiskHistory = outgoing.some((t) => HIGH_RISK_CATEGORIES.has(t.category));

  return {
    knownPayees,
    maxOutgoing: amounts.length ? Math.max(...amounts) : 0,
    medianOutgoing: median(amounts),
    hasHighRiskHistory,
    homeCountries: homeCountries.size ? homeCountries : new Set(['DE']),
  };
}

// ── Individual rules ─────────────────────────────────────────────────────────
// Each rule is a pure function: it looks at one transaction against the baseline
// (and, where needed, the recent window) and returns a signal or null.

type Rule = (tx: Transaction, ctx: RuleContext) => RiskSignal | null;

interface RuleContext {
  baseline: Baseline;
  /** Outgoing transactions in the recent window (e.g. last 24h), excluding tx itself. */
  recentOutgoing: Transaction[];
}

const eur = (n: number) => `${n.toLocaleString('de-DE', { minimumFractionDigits: 0 })} €`;

const ruleHighRiskCategory: Rule = (tx, { baseline }) => {
  if (!HIGH_RISK_CATEGORIES.has(tx.category)) return null;
  const firstEver = !baseline.hasHighRiskHistory;
  const labels: Record<string, string> = {
    crypto: 'eine Krypto-Börse',
    precious_metals: 'einen Gold-/Edelmetallhändler',
    gift_card: 'Geschenkkarten',
    money_remittance: 'einen Bargeld-Transferdienst',
  };
  return {
    rule: 'high_risk_category',
    severity: 'high',
    message: firstEver
      ? `Erste Zahlung überhaupt an ${labels[tx.category]} — ein klassischer Weg, Betrugsgeld unwiderruflich abfließen zu lassen.`
      : `Zahlung an ${labels[tx.category]}.`,
  };
};

const ruleNewPayee: Rule = (tx, { baseline }) => {
  if (baseline.knownPayees.has(tx.payeeIban)) return null;
  // A new payee alone is normal life; it only matters combined with size/category.
  const big = tx.amount > Math.max(baseline.medianOutgoing * 4, 500);
  return {
    rule: 'new_payee',
    severity: big ? 'high' : 'low',
    message: big
      ? `${eur(tx.amount)} an einen völlig neuen Empfänger (${tx.payeeName}) — deutlich über dem üblichen Rahmen.`
      : `Neuer Empfänger: ${tx.payeeName}.`,
  };
};

const ruleUnusualAmount: Rule = (tx, { baseline }) => {
  if (baseline.maxOutgoing === 0) return null;
  if (tx.amount <= baseline.maxOutgoing * 1.5) return null;
  return {
    rule: 'unusual_amount',
    severity: 'high',
    message: `${eur(tx.amount)} ist mehr als das 1,5-fache der bisher höchsten Zahlung (${eur(baseline.maxOutgoing)}).`,
  };
};

const ruleForeignCountry: Rule = (tx, { baseline }) => {
  const country = ibanCountry(tx.payeeIban);
  if (!country || baseline.homeCountries.has(country)) return null;
  const big = tx.amount > 300;
  return {
    rule: 'foreign_country',
    severity: big ? 'medium' : 'low',
    message: `Zahlung ins Ausland (${country}), untypisch für dieses Konto.`,
  };
};

const ruleVelocity: Rule = (tx, { baseline, recentOutgoing }) => {
  const newPayeeCount = recentOutgoing.filter(
    (t) => !baseline.knownPayees.has(t.payeeIban),
  ).length;
  // tx itself is a new payee if not known; count it too
  const total = newPayeeCount + (baseline.knownPayees.has(tx.payeeIban) ? 0 : 1);
  if (total < 3) return null;
  return {
    rule: 'velocity',
    severity: 'high',
    message: `${total} Zahlungen an neue Empfänger innerhalb kurzer Zeit — typisches Muster unter Anleitung eines Betrügers.`,
  };
};

const ruleCashSpike: Rule = (tx, { baseline, recentOutgoing }) => {
  if (tx.category !== 'cash_withdrawal') return null;
  const recentCash = recentOutgoing
    .filter((t) => t.category === 'cash_withdrawal')
    .reduce((sum, t) => sum + t.amount, 0);
  const totalCash = recentCash + tx.amount;
  const threshold = Math.max(baseline.medianOutgoing * 5, 1000);
  if (totalCash < threshold) return null;
  return {
    rule: 'cash_spike',
    severity: 'high',
    message: `${eur(totalCash)} Bargeld in kurzer Zeit abgehoben — weit über dem Üblichen. Bargeldübergabe ist eine häufige Betrugsmasche.`,
  };
};

const RULES: Rule[] = [
  ruleHighRiskCategory,
  ruleNewPayee,
  ruleUnusualAmount,
  ruleForeignCountry,
  ruleVelocity,
  ruleCashSpike,
];

function scoreToLevel(score: number): RiskLevel {
  if (score >= ESCALATION_THRESHOLD) return 'alert';
  if (score >= WATCH_THRESHOLD) return 'watch';
  return 'ok';
}

/**
 * Assess a single transaction against a baseline and the recent window.
 *
 * @param tx              the transaction to assess
 * @param baseline        derived from the person's own history (see buildBaseline)
 * @param recentOutgoing  other outgoing transactions in the recent window (e.g. 24h)
 */
export function assess(
  tx: Transaction,
  baseline: Baseline,
  recentOutgoing: Transaction[] = [],
): Assessment {
  if (tx.amount <= 0) {
    // Incoming money is never a fraud-outflow risk in this model.
    return { transactionId: tx.id, signals: [], score: 0, level: 'ok', shouldEscalate: false };
  }

  const ctx: RuleContext = { baseline, recentOutgoing };
  const signals: RiskSignal[] = [];
  for (const rule of RULES) {
    const signal = rule(tx, ctx);
    if (signal) signals.push(signal);
  }

  // Combine signals. We take the strongest signal at full weight and add a
  // diminishing contribution from the rest — multiple weak hints shouldn't
  // out-shout one strong one, but corroboration should still push the score up.
  const weights = signals.map((s) => SEVERITY_WEIGHT[s.severity]).sort((a, b) => b - a);
  let score = 0;
  weights.forEach((w, i) => {
    score += i === 0 ? w : w * 0.5;
  });
  score = Math.min(100, Math.round(score));

  const level = scoreToLevel(score);
  return {
    transactionId: tx.id,
    signals,
    score,
    level,
    shouldEscalate: level === 'alert',
  };
}

/**
 * Convenience: assess a whole feed at once, computing each transaction's recent
 * window on the fly. Returns assessments newest-first.
 */
export function assessFeed(history: Transaction[], windowHours = 24): Assessment[] {
  const baseline = buildBaseline(history);
  const byDateAsc = [...history].sort(
    (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
  );

  const assessments = byDateAsc.map((tx, idx) => {
    const txTime = new Date(tx.date).getTime();
    const recentOutgoing = byDateAsc
      .slice(0, idx)
      .filter(
        (t) =>
          t.amount > 0 &&
          txTime - new Date(t.date).getTime() <= windowHours * 3600_000,
      );
    return assess(tx, baseline, recentOutgoing);
  });

  return assessments.reverse();
}
