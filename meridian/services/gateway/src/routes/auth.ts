import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authUser, loginCtx } from '../middleware/auth.js';
import * as auth from '../auth/service.js';
import { registerOAuthRoutes } from './oauth.js';
import { registerPasskeyRoutes } from './passkey.js';

// AuthError -> HTTP-Status abbilden
function handle<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof auth.AuthError) {
      const err = new Error(e.message);
      (err as { statusCode?: number }).statusCode = e.status;
      throw err;
    }
    throw e;
  }
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  // ---- Registrierung / Login ----
  app.post('/v1/auth/register', async (req) => {
    const body = z.object({ email: z.string(), password: z.string(), name: z.string().optional() }).parse(req.body);
    return handle(() => auth.register(body, loginCtx(req)));
  });

  app.post('/v1/auth/login', async (req) => {
    const body = z
      .object({ email: z.string(), password: z.string(), totp: z.string().optional(), backupCode: z.string().optional() })
      .parse(req.body);
    return handle(() => auth.login(body, loginCtx(req)));
  });

  app.post('/v1/auth/refresh', async (req) => {
    const body = z.object({ refreshToken: z.string() }).parse(req.body);
    return handle(() => ({ tokens: auth.refresh(body.refreshToken, loginCtx(req)) }));
  });

  app.post('/v1/auth/guest', async (req) => auth.createGuest(loginCtx(req)));

  app.post('/v1/auth/logout', async (req) => {
    const { userId, sessionId } = authUser(req);
    return handle(() => (auth.logout(userId, sessionId ?? '', loginCtx(req)), { ok: true }));
  });
  app.post('/v1/auth/logout-all', async (req) => {
    const { userId, sessionId } = authUser(req);
    return handle(() => (auth.logoutAll(userId, sessionId, loginCtx(req)), { ok: true }));
  });

  // ---- Profil ----
  app.get('/v1/me', async (req) => {
    const { userId } = authUser(req);
    return handle(() => auth.getMe(userId));
  });
  app.patch('/v1/me', async (req) => {
    const { userId } = authUser(req);
    const body = z.object({ name: z.string().optional(), avatarColor: z.string().optional() }).parse(req.body);
    return handle(() => auth.updateProfile(userId, body));
  });

  // ---- Geräte / Sitzungen ----
  app.get('/v1/auth/sessions', async (req) => {
    const { userId, sessionId } = authUser(req);
    return handle(() => ({ sessions: auth.listSessions(userId, sessionId) }));
  });
  app.delete('/v1/auth/sessions/:id', async (req) => {
    const { userId } = authUser(req);
    const { id } = z.object({ id: z.string() }).parse(req.params);
    return handle(() => (auth.revokeSession(userId, id, loginCtx(req)), { ok: true }));
  });

  // ---- Zwei-Faktor (TOTP) ----
  app.post('/v1/auth/2fa/enroll', async (req) => {
    const { userId } = authUser(req);
    return handle(() => auth.enroll2FA(userId));
  });
  app.post('/v1/auth/2fa/enable', async (req) => {
    const { userId } = authUser(req);
    const body = z.object({ code: z.string() }).parse(req.body);
    return handle(() => auth.enable2FA(userId, body.code));
  });
  app.post('/v1/auth/2fa/disable', async (req) => {
    const { userId } = authUser(req);
    const body = z.object({ code: z.string() }).parse(req.body);
    return handle(() => auth.disable2FA(userId, body.code));
  });

  // ---- Sicherheitsprotokoll ----
  app.get('/v1/account/security-log', async (req) => {
    const { userId } = authUser(req);
    return handle(() => ({ events: auth.getSecurityLog(userId) }));
  });

  // ---- Datenschutz-Dashboard: Berechtigungen ----
  app.get('/v1/account/permissions', async (req) => {
    const { userId } = authUser(req);
    return handle(() => ({ permissions: auth.getPermissions(userId) }));
  });
  app.put('/v1/account/permissions', async (req) => {
    const { userId } = authUser(req);
    const body = z
      .object({
        location: z.boolean().optional(), camera: z.boolean().optional(), microphone: z.boolean().optional(),
        notifications: z.boolean().optional(), analytics: z.boolean().optional(), personalization: z.boolean().optional(),
      })
      .parse(req.body);
    return handle(() => ({ permissions: auth.setPermissions(userId, body) }));
  });

  // ---- E2E-Vault (Server speichert nur Chiffrat) ----
  app.put('/v1/vault/:key', async (req) => {
    const { userId } = authUser(req);
    const { key } = z.object({ key: z.string() }).parse(req.params);
    const body = z.object({ ciphertext: z.string() }).parse(req.body);
    return handle(() => auth.vaultSet(userId, key, body.ciphertext));
  });
  app.get('/v1/vault/:key', async (req) => {
    const { userId } = authUser(req);
    const { key } = z.object({ key: z.string() }).parse(req.params);
    return handle(() => auth.vaultGet(userId, key));
  });

  // ---- DSGVO: Export & Löschung ----
  app.get('/v1/account/export', async (req) => {
    const { userId } = authUser(req);
    return handle(() => auth.exportData(userId));
  });
  app.delete('/v1/account', async (req) => {
    const { userId } = authUser(req);
    return handle(() => auth.deleteAccount(userId));
  });

  await registerOAuthRoutes(app);
  await registerPasskeyRoutes(app);
}
