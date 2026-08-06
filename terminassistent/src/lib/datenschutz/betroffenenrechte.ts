import { and, eq, inArray, isNotNull, isNull, lte } from 'drizzle-orm';
import { db, schema } from '../../db/index';
import { konfig } from '../konfig';
import { entschluessle } from '../krypto';
import { mailVersand } from '../mail/ausgang';
import {
  FRISTEN,
  kontoStand,
  protokollLoeschreif,
  protokollWortlautReif,
  tokenLoeschreif,
  verbindungLoeschreif,
  vorgangLoeschreif,
} from './aufbewahrung';

/**
 * Die Betroffenenrechte, soweit sie Code sind.
 *
 * Bewusst OHNE Abhaengigkeit auf vorgang/engine.ts: die Engine ruft das
 * Aufraeumen im Takt auf, und ein Kreis aus zwei Modulen, die einander
 * importieren, waere hier besonders unangenehm — Loeschen darf nicht davon
 * abhaengen, dass der Rest der Anwendung laedt.
 */

export interface Geloescht {
  tokens: number;
  vorgaenge: number;
  protokollWortlaut: number;
  protokollEintraege: number;
  verbindungen: number;
  konten: number;
  vorwarnungen: number;
}

// ---------------------------------------------------------------------------
// Art. 5 Abs. 1 lit. e — Speicherbegrenzung
// ---------------------------------------------------------------------------

/**
 * Laeuft im Takt mit, nicht als eigener Betriebsjob.
 *
 * Ein Loeschjob, den jemand getrennt einrichten muss, ist der erste, den
 * niemand einrichtet. Er haengt deshalb an demselben Cron, der ohnehin
 * laufen muss, damit ueberhaupt Post rausgeht.
 *
 * Die Auswahl passiert grob in SQL und fein in reinen Funktionen aus
 * aufbewahrung.ts. Das kostet ein paar Zeilen mehr, macht aber die
 * Grenzfaelle testbar — vor allem den, dass ein laengst abgeschlossener
 * Vorgang mit einer Frist in der Zukunft bleiben muss.
 */
export async function raeumeAuf(jetzt: Date): Promise<Geloescht> {
  const d = await db();
  const geloescht: Geloescht = {
    tokens: 0,
    vorgaenge: 0,
    protokollWortlaut: 0,
    protokollEintraege: 0,
    verbindungen: 0,
    konten: 0,
    vorwarnungen: 0,
  };

  // 1. Anmelde-Tokens.
  const tokens = await d.select().from(schema.anmeldeTokens);
  const faelligeTokens = tokens.filter((t) => tokenLoeschreif(t, jetzt)).map((t) => t.id);
  if (faelligeTokens.length > 0) {
    await d.delete(schema.anmeldeTokens).where(inArray(schema.anmeldeTokens.id, faelligeTokens));
    geloescht.tokens = faelligeTokens.length;
  }

  // 2. Abgeschlossene Vorgaenge samt allem, was per Fremdschluessel daran
  //    haengt: Nachrichten, Anhaenge, Termine, Ausgang.
  const abgeschlossen = await d
    .select()
    .from(schema.vorgaenge)
    .where(
      and(
        inArray(schema.vorgaenge.zustand, ['erledigt', 'abgebrochen', 'fehler']),
        lte(schema.vorgaenge.geaendertAm, new Date(jetzt.getTime() - FRISTEN.vorgangTage * 86_400_000)),
      ),
    );
  const faelligeVorgaenge = abgeschlossen
    .filter((v) => vorgangLoeschreif(v, jetzt))
    .map((v) => v.id);
  if (faelligeVorgaenge.length > 0) {
    await d.delete(schema.vorgaenge).where(inArray(schema.vorgaenge.id, faelligeVorgaenge));
    geloescht.vorgaenge = faelligeVorgaenge.length;
  }

  // 3. Das Protokoll in zwei Stufen: erst der Wortlaut, dann der Eintrag.
  const alteEintraege = await d
    .select()
    .from(schema.protokoll)
    .where(
      lte(
        schema.protokoll.zeitpunkt,
        new Date(jetzt.getTime() - FRISTEN.protokollWortlautTage * 86_400_000),
      ),
    );

  const ohneWortlaut = alteEintraege
    .filter((e) => protokollWortlautReif(e, jetzt) && !protokollLoeschreif(e, jetzt))
    .map((e) => e.id);
  if (ohneWortlaut.length > 0) {
    await d
      .update(schema.protokoll)
      .set({ details: null })
      .where(inArray(schema.protokoll.id, ohneWortlaut));
    geloescht.protokollWortlaut = ohneWortlaut.length;
  }

  const ganzWeg = alteEintraege.filter((e) => protokollLoeschreif(e, jetzt)).map((e) => e.id);
  if (ganzWeg.length > 0) {
    await d.delete(schema.protokoll).where(inArray(schema.protokoll.id, ganzWeg));
    geloescht.protokollEintraege = ganzWeg.length;
  }

  // 4. Widerrufene Kalenderverbindungen.
  const widerrufen = await d
    .select()
    .from(schema.kalenderVerbindungen)
    .where(isNotNull(schema.kalenderVerbindungen.widerrufenAm));
  const faelligeVerbindungen = widerrufen
    .filter((v) => verbindungLoeschreif(v, jetzt))
    .map((v) => v.id);
  if (faelligeVerbindungen.length > 0) {
    await d
      .delete(schema.kalenderVerbindungen)
      .where(inArray(schema.kalenderVerbindungen.id, faelligeVerbindungen));
    geloescht.verbindungen = faelligeVerbindungen.length;
  }

  // 5. Ruhende Konten — mit Vorwarnung, nie ohne.
  const { geloeschteKonten, vorwarnungen } = await behandleRuhendeKonten(jetzt);
  geloescht.konten = geloeschteKonten;
  geloescht.vorwarnungen = vorwarnungen;

  return geloescht;
}

/**
 * Ein Konto, das zwei Jahre lang niemand angefasst hat, hat keinen Zweck
 * mehr. Es einfach zu loeschen waere trotzdem falsch: die Nutzerin bekommt
 * vier Wochen vorher eine Mail, und jede Anmeldung setzt die Uhr zurueck.
 */
async function behandleRuhendeKonten(
  jetzt: Date,
): Promise<{ geloeschteKonten: number; vorwarnungen: number }> {
  const d = await db();
  const alle = await d.select().from(schema.nutzer);
  let geloeschteKonten = 0;
  let vorwarnungen = 0;

  for (const nutzer of alle) {
    const aktivitaet = await letzteAktivitaet(nutzer.id, nutzer.erstelltAm);
    const stand = kontoStand(nutzer, aktivitaet, jetzt);

    if (stand === 'loeschreif') {
      await loescheKonto(nutzer.id);
      geloeschteKonten++;
      continue;
    }

    if (stand !== 'vorwarnen') continue;

    // Nicht jede Minute erneut warnen: der Vermerk landet als
    // Protokolleintrag, dessen Vorhandensein die Wiederholung verhindert.
    const [schonGewarnt] = await d
      .select()
      .from(schema.protokoll)
      .where(
        and(
          eq(schema.protokoll.nutzerId, nutzer.id),
          eq(schema.protokoll.was, VORWARNUNG),
        ),
      )
      .limit(1);
    if (schonGewarnt) continue;

    const tageBis = FRISTEN.kontoRuhendTage - FRISTEN.kontoVorwarnungTage;
    try {
      await mailVersand().sende({
        an: nutzer.email,
        betreff: 'Ihr Konto wird in Kürze gelöscht',
        text: [
          `Guten Tag${nutzer.name ? ` ${nutzer.name}` : ''},`,
          '',
          `Ihr Konto beim Terminassistenten wurde seit ${Math.round(
            FRISTEN.kontoVorwarnungTage / 30,
          )} Monaten nicht mehr benutzt.`,
          `In ${tageBis} Tagen lösche ich es samt allen Mails, Terminen und dem Protokoll.`,
          '',
          'Wenn Sie das nicht möchten, melden Sie sich einfach einmal an:',
          konfig.appUrl,
          '',
          'Wenn Sie nichts tun, passiert die Löschung von selbst. Sie müssen nicht antworten.',
        ].join('\n'),
      });
      await d.insert(schema.protokoll).values({
        nutzerId: nutzer.id,
        vorgangId: null,
        was: VORWARNUNG,
        details: `Loeschung in ${tageBis} Tagen, wenn keine Anmeldung erfolgt.`,
      });
      vorwarnungen++;
    } catch {
      /* Naechster Takt versucht es erneut. */
    }
  }

  return { geloeschteKonten, vorwarnungen };
}

const VORWARNUNG = 'Vorwarnung wegen ruhendem Konto';

/**
 * Der spaeteste Zeitpunkt, an dem irgendetwas passiert ist. Ein Konto gilt
 * nicht als ruhend, nur weil gerade keine Mail kam — jede Aenderung an
 * einem Vorgang und jeder Protokolleintrag zaehlen mit.
 */
async function letzteAktivitaet(nutzerId: string, mindestens: Date): Promise<Date> {
  const d = await db();
  const zeitpunkte: Date[] = [mindestens];

  const vorgaenge = await d
    .select({ geaendertAm: schema.vorgaenge.geaendertAm })
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.nutzerId, nutzerId));
  zeitpunkte.push(...vorgaenge.map((v) => v.geaendertAm));

  const eintraege = await d
    .select({ zeitpunkt: schema.protokoll.zeitpunkt })
    .from(schema.protokoll)
    .where(eq(schema.protokoll.nutzerId, nutzerId));
  zeitpunkte.push(...eintraege.map((e) => e.zeitpunkt));

  return new Date(Math.max(...zeitpunkte.map((z) => z.getTime())));
}

// ---------------------------------------------------------------------------
// Art. 17 — Recht auf Loeschung
// ---------------------------------------------------------------------------

/**
 * Alles zu einer Nutzerin, wirklich alles.
 *
 * Die meisten Tabellen haengen per ON DELETE CASCADE am Nutzer. Zwei nicht,
 * und genau die waeren beim Loeschen sonst uebrig geblieben:
 *
 *   - `anmelde_tokens` haengt an der MAILADRESSE, nicht an der Nutzer-ID.
 *   - Das Zugriffsrecht auf den Google-Kalender liegt bei Google, nicht
 *     hier; eine geloeschte Zeile in unserer Datenbank nimmt es Google
 *     nicht weg.
 *
 * Was hier bewusst NICHT passiert: bereits eingetragene Termine im Kalender
 * der Nutzerin werden nicht abgesagt. Das sind ihre Termine in ihrem
 * Kalender. Ein Kontoschluss, der still ihren Wochenplan leerraeumt, waere
 * ein Uebergriff, kein Datenschutz.
 */
export async function loescheKonto(nutzerId: string): Promise<void> {
  const d = await db();

  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, nutzerId))
    .limit(1);
  if (!nutzer) return;

  const verbindungen = await d
    .select()
    .from(schema.kalenderVerbindungen)
    .where(
      and(
        eq(schema.kalenderVerbindungen.nutzerId, nutzerId),
        eq(schema.kalenderVerbindungen.kind, 'google_oauth'),
        isNull(schema.kalenderVerbindungen.widerrufenAm),
      ),
    );
  for (const verbindung of verbindungen) {
    await widerrufeBeiGoogle(verbindung.secretRef);
  }

  await d.delete(schema.anmeldeTokens).where(eq(schema.anmeldeTokens.email, nutzer.email));
  // Der Rest faellt ueber ON DELETE CASCADE mit: Verbindungen, Vorgaenge,
  // Nachrichten, Anhaenge, Termine, Ausgang, Regeln, Protokoll.
  await d.delete(schema.nutzer).where(eq(schema.nutzer.id, nutzerId));
}

/**
 * Das Refresh-Token bei Google entwerten.
 *
 * ACHTUNG — ungeprueft, wie der Stripe-Teil: hier gibt es kein
 * Google-Konto, gegen das sich das ausprobieren liesse. Der Endpunkt
 * stammt aus Googles Dokumentation. Scheitert der Aufruf, wird trotzdem
 * geloescht: das Recht der Nutzerin auf Loeschung haengt nicht daran, ob
 * ein fremder Server gerade erreichbar ist. Sie kann den Zugriff zusaetzlich
 * jederzeit selbst unter myaccount.google.com entziehen — das steht so auch
 * in der Oberflaeche.
 */
async function widerrufeBeiGoogle(secretRef: string): Promise<void> {
  try {
    const token = entschluessle(secretRef);
    await fetch('https://oauth2.googleapis.com/revoke', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ token }),
    });
  } catch {
    /* Siehe oben: die Loeschung laeuft so oder so weiter. */
  }
}

// ---------------------------------------------------------------------------
// Art. 15 und 20 — Auskunft und Datenuebertragbarkeit
// ---------------------------------------------------------------------------

/**
 * Alles, was ueber eine Nutzerin gespeichert ist, in einem maschinenlesbaren
 * Format (Art. 20 Abs. 1: "strukturiert, gaengig und maschinenlesbar").
 *
 * Zwei Felder fehlen bewusst und sind unten als `nichtEnthalten` benannt,
 * statt stillschweigend zu fehlen: der entschluesselte Inhalt der
 * Kalender-Geheimnisse und der Hash der Anmelde-Tokens. Ein Export, der
 * Zugangsdaten im Klartext in eine Datei schreibt, die anschliessend im
 * Download-Ordner liegt, waere das Gegenteil von Datenschutz.
 */
export async function exportiereDaten(nutzerId: string): Promise<Record<string, unknown>> {
  const d = await db();

  const [nutzer] = await d
    .select()
    .from(schema.nutzer)
    .where(eq(schema.nutzer.id, nutzerId))
    .limit(1);
  if (!nutzer) throw new Error('Nutzerin nicht gefunden.');

  const vorgaenge = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.nutzerId, nutzerId));
  const vorgangIds = vorgaenge.map((v) => v.id);

  const nachrichten = vorgangIds.length
    ? await d.select().from(schema.nachrichten).where(inArray(schema.nachrichten.vorgangId, vorgangIds))
    : [];
  const nachrichtIds = nachrichten.map((n) => n.id);

  return {
    erstelltAm: new Date().toISOString(),
    hinweis:
      'Export nach Art. 15 und 20 DSGVO. Enthaelt alles, was zu diesem Konto gespeichert ist.',
    nichtEnthalten: [
      'Die Zugangsdaten zu Ihrem Kalender (Refresh-Token bzw. geheime iCal-Adresse). Sie liegen verschluesselt und werden hier nicht entschluesselt — eine Datei im Download-Ordner ist der falsche Ort dafuer.',
      'Die Hashes abgelaufener Anmeldelinks.',
    ],
    konto: {
      email: nutzer.email,
      name: nutzer.name,
      handle: `${nutzer.handle}@${konfig.mailDomain}`,
      zeitzone: nutzer.zeitzone,
      arbeitszeiten: nutzer.arbeitszeiten,
      abgeschlosseneVorgaenge: nutzer.abgeschlosseneVorgaenge,
      zahlendSeit: nutzer.zahlendSeit,
      erstelltAm: nutzer.erstelltAm,
    },
    kalenderverbindungen: (
      await d
        .select()
        .from(schema.kalenderVerbindungen)
        .where(eq(schema.kalenderVerbindungen.nutzerId, nutzerId))
    ).map((v) => ({
      art: v.kind,
      erstelltAm: v.erstelltAm,
      widerrufenAm: v.widerrufenAm,
      zuletztErfolgreich: v.lastOkAt,
      letzterFehler: v.lastError,
    })),
    vorgaenge,
    nachrichten,
    anhaenge: nachrichtIds.length
      ? await d.select().from(schema.anhaenge).where(inArray(schema.anhaenge.nachrichtId, nachrichtIds))
      : [],
    termine: vorgangIds.length
      ? await d.select().from(schema.termine).where(inArray(schema.termine.vorgangId, vorgangIds))
      : [],
    ausgang: vorgangIds.length
      ? await d.select().from(schema.ausgang).where(inArray(schema.ausgang.vorgangId, vorgangIds))
      : [],
    regeln: await d.select().from(schema.regeln).where(eq(schema.regeln.nutzerId, nutzerId)),
    protokoll: await d
      .select()
      .from(schema.protokoll)
      .where(eq(schema.protokoll.nutzerId, nutzerId)),
  };
}
