import Link from 'next/link';
import { redirect } from 'next/navigation';
import { loeseTokenEin } from '../../../lib/sitzung';

export const dynamic = 'force-dynamic';

export default async function TokenEinloesen({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const nutzer = await loeseTokenEin(token);
  if (nutzer) redirect('/');

  return (
    <main style={{ maxWidth: '26rem', paddingTop: '5rem' }}>
      <h1>Link ungültig</h1>
      <p className="leise">
        Der Link ist abgelaufen oder wurde bereits benutzt. Anmeldelinks gelten 30 Minuten
        und nur einmal.
      </p>
      <Link className="knopf" href="/anmelden">
        Neuen Link anfordern
      </Link>
    </main>
  );
}
