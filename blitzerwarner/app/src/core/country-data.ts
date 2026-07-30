/**
 * Umrisse der Länder, die das Länder-Gate (Spec 2 und 10.1) unterscheiden muss.
 *
 * WARUM DIESE DATEI EXISTIERT
 *
 * Die Spec schlägt für das Gate "Reverse-Geocoding offline über die
 * Bounding-Boxes" vor. Das ist an dieser Stelle nicht bloss ungenau, sondern
 * unbrauchbar:
 *
 *   - Die Boxen von DE, AT und CH überlappen grossflächig. Die Box von
 *     Österreich (rund 46,4–49,0 N / 9,5–17,2 O) enthält halb Bayern, halb
 *     Ostschweiz, ganz Liechtenstein und Teile Sloweniens.
 *   - Der Bodenseeraum liegt in allen drei Boxen gleichzeitig.
 *   - Frankreich und Deutschland teilen sich in der Oberrheinebene über
 *     200 km Box-Überlappung — und genau dort verläuft die Grenze zwischen
 *     "Warnung erlaubt" und "Warnung verboten".
 *
 * Das Gate SCHALTET DIE WARNUNG AB. Eine Fehlklassifikation in dieser
 * Richtung — Deutschland wird als Frankreich gelesen — schaltet die App im
 * falschen Land scharf. Das ist der rechtlich heikle Fall, und er darf nicht
 * an einer Rechteck-Prüfung hängen. Deshalb Punkt-in-Polygon.
 *
 * DATENQUALITÄT — BITTE VOR EINER VERÖFFENTLICHUNG LESEN
 *
 * Die Stützpunkte unten sind von Hand aus Kartenwissen eingetragen. Sie sind
 * grob: der Fehler gegenüber dem tatsächlichen Grenzverlauf liegt
 * stellenweise im Bereich mehrerer Kilometer, Exklaven und Enklaven fehlen
 * ganz, Inseln sind nur teilweise erfasst. Diese Daten sind gut genug, um zu
 * zeigen, dass das Verfahren trägt, und sie sind es NICHT, um damit zu
 * veröffentlichen.
 *
 * Ersetzt werden müssen sie durch generierte Umrisse — Natural Earth
 * admin-0 countries (1:10m), mit einer Toleranz von etwa 200 m vereinfacht,
 * von einem Skript in genau diese Struktur geschrieben. Die Struktur ist
 * bewusst so gewählt, dass ein Generator sie ohne Änderung an country.ts
 * befüllen kann. Solange DATENQUALITAET nicht auf einen generierten Stand
 * umgestellt ist, gilt der Umriss als Behelf.
 *
 * Diese Datei hat absichtlich keine Importe. Sie ist Daten plus die
 * Geometrie, die diese Daten beschreibt — nichts sonst. Damit lässt sie sich
 * komplett gegen eine generierte Fassung tauschen.
 */

/**
 * Der Zustand der Umrissdaten. Wird von der UI und vom Test gelesen; ein
 * Wechsel auf generierte Daten ändert diesen Wert.
 */
export const DATENQUALITAET = 'grob, nicht veröffentlichungsreif';

/** Woher die Stützpunkte stammen. Keine amtliche Quelle, keine Lizenzpflicht. */
export const UMRISS_QUELLE = 'Handeingabe aus Kartenwissen';

/**
 * Ein Stützpunkt, als [Breite, Länge] in Grad.
 *
 * Die Reihenfolge ist lat/lon und damit dieselbe wie überall sonst in der App
 * (Camera, Fix, geo.ts). GeoJSON dreht sie um; ein Generator muss also beim
 * Schreiben tauschen. Die benannten Tupelelemente machen jede Verwechslung
 * im Editor sichtbar.
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
 * Das ist bewusst mehr als config.LAENDER_GATE kennt: Ein Umriss für
 * Belgien, Tschechien oder Italien verhindert, dass ein Punkt dort in den
 * Nachbarumriss rutscht und dadurch fälschlich als Frankreich oder
 * Deutschland gilt. Für die Gate-Entscheidung selbst zählt allein die Liste
 * in config.
 */
export const UMRISS_CODES = [
  'DE',
  'AT',
  'CH',
  'FR',
  'ES',
  'NL',
  'LU',
  'BE',
  'DK',
  'PL',
  'CZ',
  'IT',
] as const;

export type UmrissCode = (typeof UMRISS_CODES)[number];

/**
 * Ein Abschnitt einer Umrisslinie.
 *
 * `grenze` = Landgrenze zu einem Nachbarland, `kueste` = Küste oder sonstige
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
  /** Nur die Landgrenzen, als offene Linienzüge. Für den Grenzabstand. */
  readonly grenzlinien: readonly Ring[];
  readonly bbox: BBox;
};

// --- Geometrie ------------------------------------------------------------

/** Umschliessendes Rechteck über beliebig viele Ringe. */
export function bboxAus(ringe: readonly Ring[]): BBox {
  let latMin = Number.POSITIVE_INFINITY;
  let latMax = Number.NEGATIVE_INFINITY;
  let lonMin = Number.POSITIVE_INFINITY;
  let lonMax = Number.NEGATIVE_INFINITY;

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

/** Liegt der Punkt im Rechteck? Nur Vorfilter, nie allein entscheidend. */
export function bboxEnthaelt(bbox: BBox, lat: number, lon: number): boolean {
  return lat >= bbox.latMin && lat <= bbox.latMax && lon >= bbox.lonMin && lon <= bbox.lonMax;
}

/**
 * Punkt-in-Polygon per Ray-Casting: ein Strahl nach Osten, gezählt wird, wie
 * oft er die Ringkanten schneidet. Ungerade Anzahl heisst innen.
 *
 * Gerechnet wird in Grad, also in einer ebenen Näherung. Für einen
 * Zugehörigkeitstest ist das zulässig — die Verzerrung durch die
 * Kugelgestalt verschiebt keinen Punkt über eine Kante, solange die Kanten
 * kurz gegenüber dem Erdumfang sind. Der Antimeridian und die Pole kommen im
 * abgedeckten Gebiet nicht vor.
 *
 * Die Bedingung (latI > lat) !== (latJ > lat) ist der Grund, warum ein Punkt
 * exakt auf der Höhe eines Stützpunktes nicht doppelt gezählt wird: Der
 * Vergleich ist auf einer Seite strikt, auf der anderen nicht.
 */
export function punktInRing(lat: number, lon: number, ring: Ring): boolean {
  let vorher = ring[ring.length - 1];
  if (vorher === undefined) return false;

  let innen = false;
  for (const jetzt of ring) {
    const [latJ, lonJ] = jetzt;
    const [latV, lonV] = vorher;

    if (latJ > lat !== latV > lat) {
      const schnittLon = lonJ + ((lat - latJ) / (latV - latJ)) * (lonV - lonJ);
      if (lon < schnittLon) innen = !innen;
    }
    vorher = jetzt;
  }
  return innen;
}

/** Liegt der Punkt im Umriss? Bounding-Box als Vorfilter, dann Polygon. */
export function punktImUmriss(lat: number, lon: number, umriss: Umriss): boolean {
  if (!bboxEnthaelt(umriss.bbox, lat, lon)) return false;
  for (const ring of umriss.ringe) {
    if (punktInRing(lat, lon, ring)) return true;
  }
  return false;
}

// --- Bausteine ------------------------------------------------------------

const grenze = (punkte: Ring): Abschnitt => ({ art: 'grenze', punkte });
const kueste = (punkte: Ring): Abschnitt => ({ art: 'kueste', punkte });

/** Einen Linienzug umdrehen, ohne das Original anzufassen. */
function rueckwaerts(a: Abschnitt): Abschnitt {
  return { art: a.art, punkte: [...a.punkte].reverse() };
}

function gleich(a: Punkt, b: Punkt): boolean {
  return a[0] === b[0] && a[1] === b[1];
}

/**
 * Abschnitte zu einem Ring verketten und dabei die doppelten Nahtpunkte
 * entfernen.
 *
 * Der Dreh der ganzen Datei steckt hier: Zwei Nachbarländer teilen sich
 * nicht ähnliche, sondern buchstäblich dieselben Stützpunkte. Nur so
 * entstehen an der Grenze weder Lücken (beide Länder verneinen, Warnung
 * fällt in den sicheren Default) noch Überlappungen (beide bejahen, das
 * Ergebnis hinge von der Reihenfolge ab). Beides wäre genau an der Stelle
 * falsch, an der es zählt.
 */
function ringAus(abschnitte: readonly Abschnitt[]): Ring {
  const punkte: Punkt[] = [];
  for (const abschnitt of abschnitte) {
    for (const p of abschnitt.punkte) {
      const letzter = punkte[punkte.length - 1];
      if (letzter !== undefined && gleich(letzter, p)) continue;
      punkte.push(p);
    }
  }
  // Der Ring schliesst implizit; ein wiederholter Anfangspunkt am Ende wäre
  // eine Kante der Länge null.
  const erster = punkte[0];
  const letzter = punkte[punkte.length - 1];
  if (erster !== undefined && letzter !== undefined && punkte.length > 1 && gleich(erster, letzter)) {
    punkte.pop();
  }
  return punkte;
}

function umrissAus(code: UmrissCode, name: string, ringe: readonly (readonly Abschnitt[])[]): Umriss {
  const fertigeRinge = ringe.map(ringAus);
  const grenzlinien: Ring[] = [];
  for (const abschnitte of ringe) {
    for (const abschnitt of abschnitte) {
      if (abschnitt.art === 'grenze') grenzlinien.push(abschnitt.punkte);
    }
  }
  return { code, name, ringe: fertigeRinge, grenzlinien, bbox: bboxAus(fertigeRinge) };
}

// --- Gemeinsame Grenzabschnitte -------------------------------------------
// Jeder Abschnitt ist genau einmal beschrieben und trägt seine Richtung im
// Kommentar. Wer ihn in der Gegenrichtung braucht, dreht ihn mit
// rueckwaerts() — nicht durch eine zweite Zahlenliste.

/** DE/DK: Nordsee bei Sylt nach Osten bis zur Flensburger Förde. */
const G_DE_DK = grenze([
  [54.91, 8.6],
  [54.9, 8.75],
  [54.83, 9.02],
  [54.87, 9.28],
  [54.83, 9.44],
  [54.79, 9.62],
]);

/** DE/PL: Ostsee bei Usedom nach Süden bis zum Dreiländereck mit CZ. */
const G_DE_PL = grenze([
  [53.93, 14.22],
  [53.66, 14.28],
  [53.25, 14.4],
  [52.83, 14.14],
  [52.58, 14.64],
  [52.34, 14.56],
  [51.95, 14.73],
  [51.55, 14.75],
  [51.15, 14.99],
  [50.87, 14.82],
]);

/** CZ/DE: Dreiländereck mit PL bei Zittau bis zum Dreiländereck mit AT bei Passau. */
const G_CZ_DE = grenze([
  [50.87, 14.82],
  [50.93, 14.3],
  [50.79, 14.0],
  [50.63, 13.5],
  [50.42, 12.62],
  [50.32, 12.1],
  [50.1, 12.2],
  [49.75, 12.4],
  [49.3, 12.9],
  [48.98, 13.4],
  [48.77, 13.83],
]);

/** AT/DE: Dreiländereck mit CZ bei Passau bis zum Bodensee bei Lindau. */
const G_AT_DE = grenze([
  [48.77, 13.83],
  [48.57, 13.45],
  [48.3, 13.05],
  [47.95, 12.9],
  [47.72, 13.02],
  [47.58, 12.5],
  [47.55, 12.2],
  [47.64, 11.6],
  [47.45, 11.3],
  [47.42, 10.98],
  [47.55, 10.55],
  [47.45, 10.3],
  [47.53, 10.1],
  [47.55, 9.73],
]);

/**
 * CH/DE: Bodensee bei Lindau nach Westen bis Basel.
 *
 * Zwei Eigenheiten, die eine gerade Linie falsch machen würden: Konstanz
 * liegt südlich des Rheins und ist trotzdem deutsch, und Schaffhausen liegt
 * nördlich des Rheins und ist trotzdem schweizerisch — die Linie muss dort
 * nach Norden ausholen. Im Bodensee selbst gibt es keine völkerrechtlich
 * festgelegte Grenze; der Verlauf hier ist eine Setzung.
 */
const G_CH_DE = grenze([
  [47.55, 9.73],
  [47.62, 9.35],
  [47.66, 9.18],
  [47.6, 8.95],
  [47.71, 8.72],
  [47.8, 8.57],
  [47.65, 8.4],
  [47.6, 8.22],
  [47.55, 7.95],
  [47.59, 7.59],
]);

/** DE/FR: Basel den Rhein hinauf, dann nach Westen bis Schengen. */
const G_DE_FR = grenze([
  [47.59, 7.59],
  [47.85, 7.56],
  [48.2, 7.6],
  [48.58, 7.79],
  [48.8, 8.05],
  [48.97, 8.23],
  [49.05, 7.85],
  [49.1, 7.45],
  [49.18, 7.05],
  [49.12, 6.85],
  [49.32, 6.62],
  [49.47, 6.37],
]);

/** DE/LU: Schengen im Süden bis zum Dreiländereck mit BE. */
const G_DE_LU = grenze([
  [49.47, 6.37],
  [49.6, 6.37],
  [49.72, 6.51],
  [49.83, 6.51],
  [49.9, 6.3],
  [50.05, 6.14],
  [50.18, 6.13],
]);

/** BE/DE: Dreiländereck mit LU bis Vaals (Dreiländereck mit NL). */
const G_BE_DE = grenze([
  [50.18, 6.13],
  [50.32, 6.35],
  [50.5, 6.2],
  [50.62, 6.25],
  [50.75, 6.02],
]);

/** DE/NL: Vaals im Süden bis zum Dollart im Norden. */
const G_DE_NL = grenze([
  [50.75, 6.02],
  [51.02, 6.03],
  [51.2, 6.08],
  [51.45, 6.13],
  [51.75, 6.1],
  [51.83, 5.95],
  [51.87, 6.16],
  [52.05, 6.7],
  [52.25, 6.85],
  [52.44, 7.07],
  [52.65, 7.07],
  [53.0, 7.21],
  [53.32, 7.19],
]);

/**
 * BE/NL: Nordsee bei Knokke nach Osten bis Vaals.
 *
 * Der Knick ab 51,1 N ist der schmale Zipfel der niederländischen Provinz
 * Limburg. Eine gerade Linie von Eindhoven nach Vaals legte Maastricht nach
 * Belgien — und Belgien hat keinen Eintrag in der Gate-Tabelle, die Warnung
 * fiele dort also in den Default statt in die niederländische Erlaubnis.
 */
const G_BE_NL = grenze([
  [51.38, 3.36],
  [51.28, 4.05],
  [51.45, 4.53],
  [51.42, 4.85],
  [51.48, 5.05],
  [51.3, 5.25],
  [51.2, 5.45],
  [51.1, 5.7],
  [50.97, 5.68],
  [50.86, 5.63],
  [50.78, 5.72],
  [50.76, 5.9],
  [50.75, 6.02],
]);

/** BE/FR: Nordsee bei Dünkirchen bis zum Dreiländereck mit LU. */
const G_BE_FR = grenze([
  [51.09, 2.54],
  [50.8, 3.05],
  [50.72, 3.28],
  [50.5, 4.15],
  [50.13, 4.15],
  [49.98, 4.85],
  [49.79, 5.44],
  [49.54, 5.82],
]);

/** BE/LU: Dreiländereck mit FR im Süden bis Dreiländereck mit DE im Norden. */
const G_BE_LU = grenze([
  [49.54, 5.82],
  [49.7, 5.78],
  [49.9, 5.75],
  [50.05, 6.0],
  [50.18, 6.13],
]);

/** FR/LU: Dreiländereck mit BE im Westen bis Schengen im Osten. */
const G_FR_LU = grenze([
  [49.54, 5.82],
  [49.48, 5.95],
  [49.46, 6.15],
  [49.47, 6.37],
]);

/**
 * CH/FR: Basel im Norden bis zum Mont Blanc.
 *
 * Der Bogen bei 46,1 bis 46,3 N bildet den Kanton Genf nach, der als
 * Schweizer Vorsprung fast vollständig von Frankreich umschlossen ist.
 */
const G_CH_FR = grenze([
  [47.59, 7.59],
  [47.49, 7.2],
  [47.44, 7.0],
  [47.35, 6.87],
  [47.05, 6.75],
  [46.77, 6.44],
  [46.42, 6.08],
  [46.28, 5.96],
  [46.13, 6.13],
  [46.15, 6.3],
  [46.05, 6.8],
  [45.92, 7.04],
]);

/**
 * CH/IT: Mont Blanc im Westen bis zum Dreiländereck mit AT am Reschen.
 *
 * Der Einschnitt bis 45,82 N ist die Südspitze des Tessins bei Chiasso — die
 * Grenze läuft dort auf beiden Seiten eines schmalen Schweizer Zipfels.
 */
const G_CH_IT = grenze([
  [45.92, 7.04],
  [45.94, 7.4],
  [45.97, 7.9],
  [46.1, 8.1],
  [46.25, 8.45],
  [46.1, 8.75],
  [45.98, 8.9],
  [45.82, 9.02],
  [46.05, 9.1],
  [46.2, 9.25],
  [46.35, 9.45],
  [46.45, 10.05],
  [46.63, 10.45],
  [46.85, 10.45],
]);

/**
 * AT/CH: Bodensee bei Lindau nach Süden bis zum Reschen.
 *
 * Liechtenstein liegt östlich des Rheins und ist hier dem österreichischen
 * Umriss zugeschlagen. Das ist geografisch falsch und für das Gate folgenlos:
 * AT und CH haben beide warnung: false, die Warnung bleibt so oder so aus.
 * Sobald ein generierter Umriss vorliegt, bekommt LI einen eigenen — dann
 * aber bitte zusammen mit einem eigenen Eintrag in config.LAENDER_GATE, sonst
 * fällt es in den Default und nicht in eine geprüfte Aussage.
 */
const G_AT_CH = grenze([
  [47.55, 9.73],
  [47.28, 9.6],
  [47.1, 9.55],
  [46.95, 9.6],
  [46.85, 10.1],
  [46.85, 10.45],
]);

/** AT/IT: Reschen im Westen bis zum Dreiländereck mit SI im Osten. */
const G_AT_IT = grenze([
  [46.85, 10.45],
  [46.78, 10.55],
  [46.85, 11.0],
  [47.0, 11.5],
  [46.9, 12.0],
  [46.77, 12.15],
  [46.9, 12.3],
  [46.65, 12.95],
  [46.55, 13.3],
  [46.43, 13.7],
]);

/** FR/IT: Mont Blanc im Norden bis Ventimiglia am Mittelmeer. */
const G_FR_IT = grenze([
  [45.92, 7.04],
  [45.6, 6.95],
  [45.4, 6.8],
  [45.2, 6.65],
  [45.1, 6.9],
  [44.85, 7.0],
  [44.62, 6.75],
  [44.4, 6.9],
  [44.15, 7.35],
  [44.05, 7.5],
  [43.78, 7.53],
]);

/**
 * ES/FR: Atlantik bei Hendaye bis zum Cap de Creus am Mittelmeer.
 *
 * Andorra liegt auf diesem Abschnitt und hat keinen eigenen Umriss. Es steht
 * deshalb in UNSICHERE_ZONEN — ohne diesen Eintrag fiele es je nach
 * Linienführung an Spanien oder Frankreich, und beide erlauben die Warnung.
 * Das wäre der eine Fall, in dem eine grobe Linie die Warnung fälschlich
 * einschaltet statt aus.
 */
const G_ES_FR = grenze([
  [43.38, -1.79],
  [43.05, -1.3],
  [42.92, -0.75],
  [42.8, -0.15],
  [42.85, 0.65],
  [42.72, 1.45],
  [42.5, 1.72],
  [42.55, 2.1],
  [42.35, 2.55],
  [42.48, 3.17],
]);

/** AT/CZ: Dreiländereck mit DE bei Passau bis zur slowakischen Grenze. */
const G_AT_CZ = grenze([
  [48.77, 13.83],
  [48.58, 14.05],
  [48.6, 14.7],
  [48.78, 14.98],
  [48.73, 15.15],
  [48.85, 15.55],
  [48.8, 16.1],
  [48.72, 16.95],
]);

/** CZ/PL: Dreiländereck mit DE bei Zittau bis zur slowakischen Grenze. */
const G_CZ_PL = grenze([
  [50.87, 14.82],
  [50.9, 15.3],
  [50.7, 15.8],
  [50.65, 16.2],
  [50.42, 16.2],
  [50.5, 16.7],
  [50.25, 17.2],
  [50.05, 17.7],
  [49.95, 18.3],
  [49.51, 18.85],
]);

// --- Aussenkanten ohne Nachbarn in dieser Datei ---------------------------
// Küsten sind 'kueste' und zählen nicht als Grenze. Landgrenzen zu Ländern
// ohne eigenen Umriss (PT, SI, SK, HU, und der ganze Osten Polens) sind
// 'grenze': dahinter liegt ein Land, über dessen Rechtslage hier nichts
// bekannt ist, und der Mindestabstand soll auch dort greifen.

const K_DE_OSTSEE = kueste([
  [54.79, 9.62],
  [54.42, 10.2],
  [54.28, 10.15],
  [54.45, 11.2],
  [53.95, 10.87],
  [54.18, 12.09],
  [54.31, 13.09],
  [54.55, 13.4],
  [54.1, 13.7],
  [53.93, 14.22],
]);

const K_DE_NORDSEE = kueste([
  [53.32, 7.19],
  [53.58, 6.7],
  [53.7, 8.0],
  [53.87, 8.7],
  [54.0, 8.9],
  [54.13, 8.85],
  [54.5, 8.9],
  [54.9, 8.3],
  [54.91, 8.6],
]);

const K_NL_NORDSEE = kueste([
  [53.32, 7.19],
  [53.42, 6.85],
  [53.45, 6.2],
  [53.38, 5.4],
  [53.18, 4.85],
  [52.9, 4.72],
  [52.47, 4.55],
  [52.1, 4.3],
  [51.98, 4.05],
  [51.7, 3.75],
  [51.55, 3.55],
  [51.38, 3.36],
]);

const K_BE_NORDSEE = kueste([
  [51.38, 3.36],
  [51.32, 3.15],
  [51.23, 2.93],
  [51.09, 2.54],
]);

const K_FR_MITTELMEER = kueste([
  [43.78, 7.53],
  [43.55, 7.1],
  [43.4, 6.65],
  [43.05, 6.0],
  [43.3, 5.05],
  [43.45, 4.6],
  [43.55, 4.15],
  [43.35, 3.55],
  [43.1, 3.05],
  [42.9, 3.05],
  [42.48, 3.17],
]);

const K_FR_ATLANTIK = kueste([
  [43.38, -1.79],
  [43.7, -1.42],
  [44.6, -1.25],
  [45.55, -1.2],
  [46.2, -1.55],
  [46.8, -2.15],
  [47.28, -2.3],
  [47.55, -3.1],
  [47.75, -4.05],
  [48.03, -4.75],
  [48.45, -4.8],
  [48.68, -4.05],
  [48.8, -3.05],
  [48.65, -2.02],
  [48.62, -1.55],
  [49.3, -1.62],
  [49.72, -1.94],
  [49.4, -1.15],
  [49.35, -0.25],
  [49.5, 0.2],
  [49.85, 1.15],
  [50.3, 1.55],
  [50.9, 1.6],
  [51.09, 2.54],
]);

const K_ES_MITTELMEER = kueste([
  [42.48, 3.17],
  [41.9, 3.2],
  [41.68, 2.9],
  [41.32, 2.15],
  [41.1, 1.2],
  [40.7, 0.85],
  [40.2, 0.15],
  [39.85, 0.0],
  [39.45, -0.32],
  [38.85, -0.1],
  [38.73, 0.23],
  [38.3, -0.48],
  [37.85, -0.75],
  [37.55, -1.3],
  [36.95, -1.9],
  [36.75, -2.15],
  [36.72, -3.55],
  [36.5, -4.65],
  [36.3, -5.2],
  [36.15, -5.35],
]);

const K_ES_ATLANTIK_SUED = kueste([
  [36.15, -5.35],
  [36.35, -6.2],
  [36.85, -6.35],
  [37.2, -7.0],
  [37.18, -7.4],
]);

/** ES/PT. Portugal hat keinen Umriss in dieser Datei, die Kante bleibt Grenze. */
const G_ES_PT = grenze([
  [37.18, -7.4],
  [37.55, -7.45],
  [38.1, -7.3],
  [38.2, -7.0],
  [38.75, -7.1],
  [39.1, -7.15],
  [39.45, -7.5],
  [39.7, -7.45],
  [40.15, -6.85],
  [40.6, -6.8],
  [41.05, -6.8],
  [41.4, -6.35],
  [41.7, -6.55],
  [41.9, -6.75],
  [41.95, -7.2],
  [41.85, -8.2],
  [41.88, -8.88],
]);

const K_ES_ATLANTIK_NORD = kueste([
  [41.88, -8.88],
  [42.2, -8.85],
  [42.5, -8.85],
  [42.75, -9.05],
  [43.05, -9.28],
  [43.35, -8.5],
  [43.55, -8.3],
  [43.7, -7.7],
  [43.55, -7.0],
  [43.55, -6.2],
  [43.4, -5.7],
  [43.45, -4.5],
  [43.42, -3.8],
  [43.48, -3.2],
  [43.4, -2.4],
  [43.38, -1.79],
]);

/** IT/SI. Slowenien hat keinen Umriss, die Kante bleibt Grenze. */
const G_IT_SI = grenze([
  [46.43, 13.7],
  [46.22, 13.55],
  [46.05, 13.5],
  [45.85, 13.6],
  [45.6, 13.75],
]);

const K_IT_KUESTE = kueste([
  [45.6, 13.75],
  [45.5, 13.6],
  [45.4, 12.3],
  [44.8, 12.4],
  [44.0, 12.6],
  [43.6, 13.5],
  [42.9, 14.1],
  [42.2, 14.7],
  [41.9, 15.4],
  [41.9, 16.2],
  [41.4, 16.5],
  [40.8, 17.4],
  [40.5, 18.0],
  [40.0, 18.4],
  [39.8, 18.35],
  [40.1, 17.9],
  [40.4, 17.2],
  [39.9, 16.9],
  [38.9, 16.6],
  [38.5, 16.55],
  [37.93, 15.65],
  [38.5, 15.9],
  [39.5, 16.1],
  [40.0, 15.3],
  [40.6, 14.8],
  [41.2, 13.7],
  [41.4, 13.0],
  [42.1, 11.8],
  [42.9, 10.5],
  [43.8, 10.25],
  [44.4, 9.2],
  [44.1, 8.3],
  [43.78, 7.53],
]);

const K_IT_SIZILIEN = kueste([
  [38.19, 15.56],
  [38.12, 13.36],
  [38.02, 12.5],
  [37.8, 12.43],
  [37.65, 12.6],
  [37.5, 13.08],
  [37.07, 14.25],
  [36.69, 15.1],
  [37.07, 15.28],
  [37.5, 15.1],
]);

const K_IT_SARDINIEN = kueste([
  [41.25, 9.2],
  [40.9, 9.75],
  [40.5, 9.7],
  [39.9, 9.7],
  [39.15, 9.5],
  [38.9, 8.9],
  [39.2, 8.4],
  [39.9, 8.4],
  [40.6, 8.15],
  [41.1, 8.2],
]);

const K_DK_JUETLAND = kueste([
  [54.79, 9.62],
  [55.05, 9.75],
  [55.5, 9.5],
  [56.15, 10.2],
  [56.4, 10.9],
  [56.7, 10.3],
  [57.05, 9.9],
  [57.74, 10.6],
  [57.4, 9.9],
  [56.7, 8.2],
  [56.0, 8.13],
  [55.5, 8.1],
  [55.05, 8.3],
  [54.91, 8.6],
]);

/**
 * Fünen und Seeland als ein Ring. Die Ostkante bleibt bei 12,7 O — östlich
 * davon beginnt Schweden, und Malmö darf nicht dänisch werden.
 */
const K_DK_INSELN = kueste([
  [55.6, 10.6],
  [55.3, 10.9],
  [55.0, 11.0],
  [54.85, 11.9],
  [54.95, 12.5],
  [55.3, 12.6],
  [55.75, 12.65],
  [56.1, 12.55],
  [56.15, 11.7],
  [55.9, 11.0],
]);

const K_PL_OSTSEE = kueste([
  [53.93, 14.22],
  [54.35, 15.5],
  [54.55, 16.9],
  [54.75, 18.3],
  [54.45, 18.6],
  [54.4, 19.3],
  [54.45, 19.65],
]);

/** PL zu RU, LT, BY und UA. Kein Umriss vorhanden, Kante bleibt Grenze. */
const G_PL_OST = grenze([
  [54.45, 19.65],
  [54.35, 22.8],
  [54.0, 23.5],
  [53.0, 23.9],
  [52.3, 23.6],
  [51.6, 23.7],
  [50.8, 24.1],
  [50.4, 23.9],
  [49.6, 22.7],
  [49.09, 22.86],
]);

/** PL/SK. Kein Umriss für SK, Kante bleibt Grenze. */
const G_PL_SK = grenze([
  [49.09, 22.86],
  [49.4, 21.3],
  [49.3, 20.1],
  [49.5, 19.5],
  [49.51, 18.85],
]);

/** CZ/SK. Kein Umriss für SK, Kante bleibt Grenze. */
const G_CZ_SK = grenze([
  [48.72, 16.95],
  [48.85, 17.2],
  [49.1, 18.1],
  [49.3, 18.55],
  [49.51, 18.85],
]);

/** AT zu SK, HU und SI. Kein Umriss vorhanden, Kante bleibt Grenze. */
const G_AT_OST_SUED = grenze([
  [48.72, 16.95],
  [48.8, 17.1],
  [48.4, 17.05],
  [47.9, 17.05],
  [47.7, 16.9],
  [47.4, 16.5],
  [47.0, 16.45],
  [46.7, 16.35],
  [46.5, 16.0],
  [46.65, 15.0],
  [46.5, 14.6],
  [46.43, 13.7],
]);

// --- Die Umrisse ----------------------------------------------------------

export const UMRISSE: readonly Umriss[] = [
  umrissAus('DE', 'Deutschland', [
    [
      G_DE_DK,
      K_DE_OSTSEE,
      G_DE_PL,
      G_CZ_DE,
      G_AT_DE,
      G_CH_DE,
      G_DE_FR,
      G_DE_LU,
      G_BE_DE,
      G_DE_NL,
      K_DE_NORDSEE,
    ],
  ]),

  umrissAus('AT', 'Österreich', [
    [rueckwaerts(G_AT_DE), G_AT_CZ, G_AT_OST_SUED, rueckwaerts(G_AT_IT), rueckwaerts(G_AT_CH)],
  ]),

  umrissAus('CH', 'Schweiz', [
    [rueckwaerts(G_CH_DE), G_AT_CH, rueckwaerts(G_CH_IT), rueckwaerts(G_CH_FR)],
  ]),

  umrissAus('FR', 'Frankreich', [
    [
      G_BE_FR,
      G_FR_LU,
      rueckwaerts(G_DE_FR),
      G_CH_FR,
      G_FR_IT,
      K_FR_MITTELMEER,
      rueckwaerts(G_ES_FR),
      K_FR_ATLANTIK,
    ],
  ]),

  umrissAus('ES', 'Spanien', [
    [G_ES_FR, K_ES_MITTELMEER, K_ES_ATLANTIK_SUED, G_ES_PT, K_ES_ATLANTIK_NORD],
  ]),

  umrissAus('NL', 'Niederlande', [[G_BE_NL, G_DE_NL, K_NL_NORDSEE]]),

  umrissAus('BE', 'Belgien', [
    [K_BE_NORDSEE, G_BE_FR, G_BE_LU, G_BE_DE, rueckwaerts(G_BE_NL)],
  ]),

  umrissAus('LU', 'Luxemburg', [[G_DE_LU, rueckwaerts(G_BE_LU), G_FR_LU]]),

  umrissAus('DK', 'Dänemark', [[G_DE_DK, K_DK_JUETLAND], [K_DK_INSELN]]),

  umrissAus('PL', 'Polen', [
    [K_PL_OSTSEE, G_PL_OST, G_PL_SK, rueckwaerts(G_CZ_PL), rueckwaerts(G_DE_PL)],
  ]),

  umrissAus('CZ', 'Tschechien', [
    [G_CZ_DE, G_AT_CZ, G_CZ_SK, rueckwaerts(G_CZ_PL)],
  ]),

  umrissAus('IT', 'Italien', [
    [G_CH_IT, G_AT_IT, G_IT_SI, K_IT_KUESTE, rueckwaerts(G_FR_IT)],
    [K_IT_SIZILIEN],
    [K_IT_SARDINIEN],
  ]),
];

// --- Zonen, in denen der Umriss keine Aussage tragen kann ------------------

export type UnsichereZone = {
  readonly name: string;
  readonly bbox: BBox;
  readonly grund: string;
};

/**
 * Gebiete, in denen ein grober Umriss systematisch das falsche Land liefert:
 * Kleinstaaten und Enklaven, die kleiner sind als der Fehler der Linien.
 *
 * Hier wird gar kein Land bestimmt. Das Ergebnis ist "unbekannt" und damit
 * der sichere Default aus config — die Warnung bleibt aus. Ein Rechteck ist
 * hier ausnahmsweise das richtige Werkzeug: Es soll nichts entscheiden,
 * sondern nur eine Entscheidung verhindern, und dafür darf es grosszügig
 * sein.
 *
 * Sobald ein Land einen eigenen, generierten Umriss und einen geprüften
 * Eintrag in config.LAENDER_GATE hat, fliegt es aus dieser Liste.
 */
export const UNSICHERE_ZONEN: readonly UnsichereZone[] = [
  {
    name: 'Andorra',
    bbox: { latMin: 42.35, latMax: 42.75, lonMin: 1.3, lonMax: 1.9 },
    grund: 'liegt vollständig auf der Linie ES/FR, beide erlauben die Warnung',
  },
  {
    name: 'Liechtenstein',
    bbox: { latMin: 47.0, latMax: 47.32, lonMin: 9.4, lonMax: 9.7 },
    grund: 'liegt vollständig in der Bounding-Box Österreichs',
  },
  {
    name: 'Monaco',
    bbox: { latMin: 43.68, latMax: 43.79, lonMin: 7.33, lonMax: 7.49 },
    grund: 'kleiner als der Fehler der französischen Küstenlinie',
  },
  {
    name: 'San Marino',
    bbox: { latMin: 43.82, latMax: 44.03, lonMin: 12.35, lonMax: 12.56 },
    grund: 'vollständig von Italien umschlossen',
  },
  {
    name: 'Vatikanstadt',
    bbox: { latMin: 41.88, latMax: 41.92, lonMin: 12.43, lonMax: 12.47 },
    grund: 'vollständig von Italien umschlossen',
  },
  {
    name: 'Gibraltar',
    bbox: { latMin: 36.07, latMax: 36.19, lonMin: -5.4, lonMax: -5.3 },
    grund: 'eigenes Recht, liegt im spanischen Umriss',
  },
  {
    name: 'Büsingen am Hochrhein',
    bbox: { latMin: 47.65, latMax: 47.74, lonMin: 8.63, lonMax: 8.75 },
    grund: 'deutsche Exklave in der Schweiz',
  },
  {
    name: 'Campione d’Italia',
    bbox: { latMin: 45.93, latMax: 46.02, lonMin: 8.92, lonMax: 9.04 },
    grund: 'italienische Exklave in der Schweiz',
  },
  {
    name: 'Baarle-Hertog und Baarle-Nassau',
    bbox: { latMin: 51.38, latMax: 51.5, lonMin: 4.86, lonMax: 5.02 },
    grund: 'ineinander verschachtelte Enklaven BE/NL mit unterschiedlichem Gate',
  },
];

export function inUnsichererZone(lat: number, lon: number): UnsichereZone | null {
  for (const zone of UNSICHERE_ZONEN) {
    if (bboxEnthaelt(zone.bbox, lat, lon)) return zone;
  }
  return null;
}

/** Umriss zu einem Code, oder null. Lineare Suche über zwölf Einträge. */
export function umrissFuer(code: UmrissCode): Umriss | null {
  for (const u of UMRISSE) {
    if (u.code === code) return u;
  }
  return null;
}
