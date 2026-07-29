/**
 * Gemeinsame Typen. Bewusst klein gehalten — was nur ein Modul braucht,
 * bleibt dort.
 */

export type CameraType = 'speed' | 'red_light' | 'both';

/** Eine Anlage aus dem gebündelten Datensatz. */
export type Camera = {
  lat: number;
  lon: number;
  /** Blickrichtung in Grad, null = unbekannt (rund 64 % der Einträge). */
  dir: number | null;
  /** Tempolimit in km/h, null = unbekannt. */
  max: number | null;
  type: CameraType;
};

/** Zusätzlich: Abschnittskontrollen brauchen eine eigene Behandlung (Spec 10.5). */
export type CameraKind = CameraType | 'average_speed';

export type Dataset = {
  version: number;
  osmTimestamp: string | null;
  source: string;
  license: string;
  cell: number;
  count: number;
  grid: Record<string, Camera[]>;
};

/**
 * Eine Positionsmeldung, reduziert auf das, was die Warnlogik braucht.
 * Bewusst entkoppelt von expo-location, damit der Replay-Test dieselbe
 * Logik ohne Gerät füttern kann.
 */
export type Fix = {
  lat: number;
  lon: number;
  /** Kurs über Grund in Grad, null wenn unbekannt. */
  course: number | null;
  /** Geschwindigkeit in m/s, null wenn unbekannt. */
  speed: number | null;
  /** Horizontale Genauigkeit in Metern, null wenn unbekannt. */
  accuracy: number | null;
  /** Zeitstempel in ms seit Epoch. */
  t: number;
};

/** Eine ausgelöste Warnung. */
export type Warning = {
  camera: Camera;
  /** Distanz in Metern zum Zeitpunkt der Auslösung. */
  distance: number;
  /** Zeitstempel der auslösenden Position. */
  t: number;
};

/** Warum eine Kamera NICHT gewarnt hat — für den Replay-Test unverzichtbar. */
export type SkipReason =
  | 'zu_weit'
  | 'nicht_voraus'
  | 'gegenrichtung'
  | 'bereits_gewarnt'
  | 'typ_abgeschaltet';

export type Evaluation = {
  warning: Warning | null;
  /** Alle geprüften Kameras mit Begründung. Nur im Replay/Debug gefüllt. */
  skipped?: { camera: Camera; reason: SkipReason; distance: number }[];
};

/** Einstellungen, die der Nutzer ändern kann. */
export type Settings = {
  /** Faktor auf die Warndistanz, 0.5 bis 2.0. */
  warnDistanceFactor: number;
  sprachansage: boolean;
  lautstaerke: number;
  rotlichtblitzer: boolean;
  motorradModus: boolean;
  haptik: boolean;
  tempolimitWarnung: boolean;
  /** Faktor aus der Tacho-Kalibrierung, 1.0 = nicht kalibriert. */
  tachoFaktor: number;
};
