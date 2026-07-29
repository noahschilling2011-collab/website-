/**
 * Minimaler Overpass-Client: Mirror-Fallback, Backoff, Disk-Cache.
 *
 * Läuft ausschliesslich zur Build-Zeit. Die App selbst macht zur Laufzeit
 * keinen einzigen Netzwerk-Request (siehe README, Abschnitt Akku/Datenschutz).
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Nur Mirrors mit weltweitem Datenbestand. overpass.osm.ch und
 * maps.mail.ru sind regionale Extrakte: sie antworten mit HTTP 200 und
 * `total: 0` auf eine Query nach DE-BW, was einen leeren Datensatz
 * erzeugen würde, ohne dass irgendwo ein Fehler auftaucht.
 */
export const MIRRORS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.osm.jp/api/interpreter',
];

export type OverpassElement = {
  type: 'node' | 'way' | 'relation';
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
};

export type OverpassResponse = {
  elements: OverpassElement[];
  osm3s?: { timestamp_osm_base?: string };
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Mirrors, die in diesem Prozess als nicht erreichbar aufgefallen sind.
 * Overpass-Mirrors sind je nach Netzumgebung (Proxy, Firewall, IPv6)
 * schlicht nicht erreichbar — dann lohnt kein zweiter Versuch.
 */
const deadMirrors = new Set<string>();

/**
 * Unterscheidet "Mirror kaputt/blockiert" von "Mirror gerade überlastet".
 * Ein überlasteter Mirror antwortet mit einer Fehlerseite und ist beim
 * nächsten Gebiet vielleicht wieder frei; ein nicht erreichbarer bleibt es.
 */
function isUnreachable(err: unknown): boolean {
  const e = err as { name?: string; message?: string; cause?: { code?: string } };
  if (e?.name === 'TimeoutError' || e?.name === 'AbortError') return true;
  const code = e?.cause?.code ?? '';
  if (['ENOTFOUND', 'ECONNREFUSED', 'EHOSTUNREACH', 'ENETUNREACH', 'ETIMEDOUT'].includes(code)) {
    return true;
  }
  const msg = e?.message ?? '';
  return /fetch failed|certificate|TLS|timed out/i.test(msg);
}

function cachePath(cacheDir: string, query: string): string {
  const hash = createHash('sha1').update(query).digest('hex').slice(0, 16);
  return join(cacheDir, `${hash}.json`);
}

/** Liegt für diese Query bereits eine gecachte Antwort vor? */
export function isCached(query: string, cacheDir: string): boolean {
  return existsSync(cachePath(cacheDir, query));
}

export type QueryOptions = {
  cacheDir?: string;
  /** Cache ignorieren und frisch abfragen. */
  noCache?: boolean;
  /** Timeout pro HTTP-Versuch in ms. */
  timeoutMs?: number;
  /** Versuche pro Mirror. */
  attemptsPerMirror?: number;
  log?: (msg: string) => void;
};

/**
 * Overpass-Query absetzen. Probiert der Reihe nach alle Mirrors durch,
 * mit exponentiellem Backoff pro Mirror. Ergebnis wird auf Platte gecacht,
 * damit ein erneuter Lauf die API nicht nochmal belastet.
 */
export async function overpassQuery(
  query: string,
  opts: QueryOptions = {},
): Promise<OverpassResponse> {
  const {
    cacheDir = join(process.cwd(), '.overpass-cache'),
    noCache = false,
    timeoutMs = 180_000,
    attemptsPerMirror = 3,
    log = () => {},
  } = opts;

  mkdirSync(cacheDir, { recursive: true });
  const file = cachePath(cacheDir, query);

  if (!noCache && existsSync(file)) {
    log(`  cache hit: ${file}`);
    return JSON.parse(readFileSync(file, 'utf8')) as OverpassResponse;
  }

  let lastError: unknown;

  for (const mirror of MIRRORS) {
    if (deadMirrors.has(mirror)) {
      log(`  -> ${new URL(mirror).host} übersprungen (in diesem Lauf nicht erreichbar)`);
      continue;
    }
    for (let attempt = 1; attempt <= attemptsPerMirror; attempt++) {
      const started = Date.now();
      try {
        log(`  -> ${new URL(mirror).host} (Versuch ${attempt})`);
        const res = await fetch(mirror, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            // Overpass-Betreiber bitten explizit um einen identifizierbaren UA.
            'User-Agent': 'blitzerwarner-dataset-builder/1.0 (OSM data, build time only)',
          },
          body: new URLSearchParams({ data: query }).toString(),
          signal: AbortSignal.timeout(timeoutMs),
        });

        const text = await res.text();

        // 429 (zu viele Anfragen) und 504 (Slot belegt) sind die normale
        // Art, wie Overpass Last abwehrt. Das ist kein Fehler des Mirrors,
        // sondern eine Aufforderung zu warten — kurz durchatmen und den
        // Versuch nicht als verbraucht werten.
        if (res.status === 429 || res.status === 504) {
          const wait = 15_000 * attempt;
          log(`     HTTP ${res.status} (ausgelastet), warte ${wait / 1000}s`);
          await sleep(wait);
          throw new Error(`HTTP ${res.status}: ausgelastet`);
        }

        if (!res.ok) {
          throw new Error(`HTTP ${res.status}: ${stripHtml(text).slice(0, 200)}`);
        }
        // Overpass liefert Fehler gern mit HTTP 200 als HTML aus.
        if (!text.trimStart().startsWith('{')) {
          throw new Error(`Keine JSON-Antwort: ${stripHtml(text).slice(0, 200)}`);
        }

        const json = JSON.parse(text) as OverpassResponse;
        if (!Array.isArray(json.elements)) {
          throw new Error('Antwort ohne elements-Array');
        }

        log(`     ok, ${json.elements.length} Elemente in ${Math.round((Date.now() - started) / 1000)}s`);
        writeFileSync(file, JSON.stringify(json));
        return json;
      } catch (err) {
        lastError = err;
        log(`     fehlgeschlagen: ${(err as Error).message}`);

        // Nicht erreichbare Mirrors (DNS, TLS, Timeout beim Verbinden) für
        // den Rest des Laufs überspringen. Sonst kostet jedes weitere Gebiet
        // erneut den vollen Timeout pro totem Mirror — bei 16 Bundesländern
        // sind das Stunden Wartezeit für nichts.
        if (isUnreachable(err)) {
          deadMirrors.add(mirror);
          log(`     ${new URL(mirror).host} wird in diesem Lauf nicht mehr versucht`);
          break;
        }

        if (attempt < attemptsPerMirror) {
          const backoff = 2000 * 2 ** (attempt - 1);
          await sleep(backoff);
        }
      }
    }
  }

  throw new Error(
    `Alle Overpass-Mirrors fehlgeschlagen. Letzter Fehler: ${(lastError as Error)?.message}`,
  );
}

function stripHtml(html: string): string {
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
