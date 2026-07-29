/**
 * Design-Tokens.
 *
 * Abgrenzung zu config.ts: Dort steht alles, was das Verhalten bestimmt —
 * Schwellen, Distanzen, Zeiten. Hier steht nur, wie es aussieht. Eine Zahl,
 * die eine Entscheidung auslöst, gehört nach config.ts, auch wenn sie einer
 * Farbe oder Grösse ähnlich sieht.
 *
 * Die Gestaltung folgt drei Bedingungen, unter denen die App benutzt wird:
 * direktes Sonnenlicht, Blick von der Fahrbahn weg für höchstens eine halbe
 * Sekunde, und ein Akku, der die Fahrt überstehen muss. Alles, was diesen drei
 * Punkten widerspricht, ist hier nicht vorgesehen — auch wenn es hübsch wäre.
 */

// --- Modus ----------------------------------------------------------------

/**
 * Zwei Paletten. Welche gilt, entscheidet der Aufrufer — die Regel dafür
 * (Uhrzeit, Sensor, Handschalter) ist Verhalten und gehört nicht hierher.
 */
export type ThemeMode = 'tag' | 'nacht';

export type Palette = {
  /** Hintergrund der gesamten App. */
  readonly hintergrund: string;
  /** Abgesetzte Fläche, etwa eine Karte in den Einstellungen. */
  readonly flaeche: string;
  /** Stärker abgesetzte Fläche, etwa ein gedrückter Schalter. */
  readonly flaecheHoch: string;
  /** Trennlinien. Linien statt Schatten, siehe EFFEKTE. */
  readonly linie: string;
  /** Text, der gelesen werden muss. */
  readonly text: string;
  /** Beschriftungen und Einheiten. */
  readonly textSekundaer: string;
  /** Nebensächliches, nie auf dem Fahrt-Screen. */
  readonly textLeise: string;
  /** Abgeschaltete Bedienelemente. */
  readonly textInaktiv: string;
  /** Die einzige Akzentfarbe: Warnrot. */
  readonly warn: string;
  /** Text auf Warnrot. Schwarz, weil es auf diesem Rot besser steht als Weiss. */
  readonly aufWarn: string;
  /** Gedämpftes Warnrot für Flächen, die nicht die Warnung selbst sind. */
  readonly warnGedaempft: string;
};

/**
 * Tagpalette.
 *
 * Der Hintergrund ist echtes #000000, nicht "fast schwarz". Zwei Gründe: Auf
 * OLED bleiben schwarze Pixel aus und kosten keinen Strom, und der maximale
 * Kontrast ist das Einzige, was bei Sonne auf dem Display noch hilft.
 *
 * Genau eine Akzentfarbe. Kein Grün für "alles in Ordnung", kein Gelb für
 * "Achtung": Wenn Rot die einzige Farbe im Bild ist, erkennt das Auge sie
 * peripher, ohne hinzusehen. Jede zweite Farbe entwertet diesen Effekt.
 * Der Zustand "Warnung aktiv" wird über Text und Helligkeit gezeigt, nicht
 * über Farbe.
 */
const TAG: Palette = {
  hintergrund: '#000000',
  flaeche: '#101010',
  flaecheHoch: '#1C1C1C',
  linie: '#2A2A2A',
  text: '#FFFFFF',
  textSekundaer: '#B4B4B4',
  textLeise: '#6E6E6E',
  textInaktiv: '#4A4A4A',
  // Kontrast gegen Schwarz rund 5,6:1 — reicht auch für kleinere Schrift.
  warn: '#FF2D1A',
  aufWarn: '#000000',
  warnGedaempft: '#3A0F0A',
};

/**
 * Nachtpalette.
 *
 * Nachts ist nicht der Kontrast das Problem, sondern die absolute Helligkeit:
 * Ein weisser Block auf Schwarz blendet und kostet für Sekunden die
 * Dunkeladaption. Deshalb sinkt Weiss auf ein helles Grau, und das Rot wird
 * entsättigt und abgedunkelt. Es bleibt die einzige Farbe und weiterhin
 * eindeutig rot — nur leiser.
 *
 * Der Hintergrund bleibt #000000. Dunkler geht nicht, und ein Grauschleier
 * darüber würde nur den Kontrast senken und auf OLED zusätzlich Strom kosten.
 */
const NACHT: Palette = {
  hintergrund: '#000000',
  flaeche: '#0C0C0C',
  flaecheHoch: '#161616',
  linie: '#242424',
  text: '#C8C8C8',
  textSekundaer: '#8A8A8A',
  textLeise: '#5A5A5A',
  textInaktiv: '#3C3C3C',
  // Entsättigt und dunkler, Kontrast gegen Schwarz rund 4,2:1 — genug für die
  // grossen Schriftgrade, in denen die Warnung erscheint.
  warn: '#C24438',
  aufWarn: '#000000',
  warnGedaempft: '#2A0C09',
};

export const PALETTEN: Record<ThemeMode, Palette> = {
  tag: TAG,
  nacht: NACHT,
};

export function palette(mode: ThemeMode): Palette {
  return PALETTEN[mode];
}

// --- Schrift --------------------------------------------------------------

/**
 * Schriftgrade in dp.
 *
 * Die Untergrenze ist nicht Geschmack: Aus Armlänge und mit einem Blick von
 * einer halben Sekunde ist unter 18 dp nichts mehr sicher lesbar. Was kleiner
 * ist, darf auf dem Fahrt-Screen nicht vorkommen.
 */
export const SCHRIFT = {
  /**
   * Der Tacho. Die Spec setzt 96 als Untergrenze; 120 ist gewählt, weil auch
   * ein dreistelliger Wert damit auf 320 dp Displaybreite noch passt und der
   * Wert dann ohne Fokussieren erfassbar bleibt.
   */
  TACHO: 120,
  /** Einheit neben dem Tacho, bewusst klein — sie ändert sich nie. */
  TACHO_EINHEIT: 24,
  /** Entfernung zur Anlage in der Warnung. Zweitwichtigste Zahl im Bild. */
  WARN_ENTFERNUNG: 64,
  /** Art der Anlage über der Entfernung. */
  WARN_TITEL: 36,
  /** Zahl im Tempolimit-Zeichen. */
  LIMIT: 48,
  /** Die Statuszeile. Muss im Vorbeischauen lesbar sein. */
  STATUS: 20,
  /** Fliesstext, auch die Untergrenze für alles auf dem Fahrt-Screen. */
  TEXT: 18,
  /** Beschriftungen in den Einstellungen. */
  LABEL: 16,
  /**
   * Nur für Rechtshinweis, Attribution und Lizenz. Diese Texte werden im
   * Stand gelesen, nicht während der Fahrt.
   */
  KLEIN: 14,
} as const;

export const GEWICHT = {
  NORMAL: '400',
  MITTEL: '600',
  FETT: '700',
} as const;

/**
 * Zeilenhöhen als Faktor. Grosse Zahlen brauchen weniger Luft als Fliesstext.
 */
export const ZEILENHOEHE = {
  ZAHL: 1.0,
  ENG: 1.2,
  TEXT: 1.45,
} as const;

/**
 * Ziffern mit fester Breite.
 *
 * Ohne das springt der Tacho bei jedem Wechsel von 1 auf 8 in der Breite, und
 * das Auge fängt an, der Bewegung zu folgen statt den Wert abzulesen. Gilt für
 * jede Zahl, die sich während der Fahrt ändert: Tacho, Entfernung, Restzeit.
 *
 * Die Typannotation steht da, damit der Wert ein veränderbares Tupel bleibt
 * und ohne Umweg in ein React-Native-TextStyle passt; `as const` würde ihn
 * readonly machen und dort nicht mehr zuweisbar sein.
 */
export const ZIFFERN_FEST: { fontVariant: ['tabular-nums'] } = {
  fontVariant: ['tabular-nums'],
};

// --- Mass und Fläche ------------------------------------------------------

/** Abstände in dp. Vierer-Raster, damit nichts dazwischen erfunden wird. */
export const ABSTAND = {
  XS: 4,
  S: 8,
  M: 12,
  L: 16,
  XL: 24,
  XXL: 32,
  RAND: 20,
} as const;

/**
 * Berührungsflächen in dp.
 *
 * Die Plattformvorgaben nennen 44 bis 48. Das gilt für ein ruhig gehaltenes
 * Gerät. Im fahrenden Auto zittert die Hand, das Gerät hängt schräg in der
 * Halterung und der Blick ist woanders — deshalb 64 als Untergrenze und 88
 * für alles, was während der Fahrt getroffen werden muss.
 */
export const TOUCH = {
  MIN: 64,
  FAHRT: 88,
  /** Mindestabstand zwischen zwei Zielen, damit nicht danebengegriffen wird. */
  ABSTAND: 12,
} as const;

/**
 * Eckenradien. Klein gehalten: Eine stark gerundete Fläche wirkt bei einem
 * kurzen Blick kleiner, als sie ist.
 */
export const RADIUS = {
  KEIN: 0,
  S: 8,
  M: 14,
  /** Nur für das runde Tempolimit-Zeichen. */
  KREIS: 9999,
} as const;

/** Linienstärken. */
export const LINIE = {
  DUENN: 1,
  DICK: 2,
  /** Roter Rahmen des Tempolimit-Zeichens. */
  ZEICHEN: 8,
} as const;

// --- Effekte --------------------------------------------------------------

/**
 * Was es absichtlich nicht gibt.
 *
 * Kein Glassmorphism, kein Blur, keine Schatten, keine Transparenz über dem
 * Fahrt-Screen. Drei Gründe, in dieser Reihenfolge: Durchscheinende Flächen
 * senken den Kontrast genau dann, wenn er gebraucht wird — bei Sonne. Blur
 * kostet auf jedem Frame GPU-Zeit und damit Akku, und die Fahrt dauert
 * Stunden. Und ein weicher Rand macht es schwerer, eine Fläche im
 * Augenwinkel zu finden.
 *
 * Diese Werte stehen hier als Zahlen, damit ein Blur-Wert im Code sofort als
 * Abweichung auffällt und nicht als Detail durchgeht.
 */
export const EFFEKTE = {
  BLUR_RADIUS: 0,
  SCHATTEN: false,
  /** Trennung erfolgt über Linie und Flächenhelligkeit, nicht über Erhebung. */
  ELEVATION: 0,
} as const;

/** Deckkraft. */
export const DECKKRAFT = {
  VOLL: 1,
  /** Abgeschaltetes Bedienelement. */
  INAKTIV: 0.4,
  /** Fläche unter einem geöffneten Blatt. Nur ausserhalb des Fahrt-Screens. */
  ABDECKUNG: 0.75,
} as const;

/**
 * Übergänge in ms. Kurz gehalten: Eine Warnung, die sich einblendet, kommt
 * später an als eine, die einfach da ist. Der Zustandswechsel ist die
 * Information, nicht die Bewegung dorthin.
 */
export const DAUER = {
  SOFORT: 0,
  KURZ: 120,
  NORMAL: 200,
} as const;

// --- Bündel ---------------------------------------------------------------

/**
 * Alles, was ein Screen braucht, in einem Objekt. Nur die Palette hängt am
 * Modus; Masse und Schriftgrade ändern sich nicht, wenn es dunkel wird.
 */
export type Theme = {
  readonly mode: ThemeMode;
  readonly farbe: Palette;
  readonly schrift: typeof SCHRIFT;
  readonly gewicht: typeof GEWICHT;
  readonly zeilenhoehe: typeof ZEILENHOEHE;
  readonly abstand: typeof ABSTAND;
  readonly touch: typeof TOUCH;
  readonly radius: typeof RADIUS;
  readonly linie: typeof LINIE;
  readonly effekte: typeof EFFEKTE;
  readonly deckkraft: typeof DECKKRAFT;
  readonly dauer: typeof DAUER;
};

export function theme(mode: ThemeMode): Theme {
  return {
    mode,
    farbe: PALETTEN[mode],
    schrift: SCHRIFT,
    gewicht: GEWICHT,
    zeilenhoehe: ZEILENHOEHE,
    abstand: ABSTAND,
    touch: TOUCH,
    radius: RADIUS,
    linie: LINIE,
    effekte: EFFEKTE,
    deckkraft: DECKKRAFT,
    dauer: DAUER,
  };
}

/** Vorgabe, solange der Aufrufer den Modus nicht kennt. */
export const THEME_STANDARD: Theme = theme('tag');
