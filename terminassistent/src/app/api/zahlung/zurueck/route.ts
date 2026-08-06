import { eq } from 'drizzle-orm';
import { NextResponse } from 'next/server';
import { db, schema } from '../../../../db/index';
import { konfig } from '../../../../lib/konfig';
import { aktuelleNutzerin } from '../../../../lib/sitzung';
import { protokolliere } from '../../../../lib/vorgang/engine';
import { pruefeCheckout } from '../../../../lib/zahlung';

export const dynamic = 'force-dynamic';

/**
 * Rueckkehr aus dem Stripe-Checkout.
 *
 * Die Freischaltung haengt NICHT an dem, was in der URL steht, sondern an
 * einer Rueckfrage bei Stripe. Eine Sitzungs-ID in der Adresszeile ist
 * kein Zahlungsnachweis.
 */
export async function GET(anfrage: Request): Promise<Response> {
  const ziel = new URL('/', konfig.appUrl);
  const sitzungId = new URL(anfrage.url).searchParams.get('sitzung');
  if (!sitzungId) {
    ziel.searchParams.set('zahlung', 'unvollstaendig');
    return NextResponse.redirect(ziel);
  }

  const nutzer = await aktuelleNutzerin();
  if (!nutzer) return NextResponse.redirect(new URL('/anmelden', konfig.appUrl));

  try {
    const ergebnis = await pruefeCheckout(sitzungId);

    // Die Zahlung muss zu DIESER Nutzerin gehoeren. Sonst koennte eine
    // fremde Sitzungs-ID das eigene Konto freischalten.
    if (!ergebnis.bezahlt || ergebnis.nutzerId !== nutzer.id) {
      ziel.searchParams.set('zahlung', 'nicht_bestaetigt');
      return NextResponse.redirect(ziel);
    }

    const d = await db();
    await d
      .update(schema.nutzer)
      .set({ zahlendSeit: new Date(), zahlungsKundeId: ergebnis.kundeId })
      .where(eq(schema.nutzer.id, nutzer.id));

    await protokolliere(nutzer.id, null, 'Abonnement aktiv', `Stripe-Sitzung ${sitzungId}`);
    ziel.searchParams.set('zahlung', 'aktiv');
    return NextResponse.redirect(ziel);
  } catch (fehler) {
    await protokolliere(
      nutzer.id,
      null,
      'Zahlungspruefung fehlgeschlagen',
      (fehler as Error).message,
    );
    ziel.searchParams.set('zahlung', 'fehler');
    return NextResponse.redirect(ziel);
  }
}
