/**
 * Zustandsspeicher.
 *
 * zustand statt Redux — die Spec verlangt ausdrücklich kein
 * State-Management-Framework, und für vier Screens mit einer Handvoll Werten
 * wären Actions, Reducer und Selektoren nur Zeremonie.
 *
 * Der Fahrtzustand lebt NICHT hier, sondern im Hintergrund-Task: Der läuft in
 * einem eigenen JS-Kontext, den React nicht sieht. Dieser Store spiegelt ihn
 * nur für die Anzeige.
 */
import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';

import { errorLog } from '../core/log';
import { STANDARD_SETTINGS, mischeSettings } from '../core/settings';
import { setzeSettings } from '../location/task';
import type { Settings } from '../types';

/*
 * Weitergereicht, damit die UI weiter `from '../state/store'` importiert und
 * nicht jeder Screen den Pfad nach core/ kennen muss. Die Werte selbst stehen
 * dort — einmal, statt wie vorher doppelt in Store und Task.
 */
export { STANDARD_SETTINGS };

const SETTINGS_KEY = 'blitzerwarner.einstellungen.v1';
/**
 * Exportiert, damit tests/render.test.tsx den bestätigten Zustand herstellen
 * kann, ohne den Schlüssel abzuschreiben. Ein abgeschriebener Schlüssel wäre
 * beim nächsten Umbenennen still falsch, und der Test prüfte dann dauerhaft
 * den Onboarding-Screen statt des Fahrt-Screens.
 */
export const ONBOARDING_KEY = 'blitzerwarner.rechtshinweis-bestaetigt.v1';

export type AppState = {
  settings: Settings;
  /** Rechtshinweis aktiv bestätigt? Ohne das kein Zugang zur App. */
  rechtshinweisBestaetigt: boolean;
  /** Sind die persistierten Werte schon geladen? */
  geladen: boolean;

  ladeAlles: () => Promise<void>;
  /**
   * Alles löschen, was auf dem Gerät liegt: Einstellungen zurück auf die
   * Standardwerte, Fehlerprotokoll leer.
   *
   * Der bestätigte Rechtshinweis bleibt stehen. Ihn zurückzusetzen wäre keine
   * Löschung von Daten, sondern eine Belästigung — der Nutzer müsste beim
   * nächsten Start erneut durch das Onboarding, und gelöscht wäre dadurch
   * nichts, was ihn betrifft.
   */
  loescheAlleDaten: () => Promise<void>;
  setzeEinstellung: <K extends keyof Settings>(key: K, wert: Settings[K]) => Promise<void>;
  bestaetigeRechtshinweis: () => Promise<void>;
};

async function leseSettings(): Promise<Settings> {
  try {
    const rohtext = await AsyncStorage.getItem(SETTINGS_KEY);
    if (!rohtext) return { ...STANDARD_SETTINGS };
    return mischeSettings(JSON.parse(rohtext));
  } catch (err) {
    errorLog.error('einstellungen', 'Einstellungen konnten nicht gelesen werden', err);
    return { ...STANDARD_SETTINGS };
  }
}

export const useApp = create<AppState>((set, get) => ({
  settings: { ...STANDARD_SETTINGS },
  rechtshinweisBestaetigt: false,
  geladen: false,

  async ladeAlles() {
    const settings = await leseSettings();
    let bestaetigt = false;
    try {
      bestaetigt = (await AsyncStorage.getItem(ONBOARDING_KEY)) === 'ja';
    } catch (err) {
      errorLog.error('einstellungen', 'Bestätigungsstatus nicht lesbar', err);
    }

    // Der Task muss die Einstellungen kennen, bevor der erste Fix kommt.
    setzeSettings(settings);
    set({ settings, rechtshinweisBestaetigt: bestaetigt, geladen: true });
  },

  async setzeEinstellung(key, wert) {
    const settings = { ...get().settings, [key]: wert };
    set({ settings });
    setzeSettings(settings);
    try {
      await AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (err) {
      // Die Änderung wirkt trotzdem für diese Sitzung — nur das Speichern
      // ist fehlgeschlagen. Das gehört ins Protokoll, aber nicht als
      // blockierender Fehler ins Gesicht des Nutzers.
      errorLog.error('einstellungen', `Einstellung ${String(key)} nicht gespeichert`, err);
    }
  },

  async loescheAlleDaten() {
    const settings = { ...STANDARD_SETTINGS };
    set({ settings });
    setzeSettings(settings);

    errorLog.clear();
    try {
      await AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
      await errorLog.flush();
    } catch (err) {
      // Die Änderung wirkt für diese Sitzung; nur das Speichern ist
      // fehlgeschlagen. Das gehört ins Protokoll — das damit allerdings
      // gerade nicht leer ist. Der Widerspruch ist gewollt: Ein stiller
      // Fehlschlag beim Löschen wäre schlimmer als ein sichtbarer Eintrag.
      errorLog.error('einstellungen', 'Löschen konnte nicht gespeichert werden', err);
    }
  },

  async bestaetigeRechtshinweis() {
    set({ rechtshinweisBestaetigt: true });
    try {
      await AsyncStorage.setItem(ONBOARDING_KEY, 'ja');
    } catch (err) {
      errorLog.error('einstellungen', 'Bestätigung nicht gespeichert', err);
    }
  },
}));
