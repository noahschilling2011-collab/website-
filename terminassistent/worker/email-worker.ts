/**
 * Cloudflare Email Worker — der Zubringer fuer den Maileingang.
 *
 * Er tut bewusst so wenig wie moeglich: Rohnachricht einsammeln, an die App
 * weiterreichen, fertig. Das MIME-Zerlegen und die PDF-Textextraktion
 * passieren in der App, nicht hier.
 *
 * Der Grund ist die CPU-Grenze. Cloudflare dokumentiert fuer komplexe
 * Email-Handler ausdruecklich den Fehler EXCEEDED_CPU, und der Free-Plan
 * gibt nur 10 ms CPU-Zeit pro Nachricht. Ein Weiterreichen ist fast reine
 * I/O-Wartezeit und zaehlt kaum gegen dieses Budget — ob der Free-Plan
 * dafuer reicht, ist NICHT belegt und muss gemessen werden, bevor man sich
 * die 5 USD/Monat fuer Workers Paid spart.
 *
 * Einrichtung: siehe README, Abschnitt "Maileingang".
 */

export interface Env {
  /** Basis-URL der App, z.B. https://assistent.example */
  APP_URL: string;
  /** Muss mit MAIL_WEBHOOK_SECRET der App uebereinstimmen. */
  WEBHOOK_SECRET: string;
  /** Verifizierte Zieladresse fuer den Notfall-Fallback. */
  FALLBACK_ADRESSE?: string;
}

interface ForwardableEmailMessage {
  readonly from: string;
  readonly to: string;
  readonly raw: ReadableStream<Uint8Array>;
  readonly rawSize: number;
  setReject(reason: string): void;
  forward(rcptTo: string, headers?: Headers): Promise<void>;
}

export default {
  async email(nachricht: ForwardableEmailMessage, env: Env): Promise<void> {
    // 25 MiB ist Cloudflares Eingangsgrenze; groessere Nachrichten kommen
    // gar nicht erst an. Wir ziehen die eigene Grenze deutlich frueher,
    // damit ein Riesenanhang nicht die Verarbeitung blockiert.
    const MAX = 15 * 1024 * 1024;
    if (nachricht.rawSize > MAX) {
      nachricht.setReject('Die Nachricht ist zu gross. Bitte den Anhang verkleinern.');
      return;
    }

    const roh = await new Response(nachricht.raw).arrayBuffer();

    let antwort: Response;
    try {
      antwort = await fetch(`${env.APP_URL}/api/mail/eingang`, {
        method: 'POST',
        headers: {
          'content-type': 'message/rfc822',
          'x-webhook-secret': env.WEBHOOK_SECRET,
          'x-envelope-from': nachricht.from,
          'x-envelope-to': nachricht.to,
        },
        body: roh,
      });
    } catch (fehler) {
      // Cloudflare speichert nichts: bricht der Worker ab, ist die Mail weg.
      // Deshalb wird abgelehnt statt stillschweigend verworfen — dann
      // bekommt der Absender wenigstens eine Fehlermeldung seines Providers.
      nachricht.setReject(
        `Der Assistent ist gerade nicht erreichbar (${(fehler as Error).message}). Bitte spaeter erneut senden.`,
      );
      return;
    }

    if (!antwort.ok) {
      if (env.FALLBACK_ADRESSE) {
        // Letzte Rettung: unverarbeitet an das echte Postfach der Nutzerin,
        // damit die Mail nicht verlorengeht.
        await nachricht.forward(env.FALLBACK_ADRESSE);
        return;
      }
      nachricht.setReject(
        `Der Assistent konnte die Nachricht nicht annehmen (HTTP ${antwort.status}).`,
      );
    }
  },
};
