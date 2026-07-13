import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { authUser } from '../middleware/auth.js';
import { verifyJwt } from '../auth/crypto.js';
import { config } from '../config.js';
import * as social from '../services/social.js';

// SSE-Auth: EventSource kann keine Header setzen -> Token als Query-Parameter.
function authFromQuery(req: FastifyRequest): string {
  const { token } = z.object({ token: z.string() }).parse(req.query);
  const payload = verifyJwt(token, config.jwtSecret);
  if (!payload || payload.typ !== 'access') {
    const err = new Error('Nicht angemeldet');
    (err as { statusCode?: number }).statusCode = 401;
    throw err;
  }
  return payload.sub;
}

export async function socialRoutes(app: FastifyInstance): Promise<void> {
  // ---- Freunde ----
  app.post('/v1/friends/request', async (req) => {
    const { userId } = authUser(req);
    const { email } = z.object({ email: z.string() }).parse(req.body);
    return social.requestFriend(userId, email);
  });
  app.post('/v1/friends/accept', async (req) => {
    const { userId } = authUser(req);
    const { requestId } = z.object({ requestId: z.string() }).parse(req.body);
    return social.acceptFriend(userId, requestId);
  });
  app.get('/v1/friends', async (req) => {
    const { userId } = authUser(req);
    return { friends: social.listFriends(userId), requests: social.incomingRequests(userId) };
  });

  // ---- Live-Position ----
  app.post('/v1/live/update', async (req) => {
    const { userId } = authUser(req);
    const b = z.object({ lat: z.number(), lon: z.number(), heading: z.number().optional() }).parse(req.body);
    return social.updatePosition(userId, b.lat, b.lon, b.heading);
  });

  // ---- Standort-Freigabe per Link ----
  app.post('/v1/share/start', async (req) => {
    const { userId } = authUser(req);
    const { minutes } = z.object({ minutes: z.number().min(5).max(1440).default(60) }).parse(req.body ?? {});
    return social.startShare(userId, minutes);
  });
  app.post('/v1/share/stop', async (req) => {
    const { userId } = authUser(req);
    return social.stopShare(userId);
  });
  app.get('/v1/share/me', async (req) => {
    const { userId } = authUser(req);
    return { share: social.myShare(userId) };
  });
  // Öffentlich: geteilten Standort per Code ansehen (auch ohne Konto)
  app.get('/v1/live/share/:code', async (req) => {
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const view = social.viewShare(code);
    if (!view) {
      const err = new Error('Freigabe abgelaufen oder unbekannt');
      (err as { statusCode?: number }).statusCode = 404;
      throw err;
    }
    return view;
  });

  // ---- Echtzeit-Stream (SSE) ----
  app.get('/v1/live/stream', async (req, reply) => {
    const userId = authFromQuery(req);
    reply.hijack();
    const raw = reply.raw;
    raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    raw.write('retry: 3000\n\n');
    const sink = (event: string, data: unknown) => raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    const unsub = social.subscribe(userId, sink);
    const heartbeat = setInterval(() => raw.write(': ping\n\n'), 15000);
    req.raw.on('close', () => {
      clearInterval(heartbeat);
      unsub();
    });
  });
}
