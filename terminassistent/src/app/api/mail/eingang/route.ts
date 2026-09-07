import { NextResponse } from 'next/server';
import { gleich } from '../../../../lib/krypto';
import { konfig } from '../../../../lib/konfig';
import { verarbeiteEingang } from '../../../../lib/vorgang/engine';

export const dynamic = 'force-dynamic';
export const maxDuration = 60;

/**
 * Der Endpunkt, auf den der Cloudflare Email Worker die Rohnachricht legt.
 *
 * Antwortet bewusst mit Statuscodes, auf die der Worker reagieren kann:
 * bei 4xx lehnt er die Mail beim Absender ab (der bekommt dann wenigstens
 * eine Fehlermeldung), bei 5xx faellt er auf die Zieladresse zurueck.
 * Cloudflare speichert nichts — was hier verlorengeht, ist weg.
 */
export async function POST(anfrage: Request): Promise<Response> {
  const erwartet = konfig.webhookSecret;
  if (!erwartet) {
    return NextResponse.json(
      { fehler: 'MAIL_WEBHOOK_SECRET ist nicht gesetzt.' },
      { status: 503 },
    );
  }

  const mitgeschickt = anfrage.headers.get('x-webhook-secret') ?? '';
  if (!gleich(mitgeschickt, erwartet)) {
    return NextResponse.json({ fehler: 'Nicht autorisiert.' }, { status: 401 });
  }

  const roh = await anfrage.arrayBuffer();
  if (roh.byteLength === 0) {
    return NextResponse.json({ fehler: 'Leere Nachricht.' }, { status: 400 });
  }

  try {
    const ergebnis = await verarbeiteEingang(
      roh,
      anfrage.headers.get('x-envelope-to') ?? undefined,
    );
    if ('abgelehnt' in ergebnis) {
      return NextResponse.json({ fehler: ergebnis.abgelehnt }, { status: 422 });
    }
    return NextResponse.json({ vorgangId: ergebnis.vorgangId });
  } catch (fehler) {
    console.error('Maileingang fehlgeschlagen:', fehler);
    // 5xx, damit der Worker auf die Fallback-Adresse ausweicht statt die
    // Nachricht zu verlieren.
    return NextResponse.json({ fehler: (fehler as Error).message }, { status: 500 });
  }
}
