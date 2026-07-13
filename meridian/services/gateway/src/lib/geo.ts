// Geo-Utilities: Distanz, Polyline-Kodierung (Precision 6), Sampling entlang Pfad.
import type { LonLat } from '@meridian/shared';

const R = 6371000; // Erdradius in Metern

export function haversine(a: LonLat, b: LonLat): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b[1] - a[1]);
  const dLon = toRad(b[0] - a[0]);
  const lat1 = toRad(a[1]);
  const lat2 = toRad(b[1]);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export function pathLength(points: LonLat[]): number {
  let d = 0;
  for (let i = 1; i < points.length; i++) d += haversine(points[i - 1], points[i]);
  return d;
}

// Google/Valhalla encoded polyline. precision 6 (1e6) wie bei Valhalla.
export function encodePolyline(points: LonLat[], precision = 6): string {
  const factor = 10 ** precision;
  let lastLat = 0;
  let lastLon = 0;
  let result = '';
  const enc = (v: number) => {
    v = v < 0 ? ~(v << 1) : v << 1;
    let out = '';
    while (v >= 0x20) {
      out += String.fromCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out += String.fromCharCode(v + 63);
    return out;
  };
  for (const [lon, lat] of points) {
    const la = Math.round(lat * factor);
    const lo = Math.round(lon * factor);
    result += enc(la - lastLat) + enc(lo - lastLon);
    lastLat = la;
    lastLon = lo;
  }
  return result;
}

export function decodePolyline(str: string, precision = 6): LonLat[] {
  const factor = 10 ** precision;
  let index = 0;
  let lat = 0;
  let lon = 0;
  const coords: LonLat[] = [];
  while (index < str.length) {
    let shift = 0;
    let result = 0;
    let byte: number;
    do {
      byte = str.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      byte = str.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lon += result & 1 ? ~(result >> 1) : result >> 1;
    coords.push([lon / factor, lat / factor]);
  }
  return coords;
}

// Punkte entlang eines Pfades in ~gleichen Distanzabständen (inkl. Start & Ende).
export function sampleAlong(points: LonLat[], segments: number): { at: LonLat; dist: number }[] {
  const total = pathLength(points);
  if (total === 0 || points.length < 2) {
    return [{ at: points[0] ?? [0, 0], dist: 0 }];
  }
  const step = total / segments;
  const out: { at: LonLat; dist: number }[] = [];
  let target = 0;
  let acc = 0;
  let i = 1;
  out.push({ at: points[0], dist: 0 });
  while (target <= total && out.length <= segments) {
    target += step;
    while (i < points.length && acc + haversine(points[i - 1], points[i]) < target) {
      acc += haversine(points[i - 1], points[i]);
      i++;
    }
    if (i >= points.length) break;
    const segLen = haversine(points[i - 1], points[i]);
    const t = segLen === 0 ? 0 : (target - acc) / segLen;
    const at: LonLat = [
      points[i - 1][0] + (points[i][0] - points[i - 1][0]) * t,
      points[i - 1][1] + (points[i][1] - points[i - 1][1]) * t,
    ];
    out.push({ at, dist: target });
  }
  return out;
}
