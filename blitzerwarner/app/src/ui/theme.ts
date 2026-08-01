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
  /**
   * Art der Anlage über der Entfernung — und zugleich die Überschrift jedes
   * Screens. Bewusst derselbe Grad: Es ist dieselbe Art von Aussage, und eine
   * Grösse weniger in der Skala ist eine Entscheidung weniger, die schiefgehen
   * kann.
   */
  WARN_TITEL: 36,
  /**
   * Überschrift einer ganzseitigen Meldung (Datensatz unlesbar). Kleiner als
   * WARN_TITEL, weil hier nichts im Vorbeischauen erfasst werden muss —
   * dieser Bildschirm wird im Stand gelesen, und 36 dp würden schreien.
   */
  MELDUNG: 24,
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
 *
 * WIDERSPRUCH, DER HIER AUFGELÖST WURDE
 *
 * ZAHL stand auf 1.0, im Code standen aber 1.05 (Tacho) und daneben 1.4 und
 * 1.45 für denselben Fliesstext. Aufgelöst zugunsten des Codes, weil der
 * gelaufen ist und der Token nicht: 1.05 bleibt, 1.4 wird zu 1.45. Damit
 * ändert sich am Bild nichts ausser den zwei Stellen, die vorher 1.4 hatten.
 */
export const ZEILENHOEHE = {
  /**
   * Grosse Ziffern. Nicht 1.0: Android schneidet bei lineHeight gleich
   * fontSize die Unterlängen ab, und auch Ziffern haben welche — die 3 und
   * die 9 in vielen Schnitten, die 4 in manchen.
   */
  ZAHL: 1.05,
  /** Überschriften. Eine Zeile Text braucht weniger Luft als ein Absatz. */
  ENG: 1.2,
  /** Fliesstext und alles, was mehrzeilig gelesen wird. */
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
 * Der Rahmen einer Seite.
 *
 * WARUM DAS NICHT IN ABSTAND STEHT
 *
 * ABSTAND ist eine Skala: Schritte, aus denen sich Abstände zwischen
 * Elementen zusammensetzen. Die Werte hier sind keine Schritte, sondern Masse
 * für genau eine Sache — den Rand des Inhalts gegen das Gerät. Getrennt,
 * damit OBEN nicht als "der nächste Schritt nach XXL" gelesen und irgendwo
 * mitten im Bild verwendet wird.
 */
export const SEITE = {
  /**
   * Oben. Der Inhalt beginnt unter Statusleiste und Kamerainsel; deren
   * Unterkante liegt auf den aktuellen iPhones bei rund 54 dp.
   */
  OBEN: 56,
  /**
   * Oben auf dem Fahrt-Screen. Acht weniger, weil dort kein Titel steht,
   * sondern sofort ein grosser Block beginnt — und ein Block setzt optisch
   * höher an als eine Textzeile. Der Wert stand so schon im Code; er wird
   * hier benannt, nicht neu gewählt.
   */
  OBEN_FAHRT: 48,
  /**
   * Unten am Ende einer Bildlaufliste. Ohne das klebt das letzte Element am
   * Rand und sieht aus, als sei die Liste abgeschnitten.
   */
  UNTEN: 40,
  /**
   * Zwischen den grossen Blöcken des Fahrt-Screens (Tacho, Anlage, Status).
   * Grösser als jeder Schritt aus ABSTAND, weil diese drei Blöcke im
   * Vorbeischauen als getrennte Dinge erkennbar sein müssen.
   */
  BLOCK_FAHRT: 28,
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
  /** Knöpfe, Verweise, Eingaben. */
  S: 8,
  /** Karten und Banner. */
  M: 12,
  /** Für Punkte und das runde Tempolimit-Zeichen. */
  KREIS: 9999,
} as const;

/**
 * Buchstabenabstand, als Anteil des Schriftgrads.
 *
 * WARUM DAS EIN TOKEN IST UND KEINE KOSMETIK
 *
 * Grosse Zahlen und Überschriften kommen mit dem Standardabstand auseinander
 * gezogen daher — bei 120 dp Tachoziffern sichtbar. Die übliche Korrektur sind
 * −2 bis −3 Prozent des Schriftgrads; darunter beginnt es zu drängen.
 *
 * React Native nimmt `letterSpacing` in dp, nicht in Prozent. Deshalb ein
 * Faktor und die Funktion darunter, statt sieben von Hand gerechneter Zahlen,
 * die beim nächsten Ändern eines Schriftgrads still falsch werden.
 */
export const SPUR = {
  /** Ab diesem Grad wird enger gesetzt. Darunter bringt es nichts. */
  AB_GRAD: 32,
  /** Anteil des Schriftgrads, negativ. */
  ENG: -0.025,
  /** Versalien in Abschnittsüberschriften brauchen umgekehrt mehr Luft. */
  VERSALIEN: 1,
} as const;

/**
 * Buchstabenabstand für einen Schriftgrad.
 *
 * Unterhalb von SPUR.AB_GRAD gibt es keinen — Fliesstext enger zu setzen
 * macht ihn schwerer lesbar, und lesbar ist hier die einzige Anforderung.
 */
export function spur(fontSize: number): number {
  return fontSize >= SPUR.AB_GRAD ? Math.round(fontSize * SPUR.ENG * 10) / 10 : 0;
}

/**
 * Einzelmasse, die zu keiner Skala gehören.
 *
 * Was hier steht, ist die Grösse genau eines Dings. Deshalb kein gemeinsamer
 * Rhythmus und keine Abstufung — nur ein Name statt einer Zahl im Screen.
 */
export const MASS = {
  /**
   * Der pulsierende Statuspunkt neben der Statuszeile.
   *
   * Stand vorher auf 10 und lag damit neben dem Vierer-Raster. 12, weil es
   * das nächste Rastermass ist und der Punkt seine einzige Aufgabe — im
   * Augenwinkel zeigen, dass die App läuft — damit eher besser erfüllt.
   */
  PUNKT: 12,
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
  /**
   * Gedrückt. Ohne diese Rückmeldung weiss der Nutzer nicht, ob der Griff
   * gesessen hat — und im Auto greift man daneben. Es gibt auf einem
   * Berührungsbildschirm kein "darüber", also ist der gedrückte Zustand die
   * einzige Rückmeldung, die es überhaupt geben kann.
   *
   * 0,72 statt 0,5: Deutlich genug, um es aus dem Augenwinkel zu bemerken,
   * aber nicht so stark, dass die Fläche zu verschwinden scheint.
   */
  GEDRUECKT: 0.72,
  /** Abgeschaltetes Bedienelement. */
  INAKTIV: 0.4,
  /**
   * Der Tiefpunkt des Statuspulses. Unter INAKTIV, damit "läuft, gerade
   * dunkel" nicht mit "läuft nicht" verwechselt werden kann: Ein Punkt, der
   * schwächer wird als der abgeschaltete, ist eindeutig einer, der sich
   * bewegt.
   */
  PULS_TIEF: 0.35,
  /** Fläche unter einem geöffneten Blatt. Nur ausserhalb des Fahrt-Screens. */
  ABDECKUNG: 0.75,
} as const;

/**
 * Der Stil einer berührbaren Fläche, abhängig davon, ob sie gerade gedrückt
 * ist.
 *
 * Als Funktion und nicht als Konstante, weil React Native den Zustand nur an
 * eine Funktion übergibt. Sie an einer Stelle zu haben ist der Unterschied
 * zwischen "jeder Knopf reagiert" und "der Knopf, an den jemand gedacht hat,
 * reagiert" — vor dieser Änderung hatte genau EINE von siebzehn Flächen in
 * der App eine Rückmeldung.
 */
export function gedrueckt(
  zustand: { pressed: boolean },
  abgeschaltet = false,
): { opacity: number } {
  // Abgeschaltet zuerst: Eine Fläche, die nicht reagiert, darf auch nicht so
  // aussehen, als täte sie es. React Native gibt `disabled` nicht in den
  // Zustand hinein, deshalb der zweite Parameter.
  if (abgeschaltet) return { opacity: DECKKRAFT.INAKTIV };
  return { opacity: zustand.pressed ? DECKKRAFT.GEDRUECKT : DECKKRAFT.VOLL };
}

/**
 * Übergänge in ms. Kurz gehalten: Eine Warnung, die sich einblendet, kommt
 * später an als eine, die einfach da ist. Der Zustandswechsel ist die
 * Information, nicht die Bewegung dorthin.
 */
export const DAUER = {
  SOFORT: 0,
  KURZ: 120,
  NORMAL: 200,
  /**
   * Eine Halbwelle des Statuspulses — das einzige bewegte Element der App.
   *
   * Das ist kein Übergang, sondern ein Takt: 1200 ms hin, 1200 ms zurück
   * ergibt 25 Schläge pro Minute. Langsam genug, dass die Bewegung im
   * Augenwinkel nicht ablenkt, und schnell genug, dass ein Blick von einer
   * halben Sekunde die Änderung noch trifft.
   */
  PULS: 1200,
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
  readonly seite: typeof SEITE;
  readonly touch: typeof TOUCH;
  readonly radius: typeof RADIUS;
  readonly mass: typeof MASS;
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
    seite: SEITE,
    touch: TOUCH,
    radius: RADIUS,
    mass: MASS,
    linie: LINIE,
    effekte: EFFEKTE,
    deckkraft: DECKKRAFT,
    dauer: DAUER,
  };
}

/** Vorgabe, solange der Aufrufer den Modus nicht kennt. */
export const THEME_STANDARD: Theme = theme('tag');
