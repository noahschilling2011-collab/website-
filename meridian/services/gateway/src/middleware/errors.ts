// Einheitliche Fehlerbehandlung im RFC-9457-Format (Problem Details).
import type { FastifyInstance } from 'fastify';
import type { ProblemDetails } from '@meridian/shared';
import { UpstreamError } from '../lib/http.js';

export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler((err, req, reply) => {
    let status = 500;
    let type = 'https://meridian/errors/internal';
    let title = 'Interner Fehler';

    if ((err as { validation?: unknown }).validation) {
      status = 400;
      type = 'https://meridian/errors/validation';
      title = 'Ungültige Anfrage';
    } else if (err instanceof UpstreamError) {
      status = 503;
      type = 'https://meridian/errors/upstream-unavailable';
      title = `Dienst nicht verfügbar (${err.service})`;
    } else if ((err as { statusCode?: number }).statusCode) {
      status = (err as { statusCode: number }).statusCode;
      title = err.message;
    }

    if (status >= 500) req.log.error({ err }, 'request failed');

    const body: ProblemDetails = {
      type,
      title,
      status,
      detail: process.env.NODE_ENV === 'production' ? undefined : err.message,
      instance: req.url,
    };
    reply.code(status).type('application/problem+json').send(body);
  });
}
