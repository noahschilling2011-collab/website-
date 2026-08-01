/**
 * Audio-Wiedergabe und Sprachausgabe.
 *
 * Diese Datei ist die Grenze zur Plattform: Alles, was sich ohne Gerät nicht
 * prüfen lässt, steht hier — und nur hier. Die Entscheidungen, WAS gesagt
 * wird, liegen in announce.ts und sind getestet.
 */
import { Audio, InterruptionModeAndroid, InterruptionModeIOS } from 'expo-av';
import * as Speech from 'expo-speech';

import { AUDIO } from '../config';
import { errorLog } from '../core/log';
import { alsBase64, TOENE, type TonArt } from './tone';
import {
  ansageText,
  enthaeltVerbotenesZonenwort,
  sprechrate,
  zonenAnsageText,
  type ZonenSprache,
} from './announce';
import type { Camera } from '../types';

/** Einmal erzeugte Tondaten, damit nicht bei jeder Warnung neu gerechnet wird. */
const tonCache = new Map<TonArt, string>();

function tonDaten(art: TonArt): string {
  let daten = tonCache.get(art);
  if (!daten) {
    daten = `data:audio/wav;base64,${alsBase64(TOENE[art])}`;
    tonCache.set(art, daten);
  }
  return daten;
}

let sessionBereit = false;

/**
 * Audio-Session konfigurieren.
 *
 * Der entscheidende Teil ist `shouldDuckAndroid` und
 * `interruptionModeIOS: DuckOthers`: Musik wird leiser, nicht gestoppt. Wer
 * beim Fahren Musik hört, soll nach der Warnung weiterhören, ohne zum Handy
 * greifen zu müssen.
 *
 * `staysActiveInBackground` ist nicht optional — ohne das schweigt die App
 * bei ausgeschaltetem Display, also in genau dem Zustand, für den sie
 * gebaut ist.
 */
export async function initAudio(): Promise<void> {
  try {
    await Audio.setAudioModeAsync({
      staysActiveInBackground: true,
      playsInSilentModeIOS: true,
      shouldDuckAndroid: true,
      interruptionModeAndroid: InterruptionModeAndroid.DuckOthers,
      interruptionModeIOS: InterruptionModeIOS.DuckOthers,
      allowsRecordingIOS: false,
    });
    sessionBereit = true;
    errorLog.info('audio', 'Audio-Session konfiguriert');
  } catch (err) {
    // Kein stilles Scheitern: Ohne Audio ist die App wertlos, das muss der
    // Nutzer im Fehlerprotokoll finden können.
    sessionBereit = false;
    errorLog.error('audio', 'Audio-Session konnte nicht konfiguriert werden', err);
  }
}

const schlafe = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Einen der drei Töne abspielen und warten, bis er durch ist. */
export async function spieleTon(art: TonArt, lautstaerke = 1): Promise<void> {
  if (!sessionBereit) await initAudio();

  try {
    const { sound } = await Audio.Sound.createAsync(
      { uri: tonDaten(art) },
      { shouldPlay: true, volume: Math.max(0, Math.min(1, lautstaerke)) },
    );
    // Ressource wieder freigeben, sonst sammeln sich über eine lange Fahrt
    // hunderte Sound-Objekte an.
    sound.setOnPlaybackStatusUpdate((status) => {
      if ('didJustFinish' in status && status.didJustFinish) {
        void sound.unloadAsync().catch((err) =>
          errorLog.error('audio', 'Ton konnte nicht entladen werden', err));
      }
    });
  } catch (err) {
    errorLog.error('audio', `Ton ${art} konnte nicht abgespielt werden`, err);
  }
}

/**
 * Warnung ausgeben: Ton, kurze Pause, dann Sprache.
 *
 * Die Pause ist der Grund für diese Reihenfolge. Bluetooth-Geräte gehen nach
 * einigen Sekunden Stille in einen Ruhezustand; startet man direkt mit der
 * Sprachausgabe, weckt der erste Laut die Verbindung und die ersten Silben
 * sind verloren. Der Nutzer hört dann "...zer in vierhundert Metern".
 *
 * Der Ton ist also nicht Verzierung, sondern weckt die Strecke auf.
 */
export async function gebeWarnung(
  camera: Camera,
  distanzM: number,
  opts: { sprache: boolean; lautstaerke: number; speedKmh: number | null },
): Promise<void> {
  await spieleTon('blitzer', opts.lautstaerke);

  if (!opts.sprache) return;

  await schlafe(AUDIO.WAKEUP_DELAY_MS);

  try {
    Speech.speak(ansageText(camera, distanzM), {
      language: 'de-DE',
      rate: sprechrate(opts.speedKmh),
      volume: Math.max(0, Math.min(1, opts.lautstaerke)),
      // Geklammert, weil errorLog.error() einen LogEntry zurückgibt und
      // expo-speech hier void erwartet.
      onError: (err) => { errorLog.error('audio', 'Sprachausgabe fehlgeschlagen', err); },
    });
  } catch (err) {
    errorLog.error('audio', 'Sprachausgabe konnte nicht gestartet werden', err);
  }
}

/**
 * Der Zonenhinweis (Frankreich).
 *
 * Nimmt weder Kamera noch Distanz an — was die Funktion nicht kennt, kann sie
 * nicht aussprechen. Das ist dieselbe Sicherung wie bei `Aktion` in
 * core/entscheidung.ts, nur eine Ebene tiefer.
 *
 * Die Prüfung gegen die Verbotswortliste läuft ZUR LAUFZEIT und nicht nur im
 * Test. Der Grund steht bei enthaeltVerbotenesZonenwort(): Der Textkatalog
 * kann sich ändern, die Auflage nicht. Findet sie ein verbotenes Wort, wird
 * geschwiegen statt gesprochen — der Ton allein ist zulässig, denn er benennt
 * nichts.
 */
export async function gebeZonenhinweis(
  opts: { sprache: boolean; lautstaerke: number },
): Promise<void> {
  await spieleTon('zone', opts.lautstaerke);

  if (!opts.sprache) return;

  const text = zonenAnsageText(zonenSprache());
  const verboten = enthaeltVerbotenesZonenwort(text);
  if (verboten !== null) {
    errorLog.error(
      'audio',
      `Zonenansage "${text}" enthält das unzulässige Wort "${verboten}" — nicht gesprochen`,
    );
    return;
  }

  await schlafe(AUDIO.WAKEUP_DELAY_MS);

  try {
    Speech.speak(text, {
      // Die Ansage folgt der Systemsprache, nicht der App-Sprache: Sie fällt
      // in Frankreich, und ein deutscher Satz wäre dort für Mitfahrende
      // unverständlich. Der Katalog in strings.ts deckt deshalb mehrere
      // Sprachen ab — und die Verbotsliste ebenfalls.
      language: SPRACH_CODE[zonenSprache()],
      volume: Math.max(0, Math.min(1, opts.lautstaerke)),
      onError: (err) => { errorLog.error('audio', 'Zonenansage fehlgeschlagen', err); },
    });
  } catch (err) {
    errorLog.error('audio', 'Zonenansage konnte nicht gestartet werden', err);
  }
}

/**
 * Welche Sprache die Zonenansage benutzt.
 *
 * Ohne Localization-Bibliothek: Die App hat keine, und eine neue Abhängigkeit
 * für drei Zeichenketten wäre unverhältnismässig. Gelesen wird, was die
 * JS-Umgebung ohnehin kennt.
 *
 * Fällt die Erkennung aus, gilt Französisch. Das ist die richtige Richtung:
 * Der Zonenmodus gilt derzeit nur in Frankreich, und ein französischer Satz
 * ist dort für jeden verständlich, der die Auflage kennt.
 */
function zonenSprache(): ZonenSprache {
  try {
    const roh = Intl.DateTimeFormat().resolvedOptions().locale ?? '';
    const kurz = roh.slice(0, 2).toLowerCase();
    if (kurz === 'de' || kurz === 'en' || kurz === 'fr') return kurz;
  } catch {
    // Kein Intl in dieser Umgebung. Kein Fall fürs Fehlerprotokoll — die
    // Ansage kommt trotzdem, nur eben auf Französisch.
  }
  return 'fr';
}

/** BCP-47-Kennungen für expo-speech. Getrennt vom Katalog, weil es Technik ist. */
const SPRACH_CODE: Record<ZonenSprache, string> = {
  de: 'de-DE',
  fr: 'fr-FR',
  en: 'en-GB',
};

/** Kurzer Hinweis ohne Blitzerbezug, z. B. beim Grenzübertritt. */
export async function sageAnsage(text: string, lautstaerke = 1): Promise<void> {
  await spieleTon('system', lautstaerke);
  await schlafe(AUDIO.WAKEUP_DELAY_MS);
  try {
    Speech.speak(text, { language: 'de-DE', volume: lautstaerke });
  } catch (err) {
    errorLog.error('audio', 'Ansage fehlgeschlagen', err);
  }
}

/**
 * Systemwarnung des Watchdogs.
 *
 * Bewusst laut und unabhängig von der Sprachansage-Einstellung: Wer die
 * Sprache abgeschaltet hat, muss trotzdem erfahren, dass die Warnung nicht
 * mehr läuft. Ein stiller Ausfall ist der gefährlichste Zustand der App.
 */
export async function warneSystem(text: string): Promise<void> {
  await spieleTon('system', 1);
  await schlafe(AUDIO.WAKEUP_DELAY_MS);
  try {
    Speech.speak(text, { language: 'de-DE', volume: 1 });
  } catch (err) {
    errorLog.error('audio', 'Systemwarnung konnte nicht gesprochen werden', err);
  }
}

export async function stoppeSprache(): Promise<void> {
  try {
    await Speech.stop();
  } catch (err) {
    errorLog.error('audio', 'Sprachausgabe konnte nicht gestoppt werden', err);
  }
}
