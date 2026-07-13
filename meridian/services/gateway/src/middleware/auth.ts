// Bearer-JWT-Prüfung für geschützte Endpunkte.
import type { FastifyRequest } from 'fastify';
import { verifyJwt } from '../auth/crypto.js';
import { config } from '../config.js';

export interface AuthContext {
  userId: string;
  sessionId?: string;
}

export function authUser(req: FastifyRequest): AuthContext {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    throw unauthorized();
  }
  const payload = verifyJwt(header.slice(7), config.jwtSecret);
  if (!payload || payload.typ !== 'access') throw unauthorized();
  return { userId: payload.sub, sessionId: payload.sid };
}

// Kontext für Sicherheits-Events aus dem Request ableiten.
export function loginCtx(req: FastifyRequest) {
  const ua = String(req.headers['user-agent'] ?? '');
  return { ip: req.ip, userAgent: ua, device: deviceLabel(ua) };
}

function deviceLabel(ua: string): string {
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua)) return 'iPad';
  if (/Android/.test(ua)) return 'Android-Gerät';
  if (/Macintosh/.test(ua)) return 'Mac';
  if (/Windows/.test(ua)) return 'Windows-PC';
  if (/Linux/.test(ua)) return 'Linux';
  return 'Browser';
}

function unauthorized(): Error {
  const err = new Error('Nicht angemeldet');
  (err as { statusCode?: number }).statusCode = 401;
  return err;
}
