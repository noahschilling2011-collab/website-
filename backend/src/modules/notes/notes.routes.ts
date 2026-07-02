import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';
import { publishToUser } from '../../ws/gateway.js';

const noteSchema = z.object({
  title: z.string().max(500).optional(),
  content: z.string().max(1_000_000).optional(), // ciphertext when encrypted=true
  encrypted: z.boolean().optional(),
  pinned: z.boolean().optional(),
  workspaceId: z.string().uuid().nullish(),
});

export const notesRouter = Router();
notesRouter.use(requireAuth);

notesRouter.get('/', asyncHandler(async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q : null;
  const notes = await query(
    `SELECT * FROM notes WHERE user_id = $1
       AND ($2::text IS NULL OR (NOT encrypted AND (title ILIKE '%' || $2 || '%' OR content ILIKE '%' || $2 || '%')))
     ORDER BY pinned DESC, updated_at DESC LIMIT 500`,
    [req.user!.id, q],
  );
  res.json({ notes });
}));

notesRouter.post('/', validateBody(noteSchema), asyncHandler(async (req, res) => {
  const b = req.body;
  const note = await queryOne(
    `INSERT INTO notes (user_id, workspace_id, title, content, encrypted, pinned)
     VALUES ($1, $2, COALESCE($3, ''), COALESCE($4, ''), COALESCE($5, FALSE), COALESCE($6, FALSE))
     RETURNING *`,
    [req.user!.id, b.workspaceId ?? null, b.title ?? null, b.content ?? null, b.encrypted ?? null, b.pinned ?? null],
  );
  publishToUser(req.user!.id, 'note.created', note);
  res.status(201).json({ note });
}));

notesRouter.patch('/:id', validateBody(noteSchema), asyncHandler(async (req, res) => {
  const b = req.body;
  const note = await queryOne(
    `UPDATE notes SET
       title = COALESCE($3, title),
       content = COALESCE($4, content),
       encrypted = COALESCE($5, encrypted),
       pinned = COALESCE($6, pinned)
     WHERE id = $1 AND user_id = $2 RETURNING *`,
    [req.params.id, req.user!.id, b.title ?? null, b.content ?? null, b.encrypted ?? null, b.pinned ?? null],
  );
  if (!note) throw AppError.notFound('Note not found');
  publishToUser(req.user!.id, 'note.updated', note);
  res.json({ note });
}));

notesRouter.delete('/:id', asyncHandler(async (req, res) => {
  const rows = await query('DELETE FROM notes WHERE id = $1 AND user_id = $2 RETURNING id', [req.params.id, req.user!.id]);
  if (rows.length === 0) throw AppError.notFound('Note not found');
  publishToUser(req.user!.id, 'note.deleted', { id: req.params.id });
  res.status(204).end();
}));
