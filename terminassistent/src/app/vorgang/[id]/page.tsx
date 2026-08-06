import { and, asc, desc, eq } from 'drizzle-orm';
import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { db, schema } from '../../../db/index';
import { konfig } from '../../../lib/konfig';
import { aktuelleNutzerin } from '../../../lib/sitzung';
import { platzierung, stelleDar } from '../../../lib/vorgang/darstellung';
import { zeigeAutomatikAngebot, automatikErlaubtFuer } from '../../../lib/vorgang/zustand';
import { formatiereDeutsch } from '../../../lib/zeit';
import {
  abbrechen,
  automatikAusschalten,
  automatikEinschalten,
  entwurfSpeichern,
  kompensieren,
  senden,
} from '../../aktionen';

export const dynamic = 'force-dynamic';

/**
 * Vorgangsdetail (Entwurf, Abschnitt 9).
 *
 * Der vollstaendige Mailverlauf, der aktuelle Entwurf editierbar, und der
 * Regelknopf. Hier findet die Vertrauensbildung statt: nichts geht raus,
 * was nicht vorher genau so lesbar war.
 */
export default async function VorgangsDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');

  const { id } = await params;
  const d = await db();

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(and(eq(schema.vorgaenge.id, id), eq(schema.vorgaenge.nutzerId, nutzer.id)))
    .limit(1);
  if (!vorgang) notFound();

  const verlauf = await d
    .select()
    .from(schema.nachrichten)
    .where(eq(schema.nachrichten.vorgangId, id))
    .orderBy(asc(schema.nachrichten.zeitpunkt));

  const [entwurf] = await d
    .select()
    .from(schema.ausgang)
    .where(eq(schema.ausgang.vorgangId, id))
    .orderBy(desc(schema.ausgang.erstelltAm))
    .limit(1);

  const termine = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, id))
    .orderBy(asc(schema.termine.von));

  // Kompensieren geht nur, wenn wirklich schon etwas rausgegangen ist.
  const [gesendet] = await d
    .select()
    .from(schema.ausgang)
    .where(and(eq(schema.ausgang.vorgangId, id), eq(schema.ausgang.status, 'gesendet')))
    .orderBy(desc(schema.ausgang.gesendetAm))
    .limit(1);

  const [regel] = vorgang.gegenueberEmail
    ? await d
        .select()
        .from(schema.regeln)
        .where(
          and(
            eq(schema.regeln.nutzerId, nutzer.id),
            eq(schema.regeln.empfaenger, vorgang.gegenueberEmail),
            eq(schema.regeln.aktionstyp, vorgang.art),
          ),
        )
        .limit(1)
    : [];

  const jetzt = new Date();
  const darstellung = stelleDar(vorgang, entwurf ?? null, termine[0] ?? null, nutzer.zeitzone, jetzt);
  const format = new Intl.DateTimeFormat('de-DE', {
    timeZone: nutzer.zeitzone,
    dateStyle: 'medium',
    timeStyle: 'short',
  });

  return (
    <main>
      <div className="kopf">
        <div>
          <h1>{vorgang.titel}</h1>
          <div className="leise">{darstellung.stand}</div>
        </div>
        <Link className="knopf leise-knopf" href="/">
          Zurück
        </Link>
      </div>

      {termine.length > 0 && (
        <div className="karte">
          <strong>Termine</strong>
          <table style={{ marginTop: '0.6rem' }}>
            <tbody>
              {termine.map((termin) => (
                <tr key={termin.id}>
                  <td>{formatiereDeutsch(termin.von, nutzer.zeitzone)} Uhr</td>
                  <td className="leise">{platzierung(termin)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {entwurf && entwurf.status === 'entwurf' && (
        <div className="karte">
          <strong>Entwurf an {entwurf.an}</strong>
          <p className="leise" style={{ marginTop: '0.25rem' }}>
            Sie können den Text ändern, bevor er rausgeht. Nach dem Senden läuft eine
            Haltezeit von {konfig.haltezeitSekunden} Sekunden, in der Sie noch abbrechen
            können.
          </p>

          <form action={entwurfSpeichern} style={{ marginTop: '1rem' }}>
            <input type="hidden" name="vorgangId" value={vorgang.id} />
            <div className="feld">
              <label htmlFor="betreff">Betreff</label>
              <input id="betreff" name="betreff" type="text" defaultValue={entwurf.betreff} />
            </div>
            <div className="feld">
              <label htmlFor="text">Text</label>
              <textarea id="text" name="text" defaultValue={entwurf.text} />
            </div>
            <button className="leise-knopf" type="submit">
              Änderungen übernehmen
            </button>
          </form>

          <form action={senden} style={{ marginTop: '1rem' }}>
            <input type="hidden" name="vorgangId" value={vorgang.id} />
            <button type="submit">Senden</button>
          </form>
        </div>
      )}

      {entwurf && entwurf.status === 'gehalten' && (
        <div className="karte">
          <strong>Geht gleich raus</strong>
          <p className="leise" style={{ marginTop: '0.25rem' }}>
            {darstellung.stand}
          </p>
          <pre className="wortlaut">{entwurf.text}</pre>
          <form action={abbrechen}>
            <input type="hidden" name="vorgangId" value={vorgang.id} />
            <button className="leise-knopf" type="submit">
              Doch nicht senden
            </button>
          </form>
        </div>
      )}

      {vorgang.gegenueberEmail && automatikErlaubtFuer(vorgang.art) && (
        <AutomatikKarte
          vorgangId={vorgang.id}
          empfaenger={vorgang.gegenueberEmail}
          aktionstyp={vorgang.art}
          regel={regel ?? null}
        />
      )}

      {gesendet && <KorrekturKarte vorgangId={vorgang.id} an={gesendet.an} />}

      <div className="abschnitt">Verlauf</div>
      {verlauf.length === 0 && <p className="leise">Noch keine Nachrichten.</p>}
      {verlauf.map((nachricht) => (
        <div className="verlauf" key={nachricht.id}>
          <div className="verlauf-kopf">
            {nachricht.richtung === 'ein' ? 'Von' : 'An'}{' '}
            {nachricht.richtung === 'ein' ? nachricht.von : nachricht.an} ·{' '}
            {format.format(nachricht.zeitpunkt)}
          </div>
          <div style={{ fontWeight: 600, marginBottom: '0.25rem' }}>{nachricht.betreff}</div>
          <pre className="wortlaut">{nachricht.text}</pre>
        </div>
      ))}
    </main>
  );
}

/**
 * Kompensieren. Erscheint erst, wenn tatsaechlich etwas rausgegangen ist.
 *
 * Der Text sagt ausdruecklich, was NICHT passiert: die Mail kommt nicht
 * zurueck. Ein Knopf, der "Rückgängig" verspricht, waere gelogen.
 */
function KorrekturKarte({ vorgangId, an }: { vorgangId: string; an: string }) {
  return (
    <details className="karte">
      <summary style={{ cursor: 'pointer', fontWeight: 600 }}>
        Das hätte so nicht rausgehen dürfen
      </summary>
      <p className="leise" style={{ marginTop: '0.75rem' }}>
        Die Mail an {an} ist weg und kommt nicht zurück — dafür gibt es keinen Weg. Was ich
        tun kann: einen etwaigen Termin wieder absagen und eine Korrektur an denselben
        Empfänger vorbereiten. Die Korrektur geht erst raus, wenn Sie sie freigeben.
      </p>
      <form action={kompensieren}>
        <input type="hidden" name="vorgangId" value={vorgangId} />
        <div className="feld">
          <label htmlFor="grund">Was war falsch?</label>
          <input
            id="grund"
            name="grund"
            type="text"
            required
            placeholder="Der Termin war schon vergeben."
          />
        </div>
        <button className="leise-knopf" type="submit">
          Termin absagen und Korrektur vorbereiten
        </button>
      </form>
    </details>
  );
}

/**
 * Der Regelknopf. Drei bestaetigte Sendungen erzeugen ein ANGEBOT, keine
 * Freigabe — erst dieser Klick schaltet die Automatik ein.
 */
function AutomatikKarte({
  vorgangId,
  empfaenger,
  aktionstyp,
  regel,
}: {
  vorgangId: string;
  empfaenger: string;
  aktionstyp: string;
  regel: { bestaetigteSendungen: number; automatisch: boolean } | null;
}) {
  if (regel?.automatisch) {
    return (
      <div className="karte">
        <strong>Automatik ist an</strong>
        <p className="leise" style={{ marginTop: '0.25rem' }}>
          Erinnerungen an {empfaenger} gehen ohne Rückfrage raus — weiterhin erst nach der
          Haltezeit.
        </p>
        <form action={automatikAusschalten}>
          <input type="hidden" name="vorgangId" value={vorgangId} />
          <input type="hidden" name="empfaenger" value={empfaenger} />
          <input type="hidden" name="aktionstyp" value={aktionstyp} />
          <button className="leise-knopf" type="submit">
            Wieder jedes Mal fragen
          </button>
        </form>
      </div>
    );
  }

  if (!zeigeAutomatikAngebot(regel)) {
    const bisher = regel?.bestaetigteSendungen ?? 0;
    return (
      <p className="leise">
        Nach drei von Ihnen bestätigten Erinnerungen an {empfaenger} biete ich an, das
        künftig automatisch zu tun. Bisher: {bisher} von 3.
      </p>
    );
  }

  return (
    <div className="karte">
      <strong>Soll ich das künftig allein machen?</strong>
      <p className="leise" style={{ marginTop: '0.25rem' }}>
        Sie haben drei Erinnerungen an {empfaenger} freigegeben. Ich kann das ab jetzt ohne
        Rückfrage tun — die Haltezeit von {konfig.haltezeitSekunden} Sekunden bleibt, Sie
        können also weiterhin jederzeit abbrechen.
      </p>
      <form action={automatikEinschalten}>
        <input type="hidden" name="vorgangId" value={vorgangId} />
        <input type="hidden" name="empfaenger" value={empfaenger} />
        <input type="hidden" name="aktionstyp" value={aktionstyp} />
        <button type="submit">Ja, künftig ohne Rückfrage</button>
      </form>
    </div>
  );
}
