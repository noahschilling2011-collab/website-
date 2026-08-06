import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

/**
 * Datenmodell nach docs/kalender-anbindung-entscheidung.md, Abschnitt 5.
 *
 * Die fuenf Entscheidungen, die hier festgeschrieben sind:
 *  1. Termine tragen eine EIGENE iCalendar-UID. Die Google-Event-ID steht
 *     daneben, nie als Primaerschluessel.
 *  2. Ein eigener SEQUENCE-Zaehler laeuft ab Tag 1 mit, auch im OAuth-Pfad.
 *  3. Platzierung hat drei Zustaende, nicht boolean.
 *  4. EINE Verbindungstabelle mit `kind` als Diskriminator, mit last_ok_at.
 *  5. Zeit ausschliesslich als UTC-Instant plus IANA-TZID.
 */

// ---------------------------------------------------------------------------
// Nutzer und Anmeldung
// ---------------------------------------------------------------------------

export const nutzer = pgTable('nutzer', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull().unique(),
  name: text('name'),
  /** IANA-TZID, z.B. "Europe/Berlin". Nie ein Offset. */
  zeitzone: text('zeitzone').notNull().default('Europe/Berlin'),
  /** Der lokale Teil der Weiterleitungsadresse: <handle>@<MAIL_DOMAIN>. */
  handle: text('handle').notNull().unique(),
  /** Arbeitszeiten fuer die Slot-Berechnung. */
  arbeitszeiten: jsonb('arbeitszeiten')
    .$type<Arbeitszeiten>()
    .notNull()
    .default(STANDARD_ARBEITSZEITEN()),
  /** Zaehler fuer die Gratisstufe: fuenf abgeschlossene Vorgaenge. */
  abgeschlosseneVorgaenge: integer('abgeschlossene_vorgaenge').notNull().default(0),
  zahlendSeit: timestamp('zahlend_seit', { withTimezone: true }),
  /** Kundennummer beim Zahlungsdienstleister, sobald es eine gibt. */
  zahlungsKundeId: text('zahlungs_kunde_id'),
  erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
});

/**
 * Anmeldung per Mail. Siehe README zur Abweichung vom Entwurf.
 *
 * Ein Eintrag traegt ZWEI Zugangsmittel zur selben Anmeldung: den
 * sechsstelligen Code zum Abtippen und den langen Zufallstoken im Link.
 * Beide gehoeren zusammen und werden gemeinsam entwertet — wer eins
 * benutzt, verbraucht auch das andere.
 */
export const anmeldeTokens = pgTable('anmelde_tokens', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull(),
  /** SHA-256 des Link-Tokens. 32 Zufallsbytes brauchen keinen Schluessel. */
  tokenHash: text('token_hash').notNull().unique(),
  /**
   * HMAC des sechsstelligen Codes. Mit Schluessel, weil eine Million
   * Moeglichkeiten sonst offline durchprobierbar waeren.
   */
  codeHash: text('code_hash'),
  /**
   * Fehlversuche beim Code. Ein sechsstelliger Code ist nur sicher, solange
   * er nicht beliebig oft geraten werden darf — das hier ist die eigentliche
   * Schutzmassnahme, nicht die Laenge.
   */
  versuche: integer('versuche').notNull().default(0),
  gueltigBis: timestamp('gueltig_bis', { withTimezone: true }).notNull(),
  eingeloestAm: timestamp('eingeloest_am', { withTimezone: true }),
  erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Kalenderverbindungen — Entscheidung 4
// ---------------------------------------------------------------------------

export type VerbindungsArt =
  | 'google_oauth'
  | 'ics_secret_url'
  | 'ics_publish'
  | 'imip_mail'
  | 'attrappe';

export const kalenderVerbindungen = pgTable(
  'calendar_connections',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    nutzerId: uuid('nutzer_id')
      .notNull()
      .references(() => nutzer.id, { onDelete: 'cascade' }),
    kind: text('kind').$type<VerbindungsArt>().notNull(),
    /**
     * Zeiger auf die verschluesselte Ablage: Refresh-Token bei OAuth,
     * die geheime iCal-URL bei ICS. Nie im Klartext, nie im Log.
     */
    secretRef: text('secret_ref').notNull(),
    /**
     * Nicht geheime Konfiguration, z.B. Kalender-ID oder das
     * Veroeffentlichungs-Token des eigenen Feeds.
     */
    konfig: jsonb('konfig').$type<Record<string, string>>().notNull().default({}),

    /**
     * Pflicht, keine Kuer: BEIDE Wege brechen still. Bei OAuth laeuft das
     * Refresh-Token nach 6 Monaten Nichtnutzung ab, bei ICS invalidiert ein
     * Reset der Secret Address die URL ohne jede Meldung. Ein Job ueberwacht
     * last_ok_at und schreibt die Nutzerin an.
     */
    lastOkAt: timestamp('last_ok_at', { withTimezone: true }),
    lastError: text('last_error'),
    lastErrorAt: timestamp('last_error_at', { withTimezone: true }),
    /**
     * Ein entzogenes Recht, keine Stoerung.
     *
     * Ein abgelaufenes Refresh-Token oder eine zurueckgesetzte iCal-Adresse
     * heilt nicht von selbst; ein Netzfehler heilt beim naechsten Versuch.
     * Ohne diese Unterscheidung wuerde eine einzelne Zeitueberschreitung
     * die Mail "Ihr Kalender ist nicht mehr erreichbar" ausloesen — und ein
     * Produkt, das grundlos Alarm schlaegt, wird abgeschaltet.
     */
    hartGebrochen: boolean('hart_gebrochen').notNull().default(false),
    /**
     * Wann die Nutzerin zuletzt ueber einen Bruch benachrichtigt wurde.
     * Verhindert, dass der Takt sie jede Minute erneut anschreibt.
     */
    bruchGemeldetAm: timestamp('bruch_gemeldet_am', { withTimezone: true }),

    erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
    widerrufenAm: timestamp('widerrufen_am', { withTimezone: true }),
  },
  (t) => [index('cc_nutzer_idx').on(t.nutzerId)],
);

// ---------------------------------------------------------------------------
// Vorgaenge — die Zeilen auf dem einen Bildschirm
// ---------------------------------------------------------------------------

/** Funktion A, B, C aus dem Entwurf, Abschnitt 3. */
export type VorgangsArt = 'termin' | 'frist' | 'nachfassen';

export type VorgangsZustand =
  | 'neu' //            eingegangen, noch nicht verarbeitet
  | 'warte_auf_mich' // Entwurf liegt bereit, braucht einen Klick
  | 'gehalten' //       gesendet angeklickt, 60-Sekunden-Haltezeit laeuft
  | 'warte_auf_andere' // raus, warten auf Antwort
  | 'erledigt'
  | 'abgebrochen'
  | 'fehler';

export const vorgaenge = pgTable(
  'vorgaenge',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    nutzerId: uuid('nutzer_id')
      .notNull()
      .references(() => nutzer.id, { onDelete: 'cascade' }),
    art: text('art').$type<VorgangsArt>().notNull(),
    zustand: text('zustand').$type<VorgangsZustand>().notNull().default('neu'),

    /** Ein Satz Alltagssprache. Das ist die Zeile, die die Nutzerin liest. */
    titel: text('titel').notNull(),

    gegenueberEmail: text('gegenueber_email'),
    gegenueberName: text('gegenueber_name'),

    /** Klammert alle Mails desselben Threads zusammen. */
    threadKey: text('thread_key').notNull(),

    /** Bei Fristen: der Stichtag. */
    faelligAm: timestamp('faellig_am', { withTimezone: true }),

    /** Bei Nachfassen: wann die naechste Erinnerung faellig ist. */
    naechsteErinnerung: timestamp('naechste_erinnerung', { withTimezone: true }),
    erinnerungenGesendet: integer('erinnerungen_gesendet').notNull().default(0),

    erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
    geaendertAm: timestamp('geaendert_am', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('vorgang_nutzer_idx').on(t.nutzerId),
    index('vorgang_thread_idx').on(t.threadKey),
  ],
);

// ---------------------------------------------------------------------------
// Mail
// ---------------------------------------------------------------------------

export const nachrichten = pgTable(
  'nachrichten',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    vorgangId: uuid('vorgang_id')
      .notNull()
      .references(() => vorgaenge.id, { onDelete: 'cascade' }),
    richtung: text('richtung').$type<'ein' | 'aus'>().notNull(),

    /** RFC-5322-Header, damit Antworten im selben Thread landen. */
    messageId: text('message_id'),
    inReplyTo: text('in_reply_to'),
    referenzen: text('referenzen'),

    von: text('von').notNull(),
    an: text('an').notNull(),
    betreff: text('betreff').notNull(),
    text: text('text').notNull(),

    zeitpunkt: timestamp('zeitpunkt', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('nachricht_vorgang_idx').on(t.vorgangId)],
);

export const anhaenge = pgTable('anhaenge', {
  id: uuid('id').primaryKey().defaultRandom(),
  nachrichtId: uuid('nachricht_id')
    .notNull()
    .references(() => nachrichten.id, { onDelete: 'cascade' }),
  dateiname: text('dateiname').notNull(),
  mimeTyp: text('mime_typ').notNull(),
  groesseBytes: integer('groesse_bytes').notNull(),
  /** Extrahierter Text. Der Rohanhang wird bewusst nicht gespeichert. */
  textExtrakt: text('text_extrakt'),
  /** Gescannte PDFs ohne Textschicht werden abgelehnt statt geraten. */
  extraktionFehlgeschlagen: boolean('extraktion_fehlgeschlagen').notNull().default(false),
});

// ---------------------------------------------------------------------------
// Termine — Entscheidungen 1, 2, 3
// ---------------------------------------------------------------------------

export type PlatzierungsStatus =
  /** OAuth: verifiziert im Kalender. */
  | 'placed'
  /** iMIP: Mail ist raus, Ausgang unbekannt. */
  | 'dispatched'
  /** Feed: steht im Feed, Abruf unbekannt. */
  | 'published'
  /** Noch nichts unternommen. */
  | 'offen'
  | 'abgesagt';

export const termine = pgTable(
  'termine',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    vorgangId: uuid('vorgang_id')
      .notNull()
      .references(() => vorgaenge.id, { onDelete: 'cascade' }),

    /**
     * Entscheidung 1: eigene iCalendar-UID nach RFC-822-addr-spec-Form,
     * <opaque>@<domain>. Ohne sie ist der iMIP-Pfad nie nachruestbar.
     */
    uid: text('uid').notNull().unique(),

    /**
     * Entscheidung 2: eigener SEQUENCE-Zaehler. Im OAuth-Pfad tot, kostet
     * eine Spalte. Erhoeht bei jeder Aenderung von DTSTART, DTEND, DURATION,
     * DUE, RRULE, RDATE, EXDATE, STATUS und bei jeder Absage (RFC 5546).
     */
    sequence: integer('sequence').notNull().default(0),

    titel: text('titel').notNull(),
    /** Entscheidung 5: UTC-Instant ... */
    von: timestamp('von', { withTimezone: true }).notNull(),
    bis: timestamp('bis', { withTimezone: true }).notNull(),
    /** ... plus IANA-TZID. Nie ein Offset. */
    zeitzone: text('zeitzone').notNull(),
    ort: text('ort'),

    /** Entscheidung 3: drei Zustaende statt boolean. */
    platzierungsStatus: text('platzierungs_status')
      .$type<PlatzierungsStatus>()
      .notNull()
      .default('offen'),
    /** 'google_event_id' | 'icalendar_uid' */
    platzierungsArt: text('platzierungs_art'),
    platzierungsWert: text('platzierungs_wert'),

    erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('termin_vorgang_idx').on(t.vorgangId)],
);

// ---------------------------------------------------------------------------
// Ausgang mit Haltezeit — Entwurf, Abschnitt 5 "Rueckgaengig"
// ---------------------------------------------------------------------------

export type AusgangsStatus =
  /** Liegt bereit, wartet auf den Klick der Nutzerin. Kein Ablauf. */
  | 'entwurf'
  /** Klick erfolgt, die Haltezeit laeuft. Bis haltenBis abbrechbar. */
  | 'gehalten'
  | 'gesendet'
  | 'abgebrochen'
  | 'fehler';

export const ausgang = pgTable(
  'ausgang',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    vorgangId: uuid('vorgang_id')
      .notNull()
      .references(() => vorgaenge.id, { onDelete: 'cascade' }),

    an: text('an').notNull(),
    betreff: text('betreff').notNull(),
    text: text('text').notNull(),

    /** Optionaler iCalendar-Teil (METHOD:REQUEST / CANCEL) fuer den iMIP-Weg. */
    icalMethode: text('ical_methode').$type<'REQUEST' | 'CANCEL' | null>(),
    icalInhalt: text('ical_inhalt'),

    inReplyTo: text('in_reply_to'),
    referenzen: text('referenzen'),

    /**
     * Es gibt kein Rueckgaengig fuer eine gesendete Mail. Es gibt Verzoegern:
     * bis zu diesem Zeitpunkt kann die Nutzerin abbrechen.
     */
    haltenBis: timestamp('halten_bis', { withTimezone: true }).notNull(),
    status: text('status').$type<AusgangsStatus>().notNull().default('gehalten'),

    gesendetAm: timestamp('gesendet_am', { withTimezone: true }),
    messageId: text('message_id'),
    fehler: text('fehler'),

    erstelltAm: timestamp('erstellt_am', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('ausgang_status_idx').on(t.status)],
);

// ---------------------------------------------------------------------------
// Vertrauensregeln — Entwurf, Abschnitt 5 "Grenze zwischen fragen und handeln"
// ---------------------------------------------------------------------------

/**
 * Vertrauen wird verdient, nicht abgefragt: nach drei bestaetigten Sendungen
 * desselben Typs an dieselbe Adresse bietet das System an, kuenftig
 * automatisch zu senden.
 */
export const regeln = pgTable(
  'regeln',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    nutzerId: uuid('nutzer_id')
      .notNull()
      .references(() => nutzer.id, { onDelete: 'cascade' }),
    empfaenger: text('empfaenger').notNull(),
    aktionstyp: text('aktionstyp').$type<VorgangsArt>().notNull(),
    bestaetigteSendungen: integer('bestaetigte_sendungen').notNull().default(0),
    /** Erst true, wenn die Nutzerin es ausdruecklich angeboten bekam und annahm. */
    automatisch: boolean('automatisch').notNull().default(false),
    geaendertAm: timestamp('geaendert_am', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('regel_unique').on(t.nutzerId, t.empfaenger, t.aktionstyp)],
);

// ---------------------------------------------------------------------------
// Protokoll — "nachvollziehen", im Wortlaut
// ---------------------------------------------------------------------------

export const protokoll = pgTable(
  'protokoll',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    nutzerId: uuid('nutzer_id')
      .notNull()
      .references(() => nutzer.id, { onDelete: 'cascade' }),
    vorgangId: uuid('vorgang_id'),
    zeitpunkt: timestamp('zeitpunkt', { withTimezone: true }).notNull().defaultNow(),
    was: text('was').notNull(),
    /** Der volle Wortlaut dessen, was rausging. Keine Zusammenfassung. */
    details: text('details'),
  },
  (t) => [index('protokoll_nutzer_idx').on(t.nutzerId)],
);

// ---------------------------------------------------------------------------
// Hilfstypen
// ---------------------------------------------------------------------------

export interface Arbeitszeiten {
  /** 1 = Montag ... 7 = Sonntag (ISO-8601). */
  [wochentag: string]: { von: string; bis: string }[] | undefined;
}

function STANDARD_ARBEITSZEITEN(): Arbeitszeiten {
  // Katrin aus Abschnitt 2: Montag bis Donnerstag 8-17 Uhr.
  return {
    '1': [{ von: '08:00', bis: '17:00' }],
    '2': [{ von: '08:00', bis: '17:00' }],
    '3': [{ von: '08:00', bis: '17:00' }],
    '4': [{ von: '08:00', bis: '17:00' }],
  };
}

export type Nutzer = typeof nutzer.$inferSelect;
export type Vorgang = typeof vorgaenge.$inferSelect;
export type Nachricht = typeof nachrichten.$inferSelect;
export type Termin = typeof termine.$inferSelect;
export type AusgangsEintrag = typeof ausgang.$inferSelect;
export type KalenderVerbindung = typeof kalenderVerbindungen.$inferSelect;
export type Regel = typeof regeln.$inferSelect;
