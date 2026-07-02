import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';
import { publishToUser } from '../../ws/gateway.js';

const eventSchema = z.object({
  title: z.string().min(1).max(500),
  description: z.string().max(20_000).optional(),
  location: z.string().max(500).optional(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  allDay: z.boolean().optional(),
  recurrence: z.string().max(500).nullish(),
  workspaceId: z.string().uuid().nullish(),
});

export const calendarRouter = Router();
calendarRouter.use(requireAuth);

calendarRouter.get('/events', asyncHandler(async (req, res) => {
  const from = typeof req.query.from === 'string' ? req.query.from : null;
  const to = typeof req.query.to === 'string' ? req.query.to : null;
  const events = await query(
    `SELECT * FROM calendar_events WHERE user_id = $1
       AND ($2::timestamptz IS NULL OR ends_at >= $2)
       AND ($3::timestamptz IS NULL OR starts_at <= $3)
     ORDER BY starts_at LIMIT 1000`,
    [req.user!.id, from, to],
  );
  res.json({ events });
}));

calendarRouter.post('/events', validateBody(eventSchema), asyncHandler(async (req, res) => {
  const b = req.body;
  const event = await queryOne(
    `INSERT INTO calendar_events (user_id, workspace_id, title, description, location, starts_at, ends_at, all_day, recurrence)
     VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, FALSE), $9) RETURNING *`,
    [req.user!.id, b.workspaceId ?? null, b.title, b.description ?? null, b.location ?? null,
      b.startsAt, b.endsAt, b.allDay ?? null, b.recurrence ?? null],
  );
  publishToUser(req.user!.id, 'event.created', event);
  res.status(201).json({ event });
}));

calendarRouter.patch('/events/:id', validateBody(eventSchema.partial()), asyncHandler(async (req, res) => {
  const b = req.body;
  const event = await queryOne(
    `UPDATE calendar_events SET
       title = COALESCE($3, title),
       description = COALESCE($4, description),
       location = COALESCE($5, location),
       starts_at = COALESCE($6, starts_at),
       ends_at = COALESCE($7, ends_at),
       all_day = COALESCE($8, all_day),
       recurrence = COALESCE($9, recurrence)
     WHERE id = $1 AND user_id = $2 RETURNING *`,
    [req.params.id, req.user!.id, b.title ?? null, b.description ?? null, b.location ?? null,
      b.startsAt ?? null, b.endsAt ?? null, b.allDay ?? null, b.recurrence ?? null],
  );
  if (!event) throw AppError.notFound('Event not found');
  publishToUser(req.user!.id, 'event.updated', event);
  res.json({ event });
}));

calendarRouter.delete('/events/:id', asyncHandler(async (req, res) => {
  const rows = await query('DELETE FROM calendar_events WHERE id = $1 AND user_id = $2 RETURNING id', [req.params.id, req.user!.id]);
  if (rows.length === 0) throw AppError.notFound('Event not found');
  publishToUser(req.user!.id, 'event.deleted', { id: req.params.id });
  res.status(204).end();
}));
