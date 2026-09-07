/**
 * Wer diesen Dienst betreibt.
 *
 * Steht in Umgebungsvariablen und nicht im Quelltext, weil es die einzigen
 * Angaben im Projekt sind, die niemand ausser der Betreiberin selbst
 * ausfuellen kann — und weil eine Datenschutzerklaerung mit einem
 * Platzhalter im Verantwortlichen-Feld schlechter ist als gar keine: sie
 * sieht fertig aus.
 *
 * Fehlt etwas, steht das sichtbar auf der Seite. Kein stiller Platzhalter.
 */

const FEHLT = '[nicht eingetragen — BETREIBER_* in .env setzen]';

export const betreiber = {
  get name(): string {
    return process.env.BETREIBER_NAME ?? FEHLT;
  },
  get anschrift(): string {
    return process.env.BETREIBER_ANSCHRIFT ?? FEHLT;
  },
  get email(): string {
    return process.env.BETREIBER_EMAIL ?? FEHLT;
  },
};

export function betreiberVollstaendig(): boolean {
  return Boolean(
    process.env.BETREIBER_NAME && process.env.BETREIBER_ANSCHRIFT && process.env.BETREIBER_EMAIL,
  );
}

/**
 * Der Warnkasten auf der Datenschutzseite verschwindet erst, wenn BEIDES
 * stimmt: die Betreiberangaben sind da UND jemand hat ausdruecklich
 * bestaetigt, dass der Text anwaltlich geprueft wurde.
 *
 * Zwei Bedingungen statt einer, damit die Bestaetigung nicht versehentlich
 * durch das blosse Ausfuellen der Adresse mitkommt.
 */
export function datenschutzGeprueft(): boolean {
  return betreiberVollstaendig() && process.env.DATENSCHUTZ_GEPRUEFT === 'ja';
}
