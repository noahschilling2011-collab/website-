// Shared domain types for HALT.
// Kept deliberately small — this is the model for the MVP, not for millions of users.

/** A single account movement, as delivered by a PSD2 account-information provider. */
export interface Transaction {
  id: string;
  /** ISO 8601 timestamp of when the transaction was booked. */
  date: string;
  /** Amount in EUR. Positive = money leaving the account (debit). Credits are ignored by the risk engine. */
  amount: number;
  payeeName: string;
  /** IBAN of the counterparty. First two chars are the country code. */
  payeeIban: string;
  category: TransactionCategory;
  /** How the payment was initiated. */
  channel: TransactionChannel;
}

export type TransactionCategory =
  | 'groceries'
  | 'utilities'
  | 'retail'
  | 'transfer'
  | 'cash_withdrawal'
  | 'crypto'
  | 'precious_metals'
  | 'gift_card'
  | 'money_remittance'
  | 'other';

export type TransactionChannel = 'sepa' | 'instant' | 'card' | 'atm' | 'standing_order';

/** Categories that are classic scam cash-out routes: fast, irreversible, hard to claw back. */
export const HIGH_RISK_CATEGORIES: TransactionCategory[] = [
  'crypto',
  'precious_metals',
  'gift_card',
  'money_remittance',
];

/** A behavioural baseline derived from a person's own transaction history. */
export interface Baseline {
  /** IBANs the person has paid before — trusted by definition. */
  knownPayees: Set<string>;
  /** Largest single outgoing transaction seen in history. */
  maxOutgoing: number;
  /** Median outgoing transaction — robust to outliers. */
  medianOutgoing: number;
  /** Whether the person has ever made a crypto/precious-metals transaction. */
  hasHighRiskHistory: boolean;
  /** Country codes the person normally sends money to (e.g. {'DE'}). */
  homeCountries: Set<string>;
}

export type Severity = 'low' | 'medium' | 'high';

export interface RiskSignal {
  rule: string;
  severity: Severity;
  /** Human-readable, shown to the trusted person — plain German, no jargon. */
  message: string;
}

export type RiskLevel = 'ok' | 'watch' | 'alert';

export interface Assessment {
  transactionId: string;
  signals: RiskSignal[];
  /** 0–100. Higher = more suspicious. */
  score: number;
  level: RiskLevel;
  /**
   * The only decision the machine makes: should a human be woken up?
   * The engine never decides "this is fraud" — a person who loves them does.
   */
  shouldEscalate: boolean;
}

/** A person being protected, plus who gets called when something looks wrong. */
export interface ProtectedPerson {
  id: string;
  name: string;
  bankConnected: boolean;
}

export interface TrustedContact {
  id: string;
  name: string;
  phone: string;
  relation: string;
}
