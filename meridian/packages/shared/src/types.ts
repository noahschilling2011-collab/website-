// Geteilte Typen für Gateway & Clients.

export type LonLat = [number, number]; // [lon, lat] (GeoJSON-Konvention)

export type TravelMode = 'auto' | 'bicycle' | 'pedestrian' | 'transit';
export type RoutePreference = 'fastest' | 'comfortable' | 'eco' | 'scenic';
export type PoiCategory = 'fuel' | 'charging' | 'restaurant' | 'hotel' | 'parking';

export interface Place {
  id: string;
  name: string;
  address?: string;
  category?: string;
  center: LonLat;
  bbox?: [number, number, number, number];
}

export interface Maneuver {
  instruction: string;
  type: number;
  distance: number; // Meter
  duration: number; // Sekunden
  location: LonLat;
}

export interface RouteLeg {
  distance: number;
  duration: number;
  maneuvers: Maneuver[];
}

export interface RouteScore {
  total: number;
  time: number;
  traffic: number;
  complexity: number;
  comfort: number;
  weatherRisk: number;
  scenic: number;
}

export interface Route {
  id: string;
  mode: TravelMode;
  preference: RoutePreference;
  distance: number; // Meter
  duration: number; // Sekunden (mit Verkehr)
  freeDuration?: number; // ohne Verkehr
  eta?: string; // ISO
  geometry: string; // encoded polyline (precision 6)
  legs: RouteLeg[];
  warnings: string[];
  score?: RouteScore;
}

export interface RouteRequest {
  mode: TravelMode;
  waypoints: LonLat[];
  preference?: RoutePreference;
  departAt?: string;
  alternatives?: number;
  include?: string[]; // z.B. ["weather","traffic","poi:fuel"]
}

export interface WeatherSample {
  at: LonLat;
  time: string;
  tempC: number;
  precipMm: number;
  windKmh: number;
  code: number; // WMO weather code
  risk: 'low' | 'moderate' | 'high';
}

export interface RouteResponse {
  routes: Route[];
  recommended: number;
  explanation?: string;
  weather?: WeatherSample[];
  pois?: Record<string, Place[]>;
}

export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail?: string;
  instance?: string;
}
