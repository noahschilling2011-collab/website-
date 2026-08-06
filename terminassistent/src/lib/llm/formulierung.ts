import type { Slot } from '../slots';
import { formatiereDeutsch, formatiereKurz } from '../zeit';
import {
  MODELL_FORMULIERUNG,
  hatModellZugang,
  type JsonSchema,
  strukturiert,
} from './client';

/**
 * Formulierung mit claude-sonnet-5.
 *
 * Hier geht Text an einen echten Menschen — den Kinderarzt, die Mutter,
 * den Pflegedienst. Das ist die Stelle, an der ein schlechter Satz die
 * Nutzerin Ansehen kostet, deshalb das teurere Modell.
 */

export interface Entwurf {
  betreff: string;
  text: string;
}

const SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    betreff: { type: 'string' },
    text: { type: 'string' },
  },
  required: ['betreff', 'text'],
  additionalProperties: false,
};

const SYSTEM = `Du schreibst kurze deutsche Geschaeftsmails im Auftrag einer selbstaendigen Therapeutin.

Du bist erkennbar ihr Assistent, nicht sie selbst. Die Mail geht von einer Assistenz-Adresse, nicht von ihrer eigenen — schreibe entsprechend, ohne dich als Mensch auszugeben.

Ton: hoeflich, knapp, ohne Floskeln. Wie eine gut organisierte Praxismitarbeiterin schreibt: klar, freundlich, ohne Ueberschwang.

Regeln:
- Sie-Form.
- Kein "Ich hoffe, es geht Ihnen gut", kein "Vielen Dank im Voraus fuer Ihre Muehe".
- Keine Emojis, keine Ausrufezeichen.
- Nenne Termine mit Wochentag, Datum und Uhrzeit, genau so wie sie dir gegeben werden. Rechne nichts um und erfinde keine Alternativen.
- Hoechstens sechs Zeilen Text.
- Keine Grussformel-Signatur — die haengt das System an.
- Erfinde keine Zusagen, keine Preise, keine medizinischen Aussagen.`;

/** Funktion A: Terminvorschlaege an den Dritten. */
export async function entwurfTerminvorschlag(daten: {
  gegenueberName: string | null;
  betreff: string;
  bisherigerVerlauf: string;
  vorschlaege: Slot[];
  zeitzone: string;
  nutzerName: string;
}): Promise<Entwurf> {
  const liste = daten.vorschlaege
    .map((s) => `- ${formatiereDeutsch(s.start, daten.zeitzone)} Uhr`)
    .join('\n');

  if (!hatModellZugang()) {
    return {
      betreff: daten.betreff,
      text: [
        `Guten Tag${daten.gegenueberName ? ` ${daten.gegenueberName}` : ''},`,
        '',
        'gerne schlage ich Ihnen folgende Termine vor:',
        '',
        liste,
        '',
        'Passt Ihnen einer davon? Eine kurze Antwort genuegt.',
      ].join('\n'),
    };
  }

  return strukturiert<Entwurf>({
    modell: MODELL_FORMULIERUNG,
    system: SYSTEM,
    prompt: `Schreibe eine Mail, die diese Termine zur Auswahl stellt und um eine kurze Rueckmeldung bittet.

Empfaenger: ${daten.gegenueberName ?? 'unbekannt'}
Bisheriger Betreff: ${daten.betreff}
Therapeutin: ${daten.nutzerName}

Bisheriger Verlauf:
${daten.bisherigerVerlauf}

Diese Termine stehen zur Auswahl (genau so uebernehmen):
${liste}`,
    schema: SCHEMA,
    maxTokens: 4000,
    effort: 'medium',
  });
}

/** Funktion A: Bestaetigung, nachdem ein Vorschlag angenommen wurde. */
export async function entwurfBestaetigung(daten: {
  gegenueberName: string | null;
  betreff: string;
  termin: Slot;
  zeitzone: string;
  nutzerName: string;
}): Promise<Entwurf> {
  const wann = `${formatiereDeutsch(daten.termin.start, daten.zeitzone)} Uhr`;

  if (!hatModellZugang()) {
    return {
      betreff: daten.betreff,
      text: [
        `Guten Tag${daten.gegenueberName ? ` ${daten.gegenueberName}` : ''},`,
        '',
        `vielen Dank, ich habe den Termin am ${wann} eingetragen.`,
        '',
        'Sollte etwas dazwischenkommen, sagen Sie gern rechtzeitig Bescheid.',
      ].join('\n'),
    };
  }

  return strukturiert<Entwurf>({
    modell: MODELL_FORMULIERUNG,
    system: SYSTEM,
    prompt: `Schreibe eine kurze Bestaetigung, dass dieser Termin eingetragen wurde.

Empfaenger: ${daten.gegenueberName ?? 'unbekannt'}
Bisheriger Betreff: ${daten.betreff}
Therapeutin: ${daten.nutzerName}
Termin: ${wann}`,
    schema: SCHEMA,
    maxTokens: 2000,
    effort: 'low',
  });
}

/** Funktion C: Erinnerung, wenn keine Antwort kam. */
export async function entwurfNachfassen(daten: {
  gegenueberName: string | null;
  betreff: string;
  bisherigerVerlauf: string;
  tageOhneAntwort: number;
  wievielteErinnerung: number;
  zeitzone: string;
  nutzerName: string;
}): Promise<Entwurf> {
  if (!hatModellZugang()) {
    return {
      betreff: daten.betreff,
      text: [
        `Guten Tag${daten.gegenueberName ? ` ${daten.gegenueberName}` : ''},`,
        '',
        'ich melde mich kurz zu meiner Nachricht von vor einigen Tagen.',
        '',
        'Passt Ihnen einer der genannten Termine, oder soll ich andere heraussuchen?',
      ].join('\n'),
    };
  }

  return strukturiert<Entwurf>({
    modell: MODELL_FORMULIERUNG,
    system: SYSTEM,
    prompt: `Schreibe eine freundliche Erinnerung. Es ist die ${ordnungszahl(daten.wievielteErinnerung)} Erinnerung, die letzte Nachricht liegt ${daten.tageOhneAntwort} Tage zurueck.

Nicht vorwurfsvoll, nicht laenger als drei Zeilen. Beim zweiten Mal biete an, andere Termine herauszusuchen.

Empfaenger: ${daten.gegenueberName ?? 'unbekannt'}
Bisheriger Betreff: ${daten.betreff}
Therapeutin: ${daten.nutzerName}

Bisheriger Verlauf:
${daten.bisherigerVerlauf}`,
    schema: SCHEMA,
    maxTokens: 2000,
    effort: 'low',
  });
}

/**
 * Kompensation: die Korrektur nach einer Mail, die so nicht haette
 * rausgehen duerfen.
 *
 * Es gibt kein Rueckgaengig fuer eine gesendete Mail. Es gibt nur diese
 * zweite Mail — und die muss den Fehler benennen, statt ihn zu verschleiern.
 */
export async function entwurfKorrektur(daten: {
  gegenueberName: string | null;
  betreff: string;
  falscheNachricht: string;
  grund: string;
  nutzerName: string;
}): Promise<Entwurf> {
  if (!hatModellZugang()) {
    return {
      betreff: daten.betreff,
      text: [
        `Guten Tag${daten.gegenueberName ? ` ${daten.gegenueberName}` : ''},`,
        '',
        'bitte entschuldigen Sie meine vorige Nachricht — sie war nicht korrekt.',
        '',
        daten.grund,
        '',
        'Ich melde mich mit den richtigen Angaben erneut.',
      ].join('\n'),
    };
  }

  return strukturiert<Entwurf>({
    modell: MODELL_FORMULIERUNG,
    system: SYSTEM,
    prompt: `Schreibe eine kurze Korrektur zu einer Nachricht, die soeben faelschlich verschickt wurde.

Regeln fuer diesen Fall:
- Benenne den Fehler klar, ohne ihn auszuschmuecken oder zu verharmlosen.
- Keine ausufernde Entschuldigung, ein Satz genuegt.
- Sag, was stattdessen gilt, oder dass eine korrigierte Nachricht folgt.
- Keine Schuldzuweisung an Technik oder Dritte.

Empfaenger: ${daten.gegenueberName ?? 'unbekannt'}
Bisheriger Betreff: ${daten.betreff}
Therapeutin: ${daten.nutzerName}

Das ging faelschlich raus:
${daten.falscheNachricht}

Was daran falsch war:
${daten.grund}`,
    schema: SCHEMA,
    maxTokens: 2000,
    effort: 'low',
  });
}

function ordnungszahl(n: number): string {
  return ['erste', 'zweite', 'dritte', 'vierte'][n - 1] ?? `${n}.`;
}

/** Funktion B: die Zeile, die bei einer erkannten Frist auf dem Schirm steht. */
export function fristTitel(
  gegenueber: string | null,
  faellig: Date,
  zeitzone: string,
): string {
  const wer = gegenueber ? ` ${gegenueber}` : '';
  return `Frist${wer}: ${formatiereKurz(faellig, zeitzone)}`;
}
