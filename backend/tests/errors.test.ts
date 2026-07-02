import { describe, expect, it } from 'vitest';
import { AppError } from '../src/utils/errors.js';

describe('AppError', () => {
  it('carries status and code', () => {
    const err = AppError.notFound('Nope');
    expect(err.status).toBe(404);
    expect(err.code).toBe('not_found');
    expect(err.message).toBe('Nope');
  });

  it('factories map to correct HTTP status', () => {
    expect(AppError.badRequest('x').status).toBe(400);
    expect(AppError.unauthorized().status).toBe(401);
    expect(AppError.forbidden().status).toBe(403);
    expect(AppError.conflict('x').status).toBe(409);
    expect(AppError.tooMany().status).toBe(429);
  });
});
