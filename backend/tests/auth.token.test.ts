import { describe, expect, it } from 'vitest';
import { signAccessToken, verifyAccessToken } from '../src/middleware/auth.js';

describe('access tokens', () => {
  it('round-trips user identity', () => {
    const user = { id: '11111111-1111-1111-1111-111111111111', email: 'a@b.de', role: 'user' as const };
    const token = signAccessToken(user);
    expect(verifyAccessToken(token)).toEqual(user);
  });

  it('rejects tampered tokens', () => {
    const token = signAccessToken({ id: 'x', email: 'a@b.de', role: 'user' });
    expect(() => verifyAccessToken(token.slice(0, -2) + 'zz')).toThrow();
  });
});
