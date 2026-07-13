// Kleiner HTTP-Helfer (undici) mit Timeout + JSON. Wirft UpstreamError bei Fehlern.
import { request } from 'undici';
import { config } from '../config.js';

export class UpstreamError extends Error {
  constructor(public readonly service: string, message: string) {
    super(message);
    this.name = 'UpstreamError';
  }
}

interface JsonOpts {
  method?: 'GET' | 'POST';
  query?: Record<string, string | number | undefined>;
  body?: unknown;
  timeoutMs?: number;
  headers?: Record<string, string>;
}

export async function fetchJson<T>(service: string, url: string, opts: JsonOpts = {}): Promise<T> {
  const timeout = opts.timeoutMs ?? config.requestTimeoutMs;
  let full = url;
  if (opts.query) {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(opts.query)) {
      if (v !== undefined && v !== '') q.set(k, String(v));
    }
    const qs = q.toString();
    if (qs) full += (url.includes('?') ? '&' : '?') + qs;
  }

  try {
    const res = await request(full, {
      method: opts.method ?? 'GET',
      headers: {
        accept: 'application/json',
        ...(opts.body ? { 'content-type': 'application/json' } : {}),
        ...opts.headers,
      },
      body: opts.body ? JSON.stringify(opts.body) : undefined,
      headersTimeout: timeout,
      bodyTimeout: timeout,
    });
    if (res.statusCode >= 400) {
      const text = await res.body.text();
      throw new UpstreamError(service, `HTTP ${res.statusCode}: ${text.slice(0, 200)}`);
    }
    return (await res.body.json()) as T;
  } catch (err) {
    if (err instanceof UpstreamError) throw err;
    throw new UpstreamError(service, (err as Error).message);
  }
}
