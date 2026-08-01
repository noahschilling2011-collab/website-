#!/usr/bin/env node
/**
 * Was tatsächlich im ausgelieferten Bündel landet.
 *
 *   npm run check-bundle            # beide Plattformen
 *   npm run check-bundle -- --ios   # nur eine
 *
 * WARUM DAS EIN EIGENES SKRIPT IST UND KEIN TEST
 *
 * Es baut wirklich. `expo export` braucht rund zwanzig Sekunden je Plattform
 * und schreibt ein paar Megabyte auf die Platte — das gehört nicht in ein
 * `npm test`, das man zwanzigmal am Tag laufen lässt. Es gehört vor eine
 * Auslieferung.
 *
 * WAS GEPRÜFT WIRD
 *
 *  1. Keine Source Maps. Eine mitgelieferte .map macht aus dem übersetzten
 *     Bündel wieder lesbaren Quelltext mit Kommentaren und Dateinamen. Bei
 *     einer App ohne Server ist das kein Sicherheitsloch, aber es ist der
 *     Unterschied zwischen "ausgeliefert" und "offengelegt".
 *  2. Der Datensatz ist wirklich drin. Metro legt `require()`-tes JSON in das
 *     Bündel; wenn das eines Tages nicht mehr passiert, startet die App ohne
 *     Daten — und das fällt erst auf dem Gerät auf.
 *  3. Die Grösse. Nicht als Note, sondern als Zahl, die man mit dem letzten
 *     Lauf vergleichen kann. Der Datensatz ist der grosse Posten, und er
 *     wächst mit jedem Land.
 *
 * GEMESSEN AM 2026-08-01, Expo SDK 52 / RN 0.76.5, beide Plattformen:
 *
 *   Bündel    4,04 MB (iOS) / 4,05 MB (Android), Hermes-Bytecode
 *   Module    613 / 612   (der Entwicklungsbau hat 721 — Dev-Code fällt weg)
 *   .map      keine
 *   Datensatz eingebettet (osmTimestamp im Bündel gefunden)
 *
 * GEGENPROBE, damit die OKs etwas bedeuten
 *
 * Mit `expo export --source-maps` entsteht neben dem Bündel eine .map von
 * 6,42 MB — der Test darauf greift also. Der zweite Test, auf
 * `sourceMappingURL` im Bündel, hat dabei NICHT angeschlagen: Hermes schreibt
 * die Referenz nicht in den Bytecode. Er bleibt trotzdem drin, weil er den
 * anderen Fall abdeckt — ein Bündel ohne Hermes, also einfaches JavaScript.
 * Dass er in der Gegenprobe still blieb, steht hier, damit ihn niemand für
 * einen Beweis hält, der er nicht ist.
 *
 * WAS NICHT GEPRÜFT WIRD
 *
 * Ob das fertige IPA/AAB dasselbe enthält. `expo export` erzeugt das
 * JS-Bündel, nicht das native Paket — für die Frage nach Source Maps ist das
 * die richtige Stelle, denn genau hier entstehen sie. Der native Build legt
 * eigene Symboldateien an; die gehen an Apple und Google, nicht an den Nutzer.
 *
 * Und: Der Bytecode ist kein Quelltext, aber er ist auch keine Verschlüsselung.
 * Bezeichner und Eigenschaftsnamen stehen als Zeichenketten darin — nachgesehen
 * und bestätigt für `warnmodus` und `MINDESTABSTAND_GRENZE_M`. Kommentare sind
 * weg. Wer "niemand sieht deinen Code" verspricht, verspricht zu viel; ohne
 * Source Map fehlt die Zuordnung zu Dateien, Zeilen und Begründungen.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const WURZEL = join(HIER, '..');
const APP = join(WURZEL, 'app');

/** Alle Dateien unter einem Verzeichnis, rekursiv. */
function alleDateien(wurzel: string): string[] {
  const raus: string[] = [];
  for (const name of readdirSync(wurzel)) {
    const pfad = join(wurzel, name);
    if (statSync(pfad).isDirectory()) raus.push(...alleDateien(pfad));
    else raus.push(pfad);
  }
  return raus;
}

type Befund = {
  readonly plattform: string;
  readonly bundleBytes: number;
  readonly module: number | null;
  readonly sourceMaps: string[];
  readonly sourceMappingUrl: boolean;
  readonly datensatzDrin: boolean;
  readonly dateien: number;
};

/**
 * Eine Plattform exportieren und das Ergebnis ausmessen.
 *
 * Der Datensatz wird nicht über seine Grösse nachgewiesen, sondern über einen
 * Wert, den es sonst nirgends gibt: den OSM-Zeitstempel. Er steht als
 * Zeichenkette im Bündel, wenn das JSON eingebettet wurde — und nur dann.
 */
function pruefe(plattform: 'ios' | 'android'): Befund {
  const ziel = mkdtempSync(join(tmpdir(), `static-export-${plattform}-`));
  let module: number | null = null;

  try {
    const ausgabe = execFileSync(
      'npx',
      ['expo', 'export', '--platform', plattform, '--output-dir', ziel],
      { cwd: APP, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    );
    const treffer = /\((\d+) modules\)/.exec(ausgabe);
    if (treffer) module = Number(treffer[1]);

    const dateien = alleDateien(ziel);
    const sourceMaps = dateien
      .filter((d) => extname(d) === '.map')
      .map((d) => d.slice(ziel.length + 1));

    const bundles = dateien.filter((d) => ['.hbc', '.js'].includes(extname(d)));
    const bundleBytes = bundles.reduce((s, d) => s + statSync(d).size, 0);

    const inhalt = Buffer.concat(bundles.map((d) => readFileSync(d)));
    const sourceMappingUrl = inhalt.includes(Buffer.from('sourceMappingURL'));

    const datensatz = JSON.parse(
      readFileSync(join(APP, 'assets', 'data', 'cameras.json'), 'utf8'),
    ) as { osmTimestamp: string };
    const datensatzDrin = inhalt.includes(Buffer.from(datensatz.osmTimestamp));

    return {
      plattform, bundleBytes, module, sourceMaps, sourceMappingUrl,
      datensatzDrin, dateien: dateien.length,
    };
  } finally {
    rmSync(ziel, { recursive: true, force: true });
  }
}

function mb(bytes: number): string {
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function main(): void {
  const argumente = process.argv.slice(2);
  const plattformen: ('ios' | 'android')[] =
    argumente.includes('--ios') ? ['ios']
      : argumente.includes('--android') ? ['android']
        : ['ios', 'android'];

  if (!existsSync(join(APP, 'assets', 'data', 'cameras.json'))) {
    console.error(
      'assets/data/cameras.json fehlt. Erst `npm run sync-dataset` in app/,\n' +
      'sonst exportiert dieses Skript eine App ohne Daten.',
    );
    process.exit(1);
  }

  let fehler = 0;

  for (const plattform of plattformen) {
    process.stdout.write(`${plattform} … `);
    const b = pruefe(plattform);
    console.log('fertig\n');

    console.log(`  Bündel            ${mb(b.bundleBytes)}`);
    console.log(`  Module            ${b.module ?? '?'}`);
    console.log(`  Dateien im Export ${b.dateien}`);

    const zeile = (name: string, gut: boolean, text: string) => {
      console.log(`  ${name.padEnd(18)}${text}  ${gut ? 'OK' : 'FEHLER'}`);
      if (!gut) fehler++;
    };

    zeile('Source Maps', b.sourceMaps.length === 0,
      b.sourceMaps.length === 0 ? 'keine' : b.sourceMaps.join(', '));
    zeile('sourceMappingURL', !b.sourceMappingUrl,
      b.sourceMappingUrl ? 'im Bündel' : 'nicht im Bündel');
    zeile('Datensatz', b.datensatzDrin,
      b.datensatzDrin ? 'eingebettet' : 'FEHLT im Bündel');
    console.log();
  }

  if (fehler > 0) {
    console.error(`${fehler} Punkt(e) nicht in Ordnung.`);
    process.exit(1);
  }
  console.log('Alles wie erwartet.');
}

main();
