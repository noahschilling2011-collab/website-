/**
 * Ein Ort fuer alle Umgebungsvariablen, mit ehrlichen Voreinstellungen
 * fuer den Attrappen-Modus. Nichts hiervon wirft beim Import — die App
 * muss ohne ein einziges externes Konto starten koennen.
 */

export const konfig = {
  /** Domain der Weiterleitungsadressen: <handle>@<mailDomain>. */
  get mailDomain(): string {
    return process.env.MAIL_DOMAIN ?? 'assistent.localhost';
  },
  get absender(): string {
    return process.env.MAIL_ABSENDER ?? 'Assistent <assistent@assistent.localhost>';
  },
  get appUrl(): string {
    return process.env.APP_URL ?? 'http://localhost:3000';
  },
  /** Die Haltezeit aus Abschnitt 5 des Entwurfs. */
  get haltezeitSekunden(): number {
    return Number(process.env.HALTEZEIT_SEKUNDEN ?? 60);
  },
  get webhookSecret(): string | null {
    return process.env.MAIL_WEBHOOK_SECRET ?? null;
  },
  get demoModus(): boolean {
    return !process.env.ANTHROPIC_API_KEY || !process.env.RESEND_API_KEY;
  },
  /** Standard-Termindauer in Minuten. */
  get terminDauerMinuten(): number {
    return Number(process.env.TERMIN_DAUER_MINUTEN ?? 45);
  },
  get pufferMinuten(): number {
    return Number(process.env.PUFFER_MINUTEN ?? 15);
  },
  /** Nach wie vielen Tagen ohne Antwort nachgefasst wird. */
  get nachfassenNachTagen(): number {
    return Number(process.env.NACHFASSEN_NACH_TAGEN ?? 3);
  },
  get maxErinnerungen(): number {
    return Number(process.env.MAX_ERINNERUNGEN ?? 2);
  },
};
