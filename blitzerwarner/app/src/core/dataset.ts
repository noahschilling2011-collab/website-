/**
 * Der gebündelte Blitzer-Datensatz: einmal laden, prüfen, im Speicher halten.
 *
 * Warum hier so ausführlich geprüft wird, obwohl die Daten aus der eigenen
 * Pipeline stammen: Die Suche der App (geo.neighbourKeys) und das Gitter im
 * JSON müssen dieselbe Zellgrösse benutzen. Tun sie es nicht, findet die Suche
 * schlicht nichts. Die App startet dann normal, zeigt einen Tacho, meldet
 * "Warnung aktiv" — und warnt nie. Dieser Ausfall ist von aussen nicht zu
 * bemerken und würde erst auffallen, wenn jemand geblitzt wurde. Deshalb wird
 * er beim Laden erzwungen sichtbar gemacht statt im Betrieb gehofft.
 *
 * Hier gibt es keinen Netzzugriff und keinen Nachladepfad. Der Datensatz liegt
 * im App-Paket, ein neuer Stand kommt mit einem App-Update.
 *
 * Dieses Modul protokolliert nicht selbst (kein Import von log.ts): Es wirft,
 * der Aufrufer entscheidet, ob er den Fehler protokolliert und welche Meldung
 * aus strings.ts er dazu anzeigt.
 */
import { GRID } from '../config';
import type { Camera, CameraType, Dataset } from '../types';
import { cellIndex, cellKey, haversine, keyFromIndex } from './geo';

/**
 * Format des Datensatzes, geschrieben von scripts/build-dataset.ts.
 *
 * Steht bewusst hier und nicht in config.ts: Das ist kein Stellparameter,
 * sondern ein Vertrag zwischen Pipeline und App — analog zu EARTH_RADIUS_M in
 * geo.ts. Wer das Format ändert, ändert beide Seiten und diese Zahl.
 */
export const DATASET_VERSION = 1;

/** Umschliessendes Rechteck: minLat, minLon, maxLat, maxLon. */
export type CoverageBox = readonly [number, number, number, number];

/**
 * Was tatsächlich im JSON steht. `Dataset` aus types.ts beschreibt den Kern;
 * `licenseUrl` und `countries` kommen aus der Pipeline dazu.
 *
 * `countries[x].count` ist die Zahl der Rohtreffer vor dem Dedupe und taugt
 * deshalb NICHT für eine Anzeige. Für "Enthaltene Anlagen" gilt `count` auf
 * oberster Ebene.
 */
export type BundledDataset = Dataset & {
  readonly licenseUrl: string | null;
  readonly countries: Readonly<Record<string, { bbox: CoverageBox | null; count: number }>> | null;
};

/** Liegt eine Position im Gebiet, für das Daten mitgeliefert wurden? */
export type Coverage = 'innen' | 'aussen' | 'unbekannt';

export type DatasetErrorReason =
  /** Struktur passt nicht: kein Objekt, fehlende oder falsch typisierte Felder. */
  | 'nicht_lesbar'
  /** Anderes Format als DATASET_VERSION. */
  | 'version'
  /** Zellgrösse weicht von GRID.CELL_SIZE ab — die Suche würde nichts finden. */
  | 'zellgroesse'
  /** `count` passt nicht zur Summe über das Gitter. */
  | 'anzahl'
  /** Eine Anlage liegt nicht in der Zelle, unter deren Schlüssel sie steht. */
  | 'zelle_falsch'
  /** Herkunft oder Lizenz fehlt — beides ist Pflichtangabe, kein Beiwerk. */
  | 'herkunft_fehlt'
  /** Der mitgelieferte Datensatz ist leer. */
  | 'leer';

/**
 * Die Meldung ist für das Fehlerprotokoll gedacht, nicht für den Bildschirm.
 * Dem Nutzer wird strings.fehler.datensatzUnlesbar gezeigt.
 */
export class DatasetError extends Error {
  readonly reason: DatasetErrorReason;

  constructor(reason: DatasetErrorReason, detail: string) {
    super(`${reason}: ${detail}`);
    this.name = 'DatasetError';
    this.reason = reason;
    // Ohne diese Zeile schlägt `instanceof` fehl, sobald nach ES5
    // heruntergebrochen wird — Hermes tut das für ältere Ziele.
    Object.setPrototypeOf(this, DatasetError.prototype);
  }
}

// --- Prüfhelfer -----------------------------------------------------------

function istObjekt(wert: unknown): wert is Record<string, unknown> {
  return typeof wert === 'object' && wert !== null && !Array.isArray(wert);
}

function istZahl(wert: unknown): wert is number {
  return typeof wert === 'number' && Number.isFinite(wert);
}

const KAMERA_TYPEN: readonly CameraType[] = ['speed', 'red_light', 'both'];

function istKameraTyp(wert: unknown): wert is CameraType {
  return typeof wert === 'string' && (KAMERA_TYPEN as readonly string[]).includes(wert);
}

/**
 * Eine Anlage aus dem JSON lesen.
 *
 * Fehlende `dir`/`max` werden als null übernommen: "nicht erfasst" und "Feld
 * fehlt" sind dieselbe Aussage. Bei lat/lon/type gibt es diese Nachsicht
 * nicht — daraus wird gerechnet.
 */
function leseKamera(wert: unknown, zellSchluessel: string, index: number): Camera {
  const wo = `Zelle ${zellSchluessel}, Eintrag ${index}`;
  if (!istObjekt(wert)) {
    throw new DatasetError('nicht_lesbar', `${wo}: kein Objekt`);
  }

  const lat = wert['lat'];
  const lon = wert['lon'];
  if (!istZahl(lat) || lat < -90 || lat > 90) {
    throw new DatasetError('nicht_lesbar', `${wo}: lat unbrauchbar`);
  }
  if (!istZahl(lon) || lon < -180 || lon > 180) {
    throw new DatasetError('nicht_lesbar', `${wo}: lon unbrauchbar`);
  }

  const rohDir = wert['dir'];
  let dir: number | null = null;
  if (rohDir !== null && rohDir !== undefined) {
    if (!istZahl(rohDir) || rohDir < 0 || rohDir > 360) {
      throw new DatasetError('nicht_lesbar', `${wo}: dir unbrauchbar`);
    }
    dir = rohDir;
  }

  const rohMax = wert['max'];
  let max: number | null = null;
  if (rohMax !== null && rohMax !== undefined) {
    if (!istZahl(rohMax) || rohMax <= 0) {
      throw new DatasetError('nicht_lesbar', `${wo}: max unbrauchbar`);
    }
    max = rohMax;
  }

  const type = wert['type'];
  if (!istKameraTyp(type)) {
    throw new DatasetError('nicht_lesbar', `${wo}: unbekannter Typ`);
  }

  return { lat, lon, dir, max, type };
}

/** Optionaler Abdeckungsblock. Fehlt er ganz, ist das kein Fehler. */
function leseLaender(
  wert: unknown,
): Readonly<Record<string, { bbox: CoverageBox | null; count: number }>> | null {
  if (wert === null || wert === undefined) return null;
  if (!istObjekt(wert)) {
    throw new DatasetError('nicht_lesbar', 'countries ist kein Objekt');
  }

  const laender: Record<string, { bbox: CoverageBox | null; count: number }> = {};
  for (const [code, eintrag] of Object.entries(wert)) {
    if (!istObjekt(eintrag)) {
      throw new DatasetError('nicht_lesbar', `countries.${code}: kein Objekt`);
    }

    const rohBox = eintrag['bbox'];
    let bbox: CoverageBox | null = null;
    if (rohBox !== null && rohBox !== undefined) {
      // Array.isArray() engt auf any[] ein; die Zuweisung auf unknown[] hält
      // das any aus dem Rest der Datei heraus.
      if (!Array.isArray(rohBox)) {
        throw new DatasetError('nicht_lesbar', `countries.${code}: bbox ist keine Liste`);
      }
      const werte: readonly unknown[] = rohBox;
      const [minLat, minLon, maxLat, maxLon] = werte;
      if (
        werte.length !== 4 ||
        !istZahl(minLat) || !istZahl(minLon) || !istZahl(maxLat) || !istZahl(maxLon)
      ) {
        throw new DatasetError('nicht_lesbar', `countries.${code}: bbox unbrauchbar`);
      }
      bbox = [minLat, minLon, maxLat, maxLon];
    }

    const count = eintrag['count'];
    if (!istZahl(count) || count < 0) {
      throw new DatasetError('nicht_lesbar', `countries.${code}: count unbrauchbar`);
    }

    laender[code] = { bbox, count };
  }
  return laender;
}

// --- Laden ----------------------------------------------------------------

/**
 * Rohdaten prüfen und in eine Form bringen, der der Rest der App vertrauen
 * darf. Rein und ohne Zustand, damit sich jede Abweichung mit einem
 * handgeschriebenen Objekt nachstellen lässt.
 *
 * Das Gitter wird dabei neu aufgebaut statt durchgereicht: Danach steckt in
 * jeder Zelle genau das, was geprüft wurde, und nichts sonst.
 */
export function parseDataset(raw: unknown): BundledDataset {
  if (!istObjekt(raw)) {
    throw new DatasetError('nicht_lesbar', 'Wurzel ist kein Objekt');
  }

  const version = raw['version'];
  if (version !== DATASET_VERSION) {
    throw new DatasetError(
      'version',
      `erwartet ${DATASET_VERSION}, gelesen ${String(version)}`,
    );
  }

  // Der wichtigste Vergleich der Datei. Ein Datensatz mit anderer Zellgrösse
  // ist nicht "etwas anders", er ist für diese Suche unbrauchbar.
  const cell = raw['cell'];
  if (!istZahl(cell) || cell !== GRID.CELL_SIZE) {
    throw new DatasetError(
      'zellgroesse',
      `Gitter ${String(cell)} passt nicht zu GRID.CELL_SIZE ${GRID.CELL_SIZE}`,
    );
  }

  const source = raw['source'];
  const license = raw['license'];
  if (typeof source !== 'string' || source.length === 0) {
    throw new DatasetError('herkunft_fehlt', 'source fehlt');
  }
  if (typeof license !== 'string' || license.length === 0) {
    throw new DatasetError('herkunft_fehlt', 'license fehlt');
  }

  const rohLizenzUrl = raw['licenseUrl'];
  const licenseUrl = typeof rohLizenzUrl === 'string' && rohLizenzUrl.length > 0
    ? rohLizenzUrl
    : null;

  const rohStand = raw['osmTimestamp'];
  if (rohStand !== null && typeof rohStand !== 'string') {
    throw new DatasetError('nicht_lesbar', 'osmTimestamp ist weder Text noch null');
  }
  const osmTimestamp: string | null = rohStand ?? null;

  const rohGitter = raw['grid'];
  if (!istObjekt(rohGitter)) {
    throw new DatasetError('nicht_lesbar', 'grid fehlt oder ist kein Objekt');
  }

  const grid: Record<string, Camera[]> = {};
  let summe = 0;

  for (const [schluessel, rohZelle] of Object.entries(rohGitter)) {
    if (!Array.isArray(rohZelle)) {
      throw new DatasetError('nicht_lesbar', `Zelle ${schluessel} ist keine Liste`);
    }
    // Array.isArray() engt auf any[] ein; die Zuweisung auf unknown[] hält das
    // any aus dem Rest der Datei heraus.
    const rohEintraege: readonly unknown[] = rohZelle;

    const zelle: Camera[] = [];
    for (let i = 0; i < rohEintraege.length; i++) {
      const camera = leseKamera(rohEintraege[i], schluessel, i);

      // Die Probe aufs Exempel: Die App sucht über cellKey(). Landet eine
      // Anlage damit in einer anderen Zelle als der, unter der sie steht,
      // rechnen Pipeline und App verschieden — und die Anlage wäre für die
      // Suche unsichtbar, ohne dass irgendetwas auffiele.
      const berechnet = cellKey(camera.lat, camera.lon);
      if (berechnet !== schluessel) {
        throw new DatasetError(
          'zelle_falsch',
          `${camera.lat},${camera.lon} steht in ${schluessel}, gehört nach ${berechnet}`,
        );
      }

      zelle.push(camera);
    }

    summe += zelle.length;
    grid[schluessel] = zelle;
  }

  const count = raw['count'];
  if (!istZahl(count) || count !== summe) {
    throw new DatasetError('anzahl', `count ${String(count)}, gezählt ${summe}`);
  }

  return {
    version: DATASET_VERSION,
    osmTimestamp,
    source,
    license,
    licenseUrl,
    cell,
    count,
    grid,
    countries: leseLaender(raw['countries']),
  };
}

/**
 * Die Rohdaten aus dem App-Paket.
 *
 * require() statt import: Metro löst den Pfad zur Bauzeit auf und legt das
 * JSON ins Paket — zur Laufzeit wird hier weder eine Datei gesucht noch eine
 * Verbindung geöffnet. Ein `import` desselben JSON würde TypeScript ausserdem
 * zwingen, für 370 KB Literal einen Typ zu bilden; das bremst jeden Typcheck
 * aus und ersetzt keine einzige Prüfung, weil ohnehin zur Laufzeit geprüft
 * wird. Das Ergebnis wird deshalb als `unknown` angenommen.
 */
function gebuendelteRohdaten(): unknown {
  const rohdaten: unknown = require('../../assets/data/cameras.json');
  return rohdaten;
}

type Zustand =
  | { art: 'leer' }
  | { art: 'geladen'; dataset: BundledDataset }
  | { art: 'fehler'; fehler: DatasetError };

let zustand: Zustand = { art: 'leer' };

/**
 * Den gebündelten Datensatz laden. Beim App-Start einmal aufrufen; jeder
 * weitere Aufruf liefert dasselbe Objekt zurück, ohne erneut zu parsen.
 *
 * Ein einmal gescheitertes Laden wird nicht wiederholt: Das App-Paket ändert
 * sich zur Laufzeit nicht, ein zweiter Versuch käme zum selben Ergebnis und
 * würde nur Zeit kosten. Derselbe Fehler wird erneut geworfen.
 */
export function loadDataset(): BundledDataset {
  if (zustand.art === 'geladen') return zustand.dataset;
  if (zustand.art === 'fehler') throw zustand.fehler;

  try {
    const dataset = parseDataset(gebuendelteRohdaten());

    // Ein leeres Gitter kann nur ein Fehler beim Bauen des Pakets sein. Eine
    // App, die nie warnen kann, soll das sagen und nicht so tun als ob.
    if (dataset.count === 0) {
      throw new DatasetError('leer', 'Der mitgelieferte Datensatz enthält keine Anlagen');
    }

    zustand = { art: 'geladen', dataset };
    return dataset;
  } catch (fehler) {
    const gemerkt =
      fehler instanceof DatasetError
        ? fehler
        : new DatasetError(
            'nicht_lesbar',
            fehler instanceof Error ? fehler.message : String(fehler),
          );
    zustand = { art: 'fehler', fehler: gemerkt };
    throw gemerkt;
  }
}

/** Ist der Datensatz geladen? Ohne Nebenwirkung, wirft nicht. */
export function isDatasetLoaded(): boolean {
  return zustand.art === 'geladen';
}

/**
 * Der geladene Datensatz oder null. Für Anzeigen, die auch dann etwas
 * darstellen müssen, wenn das Laden gescheitert ist — der Tacho läuft weiter,
 * auch ohne eine einzige bekannte Anlage.
 */
export function datasetOrNull(): BundledDataset | null {
  return zustand.art === 'geladen' ? zustand.dataset : null;
}

// --- Abfragen -------------------------------------------------------------

/**
 * Alle Zellschlüssel, die einen Kreis um die Position berühren können.
 *
 * Nicht neighbourKeys() aus geo.ts: Das deckt fest 3x3 ab und reicht nur für
 * Warndistanzen. Die Datenqualitäts-Anzeige fragt nach Kilometern, dafür
 * müssen die Ringe mit dem Radius wachsen.
 *
 * Die Zellgrösse wird in Metern gemessen statt aus Grad umgerechnet, damit
 * hier keine zweite Erdmodell-Konstante neben der in geo.ts entsteht.
 *
 * Am Datumsgrenze und an den Polen entstehen Schlüssel, die es im Gitter
 * nicht gibt; sie laufen ins Leere. Ein Kreis über die Datumsgrenze hinweg
 * wird also einseitig gezählt — für einen Datensatz, der in Mitteleuropa
 * liegt, ist das ohne Belang.
 */
function keysInRadius(lat: number, lon: number, radiusM: number): string[] {
  const [iLat, iLon] = cellIndex(lat, lon);

  const zellHoeheM = haversine(lat, lon, lat + GRID.CELL_SIZE, lon);
  const ringeLat = zellHoeheM > 0 ? Math.ceil(radiusM / zellHoeheM) : 0;

  // Zellen werden zu den Polen hin schmaler. Für die Ringzahl zählt die
  // schmalste Zelle im Suchfeld, sonst fehlen aussen Zellen.
  const randLat = Math.min(89, Math.abs(lat) + (ringeLat + 1) * GRID.CELL_SIZE);
  const zellBreiteM = haversine(randLat, lon, randLat, lon + GRID.CELL_SIZE);
  const maxRingeLon = Math.ceil(360 / GRID.CELL_SIZE);
  const ringeLon =
    zellBreiteM > 0 ? Math.min(maxRingeLon, Math.ceil(radiusM / zellBreiteM)) : maxRingeLon;

  const keys: string[] = [];
  for (let dLat = -ringeLat; dLat <= ringeLat; dLat++) {
    for (let dLon = -ringeLon; dLon <= ringeLon; dLon++) {
      keys.push(keyFromIndex(iLat + dLat, iLon + dLon));
    }
  }
  return keys;
}

/**
 * Wie viele erfasste Anlagen liegen im Umkreis? Für die
 * Datenqualitäts-Anzeige aus Spec 10.3.
 *
 * Die Zahl sagt etwas über den Datensatz, nicht über die Strasse: 0 heisst
 * "hier ist nichts erfasst", nicht "hier steht nichts". Der begleitende Text
 * dazu steht in strings.daten.qualitaetText.
 *
 * Der Radius ist bewusst ein Pflichtparameter ohne Vorbelegung, damit es
 * keinen zweiten Ort neben config.ts gibt, an dem eine solche Zahl steht.
 *
 * null bedeutet: mit diesen Eingaben lässt sich nichts sagen. Bewusst nicht 0
 * — 0 wäre eine Aussage über die Datenlage, und die wäre dann erfunden.
 */
export function camerasWithinRadius(
  dataset: Pick<BundledDataset, 'grid'>,
  lat: number,
  lon: number,
  radiusM: number,
): number | null {
  if (!istZahl(lat) || !istZahl(lon)) return null;
  if (!istZahl(radiusM) || radiusM <= 0) return null;

  let anzahl = 0;
  for (const key of keysInRadius(lat, lon, radiusM)) {
    const zelle = dataset.grid[key];
    if (zelle === undefined) continue;
    for (const camera of zelle) {
      if (haversine(lat, lon, camera.lat, camera.lon) <= radiusM) anzahl++;
    }
  }
  return anzahl;
}

/**
 * Liegt die Position im Gebiet, für das Daten mitgeliefert wurden?
 *
 * Grundlage sind die Rechtecke aus der Pipeline. 'unbekannt' kommt, wenn der
 * Datensatz keine Angabe dazu enthält — dann wird nichts behauptet. Ein
 * Rechteck ist grob: Innerhalb heisst nicht, dass die Gegend gut erfasst ist,
 * dafür ist camerasWithinRadius() da.
 */
export function coverageAt(
  dataset: Pick<BundledDataset, 'countries'>,
  lat: number,
  lon: number,
): Coverage {
  const laender = dataset.countries;
  if (laender === null) return 'unbekannt';
  if (!istZahl(lat) || !istZahl(lon)) return 'unbekannt';

  let einRechteckBekannt = false;
  for (const eintrag of Object.values(laender)) {
    const bbox = eintrag.bbox;
    if (bbox === null) continue;
    einRechteckBekannt = true;
    const [minLat, minLon, maxLat, maxLon] = bbox;
    if (lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon) return 'innen';
  }

  return einRechteckBekannt ? 'aussen' : 'unbekannt';
}
