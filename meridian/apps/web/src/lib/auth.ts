// Konto-Client: Token-Speicherung + automatischer Refresh + Auth-Endpunkte.
const BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? '';
const AK = 'meridian_access';
const RK = 'meridian_refresh';

export interface Me {
  id: string;
  email: string;
  name: string;
  avatarColor: string;
  totpEnabled: boolean;
  permissions: Permissions;
  oauth: string[];
  createdAt: string;
  isGuest: boolean;
}
export interface Permissions {
  location: boolean;
  camera: boolean;
  microphone: boolean;
  notifications: boolean;
  analytics: boolean;
  personalization: boolean;
}
export interface DeviceSession {
  id: string;
  device: string;
  ip: string;
  createdAt: string;
  lastSeenAt: string;
  current: boolean;
}
export interface SecurityEvent {
  type: string;
  at: string;
  ip?: string;
  device?: string;
  detail?: string;
}

export const getAccess = () => localStorage.getItem(AK);
const getRefresh = () => localStorage.getItem(RK);
function setTokens(t: { accessToken: string; refreshToken: string }) {
  localStorage.setItem(AK, t.accessToken);
  localStorage.setItem(RK, t.refreshToken);
}
export function clearTokens() {
  localStorage.removeItem(AK);
  localStorage.removeItem(RK);
}
export const isLoggedIn = () => Boolean(getAccess());

// OAuth-Redirect: Tokens aus dem URL-Fragment übernehmen (#access=…&refresh=…).
export function captureOAuthRedirect(): boolean {
  if (!location.hash.includes('access=')) return false;
  const p = new URLSearchParams(location.hash.slice(1));
  const a = p.get('access');
  const r = p.get('refresh');
  if (a && r) {
    setTokens({ accessToken: a, refreshToken: r });
    history.replaceState(null, '', location.pathname + location.search);
    return true;
  }
  return false;
}

async function raw(path: string, init?: RequestInit, withAuth = false): Promise<Response> {
  // content-type nur setzen, wenn ein Body vorhanden ist (sonst lehnt Fastify
  // POST mit leerem JSON-Body ab).
  const headers: Record<string, string> = { ...(init?.headers as Record<string, string>) };
  if (init?.body) headers['content-type'] = 'application/json';
  if (withAuth) {
    const a = getAccess();
    if (a) headers.authorization = `Bearer ${a}`;
  }
  return fetch(BASE + path, { ...init, headers });
}

// Authentifizierter Fetch mit einmaligem Refresh bei 401.
export async function authFetch<T>(path: string, init?: RequestInit): Promise<T> {
  let res = await raw(path, init, true);
  if (res.status === 401 && getRefresh()) {
    const ok = await tryRefresh();
    if (ok) res = await raw(path, init, true);
  }
  if (!res.ok) throw new Error((await safeJson(res))?.title ?? `${res.status}`);
  return res.json() as Promise<T>;
}

async function tryRefresh(): Promise<boolean> {
  try {
    const res = await raw('/v1/auth/refresh', { method: 'POST', body: JSON.stringify({ refreshToken: getRefresh() }) });
    if (!res.ok) {
      clearTokens();
      return false;
    }
    const data = (await res.json()) as { tokens: { accessToken: string; refreshToken: string } };
    setTokens(data.tokens);
    return true;
  } catch {
    clearTokens();
    return false;
  }
}

async function safeJson(res: Response): Promise<{ title?: string } | null> {
  try {
    return await res.json();
  } catch {
    return null;
  }
}

// ---- Öffentliche API ----
export interface AuthResult {
  status?: string;
  user?: Me;
  tokens?: { accessToken: string; refreshToken: string };
  newDevice?: boolean;
}

export async function register(email: string, password: string, name?: string): Promise<Me> {
  const res = await raw('/v1/auth/register', { method: 'POST', body: JSON.stringify({ email, password, name }) });
  if (!res.ok) throw new Error((await safeJson(res))?.title ?? 'Registrierung fehlgeschlagen');
  const data = (await res.json()) as Required<AuthResult>;
  setTokens(data.tokens);
  return data.user;
}

export async function login(email: string, password: string, totp?: string): Promise<AuthResult> {
  const res = await raw('/v1/auth/login', { method: 'POST', body: JSON.stringify({ email, password, totp }) });
  if (!res.ok) throw new Error((await safeJson(res))?.title ?? 'Anmeldung fehlgeschlagen');
  const data = (await res.json()) as AuthResult;
  if (data.tokens) setTokens(data.tokens);
  return data;
}

export async function guest(): Promise<Me> {
  const res = await raw('/v1/auth/guest', { method: 'POST' });
  const data = (await res.json()) as Required<AuthResult>;
  setTokens(data.tokens);
  return data.user;
}

export function oauthStart(provider: 'google' | 'apple' | 'microsoft'): Promise<{ url?: string; message?: string }> {
  return raw(`/v1/auth/oauth/${provider}/start`).then((r) => r.json());
}

export const me = () => authFetch<Me>('/v1/me');
export const updateProfile = (patch: { name?: string; avatarColor?: string }) =>
  authFetch<Me>('/v1/me', { method: 'PATCH', body: JSON.stringify(patch) });
export const listSessions = () => authFetch<{ sessions: DeviceSession[] }>('/v1/auth/sessions');
export const revokeSession = (id: string) => authFetch(`/v1/auth/sessions/${id}`, { method: 'DELETE' });
export const logoutAll = () => authFetch('/v1/auth/logout-all', { method: 'POST' });
export const enroll2FA = () => authFetch<{ secret: string; otpauthUri: string }>('/v1/auth/2fa/enroll', { method: 'POST' });
export const enable2FA = (code: string) => authFetch<{ backupCodes: string[] }>('/v1/auth/2fa/enable', { method: 'POST', body: JSON.stringify({ code }) });
export const disable2FA = (code: string) => authFetch('/v1/auth/2fa/disable', { method: 'POST', body: JSON.stringify({ code }) });
export const getPermissions = () => authFetch<{ permissions: Permissions }>('/v1/account/permissions');
export const setPermissions = (patch: Partial<Permissions>) =>
  authFetch<{ permissions: Permissions }>('/v1/account/permissions', { method: 'PUT', body: JSON.stringify(patch) });
export const securityLog = () => authFetch<{ events: SecurityEvent[] }>('/v1/account/security-log');
export const exportData = () => authFetch<unknown>('/v1/account/export');
export const deleteAccount = () => authFetch('/v1/account', { method: 'DELETE' });

export async function logout() {
  try {
    await authFetch('/v1/auth/logout', { method: 'POST' });
  } catch {
    /* egal */
  }
  clearTokens();
}
