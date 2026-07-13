// Routing-Adapter: bevorzugt Valhalla; ohne Valhalla -> Luftlinien-Fallback.
import type { LonLat, Route, RouteLeg, TravelMode, RoutePreference } from '@meridian/shared';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';
import { encodePolyline, pathLength } from '../lib/geo.js';

const COSTING: Record<TravelMode, string> = {
  auto: 'auto',
  bicycle: 'bicycle',
  pedestrian: 'pedestrian',
  transit: 'multimodal',
};

// Grobe Reisegeschwindigkeiten (km/h) für den Fallback ohne echte Engine.
const FALLBACK_KMH: Record<TravelMode, number> = {
  auto: 60,
  bicycle: 16,
  pedestrian: 5,
  transit: 30,
};

interface ValhallaManeuver {
  instruction: string;
  type: number;
  length: number; // km
  time: number; // s
  begin_shape_index: number;
}
interface ValhallaLeg {
  shape: string;
  summary: { length: number; time: number };
  maneuvers: ValhallaManeuver[];
}
interface ValhallaResponse {
  trip: { legs: ValhallaLeg[]; summary: { length: number; time: number } };
  alternates?: { trip: ValhallaResponse['trip'] }[];
}

export interface RouteOptions {
  mode: TravelMode;
  waypoints: LonLat[];
  preference: RoutePreference;
  alternatives: number;
  avoid?: string[]; // z.B. ['motorway'] für „ohne Autobahn"
}

export async function computeRoutes(opts: RouteOptions): Promise<Route[]> {
  if (config.upstreams.valhalla) {
    try {
      return await viaValhalla(opts);
    } catch {
      // fällt auf Luftlinie zurück
    }
  }
  return [fallbackRoute(opts, 0)];
}

async function viaValhalla(opts: RouteOptions): Promise<Route[]> {
  const costing = COSTING[opts.mode];
  const body: Record<string, unknown> = {
    locations: opts.waypoints.map(([lon, lat]) => ({ lon, lat })),
    costing,
    alternates: Math.max(0, opts.alternatives - 1),
    directions_options: { units: 'kilometers', language: 'de-DE' },
  };
  // „ohne Autobahn": Autobahnnutzung im Kostenmodell abwerten.
  if (opts.avoid?.includes('motorway') && (costing === 'auto' || costing === 'bicycle')) {
    body.costing_options = { [costing]: { use_highways: 0 } };
  }
  const res = await fetchJson<ValhallaResponse>(
    'valhalla',
    `${config.upstreams.valhalla}/route`,
    { method: 'POST', body },
  );
  const trips = [res, ...(res.alternates ?? []).map((a) => ({ trip: a.trip }) as ValhallaResponse)];
  return trips.map((t, i) => valhallaToRoute(t, opts, i));
}

function valhallaToRoute(res: ValhallaResponse, opts: RouteOptions, idx: number): Route {
  const legs: RouteLeg[] = res.trip.legs.map((leg) => ({
    distance: leg.summary.length * 1000,
    duration: leg.summary.time,
    maneuvers: leg.maneuvers.map((m) => ({
      instruction: m.instruction,
      type: m.type,
      distance: m.length * 1000,
      duration: m.time,
      location: [0, 0], // aus shape ableitbar; für v1 vernachlässigt
    })),
  }));
  // Valhalla-Shapes je Leg zu einer Polyline zusammenfassen (bereits precision 6).
  const geometry = res.trip.legs.map((l) => l.shape).join('');
  return {
    id: `r${idx}`,
    mode: opts.mode,
    preference: opts.preference,
    distance: res.trip.summary.length * 1000,
    duration: res.trip.summary.time,
    freeDuration: res.trip.summary.time,
    geometry,
    legs,
    warnings: [],
  };
}

function fallbackRoute(opts: RouteOptions, idx: number): Route {
  const dist = pathLength(opts.waypoints);
  const kmh = FALLBACK_KMH[opts.mode];
  const duration = (dist / 1000 / kmh) * 3600;
  const legs: RouteLeg[] = [
    {
      distance: dist,
      duration,
      maneuvers: [
        {
          instruction: 'Der Route folgen (Luftlinien-Schätzung — Routing-Engine nicht verbunden).',
          type: 0,
          distance: dist,
          duration,
          location: opts.waypoints[0],
        },
        {
          instruction: 'Ziel erreicht.',
          type: 4,
          distance: 0,
          duration: 0,
          location: opts.waypoints[opts.waypoints.length - 1],
        },
      ],
    },
  ];
  return {
    id: `r${idx}`,
    mode: opts.mode,
    preference: opts.preference,
    distance: dist,
    duration,
    freeDuration: duration,
    geometry: encodePolyline(opts.waypoints),
    legs,
    warnings: ['Schätzung ohne Straßennetz — Valhalla nicht konfiguriert.'],
  };
}
