import crypto from 'node:crypto';
import { GOOGLE_SCOPES } from './calendar/google';
import { konfig } from './konfig';

/**
 * Weg A, Zustimmungsdialog.
 *
 * Bewusst mit fetch statt googleapis: zwei Endpunkte rechtfertigen keine
 * mehrere Megabyte grosse Abhaengigkeit, und die angeforderten Scopes
 * bleiben im Code sichtbar statt in einer Bibliothek zu verschwinden.
 */

const AUTH_ENDPOINT = 'https://accounts.google.com/o/oauth2/v2/auth';
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

export function googleKonfiguriert(): boolean {
  return Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET);
}

export function rueckleitung(): string {
  return `${konfig.appUrl}/api/google/callback`;
}

/**
 * CSRF-Schutz. Der state bindet den Rueckweg an die Sitzung, die ihn
 * angestossen hat — sonst koennte ein Dritter einer angemeldeten Nutzerin
 * seinen eigenen Kalender unterschieben.
 */
export function baueState(nutzerId: string): string {
  const nonce = crypto.randomBytes(16).toString('base64url');
  const ablauf = Date.now() + 10 * 60_000;
  const nutzlast = `${nutzerId}.${nonce}.${ablauf}`;
  const signatur = crypto
    .createHmac('sha256', process.env.SECRET_KEY ?? 'entwicklung')
    .update(nutzlast)
    .digest('base64url');
  return `${nutzlast}.${signatur}`;
}

export function pruefeState(state: string): string | null {
  const teile = state.split('.');
  if (teile.length !== 4) return null;

  const [nutzerId, nonce, ablauf, signatur] = teile as [string, string, string, string];
  const erwartet = crypto
    .createHmac('sha256', process.env.SECRET_KEY ?? 'entwicklung')
    .update(`${nutzerId}.${nonce}.${ablauf}`)
    .digest('base64url');

  const a = Buffer.from(signatur);
  const b = Buffer.from(erwartet);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  if (Number(ablauf) < Date.now()) return null;
  return nutzerId;
}

export function zustimmungsUrl(nutzerId: string): string {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) throw new Error('GOOGLE_CLIENT_ID fehlt.');

  const parameter = new URLSearchParams({
    client_id: clientId,
    redirect_uri: rueckleitung(),
    response_type: 'code',
    scope: GOOGLE_SCOPES.join(' '),
    // Ohne offline gibt es kein Refresh-Token und der Zugriff endet nach
    // einer Stunde.
    access_type: 'offline',
    // Ohne consent liefert Google bei einer zweiten Zustimmung KEIN neues
    // Refresh-Token — dann steht man ohne da und merkt es erst spaeter.
    prompt: 'consent',
    include_granted_scopes: 'true',
    state: baueState(nutzerId),
  });

  return `${AUTH_ENDPOINT}?${parameter.toString()}`;
}

export interface TokenAntwort {
  refreshToken: string;
  scopes: string[];
}

export async function tauscheCode(code: string): Promise<TokenAntwort> {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error('Google-Zugangsdaten fehlen.');

  const antwort = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: rueckleitung(),
      grant_type: 'authorization_code',
    }),
  });

  if (!antwort.ok) {
    throw new Error(`Google hat den Code abgelehnt (${antwort.status}): ${await antwort.text()}`);
  }

  const daten = (await antwort.json()) as {
    refresh_token?: string;
    scope?: string;
  };

  if (!daten.refresh_token) {
    // Passiert, wenn die Nutzerin dieselbe App schon einmal freigegeben hat
    // und prompt=consent fehlt. Mit einem Access-Token allein waere die
    // Verbindung nach einer Stunde tot — deshalb hier abbrechen statt sie
    // scheinbar erfolgreich anzulegen.
    throw new Error(
      'Google hat kein Refresh-Token geliefert. Bitte den Zugriff unter myaccount.google.com/permissions entfernen und erneut verbinden.',
    );
  }

  const scopes = (daten.scope ?? '').split(' ').filter(Boolean);
  const fehlend = GOOGLE_SCOPES.filter((s) => !scopes.includes(s));
  if (fehlend.length > 0) {
    throw new Error(
      `Es fehlen Berechtigungen: ${fehlend.join(', ')}. Ohne sie kann ich keine Termine lesen oder eintragen.`,
    );
  }

  return { refreshToken: daten.refresh_token, scopes };
}
