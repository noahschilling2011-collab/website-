#!/usr/bin/env node
/**
 * Phase C.1 — Gefahrenzonen für Länder mit Zonenmodus (derzeit Frankreich).
 *
 *   npx tsx scripts/build-zones.ts FR
 *
 * Läuft NACH build-dataset.ts und erzeugt cameras.FR.zones.json.
 *
 * Warum zur Build-Zeit und nicht zur Laufzeit: Zonen sind eine Eigenschaft
 * des Datensatzes, nicht der Fahrt. Sie zur Laufzeit zu rechnen hiesse, die
 * Kamerapositionen im Gerät zu haben — und damit wäre die Zone Dekoration.
 *
 * DIE ZENTRALE AUFLAGE: Aus der Zonendatei darf sich die Kameraposition NICHT
 * rekonstruieren lassen. Eine Zone mit genau einer Kamera und dem Radius als
 * einzigem Feld gibt den Mittelpunkt her — deshalb enthält die Datei die Zahl
 * der Kameras nicht, ihre Koordinaten nicht, ihren Typ nicht und ihr
 * Tempolimit nicht. Ein Test sucht die Datei nach solchen Feldern ab.
 *
 * Frankreich verlangt seit dem 03.01.2012 Mindestlängen: 300 m innerorts,
 * 2000 m auf Land- und Nebenstrassen, 4000 m auf Autobahnen. Zwei dicht
 * aufeinanderfolgende Zonen werden zu einer grösseren zusammengefasst.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { haversine, type Camera } from './lib/normalize.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const DATA_DIR = join(ROOT, 'assets', 'data');

/**
 * Mindestlängen der Zone je Strassentyp, in Metern.
 *
 * Aus der französischen Regelung. Der Radius ist die halbe Mindestlänge:
 * Die Kamera darf an einem beliebigen Punkt innerhalb der Zone liegen, und
 * eine Zone um die Kamera herum erfüllt die Mindestlänge, wenn sie in jede
 * Richtung die Hälfte abdeckt.
 */
const MINDESTLAENGE_M = {
  innerorts: 300,
  landstrasse: 2000,
  autobahn: 4000,
} as const;

type Strassentyp = keyof typeof MINDESTLAENGE_M;

/**
 * Obergrenze für den Radius einer zusammengefassten Zone.
 *
 * Ohne diese Grenze kaskadiert das Zusammenfassen: Werden A und B zu einer
 * grösseren Zone, überlappt die anschliessend C, wird noch grösser, überlappt
 * D — gemessen an Deutschland entstand so eine Zone mit 85 km Radius. Die
 * Regelung erlaubt das Zusammenfassen ZWEI DICHT AUFEINANDERFOLGENDER Zonen,
 * nicht eine Kette durch halb Europa. Eine 85-km-Zone wäre ausserdem als
 * Hinweis wertlos.
 *
 * 6000 m ist das Anderthalbfache der längsten Mindestlänge (4000 m). Damit
 * dürfen zwei Autobahnzonen verschmelzen, aber keine Kette entstehen.
 */
const MAX_ZONEN_RADIUS_M = 6000;

/**
 * Strassentyp aus dem Tempolimit ableiten.
 *
 * DAS IST EINE ANNAHME, KEINE MESSUNG. Der Datensatz trägt kein
 * `highway`-Tag, nur `maxspeed`. Die Ableitung ist plausibel, aber sie irrt
 * sich zum Beispiel bei einer innerorts gelegenen Schnellstrasse mit Tempo 70
 * oder einer Landstrasse mit Tempo 50.
 *
 * Bei unbekanntem Tempolimit gilt die LÄNGSTE Zone. Im Zweifel die unschärfere
 * Zone — eine zu kurze Zone ist der rechtlich problematische Fall, eine zu
 * lange nur der unpräzise.
 *
 * Der saubere Weg wäre der `highway`-Tag der zugehörigen Strasse. Der steht
 * heute nicht im Datensatz; vermerkt in DATA.md als offener Punkt.
 */
export function strassentypAusTempo(max: number | null): Strassentyp {
  if (max === null) return 'autobahn';
  if (max <= 50) return 'innerorts';
  if (max < 100) return 'landstrasse';
  return 'autobahn';
}

/** Eine Zone. Mittelpunkt und Radius — nichts sonst. */
export type Zone = {
  lat: number;
  lon: number;
  r: number;
};

const round5 = (n: number) => Math.round(n * 1e5) / 1e5;

/**
 * Zonen aus Kameras erzeugen und überlappende zusammenfassen.
 *
 * Das Zusammenfassen ist von der Regelung ausdrücklich zugelassen und hat
 * einen zweiten, wichtigeren Nutzen: Es macht die Rekonstruktion schwerer.
 * Aus einer Zone, die zwei Kameras abdeckt, lässt sich keine einzelne
 * Position mehr ableiten.
 */
export function baueZonen(kameras: Camera[]): Zone[] {
  let zonen: Zone[] = kameras.map((k) => ({
    lat: k.lat,
    lon: k.lon,
    r: MINDESTLAENGE_M[strassentypAusTempo(k.max)] / 2,
  }));

  // Wiederholt zusammenfassen, bis sich nichts mehr ändert. Ein Durchlauf
  // genügt nicht: Werden A und B zu einer grösseren Zone, kann diese
  // anschliessend auch C überlappen.
  let geaendert = true;
  while (geaendert) {
    geaendert = false;
    const ergebnis: Zone[] = [];

    for (const zone of zonen) {
      let verschmolzen = false;
      for (const bestehend of ergebnis) {
        const d = haversine(zone.lat, zone.lon, bestehend.lat, bestehend.lon);
        // Überlappung, wenn der Abstand kleiner ist als die Summe der Radien.
        if (d < zone.r + bestehend.r) {
          // Vorab prüfen, ob die verschmolzene Zone die Obergrenze reisst.
          // Wenn ja: nicht verschmelzen. Zwei überlappende Zonen sind
          // unschön, aber die Laufzeit gibt dafür nur eine Ansage aus (siehe
          // pruefeZonen), und beide erfüllen weiter ihre Mindestlänge.
          const geschaetzterRadius = (d + zone.r + bestehend.r) / 2;
          if (geschaetzterRadius > MAX_ZONEN_RADIUS_M) continue;

          // Neue Zone: Mittelpunkt zwischen beiden, Radius so, dass beide
          // vollständig darin liegen. Die Mindestlänge bleibt damit erfüllt,
          // weil die Zone nur wachsen kann.
          const anteil = d === 0 ? 0.5 : (d + zone.r - bestehend.r) / (2 * d);
          const t = Math.max(0, Math.min(1, anteil));
          const neuLat = bestehend.lat + (zone.lat - bestehend.lat) * t;
          const neuLon = bestehend.lon + (zone.lon - bestehend.lon) * t;
          const neuR = Math.max(
            bestehend.r + haversine(bestehend.lat, bestehend.lon, neuLat, neuLon),
            zone.r + haversine(zone.lat, zone.lon, neuLat, neuLon),
          );
          bestehend.lat = neuLat;
          bestehend.lon = neuLon;
          bestehend.r = neuR;
          verschmolzen = true;
          geaendert = true;
          break;
        }
      }
      if (!verschmolzen) ergebnis.push({ ...zone });
    }
    zonen = ergebnis;
  }

  return zonen
    .map((z) => ({ lat: round5(z.lat), lon: round5(z.lon), r: Math.round(z.r) }))
    .sort((a, b) => a.lat - b.lat || a.lon - b.lon);
}

// --- Hauptlauf ------------------------------------------------------------

function main(): void {
  const land = (process.argv[2] ?? 'FR').toUpperCase();
  const quelle = join(DATA_DIR, `cameras.${land}.json`);
  const ziel = join(DATA_DIR, `cameras.${land}.zones.json`);

  if (!existsSync(quelle)) {
    console.error(
      `Kein Datensatz für ${land}: ${quelle}\n` +
      `Zuerst: npx tsx scripts/build-dataset.ts --countries ${land} --out ${quelle}`,
    );
    process.exit(1);
  }

  const datensatz = JSON.parse(readFileSync(quelle, 'utf8')) as {
    osmTimestamp: string | null;
    grid: Record<string, Camera[]>;
  };
  const kameras = Object.values(datensatz.grid).flat();
  console.log(`${land}: ${kameras.length} Anlagen`);

  const nachTyp = new Map<Strassentyp, number>();
  for (const k of kameras) {
    const t = strassentypAusTempo(k.max);
    nachTyp.set(t, (nachTyp.get(t) ?? 0) + 1);
  }
  console.log('\nStrassentyp aus maxspeed abgeleitet (ANNAHME, siehe DATA.md):');
  for (const [typ, n] of nachTyp) {
    console.log(`  ${typ.padEnd(12)} ${String(n).padStart(5)} Anlagen, Zonenradius ${MINDESTLAENGE_M[typ] / 2} m`);
  }
  const ohneTempo = kameras.filter((k) => k.max === null).length;
  console.log(`  davon ohne maxspeed: ${ohneTempo} — bekommen die längste Zone (4000 m)`);

  const zonen = baueZonen(kameras);

  // Die Ausgabe enthält bewusst NUR Mittelpunkt und Radius. Kein Zähler, keine
  // Typen, keine Tempolimits — sonst wäre die Zone Dekoration.
  const ausgabe = {
    version: 1 as const,
    land,
    osmTimestamp: datensatz.osmTimestamp,
    source: 'OpenStreetMap contributors',
    license: 'ODbL 1.0',
    hinweis:
      'Gefahrenzonen nach französischer Regelung. Enthält ausschliesslich ' +
      'Mittelpunkt und Radius. Die Zahl der enthaltenen Anlagen, ihre ' +
      'Koordinaten, ihr Typ und ihr Tempolimit sind absichtlich NICHT ' +
      'enthalten — sonst liesse sich die Position rekonstruieren.',
    count: zonen.length,
    zones: zonen,
  };
  writeFileSync(ziel, JSON.stringify(ausgabe));

  const bytes = readFileSync(ziel).length;
  console.log(
    `\n${'─'.repeat(64)}\n` +
    `Anlagen:        ${kameras.length}\n` +
    `Zonen:          ${zonen.length}  (${kameras.length - zonen.length} zusammengefasst)\n` +
    `kleinster Radius: ${Math.min(...zonen.map((z) => z.r))} m\n` +
    `grösster Radius:  ${Math.max(...zonen.map((z) => z.r))} m\n` +
    `Dateigrösse:    ${(bytes / 1024).toFixed(0)} KB -> ${ziel}\n` +
    `${'─'.repeat(64)}`,
  );
}

// Nur ausführen, wenn direkt aufgerufen — der Test importiert die Funktionen.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop() ?? '')) {
  main();
}
