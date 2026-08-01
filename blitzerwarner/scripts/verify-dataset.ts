#!/usr/bin/env node
/**
 * Prüft den gebauten Datensatz — Phase-1-DoD.
 *
 *   npm run verify-dataset
 *
 * Vier Teile:
 *   1. Integrität   — sitzt jede Kamera in der richtigen Gitterzelle, sind
 *                     alle Werte im plausiblen Bereich?
 *   2. Abdeckung    — Kameras pro Bundesland, absolut und pro 1000 km².
 *   3. Stichprobe   — Abgleich gegen bekannte Standorte aus einer
 *                     unabhängigen Quelle (scripts/reference-locations.json).
 *   4. Menge        — Abgleich der Landessummen gegen amtliche Zählungen
 *                     (scripts/reference-counts.json).
 *
 * Die Teile 1 und 2 prüfen den Datensatz gegen sich selbst. Das findet
 * Rechenfehler, aber keine Abdeckungslücke: Was in OpenStreetMap fehlt, fehlt
 * auch in jeder Prüfung, die nur den Datensatz liest.
 *
 * Dafür sind 3 und 4 da, und beide brauchen eine Quelle von aussen. 3 fragt
 * punktgenau ("steht diese bekannte Anlage drin?"), 4 fragt grob ("stimmt die
 * Grössenordnung?"). 4 ist billiger zu füllen und deshalb der erste Schritt;
 * 3 ist aussagekräftiger. Beide laufen nur, wenn ihre Datei gefüllt ist —
 * ohne Quelle keine Zahl.
 */
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { cellKey, haversine, CELL_SIZE, type Camera } from './lib/normalize.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const DATA_FILE = join(ROOT, 'assets', 'data', 'cameras.json');
const STATS_FILE = join(ROOT, 'assets', 'data', 'cameras.stats.json');
const REFERENCE_FILE = join(HERE, 'reference-locations.json');
const COUNTS_FILE = join(HERE, 'reference-counts.json');

/** Landesflächen in km², für die Dichteangabe. */
const AREA_KM2: Record<string, number> = {
  'DE-BW': 35_748, 'DE-BY': 70_542, 'DE-BE': 891, 'DE-BB': 29_654,
  'DE-HB': 420, 'DE-HH': 755, 'DE-HE': 21_116, 'DE-MV': 23_295,
  'DE-NI': 47_710, 'DE-NW': 34_112, 'DE-RP': 19_858, 'DE-SL': 2_571,
  'DE-SN': 18_450, 'DE-ST': 20_452, 'DE-SH': 15_804, 'DE-TH': 16_202,
  AT: 83_879, CH: 41_285, NL: 41_543, FR: 551_695, ES: 505_990,
};

/** Wie nah ein Datensatz-Eintrag an einem Referenzpunkt liegen muss. */
const REFERENCE_MATCH_RADIUS_M = 150;

type Dataset = {
  version: number;
  osmTimestamp: string | null;
  cell: number;
  count: number;
  countries: Record<string, { bbox: [number, number, number, number] | null; count: number }>;
  grid: Record<string, Camera[]>;
};

type ReferencePoint = {
  name: string;
  lat: number;
  lon: number;
  source: string;
};

/** Eine amtliche Zählung. Ohne quelle/url/zitat wird der Eintrag abgelehnt. */
type ReferenceCount = {
  anzahl: number;
  was: string;
  standDerZahl: string;
  quelle: string;
  url: string;
  zitat: string;
  /** Deckt die Zahl das ganze Land ab, oder ist sie nur eine Untergrenze? */
  landesweit: boolean;
  anmerkung?: string[];
};

type ReferenceCounts = {
  laender: Record<string, ReferenceCount>;
  ohneQuelle?: Record<string, string[]>;
};

function main() {
  if (!existsSync(DATA_FILE)) {
    console.error(`Kein Datensatz gefunden: ${DATA_FILE}\nZuerst "npm run build-dataset" ausführen.`);
    process.exit(1);
  }

  const data = JSON.parse(readFileSync(DATA_FILE, 'utf8')) as Dataset;
  const all = Object.values(data.grid).flat();

  console.log('═'.repeat(64));
  console.log('1. INTEGRITÄT');
  console.log('═'.repeat(64));

  const problems: string[] = [];

  if (data.cell !== CELL_SIZE) {
    problems.push(`Zellgrösse im Datensatz (${data.cell}) weicht vom Code (${CELL_SIZE}) ab`);
  }
  if (all.length !== data.count) {
    problems.push(`count=${data.count}, tatsächlich im Gitter: ${all.length}`);
  }

  for (const [key, cams] of Object.entries(data.grid)) {
    for (const c of cams) {
      if (cellKey(c.lat, c.lon) !== key) {
        problems.push(`Kamera ${c.lat},${c.lon} liegt in Zelle ${key}, gehört aber nach ${cellKey(c.lat, c.lon)}`);
      }
      if (!Number.isFinite(c.lat) || c.lat < -90 || c.lat > 90) problems.push(`ungültige lat: ${c.lat}`);
      if (!Number.isFinite(c.lon) || c.lon < -180 || c.lon > 180) problems.push(`ungültige lon: ${c.lon}`);
      if (c.dir != null && (c.dir < 0 || c.dir >= 360)) problems.push(`dir ausserhalb 0..360: ${c.dir}`);
      if (c.max != null && (c.max <= 0 || c.max > 200)) problems.push(`unplausible maxspeed: ${c.max}`);
      if (!['speed', 'red_light', 'both'].includes(c.type)) problems.push(`unbekannter type: ${c.type}`);
    }
  }

  // Verbliebene Dubletten: zwei Einträge < 30 m auseinander sollte es nach
  // dem Dedupe nicht mehr geben (ausser mit widersprüchlicher Richtung).
  let closePairs = 0;
  for (const cams of Object.values(data.grid)) {
    for (let i = 0; i < cams.length; i++) {
      for (let j = i + 1; j < cams.length; j++) {
        if (haversine(cams[i].lat, cams[i].lon, cams[j].lat, cams[j].lon) < 30) closePairs++;
      }
    }
  }

  console.log(`Einträge gesamt:        ${all.length}`);
  console.log(`Gitterzellen:           ${Object.keys(data.grid).length}`);
  console.log(`grösste Zelle:          ${Math.max(...Object.values(data.grid).map((c) => c.length))} Kameras`);
  console.log(`Paare < 30 m:           ${closePairs} (erwartet: nur gegenläufige Richtungen)`);
  console.log(`OSM-Datenstand:         ${data.osmTimestamp ?? 'unbekannt'}`);
  console.log(problems.length === 0 ? '\n  OK — keine Integritätsfehler.' : `\n  ${problems.length} PROBLEME:`);
  for (const p of problems.slice(0, 20)) console.log(`   - ${p}`);
  if (problems.length > 20) console.log(`   ... und ${problems.length - 20} weitere`);

  console.log('\n' + '═'.repeat(64));
  console.log('2. ABDECKUNG PRO GEBIET');
  console.log('═'.repeat(64));

  if (existsSync(STATS_FILE)) {
    const stats = JSON.parse(readFileSync(STATS_FILE, 'utf8'));
    console.log('Alle Zahlen nach Deduplizierung. "roh" = OSM-Treffer davor.\n');
    console.log('Code   Gebiet                   Anlagen      roh   /1000km²   Richtung   maxspeed');
    console.log('─'.repeat(82));
    for (const r of stats.perRegion) {
      const area = AREA_KM2[r.code];
      const density = area ? ((r.cameras / area) * 1000).toFixed(1) : '—';
      const dirPct = r.cameras ? `${Math.round((r.withDirection / r.cameras) * 100)} %` : '—';
      const maxPct = r.cameras ? `${Math.round((r.withMaxspeed / r.cameras) * 100)} %` : '—';
      console.log(
        `${r.code.padEnd(6)} ${r.name.padEnd(24)} ${String(r.cameras).padStart(6)} ` +
        `${String(r.raw ?? '—').padStart(8)} ${density.padStart(10)} ` +
        `${dirPct.padStart(10)} ${maxPct.padStart(10)}` +
        (r.error ? '   FEHLER' : ''),
      );
    }
    console.log('─'.repeat(82));
    console.log(`vor Dedupe: ${stats.totalBeforeDedupe}, danach: ${stats.totalAfterDedupe} ` +
      `(${stats.removedByDedupe} zusammengefasst)`);
    // Die Summe der Gebietszahlen darf minimal über der globalen liegen:
    // Anlagen auf einer Landesgrenze werden global noch einmal gefasst.
    const sumRegions = stats.perRegion.reduce((n: number, r: { cameras: number }) => n + r.cameras, 0);
    if (sumRegions !== stats.totalAfterDedupe) {
      console.log(`Summe der Gebiete: ${sumRegions} (${sumRegions - stats.totalAfterDedupe} grenzüberschreitende Dubletten)`);
    }
  } else {
    console.log('Keine Statistikdatei — build-dataset erneut ausführen.');
  }

  console.log('\n' + '═'.repeat(64));
  console.log('3. STICHPROBE GEGEN BEKANNTE STANDORTE');
  console.log('═'.repeat(64));

  const reference = loadReference();
  if (reference.length === 0) {
    console.log('Keine Referenzstandorte hinterlegt.');
    console.log(`Datei: ${REFERENCE_FILE}`);
    console.log(
      '\nDiese Liste muss von Hand aus einer vom Datensatz UNABHÄNGIGEN Quelle\n' +
      'gefüllt werden (Pressemeldungen, Mitteilungen der Städte, eigene\n' +
      'Beobachtung). Ohne sie ist keine Aussage über die Trefferquote möglich —\n' +
      'die Zahlen aus Teil 2 sagen nur, wie viel in OSM steht, nicht wie viel\n' +
      'davon in der Realität existiert oder fehlt.',
    );
  } else {
    let hits = 0;
    console.log(`${reference.length} Referenzstandorte:\n`);
    for (const ref of reference) {
      let best = Infinity;
      for (const c of all) {
        const d = haversine(ref.lat, ref.lon, c.lat, c.lon);
        if (d < best) best = d;
      }
      const hit = best <= REFERENCE_MATCH_RADIUS_M;
      if (hit) hits++;
      console.log(
        `  ${hit ? 'TREFFER ' : 'FEHLT   '} ${ref.name.padEnd(40)} ` +
        `${best === Infinity ? '—' : `nächster Eintrag ${Math.round(best)} m`}`,
      );
    }
    const rate = ((hits / reference.length) * 100).toFixed(0);
    console.log(`\n  Trefferquote: ${hits}/${reference.length} (${rate} %)`);
    console.log('  Diese Zahl gehört nach DATA.md.');
  }

  console.log('\n' + '═'.repeat(64));
  console.log('4. MENGENABGLEICH GEGEN AMTLICHE ZAHLEN');
  console.log('═'.repeat(64));
  mengenabgleich(data);
}

/**
 * Wie viele Anlagen kennt der Datensatz, verglichen mit einer unabhängigen
 * Zählung?
 *
 * Teil 3 fragt "sind die bekannten Standorte drin?" und braucht dafür
 * Koordinaten. Diese Prüfung fragt das Gröbere und Billigere: Stimmt die
 * Grössenordnung überhaupt? Dafür genügt eine Zahl je Land — und die gibt es
 * für ein paar Länder amtlich.
 *
 * Der Vergleich ist absichtlich nicht scharf. Die Referenzen zählen nicht
 * dasselbe wie OpenStreetMap: mal nur staatliche Strassen, mal ohne einzelne
 * Regionen, mal einen Stichtag vor Monaten. Deshalb wird nichts als "falsch"
 * gemeldet, sondern nur eingeordnet — und die Einschränkung jeder Zahl steht
 * daneben, damit niemand die Abweichung für ein Ergebnis hält.
 */
function mengenabgleich(data: Dataset): void {
  if (!existsSync(COUNTS_FILE)) {
    console.log(`Keine Referenzzahlen hinterlegt.\nDatei: ${COUNTS_FILE}`);
    return;
  }

  const ref = JSON.parse(readFileSync(COUNTS_FILE, 'utf8')) as ReferenceCounts;
  const laender = Object.entries(ref.laender);

  if (laender.length === 0) {
    console.log('Referenzdatei ist leer.');
    return;
  }

  for (const [code, e] of laender) {
    if (!e.quelle || !e.url || !e.zitat) {
      throw new Error(`Referenzzahl für ${code} ohne Quelle, URL oder Zitat`);
    }

    const imDatensatz = data.countries[code]?.count;
    console.log(`\n${code}  ${e.was}`);
    console.log(`  Referenz     ${String(e.anzahl).padStart(7)}  (${e.quelle}, Stand ${e.standDerZahl})`);

    if (imDatensatz === undefined) {
      console.log('  Datensatz          —  dieses Land ist nicht gebaut');
      continue;
    }

    const faktor = imDatensatz / e.anzahl;
    console.log(`  Datensatz    ${String(imDatensatz).padStart(7)}  ${(faktor * 100).toFixed(0)} % der Referenz`);

    // Nur dort eine Erwartung äussern, wo die Referenz das ganze Land abdeckt.
    // Bei einer Untergrenze ist "mehr im Datensatz" kein Widerspruch.
    if (e.landesweit) {
      if (faktor < 0.5) console.log('  -> weniger als die Hälfte. Abdeckungslücke oder anderer Anlagenbegriff.');
      else if (faktor > 1.5) console.log('  -> deutlich mehr als amtlich. Dubletten oder mitgezählte Fremdtypen?');
      else console.log('  -> Grössenordnung passt.');
    } else {
      console.log('  -> Referenz ist eine Untergrenze, kein Landeswert. Nur nach unten aussagekräftig.');
      if (imDatensatz < e.anzahl) console.log('     WENIGER als die Untergrenze — das ist ein Befund.');
    }
    for (const zeile of e.anmerkung ?? []) console.log(`     ${zeile}`);
  }

  const ohne = Object.keys(ref.ohneQuelle ?? {});
  if (ohne.length > 0) {
    console.log(`\nOhne belegte Referenzzahl: ${ohne.join(', ')}`);
    console.log('Begründung je Land steht in reference-counts.json.');
  }
}

function loadReference(): ReferencePoint[] {
  if (!existsSync(REFERENCE_FILE)) return [];
  const parsed = JSON.parse(readFileSync(REFERENCE_FILE, 'utf8'));
  const points: ReferencePoint[] = parsed.locations ?? [];
  for (const p of points) {
    if (typeof p.lat !== 'number' || typeof p.lon !== 'number') {
      throw new Error(`Referenzstandort ohne gültige Koordinaten: ${JSON.stringify(p)}`);
    }
    if (!p.source) {
      throw new Error(`Referenzstandort ohne Quellenangabe: ${p.name}`);
    }
  }
  return points;
}

main();
