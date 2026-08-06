import fs from 'node:fs';
import path from 'node:path';

/**
 * Giesst das von drizzle-kit erzeugte SQL in ein TypeScript-Modul.
 *
 * Grund: db/index.ts darf zur Laufzeit NICHT im Dateisystem suchen. Ein
 * dynamischer fs-Zugriff zwingt den Bundler, das gesamte Projekt in das
 * Deploy-Paket zu ziehen ("causes the whole project to be traced") — inklusive
 * aller Quelldateien. Als statischer Import ist das SQL einfach Teil des
 * Moduls und der Bundler kann normal arbeiten.
 *
 * Aufruf: npm run db:sql   (nach jedem drizzle-kit generate)
 */

const wurzel = path.join(import.meta.dirname, '..');
const quelle = path.join(wurzel, 'drizzle');
const ziel = path.join(wurzel, 'src', 'db', 'schema-sql.ts');

if (!fs.existsSync(quelle)) {
  console.error('Kein drizzle/-Verzeichnis. Erst `npx drizzle-kit generate` ausfuehren.');
  process.exit(1);
}

const dateien = fs
  .readdirSync(quelle)
  .filter((d) => d.endsWith('.sql'))
  .sort();

if (dateien.length === 0) {
  console.error('Keine .sql-Dateien in drizzle/.');
  process.exit(1);
}

const sql = dateien
  .map((d) => fs.readFileSync(path.join(quelle, d), 'utf8'))
  .join('\n')
  .split('--> statement-breakpoint')
  .join('\n')
  // Wiederholbar machen: PGlite spielt das bei jedem Start komplett ein.
  .replace(/CREATE TABLE "/g, 'CREATE TABLE IF NOT EXISTS "')
  .replace(/CREATE INDEX "/g, 'CREATE INDEX IF NOT EXISTS "')
  .replace(/CREATE UNIQUE INDEX "/g, 'CREATE UNIQUE INDEX IF NOT EXISTS "')
  .replace(/ADD COLUMN "/g, 'ADD COLUMN IF NOT EXISTS "')
  // Fremdschluessel kennen kein IF NOT EXISTS und wuerden beim zweiten Lauf
  // mit "already exists" scheitern. Fuer die eingebettete Entwicklungs-
  // datenbank ist referenzielle Integritaet verzichtbar; gegen echtes
  // Postgres laeuft ohnehin drizzle-kit push mit dem vollen SQL.
  .replace(/ALTER TABLE .*? ADD CONSTRAINT .*?;/gs, (treffer) =>
    treffer.replace(/^/gm, '-- '),
  );

const inhalt = `// Erzeugt von scripts/schema-sql.ts — nicht von Hand aendern.
// Quelle: ${dateien.join(', ')}

export const SCHEMA_SQL = ${JSON.stringify(sql)};
`;

fs.writeFileSync(ziel, inhalt);
console.log(`schema-sql.ts geschrieben (${sql.length} Zeichen aus ${dateien.length} Datei(en)).`);
