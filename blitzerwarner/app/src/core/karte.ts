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
import { TOLERANZ_GRENZE_M, UMRISSE } from './country-data';
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

// --- Landesumrisse --------------------------------------------------------

/**
 * Ab welchem Umkreis ein Umriss überhaupt gezeichnet werden darf.
 *
 * Gerechnet, nicht gewählt: Die Linien sind auf TOLERANZ_GRENZE_M vereinfacht,
 * und mehr als UMRISS_MAX_FEHLER_ANTEIL des halben Bildes darf die Abweichung
 * nicht ausmachen. Ändert jemand die Vereinfachung in der Pipeline, wandert
 * diese Grenze mit.
 */
export function umrissAbRadiusM(): number {
  return TOLERANZ_GRENZE_M / KARTE.UMRISS_MAX_FEHLER_ANTEIL;
}

/** Eine gezeichnete Linie: aufeinanderfolgende Bildpunkte. */
export type Linienzug = readonly { readonly x: number; readonly y: number }[];

/**
 * Die sichtbaren Stücke der Landesumrisse, projiziert.
 *
 * WARUM DAS DER EINZIGE ECHTE KARTENINHALT IST
 *
 * Punkte ohne Bezug sind keine Karte. Strassen kann diese App nicht zeigen —
 * Strassengeometrie offline wären hunderte Megabyte. Die Landesumrisse liegen
 * dagegen schon im Paket: Das Länder-Gate braucht sie ohnehin, sie sind Public
 * Domain (Natural Earth) und kosten nichts extra. An einer Küste oder in
 * Grenznähe machen sie aus einem Punktfeld ein Bild.
 *
 * ZUSCHNITT STATT ALLES ZEICHNEN
 *
 * 39 219 Punkte in 507 Ringen liegen im Paket. Ungefiltert zu zeichnen wäre
 * bei jeder Aktualisierung eine spürbare Pause. Deshalb erst das Rechteck des
 * Bildausschnitts, dann nur die Ringe, deren eigenes Rechteck sich damit
 * überschneidet, und daraus nur die Abschnitte, die hineinragen.
 *
 * Ein Ring zerfällt dabei in mehrere Züge — er kann das Bild mehrfach queren.
 */
export function umrissLinien(
  mitteLat: number, mitteLon: number,
  groesseDp: number, radiusM: number,
): Linienzug[] {
  if (!Number.isFinite(mitteLat) || !Number.isFinite(mitteLon)) return [];
  if (!Number.isFinite(groesseDp) || groesseDp <= 0) return [];
  if (!Number.isFinite(radiusM) || radiusM < umrissAbRadiusM()) return [];

  // Das Sichtfeld als geografisches Rechteck, mit etwas Rand: Ein Abschnitt,
  // dessen beide Enden knapp draussen liegen, kann das Bild trotzdem queren.
  const randM = radiusM * 0.5;
  const spanne = radiusM + randM;
  const cos = Math.cos((mitteLat * Math.PI) / 180);
  const dLat = spanne / METER_JE_GRAD;
  const dLon = cos > 0 ? spanne / (METER_JE_GRAD * cos) : 180;

  const box = {
    latMin: mitteLat - dLat, latMax: mitteLat + dLat,
    lonMin: mitteLon - dLon, lonMax: mitteLon + dLon,
  };
  const drin = (lat: number, lon: number): boolean =>
    lat >= box.latMin && lat <= box.latMax && lon >= box.lonMin && lon <= box.lonMax;

  const raus: Linienzug[] = [];

  for (const umriss of UMRISSE) {
    const b = umriss.bbox;
    // Rechtecke, die sich nicht überschneiden — das ganze Land fällt weg.
    if (b.latMax < box.latMin || b.latMin > box.latMax) continue;
    if (b.lonMax < box.lonMin || b.lonMin > box.lonMax) continue;

    for (const ring of [...umriss.ringe, ...umriss.loecher]) {
      let zug: { x: number; y: number }[] = [];
      for (let i = 0; i < ring.length; i++) {
        const [lat, lon] = ring[i]!;
        const naechster = ring[i + 1];
        // Ein Abschnitt zählt, wenn eines seiner Enden im Rechteck liegt.
        const zaehlt =
          drin(lat, lon) || (naechster !== undefined && drin(naechster[0], naechster[1]));

        if (zaehlt) {
          zug.push(projiziere(mitteLat, mitteLon, lat, lon, groesseDp, radiusM));
        } else if (zug.length > 1) {
          raus.push(zug);
          zug = [];
        } else {
          zug = [];
        }
      }
      if (zug.length > 1) raus.push(zug);
    }
  }

  return raus;
}

// --- Massstabsbalken ------------------------------------------------------

/**
 * Ein runder Wert für den Massstabsbalken und seine Länge in Bildpunkten.
 *
 * Ohne Balken hat eine Karte ohne Strassen überhaupt keinen Bezug — die Ringe
 * allein sagen nur "gleich weit", nicht "wie weit". Gewählt wird der grösste
 * runde Wert, der höchstens ein Drittel der Bildbreite einnimmt: Länger
 * konkurriert er mit dem Inhalt, kürzer wird er ungenau abzulesen.
 */
export function massstabsbalken(
  groesseDp: number, radiusM: number,
): { meter: number; laengeDp: number } {
  const STUFEN = [
    10, 20, 50, 100, 200, 500,
    1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000,
  ];
  const maxDp = groesseDp / 3;
  const s = massstab(groesseDp, radiusM);

  let gewaehlt = STUFEN[0]!;
  for (const stufe of STUFEN) {
    if (stufe * s <= maxDp) gewaehlt = stufe;
  }
  return { meter: gewaehlt, laengeDp: gewaehlt * s };
}

// --- Auswahl per Fingertipp -----------------------------------------------

/**
 * Welcher Punkt ist gemeint?
 *
 * Ein Anlagenpunkt ist 8 dp gross, eine Fingerkuppe rund 45. Auf den Punkt zu
 * zielen wäre aussichtslos; deshalb gewinnt die nächstgelegene Anlage im
 * Umkreis von KARTE.TIPP_RADIUS_DP. null heisst: hier war nichts in der Nähe,
 * und dann wird die Auswahl aufgehoben statt der falsche Punkt gewählt.
 */
export function punktBeiTipp(
  karte: Karte, x: number, y: number,
  radiusDp: number = KARTE.TIPP_RADIUS_DP,
): Bildpunkt | null {
  let bester: Bildpunkt | null = null;
  let besteDistanz = radiusDp;
  for (const p of karte.punkte) {
    const d = Math.hypot(p.x - x, p.y - y);
    if (d <= besteDistanz) { besteDistanz = d; bester = p; }
  }
  return bester;
}

// --- Verschieben ----------------------------------------------------------

/**
 * Den Mittelpunkt um eine Bildverschiebung versetzen.
 *
 * Ziehen bewegt die Karte, nicht den Mittelpunkt — deshalb kehren die
 * Vorzeichen sich um: Wer den Finger nach rechts zieht, will weiter nach
 * Westen sehen.
 */
export function verschiebe(
  mitteLat: number, mitteLon: number,
  dxDp: number, dyDp: number,
  groesseDp: number, radiusM: number,
): { lat: number; lon: number } {
  const s = massstab(groesseDp, radiusM);
  if (s === 0 || !Number.isFinite(s)) return { lat: mitteLat, lon: mitteLon };

  const cos = Math.cos((mitteLat * Math.PI) / 180);
  const lat = mitteLat + (dyDp / s) / METER_JE_GRAD;
  const lon = cos > 0 ? mitteLon - (dxDp / s) / (METER_JE_GRAD * cos) : mitteLon;

  // Über die Pole hinaus zu schieben ergibt keine Karte mehr.
  return { lat: Math.max(-85, Math.min(85, lat)), lon };
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
