/**
 * Fehlerprotokoll, Qualitätsvorgabe 1d.
 *
 * Das ist der Ersatz für den Absturzberichtsdienst, den es hier nicht gibt.
 * Und zwar nicht aus Sparsamkeit: Ein Crashlytics oder Sentry im Paket wäre
 * eine Netzverbindung und eine Datenweitergabe, und beides ist genau das, was
 * die App verspricht nicht zu tun. Also bleibt das Protokoll auf dem Gerät.
 * Der Nutzer kann es lesen, kopieren und löschen — und niemand sonst kommt
 * daran. Es gibt keinen Versandpfad, auch keinen abgeschalteten.
 *
 * Deshalb steht in diesem Modul auch kein einziger Aufruf, der etwas
 * verschickt, und keine Kennung, die ein Gerät wiedererkennbar macht.
 *
 * Kein console.log: Ein Fehler, der nur in der Entwicklerkonsole steht, ist
 * auf dem Gerät eines Nutzers nicht vorhanden.
 */
import { ERROR_LOG } from '../config';

/**
 * Ebenen. 'error' heisst: etwas funktioniert nicht mehr. 'warn': es läuft,
 * aber schlechter als vorgesehen. 'info': Verlauf, der beim Verstehen hilft
 * (Start, Wechsel des Ortungsmodus).
 */
const EBENEN = ['info', 'warn', 'error'] as const;
export type LogLevel = (typeof EBENEN)[number];

/**
 * Bereiche. Geschlossene Liste statt freiem Text, aus demselben Grund wie bei
 * StatusKey in strings.ts: Ein Feld, in das jeder schreiben darf, was er will,
 * ist beim Suchen nach dem dritten Modul wertlos.
 */
const BEREICHE = [
  'start',
  'daten',
  'position',
  'hintergrund',
  'warnung',
  'audio',
  'speicher',
  'einstellungen',
] as const;
export type LogArea = (typeof BEREICHE)[number];

export type LogEntry = {
  /** Zeitstempel in ms seit Epoch. */
  readonly t: number;
  readonly level: LogLevel;
  readonly area: LogArea;
  /** Was passiert ist. Eine Zeile, technisch, ohne Anrede. */
  readonly message: string;
  /** Der zugehörige Fehlertext, falls es einen gab. */
  readonly detail: string | null;
};

/**
 * Die Schnittstelle zum dauerhaften Speicher, zugeschnitten auf das, was
 * AsyncStorage kann. Als Interface, damit dieses Modul nichts von React Native
 * weiss und der Test es mit einem Attrappen-Speicher füttern kann — inklusive
 * eines Speichers, der absichtlich scheitert. Genau dieser Fall ist der
 * interessante und lässt sich auf einem Gerät kaum herstellen.
 */
export interface KeyValueStore {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/** Schlüssel im Gerätespeicher. Die Version steht drin, damit ein späteres Format das alte nicht falsch liest. */
export const LOG_STORAGE_KEY = 'blitzerwarner.fehlerprotokoll.v1';

/**
 * Obergrenze für Nachricht und Fehlertext in Zeichen.
 *
 * Ein Stapelverlauf kann Kilobytes lang sein; 200 solcher Einträge sprengen
 * den Gerätespeicher und machen das Protokoll unlesbar. Der Wert gehört
 * eigentlich neben ERROR_LOG.MAX_ENTRIES in die config.ts und steht nur hier,
 * weil diese Datei nicht angefasst werden darf.
 */
export const MAX_TEXT_LAENGE = 300;

/** Fällt beim Kürzen an. Bewusst am Ende, damit der Anfang lesbar bleibt. */
const GEKUERZT = '…';

/**
 * Meldungen, die dieses Modul selbst erzeugt.
 *
 * Nicht in strings.ts, obwohl der Nutzer sie im Protokoll zu sehen bekommt:
 * Das Protokoll ist eine technische Aufzeichnung und keine Bildschirmtexte.
 * Und diese beiden Sätze müssen ausgerechnet dann noch stimmen, wenn der
 * Speicher nicht mehr mitspielt.
 */
const EIGENE_MELDUNG = {
  speichernFehlgeschlagen: 'Fehlerprotokoll konnte nicht gespeichert werden',
  lesenFehlgeschlagen: 'Gespeichertes Fehlerprotokoll war nicht lesbar und wurde verworfen',
} as const;

// --- Helfer ---------------------------------------------------------------

/**
 * Text für eine Protokollzeile aufbereiten: Zeilenumbrüche raus, gekürzt.
 *
 * Ein Eintrag ist genau eine Zeile. Das ist keine Kosmetik — ein Protokoll,
 * dessen Einträge über mehrere Zeilen laufen, lässt sich weder überfliegen
 * noch beim Kopieren sinnvoll zusammenhalten.
 */
function einzeilig(text: string): string {
  const flach = text.replace(/\s+/g, ' ').trim();
  if (flach.length <= MAX_TEXT_LAENGE) return flach;
  return flach.slice(0, MAX_TEXT_LAENGE - GEKUERZT.length) + GEKUERZT;
}

/**
 * Aus einem geworfenen Wert einen Text machen.
 *
 * `unknown` und nicht `Error`, weil in JavaScript alles geworfen werden darf
 * und Bibliotheken davon reichlich Gebrauch machen. Ein unbrauchbarer Wert
 * ergibt lieber "[object Object]" als gar nichts — dass etwas geworfen wurde,
 * ist die halbe Information.
 */
export function fehlerText(fehler: unknown): string | null {
  if (fehler === null || fehler === undefined) return null;

  if (fehler instanceof Error) {
    const text = fehler.name === 'Error' ? fehler.message : `${fehler.name}: ${fehler.message}`;
    return einzeilig(text.length > 0 ? text : fehler.name);
  }
  if (typeof fehler === 'string') {
    return fehler.length > 0 ? einzeilig(fehler) : null;
  }
  if (typeof fehler === 'number' || typeof fehler === 'boolean') {
    return String(fehler);
  }

  try {
    const json = JSON.stringify(fehler);
    return json === undefined ? Object.prototype.toString.call(fehler) : einzeilig(json);
  } catch {
    // Zirkuläre Verweise lassen JSON.stringify werfen. Dann eben die grobe
    // Auskunft — der Versuch, den Fehlertext zu bilden, darf nicht selbst
    // zum Fehler werden.
    return Object.prototype.toString.call(fehler);
  }
}

function istEbene(wert: unknown): wert is LogLevel {
  return typeof wert === 'string' && (EBENEN as readonly string[]).includes(wert);
}

function istBereich(wert: unknown): wert is LogArea {
  return typeof wert === 'string' && (BEREICHE as readonly string[]).includes(wert);
}

function istObjekt(wert: unknown): wert is Record<string, unknown> {
  return typeof wert === 'object' && wert !== null && !Array.isArray(wert);
}

/** Einen gespeicherten Eintrag zurücklesen, oder null, wenn er nicht passt. */
function leseEintrag(roh: unknown): LogEntry | null {
  if (!istObjekt(roh)) return null;

  const t = roh['t'];
  const level = roh['level'];
  const area = roh['area'];
  const message = roh['message'];
  const detail = roh['detail'];

  if (typeof t !== 'number' || !Number.isFinite(t)) return null;
  if (!istEbene(level) || !istBereich(area)) return null;
  if (typeof message !== 'string') return null;
  if (detail !== null && detail !== undefined && typeof detail !== 'string') return null;

  return { t, level, area, message, detail: detail ?? null };
}

/** Breite der Spalten im Textexport, aus den Listen abgeleitet statt geraten. */
const EBENE_BREITE = Math.max(...EBENEN.map((e) => e.length));
const BEREICH_BREITE = Math.max(...BEREICHE.map((b) => b.length));

/**
 * Eine Zeile des Exports.
 *
 * Zeitstempel in UTC nach ISO 8601. Nicht die Ortszeit: Der Text soll ohne
 * Zusatzwissen lesbar sein, auch wenn ihn jemand aus einer anderen Zeitzone
 * liest, und ISO braucht dafür keine Locale-Bibliothek.
 *
 * Die Feldnamen bleiben englisch und unübersetzt (INFO/WARN/ERROR). Das sind
 * technische Marken, keine Bildschirmtexte — sie gehören deshalb nicht nach
 * strings.ts.
 */
function zeile(eintrag: LogEntry): string {
  const zeit = new Date(eintrag.t).toISOString();
  const ebene = eintrag.level.toUpperCase().padEnd(EBENE_BREITE);
  const bereich = eintrag.area.padEnd(BEREICH_BREITE);
  const kopf = `${zeit} ${ebene} ${bereich} ${eintrag.message}`;
  return eintrag.detail === null ? kopf : `${kopf} | ${eintrag.detail}`;
}

export type ErrorLogOptions = {
  /** Ohne Speicher lebt das Protokoll nur im Arbeitsspeicher. */
  store?: KeyValueStore;
  /** Vorbelegt mit ERROR_LOG.MAX_ENTRIES. */
  maxEntries?: number;
  key?: string;
  /** Einspeisbare Uhr, damit Tests nicht auf echte Zeit angewiesen sind. */
  now?: () => number;
};

/**
 * Ringpuffer der letzten Einträge, im Arbeitsspeicher, mit Persistenz
 * nebenher.
 *
 * Der Puffer ist bewusst ein schlichtes Array mit Abschneiden am Anfang und
 * kein echter Ringpuffer mit Schreibzeiger: Bei 200 Einträgen ist das
 * Umkopieren nicht messbar, und der Code bleibt lesbar. Ein Protokoll, dessen
 * Reihenfolge man erst ausrechnen muss, ist beim Suchen nach einem Fehler das
 * Letzte, was man gebrauchen kann.
 */
export class ErrorLog {
  private eintraege: LogEntry[] = [];
  private store: KeyValueStore | null;
  private readonly max: number;
  private readonly key: string;
  private readonly now: () => number;

  /** Reihe der Schreibvorgänge. Ein Schreibvorgang nach dem anderen. */
  private kette: Promise<void> = Promise.resolve();
  private schmutzig = false;
  private loeschAuftrag = false;
  private speicherGestoert = false;

  constructor(options: ErrorLogOptions = {}) {
    this.store = options.store ?? null;
    this.key = options.key ?? LOG_STORAGE_KEY;
    this.now = options.now ?? (() => Date.now());

    const gewuenscht = options.maxEntries;
    this.max =
      gewuenscht !== undefined && Number.isFinite(gewuenscht) && gewuenscht >= 0
        ? Math.floor(gewuenscht)
        : ERROR_LOG.MAX_ENTRIES;
  }

  // --- Schreiben ----------------------------------------------------------

  /**
   * Einen Eintrag anlegen. Gibt ihn zurück, damit der Aufrufer ihn nicht
   * zweimal formulieren muss.
   *
   * Wirft nicht. Diese Methode wird aus Fehlerbehandlungen heraus aufgerufen;
   * ein Protokoll, das dort selbst wirft, verdeckt den eigentlichen Fehler.
   */
  add(level: LogLevel, area: LogArea, message: string, fehler?: unknown): LogEntry {
    const eintrag: LogEntry = {
      t: this.now(),
      level,
      area,
      message: einzeilig(message),
      detail: fehlerText(fehler),
    };
    this.haengeAn(eintrag);
    this.schmutzig = true;
    this.planeSchreiben();
    return eintrag;
  }

  info(area: LogArea, message: string, fehler?: unknown): LogEntry {
    return this.add('info', area, message, fehler);
  }

  warn(area: LogArea, message: string, fehler?: unknown): LogEntry {
    return this.add('warn', area, message, fehler);
  }

  error(area: LogArea, message: string, fehler?: unknown): LogEntry {
    return this.add('error', area, message, fehler);
  }

  /** Anhängen und vorne abschneiden, ohne Persistenz anzustossen. */
  private haengeAn(eintrag: LogEntry): void {
    if (this.max === 0) return;
    this.eintraege.push(eintrag);
    if (this.eintraege.length > this.max) {
      this.eintraege.splice(0, this.eintraege.length - this.max);
    }
  }

  // --- Lesen --------------------------------------------------------------

  /**
   * Alle Einträge, ältester zuerst. Eine Kopie: Der Puffer gehört diesem
   * Objekt, und ein von aussen veränderter Verlauf wäre kein Verlauf mehr.
   * Wer die neuesten oben will, dreht die Liste in der Anzeige um.
   */
  entries(): readonly LogEntry[] {
    return this.eintraege.slice();
  }

  get size(): number {
    return this.eintraege.length;
  }

  /**
   * Konnte zuletzt nicht gespeichert werden? Für den Hinweis
   * strings.fehler.keinSpeicherplatz. Das Protokoll läuft im Arbeitsspeicher
   * weiter, es geht nur beim nächsten Start verloren.
   */
  get storageFailed(): boolean {
    return this.speicherGestoert;
  }

  /**
   * Das Protokoll als Text, eine Zeile je Eintrag, ältester zuerst.
   *
   * Für den Knopf, mit dem der Nutzer es in die Zwischenablage legt. Das
   * Verschicken macht danach er, mit dem Werkzeug seiner Wahl, an den
   * Empfänger seiner Wahl — die App kennt keinen.
   *
   * Leeres Protokoll ergibt einen leeren Text; die Anzeige nimmt dafür
   * strings.leer.keineFehlerText.
   */
  toText(): string {
    return this.eintraege.map(zeile).join('\n');
  }

  // --- Persistenz ---------------------------------------------------------

  /**
   * Speicher nachträglich verbinden, gespeicherte Einträge einlesen und den
   * bisherigen Verlauf sichern.
   *
   * Nötig, weil beim App-Start schon protokolliert wird, bevor AsyncStorage
   * bereitsteht — die frühen Einträge sind die interessanten.
   */
  async attachStore(store: KeyValueStore): Promise<void> {
    this.store = store;
    const hatteEintraege = this.eintraege.length > 0;
    await this.load();
    if (hatteEintraege) {
      this.schmutzig = true;
      this.planeSchreiben();
    }
    await this.flush();
  }

  /**
   * Gespeicherte Einträge einlesen und mit den vorhandenen zusammenführen,
   * nach Zeit sortiert.
   */
  async load(): Promise<void> {
    const store = this.store;
    if (store === null) return;

    let roh: string | null;
    try {
      roh = await store.getItem(this.key);
    } catch (fehler) {
      this.merkeSpeicherfehler(fehler);
      return;
    }
    if (roh === null) return;

    const gelesen = this.entpacke(roh);
    if (gelesen === null) {
      // Kaputter Inhalt wird verworfen, aber nicht verschwiegen — sonst steht
      // der Nutzer vor einem leeren Protokoll und hält es für "keine Fehler".
      this.haengeAn({
        t: this.now(),
        level: 'warn',
        area: 'speicher',
        message: EIGENE_MELDUNG.lesenFehlgeschlagen,
        detail: null,
      });
      this.schmutzig = true;
      this.planeSchreiben();
      return;
    }

    // Gespeicherte zuerst, dann die bereits im Speicher gesammelten. Bei
    // gleichem Zeitstempel bleibt diese Reihenfolge erhalten, weil sort()
    // seit ES2019 stabil ist.
    const zusammen = [...gelesen, ...this.eintraege].sort((a, b) => a.t - b.t);
    this.eintraege = zusammen.slice(Math.max(0, zusammen.length - this.max));
  }

  /** Rohtext zu Einträgen. null heisst: unbrauchbar, nicht bloss leer. */
  private entpacke(roh: string): LogEntry[] | null {
    let gelesen: unknown;
    try {
      gelesen = JSON.parse(roh);
    } catch {
      // Abgeschnittene Datei nach einem harten Abschuss der App. Der Aufrufer
      // legt einen Vermerk an; hier ist nur zu entscheiden, ob es taugt.
      return null;
    }
    if (!Array.isArray(gelesen)) return null;

    const liste: readonly unknown[] = gelesen;
    const eintraege: LogEntry[] = [];
    for (const wert of liste) {
      const eintrag = leseEintrag(wert);
      // Einzelne kaputte Einträge überspringen statt alles zu verwerfen: Der
      // Rest des Verlaufs ist zu wertvoll, um ihn wegen einer Zeile zu opfern.
      if (eintrag !== null) eintraege.push(eintrag);
    }
    return eintraege;
  }

  /**
   * Alles löschen, auch aus dem Gerätespeicher.
   *
   * Kein Zurückholen, keine Kopie an anderer Stelle — das ist die Zusage aus
   * strings.datenschutz.lokaleDaten.
   */
  clear(): void {
    this.eintraege = [];
    this.schmutzig = false;
    this.loeschAuftrag = true;
    this.planeSchreiben();
  }

  /**
   * Warten, bis alles Angefallene geschrieben ist.
   *
   * Beim Wechsel in den Hintergrund aufzurufen und in Tests. Wirft nicht;
   * Schreibfehler stehen in `storageFailed`.
   */
  async flush(): Promise<void> {
    let beobachtet: Promise<void>;
    do {
      beobachtet = this.kette;
      await beobachtet;
      // Ein während des Schreibens hinzugekommener Eintrag hat sich hinten
      // angehängt; dann ist die Kette eine andere und es geht weiter.
    } while (beobachtet !== this.kette);
  }

  private planeSchreiben(): void {
    if (this.store === null) return;
    this.kette = this.kette.then(
      () => this.schreibeWennNoetig(),
      // Auch wenn ein früherer Durchlauf gescheitert ist, muss der nächste
      // laufen — sonst reisst die Kette nach dem ersten Fehler ab.
      () => this.schreibeWennNoetig(),
    );
  }

  private async schreibeWennNoetig(): Promise<void> {
    const store = this.store;
    if (store === null) return;

    if (this.loeschAuftrag) {
      this.loeschAuftrag = false;
      this.schmutzig = false;
      try {
        await store.removeItem(this.key);
        this.speicherGestoert = false;
      } catch (fehler) {
        this.merkeSpeicherfehler(fehler);
      }
      return;
    }

    if (!this.schmutzig) return;
    // Vor dem Warten zurücksetzen: Was währenddessen dazukommt, setzt die
    // Marke erneut und wird im nächsten Durchlauf geschrieben.
    this.schmutzig = false;
    const text = JSON.stringify(this.eintraege);

    try {
      await store.setItem(this.key, text);
      // Wieder Platz: Der Hinweis in der Oberfläche darf verschwinden.
      this.speicherGestoert = false;
    } catch (fehler) {
      this.merkeSpeicherfehler(fehler);
    }
  }

  /**
   * Einen fehlgeschlagenen Schreibvorgang vermerken.
   *
   * Der Vermerk selbst wird bewusst nicht gespeichert: Ein Eintrag über einen
   * gescheiterten Schreibvorgang, der einen Schreibvorgang auslöst, der wieder
   * scheitert, füllt das Protokoll in Sekunden mit sich selbst. Deshalb nur
   * beim ersten Mal und ohne Persistenz.
   */
  private merkeSpeicherfehler(fehler: unknown): void {
    if (this.speicherGestoert) return;
    this.speicherGestoert = true;
    this.haengeAn({
      t: this.now(),
      level: 'error',
      area: 'speicher',
      message: EIGENE_MELDUNG.speichernFehlgeschlagen,
      detail: fehlerText(fehler),
    });
  }
}

/**
 * Das Protokoll der App.
 *
 * Ein gemeinsames Objekt und keine Instanz je Modul: Ein Verlauf, der über
 * vier Protokolle verteilt liegt, beantwortet die Frage "was ist vorhin
 * passiert" nicht mehr. Es startet ohne Speicher, damit auch Module
 * protokollieren können, die noch vor der Einrichtung von AsyncStorage laufen;
 * beim App-Start wird der Speicher mit `attachStore` nachgereicht und die
 * bisherigen Einträge werden dabei gesichert.
 *
 * Tests bauen sich ihre eigene Instanz — dieses Objekt bleibt der App.
 */
export const errorLog = new ErrorLog();
