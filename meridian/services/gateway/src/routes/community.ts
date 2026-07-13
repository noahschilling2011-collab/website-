import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { submitReport, reportsInBBox, type ReportKind } from '../services/reports.js';

const lonLat = z.tuple([z.number(), z.number()]);
const kind = z.enum(['accident', 'animal', 'closure', 'roadworks', 'jam', 'hazard']);

export async function communityRoutes(app: FastifyInstance): Promise<void> {
  // Gefahr melden (per App oder Sprachassistent)
  app.post('/v1/reports', async (req) => {
    const body = z
      .object({ kind, at: lonLat, note: z.string().max(280).optional(), reporterId: z.string().optional() })
      .parse(req.body);
    const report = submitReport({ kind: body.kind as ReportKind, at: body.at, note: body.note, reporterId: body.reporterId });
    return {
      report,
      accepted: report.credibility >= 0.4,
      message:
        report.status === 'confirmed'
          ? 'Meldung bestätigt und wird geteilt.'
          : `Meldung erfasst (Glaubwürdigkeit ${Math.round(report.credibility * 100)} %). Wird bei Bestätigung geteilt.`,
    };
  });

  // Aktive, glaubwürdige Meldungen als Live-Layer
  app.get('/v1/reports', async (req) => {
    const q = z
      .object({ bbox: z.string(), minCredibility: z.coerce.number().min(0).max(1).default(0.4) })
      .parse(req.query);
    const parts = q.bbox.split(',').map(Number);
    if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) {
      const err = new Error('bbox muss minLon,minLat,maxLon,maxLat sein');
      (err as { statusCode?: number }).statusCode = 400;
      throw err;
    }
    return { reports: reportsInBBox(parts as [number, number, number, number], q.minCredibility) };
  });
}
