import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { config } from './config.js';
import { registerErrorHandler } from './middleware/errors.js';
import { healthRoutes } from './routes/health.js';
import { searchRoutes } from './routes/search.js';
import { routeRoutes } from './routes/route.js';
import { styleRoutes } from './routes/style.js';
import { assistantRoutes } from './routes/assistant.js';
import { communityRoutes } from './routes/community.js';
import { authRoutes } from './routes/auth.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.logLevel },
    trustProxy: true,
  });

  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, {
    origin: config.corsOrigins.includes('*') ? true : config.corsOrigins,
  });
  await app.register(rateLimit, {
    max: 300,
    timeWindow: '1 minute',
  });

  registerErrorHandler(app);

  await app.register(healthRoutes);
  await app.register(searchRoutes);
  await app.register(routeRoutes);
  await app.register(styleRoutes);
  await app.register(assistantRoutes);
  await app.register(communityRoutes);
  await app.register(authRoutes);

  return app;
}
