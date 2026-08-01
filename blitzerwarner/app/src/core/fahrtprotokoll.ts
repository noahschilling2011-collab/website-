/**
 * Der Fahrtenschreiber — die Instrumentierung für die eine Testfahrt.
 *
 * WOZU
 *
 * Die Phasen 2, 4 und 5 sind blockiert, weil drei Dinge nur im Auto messbar
 * sind: 20 Minuten lückenloses Tracking bei ausgeschaltetem Display, der
 * Akkuverbrauch gegen das Ziel unter 3 %/h, und der Vergleich gegen den
 * Fahrzeugtacho. Ohne Aufzeichnung liefert eine Testfahrt davon nichts —
 * "es lief gut" ist kein Messwert.
 *
 * Diese Datei verwandelt eine Fahrt in alle drei Antworten.
 *
 * WARUM NICHT DAS FEHLERPROTOKOLL
 *
 * Das fasst ERROR_LOG.MAX_ENTRIES = 200 Einträge und ist für Fehler gedacht.
 * Im Annäherungsmodus kommt alle 25 m eine Position; bei 100 km/h wäre es
 * nach drei Minuten voll — und hätte die Fehler verdrängt, wegen derer es
 * existiert.
 *
 * DATENSCHUTZ
 *
 * Hier entsteht eine vollständige Bewegungsspur. Genau das tut die App laut
 * README sonst nicht, und das bleibt auch so: Der Schreiber hängt hinter
 * einem eigenen, standardmässig ausgeschalteten Schalter, das Protokoll lebt
 * nur im Arbeitsspeicher, wird beim Ausschalten gelöscht und geht nirgendwo
 * hin — es gibt nichts, wohin es gehen könnte.
 *
 * Reine Funktionen über explizitem Zustand, wie warn.ts und zone.ts.
 */
import { FAHRTPROTOKOLL } from '../config';
import type { Warnmodus } from '../config';
import type { Modus as StrategieModus } from '../location/strategy';

/**
 * Eine Zeile. Genau die Felder, aus denen sich die drei offenen Fragen
 * beantworten lassen — und keine weiteren.
 */
export type Fahrteintrag = {
  readonly t: number;
  readonly lat: number;
  readonly lon: number;
  /** m/s, null wenn das Gerät nichts liefert. */
  readonly speed: number | null;
  readonly accuracy: number | null;
  readonly course: number | null;
  /** Akku-Strategie zum Zeitpunkt des Fixes. Für den Zeitanteil je Modus. */
  readonly strategie: StrategieModus;
  /** Was das Länder-Gate erlaubt hat. */
  readonly warnmodus: Warnmodus;
  /** Distanz zur nächsten bekannten Anlage in Metern, null wenn keine im Gitter. */
  readonly naechsteM: number | null;
  /** Wurde bei diesem Fix gewarnt oder ein Zonenhinweis gegeben? */
  readonly gewarnt: boolean;
  /**
   * Abstand zum vorherigen Fix in ms. null beim ersten Eintrag — dort gibt es
   * keinen Vorgänger, und 0 wäre eine Behauptung.
   */
  readonly abstandMs: number | null;
  /** Liegt `abstandMs` über FAHRTPROTOKOLL.LUECKE_AB_MS? */
  readonly luecke: boolean;
};

/** Was der Schreiber liefert; abstandMs und luecke rechnet er selbst. */
export type NeuerEintrag = Omit<Fahrteintrag, 'abstandMs' | 'luecke'>;

/**
 * Der Ringpuffer.
 *
 * Ein festes Array mit Schreibzeiger statt push/shift: shift() auf einem
 * Array mit 10000 Einträgen kopiert bei jedem Fix das ganze Array um. Im
 * Hintergrund-Task, der ohnehin unter Beobachtung des Systems läuft, ist das
 * die falsche Sorte Arbeit.
 */
export type Fahrtprotokoll = {
  eintraege: (Fahrteintrag | undefined)[];
  /** Wohin der nächste Eintrag geht. */
  index: number;
  /** Hat der Puffer schon einmal übergelaufen? Dann ist er voll. */
  uebergelaufen: boolean;
  /** Zeitstempel des ersten je geschriebenen Eintrags. Für den Kopf des Exports. */
  startT: number | null;
  /** Zeitstempel des letzten. */
  endeT: number | null;
  /** Wie viele Einträge der Ring seit dem Start verdrängt hat. */
  verdraengt: number;
  /** Zeit des letzten Eintrags, für die Lückenrechnung. Auch nach Verdrängung. */
  letzteT: number | null;
};

export function createFahrtprotokoll(): Fahrtprotokoll {
  return {
    eintraege: new Array<Fahrteintrag | undefined>(FAHRTPROTOKOLL.MAX_EINTRAEGE),
    index: 0,
    uebergelaufen: false,
    startT: null,
    endeT: null,
    verdraengt: 0,
    letzteT: null,
  };
}

/**
 * Eine Position aufzeichnen.
 *
 * Die Lücke wird BEIM SCHREIBEN gerechnet und nicht beim Auswerten. Grund:
 * Der Ring verdrängt alte Einträge, und mit ihnen ginge der Abstand zum
 * jeweils vorherigen verloren. Ein Export aus einem übergelaufenen Puffer
 * würde die Lücke am Schnitt dann als riesig oder als gar nicht vorhanden
 * ausweisen — je nachdem, was zufällig noch drinsteht.
 */
export function schreibe(protokoll: Fahrtprotokoll, eintrag: NeuerEintrag): Fahrteintrag {
  const abstandMs = protokoll.letzteT === null ? null : eintrag.t - protokoll.letzteT;
  const vollstaendig: Fahrteintrag = {
    ...eintrag,
    abstandMs,
    luecke: abstandMs !== null && abstandMs > FAHRTPROTOKOLL.LUECKE_AB_MS,
  };

  if (protokoll.eintraege[protokoll.index] !== undefined) protokoll.verdraengt++;
  protokoll.eintraege[protokoll.index] = vollstaendig;

  protokoll.index = (protokoll.index + 1) % FAHRTPROTOKOLL.MAX_EINTRAEGE;
  if (protokoll.index === 0) protokoll.uebergelaufen = true;

  if (protokoll.startT === null) protokoll.startT = eintrag.t;
  protokoll.endeT = eintrag.t;
  protokoll.letzteT = eintrag.t;

  return vollstaendig;
}

/** Die Einträge in Fahrtreihenfolge, ältester zuerst. */
export function eintraege(protokoll: Fahrtprotokoll): Fahrteintrag[] {
  const alle = protokoll.eintraege;
  const geordnet = protokoll.uebergelaufen
    ? [...alle.slice(protokoll.index), ...alle.slice(0, protokoll.index)]
    : alle.slice(0, protokoll.index);
  return geordnet.filter((e): e is Fahrteintrag => e !== undefined);
}

/**
 * Alles vergessen.
 *
 * Wird beim Ausschalten des Schalters aufgerufen, nicht nur beim Start einer
 * neuen Fahrt: Wer den Schreiber abschaltet, will die Spur los sein, nicht
 * bloss keine neue mehr.
 */
export function leere(protokoll: Fahrtprotokoll): void {
  protokoll.eintraege = new Array<Fahrteintrag | undefined>(FAHRTPROTOKOLL.MAX_EINTRAEGE);
  protokoll.index = 0;
  protokoll.uebergelaufen = false;
  protokoll.startT = null;
  protokoll.endeT = null;
  protokoll.verdraengt = 0;
  protokoll.letzteT = null;
}

// --- Export ---------------------------------------------------------------

/** Die Spalten. Reihenfolge und Namen sind der Vertrag zu scripts/analyze-drive.ts. */
export const SPALTEN = [
  't_iso', 'lat', 'lon', 'speed_ms', 'accuracy_m', 'course_deg',
  'strategie', 'warnmodus', 'naechste_m', 'gewarnt', 'abstand_ms', 'luecke',
] as const;

/** Zeichen, mit dem Kopfzeilen beginnen. Auch von analyze-drive.ts erwartet. */
export const KOPF_PRAEFIX = '#';

const zahl = (n: number | null, stellen: number): string =>
  n === null ? '' : n.toFixed(stellen);

/**
 * Das Protokoll als CSV.
 *
 * Der Kopf steht in `#`-Zeilen über der Tabelle. Ein Tabellenprogramm zeigt
 * sie als eine Spalte an, was hinnehmbar ist; die Alternative — den Kopf
 * weglassen — hiesse, Start- und Endzeit und damit die Akkufrage zu
 * verlieren.
 *
 * DIE AKKUZEILEN SIND ABSICHTLICH LEER. Der Fahrer trägt den Akkustand vor
 * und nach der Fahrt aus den Systemeinstellungen ein. Das ist der Weg ohne
 * neue Abhängigkeit; die geprüfte Alternative steht im README.
 *
 * Zeitstempel in UTC nach ISO 8601, wie im Fehlerprotokoll und aus demselben
 * Grund: ohne Locale-Bibliothek lesbar, auch aus einer anderen Zeitzone.
 */
export function alsCsv(protokoll: Fahrtprotokoll): string {
  const zeilen = eintraege(protokoll);
  const dauerMs =
    protokoll.startT !== null && protokoll.endeT !== null
      ? protokoll.endeT - protokoll.startT
      : 0;

  const luecken = zeilen.filter((e) => e.luecke);
  const kopf = [
    'Static — Fahrtprotokoll',
    '',
    `Start (UTC):        ${protokoll.startT === null ? '—' : new Date(protokoll.startT).toISOString()}`,
    `Ende (UTC):         ${protokoll.endeT === null ? '—' : new Date(protokoll.endeT).toISOString()}`,
    `Dauer:              ${(dauerMs / 60000).toFixed(1)} min`,
    `Positionen:         ${zeilen.length}`,
    `davon Lücken:       ${luecken.length}  (Schwelle ${FAHRTPROTOKOLL.LUECKE_AB_MS / 1000} s)`,
    `verdrängt:          ${protokoll.verdraengt}` +
      (protokoll.verdraengt > 0
        ? '  ACHTUNG: Der Ringpuffer war voll, der Anfang der Fahrt fehlt.'
        : ''),
    '',
    'Vom Fahrer auszufüllen — aus den Systemeinstellungen ablesen:',
    'Akku bei Start (%): ',
    'Akku bei Ende (%):  ',
    '',
    'Auswertung: npx tsx scripts/analyze-drive.ts <diese-datei>',
  ].map((z) => `${KOPF_PRAEFIX} ${z}`.trimEnd());

  const tabelle = zeilen.map((e) => [
    new Date(e.t).toISOString(),
    e.lat.toFixed(6),
    e.lon.toFixed(6),
    zahl(e.speed, 2),
    zahl(e.accuracy, 1),
    zahl(e.course, 1),
    e.strategie,
    e.warnmodus,
    zahl(e.naechsteM, 0),
    e.gewarnt ? '1' : '0',
    e.abstandMs === null ? '' : String(e.abstandMs),
    e.luecke ? '1' : '0',
  ].join(','));

  return [...kopf, SPALTEN.join(','), ...tabelle].join('\n') + '\n';
}
