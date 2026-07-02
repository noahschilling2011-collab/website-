/**
 * Minimal forward-only migration runner.
 * Applies every migrations/NNN_*.sql not yet recorded in schema_migrations.
 */
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { pool } from './pool.js';
import { logger } from '../utils/logger.js';

const MIGRATIONS_DIR = path.resolve(process.cwd(), 'migrations');

export async function migrate(): Promise<void> {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);

  const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();
  const applied = new Set(
    (await pool.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name as string),
  );

  for (const file of files) {
    if (applied.has(file)) continue;
    const sql = await readFile(path.join(MIGRATIONS_DIR, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
      await client.query('COMMIT');
      logger.info({ file }, 'Migration applied');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}

// Allow "npm run migrate"
if (import.meta.url === `file://${process.argv[1]}`) {
  migrate()
    .then(() => { logger.info('Migrations complete'); process.exit(0); })
    .catch((err) => { logger.error({ err }, 'Migration failed'); process.exit(1); });
}
