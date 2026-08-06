import Link from 'next/link';
import { redirect } from 'next/navigation';
import { konfig } from '../../../lib/konfig';
import { CODE_GUELTIG_MINUTEN, MAX_VERSUCHE } from '../../../lib/sitzung';
import { codeErneutSenden, codePruefen } from '../../aktionen';

export const dynamic = 'force-dynamic';

/**
 * Schritt 2 der Anmeldung: den Code aus der Mail abtippen.
 *
 * Die Adresse steht in der URL, damit ein Neuladen der Seite den Schritt
 * nicht zerstoert. Sie ist kein Geheimnis — die Nutzerin hat sie eine Seite
 * vorher selbst eingetippt, und ohne den Code aus ihrem Postfach nuetzt sie
 * niemandem etwas.
 *
 * Der statische Pfad /anmelden/code gewinnt gegen das dynamische
 * /anmelden/[token] daneben; ein Link-Token besteht aus 32 zufaelligen
 * Bytes und lautet nie "code".
 */
export default async function CodeEingeben({
  searchParams,
}: {
  searchParams: Promise<{ email?: string; fehler?: string; hinweis?: string }>;
}) {
  const { email, fehler, hinweis } = await searchParams;
  if (!email) redirect('/anmelden');

  return (
    <main style={{ maxWidth: '26rem', paddingTop: '5rem' }}>
      <h1>Code eingeben</h1>
      <p className="leise" style={{ marginTop: 0, marginBottom: '2rem' }}>
        Wir haben einen sechsstelligen Code an <strong>{email}</strong> geschickt. Er gilt{' '}
        {CODE_GUELTIG_MINUTEN} Minuten.
      </p>

      {fehler && <div className="hinweis">{fehlertext(fehler)}</div>}
      {hinweis === 'erneut' && <div className="hinweis">Ein neuer Code ist unterwegs.</div>}
      {hinweis === 'zu_haeufig' && (
        <div className="hinweis">
          Es wurde gerade schon ein Code verschickt. Sehen Sie im Postfach nach — die
          vorherige Mail gilt noch.
        </div>
      )}

      {konfig.demoModus && (
        <div className="hinweis">
          Im Demo-Modus wird nichts versendet. Der Code steht auf der Konsole, auf der{' '}
          <code>npm run dev</code> läuft.
        </div>
      )}

      <form action={codePruefen}>
        <input type="hidden" name="email" value={email} />
        <div className="feld">
          <label htmlFor="code">Code aus der Mail</label>
          <input
            id="code"
            name="code"
            type="text"
            required
            autoFocus
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]*"
            maxLength={6}
            placeholder="123456"
            style={{ fontSize: '1.5rem', letterSpacing: '0.4em', fontFamily: 'monospace' }}
          />
        </div>
        <button type="submit">Anmelden</button>
      </form>

      <div style={{ marginTop: '1.5rem', display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
        <form action={codeErneutSenden}>
          <input type="hidden" name="email" value={email} />
          <button className="leise-knopf" type="submit">
            Neuen Code schicken
          </button>
        </form>
        <Link className="leise" href="/anmelden">
          Andere Adresse
        </Link>
      </div>

      <p className="leise" style={{ marginTop: '2.5rem' }}>
        In derselben Mail steht auch ein Link, der Sie direkt anmeldet. Der Code ist der
        Weg, der auch dann funktioniert, wenn Ihr Mailprogramm Links in seinem eigenen
        Browser öffnet.
      </p>
    </main>
  );
}

function fehlertext(fehler: string): string {
  switch (fehler) {
    case 'falsch':
      return 'Der Code stimmt nicht. Bitte prüfen Sie die Ziffern aus der Mail.';
    case 'abgelaufen':
      return `Es liegt kein gültiger Code vor. Codes gelten ${CODE_GUELTIG_MINUTEN} Minuten und nur einmal — fordern Sie einen neuen an.`;
    case 'zu_viele_versuche':
      return `Nach ${MAX_VERSUCHE} Fehlversuchen ist dieser Code gesperrt. Fordern Sie einen neuen an.`;
    default:
      return 'Das hat nicht geklappt. Bitte fordern Sie einen neuen Code an.';
  }
}
