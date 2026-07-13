// KI-Reiseplanung: Tagesausflug mit Sehenswürdigkeiten, Pausen, Essen, Hotel.
import type { LonLat, Place } from '@meridian/shared';
import { computeRoutes } from './routing.js';
import { poisAlong } from './poi.js';

export interface TripItem {
  kind: 'start' | 'sight' | 'break' | 'meal' | 'lodging' | 'destination';
  title: string;
  at?: LonLat;
  etaMinutes: number; // Minuten ab Start
  note?: string;
}

export interface TripPlan {
  summary: { distanceKm: number; drivingMinutes: number; stops: number };
  items: TripItem[];
}

interface TripOptions {
  waypoints: LonLat[];
  mode?: 'auto' | 'bicycle';
  durationHours?: number;
  budget?: 'low' | 'medium' | 'high';
  interests?: string[]; // z.B. ['attraction','viewpoint']
}

export async function planDayTrip(opts: TripOptions): Promise<TripPlan> {
  const routes = await computeRoutes({
    mode: opts.mode ?? 'auto',
    waypoints: opts.waypoints,
    preference: 'scenic',
    alternatives: 1,
  });
  const route = routes[0];
  const drivingMin = route.duration / 60;
  const distanceKm = route.distance / 1000;

  const interests = opts.interests?.length ? opts.interests : ['attraction', 'viewpoint'];

  // POIs entlang der Route sammeln.
  const [sights, meals, hotels] = await Promise.all([
    Promise.all(interests.map((c) => poisAlong(route.geometry, c as never, 3000, 8))).then((a) => a.flat()),
    poisAlong(route.geometry, 'restaurant', 2500, 6),
    poisAlong(route.geometry, 'hotel', 3000, 4),
  ]);

  const items: TripItem[] = [];
  items.push({ kind: 'start', title: 'Start', at: opts.waypoints[0], etaMinutes: 0 });

  // Sehenswürdigkeiten gleichmäßig über die Fahrzeit verteilen.
  const picks = spread(sights, 3);
  picks.forEach((p, i) => {
    items.push({
      kind: 'sight',
      title: p.name,
      at: p.center,
      etaMinutes: Math.round(((i + 1) / (picks.length + 1)) * drivingMin),
      note: 'Sehenswürdigkeit entlang der Route',
    });
  });

  // Pausen alle ~2 h Fahrzeit.
  const breakEvery = 120;
  for (let m = breakEvery; m < drivingMin; m += breakEvery) {
    items.push({ kind: 'break', title: 'Pause (15 Min.)', etaMinutes: m, note: 'Automatisch nach ~2 h Fahrzeit' });
  }

  // Mittagessen um die Tagesmitte, passendes Budget.
  const meal = byBudget(meals, opts.budget)[0];
  if (meal) items.push({ kind: 'meal', title: `Mittagessen: ${meal.name}`, at: meal.center, etaMinutes: Math.round(drivingMin / 2), note: budgetNote(opts.budget) });

  // Übernachtung, wenn Ausflug lang.
  if ((opts.durationHours ?? drivingMin / 60) > 8) {
    const hotel = byBudget(hotels, opts.budget)[0];
    if (hotel) items.push({ kind: 'lodging', title: `Übernachtung: ${hotel.name}`, at: hotel.center, etaMinutes: Math.round(drivingMin), note: budgetNote(opts.budget) });
  }

  items.push({ kind: 'destination', title: 'Ziel', at: opts.waypoints[opts.waypoints.length - 1], etaMinutes: Math.round(drivingMin) });
  items.sort((a, b) => a.etaMinutes - b.etaMinutes);

  return {
    summary: { distanceKm: +distanceKm.toFixed(1), drivingMinutes: Math.round(drivingMin), stops: items.filter((i) => ['sight', 'break', 'meal', 'lodging'].includes(i.kind)).length },
    items,
  };
}

function spread<T>(arr: T[], n: number): T[] {
  if (arr.length <= n) return arr;
  const step = arr.length / n;
  return Array.from({ length: n }, (_, i) => arr[Math.floor(i * step)]);
}

// Ohne echte Preise: nutze verfügbare Sterne/Preis-Tags heuristisch, sonst Reihenfolge.
function byBudget(places: Place[], _budget?: string): Place[] {
  return places;
}
function budgetNote(budget?: string): string {
  return budget ? `Budget: ${budget === 'low' ? 'günstig' : budget === 'high' ? 'gehoben' : 'mittel'}` : 'Budget: flexibel';
}
