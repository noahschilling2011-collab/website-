import crypto from 'node:crypto';
import { and, desc, eq, gt, isNull } from 'drizzle-orm';
import { cookies } from 'next/headers';
import { db, schema } from '../db/index';
import type { Nutzer } from '../db/schema';
import { gleich, hashe, hasheMitSchluessel, zufallsCode, zufallsToken } from './krypto';
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
 * Eine Anmeldung per Mail passt ausserdem zum Produkt: es ist ein
 * Mail-Produkt, die Nutzerin hat ihr Postfach ohnehin offen.
 *
 * Der Weg hinein ist ein sechsstelliger CODE zum Abtippen; in derselben Mail
 * steht zusaetzlich ein Link. Der Code ist der Weg, der immer funktioniert:
 * ein Link, den das Mailprogramm in seinem eigenen eingebauten Browser
 * oeffnet, meldet in einer Sitzung an, die die Nutzerin anschliessend nicht
 * wiederfindet. Der Code hat dieses Problem nicht.
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

/** Wie lange ein Code und der zugehoerige Link gelten. */
export const CODE_GUELTIG_MINUTEN = 15;
/** So viele Fehlversuche, dann ist der Code verbraucht. */
export const MAX_VERSUCHE = 5;
/** Kein zweiter Code vor Ablauf dieser Zeit. */
const SPERRE_SEKUNDEN = 60;
/** So viele Codes pro Adresse und Stunde. */
const MAX_PRO_STUNDE = 5;

export type AnmeldeErgebnis =
  | { ok: true }
  /** Zu schnell hintereinander — die alte Mail gilt noch. */
  | { ok: false; grund: 'zu_haeufig' };

/**
 * Schickt den sechsstelligen Anmeldecode. Im Attrappen-Modus landet er auf
 * der Konsole.
 *
 * In derselben Mail steht zusaetzlich ein Link. Der Code ist der Weg, der
 * immer funktioniert — ein Link, den das Mailprogramm in seinem eigenen
 * eingebauten Browser oeffnet, landet in einer Sitzung, die niemand sieht.
 * Beide gehoeren zu EINEM Eintrag und werden gemeinsam entwertet.
 *
 * Es gibt keine getrennte Registrierung: wer sich zum ersten Mal anmeldet,
 * bekommt beim Einloesen ein Konto. Deshalb verraet diese Funktion auch
 * nichts darueber, ob eine Adresse bekannt ist — es gibt nichts zu verraten.
 */
export async function sendeAnmeldeCode(email: string): Promise<AnmeldeErgebnis> {
  const d = await db();
  const adresse = email.toLowerCase().trim();
  const jetzt = new Date();

  // Zwei Bremsen. Die erste verhindert, dass ein Doppelklick zwei Mails
  // ausloest und die zweite Mail die erste entwertet. Die zweite begrenzt,
  // wie viele Rateversuche sich jemand durch immer neue Codes erkaufen kann
  // — der eigentliche Grund, warum ein sechsstelliger Code hier reicht.
  const offen = await d
    .select()
    .from(schema.anmeldeTokens)
    .where(eq(schema.anmeldeTokens.email, adresse));

  const letzter = offen
    .filter((e) => !e.eingeloestAm && e.gueltigBis > jetzt)
    .sort((a, b) => b.erstelltAm.getTime() - a.erstelltAm.getTime())[0];
  if (letzter && jetzt.getTime() - letzter.erstelltAm.getTime() < SPERRE_SEKUNDEN * 1000) {
    return { ok: false, grund: 'zu_haeufig' };
  }

  const letzteStunde = offen.filter(
    (e) => jetzt.getTime() - e.erstelltAm.getTime() < 3_600_000,
  );
  if (letzteStunde.length >= MAX_PRO_STUNDE) {
    return { ok: false, grund: 'zu_haeufig' };
  }

  const token = zufallsToken();
  const code = zufallsCode();

  await d.insert(schema.anmeldeTokens).values({
    email: adresse,
    tokenHash: hashe(token),
    codeHash: hasheMitSchluessel(code),
    gueltigBis: new Date(jetzt.getTime() + CODE_GUELTIG_MINUTEN * 60_000),
  });

  const link = `${konfig.appUrl}/anmelden/${token}`;
  await mailVersand().sende({
    an: email,
    betreff: `${code} ist Ihr Anmeldecode`,
    text: [
      'Guten Tag,',
      '',
      'Ihr Anmeldecode lautet:',
      '',
      `    ${code}`,
      '',
      `Er gilt ${CODE_GUELTIG_MINUTEN} Minuten und nur einmal.`,
      '',
      'Wenn Sie lieber klicken: dieser Link meldet Sie direkt an.',
      '',
      link,
      '',
      'Wenn Sie das nicht angefordert haben, ignorieren Sie diese Mail. Ohne',
      'den Code oder den Link passiert nichts.',
    ].join('\n'),
  });

  return { ok: true };
}

/**
 * Diese beiden Funktionen setzen KEINE Sitzung.
 *
 * Das Cookie zu setzen ist Sache des Randes — einer Server Action oder eines
 * Route Handlers. Zwei Gruende: Next.js erlaubt `cookies().set()` ohnehin nur
 * dort, und die Pruefung von Zugangsdaten laesst sich so ohne Request-Kontext
 * testen. Bei Anmeldecode gegen Fehlversuchszaehler ist das keine
 * Kleinigkeit: das ist der Teil, der Tests am dringendsten braucht.
 */

export type CodeErgebnis =
  | { ok: true; nutzer: Nutzer }
  | { ok: false; grund: 'falsch' | 'abgelaufen' | 'zu_viele_versuche' };

/**
 * Prueft den abgetippten Code.
 *
 * Gesucht wird ueber die MAILADRESSE, nicht ueber den Codewert. Der
 * Unterschied ist der Kern der Sache: wuerde nur nach dem Code gesucht,
 * traefe ein geratenes "000000" irgendeinen gerade offenen Code
 * irgendeiner Nutzerin. Bei einer Million Moeglichkeiten und genuegend
 * gleichzeitig offenen Codes ist das keine theoretische Sorge. So gilt jeder
 * Versuch genau einem Konto — und wird dort mitgezaehlt.
 */
export async function loeseCodeEin(email: string, code: string): Promise<CodeErgebnis> {
  const d = await db();
  const adresse = email.toLowerCase().trim();
  const eingabe = code.replace(/\D/g, '');

  const [eintrag] = await d
    .select()
    .from(schema.anmeldeTokens)
    .where(
      and(
        eq(schema.anmeldeTokens.email, adresse),
        isNull(schema.anmeldeTokens.eingeloestAm),
        gt(schema.anmeldeTokens.gueltigBis, new Date()),
      ),
    )
    .orderBy(desc(schema.anmeldeTokens.erstelltAm))
    .limit(1);

  if (!eintrag || !eintrag.codeHash) return { ok: false, grund: 'abgelaufen' };

  if (eintrag.versuche >= MAX_VERSUCHE) {
    return { ok: false, grund: 'zu_viele_versuche' };
  }

  if (eingabe.length !== 6 || !gleich(hasheMitSchluessel(eingabe), eintrag.codeHash)) {
    const versuche = eintrag.versuche + 1;
    await d
      .update(schema.anmeldeTokens)
      .set({
        versuche,
        // Aufgebraucht heisst aufgebraucht: der Eintrag wird sofort
        // entwertet, nicht erst beim naechsten Versuch geprueft.
        eingeloestAm: versuche >= MAX_VERSUCHE ? new Date() : null,
      })
      .where(eq(schema.anmeldeTokens.id, eintrag.id));
    return { ok: false, grund: versuche >= MAX_VERSUCHE ? 'zu_viele_versuche' : 'falsch' };
  }

  await d
    .update(schema.anmeldeTokens)
    .set({ eingeloestAm: new Date() })
    .where(eq(schema.anmeldeTokens.id, eintrag.id));

  const nutzer = await findeOderLegeAn(eintrag.email);
  return { ok: true, nutzer };
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

  return findeOderLegeAn(eintrag.email);
}

async function findeOderLegeAn(email: string): Promise<Nutzer> {
  const d = await db();
  const [vorhanden] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.email, email))
    .limit(1);
  return vorhanden ?? (await legeNutzerAn(email));
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

/**
 * Name, Wert und Optionen des Sitzungscookies — ohne es zu setzen.
 *
 * Es gibt zwei Orte, an denen das Cookie gesetzt wird, und sie brauchen
 * verschiedene Wege: eine Server Action schreibt in den `cookies()`-Speicher,
 * ein Route Handler, der seine EIGENE Antwort zurueckgibt, muss es auf diese
 * Antwort setzen. Aenderungen am `cookies()`-Speicher landen dort nicht
 * zuverlaessig — der Anmeldelink hat deshalb zwar ein Cookie erzeugt, aber
 * keine Anmeldung: der Browser bekam es nicht.
 *
 * Beide Wege holen sich die Werte hier, damit sie nicht auseinanderlaufen.
 */
export function sitzungsKeks(nutzerId: string): {
  name: string;
  wert: string;
  optionen: {
    httpOnly: true;
    sameSite: 'lax';
    secure: boolean;
    path: '/';
    maxAge: number;
  };
} {
  const ablauf = Date.now() + GUELTIG_TAGE * 86_400_000;
  return {
    name: COOKIE,
    wert: signiere(`${nutzerId}|${ablauf}`),
    optionen: {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
      maxAge: GUELTIG_TAGE * 86_400,
    },
  };
}

/** Fuer Server Actions. Route Handler benutzen `sitzungsKeks` direkt. */
export async function setzeSitzung(nutzerId: string): Promise<void> {
  const keks = sitzungsKeks(nutzerId);
  const laden = await cookies();
  laden.set(keks.name, keks.wert, keks.optionen);
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
