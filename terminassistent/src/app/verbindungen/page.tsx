import { and, eq, isNull } from 'drizzle-orm';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { db, schema } from '../../db/index';
import { googleKonfiguriert } from '../../lib/google-oauth';
import { konfig } from '../../lib/konfig';
import { aktuelleNutzerin } from '../../lib/sitzung';
import {
  attrappeVerbinden,
  icsVerbindungSpeichern,
  verbindungWiderrufen,
} from '../aktionen';

export const dynamic = 'force-dynamic';

const BESCHREIBUNG: Record<string, string> = {
  google_oauth: 'Google Kalender (OAuth)',
  ics_secret_url: 'Kalender lesen über geheime iCal-Adresse',
  ics_publish: 'Termine schreiben über ein eigenes Abo',
  imip_mail: 'Termine als Mail-Einladung',
  attrappe: 'Demo-Kalender (trägt nirgends wirklich ein)',
};

/**
 * Der Rueckweg aus dem Google-Dialog bringt nur einen CODE mit, keinen Text.
 * Was auf dieser Seite steht, steht hier — nicht in der Adresszeile. Sonst
 * koennte ein fremder Link der Nutzerin einen beliebigen Satz auf ihrer
 * eigenen Seite unterschieben.
 */
const RUECKMELDUNGEN: Record<string, string> = {
  verbunden: 'Google Kalender ist verbunden.',
  abgelehnt: 'Sie haben den Zugriff nicht erteilt. Es wurde nichts gespeichert.',
  unvollstaendig: 'Die Antwort von Google war unvollständig. Bitte erneut versuchen.',
  rueckweg_ungueltig: 'Der Rückweg war ungültig oder abgelaufen. Bitte erneut versuchen.',
  sitzung_passt_nicht:
    'Die Anmeldung passt nicht zur Anfrage. Bitte melden Sie sich an und versuchen Sie es erneut.',
  kein_refresh_token:
    'Google hat kein dauerhaftes Zugriffsrecht zurückgegeben. Einzelheiten stehen im Protokoll.',
  abgebrochen: 'Die Zahlung wurde abgebrochen. Es wurde nichts berechnet.',
};

function rueckmeldung(code: string | undefined): string {
  return (code && RUECKMELDUNGEN[code]) ?? 'Unbekannte Rückmeldung.';
}

export default async function Verbindungen({
  searchParams,
}: {
  searchParams: Promise<{ verbunden?: string; fehler?: string }>;
}) {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');

  const meldung = await searchParams;

  const d = await db();
  const verbindungen = await d
    .select()
    .from(schema.kalenderVerbindungen)
    .where(
      and(
        eq(schema.kalenderVerbindungen.nutzerId, nutzer.id),
        isNull(schema.kalenderVerbindungen.widerrufenAm),
      ),
    );

  const format = new Intl.DateTimeFormat('de-DE', {
    timeZone: nutzer.zeitzone,
    dateStyle: 'medium',
    timeStyle: 'short',
  });

  return (
    <main>
      <div className="kopf">
        <h1>Verbindungen</h1>
        <Link className="knopf leise-knopf" href="/">
          Zurück
        </Link>
      </div>

      {(meldung.fehler || meldung.verbunden) && (
        <div className="hinweis">{rueckmeldung(meldung.fehler ?? meldung.verbunden)}</div>
      )}

      <div className="karte">
        <strong>Ihre Weiterleitungsadresse</strong>
        <p style={{ marginBottom: '0.35rem' }}>
          <code>
            {nutzer.handle}@{konfig.mailDomain}
          </code>
        </p>
        <p className="leise" style={{ margin: 0 }}>
          Leiten Sie eine Mail hierher weiter oder setzen Sie die Adresse in CC. Der
          Assistent sieht ausschließlich das, was Sie ihm schicken — kein Zugriff auf Ihr
          Postfach.
        </p>
      </div>

      <div className="abschnitt">Kalender</div>

      {verbindungen.length === 0 && (
        <p className="leise">Noch kein Kalender verbunden.</p>
      )}

      {verbindungen.map((verbindung) => (
        <div className="karte" key={verbindung.id}>
          <div className="zeile-kopf">
            <div>
              <strong>{BESCHREIBUNG[verbindung.kind] ?? verbindung.kind}</strong>
              <div className="leise" style={{ marginTop: '0.2rem' }}>
                {verbindung.lastError ? (
                  <>
                    Zuletzt fehlgeschlagen
                    {verbindung.lastErrorAt && ` am ${format.format(verbindung.lastErrorAt)}`}:{' '}
                    {verbindung.lastError}
                  </>
                ) : verbindung.lastOkAt ? (
                  <>Zuletzt erfolgreich gelesen am {format.format(verbindung.lastOkAt)}</>
                ) : (
                  'Noch nicht benutzt'
                )}
              </div>
            </div>
            <form action={verbindungWiderrufen}>
              <input type="hidden" name="id" value={verbindung.id} />
              <button className="leise-knopf" type="submit">
                Trennen
              </button>
            </form>
          </div>
        </div>
      ))}

      <div className="karte">
        <strong>Google Kalender verbinden</strong>
        <p className="leise" style={{ marginTop: '0.25rem' }}>
          Der direkte Weg. Ich lese ausschließlich Belegtzeiten — keine Termintitel, keine
          Teilnehmer — und trage neue Termine ein. Google zeigt dabei einen Bildschirm
          „Diese App wurde nicht überprüft"; das liegt daran, dass die App noch nicht durch
          Googles Verifizierung gelaufen ist.
        </p>
        {googleKonfiguriert() ? (
          <a className="knopf" href="/api/google/start">
            Mit Google verbinden
          </a>
        ) : (
          <p className="leise">
            Nicht eingerichtet: <code>GOOGLE_CLIENT_ID</code> und{' '}
            <code>GOOGLE_CLIENT_SECRET</code> fehlen.
          </p>
        )}
      </div>

      <div className="karte">
        <strong>Kalender ohne Google-Anmeldung verbinden</strong>
        <p className="leise" style={{ marginTop: '0.25rem' }}>
          In Google Kalender: Einstellungen → Einstellungen für meine Kalender → Ihren
          Kalender wählen → Kalender integrieren → <em>Geheime Adresse im iCal-Format</em>{' '}
          kopieren. In Outlook.com und iCloud gibt es einen entsprechenden Weg.
        </p>
        <p className="leise">
          Diese Adresse ist ein Geheimnis: Wer sie hat, sieht Ihren Kalender. Sie können sie
          in Google jederzeit zurücksetzen — dann wird sie hier ungültig und Sie tragen die
          neue ein.
        </p>
        <form action={icsVerbindungSpeichern}>
          <div className="feld">
            <label htmlFor="url">Geheime iCal-Adresse</label>
            <input id="url" name="url" type="url" placeholder="https://calendar.google.com/calendar/ical/.../basic.ics" />
          </div>
          <button type="submit">Verbinden</button>
        </form>
      </div>

      {konfig.demoModus && (
        <div className="karte">
          <strong>Demo</strong>
          <p className="leise" style={{ marginTop: '0.25rem' }}>
            Ein Kalender ohne jedes externe Konto. Er meldet immer freie Zeiten und trägt
            nichts wirklich ein — genug, um den ganzen Ablauf durchzuspielen.
          </p>
          <form action={attrappeVerbinden}>
            <button className="leise-knopf" type="submit">
              Demo-Kalender verbinden
            </button>
          </form>
        </div>
      )}

      <div className="fuss">
        <Link href="/protokoll">Was ist bisher passiert</Link>
      </div>
    </main>
  );
}
