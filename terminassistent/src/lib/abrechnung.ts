/**
 * Die Bezahlschranke aus Abschnitt 10 des Entwurfs.
 *
 * "Kostenlos sind die ersten fuenf abgeschlossenen Vorgaenge — nicht 14
 * Tage, sondern fuenf Ergebnisse. Ein Zeitlimit misst, wie beschaeftigt
 * jemand war; ein Ergebnislimit misst, ob das Produkt gearbeitet hat."
 *
 * Rein und ohne Datenbank, damit die Grenzfaelle testbar sind: genau bei
 * fuenf, direkt nach der Zahlung, und der Fall, dass jemand waehrend eines
 * laufenden Vorgangs die Grenze erreicht.
 */

export const FREIE_VORGAENGE = 5;

export interface AbrechnungsStand {
  abgeschlosseneVorgaenge: number;
  zahlendSeit: Date | null;
}

export interface Schranke {
  erlaubt: boolean;
  /** Wird der Nutzerin wortwoertlich angezeigt. */
  grund?: string;
  /** Wie viele freie Vorgaenge noch uebrig sind. */
  verbleibend: number;
}

export function pruefeSchranke(stand: AbrechnungsStand): Schranke {
  if (stand.zahlendSeit) {
    return { erlaubt: true, verbleibend: Number.POSITIVE_INFINITY };
  }

  const verbleibend = Math.max(0, FREIE_VORGAENGE - stand.abgeschlosseneVorgaenge);
  if (verbleibend > 0) return { erlaubt: true, verbleibend };

  return {
    erlaubt: false,
    verbleibend: 0,
    grund: `Die ersten ${FREIE_VORGAENGE} Vorgänge sind kostenlos, und die sind erledigt. Für alles Weitere brauche ich ein Abonnement.`,
  };
}

/**
 * Der Hinweis auf dem Bildschirm, bevor die Schranke zuschlaegt.
 *
 * Bewusst erst ab dem vorletzten freien Vorgang: eine Zahlungsaufforderung
 * beim ersten Ergebnis waere die Sorte Druck, die das Produkt gerade
 * nicht ausueben soll.
 */
export function zeigeHinweis(stand: AbrechnungsStand): string | null {
  if (stand.zahlendSeit) return null;
  const verbleibend = Math.max(0, FREIE_VORGAENGE - stand.abgeschlosseneVorgaenge);
  if (verbleibend === 0) {
    return 'Ihre kostenlosen Vorgänge sind aufgebraucht.';
  }
  if (verbleibend > 2) return null;
  return verbleibend === 1
    ? 'Noch ein kostenloser Vorgang.'
    : `Noch ${verbleibend} kostenlose Vorgänge.`;
}
