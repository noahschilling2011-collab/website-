// Prädiktiver Verkehr + Parkplatz-Wahrscheinlichkeit (Heuristik + ML-Interface).
// Die Heuristiken liefern sofort sinnvolle Werte; das Interface bleibt stabil,
// wenn später ein ML-Modell (TimescaleDB-Historie -> GBDT/TFT) angebunden wird.
import type { LonLat, Place } from '@meridian/shared';
import { poisAlong } from './poi.js';
import { encodePolyline } from '../lib/geo.js';

export type Congestion = 'free' | 'light' | 'moderate' | 'heavy';

// Tages-/Wochenmuster: Rush-Hour werktags morgens/abends.
export function predictCongestion(at: Date, urban = true): { level: Congestion; factor: number; reason: string } {
  const day = at.getUTCDay(); // 0=So
  const hour = at.getUTCHours();
  const weekday = day >= 1 && day <= 5;
  let factor = 1.0;
  let reason = 'ruhige Zeit';
  if (weekday && (hour === 7 || hour === 8 || hour === 17 || hour === 18)) {
    factor = urban ? 1.8 : 1.4;
    reason = 'Berufsverkehr (Stoßzeit)';
  } else if (weekday && (hour === 9 || hour === 16 || hour === 19)) {
    factor = 1.3;
    reason = 'erhöhtes Verkehrsaufkommen';
  } else if (day === 0 && hour >= 16) {
    factor = 1.25;
    reason = 'Sonntag-Rückreiseverkehr';
  }
  const level: Congestion = factor >= 1.6 ? 'heavy' : factor >= 1.3 ? 'moderate' : factor > 1.05 ? 'light' : 'free';
  return { level, factor, reason };
}

// „Staus, bevor sie entstehen": Vorhersage entlang der Route für die
// voraussichtliche Ankunftszeit je Abschnitt.
export function predictAlongRoute(departAt: Date, durationS: number): { at: string; level: Congestion; reason: string }[] {
  const out: { at: string; level: Congestion; reason: string }[] = [];
  const steps = 4;
  for (let i = 1; i <= steps; i++) {
    const when = new Date(departAt.getTime() + (durationS * 1000 * i) / steps);
    const p = predictCongestion(when);
    out.push({ at: when.toISOString(), level: p.level, reason: p.reason });
  }
  return out;
}

export interface ParkingSpot extends Place {
  probability: number; // 0..1: frei zu finden
  capacity?: number;
}

// Parkplatz-Wahrscheinlichkeit: OSM-Parkplätze + Belegungs-Heuristik.
export async function parkingNear(at: LonLat, radiusM = 800, when = new Date()): Promise<ParkingSpot[]> {
  // poisAlong erwartet eine Polyline; für einen Punkt eine Mini-Linie bauen.
  const line = encodePolyline([at, [at[0] + 0.0005, at[1] + 0.0005]]);
  const spots = await poisAlong(line, 'parking', radiusM, 2);
  const occ = occupancyFactor(when);
  return spots.map((s, i) => {
    // Näher am Zentrum (früher in der Liste) = voller; Rand = wahrscheinlicher frei.
    const distanceFactor = Math.min(1, 0.5 + i * 0.05);
    const probability = Math.max(0.05, Math.min(0.98, distanceFactor * (1 - occ)));
    return { ...s, probability: +probability.toFixed(2) };
  }).sort((a, b) => b.probability - a.probability);
}

function occupancyFactor(when: Date): number {
  const day = when.getUTCDay();
  const hour = when.getUTCHours();
  const weekday = day >= 1 && day <= 5;
  if (weekday && hour >= 9 && hour <= 17) return 0.75; // Bürozeit: voll
  if (!weekday && hour >= 11 && hour <= 18) return 0.65; // Wochenend-Shopping
  if (hour >= 20 || hour <= 6) return 0.2; // nachts: frei
  return 0.45;
}
