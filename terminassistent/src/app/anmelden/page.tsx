import { konfig } from '../../lib/konfig';
import { anmelden } from '../aktionen';

export const dynamic = 'force-dynamic';

export default async function Anmelden({
  searchParams,
}: {
  searchParams: Promise<{ gesendet?: string }>;
}) {
  const { gesendet } = await searchParams;

  return (
    <main style={{ maxWidth: '26rem', paddingTop: '5rem' }}>
      <h1>Terminassistent</h1>
      <p className="leise" style={{ marginTop: 0, marginBottom: '2rem' }}>
        Erledigt Terminabsprachen und Fristen per Mail.
      </p>

      {gesendet ? (
        <div className="karte">
          <p style={{ marginTop: 0 }}>
            Wenn die Adresse bei uns bekannt ist, liegt der Anmeldelink jetzt im Postfach.
            Er gilt 30 Minuten.
          </p>
          {konfig.demoModus && (
            <p className="leise" style={{ marginBottom: 0 }}>
              Im Demo-Modus wird nichts versendet — der Link steht auf der Konsole, auf der{' '}
              <code>npm run dev</code> läuft.
            </p>
          )}
        </div>
      ) : (
        <form action={anmelden}>
          <div className="feld">
            <label htmlFor="email">Ihre E-Mail-Adresse</label>
            <input id="email" name="email" type="email" required autoComplete="email" />
          </div>
          <button type="submit">Anmeldelink schicken</button>
        </form>
      )}

      <p className="leise" style={{ marginTop: '2.5rem' }}>
        Kein Passwort, kein Google-Login. Der Zugriff auf Ihren Kalender wird erst später
        gefragt — dann, wenn der erste Termin eingetragen werden soll.
      </p>
    </main>
  );
}
