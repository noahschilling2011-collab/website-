/**
 * Die Abstraktion aus docs/kalender-anbindung-entscheidung.md, Abschnitt 5.
 *
 * Lesen und Schreiben sind bei den ICS-Wegen physisch VERSCHIEDENE Kanaele
 * und stecken deshalb nicht in einem Interface. Wer sie zusammenlegt, kann
 * den ICS-Weg nie nachruesten.
 *
 * Anwendungscode darf niemals `if (kind === 'google_oauth')` schreiben.
 * Er fragt `capabilities`. Sobald irgendwo der Kanalname abgefragt wird,
 * ist die Abstraktion tot.
 */

export interface BusyInterval {
  start: Date;
  end: Date;
  /** Woher das Intervall stammt, fuer das Protokoll. Nie ein Termintitel. */
  source: string;
}

export interface EventDraft {
  /** Unsere eigene iCalendar-UID. Entscheidung 1. */
  uid: string;
  /** Unser eigener Zaehler. Entscheidung 2. */
  sequence: number;
  titel: string;
  start: Date;
  end: Date;
  /** IANA-TZID. Entscheidung 5. */
  zeitzone: string;
  ort?: string;
  beschreibung?: string;
  /** Mailadresse des Dritten. Leer bei rein internen Eintraegen (Fristen). */
  teilnehmer?: string;
  organisator?: { name: string; email: string };
}

export type PlacementRef = {
  kind: 'google_event_id' | 'icalendar_uid';
  value: string;
};

/**
 * Entscheidung 3: drei Zustaende statt boolean.
 *
 * Der Unterschied zwischen "steht im Kalender", "Mail ist raus" und "steht
 * im Feed" ist der einzige, der bis in die UI durchschlaegt. Wer das auf
 * success:true reduziert, muss beim Providerwechsel jeden UI-Text anfassen.
 */
export type PlacementResult =
  | { status: 'placed'; ref: PlacementRef }
  | { status: 'dispatched'; ref: PlacementRef }
  | { status: 'published'; ref: PlacementRef };

export interface SourceCapabilities {
  /** Push-Benachrichtigungen statt Polling? Bei ICS immer false. */
  push: boolean;
  /**
   * 'busy' liefert nur Belegtzeiten (freebusy.query), 'full' den ganzen
   * Kalender inklusive Titeln und Teilnehmern (ICS-Feed). Das ist auch eine
   * Datenschutzaussage, nicht nur eine technische.
   */
  detail: 'busy' | 'full';
  /**
   * Wie alt duerfen gelesene Belegtzeiten hoechstens sein, in Sekunden?
   * Die Slot-Berechnung liest diesen Wert und haelt entsprechend Abstand
   * zu Slots, die gerade erst frei geworden sein koennten. Beim Wechsel
   * auf OAuth faellt die Zahl auf ~0 und die Vorschlaege werden ohne
   * Codeaenderung praeziser.
   */
  maxStalenessSeconds: number;
  /** iCloud liefert nur -6 Monate bis +3 Jahre. */
  horizonPast?: Date;
  horizonFuture?: Date;
}

export interface SinkCapabilities {
  /** Nur OAuth bestaetigt, dass der Termin wirklich im Kalender steht. */
  confirmsPlacement: boolean;
  /** Beim ICS-Abo ist der Termin im Nutzerkalender schreibgeschuetzt. */
  userEditable: boolean;
  /** Nur iMIP erreicht den Dritten direkt. */
  deliversToThirdParties: boolean;
}

export interface CalendarSource {
  readonly connectionId: string;
  readonly capabilities: SourceCapabilities;
  getBusy(range: { from: Date; to: Date }): Promise<BusyInterval[]>;
  /** Einmalige Verbindungspruefung. Die Meldung liest die Nutzerin. */
  pruefe(): Promise<{ ok: true } | { ok: false; grund: string }>;
}

export interface CalendarSink {
  readonly connectionId: string;
  readonly capabilities: SinkCapabilities;
  create(draft: EventDraft): Promise<PlacementResult>;
  update(ref: PlacementRef, draft: EventDraft): Promise<PlacementResult>;
  cancel(ref: PlacementRef, draft: EventDraft, grund?: string): Promise<PlacementResult>;
}

/** Wird geworfen, wenn eine Verbindung still gebrochen ist. */
export class VerbindungGebrochen extends Error {
  constructor(
    public readonly connectionId: string,
    grund: string,
  ) {
    super(grund);
    this.name = 'VerbindungGebrochen';
  }
}
