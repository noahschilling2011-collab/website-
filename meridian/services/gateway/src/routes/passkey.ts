// Passkeys / WebAuthn (passwortlose & biometrische Anmeldung — Face ID/Touch ID/
// Windows Hello laufen über denselben WebAuthn-Flow auf dem Gerät).
//
// Die *Options*-Endpunkte (Challenge-Ausgabe) sind vollständig implementiert.
// Die kryptografische Verifikation von Attestation/Assertion erfordert eine
// geprüfte Bibliothek — Meridian nutzt dafür @simplewebauthn/server. Solange die
// nicht eingebunden ist, antwortet /verify mit 501 (kein Fake-Sicherheitscheck).
// Details & Integrationsschritte: docs/ACCOUNTS.md.
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { randomToken } from '../auth/crypto.js';

const challenges = new Map<string, { challenge: string; expires: number }>();

export async function registerPasskeyRoutes(app: FastifyInstance): Promise<void> {
  // Registrierungs-Optionen (navigator.credentials.create)
  app.post('/v1/auth/passkey/register-options', async (req) => {
    const body = z.object({ userId: z.string(), email: z.string() }).parse(req.body);
    const challenge = randomToken(32);
    challenges.set(body.userId, { challenge, expires: Date.now() + 5 * 60 * 1000 });
    return {
      challenge,
      rp: { id: config.rpId, name: 'Meridian' },
      user: { id: body.userId, name: body.email, displayName: body.email },
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 }, // ES256
        { type: 'public-key', alg: -257 }, // RS256
      ],
      authenticatorSelection: { residentKey: 'preferred', userVerification: 'preferred' },
      timeout: 60000,
      attestation: 'none',
    };
  });

  // Anmelde-Optionen (navigator.credentials.get)
  app.post('/v1/auth/passkey/login-options', async (req) => {
    const body = z.object({ email: z.string().optional() }).parse(req.body);
    const challenge = randomToken(32);
    challenges.set(body.email ?? 'discoverable', { challenge, expires: Date.now() + 5 * 60 * 1000 });
    return { challenge, rpId: config.rpId, userVerification: 'preferred', timeout: 60000 };
  });

  // Verifikation — benötigt @simplewebauthn/server (siehe docs/ACCOUNTS.md).
  const notImplemented = async (_req: unknown, reply: { code: (n: number) => { send: (b: unknown) => unknown } }) =>
    reply.code(501).send({
      error: 'verification_requires_library',
      message:
        'Passkey-Verifikation erfordert @simplewebauthn/server für die kryptografische Prüfung ' +
        'der Attestation/Assertion. Options-Flow ist aktiv; Integration siehe docs/ACCOUNTS.md.',
    });
  app.post('/v1/auth/passkey/register-verify', notImplemented);
  app.post('/v1/auth/passkey/login-verify', notImplemented);
}
