/**
 * Realtime gateway (Socket.IO). Clients authenticate with their access
 * token and join a per-user room; CRUD services publish sync events so
 * every device of a user stays consistent (cloud sync / offline queue).
 *
 * Horizontal scaling: attach the Redis adapter (socket.io/redis-adapter)
 * so events reach users connected to other pods.
 */
import type { Server as HttpServer } from 'node:http';
import { Server } from 'socket.io';
import { verifyAccessToken } from '../middleware/auth.js';
import { logger } from '../utils/logger.js';

let io: Server | null = null;

export function initWebSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: { origin: '*' },
    path: '/ws',
  });

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token as string | undefined;
      if (!token) return next(new Error('missing token'));
      const user = verifyAccessToken(token);
      socket.data.user = user;
      next();
    } catch {
      next(new Error('invalid token'));
    }
  });

  io.on('connection', (socket) => {
    const userId = socket.data.user.id as string;
    socket.join(`user:${userId}`);
    logger.debug({ userId }, 'WS connected');

    socket.on('workspace:join', (workspaceId: string) => {
      if (typeof workspaceId === 'string') socket.join(`workspace:${workspaceId}`);
    });
    socket.on('workspace:leave', (workspaceId: string) => {
      if (typeof workspaceId === 'string') socket.leave(`workspace:${workspaceId}`);
    });
  });

  return io;
}

/** Emits a sync event to all connected devices of a user. No-op before init. */
export function publishToUser(userId: string, event: string, payload: unknown): void {
  io?.to(`user:${userId}`).emit(event, payload);
}

export function publishToWorkspace(workspaceId: string, event: string, payload: unknown): void {
  io?.to(`workspace:${workspaceId}`).emit(event, payload);
}
