import { and, eq, isNull, ne, sql } from 'drizzle-orm';
import { db, schema } from '../../../../db/index';
import { baueFeed } from '../../../../lib/calendar/ics';
import type { EventDraft } from '../../../../lib/calendar/types';

export const dynamic = 'force-dynamic';

/**
 * Weg B, Schreibseite: der abonnierbare ICS-Feed.
 *
 * Der IcsPublishSink uebertraegt nichts — die App IST der Terminspeicher,
 * und dieser Endpunkt rendert ihn bei jedem Abruf neu. Deshalb ist der
 * Platzierungsstatus 'published' und nicht 'placed': wir wissen, dass der
 * Termin im Feed steht, aber nie, ob ein Kalender ihn abgerufen hat.
 */
export async function GET(
  _anfrage: Request,
  kontext: { params: Promise<{ token: string }> },
): Promise<Response> {
  const { token } = await kontext.params;
  const d = await db();

  // Das Token steckt in der Verbindungskonfiguration, nicht in der URL-Tabelle.
  const [verbindung] = await d
    .select()
    .from(schema.kalenderVerbindungen)
    .where(
      and(
        eq(schema.kalenderVerbindungen.kind, 'ics_publish'),
        isNull(schema.kalenderVerbindungen.widerrufenAm),
        sql`${schema.kalenderVerbindungen.konfig}->>'token' = ${token}`,
      ),
    )
    .limit(1);

  if (!verbindung) {
    return new Response('Nicht gefunden.', { status: 404 });
  }

  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, verbindung.nutzerId))
    .limit(1);
  if (!nutzer) return new Response('Nicht gefunden.', { status: 404 });

  const zeilen = await d
    .select({
      uid: schema.termine.uid,
      sequence: schema.termine.sequence,
      titel: schema.termine.titel,
      von: schema.termine.von,
      bis: schema.termine.bis,
      zeitzone: schema.termine.zeitzone,
      ort: schema.termine.ort,
    })
    .from(schema.termine)
    .innerJoin(schema.vorgaenge, eq(schema.termine.vorgangId, schema.vorgaenge.id))
    .where(
      and(
        eq(schema.vorgaenge.nutzerId, nutzer.id),
        // Blosse Vorschlaege gehoeren nicht in den Kalender der Nutzerin.
        ne(schema.termine.platzierungsStatus, 'offen'),
        ne(schema.termine.platzierungsStatus, 'abgesagt'),
      ),
    );

  const termine: EventDraft[] = zeilen.map((z) => ({
    uid: z.uid,
    sequence: z.sequence,
    titel: z.titel,
    start: z.von,
    end: z.bis,
    zeitzone: z.zeitzone,
    ort: z.ort ?? undefined,
  }));

  const ics = baueFeed('Terminassistent', termine, nutzer.zeitzone);

  return new Response(ics, {
    headers: {
      'content-type': 'text/calendar; charset=utf-8',
      'cache-control': 'no-cache, no-store, must-revalidate',
      'content-disposition': 'inline; filename="terminassistent.ics"',
    },
  });
}
