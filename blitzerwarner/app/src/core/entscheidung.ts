/**
 * Was bei dieser Position zu tun ist — als reine Funktion.
 *
 * WARUM DIESE DATEI EXISTIERT
 *
 * Die Entscheidung stand vorher mitten in `location/task.ts`, verwoben mit
 * `expo-location`, `expo-av` und dem Watchdog. Damit war sie nicht prüfbar:
 * Getestet wurde `evaluate()` und `pruefeZonen()` einzeln, aber nicht, WELCHE
 * der beiden bei welchem Warnmodus überhaupt zum Zug kommt. Genau dort sass
 * der Fehler, der Frankreich stumm liess — beide Bausteine waren in Ordnung,
 * die Verdrahtung nicht.
 *
 * Diese Datei kennt kein expo, keinen Ton und keine Stimme. Sie sagt nur, was
 * geschehen soll; das Ausführen bleibt im Task.
 *
 * DIE WICHTIGSTE EIGENSCHAFT IST DER TYP, NICHT DER CODE
 *
 * `Aktion` ist so geschnitten, dass eine Zonenansage mit Entfernung sich gar
 * nicht erst hinschreiben lässt: Der Fall 'zonenhinweis' hat keine Felder.
 * Frankreich untersagt seit 03.01.2012 die Entfernungsangabe (bis 1500 Euro,
 * Einziehung des Geräts). Eine Prüfung, die man umgehen kann, indem man ein
 * Feld befüllt, wäre schwächer als eine, die es nicht gibt.
 */
import type { Warnmodus } from '../config';
import type { Camera, Fix, Settings } from '../types';
import { evaluate, type TripState } from './warn';
import { pruefeZonen, type Zone, type ZonenZustand } from './zone';

/** Warum nichts geschieht. Nicht für die UI, sondern für Test und Protokoll. */
export type NichtsGrund =
  /** Das Länder-Gate erlaubt in diesem Land keine Warnung. */
  | 'land_gesperrt'
  /** Punktmodus, aber keine Anlage in Reichweite und Richtung. */
  | 'keine_anlage'
  /** Zonenmodus, aber die Position liegt in keiner neu betretenen Zone. */
  | 'keine_zone'
  /**
   * Zonenmodus, aber für dieses Land liegen keine Zonendaten vor.
   *
   * Ein eigener Grund und nicht 'keine_zone': Der Unterschied zwischen "hier
   * ist keine Zone" und "wir wissen es nicht" ist der ganze Punkt. Der erste
   * Fall ist Normalbetrieb, der zweite ein Ausfall, der protokolliert gehört.
   */
  | 'zonendaten_fehlen';

/**
 * Was der Task tun soll.
 *
 * 'zonenhinweis' trägt bewusst KEINE Nutzlast — keine Zone, keine Entfernung,
 * keine Zahl. Was die Aktion nicht kennt, kann der Task nicht aussprechen.
 */
export type Aktion =
  | { readonly art: 'nichts'; readonly grund: NichtsGrund }
  | { readonly art: 'punktwarnung'; readonly camera: Camera; readonly distanzM: number }
  | { readonly art: 'zonenhinweis' };

/**
 * Alles, was die Entscheidung ausser der Position braucht.
 *
 * Als ein Objekt und nicht als sechs Parameter: Die Reihenfolge von sechs
 * Argumenten verwechselt man, einen Feldnamen nicht.
 */
export type Eingang = {
  readonly grid: Record<string, Camera[]>;
  /** Fahrtzustand der Punktwarnung. Wird von evaluate() fortgeschrieben. */
  readonly trip: TripState;
  readonly settings: Settings;
  /**
   * Zonen des aktuellen Landes, oder null, wenn keine vorliegen.
   *
   * null ist nicht dasselbe wie eine leere Liste: leer hiesse "dieses Land hat
   * keine Zonen", null heisst "wir haben die Daten nicht". Nur der zweite Fall
   * ist ein Ausfall.
   */
  readonly zonen: readonly Zone[] | null;
  /** Zonenzustand der Fahrt. Wird von pruefeZonen() fortgeschrieben. */
  readonly zonenZustand: ZonenZustand;
};

/**
 * Die Entscheidung.
 *
 * Der Warnmodus kommt fertig herein und wird hier nicht noch einmal aus der
 * Gate-Tabelle abgeleitet. Grund: Die Modusbestimmung hängt an der Hysterese
 * in country.ts und damit an einem Zustand über die Fahrt. Sie hier zu
 * wiederholen hiesse, zwei Orte zu haben, an denen "welches Land" beantwortet
 * wird — und irgendwann antworten sie verschieden.
 */
export function entscheide(fix: Fix, modus: Warnmodus, eingang: Eingang): Aktion {
  if (modus === 'aus') {
    return { art: 'nichts', grund: 'land_gesperrt' };
  }

  if (modus === 'zone') {
    // Kein Rückfall auf die Punktwarnung. Das wäre der teuerste Fehler, den
    // diese Datei machen könnte: In Frankreich ist die Punktwarnung verboten,
    // "lieber irgendetwas als nichts" also genau falsch herum.
    if (eingang.zonen === null) {
      return { art: 'nichts', grund: 'zonendaten_fehlen' };
    }
    const ergebnis = pruefeZonen(fix.lat, fix.lon, eingang.zonen, eingang.zonenZustand);
    return ergebnis.betreten === null
      ? { art: 'nichts', grund: 'keine_zone' }
      : { art: 'zonenhinweis' };
  }

  // modus === 'punkt'
  const ergebnis = evaluate(fix, eingang.grid, eingang.trip, eingang.settings);
  if (ergebnis.warning === null) {
    return { art: 'nichts', grund: 'keine_anlage' };
  }
  return {
    art: 'punktwarnung',
    camera: ergebnis.warning.camera,
    distanzM: ergebnis.warning.distance,
  };
}
