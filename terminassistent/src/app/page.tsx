import { desc, eq } from 'drizzle-orm';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { db, schema } from '../db/index';
import type { AusgangsEintrag, Nutzer, Termin, Vorgang } from '../db/schema';
import { pruefeSchranke, zeigeHinweis } from '../lib/abrechnung';
import { konfig } from '../lib/konfig';
import { sortiere, stelleDar } from '../lib/vorgang/darstellung';
import { aktuelleNutzerin } from '../lib/sitzung';
import { abbrechen, demoMailEinspielen, senden, zahlungStarten } from './aktionen';

export const dynamic = 'force-dynamic';

/**
 * DER eine Bildschirm (Entwurf, Abschnitt 9).
 *
 * Eine Liste laufender Vorgaenge. Kein Chat, kein Posteingang, kein
 * Dashboard, keine Statistik, keine Suche, keine Ordner.
 *
 * Die Zeilen, die auf die Nutzerin warten, stehen oben und tragen den
 * einen Knopf.
 */
export default async function Startseite({
  searchParams,
}: {
  searchParams: Promise<{ zahlung?: string }>;
}) {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');

  const { zahlung } = await searchParams;
  const d = await db();
  const vorgaenge = await d
    .select()
    .from(schema.vorgaenge)
    .where(eq(schema.vorgaenge.nutzerId, nutzer.id))
    .orderBy(desc(schema.vorgaenge.geaendertAm))
    .limit(100);

  const angereichert = await Promise.all(
    vorgaenge.map(async (vorgang) => ({
      vorgang,
      ausgang: await neuesterAusgang(vorgang.id),
      termin: await neuesterTermin(vorgang.id),
    })),
  );

  const jetzt = new Date();
  const zeilen = sortiere(
    angereichert.map((e) => ({
      ...e,
      darstellung: stelleDar(e.vorgang, e.ausgang, e.termin, nutzer.zeitzone, jetzt),
    })),
  );

  const offen = zeilen.filter((z) => z.darstellung.dringend || z.darstellung.laeuft);
  const rest = zeilen.filter((z) => !z.darstellung.dringend && !z.darstellung.laeuft);

  return (
    <main>
      <div className="kopf">
        <div>
          <h1>Was gerade läuft</h1>
          <div className="leise">
            Weiterleiten an <code>{nutzer.handle}@{konfig.mailDomain}</code>
          </div>
        </div>
        <Link className="knopf leise-knopf" href="/verbindungen">
          Verbindungen
        </Link>
      </div>

      <ZahlungsRueckmeldung code={zahlung} />
      <AbrechnungsHinweis nutzer={nutzer} />
      {konfig.demoModus && <DemoHinweis />}

      {zeilen.length === 0 ? (
        <div className="leer">
          <p>Noch nichts da.</p>
          <p className="leise">
            Leiten Sie eine Mail an <code>{nutzer.handle}@{konfig.mailDomain}</code> weiter.
          </p>
        </div>
      ) : (
        <>
          {offen.length > 0 && (
            <>
              <div className="abschnitt">Wartet auf Sie</div>
              <div className="liste">
                {offen.map((z) => (
                  <Zeile key={z.vorgang.id} {...z} />
                ))}
              </div>
            </>
          )}
          {rest.length > 0 && (
            <>
              <div className="abschnitt">Läuft</div>
              <div className="liste">
                {rest.map((z) => (
                  <Zeile key={z.vorgang.id} {...z} />
                ))}
              </div>
            </>
          )}
        </>
      )}

      <div className="fuss">
        <Link href="/protokoll">Was ist bisher passiert</Link>
        <form action={abmeldenWrapper}>
          <button className="leise-knopf" type="submit">
            Abmelden
          </button>
        </form>
      </div>
    </main>
  );
}

function Zeile({
  vorgang,
  darstellung,
}: {
  vorgang: Vorgang;
  darstellung: ReturnType<typeof stelleDar>;
}) {
  const klasse = darstellung.dringend ? 'zeile dringend' : darstellung.laeuft ? 'zeile laeuft' : 'zeile';

  return (
    <div className={klasse}>
      <div className="zeile-kopf">
        <div>
          <div className="zeile-titel">
            <Link href={`/vorgang/${vorgang.id}`} style={{ textDecoration: 'none' }}>
              {vorgang.titel}
            </Link>
          </div>
          <div className="zeile-stand">{darstellung.stand}</div>
        </div>

        {darstellung.knopf === 'senden' && (
          <form action={senden}>
            <input type="hidden" name="vorgangId" value={vorgang.id} />
            <button type="submit">Senden</button>
          </form>
        )}
        {darstellung.knopf === 'abbrechen' && (
          <form action={abbrechen}>
            <input type="hidden" name="vorgangId" value={vorgang.id} />
            <button className="leise-knopf" type="submit">
              Abbrechen
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

/**
 * Die Bezahlaufforderung erscheint genau in dem Moment, in dem der sechste
 * Vorgang abgeschlossen waere — also nach nachweisbarem Nutzen, nicht davor.
 * Davor gibt es hoechstens einen leisen Zaehler, und auch den erst ab dem
 * drittletzten freien Vorgang.
 */
/**
 * Nach der Rueckkehr aus dem Bezahlvorgang. Nur feste Codes, kein Text aus
 * der Adresszeile — sonst koennte ein fremder Link der Nutzerin einen
 * beliebigen Satz auf ihrer eigenen Seite unterschieben.
 *
 * Ohne diesen Hinweis waere eine gescheiterte Zahlung nicht von einer
 * erfolgreichen zu unterscheiden: die Seite saehe in beiden Faellen
 * gleich aus.
 */
const ZAHLUNGSTEXTE: Record<string, string> = {
  aktiv: 'Das Abonnement ist aktiv. Alle Vorgänge werden wieder bearbeitet.',
  nicht_bestaetigt:
    'Die Zahlung konnte nicht bestätigt werden. Es wurde nichts freigeschaltet — falls doch abgebucht wurde, schreiben Sie mir.',
  unvollstaendig: 'Der Bezahlvorgang wurde ohne Ergebnis beendet.',
  fehler: 'Die Prüfung der Zahlung ist fehlgeschlagen. Einzelheiten stehen im Protokoll.',
  nicht_eingerichtet: 'Die Bezahlung ist auf diesem Server nicht eingerichtet.',
};

function ZahlungsRueckmeldung({ code }: { code: string | undefined }) {
  const text = code ? ZAHLUNGSTEXTE[code] : undefined;
  if (!text) return null;
  return <div className="hinweis">{text}</div>;
}

function AbrechnungsHinweis({ nutzer }: { nutzer: Nutzer }) {
  const schranke = pruefeSchranke(nutzer);
  const hinweis = zeigeHinweis(nutzer);
  if (!hinweis) return null;

  if (schranke.erlaubt) {
    return <p className="leise">{hinweis}</p>;
  }

  return (
    <div className="hinweis">
      <strong>{hinweis}</strong>
      <p style={{ marginTop: '0.35rem', marginBottom: '0.75rem' }}>
        Neue Mails werden weiterhin gespeichert, aber nicht mehr bearbeitet. 9 € im Monat,
        monatlich kündbar.
      </p>
      <form action={zahlungStarten}>
        <button type="submit">Abonnement abschließen</button>
      </form>
    </div>
  );
}

function DemoHinweis() {
  return (
    <div className="hinweis">
      <strong>Demo-Modus.</strong> Ohne <code>ANTHROPIC_API_KEY</code> und{' '}
      <code>RESEND_API_KEY</code> werden Texte regelbasiert erzeugt und Mails nur auf die
      Konsole geschrieben, nicht versendet.
      <div style={{ marginTop: '0.75rem', display: 'flex', gap: '0.5rem' }}>
        <form action={demoMailEinspielen}>
          <input type="hidden" name="art" value="termin" />
          <button className="leise-knopf" type="submit">
            Beispiel: Terminanfrage
          </button>
        </form>
        <form action={demoMailEinspielen}>
          <input type="hidden" name="art" value="frist" />
          <button className="leise-knopf" type="submit">
            Beispiel: Verordnung mit Frist
          </button>
        </form>
      </div>
    </div>
  );
}

async function abmeldenWrapper() {
  'use server';
  const { abmelden } = await import('./aktionen');
  await abmelden();
}

async function neuesterAusgang(vorgangId: string): Promise<AusgangsEintrag | null> {
  const d = await db();
  const [eintrag] = await d
    .select()
    .from(schema.ausgang)
    .where(eq(schema.ausgang.vorgangId, vorgangId))
    .orderBy(desc(schema.ausgang.erstelltAm))
    .limit(1);
  return eintrag ?? null;
}

async function neuesterTermin(vorgangId: string): Promise<Termin | null> {
  const d = await db();
  const [eintrag] = await d
    .select()
    .from(schema.termine)
    .where(eq(schema.termine.vorgangId, vorgangId))
    .orderBy(desc(schema.termine.erstelltAm))
    .limit(1);
  return eintrag ?? null;
}
