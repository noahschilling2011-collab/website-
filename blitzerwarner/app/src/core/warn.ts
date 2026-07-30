/**
 * Der Warnalgorithmus, Spec Abschnitt 5.
 *
 * Bewusst als reine Funktion über einem expliziten Zustand gebaut, ohne
 * jeden Bezug zu expo-location, Audio oder UI. Der Grund steht in der Spec:
 * Phase 3 ist die Phase, in der solche Projekte sterben, und die Warnlogik
 * lässt sich nur beim Autofahren debuggen, wenn sie nicht isoliert testbar
 * ist. Genau deshalb füttert der Replay-Test dieselbe Funktion mit GPX.
 */
import { WARN } from '../config';
import type { Camera, Evaluation, Fix, Settings, SkipReason } from '../types';
import { angleDiff, bearing, haversine, neighbourKeys } from './geo';

/** Zustand über eine Fahrt hinweg. Vom Aufrufer gehalten, nicht global. */
export type TripState = {
  /**
   * Kameras, vor denen in dieser Fahrt bereits gewarnt wurde, und ob sie
   * wieder scharf sind. Schlüssel ist die gerundete Koordinate.
   */
  gewarnt: Map<string, { wiederScharf: boolean }>;
  /**
   * Zeitstempel der letzten ausgelösten Warnung, für WARN.MIN_ANSAGE_ABSTAND_MS.
   * null = in dieser Fahrt noch nicht gewarnt.
   */
  letzteAnsageT: number | null;
};

export function createTripState(): TripState {
  return { gewarnt: new Map(), letzteAnsageT: null };
}

export function cameraKey(c: Camera): string {
  return `${c.lat.toFixed(5)},${c.lon.toFixed(5)}`;
}

/** Warndistanz in Abhängigkeit der Geschwindigkeit, Spec Abschnitt 5. */
export function warnDistance(speedMs: number | null, factor = 1): number {
  const v = speedMs ?? 0;
  if (v < WARN.UNRELIABLE_COURSE_SPEED_MS) {
    // Langsam: Kurs unzuverlässig, deshalb nur auf kurze Distanz warnen.
    return WARN.SLOW_SPEED_DISTANCE_M * factor;
  }
  return Math.max(WARN.MIN_DISTANCE_M, v * WARN.DISTANCE_PER_SPEED) * factor;
}

/** Ist der GPS-Kurs bei dieser Geschwindigkeit brauchbar? */
export function courseIsReliable(speedMs: number | null, course: number | null): boolean {
  if (course == null) return false;
  return (speedMs ?? 0) >= WARN.UNRELIABLE_COURSE_SPEED_MS;
}

/** Soll dieser Kameratyp überhaupt warnen? */
function typeEnabled(camera: Camera, settings: Pick<Settings, 'rotlichtblitzer'>): boolean {
  if (camera.type === 'red_light') return settings.rotlichtblitzer;
  return true;
}

/**
 * Eine Position auswerten und gegebenenfalls eine Warnung zurückgeben.
 *
 * `collectSkipped` füllt die Begründungen, warum Kameras verworfen wurden.
 * Im Betrieb aus (kostet Speicher), im Replay-Test an — dort ist genau das
 * die interessante Information.
 */
export function evaluate(
  fix: Fix,
  grid: Record<string, Camera[]>,
  state: TripState,
  settings: Pick<Settings, 'rotlichtblitzer' | 'warnDistanceFactor'>,
  collectSkipped = false,
): Evaluation {
  const skipped: Evaluation['skipped'] = collectSkipped ? [] : undefined;
  const note = (camera: Camera, reason: SkipReason, distance: number) => {
    if (skipped) skipped.push({ camera, reason, distance });
  };

  const reichweite = warnDistance(fix.speed, settings.warnDistanceFactor);
  const kursBrauchbar = courseIsReliable(fix.speed, fix.course);

  let beste: { camera: Camera; distance: number } | null = null;

  for (const key of neighbourKeys(fix.lat, fix.lon)) {
    const zelle = grid[key];
    if (!zelle) continue;

    for (const camera of zelle) {
      const d = haversine(fix.lat, fix.lon, camera.lat, camera.lon);

      // Schritt f zuerst: Eine Kamera, die sich weit genug entfernt hat,
      // wird wieder scharf. Das muss auch dann laufen, wenn sie gerade
      // ausserhalb der Warndistanz liegt — sonst wird sie nie wieder scharf.
      const key2 = cameraKey(camera);
      const merk = state.gewarnt.get(key2);
      if (merk && !merk.wiederScharf && d > reichweite * WARN.REARM_DISTANCE_FACTOR) {
        merk.wiederScharf = true;
      }

      if (d > reichweite) {
        note(camera, 'zu_weit', d);
        continue;
      }

      if (!typeEnabled(camera, settings)) {
        note(camera, 'typ_abgeschaltet', d);
        continue;
      }

      if (merk && !merk.wiederScharf) {
        note(camera, 'bereits_gewarnt', d);
        continue;
      }

      if (kursBrauchbar) {
        // Schritt d: Liegt die Kamera voraus?
        const peilung = bearing(fix.lat, fix.lon, camera.lat, camera.lon);
        if (angleDiff(peilung, fix.course!) > WARN.MAX_BEARING_DELTA_DEG) {
          note(camera, 'nicht_voraus', d);
          continue;
        }

        // Schritt e: Überwacht die Kamera unsere Richtung?
        // Greift nur bei den rund 36 % mit bekannter Ausrichtung.
        if (
          camera.dir != null &&
          angleDiff(camera.dir, fix.course!) > WARN.MAX_CAMERA_DIR_DELTA_DEG
        ) {
          note(camera, 'gegenrichtung', d);
          continue;
        }
      }

      if (!beste || d < beste.distance) beste = { camera, distance: d };
    }
  }

  if (!beste) return { warning: null, skipped };

  /*
   * Zwei Ansagen dürfen sich nicht überschneiden.
   *
   * Der Fall, gegen den das steht: Zwei Anlagen liegen gleichzeitig in
   * Reichweite. Vermerkt wird nur die nächstgelegene, die zweite löst
   * deshalb beim nächsten Fix eine eigene Warnung aus — im Annäherungsmodus
   * bei 100 km/h also 0,9 s später. Gemessen an Paaren mit 20 bis 50 m
   * Abstand, und davon gibt es im deutschen Datensatz 344.
   *
   * DIE KAMERA WIRD NICHT VERMERKT. Sie ist nicht abgehandelt, sondern
   * verschoben: Sobald der Abstand eingehalten ist, kommt ihre Warnung — dann
   * bei kürzerer Entfernung. Sie hier zu vermerken hiesse, die zweite Anlage
   * stillschweigend zu verschlucken, und das ist bei 250 m Abstand (9 s, zwei
   * getrennte Warnungen) genau die falsche Antwort.
   */
  if (
    state.letzteAnsageT !== null &&
    fix.t - state.letzteAnsageT < WARN.MIN_ANSAGE_ABSTAND_MS
  ) {
    note(beste.camera, 'ansage_zu_dicht', beste.distance);
    return { warning: null, skipped };
  }

  state.gewarnt.set(cameraKey(beste.camera), { wiederScharf: false });
  state.letzteAnsageT = fix.t;
  return {
    warning: { camera: beste.camera, distance: beste.distance, t: fix.t },
    skipped,
  };
}

/**
 * Distanz zur nächsten Kamera überhaupt — unabhängig von Richtung und
 * Warnstatus. Braucht die Akku-Strategie, um zwischen Leerlauf und
 * Annäherungsmodus umzuschalten (Spec Abschnitt 6).
 */
export function distanceToNearest(
  fix: Pick<Fix, 'lat' | 'lon'>,
  grid: Record<string, Camera[]>,
): number | null {
  let best: number | null = null;
  for (const key of neighbourKeys(fix.lat, fix.lon)) {
    const zelle = grid[key];
    if (!zelle) continue;
    for (const camera of zelle) {
      const d = haversine(fix.lat, fix.lon, camera.lat, camera.lon);
      if (best == null || d < best) best = d;
    }
  }
  return best;
}
