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
  /*
   * Hier stand `tempolimitWarnung`. Entfernt, weil der Schalter nichts tat:
   * SPEED_LIMIT_ALERT in config.ts wurde von keinem Modul gelesen, und der
   * Tempolimit-Datensatz aus Phase 6 existiert nicht. Ein Schalter, der
   * nichts tut, ist schlimmer als eine fehlende Funktion — er behauptet
   * gegenueber dem Fahrer, die App ueberwache sein Tempolimit.
   *
   * Kommt die Funktion, kommt das Feld zurueck. leseSettings() in
   * state/store.ts verwirft den gespeicherten Wert, ohne zu werfen.
   */
  /** Faktor aus der Tacho-Kalibrierung, 1.0 = nicht kalibriert. */
  tachoFaktor: number;
  /**
   * Fahrtenschreiber für die Testfahrt. Standardmässig AUS.
   *
   * Der einzige Schalter der App, der eine vollständige Bewegungsspur
   * entstehen lässt — also genau das, was die App sonst nicht tut. Deshalb
   * aus, deshalb ein eigener Hinweistext, und deshalb wird das Protokoll
   * beim Ausschalten gelöscht statt nur nicht mehr fortgeschrieben.
   */
  fahrtprotokoll: boolean;
};
