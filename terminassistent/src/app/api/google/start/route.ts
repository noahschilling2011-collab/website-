import { NextResponse } from 'next/server';
import { googleKonfiguriert, zustimmungsUrl } from '../../../../lib/google-oauth';
import { aktuelleNutzerin } from '../../../../lib/sitzung';

export const dynamic = 'force-dynamic';

export async function GET(): Promise<Response> {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) return NextResponse.redirect(new URL('/anmelden', process.env.APP_URL ?? 'http://localhost:3000'));

  if (!googleKonfiguriert()) {
    return NextResponse.json(
      { fehler: 'GOOGLE_CLIENT_ID und GOOGLE_CLIENT_SECRET fehlen. Siehe .env.example.' },
      { status: 503 },
    );
  }

  return NextResponse.redirect(zustimmungsUrl(nutzer.id));
}
