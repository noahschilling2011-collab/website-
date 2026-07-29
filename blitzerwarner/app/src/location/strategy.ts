/**
 * Akku-Strategie, Spec Abschnitt 6.
 *
 * Reine Funktionen über explizitem Zustand — kein expo-Import, damit die
 * Strategie testbar ist, ohne stundenlang mit dem Handy herumzufahren.
 *
 * Das messbare Ziel lautet unter 3 % Akku pro Stunde. Der grösste Posten
 * dabei ist die GPS-Genauigkeit: Hochgenaue Ortung dauerhaft laufen zu
 * lassen kostet ein Mehrfaches. Deshalb wird sie nur eingeschaltet, wenn
 * überhaupt eine Kamera in der Nähe ist.
 */
import { BATTERY, WARN } from '../config';

export type Genauigkeit = 'balanced' | 'high';

export type Modus =
  /** Weit weg von jeder Kamera: sparsam. */
  | 'leerlauf'
  /** Kamera in der Nähe: genau. */
  | 'annaeherung'
  /** Steht offenbar: maximal sparsam. */
  | 'geparkt';

export type Vorgabe = {
  modus: Modus;
  genauigkeit: Genauigkeit;
  distanceIntervalM: number;
};

export type StrategyState = {
  modus: Modus;
  /** Seit wann durchgehend langsam? null = fährt. */
  langsamSeit: number | null;
};

export function createStrategyState(): StrategyState {
  return { modus: 'leerlauf', langsamSeit: null };
}

const VORGABEN: Record<Modus, Omit<Vorgabe, 'modus'>> = {
  leerlauf: { genauigkeit: 'balanced', distanceIntervalM: BATTERY.IDLE_DISTANCE_INTERVAL_M },
  annaeherung: { genauigkeit: 'high', distanceIntervalM: BATTERY.APPROACH_DISTANCE_INTERVAL_M },
  geparkt: { genauigkeit: 'balanced', distanceIntervalM: BATTERY.PARKED_DISTANCE_INTERVAL_M },
};

/**
 * Den gewünschten Modus bestimmen.
 *
 * `distanzZurNaechsten` ist die Entfernung zur nächsten Kamera überhaupt,
 * unabhängig von Richtung — wir wissen ja noch nicht, wohin gefahren wird.
 * null bedeutet, dass in der geladenen Nachbarschaft keine liegt.
 */
export function bestimmeModus(
  state: StrategyState,
  distanzZurNaechsten: number | null,
  speedMs: number | null,
  jetzt: number,
): Modus {
  const v = speedMs ?? 0;

  // Langsam-Zähler pflegen. Er läuft unabhängig vom Modus, damit ein
  // Fahrzeug, das im Annäherungsmodus stehenbleibt, irgendwann drosselt.
  if (v < BATTERY.PARKED_SPEED_MS) {
    state.langsamSeit ??= jetzt;
  } else {
    state.langsamSeit = null;
  }

  const stehtLange =
    state.langsamSeit != null && jetzt - state.langsamSeit >= BATTERY.PARKED_AFTER_MS;

  const kameraNah =
    distanzZurNaechsten != null && distanzZurNaechsten <= BATTERY.HIGH_ACCURACY_RADIUS_M;

  // Eine nahe Kamera schlägt "geparkt" NICHT, wenn man sehr nah dran ist:
  // Wer im Stau 100 m vor der Kamera steht, soll die Warnung noch bekommen.
  // Nur wenn die Kamera weiter weg ist als die Warndistanz im Stand, darf
  // gedrosselt werden.
  if (stehtLange && (!kameraNah || (distanzZurNaechsten ?? 0) > WARN.SLOW_SPEED_DISTANCE_M * 2)) {
    return 'geparkt';
  }

  return kameraNah ? 'annaeherung' : 'leerlauf';
}

/**
 * Die aktuelle Vorgabe berechnen und nur bei echtem Moduswechsel melden.
 *
 * Jede Neukonfiguration des Location-Providers kostet Strom und kann kurz
 * zu Aussetzern führen. Deshalb wird der Aufrufer nur informiert, wenn sich
 * tatsächlich etwas ändert — das ist die Hysterese.
 */
export function aktualisiere(
  state: StrategyState,
  distanzZurNaechsten: number | null,
  speedMs: number | null,
  jetzt: number,
): { vorgabe: Vorgabe; geaendert: boolean } {
  const neuerModus = bestimmeModus(state, distanzZurNaechsten, speedMs, jetzt);
  const geaendert = neuerModus !== state.modus;
  state.modus = neuerModus;
  return { vorgabe: { modus: neuerModus, ...VORGABEN[neuerModus] }, geaendert };
}

/** Vorgabe zum Modus, ohne den Zustand zu verändern. */
export function vorgabeFuer(modus: Modus): Vorgabe {
  return { modus, ...VORGABEN[modus] };
}
