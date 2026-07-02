import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';

export const usersRouter = Router();
usersRouter.use(requireAuth);

usersRouter.get('/me', asyncHandler(async (req, res) => {
  const user = await queryOne(
    `SELECT id, email, display_name, avatar_url, locale, role, totp_enabled, e2ee_public_key, created_at
     FROM users WHERE id = $1`,
    [req.user!.id],
  );
  res.json({ user });
}));

usersRouter.patch('/me', validateBody(z.object({
  displayName: z.string().min(1).max(100).optional(),
  avatarUrl: z.string().url().nullish(),
  locale: z.string().min(2).max(10).optional(),
  e2eePublicKey: z.string().max(500).nullish(),
})), asyncHandler(async (req, res) => {
  const b = req.body;
  const user = await queryOne(
    `UPDATE users SET
       display_name = COALESCE($2, display_name),
       avatar_url = COALESCE($3, avatar_url),
       locale = COALESCE($4, locale),
       e2ee_public_key = COALESCE($5, e2ee_public_key)
     WHERE id = $1
     RETURNING id, email, display_name, avatar_url, locale, role, totp_enabled, e2ee_public_key`,
    [req.user!.id, b.displayName ?? null, b.avatarUrl ?? null, b.locale ?? null, b.e2eePublicKey ?? null],
  );
  res.json({ user });
}));

/** Registers a device push token (FCM/APNs via Firebase) for notifications. */
usersRouter.post('/me/devices', validateBody(z.object({
  platform: z.enum(['ios', 'android', 'web']),
  pushToken: z.string().min(1).max(4096),
})), asyncHandler(async (req, res) => {
  await query(
    `INSERT INTO devices (user_id, platform, push_token) VALUES ($1, $2, $3)
     ON CONFLICT (user_id, push_token) DO NOTHING`,
    [req.user!.id, req.body.platform, req.body.pushToken],
  );
  res.status(201).json({ ok: true });
}));
