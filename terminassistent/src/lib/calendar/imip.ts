import { baueEinladung } from './ics';
import type {
  CalendarSink,
  EventDraft,
  PlacementRef,
  PlacementResult,
  SinkCapabilities,
} from './types';

/**
 * Weg C aus dem Entscheidungsdokument: der Termin geht als echte
 * Kalendereinladung per Mail an den Dritten (RFC 5545 / 5546 / 6047).
 *
 * Der Sink verschickt NICHT selbst. Er uebergibt die fertige Einladung an
 * einen Kanal, den die Engine stellt — in der Praxis der Ausgang mit der
 * 60-Sekunden-Haltezeit. Sonst haette dieser eine Sink die Faehigkeit, an
 * der Vertrauensmechanik vorbei Post an einen echten Menschen zu schicken.
 *
 * Der Status ist 'dispatched' und niemals 'placed': ob die Einladung im
 * Kalender des Empfaengers landet, entscheidet dessen Einstellung (Gmail
 * kennt drei Stufen, in Workspace setzt sie der Admin). Diese Einstellung
 * ist weder auslesbar noch als Fehlerursache erkennbar — deshalb waere
 * jede Erfolgsmeldung hier gelogen.
 */

export interface EinladungsKanal {
  (auftrag: {
    an: string;
    betreff: string;
    text: string;
    methode: 'REQUEST' | 'CANCEL';
    ical: string;
    uid: string;
  }): Promise<void>;
}

export class ImipMailSink implements CalendarSink {
  readonly capabilities: SinkCapabilities = {
    confirmsPlacement: false,
    userEditable: true, // Im Kalender des Empfaengers ist es sein Termin.
    deliversToThirdParties: true, // Der einzige Weg, der das kann.
  };

  constructor(
    readonly connectionId: string,
    private readonly kanal: EinladungsKanal,
  ) {}

  async create(draft: EventDraft): Promise<PlacementResult> {
    await this.verschicke(draft, 'REQUEST');
    return { status: 'dispatched', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  /**
   * Aenderung: dieselbe UID, hoehere SEQUENCE, erneut METHOD:REQUEST.
   * RFC 5546: "the component with the highest numeric value for the
   * SEQUENCE property obsoletes all other revisions".
   */
  async update(_ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    await this.verschicke(draft, 'REQUEST');
    return { status: 'dispatched', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  async cancel(_ref: PlacementRef, draft: EventDraft, grund?: string): Promise<PlacementResult> {
    await this.verschicke(draft, 'CANCEL', grund);
    return { status: 'dispatched', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  private async verschicke(
    draft: EventDraft,
    methode: 'REQUEST' | 'CANCEL',
    grund?: string,
  ): Promise<void> {
    if (!draft.teilnehmer) {
      throw new Error(
        'Eine Kalendereinladung ohne Empfaenger ergibt keinen Sinn — draft.teilnehmer fehlt.',
      );
    }
    if (!draft.organisator) {
      // Die ORGANIZER-Adresse muss zur Absenderdomain passen, sonst
      // verwerfen Empfaenger die Einladung. Ohne Organisator waere die
      // Einladung formal unvollstaendig.
      throw new Error('draft.organisator fehlt; ohne ORGANIZER ist die Einladung ungueltig.');
    }

    const ical = baueEinladung(draft, methode);
    const betreff =
      methode === 'CANCEL' ? `Abgesagt: ${draft.titel}` : `Termin: ${draft.titel}`;

    await this.kanal({
      an: draft.teilnehmer,
      betreff,
      text:
        methode === 'CANCEL'
          ? `Der Termin wurde abgesagt.${grund ? `\n\n${grund}` : ''}`
          : 'Im Anhang finden Sie die Termineinladung.',
      methode,
      ical,
      uid: draft.uid,
    });
  }
}
