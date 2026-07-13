// Zentrale Konfiguration aus Umgebungsvariablen.
const env = process.env;

function list(v: string | undefined, fallback: string[]): string[] {
  if (!v) return fallback;
  return v.split(',').map((s) => s.trim()).filter(Boolean);
}

export const config = {
  port: Number(env.PORT ?? 8090),
  nodeEnv: env.NODE_ENV ?? 'development',
  logLevel: env.LOG_LEVEL ?? 'info',
  corsOrigins: list(env.CORS_ORIGINS, ['http://localhost:5173']),

  upstreams: {
    valhalla: env.VALHALLA_URL ?? '',
    photon: env.PHOTON_URL ?? '',
    nominatim: env.NOMINATIM_URL ?? '',
    overpass: env.OVERPASS_URL ?? 'https://overpass-api.de/api/interpreter',
    openMeteo: env.OPEN_METEO_URL ?? 'https://api.open-meteo.com/v1/forecast',
    openChargeMap: env.OPEN_CHARGE_MAP_URL ?? 'https://api.openchargemap.io/v3/poi',
    openChargeMapKey: env.OPEN_CHARGE_MAP_KEY ?? '',
  },

  tiles: {
    vector: env.TILE_URL ?? 'http://localhost:3000',
    satellite: env.SATELLITE_TILE_URL ?? '',
    mapillaryToken: env.MAPILLARY_TOKEN ?? '',
  },

  ai: {
    provider: (env.AI_PROVIDER ?? 'none') as 'anthropic' | 'local' | 'none',
    model: env.AI_MODEL ?? 'claude-opus-4-8',
    anthropicKey: env.ANTHROPIC_API_KEY ?? '',
  },

  jwtSecret: env.JWT_SECRET ?? 'dev-secret-change-me',
  requestTimeoutMs: 8000,

  appUrl: env.APP_URL ?? 'http://localhost:5173',
  rpId: env.RP_ID ?? 'localhost', // WebAuthn Relying-Party-ID
  oauth: {
    google: { clientId: env.GOOGLE_CLIENT_ID ?? '', clientSecret: env.GOOGLE_CLIENT_SECRET ?? '' },
    microsoft: { clientId: env.MS_CLIENT_ID ?? '', clientSecret: env.MS_CLIENT_SECRET ?? '', tenant: env.MS_TENANT ?? 'common' },
    apple: { clientId: env.APPLE_CLIENT_ID ?? '' },
  },
};

export type Config = typeof config;
