import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';
import { publishToUser } from '../../ws/gateway.js';

const taskSchema = z.object({
  title: z.string().min(1).max(500),
  description: z.string().max(20_000).optional(),
  status: z.enum(['open', 'in_progress', 'done', 'archived']).optional(),
  priority: z.number().int().min(0).max(4).optional(),
  dueAt: z.string().datetime().nullish(),
  workspaceId: z.string().uuid().nullish(),
  assigneeId: z.string().uuid().nullish(),
});

export const tasksRouter = Router();
tasksRouter.use(requireAuth);

tasksRouter.get('/', asyncHandler(async (req, res) => {
  const status = typeof req.query.status === 'string' ? req.query.status : null;
  const tasks = await query(
    `SELECT * FROM tasks WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
     ORDER BY priority DESC, due_at NULLS LAST, created_at DESC LIMIT 500`,
    [req.user!.id, status],
  );
  res.json({ tasks });
}));

tasksRouter.post('/', validateBody(taskSchema), asyncHandler(async (req, res) => {
  const b = req.body;
  const task = await queryOne(
    `INSERT INTO tasks (user_id, workspace_id, title, description, status, priority, due_at, assignee_id)
     VALUES ($1, $2, $3, $4, COALESCE($5, 'open'), COALESCE($6, 2), $7, $8) RETURNING *`,
    [req.user!.id, b.workspaceId ?? null, b.title, b.description ?? null, b.status ?? null,
      b.priority ?? null, b.dueAt ?? null, b.assigneeId ?? null],
  );
  publishToUser(req.user!.id, 'task.created', task);
  res.status(201).json({ task });
}));

tasksRouter.patch('/:id', validateBody(taskSchema.partial()), asyncHandler(async (req, res) => {
  const b = req.body;
  const task = await queryOne(
    `UPDATE tasks SET
       title = COALESCE($3, title),
       description = COALESCE($4, description),
       status = COALESCE($5, status),
       priority = COALESCE($6, priority),
       due_at = COALESCE($7, due_at),
       assignee_id = COALESCE($8, assignee_id)
     WHERE id = $1 AND user_id = $2 RETURNING *`,
    [req.params.id, req.user!.id, b.title ?? null, b.description ?? null, b.status ?? null,
      b.priority ?? null, b.dueAt ?? null, b.assigneeId ?? null],
  );
  if (!task) throw AppError.notFound('Task not found');
  publishToUser(req.user!.id, 'task.updated', task);
  res.json({ task });
}));

tasksRouter.delete('/:id', asyncHandler(async (req, res) => {
  const rows = await query('DELETE FROM tasks WHERE id = $1 AND user_id = $2 RETURNING id', [req.params.id, req.user!.id]);
  if (rows.length === 0) throw AppError.notFound('Task not found');
  publishToUser(req.user!.id, 'task.deleted', { id: req.params.id });
  res.status(204).end();
}));
