/**
 * Text der Sprachansagen.
 *
 * Reine Funktionen: Der Ansagetext wird zusammengebaut und getestet, ohne
 * dass eine TTS-Stimme im Spiel ist. Was die Stimme daraus macht, lässt sich
 * nur am Gerät prüfen — dass der Text stimmt, hier.
 */
import { AUDIO } from '../config';
import type { Camera } from '../types';

/**
 * Zahlen als Wort.
 *
 * Nötig, weil TTS-Stimmen bei Ziffern uneinheitlich sind: Manche lesen "400"
 * als "vierhundert", andere als "vier null null". Bei einer Warnung, die man
 * in einer Sekunde erfassen muss, ist das nicht egal.
 *
 * Abgedeckt wird der real vorkommende Bereich: Entfernungen bis 900 m in
 * 50er-Schritten und Tempolimits bis 130. Ausserhalb wird die Ziffernfolge
 * zurückgegeben — lieber eine hölzern gelesene Zahl als eine falsche.
 */
const EINER = [
  'null', 'eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun',
  'zehn', 'elf', 'zwölf', 'dreizehn', 'vierzehn', 'fünfzehn', 'sechzehn', 'siebzehn',
  'achtzehn', 'neunzehn',
];
const ZEHNER = [
  '', '', 'zwanzig', 'dreißig', 'vierzig', 'fünfzig', 'sechzig', 'siebzig', 'achtzig', 'neunzig',
];

export function zahlAlsWort(n: number): string {
  if (!Number.isFinite(n) || n < 0 || n !== Math.floor(n)) return String(n);
  if (n < 20) return EINER[n]!;

  if (n < 100) {
    const z = Math.floor(n / 10);
    const e = n % 10;
    if (e === 0) return ZEHNER[z]!;
    // Deutsche Eigenheit: Einer vor Zehner, "einundzwanzig".
    return `${e === 1 ? 'ein' : EINER[e]}und${ZEHNER[z]}`;
  }

  if (n < 1000) {
    const h = Math.floor(n / 100);
    const rest = n % 100;
    const hundert = `${h === 1 ? 'ein' : EINER[h]}hundert`;
    return rest === 0 ? hundert : `${hundert}${zahlAlsWort(rest)}`;
  }

  if (n === 1000) return 'eintausend';
  return String(n);
}

/**
 * Entfernung für die Ansage runden.
 *
 * "dreihundertzweiundzwanzig Meter" ist als Ansage unbrauchbar — niemand
 * braucht die Meterzahl exakt, und die Silben kosten Zeit, die man beim
 * Fahren nicht hat. Gerundet wird auf 50 m, unter 100 m auf 10 m.
 */
export function rundeEntfernung(meter: number): number {
  if (meter < 100) return Math.max(10, Math.round(meter / 10) * 10);
  return Math.round(meter / 50) * 50;
}

/**
 * Der Ansagetext.
 *
 * Immer gleich aufgebaut, keine Begrüssung, kein "Achtung", kein "bitte".
 * Die Gleichförmigkeit ist der Punkt: Wer den Satzbau kennt, versteht ihn
 * auch halb überhört.
 */
export function ansageText(camera: Camera, distanzM: number): string {
  const entfernung = rundeEntfernung(distanzM);
  const teile = ['Blitzer', `${zahlAlsWort(entfernung)} Meter`];

  if (camera.max != null) {
    teile.push(`Tempo ${zahlAlsWort(camera.max)}`);
  }

  // Rotlichtblitzer sind eine andere Sache als eine Geschwindigkeitsmessung —
  // wer das weiss, verhält sich anders.
  if (camera.type === 'red_light') {
    return `Rotlichtblitzer, ${zahlAlsWort(entfernung)} Meter`;
  }
  if (camera.type === 'both') {
    teile.splice(1, 0, 'und Rotlicht');
  }

  return teile.join(', ');
}

/** Sprechrate: Bei hohem Tempo bleibt weniger Zeit für die Ansage. */
export function sprechrate(speedKmh: number | null): number {
  if (speedKmh == null) return 1;
  return speedKmh > AUDIO.FAST_SPEECH_ABOVE_KMH ? AUDIO.FAST_SPEECH_RATE : 1;
}

/** Ansage für den Grenzübertritt, Spec Abschnitt 10.1. */
export function landwechselText(warnungAktiv: boolean): string {
  return warnungAktiv ? 'Blitzerwarnung aktiviert' : 'Blitzerwarnung deaktiviert';
}

// --- Zonenmodus (Frankreich, Spec Phase C) --------------------------------

/**
 * Wörter, die im Zonenmodus in KEINER Ansage vorkommen dürfen.
 *
 * Das ist die Kernauflage, nicht eine Stilfrage. Frankreich erlaubt seit dem
 * 03.01.2012 nur den Hinweis auf einen Gefahrenbereich; die Zone darf die Art
 * der Gefahr nicht benennen. Wer "Blitzer" sagt, benennt sie.
 *
 * Die Liste enthält absichtlich mehrere Sprachen: Der Ansagetext folgt der
 * Systemsprache, und ein französischer oder englischer Katalog käme sonst
 * ungeprüft durch. Sie ist bewusst breiter als nötig — ein zu strenger Test
 * kostet eine Formulierung, ein zu lascher ein Bussgeld.
 */
export const VERBOTENE_ZONENWOERTER = [
  // deutsch
  'blitzer', 'radar', 'kamera', 'kontrolle', 'messstelle', 'messung',
  'geschwindigkeitsmessung', 'überwachung', 'polizei', 'tempolimit',
  // französisch
  'radar', 'contrôle', 'controle', 'caméra', 'camera', 'police',
  'vitesse', 'cinémomètre', 'cinemometre',
  // englisch
  'speed camera', 'speed trap', 'enforcement', 'surveillance', 'police',
] as const;

/**
 * Ansagetexte für den Zonenmodus.
 *
 * Bewusst ein GETRENNTER Katalog und nicht der normale mit anderer
 * Formulierung: Wer später einen Punkt-Ansagetext ergänzt, soll ihn nicht
 * versehentlich in einer Zone verwenden können. Die Trennung ist die
 * Sicherung, der Test dahinter die Kontrolle.
 *
 * Genannt wird ein Aufmerksamkeitshinweis auf einen Streckenabschnitt —
 * keine Entfernung, keine Richtung, keine Art der Gefahr.
 */
export const ZONEN_ANSAGE = {
  de: 'Achtungsbereich',
  fr: 'Zone de vigilance',
  en: 'Caution zone',
} as const;

export type ZonenSprache = keyof typeof ZONEN_ANSAGE;

/**
 * Der Ansagetext beim Eintritt in eine Zone.
 *
 * Genau EINE Ansage pro Zone, ohne Entfernung, ohne Countdown. Die Funktion
 * nimmt deshalb auch keine Distanz an — was sie nicht kennt, kann sie nicht
 * versehentlich aussprechen.
 */
export function zonenAnsageText(sprache: ZonenSprache = 'fr'): string {
  return ZONEN_ANSAGE[sprache];
}

/**
 * Prüft einen Text gegen die Verbotswortliste.
 *
 * Läuft nicht nur im Test, sondern auch zur Laufzeit vor der Ausgabe: Der
 * Katalog kann sich ändern, die Auflage nicht.
 */
export function enthaeltVerbotenesZonenwort(text: string): string | null {
  const klein = text.toLowerCase();
  for (const wort of VERBOTENE_ZONENWOERTER) {
    if (klein.includes(wort)) return wort;
  }
  return null;
}
