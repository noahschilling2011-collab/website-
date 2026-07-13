// POIs entlang der Route: Overpass (OSM) + Open Charge Map (Ladesäulen).
import type { LonLat, Place, PoiCategory } from '@meridian/shared';
import { request } from 'undici';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';
import { decodePolyline, sampleAlong, haversine } from '../lib/geo.js';

const OSM_FILTER: Record<Exclude<PoiCategory, 'charging'>, string> = {
  fuel: 'node["amenity"="fuel"]',
  restaurant: 'node["amenity"="restaurant"]',
  hotel: 'node["tourism"="hotel"]',
  parking: 'node["amenity"="parking"]',
};

interface OverpassEl {
  id: number;
  lat: number;
  lon: number;
  tags?: Record<string, string>;
}
interface OverpassResponse {
  elements: OverpassEl[];
}
interface OcmPoi {
  ID: number;
  AddressInfo: { Title: string; Latitude: number; Longitude: number; AddressLine1?: string };
}

// Korridor entlang der Polyline: um jeden Sample-Punkt im Radius suchen.
export async function poisAlong(
  polyline: string,
  category: PoiCategory,
  radiusM = 2000,
  segments = 8,
): Promise<Place[]> {
  const pts = decodePolyline(polyline);
  if (pts.length === 0) return [];
  const samples = sampleAlong(pts, segments).map((s) => s.at);

  if (category === 'charging') return chargingNear(samples, radiusM);
  return overpassNear(samples, category, radiusM);
}

async function overpassNear(samples: LonLat[], category: Exclude<PoiCategory, 'charging'>, radiusM: number): Promise<Place[]> {
  const filter = OSM_FILTER[category];
  const clauses = samples.map(([lon, lat]) => `${filter}(around:${radiusM},${lat},${lon});`).join('');
  const query = `[out:json][timeout:20];(${clauses});out body ${Math.min(60, samples.length * 8)};`;
  try {
    // Overpass erwartet den Query als Formularfeld "data".
    const r = await request(config.upstreams.overpass, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ data: query }).toString(),
      headersTimeout: config.requestTimeoutMs * 3,
      bodyTimeout: config.requestTimeoutMs * 3,
    });
    const res = (await r.body.json()) as OverpassResponse;
    return dedupeByProximity(
      res.elements.map((e) => ({
        id: `osm-${e.id}`,
        name: e.tags?.name ?? category,
        address: e.tags?.['addr:street'],
        category,
        center: [e.lon, e.lat] as LonLat,
      })),
    );
  } catch {
    return [];
  }
}

async function chargingNear(samples: LonLat[], radiusM: number): Promise<Place[]> {
  const out: Place[] = [];
  for (const [lon, lat] of samples.slice(0, 5)) {
    try {
      const res = await fetchJson<OcmPoi[]>('open-charge-map', config.upstreams.openChargeMap, {
        query: {
          output: 'json',
          latitude: lat,
          longitude: lon,
          distance: (radiusM / 1000).toFixed(1),
          distanceunit: 'KM',
          maxresults: 10,
          key: config.upstreams.openChargeMapKey || undefined,
        },
      });
      for (const p of res) {
        out.push({
          id: `ocm-${p.ID}`,
          name: p.AddressInfo.Title,
          address: p.AddressInfo.AddressLine1,
          category: 'charging',
          center: [p.AddressInfo.Longitude, p.AddressInfo.Latitude],
        });
      }
    } catch {
      // weiter
    }
  }
  return dedupeByProximity(out);
}

// Entfernt Duplikate, die < 30 m auseinander liegen.
function dedupeByProximity(places: Place[]): Place[] {
  const kept: Place[] = [];
  for (const p of places) {
    if (!kept.some((k) => haversine(k.center, p.center) < 30)) kept.push(p);
  }
  return kept.slice(0, 50);
}
