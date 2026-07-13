// OAuth 2.0 / OIDC Authorization-Code-Flow für Google & Microsoft.
// Aktiv, sobald Client-ID/Secret gesetzt sind (siehe .env.example). Apple (Sign in
// with Apple) benötigt ein signiertes JWT-Client-Secret — Struktur in docs/ACCOUNTS.md.
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { request } from 'undici';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';
import * as auth from '../auth/service.js';
import { loginCtx } from '../middleware/auth.js';
import { randomToken } from '../auth/crypto.js';

interface ProviderCfg {
  authUrl: string;
  tokenUrl: string;
  userinfoUrl: string;
  scope: string;
  clientId: string;
  clientSecret: string;
}

function providerConfig(provider: string): ProviderCfg | null {
  if (provider === 'google' && config.oauth.google.clientId) {
    return {
      authUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenUrl: 'https://oauth2.googleapis.com/token',
      userinfoUrl: 'https://openidconnect.googleapis.com/v1/userinfo',
      scope: 'openid email profile',
      ...config.oauth.google,
    };
  }
  if (provider === 'microsoft' && config.oauth.microsoft.clientId) {
    const t = config.oauth.microsoft.tenant;
    return {
      authUrl: `https://login.microsoftonline.com/${t}/oauth2/v2.0/authorize`,
      tokenUrl: `https://login.microsoftonline.com/${t}/oauth2/v2.0/token`,
      userinfoUrl: 'https://graph.microsoft.com/oidc/userinfo',
      scope: 'openid email profile',
      clientId: config.oauth.microsoft.clientId,
      clientSecret: config.oauth.microsoft.clientSecret,
    };
  }
  return null;
}

// Kurzlebiger State-Speicher (CSRF-Schutz). Produktion: Redis mit TTL.
const stateStore = new Map<string, number>();

function redirectUri(provider: string): string {
  return `${config.appUrl.replace(/\/$/, '')}/v1/auth/oauth/${provider}/callback`;
}

export async function registerOAuthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/v1/auth/oauth/:provider/start', async (req, reply) => {
    const { provider } = z.object({ provider: z.string() }).parse(req.params);
    const cfg = providerConfig(provider);
    if (!cfg) {
      reply.code(501);
      return { error: 'not_configured', message: `OAuth für ${provider} nicht konfiguriert (Client-ID/Secret setzen).` };
    }
    const state = randomToken(16);
    stateStore.set(state, Date.now() + 10 * 60 * 1000);
    const url = new URL(cfg.authUrl);
    url.searchParams.set('client_id', cfg.clientId);
    url.searchParams.set('redirect_uri', redirectUri(provider));
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('scope', cfg.scope);
    url.searchParams.set('state', state);
    return { url: url.toString() };
  });

  app.get('/v1/auth/oauth/:provider/callback', async (req, reply) => {
    const { provider } = z.object({ provider: z.string() }).parse(req.params);
    const q = z.object({ code: z.string(), state: z.string() }).parse(req.query);
    const cfg = providerConfig(provider);
    if (!cfg) {
      reply.code(501);
      return { error: 'not_configured' };
    }
    const expiry = stateStore.get(q.state);
    if (!expiry || expiry < Date.now()) {
      reply.code(400);
      return { error: 'invalid_state' };
    }
    stateStore.delete(q.state);

    // Code -> Token (Form-POST)
    const tokenRes = await request(cfg.tokenUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
      body: new URLSearchParams({
        code: q.code,
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
        redirect_uri: redirectUri(provider),
        grant_type: 'authorization_code',
      }).toString(),
    });
    const token = (await tokenRes.body.json()) as { access_token: string };

    // Token -> Userinfo
    const info = await fetchJson<{ sub: string; email?: string; name?: string }>('oauth-userinfo', cfg.userinfoUrl, {
      headers: { authorization: `Bearer ${token.access_token}` },
    });

    const result = auth.oauthUpsert({ provider, sub: info.sub, email: info.email, name: info.name }, loginCtx(req));
    // Tokens an die App zurückgeben (Fragment, damit sie nicht im Referrer landen).
    return reply.redirect(`${config.appUrl}/#access=${result.tokens.accessToken}&refresh=${result.tokens.refreshToken}`);
  });
}
