import ical from 'node-ical';
import icalGenerator, { ICalCalendarMethod, ICalEventStatus } from 'ical-generator';
import {
  type BusyInterval,
  type CalendarSink,
  type CalendarSource,
  type EventDraft,
  type PlacementRef,
  type PlacementResult,
  type SinkCapabilities,
  type SourceCapabilities,
  VerbindungGebrochen,
} from './types';

/**
 * Weg B aus dem Entscheidungsdokument: ICS-Feed lesen, eigenen ICS-Feed
 * zum Abonnieren schreiben. Braucht kein OAuth, kein Google-Projekt, keine
 * Verifizierung — und funktioniert bei Google, Apple und Outlook gleich.
 */

// ---------------------------------------------------------------------------
// Lesen: die geheime iCal-Adresse des Nutzerkalenders
// ---------------------------------------------------------------------------

export interface IcsFeedZugang {
  /** Googles "Geheime Adresse im iCal-Format", Apples oeffentlicher Link, ... */
  url: string;
  /** Wie oft wir pollen. Bestimmt zugleich maxStalenessSeconds. */
  pollIntervallSekunden?: number;
}

export class IcsFeedSource implements CalendarSource {
  readonly capabilities: SourceCapabilities;

  constructor(
    readonly connectionId: string,
    private readonly zugang: IcsFeedZugang,
  ) {
    const intervall = zugang.pollIntervallSekunden ?? 900;
    this.capabilities = {
      push: false,
      // Der Feed liefert den VOLLEN Kalender inklusive Titeln und
      // Teilnehmern. Das ist der Datenschutz-Preis dieses Weges, und der
      // Grund, warum wir hier ausschliesslich Zeiten herausziehen und
      // alles andere sofort verwerfen.
      detail: 'full',
      maxStalenessSeconds: intervall,
    };
  }

  async getBusy(range: { from: Date; to: Date }): Promise<BusyInterval[]> {
    let daten: Record<string, unknown>;
    try {
      daten = (await ical.async.fromURL(this.zugang.url)) as Record<string, unknown>;
    } catch (fehler) {
      // Ein Reset der Secret Address invalidiert die URL OHNE jede Meldung.
      // Genau dafuer existiert last_error in der Verbindungstabelle.
      throw new VerbindungGebrochen(
        this.connectionId,
        `Der Kalender-Feed ist nicht erreichbar. Moeglicherweise wurde die geheime Adresse zurueckgesetzt. (${(fehler as Error).message})`,
      );
    }

    const belegt: BusyInterval[] = [];
    for (const eintrag of Object.values(daten)) {
      const ereignis = eintrag as IcsEreignis;
      if (!ereignis || ereignis.type !== 'VEVENT') continue;
      // TRANSP:TRANSPARENT heisst ausdruecklich "blockiert nicht".
      if (ereignis.transparency === 'TRANSPARENT') continue;
      if (ereignis.status === 'CANCELLED') continue;
      belegt.push(...expandiere(ereignis, range));
    }
    return verschmelze(belegt);
  }

  async pruefe(): Promise<{ ok: true } | { ok: false; grund: string }> {
    try {
      const jetzt = new Date();
      await this.getBusy({ from: jetzt, to: new Date(jetzt.getTime() + 86_400_000) });
      return { ok: true };
    } catch (fehler) {
      return { ok: false, grund: (fehler as Error).message };
    }
  }
}

interface IcsEreignis {
  type?: string;
  start?: Date & { dateOnly?: boolean };
  end?: Date & { dateOnly?: boolean };
  datetype?: 'date' | 'date-time';
  summary?: string;
  transparency?: string;
  status?: string;
  rrule?: { between(a: Date, b: Date, inc?: boolean): Date[] };
  exdate?: Record<string, Date>;
  recurrences?: Record<string, IcsEreignis>;
}

/**
 * Wiederholungen auffalten. node-ical liefert die RRULE als rrule-Objekt,
 * Ausnahmen als exdate und einzeln verschobene Termine als recurrences.
 * Alle drei muessen beruecksichtigt werden, sonst schlaegt die App
 * Termine vor, die belegt sind.
 */
export function expandiere(
  ereignis: IcsEreignis,
  range: { from: Date; to: Date },
): BusyInterval[] {
  const start = ereignis.start;
  const ende = ereignis.end;
  if (!start) return [];

  const ganztaegig = ereignis.datetype === 'date';
  const dauer = ende ? ende.getTime() - start.getTime() : ganztaegig ? 86_400_000 : 3_600_000;
  const quelle = 'ics:feed';

  if (!ereignis.rrule) {
    if (start.getTime() < range.to.getTime() && start.getTime() + dauer > range.from.getTime()) {
      return [{ start, end: new Date(start.getTime() + dauer), source: quelle }];
    }
    return [];
  }

  const ausnahmen = new Set(
    Object.values(ereignis.exdate ?? {}).map((d) => new Date(d).toISOString().slice(0, 10)),
  );
  const verschoben = ereignis.recurrences ?? {};

  const treffer: BusyInterval[] = [];
  // Etwas Vorlauf, damit ein Termin, der vor `from` beginnt und hineinragt,
  // nicht verlorengeht.
  const suchStart = new Date(range.from.getTime() - dauer);
  for (const vorkommen of ereignis.rrule.between(suchStart, range.to, true)) {
    const tag = vorkommen.toISOString().slice(0, 10);
    if (ausnahmen.has(tag)) continue;

    const ersatz = verschoben[tag];
    if (ersatz?.start) {
      const ersatzDauer = ersatz.end
        ? ersatz.end.getTime() - ersatz.start.getTime()
        : dauer;
      treffer.push({
        start: ersatz.start,
        end: new Date(ersatz.start.getTime() + ersatzDauer),
        source: quelle,
      });
      continue;
    }
    treffer.push({
      start: vorkommen,
      end: new Date(vorkommen.getTime() + dauer),
      source: quelle,
    });
  }
  return treffer;
}

/** Ueberlappende Belegtzeiten zusammenfassen, damit Slots sauber fallen. */
export function verschmelze(intervalle: BusyInterval[]): BusyInterval[] {
  if (intervalle.length === 0) return [];
  const sortiert = [...intervalle].sort((a, b) => a.start.getTime() - b.start.getTime());
  const ergebnis: BusyInterval[] = [{ ...sortiert[0]! }];
  for (const aktuell of sortiert.slice(1)) {
    const letzter = ergebnis[ergebnis.length - 1]!;
    if (aktuell.start.getTime() <= letzter.end.getTime()) {
      if (aktuell.end.getTime() > letzter.end.getTime()) letzter.end = aktuell.end;
    } else {
      ergebnis.push({ ...aktuell });
    }
  }
  return ergebnis;
}

// ---------------------------------------------------------------------------
// Schreiben: unser eigener, abonnierbarer Feed
// ---------------------------------------------------------------------------

/**
 * Der Sink schreibt NICHT in einen Fremdkalender. Die App ist der
 * Terminspeicher; der Feed wird bei jedem Abruf aus der Datenbank
 * gerendert (siehe app/api/feed/[token]/route.ts).
 *
 * Deshalb ist create() hier fast leer: es gibt nichts zu uebertragen. Der
 * Status ist 'published' — "steht im Feed, Abruf unbekannt" —, und genau
 * dieser Unterschied zu 'placed' ist der Grund, warum PlacementResult drei
 * Zustaende hat statt eines boolean.
 */
export class IcsPublishSink implements CalendarSink {
  readonly capabilities: SinkCapabilities = {
    confirmsPlacement: false, // Wir erfahren nie, ob der Kalender abgerufen hat.
    userEditable: false, // Im Nutzerkalender ist das Abo schreibgeschuetzt.
    deliversToThirdParties: false,
  };

  constructor(readonly connectionId: string) {}

  async create(draft: EventDraft): Promise<PlacementResult> {
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  async update(_ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  async cancel(_ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }
}

// ---------------------------------------------------------------------------
// iCalendar erzeugen
// ---------------------------------------------------------------------------

/** Der abonnierbare Feed: PUBLISH-Semantik, ohne METHOD. */
export function baueFeed(
  name: string,
  termine: EventDraft[],
  zeitzone: string,
): string {
  const kalender = icalGenerator({ name, timezone: zeitzone, prodId: PROD_ID });
  for (const termin of termine) {
    kalender.createEvent({
      id: termin.uid,
      sequence: termin.sequence,
      start: termin.start,
      end: termin.end,
      summary: termin.titel,
      description: termin.beschreibung,
      location: termin.ort,
      timezone: termin.zeitzone,
    });
  }
  return kalender.toString();
}

/**
 * Weg C: eine echte Kalendereinladung als Mailanhang (RFC 5545/5546/6047).
 *
 * METHOD ist Pflicht — ohne sie zeigt Outlook den Teil als Anhang statt als
 * Einladung an (MS-STANOICAL V0341). Bei Aenderungen dieselbe UID mit
 * erhoehter SEQUENCE, bei Absagen METHOD:CANCEL mit STATUS:CANCELLED.
 */
export function baueEinladung(
  draft: EventDraft,
  methode: 'REQUEST' | 'CANCEL',
): string {
  const kalender = icalGenerator({ prodId: PROD_ID, timezone: draft.zeitzone });
  kalender.method(
    methode === 'REQUEST' ? ICalCalendarMethod.REQUEST : ICalCalendarMethod.CANCEL,
  );

  const ereignis = kalender.createEvent({
    id: draft.uid,
    sequence: draft.sequence,
    start: draft.start,
    end: draft.end,
    summary: draft.titel,
    description: draft.beschreibung,
    location: draft.ort,
    timezone: draft.zeitzone,
  });

  if (draft.organisator) {
    // Die ORGANIZER-Adresse muss zur Absenderdomain passen, sonst verwerfen
    // Empfaenger die Einladung. RFC 6047 stellt ausdruecklich klar, dass die
    // Absenderauthentizitaet aus den Mailheadern NICHT ableitbar ist.
    ereignis.organizer({ name: draft.organisator.name, email: draft.organisator.email });
  }
  if (draft.teilnehmer) {
    ereignis.createAttendee({ email: draft.teilnehmer, rsvp: true });
  }
  if (methode === 'CANCEL') {
    ereignis.status(ICalEventStatus.CANCELLED);
  }

  return kalender.toString();
}

const PROD_ID = { company: 'terminassistent', product: 'terminassistent', language: 'DE' };
