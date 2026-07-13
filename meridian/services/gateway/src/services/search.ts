// Geocoding-Adapter: Photon (Autocomplete) / Nominatim; Fallback = Demo-Orte.
import type { LonLat, Place } from '@meridian/shared';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';

interface PhotonFeature {
  geometry: { coordinates: [number, number] };
  properties: {
    osm_id?: number;
    name?: string;
    street?: string;
    housenumber?: string;
    city?: string;
    country?: string;
    osm_key?: string;
  };
}
interface PhotonResponse {
  features: PhotonFeature[];
}

const DEMO: Place[] = [
  { id: 'demo-1', name: 'Brandenburger Tor', address: 'Pariser Platz, Berlin', center: [13.3777, 52.5163] },
  { id: 'demo-2', name: 'Marienplatz', address: 'München', center: [11.5755, 48.1374] },
  { id: 'demo-3', name: 'Kölner Dom', address: 'Köln', center: [6.9583, 50.9413] },
  { id: 'demo-4', name: 'Elbphilharmonie', address: 'Hamburg', center: [9.9841, 53.5413] },
  { id: 'demo-5', name: 'Zwinger', address: 'Dresden', center: [13.7333, 51.0533] },
];

export async function search(q: string, near?: LonLat, limit = 8): Promise<Place[]> {
  if (config.upstreams.photon) {
    try {
      const res = await fetchJson<PhotonResponse>('photon', `${config.upstreams.photon}/api`, {
        query: {
          q,
          limit,
          lang: 'de',
          lon: near?.[0],
          lat: near?.[1],
        },
      });
      return res.features.map(featureToPlace);
    } catch {
      // Fallback
    }
  }
  const needle = q.toLowerCase();
  return DEMO.filter((p) => p.name.toLowerCase().includes(needle) || needle.length < 2).slice(0, limit);
}

export async function reverse(lon: number, lat: number): Promise<Place | null> {
  if (config.upstreams.photon) {
    try {
      const res = await fetchJson<PhotonResponse>('photon', `${config.upstreams.photon}/reverse`, {
        query: { lon, lat, lang: 'de' },
      });
      const f = res.features[0];
      return f ? featureToPlace(f) : null;
    } catch {
      // Fallback
    }
  }
  return { id: 'rev', name: `Ort bei ${lat.toFixed(4)}, ${lon.toFixed(4)}`, center: [lon, lat] };
}

function featureToPlace(f: PhotonFeature): Place {
  const p = f.properties;
  const addressParts = [p.street, p.housenumber, p.city, p.country].filter(Boolean);
  return {
    id: String(p.osm_id ?? Math.random()),
    name: p.name ?? addressParts[0] ?? 'Unbenannt',
    address: addressParts.join(' '),
    category: p.osm_key,
    center: f.geometry.coordinates,
  };
}
