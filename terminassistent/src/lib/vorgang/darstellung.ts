import type { AusgangsEintrag, Termin, Vorgang } from '../../db/schema';
import { formatiereDeutsch, formatiereKurz } from '../zeit';

/**
 * Die Zeile, die die Nutzerin liest.
 *
 * Bewusst als eigene, testbare Funktion statt als JSX-Gestrick: das hier
 * IST das Produkt. Auf dem einen Bildschirm steht nichts anderes, und
 * jeder Zustand muss ohne Legende verstaendlich sein.
 */

export interface Darstellung {
  stand: string;
  /** Steht die Zeile oben und traegt einen Knopf? */
  dringend: boolean;
  /** Laeuft gerade die Haltezeit? */
  laeuft: boolean;
  knopf: 'senden' | 'abbrechen' | 'ansehen';
}

export function stelleDar(
  vorgang: Vorgang,
  ausgang: AusgangsEintrag | null,
  termin: Termin | null,
  zeitzone: string,
  jetzt = new Date(),
): Darstellung {
  switch (vorgang.zustand) {
    case 'warte_auf_mich':
      if (ausgang?.status === 'entwurf') {
        return {
          stand: 'Entwurf fertig',
          dringend: true,
          laeuft: false,
          knopf: 'senden',
        };
      }
      return {
        stand: 'Braucht Ihre Entscheidung',
        dringend: true,
        laeuft: false,
        knopf: 'ansehen',
      };

    case 'gehalten': {
      const sekunden = ausgang
        ? Math.max(0, Math.round((ausgang.haltenBis.getTime() - jetzt.getTime()) / 1000))
        : 0;
      return {
        stand:
          sekunden > 0
            ? `Geht in ${sekunden} Sekunden raus — noch abbrechbar`
            : 'Wird gerade gesendet',
        dringend: false,
        laeuft: true,
        knopf: sekunden > 0 ? 'abbrechen' : 'ansehen',
      };
    }

    case 'warte_auf_andere': {
      const seit = tageSeit(vorgang.geaendertAm, jetzt);
      const naechste = vorgang.naechsteErinnerung
        ? ` · nächste Erinnerung ${formatiereKurz(vorgang.naechsteErinnerung, zeitzone)}`
        : '';
      return {
        stand: `Warte auf Antwort seit ${seit}${naechste}`,
        dringend: false,
        laeuft: false,
        knopf: 'ansehen',
      };
    }

    case 'erledigt':
      if (vorgang.art === 'frist' && vorgang.faelligAm) {
        return {
          stand: `Frist ${formatiereKurz(vorgang.faelligAm, zeitzone)} · im Kalender`,
          dringend: false,
          laeuft: false,
          knopf: 'ansehen',
        };
      }
      if (termin) {
        return {
          stand: `${formatiereDeutsch(termin.von, zeitzone)} Uhr · ${platzierung(termin)}`,
          dringend: false,
          laeuft: false,
          knopf: 'ansehen',
        };
      }
      return { stand: 'Erledigt', dringend: false, laeuft: false, knopf: 'ansehen' };

    case 'fehler':
      return {
        stand: 'Etwas ist schiefgegangen',
        dringend: true,
        laeuft: false,
        knopf: 'ansehen',
      };

    case 'abgebrochen':
      return { stand: 'Abgebrochen', dringend: false, laeuft: false, knopf: 'ansehen' };

    case 'neu':
    default:
      return { stand: 'Wird gelesen', dringend: false, laeuft: false, knopf: 'ansehen' };
  }
}

/**
 * Der Unterschied zwischen "steht im Kalender" und "verschickt, Ausgang
 * unbekannt" schlaegt bis hierher durch. Genau dafuer hat PlacementResult
 * drei Zustaende und nicht einen boolean — die Nutzerin darf nicht glauben,
 * ein Termin stehe fest, wenn er nur unterwegs ist.
 */
export function platzierung(termin: Termin): string {
  switch (termin.platzierungsStatus) {
    case 'placed':
      return 'im Kalender';
    case 'dispatched':
      return 'Einladung verschickt, Eintrag unbestätigt';
    case 'published':
      return 'im Kalender-Abo veröffentlicht';
    case 'abgesagt':
      return 'abgesagt';
    case 'offen':
    default:
      return 'vorgeschlagen';
  }
}

export function tageSeit(zeitpunkt: Date, jetzt: Date): string {
  const stunden = Math.floor((jetzt.getTime() - zeitpunkt.getTime()) / 3_600_000);
  if (stunden < 1) return 'wenigen Minuten';
  if (stunden < 24) return stunden === 1 ? '1 Stunde' : `${stunden} Stunden`;
  const tage = Math.floor(stunden / 24);
  return tage === 1 ? '1 Tag' : `${tage} Tagen`;
}

/** Wartende Zeilen zuerst, danach das Laufende, dann der Rest nach Datum. */
export function sortiere<T extends { darstellung: Darstellung; vorgang: Vorgang }>(
  eintraege: T[],
): T[] {
  return [...eintraege].sort((a, b) => {
    if (a.darstellung.dringend !== b.darstellung.dringend) {
      return a.darstellung.dringend ? -1 : 1;
    }
    if (a.darstellung.laeuft !== b.darstellung.laeuft) {
      return a.darstellung.laeuft ? -1 : 1;
    }
    return b.vorgang.geaendertAm.getTime() - a.vorgang.geaendertAm.getTime();
  });
}
