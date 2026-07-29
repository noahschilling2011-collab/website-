/**
 * Alle Zahlen und Schwellwerte der App.
 *
 * Qualitätsvorgabe Abschnitt 5: kein einziger Magic Number im Code. Wenn du
 * beim Lesen einer Datei über eine nackte Zahl stolperst, gehört sie hierher.
 *
 * Jede Konstante trägt den Grund, warum sie diesen Wert hat — sonst traut
 * sich später niemand, sie zu ändern.
 */

/** Warnlogik, Spec Abschnitt 5. */
export const WARN = {
  /** Untergrenze der Warndistanz in Metern, auch bei Schrittgeschwindigkeit. */
  MIN_DISTANCE_M: 300,

  /**
   * Warndistanz = max(MIN_DISTANCE_M, v * DISTANCE_PER_SPEED).
   * Bei 100 km/h (27,8 m/s) also 333 m, bei 160 km/h 533 m.
   */
  DISTANCE_PER_SPEED: 12,

  /**
   * Der Peilungsfilter: Liegt die Kamera mehr als so viel Grad neben der
   * Fahrtrichtung, ist sie nicht voraus, sondern seitlich oder hinten.
   * Das ist der Filter, der über brauchbar und unbrauchbar entscheidet.
   */
  MAX_BEARING_DELTA_DEG: 45,

  /**
   * Der Ausrichtungsfilter: Zeigt die Kamera mehr als so viel Grad von
   * unserem Kurs weg, überwacht sie die Gegenrichtung.
   * Greift nur bei Kameras mit bekannter Richtung — das sind laut DATA.md
   * nur rund 36 %.
   */
  MAX_CAMERA_DIR_DELTA_DEG: 60,

  /**
   * Unterhalb dieser Geschwindigkeit ist der GPS-Kurs unzuverlässig
   * (Spec 5). Dann wird der Richtungsfilter komplett abgeschaltet und nur
   * noch auf kurze Distanz gewarnt.
   */
  UNRELIABLE_COURSE_SPEED_MS: 5,

  /** Warndistanz, solange der Kurs unzuverlässig ist. */
  SLOW_SPEED_DISTANCE_M: 150,

  /**
   * Anti-Doppelwarnung: Eine bereits gewarnte Kamera wird erst wieder
   * scharf, wenn wir uns weiter als das Vielfache der Warndistanz entfernt
   * haben. Verhindert Dauerfeuer im Stau vor der Kamera.
   */
  REARM_DISTANCE_FACTOR: 2,
} as const;

/** Akku-Strategie, Spec Abschnitt 6. */
export const BATTERY = {
  /** Ab dieser Nähe zur nächsten Kamera auf hohe GPS-Genauigkeit schalten. */
  HIGH_ACCURACY_RADIUS_M: 2000,

  /** Positionsabstand im Leerlauf, weit weg von jeder Kamera. */
  IDLE_DISTANCE_INTERVAL_M: 200,

  /** Positionsabstand im Annäherungsmodus. */
  APPROACH_DISTANCE_INTERVAL_M: 25,

  /** Positionsabstand, wenn wir offenbar stehen. */
  PARKED_DISTANCE_INTERVAL_M: 500,

  /** Unterhalb dieser Geschwindigkeit gilt das Fahrzeug als stehend. */
  PARKED_SPEED_MS: 2,

  /** So lange muss es langsam sein, bevor gedrosselt wird. */
  PARKED_AFTER_MS: 3 * 60 * 1000,
} as const;

/** Tacho, Spec Abschnitt 8a. */
export const SPEEDOMETER = {
  /**
   * Glättung als exponentieller gleitender Mittelwert. Mehr Glättung macht
   * die Anzeige beim Bremsen träge und damit unbrauchbar.
   */
  EMA_ALPHA: 0.4,

  /** Ab dieser Ungenauigkeit ist der Wert nicht mehr vertrauenswürdig. */
  MAX_ACCURACY_M: 30,

  /**
   * So lange wird der letzte gültige Wert gehalten, wenn das GPS nichts
   * liefert. Danach "—". Niemals 0 anzeigen, wenn wir es nicht wissen.
   */
  HOLD_LAST_VALUE_MS: 3000,
} as const;

/**
 * Tacho-Abweichung nach UNECE-Regelung Nr. 39: Die Anzeige darf nie weniger
 * als die tatsächliche Geschwindigkeit zeigen und höchstens
 * 0,1 * v + 4 km/h darüber liegen.
 *
 * ACHTUNG: Diese Formel ist aus der Spec übernommen und vor einer
 * Veröffentlichung gegen den Verordnungstext zu prüfen. Sie erscheint nur
 * im Erklär-Screen, nicht in einer Berechnung, die etwas auslöst.
 */
export const SPEEDO_TOLERANCE = {
  FACTOR: 0.1,
  OFFSET_KMH: 4,
  QUELLE: 'UNECE-Regelung Nr. 39',
  GEPRUEFT_AM: null as string | null,
} as const;

/** Über-Limit-Warnung, Spec Abschnitt 8b. */
export const SPEED_LIMIT_ALERT = {
  /** Standardmässig aus. Wer sie will, schaltet sie ein. */
  DEFAULT_ENABLED: false,

  /** Erst ab Limit + dieser Toleranz. */
  THRESHOLD_KMH: 5,

  /** Und erst nach so langer ununterbrochener Überschreitung. */
  SUSTAINED_MS: 5000,
} as const;

/** Map-Matching, Spec Abschnitt 8b. */
export const MAP_MATCHING = {
  /** Suchradius um die Position. */
  SEARCH_RADIUS_M: 25,

  /**
   * Gewicht der Winkelabweichung im Score, in Metern pro Grad.
   * Der Score addiert Meter und Grad, deshalb braucht der Winkelanteil
   * eine Einheit — sonst vergleicht man Äpfel mit Birnen.
   */
  ANGLE_WEIGHT_M_PER_DEG: 2.0,

  /** Oberhalb dieses Scores gilt kein Kandidat als brauchbar. */
  MAX_SCORE: 120,

  /** Ein anderer Kandidat muss so viel besser sein, um zu gewinnen. */
  HYSTERESIS_RATIO: 0.8,

  /** Und das über so viele Updates in Folge. */
  HYSTERESIS_UPDATES: 2,
} as const;

/** Watchdog, Qualitätsvorgabe Abschnitt 1b. */
export const WATCHDOG = {
  /** Wie oft der Vordergrund prüft, ob der Hintergrund-Task noch lebt. */
  CHECK_INTERVAL_MS: 30_000,

  /** Ab dieser Stille gilt der Task als tot und es gibt hörbaren Alarm. */
  STALE_AFTER_MS: 90_000,
} as const;

/** Audio, Qualitätsvorgabe Abschnitt 2. */
export const AUDIO = {
  /**
   * Bluetooth-Geräte schlafen nach einigen Sekunden Stille ein. Der Ton
   * weckt die Verbindung, danach diese Pause, erst dann die Sprache —
   * sonst fehlen die ersten Silben.
   */
  WAKEUP_DELAY_MS: 300,

  /** Rampe, mit der die Musik nach der Ansage wieder hochkommt. */
  DUCK_RESTORE_MS: 500,

  /** Oberhalb dieser Geschwindigkeit wird die Ansage beschleunigt. */
  FAST_SPEECH_ABOVE_KMH: 130,

  /** Um diesen Faktor. */
  FAST_SPEECH_RATE: 1.15,
} as const;

/** Meldefunktion, Spec Abschnitt 9. */
export const REPORTING = {
  MAX_PER_DAY: 20,
  /** Ungenauere Positionen werden gar nicht erst zum Melden angeboten. */
  MAX_ACCURACY_M: 20,
  /** Absenden nur im Stand. */
  MAX_SEND_SPEED_MS: 0.5,
} as const;

/** Fehlerprotokoll, Qualitätsvorgabe Abschnitt 1d. */
export const ERROR_LOG = {
  MAX_ENTRIES: 200,
} as const;

/**
 * Länder-Gate, Spec Abschnitt 2 und 10.1.
 *
 * `warnung` = darf die Blitzerwarnung in diesem Land laufen?
 * Die Liste trägt ein Datum, weil sich Gesetze ändern.
 *
 * KEINE RECHTSBERATUNG. Vor Veröffentlichung von jemandem mit
 * einschlägiger Qualifikation prüfen lassen.
 */
export const LAENDER_GATE = {
  STAND: '2026-07-29',
  /** Verhalten, wenn das Land nicht sicher bestimmbar ist. */
  FALLBACK_WARNUNG_ERLAUBT: false,
  LAENDER: {
    DE: { warnung: false, hinweisBanner: true, grund: '§ 23 Abs. 1c StVO' },
    AT: { warnung: false, hinweisBanner: true, grund: '§ 98a KFG' },
    CH: { warnung: false, hinweisBanner: true, grund: 'Art. 57b SVG' },
    FR: { warnung: true, hinweisBanner: false, grund: 'Warnung zulässig, Anzeige exakter Standorte eingeschränkt' },
    ES: { warnung: true, hinweisBanner: false, grund: 'Warnung zulässig' },
    NL: { warnung: true, hinweisBanner: false, grund: 'Warnung zulässig' },
  },
} as const;

export type LandCode = keyof typeof LAENDER_GATE.LAENDER;

/** Räumlicher Index — muss zum Datensatz aus der Pipeline passen. */
export const GRID = {
  /** Kantenlänge einer Zelle in Grad. Identisch mit scripts/lib/normalize.ts. */
  CELL_SIZE: 0.05,
} as const;
