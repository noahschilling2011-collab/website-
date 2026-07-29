/**
 * Normalisierung, Deduplizierung und Gitter-Indexierung der OSM-Rohdaten.
 *
 * Reine Funktionen ohne I/O, damit sie im Unit-Test ohne Netz laufen.
 */
import type { OverpassElement } from './overpass.js';

export type CameraType = 'speed' | 'red_light' | 'both';

export type Camera = {
  /** gerundet auf 5 Nachkommastellen (~1,1 m) */
  lat: number;
  lon: number;
  /** Peilung in Grad (0 = Nord, im Uhrzeigersinn), null = unbekannt */
  dir: number | null;
  /** maxspeed in km/h, null = unbekannt */
  max: number | null;
  type: CameraType;
};

/**
 * Interne Zwischenform: merkt sich, ob der Eintrag aus einem OSM-Node oder
 * einer Enforcement-Relation stammt. Der Dedupe braucht das, um echte
 * Doppelerfassungen (Node UND Relation für dieselbe Anlage) von zwei
 * getrennt erfassten Kameras am selben Ort zu unterscheiden.
 * Wird nicht in den Datensatz geschrieben.
 */
export type RawCamera = Camera & {
  src: 'node' | 'relation';
  /** Wurde dieser Eintrag bereits mit einem anderen zusammengefasst? */
  mergedOnce?: boolean;
};

/** Kantenlänge einer Gitterzelle in Grad. */
export const CELL_SIZE = 0.05;

/** Radius, innerhalb dessen zwei Einträge als dieselbe Anlage gelten. */
export const DEDUPE_RADIUS_M = 30;

/** Richtungsdifferenz, bis zu der zwei Einträge als "gleiche Richtung" gelten. */
export const DEDUPE_BEARING_TOLERANCE_DEG = 45;

const COMPASS: Record<string, number> = {
  N: 0, NNE: 22.5, NE: 45, ENE: 67.5,
  E: 90, ESE: 112.5, SE: 135, SSE: 157.5,
  S: 180, SSW: 202.5, SW: 225, WSW: 247.5,
  W: 270, WNW: 292.5, NW: 315, NNW: 337.5,
};

/**
 * Peilung aus den OSM-Tags lesen.
 *
 * Unterstützt Gradzahlen ("135", "135.5") und Kompassangaben ("NW", "ssw").
 * "forward"/"backward" sind relativ zur Richtung eines Ways und ohne dessen
 * Geometrie nicht auflösbar -> null (die Kamera wird dann richtungslos
 * behandelt und nur über den Peilungsfilter des Fahrers gefiltert).
 */
export function parseDirection(tags: Record<string, string>): number | null {
  const raw =
    tags['camera:direction'] ??
    tags['direction'] ??
    tags['camera:direction:forward'] ??
    null;
  if (raw == null) return null;

  const value = raw.trim();
  if (value === '') return null;

  const numeric = Number(value);
  if (Number.isFinite(numeric)) {
    return normalizeBearing(numeric);
  }

  const compass = COMPASS[value.toUpperCase()];
  if (compass != null) return compass;

  return null;
}

export function normalizeBearing(deg: number): number {
  return ((deg % 360) + 360) % 360;
}

/**
 * maxspeed in km/h. "50", "50 km/h", "30 mph". Zonen-Angaben wie
 * "DE:urban" tragen keine konkrete Zahl -> null.
 */
export function parseMaxspeed(tags: Record<string, string>): number | null {
  const raw = tags['maxspeed'] ?? tags['maxspeed:forward'] ?? tags['maxspeed:backward'];
  if (!raw) return null;

  const value = raw.trim().toLowerCase();
  const mph = value.match(/^(\d+(?:\.\d+)?)\s*mph$/);
  if (mph) return Math.round(Number(mph[1]) * 1.609344);

  const kmh = value.match(/^(\d+(?:\.\d+)?)\s*(?:km\/h|kmh)?$/);
  if (kmh) {
    const n = Number(kmh[1]);
    return n > 0 && n <= 200 ? Math.round(n) : null;
  }

  return null;
}

/**
 * Kameratyp bestimmen. Rotlichtblitzer werden separat geführt, weil sie in
 * den Einstellungen einzeln abschaltbar sind.
 */
export function parseType(tags: Record<string, string>): CameraType {
  const enforcement = (tags['enforcement'] ?? '').toLowerCase();
  const parts = enforcement.split(/[;,]/).map((s) => s.trim()).filter(Boolean);

  const hasRedLight =
    parts.includes('traffic_signals') ||
    tags['highway'] === 'traffic_signals' ||
    (tags['traffic_signals'] ?? '').includes('camera');
  const hasSpeed =
    parts.includes('maxspeed') ||
    parts.includes('average_speed') ||
    tags['highway'] === 'speed_camera';

  if (hasRedLight && hasSpeed) return 'both';
  if (hasRedLight) return 'red_light';
  return 'speed';
}

const round5 = (n: number) => Math.round(n * 1e5) / 1e5;

/** Trägt diese Enforcement-Relation überhaupt eine Verkehrsüberwachung? */
function isRelevantEnforcement(tags: Record<string, string>): boolean {
  const enforcement = (tags['enforcement'] ?? '').toLowerCase();
  // type=enforcement gibt es auch für Maut, Höhen- und Gewichtsbeschränkungen
  // sowie Zufahrtskontrollen. Das sind keine Blitzer.
  return ['maxspeed', 'average_speed', 'traffic_signals'].some((r) =>
    enforcement.includes(r),
  );
}

/**
 * OSM-Elemente in das flache Camera-Format überführen.
 *
 * Für Enforcement-Relationen wird der Standort der als `device` referenzierten
 * Nodes verwendet, nicht der Mittelpunkt der Relation. Der Mittelpunkt ist der
 * Schwerpunkt aller Mitglieder, also inklusive der überwachten Straße, und
 * liegt entsprechend oft neben der Kamera. Nur wenn eine Relation keinen
 * device-Node hat (oder dieser nicht mitgeliefert wurde), bleibt der
 * Mittelpunkt als Notbehelf.
 *
 * Eine Abschnittskontrolle mit Kameras an beiden Enden ergibt dadurch auch
 * zwei Einträge statt einem in der Streckenmitte.
 */
export function normalize(elements: OverpassElement[]): RawCamera[] {
  const cameras: RawCamera[] = [];

  // Nachschlagetabelle für die Mitglieder-Auflösung.
  const nodesById = new Map<number, OverpassElement>();
  for (const el of elements) {
    if (el.type === 'node' && el.lat != null && el.lon != null) {
      nodesById.set(el.id, el);
    }
  }

  const add = (
    lat: number,
    lon: number,
    tags: Record<string, string>,
    src: 'node' | 'relation',
  ) => {
    cameras.push({
      lat: round5(lat),
      lon: round5(lon),
      dir: parseDirection(tags),
      max: parseMaxspeed(tags),
      type: parseType(tags),
      src,
    });
  };

  for (const el of elements) {
    const tags = el.tags ?? {};

    if (el.type === 'relation') {
      if (!isRelevantEnforcement(tags)) continue;

      const devices = (el.members ?? []).filter(
        (m) => m.role === 'device' && m.type === 'node',
      );

      let placed = 0;
      for (const member of devices) {
        const node = nodesById.get(member.ref);
        if (!node?.lat || !node?.lon) continue;
        // Tags des Nodes gewinnen — er trägt die genauere Richtung und oft
        // ein eigenes maxspeed. Die Relation ergänzt, was dort fehlt.
        add(node.lat, node.lon, { ...tags, ...(node.tags ?? {}) }, 'relation');
        placed++;
      }

      if (placed === 0 && el.center) {
        add(el.center.lat, el.center.lon, tags, 'relation');
      }
      continue;
    }

    // Reine Kamera-Nodes. Device-Nodes einer Relation, die zusätzlich als
    // highway=speed_camera getaggt sind, kommen hier ein zweites Mal vor —
    // beide Einträge liegen dann exakt aufeinander und der Dedupe fasst sie
    // zusammen.
    if (el.type === 'node' && tags['highway'] === 'speed_camera') {
      if (el.lat == null || el.lon == null) continue;
      add(el.lat, el.lon, tags, 'node');
    }
  }

  return cameras;
}

const EARTH_RADIUS_M = 6_371_000;
const toRad = (deg: number) => (deg * Math.PI) / 180;

export function haversine(
  aLat: number,
  aLon: number,
  bLat: number,
  bLon: number,
): number {
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Kleinste Differenz zweier Peilungen, 0..180. */
export function bearingDelta(a: number, b: number): number {
  const d = Math.abs(normalizeBearing(a) - normalizeBearing(b));
  return d > 180 ? 360 - d : d;
}

function sameDirection(a: Camera, b: Camera): boolean {
  if (a.dir == null || b.dir == null) return true; // unbekannt -> nicht widersprüchlich
  return bearingDelta(a.dir, b.dir) <= DEDUPE_BEARING_TOLERANCE_DEG;
}

/**
 * Richtung zweier zusammenzufassender Einträge bestimmen.
 *
 * Node + Relation sind dieselbe real existierende Anlage, doppelt erfasst —
 * die bekannte Richtung gilt für beide und wird übernommen.
 *
 * Zwei Nodes (oder zwei Relationen) am selben Ort können dagegen zwei
 * getrennt erfasste Kameras sein, etwa je eine pro Fahrtrichtung. Wenn dann
 * nur eine davon eine Richtung trägt, wäre das Übernehmen dieser Richtung
 * gefährlich: die Warnlogik würde die Gegenrichtung aussortieren und für
 * die andere Fahrtrichtung nie warnen. In dem Fall bleibt die Richtung
 * unbekannt — die App warnt dann richtungsunabhängig. Ein Fehlalarm ist
 * ärgerlich, eine ausbleibende Warnung ist ein kaputtes Produkt.
 *
 * Ab dem dritten Eintrag an einem Ort lässt sich "doppelt erfasst" nicht
 * mehr von "mehrere Kameras" unterscheiden — dann gilt ebenfalls die
 * vorsichtige Variante.
 */
function mergeDirection(a: RawCamera, b: RawCamera): number | null {
  if (a.dir != null && b.dir != null) return a.dir; // stimmen bereits überein
  if (a.dir == null && b.dir == null) return null;

  const isDoubleMapping = a.src !== b.src && !a.mergedOnce && !b.mergedOnce;
  return isDoubleMapping ? (a.dir ?? b.dir) : null;
}

function mergeType(a: CameraType, b: CameraType): CameraType {
  if (a === b) return a;
  return 'both';
}

/**
 * Dedupliziert Einträge, die dieselbe Anlage beschreiben.
 *
 * OSM enthält für viele Anlagen sowohl einen highway=speed_camera-Node als
 * auch eine type=enforcement-Relation. Zusammengefasst wird alles innerhalb
 * von DEDUPE_RADIUS_M, sofern die Richtungen nicht widersprechen.
 * Beim Zusammenfassen gewinnt der Eintrag mit den meisten Informationen.
 */
export function dedupe(cameras: RawCamera[]): Camera[] {
  // Nach Zellen vorsortieren, damit der Vergleich nicht O(n^2) über alles läuft.
  const buckets = new Map<string, RawCamera[]>();
  const bucketSize = 0.005; // ~500 m — deutlich grösser als der Dedupe-Radius
  const bucketKey = (lat: number, lon: number) =>
    `${Math.floor(lat / bucketSize)},${Math.floor(lon / bucketSize)}`;

  const result: RawCamera[] = [];

  for (const cam of cameras) {
    const bLat = Math.floor(cam.lat / bucketSize);
    const bLon = Math.floor(cam.lon / bucketSize);

    let merged = false;
    for (let dLat = -1; dLat <= 1 && !merged; dLat++) {
      for (let dLon = -1; dLon <= 1 && !merged; dLon++) {
        const existing = buckets.get(`${bLat + dLat},${bLon + dLon}`);
        if (!existing) continue;

        for (const other of existing) {
          if (!sameDirection(cam, other)) continue;
          if (haversine(cam.lat, cam.lon, other.lat, other.lon) > DEDUPE_RADIUS_M) continue;

          other.dir = mergeDirection(other, cam);
          other.max = other.max ?? cam.max;
          other.type = mergeType(other.type, cam.type);
          other.mergedOnce = true;
          merged = true;
          break;
        }
      }
    }

    if (merged) continue;

    // Kopie ablegen, nicht das Original: Zusammenfassen verändert den
    // behaltenen Eintrag, und die Eingabe darf davon nichts mitbekommen —
    // sonst liefert ein zweiter dedupe-Lauf über dieselben Objekte (etwa
    // für die Statistik pro Bundesland) andere Ergebnisse als der erste.
    const kept = { ...cam };
    result.push(kept);
    const key = bucketKey(kept.lat, kept.lon);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(kept);
    else buckets.set(key, [kept]);
  }

  // src/mergedOnce sind Bau-Interna und gehören nicht in den Datensatz.
  return result.map(({ src, mergedOnce, ...camera }) => camera);
}

/**
 * Koordinaten werden in Einheiten von 1e-5 Grad gerechnet, damit die
 * Zellzuordnung ohne Fliesskomma-Artefakte auskommt: `48.80 / 0.05` ergibt
 * in double-Arithmetik 975.9999999999999, und ein Punkt genau auf der
 * Zellgrenze landet dann in der falschen Zelle. Da alle Koordinaten
 * ohnehin auf 5 Nachkommastellen gerundet sind, ist die Skalierung exakt.
 */
const COORD_SCALE = 1e5;
const CELL_UNITS = Math.round(CELL_SIZE * COORD_SCALE);

/** Zellindex (ganzzahlig) einer Koordinate. */
export function cellIndex(lat: number, lon: number): [number, number] {
  return [
    Math.floor(Math.round(lat * COORD_SCALE) / CELL_UNITS),
    Math.floor(Math.round(lon * COORD_SCALE) / CELL_UNITS),
  ];
}

/** Schlüssel aus Zellindizes, z. B. [975, 196] -> "48.75,9.80". */
export function keyFromIndex(iLat: number, iLon: number): string {
  const lat = (iLat * CELL_UNITS) / COORD_SCALE;
  const lon = (iLon * CELL_UNITS) / COORD_SCALE;
  return `${lat.toFixed(2)},${lon.toFixed(2)}`;
}

/** Gitterzellen-Schlüssel, z. B. "48.75,9.80". */
export function cellKey(lat: number, lon: number): string {
  const [iLat, iLon] = cellIndex(lat, lon);
  return keyFromIndex(iLat, iLon);
}

/**
 * Schlüssel der 3×3-Nachbarschaft um eine Position — Schritt 3 des
 * Warnalgorithmus. Steht hier, damit Build und Laufzeit dieselbe
 * Index-Arithmetik benutzen.
 */
export function neighbourKeys(lat: number, lon: number): string[] {
  const [iLat, iLon] = cellIndex(lat, lon);
  const keys: string[] = [];
  for (let dLat = -1; dLat <= 1; dLat++) {
    for (let dLon = -1; dLon <= 1; dLon++) {
      keys.push(keyFromIndex(iLat + dLat, iLon + dLon));
    }
  }
  return keys;
}

/** Kameras in das Gitter (0,05° × 0,05°) einsortieren — der räumliche Index. */
export function buildGrid(cameras: Camera[]): Record<string, Camera[]> {
  const grid: Record<string, Camera[]> = {};
  for (const cam of cameras) {
    const key = cellKey(cam.lat, cam.lon);
    (grid[key] ??= []).push(cam);
  }
  // Stabile Ausgabe: Zellen und Inhalte sortiert, damit ein erneuter Build
  // ohne Datenänderung ein byte-identisches JSON erzeugt.
  const sorted: Record<string, Camera[]> = {};
  for (const key of Object.keys(grid).sort()) {
    sorted[key] = grid[key].sort((a, b) => a.lat - b.lat || a.lon - b.lon);
  }
  return sorted;
}

export function boundingBox(cameras: Camera[]): [number, number, number, number] | null {
  if (cameras.length === 0) return null;
  let minLat = Infinity, minLon = Infinity, maxLat = -Infinity, maxLon = -Infinity;
  for (const c of cameras) {
    if (c.lat < minLat) minLat = c.lat;
    if (c.lat > maxLat) maxLat = c.lat;
    if (c.lon < minLon) minLon = c.lon;
    if (c.lon > maxLon) maxLon = c.lon;
  }
  return [round5(minLat), round5(minLon), round5(maxLat), round5(maxLon)];
}
