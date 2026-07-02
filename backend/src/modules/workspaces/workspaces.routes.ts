/**
 * Team workspaces with role-based access control.
 * Roles: owner > admin > editor > member > viewer.
 */
import { Router } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';

const ROLE_RANK: Record<string, number> = { owner: 4, admin: 3, editor: 2, member: 1, viewer: 0 };

export async function requireWorkspaceRole(workspaceId: string, userId: string, minRole: string): Promise<string> {
  const row = await queryOne<{ role: string }>(
    'SELECT role FROM workspace_members WHERE workspace_id = $1 AND user_id = $2',
    [workspaceId, userId],
  );
  if (!row) throw AppError.forbidden('Not a member of this workspace');
  if ((ROLE_RANK[row.role] ?? -1) < (ROLE_RANK[minRole] ?? 99)) {
    throw AppError.forbidden(`Requires role ${minRole} or higher`);
  }
  return row.role;
}

export const workspacesRouter = Router();
workspacesRouter.use(requireAuth);

workspacesRouter.get('/', asyncHandler(async (req, res) => {
  const workspaces = await query(
    `SELECT w.*, m.role AS my_role FROM workspaces w
     JOIN workspace_members m ON m.workspace_id = w.id
     WHERE m.user_id = $1 ORDER BY w.created_at`,
    [req.user!.id],
  );
  res.json({ workspaces });
}));

workspacesRouter.post('/', validateBody(z.object({ name: z.string().min(1).max(200) })), asyncHandler(async (req, res) => {
  const workspace = await queryOne<{ id: string }>(
    'INSERT INTO workspaces (name, owner_id) VALUES ($1, $2) RETURNING *',
    [req.body.name, req.user!.id],
  );
  await query(
    `INSERT INTO workspace_members (workspace_id, user_id, role) VALUES ($1, $2, 'owner')`,
    [workspace!.id, req.user!.id],
  );
  res.status(201).json({ workspace });
}));

workspacesRouter.get('/:id/members', asyncHandler(async (req, res) => {
  await requireWorkspaceRole(req.params.id!, req.user!.id, 'viewer');
  const members = await query(
    `SELECT u.id, u.email, u.display_name, u.avatar_url, m.role, m.joined_at
     FROM workspace_members m JOIN users u ON u.id = m.user_id
     WHERE m.workspace_id = $1 ORDER BY m.joined_at`,
    [req.params.id!],
  );
  res.json({ members });
}));

workspacesRouter.post('/:id/members',
  validateBody(z.object({
    email: z.string().email(),
    role: z.enum(['admin', 'editor', 'member', 'viewer']).default('member'),
  })),
  asyncHandler(async (req, res) => {
    await requireWorkspaceRole(req.params.id!, req.user!.id, 'admin');
    const invitee = await queryOne<{ id: string }>('SELECT id FROM users WHERE email = $1', [req.body.email]);
    if (!invitee) throw AppError.notFound('No user with this email');
    await query(
      `INSERT INTO workspace_members (workspace_id, user_id, role) VALUES ($1, $2, $3)
       ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
      [req.params.id!, invitee.id, req.body.role],
    );
    res.status(201).json({ ok: true });
  }));

workspacesRouter.delete('/:id/members/:userId', asyncHandler(async (req, res) => {
  await requireWorkspaceRole(req.params.id!, req.user!.id, 'admin');
  const target = await queryOne<{ role: string }>(
    'SELECT role FROM workspace_members WHERE workspace_id = $1 AND user_id = $2',
    [req.params.id!, req.params.userId!],
  );
  if (!target) throw AppError.notFound('Member not found');
  if (target.role === 'owner') throw AppError.forbidden('The owner cannot be removed');
  await query('DELETE FROM workspace_members WHERE workspace_id = $1 AND user_id = $2', [req.params.id!, req.params.userId!]);
  res.status(204).end();
}));

workspacesRouter.delete('/:id', asyncHandler(async (req, res) => {
  await requireWorkspaceRole(req.params.id!, req.user!.id, 'owner');
  await query('DELETE FROM workspaces WHERE id = $1', [req.params.id!]);
  res.status(204).end();
}));
