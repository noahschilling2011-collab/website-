import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { authenticator } from 'otplib';
import { query, queryOne } from '../../db/pool.js';
import { config } from '../../config/index.js';
import { AppError } from '../../utils/errors.js';
import { signAccessToken, type AuthUser } from '../../middleware/auth.js';

export interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  display_name: string;
  role: 'user' | 'admin';
  totp_secret: string | null;
  totp_enabled: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

const sha256 = (v: string) => crypto.createHash('sha256').update(v).digest('hex');

async function issueTokens(user: UserRow, device?: string): Promise<TokenPair> {
  const authUser: AuthUser = { id: user.id, email: user.email, role: user.role };
  const refreshToken = jwt.sign({ sub: user.id, typ: 'refresh' }, config.jwtRefreshSecret, {
    expiresIn: config.refreshTokenTtl,
    jwtid: crypto.randomUUID(),
  });
  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device, expires_at)
     VALUES ($1, $2, $3, now() + ($4 || ' seconds')::interval)`,
    [user.id, sha256(refreshToken), device ?? null, String(config.refreshTokenTtl)],
  );
  return { accessToken: signAccessToken(authUser), refreshToken };
}

export async function register(input: {
  email: string;
  password: string;
  displayName: string;
}): Promise<{ user: Pick<UserRow, 'id' | 'email' | 'display_name' | 'role'>; tokens: TokenPair }> {
  const existing = await queryOne('SELECT id FROM users WHERE email = $1', [input.email]);
  if (existing) throw AppError.conflict('Email already registered', 'email_taken');

  const passwordHash = await bcrypt.hash(input.password, 12);
  const user = await queryOne<UserRow>(
    `INSERT INTO users (email, password_hash, display_name)
     VALUES ($1, $2, $3) RETURNING *`,
    [input.email, passwordHash, input.displayName],
  );
  if (!user) throw new AppError(500, 'internal_error', 'User creation failed');
  const tokens = await issueTokens(user);
  return { user: { id: user.id, email: user.email, display_name: user.display_name, role: user.role }, tokens };
}

export async function login(input: {
  email: string;
  password: string;
  totpCode?: string;
  device?: string;
}): Promise<{ tokens: TokenPair } | { requiresTotp: true }> {
  const user = await queryOne<UserRow>('SELECT * FROM users WHERE email = $1', [input.email]);
  if (!user || !(await bcrypt.compare(input.password, user.password_hash))) {
    throw AppError.unauthorized('Invalid credentials', 'invalid_credentials');
  }
  if (user.totp_enabled) {
    if (!input.totpCode) return { requiresTotp: true };
    if (!user.totp_secret || !authenticator.check(input.totpCode, user.totp_secret)) {
      throw AppError.unauthorized('Invalid 2FA code', 'totp_invalid');
    }
  }
  return { tokens: await issueTokens(user, input.device) };
}

export async function refresh(refreshToken: string): Promise<TokenPair> {
  let payload: jwt.JwtPayload;
  try {
    payload = jwt.verify(refreshToken, config.jwtRefreshSecret) as jwt.JwtPayload;
  } catch {
    throw AppError.unauthorized('Invalid refresh token', 'refresh_invalid');
  }
  const stored = await queryOne<{ id: string }>(
    `SELECT id FROM refresh_tokens
     WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`,
    [sha256(refreshToken)],
  );
  if (!stored) throw AppError.unauthorized('Refresh token revoked', 'refresh_revoked');

  // Rotation: old token becomes unusable the moment a new pair is issued.
  await query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [stored.id]);
  const user = await queryOne<UserRow>('SELECT * FROM users WHERE id = $1', [String(payload.sub)]);
  if (!user) throw AppError.unauthorized();
  return issueTokens(user);
}

export async function logout(refreshToken: string): Promise<void> {
  await query('UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1', [sha256(refreshToken)]);
}

/** Step 1 of 2FA enrollment: create a secret; client confirms with a code in enableTotp. */
export async function setupTotp(userId: string): Promise<{ secret: string; otpauthUrl: string }> {
  const user = await queryOne<UserRow>('SELECT * FROM users WHERE id = $1', [userId]);
  if (!user) throw AppError.notFound('User not found');
  const secret = authenticator.generateSecret();
  await query('UPDATE users SET totp_secret = $1, totp_enabled = FALSE WHERE id = $2', [secret, userId]);
  return { secret, otpauthUrl: authenticator.keyuri(user.email, 'Nexus AI', secret) };
}

export async function enableTotp(userId: string, code: string): Promise<void> {
  const user = await queryOne<UserRow>('SELECT * FROM users WHERE id = $1', [userId]);
  if (!user?.totp_secret) throw AppError.badRequest('TOTP setup not started', 'totp_not_setup');
  if (!authenticator.check(code, user.totp_secret)) {
    throw AppError.unauthorized('Invalid 2FA code', 'totp_invalid');
  }
  await query('UPDATE users SET totp_enabled = TRUE WHERE id = $1', [userId]);
}
