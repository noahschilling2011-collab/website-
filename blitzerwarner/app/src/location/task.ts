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
import { createTripState, distanceToNearest, type TripState } from '../core/warn';
import { entscheide } from '../core/entscheidung';
import { createZonenZustand, type ZonenZustand } from '../core/zone';
import { brauchtZonen, zonenFehler, zonenOderNull } from '../core/zonendaten';
import { aktualisiere, createStrategyState, vorgabeFuer, type StrategyState } from './strategy';
import { createWatchdogState, meldeFix, starte, stoppe, type WatchdogState } from './watchdog';
import { gebeWarnung, gebeZonenhinweis, sageAnsage } from '../audio/player';
import { landwechselText } from '../audio/announce';
import { aktualisiereLand, createLandZustand, leseLand, warnmodus, type LandStatus, type LandZustand } from '../core/country';
import type { Warnmodus } from '../config';
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
  /**
   * Zuletzt gemeldeter Warnmodus, um Wechsel zu bemerken. null = noch kein
   * Fix verarbeitet; daran hängt, dass der erste Fix keine Ansage auslöst.
   */
  letzterModus: Warnmodus | null;
  /**
   * Ob beim letzten Moduswechsel Punktwarnungen erlaubt waren. Nur für das
   * Protokoll und die UI — die Entscheidung fällt `modus`, nicht dieser Wert.
   */
  warnungWarErlaubt: boolean | null;
  /**
   * Zonenzustand der Fahrt (Frankreich). Analog zu `trip` und `strategy`:
   * gehört zur Fahrt, nicht zur App, und wird beim Start zurückgesetzt.
   */
  zonen: ZonenZustand;
  /**
   * Für welches Land der fehlende Zonendatensatz schon protokolliert wurde.
   *
   * Ein Set und kein Wahrheitswert: Auf einer Fahrt von Frankreich nach
   * Spanien wären es zwei verschiedene Ausfälle, und der zweite darf nicht
   * verschluckt werden, nur weil der erste gemeldet war. Bei jedem Fix
   * erneut zu protokollieren wäre die andere Untugend — das Protokoll fasst
   * 200 Einträge und wäre in einer Minute voll.
   */
  zonenAusfallGemeldet: Set<string>;
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
  letzterModus: null,
  warnungWarErlaubt: null,
  zonen: createZonenZustand(),
  zonenAusfallGemeldet: new Set(),
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

  /*
   * Der Warnmodus, nicht bloss ein Ja/Nein.
   *
   * Wichtig, und zwar rechtlich: 'zone' ist NICHT dasselbe wie 'punkt'.
   * Frankreich erlaubt seit 03.01.2012 nur den Hinweis auf einen
   * Gefahrenbereich; die Punktwarnung mit Entfernungsansage ist dort
   * verboten, bis 1500 Euro und Einziehung des Geräts.
   */
  const modus = warnmodus(landStatus.land);
  const darfWarnen = modus !== 'aus';

  /*
   * Der Grenzübertritt wird am MODUS erkannt, nicht an einem Ja/Nein.
   *
   * Die frühere Fassung verglich `darfPunktWarnen`. Beim Übertritt nach
   * Frankreich wechselt der Modus von 'aus' auf 'zone' — `darfPunktWarnen`
   * bleibt dabei in beiden Fällen false, der Wechsel fiel also stillschweigend
   * aus. Gemessen am Grenztrack (fixtures/grenze-kehl-strasbourg.gpx): ein
   * Moduswechsel, null Ansagen. Der Fahrer erfuhr nicht, dass die App jetzt
   * etwas tut.
   */
  if (laufzeit.letzterModus !== modus) {
    // Beim Grenzübertritt eine kurze Ansage (Spec 10.1). Beim allerersten
    // Fix wird nichts angesagt — da hat der Nutzer die App gerade gestartet
    // und braucht keine Meldung über einen Wechsel, der keiner war.
    const erstmalig = laufzeit.letzterModus === null;
    laufzeit.letzterModus = modus;
    laufzeit.warnungWarErlaubt = darfWarnen;
    errorLog.info(
      'position',
      `Land ${landStatus.umriss ?? 'unbestimmt'} (${landStatus.grund}), ` +
      `Warnmodus ${modus}`,
    );
    if (!erstmalig) {
      await sageAnsage(landwechselText(modus), laufzeit.settings.lautstaerke);
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

  /*
   * 4. Die Entscheidung. Bewusst als reine Funktion ausgelagert
   *    (core/entscheidung.ts): Welche Logik bei welchem Modus greift, ist
   *    genau die Stelle, an der Frankreich stumm blieb — beide Bausteine
   *    waren in Ordnung, die Verdrahtung nicht. Sie steckte hier zwischen
   *    expo-Aufrufen und war damit nicht prüfbar.
   */
  const zonen = brauchtZonen(landStatus.land) && landStatus.land !== null
    ? zonenOderNull(landStatus.land)
    : null;

  const aktion = entscheide(fix, modus, {
    grid,
    trip: laufzeit.trip,
    settings: laufzeit.settings,
    zonen,
    zonenZustand: laufzeit.zonen,
  });

  // 5. Ausführen. Ab hier nur noch Plattform, keine Entscheidung mehr.
  switch (aktion.art) {
    case 'punktwarnung':
      await gebeWarnung(aktion.camera, aktion.distanzM, {
        sprache: laufzeit.settings.sprachansage,
        lautstaerke: laufzeit.settings.lautstaerke,
        speedKmh: fix.speed != null ? fix.speed * 3.6 : null,
      });
      return;

    case 'zonenhinweis':
      // Kein speedKmh, keine Distanz — die Aktion trägt beides gar nicht.
      await gebeZonenhinweis({
        sprache: laufzeit.settings.sprachansage,
        lautstaerke: laufzeit.settings.lautstaerke,
      });
      return;

    case 'nichts':
      /*
       * Der einzige Grund, der kein Normalbetrieb ist.
       *
       * Eine App, die im Zonenmodus "Hinweise aktiviert" ansagt und danach
       * für die ganze Fahrt schweigt, ist von aussen nicht von einer Strecke
       * ohne Zonen zu unterscheiden. Genau dieser stille Ausfall ist im
       * Kopfkommentar von core/dataset.ts beschrieben — deshalb hier ein
       * ERROR und keine stille Rückkehr.
       */
      if (aktion.grund === 'zonendaten_fehlen' && landStatus.land !== null) {
        if (!laufzeit.zonenAusfallGemeldet.has(landStatus.land)) {
          laufzeit.zonenAusfallGemeldet.add(landStatus.land);
          const fehler = zonenFehler(landStatus.land);
          errorLog.error(
            'daten',
            `Zonendatensatz für ${landStatus.land} fehlt oder ist unlesbar — ` +
            'es wird hier NICHT gewarnt',
            fehler,
          );
        }
      }
      return;
  }
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
  laufzeit.letzterModus = null;
  laufzeit.warnungWarErlaubt = null;
  laufzeit.zonen = createZonenZustand();
  laufzeit.zonenAusfallGemeldet = new Set();

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
