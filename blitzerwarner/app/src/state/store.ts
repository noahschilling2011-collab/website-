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
import { setzeSettings } from '../location/task';
import type { Settings } from '../types';

const SETTINGS_KEY = 'blitzerwarner.einstellungen.v1';
const ONBOARDING_KEY = 'blitzerwarner.rechtshinweis-bestaetigt.v1';

export const STANDARD_SETTINGS: Settings = {
  warnDistanceFactor: 1,
  sprachansage: true,
  lautstaerke: 1,
  rotlichtblitzer: true,
  motorradModus: false,
  haptik: false,
  // Standardmässig aus (Spec 8b): Wer sie will, schaltet sie ein. Sonst
  // piept es beim ersten Überholvorgang und der Nutzer schaltet alles ab.
  tempolimitWarnung: false,
  tachoFaktor: 1,
};

export type AppState = {
  settings: Settings;
  /** Rechtshinweis aktiv bestätigt? Ohne das kein Zugang zur App. */
  rechtshinweisBestaetigt: boolean;
  /** Sind die persistierten Werte schon geladen? */
  geladen: boolean;

  ladeAlles: () => Promise<void>;
  setzeEinstellung: <K extends keyof Settings>(key: K, wert: Settings[K]) => Promise<void>;
  bestaetigeRechtshinweis: () => Promise<void>;
};

/**
 * Einstellungen aus dem Speicher lesen und mit den Standardwerten mischen.
 *
 * Das Mischen ist wichtig: Kommt in einer späteren Version eine Einstellung
 * dazu, fehlt sie in den gespeicherten Daten. Ohne die Standardwerte wäre sie
 * dann `undefined` und würde als "aus" gelesen — auch dort, wo "ein" der
 * richtige Standard ist.
 */
async function leseSettings(): Promise<Settings> {
  try {
    const rohtext = await AsyncStorage.getItem(SETTINGS_KEY);
    if (!rohtext) return { ...STANDARD_SETTINGS };
    const gelesen = JSON.parse(rohtext) as Partial<Settings>;
    return { ...STANDARD_SETTINGS, ...gelesen };
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

  async bestaetigeRechtshinweis() {
    set({ rechtshinweisBestaetigt: true });
    try {
      await AsyncStorage.setItem(ONBOARDING_KEY, 'ja');
    } catch (err) {
      errorLog.error('einstellungen', 'Bestätigung nicht gespeichert', err);
    }
  },
}));
