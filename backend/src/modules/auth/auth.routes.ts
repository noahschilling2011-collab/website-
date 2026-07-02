import { Router } from 'express';
import { z } from 'zod';
import * as service from './auth.service.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { validateBody } from '../../middleware/validate.js';
import { requireAuth } from '../../middleware/auth.js';
import { rateLimit } from '../../middleware/rateLimit.js';

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(1).max(100),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
  totpCode: z.string().length(6).optional(),
  device: z.string().max(200).optional(),
});

export const authRouter = Router();

const authLimiter = rateLimit({ windowSec: 60, max: 10, keyPrefix: 'auth' });

authRouter.post('/register', authLimiter, validateBody(registerSchema), asyncHandler(async (req, res) => {
  const result = await service.register(req.body);
  res.status(201).json(result);
}));

authRouter.post('/login', authLimiter, validateBody(loginSchema), asyncHandler(async (req, res) => {
  res.json(await service.login(req.body));
}));

authRouter.post('/refresh', validateBody(z.object({ refreshToken: z.string() })), asyncHandler(async (req, res) => {
  res.json({ tokens: await service.refresh(req.body.refreshToken) });
}));

authRouter.post('/logout', validateBody(z.object({ refreshToken: z.string() })), asyncHandler(async (req, res) => {
  await service.logout(req.body.refreshToken);
  res.status(204).end();
}));

authRouter.post('/totp/setup', requireAuth, asyncHandler(async (req, res) => {
  res.json(await service.setupTotp(req.user!.id));
}));

authRouter.post('/totp/enable', requireAuth, validateBody(z.object({ code: z.string().length(6) })),
  asyncHandler(async (req, res) => {
    await service.enableTotp(req.user!.id, req.body.code);
    res.status(204).end();
  }));
