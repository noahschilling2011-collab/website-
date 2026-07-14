// HALT risk engine — server-side port of halt/app/src/lib/ruleEngine.ts.
// This is where the trigger belongs in production: it runs on the account feed
// in the background, so it works even when the protected person never touches a
// phone. Same rules, same thresholds as the tested app engine.

export const HIGH_RISK = new Set(['crypto', 'precious_metals', 'gift_card', 'money_remittance']);
const W = { low: 15, medium: 35, high: 60 };
export const ESCALATION_THRESHOLD = 60;
export const WATCH_THRESHOLD = 30;

const eur = (n) => `${n.toLocaleString('de-DE')} €`;
const ibanCountry = (iban) => (iban || '').trim().slice(0, 2).toUpperCase();

function median(a) {
  if (!a.length) return 0;
  const s = [...a].sort((x, y) => x - y);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

export function buildBaseline(history) {
  const out = history.filter((t) => t.amount > 0);
  const amts = out.map((t) => t.amount);
  const homeCountries = new Set(out.map((t) => ibanCountry(t.payeeIban)).filter(Boolean));
  return {
    knownPayees: new Set(out.map((t) => t.payeeIban).filter(Boolean)),
    maxOutgoing: amts.length ? Math.max(...amts) : 0,
    medianOutgoing: median(amts),
    hasHighRiskHistory: out.some((t) => HIGH_RISK.has(t.category)),
    homeCountries: homeCountries.size ? homeCountries : new Set(['DE']),
  };
}

const CAT_LABEL = {
  crypto: 'eine Krypto-Börse',
  precious_metals: 'einen Gold-/Edelmetallhändler',
  gift_card: 'Geschenkkarten',
  money_remittance: 'einen Bargeld-Transferdienst',
};

function rules(tx, b, recent) {
  const out = [];
  if (HIGH_RISK.has(tx.category)) {
    const first = !b.hasHighRiskHistory;
    out.push({
      rule: 'high_risk_category',
      severity: 'high',
      message: first
        ? `Erste Zahlung überhaupt an ${CAT_LABEL[tx.category]} — ein klassischer Weg, Betrugsgeld unwiderruflich abfließen zu lassen.`
        : `Zahlung an ${CAT_LABEL[tx.category]}.`,
    });
  }
  if (!b.knownPayees.has(tx.payeeIban)) {
    const big = tx.amount > Math.max(b.medianOutgoing * 4, 500);
    out.push({
      rule: 'new_payee',
      severity: big ? 'high' : 'low',
      message: big
        ? `${eur(tx.amount)} an einen völlig neuen Empfänger (${tx.payeeName}) — deutlich über dem üblichen Rahmen.`
        : `Neuer Empfänger: ${tx.payeeName}.`,
    });
  }
  if (b.maxOutgoing > 0 && tx.amount > b.maxOutgoing * 1.5) {
    out.push({
      rule: 'unusual_amount',
      severity: 'high',
      message: `${eur(tx.amount)} ist mehr als das 1,5-fache der bisher höchsten Zahlung (${eur(b.maxOutgoing)}).`,
    });
  }
  const country = ibanCountry(tx.payeeIban);
  if (country && !b.homeCountries.has(country)) {
    out.push({
      rule: 'foreign_country',
      severity: tx.amount > 300 ? 'medium' : 'low',
      message: `Zahlung ins Ausland (${country}), untypisch für dieses Konto.`,
    });
  }
  const newRecent =
    recent.filter((t) => !b.knownPayees.has(t.payeeIban)).length +
    (b.knownPayees.has(tx.payeeIban) ? 0 : 1);
  if (newRecent >= 3) {
    out.push({
      rule: 'velocity',
      severity: 'high',
      message: `${newRecent} Zahlungen an neue Empfänger innerhalb kurzer Zeit — typisches Muster unter Anleitung eines Betrügers.`,
    });
  }
  if (tx.category === 'cash_withdrawal') {
    const total =
      recent.filter((t) => t.category === 'cash_withdrawal').reduce((s, t) => s + t.amount, 0) + tx.amount;
    if (total >= Math.max(b.medianOutgoing * 5, 1000)) {
      out.push({
        rule: 'cash_spike',
        severity: 'high',
        message: `${eur(total)} Bargeld in kurzer Zeit abgehoben — weit über dem Üblichen. Bargeldübergabe ist eine häufige Betrugsmasche.`,
      });
    }
  }
  return out;
}

const levelOf = (score) => (score >= ESCALATION_THRESHOLD ? 'alert' : score >= WATCH_THRESHOLD ? 'watch' : 'ok');

export function assess(tx, baseline, recent = []) {
  if (tx.amount <= 0) {
    return { transactionId: tx.id, signals: [], score: 0, level: 'ok', shouldEscalate: false };
  }
  const signals = rules(tx, baseline, recent);
  const weights = signals.map((s) => W[s.severity]).sort((a, c) => c - a);
  let score = 0;
  weights.forEach((w, i) => (score += i === 0 ? w : w * 0.5));
  score = Math.min(100, Math.round(score));
  const level = levelOf(score);
  return { transactionId: tx.id, signals, score, level, shouldEscalate: level === 'alert' };
}

export function assessFeed(history, windowHours = 24) {
  const b = buildBaseline(history);
  const asc = [...history].sort((a, c) => new Date(a.date) - new Date(c.date));
  const res = asc.map((tx, idx) => {
    const t0 = new Date(tx.date).getTime();
    const recent = asc
      .slice(0, idx)
      .filter((t) => t.amount > 0 && t0 - new Date(t.date).getTime() <= windowHours * 3600000);
    return assess(tx, b, recent);
  });
  return res.reverse();
}
