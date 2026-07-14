// On-device heuristic for the manual "check this message" flow.
// The allowed passive-channel companion to the account engine: a keyword/pattern
// screen that stays offline and fully explainable. In production the text could
// additionally go to an LLM; this local pass runs first and needs no network.

import type { RiskLevel } from '../types';

export interface MessageCheckResult {
  level: RiskLevel;
  reasons: string[];
}

const RED_FLAGS: { pattern: RegExp; reason: string }[] = [
  { pattern: /\b(sofort|dringend|umgehend|innerhalb von \d+ (minuten|stunden))\b/i, reason: 'Zeitdruck — Betrüger drängen zur Eile.' },
  { pattern: /\b(krypto|bitcoin|wallet|gutschein|guthabenkarte|steam|google play|amazon-karte)\b/i, reason: 'Ungewöhnliche Zahlungsart (Krypto/Geschenkkarten) — kaum rückholbar.' },
  { pattern: /\b(geheim|niemandem sagen|nicht verraten|unter uns)\b/i, reason: 'Aufforderung zur Geheimhaltung — ein starkes Warnzeichen.' },
  { pattern: /\b(enkel|neffe|nichte)\b[\s\S]*\b(geld|not|unfall|kaution)\b/i, reason: 'Klassischer Enkeltrick.' },
  { pattern: /\b(microsoft|paypal|amazon|bank|zoll|polizei|europol)\b[\s\S]*\b(konto|gesperrt|verifizieren|bestätigen)\b/i, reason: 'Angebliche Behörde/Firma will Konto „verifizieren".' },
  { pattern: /\b(neue nummer|handy kaputt|schreib mir auf whatsapp)\b/i, reason: '„Neue Nummer" — beliebter Einstieg für Betrug per Messenger.' },
  { pattern: /https?:\/\/\S+/i, reason: 'Enthält einen Link — nicht ungeprüft anklicken.' },
];

/** Screen a free-text message for classic fraud patterns. Pure and deterministic. */
export function checkMessage(text: string): MessageCheckResult {
  const reasons = RED_FLAGS.filter((f) => f.pattern.test(text)).map((f) => f.reason);
  const level: RiskLevel = reasons.length >= 2 ? 'alert' : reasons.length === 1 ? 'watch' : 'ok';
  return { level, reasons };
}
