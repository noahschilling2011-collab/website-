#!/usr/bin/env node
/**
 * Die Rechtstexte als Markdown erzeugen.
 *
 *   npx tsx scripts/make-legal-docs.ts
 *
 * WOZU ZWEI FASSUNGEN
 *
 * Die Texte müssen an zwei Orten stehen: IN der App, damit der Nutzer sie
 * ohne Netz lesen kann, und AUSSERHALB unter einer aufrufbaren Adresse, weil
 * Apple und Google das bei der Einreichung verlangen.
 *
 * Beide von Hand zu pflegen wäre der sichere Weg in zwei Fassungen, die
 * auseinanderlaufen — und von zwei Datenschutzerklärungen ist mindestens eine
 * falsch. Deshalb ist app/src/rechtstexte.ts die einzige Quelle, und dieses
 * Skript erzeugt daraus die Markdown-Dateien.
 *
 * tests/rechtstexte.test.ts prüft, dass die erzeugten Dateien zum aktuellen
 * Stand passen. Wer den Text ändert und dieses Skript vergisst, bekommt einen
 * roten Test statt einer veralteten Erklärung im Netz.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  AUSZUFUELLEN,
  DATEINAME,
  NACH_SCHLUESSEL,
  RECHTSSTAND,
  hatLuecken,
  type Dokument,
  type DokumentSchluessel,
} from '../app/src/rechtstexte.js';

const HIER = dirname(fileURLToPath(import.meta.url));
const WURZEL = join(HIER, '..');
const ZIEL = join(WURZEL, 'rechtliches');

/**
 * Ein Dokument als Markdown.
 *
 * Bewusst schlicht: Überschrift, Stand, Vorspann, dann die Abschnitte. Kein
 * Inhaltsverzeichnis, keine Ankerlinks. Diese Dateien werden gelesen, nicht
 * durchsucht, und jede Zutat mehr ist eine Stelle, an der die erzeugte
 * Fassung von der App abweichen kann.
 */
export function alsMarkdown(dokument: Dokument): string {
  const zeilen: string[] = [
    `# ${dokument.titel}`,
    '',
    `**Static** — Offline-Warner für stationäre Blitzer`,
    '',
    `Stand: ${dokument.stand}`,
    '',
    dokument.vorspann,
    '',
    '> Diese Datei wird aus `app/src/rechtstexte.ts` erzeugt.',
    '> Änderungen gehören dorthin, sonst sind sie beim nächsten Lauf weg.',
    '',
  ];

  if (hatLuecken(dokument)) {
    zeilen.push(
      `> **Noch nicht vollständig.** Die mit \`${AUSZUFUELLEN}\` markierten`,
      '> Stellen kann nur der Betreiber ausfüllen. Solange sie offen sind,',
      '> ist dieses Dokument nicht veröffentlichungsreif.',
      '',
    );
  }

  for (const abschnitt of dokument.abschnitte) {
    zeilen.push(`## ${abschnitt.titel}`, '');
    for (const absatz of abschnitt.absaetze) zeilen.push(absatz, '');
  }

  zeilen.push(
    '---',
    '',
    'Keine Rechtsberatung. Diese Texte beschreiben nach bestem Wissen, was die',
    'App tut. Ob die Formulierungen den Anforderungen genügen, muss vor einer',
    'Veröffentlichung jemand mit einschlägiger Qualifikation prüfen.',
  );

  return zeilen.join('\n') + '\n';
}

/** Alle Dokumente erzeugen und melden, was noch offen ist. */
export function erzeugeAlle(zielVerzeichnis: string): { geschrieben: string[]; offen: string[] } {
  const geschrieben: string[] = [];
  const offen: string[] = [];

  for (const schluessel of Object.keys(NACH_SCHLUESSEL) as DokumentSchluessel[]) {
    const dokument = NACH_SCHLUESSEL[schluessel];
    const pfad = join(zielVerzeichnis, DATEINAME[schluessel]);
    writeFileSync(pfad, alsMarkdown(dokument));
    geschrieben.push(DATEINAME[schluessel]);
    if (hatLuecken(dokument)) offen.push(DATEINAME[schluessel]);
  }

  return { geschrieben, offen };
}

// --- Hauptlauf ------------------------------------------------------------

function main(): void {
  mkdirSync(ZIEL, { recursive: true });

  const { geschrieben, offen } = erzeugeAlle(ZIEL);

  for (const name of geschrieben) {
    const bytes = readFileSync(join(ZIEL, name)).length;
    console.log(`${name.padEnd(28)} ${(bytes / 1024).toFixed(1).padStart(5)} KB`);
  }

  console.log(`\n${geschrieben.length} Dateien in ${ZIEL}`);
  console.log(`Stand: ${RECHTSSTAND}`);

  if (offen.length > 0) {
    console.log(
      `\nNOCH NICHT VEROEFFENTLICHUNGSREIF: ${offen.join(', ')}\n` +
      `Diese Dateien enthalten ${AUSZUFUELLEN}-Stellen. Sie kann nur der\n` +
      'Betreiber fuellen — Name und ladungsfaehige Anschrift lassen sich\n' +
      'nicht erfinden. Bis dahin lehnen beide App-Stores die Einreichung ab.',
    );
  }
}

// Nur ausführen, wenn direkt aufgerufen — der Test importiert die Funktionen.
if (process.argv[1] !== undefined && import.meta.url.endsWith(process.argv[1].split('/').pop() ?? '')) {
  main();
}
