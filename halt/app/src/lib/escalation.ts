// ─────────────────────────────────────────────────────────────────────────────
// Escalation — the moment that matters.
//
// When the engine says "wake a human", HALT reaches the trusted person as
// loudly as possible: a push notification AND, for a real alert, a phone call.
//
// Both channels are STUBBED here with clear integration points:
//   • Push  → Expo Notifications → APNs/FCM
//   • Call  → Twilio Programmable Voice (server-side; never ship the token in the app)
//
// The app logic around them is real: decide → notify → record. Only the two
// outbound wires are placeholders.
// ─────────────────────────────────────────────────────────────────────────────

import type { Assessment, TrustedContact, Transaction } from '../types';

export interface EscalationResult {
  delivered: boolean;
  channel: 'call' | 'push';
  to: string;
  at: string;
}

/**
 * PRODUCTION: call your backend endpoint, which triggers Twilio Programmable
 * Voice. The Twilio credentials live on the server only.
 *
 *   await fetch(`${API}/escalate`, { method: 'POST', body: JSON.stringify({...}) })
 */
export async function placeEscalationCall(
  contact: TrustedContact,
  tx: Transaction,
  assessment: Assessment,
  now: string,
): Promise<EscalationResult> {
  // eslint-disable-next-line no-console
  console.log(
    `[HALT] ☎️  ESKALATION → würde ${contact.name} (${contact.phone}) anrufen. ` +
      `Auslöser: ${tx.payeeName}, ${tx.amount} € (Score ${assessment.score}).`,
  );
  return { delivered: true, channel: 'call', to: contact.phone, at: now };
}

/**
 * PRODUCTION: Expo push token → Expo push service → APNs/FCM.
 */
export async function sendPush(
  contact: TrustedContact,
  message: string,
  now: string,
): Promise<EscalationResult> {
  // eslint-disable-next-line no-console
  console.log(`[HALT] 🔔 Push an ${contact.name}: ${message}`);
  return { delivered: true, channel: 'push', to: contact.phone, at: now };
}

/** Human-readable one-liner for a notification. */
export function alertSummary(tx: Transaction, assessment: Assessment): string {
  const top = assessment.signals[0]?.message ?? 'Ungewöhnliche Kontobewegung.';
  return `Verdächtige Bewegung: ${tx.amount.toLocaleString('de-DE')} € an ${tx.payeeName}. ${top}`;
}
