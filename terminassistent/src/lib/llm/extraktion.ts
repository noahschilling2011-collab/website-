import type { VorgangsArt } from '../../db/schema';
import type { EingehendeMail } from '../mail/eingang';
import { MODELL_EXTRAKTION, hatModellZugang, type JsonSchema, strukturiert } from './client';

/**
 * Klassifikation und Extraktion mit claude-haiku-4-5.
 *
 * Zwei Aufgaben in einem Aufruf: Worum geht es (Funktion A, B oder
 * nichts davon), und welche harten Daten stecken drin (Frist, Betrag,
 * Zusage auf einen Vorschlag).
 */

export interface Analyse {
  art: VorgangsArt | 'sonstiges';
  /** Ein Satz Alltagssprache. Genau die Zeile auf dem Bildschirm. */
  titel: string;
  gegenueberName: string | null;
  /** ISO-Datum, nur bei Fristen. */
  fristDatum: string | null;
  betragEuro: number | null;
  /** Antwortet die Nachricht auf unsere Terminvorschlaege mit einer Zusage? */
  istZusage: boolean;
  /** 1-basiert, wenn genau ein Vorschlag zugesagt wurde. */
  zugesagterVorschlag: number | null;
  /** Bei "niedrig" fragt die App nach, statt zu handeln. */
  vertrauen: 'hoch' | 'mittel' | 'niedrig';
  begruendung: string;
}

const SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    art: { type: 'string', enum: ['termin', 'frist', 'nachfassen', 'sonstiges'] },
    titel: { type: 'string' },
    // anyOf statt type:['string','null'] — Typ-Arrays sind fuer Structured
    // Outputs nicht als unterstuetzt dokumentiert, anyOf schon.
    gegenueberName: { anyOf: [{ type: 'string' }, { type: 'null' }] },
    fristDatum: {
      anyOf: [{ type: 'string' }, { type: 'null' }],
      description: 'ISO-Datum JJJJ-MM-TT',
    },
    betragEuro: { anyOf: [{ type: 'number' }, { type: 'null' }] },
    istZusage: { type: 'boolean' },
    zugesagterVorschlag: { anyOf: [{ type: 'integer' }, { type: 'null' }] },
    vertrauen: { type: 'string', enum: ['hoch', 'mittel', 'niedrig'] },
    begruendung: { type: 'string' },
  },
  required: [
    'art',
    'titel',
    'gegenueberName',
    'fristDatum',
    'betragEuro',
    'istZusage',
    'zugesagterVorschlag',
    'vertrauen',
    'begruendung',
  ],
  additionalProperties: false,
};

const SYSTEM = `Du analysierst E-Mails, die eine selbstaendige Therapeutin an ihren Assistenten weitergeleitet hat.

Deine Aufgabe ist Klassifikation und Extraktion, nicht Formulierung.

Kategorien:
- "termin": Es geht darum, einen Termin zu vereinbaren, zu verschieben oder abzusagen.
- "frist": Ein Dokument mit einem Stichtag, einer Gueltigkeit oder einem Betrag, meist eine Verordnung.
- "nachfassen": Eine eigene frueher gestellte Frage ist unbeantwortet geblieben.
- "sonstiges": Alles andere. Im Zweifel diese Kategorie.

Regeln:
- Erfinde keine Daten. Steht ein Datum nicht in der Nachricht, ist fristDatum null.
- Relative Angaben ("naechste Woche", "in 14 Tagen") rechnest du gegen das mitgelieferte heutige Datum aus.
- Ein deutsches Datum 18.08.2026 ist der 18. August, nicht der 8. Oktober.
- titel ist EIN Satz, den die Therapeutin auf einen Blick versteht. Kein Fachjargon, keine Anrede, kein Betreff-Zitat. Beispiel: "Termin mit Frau Berger (Mutter von Jonas)".
- vertrauen ist "niedrig", sobald du raten muesstest. Ein falsch gelesenes Datum kostet die Therapeutin bares Geld; eine Rueckfrage kostet sie zehn Sekunden.
- istZusage ist nur true, wenn eindeutig ein konkreter Terminvorschlag angenommen wurde.`;

export type Analysator = (
  mail: EingehendeMail,
  kontext: { heute: Date; zeitzone: string; vorschlaege?: string[] },
) => Promise<Analyse>;

let ueberschrieben: Analysator | null = null;

/**
 * Testnaht. Ohne sie waeren die Engine-Tests entweder von einem echten
 * Modellaufruf abhaengig oder wuerden nur den Attrappen-Pfad pruefen, der
 * absichtlich immer "vertrauen: niedrig" liefert — der interessante Pfad
 * bliebe ungetestet.
 */
export function setzeAnalysator(fn: Analysator | null): void {
  ueberschrieben = fn;
}

export async function analysiere(
  mail: EingehendeMail,
  kontext: { heute: Date; zeitzone: string; vorschlaege?: string[] },
): Promise<Analyse> {
  if (ueberschrieben) return ueberschrieben(mail, kontext);
  if (!hatModellZugang()) return attrappenAnalyse(mail);

  const anhangText = mail.anhaenge
    .map((a) =>
      a.extraktionFehlgeschlagen
        ? `[Anhang ${a.dateiname}: kein Text lesbar, vermutlich ein Scan]`
        : `[Anhang ${a.dateiname}]\n${a.textExtrakt?.slice(0, 8000)}`,
    )
    .join('\n\n');

  const vorschlagsBlock = kontext.vorschlaege?.length
    ? `\n\nWir hatten diese Termine vorgeschlagen:\n${kontext.vorschlaege
        .map((v, i) => `${i + 1}. ${v}`)
        .join('\n')}`
    : '';

  const prompt = `Heutiges Datum: ${kontext.heute.toISOString().slice(0, 10)} (Zeitzone ${kontext.zeitzone})

Von: ${mail.vonName ?? ''} <${mail.von}>
Betreff: ${mail.betreff}

${mail.text}

${anhangText}${vorschlagsBlock}`;

  return strukturiert<Analyse>({
    modell: MODELL_EXTRAKTION,
    system: SYSTEM,
    prompt,
    schema: SCHEMA,
    maxTokens: 1000,
  });
}

/**
 * Ohne API-Schluessel: eine ehrliche, regelbasierte Notloesung.
 *
 * Sie ist absichtlich schlecht und setzt vertrauen auf "niedrig", damit im
 * Attrappen-Modus jeder Vorgang zur Rueckfrage fuehrt statt zu einer
 * Handlung. Sie existiert, damit `npm run dev` ohne Konto laeuft — nicht,
 * damit man sie produktiv nimmt.
 */
export function attrappenAnalyse(mail: EingehendeMail): Analyse {
  const text = `${mail.betreff}\n${mail.text}`.toLowerCase();
  const datum = /(\d{1,2})\.(\d{1,2})\.(\d{4})/.exec(`${mail.betreff} ${mail.text} ${
    mail.anhaenge.map((a) => a.textExtrakt ?? '').join(' ')
  }`);

  const art: Analyse['art'] = /verordnung|frist|gueltig|gültig/.test(text)
    ? 'frist'
    : /termin|verschieben|absagen|uhrzeit/.test(text)
      ? 'termin'
      : 'sonstiges';

  return {
    art,
    titel:
      art === 'frist'
        ? `Dokument von ${mail.vonName ?? mail.von}`
        : `Termin mit ${mail.vonName ?? mail.von}`,
    gegenueberName: mail.vonName,
    fristDatum: datum ? `${datum[3]}-${datum[2]!.padStart(2, '0')}-${datum[1]!.padStart(2, '0')}` : null,
    betragEuro: null,
    istZusage: false,
    zugesagterVorschlag: null,
    vertrauen: 'niedrig',
    begruendung:
      'Attrappen-Modus ohne ANTHROPIC_API_KEY: regelbasiert geraten, deshalb immer geringes Vertrauen.',
  };
}
