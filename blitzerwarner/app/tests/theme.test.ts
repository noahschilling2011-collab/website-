/**
 * Die Design-Tokens — und ob die Screens sie überhaupt benutzen.
 *
 * DER ANLASS
 *
 * theme.ts war vollständig durchdacht: Vierer-Raster, eine Akzentfarbe, keine
 * Schatten, 64 dp Berührungsflächen statt der üblichen 44. Nur benutzt hat es
 * niemand. Gemessen vor dieser Änderung: `ABSTAND`, `RADIUS`, `LINIE`,
 * `ZEILENHOEHE`, `DECKKRAFT` und `EFFEKTE` wurden von KEINEM Screen gelesen —
 * jeder hatte seine Zahlen selbst hingeschrieben. Neun Mal `borderRadius: 12`
 * neben sechs Mal `borderRadius: 8`, und der Token dazu stand auf 14.
 *
 * Das ist derselbe Fehler wie bei den Konfigblöcken in config.ts, nur eine
 * Ebene höher: Werte, die aussehen, als steuerten sie etwas. Und es ist die
 * Ursache dafür, dass eine Oberfläche "generiert" wirkt — nicht der einzelne
 * falsche Wert, sondern dass es für dieselbe Sache mehrere gibt.
 *
 * Was dieser Test NICHT kann: beurteilen, ob es gut aussieht. Balance,
 * Weissraum und Gesamtwirkung lassen sich nicht aus dem Quelltext lesen. Er
 * prüft nur, dass die Entscheidungen an einer Stelle stehen und dort auch
 * gelesen werden.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  ABSTAND,
  DECKKRAFT,
  EFFEKTE,
  MASS,
  PALETTEN,
  RADIUS,
  SCHRIFT,
  SEITE,
  SPUR,
  TOUCH,
  ZEILENHOEHE,
  gedrueckt,
  spur,
} from '../src/ui/theme';

const HIER = dirname(fileURLToPath(import.meta.url));
const SRC = join(HIER, '..', 'src');
const UI = join(SRC, 'ui');
const THEME = join(UI, 'theme.ts');

/** Alle Dateien, die Oberfläche bauen: die Screens und die Wurzelkomponente. */
function oberflaechenDateien(): string[] {
  const dateien = readdirSync(UI)
    .filter((n) => extname(n) === '.tsx')
    .map((n) => join(UI, n));
  return [...dateien, join(HIER, '..', 'App.tsx')];
}

const QUELLEN = oberflaechenDateien().map((d) => ({
  name: d.split('/').pop()!,
  text: readFileSync(d, 'utf8'),
}));

// --- Das Raster -----------------------------------------------------------

test('jeder Abstands-Token liegt auf dem Vierer-Raster', () => {
  // Nicht weil 4 magisch wäre, sondern weil dann alles halbierbar bleibt —
  // und Halbierbarkeit ist, was Gleichmass erzeugt.
  for (const gruppe of [
    { praefix: 'ABSTAND', werte: ABSTAND as Record<string, number> },
    { praefix: 'SEITE', werte: SEITE as Record<string, number> },
    { praefix: 'MASS', werte: MASS as Record<string, number> },
  ]) {
    for (const [name, wert] of Object.entries(gruppe.werte)) {
      assert.equal(
        wert % 4, 0,
        `${gruppe.praefix}.${name} = ${wert} liegt neben dem Raster`,
      );
    }
  }
  for (const [name, wert] of Object.entries(RADIUS)) {
    if (wert === RADIUS.KREIS) continue; // der Kreis ist kein Rastermass
    assert.equal(wert % 4, 0, `RADIUS.${name} = ${wert} liegt neben dem Raster`);
  }
});

test('für dieselbe Sache gibt es genau einen Wert', () => {
  // Der eigentliche Befund der Prüfung war nicht, dass ein Wert falsch war,
  // sondern dass es ihn mehrfach gab: neun Mal borderRadius 12 neben sechs
  // Mal 8, Zeilenhöhe 1.4 neben 1.45 für denselben Fliesstext. Hier wird das
  // an der einzigen Stelle geprüft, an der es prüfbar ist — den Tokens.
  const doppelt = (werte: Record<string, number>) => {
    const gesehen = new Map<number, string>();
    for (const [name, wert] of Object.entries(werte)) {
      const vorher = gesehen.get(wert);
      assert.equal(vorher, undefined, `${name} und ${vorher} sind beide ${wert}`);
      gesehen.set(wert, name);
    }
  };
  doppelt(ABSTAND as Record<string, number>);
  doppelt(SEITE as Record<string, number>);
  doppelt(ZEILENHOEHE as Record<string, number>);

  // SCHRIFT steht bewusst nicht in der Liste. Masse sind eine Skala — zwei
  // Namen für denselben Schritt heisst dort, dass jemand einen erfunden hat.
  // Schriftgrade sind Rollen, und zwei Rollen dürfen sich einen Grad teilen;
  // eine Skala mit weniger Stufen ist die bessere. Konkret trifft das
  // MELDUNG und TACHO_EINHEIT, beide 24 — das ist gewollt und hier notiert,
  // damit es nicht stillschweigend passiert.
  assert.equal(SCHRIFT.MELDUNG, SCHRIFT.TACHO_EINHEIT);
});

test('jede Zeilenhöhe wird aus einem Faktor gerechnet, nicht hingeschrieben', () => {
  // Sonst wird sie beim nächsten Ändern eines Schriftgrads still falsch: Die
  // Schrift wächst, die Zeile nicht, und die Zeilen kleben aufeinander.
  for (const { name, text } of QUELLEN) {
    for (const m of text.matchAll(/lineHeight: ([^,}]+)/g)) {
      assert.match(
        m[1]!, /ZEILENHOEHE\./,
        `${name}: ${m[0]} — als SCHRIFT.X * ZEILENHOEHE.Y schreiben`,
      );
    }
  }
});

test('kein Screen schreibt Abstände oder Radien als nackte Zahl hin', () => {
  // Das ist die eigentliche Zusage. Solange die Zahlen in den Screens stehen,
  // gibt es für dieselbe Sache mehrere — und genau daran erkennt man eine
  // Oberfläche, die aus Teilen zusammengesetzt statt entworfen wurde.
  const FELDER = [
    'padding', 'paddingHorizontal', 'paddingVertical', 'paddingTop', 'paddingBottom',
    'gap', 'rowGap', 'columnGap', 'marginTop', 'marginBottom', 'marginHorizontal',
    'borderRadius', 'borderWidth', 'borderBottomWidth', 'borderTopWidth',
    // letterSpacing steht hier, weil die Versalien-Beschriftungen dreimal
    // eine hingeschriebene 1 hatten — dieselbe Sache, drei Stellen.
    'letterSpacing',
    // width/height nur, wo sie eine gestaltete Grösse sind: der Statuspunkt
    // stand auf 10 und lag damit als einziges Mass neben dem Raster.
    'width', 'height', 'minHeight', 'minWidth',
  ];
  const muster = new RegExp(`\\b(${FELDER.join('|')}): (\\d+)\\b`, 'g');

  const funde: string[] = [];
  for (const { name, text } of QUELLEN) {
    for (const m of text.matchAll(muster)) {
      // 0 ist erlaubt: "kein Rand" braucht keinen Token.
      if (m[2] === '0') continue;
      funde.push(`${name}: ${m[0]}`);
    }
  }

  assert.deepEqual(
    funde, [],
    `Nackte Masszahlen in Screens:\n  ${funde.join('\n  ')}\n` +
    'Sie gehören nach ui/theme.ts. Sonst gibt es für dieselbe Sache mehrere Werte.',
  );
});

// --- Werden die Tokens gelesen? -------------------------------------------

const THEME_QUELLE = readFileSync(THEME, 'utf8');

/** Wird der Name irgendwo in einem Screen genannt? */
function direktGelesen(name: string): boolean {
  return QUELLEN.some((q) => new RegExp(`\\b${name}\\b`).test(q.text));
}

/**
 * Die Rümpfe der aus theme.ts exportierten Funktionen.
 *
 * Gelesen wird bis zur schliessenden Klammer am Zeilenanfang — theme.ts ist
 * durchgehend so formatiert, und ein Parser für diese eine Frage wäre mehr
 * Maschinerie als Erkenntnis.
 */
function funktionsRuempfe(): Map<string, string> {
  const ruempfe = new Map<string, string>();
  const muster = /^export function ([A-Za-z_][A-Za-z0-9_]*)\b/gm;
  for (const treffer of THEME_QUELLE.matchAll(muster)) {
    const start = treffer.index!;
    const ende = THEME_QUELLE.indexOf('\n}', start);
    ruempfe.set(treffer[1]!, THEME_QUELLE.slice(start, ende < 0 ? undefined : ende));
  }
  return ruempfe;
}

test('JEDER exportierte Token wird gelesen — direkt oder über eine Funktion', () => {
  // Die Gegenrichtung zum Test darüber. Ein Token, den niemand liest, ist
  // kein Token, sondern eine Notiz — und er suggeriert eine Entscheidung, die
  // in Wahrheit anderswo getroffen wird.
  //
  // "Gelesen" heisst nicht zwingend "im Screen genannt". SPUR und DECKKRAFT
  // stehen absichtlich nur in spur() und gedrueckt(): Der Screen soll die
  // Zahl dahinter gar nicht kennen, sonst schreibt der nächste sie wieder
  // selbst hin. Ein Token gilt deshalb auch dann als gelesen, wenn eine
  // exportierte Funktion aus theme.ts ihn benutzt UND diese Funktion in
  // einem Screen vorkommt.
  const namen = [...THEME_QUELLE.matchAll(/^export (?:const|function) ([A-Za-z_][A-Za-z0-9_]*)/gm)]
    .map((m) => m[1]!)
    .filter((n) => !AUSGENOMMEN.includes(n));

  const ruempfe = funktionsRuempfe();
  const erreichbareFunktionen = [...ruempfe.entries()].filter(([fn]) => direktGelesen(fn));

  const ohneLeser = namen.filter((name) =>
    !direktGelesen(name) &&
    !erreichbareFunktionen.some(([, rumpf]) => new RegExp(`\\b${name}\\b`).test(rumpf)),
  );

  assert.deepEqual(
    ohneLeser, [],
    `Design-Tokens ohne Leser: ${ohneLeser.join(', ')}\n` +
    'Entweder benutzen oder entfernen. Ein Wert, der nichts steuert, sieht ' +
    'aus wie einer, der etwas steuert.',
  );
});

/**
 * Was der Leser-Test nicht erfassen kann — mit Begründung je Eintrag.
 *
 * Die Liste ist kurz zu halten. Jeder Eintrag ist eine Ausnahme von der
 * Zusage, und eine Ausnahme, die niemand mehr begründen kann, ist der Anfang
 * einer Tokendatei, die wieder niemand liest.
 */
const AUSGENOMMEN = [
  // Das Bündel für Aufrufer, die den Modus nicht kennen. Die Screens holen
  // sich stattdessen palette(mode) und die Tokens einzeln.
  'THEME_STANDARD', 'theme',
  // Der Zugang zu den Paletten führt über palette(); PALETTEN selbst wird nur
  // hier im Test durchgezählt.
  'PALETTEN',
  // EFFEKTE beschreibt, was es absichtlich NICHT gibt. Ein Leser dafür kann
  // es per Definition nicht geben — geprüft wird die Zusage im Test darunter.
  'EFFEKTE',
  // MASS und SEITE sind Sammelnamen; geprüft werden ihre Einträge über die
  // Screens, die sie benutzen.
];

test('was EFFEKTE ausschliesst, kommt in keinem Screen vor', () => {
  // Der Ersatz für einen Leser-Test: EFFEKTE ist eine Verneinung, also wird
  // die Verneinung geprüft. Kein Schatten, kein Blur, keine Erhebung — die
  // drei Gründe stehen in theme.ts: Kontrast bei Sonne, GPU-Zeit pro Frame,
  // und ein weicher Rand ist im Augenwinkel schwerer zu finden.
  const verboten = [
    /\bshadow(Color|Offset|Opacity|Radius)\b/,
    /\belevation\s*:/,
    /\bBlurView\b/,
    /\bblurRadius\b/,
  ];
  for (const { name, text } of QUELLEN) {
    for (const muster of verboten) {
      assert.ok(
        !muster.test(text),
        `${name} benutzt ${muster.source} — EFFEKTE schliesst das aus`,
      );
    }
  }

  assert.equal(EFFEKTE.BLUR_RADIUS, 0);
  assert.equal(EFFEKTE.SCHATTEN, false);
  assert.equal(EFFEKTE.ELEVATION, 0);
});

// --- Die harten Regeln ----------------------------------------------------

test('Berührungsflächen sind mindestens 44 dp — hier sogar deutlich mehr', () => {
  // 44 dp ist die Plattformvorgabe und die häufigste Verfehlung in
  // generierter Oberfläche. Diese App liegt bewusst darüber: Im fahrenden
  // Auto zittert die Hand und der Blick ist woanders.
  assert.ok(TOUCH.MIN >= 44, `TOUCH.MIN = ${TOUCH.MIN}`);
  assert.ok(TOUCH.FAHRT >= TOUCH.MIN, 'die Fahrtfläche ist kleiner als das Minimum');
});

test('jede berührbare Fläche hat eine Rückmeldung beim Drücken', () => {
  // Auf einem Berührungsbildschirm gibt es kein "darüber". Der gedrückte
  // Zustand ist die einzige Rückmeldung, die es überhaupt geben kann — und
  // vor dieser Änderung hatte genau EINE von siebzehn Flächen eine.
  const ohne: string[] = [];
  for (const { name, text } of QUELLEN) {
    let i = 0;
    while ((i = text.indexOf('<Pressable', i)) >= 0) {
      // Bis zum Ende des öffnenden Tags lesen, geschweifte Klammern zählen.
      let j = i, tiefe = 0;
      for (; j < text.length; j++) {
        if (text[j] === '{') tiefe++;
        else if (text[j] === '}') tiefe--;
        else if (text[j] === '>' && tiefe === 0) break;
      }
      const tag = text.slice(i, j);
      if (!tag.includes('gedrueckt') && !tag.includes('pressed')) {
        const zeile = text.slice(0, i).split('\n').length;
        ohne.push(`${name}:${zeile}`);
      }
      i = j;
    }
  }

  assert.deepEqual(
    ohne, [],
    `Pressable ohne Rückmeldung: ${ohne.join(', ')}\n` +
    'Ergänzen mit: style={(z) => [stil.x, gedrueckt(z)]}',
  );
});

test('gedrueckt() liefert drei Zustände und nichts dazwischen', () => {
  assert.deepEqual(gedrueckt({ pressed: false }), { opacity: DECKKRAFT.VOLL });
  assert.deepEqual(gedrueckt({ pressed: true }), { opacity: DECKKRAFT.GEDRUECKT });
  // Abgeschaltet schlägt gedrückt: Wer auf eine tote Fläche drückt, soll
  // nicht die Rückmeldung bekommen, es sei etwas passiert.
  assert.deepEqual(gedrueckt({ pressed: true }, true), { opacity: DECKKRAFT.INAKTIV });
  assert.deepEqual(gedrueckt({ pressed: false }, true), { opacity: DECKKRAFT.INAKTIV });

  assert.ok(
    DECKKRAFT.GEDRUECKT < DECKKRAFT.VOLL && DECKKRAFT.GEDRUECKT > DECKKRAFT.INAKTIV,
    'gedrückt muss sichtbar sein, aber schwächer als abgeschaltet',
  );
});

test('eine abgeschaltete Fläche sieht auch abgeschaltet aus', () => {
  // Der teuerste Zustandsfehler auf einem Berührungsbildschirm: Ein Knopf,
  // der nicht reagiert und dabei aussieht wie einer, der reagiert. Der Nutzer
  // drückt dann fester, nicht woanders hin.
  //
  // Geprüft wird schwach, aber prüfbar: Das Aussehen einer Fläche mit
  // `disabled` muss von irgendetwas abhängen. Zwei Wege sind in Gebrauch —
  // gedrueckt(z, …) für Nebenknöpfe, und beim Weiter-Knopf im Onboarding ein
  // Farbwechsel, weil dort die Fläche selbst die Hauptaussage ist.
  for (const { name, text } of QUELLEN) {
    let i = 0;
    while ((i = text.indexOf('<Pressable', i)) >= 0) {
      let j = i, tiefe = 0;
      for (; j < text.length; j++) {
        if (text[j] === '{') tiefe++;
        else if (text[j] === '}') tiefe--;
        else if (text[j] === '>' && tiefe === 0) break;
      }
      const tag = text.slice(i, j);
      i = j;
      if (!/disabled=\{/.test(tag)) continue;

      const zeile = text.slice(0, text.indexOf(tag)).split('\n').length;
      assert.ok(
        /gedrueckt\(z, /.test(tag) || /style=\{[\s\S]*\?[\s\S]*:/.test(tag),
        `${name}:${zeile}: Pressable mit disabled, aber das Aussehen ändert ` +
        'sich nicht — gedrueckt(z, bedingung) oder einen Farbwechsel ergänzen.',
      );
    }
  }
});

test('genau eine Akzentfarbe je Palette', () => {
  // Wenn Rot die einzige Farbe im Bild ist, erkennt das Auge sie peripher,
  // ohne hinzusehen. Jede zweite Farbe entwertet das. Geprüft wird, dass
  // ausser Warnrot und seiner gedämpften Fläche alles unbunt ist — bei einem
  // Grauton sind die drei Kanäle gleich.
  for (const [modus, p] of Object.entries(PALETTEN)) {
    for (const [name, wert] of Object.entries(p)) {
      if (name === 'warn' || name === 'warnGedaempft') continue;
      const [r, g, b] = [1, 3, 5].map((i) => parseInt(wert.slice(i, i + 2), 16));
      assert.ok(
        r === g && g === b,
        `${modus}.${name} = ${wert} ist bunt — es gibt nur eine Akzentfarbe`,
      );
    }
  }
});

// --- Schrift --------------------------------------------------------------

test('grosse Grade werden enger gesetzt, kleine nicht', () => {
  // Grosse Zahlen kommen mit Standardabstand auseinandergezogen daher; bei
  // 120 dp Tachoziffern sichtbar. Fliesstext enger zu setzen macht ihn
  // dagegen schwerer lesbar, und lesbar ist hier die einzige Anforderung.
  assert.ok(spur(SCHRIFT.TACHO) < 0, 'der Tacho wird nicht enger gesetzt');
  assert.ok(spur(SCHRIFT.WARN_TITEL) < 0, 'die Warnüberschrift wird nicht enger gesetzt');
  assert.equal(spur(SCHRIFT.TEXT), 0, 'Fliesstext wird enger gesetzt');
  assert.equal(spur(SCHRIFT.KLEIN), 0, 'Kleintext wird enger gesetzt');

  // Der Betrag bleibt im üblichen Rahmen von zwei bis drei Prozent.
  const anteil = Math.abs(spur(SCHRIFT.TACHO)) / SCHRIFT.TACHO;
  assert.ok(anteil >= 0.02 && anteil <= 0.03, `${(anteil * 100).toFixed(1)} %`);
  assert.equal(SPUR.AB_GRAD >= SCHRIFT.TEXT, true);
});

test('der kleinste Grad auf dem Fahrt-Screen bleibt lesbar', () => {
  // Aus Armlänge, mit einem Blick von einer halben Sekunde. Unter 18 dp ist
  // nichts mehr sicher zu erfassen.
  assert.ok(SCHRIFT.TEXT >= 18, `SCHRIFT.TEXT = ${SCHRIFT.TEXT}`);
  assert.ok(SCHRIFT.STATUS >= 18, `SCHRIFT.STATUS = ${SCHRIFT.STATUS}`);
});

test('keine Emoji als Bedienelemente', () => {
  // Emoji sehen auf jedem System anders aus, lassen sich nicht einfärben und
  // haben keine gemeinsame Strichstärke.
  const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;
  for (const { name, text } of QUELLEN) {
    assert.ok(!emoji.test(text), `${name} enthält ein Emoji`);
  }
});
