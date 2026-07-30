/**
 * Kein Konfigblock ohne Leser.
 *
 * Der Anlass: `SPEED_LIMIT_ALERT`, `MAP_MATCHING` und `REPORTING` standen
 * vollständig kommentiert in config.ts und wurden von KEINEM Modul importiert.
 * Dazu ein sichtbarer Schalter "Bei Tempoüberschreitung warnen", der nichts
 * tat. Das ist schlimmer als eine fehlende Funktion: Der Schalter behauptet
 * gegenüber dem Fahrer, die App überwache sein Tempolimit.
 *
 * Ein Kommentar hätte das nicht verhindert — der stand ja schon da. Deshalb
 * ein Test, der die Quelltexte liest.
 *
 * Der Test ist absichtlich grob: Er sucht den Namen im Quelltext, statt
 * Importe aufzulösen. Ein zu strenger Test wird abgeschaltet, ein zu lascher
 * übersehen — hier ist grob und laut besser als genau und leise.
 *
 * KOMMENTARE ZÄHLEN NICHT. Das musste sein: Der Hinweis in types.ts, warum
 * `tempolimitWarnung` verschwunden ist, nennt SPEED_LIMIT_ALERT beim Namen —
 * und liess den Block damit als "wird gelesen" erscheinen. Eine Erwähnung ist
 * kein Leser.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const SRC = join(HIER, '..', 'src');
const CONFIG = join(SRC, 'config.ts');

const MARKER_ANFANG = '// --- Noch nicht gebaut ---';
const MARKER_ENDE = '// --- Ende "noch nicht gebaut" ---';

/**
 * Kommentare entfernen, damit eine Erwähnung nicht als Leser zählt.
 *
 * Bewusst per Regex und nicht über den TypeScript-Parser: Der Test soll ohne
 * zusätzliche Abhängigkeit laufen. Die bekannte Schwäche ist ein `//` in
 * einer Zeichenkette (etwa in einer URL); dagegen steht die Ausnahme für
 * `://`. Ein Konfigname in einer URL wäre ohnehin kein Leser.
 */
function ohneKommentare(quelle: string): string {
  return quelle
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}

function alleQuelldateien(verzeichnis: string): string[] {
  const dateien: string[] = [];
  for (const eintrag of readdirSync(verzeichnis, { withFileTypes: true })) {
    const pfad = join(verzeichnis, eintrag.name);
    if (eintrag.isDirectory()) dateien.push(...alleQuelldateien(pfad));
    else if (['.ts', '.tsx'].includes(extname(eintrag.name))) dateien.push(pfad);
  }
  return dateien;
}

/** Exportierte Konstanten aus config.ts, getrennt nach der Marker-Linie. */
function bloecke(): { gebaut: string[]; nichtGebaut: string[] } {
  const quelle = readFileSync(CONFIG, 'utf8');

  const anfang = quelle.indexOf(MARKER_ANFANG);
  const ende = quelle.indexOf(MARKER_ENDE);
  assert.ok(anfang > 0, `${MARKER_ANFANG} fehlt in config.ts`);
  assert.ok(ende > anfang, `${MARKER_ENDE} fehlt oder steht vor dem Anfang`);

  const namen = (text: string): string[] =>
    [...text.matchAll(/^export const ([A-Z][A-Z0-9_]*) = /gm)].map((m) => m[1]!);

  return {
    gebaut: [
      ...namen(quelle.slice(0, anfang)),
      ...namen(quelle.slice(ende)),
    ],
    nichtGebaut: namen(quelle.slice(anfang, ende)),
  };
}

test('die Marker-Linien stehen in config.ts', () => {
  const { gebaut, nichtGebaut } = bloecke();
  assert.ok(gebaut.length > 0, 'kein einziger gebauter Block gefunden');
  assert.ok(
    nichtGebaut.length > 0,
    'der Abschnitt "noch nicht gebaut" ist leer — dann kann die Linie weg',
  );
});

test('JEDER Konfigblock hat einen Leser oder steht unter "noch nicht gebaut"', () => {
  const { gebaut } = bloecke();
  const dateien = alleQuelldateien(SRC).filter((d) => d !== CONFIG);
  const quellen = dateien.map((d) => ohneKommentare(readFileSync(d, 'utf8')));

  const ohneLeser: string[] = [];
  for (const name of gebaut) {
    const gelesen = quellen.some((q) => new RegExp(`\\b${name}\\b`).test(q));
    if (!gelesen) ohneLeser.push(name);
  }

  assert.deepEqual(
    ohneLeser, [],
    `Konfigblöcke ohne Leser: ${ohneLeser.join(', ')}\n` +
    'Entweder die Funktion bauen, oder den Block unter ' +
    `"${MARKER_ANFANG}" verschieben. Ein Block, der nichts steuert, ` +
    'sieht aus wie ein Stellparameter und ist keiner.',
  );
});

test('die Blöcke unter "noch nicht gebaut" werden wirklich nicht gelesen', () => {
  // Die Gegenrichtung. Ohne sie könnte jemand einen benutzten Block unter die
  // Linie schieben, um den Test oben ruhigzustellen — und die Zahl stünde
  // dann als "steuert nichts" da, obwohl sie etwas steuert.
  const { nichtGebaut } = bloecke();
  const dateien = alleQuelldateien(SRC).filter((d) => d !== CONFIG);
  const quellen = dateien.map((d) => ohneKommentare(readFileSync(d, 'utf8')));

  const dochGelesen: string[] = [];
  for (const name of nichtGebaut) {
    if (quellen.some((q) => new RegExp(`\\b${name}\\b`).test(q))) dochGelesen.push(name);
  }

  assert.deepEqual(
    dochGelesen, [],
    `steht unter "noch nicht gebaut", wird aber gelesen: ${dochGelesen.join(', ')}`,
  );
});

test('kein Schalter in der UI ohne Feld in Settings', () => {
  // Der zweite Teil derselben Zusage: Kein UI-Element, das eine Funktion
  // behauptet, die es nicht gibt. `schalter(...)` im Einstellungs-Screen wird
  // über einen Settings-Schlüssel aufgerufen; steht der nicht mehr in
  // `Settings`, fängt es der Typcheck. Was er NICHT fängt, ist ein Feld in
  // Settings, das kein Modul ausser der UI liest — genau der Fall von
  // tempolimitWarnung.
  const typen = readFileSync(join(SRC, 'types.ts'), 'utf8');
  const abschnitt = typen.slice(typen.indexOf('export type Settings = {'));
  const felder = [...abschnitt.slice(0, abschnitt.indexOf('};')).matchAll(/^\s{2}(\w+)[?]?:/gm)]
    .map((m) => m[1]!);

  assert.ok(felder.length > 0, 'keine Settings-Felder gefunden');

  // Gelesen werden muss ausserhalb von types.ts, strings.ts und der UI. Die
  // ersten beiden beschreiben das Feld nur, die UI stellt es dar — keiner der
  // drei macht daraus Verhalten.
  const beschreibend = ['types.ts', 'strings.ts'];
  const verhalten = alleQuelldateien(SRC)
    .filter((d) => !beschreibend.some((b) => d.endsWith(b)))
    .filter((d) => !d.includes(`${'/'}ui${'/'}`))
    .map((d) => ohneKommentare(readFileSync(d, 'utf8')));

  const ohneWirkung: string[] = [];
  for (const feld of felder) {
    if (!verhalten.some((q) => new RegExp(`\\b${feld}\\b`).test(q))) ohneWirkung.push(feld);
  }

  assert.deepEqual(
    ohneWirkung, [],
    `Settings-Felder ohne Wirkung ausserhalb der UI: ${ohneWirkung.join(', ')}\n` +
    'Ein Schalter, der nichts tut, behauptet eine Funktion, die es nicht gibt.',
  );
});
