/**
 * Das Länder-Gate, Spec Abschnitt 2 und 10.1.
 *
 * Aufgabe: feststellen, in welchem Land das Gerät gerade ist, und daraus
 * ableiten, ob die Blitzerwarnung überhaupt laufen darf. Die Datei entscheidet
 * nichts über Recht — sie liest die Tabelle in config.LAENDER_GATE. Sie
 * entscheidet über Geografie, und zwar so, dass eine falsche Antwort nicht
 * zufällig die gefährliche Antwort ist.
 *
 * Warum kein Bounding-Box-Reverse-Geocoding: siehe Kopf von country-data.ts.
 * Kurz — die Boxen von DE, AT und CH überlappen sich über Hunderte von
 * Kilometern, und das Gate soll genau dort abschalten.
 */
import { LAENDER_GATE, type LandCode, type Warnmodus } from '../config';
import type { Fix } from '../types';
import { distanceToSegment } from './geo';
import {
  TOLERANZ_GRENZE_M,
  UMRISSE,
  UMRISS_CODES,
  type Punkt,
  type UmrissCode,
  inUnsichererZone,
  punktImUmriss,
  umrissFuer,
} from './country-data';

/**
 * Schwellwerte der Hysterese.
 *
 * ANMERKUNG ZUR ABLAGE: Nach Qualitätsvorgabe Abschnitt 5 gehören diese drei
 * Zahlen nach src/config.ts. Sie stehen hier, weil config.ts nicht zu dieser
 * Änderung gehört und von anderer Hand geschrieben wird. Beim nächsten
 * Anfassen von config.ts wandert der Block dorthin — die Namen bleiben, damit
 * der Umzug ein Verschieben und kein Umschreiben ist.
 */
export const LAND_HYSTERESE = {
  /**
   * So viele Fixes in Folge muss ein neues Land gelesen werden, bevor die
   * Warnung dort eingeschaltet wird. Bei einem Positionsintervall von
   * wenigen Sekunden sind das einige Sekunden Verzögerung — der Preis dafür,
   * dass ein einzelner Ausreisser die Warnung nicht scharf schaltet.
   */
  BESTAETIGENDE_FIXES: 5,

  /**
   * Und so weit muss die Position von der nächsten Landgrenze entfernt sein.
   *
   * DER WERT IST ABGELEITET, NICHT GEWÄHLT: das Doppelte der
   * Vereinfachungstoleranz der Umrisse an Landgrenzen. Er muss grösser sein
   * als deren Fehler, sonst prüft er sich selbst; und er darf nicht viel
   * grösser sein, sonst bleibt die Warnung weit hinter der Grenze noch aus.
   *
   * Warum das Doppelte und nicht das Einfache: Liegt die generierte Linie um
   * die volle Toleranz nach Osten verschoben, dann liegt die tatsächliche
   * Grenze 200 m westlich von ihr — ein Wechsel 200 m hinter der Linie wäre
   * dann ein Wechsel genau AUF der Grenze. Erst 400 m stellen sicher, dass
   * die Position auch im schlechtesten Fall der Vereinfachung im neuen Land
   * liegt.
   *
   * GEMESSEN an fixtures/grenze-kehl-strasbourg.gpx (Europabrücke Kehl ->
   * Strasbourg, 13,9 m/s, ein Fix je 14 m):
   *
   *   Schwellwert   Wechsel liegt hinter der Grenze
   *      3000 m                 2988 m
   *      2000 m                 1988 m
   *      1000 m                  987 m
   *       400 m                  389 m
   *
   * Der frühere Wert 3000 m schaltete die Zonenwarnung erst drei Kilometer
   * hinter dem Rhein frei — mitten in Strasbourg. Er stammte aus der Zeit der
   * handeingetragenen Linien, deren Fehler unbekannt war. Mit 400 m fällt der
   * Wechsel auf 389 m hinter der Grenze und damit in das geforderte Fenster
   * von 0 bis 500 m.
   *
   * Die Kopplung an TOLERANZ_GRENZE_M ist Absicht: Wird die Toleranz im
   * Generator geändert, wandert dieser Schwellwert mit, und der Test in
   * tests/gate.test.ts schlägt an, falls das Fenster dabei gerissen wird.
   */
  MINDESTABSTAND_GRENZE_M: 2 * TOLERANZ_GRENZE_M,

  /**
   * Fixes, die ungenauer sind als das, entscheiden nicht über das Land.
   * Deutlich grosszügiger als SPEEDOMETER.MAX_ACCURACY_M — hier geht es um
   * Kilometer bis zur Grenze, nicht um Meter für die Anzeige.
   */
  MAX_GENAUIGKEIT_M: 200,
} as const;

// --- Gate-Tabelle ---------------------------------------------------------

/**
 * Gehört dieser Code zur Gate-Tabelle in config?
 *
 * Object.keys verliert die Typinformation, deshalb ein Typprädikat statt
 * einer Zusicherung an der Aufrufstelle. Die Prüfung selbst ist echt: sie
 * schaut in dieselbe Tabelle, aus der LandCode abgeleitet ist.
 */
function istLandCode(code: string): code is LandCode {
  return Object.prototype.hasOwnProperty.call(LAENDER_GATE.LAENDER, code);
}

/** Umrisscode auf die Gate-Tabelle abbilden. null = kein Eintrag vorhanden. */
function gateLand(umriss: UmrissCode | null): LandCode | null {
  if (umriss === null) return null;
  return istLandCode(umriss) ? umriss : null;
}

/**
 * Darf die Warnung in diesem Land laufen?
 *
 * null bedeutet: Land nicht sicher bestimmbar — oder bestimmbar, aber ohne
 * geprüften Eintrag in der Tabelle. Beides führt in denselben Default.
 *
 * WARUM DER DEFAULT false IST
 *
 * In Deutschland, Österreich und der Schweiz ist der Betrieb einer
 * Einrichtung, die vor Geschwindigkeitsmessungen warnt, dem Fahrzeugführer
 * untersagt (§ 23 Abs. 1c StVO, § 98a KFG, Art. 57b SVG — Stand siehe
 * LAENDER_GATE.STAND). Diese drei Länder sind zugleich das gesamte
 * Kerngebiet dieser App. Ein Default "im Zweifel an" hiesse also: im
 * statistisch wahrscheinlichsten Fall läuft eine verbotene Funktion, und
 * zwar ausgerechnet dann, wenn die Ortung unsicher ist.
 *
 * Der umgekehrte Fehler — die Warnung bleibt in Frankreich aus, obwohl sie
 * dort zulässig wäre — kostet eine Funktion. Er kostet niemanden ein
 * Bussgeld. Die beiden Fehler sind nicht gleich viel wert, deshalb ist das
 * Gate nicht symmetrisch.
 *
 * KEINE RECHTSBERATUNG. Die Tabelle in config gehört vor einer
 * Veröffentlichung geprüft.
 */
export function warnungErlaubt(land: LandCode | null): boolean {
  return warnmodus(land) !== 'aus';
}

/**
 * Wie darf in diesem Land gewarnt werden?
 *
 * Die zweite Bedingung ist die Invariante aus config: Ein Eintrag, über dessen
 * Rechtslage GAR NICHTS bekannt ist, warnt nicht — egal was in `modus` steht.
 * Sie wird hier durchgesetzt und nicht bloss in der Tabelle vorausgesetzt,
 * damit ein neuer Eintrag mit vergessenem `modus: 'aus'` nicht durchrutscht.
 *
 * Die Schwelle liegt bei 'unklar' und nicht mehr bei 'belegt'. Der Grund steht
 * ausführlich im Kopf von LAENDER_GATE; kurz: 'strittig' heisst, dass wir die
 * Norm kennen und nur ihre Reichweite umstritten ist. Darüber kann der Fahrer
 * entscheiden, wenn man ihm den ungünstigeren Fall nennt. Bei 'unklar' wissen
 * wir gar nichts, und dann gibt es auch nichts vorzulegen.
 */
export function warnmodus(land: LandCode | null): Warnmodus {
  if (land === null) {
    return LAENDER_GATE.FALLBACK_WARNUNG_ERLAUBT ? 'punkt' : 'aus';
  }
  const eintrag = LAENDER_GATE.LAENDER[land];
  if (eintrag.status === 'unklar') return 'aus';
  return eintrag.modus;
}

/**
 * Trifft den FAHRZEUGFÜHRER hier ein Betriebsverbot?
 *
 * Getrennt von warnmodus(), weil es zwei verschiedene Fragen sind: was die App
 * tut, und was den Fahrer trifft, wenn er sie betreibt. Die erste ist eine
 * Produktentscheidung, die zweite eine Tatsache über das Recht.
 *
 * Von dieser Antwort hängt der dauerhafte Banner ab — und nur davon. Ein Land
 * ohne Fahrerverbot bekommt keinen, eines mit Fahrerverbot bekommt ihn, und er
 * lässt sich nicht abschalten.
 */
export function fahrerverbot(land: LandCode | null): 'ja' | 'nein' | 'unklar' {
  if (land === null) return 'unklar';
  return LAENDER_GATE.LAENDER[land].fahrerverbot;
}

/** Der Hinweistext für die App. Leer, wenn kein Eintrag existiert. */
export function landHinweis(land: LandCode | null): string | null {
  return land === null ? null : LAENDER_GATE.LAENDER[land].hinweis;
}

// --- Erkennung ------------------------------------------------------------

/** Steht für diesen Code ein Umriss bereit? */
function istUmrissCode(code: string): code is UmrissCode {
  // Die Zusicherung weitet nur den Elementtyp des Literal-Tupels auf string
  // auf, damit includes() einen beliebigen String annimmt.
  return (UMRISS_CODES as readonly string[]).includes(code);
}

/**
 * Roher Umriss-Treffer an dieser Position, ohne Gate und ohne Hysterese.
 *
 * Drei Wege führen zu null, und alle drei bedeuten dasselbe: keine Aussage.
 *  - Die Position liegt in keinem Umriss (ausserhalb des abgedeckten Gebiets).
 *  - Sie liegt in zweien. Die groben Linien überlappen sich dort, und welcher
 *    Umriss gewinnt, hinge an der Reihenfolge im Array. Das wäre eine
 *    Entscheidung ohne Grundlage, also fällt sie nicht.
 *  - Sie liegt in einer Zone, die kleiner ist als der Fehler der Linien
 *    (Andorra, Liechtenstein, Enklaven — siehe UNSICHERE_ZONEN).
 */
export function erkenneUmriss(lat: number, lon: number): UmrissCode | null {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  if (inUnsichererZone(lat, lon) !== null) return null;

  let treffer: UmrissCode | null = null;
  for (const umriss of UMRISSE) {
    if (!punktImUmriss(lat, lon, umriss)) continue;
    if (treffer !== null) return null;
    treffer = umriss.code;
  }
  return treffer;
}

/**
 * Land an dieser Position nach der Gate-Tabelle, ohne Hysterese.
 *
 * Für Länder mit Umriss, aber ohne Eintrag in config (BE, LU, DK, PL, CZ, IT)
 * kommt null zurück. Das ist kein Versehen: Ohne geprüfte Rechtslage gibt es
 * keine Erlaubnis, und der Umriss dient dort nur dazu, den Punkt nicht dem
 * falschen Nachbarn zuzuschlagen.
 */
export function detectCountry(lat: number, lon: number): LandCode | null {
  return gateLand(erkenneUmriss(lat, lon));
}

/**
 * Kürzester Abstand zur nächsten Landgrenze dieses Landes, in Metern.
 *
 * Küsten zählen nicht mit. Zählte man sie mit, käme in Marseille, Valencia
 * oder Den Haag nie ein Land zustande und die Warnung bliebe dort dauerhaft
 * aus — obwohl von der nächsten Landesgrenze keine Rede ist.
 *
 * Ohne Umriss kommt 0 zurück, nicht Unendlich: Ein unbekanntes Land ist kein
 * weit entferntes Land, und 0 sperrt den Wechsel, statt ihn durchzuwinken.
 */
export function abstandZurGrenze(lat: number, lon: number, code: UmrissCode): number {
  const umriss = umrissFuer(code);
  if (umriss === null) return 0;

  let kleinster = Number.POSITIVE_INFINITY;
  for (const linie of umriss.grenzlinien) {
    let vorher: Punkt | null = null;
    for (const jetzt of linie) {
      if (vorher !== null) {
        const d = distanceToSegment(lat, lon, vorher[0], vorher[1], jetzt[0], jetzt[1]);
        if (d < kleinster) kleinster = d;
      }
      vorher = jetzt;
    }
  }
  return kleinster;
}

// --- Hysterese ------------------------------------------------------------

/**
 * Warum der Status so lautet, wie er lautet. Nicht für die UI gedacht,
 * sondern für den Test und das Fehlerprotokoll: Ohne diese Angabe ist im
 * Nachhinein nicht zu unterscheiden, ob die Warnung aus war, weil das Land
 * es verbietet, oder weil die Ortung nichts hergab.
 */
export type LandGrund =
  | 'bestaetigt'
  | 'unbestimmt'
  | 'wartet_bestaetigung'
  | 'grenznah'
  | 'ungenau'
  | 'kein_gate_eintrag';

export type LandStatus = {
  /** Erkannter Umriss, auch wenn die Gate-Tabelle ihn nicht kennt. */
  readonly umriss: UmrissCode | null;
  /** Land nach der Gate-Tabelle. null = keine gesicherte Einstufung. */
  readonly land: LandCode | null;
  readonly warnungErlaubt: boolean;
  readonly grund: LandGrund;
};

/** Zustand über eine Fahrt hinweg. Vom Aufrufer gehalten, nicht global. */
export type LandZustand = {
  /** Der Umriss, den die App gerade zugrunde legt. */
  bestaetigt: UmrissCode | null;
  /** Ein abweichender Umriss, der auf Bestätigung wartet. */
  kandidat: UmrissCode | null;
  kandidatTreffer: number;
};

export function createLandZustand(): LandZustand {
  return { bestaetigt: null, kandidat: null, kandidatTreffer: 0 };
}

function status(zustand: LandZustand, grund: LandGrund): LandStatus {
  const umriss = zustand.bestaetigt;
  const land = gateLand(umriss);
  // Ein erkanntes Land ohne Eintrag in der Tabelle ist etwas anderes als eine
  // gescheiterte Ortung, auch wenn die Warnung in beiden Fällen aus bleibt.
  const echterGrund: LandGrund = grund === 'bestaetigt' && land === null ? 'kein_gate_eintrag' : grund;
  return { umriss, land, warnungErlaubt: warnungErlaubt(land), grund: echterGrund };
}

/** Aktueller Stand, ohne einen neuen Fix zu verarbeiten. */
export function leseLand(zustand: LandZustand): LandStatus {
  return status(zustand, zustand.bestaetigt === null ? 'unbestimmt' : 'bestaetigt');
}

/**
 * Eine Position verarbeiten und den Landstatus fortschreiben.
 *
 * DIE HYSTERESE IST MIT ABSICHT UNSYMMETRISCH.
 *
 * Das Problem, gegen das sie gebaut ist: Auf einer Fahrt entlang der Grenze —
 * die B9 bei Lauterbourg, die A5 bei Weil am Rhein, die Rheinbrücken bei
 * Strasbourg — liefert die Erkennung im Sekundentakt abwechselnd beide
 * Länder. Ohne Dämpfung schaltete die Warnung im selben Takt an und aus und
 * sagte jedes Mal etwas an. Das ist unbenutzbar.
 *
 * Die naheliegende Lösung, jeden Wechsel gleich zu bremsen, wäre aber falsch:
 * Sie hielte die Warnung nach dem Grenzübertritt nach Deutschland noch einige
 * Sekunden lang scharf — also genau dort, wo sie nicht laufen darf.
 *
 * Deshalb zwei Geschwindigkeiten:
 *  - Eine Lesung, die die Warnung ABSCHALTEN würde (Land mit warnung: false,
 *    Land ohne Eintrag, oder gar kein Ergebnis), gilt sofort. Ohne Zähler,
 *    ohne Grenzabstand.
 *  - Eine Lesung, die sie EINSCHALTEN würde, muss sich qualifizieren: mehrere
 *    Fixes in Folge und ein Mindestabstand zur Landgrenze.
 *
 * Das Ergebnis an der Grenze ist nicht Flackern, sondern ein stabiles Aus. Es
 * schaltet einmal ab und bleibt aus, bis die Position ein Stück weit im
 * erlaubten Land liegt. Der Preis: eine einzelne Fehllesung mitten in
 * Frankreich unterbricht die Warnung kurz. Das ist die Richtung, in die ein
 * Fehler fallen soll.
 */
export function aktualisiereLand(
  zustand: LandZustand,
  fix: Pick<Fix, 'lat' | 'lon' | 'accuracy'>,
): LandStatus {
  // Eine fehlende Genauigkeitsangabe wird akzeptiert. Manche Geräte liefern
  // sie im Hintergrundmodus gar nicht, und der Fix deshalb zu verwerfen
  // hiesse, die Warnung dort dauerhaft in den Default fallen zu lassen.
  if (fix.accuracy != null && fix.accuracy > LAND_HYSTERESE.MAX_GENAUIGKEIT_M) {
    // Der Kandidatenzähler bleibt unangetastet: Eine einzelne schlechte
    // Messung soll eine laufende Bestätigung nicht auf null zurückwerfen.
    return status(zustand, 'ungenau');
  }

  const gelesen = erkenneUmriss(fix.lat, fix.lon);

  if (gelesen === zustand.bestaetigt) {
    zustand.kandidat = null;
    zustand.kandidatTreffer = 0;
    return status(zustand, gelesen === null ? 'unbestimmt' : 'bestaetigt');
  }

  // Der schnelle Weg: alles, was die Warnung abschaltet, gilt sofort.
  if (!warnungErlaubt(gateLand(gelesen))) {
    zustand.bestaetigt = gelesen;
    zustand.kandidat = null;
    zustand.kandidatTreffer = 0;
    return status(zustand, gelesen === null ? 'unbestimmt' : 'bestaetigt');
  }

  // Der langsame Weg: einschalten nur gegen Bestätigung.
  if (zustand.kandidat !== gelesen) {
    zustand.kandidat = gelesen;
    zustand.kandidatTreffer = 1;
  } else {
    zustand.kandidatTreffer += 1;
  }

  if (zustand.kandidatTreffer < LAND_HYSTERESE.BESTAETIGENDE_FIXES) {
    return status(zustand, 'wartet_bestaetigung');
  }

  const abstand =
    gelesen === null
      ? // Ohne Umriss gibt es keine Grenze, zu der sich ein Abstand messen
        // liesse. Erreichbar nur, wenn jemand den Fallback in config auf
        // "erlaubt" stellt — dann soll die Prüfung nicht stillschweigend
        // durchfallen.
        Number.POSITIVE_INFINITY
      : abstandZurGrenze(fix.lat, fix.lon, gelesen);

  if (abstand < LAND_HYSTERESE.MINDESTABSTAND_GRENZE_M) {
    // Der Zähler bleibt stehen. Sobald der Abstand passt, greift der Wechsel
    // beim nächsten Fix, ohne dass wieder von vorn gezählt wird.
    return status(zustand, 'grenznah');
  }

  zustand.bestaetigt = gelesen;
  zustand.kandidat = null;
  zustand.kandidatTreffer = 0;
  return status(zustand, 'bestaetigt');
}

// --- Konsistenz -----------------------------------------------------------

/**
 * Länder, die die Gate-Tabelle kennt, für die aber kein Umriss vorliegt.
 *
 * Ein solcher Eintrag ist stumm wirkungslos: Das Land käme nie zustande und
 * fiele immer in den Default. Der Test prüft, dass die Liste leer ist —
 * gemeldet wird das hier und nicht durch einen Absturz beim Start, denn eine
 * App, die wegen einer Tabellenlücke nicht startet, warnt auch nicht.
 */
export function laenderOhneUmriss(): string[] {
  return Object.keys(LAENDER_GATE.LAENDER).filter((code) => !istUmrissCode(code));
}
