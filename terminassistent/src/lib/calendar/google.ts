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
 * Weg A aus dem Entscheidungsdokument: Google OAuth, eng gefasst.
 *
 * Lesen ueber freebusy.query mit dem engsten dafuer zulaessigen Scope
 * (calendar.freebusy). Das liefert ausschliesslich Belegtzeiten — keine
 * Titel, keine Teilnehmer. Schreiben ueber events.* mit calendar.events.
 *
 * Bewusst mit fetch statt googleapis: zwei Endpunkte rechtfertigen keine
 * Abhaengigkeit von mehreren Megabyte, und die Scopes bleiben sichtbar.
 */

export const GOOGLE_SCOPES = [
  'https://www.googleapis.com/auth/calendar.freebusy',
  'https://www.googleapis.com/auth/calendar.events',
] as const;

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const API = 'https://www.googleapis.com/calendar/v3';

export interface GoogleZugang {
  refreshToken: string;
  clientId: string;
  clientSecret: string;
  /** Fast immer "primary". */
  kalenderId: string;
}

/** Access-Tokens leben eine Stunde; im Prozess gecacht, nie persistiert. */
const tokenCache = new Map<string, { token: string; gueltigBis: number }>();

async function accessToken(id: string, zugang: GoogleZugang): Promise<string> {
  const vorhanden = tokenCache.get(id);
  if (vorhanden && vorhanden.gueltigBis > Date.now() + 60_000) return vorhanden.token;

  const antwort = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: zugang.clientId,
      client_secret: zugang.clientSecret,
      refresh_token: zugang.refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!antwort.ok) {
    const text = await antwort.text();
    // invalid_grant heisst: Refresh-Token ist tot. Das passiert nach sechs
    // Monaten Nichtnutzung oder wenn die Nutzerin den Zugriff entzogen hat.
    // Beides bricht STILL — deshalb hier eine eigene Fehlerklasse, die der
    // Aufrufer in last_error schreibt.
    if (text.includes('invalid_grant')) {
      throw new VerbindungGebrochen(
        id,
        'Der Google-Zugriff ist abgelaufen oder wurde entzogen. Bitte den Kalender neu verbinden.',
      );
    }
    throw new Error(`Google-Token-Anfrage fehlgeschlagen (${antwort.status}): ${text}`);
  }

  const daten = (await antwort.json()) as { access_token: string; expires_in: number };
  tokenCache.set(id, {
    token: daten.access_token,
    gueltigBis: Date.now() + daten.expires_in * 1000,
  });
  return daten.access_token;
}

async function api<T>(
  id: string,
  zugang: GoogleZugang,
  pfad: string,
  init: RequestInit = {},
): Promise<T> {
  const token = await accessToken(id, zugang);
  const antwort = await fetch(`${API}${pfad}`, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
  });
  if (antwort.status === 401 || antwort.status === 403) {
    tokenCache.delete(id);
    throw new VerbindungGebrochen(
      id,
      `Google hat den Zugriff verweigert (${antwort.status}). Bitte den Kalender neu verbinden.`,
    );
  }
  if (!antwort.ok) {
    throw new Error(`Google-API ${pfad} fehlgeschlagen (${antwort.status}): ${await antwort.text()}`);
  }
  if (antwort.status === 204) return undefined as T;
  return (await antwort.json()) as T;
}

// ---------------------------------------------------------------------------
// Lesen
// ---------------------------------------------------------------------------

export class GoogleCalendarSource implements CalendarSource {
  readonly capabilities: SourceCapabilities = {
    push: false, // Push waere ueber watch() moeglich, ist aber nicht gebaut.
    detail: 'busy', // freebusy.query liefert nur Belegtzeiten.
    maxStalenessSeconds: 0, // Direktabfrage, kein Cache dazwischen.
  };

  constructor(
    readonly connectionId: string,
    private readonly zugang: GoogleZugang,
  ) {}

  async getBusy(range: { from: Date; to: Date }): Promise<BusyInterval[]> {
    const antwort = await api<{
      calendars: Record<string, { busy?: { start: string; end: string }[]; errors?: unknown[] }>;
    }>(this.connectionId, this.zugang, '/freeBusy', {
      method: 'POST',
      body: JSON.stringify({
        timeMin: range.from.toISOString(),
        timeMax: range.to.toISOString(),
        items: [{ id: this.zugang.kalenderId }],
      }),
    });

    const kalender = antwort.calendars[this.zugang.kalenderId];
    if (!kalender) return [];
    if (kalender.errors?.length) {
      throw new VerbindungGebrochen(
        this.connectionId,
        `Google meldet einen Fehler fuer den Kalender: ${JSON.stringify(kalender.errors)}`,
      );
    }
    return (kalender.busy ?? []).map((b) => ({
      start: new Date(b.start),
      end: new Date(b.end),
      source: 'google:freebusy',
    }));
  }

  async pruefe(): Promise<{ ok: true } | { ok: false; grund: string }> {
    try {
      const jetzt = new Date();
      await this.getBusy({ from: jetzt, to: new Date(jetzt.getTime() + 3600_000) });
      return { ok: true };
    } catch (fehler) {
      return { ok: false, grund: (fehler as Error).message };
    }
  }
}

// ---------------------------------------------------------------------------
// Schreiben
// ---------------------------------------------------------------------------

interface GoogleEvent {
  id: string;
  htmlLink?: string;
}

/** Unsere eigene UID reist als private extendedProperty mit. */
const UID_SCHLUESSEL = 'assistentUid';

function zuGoogleEvent(draft: EventDraft) {
  return {
    summary: draft.titel,
    description: draft.beschreibung,
    location: draft.ort,
    start: { dateTime: draft.start.toISOString(), timeZone: draft.zeitzone },
    end: { dateTime: draft.end.toISOString(), timeZone: draft.zeitzone },
    attendees: draft.teilnehmer ? [{ email: draft.teilnehmer }] : undefined,
    extendedProperties: { private: { [UID_SCHLUESSEL]: draft.uid } },
  };
}

export class GoogleCalendarSink implements CalendarSink {
  readonly capabilities: SinkCapabilities = {
    confirmsPlacement: true, // Der einzige Weg mit echter Bestaetigung.
    userEditable: true,
    deliversToThirdParties: false, // Google verschickt Einladungen selbst nur
    // bei sendUpdates; wir verlassen uns darauf bewusst nicht.
  };

  constructor(
    readonly connectionId: string,
    private readonly zugang: GoogleZugang,
  ) {}

  private get basis() {
    return `/calendars/${encodeURIComponent(this.zugang.kalenderId)}/events`;
  }

  async create(draft: EventDraft): Promise<PlacementResult> {
    const event = await api<GoogleEvent>(this.connectionId, this.zugang, this.basis, {
      method: 'POST',
      body: JSON.stringify(zuGoogleEvent(draft)),
    });
    return { status: 'placed', ref: { kind: 'google_event_id', value: event.id } };
  }

  async update(ref: PlacementRef, draft: EventDraft): Promise<PlacementResult> {
    const id = this.eventId(ref);
    const event = await api<GoogleEvent>(
      this.connectionId,
      this.zugang,
      `${this.basis}/${encodeURIComponent(id)}`,
      { method: 'PATCH', body: JSON.stringify(zuGoogleEvent(draft)) },
    );
    return { status: 'placed', ref: { kind: 'google_event_id', value: event.id ?? id } };
  }

  async cancel(ref: PlacementRef): Promise<PlacementResult> {
    const id = this.eventId(ref);
    await api<void>(
      this.connectionId,
      this.zugang,
      `${this.basis}/${encodeURIComponent(id)}`,
      { method: 'DELETE' },
    );
    return { status: 'placed', ref };
  }

  private eventId(ref: PlacementRef): string {
    if (ref.kind !== 'google_event_id') {
      // Kann nur passieren, wenn ein Termin unter einem anderen Kanal
      // angelegt und dann auf Google umgestellt wurde. Dann muss neu
      // angelegt statt geraten werden.
      throw new Error(
        `Dieser Termin wurde nicht ueber Google angelegt (${ref.kind}); Aenderung nicht moeglich.`,
      );
    }
    return ref.value;
  }
}
