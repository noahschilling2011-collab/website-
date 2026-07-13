import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { LonLat, PoiCategory, Place, RouteResponse, WeatherSample } from '@meridian/shared';
import { computeRoutes } from '../services/routing.js';
import { weatherAlong } from '../services/weather.js';
import { poisAlong } from '../services/poi.js';
import { scoreRoutes, pickRecommended, explainRecommendation } from '../services/aiRouter.js';

const lonLat = z.tuple([z.number(), z.number()]);

const routeBody = z.object({
  mode: z.enum(['auto', 'bicycle', 'pedestrian', 'transit']).default('auto'),
  waypoints: z.array(lonLat).min(2),
  preference: z.enum(['fastest', 'comfortable', 'eco', 'scenic']).default('fastest'),
  departAt: z.string().datetime().optional(),
  alternatives: z.number().min(1).max(4).default(3),
  include: z.array(z.string()).default([]),
  avoid: z.array(z.string()).optional(),
});

export async function routeRoutes(app: FastifyInstance): Promise<void> {
  app.post('/v1/route', async (req): Promise<RouteResponse> => {
    const body = routeBody.parse(req.body);

    const routes = await computeRoutes({
      mode: body.mode,
      waypoints: body.waypoints as LonLat[],
      preference: body.preference,
      alternatives: body.alternatives,
      avoid: body.avoid,
    });

    const wantWeather = body.include.includes('weather');
    const poiCats = body.include
      .filter((i) => i.startsWith('poi:'))
      .map((i) => i.slice(4)) as PoiCategory[];

    const best = routes[0];

    // Kontext parallel für die (vorläufig) erste Route holen.
    const [weather, pois] = await Promise.all([
      wantWeather && best
        ? weatherAlong(best.geometry, body.departAt, best.duration)
        : Promise.resolve<WeatherSample[]>([]),
      poiCats.length && best
        ? Promise.all(poiCats.map((c) => poisAlong(best.geometry, c).then((p) => [c, p] as const))).then(
            (entries) => Object.fromEntries(entries) as Record<string, Place[]>,
          )
        : Promise.resolve<Record<string, Place[]>>({}),
    ]);

    scoreRoutes(routes, body.preference, { weather });
    const recommended = pickRecommended(routes);
    const explanation = await explainRecommendation(routes, recommended, body.preference);

    // ETA setzen
    const start = body.departAt ? new Date(body.departAt) : new Date();
    for (const r of routes) {
      r.eta = new Date(start.getTime() + r.duration * 1000).toISOString();
    }

    return {
      routes,
      recommended,
      explanation,
      weather: wantWeather ? weather : undefined,
      pois: poiCats.length ? pois : undefined,
    };
  });

  // Wetter / POIs eigenständig (für „entlang der aktuellen Route“ nachladen)
  app.get('/v1/weather', async (req) => {
    const q = z.object({ path: z.string().min(1), departAt: z.string().optional(), duration: z.coerce.number().default(3600) });
    const { path, departAt, duration } = q.parse(req.query);
    return { samples: await weatherAlong(path, departAt, duration) };
  });

  app.get('/v1/poi', async (req) => {
    const q = z.object({
      path: z.string().min(1),
      category: z.enum(['fuel', 'charging', 'restaurant', 'hotel', 'parking']),
      buffer: z.coerce.number().min(200).max(10000).default(2000),
    });
    const { path, category, buffer } = q.parse(req.query);
    return { results: await poisAlong(path, category, buffer) };
  });
}
