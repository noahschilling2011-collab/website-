import { NextResponse } from 'next/server';
import { konfig } from '../../../lib/konfig';
import { loeseTokenEin, sitzungsKeks } from '../../../lib/sitzung';

export const dynamic = 'force-dynamic';

/**
 * Der Link aus der Anmeldemail.
 *
 * Route Handler und nicht Seite: eine Server Component darf in Next.js keine
 * Cookies setzen. Als Seite hat dieser Weg eine Sitzung "gesetzt", die nie
 * ankam.
 *
 * Und das Cookie geht direkt auf DIESE Antwort, nicht ueber den
 * `cookies()`-Speicher. Wer eine eigene NextResponse zurueckgibt, bekommt
 * Aenderungen an jenem Speicher nicht zuverlaessig mit — im Browser fehlte
 * das Cookie, die Weiterleitung landete wieder auf der Anmeldeseite, und
 * von aussen sah es aus wie ein abgelaufener Link.
 */
export async function GET(
  _anfrage: Request,
  { params }: { params: Promise<{ token: string }> },
): Promise<Response> {
  const { token } = await params;
  const nutzer = await loeseTokenEin(token);

  if (!nutzer) {
    return NextResponse.redirect(new URL('/anmelden?fehler=link', konfig.appUrl));
  }

  const antwort = NextResponse.redirect(new URL('/', konfig.appUrl));
  const keks = sitzungsKeks(nutzer.id);
  antwort.cookies.set(keks.name, keks.wert, keks.optionen);
  return antwort;
}
