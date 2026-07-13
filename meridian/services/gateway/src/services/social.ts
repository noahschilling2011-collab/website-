// Community: Freunde, Live-Standort-Freigabe, Gruppenreisen.
// Echtzeit über SSE-Hub (v1). Produktion: WebSocket + Redis-Pub/Sub für
// horizontales Fan-out (siehe docs/SCALING.md). In-Memory-Store, DB-ready.
import { config } from '../config.js';
import { randomToken } from '../auth/crypto.js';
import * as auth from '../auth/service.js';

export interface Position {
  lat: number;
  lon: number;
  heading?: number;
  ts: number;
}
type Sink = (event: string, data: unknown) => void;

const friends = new Map<string, Set<string>>(); // userId -> friendIds
const requests: { id: string; fromId: string; toId: string; status: 'pending' | 'accepted' }[] = [];
const positions = new Map<string, Position>(); // userId -> letzte Position
const shares = new Map<string, { ownerId: string; expiresAt: number }>(); // code -> share
const ownerShare = new Map<string, string>(); // userId -> code
const clients = new Map<string, Set<Sink>>(); // userId -> SSE-Sinks

const POSITION_TTL = 60 * 1000;

function friendsOf(userId: string): string[] {
  return [...(friends.get(userId) ?? [])];
}
function link(a: string, b: string) {
  if (!friends.has(a)) friends.set(a, new Set());
  if (!friends.has(b)) friends.set(b, new Set());
  friends.get(a)!.add(b);
  friends.get(b)!.add(a);
}

// ---- Freunde ----
export function requestFriend(fromId: string, email: string) {
  const target = auth.lookupByEmail(email);
  if (!target) return { status: 'not_found' as const };
  if (target.id === fromId) return { status: 'self' as const };
  if (friendsOf(fromId).includes(target.id)) return { status: 'already' as const };
  const existing = requests.find((r) => r.fromId === fromId && r.toId === target.id && r.status === 'pending');
  const req = existing ?? { id: randomToken(6), fromId, toId: target.id, status: 'pending' as const };
  if (!existing) requests.push(req);
  return { status: 'sent' as const, requestId: req.id };
}

export function acceptFriend(userId: string, requestId: string) {
  const req = requests.find((r) => r.id === requestId && r.toId === userId && r.status === 'pending');
  if (!req) return { ok: false };
  req.status = 'accepted';
  link(req.fromId, req.toId);
  return { ok: true };
}

export function incomingRequests(userId: string) {
  return requests
    .filter((r) => r.toId === userId && r.status === 'pending')
    .map((r) => ({ id: r.id, from: { id: r.fromId, name: auth.nameOf(r.fromId) } }));
}

export function listFriends(userId: string) {
  return friendsOf(userId).map((id) => {
    const pos = livePosition(id);
    return { id, name: auth.nameOf(id), color: auth.avatarOf(id), sharing: Boolean(pos), position: pos ?? null };
  });
}

// ---- Live-Position ----
export function updatePosition(userId: string, lat: number, lon: number, heading?: number) {
  const pos: Position = { lat, lon, heading, ts: Date.now() };
  positions.set(userId, pos);
  // an verbundene Freunde broadcasten
  broadcast(friendsOf(userId), 'position', { userId, name: auth.nameOf(userId), color: auth.avatarOf(userId), ...pos });
  return { ok: true };
}

function livePosition(userId: string): Position | undefined {
  const p = positions.get(userId);
  if (!p) return undefined;
  if (Date.now() - p.ts > POSITION_TTL) return undefined;
  return p;
}

// ---- SSE-Hub ----
export function subscribe(userId: string, sink: Sink): () => void {
  if (!clients.has(userId)) clients.set(userId, new Set());
  clients.get(userId)!.add(sink);
  // Anfangs-Snapshot: aktuelle Positionen der Freunde
  for (const f of listFriends(userId)) {
    if (f.position) sink('position', { userId: f.id, name: f.name, color: f.color, ...f.position });
  }
  return () => {
    clients.get(userId)?.delete(sink);
  };
}

function broadcast(userIds: string[], event: string, data: unknown) {
  for (const uid of userIds) {
    const sinks = clients.get(uid);
    if (sinks) for (const s of sinks) s(event, data);
  }
}

// ---- Standort-Freigabe per Link (auch für Nicht-Nutzer) ----
export function startShare(userId: string, minutes = 60) {
  const existing = ownerShare.get(userId);
  if (existing) shares.delete(existing);
  const code = randomToken(5);
  const expiresAt = Date.now() + minutes * 60 * 1000;
  shares.set(code, { ownerId: userId, expiresAt });
  ownerShare.set(userId, code);
  return { code, url: `${config.appUrl}/#share=${code}`, expiresAt: new Date(expiresAt).toISOString() };
}

export function stopShare(userId: string) {
  const code = ownerShare.get(userId);
  if (code) shares.delete(code);
  ownerShare.delete(userId);
  return { ok: true };
}

export function viewShare(code: string) {
  const s = shares.get(code);
  if (!s || s.expiresAt < Date.now()) return null;
  const pos = livePosition(s.ownerId);
  return { name: auth.nameOf(s.ownerId), color: auth.avatarOf(s.ownerId), position: pos ?? null, expiresAt: new Date(s.expiresAt).toISOString() };
}

export function myShare(userId: string) {
  const code = ownerShare.get(userId);
  if (!code) return null;
  const s = shares.get(code);
  if (!s || s.expiresAt < Date.now()) {
    ownerShare.delete(userId);
    return null;
  }
  return { code, url: `${config.appUrl}/#share=${code}`, expiresAt: new Date(s.expiresAt).toISOString() };
}
