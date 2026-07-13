// Konto- & Sicherheitslogik. v1: prozesslokaler In-Memory-Store (DB-ready:
// siehe db/migrations/003_accounts.sql). Swap-fähig gegen PostgreSQL/Redis.
import { config } from '../config.js';
import {
  hashPassword,
  verifyPassword,
  signJwt,
  randomToken,
  sha256Hex,
  generateTotpSecret,
  verifyTotp,
  otpauthUri,
  generateBackupCodes,
} from './crypto.js';

export interface Permissions {
  location: boolean;
  camera: boolean;
  microphone: boolean;
  notifications: boolean;
  analytics: boolean;
  personalization: boolean;
}
export interface User {
  id: string;
  email: string;
  name: string;
  avatarColor: string;
  passwordHash?: string;
  totpSecret?: string; // pending oder aktiv
  totpEnabled: boolean;
  backupCodes: string[];
  failedAttempts: number;
  lockedUntil?: number;
  createdAt: number;
  permissions: Permissions;
  oauth: { provider: string; sub: string }[];
  isGuest?: boolean;
}
export interface Session {
  id: string;
  userId: string;
  refreshHash: string;
  usedHashes: Set<string>;
  device: string;
  ip: string;
  userAgent: string;
  createdAt: number;
  lastSeenAt: number;
  revoked: boolean;
}
export type SecurityEventType =
  | 'register' | 'login' | 'login_failed' | 'logout' | 'logout_all'
  | 'new_device_login' | 'account_locked' | 'refresh_reuse'
  | '2fa_enabled' | '2fa_disabled' | 'session_revoked' | 'password_changed'
  | 'permissions_changed' | 'account_deleted' | 'oauth_login';
export interface SecurityEvent {
  id: string;
  userId: string;
  type: SecurityEventType;
  at: number;
  ip?: string;
  device?: string;
  detail?: string;
}
export interface Tokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

const ACCESS_TTL = 15 * 60; // 15 min
const REFRESH_TTL = 30 * 24 * 60 * 60; // 30 Tage
const MAX_FAILED = 5;
const LOCK_MS = 15 * 60 * 1000;

const COLORS = ['#0a84ff', '#ff375f', '#30d158', '#ff9f0a', '#bf5af2', '#5e5ce6'];
const DEFAULT_PERMS: Permissions = { location: true, camera: false, microphone: false, notifications: true, analytics: false, personalization: false };

// ---- Store ----
const users = new Map<string, User>();
const emailIndex = new Map<string, string>();
const sessions = new Map<string, Session>();
const events: SecurityEvent[] = [];
const vault = new Map<string, Map<string, string>>(); // userId -> key -> ciphertext(base64)

let seq = 0;
const id = (p: string) => `${p}_${(++seq).toString(36)}_${randomToken(4)}`;

export class AuthError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

function record(userId: string, type: SecurityEventType, ctx?: { ip?: string; device?: string; detail?: string }) {
  events.push({ id: id('evt'), userId, type, at: Date.now(), ...ctx });
}

function publicUser(u: User) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    avatarColor: u.avatarColor,
    totpEnabled: u.totpEnabled,
    permissions: u.permissions,
    oauth: u.oauth.map((o) => o.provider),
    createdAt: new Date(u.createdAt).toISOString(),
    isGuest: Boolean(u.isGuest),
  };
}

function issueTokens(user: User, session: Session): Tokens {
  const accessToken = signJwt({ sub: user.id, sid: session.id, typ: 'access' }, config.jwtSecret, ACCESS_TTL);
  const refresh = randomToken(32);
  session.refreshHash = sha256Hex(refresh);
  return { accessToken, refreshToken: refresh, expiresIn: ACCESS_TTL };
}

function newSession(userId: string, ctx: LoginCtx): Session {
  const s: Session = {
    id: id('sess'),
    userId,
    refreshHash: '',
    usedHashes: new Set(),
    device: ctx.device ?? 'Unbekanntes Gerät',
    ip: ctx.ip ?? '0.0.0.0',
    userAgent: ctx.userAgent ?? '',
    createdAt: Date.now(),
    lastSeenAt: Date.now(),
    revoked: false,
  };
  sessions.set(s.id, s);
  return s;
}

export interface LoginCtx {
  ip?: string;
  device?: string;
  userAgent?: string;
}

// ---- Registrierung ----
export function register(input: { email: string; password: string; name?: string }, ctx: LoginCtx) {
  const email = input.email.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new AuthError('invalid_email', 'Ungültige E-Mail', 400);
  if (input.password.length < 8) throw new AuthError('weak_password', 'Passwort muss mindestens 8 Zeichen haben', 400);
  if (emailIndex.has(email)) throw new AuthError('email_taken', 'E-Mail bereits registriert', 409);

  const user: User = {
    id: id('usr'),
    email,
    name: input.name?.trim() || email.split('@')[0],
    avatarColor: COLORS[users.size % COLORS.length],
    passwordHash: hashPassword(input.password),
    totpEnabled: false,
    backupCodes: [],
    failedAttempts: 0,
    createdAt: Date.now(),
    permissions: { ...DEFAULT_PERMS },
    oauth: [],
  };
  users.set(user.id, user);
  emailIndex.set(email, user.id);
  const session = newSession(user.id, ctx);
  const tokens = issueTokens(user, session);
  record(user.id, 'register', ctx);
  return { user: publicUser(user), tokens, sessionId: session.id };
}

// ---- Login ----
export function login(input: { email: string; password: string; totp?: string; backupCode?: string }, ctx: LoginCtx) {
  const email = input.email.trim().toLowerCase();
  const userId = emailIndex.get(email);
  const user = userId ? users.get(userId) : undefined;
  // Zeitkonstante-nahe Fehlbehandlung: immer verifyPassword ausführen wäre ideal.
  if (!user || !user.passwordHash) throw new AuthError('invalid_credentials', 'E-Mail oder Passwort falsch', 401);

  if (user.lockedUntil && user.lockedUntil > Date.now()) {
    throw new AuthError('account_locked', `Konto gesperrt bis ${new Date(user.lockedUntil).toLocaleTimeString('de-DE')}`, 423);
  }

  if (!verifyPassword(input.password, user.passwordHash)) {
    user.failedAttempts += 1;
    record(user.id, 'login_failed', ctx);
    if (user.failedAttempts >= MAX_FAILED) {
      user.lockedUntil = Date.now() + LOCK_MS;
      user.failedAttempts = 0;
      record(user.id, 'account_locked', { ...ctx, detail: `${MAX_FAILED} Fehlversuche` });
      throw new AuthError('account_locked', 'Zu viele Fehlversuche — Konto vorübergehend gesperrt', 423);
    }
    throw new AuthError('invalid_credentials', 'E-Mail oder Passwort falsch', 401);
  }

  // 2FA
  if (user.totpEnabled) {
    const ok =
      (input.totp && verifyTotp(user.totpSecret!, input.totp)) ||
      (input.backupCode && consumeBackupCode(user, input.backupCode));
    if (!ok) {
      if (input.totp || input.backupCode) throw new AuthError('invalid_2fa', '2FA-Code ungültig', 401);
      return { status: '2fa_required' as const };
    }
  }

  user.failedAttempts = 0;
  const alert = detectNewDevice(user.id, ctx);
  const session = newSession(user.id, ctx);
  const tokens = issueTokens(user, session);
  record(user.id, 'login', ctx);
  if (alert) record(user.id, 'new_device_login', { ...ctx, detail: 'Anmeldung von neuem Gerät/Standort' });
  return { status: 'ok' as const, user: publicUser(user), tokens, sessionId: session.id, newDevice: alert };
}

function detectNewDevice(userId: string, ctx: LoginCtx): boolean {
  const prior = [...sessions.values()].filter((s) => s.userId === userId);
  if (prior.length === 0) return false;
  return !prior.some((s) => s.device === ctx.device && s.ip === ctx.ip);
}

// ---- Token-Refresh mit Rotation & Reuse-Detection ----
export function refresh(refreshToken: string, ctx: LoginCtx): Tokens {
  const hash = sha256Hex(refreshToken);
  const session = [...sessions.values()].find((s) => !s.revoked && s.refreshHash === hash);
  if (!session) {
    // Reuse eines bereits rotierten Tokens? -> Session-Familie kompromittiert.
    const reused = [...sessions.values()].find((s) => s.usedHashes.has(hash));
    if (reused) {
      reused.revoked = true;
      record(reused.userId, 'refresh_reuse', { ...ctx, detail: 'Wiederverwendetes Refresh-Token — Sitzung gesperrt' });
    }
    throw new AuthError('invalid_refresh', 'Refresh-Token ungültig', 401);
  }
  const user = users.get(session.userId);
  if (!user) throw new AuthError('invalid_refresh', 'Refresh-Token ungültig', 401);
  session.usedHashes.add(session.refreshHash);
  session.lastSeenAt = Date.now();
  return issueTokens(user, session);
}

// ---- Sessions / Geräteverwaltung ----
export function listSessions(userId: string, currentSid?: string) {
  return [...sessions.values()]
    .filter((s) => s.userId === userId && !s.revoked)
    .sort((a, b) => b.lastSeenAt - a.lastSeenAt)
    .map((s) => ({
      id: s.id,
      device: s.device,
      ip: s.ip,
      createdAt: new Date(s.createdAt).toISOString(),
      lastSeenAt: new Date(s.lastSeenAt).toISOString(),
      current: s.id === currentSid,
    }));
}
export function revokeSession(userId: string, sessionId: string, ctx: LoginCtx) {
  const s = sessions.get(sessionId);
  if (!s || s.userId !== userId) throw new AuthError('not_found', 'Sitzung nicht gefunden', 404);
  s.revoked = true;
  record(userId, 'session_revoked', { ...ctx, detail: s.device });
}
export function logoutAll(userId: string, exceptSid: string | undefined, ctx: LoginCtx) {
  for (const s of sessions.values()) if (s.userId === userId && s.id !== exceptSid) s.revoked = true;
  record(userId, 'logout_all', ctx);
}
export function logout(userId: string, sessionId: string, ctx: LoginCtx) {
  const s = sessions.get(sessionId);
  if (s && s.userId === userId) s.revoked = true;
  record(userId, 'logout', ctx);
}

// ---- Profil ----
export function getMe(userId: string) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  return publicUser(u);
}
export function updateProfile(userId: string, patch: { name?: string; avatarColor?: string }) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  if (patch.name !== undefined) u.name = patch.name.trim().slice(0, 60);
  if (patch.avatarColor) u.avatarColor = patch.avatarColor;
  return publicUser(u);
}

// ---- 2FA ----
export function enroll2FA(userId: string) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  u.totpSecret = generateTotpSecret();
  return { secret: u.totpSecret, otpauthUri: otpauthUri(u.totpSecret, u.email) };
}
export function enable2FA(userId: string, code: string) {
  const u = users.get(userId);
  if (!u || !u.totpSecret) throw new AuthError('no_enrollment', 'Kein 2FA-Setup aktiv', 400);
  if (!verifyTotp(u.totpSecret, code)) throw new AuthError('invalid_2fa', 'Code ungültig', 400);
  u.totpEnabled = true;
  u.backupCodes = generateBackupCodes();
  record(userId, '2fa_enabled');
  return { backupCodes: u.backupCodes };
}
export function disable2FA(userId: string, code: string) {
  const u = users.get(userId);
  if (!u || !u.totpEnabled) throw new AuthError('not_enabled', '2FA nicht aktiv', 400);
  if (!verifyTotp(u.totpSecret!, code) && !consumeBackupCode(u, code)) throw new AuthError('invalid_2fa', 'Code ungültig', 400);
  u.totpEnabled = false;
  u.totpSecret = undefined;
  u.backupCodes = [];
  record(userId, '2fa_disabled');
  return { ok: true };
}
function consumeBackupCode(u: User, code: string): boolean {
  const i = u.backupCodes.indexOf(code.trim());
  if (i < 0) return false;
  u.backupCodes.splice(i, 1);
  return true;
}

// ---- Sicherheitsprotokoll ----
export function getSecurityLog(userId: string, limit = 50) {
  return events
    .filter((e) => e.userId === userId)
    .sort((a, b) => b.at - a.at)
    .slice(0, limit)
    .map((e) => ({ type: e.type, at: new Date(e.at).toISOString(), ip: e.ip, device: e.device, detail: e.detail }));
}

// ---- Berechtigungen (Datenschutz-Dashboard) ----
export function getPermissions(userId: string): Permissions {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  return u.permissions;
}
export function setPermissions(userId: string, patch: Partial<Permissions>) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  u.permissions = { ...u.permissions, ...patch };
  record(userId, 'permissions_changed', { detail: Object.keys(patch).join(',') });
  return u.permissions;
}

// ---- E2E-Vault (nur Chiffrat; Server kann nicht entschlüsseln) ----
export function vaultSet(userId: string, key: string, ciphertext: string) {
  if (!vault.has(userId)) vault.set(userId, new Map());
  vault.get(userId)!.set(key, ciphertext);
  return { ok: true };
}
export function vaultGet(userId: string, key: string) {
  return { key, ciphertext: vault.get(userId)?.get(key) ?? null };
}
export function vaultList(userId: string) {
  return { keys: [...(vault.get(userId)?.keys() ?? [])] };
}

// ---- DSGVO: Export & Löschung ----
export function exportData(userId: string) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  return {
    account: publicUser(u),
    sessions: listSessions(userId),
    securityLog: getSecurityLog(userId, 1000),
    vaultKeys: vaultList(userId).keys,
    exportedAt: new Date().toISOString(),
  };
}
export function deleteAccount(userId: string) {
  const u = users.get(userId);
  if (!u) throw new AuthError('not_found', 'Konto nicht gefunden', 404);
  emailIndex.delete(u.email);
  users.delete(userId);
  for (const s of [...sessions.values()]) if (s.userId === userId) sessions.delete(s.id);
  vault.delete(userId);
  record(userId, 'account_deleted');
  return { ok: true };
}

// ---- OAuth (Google/Apple/Microsoft): Konto finden oder anlegen ----
export function oauthUpsert(input: { provider: string; sub: string; email?: string; name?: string }, ctx: LoginCtx) {
  let user = [...users.values()].find((u) => u.oauth.some((o) => o.provider === input.provider && o.sub === input.sub));
  if (!user && input.email) {
    const existingId = emailIndex.get(input.email.toLowerCase());
    if (existingId) {
      user = users.get(existingId);
      user?.oauth.push({ provider: input.provider, sub: input.sub });
    }
  }
  if (!user) {
    const email = input.email?.toLowerCase() ?? `${input.provider}_${input.sub}@meridian.local`;
    user = {
      id: id('usr'),
      email,
      name: input.name ?? email.split('@')[0],
      avatarColor: COLORS[users.size % COLORS.length],
      totpEnabled: false,
      backupCodes: [],
      failedAttempts: 0,
      createdAt: Date.now(),
      permissions: { ...DEFAULT_PERMS },
      oauth: [{ provider: input.provider, sub: input.sub }],
    };
    users.set(user.id, user);
    emailIndex.set(email, user.id);
  }
  const session = newSession(user.id, ctx);
  const tokens = issueTokens(user, session);
  record(user.id, 'oauth_login', { ...ctx, detail: input.provider });
  return { user: publicUser(user), tokens, sessionId: session.id };
}

// ---- Nachschlage-Helfer (für andere Module, z. B. Freunde) ----
export function lookupByEmail(email: string): { id: string; name: string } | null {
  const uid = emailIndex.get(email.trim().toLowerCase());
  const u = uid ? users.get(uid) : undefined;
  return u ? { id: u.id, name: u.name } : null;
}
export function nameOf(userId: string): string {
  return users.get(userId)?.name ?? 'Nutzer';
}
export function avatarOf(userId: string): string {
  return users.get(userId)?.avatarColor ?? '#8a8a8e';
}
export function userExists(userId: string): boolean {
  return users.has(userId);
}

// ---- Gastmodus (flüchtiges Konto ohne Anmeldung) ----
export function createGuest(ctx: LoginCtx) {
  const user: User = {
    id: id('guest'),
    email: '',
    name: 'Gast',
    avatarColor: '#8a8a8e',
    totpEnabled: false,
    backupCodes: [],
    failedAttempts: 0,
    createdAt: Date.now(),
    permissions: { ...DEFAULT_PERMS, analytics: false, personalization: false },
    oauth: [],
    isGuest: true,
  };
  users.set(user.id, user);
  const session = newSession(user.id, ctx);
  const tokens = issueTokens(user, session);
  return { user: publicUser(user), tokens, sessionId: session.id };
}
