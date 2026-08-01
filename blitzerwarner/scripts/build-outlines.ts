#!/usr/bin/env node
/**
 * Erzeugt app/src/core/country-data.ts aus Natural Earth.
 *
 *   npx tsx scripts/build-outlines.ts
 *
 * Warum das sein muss: Die Umrisse waren von Hand aus Kartenwissen
 * eingetragen — Deutschland mit 88 Stützpunkten für rund 3700 km Grenze, also
 * im Schnitt gut 40 km je Segment. In der Oberrheinebene liegen DE und FR
 * wenige Kilometer auseinander; bei 40-km-Segmenten ist die Zuordnung dort
 * Zufall. Und über diese Zuordnung entscheidet sich, ob die App im falschen
 * Land scharf ist.
 *
 * QUELLE: Natural Earth, Admin 0 Countries, 1:10m. Public Domain, keine
 * Attributionspflicht — anders als OSM, das über ODbL Share-Alike auslösen
 * würde und damit den ganzen Datensatz binden könnte.
 *
 * ZWEI TOLERANZEN, mit Absicht: Landgrenzen werden fein vereinfacht,
 * Küstenlinien grob. Ein Fehler an der Landgrenze heisst "falsches Land",
 * also möglicherweise Warnung im verbotenen Land. Ein Fehler an der Küste
 * heisst "Land oder Meer" — und wer im Meer fährt, braucht keine
 * Blitzerwarnung. Die grobe Küste spart den Grossteil der Datenmenge;
 * Norwegen, Kroatien und Griechenland bestehen fast nur aus Küste.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CACHE_DIR = join(ROOT, '.natural-earth-cache');
const CACHE_FILE = join(CACHE_DIR, 'ne_10m_admin_0_countries.geojson');
const OUT_FILE = join(ROOT, 'app', 'src', 'core', 'country-data.ts');

const QUELLE_URL =
  'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson';

// --- Konstanten -----------------------------------------------------------

/**
 * Vereinfachungstoleranz an Landgrenzen. Der maximale Abstand zwischen
 * vereinfachter und originaler Linie bleibt darunter; das Skript misst es und
 * gibt es aus, statt es zu behaupten.
 */
const TOLERANZ_GRENZE_M = 200;

/**
 * Toleranz an Küsten.
 *
 * Ein erster Versuch stand hier bei 2000 m, mit der Begründung, ein Fehler an
 * der Küste heisse nur "Land oder Meer". Das war falsch, und der Test hat es
 * gezeigt: Bei 2000 m wanderte die dänische Küste so weit landeinwärts, dass
 * KOPENHAGEN in keinem Umriss mehr lag. Eine Küstenstadt gehört dann zu
 * keinem Land, und das Gate fällt dort dauerhaft auf "keine Warnung".
 *
 * 500 m ist der Kompromiss: noch deutlich grober als an der Grenze, wo es
 * rechtlich zählt, aber fein genug, dass Städte am Wasser im Land bleiben.
 */
const TOLERANZ_KUESTE_M = 500;

/**
 * Bis zu diesem Abstand zu einem fremden Umriss gilt ein Stützpunkt als
 * Landgrenze. Natural Earth führt Nachbarländer aus derselben Quelle, die
 * gemeinsame Linie ist deshalb nahezu deckungsgleich — aber nicht exakt.
 */
const NACHBAR_ABSTAND_M = 1500;

/**
 * Ringe unter dieser Fläche fallen weg. Kleine unbewohnte Inseln tragen zur
 * Landeserkennung nichts bei und kosten Stützpunkte. 5 km² lässt bewohnte
 * Inseln und alle Exklaven drin, die Natural Earth überhaupt führt.
 */
const MIN_RING_FLAECHE_KM2 = 5;

/**
 * Löcher unter dieser Fläche fallen weg. Kleiner als die Ringschwelle, weil
 * Enklaven klein sind: San Marino hat 61 km², Llívia 13, Campione 2,7.
 */
const MIN_LOCH_FLAECHE_KM2 = 1;

/**
 * Länder, für die ein Umriss erzeugt wird.
 *
 * Das ist bewusst MEHR als das Gate kennt: Ein Umriss für ein Nachbarland
 * verhindert, dass ein Punkt dort in den eigenen Umriss rutscht. Fehlt Polen,
 * gilt ein Punkt hinter der Oder womöglich als Deutschland. Für die
 * Gate-Entscheidung selbst zählt allein die Tabelle in config.ts.
 */
const ZIEL_LAENDER: { code: string; name: string }[] = [
  { code: 'DE', name: 'Deutschland' },
  { code: 'AT', name: 'Österreich' },
  { code: 'CH', name: 'Schweiz' },
  { code: 'FR', name: 'Frankreich' },
  { code: 'IT', name: 'Italien' },
  { code: 'ES', name: 'Spanien' },
  { code: 'PT', name: 'Portugal' },
  { code: 'NL', name: 'Niederlande' },
  { code: 'BE', name: 'Belgien' },
  { code: 'LU', name: 'Luxemburg' },
  { code: 'DK', name: 'Dänemark' },
  { code: 'PL', name: 'Polen' },
  { code: 'CZ', name: 'Tschechien' },
  { code: 'SK', name: 'Slowakei' },
  { code: 'HU', name: 'Ungarn' },
  { code: 'SI', name: 'Slowenien' },
  { code: 'HR', name: 'Kroatien' },
  { code: 'BA', name: 'Bosnien und Herzegowina' },
  { code: 'RS', name: 'Serbien' },
  { code: 'ME', name: 'Montenegro' },
  { code: 'MK', name: 'Nordmazedonien' },
  { code: 'AL', name: 'Albanien' },
  { code: 'GR', name: 'Griechenland' },
  { code: 'BG', name: 'Bulgarien' },
  { code: 'RO', name: 'Rumänien' },
  { code: 'SE', name: 'Schweden' },
  { code: 'NO', name: 'Norwegen' },
  { code: 'FI', name: 'Finnland' },
  { code: 'EE', name: 'Estland' },
  { code: 'LV', name: 'Lettland' },
  { code: 'LT', name: 'Litauen' },
  { code: 'IE', name: 'Irland' },
  { code: 'GB', name: 'Grossbritannien' },
  { code: 'LI', name: 'Liechtenstein' },
  { code: 'AD', name: 'Andorra' },
  { code: 'MC', name: 'Monaco' },
  { code: 'SM', name: 'San Marino' },
];

/**
 * Exklaven, die Natural Earth 1:10m NICHT führt.
 *
 * Nachgemessen: Ein Punkt in Büsingen am Hochrhein (DE-Exklave, von der
 * Schweiz umschlossen) und einer in Campione d'Italia (IT-Exklave, ebenfalls
 * von der Schweiz umschlossen) fallen in Natural Earth beide an die Schweiz.
 * Llívia (ES-Exklave in Frankreich) ist dagegen enthalten.
 *
 * Korrekt darstellen liesse sich das nur, wenn der Umriss der Schweiz an
 * diesen Stellen ein Loch hätte. Der Umriss-Typ in country-data.ts kennt aber
 * nur Aussenringe, die verodert werden — ein Loch ist darin nicht abbildbar,
 * und die Struktur soll unverändert bleiben.
 *
 * Deshalb werden diese Gebiete als unsichere Zone geführt: erkenneUmriss()
 * liefert dort null, das Gate fällt auf den sicheren Standard (keine Warnung).
 * Praktische Auswirkung nach heutiger Gate-Tabelle: keine. DE, IT und CH
 * stehen alle drei auf 'aus', die Zuordnung würde am Verhalten nichts ändern.
 * Der Eintrag steht hier, damit das so bleibt, wenn sich die Tabelle ändert.
 */
const FEHLENDE_EXKLAVEN = [
  {
    name: 'Büsingen am Hochrhein',
    gehoertZu: 'DE',
    lat: 47.696, lon: 8.689, radiusM: 3500,
    grund: 'DE-Exklave, in Natural Earth 1:10m der Schweiz zugeordnet',
  },
  {
    name: "Campione d'Italia",
    gehoertZu: 'IT',
    lat: 45.968, lon: 8.970, radiusM: 2500,
    grund: 'IT-Exklave, in Natural Earth 1:10m der Schweiz zugeordnet',
  },
];

// --- Geometrie ------------------------------------------------------------

type LonLat = [number, number];
/** lat, lon — die Reihenfolge, die die App überall benutzt. */
type LatLon = [number, number];

const toRad = (d: number) => (d * Math.PI) / 180;
const LAT_M_PER_DEG = 111_320;

/** Meter pro Längengrad auf dieser Breite. */
const lonMeterPerDeg = (lat: number) => LAT_M_PER_DEG * Math.cos(toRad(lat));

/** Näherungsabstand in Metern, ebene Projektion um einen Bezugsbreitengrad. */
function abstandM(a: LatLon, b: LatLon, bezugLat: number): number {
  const dx = (a[1] - b[1]) * lonMeterPerDeg(bezugLat);
  const dy = (a[0] - b[0]) * LAT_M_PER_DEG;
  return Math.hypot(dx, dy);
}

/** Senkrechter Abstand eines Punktes zur Strecke a-b, in Metern. */
function abstandZuStrecke(p: LatLon, a: LatLon, b: LatLon, bezugLat: number): number {
  const sx = lonMeterPerDeg(bezugLat);
  const px = p[1] * sx, py = p[0] * LAT_M_PER_DEG;
  const ax = a[1] * sx, ay = a[0] * LAT_M_PER_DEG;
  const bx = b[1] * sx, by = b[0] * LAT_M_PER_DEG;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  if (len2 === 0) return Math.hypot(px - ax, py - ay);
  let t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

/**
 * Douglas-Peucker, iterativ statt rekursiv.
 *
 * Rekursiv wäre kürzer, läuft bei Ringen mit einigen Tausend Punkten aber in
 * einen Stack-Überlauf — Norwegens Küste hat über 30.000.
 */
function douglasPeucker(
  punkte: LatLon[], toleranzM: number, bezugLat: number,
): { punkte: LatLon[]; behaltenIndizes: number[] } {
  if (punkte.length <= 2) {
    return { punkte: punkte.slice(), behaltenIndizes: punkte.map((_, i) => i) };
  }

  const behalten = new Uint8Array(punkte.length);
  behalten[0] = 1;
  behalten[punkte.length - 1] = 1;

  const stapel: [number, number][] = [[0, punkte.length - 1]];
  while (stapel.length > 0) {
    const [von, bis] = stapel.pop()!;
    let maxAbstand = -1;
    let maxIndex = -1;
    for (let i = von + 1; i < bis; i++) {
      const d = abstandZuStrecke(punkte[i]!, punkte[von]!, punkte[bis]!, bezugLat);
      if (d > maxAbstand) { maxAbstand = d; maxIndex = i; }
    }
    if (maxAbstand > toleranzM && maxIndex > 0) {
      behalten[maxIndex] = 1;
      stapel.push([von, maxIndex], [maxIndex, bis]);
    }
  }

  const behaltenIndizes: number[] = [];
  for (let i = 0; i < punkte.length; i++) if (behalten[i] === 1) behaltenIndizes.push(i);
  return { punkte: behaltenIndizes.map((i) => punkte[i]!), behaltenIndizes };
}

/**
 * Grösste Abweichung der vereinfachten von der originalen Linie, in Metern.
 *
 * Exakt, nicht genähert — und das ist der Punkt. Ein erster Versuch suchte für
 * jeden Originalpunkt das "nächstgelegene" Segment über einen monoton
 * vorwärtslaufenden Index. Das verfehlt bei geschlossenen Ringen regelmässig
 * das richtige Segment und meldete bis zu 25 km Abweichung, wo Douglas-Peucker
 * konstruktiv unter 200 m bleibt. Die Zahl war falsch, nicht die Vereinfachung.
 *
 * Weil die vereinfachte Linie eine TEILFOLGE der originalen ist, geht es
 * exakt und billig: Jeder weggelassene Punkt liegt zwischen zwei behaltenen,
 * und sein Abstand zur Strecke zwischen genau diesen beiden ist die
 * Abweichung. Kein Suchen nötig.
 */
function maxAbweichung(
  original: LatLon[], behaltenIndizes: number[], bezugLat: number,
): number {
  let max = 0;
  for (let k = 0; k + 1 < behaltenIndizes.length; k++) {
    const von = behaltenIndizes[k]!;
    const bis = behaltenIndizes[k + 1]!;
    const a = original[von]!, b = original[bis]!;
    for (let i = von + 1; i < bis; i++) {
      const d = abstandZuStrecke(original[i]!, a, b, bezugLat);
      if (d > max) max = d;
    }
  }
  return max;
}

/** Ringfläche in km², über die Trapezformel auf der Kugel genähert. */
function flaecheKm2(ring: LatLon[]): number {
  if (ring.length < 3) return 0;
  const bezugLat = ring[0]![0];
  const sx = lonMeterPerDeg(bezugLat);
  let summe = 0;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i]!, b = ring[(i + 1) % ring.length]!;
    summe += (a[1] * sx) * (b[0] * LAT_M_PER_DEG) - (b[1] * sx) * (a[0] * LAT_M_PER_DEG);
  }
  return Math.abs(summe / 2) / 1e6;
}

// --- Natural Earth einlesen ----------------------------------------------

type Feature = {
  properties: Record<string, unknown>;
  geometry: { type: string; coordinates: unknown };
};

function isoCode(props: Record<string, unknown>): string | null {
  for (const key of ['ISO_A2_EH', 'ISO_A2']) {
    const wert = props[key];
    if (typeof wert === 'string' && wert !== '-99' && wert.length === 2) return wert;
  }
  return null;
}

/**
 * Ringe eines Features in lat/lon.
 *
 * `nurAussen = true` liefert die Aussenringe für den Umriss selbst.
 * `false` liefert zusätzlich die Löcher — die braucht das
 * Nachbarschaftsgitter. Ohne sie wird San Marino falsch klassifiziert:
 * Natural Earth führt es als Loch im italienischen Polygon, und ohne dieses
 * Loch liegt kein italienischer Stützpunkt in der Nähe. San Marino gälte
 * damit als Küste, würde mit 2000 m statt 200 m vereinfacht und schrumpfte
 * von 18 auf 4 Stützpunkte — für ein Land von 61 km² ist das kein Umriss
 * mehr, sondern ein Dreieck. Dasselbe gilt für jede Enklave.
 */
function ringeAus(geometry: Feature['geometry'], modus: 'aussen' | 'loecher' | 'alle'): LatLon[][] {
  const polygone: LonLat[][][] =
    geometry.type === 'MultiPolygon'
      ? (geometry.coordinates as LonLat[][][])
      : [geometry.coordinates as unknown as LonLat[][]];

  const ringe: LatLon[][] = [];
  for (const poly of polygone) {
    const zuNehmen =
      modus === 'aussen' ? poly.slice(0, 1)
      : modus === 'loecher' ? poly.slice(1)
      : poly;
    for (const aussen of zuNehmen) {
    if (!aussen) continue;
    // GeoJSON ist lon/lat und wiederholt den ersten Punkt am Ende. Die App
    // erwartet lat/lon und schliesst den Ring implizit.
    const punkte: LatLon[] = aussen.map(([lon, lat]) => [lat, lon] as LatLon);
    if (punkte.length > 1) {
      const erst = punkte[0]!, letzt = punkte[punkte.length - 1]!;
      if (erst[0] === letzt[0] && erst[1] === letzt[1]) punkte.pop();
    }
    if (punkte.length >= 3) ringe.push(punkte);
    }
  }
  return ringe;
}

// --- Grenze gegen Küste unterscheiden ------------------------------------

/**
 * Gitter über alle fremden Stützpunkte, für die Nachbarschaftsprüfung.
 *
 * Ohne räumlichen Index wäre das ein Vergleich jedes Punktes gegen jeden —
 * bei über 400.000 Stützpunkten in Europa läuft das nicht durch.
 */
class PunktGitter {
  private readonly zellen = new Map<string, LatLon[]>();
  /** Zellgrösse in Grad, etwas grösser als der Suchradius. */
  private readonly schritt = 0.05;

  private key(lat: number, lon: number): string {
    return `${Math.floor(lat / this.schritt)},${Math.floor(lon / this.schritt)}`;
  }

  add(punkte: LatLon[]): void {
    for (const p of punkte) {
      const k = this.key(p[0], p[1]);
      const liste = this.zellen.get(k);
      if (liste) liste.push(p);
      else this.zellen.set(k, [p]);
    }
  }

  /** Gibt es einen Punkt innerhalb von radiusM? */
  inReichweite(lat: number, lon: number, radiusM: number): boolean {
    const iLat = Math.floor(lat / this.schritt);
    const iLon = Math.floor(lon / this.schritt);
    for (let dLat = -1; dLat <= 1; dLat++) {
      for (let dLon = -1; dLon <= 1; dLon++) {
        const liste = this.zellen.get(`${iLat + dLat},${iLon + dLon}`);
        if (!liste) continue;
        for (const p of liste) {
          if (abstandM([lat, lon], p, lat) <= radiusM) return true;
        }
      }
    }
    return false;
  }
}

type Abschnitt = { art: 'grenze' | 'kueste'; punkte: LatLon[] };

/**
 * Einen Ring in Abschnitte zerlegen und je nach Art unterschiedlich stark
 * vereinfachen.
 *
 * Die Klassifikation läuft auf den ORIGINALPUNKTEN, nicht auf den
 * vereinfachten — sonst würde die Vereinfachung die Information zerstören,
 * anhand der sie entscheiden soll, wie stark sie vereinfachen darf.
 */
function zerlegeUndVereinfache(
  ring: LatLon[],
  fremde: PunktGitter,
): { punkte: LatLon[]; grenzlinien: LatLon[][]; abweichungM: number } {
  const bezugLat = ring[0]![0];

  const arten: ('grenze' | 'kueste')[] = ring.map((p) =>
    fremde.inReichweite(p[0], p[1], NACHBAR_ABSTAND_M) ? 'grenze' : 'kueste',
  );

  // Zusammenhängende Läufe gleicher Art bilden.
  const abschnitte: Abschnitt[] = [];
  let start = 0;
  for (let i = 1; i <= ring.length; i++) {
    if (i === ring.length || arten[i] !== arten[start]) {
      abschnitte.push({ art: arten[start]!, punkte: ring.slice(start, i) });
      start = i;
    }
  }

  const ergebnis: LatLon[] = [];
  const grenzlinien: LatLon[][] = [];
  let maxAbw = 0;

  for (const a of abschnitte) {
    const toleranz = a.art === 'grenze' ? TOLERANZ_GRENZE_M : TOLERANZ_KUESTE_M;
    // Bezugsbreite je Abschnitt, nicht je Ring: Norwegen reicht von 58 bis
    // 71 Grad, und ein Längengrad ist dort zwischen 59 und 36 km breit. Eine
    // Bezugsbreite für den ganzen Ring würde die Toleranz am anderen Ende
    // um fast die Hälfte verfehlen.
    const abschnittLat = a.punkte[Math.floor(a.punkte.length / 2)]![0];
    const { punkte: vereinfacht, behaltenIndizes } =
      douglasPeucker(a.punkte, toleranz, abschnittLat);
    const abw = maxAbweichung(a.punkte, behaltenIndizes, abschnittLat);
    if (abw > maxAbw) maxAbw = abw;

    // Der erste Punkt eines Abschnitts ist der letzte des vorherigen.
    ergebnis.push(...(ergebnis.length > 0 ? vereinfacht.slice(1) : vereinfacht));

    if (a.art === 'grenze' && vereinfacht.length >= 2) grenzlinien.push(vereinfacht);
  }

  return { punkte: ergebnis, grenzlinien, abweichungM: maxAbw };
}

// --- Hauptlauf ------------------------------------------------------------

async function ladeNaturalEarth(): Promise<Feature[]> {
  mkdirSync(CACHE_DIR, { recursive: true });
  if (!existsSync(CACHE_FILE)) {
    console.log(`Lade Natural Earth (einmalig, rund 13 MB)\n  ${QUELLE_URL}`);
    const res = await fetch(QUELLE_URL);
    if (!res.ok) throw new Error(`Download fehlgeschlagen: HTTP ${res.status}`);
    writeFileSync(CACHE_FILE, Buffer.from(await res.arrayBuffer()));
  } else {
    console.log(`Natural Earth aus dem Cache: ${CACHE_FILE}`);
  }
  const daten = JSON.parse(readFileSync(CACHE_FILE, 'utf8')) as { features: Feature[] };
  return daten.features;
}

function zahl(n: number): string {
  // Fünf Nachkommastellen entsprechen rund 1,1 m — feiner als die Toleranz.
  return n.toFixed(5).replace(/\.?0+$/, '');
}

async function main(): Promise<void> {
  const features = await ladeNaturalEarth();

  // Nach ISO-Code sammeln. Ein Land kann mehrere Features haben.
  const nachCode = new Map<string, LatLon[][]>();
  // Getrennt gehalten: fürs Nachbarschaftsgitter zählen auch die Löcher.
  const nachCodeMitLoechern = new Map<string, LatLon[][]>();
  const nachCodeNurLoecher = new Map<string, LatLon[][]>();
  for (const feat of features) {
    const code = isoCode(feat.properties);
    if (!code) continue;
    for (const [karte, modus] of [
      [nachCode, 'aussen'], [nachCodeMitLoechern, 'alle'], [nachCodeNurLoecher, 'loecher'],
    ] as const) {
      const ringe = ringeAus(feat.geometry, modus);
      const vorhanden = karte.get(code);
      if (vorhanden) vorhanden.push(...ringe);
      else karte.set(code, ringe);
    }
  }

  const fehlend = ZIEL_LAENDER.filter((l) => !nachCode.has(l.code));
  if (fehlend.length > 0) {
    throw new Error(`Kein Umriss in Natural Earth für: ${fehlend.map((l) => l.code).join(', ')}`);
  }

  console.log(`\n${ZIEL_LAENDER.length} Zielländer, Klassifikation Grenze/Küste läuft\n`);

  type Ergebnis = {
    code: string; name: string;
    ringe: LatLon[][]; loecher: LatLon[][]; grenzlinien: LatLon[][];
    punkteVorher: number; punkteNachher: number; abweichungM: number;
    verworfeneRinge: number;
  };
  const ergebnisse: Ergebnis[] = [];

  for (const land of ZIEL_LAENDER) {
    const alleRinge = nachCode.get(land.code)!;

    // Fremdpunkte: alle anderen Länder aus Natural Earth, nicht nur die
    // Zielländer. Sonst würde die Grenze zu einem Nachbarn, der nicht in der
    // Liste steht, fälschlich als Küste gelten und zu grob vereinfacht.
    const fremde = new PunktGitter();
    for (const [code, ringe] of nachCodeMitLoechern) {
      if (code === land.code) continue;
      for (const r of ringe) fremde.add(r);
    }

    // Löcher des eigenen Landes: Enklaven fremder Staaten. Ohne sie umschliesst
    // Italiens Aussenring San Marino und Frankreichs Aussenring Llívia, beide
    // Punkte liegen dann in zwei Umrissen und erkenneUmriss() liefert null.
    // Für Llívia ist das nicht bloss unschön: Spanien darf punktgenau warnen,
    // Frankreich nur in Zonen.
    const eigeneLoecher = (nachCodeNurLoecher.get(land.code) ?? [])
      .filter((r) => flaecheKm2(r) >= MIN_LOCH_FLAECHE_KM2);

    const grosseRinge = alleRinge.filter((r) => flaecheKm2(r) >= MIN_RING_FLAECHE_KM2);
    const verworfen = alleRinge.length - grosseRinge.length;

    const ringe: LatLon[][] = [];
    const grenzlinien: LatLon[][] = [];
    let vorher = 0, nachher = 0, maxAbw = 0;

    for (const ring of grosseRinge) {
      vorher += ring.length;
      const { punkte, grenzlinien: gl, abweichungM } = zerlegeUndVereinfache(ring, fremde);
      if (punkte.length < 3) continue;
      nachher += punkte.length;
      ringe.push(punkte);
      grenzlinien.push(...gl);
      if (abweichungM > maxAbw) maxAbw = abweichungM;
    }

    // Löcher werden mit Grenztoleranz vereinfacht: Eine Enklave besteht
    // ausschliesslich aus Landgrenze.
    const loecher: LatLon[][] = [];
    for (const loch of eigeneLoecher) {
      const bezug = loch[Math.floor(loch.length / 2)]![0];
      const { punkte } = douglasPeucker(loch, TOLERANZ_GRENZE_M, bezug);
      if (punkte.length >= 3) loecher.push(punkte);
    }

    ergebnisse.push({
      code: land.code, name: land.name, ringe, loecher, grenzlinien,
      punkteVorher: vorher, punkteNachher: nachher,
      abweichungM: maxAbw, verworfeneRinge: verworfen,
    });

    console.log(
      `  ${land.code}  ${land.name.padEnd(26)} ` +
      `${String(vorher).padStart(7)} -> ${String(nachher).padStart(6)} Punkte, ` +
      `${String(ringe.length).padStart(3)} Ringe, ` +
      `Abweichung max ${maxAbw.toFixed(0).padStart(4)} m` +
      (verworfen > 0 ? `, ${verworfen} Kleinringe verworfen` : ''),
    );
  }

  // Toleranz-Zusage prüfen, nicht behaupten.
  const verletzung = ergebnisse.filter((e) => e.abweichungM > TOLERANZ_KUESTE_M * 1.05);
  if (verletzung.length > 0) {
    throw new Error(
      'Vereinfachung überschreitet die Toleranz bei: ' +
      verletzung.map((e) => `${e.code} (${e.abweichungM.toFixed(0)} m)`).join(', '),
    );
  }

  schreibeDatei(ergebnisse);

  const punkteGesamt = ergebnisse.reduce((n, e) => n + e.punkteNachher, 0);
  const bytes = readFileSync(OUT_FILE).length;
  console.log(
    `\n${'─'.repeat(72)}\n` +
    `Stützpunkte gesamt: ${punkteGesamt}\n` +
    `Grenzlinien:        ${ergebnisse.reduce((n, e) => n + e.grenzlinien.length, 0)}\n` +
    `Dateigrösse:        ${(bytes / 1024).toFixed(0)} KB -> ${OUT_FILE}\n` +
    `Toleranz:           ${TOLERANZ_GRENZE_M} m an Grenzen, ${TOLERANZ_KUESTE_M} m an Küsten\n` +
    `grösste Abweichung: ${Math.max(...ergebnisse.map((e) => e.abweichungM)).toFixed(0)} m\n` +
    `${'─'.repeat(72)}`,
  );
}

function schreibeDatei(ergebnisse: {
  code: string; name: string; ringe: LatLon[][]; loecher: LatLon[][];
  grenzlinien: LatLon[][]; punkteNachher: number; abweichungM: number;
}[]): void {
  const ringText = (r: LatLon[]) =>
    `[${r.map((p) => `[${zahl(p[0])},${zahl(p[1])}]`).join(',')}]`;

  // Als Literal, nicht als bboxAus(...)-Aufruf: Der Aufruf müsste alle Ringe
  // ein zweites Mal in die Datei schreiben, was sie verdoppelt, und würde die
  // Boxen bei jedem App-Start neu rechnen.
  const bboxText = (ringe: LatLon[][]) => {
    let latMin = Infinity, latMax = -Infinity, lonMin = Infinity, lonMax = -Infinity;
    for (const r of ringe) for (const [lat, lon] of r) {
      if (lat < latMin) latMin = lat;
      if (lat > latMax) latMax = lat;
      if (lon < lonMin) lonMin = lon;
      if (lon > lonMax) lonMax = lon;
    }
    return `{ latMin: ${zahl(latMin)}, latMax: ${zahl(latMax)}, ` +
           `lonMin: ${zahl(lonMin)}, lonMax: ${zahl(lonMax)} }`;
  };

  const laender = ergebnisse.map((e) => `  {
    code: '${e.code}',
    name: ${JSON.stringify(e.name)},
    ringe: [
${e.ringe.map((r) => `      ${ringText(r)},`).join('\n')}
    ],
    loecher: [
${e.loecher.map((r) => `      ${ringText(r)},`).join('\n')}
    ],
    grenzlinien: [
${e.grenzlinien.map((r) => `      ${ringText(r)},`).join('\n')}
    ],
    bbox: ${bboxText(e.ringe)},
  },`).join('\n');

  const codes = ergebnisse.map((e) => `  '${e.code}',`).join('\n');

  const exklaven = FEHLENDE_EXKLAVEN.map((x) => `  {
    name: ${JSON.stringify(`${x.name} (${x.gehoertZu})`)},
    lat: ${x.lat}, lon: ${x.lon}, radiusM: ${x.radiusM},
    grund: ${JSON.stringify(x.grund)},
  },`).join('\n');

  const inhalt = `/**
 * Umrisse der Länder für das Länder-Gate.
 *
 * ERZEUGT von scripts/build-outlines.ts — NICHT VON HAND ÄNDERN.
 * Änderungen gehören in den Generator, sonst sind sie beim nächsten Lauf weg.
 *
 * WARUM DIESE DATEI EXISTIERT
 *
 * Die Spec schlägt für das Gate "Reverse-Geocoding offline über die
 * Bounding-Boxes" vor. Das ist an dieser Stelle nicht bloss ungenau, sondern
 * unbrauchbar: Die Boxen von DE, AT und CH überlappen grossflächig, der
 * Bodenseeraum liegt in allen drei gleichzeitig, und Frankreich und
 * Deutschland teilen sich in der Oberrheinebene über 200 km
 * Box-Überlappung — genau dort verläuft die Grenze zwischen "Warnung
 * erlaubt" und "Warnung verboten".
 *
 * Das Gate SCHALTET DIE WARNUNG AB. Eine Fehlklassifikation in dieser
 * Richtung schaltet die App im falschen Land scharf. Deshalb
 * Punkt-in-Polygon.
 *
 * ZWEI TOLERANZEN
 *
 * Landgrenzen sind auf ${TOLERANZ_GRENZE_M} m vereinfacht, Küstenlinien auf
 * ${TOLERANZ_KUESTE_M} m. Ein Fehler an der Landgrenze heisst "falsches Land",
 * ein Fehler an der Küste heisst "Land oder Meer" — und wer im Meer fährt,
 * braucht keine Blitzerwarnung. Die grobe Küste spart den Grossteil der
 * Datenmenge.
 *
 * Diese Datei hat absichtlich keine Importe. Sie ist Daten plus die
 * Geometrie, die diese Daten beschreibt — nichts sonst.
 */

/** Der Zustand der Umrissdaten. Wird von der UI und vom Test gelesen. */
export const DATENQUALITAET: string = 'generiert, Natural Earth 1:10m';

/** Woher die Stützpunkte stammen. Public Domain, keine Attributionspflicht. */
export const UMRISS_QUELLE = 'Natural Earth, Admin 0 Countries, 1:10m (Public Domain)';

/** Vereinfachungstoleranz an Landgrenzen, in Metern. */
export const TOLERANZ_GRENZE_M = ${TOLERANZ_GRENZE_M};

/** Vereinfachungstoleranz an Küsten, in Metern. */
export const TOLERANZ_KUESTE_M = ${TOLERANZ_KUESTE_M};

/**
 * Ein Stützpunkt, als [Breite, Länge] in Grad.
 *
 * Die Reihenfolge ist lat/lon und damit dieselbe wie überall sonst in der App
 * (Camera, Fix, geo.ts). GeoJSON dreht sie um; der Generator tauscht beim
 * Schreiben.
 */
export type Punkt = readonly [lat: number, lon: number];

/**
 * Ein geschlossener Ring. Der letzte Punkt wird implizit mit dem ersten
 * verbunden, er wird NICHT wiederholt.
 */
export type Ring = readonly Punkt[];

/** Umschliessendes Rechteck, nur als Vorfilter. */
export type BBox = {
  readonly latMin: number;
  readonly latMax: number;
  readonly lonMin: number;
  readonly lonMax: number;
};

/**
 * Landcodes, für die ein Umriss vorliegt.
 *
 * Das ist bewusst mehr als config.LAENDER_GATE kennt: Ein Umriss für ein
 * Nachbarland verhindert, dass ein Punkt dort in den eigenen Umriss rutscht.
 * Für die Gate-Entscheidung selbst zählt allein die Liste in config.
 */
export const UMRISS_CODES = [
${codes}
] as const;

export type UmrissCode = (typeof UMRISS_CODES)[number];

/**
 * Ein Abschnitt einer Umrisslinie.
 *
 * \`grenze\` = Landgrenze zu einem Nachbarland, \`kueste\` = Küste oder sonstige
 * Aussenkante. Der Unterschied ist nicht kosmetisch: Die Hysterese in
 * country.ts verlangt einen Mindestabstand zur Landesgrenze, bevor sie ein
 * Land übernimmt. Zählte die Küste als Grenze, käme in Marseille, Valencia
 * oder Den Haag nie ein Land zustande und die Warnung bliebe dort dauerhaft
 * aus.
 */
export type Abschnittsart = 'grenze' | 'kueste';

export type Abschnitt = {
  readonly art: Abschnittsart;
  readonly punkte: Ring;
};

export type Umriss = {
  readonly code: UmrissCode;
  readonly name: string;
  /** Aussenringe. Mehrere, wenn ein Land aus getrennten Landmassen besteht. */
  readonly ringe: readonly Ring[];
  /**
   * Löcher: Enklaven fremder Staaten im eigenen Gebiet.
   *
   * Nachträglich ergänzt, und zwar nicht aus Ordnungsliebe. Ohne dieses Feld
   * umschliesst Italiens Aussenring San Marino und Frankreichs Aussenring
   * Llívia. Ein Punkt dort liegt in zwei Umrissen, erkenneUmriss() erkennt die
   * Mehrdeutigkeit und liefert null — sicher, aber falsch: Spanien darf
   * punktgenau warnen, Frankreich nur in Zonen.
   */
  readonly loecher: readonly Ring[];
  /** Nur die Landgrenzen, als offene Linienzüge. Für den Grenzabstand. */
  readonly grenzlinien: readonly Ring[];
  readonly bbox: BBox;
};

// --- Geometrie ------------------------------------------------------------

/** Umschliessendes Rechteck über beliebig viele Ringe. */
export function bboxAus(ringe: readonly Ring[]): BBox {
  let latMin = Infinity, latMax = -Infinity, lonMin = Infinity, lonMax = -Infinity;
  for (const ring of ringe) {
    for (const [lat, lon] of ring) {
      if (lat < latMin) latMin = lat;
      if (lat > latMax) latMax = lat;
      if (lon < lonMin) lonMin = lon;
      if (lon > lonMax) lonMax = lon;
    }
  }
  return { latMin, latMax, lonMin, lonMax };
}

export function bboxEnthaelt(bbox: BBox, lat: number, lon: number): boolean {
  return lat >= bbox.latMin && lat <= bbox.latMax && lon >= bbox.lonMin && lon <= bbox.lonMax;
}

/**
 * Punkt-in-Ring über Ray-Casting.
 *
 * Der Strahl läuft nach Westen. Die Bedingung \`(lat1 > lat) !== (lat2 > lat)\`
 * zählt eine Kante genau dann, wenn sie die Höhe des Punktes kreuzt — dass
 * die Vergleiche unterschiedlich streng sind (\`>\` gegen \`>\`), ist Absicht
 * und verhindert Doppelzählung an einem Stützpunkt, der genau auf der Höhe
 * liegt.
 */
export function punktInRing(lat: number, lon: number, ring: Ring): boolean {
  let innen = false;
  const n = ring.length;
  for (let i = 0; i < n; i++) {
    const a = ring[i]!;
    const b = ring[(i + 1) % n]!;
    const lat1 = a[0], lon1 = a[1];
    const lat2 = b[0], lon2 = b[1];
    if ((lat1 > lat) !== (lat2 > lat)) {
      const schnittLon = ((lon2 - lon1) * (lat - lat1)) / (lat2 - lat1) + lon1;
      if (lon < schnittLon) innen = !innen;
    }
  }
  return innen;
}

export function punktImUmriss(lat: number, lon: number, umriss: Umriss): boolean {
  if (!bboxEnthaelt(umriss.bbox, lat, lon)) return false;
  // Löcher zuerst: Ein Punkt in einer Enklave liegt zwar innerhalb des
  // Aussenrings, gehört aber nicht zum Land.
  for (const loch of umriss.loecher) {
    if (punktInRing(lat, lon, loch)) return false;
  }
  for (const ring of umriss.ringe) {
    if (punktInRing(lat, lon, ring)) return true;
  }
  return false;
}

// --- Daten ---------------------------------------------------------------

export const UMRISSE: readonly Umriss[] = [
${laender}
];

/**
 * Ein Gebiet, in dem die Landeserkennung bewusst kein Ergebnis liefert.
 *
 * \`erkenneUmriss()\` gibt hier null zurück, das Gate fällt damit auf den
 * sicheren Standard (keine Warnung). Das ist der richtige Ausgang für jeden
 * Ort, an dem die Datengrundlage die Zuordnung nicht hergibt.
 */
export type UnsichereZone = {
  readonly name: string;
  readonly lat: number;
  readonly lon: number;
  readonly radiusM: number;
  readonly grund: string;
};

/**
 * Exklaven, die Natural Earth 1:10m nicht führt.
 *
 * Nachgemessen: Büsingen am Hochrhein und Campione d'Italia fallen in
 * Natural Earth beide an die Schweiz. Korrekt darstellbar wäre das nur mit
 * einem Loch im Schweizer Umriss; der Umriss-Typ kennt aber nur Aussenringe,
 * die verodert werden.
 *
 * Praktische Auswirkung nach heutiger Gate-Tabelle: keine. DE, IT und CH
 * stehen alle drei auf 'aus'. Der Eintrag steht hier, damit das so bleibt,
 * wenn sich die Tabelle ändert.
 */
export const UNSICHERE_ZONEN: readonly UnsichereZone[] = [
${exklaven}
];

export function inUnsichererZone(lat: number, lon: number): UnsichereZone | null {
  const LAT_M = 111320;
  for (const zone of UNSICHERE_ZONEN) {
    const dy = (lat - zone.lat) * LAT_M;
    const dx = (lon - zone.lon) * LAT_M * Math.cos((lat * Math.PI) / 180);
    if (Math.hypot(dx, dy) <= zone.radiusM) return zone;
  }
  return null;
}

export function umrissFuer(code: UmrissCode): Umriss | null {
  return UMRISSE.find((u) => u.code === code) ?? null;
}
`;

  mkdirSync(dirname(OUT_FILE), { recursive: true });
  writeFileSync(OUT_FILE, inhalt);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
