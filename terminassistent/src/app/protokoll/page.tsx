import { desc, eq } from 'drizzle-orm';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { db, schema } from '../../db/index';
import { aktuelleNutzerin } from '../../lib/sitzung';

export const dynamic = 'force-dynamic';

/**
 * "Nachvollziehen" aus Abschnitt 5 des Entwurfs.
 *
 * Der volle Wortlaut dessen, was rausging — keine Zusammenfassung. Das ist
 * der dritte der drei Ersatzmechanismen fuer ein Rueckgaengig, das es
 * fuer eine gesendete Mail nicht gibt.
 */
export default async function Protokoll() {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');

  const d = await db();
  const eintraege = await d
    .select()
    .from(schema.protokoll)
    .where(eq(schema.protokoll.nutzerId, nutzer.id))
    .orderBy(desc(schema.protokoll.zeitpunkt))
    .limit(300);

  const format = new Intl.DateTimeFormat('de-DE', {
    timeZone: nutzer.zeitzone,
    dateStyle: 'medium',
    timeStyle: 'short',
  });

  return (
    <main>
      <div className="kopf">
        <h1>Was bisher passiert ist</h1>
        <Link className="knopf leise-knopf" href="/">
          Zurück
        </Link>
      </div>

      {eintraege.length === 0 ? (
        <div className="leer">Noch nichts passiert.</div>
      ) : (
        eintraege.map((eintrag) => (
          <div className="karte" key={eintrag.id}>
            <div className="verlauf-kopf">
              {format.format(eintrag.zeitpunkt)}
              {eintrag.vorgangId && (
                <>
                  {' · '}
                  <Link href={`/vorgang/${eintrag.vorgangId}`}>Vorgang</Link>
                </>
              )}
            </div>
            <strong>{eintrag.was}</strong>
            {eintrag.details && (
              <pre className="wortlaut" style={{ marginTop: '0.6rem' }}>
                {eintrag.details}
              </pre>
            )}
          </div>
        ))
      )}
    </main>
  );
}
