/**
 * Sonnenauf- und -untergang, offline gerechnet.
 *
 * Für den Nachtmodus (Qualitätsvorgabe Abschnitt 4): Nach Sonnenuntergang
 * wird die Anzeige gedimmt und das Rot entsättigt. Ein Helligkeitssensor wäre
 * genauer, ist aber nicht überall verfügbar und würde im Tunnel oder in der
 * Hosentasche ständig umschalten. Sonnenstand aus Position und Datum ist
 * stabil und kostet nichts.
 *
 * Verfahren nach dem NOAA-Sonnenstandsalgorithmus in der üblichen
 * vereinfachten Form. Genauigkeit rund eine Minute — für einen Farbwechsel
 * mehr als genug.
 */

const toRad = (d: number) => (d * Math.PI) / 180;
const toDeg = (r: number) => (r * 180) / Math.PI;

/** Sonnenhöhe, ab der es als Nacht gilt. -6 Grad = Ende der bürgerlichen Dämmerung. */
const NACHT_HOEHE_GRAD = -6;

/** Julianisches Datum aus einem Zeitpunkt. */
function julianischesDatum(d: Date): number {
  return d.getTime() / 86_400_000 + 2_440_587.5;
}

/**
 * Sonnenhöhe über dem Horizont in Grad.
 *
 * Positiv heisst über dem Horizont. Diese Funktion ist der Kern — sie
 * beantwortet die Frage direkt, ohne den Umweg über Auf- und
 * Untergangszeiten. Das vermeidet die Sonderfälle, an denen solche
 * Berechnungen sonst scheitern: Polartag und Polarnacht, an denen es gar
 * keinen Sonnenaufgang gibt und eine Zeitberechnung NaN liefert.
 */
export function sonnenhoehe(lat: number, lon: number, zeit: Date): number {
  const jd = julianischesDatum(zeit);
  const n = jd - 2_451_545.0;

  // Mittlere Länge und Anomalie der Sonne.
  const L = (280.460 + 0.9856474 * n) % 360;
  const g = toRad((357.528 + 0.9856003 * n) % 360);

  // Ekliptikale Länge.
  const lambda = toRad(L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g));

  // Schiefe der Ekliptik.
  const epsilon = toRad(23.439 - 0.0000004 * n);

  // Rektaszension und Deklination.
  const alpha = Math.atan2(Math.cos(epsilon) * Math.sin(lambda), Math.cos(lambda));
  const delta = Math.asin(Math.sin(epsilon) * Math.sin(lambda));

  // Sternzeit in Greenwich, daraus der Stundenwinkel.
  const gmst = (18.697374558 + 24.06570982441908 * n) % 24;
  const lmst = toRad(((gmst * 15) + lon + 360) % 360);
  const H = lmst - alpha;

  const phi = toRad(lat);
  const hoehe = Math.asin(
    Math.sin(phi) * Math.sin(delta) + Math.cos(phi) * Math.cos(delta) * Math.cos(H),
  );

  return toDeg(hoehe);
}

/**
 * Ist es an dieser Position und zu dieser Zeit Nacht?
 *
 * Bewusst über die Sonnenhöhe statt über Auf- und Untergangszeiten: Im
 * hohen Norden gibt es Tage ohne Sonnenauf- oder -untergang, und eine
 * Zeitberechnung liefert dort NaN. Die Höhe ist immer definiert.
 */
export function istNacht(lat: number, lon: number, zeit: Date): boolean {
  const hoehe = sonnenhoehe(lat, lon, zeit);
  // NaN würde als false durchrutschen und den Nachtmodus stumm ausschalten.
  if (!Number.isFinite(hoehe)) return false;
  return hoehe < NACHT_HOEHE_GRAD;
}
