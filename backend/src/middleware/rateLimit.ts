import type { NextFunction, Request, Response } from 'express';
import { redis } from '../db/redis.js';
import { AppError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

/**
 * Sliding-window rate limiter backed by Redis (fixed window per key).
 * Fails open if Redis is unavailable so the API keeps serving traffic.
 */
export function rateLimit(opts: { windowSec: number; max: number; keyPrefix: string }) {
  return async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
    const identity = req.user?.id ?? req.ip ?? 'anon';
    const key = `rl:${opts.keyPrefix}:${identity}`;
    try {
      const count = await redis.incr(key);
      if (count === 1) await redis.expire(key, opts.windowSec);
      if (count > opts.max) return next(AppError.tooMany());
      next();
    } catch (err) {
      logger.warn({ err: (err as Error).message }, 'Rate limiter unavailable, failing open');
      next();
    }
  };
}
