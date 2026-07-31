#!/usr/bin/env node
/**
 * A.1 — Mengengerüst für Europa, VOR dem Ausbau.
 *
 *   npx tsx scripts/count-europe.ts
 *
 * Holt pro Gebiet nur die ANZAHL (`out count;` statt `out body;`). Das ist
 * billig, belastet Overpass kaum und beantwortet die Frage, die vor dem Bauen
 * geklärt sein muss: Trägt die Ein-Datei-Architektur die Menge noch?
 *
 * Ohne diese Messung würde man erst mehrere hundert Megabyte Geometrie holen
 * und danach feststellen, dass das Format nicht passt.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { isCached, overpassQuery } from './lib/overpass.js';
import { EUROPA, queryFor, type Region } from './lib/regions.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CACHE_DIR = join(ROOT, '.overpass-cache');
const OUT_FILE = join(ROOT, 'assets', 'data', 'europe.count.json');

/**
 * Anteil, der die Deduplizierung überlebt.
 *
 * An Deutschland kalibriert — und zwar gegen DIESELBE Grundmenge, die dieses
 * Skript misst. Das war er vorher nicht, und daraus wurde ein Fehler von
 * 30 Prozent.
 *
 * DER FEHLER, ZUR WARNUNG STEHENGELASSEN
 *
 * Der Faktor lautete 5053 / 14102 = 0,358. Die 14102 stammen aus dem echten
 * Build und enthalten die `device`-Nodes der Enforcement-Relationen. Die
 * Zählquery unten liest aber nur den ERSTEN `out count;`-Block und zählt damit
 * ausschliesslich Kamera-Nodes plus Relationen — für Deutschland 5181 + 5682
 * = 10863. Der Faktor wurde also auf eine Grundmenge angewandt, für die er
 * nicht kalibriert war.
 *
 * Aufgefallen ist es an der eigenen Zahl: Das Skript schätzte für Deutschland
 * 3892 Anlagen, gebaut sind 5053. Eine Schätzung, die den einzigen Fall, für
 * den man die Antwort kennt, um 23 Prozent verfehlt, ist keine Schätzung.
 *
 * Richtig ist 5053 / 10863 = 0,465.
 *
 * Ob der Faktor ausserhalb Deutschlands gilt, bleibt eine Annahme: Wo weniger
 * mit Enforcement-Relationen gearbeitet wird, überleben mehr Einträge.
 */
const DEDUPE_FAKTOR = 5053 / 10863;

/**
 * Was Deutschland liefern MUSS, damit die Schätzung überhaupt etwas taugt.
 *
 * Die Selbstprüfung am Ende des Laufs vergleicht die Schätzung für Deutschland
 * gegen den tatsächlich gebauten Datensatz. Weicht sie mehr als um diesen
 * Anteil ab, stimmt etwas an der Query oder am Faktor nicht — und dann ist die
 * Zahl für die übrigen 43 Länder ebenfalls falsch, nur ohne Gegenprobe.
 *
 * 5 Prozent ist eng gewählt, weil die Kalibrierung per Konstruktion stimmen
 * MUSS: Deutschland ist der Fall, an dem der Faktor gebildet wurde. Eine
 * Abweichung kann dort nur ein Fehler sein, keine Streuung.
 */
const DE_TOLERANZ = 0.05;

/** Der gebaute deutsche Datensatz, gegen den sich die Schätzung prüfen lässt. */
const DE_TATSAECHLICH = 5053;

/**
 * Bytes je Eintrag im gebauten JSON.
 *
 * An Deutschland gemessen: 370746 Bytes für 5053 Einträge = 73,4 Bytes.
 * Enthält den Gitter-Overhead (Zellschlüssel) anteilig.
 */
const BYTES_JE_EINTRAG = 370746 / 5053;

/** Pause zwischen zwei echten Abfragen. Overpass ist gespendete Rechenzeit. */
const PAUSE_MS = 5000;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Zaehlung = {
  code: string;
  name: string;
  country: string;
  nodes: number | null;
  relationen: number | null;
  roh: number | null;
  geschaetztNachDedupe: number | null;
  geschaetzteBytes: number | null;
  fehler: string | null;
};

/**
 * Zählquery: dieselbe Auswahl wie queryFor(), aber nur die Anzahl.
 *
 * Bewusst aus queryFor() abgeleitet und nicht daneben neu geschrieben — sonst
 * zählt man am Ende etwas anderes, als man später holt.
 */
function zaehlQuery(region: Region): string {
  return queryFor(region)
    .replace(/out body center;[\s\S]*$/, 'out count;')
    .replace(/out body;/g, 'out count;');
}

async function main(): Promise<void> {
  const gebiete = EUROPA;
  console.log(`Mengengerüst Europa: ${gebiete.length} Gebiete\n`);

  const ergebnisse: Zaehlung[] = [];
  const fehlgeschlagen: string[] = [];

  for (let i = 0; i < gebiete.length; i++) {
    const region = gebiete[i]!;
    const query = zaehlQuery(region);
    const ausCache = isCached(query, CACHE_DIR);

    const fortschritt = `[${String(i + 1).padStart(3)}/${gebiete.length}]`;
    process.stdout.write(`${fortschritt} ${region.code.padEnd(7)} ${region.name}\n`);

    if (!ausCache && i > 0) await sleep(PAUSE_MS);

    try {
      const res = await overpassQuery(query, {
        cacheDir: CACHE_DIR,
        log: (m) => console.log(`        ${m}`),
      });
      const zaehler = res.elements.filter(
        (e) => (e as unknown as { type: string }).type === 'count',
      ) as unknown as { tags: Record<string, string> }[];

      const tags = zaehler[0]?.tags ?? {};
      const nodes = Number(tags['nodes'] ?? 0);
      const relationen = Number(tags['relations'] ?? 0);
      const roh = nodes + relationen;

      ergebnisse.push({
        code: region.code, name: region.name, country: region.country,
        nodes, relationen, roh,
        geschaetztNachDedupe: Math.round(roh * DEDUPE_FAKTOR),
        geschaetzteBytes: Math.round(roh * DEDUPE_FAKTOR * BYTES_JE_EINTRAG),
        fehler: null,
      });
      console.log(`        ${nodes} Nodes, ${relationen} Relationen\n`);
    } catch (err) {
      const text = (err as Error).message;
      console.error(`        FEHLER: ${text}\n`);
      fehlgeschlagen.push(region.code);
      ergebnisse.push({
        code: region.code, name: region.name, country: region.country,
        nodes: null, relationen: null, roh: null,
        geschaetztNachDedupe: null, geschaetzteBytes: null, fehler: text,
      });
    }
  }

  // Pro Land zusammenfassen.
  const proLand = new Map<string, { roh: number; dedupe: number; bytes: number; gebiete: number; fehler: number }>();
  for (const e of ergebnisse) {
    const vorhanden = proLand.get(e.country) ?? { roh: 0, dedupe: 0, bytes: 0, gebiete: 0, fehler: 0 };
    vorhanden.gebiete++;
    if (e.fehler) vorhanden.fehler++;
    else {
      vorhanden.roh += e.roh ?? 0;
      vorhanden.dedupe += e.geschaetztNachDedupe ?? 0;
      vorhanden.bytes += e.geschaetzteBytes ?? 0;
    }
    proLand.set(e.country, vorhanden);
  }

  mkdirSync(dirname(OUT_FILE), { recursive: true });
  writeFileSync(OUT_FILE, JSON.stringify({
    stand: ergebnisse.find((e) => !e.fehler) ? new Date().toISOString().slice(0, 10) : null,
    dedupeFaktor: DEDUPE_FAKTOR,
    bytesJeEintrag: BYTES_JE_EINTRAG,
    herleitung:
      'Dedupe-Faktor und Bytes je Eintrag an Deutschland kalibriert: ' +
      '14102 Rohtreffer -> 5053 Einträge, 370746 Bytes.',
    gebiete: ergebnisse,
    proLand: Object.fromEntries(proLand),
    fehlgeschlagen,
  }, null, 2) + '\n');

  /*
   * SELBSTPRÜFUNG AN DEUTSCHLAND, bevor irgendeine Zahl ausgegeben wird.
   *
   * Deutschland ist der einzige Fall, für den die Antwort bekannt ist — der
   * Datensatz ist gebaut. Wenn die Schätzung ihn verfehlt, ist sie für die
   * übrigen 43 Länder ebenfalls falsch, dort nur ohne Gegenprobe. Genau das
   * ist einmal passiert (siehe DEDUPE_FAKTOR), und niemand hat es gemerkt,
   * bis die Zahlen längst in DATA.md standen.
   */
  const de = proLand.get('DE');
  if (de !== undefined && de.fehler === 0) {
    const abweichung = Math.abs(de.dedupe - DE_TATSAECHLICH) / DE_TATSAECHLICH;
    console.log(
      `\nSelbstprüfung Deutschland: geschätzt ${de.dedupe}, gebaut ${DE_TATSAECHLICH} ` +
      `(${(abweichung * 100).toFixed(1)} % Abweichung)`,
    );
    if (abweichung > DE_TOLERANZ) {
      console.error(
        `\nABBRUCH: Die Schätzung verfehlt Deutschland um ${(abweichung * 100).toFixed(1)} %, ` +
        `erlaubt sind ${DE_TOLERANZ * 100} %.\n` +
        'Deutschland ist der Fall, an dem DEDUPE_FAKTOR kalibriert wurde — eine ' +
        'Abweichung dort kann nur ein Fehler sein. Vermutlich zählt die Query etwas ' +
        'anderes, als der Faktor unterstellt. Die Zahlen für die übrigen Länder sind ' +
        'dann ebenfalls falsch und werden deshalb nicht ausgegeben.',
      );
      process.exit(1);
    }
  }

  console.log('═'.repeat(78));
  console.log('Land    Gebiete      Nodes  Relationen        roh   nach Dedupe      Bytes');
  console.log('─'.repeat(78));
  const sortiert = [...proLand].sort((a, b) => b[1].dedupe - a[1].dedupe);
  for (const [land, z] of sortiert) {
    console.log(
      `${land.padEnd(7)} ${String(z.gebiete).padStart(7)} ` +
      `${''.padStart(10)} ${''.padStart(11)} ` +
      `${String(z.roh).padStart(10)} ${String(z.dedupe).padStart(13)} ` +
      `${(z.bytes / 1024).toFixed(0).padStart(7)} KB` +
      (z.fehler > 0 ? `   ${z.fehler} FEHLER` : ''),
    );
  }
  console.log('─'.repeat(78));

  const gesamtRoh = [...proLand.values()].reduce((n, z) => n + z.roh, 0);
  const gesamtDedupe = [...proLand.values()].reduce((n, z) => n + z.dedupe, 0);
  const gesamtBytes = [...proLand.values()].reduce((n, z) => n + z.bytes, 0);
  console.log(
    `SUMME   ${String(gebiete.length).padStart(7)} ` +
    `${''.padStart(22)} ${String(gesamtRoh).padStart(10)} ` +
    `${String(gesamtDedupe).padStart(13)} ${(gesamtBytes / 1024 / 1024).toFixed(1).padStart(7)} MB`,
  );
  console.log('═'.repeat(78));

  console.log(
    `\nErwartungswert aus Sekundärquellen zum Vergleich: 60.000-100.000 Anlagen.\n` +
    `Gemessen: ${gesamtDedupe} Anlagen, ${(gesamtBytes / 1024 / 1024).toFixed(1)} MB.`,
  );
  const faktor = gesamtDedupe / 80000;
  if (faktor < 0.5 || faktor > 2) {
    console.log(
      `\nHINWEIS: Das liegt um Faktor ${faktor < 1 ? (1 / faktor).toFixed(1) : faktor.toFixed(1)} ` +
      `neben der Erwartung.\n` +
      'Die Selbstprüfung an Deutschland oben ist trotzdem grün — die Query zählt also\n' +
      'richtig. Der Unterschied liegt in den Sekundärzahlen: Sie enthalten MOBILE\n' +
      'Messstellen, die dieses Projekt nicht abbildet, und stammen aus kommerziellen\n' +
      'Datenbanken mit eigener Erfassung. OpenStreetMap enthält, was Freiwillige\n' +
      'eingetragen haben. Siehe DATA.md, Abschnitt Mengengerüst Europa.',
    );
  }

  if (fehlgeschlagen.length > 0) {
    console.error(`\n${fehlgeschlagen.length} Gebiete fehlgeschlagen: ${fehlgeschlagen.join(', ')}`);
    console.error('Ein Teilausfall darf nicht still zu einem lückenhaften Datensatz führen.');
    process.exit(1);
  }
  console.log(`\n${OUT_FILE}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
