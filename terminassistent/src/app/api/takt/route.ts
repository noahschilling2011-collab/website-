import { NextResponse } from 'next/server';
import { gleich } from '../../../lib/krypto';
import { konfig } from '../../../lib/konfig';
import { takt } from '../../../lib/vorgang/engine';

export const dynamic = 'force-dynamic';
export const maxDuration = 60;

/**
 * Der Takt. Sendet abgelaufene Haltezeiten und legt faellige Erinnerungen an.
 *
 * Aufgerufen von einem Cloudflare Cron Trigger (minutengenau, im
 * Paid-Plan 250 Trigger — und der Worker laeuft ohnehin schon fuer den
 * Maileingang). Vercel Cron kann im Hobby-Plan nur einmal taeglich, was
 * fuer eine 60-Sekunden-Haltezeit offensichtlich nicht reicht.
 */
export async function POST(anfrage: Request): Promise<Response> {
  const erwartet = konfig.webhookSecret;
  if (!erwartet) {
    return NextResponse.json({ fehler: 'MAIL_WEBHOOK_SECRET fehlt.' }, { status: 503 });
  }
  if (!gleich(anfrage.headers.get('x-webhook-secret') ?? '', erwartet)) {
    return NextResponse.json({ fehler: 'Nicht autorisiert.' }, { status: 401 });
  }

  const ergebnis = await takt();
  return NextResponse.json(ergebnis);
}
