// Community-Client: Freunde, Live-Standort-Freigabe, Echtzeit-Stream (SSE).
import { authFetch, getAccess } from './auth';

const BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? '';

export interface Person {
  id: string;
  name: string;
  color: string;
  sharing: boolean;
  position: { lat: number; lon: number; heading?: number; ts: number } | null;
}
export interface FriendRequest {
  id: string;
  from: { id: string; name: string };
}
export interface ShareInfo {
  code: string;
  url: string;
  expiresAt: string;
}
export interface LivePosition {
  userId: string;
  name: string;
  color: string;
  lat: number;
  lon: number;
  heading?: number;
}

export const getFriends = () => authFetch<{ friends: Person[]; requests: FriendRequest[] }>('/v1/friends');
export const requestFriend = (email: string) =>
  authFetch<{ status: string; requestId?: string }>('/v1/friends/request', { method: 'POST', body: JSON.stringify({ email }) });
export const acceptFriend = (requestId: string) =>
  authFetch<{ ok: boolean }>('/v1/friends/accept', { method: 'POST', body: JSON.stringify({ requestId }) });

export const startShare = (minutes = 60) =>
  authFetch<ShareInfo>('/v1/share/start', { method: 'POST', body: JSON.stringify({ minutes }) });
export const stopShare = () => authFetch<{ ok: boolean }>('/v1/share/stop', { method: 'POST', body: JSON.stringify({}) });
export const myShare = () => authFetch<{ share: ShareInfo | null }>('/v1/share/me');

export const updatePosition = (lat: number, lon: number, heading?: number) =>
  authFetch<{ ok: boolean }>('/v1/live/update', { method: 'POST', body: JSON.stringify({ lat, lon, heading }) });

// Echtzeit-Positionen der Freunde empfangen. Gibt die EventSource zurück (zum Schließen).
export function subscribeLive(onPosition: (p: LivePosition) => void): EventSource | null {
  const token = getAccess();
  if (!token) return null;
  const es = new EventSource(`${BASE}/v1/live/stream?token=${encodeURIComponent(token)}`);
  es.addEventListener('position', (e) => {
    try {
      onPosition(JSON.parse((e as MessageEvent).data) as LivePosition);
    } catch {
      /* ignore */
    }
  });
  return es;
}
