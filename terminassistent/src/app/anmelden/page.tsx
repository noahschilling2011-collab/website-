import { anmelden } from '../aktionen';

export const dynamic = 'force-dynamic';

export default async function Anmelden({
  searchParams,
}: {
  searchParams: Promise<{ fehler?: string; geloescht?: string }>;
}) {
  const { fehler, geloescht } = await searchParams;

  return (
    <main style={{ maxWidth: '26rem', paddingTop: '5rem' }}>
      <h1>Terminassistent</h1>
      <p className="leise" style={{ marginTop: 0, marginBottom: '2rem' }}>
        Erledigt Terminabsprachen und Fristen per Mail.
      </p>

      {geloescht && (
        <div className="hinweis">
          Ihr Konto und alle Daten sind gelöscht. Es ist nichts übrig geblieben.
        </div>
      )}
      {fehler === 'adresse' && (
        <div className="hinweis">Das sieht nicht nach einer E-Mail-Adresse aus.</div>
      )}
      {fehler === 'link' && (
        <div className="hinweis">
          Der Link ist abgelaufen oder wurde schon benutzt — auch dann, wenn Sie den Code aus
          derselben Mail eingegeben haben. Fordern Sie einfach einen neuen an.
        </div>
      )}

      <form action={anmelden}>
        <div className="feld">
          <label htmlFor="email">Ihre E-Mail-Adresse</label>
          <input
            id="email"
            name="email"
            type="email"
            required
            autoComplete="email"
            autoFocus
            placeholder="name@praxis.de"
          />
        </div>
        <button type="submit">Code schicken</button>
      </form>

      <p className="leise" style={{ marginTop: '2.5rem' }}>
        Sie bekommen einen sechsstelligen Code per Mail. Kein Passwort, kein Google-Login.
        Der Zugriff auf Ihren Kalender wird erst später gefragt — dann, wenn der erste
        Termin eingetragen werden soll.
      </p>
    </main>
  );
}
