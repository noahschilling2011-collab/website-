import pg from 'pg';
import { config } from '../config/index.js';
import { logger } from '../utils/logger.js';

export const pool = new pg.Pool({
  connectionString: config.postgresUrl,
  max: Number(process.env.PG_POOL_SIZE ?? 20),
  idleTimeoutMillis: 30_000,
});

pool.on('error', (err) => logger.error({ err }, 'Unexpected PG pool error'));

/** Thin query helper so call sites stay terse and typed. */
export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T[]> {
  const res = await pool.query<T>(text, params);
  return res.rows;
}

export async function queryOne<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<T | null> {
  const rows = await query<T>(text, params);
  return rows[0] ?? null;
}
