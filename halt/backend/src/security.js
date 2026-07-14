// Publish-readiness hardening: security headers, a strict-but-app-friendly CSP,
// a small in-memory rate limiter, and an origin-checked CORS policy.

// The web app is a single inline-styled/-scripted file, so the CSP must allow
// inline style+script — but nothing external, and no framing.
const CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "connect-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join('; ');

export function securityHeaders(_req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  res.setHeader('Content-Security-Policy', CSP);
  res.setHeader('Strict-Transport-Security', 'max-age=15552000; includeSubDomains');
  next();
}

/**
 * CORS: the app is normally served same-origin (no CORS needed). Allow cross-origin
 * only for explicitly configured origins. Setting CORS_ORIGINS="*" opts into the
 * old permissive behaviour (handy for local file:// testing, not for publish).
 */
export function cors(allowed) {
  const any = allowed.includes('*');
  const set = new Set(allowed);
  return (req, res, next) => {
    const origin = req.headers.origin;
    if (origin && (any || set.has(origin))) {
      res.setHeader('Access-Control-Allow-Origin', any ? '*' : origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,OPTIONS');
    }
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    next();
  };
}

/** Fixed-window in-memory limiter. Keyed by client IP, or a custom key function
 *  (e.g. the authenticated userId for outbound-message limits). */
export function rateLimit({ windowMs, max, message, key }) {
  const hits = new Map();
  return (req, res, next) => {
    const now = Date.now();
    const id = (key ? key(req) : null) || req.ip || req.socket?.remoteAddress || 'unknown';
    let rec = hits.get(id);
    if (!rec || now > rec.reset) {
      rec = { count: 0, reset: now + windowMs };
      hits.set(id, rec);
    }
    rec.count += 1;
    if (rec.count > max) {
      res.setHeader('Retry-After', String(Math.ceil((rec.reset - now) / 1000)));
      return res.status(429).json({ error: message || 'Zu viele Anfragen. Bitte später erneut.' });
    }
    next();
  };
}
