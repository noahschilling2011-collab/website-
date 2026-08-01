/**
 * Die Einstellungen: Standardwerte und das Lesen gespeicherter Stände.
 *
 * WARUM DAS IN core/ LIEGT UND NICHT IM STORE
 *
 * Zwei Gründe, und der zweite ist der wichtigere:
 *
 *  1. Die Werte standen doppelt da — einmal in state/store.ts und einmal in
 *     location/task.ts, Zeichen für Zeichen gleich. Zwei Wahrheiten, die
 *     irgendwann auseinanderlaufen: Wer im Store einen Standard ändert und
 *     den Task übersieht, bekommt eine App, die vor dem ersten Laden anders
 *     rechnet als danach.
 *  2. state/store.ts zieht zustand und AsyncStorage und damit react-native
 *     herein. Damit ist es unter `tsx --test` nicht ladbar, und die Migration
 *     wäre ungetestet geblieben — ausgerechnet der Teil, der alte
 *     Speicherstände überlebt.
 *
 * Reine Funktionen über explizitem Zustand, wie warn.ts und zone.ts. Kein
 * expo, kein react-native, kein Speicher.
 */
import type { Settings } from '../types';

export const STANDARD_SETTINGS: Settings = {
  warnDistanceFactor: 1,
  sprachansage: true,
  lautstaerke: 1,
  rotlichtblitzer: true,
  motorradModus: false,
  haptik: false,
  tachoFaktor: 1,
  // Aus. Siehe types.ts — hier entsteht eine Bewegungsspur.
  fahrtprotokoll: false,
};

/**
 * Gespeicherte Werte mit den Standardwerten mischen.
 *
 * Drei Aufgaben, alle drei nötig:
 *
 *  - FEHLENDE Felder bekommen den Standardwert. Kommt in einer späteren
 *    Version eine Einstellung dazu, fehlt sie in den gespeicherten Daten.
 *    Ohne die Standardwerte wäre sie `undefined` und würde als "aus" gelesen
 *    — auch dort, wo "ein" der richtige Standard ist.
 *  - UNBEKANNTE Felder werden verworfen. Vorher übernahm ein
 *    `{ ...STANDARD_SETTINGS, ...gelesen }` alles, was im Speicher stand,
 *    auch entfernte Einstellungen. `tempolimitWarnung` wäre so als Leiche im
 *    Settings-Objekt weitergereist, ohne dass der Typcheck etwas gemerkt
 *    hätte — ein Spread verengt den Typ nicht.
 *  - FALSCH GETIPPTE Werte werden verworfen. Der Speicher enthält, was eine
 *    frühere Version geschrieben hat, und der Wert landet ungeprüft im
 *    Hintergrund-Task. Ein `lautstaerke: "laut"` wäre dort ein stiller
 *    Rechenfehler statt eines Absturzes.
 *
 * Wirft nicht. Eine App, die wegen alter Einstellungen nicht startet, warnt
 * auch nicht.
 */
export function mischeSettings(gelesen: unknown): Settings {
  const settings: Settings = { ...STANDARD_SETTINGS };
  if (typeof gelesen !== 'object' || gelesen === null || Array.isArray(gelesen)) {
    return settings;
  }

  const roh = gelesen as Record<string, unknown>;
  for (const schluessel of Object.keys(STANDARD_SETTINGS) as (keyof Settings)[]) {
    const wert = roh[schluessel];
    if (wert === undefined) continue;
    if (typeof wert !== typeof settings[schluessel]) continue;
    (settings as Record<string, unknown>)[schluessel] = wert;
  }
  return settings;
}
