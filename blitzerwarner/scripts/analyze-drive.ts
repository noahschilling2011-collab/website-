#!/usr/bin/env node
/**
 * Auswertung einer Testfahrt — Phasen 2, 4 und 5 in einem Befehl.
 *
 *   npx tsx scripts/analyze-drive.ts fahrt.csv
 *
 * Liest eine Datei, die der Fahrtenschreiber der App ausgegeben hat
 * (Einstellungen -> Diagnose -> Fahrt aufzeichnen, danach Info -> teilen).
 *
 * Beantwortet die drei Fragen, die nur im Auto messbar sind:
 *  - Phase 2: Lief das Tracking 20 Minuten lückenlos? -> Lückenliste
 *  - Phase 4: Wie oft wurde gewarnt, und in welchem Modus?
 *  - Phase 5: Wie hat sich die Akku-Strategie verhalten, und was kostete sie?
 *
 * Das Skript rechnet nichts schön: Es zählt, was in der Datei steht. Fehlen
 * die Akkuwerte im Kopf, sagt es das, statt eine Zahl zu erfinden.
 */
import { readFileSync } from 'node:fs';

const SPALTEN = [
  't_iso', 'lat', 'lon', 'speed_ms', 'accuracy_m', 'course_deg',
  'strategie', 'warnmodus', 'naechste_m', 'gewarnt', 'abstand_ms', 'luecke',
] as const;

type Spalte = (typeof SPALTEN)[number];
type Zeile = Record<Spalte, string>;

const KOPF_PRAEFIX = '#';

/** Eine Zahl aus der Zelle, oder null bei leerer Zelle. */
function zahl(zelle: string): number | null {
  if (zelle === '') return null;
  const n = Number(zelle);
  return Number.isFinite(n) ? n : null;
}

function lies(pfad: string): { kopf: string[]; zeilen: Zeile[] } {
  const text = readFileSync(pfad, 'utf8');
  const alle = text.split('\n').filter((z) => z.trim() !== '');

  const kopf = alle
    .filter((z) => z.startsWith(KOPF_PRAEFIX))
    .map((z) => z.slice(KOPF_PRAEFIX.length).trim());
  const tabelle = alle.filter((z) => !z.startsWith(KOPF_PRAEFIX));

  const kopfzeile = tabelle[0];
  if (kopfzeile === undefined) {
    throw new Error('Die Datei enthält keine Tabelle, nur Kopfzeilen.');
  }
  const spalten = kopfzeile.split(',');

  // Die Spaltenreihenfolge ist der Vertrag zu app/src/core/fahrtprotokoll.ts.
  // Sie zu prüfen statt zu unterstellen ist der Unterschied zwischen einer
  // Fehlermeldung und einer stillschweigend falschen Auswertung.
  const fehlend = SPALTEN.filter((s) => !spalten.includes(s));
  if (fehlend.length > 0) {
    throw new Error(
      `Spalten fehlen: ${fehlend.join(', ')}\n` +
      `Gelesen wurde: ${spalten.join(', ')}\n` +
      'Stammt die Datei aus einer anderen Version des Fahrtenschreibers?',
    );
  }

  const zeilen: Zeile[] = [];
  for (const roh of tabelle.slice(1)) {
    const felder = roh.split(',');
    const zeile = {} as Zeile;
    for (const spalte of SPALTEN) {
      zeile[spalte] = felder[spalten.indexOf(spalte)] ?? '';
    }
    zeilen.push(zeile);
  }
  return { kopf, zeilen };
}

/** Zahl aus einer Kopfzeile wie "Akku bei Start (%): 87". */
function ausKopf(kopf: string[], praefix: string): number | null {
  const zeile = kopf.find((z) => z.startsWith(praefix));
  if (zeile === undefined) return null;
  return zahl(zeile.slice(praefix.length).replace(/[^\d.,-]/g, '').replace(',', '.'));
}

function balken(anteil: number, breite = 28): string {
  const voll = Math.round(anteil * breite);
  return '█'.repeat(voll) + '·'.repeat(breite - voll);
}

function main(): void {
  const pfad = process.argv[2];
  if (pfad === undefined) {
    console.error(
      'Kein Pfad angegeben.\n' +
      '  npx tsx scripts/analyze-drive.ts fahrt.csv\n\n' +
      'Die Datei kommt aus der App: Einstellungen -> Diagnose -> Fahrt\n' +
      'aufzeichnen einschalten, fahren, danach Info -> Fahrtprotokoll teilen.',
    );
    process.exit(1);
  }

  const { kopf, zeilen } = lies(pfad);
  if (zeilen.length === 0) {
    console.error('Die Datei enthält keine Positionen.');
    process.exit(1);
  }

  const erste = zeilen[0]!;
  const letzte = zeilen[zeilen.length - 1]!;
  const startMs = Date.parse(erste.t_iso);
  const endeMs = Date.parse(letzte.t_iso);
  const dauerMin = (endeMs - startMs) / 60000;
  const dauerStunden = dauerMin / 60;

  console.log('═'.repeat(72));
  console.log('Fahrtauswertung');
  console.log('═'.repeat(72));
  console.log(`Datei:       ${pfad}`);
  console.log(`Start:       ${erste.t_iso}`);
  console.log(`Ende:        ${letzte.t_iso}`);
  console.log(`Dauer:       ${dauerMin.toFixed(1)} min`);
  console.log(`Positionen:  ${zeilen.length}`);

  // --- Phase 2: Lücken ----------------------------------------------------

  const abstaende = zeilen.map((z) => zahl(z.abstand_ms)).filter((n): n is number => n !== null);
  const luecken = zeilen
    .map((z, i) => ({ z, i }))
    .filter(({ z }) => z.luecke === '1');

  console.log(`\n${'─'.repeat(72)}`);
  console.log('PHASE 2 — Lückenloses Tracking');
  console.log('─'.repeat(72));

  if (abstaende.length > 0) {
    const sortiert = [...abstaende].sort((a, b) => a - b);
    const median = sortiert[Math.floor(sortiert.length / 2)]!;
    console.log(
      `Fixabstand:  Median ${(median / 1000).toFixed(1)} s, ` +
      `Maximum ${(Math.max(...abstaende) / 1000).toFixed(1)} s`,
    );
  }

  if (luecken.length === 0) {
    console.log('Lücken:      keine über der Schwelle');
  } else {
    console.log(`Lücken:      ${luecken.length}`);
    for (const { z, i } of luecken) {
      const ms = zahl(z.abstand_ms) ?? 0;
      const seitStart = (Date.parse(z.t_iso) - startMs) / 60000;
      console.log(
        `  bei ${seitStart.toFixed(1).padStart(6)} min  ` +
        `${(ms / 1000).toFixed(1).padStart(6)} s  ` +
        `Zeile ${i + 1}, Strategie ${z.strategie}`,
      );
    }
    const gesamt = luecken.reduce((n, { z }) => n + (zahl(z.abstand_ms) ?? 0), 0);
    console.log(
      `Summe der Lücken: ${(gesamt / 1000).toFixed(0)} s ` +
      `(${((gesamt / (endeMs - startMs)) * 100).toFixed(1)} % der Fahrt)`,
    );
  }

  // Die Zusage aus dem README, wörtlich geprüft.
  const ZIEL_MIN = 20;
  if (dauerMin < ZIEL_MIN) {
    console.log(
      `\nHINWEIS: Die Fahrt ist mit ${dauerMin.toFixed(1)} min kürzer als die ` +
      `geforderten ${ZIEL_MIN} min. Phase 2 ist damit nicht belegt.`,
    );
  } else if (luecken.length === 0) {
    console.log(`\nPhase 2 erfüllt: ${dauerMin.toFixed(1)} min ohne Lücke über der Schwelle.`);
  } else {
    console.log(
      `\nPhase 2 NICHT erfüllt: ${luecken.length} Lücke(n) in ${dauerMin.toFixed(1)} min.`,
    );
  }

  // --- Phase 4: Warnungen und Modi ----------------------------------------

  console.log(`\n${'─'.repeat(72)}`);
  console.log('PHASE 4 — Warnungen und Länder-Gate');
  console.log('─'.repeat(72));

  const gewarnt = zeilen.filter((z) => z.gewarnt === '1');
  console.log(`Warnungen:   ${gewarnt.length}`);
  for (const z of gewarnt) {
    const seitStart = (Date.parse(z.t_iso) - startMs) / 60000;
    const v = zahl(z.speed_ms);
    console.log(
      `  bei ${seitStart.toFixed(1).padStart(6)} min  Modus ${z.warnmodus.padEnd(6)} ` +
      `Distanz ${(z.naechste_m || '—').padStart(5)} m  ` +
      `Tempo ${v === null ? '—' : (v * 3.6).toFixed(0)} km/h`,
    );
  }

  const nachModus = new Map<string, number>();
  for (const z of zeilen) nachModus.set(z.warnmodus, (nachModus.get(z.warnmodus) ?? 0) + 1);
  console.log('\nZeitanteil je Warnmodus:');
  for (const [modus, n] of [...nachModus].sort((a, b) => b[1] - a[1])) {
    const anteil = n / zeilen.length;
    console.log(`  ${modus.padEnd(8)} ${balken(anteil)} ${(anteil * 100).toFixed(1).padStart(5)} %`);
  }

  // --- Phase 5: Akku ------------------------------------------------------

  console.log(`\n${'─'.repeat(72)}`);
  console.log('PHASE 5 — Akku-Strategie');
  console.log('─'.repeat(72));

  const nachStrategie = new Map<string, number>();
  for (const z of zeilen) nachStrategie.set(z.strategie, (nachStrategie.get(z.strategie) ?? 0) + 1);
  for (const [modus, n] of [...nachStrategie].sort((a, b) => b[1] - a[1])) {
    const anteil = n / zeilen.length;
    console.log(`  ${modus.padEnd(12)} ${balken(anteil)} ${(anteil * 100).toFixed(1).padStart(5)} %`);
  }

  const genauigkeiten = zeilen
    .map((z) => zahl(z.accuracy_m))
    .filter((n): n is number => n !== null);
  if (genauigkeiten.length > 0) {
    const mittel = genauigkeiten.reduce((a, b) => a + b, 0) / genauigkeiten.length;
    console.log(
      `\nGenauigkeit: Mittel ${mittel.toFixed(1)} m, ` +
      `Maximum ${Math.max(...genauigkeiten).toFixed(1)} m ` +
      `(${genauigkeiten.length} von ${zeilen.length} Positionen mit Angabe)`,
    );
  }

  const akkuStart = ausKopf(kopf, 'Akku bei Start (%):');
  const akkuEnde = ausKopf(kopf, 'Akku bei Ende (%):');

  if (akkuStart === null || akkuEnde === null) {
    console.log(
      '\nAkkuverbrauch: nicht auswertbar. Die Zeilen "Akku bei Start (%)" und\n' +
      '"Akku bei Ende (%)" im Kopf der Datei sind leer. Sie sind vom Fahrer\n' +
      'auszufüllen — der Wert steht in den Systemeinstellungen.',
    );
  } else if (dauerStunden <= 0) {
    console.log('\nAkkuverbrauch: die Fahrt hat keine messbare Dauer.');
  } else {
    const proStunde = (akkuStart - akkuEnde) / dauerStunden;
    const ZIEL_PROZENT_PRO_STUNDE = 3;
    console.log(
      `\nAkku:        ${akkuStart} % -> ${akkuEnde} % in ${dauerMin.toFixed(1)} min ` +
      `= ${proStunde.toFixed(1)} %/h`,
    );
    console.log(
      proStunde <= ZIEL_PROZENT_PRO_STUNDE
        ? `Ziel erfüllt: unter ${ZIEL_PROZENT_PRO_STUNDE} %/h.`
        : `Ziel VERFEHLT: über ${ZIEL_PROZENT_PRO_STUNDE} %/h.`,
    );
    if (dauerMin < 30) {
      console.log(
        'Vorsicht bei der Hochrechnung: Der Akkustand ist in Prozentschritten\n' +
        'abgelesen. Bei einer kurzen Fahrt schlägt ein einzelner Prozentpunkt\n' +
        'stark durch. Für eine belastbare Zahl mindestens eine Stunde fahren.',
      );
    }
  }

  // Der Ringpuffer könnte übergelaufen sein; dann fehlt der Anfang.
  const warnung = kopf.find((z) => z.includes('ACHTUNG'));
  if (warnung !== undefined) console.log(`\n${warnung}`);

  console.log(`\n${'═'.repeat(72)}`);
}

main();
