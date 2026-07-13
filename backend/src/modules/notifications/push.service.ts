/**
 * Push notifications via Firebase Cloud Messaging (HTTP v1).
 * Auth uses the service-account JWT bearer grant directly (no SDK):
 * FCM_SERVICE_ACCOUNT_JSON holds the service account key file content.
 */
import jwt from 'jsonwebtoken';
import { query } from '../../db/pool.js';
import { redis } from '../../db/redis.js';
import { logger } from '../../utils/logger.js';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function serviceAccount(): ServiceAccount | null {
  const raw = process.env.FCM_SERVICE_ACCOUNT_JSON;
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ServiceAccount;
  } catch {
    logger.warn('FCM_SERVICE_ACCOUNT_JSON is not valid JSON');
    return null;
  }
}

export function pushConfigured(): boolean {
  return serviceAccount() !== null;
}

/** OAuth2 access token via signed JWT; cached in Redis until shortly before expiry. */
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const cacheKey = 'fcm:access_token';
  const cached = await redis.get(cacheKey).catch(() => null);
  if (cached) return cached;

  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    {
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    sa.private_key,
    { algorithm: 'RS256' },
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`FCM token exchange failed: ${res.status} ${await res.text()}`);
  const data = await res.json() as { access_token: string; expires_in: number };
  await redis.set(cacheKey, data.access_token, 'EX', Math.max(60, data.expires_in - 120)).catch(() => undefined);
  return data.access_token;
}

/**
 * Sends a push to every registered device of a user. Silently no-ops when
 * FCM is not configured; invalid tokens are pruned from the devices table.
 */
export async function sendPushToUser(
  userId: string,
  notification: { title: string; body: string },
  data?: Record<string, string>,
): Promise<void> {
  const sa = serviceAccount();
  if (!sa) return;

  const devices = await query<{ push_token: string }>(
    'SELECT push_token FROM devices WHERE user_id = $1',
    [userId],
  );
  if (devices.length === 0) return;

  const accessToken = await getAccessToken(sa);
  await Promise.all(devices.map(async ({ push_token }) => {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${accessToken}` },
        body: JSON.stringify({ message: { token: push_token, notification, data } }),
      },
    );
    if (res.status === 404 || res.status === 410) {
      await query('DELETE FROM devices WHERE push_token = $1', [push_token]);
    } else if (!res.ok) {
      logger.warn({ status: res.status, body: await res.text() }, 'FCM send failed');
    }
  }));
}
