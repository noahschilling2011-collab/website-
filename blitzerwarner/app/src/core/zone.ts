/**
 * Zonenmodus, Spec Phase C.2.
 *
 * Reine Funktionen über explizitem Zustand, wie warn.ts — damit der
 * Replay-Test dieselbe Logik ohne Gerät füttern kann.
 *
 * WAS HIER ANDERS IST ALS BEI DER PUNKTWARNUNG, und warum:
 *
 *  - Keine Entfernung. Die Regelung erlaubt den Hinweis auf einen Bereich,
 *    nicht auf einen Punkt. Diese Datei kennt deshalb keine Distanz zur
 *    Kamera — sie kennt gar keine Kameras.
 *  - Keine Richtungsfilterung. Eine Zone ist rundum; sie beginnt vor der
 *    Anlage und endet dahinter. Das ist keine Vereinfachung, sondern die
 *    Konsequenz aus der Vorgabe.
 *  - Genau eine Ansage beim Eintritt. Kein Countdown, keine zweite Ansage
 *    innerhalb derselben Zone.
 */

/** Eine Zone aus cameras.<Land>.zones.json. Mittelpunkt und Radius, sonst nichts. */
export type Zone = {
  readonly lat: number;
  readonly lon: number;
  readonly r: number;
};

export type ZonenDatensatz = {
  readonly version: number;
  readonly land: string;
  readonly osmTimestamp: string | null;
  readonly count: number;
  readonly zones: readonly Zone[];
};

/**
 * Zustand über eine Fahrt.
 *
 * `drin` hält die Zonen, in denen wir uns gerade befinden. Der Schlüssel ist
 * Mittelpunkt plus Radius — eine Zone hat keine ID, und sie soll auch keine
 * bekommen: Eine ID wäre ein weiteres Feld, über das sich Zonen einzeln
 * wiedererkennen und mit Beobachtungen verknüpfen liessen.
 */
export type ZonenZustand = {
  drin: Set<string>;
};

export function createZonenZustand(): ZonenZustand {
  return { drin: new Set() };
}

function schluessel(z: Zone): string {
  return `${z.lat},${z.lon},${z.r}`;
}

const EARTH_RADIUS_M = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

/** Abstand in Metern. Eigene Kopie, damit dieses Modul für sich steht. */
function abstand(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

export type ZonenErgebnis = {
  /** Zone, die JETZT betreten wurde. null, wenn keine. */
  betreten: Zone | null;
  /** Wie viele Zonen umschliessen die Position gerade? Nur für die Anzeige. */
  aktiveZonen: number;
};

/**
 * Eine Position auswerten.
 *
 * Meldet eine Zone genau dann, wenn wir sie in diesem Schritt BETRETEN haben.
 * Solange wir drin bleiben, kommt nichts mehr — und beim Verlassen wird der
 * Zustand zurückgesetzt, damit ein erneutes Betreten wieder ansagt.
 *
 * Das Verlassen wird über den vollen Zonensatz geprüft und nicht über eine
 * Distanzschwelle: Bei einer zusammengefassten Zone von 8 km Durchmesser wäre
 * jede Schwelle geraten.
 */
export function pruefeZonen(
  lat: number,
  lon: number,
  zonen: readonly Zone[],
  zustand: ZonenZustand,
): ZonenErgebnis {
  const jetztDrin = new Set<string>();
  let betreten: Zone | null = null;
  let aktive = 0;

  for (const zone of zonen) {
    if (abstand(lat, lon, zone.lat, zone.lon) > zone.r) continue;

    aktive++;
    const k = schluessel(zone);
    jetztDrin.add(k);

    // Nur die erste neu betretene Zone wird gemeldet. Zwei Ansagen im selben
    // Moment wären zwei Ansagen für einen Bereich.
    if (!zustand.drin.has(k) && betreten === null) betreten = zone;
  }

  zustand.drin = jetztDrin;
  return { betreten, aktiveZonen: aktive };
}

/**
 * Zonen in der Nähe, für den Vorfilter.
 *
 * Anders als bei den Kameras gibt es hier kein Gitter: Ein Land hat einige
 * tausend Zonen, und ein linearer Durchlauf über ein paar tausend Abstände
 * kostet unter einer Millisekunde. Ein Gitter wäre Aufwand ohne Gegenwert —
 * und ein zweites Indexformat, das falsch werden kann.
 */
export function zonenDatensatzPruefen(daten: unknown): ZonenDatensatz {
  const d = daten as Partial<ZonenDatensatz> & Record<string, unknown>;
  if (d.version !== 1) throw new Error(`Zonendatei: unbekannte Version ${String(d.version)}`);
  if (!Array.isArray(d.zones)) throw new Error('Zonendatei: zones fehlt');
  if (d.zones.length !== d.count) {
    throw new Error(`Zonendatei: count ${String(d.count)} passt nicht zu ${d.zones.length} Zonen`);
  }

  for (const z of d.zones as Zone[]) {
    if (!Number.isFinite(z.lat) || !Number.isFinite(z.lon) || !Number.isFinite(z.r)) {
      throw new Error('Zonendatei: Zone mit ungültigen Zahlen');
    }
    // Die Mindestlängen der Regelung: 300 m innerorts ergibt 150 m Radius.
    // Etwas darunter kann nur ein Fehler im Generator sein — und eine zu
    // kleine Zone ist der rechtlich problematische Fall.
    if (z.r < 150) throw new Error(`Zonendatei: Radius ${z.r} m unter der Mindestlänge`);
  }

  return d as ZonenDatensatz;
}
