import 'dotenv/config';

function required(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export const config = {
  env: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 8080),
  corsOrigin: process.env.CORS_ORIGIN ?? '*',

  postgresUrl: required('POSTGRES_URL', 'postgres://nexus:nexus@localhost:5432/nexus'),
  redisUrl: required('REDIS_URL', 'redis://localhost:6379'),

  jwtSecret: required('JWT_SECRET', 'dev-secret-change-me'),
  jwtRefreshSecret: required('JWT_REFRESH_SECRET', 'dev-refresh-secret-change-me'),
  accessTokenTtl: Number(process.env.ACCESS_TOKEN_TTL ?? 900),
  refreshTokenTtl: Number(process.env.REFRESH_TOKEN_TTL ?? 2_592_000),

  openaiApiKey: process.env.OPENAI_API_KEY ?? '',
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? '',
  geminiApiKey: process.env.GEMINI_API_KEY ?? '',
  replicateApiToken: process.env.REPLICATE_API_TOKEN ?? '',

  uploadDir: process.env.UPLOAD_DIR ?? './uploads',
} as const;

export const isProduction = config.env === 'production';
