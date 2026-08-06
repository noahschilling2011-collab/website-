import Link from 'next/link';
import { FRISTEN } from '../../lib/datenschutz/aufbewahrung';
import { betreiber, datenschutzGeprueft } from '../../lib/datenschutz/betreiber';
import { konfig } from '../../lib/konfig';

export const dynamic = 'force-dynamic';

/**
 * Datenschutzerklaerung.
 *
 * Die Speicherdauern kommen aus FRISTEN, nicht aus diesem Text. Eine
 * Datenschutzerklaerung, die eigene Zahlen nennt, laeuft beim ersten
 * Anfassen des Loeschkonzepts auseinander — und dann steht dort etwas
 * anderes, als die Anwendung tut. Das ist der haeufigste Weg, wie so ein
 * Text falsch wird.
 *
 * Der Warnhinweis oben verschwindet erst, wenn DATENSCHUTZ_GEPRUEFT
 * gesetzt ist. Das ist Absicht: er soll nicht vergessen werden koennen.
 */
export default function Datenschutz() {
  return (
    <main>
      <div className="kopf">
        <h1>Datenschutz</h1>
        <Link className="knopf leise-knopf" href="/">
          Zurück
        </Link>
      </div>

      {!datenschutzGeprueft() && (
        <div className="hinweis">
          <strong>Ungeprüfter Entwurf.</strong>
          <p style={{ marginTop: '0.35rem', marginBottom: 0 }}>
            Dieser Text beschreibt zutreffend, was die Anwendung mit Daten tut — er ist aus dem
            Quelltext abgeleitet. Er ist aber nicht anwaltlich geprüft, und die Angaben zum
            Verantwortlichen und zu den Auftragsverarbeitern sind unvollständig. Vor dem ersten
            echten Einsatz gehört beides erledigt. Solange <code>DATENSCHUTZ_GEPRUEFT</code>{' '}
            nicht gesetzt ist, bleibt dieser Kasten stehen.
          </p>
        </div>
      )}

      <div className="karte">
        <strong>Verantwortlicher</strong>
        <p style={{ marginTop: '0.35rem' }}>
          {betreiber.name}
          <br />
          {betreiber.anschrift}
          <br />
          {betreiber.email}
        </p>
      </div>

      <div className="abschnitt">Was verarbeitet wird und warum</div>

      <div className="karte">
        <strong>Zwei verschiedene Rollen</strong>
        <p className="leise" style={{ marginTop: '0.35rem' }}>
          Für Ihre eigenen Kontodaten — Mailadresse, Name, Arbeitszeiten, Zeitzone — bin ich{' '}
          <em>Verantwortlicher</em> im Sinne von Art. 4 Nr. 7 DSGVO. Rechtsgrundlage ist
          Art. 6 Abs. 1 lit. b DSGVO: ohne diese Daten gibt es keinen Vertrag zu erfüllen.
        </p>
        <p className="leise">
          Für alles, was Sie mir weiterleiten — Mails von Angehörigen, Praxen, Kostenträgern,
          und die Angaben darin — bin ich <em>Auftragsverarbeiter</em> nach Art. 28 DSGVO.
          Verantwortlich sind Sie. Ich verarbeite diese Daten ausschließlich nach Ihrer
          Weisung, und die Weisung ist die Weiterleitung selbst.
        </p>
        <p className="leise">
          Diese Unterscheidung ist nicht formal: sie entscheidet darüber, wer gegenüber Ihren
          Klientinnen und Klienten auskunftspflichtig ist, und wer eine Meldung nach Art. 33
          abgeben muss. Beides sind Sie.
        </p>
      </div>

      <div className="karte">
        <strong>Gesundheitsdaten</strong>
        <p className="leise" style={{ marginTop: '0.35rem' }}>
          Eine weitergeleitete Heilmittelverordnung enthält Gesundheitsdaten im Sinne von
          Art. 9 Abs. 1 DSGVO — besondere Kategorien personenbezogener Daten. Das ist der
          eigentliche Kern dieses Produkts und der Grund, warum es sich nicht wie ein
          gewöhnliches Mailwerkzeug behandeln lässt.
        </p>
        <p className="leise">
          Wenn Sie einem Heilberuf mit staatlich geregelter Ausbildung angehören, unterliegen
          Sie zusätzlich der Schweigepflicht nach § 203 StGB. Mich als technischen Dienstleister
          einzuschalten ist nach § 203 Abs. 3 StGB möglich, verlangt aber eine ausdrückliche
          Verpflichtung zur Geheimhaltung und die Beschränkung auf das Erforderliche. Beides
          gehört in den Auftragsverarbeitungsvertrag.
        </p>
      </div>

      <div className="abschnitt">Wohin Daten gehen</div>

      <div className="karte">
        <strong>Empfänger</strong>
        <p className="leise" style={{ marginTop: '0.35rem' }}>
          Damit der Assistent arbeiten kann, verlassen Inhalte diesen Server. Das ist keine
          Nebenwirkung, sondern die Funktionsweise — deshalb steht es hier und nicht im
          Kleingedruckten.
        </p>
        <table style={{ marginTop: '0.6rem' }}>
          <tbody>
            <tr>
              <td>Modellanbieter (Anthropic)</td>
              <td className="leise">
                Bekommt den <strong>Text Ihrer weitergeleiteten Mails samt Anhangstext</strong>,
                um Termine und Fristen zu erkennen und Antworten zu formulieren. Das ist der
                weitreichendste Empfang in dieser Liste.
              </td>
            </tr>
            <tr>
              <td>Mailversand</td>
              <td className="leise">
                Bekommt die ausgehenden Mails samt Empfängeradresse und Inhalt.
              </td>
            </tr>
            <tr>
              <td>Maileingang</td>
              <td className="leise">
                Bekommt die eingehenden Mails, bevor ich sie sehe.
              </td>
            </tr>
            <tr>
              <td>Datenbank und Hosting</td>
              <td className="leise">Speichern alles, was oben unter „Ihre Daten" steht.</td>
            </tr>
            <tr>
              <td>Kalenderanbieter</td>
              <td className="leise">
                Nur wenn Sie einen Kalender verbinden. Bekommt Titel und Zeit der Termine, die
                ich eintrage. Belegtzeiten lese ich ohne Termintitel und ohne Teilnehmer.
              </td>
            </tr>
            <tr>
              <td>Zahlungsdienstleister</td>
              <td className="leise">
                Nur bei einem Abonnement. Bekommt Mailadresse und Zahlungsdaten — keine
                Inhalte, keine Gesundheitsdaten.
              </td>
            </tr>
          </tbody>
        </table>
        <p className="leise" style={{ marginTop: '0.75rem' }}>
          Die genauen Firmen, ihre Sitzländer und die jeweilige Grundlage für eine Übermittlung
          in Drittländer (Art. 44 ff. DSGVO) sind in{' '}
          <code>docs/datenschutz/auftragsverarbeiter.md</code> aufgeführt und müssen vor dem
          ersten echten Einsatz vervollständigt werden.
        </p>
      </div>

      <div className="abschnitt">Wie lange</div>

      <div className="karte">
        <p className="leise" style={{ marginTop: 0 }}>
          Gelöscht wird automatisch, nicht auf Antrag. Diese Zahlen stehen im Quelltext an einer
          Stelle und werden hier daraus angezeigt.
        </p>
        <table style={{ marginTop: '0.6rem' }}>
          <tbody>
            <tr>
              <td>Abgeschlossene Vorgänge samt Mails und Anhangstexten</td>
              <td className="leise">{FRISTEN.vorgangTage} Tage</td>
            </tr>
            <tr>
              <td>Der Wortlaut im Protokoll</td>
              <td className="leise">{FRISTEN.protokollWortlautTage} Tage</td>
            </tr>
            <tr>
              <td>Der Protokolleintrag ohne Wortlaut</td>
              <td className="leise">{FRISTEN.protokollTage} Tage</td>
            </tr>
            <tr>
              <td>Anmeldecodes und -links</td>
              <td className="leise">{FRISTEN.anmeldeTokenTage} Tag</td>
            </tr>
            <tr>
              <td>Getrennte Kalenderverbindungen</td>
              <td className="leise">{FRISTEN.widerrufeneVerbindungTage} Tage</td>
            </tr>
            <tr>
              <td>Konten ohne jede Nutzung</td>
              <td className="leise">
                {Math.round(FRISTEN.kontoRuhendTage / 30)} Monate, mit Vorwarnung per Mail
              </td>
            </tr>
          </tbody>
        </table>
        <p className="leise" style={{ marginTop: '0.75rem' }}>
          Der Rohanhang einer Mail wird nie gespeichert. Aus einer PDF wird der Text gelesen,
          danach ist die Datei weg. Gescannte PDFs ohne Textschicht werden abgelehnt statt
          geraten.
        </p>
      </div>

      <div className="abschnitt">Ihre Rechte</div>

      <div className="karte">
        <p className="leise" style={{ marginTop: 0 }}>
          Auskunft (Art. 15), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung
          (Art. 18), Datenübertragbarkeit (Art. 20) und Widerspruch (Art. 21).
        </p>
        <p className="leise">
          Zwei davon brauchen keinen Antrag und keine Frist: unter{' '}
          <Link href="/daten">Ihre Daten</Link> laden Sie alles Gespeicherte als Datei herunter
          und löschen das Konto samt allem daran selbst. Für alles Übrige schreiben Sie an{' '}
          {betreiber.email}.
        </p>
        <p className="leise">
          Sie können sich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren (Art. 77);
          zuständig ist die des Bundeslandes, in dem Sie Ihren Sitz haben.
        </p>
      </div>

      <div className="karte">
        <strong>Automatisierte Entscheidungen</strong>
        <p className="leise" style={{ marginTop: '0.35rem' }}>
          Der Assistent formuliert Mails und schlägt Termine vor. Nichts davon verlässt den
          Server ohne Ihre Freigabe, und auch eine freigegebene Automatik lässt Ihnen{' '}
          {konfig.haltezeitSekunden} Sekunden zum Abbrechen. Es findet keine automatisierte
          Entscheidung im Sinne von Art. 22 DSGVO statt, die jemandem gegenüber rechtliche
          Wirkung entfaltet.
        </p>
      </div>

      <div className="fuss">
        <Link href="/">Zurück zur Übersicht</Link>
        <Link href="/daten">Ihre Daten</Link>
      </div>
    </main>
  );
}
