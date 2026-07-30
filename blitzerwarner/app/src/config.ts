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

// --- Noch nicht gebaut ----------------------------------------------------
//
// Die Zahlen unter dieser Überschrift steuern NICHTS. Sie gehören zu
// Funktionen, die geplant, aber nicht gebaut sind — kein Modul importiert
// sie. Sie stehen hier und nicht in einer Notiz, weil die Begründungen
// erarbeitet sind und beim Bauen gebraucht werden.
//
// Der Grund für die Überschrift: Ein Konfigblock sieht aus wie ein
// Stellparameter. Wer SPEED_LIMIT_ALERT.THRESHOLD_KMH von 5 auf 10 setzt und
// nichts merkt, sucht den Fehler bei sich. Die Trennung sagt vorher, dass es
// nichts zu merken gibt.
//
// tests/config.test.ts hält das durch: Jeder exportierte Block über dieser
// Linie muss von mindestens einem Modul gelesen werden.
//
// Was noch fehlt, steht jeweils im Block. Der Schalter für die
// Tempolimit-Warnung ist aus der UI entfernt worden — ein Schalter, der
// nichts tut, behauptet gegenüber dem Fahrer eine Überwachung, die es nicht
// gibt.

/**
 * Über-Limit-Warnung, Spec Abschnitt 8b. NICHT GEBAUT.
 *
 * Setzt den Tempolimit-Datensatz aus Phase 6 voraus, den es nicht gibt:
 * scripts/count-speedlimits.ts hat nur das Mengengerüst gemessen. Ohne
 * flächendeckende Limits an den Strassen — nicht nur an den Kameras — meldete
 * sich die Warnung an zufälligen Stellen und schwiege an den übrigen.
 */
export const SPEED_LIMIT_ALERT = {
  /** Standardmässig aus. Wer sie will, schaltet sie ein. */
  DEFAULT_ENABLED: false,

  /** Erst ab Limit + dieser Toleranz. */
  THRESHOLD_KMH: 5,

  /** Und erst nach so langer ununterbrochener Überschreitung. */
  SUSTAINED_MS: 5000,
} as const;
/**
 * Map-Matching, Spec Abschnitt 8b (Phase 7). NICHT GEBAUT.
 *
 * Braucht ein Strassennetz im App-Paket. Der Datensatz enthält heute nur
 * Punkte, keine Wege.
 */
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
/**
 * Meldefunktion, Spec Abschnitt 9 (Phase 8). NICHT GEBAUT.
 *
 * Die Zahlen beschreiben, wie eine Meldung ENTSTEHEN dürfte. Wohin sie ginge,
 * ist offen — die App macht zur Laufzeit keine Netzwerk-Requests, und das ist
 * das Produktversprechen und nicht eine offene Aufgabe.
 */
export const REPORTING = {
  MAX_PER_DAY: 20,
  /** Ungenauere Positionen werden gar nicht erst zum Melden angeboten. */
  MAX_ACCURACY_M: 20,
  /** Absenden nur im Stand. */
  MAX_SEND_SPEED_MS: 0.5,
} as const;
// --- Ende "noch nicht gebaut" ---------------------------------------------

/** Fehlerprotokoll, Qualitätsvorgabe Abschnitt 1d. */
export const ERROR_LOG = {
  MAX_ENTRIES: 200,
} as const;

/**
 * Wie darf in einem Land gewarnt werden?
 *
 * 'punkt' — Warnung an der Position der Anlage, mit Entfernungsansage.
 * 'zone'  — nur Hinweis auf einen Gefahrenbereich, ohne Position, ohne
 *           Entfernung, ohne Benennung der Gefahr. Frankreich verlangt das.
 * 'aus'   — keine Warnung.
 */
export type Warnmodus = 'punkt' | 'zone' | 'aus';

/**
 * Wie belastbar ist der Eintrag?
 *
 * 'belegt'   — die Quelle sagt es ausdrücklich.
 * 'strittig' — Quellen widersprechen sich.
 * 'unklar'   — die Quelle nennt ein Verbot, sagt aber nichts zur
 *              POI-Funktion, oder sie ist in sich widersprüchlich.
 *
 * Nur 'belegt' erlaubt einen Modus ausser 'aus'. Ein Test hält das fest.
 */
export type Belastbarkeit = 'belegt' | 'strittig' | 'unklar';

export type Landeseintrag = {
  readonly modus: Warnmodus;
  readonly hinweisBanner: boolean;
  readonly status: Belastbarkeit;
  /** Norm oder Quelle, aus der der Eintrag stammt. Pflichtfeld. */
  readonly grund: string;
  /** Was in der App steht, wenn der Nutzer nachfragt. */
  readonly hinweis: string;
};

/**
 * Länder-Gate, Spec Abschnitt 2 und 10.1.
 *
 * WARUM DIE STRUKTUR SO AUSSIEHT
 *
 * Ein einfaches `warnung: boolean` reicht für Europa nicht. In fast keinem
 * Land ist "Warnung" verboten, sondern eine bestimmte ART VON GERÄT: aktive
 * Radardetektoren, die Messanlagen aufspüren oder stören. Ein
 * Datenbank-Warner, der eine GPS-Position mit einer Liste vergleicht, ist
 * etwas anderes — er misst nichts und stört nichts. Diese Unterscheidung
 * fehlte, und sie ist der Grund, warum der Eintrag für Österreich strittig ist.
 *
 * Frankreich braucht eine dritte Möglichkeit: Dort ist der Hinweis auf einen
 * Gefahrenbereich erlaubt, die Punktwarnung nicht.
 *
 * DIE INVARIANTE: status !== 'belegt' erzwingt modus 'aus'.
 *
 * Ein Land, dessen Rechtslage nicht belegt ist, warnt nicht. Der eine Fehler
 * kostet eine Funktion, der andere ein Bussgeld — die zwei sind nicht gleich
 * viel wert.
 *
 * KEINE RECHTSBERATUNG. Vor Veröffentlichung von jemandem mit einschlägiger
 * Qualifikation prüfen lassen.
 */
export const LAENDER_GATE = {
  QUELLE:
    'ADAC, Juristische Zentrale, Übersicht Radarwarner und Blitzer-Apps im ' +
    'Ausland, Stand 5/2025, ausdrücklich ohne Gewähr',
  STAND: '2025-05',
  /** Verhalten, wenn das Land nicht sicher bestimmbar ist. */
  FALLBACK_WARNUNG_ERLAUBT: false,

  LAENDER: {
    // --- POI-Funktion laut Quelle ausdrücklich erlaubt --------------------
    BE: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    FI: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    LU: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    NL: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    PT: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    RS: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    ES: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },
    CZ: {
      modus: 'punkt', hinweisBanner: false, status: 'belegt',
      grund: 'POI-Funktion laut Quelle ausdrücklich erlaubt',
      hinweis: 'Der Hinweis auf gespeicherte Standorte ist hier zulässig.',
    },

    // --- Sonderfall Frankreich: Zonen statt Punkte ------------------------
    FR: {
      modus: 'zone', hinweisBanner: true, status: 'belegt',
      grund:
        'Seit 03.01.2012 ist der deutliche und unmittelbare Hinweis auf ' +
        'Messstellen verboten; erlaubt ist der allgemeine Hinweis auf ' +
        'Gefahrenzonen mit Mindestlänge (300 m innerorts, 2000 m Landstrasse, ' +
        '4000 m Autobahn)',
      hinweis:
        'In Frankreich darf nur auf einen Gefahrenbereich hingewiesen werden, ' +
        'nicht auf eine einzelne Messstelle. Die App nennt deshalb keine ' +
        'Entfernung und keine Art der Gefahr.',
    },

    // --- Ausdrücklich verboten, POI eingeschlossen ------------------------
    DE: {
      modus: 'aus', hinweisBanner: true, status: 'belegt',
      grund:
        '§ 23 Abs. 1c StVO; OLG Karlsruhe, Beschl. v. 07.02.2023, ' +
        'Az. 2 ORbs 35 Ss 9/23 (auch Bedienung durch den Beifahrer)',
      hinweis:
        'In Deutschland ist dem Fahrzeugführer der Betrieb und das ' +
        'betriebsbereite Mitführen eines solchen Geräts untersagt. Die ' +
        'Warnfunktion bleibt hier abgeschaltet.',
    },
    CH: {
      modus: 'aus', hinweisBanner: true, status: 'belegt',
      grund: 'Art. 57b SVG; die Quelle nennt die POI-Funktion ausdrücklich mit im Verbot',
      hinweis:
        'In der Schweiz ist das Verwenden solcher Geräte untersagt, die Quelle ' +
        'nennt die Funktion für gespeicherte Standorte ausdrücklich mit. Die ' +
        'Warnfunktion bleibt hier abgeschaltet.',
    },

    // --- Strittig --------------------------------------------------------
    AT: {
      modus: 'aus', hinweisBanner: true, status: 'strittig',
      grund:
        'WIDERSPRUCH, nicht aufgelöst. Bisheriger Eintrag im Projekt: § 98a KFG, ' +
        'Warnung verboten. Die Quelle (ADAC 5/2025) beschreibt dagegen als ' +
        'verboten nur Geräte, mit denen Überwachungseinrichtungen BEEINFLUSST ' +
        'oder GESTÖRT werden können, und nennt GPS-Geräte mit POI-Warner als ' +
        'Ankündigungsfunktion ausdrücklich als erlaubt. Strafrahmen bis 10.000 ' +
        'Euro und Einziehung des Geräts. Eine der beiden Aussagen ist falsch; ' +
        'das klärt nur der Gesetzestext in geltender Fassung. Siehe DATA.md, ' +
        'Abschnitt Offene Rechtsfragen.',
      hinweis:
        'Für Österreich ist die Rechtslage in diesem Projekt nicht geklärt: Die ' +
        'Quellen widersprechen sich, ob ein Warner ohne Messfunktion erlaubt ist. ' +
        'Solange das offen ist, bleibt die Warnfunktion abgeschaltet.',
    },

    // --- Unklar: Verbot genannt, POI-Funktion nicht behandelt -------------
    BG: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    DK: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    GR: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    IT: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    HR: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund:
        'WIDERSPRÜCHLICH: Die Quelle nennt weder ein Mitführ- noch ein ' +
        'Benutzungsverbot, die Anmerkung nennt aber Radarwarner als verboten. ' +
        'Zu widersprüchlich für belegt; der Widerspruch wird hier benannt, nicht aufgelöst.',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    LV: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    LT: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    NO: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    PL: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    RO: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund:
        'WIDERSPRÜCHLICH: kein Mitführ- und kein Benutzungsverbot genannt, ' +
        'die Anmerkung nennt aber Radarwarner beziehungsweise Störsender als ' +
        'verboten. Der Widerspruch wird hier benannt, nicht aufgelöst.',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    SE: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    SK: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    SI: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    TR: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund: 'Quelle nennt ein Benutzungsverbot, sagt nichts zur POI-Funktion',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },
    HU: {
      modus: 'aus', hinweisBanner: false, status: 'unklar',
      grund:
        'WIDERSPRÜCHLICH: kein Mitführ- und kein Benutzungsverbot genannt, ' +
        'die Anmerkung nennt aber Radarwarner als verboten. Der Widerspruch ' +
        'wird hier benannt, nicht aufgelöst.',
      hinweis: 'Für dieses Land ist die Rechtslage nicht belegt. Die Warnfunktion bleibt abgeschaltet.',
    },

    // Länder, die in der Quelle NICHT vorkommen, haben absichtlich keinen
    // Eintrag — damit greift FALLBACK_WARNUNG_ERLAUBT. Betrifft unter
    // anderem IE, GB, EE, IS, MT, CY, AL, BA, MK, ME, XK, MD, UA, LI, AD,
    // MC, SM. Ein fehlender Eintrag ist eine Aussage: wir wissen es nicht.
  },
} as const satisfies { readonly LAENDER: Readonly<Record<string, Landeseintrag>> } & Record<string, unknown>;

export type LandCode = keyof typeof LAENDER_GATE.LAENDER;

/** Räumlicher Index — muss zum Datensatz aus der Pipeline passen. */
export const GRID = {
  /** Kantenlänge einer Zelle in Grad. Identisch mit scripts/lib/normalize.ts. */
  CELL_SIZE: 0.05,
} as const;
