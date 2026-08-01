/**
 * Die Umgebungskarte — die Rechnung dahinter.
 *
 * Reine Funktionen über explizitem Zustand: rein gehen Position, Radius,
 * Anlagen und Bildgrösse, raus kommen Bildpunkte. Kein React, kein `expo-*`,
 * keine Uhr, kein Zufall. Das Zeichnen macht ui/KarteScreen.tsx.
 *
 * WELCHE PROJEKTION UND WARUM DIE EINFACHE REICHT
 *
 * Eine lokale ebene Näherung (Äquirektangular um den Mittelpunkt): Ost-West
 * wird mit cos(Breite) gestaucht, sonst nichts. Der Fehler wächst mit dem
 * Bildausschnitt und liegt bei 20 km Radius in Mitteleuropa unter einem
 * Promille — bei 300 Bildpunkten Kantenlänge also weit unter einem Pixel.
 * Eine Mercator- oder gar geodätische Rechnung wäre hier nicht genauer,
 * sondern nur länger.
 *
 * Norden ist oben. Eine mitdrehende Karte wäre unterwegs nützlicher, aber
 * diese Karte ist nicht für unterwegs (siehe KARTE in config.ts) — und eine
 * Karte, die sich mit jedem GPS-Zittern dreht, ist im Stand unlesbar.
 */
import { KARTE } from '../config';
import type { Camera } from '../types';

/** Meter je Grad Breite. Konstant genug: Die Abweichung liegt unter 1 %. */
const METER_JE_GRAD = 111_320;

export type Bildpunkt = {
  /** Bildkoordinaten in dp, Ursprung oben links. */
  readonly x: number;
  readonly y: number;
  /** Entfernung vom Mittelpunkt in Metern — für Beschriftung und Sortierung. */
  readonly distanzM: number;
  readonly camera: Camera;
};

export type Karte = {
  /** Kantenlänge des quadratischen Bildes in dp. */
  readonly groesseDp: number;
  /** Radius am Bildrand in Metern. */
  readonly radiusM: number;
  /** Was gezeichnet wird. */
  readonly punkte: readonly Bildpunkt[];
  /**
   * Wie viele Anlagen im Radius liegen, aber nicht gezeichnet werden.
   *
   * Grösser als 0 heisst: Das Bild ist unvollständig, und der Screen muss das
   * sagen. Eine stillschweigend abgeschnittene Karte sieht vollständig aus.
   */
  readonly nichtGezeichnet: number;
  /** Radien der Entfernungsringe in Metern, von innen nach aussen. */
  readonly ringeM: readonly number[];
};

/** Bildpunkte je Meter bei dieser Bildgrösse und diesem Radius. */
export function massstab(groesseDp: number, radiusM: number): number {
  return groesseDp / 2 / radiusM;
}

/**
 * Eine Position in Bildkoordinaten.
 *
 * Ausgelagert, weil ausser den Anlagen auch die eigene Position und später
 * vielleicht eine Zone denselben Weg gehen — und zwei Projektionen
 * nebeneinander wären zwei Gelegenheiten, sie unterschiedlich zu machen.
 */
export function projiziere(
  mitteLat: number, mitteLon: number,
  lat: number, lon: number,
  groesseDp: number, radiusM: number,
): { x: number; y: number } {
  const s = massstab(groesseDp, radiusM);
  const cos = Math.cos((mitteLat * Math.PI) / 180);
  const ostM = (lon - mitteLon) * METER_JE_GRAD * cos;
  const nordM = (lat - mitteLat) * METER_JE_GRAD;
  return {
    x: groesseDp / 2 + ostM * s,
    // Bildkoordinaten wachsen nach unten, Norden liegt oben: Vorzeichen dreht.
    y: groesseDp / 2 - nordM * s,
  };
}

/** Entfernung in der ebenen Näherung. Gleiche Grundlage wie die Projektion. */
function abstandM(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const cos = Math.cos((aLat * Math.PI) / 180);
  const ost = (bLon - aLon) * METER_JE_GRAD * cos;
  const nord = (bLat - aLat) * METER_JE_GRAD;
  return Math.hypot(ost, nord);
}

/**
 * Die Ringe, von innen nach aussen. Der äusserste ist immer der Radius selbst,
 * damit der Bildrand eine Bedeutung hat und nicht bloss dort endet, wo das
 * Bild aufhört.
 */
export function ringe(radiusM: number, anzahl = KARTE.RINGE): number[] {
  const raus: number[] = [];
  for (let i = 1; i <= anzahl; i++) raus.push((radiusM / anzahl) * i);
  return raus;
}

/**
 * Die Karte für eine Position berechnen.
 *
 * Anlagen ausserhalb des Radius fallen weg — nicht erst beim Zeichnen,
 * sondern hier, damit der Screen keine eigene Entscheidung trifft. Was
 * übrig ist, wird nach Entfernung sortiert: So bleibt die Auswahl bei
 * Überschreiten von MAX_PUNKTE die nächstgelegene und damit die
 * interessanteste, und sie ist reproduzierbar statt von der
 * Gitterreihenfolge abhängig.
 */
export function baueKarte(
  mitteLat: number,
  mitteLon: number,
  cameras: readonly Camera[],
  groesseDp: number,
  radiusM: number,
): Karte {
  // Eine leere Karte statt eines Fehlers: Ohne Position gibt es nichts zu
  // zeichnen, und das ist ein normaler Zustand — die App startet so, bevor
  // der erste Fix da ist. Ringe bleiben dabei ebenfalls leer, sonst stünde
  // eine Massstabsangabe über einem Bild ohne Bezug.
  const leer: Karte = {
    groesseDp, radiusM, punkte: [], nichtGezeichnet: 0, ringeM: [],
  };

  if (!Number.isFinite(mitteLat) || !Number.isFinite(mitteLon)) return leer;
  if (!Number.isFinite(groesseDp) || groesseDp <= 0) return leer;
  if (!Number.isFinite(radiusM) || radiusM <= 0) return leer;

  const drin: Bildpunkt[] = [];
  for (const camera of cameras) {
    if (!Number.isFinite(camera.lat) || !Number.isFinite(camera.lon)) continue;
    const distanzM = abstandM(mitteLat, mitteLon, camera.lat, camera.lon);
    if (distanzM > radiusM) continue;
    const { x, y } = projiziere(mitteLat, mitteLon, camera.lat, camera.lon, groesseDp, radiusM);
    drin.push({ x, y, distanzM, camera });
  }

  drin.sort((a, b) => a.distanzM - b.distanzM);

  const punkte = drin.slice(0, KARTE.MAX_PUNKTE);
  return {
    groesseDp,
    radiusM,
    punkte,
    nichtGezeichnet: drin.length - punkte.length,
    ringeM: ringe(radiusM),
  };
}
