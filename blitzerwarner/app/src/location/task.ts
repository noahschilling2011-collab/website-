/**
 * Der Hintergrund-Task.
 *
 * Wird von index.ts auf oberster Modulebene importiert, NICHT aus einem
 * Effect heraus. Wenn das System die App killt und später nur zur
 * Zustellung einer Position wieder hochfährt, läuft ausschliesslich
 * Modulcode — eine Registrierung in einem useEffect käme zu spät und der
 * Task wäre stumm. Genau das ist der Ausfall, den man erst merkt, wenn eine
 * Warnung nicht kommt.
 */
import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { errorLog } from '../core/log';
import { datasetOrNull } from '../core/dataset';
import { createTripState, distanceToNearest, evaluate, type TripState } from '../core/warn';
import { aktualisiere, createStrategyState, vorgabeFuer, type StrategyState } from './strategy';
import { createWatchdogState, meldeFix, starte, stoppe, type WatchdogState } from './watchdog';
import { gebeWarnung, sageAnsage } from '../audio/player';
import { landwechselText } from '../audio/announce';
import { aktualisiereLand, createLandZustand, leseLand, type LandStatus, type LandZustand } from '../core/country';
import type { Fix, Settings } from '../types';

export const LOCATION_TASK = 'blitzerwarner-location';

/**
 * Zustand des Tasks.
 *
 * Bewusst Modul-global: Der Task läuft in einem eigenen JS-Kontext, den React
 * nicht sieht. Ein React-State wäre hier nicht erreichbar.
 */
type TaskLaufzeit = {
  trip: TripState;
  strategy: StrategyState;
  watchdog: WatchdogState;
  settings: Settings;
  /** Letzte Position, für die UI über den Speicher. */
  letzterFix: Fix | null;
  /** Landerkennung mit Hysterese gegen Flackern an der Grenze. */
  landZustand: LandZustand;
  /** Zuletzt gemeldeter Zustand, um Wechsel zu bemerken. */
  warnungWarErlaubt: boolean | null;
};

const STANDARD_SETTINGS: Settings = {
  warnDistanceFactor: 1,
  sprachansage: true,
  lautstaerke: 1,
  rotlichtblitzer: true,
  motorradModus: false,
  haptik: false,
  tempolimitWarnung: false,
  tachoFaktor: 1,
};

const laufzeit: TaskLaufzeit = {
  trip: createTripState(),
  strategy: createStrategyState(),
  watchdog: createWatchdogState(),
  settings: { ...STANDARD_SETTINGS },
  letzterFix: null,
  landZustand: createLandZustand(),
  warnungWarErlaubt: null,
};

/** Von der UI aufzurufen, wenn der Nutzer Einstellungen ändert. */
export function setzeSettings(settings: Settings): void {
  laufzeit.settings = settings;
}

export function watchdogState(): WatchdogState {
  return laufzeit.watchdog;
}

export function letzterFix(): Fix | null {
  return laufzeit.letzterFix;
}

/**
 * Aktueller Landstatus für die Anzeige.
 *
 * Muss aus dem Task kommen: Der Zustand mit der Hysterese lebt dort. Würde
 * die UI sich einen eigenen Zustand anlegen, wäre er bei jedem Render leer
 * und das Rechtshinweis-Banner erschiene nie — also genau der Fall, der
 * rechtlich zählt.
 */
export function landStatus(): LandStatus {
  return leseLand(laufzeit.landZustand);
}

/** expo-location-Position in unser entkoppeltes Fix-Format. */
function alsFix(ort: Location.LocationObject): Fix {
  return {
    lat: ort.coords.latitude,
    lon: ort.coords.longitude,
    // expo liefert -1 statt null, wenn Kurs oder Tempo unbekannt sind.
    course: ort.coords.heading != null && ort.coords.heading >= 0 ? ort.coords.heading : null,
    speed: ort.coords.speed != null && ort.coords.speed >= 0 ? ort.coords.speed : null,
    accuracy: ort.coords.accuracy ?? null,
    t: ort.timestamp,
  };
}

/**
 * Eine Position verarbeiten. Herausgezogen aus dem Task-Handler, damit die
 * Reihenfolge der Schritte nachvollziehbar bleibt.
 */
async function verarbeite(fix: Fix): Promise<void> {
  // 1. Watchdog zuerst. Selbst wenn alles Weitere scheitert, ist damit
  //    belegt, dass der Task lebt.
  meldeFix(laufzeit.watchdog, Date.now());
  laufzeit.letzterFix = fix;

  const dataset = datasetOrNull();
  if (!dataset) {
    errorLog.error('daten', 'Kein Datensatz geladen — Warnung nicht möglich');
    return;
  }
  const grid = dataset.grid;

  // 2. Länder-Gate. In Deutschland, Österreich und der Schweiz darf die
  //    Warnung nach § 23 Abs. 1c StVO nicht laufen. Bewusst über
  //    aktualisiereLand() statt über eine direkte Abfrage: nur so greift die
  //    unsymmetrische Hysterese, die an Grenzfahrten das Flackern verhindert
  //    und im Zweifel abschaltet statt einzuschalten.
  const landStatus = aktualisiereLand(laufzeit.landZustand, fix);
  const darfWarnen = landStatus.warnungErlaubt;

  if (laufzeit.warnungWarErlaubt !== darfWarnen) {
    // Beim Grenzübertritt eine kurze Ansage (Spec 10.1). Beim allerersten
    // Fix wird nichts angesagt — da hat der Nutzer die App gerade gestartet
    // und braucht keine Meldung über einen Wechsel, der keiner war.
    const erstmalig = laufzeit.warnungWarErlaubt === null;
    laufzeit.warnungWarErlaubt = darfWarnen;
    errorLog.info(
      'position',
      `Land ${landStatus.umriss ?? 'unbestimmt'} (${landStatus.grund}), ` +
      `Warnung ${darfWarnen ? 'erlaubt' : 'gesperrt'}`,
    );
    if (!erstmalig) {
      await sageAnsage(landwechselText(darfWarnen), laufzeit.settings.lautstaerke);
    }
  }

  // 3. Akku-Strategie. Auch wenn nicht gewarnt werden darf, wird der Modus
  //    gepflegt — sonst läuft die App im falschen Land mit hoher
  //    Genauigkeit und frisst Akku ohne Nutzen.
  const naechste = distanceToNearest(fix, grid);
  const { vorgabe, geaendert } = aktualisiere(
    laufzeit.strategy, naechste, fix.speed, Date.now(),
  );
  if (geaendert) {
    await konfiguriereUpdates(vorgabe.genauigkeit, vorgabe.distanceIntervalM);
  }

  if (!darfWarnen) return;

  // 4. Warnlogik.
  const ergebnis = evaluate(fix, grid, laufzeit.trip, laufzeit.settings);
  if (!ergebnis.warning) return;

  await gebeWarnung(ergebnis.warning.camera, ergebnis.warning.distance, {
    sprache: laufzeit.settings.sprachansage,
    lautstaerke: laufzeit.settings.lautstaerke,
    speedKmh: fix.speed != null ? fix.speed * 3.6 : null,
  });
}

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  // Fehler NIEMALS verschlucken. Ein stiller Ausfall des Tasks ist der
  // gefährlichste Zustand der App.
  if (error) {
    errorLog.error('hintergrund', 'Location-Task meldet Fehler', error);
    return;
  }

  const positionen = (data as { locations?: Location.LocationObject[] } | null)?.locations;
  if (!positionen?.length) return;

  for (const ort of positionen) {
    try {
      await verarbeite(alsFix(ort));
    } catch (err) {
      errorLog.error('hintergrund', 'Position konnte nicht verarbeitet werden', err);
    }
  }
});

/** Genauigkeit auf die expo-Stufen abbilden. */
function accuracyFuer(genauigkeit: 'balanced' | 'high'): Location.LocationAccuracy {
  // BestForNavigation wäre genauer, kostet aber deutlich mehr Strom und
  // bringt für eine Distanzmessung auf einige hundert Meter nichts.
  return genauigkeit === 'high'
    ? Location.Accuracy.High
    : Location.Accuracy.Balanced;
}

async function konfiguriereUpdates(
  genauigkeit: 'balanced' | 'high',
  distanceIntervalM: number,
): Promise<void> {
  try {
    const laeuft = await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK);
    if (!laeuft) return;

    await Location.startLocationUpdatesAsync(LOCATION_TASK, {
      accuracy: accuracyFuer(genauigkeit),
      distanceInterval: distanceIntervalM,
      // Android: ohne sichtbare Notification killt das System den Task.
      foregroundService: {
        notificationTitle: 'Blitzerwarnung aktiv',
        notificationBody: 'Position wird nur auf dem Gerät verarbeitet.',
        notificationColor: '#FF3B30',
      },
      pausesUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
    });
    errorLog.info('hintergrund', `Updates neu konfiguriert: ${genauigkeit}, ${distanceIntervalM} m`);
  } catch (err) {
    errorLog.error('hintergrund', 'Updates konnten nicht neu konfiguriert werden', err);
  }
}

/** Tracking starten. Setzt den Fahrtzustand zurück. */
export async function starteTracking(settings: Settings): Promise<boolean> {
  laufzeit.settings = settings;
  laufzeit.trip = createTripState();
  laufzeit.strategy = createStrategyState();
  laufzeit.landZustand = createLandZustand();
  laufzeit.warnungWarErlaubt = null;

  const start = vorgabeFuer('leerlauf');

  try {
    await Location.startLocationUpdatesAsync(LOCATION_TASK, {
      accuracy: accuracyFuer(start.genauigkeit),
      distanceInterval: start.distanceIntervalM,
      foregroundService: {
        notificationTitle: 'Blitzerwarnung aktiv',
        notificationBody: 'Position wird nur auf dem Gerät verarbeitet.',
        notificationColor: '#FF3B30',
      },
      pausesUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
    });
    starte(laufzeit.watchdog, Date.now());
    errorLog.info('hintergrund', 'Tracking gestartet');
    return true;
  } catch (err) {
    errorLog.error('hintergrund', 'Tracking konnte nicht gestartet werden', err);
    return false;
  }
}

export async function stoppeTracking(): Promise<void> {
  try {
    const laeuft = await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK);
    if (laeuft) await Location.stopLocationUpdatesAsync(LOCATION_TASK);
    stoppe(laufzeit.watchdog);
    errorLog.info('hintergrund', 'Tracking gestoppt');
  } catch (err) {
    errorLog.error('hintergrund', 'Tracking konnte nicht gestoppt werden', err);
  }
}

export async function laeuftTracking(): Promise<boolean> {
  try {
    return await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK);
  } catch (err) {
    errorLog.error('hintergrund', 'Status des Trackings unbekannt', err);
    return false;
  }
}
