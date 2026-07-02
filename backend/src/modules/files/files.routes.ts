/**
 * File manager & cloud sync. Files are stored on local disk under
 * UPLOAD_DIR by default; the storage_key column keeps the code
 * S3-compatible (swap the read/write helpers for S3 in production).
 */
import { Router } from 'express';
import multer from 'multer';
import { mkdir, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { z } from 'zod';
import { query, queryOne } from '../../db/pool.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { AppError } from '../../utils/errors.js';
import { config } from '../../config/index.js';

const upload = multer({
  storage: multer.diskStorage({
    destination: async (_req, _file, cb) => {
      await mkdir(config.uploadDir, { recursive: true });
      cb(null, config.uploadDir);
    },
    filename: (_req, file, cb) => {
      cb(null, `${crypto.randomUUID()}${path.extname(file.originalname).slice(0, 16)}`);
    },
  }),
  limits: { fileSize: 200 * 1024 * 1024 },
});

interface FileRow {
  id: string;
  name: string;
  mime_type: string;
  size_bytes: string;
  storage_key: string;
  folder: string;
}

export const filesRouter = Router();
filesRouter.use(requireAuth);

filesRouter.get('/', asyncHandler(async (req, res) => {
  const folder = typeof req.query.folder === 'string' ? req.query.folder : '/';
  const files = await query<FileRow>(
    'SELECT id, name, mime_type, size_bytes, folder, created_at FROM files WHERE user_id = $1 AND folder = $2 ORDER BY name',
    [req.user!.id, folder],
  );
  res.json({ files });
}));

filesRouter.post('/', upload.single('file'), asyncHandler(async (req, res) => {
  if (!req.file) throw AppError.badRequest('No file uploaded (field name: "file")');
  const folder = typeof req.body.folder === 'string' && req.body.folder.startsWith('/') ? req.body.folder : '/';
  const file = await queryOne<FileRow>(
    `INSERT INTO files (user_id, name, mime_type, size_bytes, storage_key, folder)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, name, mime_type, size_bytes, folder, created_at`,
    [req.user!.id, req.file.originalname, req.file.mimetype, req.file.size, req.file.filename, folder],
  );
  res.status(201).json({ file });
}));

filesRouter.get('/:id/download', asyncHandler(async (req, res) => {
  const file = await queryOne<FileRow>(
    'SELECT * FROM files WHERE id = $1 AND user_id = $2',
    [req.params.id, req.user!.id],
  );
  if (!file) throw AppError.notFound('File not found');
  res.setHeader('content-type', file.mime_type);
  res.setHeader('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(file.name)}`);
  createReadStream(path.join(config.uploadDir, path.basename(file.storage_key))).pipe(res);
}));

filesRouter.patch('/:id', validateBody(z.object({
  name: z.string().min(1).max(500).optional(),
  folder: z.string().startsWith('/').max(1000).optional(),
})), asyncHandler(async (req, res) => {
  const file = await queryOne<FileRow>(
    `UPDATE files SET name = COALESCE($3, name), folder = COALESCE($4, folder)
     WHERE id = $1 AND user_id = $2
     RETURNING id, name, mime_type, size_bytes, folder, created_at`,
    [req.params.id, req.user!.id, req.body.name ?? null, req.body.folder ?? null],
  );
  if (!file) throw AppError.notFound('File not found');
  res.json({ file });
}));

filesRouter.delete('/:id', asyncHandler(async (req, res) => {
  const file = await queryOne<FileRow>(
    'DELETE FROM files WHERE id = $1 AND user_id = $2 RETURNING storage_key',
    [req.params.id, req.user!.id],
  );
  if (!file) throw AppError.notFound('File not found');
  await unlink(path.join(config.uploadDir, path.basename(file.storage_key))).catch(() => undefined);
  res.status(204).end();
}));
