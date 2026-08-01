/**
 * Die gebündelten Zonendatensätze: pro Land einmal laden, prüfen, halten.
 *
 * Gegenstück zu dataset.ts, und aus demselben Grund so ausführlich: Ein
 * Zonendatensatz, der nicht ankommt, ist von aussen nicht zu bemerken. Die
 * App startet, meldet den Zonenmodus, sagt "Hinweise aktiviert" — und schweigt
 * danach für den Rest der Fahrt. Wer das erlebt, hält es für "hier stand
 * eben nichts". Deshalb wird ein fehlender oder unlesbarer Datensatz hier
 * erzwungen sichtbar gemacht und nicht im Betrieb gehofft.
 *
 * WARUM PRO LAND UND NICHT ALLES AUF VORRAT
 *
 * Ein Zonendatensatz ist kein kleiner Anhang: Frankreich sind 103 KB, und
 * mit dem Ausbau auf Europa kämen weitere dazu. Geladen wird deshalb genau
 * das Land, in dem gefahren wird, und erst wenn das Länder-Gate es
 * festgestellt hat.
 *
 * Kein Netzzugriff, kein Nachladepfad. Die Dateien liegen im App-Paket, ein
 * neuer Stand kommt mit einem App-Update.
 *
 * Dieses Modul protokolliert nicht selbst (kein Import von log.ts): Es liefert
 * einen Status, der Aufrufer entscheidet, was er damit meldet — genauso wie
 * dataset.ts.
 */
import { LAENDER_GATE, type LandCode } from '../config';
import { zonenDatensatzPruefen, type Zone, type ZonenDatensatz } from './zone';

/**
 * Welche Länder eine Zonendatei im Paket haben.
 *
 * Die require()-Aufrufe stehen einzeln und mit festem Pfad da, weil Metro sie
 * zur Bauzeit auflösen muss. Ein berechneter Pfad
 * (`require('../../assets/data/cameras.' + land + '.zones.json')`) landet
 * NICHT im Paket — Metro sieht ihn nicht und packt die Datei nicht ein. Zur
 * Laufzeit käme dann ein Fehler, den kein Test hier bemerkt, weil unter Node
 * dieselbe Zeile funktioniert. Das ist genau die Sorte Ausfall, gegen die
 * dieses Modul gebaut ist.
 *
 * Warum hier nur FR steht, obwohl scripts/build-zones.ts auch eine deutsche
 * Datei erzeugt: Deutschland ist per Gate 'aus' (§ 23 Abs. 1c StVO). Ein
 * Eintrag dafür würde 120 KB ins Paket ziehen, die nie gelesen werden — und
 * schlimmer, er würde behaupten, dass in Deutschland Hinweise vorgesehen sind.
 * Die deutsche Zonendatei entsteht nur, damit sich der Generator gegen einen
 * grossen, dichten Datensatz prüfen lässt (siehe DATA.md, MAX_ZONEN_RADIUS_M).
 */
const ROHDATEN: Partial<Record<LandCode, () => unknown>> = {
  FR: () => require('../../assets/data/cameras.FR.zones.json') as unknown,
};

export type ZonenFehlerGrund =
  /** Für dieses Land liegt gar keine Datei im Paket. */
  | 'keine_datei'
  /** Die Datei ist da, aber die Prüfung in zone.ts hat sie abgelehnt. */
  | 'unlesbar';

export class ZonenFehler extends Error {
  readonly grund: ZonenFehlerGrund;
  readonly land: string;

  constructor(grund: ZonenFehlerGrund, land: string, detail: string) {
    super(`${land}: ${grund}: ${detail}`);
    this.name = 'ZonenFehler';
    this.grund = grund;
    this.land = land;
    // Ohne diese Zeile schlägt `instanceof` fehl, sobald nach ES5
    // heruntergebrochen wird — Hermes tut das für ältere Ziele.
    Object.setPrototypeOf(this, ZonenFehler.prototype);
  }
}

type Zustand =
  | { art: 'leer' }
  | { art: 'geladen'; datensatz: ZonenDatensatz }
  | { art: 'fehler'; fehler: ZonenFehler };

/** Pro Land ein Zustand. Modul-global wie in dataset.ts, aus demselben Grund. */
const zustaende = new Map<string, Zustand>();

function zustandVon(land: LandCode): Zustand {
  return zustaende.get(land) ?? { art: 'leer' };
}

/**
 * Erwartet dieses Land überhaupt Zonen?
 *
 * Die Antwort kommt aus der Gate-Tabelle und nicht aus ROHDATEN — sonst
 * definierte die Anwesenheit einer Datei, was rechtlich gilt. Die Reihenfolge
 * ist umgekehrt: Das Gate sagt, was gebraucht wird, und das Fehlen der Datei
 * ist dann ein Fehler und kein Zustand.
 */
export function brauchtZonen(land: LandCode | null): boolean {
  if (land === null) return false;
  const eintrag = LAENDER_GATE.LAENDER[land];
  return eintrag.status === 'belegt' && eintrag.modus === 'zone';
}

/**
 * Den Zonendatensatz eines Landes laden. Wirft bei fehlender oder unlesbarer
 * Datei.
 *
 * Ein einmal gescheitertes Laden wird nicht wiederholt: Das App-Paket ändert
 * sich zur Laufzeit nicht, ein zweiter Versuch käme zum selben Ergebnis. Das
 * ist hier wichtiger als bei dataset.ts, weil dieser Aufruf im Hintergrund-
 * Task pro Position laufen kann — ohne die Merkung würde bei jedem Fix erneut
 * geparst und erneut protokolliert.
 */
export function ladeZonen(land: LandCode): ZonenDatensatz {
  const vorhanden = zustandVon(land);
  if (vorhanden.art === 'geladen') return vorhanden.datensatz;
  if (vorhanden.art === 'fehler') throw vorhanden.fehler;

  try {
    const lader = ROHDATEN[land];
    if (lader === undefined) {
      throw new ZonenFehler(
        'keine_datei', land,
        'kein Eintrag in ROHDATEN — die Datei ist nicht im App-Paket',
      );
    }

    const datensatz = zonenDatensatzPruefen(lader());
    if (datensatz.land !== land) {
      throw new ZonenFehler(
        'unlesbar', land,
        `die Datei gehört zu ${datensatz.land}`,
      );
    }
    // Eine leere Zonendatei kann nur ein Fehler beim Bauen sein. Sie führte
    // sonst zu genau dem stillen Ausfall, gegen den dieses Modul steht.
    if (datensatz.zones.length === 0) {
      throw new ZonenFehler('unlesbar', land, 'die Datei enthält keine Zonen');
    }

    zustaende.set(land, { art: 'geladen', datensatz });
    return datensatz;
  } catch (fehler) {
    const gemerkt =
      fehler instanceof ZonenFehler
        ? fehler
        : new ZonenFehler(
            'unlesbar', land,
            fehler instanceof Error ? fehler.message : String(fehler),
          );
    zustaende.set(land, { art: 'fehler', fehler: gemerkt });
    throw gemerkt;
  }
}

/**
 * Die Zonen eines Landes oder null, wenn sie nicht zu haben sind.
 *
 * Die Variante ohne Ausnahme, für den Hintergrund-Task: Dort ist ein Wurf pro
 * Position teuer und der Umgang mit dem Fehler ohnehin derselbe. Wer wissen
 * will, WARUM null kommt, fragt zonenFehler().
 */
export function zonenOderNull(land: LandCode): readonly Zone[] | null {
  try {
    return ladeZonen(land).zones;
  } catch {
    return null;
  }
}

/**
 * Der gemerkte Fehler für ein Land, oder null.
 *
 * Absichtlich getrennt von zonenOderNull(): Der Aufrufer soll den Fehler genau
 * einmal protokollieren können, ohne ihn bei jedem Fix erneut zu erzeugen.
 */
export function zonenFehler(land: LandCode): ZonenFehler | null {
  const z = zustandVon(land);
  return z.art === 'fehler' ? z.fehler : null;
}

/** Ist der Datensatz für dieses Land geladen? Ohne Nebenwirkung, wirft nicht. */
export function sindZonenGeladen(land: LandCode): boolean {
  return zustandVon(land).art === 'geladen';
}

/**
 * Nur für Tests: den gemerkten Zustand vergessen.
 *
 * Steht hier und nicht in einer Testhilfe, weil der Zustand modul-global ist
 * und ein Test sonst den nächsten beeinflusst. Im Betrieb ruft das niemand
 * auf — es gäbe auch keinen Grund, das App-Paket ändert sich nicht.
 */
export function vergisseZonen(): void {
  zustaende.clear();
}
