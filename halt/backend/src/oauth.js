// Social login (OAuth 2.0 / OpenID Connect).
//
// GOOGLE is implemented for real (free to set up). APPLE is scaffolded — the same
// shape — but needs a paid Apple Developer account, so its client-secret signing
// is left as a clearly-marked TODO and it stays off until configured.
//
// The security-critical bits (CSRF state, ID-token claim validation) are pure
// functions with unit tests. The HTTP calls take an injectable fetch so the flow
// is testable without hitting Google.

import { randomBytes } from 'node:crypto';

const GOOGLE_AUTH = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN = 'https://oauth2.googleapis.com/token';
const GOOGLE_TOKENINFO = 'https://oauth2.googleapis.com/tokeninfo';

const randomHex = () => randomBytes(24).toString('hex');

/** Validate the claims of a Google ID token. Pure + throws on any problem. */
export function validateGoogleClaims(claims, clientId, now) {
  if (!claims || typeof claims !== 'object') throw new Error('Keine Token-Daten.');
  if (claims.aud !== clientId) throw new Error('Token nicht für diese App (aud).');
  const iss = claims.iss;
  if (iss !== 'https://accounts.google.com' && iss !== 'accounts.google.com') {
    throw new Error('Falscher Aussteller (iss).');
  }
  if (!claims.exp || Number(claims.exp) * 1000 < now) throw new Error('Token abgelaufen.');
  if (!claims.email) throw new Error('Keine E-Mail vom Anbieter.');
  const verified = claims.email_verified === true || claims.email_verified === 'true';
  if (!verified) throw new Error('E-Mail beim Anbieter nicht verifiziert.');
  return { email: String(claims.email).toLowerCase(), provider: 'google' };
}

export function createOAuth(config) {
  const states = new Map(); // state -> expiry ms

  function newState(now) {
    const s = randomHex();
    states.set(s, now + 10 * 60 * 1000); // 10 min
    // opportunistic cleanup
    for (const [k, exp] of states) if (exp < now) states.delete(k);
    return s;
  }
  function consumeState(s, now) {
    const exp = states.get(s);
    states.delete(s);
    return Boolean(exp && now < exp);
  }

  const googleRedirect = () => `${config.appUrl}/auth/google/callback`;

  function googleStartUrl(state) {
    const p = new URLSearchParams({
      client_id: config.oauth.google.clientId,
      redirect_uri: googleRedirect(),
      response_type: 'code',
      scope: 'openid email',
      state,
      prompt: 'select_account',
    });
    return `${GOOGLE_AUTH}?${p.toString()}`;
  }

  // Exchange the auth code for an ID token and validate it. Returns { email }.
  async function googleExchange(code, now, fetchImpl = fetch) {
    const tokenRes = await fetchImpl(GOOGLE_TOKEN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: config.oauth.google.clientId,
        client_secret: config.oauth.google.clientSecret,
        redirect_uri: googleRedirect(),
        grant_type: 'authorization_code',
      }),
    });
    const tokenData = await tokenRes.json().catch(() => ({}));
    if (!tokenRes.ok) throw new Error(`Google Token: ${tokenData.error_description || tokenData.error || tokenRes.status}`);
    if (!tokenData.id_token) throw new Error('Google lieferte kein id_token.');

    // Validate the ID token via Google's tokeninfo endpoint (verifies signature).
    const infoRes = await fetchImpl(`${GOOGLE_TOKENINFO}?id_token=${encodeURIComponent(tokenData.id_token)}`);
    const claims = await infoRes.json().catch(() => ({}));
    if (!infoRes.ok) throw new Error('Google Tokeninfo: ungültiges Token.');
    return validateGoogleClaims(claims, config.oauth.google.clientId, now);
  }

  // ── Apple (scaffold) ────────────────────────────────────────────────────────
  const appleRedirect = () => `${config.appUrl}/auth/apple/callback`;
  function appleStartUrl(state) {
    const p = new URLSearchParams({
      client_id: config.oauth.apple.clientId,
      redirect_uri: appleRedirect(),
      response_type: 'code',
      scope: 'name email',
      response_mode: 'form_post',
      state,
    });
    return `https://appleid.apple.com/auth/authorize?${p.toString()}`;
  }
  // TODO(apple): exchanging the code requires a client secret that is an ES256
  // JWT signed with your Apple private key (needs the paid Developer account).
  // Left unimplemented on purpose rather than shipped untested.

  return {
    newState,
    consumeState,
    googleStartUrl,
    googleExchange,
    appleStartUrl,
    googleRedirect,
  };
}
