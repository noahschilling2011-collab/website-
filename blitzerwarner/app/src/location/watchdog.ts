/**
 * Watchdog — laut Qualitätsvorgabe der kritischste Punkt der ganzen App.
 *
 * Eine Warn-App, die still stirbt, ist GEFÄHRLICHER als keine App, weil der
 * Nutzer sich auf sie verlässt. Android killt Hintergrund-Tasks aggressiv,
 * besonders bei Herstellern mit eigenem Akku-Management. Ohne Watchdog
 * bemerkt man das erst, wenn eine Warnung ausgeblieben ist — also zu spät.
 *
 * Die Entscheidungslogik ist absichtlich als reine Funktion herausgezogen,
 * damit sie testbar ist, ohne einen Task zu killen.
 */
import { WATCHDOG } from '../config';

/** Zustand, wie ihn der Vordergrund sieht. */
export type WatchdogStatus =
  /** Tracking läuft nicht — kein Alarm, das ist gewollt. */
  | 'aus'
  /** Tracking läuft und liefert. */
  | 'lebendig'
  /** Tracking sollte laufen, liefert aber nichts mehr. */
  | 'tot';

export type WatchdogState = {
  aktiv: boolean;
  /** Zeitstempel des letzten Positionsupdates, null = noch keins. */
  letzterFix: number | null;
  /** Wann wurde das Tracking gestartet? Für die Anlaufzeit. */
  gestartet: number | null;
  /** Wurde für den aktuellen Totzustand bereits Alarm gegeben? */
  alarmGegeben: boolean;
};

export function createWatchdogState(): WatchdogState {
  return { aktiv: false, letzterFix: null, gestartet: null, alarmGegeben: false };
}

/**
 * Gilt der Task als tot?
 *
 * Zwei Feinheiten, die den Unterschied zwischen brauchbar und nervig machen:
 *
 * 1. Direkt nach dem Start gibt es noch keinen Fix. Ein GPS-Fix kann unter
 *    freiem Himmel Sekunden, in der Garage Minuten dauern. Deshalb zählt in
 *    dieser Phase die Zeit seit dem START, nicht seit dem letzten Fix —
 *    sonst schlägt der Alarm sofort beim Losfahren an.
 * 2. Bei ausgeschaltetem Tracking gibt es nichts zu überwachen.
 */
export function istTaskTot(state: WatchdogState, jetzt: number): boolean {
  if (!state.aktiv) return false;

  const bezug = state.letzterFix ?? state.gestartet;
  if (bezug == null) return false;

  return jetzt - bezug > WATCHDOG.STALE_AFTER_MS;
}

export function status(state: WatchdogState, jetzt: number): WatchdogStatus {
  if (!state.aktiv) return 'aus';
  return istTaskTot(state, jetzt) ? 'tot' : 'lebendig';
}

/**
 * Prüfen und entscheiden, ob JETZT Alarm zu geben ist.
 *
 * Der Alarm kommt genau einmal pro Totzustand. Ein Dauerpiepen, während man
 * an der Ampel steht und das GPS keinen Empfang hat, würde dazu führen, dass
 * der Nutzer die App abschaltet — und damit hätte der Watchdog das Gegenteil
 * seines Zwecks erreicht.
 */
export function pruefe(
  state: WatchdogState,
  jetzt: number,
): { status: WatchdogStatus; alarmAusloesen: boolean } {
  const s = status(state, jetzt);

  if (s === 'tot') {
    const alarmAusloesen = !state.alarmGegeben;
    state.alarmGegeben = true;
    return { status: s, alarmAusloesen };
  }

  // Erholt sich der Task, ist der nächste Ausfall wieder ein neuer Alarm.
  state.alarmGegeben = false;
  return { status: s, alarmAusloesen: false };
}

/** Vom Background-Task bei jedem Update aufzurufen. */
export function meldeFix(state: WatchdogState, jetzt: number): void {
  state.letzterFix = jetzt;
}

export function starte(state: WatchdogState, jetzt: number): void {
  state.aktiv = true;
  state.gestartet = jetzt;
  state.letzterFix = null;
  state.alarmGegeben = false;
}

export function stoppe(state: WatchdogState): void {
  state.aktiv = false;
  state.letzterFix = null;
  state.gestartet = null;
  state.alarmGegeben = false;
}

/**
 * Text für die Statuszeile im Fahrt-Screen.
 *
 * Die Qualitätsvorgabe verlangt, dass der Nutzer auf einen Blick sieht, dass
 * die App wirklich läuft. "Aktiv" allein genügt dafür nicht — ein
 * eingefrorener Task sieht genauso aus.
 */
export function statuszeile(state: WatchdogState, jetzt: number): {
  aktivSeitMin: number | null;
  letzterFixVorSek: number | null;
  status: WatchdogStatus;
} {
  return {
    aktivSeitMin: state.gestartet != null ? Math.floor((jetzt - state.gestartet) / 60_000) : null,
    letzterFixVorSek:
      state.letzterFix != null ? Math.floor((jetzt - state.letzterFix) / 1000) : null,
    status: status(state, jetzt),
  };
}

/** Prüfintervall für den Vordergrund-Timer. */
export const PRUEF_INTERVALL_MS = WATCHDOG.CHECK_INTERVAL_MS;
