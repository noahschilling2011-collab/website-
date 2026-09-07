import type {
  BusyInterval,
  CalendarSink,
  CalendarSource,
  EventDraft,
  PlacementRef,
  PlacementResult,
  SinkCapabilities,
  SourceCapabilities,
} from './types';

/**
 * Attrappe fuer Entwicklung und Tests.
 *
 * Existiert, damit `npm run dev` und `npm test` ohne Google-Projekt,
 * ohne Kalenderkonto und ohne Netz laufen. Sie gibt sich bewusst als
 * schwaechster Kanal aus — detail:'full', maxStalenessSeconds > 0,
 * confirmsPlacement:false —, damit Code, der gegen sie entwickelt wurde,
 * die Faehigkeiten wirklich abfragt statt sie anzunehmen.
 */
export class AttrappeSource implements CalendarSource {
  readonly capabilities: SourceCapabilities = {
    push: false,
    detail: 'full',
    maxStalenessSeconds: 900,
  };

  constructor(
    readonly connectionId: string,
    private readonly belegt: BusyInterval[] = [],
  ) {}

  async getBusy(range: { from: Date; to: Date }): Promise<BusyInterval[]> {
    return this.belegt.filter(
      (b) => b.start.getTime() < range.to.getTime() && b.end.getTime() > range.from.getTime(),
    );
  }

  async pruefe(): Promise<{ ok: true }> {
    return { ok: true };
  }
}

export class AttrappeSink implements CalendarSink {
  readonly capabilities: SinkCapabilities = {
    confirmsPlacement: false,
    userEditable: false,
    deliversToThirdParties: false,
  };

  readonly angelegt: EventDraft[] = [];
  readonly abgesagt: string[] = [];

  constructor(readonly connectionId: string) {}

  async create(draft: EventDraft): Promise<PlacementResult> {
    this.angelegt.push(draft);
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  async update(_ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    this.angelegt.push(draft);
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }

  async cancel(_ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    this.abgesagt.push(draft.uid);
    return { status: 'published', ref: { kind: 'icalendar_uid', value: draft.uid } };
  }
}
