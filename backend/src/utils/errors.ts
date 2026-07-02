/** Typed application error with HTTP status and stable machine-readable code. */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AppError';
  }

  static badRequest(msg: string, code = 'bad_request') { return new AppError(400, code, msg); }
  static unauthorized(msg = 'Not authenticated', code = 'unauthorized') { return new AppError(401, code, msg); }
  static forbidden(msg = 'Not allowed', code = 'forbidden') { return new AppError(403, code, msg); }
  static notFound(msg = 'Not found', code = 'not_found') { return new AppError(404, code, msg); }
  static conflict(msg: string, code = 'conflict') { return new AppError(409, code, msg); }
  static tooMany(msg = 'Rate limit exceeded', code = 'rate_limited') { return new AppError(429, code, msg); }
}
