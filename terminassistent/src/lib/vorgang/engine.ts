import crypto from 'node:crypto';
import { and, asc, desc, eq, isNull, lte } from 'drizzle-orm';
import { db, schema } from '../../db/index';
import type { Nutzer, Vorgang, VorgangsArt } from '../../db/schema';
import { baueSink, baueSource } from '../calendar/registry';
import type { CalendarSink, CalendarSource, EventDraft } from '../calendar/types';
import { VerbindungGebrochen } from '../calendar/types';
import { konfig } from '../konfig';
import { analysiere, type Analyse } from '../llm/extraktion';
import {
  entwurfBestaetigung,
  entwurfNachfassen,
  entwurfTerminvorschlag,
  fristTitel,
} from '../llm/formulierung';
import { mailVersand } from '../mail/ausgang';
import { handleAus, parseEingang, type EingehendeMail } from '../mail/eingang';
import { antwortBetreff, antwortHeader } from '../mail/threading';
import { freieSlots, waehleVorschlaege, type Slot } from '../slots';
import { formatiereDeutsch, lokalZuUtc } from '../zeit';
import {
  automatikErlaubtFuer,
  darfAutomatischSenden,
  naechsterZustand,
  type Ereignis,
} from './zustand';

/**
 * Die Engine verbindet Mail, Modell, Kalender und Zustandsmaschine.
 *
 * Sie enthaelt bewusst KEINE Entscheidung darueber, ob etwas an die
 * Aussenwelt geht — das entscheidet ausschliesslich zustand.ts. Hier
 * stehen nur die Seiteneffekte.
 */

// ---------------------------------------------------------------------------
// Eingang
// ---------------------------------------------------------------------------

export async function verarbeiteEingang(
  roh: ArrayBuffer | Uint8Array | string,
  umschlagAn?: string,
): Promise<{ vorgangId: string } | { abgelehnt: string }> {
  const d = await db();
  const mail = await parseEingang(roh);

  const adressen = [...mail.an, ...(umschlagAn ? [umschlagAn] : [])];
  const handle = handleAus(adressen, konfig.mailDomain);
  if (!handle) {
    return { abgelehnt: `Keine Empfaengeradresse auf ${konfig.mailDomain} gefunden.` };
  }

  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.handle, handle))
    .limit(1);
  if (!nutzer) return { abgelehnt: `Unbekannte Adresse: ${handle}@${konfig.mailDomain}` };

  const vorgang = await findeOderErstelleVorgang(nutzer, mail);
  await speichereNachricht(vorgang.id, mail);

  const vorschlaege = await offeneVorschlaege(vorgang.id, nutzer.zeitzone);
  const analyse = await analysiere(mail, {
    heute: new Date(),
    zeitzone: nutzer.zeitzone,
    vorschlaege,
  });

  await protokolliere(nutzer.id, vorgang.id, 'Mail empfangen und analysiert', [
    `Von: ${mail.von}`,
    `Betreff: ${mail.betreff}`,
    `Erkannt als: ${analyse.art} (Vertrauen: ${analyse.vertrauen})`,
    analyse.begruendung,
  ].join('\n'));

  await wendeAnalyseAn(nutzer, vorgang, mail, analyse);
  return { vorgangId: vorgang.id };
}

async function wendeAnalyseAn(
  nutzer: Nutzer,
  vorgang: Vorgang,
  mail: EingehendeMail,
  analyse: Analyse,
): Promise<void> {
  const d = await db();

  // Eine Zusage auf unsere Vorschlaege hat Vorrang vor der Kategorie.
  if (vorgang.zustand === 'warte_auf_andere' && analyse.istZusage) {
    await verarbeiteZusage(nutzer, vorgang, mail, analyse);
    return;
  }

  const braucht_rueckfrage = analyse.vertrauen === 'niedrig' || analyse.art === 'sonstiges';
  const uebergang = naechsterZustand(vorgang.zustand, {
    art: 'mail_eingegangen',
    braucht_rueckfrage,
  });

  const art: VorgangsArt = analyse.art === 'sonstiges' ? 'termin' : analyse.art;

  await d
    .update(schema.vorgaenge)
    .set({
      art,
      titel: analyse.titel,
      gegenueberEmail: mail.von,
      gegenueberName: analyse.gegenueberName ?? mail.vonName,
      zustand: braucht_rueckfrage ? 'warte_auf_mich' : uebergang.zustand,
      faelligAm: analyse.fristDatum
        ? lokalZuUtc(...zerlegeIsoDatum(analyse.fristDatum), 9, 0, nutzer.zeitzone)
        : vorgang.faelligAm,
      geaendertAm: new Date(),
    })
    .where(eq(schema.vorgaenge.id, vorgang.id));

  if (braucht_rueckfrage) {
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Rueckfrage statt Handlung',
      analyse.begruendung,
    );
    return;
  }

  if (uebergang.wirkung !== 'entwurf_erzeugen') return;

  if (analyse.art === 'frist') {
    await trageFristEin(nutzer, { ...vorgang, art, titel: analyse.titel }, analyse);
  } else {
    await erzeugeTerminEntwurf(nutzer, { ...vorgang, art, titel: analyse.titel }, mail);
  }
}

// ---------------------------------------------------------------------------
// Funktion B: Frist eintragen
// ---------------------------------------------------------------------------

async function trageFristEin(
  nutzer: Nutzer,
  vorgang: Vorgang,
  analyse: Analyse,
): Promise<void> {
  const d = await db();
  if (!analyse.fristDatum) {
    await setzeZustand(vorgang.id, 'warte_auf_mich');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Frist erkannt, aber kein Datum',
      'Ohne belegbares Datum wird nichts eingetragen.',
    );
    return;
  }

  const faellig = lokalZuUtc(...zerlegeIsoDatum(analyse.fristDatum), 9, 0, nutzer.zeitzone);
  const draft: EventDraft = {
    uid: neueUid(),
    sequence: 0,
    titel: fristTitel(analyse.gegenueberName, faellig, nutzer.zeitzone),
    start: faellig,
    end: new Date(faellig.getTime() + 30 * 60_000),
    zeitzone: nutzer.zeitzone,
    beschreibung: [
      analyse.titel,
      analyse.betragEuro !== null ? `Betrag: ${analyse.betragEuro} EUR` : null,
      `Eingetragen vom Assistenten aus einer Mail von ${vorgang.gegenueberEmail ?? 'unbekannt'}.`,
    ]
      .filter(Boolean)
      .join('\n'),
  };

  const [termin] = await d
    .insert(schema.termine)
    .values({
      vorgangId: vorgang.id,
      uid: draft.uid,
      sequence: 0,
      titel: draft.titel,
      von: draft.start,
      bis: draft.end,
      zeitzone: draft.zeitzone,
    })
    .returning();

  const kanal = await kalenderKanal(nutzer.id);
  if (!kanal?.sink) {
    await setzeZustand(vorgang.id, 'warte_auf_mich');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Frist erkannt, aber kein Kalender verbunden',
      'Bitte unter Verbindungen einen Kalender hinterlegen.',
    );
    return;
  }

  const ergebnis = await kanal.sink.create(draft);
  await d
    .update(schema.termine)
    .set({
      platzierungsStatus: ergebnis.status,
      platzierungsArt: ergebnis.ref.kind,
      platzierungsWert: ergebnis.ref.value,
    })
    .where(eq(schema.termine.id, termin!.id));

  const uebergang = naechsterZustand(vorgang.zustand, { art: 'frist_eingetragen' });
  await setzeZustand(vorgang.id, uebergang.zustand, { faelligAm: faellig });
  await zaehleAbgeschlossen(nutzer.id);

  await protokolliere(
    nutzer.id,
    vorgang.id,
    'Frist in den Kalender eingetragen',
    [
      `Termin: ${formatiereDeutsch(faellig, nutzer.zeitzone)} Uhr`,
      `Status: ${beschreibePlatzierung(ergebnis.status)}`,
      `UID: ${draft.uid}`,
    ].join('\n'),
  );
}

// ---------------------------------------------------------------------------
// Funktion A: Terminabstimmung
// ---------------------------------------------------------------------------

async function erzeugeTerminEntwurf(
  nutzer: Nutzer,
  vorgang: Vorgang,
  mail: EingehendeMail,
): Promise<void> {
  const kanal = await kalenderKanal(nutzer.id);
  if (!kanal?.source) {
    await setzeZustand(vorgang.id, 'warte_auf_mich');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Kein Kalender verbunden',
      'Ohne Kalender koennen keine Termine vorgeschlagen werden.',
    );
    return;
  }

  const von = new Date();
  const bis = new Date(von.getTime() + 14 * 86_400_000);

  let belegt;
  try {
    belegt = await kanal.source.getBusy({ from: von, to: bis });
    await merkeVerbindungOk(kanal.verbindungId);
  } catch (fehler) {
    await merkeVerbindungFehler(kanal.verbindungId, (fehler as Error).message);
    await setzeZustand(vorgang.id, 'fehler');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Kalender nicht lesbar',
      (fehler as Error).message,
    );
    return;
  }

  const slots = freieSlots(
    belegt,
    {
      von,
      bis,
      dauerMinuten: konfig.terminDauerMinuten,
      pufferMinuten: konfig.pufferMinuten,
      arbeitszeiten: nutzer.arbeitszeiten,
      zeitzone: nutzer.zeitzone,
    },
    kanal.source.capabilities,
  );

  const vorschlaege = waehleVorschlaege(slots, 3, nutzer.zeitzone);
  if (vorschlaege.length === 0) {
    await setzeZustand(vorgang.id, 'warte_auf_mich');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Keine freien Termine gefunden',
      'In den naechsten 14 Tagen ist innerhalb der Arbeitszeiten nichts frei.',
    );
    return;
  }

  await merkeVorschlaege(vorgang.id, vorschlaege, nutzer.zeitzone, vorgang.titel);

  const entwurf = await entwurfTerminvorschlag({
    gegenueberName: vorgang.gegenueberName,
    betreff: antwortBetreff(mail.betreff),
    bisherigerVerlauf: mail.text.slice(0, 2000),
    vorschlaege,
    zeitzone: nutzer.zeitzone,
    nutzerName: nutzer.name ?? '',
  });

  await legeEntwurfAb(nutzer, vorgang, entwurf, mail);
}

async function verarbeiteZusage(
  nutzer: Nutzer,
  vorgang: Vorgang,
  mail: EingehendeMail,
  analyse: Analyse,
): Promise<void> {
  const d = await db();
  const vorschlaege = await geladeneVorschlaege(vorgang.id);
  const index = (analyse.zugesagterVorschlag ?? 1) - 1;
  const gewaehlt = vorschlaege[index];

  if (!gewaehlt) {
    await setzeZustand(vorgang.id, 'warte_auf_mich');
    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Zusage erkannt, aber kein passender Vorschlag',
      `Das Modell nannte Vorschlag ${analyse.zugesagterVorschlag}, gespeichert sind ${vorschlaege.length}.`,
    );
    return;
  }

  // Der bestaetigte Termin behaelt die UID, unter der er vorgeschlagen
  // wurde. Die uebrigen Vorschlaege verfallen.
  for (const anderer of vorschlaege) {
    if (anderer.id === gewaehlt.id) continue;
    await d.delete(schema.termine).where(eq(schema.termine.id, anderer.id));
  }

  const draft: EventDraft = {
    uid: gewaehlt.uid,
    sequence: gewaehlt.sequence,
    titel: vorgang.titel,
    start: gewaehlt.von,
    end: gewaehlt.bis,
    zeitzone: nutzer.zeitzone,
    teilnehmer: vorgang.gegenueberEmail ?? undefined,
    organisator: nutzer.name ? { name: nutzer.name, email: konfig.absender } : undefined,
  };

  const kanal = await kalenderKanal(nutzer.id);
  if (kanal?.sink) {
    const ergebnis = await kanal.sink.create(draft);
    await d
      .update(schema.termine)
      .set({
        titel: draft.titel,
        platzierungsStatus: ergebnis.status,
        platzierungsArt: ergebnis.ref.kind,
        platzierungsWert: ergebnis.ref.value,
      })
      .where(eq(schema.termine.id, gewaehlt.id));

    await protokolliere(
      nutzer.id,
      vorgang.id,
      'Termin eingetragen',
      [
        `${formatiereDeutsch(gewaehlt.von, nutzer.zeitzone)} Uhr`,
        `Status: ${beschreibePlatzierung(ergebnis.status)}`,
        `UID: ${gewaehlt.uid}`,
      ].join('\n'),
    );
  }

  const entwurf = await entwurfBestaetigung({
    gegenueberName: vorgang.gegenueberName,
    betreff: antwortBetreff(mail.betreff),
    termin: { start: gewaehlt.von, ende: gewaehlt.bis },
    zeitzone: nutzer.zeitzone,
    nutzerName: nutzer.name ?? '',
  });

  await legeEntwurfAb(nutzer, vorgang, entwurf, mail);
}

// ---------------------------------------------------------------------------
// Entwurf ablegen und Haltezeit
// ---------------------------------------------------------------------------

async function legeEntwurfAb(
  nutzer: Nutzer,
  vorgang: Vorgang,
  entwurf: { betreff: string; text: string },
  bezugsMail: EingehendeMail | null,
): Promise<void> {
  const d = await db();
  const regel = await findeRegel(nutzer.id, vorgang.gegenueberEmail, vorgang.art);
  const automatisch = automatikErlaubtFuer(vorgang.art) && darfAutomatischSenden(regel);

  const uebergang = naechsterZustand(vorgang.zustand, {
    art: 'entwurf_bereit',
    darf_automatisch: automatisch,
  });

  const header = bezugsMail
    ? antwortHeader({ messageId: bezugsMail.messageId, referenzen: bezugsMail.referenzen })
    : { inReplyTo: null, referenzen: null };

  await d.insert(schema.ausgang).values({
    vorgangId: vorgang.id,
    an: vorgang.gegenueberEmail ?? '',
    betreff: entwurf.betreff,
    text: mitSignatur(entwurf.text, nutzer),
    inReplyTo: header.inReplyTo,
    referenzen: header.referenzen,
    // Die Haltezeit laeuft erst ab dem Klick. Bis dahin liegt der Entwurf
    // ohne Ablauf da — deshalb hier ein weit entfernter Zeitpunkt, der
    // beim Ausloesen ueberschrieben wird.
    // Ein Entwurf hat keine Haltezeit — die beginnt erst mit dem Klick.
    haltenBis: uebergang.wirkung === 'in_ausgang_legen' ? haltenBis() : NIE,
    status: uebergang.wirkung === 'in_ausgang_legen' ? 'gehalten' : 'entwurf',
  });

  await setzeZustand(vorgang.id, uebergang.zustand);
  await protokolliere(
    nutzer.id,
    vorgang.id,
    automatisch ? 'Entwurf erstellt, Automatik aktiv' : 'Entwurf erstellt, wartet auf Freigabe',
    `Betreff: ${entwurf.betreff}\n\n${entwurf.text}`,
  );
}

/** Die Nutzerin hat auf "Senden" geklickt. Jetzt laeuft die Haltezeit. */
export async function sendenAusloesen(vorgangId: string): Promise<void> {
  const d = await db();
  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId))
    .limit(1);
  if (!vorgang) throw new Error('Vorgang nicht gefunden.');

  const uebergang = naechsterZustand(vorgang.zustand, { art: 'senden_ausgeloest' });
  if (uebergang.wirkung !== 'in_ausgang_legen') return;

  const entwurf = await neuesterEntwurf(vorgangId);
  if (!entwurf) throw new Error('Kein Entwurf vorhanden.');
  if (entwurf.status !== 'entwurf') return; // schon unterwegs oder erledigt

  await d
    .update(schema.ausgang)
    .set({ status: 'gehalten', haltenBis: haltenBis() })
    .where(eq(schema.ausgang.id, entwurf.id));

  await setzeZustand(vorgangId, uebergang.zustand);
  await protokolliere(
    vorgang.nutzerId,
    vorgangId,
    'Senden ausgeloest',
    `Haltezeit laeuft ${konfig.haltezeitSekunden} Sekunden. Bis dahin abbrechbar.`,
  );
}

/** Abbruch innerhalb der Haltezeit. Danach hilft nur noch Kompensieren. */
export async function haltezeitAbbrechen(vorgangId: string): Promise<boolean> {
  const d = await db();
  const entwurf = await neuesterEntwurf(vorgangId);
  if (!entwurf || entwurf.status !== 'gehalten') return false;
  if (entwurf.haltenBis.getTime() <= Date.now()) return false;

  await d
    .update(schema.ausgang)
    .set({ status: 'abgebrochen' })
    .where(eq(schema.ausgang.id, entwurf.id));

  const [vorgang] = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId))
    .limit(1);
  if (!vorgang) return false;

  const uebergang = naechsterZustand(vorgang.zustand, { art: 'haltezeit_abgebrochen' });
  await setzeZustand(vorgangId, uebergang.zustand);
  await protokolliere(vorgang.nutzerId, vorgangId, 'Versand abgebrochen', 'Innerhalb der Haltezeit.');
  return true;
}

// ---------------------------------------------------------------------------
// Der Takt: faellige Sendungen und Erinnerungen
// ---------------------------------------------------------------------------

export interface TaktErgebnis {
  gesendet: number;
  erinnerungen: number;
  fehler: number;
}

export async function takt(jetzt = new Date()): Promise<TaktErgebnis> {
  const ergebnis: TaktErgebnis = { gesendet: 0, erinnerungen: 0, fehler: 0 };
  const d = await db();

  // 1. Abgelaufene Haltezeiten senden.
  const faellig = await d
    .select()
    .from(schema.ausgang)
    .where(and(eq(schema.ausgang.status, 'gehalten'), lte(schema.ausgang.haltenBis, jetzt)));

  for (const eintrag of faellig) {
    try {
      const versand = await mailVersand().sende({
        an: eintrag.an,
        betreff: eintrag.betreff,
        text: eintrag.text,
        inReplyTo: eintrag.inReplyTo,
        referenzen: eintrag.referenzen,
        ical: eintrag.icalMethode
          ? { methode: eintrag.icalMethode, inhalt: eintrag.icalInhalt ?? '' }
          : null,
      });

      await d
        .update(schema.ausgang)
        .set({ status: 'gesendet', gesendetAm: jetzt, messageId: versand.messageId })
        .where(eq(schema.ausgang.id, eintrag.id));

      const [vorgang] = await d
        .select()
        .from(schema.vorgaenge)
        .where(eq(schema.vorgaenge.id, eintrag.vorgangId))
        .limit(1);
      if (!vorgang) continue;

      const uebergang = naechsterZustand(vorgang.zustand, { art: 'versandt' });
      await setzeZustand(vorgang.id, uebergang.zustand, {
        naechsteErinnerung: new Date(
          jetzt.getTime() + konfig.nachfassenNachTagen * 86_400_000,
        ),
      });

      await zaehleBestaetigung(vorgang.nutzerId, eintrag.an, vorgang.art);
      await protokolliere(
        vorgang.nutzerId,
        vorgang.id,
        'Mail gesendet',
        `An: ${eintrag.an}\nBetreff: ${eintrag.betreff}\n\n${eintrag.text}`,
      );
      ergebnis.gesendet++;
    } catch (fehler) {
      await d
        .update(schema.ausgang)
        .set({ status: 'fehler', fehler: (fehler as Error).message })
        .where(eq(schema.ausgang.id, eintrag.id));
      await setzeZustand(eintrag.vorgangId, 'fehler');
      ergebnis.fehler++;
    }
  }

  // 2. Faellige Erinnerungen (Funktion C).
  const wartend = await d
    .select()
    .from(schema.vorgaenge)
    .where(
      and(
        eq(schema.vorgaenge.zustand, 'warte_auf_andere'),
        lte(schema.vorgaenge.naechsteErinnerung, jetzt),
      ),
    );

  for (const vorgang of wartend) {
    if (vorgang.erinnerungenGesendet >= konfig.maxErinnerungen) {
      await setzeZustand(vorgang.id, 'warte_auf_mich', { naechsteErinnerung: null });
      await protokolliere(
        vorgang.nutzerId,
        vorgang.id,
        'Nachfassen beendet',
        `Nach ${vorgang.erinnerungenGesendet} Erinnerungen ohne Antwort uebernimmt wieder die Nutzerin.`,
      );
      continue;
    }
    try {
      await erzeugeErinnerung(vorgang, jetzt);
      ergebnis.erinnerungen++;
    } catch {
      ergebnis.fehler++;
    }
  }

  return ergebnis;
}

async function erzeugeErinnerung(vorgang: Vorgang, jetzt: Date): Promise<void> {
  const d = await db();
  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, vorgang.nutzerId))
    .limit(1);
  if (!nutzer) return;

  const letzte = await letzteNachricht(vorgang.id);
  const tage = letzte
    ? Math.round((jetzt.getTime() - letzte.zeitpunkt.getTime()) / 86_400_000)
    : konfig.nachfassenNachTagen;

  const entwurf = await entwurfNachfassen({
    gegenueberName: vorgang.gegenueberName,
    betreff: letzte ? antwortBetreff(letzte.betreff) : vorgang.titel,
    bisherigerVerlauf: letzte?.text.slice(0, 1500) ?? '',
    tageOhneAntwort: tage,
    wievielteErinnerung: vorgang.erinnerungenGesendet + 1,
    zeitzone: nutzer.zeitzone,
    nutzerName: nutzer.name ?? '',
  });

  const regel = await findeRegel(nutzer.id, vorgang.gegenueberEmail, 'nachfassen');
  const automatisch = darfAutomatischSenden(regel);
  const uebergang = naechsterZustand(vorgang.zustand, {
    art: 'erinnerung_faellig',
    darf_automatisch: automatisch,
  });

  const header = letzte
    ? antwortHeader({ messageId: letzte.messageId, referenzen: letzte.referenzen })
    : { inReplyTo: null, referenzen: null };

  await d.insert(schema.ausgang).values({
    vorgangId: vorgang.id,
    an: vorgang.gegenueberEmail ?? '',
    betreff: entwurf.betreff,
    text: mitSignatur(entwurf.text, nutzer),
    inReplyTo: header.inReplyTo,
    referenzen: header.referenzen,
    // Ein Entwurf hat keine Haltezeit — die beginnt erst mit dem Klick.
    haltenBis: uebergang.wirkung === 'in_ausgang_legen' ? haltenBis() : NIE,
    status: uebergang.wirkung === 'in_ausgang_legen' ? 'gehalten' : 'entwurf',
  });

  await d
    .update(schema.vorgaenge)
    .set({
      zustand: uebergang.zustand,
      erinnerungenGesendet: vorgang.erinnerungenGesendet + 1,
      naechsteErinnerung: new Date(jetzt.getTime() + konfig.nachfassenNachTagen * 86_400_000),
      geaendertAm: jetzt,
    })
    .where(eq(schema.vorgaenge.id, vorgang.id));

  await protokolliere(
    nutzer.id,
    vorgang.id,
    automatisch ? 'Erinnerung erstellt, Automatik aktiv' : 'Erinnerung erstellt, wartet auf Freigabe',
    `${entwurf.betreff}\n\n${entwurf.text}`,
  );
}

// ---------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------

export function neueUid(): string {
  return `${crypto.randomUUID()}@${konfig.mailDomain}`;
}

function haltenBis(): Date {
  return new Date(Date.now() + konfig.haltezeitSekunden * 1000);
}

/**
 * Platzhalter fuer "hat keine Haltezeit". Nicht Date(8.64e15) — der
 * groesste gueltige JS-Zeitpunkt liegt jenseits dessen, was Postgres in
 * timestamptz abbilden kann, und faellt beim Schreiben um.
 */
const NIE = new Date('9999-12-31T00:00:00Z');

function zerlegeIsoDatum(iso: string): [number, number, number] {
  const [j, m, t] = iso.split('-').map(Number);
  return [j ?? 1970, m ?? 1, t ?? 1];
}

export function beschreibePlatzierung(status: string): string {
  switch (status) {
    case 'placed':
      return 'steht im Kalender (bestaetigt)';
    case 'dispatched':
      return 'Einladung verschickt (Eintrag nicht bestaetigt)';
    case 'published':
      return 'im Feed veroeffentlicht (Abruf nicht bestaetigt)';
    default:
      return status;
  }
}

function mitSignatur(text: string, nutzer: Nutzer): string {
  // Es wird NICHT in Katrins Namen von ihrer Adresse gesendet. Die Signatur
  // sagt offen, wer hier schreibt (Entwurf, Abschnitt 6).
  return `${text.trim()}\n\nMit freundlichen Gruessen\nAssistenz${
    nutzer.name ? ` von ${nutzer.name}` : ''
  }\n\n--\nDiese Nachricht wurde von einem Assistenzsystem verfasst und vor dem Versand freigegeben.`;
}

async function findeOderErstelleVorgang(
  nutzer: Nutzer,
  mail: EingehendeMail,
): Promise<Vorgang> {
  const d = await db();
  const [vorhanden] = await d
    .select()
    .from(schema.vorgaenge)
    .where(
      and(
        eq(schema.vorgaenge.nutzerId, nutzer.id),
        eq(schema.vorgaenge.threadKey, mail.threadKey),
      ),
    )
    .limit(1);
  if (vorhanden) return vorhanden;

  const [neu] = await d
    .insert(schema.vorgaenge)
    .values({
      nutzerId: nutzer.id,
      art: 'termin',
      zustand: 'neu',
      titel: mail.betreff,
      gegenueberEmail: mail.von,
      gegenueberName: mail.vonName,
      threadKey: mail.threadKey,
    })
    .returning();
  return neu!;
}

async function speichereNachricht(vorgangId: string, mail: EingehendeMail): Promise<void> {
  const d = await db();
  const [nachricht] = await d
    .insert(schema.nachrichten)
    .values({
      vorgangId,
      richtung: 'ein',
      messageId: mail.messageId,
      inReplyTo: mail.inReplyTo,
      referenzen: mail.referenzen,
      von: mail.von,
      an: mail.an.join(', '),
      betreff: mail.betreff,
      text: mail.text,
    })
    .returning();

  for (const anhang of mail.anhaenge) {
    await d.insert(schema.anhaenge).values({
      nachrichtId: nachricht!.id,
      dateiname: anhang.dateiname,
      mimeTyp: anhang.mimeTyp,
      groesseBytes: anhang.groesseBytes,
      textExtrakt: anhang.textExtrakt,
      extraktionFehlgeschlagen: anhang.extraktionFehlgeschlagen,
    });
  }
}

async function setzeZustand(
  vorgangId: string,
  zustand: Vorgang['zustand'],
  extra: Partial<typeof schema.vorgaenge.$inferInsert> = {},
): Promise<void> {
  const d = await db();
  await d
    .update(schema.vorgaenge)
    .set({ zustand, geaendertAm: new Date(), ...extra })
    .where(eq(schema.vorgaenge.id, vorgangId));
}

export async function protokolliere(
  nutzerId: string,
  vorgangId: string | null,
  was: string,
  details?: string,
): Promise<void> {
  const d = await db();
  await d.insert(schema.protokoll).values({ nutzerId, vorgangId, was, details });
}

async function neuesterEntwurf(vorgangId: string) {
  const d = await db();
  const [eintrag] = await d
    .select()
    .from(schema.ausgang)
    .where(eq(schema.ausgang.vorgangId, vorgangId))
    .orderBy(desc(schema.ausgang.erstelltAm))
    .limit(1);
  return eintrag;
}

async function letzteNachricht(vorgangId: string) {
  const d = await db();
  const [eintrag] = await d
    .select()
    .from(schema.nachrichten)
    .where(eq(schema.nachrichten.vorgangId, vorgangId))
    .orderBy(desc(schema.nachrichten.zeitpunkt))
    .limit(1);
  return eintrag;
}

/** Kalenderkanal einer Nutzerin: Lesen und Schreiben koennen getrennt sein. */
async function kalenderKanal(nutzerId: string): Promise<{
  source: CalendarSource | null;
  sink: CalendarSink | null;
  verbindungId: string;
} | null> {
  const d = await db();
  const verbindungen = await d
    .select()
    .from(schema.kalenderVerbindungen)
    .where(
      and(
        eq(schema.kalenderVerbindungen.nutzerId, nutzerId),
        isNull(schema.kalenderVerbindungen.widerrufenAm),
      ),
    )
    .orderBy(asc(schema.kalenderVerbindungen.erstelltAm));

  if (verbindungen.length === 0) return null;

  let source: CalendarSource | null = null;
  let sink: CalendarSink | null = null;
  for (const verbindung of verbindungen) {
    if (!source) {
      try {
        source = baueSource(verbindung);
      } catch {
        /* Kanal kann nicht lesen — der naechste vielleicht. */
      }
    }
    if (!sink) {
      try {
        sink = baueSink(verbindung);
      } catch {
        /* Kanal kann nicht schreiben. */
      }
    }
  }
  return { source, sink, verbindungId: verbindungen[0]!.id };
}

async function merkeVerbindungOk(id: string): Promise<void> {
  const d = await db();
  await d
    .update(schema.kalenderVerbindungen)
    .set({ lastOkAt: new Date(), lastError: null, lastErrorAt: null })
    .where(eq(schema.kalenderVerbindungen.id, id));
}

async function merkeVerbindungFehler(id: string, grund: string): Promise<void> {
  const d = await db();
  await d
    .update(schema.kalenderVerbindungen)
    .set({ lastError: grund, lastErrorAt: new Date() })
    .where(eq(schema.kalenderVerbindungen.id, id));
}

async function findeRegel(nutzerId: string, empfaenger: string | null, art: VorgangsArt) {
  if (!empfaenger) return null;
  const d = await db();
  const [regel] = await d
    .select()
    .from(schema.regeln)
    .where(
      and(
        eq(schema.regeln.nutzerId, nutzerId),
        eq(schema.regeln.empfaenger, empfaenger),
        eq(schema.regeln.aktionstyp, art),
      ),
    )
    .limit(1);
  return regel ?? null;
}

/** Jede bestaetigte Sendung zaehlt auf das Automatik-Angebot ein. */
async function zaehleBestaetigung(
  nutzerId: string,
  empfaenger: string,
  art: VorgangsArt,
): Promise<void> {
  const d = await db();
  const vorhanden = await findeRegel(nutzerId, empfaenger, art);
  if (vorhanden) {
    await d
      .update(schema.regeln)
      .set({
        bestaetigteSendungen: vorhanden.bestaetigteSendungen + 1,
        geaendertAm: new Date(),
      })
      .where(eq(schema.regeln.id, vorhanden.id));
  } else {
    await d
      .insert(schema.regeln)
      .values({ nutzerId, empfaenger, aktionstyp: art, bestaetigteSendungen: 1 });
  }
}

async function zaehleAbgeschlossen(nutzerId: string): Promise<void> {
  const d = await db();
  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, nutzerId))
    .limit(1);
  if (!nutzer) return;
  await d
    .update(schema.nutzer)
    .set({ abgeschlosseneVorgaenge: nutzer.abgeschlosseneVorgaenge + 1 })
    .where(eq(schema.nutzer.id, nutzerId));
}

/**
 * Vorschlaege liegen in der Datenbank, nicht im Prozessspeicher.
 *
 * Zwischen dem Vorschlag und der Zusage ("Dienstag passt") liegen Stunden
 * oder Tage. Auf einer Plattform, die Instanzen jederzeit einfriert, waere
 * eine Map im Speicher genau dann leer, wenn sie gebraucht wird — die
 * Zusage liefe ins Leere und die Nutzerin saehe einen kaputten Vorgang.
 *
 * Deshalb sind Vorschlaege echte Termine mit platzierungsStatus 'offen'.
 * Ihre UID wird schon hier vergeben, nicht erst bei der Zusage: damit
 * traegt der spaeter bestaetigte Termin dieselbe UID, unter der er
 * vorgeschlagen wurde — Voraussetzung fuer den iMIP-Weg (Entscheidung 1).
 */
async function merkeVorschlaege(
  vorgangId: string,
  slots: Slot[],
  zeitzone: string,
  titel: string,
): Promise<void> {
  const d = await db();

  // Aeltere, nicht angenommene Vorschlaege desselben Vorgangs verfallen.
  await d
    .delete(schema.termine)
    .where(
      and(
        eq(schema.termine.vorgangId, vorgangId),
        eq(schema.termine.platzierungsStatus, 'offen'),
      ),
    );

  for (const slot of slots) {
    await d.insert(schema.termine).values({
      vorgangId,
      uid: neueUid(),
      sequence: 0,
      titel,
      von: slot.start,
      bis: slot.ende,
      zeitzone,
      platzierungsStatus: 'offen',
    });
  }

  const nutzerId = await vorgangNutzer(vorgangId);
  if (nutzerId) {
    await protokolliere(
      nutzerId,
      vorgangId,
      'Termine vorgeschlagen',
      slots.map((s, i) => `${i + 1}. ${formatiereDeutsch(s.start, zeitzone)} Uhr`).join('\n'),
    );
  }
}

/** Die offenen Vorschlaege eines Vorgangs, stabil nach Zeit sortiert. */
async function geladeneVorschlaege(vorgangId: string) {
  const d = await db();
  return d
    .select()
    .from(schema.termine)
    .where(
      and(
        eq(schema.termine.vorgangId, vorgangId),
        eq(schema.termine.platzierungsStatus, 'offen'),
      ),
    )
    .orderBy(asc(schema.termine.von));
}

async function offeneVorschlaege(vorgangId: string, zeitzone: string): Promise<string[]> {
  const vorschlaege = await geladeneVorschlaege(vorgangId);
  return vorschlaege.map((t) => `${formatiereDeutsch(t.von, zeitzone)} Uhr`);
}

async function vorgangNutzer(vorgangId: string): Promise<string | null> {
  const d = await db();
  const [vorgang] = await d
    .select({ nutzerId: schema.vorgaenge.nutzerId })
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.id, vorgangId))
    .limit(1);
  return vorgang?.nutzerId ?? null;
}

export { VerbindungGebrochen };
