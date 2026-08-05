import type { VorgangsArt, VorgangsZustand } from '../../db/schema';

/**
 * Die Zustandsmaschine eines Vorgangs — bewusst rein, ohne Datenbank und
 * ohne Uhr, damit sie vollstaendig testbar ist.
 *
 * Die zentrale Regel aus dem Entwurf, Abschnitt 5:
 *
 *   Alles, was das System NICHT verlaesst, passiert automatisch.
 *   Alles, was die Aussenwelt erreicht, braucht einen Klick —
 *   ausser der Empfaenger ist fuer diesen Aktionstyp freigegeben.
 *
 * Der Zustand `gehalten` ist die 60-Sekunden-Haltezeit. Er existiert, weil
 * es fuer eine gesendete Mail kein Rueckgaengig gibt: nur Verzoegern.
 */

export type Ereignis =
  | { art: 'mail_eingegangen'; braucht_rueckfrage: boolean }
  | { art: 'entwurf_bereit'; darf_automatisch: boolean }
  | { art: 'senden_ausgeloest' }
  | { art: 'haltezeit_abgebrochen' }
  | { art: 'versandt' }
  | { art: 'antwort_eingegangen'; ist_zusage: boolean }
  | { art: 'frist_eingetragen' }
  | { art: 'erinnerung_faellig'; darf_automatisch: boolean }
  | { art: 'aufgegeben' }
  | { art: 'fehlgeschlagen' };

export interface Uebergang {
  zustand: VorgangsZustand;
  /** Was der Aufrufer zusaetzlich tun muss. Nie im Zustand versteckt. */
  wirkung?: 'entwurf_erzeugen' | 'in_ausgang_legen' | 'sofort_senden' | 'termin_eintragen';
}

export function naechsterZustand(
  aktuell: VorgangsZustand,
  ereignis: Ereignis,
): Uebergang {
  // Endzustaende reagieren auf nichts mehr ausser einer neuen Mail.
  if ((aktuell === 'erledigt' || aktuell === 'abgebrochen') && ereignis.art !== 'mail_eingegangen') {
    return { zustand: aktuell };
  }

  switch (ereignis.art) {
    case 'mail_eingegangen':
      // Eine neue Nachricht weckt auch einen abgeschlossenen Vorgang.
      return { zustand: 'neu', wirkung: ereignis.braucht_rueckfrage ? undefined : 'entwurf_erzeugen' };

    case 'entwurf_bereit':
      // Der einzige Ort, an dem die Vertrauensregel greift.
      return ereignis.darf_automatisch
        ? { zustand: 'gehalten', wirkung: 'in_ausgang_legen' }
        : { zustand: 'warte_auf_mich' };

    case 'senden_ausgeloest':
      if (aktuell !== 'warte_auf_mich') return { zustand: aktuell };
      return { zustand: 'gehalten', wirkung: 'in_ausgang_legen' };

    case 'haltezeit_abgebrochen':
      if (aktuell !== 'gehalten') return { zustand: aktuell };
      // Zurueck in die Hand der Nutzerin, nicht in den Papierkorb.
      return { zustand: 'warte_auf_mich' };

    case 'versandt':
      return { zustand: 'warte_auf_andere' };

    case 'antwort_eingegangen':
      return ereignis.ist_zusage
        ? { zustand: 'warte_auf_mich', wirkung: 'termin_eintragen' }
        : { zustand: 'neu', wirkung: 'entwurf_erzeugen' };

    case 'frist_eingetragen':
      // Funktion B endet hier: der Kalendereintrag ist umkehrbar und
      // verlaesst das System nicht, also braucht er keinen Klick.
      return { zustand: 'erledigt' };

    case 'erinnerung_faellig':
      if (aktuell !== 'warte_auf_andere') return { zustand: aktuell };
      return ereignis.darf_automatisch
        ? { zustand: 'gehalten', wirkung: 'in_ausgang_legen' }
        : { zustand: 'warte_auf_mich' };

    case 'aufgegeben':
      return { zustand: 'abgebrochen' };

    case 'fehlgeschlagen':
      return { zustand: 'fehler' };
  }
}

/** Steht diese Zeile oben auf dem Bildschirm und traegt den Knopf? */
export function wartetAufNutzerin(zustand: VorgangsZustand): boolean {
  return zustand === 'warte_auf_mich' || zustand === 'fehler';
}

// ---------------------------------------------------------------------------
// Vertrauensregeln
// ---------------------------------------------------------------------------

export const SENDUNGEN_BIS_ANGEBOT = 3;

export interface RegelStand {
  bestaetigteSendungen: number;
  automatisch: boolean;
}

/**
 * Vertrauen wird verdient, nicht abgefragt.
 *
 * Nach drei bestaetigten Sendungen desselben Typs an dieselbe Adresse
 * BIETET das System an, kuenftig automatisch zu senden. Es schaltet nicht
 * selbst um — die Zustimmung ist ein eigener, ausdruecklicher Klick.
 */
export function zeigeAutomatikAngebot(regel: RegelStand | null | undefined): boolean {
  if (!regel) return false;
  return !regel.automatisch && regel.bestaetigteSendungen >= SENDUNGEN_BIS_ANGEBOT;
}

export function darfAutomatischSenden(regel: RegelStand | null | undefined): boolean {
  return Boolean(regel?.automatisch);
}

/**
 * Ein Irrtum kostet je nach Aktionstyp unterschiedlich viel (Entwurf,
 * Abschnitt 3). Ein falsches Nachfassen nervt; ein falscher Termin kostet
 * einen Ausfall. Deshalb ist Nachfassen der einzige Typ, fuer den die
 * Automatik ueberhaupt angeboten wird.
 */
export function automatikErlaubtFuer(art: VorgangsArt): boolean {
  return art === 'nachfassen';
}
