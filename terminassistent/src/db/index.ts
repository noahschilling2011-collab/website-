import * as schema from './schema';
import { SCHEMA_SQL } from './schema-sql';

/**
 * Zwei Treiber, ein Schema.
 *
 * Mit DATABASE_URL laeuft die App gegen Postgres (Neon). Ohne DATABASE_URL
 * faellt sie auf PGlite zurueck — ein eingebettetes Postgres, das keine
 * Installation braucht. Das ist der Grund, warum `npm run dev` und
 * `npm test` ohne ein einziges externes Konto laufen.
 *
 * Das Schema-SQL wird statisch importiert, nicht zur Laufzeit aus dem
 * Dateisystem gelesen: ein dynamischer fs-Zugriff zwingt den Bundler,
 * das gesamte Projekt in das Deploy-Paket zu ziehen.
 */

export type Db = Awaited<ReturnType<typeof erzeugeDb>>;

let cache: Promise<Db> | null = null;

export function db(): Promise<Db> {
  if (!cache) cache = erzeugeDb();
  return cache;
}

async function erzeugeDb() {
  const url = process.env.DATABASE_URL;

  if (url) {
    const { drizzle } = await import('drizzle-orm/postgres-js');
    const postgres = (await import('postgres')).default;
    const client = postgres(url, { max: 5 });
    return drizzle(client, { schema });
  }

  const { PGlite } = await import('@electric-sql/pglite');
  const { drizzle } = await import('drizzle-orm/pglite');

  // Verzeichnis statt In-Memory, damit ein Neustart des Dev-Servers die
  // Vorgaenge nicht verliert.
  const client = new PGlite(process.env.PGLITE_DIR ?? '.pglite');
  await client.waitReady;
  await client.exec(SCHEMA_SQL);
  return drizzle(client, { schema });
}

export { schema };
