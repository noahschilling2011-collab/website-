import type { NextFunction, Request, Response } from 'express';
import type { ZodSchema } from 'zod';

/** Parses and replaces req.body with the validated payload; ZodError is handled centrally. */
export function validateBody(schema: ZodSchema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    req.body = schema.parse(req.body);
    next();
  };
}
