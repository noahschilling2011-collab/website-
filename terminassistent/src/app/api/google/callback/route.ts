import { and, eq, isNull } from 'drizzle-orm';
import { NextResponse } from 'next/server';
import { db, schema } from '../../../../db/index';
import { pruefeState, tauscheCode } from '../../../../lib/google-oauth';
import { konfig } from '../../../../lib/konfig';
import { verschluessle } from '../../../../lib/krypto';
import { aktuelleNutzerin } from '../../../../lib/sitzung';
import { protokolliere } from '../../../../lib/vorgang/engine';

export const dynamic = 'force-dynamic';

/**
 * Zurueck zur Verbindungsseite — mit einem CODE, nie mit freiem Text.
 *
 * Wuerde hier eine Meldung aus der URL oder aus Googles Antwort
 * durchgereicht, koennte jeder einen Link bauen, der einen beliebigen Satz
 * auf der eigenen Seite der Nutzerin erscheinen laesst. Bei einem Produkt,
 * dessen ganzer Zweck Vertrauen in das Angezeigte ist, waere das der
 * falsche Handel. Die Einzelheiten stehen im Protokoll.
 */
type Meldung = keyof typeof MELDUNGEN;
const MELDUNGEN = {
  verbunden: 'ok',
  abgelehnt: 'fehler',
  unvollstaendig: 'fehler',
  rueckweg_ungueltig: 'fehler',
  sitzung_passt_nicht: 'fehler',
  kein_refresh_token: 'fehler',
} as const;

function zurueck(meldung: Meldung): Response {
  const ziel = new URL('/verbindungen', konfig.appUrl);
  ziel.searchParams.set(MELDUNGEN[meldung] === 'ok' ? 'verbunden' : 'fehler', meldung);
  return NextResponse.redirect(ziel);
}

export async function GET(anfrage: Request): Promise<Response> {
  const url = new URL(anfrage.url);
  const fehler = url.searchParams.get('error');
  if (fehler) {
    // Die Nutzerin hat abgebrochen oder Google hat abgelehnt.
    return zurueck('abgelehnt');
  }

  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  if (!code || !state) return zurueck('unvollstaendig');

  const nutzerIdAusState = pruefeState(state);
  if (!nutzerIdAusState) return zurueck('rueckweg_ungueltig');

  // Doppelt gesichert: der state muss zur AKTUELL angemeldeten Sitzung
  // passen. Sonst koennte ein abgefangener Rueckweg den Kalender eines
  // Dritten an ein fremdes Konto haengen.
  const nutzer = await aktuelleNutzerin();
  if (!nutzer || nutzer.id !== nutzerIdAusState) return zurueck('sitzung_passt_nicht');

  let refreshToken: string;
  try {
    ({ refreshToken } = await tauscheCode(code));
  } catch (ausnahme) {
    // Der Wortlaut gehoert ins Protokoll, nicht in die Adresszeile.
    await protokolliere(
      nutzer.id,
      null,
      'Google-Anbindung fehlgeschlagen',
      (ausnahme as Error).message,
    );
    return zurueck('kein_refresh_token');
  }

  const d = await db();

  // Eine bestehende Google-Verbindung wird ersetzt, nicht verdoppelt.
  await d
    .update(schema.kalenderVerbindungen)
    .set({ widerrufenAm: new Date() })
    .where(
      and(
        eq(schema.kalenderVerbindungen.nutzerId, nutzer.id),
        eq(schema.kalenderVerbindungen.kind, 'google_oauth'),
        isNull(schema.kalenderVerbindungen.widerrufenAm),
      ),
    );

  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'google_oauth',
    secretRef: verschluessle(refreshToken),
    konfig: { kalenderId: 'primary' },
    lastOkAt: new Date(),
  });

  await protokolliere(
    nutzer.id,
    null,
    'Google Kalender verbunden',
    'Scopes: calendar.freebusy (lesen) und calendar.events (schreiben). Das Refresh-Token liegt verschluesselt in der Datenbank.',
  );

  return zurueck('verbunden');
}
