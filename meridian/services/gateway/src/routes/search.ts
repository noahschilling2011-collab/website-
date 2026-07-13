import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { LonLat } from '@meridian/shared';
import { search, reverse } from '../services/search.js';

const nearSchema = z
  .string()
  .optional()
  .transform((v) => {
    if (!v) return undefined;
    const [lon, lat] = v.split(',').map(Number);
    return Number.isFinite(lon) && Number.isFinite(lat) ? ([lon, lat] as LonLat) : undefined;
  });

export async function searchRoutes(app: FastifyInstance): Promise<void> {
  app.get('/v1/search', async (req) => {
    const q = z.object({ q: z.string().min(1), near: nearSchema, limit: z.coerce.number().min(1).max(20).default(8) });
    const { q: query, near, limit } = q.parse(req.query);
    return { results: await search(query, near, limit) };
  });

  // Typeahead-Alias
  app.get('/v1/suggest', async (req) => {
    const q = z.object({ q: z.string().min(1), near: nearSchema });
    const { q: query, near } = q.parse(req.query);
    return { results: await search(query, near, 6) };
  });

  app.get('/v1/reverse', async (req) => {
    const q = z.object({ lon: z.coerce.number(), lat: z.coerce.number() });
    const { lon, lat } = q.parse(req.query);
    return { result: await reverse(lon, lat) };
  });
}
