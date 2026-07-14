import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import { createYoga } from 'graphql-yoga';
import { config } from './config/index.js';
import { logger } from './utils/logger.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { verifyAccessToken } from './middleware/auth.js';
import { authRouter } from './modules/auth/auth.routes.js';
import { usersRouter } from './modules/users/users.routes.js';
import { aiRouter } from './modules/ai/ai.routes.js';
import { tasksRouter } from './modules/tasks/tasks.routes.js';
import { notesRouter } from './modules/notes/notes.routes.js';
import { calendarRouter } from './modules/calendar/calendar.routes.js';
import { workspacesRouter } from './modules/workspaces/workspaces.routes.js';
import { filesRouter } from './modules/files/files.routes.js';
import { adminRouter, analyticsRouter } from './modules/analytics/analytics.routes.js';
import { schema, type GqlContext } from './graphql/schema.js';

export function createApp(): express.Express {
  const app = express();

  app.set('trust proxy', 1);
  // CSP allows the inline script/styles of the single-file web app in public/.
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'", 'https:', 'wss:'],
      },
    },
  }));
  app.use(cors({ origin: config.corsOrigin === '*' ? true : config.corsOrigin.split(',') }));
  app.use(express.json({ limit: '10mb' }));
  app.use(pinoHttp({
    logger,
    autoLogging: { ignore: (req) => req.url === '/health' },
  }));

  // Liveness/readiness for load balancers and Kubernetes probes.
  app.get('/health', (_req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

  // Single-file web app (website + installable PWA-style client).
  app.use(express.static('public', { index: 'index.html', maxAge: '5m' }));

  app.use('/api/auth', authRouter);
  app.use('/api/users', usersRouter);
  app.use('/api/ai', aiRouter);
  app.use('/api/tasks', tasksRouter);
  app.use('/api/notes', notesRouter);
  app.use('/api/calendar', calendarRouter);
  app.use('/api/workspaces', workspacesRouter);
  app.use('/api/files', filesRouter);
  app.use('/api/analytics', analyticsRouter);
  app.use('/api/admin', adminRouter);

  const yoga = createYoga<GqlContext>({
    schema,
    graphqlEndpoint: '/graphql',
    context: ({ request }): GqlContext => {
      const header = request.headers.get('authorization');
      if (!header?.startsWith('Bearer ')) return { user: null };
      try {
        return { user: verifyAccessToken(header.slice(7)) };
      } catch {
        return { user: null };
      }
    },
  });
  // graphql-yoga's fetch-style handler is request-compatible with Express
  // but its call signatures don't line up with Express typings.
  app.use('/graphql', yoga as unknown as express.RequestHandler);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
