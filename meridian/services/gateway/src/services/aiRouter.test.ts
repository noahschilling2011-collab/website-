import { describe, it, expect } from 'vitest';
import { scoreRoutes, pickRecommended } from './aiRouter.js';
import { encodePolyline, decodePolyline } from '../lib/geo.js';
import type { Route } from '@meridian/shared';

function mkRoute(id: string, durationS: number, distanceM: number, maneuvers: number, freeS?: number): Route {
  return {
    id,
    mode: 'auto',
    preference: 'fastest',
    distance: distanceM,
    duration: durationS,
    freeDuration: freeS ?? durationS,
    geometry: '',
    legs: [
      {
        distance: distanceM,
        duration: durationS,
        maneuvers: Array.from({ length: maneuvers }, () => ({
          instruction: 'x',
          type: 1,
          distance: 1,
          duration: 1,
          location: [0, 0] as [number, number],
        })),
      },
    ],
    warnings: [],
  };
}

describe('geo polyline', () => {
  it('kodiert und dekodiert verlustarm (precision 6)', () => {
    const pts: [number, number][] = [
      [13.3777, 52.5163],
      [11.5755, 48.1374],
    ];
    const decoded = decodePolyline(encodePolyline(pts));
    expect(decoded[0][0]).toBeCloseTo(13.3777, 5);
    expect(decoded[1][1]).toBeCloseTo(48.1374, 5);
  });
});

describe('aiRouter', () => {
  it('wählt bei "fastest" die schnellste Route', () => {
    const routes = [mkRoute('a', 1800, 30000, 10), mkRoute('b', 1500, 32000, 12)];
    scoreRoutes(routes, 'fastest');
    expect(pickRecommended(routes)).toBe(1); // b ist schneller
  });

  it('bevorzugt bei "comfortable" die manöverärmere Route trotz mehr Zeit', () => {
    const fastComplex = mkRoute('a', 1500, 30000, 40);
    const slowSimple = mkRoute('b', 1700, 30000, 6);
    const routes = [fastComplex, slowSimple];
    scoreRoutes(routes, 'comfortable');
    expect(pickRecommended(routes)).toBe(1); // b ist angenehmer
  });
});
