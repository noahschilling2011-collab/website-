import Anthropic from '@anthropic-ai/sdk';

/**
 * Zwei Modelle, zwei Aufgaben (Entwurf, Abschnitt 6):
 *
 *   claude-haiku-4-5  Klassifikation und Extraktion. Viele Aufrufe, kurze
 *                     Ausgaben, strukturiertes JSON.
 *   claude-sonnet-5   Formulierung und Verhandlung. Wenige Aufrufe, laengere
 *                     Ausgaben, geht an einen echten Menschen.
 *
 * Zur Kostenrechnung in Abschnitt 10 des Entwurfs eine Korrektur: dort
 * stand "Prompt Caching fuer den System-Prompt". Das traegt hier nicht.
 * Die cachebare Mindestlaenge liegt bei Haiku 4.5 bei 4096 und bei
 * Sonnet 5 bei 1024 Token; die System-Prompts unten liegen deutlich
 * darunter. Ein cache_control-Marker waere reine Dekoration — er wuerde
 * stillschweigend nichts cachen. Deshalb steht er nicht im Code.
 */

export const MODELL_EXTRAKTION = 'claude-haiku-4-5';
export const MODELL_FORMULIERUNG = 'claude-sonnet-5';

let client: Anthropic | null = null;

export function anthropic(): Anthropic {
  if (!client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error(
        'ANTHROPIC_API_KEY fehlt. Ohne den Schluessel laeuft die App im Attrappen-Modus (siehe README).',
      );
    }
    client = new Anthropic({ apiKey });
  }
  return client;
}

export function hatModellZugang(): boolean {
  return Boolean(process.env.ANTHROPIC_API_KEY);
}

/** JSON-Schema fuer Structured Outputs. */
export type JsonSchema = {
  type: 'object';
  properties: Record<string, unknown>;
  required: string[];
  additionalProperties: false;
};

/**
 * Ein Aufruf mit garantiert schema-konformer JSON-Antwort.
 *
 * output_config.format zwingt das Modell in die Form; die Antwort muss
 * trotzdem geparst werden, und `stop_reason` muss vorher geprueft werden:
 * bei "refusal" ist content leer, bei "max_tokens" abgeschnitten. Wer
 * blind content[0].text liest, faellt bei beidem auf die Nase.
 */
export async function strukturiert<T>(optionen: {
  modell: string;
  system: string;
  prompt: string;
  schema: JsonSchema;
  maxTokens?: number;
  effort?: 'low' | 'medium' | 'high';
}): Promise<T> {
  const anfrage: Record<string, unknown> = {
    model: optionen.modell,
    max_tokens: optionen.maxTokens ?? 2000,
    system: optionen.system,
    messages: [{ role: 'user', content: optionen.prompt }],
    output_config: {
      format: { type: 'json_schema', schema: optionen.schema },
      // effort gibt es auf Haiku 4.5 nicht — dort wuerde der Parameter
      // einen Fehler ausloesen. Deshalb nur setzen, wenn der Aufrufer ihn
      // ausdruecklich mitgibt.
      ...(optionen.effort ? { effort: optionen.effort } : {}),
    },
  };

  const antwort = await anthropic().messages.create(anfrage as never);

  if (antwort.stop_reason === 'refusal') {
    throw new Error(
      `Das Modell hat die Anfrage abgelehnt (${antwort.stop_details?.category ?? 'ohne Kategorie'}).`,
    );
  }
  if (antwort.stop_reason === 'max_tokens') {
    throw new Error('Die Antwort wurde abgeschnitten. max_tokens erhoehen.');
  }

  const block = antwort.content.find((b) => b.type === 'text');
  if (!block || block.type !== 'text') {
    throw new Error('Das Modell hat keinen Textblock geliefert.');
  }
  return JSON.parse(block.text) as T;
}
