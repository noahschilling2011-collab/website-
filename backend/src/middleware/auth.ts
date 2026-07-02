import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';
import { AppError } from '../utils/errors.js';

export interface AuthUser {
  id: string;
  email: string;
  role: 'user' | 'admin';
}

declare module 'express-serve-static-core' {
  interface Request {
    user?: AuthUser;
  }
}

export function signAccessToken(user: AuthUser): string {
  return jwt.sign({ sub: user.id, email: user.email, role: user.role }, config.jwtSecret, {
    expiresIn: config.accessTokenTtl,
  });
}

export function verifyAccessToken(token: string): AuthUser {
  const payload = jwt.verify(token, config.jwtSecret) as jwt.JwtPayload;
  return { id: String(payload.sub), email: String(payload.email), role: payload.role as AuthUser['role'] };
}

/** Requires a valid Bearer token; attaches req.user. */
export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return next(AppError.unauthorized());
  try {
    req.user = verifyAccessToken(header.slice(7));
    next();
  } catch {
    next(AppError.unauthorized('Invalid or expired token', 'token_invalid'));
  }
}

/** Requires the global admin role (admin panel / analytics endpoints). */
export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  if (req.user?.role !== 'admin') return next(AppError.forbidden('Admin role required'));
  next();
}
