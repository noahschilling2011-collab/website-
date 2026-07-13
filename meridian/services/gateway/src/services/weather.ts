// Wetter entlang der Route: Open-Meteo je Sample-Punkt zur Ankunftszeit.
import type { LonLat, WeatherSample } from '@meridian/shared';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';
import { decodePolyline, sampleAlong, pathLength } from '../lib/geo.js';

interface MeteoResponse {
  hourly?: { time: string[]; temperature_2m: number[]; precipitation: number[]; wind_speed_10m: number[]; weather_code: number[] };
}

function riskFrom(precip: number, wind: number, code: number): WeatherSample['risk'] {
  if (precip > 4 || wind > 55 || [95, 96, 99, 75, 82].includes(code)) return 'high';
  if (precip > 1 || wind > 30 || [61, 63, 71, 73, 45, 48].includes(code)) return 'moderate';
  return 'low';
}

// polyline = encoded (precision 6); departAt ISO; segments = Anzahl Stützpunkte.
export async function weatherAlong(
  polyline: string,
  departAt: string | undefined,
  totalDurationS: number,
  segments = 6,
): Promise<WeatherSample[]> {
  const pts = decodePolyline(polyline);
  if (pts.length === 0) return [];
  const samples = sampleAlong(pts, segments);
  const total = pathLength(pts) || 1;
  const start = departAt ? new Date(departAt) : new Date();

  const results = await Promise.all(
    samples.map(async (s) => {
      const frac = s.dist / total;
      const when = new Date(start.getTime() + frac * totalDurationS * 1000);
      return sampleWeather(s.at, when);
    }),
  );
  return results;
}

async function sampleWeather(at: LonLat, when: Date): Promise<WeatherSample> {
  try {
    const res = await fetchJson<MeteoResponse>('open-meteo', config.upstreams.openMeteo, {
      query: {
        longitude: at[0].toFixed(4),
        latitude: at[1].toFixed(4),
        hourly: 'temperature_2m,precipitation,wind_speed_10m,weather_code',
        forecast_days: 2,
        timezone: 'UTC',
      },
    });
    const h = res.hourly;
    if (!h) throw new Error('no hourly');
    // nächstliegende Stunde finden
    const targetHour = when.toISOString().slice(0, 13);
    let idx = h.time.findIndex((t) => t.slice(0, 13) === targetHour);
    if (idx < 0) idx = 0;
    return {
      at,
      time: when.toISOString(),
      tempC: h.temperature_2m[idx],
      precipMm: h.precipitation[idx],
      windKmh: h.wind_speed_10m[idx],
      code: h.weather_code[idx],
      risk: riskFrom(h.precipitation[idx], h.wind_speed_10m[idx], h.weather_code[idx]),
    };
  } catch {
    return { at, time: when.toISOString(), tempC: NaN, precipMm: 0, windKmh: 0, code: 0, risk: 'low' };
  }
}
