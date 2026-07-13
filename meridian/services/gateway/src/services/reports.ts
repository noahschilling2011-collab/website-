// Gemeinschaft: Gefahrenmeldungen + KI-Glaubwürdigkeitsprüfung.
// v1: In-Memory-Store (prozesslokal). Produktion: PostGIS-Tabelle `incidents`
// (siehe db/migrations/002_features.sql) + Redis-Pub/Sub für Live-Verteilung.
import type { LonLat } from '@meridian/shared';
import { haversine } from '../lib/geo.js';

export type ReportKind = 'accident' | 'animal' | 'closure' | 'roadworks' | 'jam' | 'hazard';

export interface Report {
  id: string;
  kind: ReportKind;
  at: LonLat;
  note?: string;
  createdAt: number; // epoch ms
  reporterId?: string;
  credibility: number; // 0..1
  status: 'pending' | 'confirmed' | 'expired';
  confirmations: number;
}

const TTL_MS: Record<ReportKind, number> = {
  accident: 60 * 60 * 1000, animal: 30 * 60 * 1000, closure: 6 * 60 * 60 * 1000,
  roadworks: 24 * 60 * 60 * 1000, jam: 45 * 60 * 1000, hazard: 60 * 60 * 1000,
};

const store: Report[] = [];
let seq = 0;

// Reputationsgewicht je Melder (vereinfachte On-Device-/Server-Reputation).
const reputation = new Map<string, number>();

function now(createdAt?: number): number {
  return createdAt ?? Date.parse(new Date().toISOString());
}

// Glaubwürdigkeit: Korroboration (nahe, gleichartige, junge Meldungen) +
// Melder-Reputation + Basis je Art. Ergebnis 0..1.
export function scoreCredibility(kind: ReportKind, at: LonLat, reporterId: string | undefined, ts: number): { credibility: number; confirmations: number } {
  const base = kind === 'roadworks' || kind === 'closure' ? 0.55 : 0.4;
  const corroborators = store.filter(
    (r) => r.kind === kind && r.status !== 'expired' && ts - r.createdAt < TTL_MS[kind] && haversine(r.at, at) < 150,
  );
  const rep = reporterId ? reputation.get(reporterId) ?? 0.5 : 0.4;
  const corroBoost = Math.min(0.4, corroborators.length * 0.15);
  const credibility = Math.max(0, Math.min(1, base * 0.6 + rep * 0.4 + corroBoost));
  return { credibility, confirmations: corroborators.length };
}

export function submitReport(input: { kind: ReportKind; at: LonLat; note?: string; reporterId?: string; ts?: number }): Report {
  const ts = now(input.ts);
  const { credibility, confirmations } = scoreCredibility(input.kind, input.at, input.reporterId, ts);

  // Nahe Duplikat-Meldung? Dann bestehende bestätigen statt neu anlegen.
  const existing = store.find((r) => r.kind === input.kind && r.status !== 'expired' && ts - r.createdAt < TTL_MS[input.kind] && haversine(r.at, input.at) < 80);
  if (existing) {
    existing.confirmations += 1;
    existing.credibility = Math.min(1, existing.credibility + 0.15);
    if (existing.credibility >= 0.7) existing.status = 'confirmed';
    if (input.reporterId) reputation.set(input.reporterId, Math.min(1, (reputation.get(input.reporterId) ?? 0.5) + 0.02));
    return existing;
  }

  const report: Report = {
    id: `rep-${++seq}`,
    kind: input.kind,
    at: input.at,
    note: input.note,
    createdAt: ts,
    reporterId: input.reporterId,
    credibility,
    confirmations,
    status: credibility >= 0.7 ? 'confirmed' : 'pending',
  };
  store.push(report);
  return report;
}

// Aktive, glaubwürdige Meldungen in einer Bounding-Box (minLon,minLat,maxLon,maxLat).
export function reportsInBBox(bbox: [number, number, number, number], minCredibility = 0.4, ts?: number): Report[] {
  const t = now(ts);
  const [minLon, minLat, maxLon, maxLat] = bbox;
  return store
    .filter((r) => {
      if (t - r.createdAt > TTL_MS[r.kind]) {
        r.status = 'expired';
        return false;
      }
      return r.credibility >= minCredibility && r.at[0] >= minLon && r.at[0] <= maxLon && r.at[1] >= minLat && r.at[1] <= maxLat;
    })
    .sort((a, b) => b.credibility - a.credibility);
}
