/**
 * Tacho, Spec Abschnitt 8a.
 *
 * Wie warn.ts bewusst als reine Logik über einem expliziten Zustand gebaut,
 * ohne React, ohne expo-location. Der Grund ist derselbe: Ein Tacho lässt
 * sich am Schreibtisch nur dann prüfen, wenn man ihn ohne Gerät mit einer
 * Fixfolge füttern kann. Die Klasse am Ende ist nur eine Hülle für die UI.
 *
 * Die eine Regel, an der hier alles hängt: Ein unbekannter Wert wird als
 * unbekannt gemeldet, niemals als 0. Ein Tacho, der bei ausgefallenem GPS
 * "0" zeigt, behauptet etwas über die Fahrt, was er nicht weiss — und
 * genau in dem Moment schaut jemand hin.
 */
import { SPEEDOMETER, SPEEDO_TOLERANCE } from '../config';
import type { Fix, Settings } from '../types';

/**
 * Umrechnung m/s in km/h. Physikalische Konstante, kein Stellparameter —
 * deshalb hier und nicht in config.ts, analog zu EARTH_RADIUS_M in geo.ts.
 */
const MS_TO_KMH = 3.6;

/** Faktor, bei dem keine Tacho-Kalibrierung vorliegt (siehe Settings.tachoFaktor). */
export const TACHO_FAKTOR_NEUTRAL = 1;

/**
 * 'ok'        — verwertbarer Wert.
 * 'unsicher'  — Wert vorhanden, aber die Position ist zu ungenau; die UI
 *               graut ihn aus, statt ihn zu verschweigen.
 * 'unbekannt' — wir wissen es nicht. Dann ist `kmh` null, nicht 0.
 */
export type SpeedQuality = 'ok' | 'unsicher' | 'unbekannt';

/** Die Güte, die ein tatsächlich vorhandener Wert haben kann. */
type GueteMitWert = Exclude<SpeedQuality, 'unbekannt'>;

export type SpeedReading = {
  /** Geglättete Geschwindigkeit in m/s, null wenn unbekannt. */
  ms: number | null;
  /**
   * Anzeigewert in ganzen km/h, null wenn unbekannt.
   * Invariante: `kmh === null` genau dann, wenn `quality === 'unbekannt'`.
   * 0 erscheint nur, wenn wirklich ein Stillstand gemessen wurde.
   */
  kmh: number | null;
  /**
   * Was der Auto-Tacho bei dieser Geschwindigkeit ungefähr anzeigt, mit dem
   * kalibrierten Faktor. Ohne Kalibrierung identisch mit `kmh`.
   */
  tachoKmh: number | null;
  quality: SpeedQuality;
  /**
   * Der zuletzt verarbeitete Fix hatte keine gültige Geschwindigkeit, der
   * angezeigte Wert wird nur noch gehalten. Für einen dezenten Hinweis.
   */
  gehalten: boolean;
  /** Alter des angezeigten Wertes in ms, null wenn unbekannt. */
  alterMs: number | null;
};

/**
 * Zustand eines Tachos. Vom Aufrufer gehalten, nicht global.
 *
 * Wert, Zeitstempel und Güte stecken absichtlich in einem gemeinsamen
 * Objekt: So kann es keinen Zustand geben, in dem ein Wert ohne Zeitstempel
 * existiert und die Haltezeit nie ablaufen würde.
 */
export type SpeedState = {
  wert: { ms: number; t: number; guete: GueteMitWert } | null;
  haltend: boolean;
};

export function createSpeedState(): SpeedState {
  return { wert: null, haltend: false };
}

/**
 * Bewusst eine Funktion und kein geteiltes Objekt: Ein einziges,
 * mehrfach zurückgegebenes Ergebnis wäre von aussen veränderbar und der
 * Fehler tauchte irgendwo ganz anders auf.
 */
function unbekannt(): SpeedReading {
  return {
    ms: null,
    kmh: null,
    tachoKmh: null,
    quality: 'unbekannt',
    gehalten: false,
    alterMs: null,
  };
}

/**
 * Kalibrierfaktor aus den Einstellungen, gegen Unsinn abgesichert.
 *
 * Ein durch einen früheren Fehler auf 0 oder NaN gelaufener gespeicherter
 * Wert darf nicht dazu führen, dass der Tacho gar nichts mehr anzeigt.
 */
function wirksamerFaktor(settings: Pick<Settings, 'tachoFaktor'>): number {
  const f = settings.tachoFaktor;
  return Number.isFinite(f) && f > 0 ? f : TACHO_FAKTOR_NEUTRAL;
}

export function istKalibriert(settings: Pick<Settings, 'tachoFaktor'>): boolean {
  return wirksamerFaktor(settings) !== TACHO_FAKTOR_NEUTRAL;
}

/**
 * Güte aus der horizontalen Genauigkeit.
 *
 * Die Genauigkeit der Geschwindigkeit selbst liefert nicht jede Plattform,
 * die Positionsgenauigkeit schon. Sie ist ein brauchbarer Stellvertreter:
 * Wenn die Position in der Tunnelausfahrt um 80 m springt, taugt auch die
 * Doppler-Lösung nichts.
 *
 * Eine fehlende Genauigkeitsangabe gilt als 'unsicher'. Wir können den Wert
 * dann nicht beurteilen, und "nicht beurteilbar" ist näher an unsicher als
 * an gut. Ausgegraut wird er trotzdem angezeigt, es geht nichts verloren.
 */
function accuracyGuete(accuracy: number | null): GueteMitWert {
  if (accuracy == null || !Number.isFinite(accuracy)) return 'unsicher';
  return accuracy > SPEEDOMETER.MAX_ACCURACY_M ? 'unsicher' : 'ok';
}

/** km/h zur Anzeige: ganze Zahl, keine Nachkommastellen. */
export function kmhFromMs(ms: number): number {
  return Math.round(ms * MS_TO_KMH);
}

/**
 * Den aktuellen Anzeigewert lesen, ohne dass ein neuer Fix vorliegt.
 *
 * Das ist kein Komfort, sondern der Kern der Haltelogik: Wenn das GPS
 * schweigt, kommt gar kein Fix mehr, mit dem man den Ablauf der Haltezeit
 * bemerken könnte. Die UI ruft das im Anzeigetakt auf und bekommt nach
 * SPEEDOMETER.HOLD_LAST_VALUE_MS von selbst 'unbekannt'.
 */
export function readSpeed(
  state: SpeedState,
  now: number,
  settings: Pick<Settings, 'tachoFaktor'>,
): SpeedReading {
  const wert = state.wert;
  if (wert == null) return unbekannt();

  // Ein Fix aus der Zukunft (Uhrensprung) darf kein negatives Alter ergeben.
  const alterMs = Math.max(0, now - wert.t);

  if (alterMs >= SPEEDOMETER.HOLD_LAST_VALUE_MS) {
    // Haltezeit abgelaufen. Zustand verwerfen, damit der nächste gültige Fix
    // die Glättung frisch aufsetzt statt gegen einen veralteten Wert.
    state.wert = null;
    state.haltend = false;
    return unbekannt();
  }

  const kmh = kmhFromMs(wert.ms);
  return {
    ms: wert.ms,
    kmh,
    // Aus dem ungerundeten Wert gerechnet, sonst rundet man zweimal.
    tachoKmh: Math.round(wert.ms * MS_TO_KMH * wirksamerFaktor(settings)),
    quality: wert.guete,
    gehalten: state.haltend,
    alterMs,
  };
}

/**
 * Einen Fix einarbeiten und den neuen Anzeigewert zurückgeben.
 * Verändert `state`, wie evaluate() in warn.ts auch.
 */
export function updateSpeed(
  state: SpeedState,
  fix: Pick<Fix, 'speed' | 'accuracy' | 't'>,
  settings: Pick<Settings, 'tachoFaktor'>,
): SpeedReading {
  const roh = fix.speed;
  const gueltig = roh != null && Number.isFinite(roh) && roh >= 0;

  if (!gueltig) {
    // Android liefert null, iOS -1, wenn keine Doppler-Lösung vorliegt.
    // Beides heisst "unbekannt" und nicht "steht" — deshalb halten.
    if (state.wert != null) state.haltend = true;
    return readSpeed(state, fix.t, settings);
  }

  const vorher = state.wert;
  // Lag der letzte gültige Wert länger zurück als die Haltezeit, ist er
  // wertlos: zwischen zwei Fixes im Minutenabstand kann alles passiert sein.
  // Dann neu aufsetzen, statt 130 km/h in den Stillstand hineinzuglätten.
  const basis =
    vorher != null && fix.t - vorher.t < SPEEDOMETER.HOLD_LAST_VALUE_MS ? vorher.ms : null;

  // Der erste Wert setzt den Mittelwert direkt, ohne Anlauf von 0 aus.
  // Sonst zeigte der Tacho nach dem Start mehrere Sekunden zu wenig an.
  const ms =
    basis == null ? roh : SPEEDOMETER.EMA_ALPHA * roh + (1 - SPEEDOMETER.EMA_ALPHA) * basis;

  // Ein ungenauer Fix fliesst trotzdem in die Glättung ein — er ist das
  // Beste, was wir haben. Er wird nur als unsicher gekennzeichnet.
  state.wert = { ms, t: fix.t, guete: accuracyGuete(fix.accuracy) };
  state.haltend = false;

  return readSpeed(state, fix.t, settings);
}

// --- Kalibrierung ---------------------------------------------------------

/**
 * Faktor aus einer Ablesung: Der Fahrer liest bei bekannter echter
 * Geschwindigkeit ab, was sein Auto-Tacho zeigt.
 *
 * Gibt null zurück, wenn die Eingabe unbrauchbar ist. Bewusst kein
 * Zurechtbiegen auf einen "plausiblen" Wert: Eine stille Korrektur der
 * Eingabe wäre für den Nutzer nicht nachvollziehbar.
 */
export function kalibrierfaktor(echteKmh: number, abgeleseneKmh: number): number | null {
  if (!Number.isFinite(echteKmh) || !Number.isFinite(abgeleseneKmh)) return null;
  if (echteKmh <= 0 || abgeleseneKmh <= 0) return null;
  return abgeleseneKmh / echteKmh;
}

/**
 * Zulässige Anzeigespanne eines Auto-Tachos für eine echte Geschwindigkeit,
 * für den Erklär-Screen.
 *
 * NUR ZUR ERKLÄRUNG. Aus dieser Spanne wird nichts abgeleitet, was eine
 * Warnung auslöst oder unterdrückt — die Warnlogik in warn.ts kennt diese
 * Funktion nicht. Die Formel selbst steht unter dem Prüfvorbehalt in
 * config.ts (SPEEDO_TOLERANCE.GEPRUEFT_AM ist noch null).
 *
 * Gibt null bei unbrauchbarer Eingabe zurück.
 */
export function zulaessigeTachoSpanne(
  echteKmh: number,
): { minKmh: number; maxKmh: number } | null {
  if (!Number.isFinite(echteKmh) || echteKmh < 0) return null;
  return {
    // Die Anzeige darf nie weniger zeigen als tatsächlich gefahren wird.
    minKmh: echteKmh,
    maxKmh: echteKmh * (1 + SPEEDO_TOLERANCE.FACTOR) + SPEEDO_TOLERANCE.OFFSET_KMH,
  };
}

/**
 * Liegt eine Ablesung innerhalb der zulässigen Spanne?
 *
 * Ebenfalls nur erklärend: Der Kalibrier-Screen kann damit einen Hinweis
 * anzeigen, wenn eine Eingabe vermutlich ein Tippfehler war. Die
 * Kalibrierung wird dadurch nicht blockiert.
 */
export function tachoAnzeigePlausibel(echteKmh: number, abgeleseneKmh: number): boolean {
  const spanne = zulaessigeTachoSpanne(echteKmh);
  if (spanne == null || !Number.isFinite(abgeleseneKmh)) return false;
  return abgeleseneKmh >= spanne.minKmh && abgeleseneKmh <= spanne.maxKmh;
}

// --- Hülle für die UI -----------------------------------------------------

/**
 * Dünne Hülle um den Zustand. Enthält keine Rechnung — alles Rechnende steht
 * in den Funktionen oben, damit der Replay-Test ohne Instanz auskommt.
 */
export class Speedometer {
  private readonly state: SpeedState;
  private settings: Pick<Settings, 'tachoFaktor'>;

  constructor(settings?: Pick<Settings, 'tachoFaktor'>) {
    this.state = createSpeedState();
    this.settings = settings ?? { tachoFaktor: TACHO_FAKTOR_NEUTRAL };
  }

  /** Nach einer Änderung der Kalibrierung in den Einstellungen aufrufen. */
  setSettings(settings: Pick<Settings, 'tachoFaktor'>): void {
    this.settings = settings;
  }

  update(fix: Pick<Fix, 'speed' | 'accuracy' | 't'>): SpeedReading {
    return updateSpeed(this.state, fix, this.settings);
  }

  read(now: number): SpeedReading {
    return readSpeed(this.state, now, this.settings);
  }
}
