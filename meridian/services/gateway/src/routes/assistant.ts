import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { LonLat } from '@meridian/shared';
import { handleCommand } from '../services/assistant.js';
import { planDayTrip } from '../services/trip.js';
import { predictAlongRoute, predictCongestion, parkingNear } from '../services/predict.js';
import { computeRoutes } from '../services/routing.js';

const lonLat = z.tuple([z.number(), z.number()]);
const placeSchema = z.object({ id: z.string(), name: z.string(), center: lonLat, address: z.string().optional() });

export async function assistantRoutes(app: FastifyInstance): Promise<void> {
  // Natürlichsprachiger Befehl -> Absicht + Aktion
  app.post('/v1/assistant/command', async (req) => {
    const body = z
      .object({
        text: z.string().min(1),
        context: z
          .object({ near: lonLat.optional(), from: placeSchema.optional(), to: placeSchema.optional(), hasRoute: z.boolean().optional() })
          .optional(),
      })
      .parse(req.body);
    return handleCommand(body.text, body.context ?? {});
  });

  // Proaktives Briefing (Premium-KI-Begleiter)
  app.post('/v1/assistant/briefing', async (req) => {
    const body = z
      .object({ from: placeSchema, to: placeSchema, mode: z.enum(['auto', 'bicycle', 'pedestrian', 'transit']).default('auto'), arriveBy: z.string().datetime().optional() })
      .parse(req.body);

    const routes = await computeRoutes({ mode: body.mode, waypoints: [body.from.center, body.to.center], preference: 'fastest', alternatives: 1 });
    const route = routes[0];
    const now = new Date();
    const congestion = predictCongestion(now);
    const durationS = route.duration * congestion.factor;
    const parking = await parkingNear(body.to.center).catch(() => []);
    const bestParking = parking[0];

    const leaveInMin = body.arriveBy
      ? Math.max(0, Math.round((Date.parse(body.arriveBy) - now.getTime()) / 60000 - durationS / 60))
      : null;

    const parts: string[] = [];
    if (leaveInMin !== null) parts.push(leaveInMin <= 0 ? 'Du solltest jetzt losfahren.' : `Du musst in ${leaveInMin} Minuten losfahren.`);
    if (congestion.factor > 1.2) parts.push(`Grund: ${congestion.reason} auf der Strecke.`);
    parts.push(`Ich habe die schnellste Route (${Math.round(durationS / 60)} Min.) vorbereitet.`);
    if (bestParking) parts.push(`Parkplatz „${bestParking.name}" in der Nähe gefunden (Wahrscheinlichkeit frei ~ ${Math.round(bestParking.probability * 100)} %).`);

    return {
      message: parts.join(' '),
      leaveInMinutes: leaveInMin,
      etaMinutes: Math.round(durationS / 60),
      congestion,
      parking: bestParking ?? null,
      route: { distance: route.distance, geometry: route.geometry },
    };
  });

  // Tagesausflug planen
  app.post('/v1/trip/plan', async (req) => {
    const body = z
      .object({
        waypoints: z.array(lonLat).min(2),
        mode: z.enum(['auto', 'bicycle']).default('auto'),
        durationHours: z.number().optional(),
        budget: z.enum(['low', 'medium', 'high']).optional(),
        interests: z.array(z.string()).optional(),
      })
      .parse(req.body);
    return planDayTrip({ ...body, waypoints: body.waypoints as LonLat[] });
  });

  // Verkehrsvorhersage entlang der Route
  app.post('/v1/predict/traffic', async (req) => {
    const body = z.object({ departAt: z.string().datetime().optional(), durationS: z.number().default(3600) }).parse(req.body);
    const depart = body.departAt ? new Date(body.departAt) : new Date();
    return { segments: predictAlongRoute(depart, body.durationS) };
  });

  // Parkplatz-Wahrscheinlichkeit
  app.get('/v1/parking', async (req) => {
    const q = z.object({ lon: z.coerce.number(), lat: z.coerce.number(), radius: z.coerce.number().min(100).max(3000).default(800) }).parse(req.query);
    return { spots: await parkingNear([q.lon, q.lat], q.radius) };
  });
}
