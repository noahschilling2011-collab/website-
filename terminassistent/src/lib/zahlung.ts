import { konfig } from './konfig';

/**
 * Stripe Checkout, ueber die REST-Schnittstelle statt ueber das SDK.
 *
 * ACHTUNG — ungeprueft. Dieser Code ist nie gegen echte Stripe-Endpunkte
 * gelaufen; hier gibt es kein Stripe-Konto. Die Feldnamen stammen aus der
 * dokumentierten Checkout-API, die Ablaeufe sind plausibel, aber vor dem
 * ersten echten Einsatz gehoert das im Stripe-Testmodus durchgespielt.
 * Alles andere in diesem Projekt ist getestet; das hier nicht.
 *
 * Bewusst OHNE Webhook: eine Webhook-Signaturpruefung, die niemand
 * verifizieren kann, ist gefaehrlicher als keine. Stattdessen wird beim
 * Rueckkehr-Aufruf die Sitzung direkt bei Stripe nachgeschlagen. Der
 * Nachteil ist bekannt und im README benannt: kehrt die Nutzerin nach der
 * Zahlung nicht zurueck, bleibt die Freischaltung aus, bis sie die Seite
 * das naechste Mal oeffnet.
 */

const API = 'https://api.stripe.com/v1';

export function zahlungKonfiguriert(): boolean {
  return Boolean(process.env.STRIPE_SECRET_KEY && process.env.STRIPE_PREIS_ID);
}

async function stripe<T>(pfad: string, koerper?: URLSearchParams): Promise<T> {
  const schluessel = process.env.STRIPE_SECRET_KEY;
  if (!schluessel) throw new Error('STRIPE_SECRET_KEY fehlt.');

  const antwort = await fetch(`${API}${pfad}`, {
    method: koerper ? 'POST' : 'GET',
    headers: {
      authorization: `Bearer ${schluessel}`,
      ...(koerper ? { 'content-type': 'application/x-www-form-urlencoded' } : {}),
    },
    body: koerper,
  });

  if (!antwort.ok) {
    throw new Error(`Stripe ${pfad} fehlgeschlagen (${antwort.status}): ${await antwort.text()}`);
  }
  return (await antwort.json()) as T;
}

export async function starteCheckout(daten: {
  nutzerId: string;
  email: string;
  kundeId: string | null;
}): Promise<string> {
  const preisId = process.env.STRIPE_PREIS_ID;
  if (!preisId) throw new Error('STRIPE_PREIS_ID fehlt.');

  const felder = new URLSearchParams({
    mode: 'subscription',
    'line_items[0][price]': preisId,
    'line_items[0][quantity]': '1',
    success_url: `${konfig.appUrl}/api/zahlung/zurueck?sitzung={CHECKOUT_SESSION_ID}`,
    cancel_url: `${konfig.appUrl}/verbindungen?fehler=abgebrochen`,
    // Bindet die Zahlung an die Nutzerin, damit die Rueckkehr eindeutig
    // zuzuordnen ist.
    client_reference_id: daten.nutzerId,
  });

  if (daten.kundeId) felder.set('customer', daten.kundeId);
  else felder.set('customer_email', daten.email);

  const sitzung = await stripe<{ url: string }>('/checkout/sessions', felder);
  return sitzung.url;
}

export interface CheckoutErgebnis {
  bezahlt: boolean;
  nutzerId: string | null;
  kundeId: string | null;
}

export async function pruefeCheckout(sitzungId: string): Promise<CheckoutErgebnis> {
  const sitzung = await stripe<{
    payment_status?: string;
    status?: string;
    client_reference_id?: string | null;
    customer?: string | null;
  }>(`/checkout/sessions/${encodeURIComponent(sitzungId)}`);

  return {
    bezahlt: sitzung.payment_status === 'paid' || sitzung.status === 'complete',
    nutzerId: sitzung.client_reference_id ?? null,
    kundeId: typeof sitzung.customer === 'string' ? sitzung.customer : null,
  };
}
