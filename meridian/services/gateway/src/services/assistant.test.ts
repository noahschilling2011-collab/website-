import { describe, it, expect } from 'vitest';
import { handleCommand } from './assistant.js';
import { submitReport, reportsInBBox } from './reports.js';
import { predictCongestion } from './predict.js';

describe('assistant intent parsing', () => {
  it('„ohne Autobahn nach Hause" -> navigate, avoid motorway, nicht transit', async () => {
    const r = await handleCommand('Bring mich ohne Autobahn nach Hause');
    expect(r.action.type).toBe('navigate');
    expect(r.action.avoid).toContain('motorway');
    expect(r.action.destinationQuery).toBe('Zuhause');
    expect(r.action.mode).not.toBe('transit'); // "autobahn" darf transit nicht auslösen
  });

  it('„günstigsten Supermarkt auf dem Weg" -> search, alongRoute, cheapest', async () => {
    const r = await handleCommand('Finde den günstigsten Supermarkt auf dem Weg', { hasRoute: true });
    expect(r.action.type).toBe('search');
    expect(r.action.category).toBe('supermarket');
    expect(r.action.alongRoute).toBe(true);
    expect(r.action.cheapest).toBe(true);
  });

  it('„Zwischenstopp zum Essen" -> add_stop restaurant', async () => {
    const r = await handleCommand('Plane einen Zwischenstopp zum Essen');
    expect(r.action.type).toBe('add_stop');
    expect(r.action.category).toBe('restaurant');
  });

  it('„Satellit in 3D" -> ui', async () => {
    const r = await handleCommand('Zeig mir die Satellitenansicht in 3D');
    expect(r.action.type).toBe('ui');
    expect(r.action.ui?.view).toBe('satellite');
    expect(r.action.ui?.threeD).toBe(true);
  });
});

describe('community credibility', () => {
  it('nahe Bestätigungen erhöhen die Glaubwürdigkeit bis „confirmed"', () => {
    const at: [number, number] = [9.99, 53.55];
    const a = submitReport({ kind: 'hazard', at, reporterId: 'u1', ts: 1_000_000 });
    const initialCred = a.credibility; // Zahl-Snapshot (submitReport mutiert die bestehende Meldung)
    expect(a.status).toBe('pending');
    // nahe Folgemeldungen werden zur selben Meldung korroboriert
    submitReport({ kind: 'hazard', at: [9.9901, 53.5501], reporterId: 'u2', ts: 1_001_000 });
    const c = submitReport({ kind: 'hazard', at: [9.9902, 53.5502], reporterId: 'u3', ts: 1_002_000 });
    expect(c.credibility).toBeGreaterThan(initialCred);
    expect(c.confirmations).toBeGreaterThanOrEqual(2);
    expect(c.status).toBe('confirmed');
    const live = reportsInBBox([9.98, 53.54, 10.0, 53.56], 0.4, 1_003_000);
    expect(live.length).toBeGreaterThan(0);
  });
});

describe('traffic prediction', () => {
  it('erkennt werktags Berufsverkehr', () => {
    const tuesday8 = new Date(Date.UTC(2026, 6, 14, 8, 0, 0)); // Di 08:00 UTC
    expect(predictCongestion(tuesday8).level === 'heavy' || predictCongestion(tuesday8).level === 'moderate').toBe(true);
  });
});
