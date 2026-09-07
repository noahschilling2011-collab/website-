import { count, eq, inArray } from 'drizzle-orm';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { db, schema } from '../../db/index';
import { FRISTEN } from '../../lib/datenschutz/aufbewahrung';
import { konfig } from '../../lib/konfig';
import { aktuelleNutzerin } from '../../lib/sitzung';
import { kontoLoeschen } from '../aktionen';

export const dynamic = 'force-dynamic';

/**
 * Die Betroffenenrechte als Bildschirm, nicht als Absatz in einer
 * Datenschutzerklaerung.
 *
 * Art. 15 und 20 verlangen Auskunft und Uebertragbarkeit, Art. 17 die
 * Loeschung. Ein Formular, in das man eine Mail an den Betreiber tippt,
 * erfuellt das formal; ein Knopf, der die Datei sofort herausgibt und ein
 * zweiter, der das Konto wirklich loescht, erfuellt es tatsaechlich. Bei
 * einem Ein-Personen-Betrieb ist das ausserdem der einzige Weg, der die
 * Fristen aus Art. 12 Abs. 3 sicher haelt: es gibt niemanden, der einen
 * Antrag bearbeiten koennte.
 */
export default async function Daten() {
  const nutzer = await aktuelleNutzerin();
  if (!nutzer) redirect('/anmelden');

  const bestand = await zaehleBestand(nutzer.id);

  return (
    <main>
      <div className="kopf">
        <div>
          <h1>Ihre Daten</h1>
          <div className="leise">Was hier liegt, wie lange, und wie Sie es loswerden.</div>
        </div>
        <Link className="knopf leise-knopf" href="/">
          Zurück
        </Link>
      </div>

      <div className="karte">
        <strong>Was gerade gespeichert ist</strong>
        <table style={{ marginTop: '0.6rem' }}>
          <tbody>
            <tr>
              <td>Vorgänge</td>
              <td className="leise">{bestand.vorgaenge}</td>
            </tr>
            <tr>
              <td>Mails (ein- und ausgehend)</td>
              <td className="leise">{bestand.nachrichten}</td>
            </tr>
            <tr>
              <td>Texte aus Anhängen</td>
              <td className="leise">{bestand.anhaenge}</td>
            </tr>
            <tr>
              <td>Termine</td>
              <td className="leise">{bestand.termine}</td>
            </tr>
            <tr>
              <td>Protokolleinträge</td>
              <td className="leise">{bestand.protokoll}</td>
            </tr>
          </tbody>
        </table>
        <p className="leise" style={{ marginTop: '0.75rem' }}>
          Der Anhang selbst wird nie gespeichert — nur der Text, den ich daraus lese. Die PDF
          ist nach der Verarbeitung weg.
        </p>
      </div>

      <div className="karte">
        <strong>Wann was von selbst verschwindet</strong>
        <table style={{ marginTop: '0.6rem' }}>
          <tbody>
            <tr>
              <td>Abgeschlossene Vorgänge mit allen Mails</td>
              <td className="leise">nach {FRISTEN.vorgangTage} Tagen</td>
            </tr>
            <tr>
              <td>Der Wortlaut im Protokoll</td>
              <td className="leise">nach {FRISTEN.protokollWortlautTage} Tagen</td>
            </tr>
            <tr>
              <td>Der Protokolleintrag selbst</td>
              <td className="leise">nach {FRISTEN.protokollTage} Tagen</td>
            </tr>
            <tr>
              <td>Anmeldecodes und -links</td>
              <td className="leise">nach {FRISTEN.anmeldeTokenTage} Tag</td>
            </tr>
            <tr>
              <td>Getrennte Kalenderverbindungen</td>
              <td className="leise">nach {FRISTEN.widerrufeneVerbindungTage} Tagen</td>
            </tr>
            <tr>
              <td>Ein Konto, das niemand mehr benutzt</td>
              <td className="leise">
                nach {Math.round(FRISTEN.kontoRuhendTage / 30)} Monaten, mit Vorwarnung
              </td>
            </tr>
          </tbody>
        </table>
        <p className="leise" style={{ marginTop: '0.75rem' }}>
          Ein Vorgang mit einer Frist in der Zukunft bleibt, auch wenn er längst abgeschlossen
          ist — sonst könnten Sie später nicht mehr nachsehen, woher ein Termin in Ihrem
          Kalender kommt.
        </p>
      </div>

      <div className="karte">
        <strong>Alles herunterladen</strong>
        <p className="leise" style={{ marginTop: '0.25rem' }}>
          Eine Datei mit allem, was zu diesem Konto gespeichert ist (Art. 15 und 20 DSGVO).
          Nicht enthalten sind die Zugangsdaten zu Ihrem Kalender — die liegen verschlüsselt
          und gehören nicht in eine Datei in Ihrem Download-Ordner.
        </p>
        <a className="knopf leise-knopf" href="/api/daten/export">
          Datei herunterladen
        </a>
      </div>

      <div className="karte">
        <strong>Wohin Ihre Daten gehen</strong>
        <p className="leise" style={{ marginTop: '0.25rem' }}>
          Damit der Assistent arbeiten kann, verlassen Inhalte Ihrer Mails diesen Server.
          Welche Dienste das sind und was sie jeweils zu sehen bekommen, steht in der{' '}
          <Link href="/datenschutz">Datenschutzerklärung</Link>.
        </p>
        {konfig.demoModus && (
          <p className="leise">
            Im Demo-Modus geht nichts nach draußen: Texte werden regelbasiert erzeugt, Mails
            landen auf der Konsole.
          </p>
        )}
      </div>

      <details className="karte">
        <summary style={{ cursor: 'pointer', fontWeight: 600 }}>Konto löschen</summary>
        <p className="leise" style={{ marginTop: '0.75rem' }}>
          Löscht dieses Konto und alles daran: Mails, Anhangstexte, Termine, Regeln, das
          Protokoll und die Kalenderverbindungen. Sofort, ohne Papierkorb, ohne Rückfrage
          danach.
        </p>
        <p className="leise">
          <strong>Was nicht passiert:</strong> Termine, die bereits in Ihrem Kalender stehen,
          bleiben stehen. Das sind Ihre Termine — ich räume Ihnen nicht den Wochenplan leer.
          Und Mails, die bereits rausgegangen sind, kommen nicht zurück; dafür gibt es keinen
          Weg.
        </p>
        <form action={kontoLoeschen} style={{ marginTop: '1rem' }}>
          <div className="feld">
            <label htmlFor="bestaetigung">
              Tippen Sie <code>{nutzer.email}</code>, um es zu bestätigen
            </label>
            <input id="bestaetigung" name="bestaetigung" type="text" required />
          </div>
          <button type="submit">Konto und alle Daten endgültig löschen</button>
        </form>
      </details>
    </main>
  );
}

async function zaehleBestand(nutzerId: string) {
  const d = await db();
  const wieViele = async (
    ergebnis: Promise<{ n: number }[]>,
  ): Promise<number> => (await ergebnis)[0]?.n ?? 0;

  const vorgangIds = (
    await d
      .select({ id: schema.vorgaenge.id })
      .from(schema.vorgaenge)
      .where(eq(schema.vorgaenge.nutzerId, nutzerId))
  ).map((v) => v.id);

  const nachrichtIds = vorgangIds.length
    ? (
        await d
          .select({ id: schema.nachrichten.id })
          .from(schema.nachrichten)
          .where(inArray(schema.nachrichten.vorgangId, vorgangIds))
      ).map((n) => n.id)
    : [];

  return {
    vorgaenge: vorgangIds.length,
    nachrichten: nachrichtIds.length,
    anhaenge: nachrichtIds.length
      ? await wieViele(
          d
            .select({ n: count() })
            .from(schema.anhaenge)
            .where(inArray(schema.anhaenge.nachrichtId, nachrichtIds)),
        )
      : 0,
    termine: vorgangIds.length
      ? await wieViele(
          d
            .select({ n: count() })
            .from(schema.termine)
            .where(inArray(schema.termine.vorgangId, vorgangIds)),
        )
      : 0,
    protokoll: await wieViele(
      d
        .select({ n: count() })
        .from(schema.protokoll)
        .where(eq(schema.protokoll.nutzerId, nutzerId)),
    ),
  };
}
