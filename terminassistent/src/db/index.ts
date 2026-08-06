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

/**
 * Der Zwischenspeicher haengt am PROZESS, nicht am Modul.
 *
 * Next.js buendelt Route Handler getrennt von Seiten und Server Actions.
 * Ein modul-lokales `let cache` gibt es dann zweimal — und mit ihm zwei
 * PGlite-Instanzen auf demselben Verzeichnis. PGlite ist eine eingebettete
 * Einzelprozess-Datenbank; zwei Instanzen sehen die Schreibvorgaenge der
 * jeweils anderen nicht.
 *
 * Der Anmeldelink ist genau daran gescheitert: die Server Action legte den
 * Token an, der Route Handler suchte ihn in seiner eigenen Datenbank und fand
 * nichts — nach aussen sah es aus wie ein abgelaufener Link. Betroffen waren
 * ebenso /api/takt, /api/mail/eingang und der Kalenderfeed.
 *
 * Gegen echtes Postgres faellt das nicht auf, weil dort ohnehin beide
 * Instanzen mit demselben Server reden. Das macht es zu der unangenehmen
 * Sorte Fehler: er tritt nur im Demo-Modus auf, also genau da, wo jemand das
 * Projekt zum ersten Mal ausprobiert.
 */
const SCHLUESSEL = Symbol.for('terminassistent.db');
type Global = typeof globalThis & { [SCHLUESSEL]?: Promise<Db> };

export function db(): Promise<Db> {
  const g = globalThis as Global;
  if (!g[SCHLUESSEL]) g[SCHLUESSEL] = erzeugeDb();
  return g[SCHLUESSEL];
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
