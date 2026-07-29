/**
 * Geometrie. Reine Funktionen, keine Abhängigkeiten, voll testbar.
 *
 * Diese Datei ist die Stelle, an der die Warnlogik richtig oder falsch wird.
 * Jede Funktion hier hat einen Unit-Test.
 */
import { GRID } from '../config';

const EARTH_RADIUS_M = 6_371_000;
const toRad = (deg: number) => (deg * Math.PI) / 180;
const toDeg = (rad: number) => (rad * 180) / Math.PI;

/** Winkel auf 0..360 normalisieren. */
export function normalizeBearing(deg: number): number {
  return ((deg % 360) + 360) % 360;
}

/**
 * Kürzeste Differenz zweier Winkel, 0..180.
 *
 * ACHTUNG, das ist die Funktion, an der die halbe App hängt: Der naive
 * Ausdruck |a - b| rechnet bei Peilung 350 und Kurs 10 eine Differenz von
 * 340 statt 20 und verwirft die Kamera. Ergebnis wäre, dass jede Warnung
 * auf einer ungefähr nach Norden führenden Strasse lautlos ausfällt.
 */
export function angleDiff(a: number, b: number): number {
  const d = Math.abs(normalizeBearing(a) - normalizeBearing(b));
  return d > 180 ? 360 - d : d;
}

/** Entfernung zweier Punkte in Metern. */
export function haversine(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Peilung von A nach B in Grad (0 = Nord, im Uhrzeigersinn).
 * Rechtweisend, nicht die Loxodrome — auf den hier relevanten Distanzen
 * (unter 1 km) ist der Unterschied bedeutungslos.
 */
export function bearing(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const dLon = toRad(bLon - aLon);
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return normalizeBearing(toDeg(Math.atan2(y, x)));
}

// --- Gitter ---------------------------------------------------------------
// Muss byte-genau zu scripts/lib/normalize.ts passen, sonst findet die App
// die Kameras nicht, die die Pipeline einsortiert hat.

const COORD_SCALE = 1e5;
const CELL_UNITS = Math.round(GRID.CELL_SIZE * COORD_SCALE);

/**
 * Zellindex einer Koordinate, in Ganzzahlarithmetik.
 *
 * Der Umweg über Ganzzahlen ist nicht Vorsicht, sondern nötig:
 * 48.80 / 0.05 ergibt in double-Arithmetik 975.9999999999999, und ein Punkt
 * genau auf der Zellgrenze landet dann in der falschen Zelle.
 */
export function cellIndex(lat: number, lon: number): [number, number] {
  return [
    Math.floor(Math.round(lat * COORD_SCALE) / CELL_UNITS),
    Math.floor(Math.round(lon * COORD_SCALE) / CELL_UNITS),
  ];
}

export function keyFromIndex(iLat: number, iLon: number): string {
  const lat = (iLat * CELL_UNITS) / COORD_SCALE;
  const lon = (iLon * CELL_UNITS) / COORD_SCALE;
  return `${lat.toFixed(2)},${lon.toFixed(2)}`;
}

export function cellKey(lat: number, lon: number): string {
  const [iLat, iLon] = cellIndex(lat, lon);
  return keyFromIndex(iLat, iLon);
}

/** Die 3x3-Nachbarschaft um eine Position, Schritt 3 des Algorithmus. */
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

/**
 * Reicht die 3x3-Nachbarschaft für diese Warndistanz?
 *
 * Eine Zelle ist 0,05 Grad hoch, also rund 5,5 km. In der Breite schrumpft
 * sie mit cos(lat): bei 48 Grad rund 3,7 km. Aus der Mittelzelle heraus ist
 * der garantierte Suchradius eine halbe Zelle — schlimmstenfalls steht man
 * am Zellrand. Bei Warndistanzen bis rund 500 m ist das unkritisch, aber
 * die Annahme gehört geprüft statt geglaubt.
 */
export function neighbourhoodCoversRadius(lat: number, radiusM: number): boolean {
  const cellWidthM = GRID.CELL_SIZE * 111_320 * Math.cos(toRad(lat));
  return radiusM <= cellWidthM;
}

/**
 * Senkrechter Abstand eines Punktes zu einem Liniensegment, in Metern.
 * Für das Map-Matching (Spec 8b).
 *
 * Rechnet in einer lokalen ebenen Näherung: Auf Segmentlängen von einigen
 * hundert Metern ist der Fehler weit unter der GPS-Genauigkeit.
 */
export function distanceToSegment(
  pLat: number, pLon: number,
  aLat: number, aLon: number,
  bLat: number, bLon: number,
): number {
  const latScale = 111_320;
  const lonScale = 111_320 * Math.cos(toRad(pLat));

  const px = pLon * lonScale, py = pLat * latScale;
  const ax = aLon * lonScale, ay = aLat * latScale;
  const bx = bLon * lonScale, by = bLat * latScale;

  const dx = bx - ax, dy = by - ay;
  const laengeQuadrat = dx * dx + dy * dy;

  if (laengeQuadrat === 0) return Math.hypot(px - ax, py - ay);

  // Projektion auf das Segment, auf [0,1] begrenzt — sonst misst man den
  // Abstand zur verlängerten Geraden statt zum Segment.
  let t = ((px - ax) * dx + (py - ay) * dy) / laengeQuadrat;
  t = Math.max(0, Math.min(1, t));

  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
