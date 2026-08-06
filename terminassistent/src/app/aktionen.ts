'use server';

import { and, desc, eq } from 'drizzle-orm';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { db, schema } from '../db/index';
import { loescheKonto } from '../lib/datenschutz/betroffenenrechte';
import { verschluessle, zufallsToken } from '../lib/krypto';
import {
  eigenerVorgang,
  haltezeitAbbrechen,
  kompensiere,
  protokolliere,
  sendenAusloesen,
  verarbeiteEingang,
} from '../lib/vorgang/engine';
import { aktuelleNutzerin, beendeSitzung, sendeAnmeldeLink } from '../lib/sitzung';
import { starteCheckout, zahlungKonfiguriert } from '../lib/zahlung';

async function nutzerinOderRaus() {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');
  return nutzer;
}

export async function anmelden(formData: FormData): Promise<void> {
  const email = String(formData.get('email') ?? '').trim();
  if (!email.includes('@')) return;
  await sendeAnmeldeLink(email);
  redirect('/anmelden?gesendet=1');
}

export async function abmelden(): Promise<void> {
  await beendeSitzung();
  redirect('/anmelden');
}

/** Der eine Knopf auf dem Hauptbildschirm. Startet die Haltezeit. */
export async function senden(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  await sendenAusloesen(vorgangId, nutzer.id);
  revalidatePath('/');
  revalidatePath(`/vorgang/${vorgangId}`);
}

/** Innerhalb der Haltezeit. Danach hilft nur noch Kompensieren. */
export async function abbrechen(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  await haltezeitAbbrechen(vorgangId, nutzer.id);
  revalidatePath('/');
  revalidatePath(`/vorgang/${vorgangId}`);
}

/** Die Nutzerin darf jeden Entwurf umschreiben, bevor er rausgeht. */
export async function entwurfSpeichern(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  const text = String(formData.get('text') ?? '');
  const betreff = String(formData.get('betreff') ?? '');

  // Die Vorgangs-ID kommt aus einem versteckten Formularfeld. Ohne diese
  // Pruefung koennte jede angemeldete Person den Text umschreiben, den eine
  // fremde Nutzerin gleich abschickt.
  if (!(await eigenerVorgang(vorgangId, nutzer.id))) return;

  const d = await db();
  const [entwurf] = await d
    .select()
    .from(schema.ausgang)
    .where(eq(schema.ausgang.vorgangId, vorgangId))
    .orderBy(desc(schema.ausgang.erstelltAm))
    .limit(1);
  if (!entwurf || entwurf.status !== 'entwurf') return;

  await d
    .update(schema.ausgang)
    .set({ text, betreff })
    .where(eq(schema.ausgang.id, entwurf.id));

  await protokolliere(nutzer.id, vorgangId, 'Entwurf von Hand geaendert', text);
  revalidatePath(`/vorgang/${vorgangId}`);
}

/**
 * Die ausdrueckliche Zustimmung zur Automatik.
 *
 * Drei bestaetigte Sendungen erzeugen nur ein ANGEBOT. Erst dieser Klick
 * setzt automatisch auf true — Vertrauen wird verdient, nicht abgefragt.
 */
export async function automatikEinschalten(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  const empfaenger = String(formData.get('empfaenger'));
  const aktionstyp = String(formData.get('aktionstyp')) as 'nachfassen';

  const d = await db();
  await d
    .update(schema.regeln)
    .set({ automatisch: true, geaendertAm: new Date() })
    .where(
      and(
        eq(schema.regeln.nutzerId, nutzer.id),
        eq(schema.regeln.empfaenger, empfaenger),
        eq(schema.regeln.aktionstyp, aktionstyp),
      ),
    );

  await protokolliere(
    nutzer.id,
    vorgangId,
    'Automatik eingeschaltet',
    `Kuenftig geht "${aktionstyp}" an ${empfaenger} ohne Rueckfrage raus — weiterhin mit Haltezeit.`,
  );
  revalidatePath(`/vorgang/${vorgangId}`);
}

export async function automatikAusschalten(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  const empfaenger = String(formData.get('empfaenger'));
  const aktionstyp = String(formData.get('aktionstyp')) as 'nachfassen';

  const d = await db();
  await d
    .update(schema.regeln)
    .set({ automatisch: false, geaendertAm: new Date() })
    .where(
      and(
        eq(schema.regeln.nutzerId, nutzer.id),
        eq(schema.regeln.empfaenger, empfaenger),
        eq(schema.regeln.aktionstyp, aktionstyp),
      ),
    );
  await protokolliere(nutzer.id, vorgangId, 'Automatik ausgeschaltet', empfaenger);
  revalidatePath(`/vorgang/${vorgangId}`);
}

// ---------------------------------------------------------------------------
// Verbindungen
// ---------------------------------------------------------------------------

/** Weg B: die geheime iCal-Adresse zum Lesen. */
export async function icsVerbindungSpeichern(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const url = String(formData.get('url') ?? '').trim();
  if (!url.startsWith('http')) return;

  const d = await db();
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'ics_secret_url',
    secretRef: verschluessle(url),
    konfig: { pollIntervallSekunden: '900' },
  });

  // Weg B braucht zwei Haelften: lesen per Feed, schreiben per eigenem Abo.
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'ics_publish',
    secretRef: verschluessle('feed'),
    konfig: { token: zufallsToken(24) },
  });

  await protokolliere(
    nutzer.id,
    null,
    'Kalender verbunden (ICS)',
    'Lesen ueber die geheime iCal-Adresse, Schreiben ueber ein eigenes Abo.',
  );
  revalidatePath('/verbindungen');
}

/** Fuer die Demo: ein Kalender ohne jedes externe Konto. */
export async function attrappeVerbinden(): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const d = await db();
  await d.insert(schema.kalenderVerbindungen).values({
    nutzerId: nutzer.id,
    kind: 'attrappe',
    secretRef: verschluessle('attrappe'),
    konfig: {},
  });
  await protokolliere(
    nutzer.id,
    null,
    'Demo-Kalender verbunden',
    'Attrappe ohne externes Konto. Termine werden nirgends wirklich eingetragen.',
  );
  revalidatePath('/verbindungen');
}

export async function verbindungWiderrufen(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const id = String(formData.get('id'));
  const d = await db();
  await d
    .update(schema.kalenderVerbindungen)
    .set({ widerrufenAm: new Date() })
    .where(
      and(
        eq(schema.kalenderVerbindungen.id, id),
        eq(schema.kalenderVerbindungen.nutzerId, nutzer.id),
      ),
    );
  await protokolliere(nutzer.id, null, 'Kalenderverbindung widerrufen', id);
  revalidatePath('/verbindungen');
}

// ---------------------------------------------------------------------------
// Kompensieren
// ---------------------------------------------------------------------------

/**
 * "Das hätte so nicht rausgehen dürfen."
 *
 * Es gibt kein Rueckgaengig. Diese Aktion sagt einen etwaigen Termin ab
 * und legt einen Korrekturentwurf bereit — als Entwurf, denn auch die
 * Korrektur ist eine Mail an einen Menschen.
 */
export async function kompensieren(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const vorgangId = String(formData.get('vorgangId'));
  const grund = String(formData.get('grund') ?? '').trim();
  if (!grund) return;

  await kompensiere(vorgangId, nutzer.id, grund);
  revalidatePath('/');
  revalidatePath(`/vorgang/${vorgangId}`);
}

// ---------------------------------------------------------------------------
// Zahlung
// ---------------------------------------------------------------------------

export async function zahlungStarten(): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  if (!zahlungKonfiguriert()) {
    await protokolliere(
      nutzer.id,
      null,
      'Zahlung nicht eingerichtet',
      'STRIPE_SECRET_KEY und STRIPE_PREIS_ID fehlen.',
    );
    redirect('/?zahlung=nicht_eingerichtet');
  }

  const url = await starteCheckout({
    nutzerId: nutzer.id,
    email: nutzer.email,
    kundeId: nutzer.zahlungsKundeId,
  });
  redirect(url);
}

// ---------------------------------------------------------------------------
// Betroffenenrechte
// ---------------------------------------------------------------------------

/**
 * Art. 17 DSGVO, mit einem Riegel davor.
 *
 * Die Nutzerin muss ihre eigene Mailadresse tippen. Nicht als Ritual: der
 * Knopf steht auf derselben Seite wie der Export, und ein Fehlklick waere
 * hier nicht rueckgaengig zu machen — es gibt keinen Papierkorb und keine
 * Sicherung, aus der sich ein Konto zurueckholen liesse. Genau das ist ja
 * der Sinn der Loeschung.
 */
export async function kontoLoeschen(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const bestaetigung = String(formData.get('bestaetigung') ?? '').trim();
  if (bestaetigung.toLowerCase() !== nutzer.email.toLowerCase()) {
    redirect('/daten?fehler=bestaetigung');
  }

  await loescheKonto(nutzer.id);
  await beendeSitzung();
  redirect('/anmelden?geloescht=1');
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

/**
 * Spielt die Mail aus Abschnitt 2 des Entwurfs ein — den Dienstag, an dem
 * Katrin das Produkt zum ersten Mal oeffnet.
 */
export async function demoMailEinspielen(formData: FormData): Promise<void> {
  const nutzer = await nutzerinOderRaus();
  const art = String(formData.get('art') ?? 'termin');

  const nachrichten: Record<string, { von: string; betreff: string; text: string }> = {
    termin: {
      von: 'Sabine Berger <s.berger@example.test>',
      betreff: 'Termin Jonas am Donnerstag',
      text: 'Guten Tag Frau Weber,\n\nleider muss ich den Termin von Jonas am Donnerstag absagen. Haetten Sie in den naechsten zwei Wochen noch etwas frei?\n\nViele Gruesse\nSabine Berger',
    },
    frist: {
      von: 'Praxis Dr. Kaufmann <praxis@kaufmann.test>',
      betreff: 'Folgeverordnung Jonas Berger',
      text: 'Guten Tag,\n\nanbei die Folgeverordnung fuer Jonas Berger. Bitte beachten Sie, dass die Verordnung bis zum 18.08.2026 begonnen werden muss, Betrag 312,00 EUR.\n\nMit freundlichen Gruessen\nPraxis Dr. Kaufmann',
    },
  };

  const inhalt = nachrichten[art] ?? nachrichten.termin!;
  const roh = [
    `From: ${inhalt.von}`,
    `To: ${nutzer.handle}@${process.env.MAIL_DOMAIN ?? 'assistent.localhost'}`,
    `Subject: ${inhalt.betreff}`,
    `Message-ID: <demo-${Date.now()}@example.test>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    '',
    inhalt.text,
  ].join('\r\n');

  await verarbeiteEingang(roh);
  revalidatePath('/');
}
