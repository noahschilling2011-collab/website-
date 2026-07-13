import type { FastifyInstance } from 'fastify';
import { config } from '../config.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => ({ status: 'ok', ts: new Date().toISOString() }));

  app.get('/v1/status', async () => ({
    service: 'meridian-gateway',
    version: '1.0.0',
    upstreams: {
      valhalla: Boolean(config.upstreams.valhalla),
      photon: Boolean(config.upstreams.photon),
      overpass: Boolean(config.upstreams.overpass),
      weather: Boolean(config.upstreams.openMeteo),
    },
    ai: config.ai.provider,
  }));
}
