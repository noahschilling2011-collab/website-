import crypto from 'node:crypto';
import { and, eq, gt, isNull } from 'drizzle-orm';
import { cookies } from 'next/headers';
import { db, schema } from '../db/index';
import type { Nutzer } from '../db/schema';
import { hashe, zufallsToken } from './krypto';
import { konfig } from './konfig';
import { mailVersand } from './mail/ausgang';

/**
 * Anmeldung per Magic Link statt per Google-OAuth.
 *
 * ABWEICHUNG vom Entwurf, Abschnitt 6, wo "Auth.js v5 mit Google" steht.
 * Der Grund steht zwei Absaetze weiter oben im selben Entwurf: "der
 * einzige echte OAuth-Dialog ist der Kalender, und er kommt erst, wenn
 * der erste Termin geschrieben werden soll — nach dem ersten sichtbaren
 * Nutzen, nicht davor." Google-Login bei der Registrierung waere genau
 * der OAuth-Dialog, den der Entwurf nach hinten schieben will.
 *
 * Ein Magic Link passt ausserdem zum Produkt: es ist ein Mail-Produkt,
 * die Nutzerin hat ihr Postfach ohnehin offen.
 */

const COOKIE = 'sitzung';
const GUELTIG_TAGE = 30;

function signiere(wert: string): string {
  const geheim = process.env.SECRET_KEY ?? 'unsicherer-entwicklungsschluessel';
  const signatur = crypto.createHmac('sha256', geheim).update(wert).digest('base64url');
  return `${wert}.${signatur}`;
}

function pruefeSignatur(signiert: string): string | null {
  const index = signiert.lastIndexOf('.');
  if (index < 1) return null;
  const wert = signiert.slice(0, index);
  const erwartet = signiere(wert);
  const a = Buffer.from(signiert);
  const b = Buffer.from(erwartet);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  const [nutzerId, ablauf] = wert.split('|');
  if (!nutzerId || !ablauf || Number(ablauf) < Date.now()) return null;
  return nutzerId;
}

/** Schickt den Anmeldelink. Im Attrappen-Modus landet er auf der Konsole. */
export async function sendeAnmeldeLink(email: string): Promise<void> {
  const d = await db();
  const token = zufallsToken();

  await d.insert(schema.anmeldeTokens).values({
    email: email.toLowerCase().trim(),
    tokenHash: hashe(token),
    gueltigBis: new Date(Date.now() + 30 * 60_000),
  });

  const link = `${konfig.appUrl}/anmelden/${token}`;
  await mailVersand().sende({
    an: email,
    betreff: 'Ihr Anmeldelink',
    text: `Guten Tag,\n\nmit diesem Link melden Sie sich an:\n\n${link}\n\nDer Link gilt 30 Minuten und nur einmal.\n\nWenn Sie das nicht angefordert haben, ignorieren Sie diese Mail.`,
  });
}

/** Loest den Token ein und legt die Nutzerin bei Bedarf an. */
export async function loeseTokenEin(token: string): Promise<Nutzer | null> {
  const d = await db();
  const [eintrag] = await d
    .select()
    .from(schema.anmeldeTokens)
    .where(
      and(
        eq(schema.anmeldeTokens.tokenHash, hashe(token)),
        isNull(schema.anmeldeTokens.eingeloestAm),
        gt(schema.anmeldeTokens.gueltigBis, new Date()),
      ),
    )
    .limit(1);
  if (!eintrag) return null;

  // Einmalig: sofort entwerten, auch wenn danach etwas schiefgeht.
  await d
    .update(schema.anmeldeTokens)
    .set({ eingeloestAm: new Date() })
    .where(eq(schema.anmeldeTokens.id, eintrag.id));

  const [vorhanden] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.email, eintrag.email))
    .limit(1);

  const nutzer = vorhanden ?? (await legeNutzerAn(eintrag.email));
  await setzeSitzung(nutzer.id);
  return nutzer;
}

async function legeNutzerAn(email: string): Promise<Nutzer> {
  const d = await db();
  const basis = (email.split('@')[0] ?? 'nutzer').replace(/[^a-z0-9]/gi, '').toLowerCase();

  // Der Handle wird zur oeffentlichen Weiterleitungsadresse — er muss
  // eindeutig sein und darf nicht erraten werden koennen.
  let handle = basis || 'nutzer';
  for (let versuch = 0; versuch < 20; versuch++) {
    const [belegt] = await d
      .select({ id: schema.nutzer.id })
      .from(schema.nutzer)
      .where(eq(schema.nutzer.handle, handle))
      .limit(1);
    if (!belegt) break;
    handle = `${basis}${crypto.randomInt(100, 999)}`;
  }

  const [nutzer] = await d.insert(schema.nutzer).values({ email, handle }).returning();
  return nutzer!;
}

export async function setzeSitzung(nutzerId: string): Promise<void> {
  const ablauf = Date.now() + GUELTIG_TAGE * 86_400_000;
  const laden = await cookies();
  laden.set(COOKIE, signiere(`${nutzerId}|${ablauf}`), {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: GUELTIG_TAGE * 86_400,
  });
}

export async function beendeSitzung(): Promise<void> {
  const laden = await cookies();
  laden.delete(COOKIE);
}

export async function aktuelleNutzerin(): Promise<Nutzer | null> {
  const laden = await cookies();
  const roh = laden.get(COOKIE)?.value;
  if (!roh) return null;

  const nutzerId = pruefeSignatur(roh);
  if (!nutzerId) return null;

  const d = await db();
  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, nutzerId))
    .limit(1);
  return nutzer ?? null;
}
