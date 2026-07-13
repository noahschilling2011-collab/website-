/**
 * Analytics ingestion (any authenticated user) and the admin dashboard /
 * admin panel API (admin role only).
 */
import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAdmin, requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';
import { pushConfigured, sendPushToUser } from '../notifications/push.service.js';

export const analyticsRouter = Router();
analyticsRouter.use(requireAuth);

analyticsRouter.post('/events', validateBody(z.object({
  name: z.string().min(1).max(100),
  properties: z.record(z.unknown()).optional(),
})), asyncHandler(async (req, res) => {
  await query(
    'INSERT INTO analytics_events (user_id, name, properties) VALUES ($1, $2, $3)',
    [req.user!.id, req.body.name, JSON.stringify(req.body.properties ?? {})],
  );
  res.status(202).json({ ok: true });
}));

// ---------- Admin dashboard ----------

export const adminRouter = Router();
adminRouter.use(requireAuth, requireAdmin);

adminRouter.get('/dashboard', asyncHandler(async (_req, res) => {
  const [users, conversations, messages, jobs, activity] = await Promise.all([
    queryOne<{ count: string }>('SELECT count(*) FROM users'),
    queryOne<{ count: string }>('SELECT count(*) FROM conversations'),
    queryOne<{ count: string }>('SELECT count(*) FROM messages'),
    query(`SELECT kind, status, count(*) FROM ai_jobs GROUP BY kind, status`),
    query(`SELECT date_trunc('day', created_at) AS day, count(*)
           FROM analytics_events WHERE created_at > now() - interval '30 days'
           GROUP BY 1 ORDER BY 1`),
  ]);
  res.json({
    totals: {
      users: Number(users?.count ?? 0),
      conversations: Number(conversations?.count ?? 0),
      messages: Number(messages?.count ?? 0),
    },
    aiJobs: jobs,
    dailyActivity: activity,
  });
}));

adminRouter.get('/users', asyncHandler(async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q : null;
  const users = await query(
    `SELECT id, email, display_name, role, totp_enabled, created_at FROM users
     WHERE $1::text IS NULL OR email ILIKE '%' || $1 || '%' OR display_name ILIKE '%' || $1 || '%'
     ORDER BY created_at DESC LIMIT 200`,
    [q],
  );
  res.json({ users });
}));

adminRouter.patch('/users/:id/role', validateBody(z.object({ role: z.enum(['user', 'admin']) })),
  asyncHandler(async (req, res) => {
    const user = await queryOne(
      'UPDATE users SET role = $2 WHERE id = $1 RETURNING id, email, role',
      [req.params.id, req.body.role],
    );
    if (!user) throw AppError.notFound('User not found');
    res.json({ user });
  }));

adminRouter.get('/audit', asyncHandler(async (_req, res) => {
  res.json({ entries: await query('SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 500') });
}));

/** Sends a push notification to one user or (userId omitted) to everyone with a device. */
adminRouter.post('/notify', validateBody(z.object({
  userId: z.string().uuid().optional(),
  title: z.string().min(1).max(200),
  body: z.string().min(1).max(1000),
})), asyncHandler(async (req, res) => {
  if (!pushConfigured()) throw AppError.badRequest('FCM_SERVICE_ACCOUNT_JSON not configured', 'push_unconfigured');
  const targets = req.body.userId
    ? [{ user_id: req.body.userId }]
    : await query<{ user_id: string }>('SELECT DISTINCT user_id FROM devices');
  await Promise.all(targets.map((t) =>
    sendPushToUser(t.user_id, { title: req.body.title, body: req.body.body })));
  res.json({ sent: targets.length });
}));
