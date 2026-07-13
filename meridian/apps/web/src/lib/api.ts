// Dünner Client für das Meridian-Gateway.
export type LonLat = [number, number];

export interface Place {
  id: string;
  name: string;
  address?: string;
  center: LonLat;
}

export interface Route {
  id: string;
  distance: number;
  duration: number;
  eta?: string;
  geometry: string;
  legs: { maneuvers: { instruction: string; distance: number }[] }[];
  warnings: string[];
  score?: { total: number };
}

export interface RouteResponse {
  routes: Route[];
  recommended: number;
  explanation?: string;
  weather?: { time: string; tempC: number; precipMm: number; risk: string }[];
  pois?: Record<string, Place[]>;
}

const BASE = import.meta.env.VITE_API_BASE ?? '';

async function json<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(BASE + url, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) },
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json() as Promise<T>;
}

export function search(q: string, near?: LonLat): Promise<{ results: Place[] }> {
  const params = new URLSearchParams({ q });
  if (near) params.set('near', `${near[0]},${near[1]}`);
  return json(`/v1/search?${params}`);
}

export function route(body: {
  mode: string;
  waypoints: LonLat[];
  preference: string;
  alternatives?: number;
  include?: string[];
  avoid?: string[];
}): Promise<RouteResponse> {
  return json('/v1/route', { method: 'POST', body: JSON.stringify(body) });
}

// --- Assistent ---
export interface AssistantAction {
  type: 'navigate' | 'search' | 'add_stop' | 'set_pref' | 'ui' | 'plan_trip' | 'briefing' | 'report' | 'none';
  place?: Place;
  destinationQuery?: string;
  category?: string;
  alongRoute?: boolean;
  cheapest?: boolean;
  avoid?: string[];
  mode?: string;
  preference?: string;
  ui?: { view?: 'streets' | 'satellite'; threeD?: boolean; streetView?: boolean };
  reportKind?: string;
}
export interface AssistantResult {
  reply: string;
  action: AssistantAction;
}
export interface AssistantContext {
  near?: LonLat;
  from?: Place;
  to?: Place;
  hasRoute?: boolean;
}

export function assistantCommand(text: string, context?: AssistantContext): Promise<AssistantResult> {
  return json('/v1/assistant/command', { method: 'POST', body: JSON.stringify({ text, context }) });
}

export interface TripItem {
  kind: string;
  title: string;
  etaMinutes: number;
  note?: string;
}
export interface TripPlan {
  summary: { distanceKm: number; drivingMinutes: number; stops: number };
  items: TripItem[];
}
export function planTrip(waypoints: LonLat[], budget?: string): Promise<TripPlan> {
  return json('/v1/trip/plan', { method: 'POST', body: JSON.stringify({ waypoints, budget }) });
}

export interface Briefing {
  message: string;
  leaveInMinutes: number | null;
  etaMinutes: number;
}
export function briefing(from: Place, to: Place, arriveBy?: string): Promise<Briefing> {
  return json('/v1/assistant/briefing', { method: 'POST', body: JSON.stringify({ from, to, arriveBy }) });
}
