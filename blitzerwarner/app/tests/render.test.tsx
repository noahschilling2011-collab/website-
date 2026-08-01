/**
 * Rendern die Screens überhaupt?
 *
 * DIE LÜCKE, DIE DIESE DATEI SCHLIESST
 *
 * Bis hierher prüften 347 Tests die Logik — und kein einziger hat je einen
 * Screen gerendert. Ob die App sich öffnen lässt, war damit ungeprüft. Ein
 * Absturz beim ersten Render ist der auffälligste denkbare Fehler und war
 * zugleich der einzige, den keine Prüfung gefunden hätte.
 *
 * `react-native` ist unter Node nicht ladbar (Flow-Typen, esbuild bricht ab).
 * tests/hilfen/ ersetzt deshalb genau die Plattformmodule durch Attrappen;
 * alles andere — Store, Datensatz, Länder-Gate, Textkatalog — läuft echt.
 *
 * WAS DIESER TEST NICHT LEISTET
 *
 * Nichts über Aussehen, Layout, Lesbarkeit bei Sonne oder Touch-Ziele. Und
 * nichts über die Plattform selbst: ob expo-location Positionen liefert und
 * ob ein Ton hörbar wird, zeigt nur das Gerät.
 *
 * AUSFÜHRUNG: `npm run test:render`, und über `npm test` mit. Der Test wird
 * dabei erst gebündelt (tests/hilfen/baue-rendertest.mjs), weil sich die
 * Attrappen nur so einsetzen lassen — die Begründung steht dort.
 *
 * `--test-force-exit` ist nötig und kein Versäumnis: Reacts Scheduler hält
 * unter Node über einen MessageChannel den Event-Loop offen, auch nachdem
 * jeder Baum abgeräumt ist. Die Timer der App selbst werden sauber
 * aufgeräumt — App.tsx und DriveScreen geben beide ein clearInterval aus
 * ihrem Effect zurück, nachgeprüft.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement } from 'react';
import { create, act, type ReactTestRenderer } from 'react-test-renderer';

import App from '../App';
import DriveScreen from '../src/ui/DriveScreen';
import InfoScreen from '../src/ui/InfoScreen';
import OnboardingScreen from '../src/ui/OnboardingScreen';
import RechtlichesScreen from '../src/ui/RechtlichesScreen';
import SettingsScreen from '../src/ui/SettingsScreen';
import AsyncStorage from '@react-native-async-storage/async-storage';

import { ONBOARDING_KEY, useApp } from '../src/state/store';
import type { ThemeMode } from '../src/ui/theme';

/**
 * Einen Baum rendern und wieder abräumen.
 *
 * `act()` deckt die Effekte mit ab — ohne das liefe nur der erste Durchlauf,
 * und genau in den Effekten steckt das Laden von Datensatz, Audio und
 * Einstellungen.
 */
async function rendere(element: React.ReactElement): Promise<ReactTestRenderer> {
  let baum!: ReactTestRenderer;
  await act(async () => { baum = create(element); });
  return baum;
}

/** Alle Textinhalte eines Baums, für Prüfungen auf sichtbare Sätze. */
function texte(baum: ReactTestRenderer): string[] {
  const gefunden: string[] = [];
  const gehe = (knoten: unknown): void => {
    if (typeof knoten === 'string') { gefunden.push(knoten); return; }
    if (Array.isArray(knoten)) { knoten.forEach(gehe); return; }
    if (knoten && typeof knoten === 'object' && 'children' in knoten) {
      gehe((knoten as { children: unknown }).children);
    }
  };
  gehe(baum.toJSON());
  return gefunden;
}

const MODI: ThemeMode[] = ['tag', 'nacht'];

// --- Die einzelnen Screens ------------------------------------------------

test('OnboardingScreen rendert', async () => {
  // Der erste Bildschirm überhaupt. Stürzt er ab, sieht der Nutzer die App
  // nie von innen.
  for (const mode of MODI) {
    const baum = await rendere(createElement(OnboardingScreen, { mode }));
    assert.ok(baum.toJSON() !== null, `${mode}: leerer Baum`);
    baum.unmount();
  }
});

test('der Rechtshinweis steht wirklich auf dem ersten Bildschirm', async () => {
  // Nicht nur "rendert", sondern: Der Satz, auf den es rechtlich ankommt, ist
  // sichtbar. Ein Onboarding ohne ihn wäre gerendert und trotzdem falsch.
  const baum = await rendere(createElement(OnboardingScreen, { mode: 'tag' as const }));
  const alle = texte(baum).join(' ');

  assert.match(alle, /23 Abs\. 1c StVO/, 'die Norm fehlt');
  assert.match(alle, /Fahrzeugführer/, 'unklar, wen das Verbot trifft');
  assert.match(alle, /mobilen Messstellen/, 'die Grenzen der App fehlen');
  baum.unmount();
});

test('DriveScreen rendert', async () => {
  for (const mode of MODI) {
    const baum = await rendere(createElement(DriveScreen, {
      mode, onOeffneEinstellungen: () => {}, onOeffneInfo: () => {},
    }));
    assert.ok(baum.toJSON() !== null, `${mode}: leerer Baum`);
    baum.unmount();
  }
});

test('SettingsScreen rendert und zeigt jeden Schalter', async () => {
  const baum = await rendere(createElement(SettingsScreen, {
    mode: 'tag' as const, onZurueck: () => {}, onOeffneRechtliches: () => {},
  }));
  const alle = texte(baum).join(' ');

  // Die Schalter, die es geben MUSS. Verschwindet einer stillschweigend aus
  // dem JSX, fällt es hier auf und nicht erst auf dem Gerät.
  for (const titel of ['Sprachansage', 'Vibration', 'Fahrt aufzeichnen']) {
    assert.ok(alle.includes(titel), `Schalter "${titel}" fehlt`);
  }
  // Und der, den es NICHT mehr geben darf.
  assert.ok(
    !alle.includes('Tempoüberschreitung'),
    'der entfernte Schalter ist wieder da — er tut nichts',
  );
  baum.unmount();
});

test('InfoScreen rendert und trägt die Lizenzangabe', async () => {
  // Attribution ist Lizenzpflicht aus der ODbL, kein Beiwerk.
  const baum = await rendere(createElement(InfoScreen, {
    mode: 'tag' as const, onZurueck: () => {}, onOeffneRechtliches: () => {},
  }));
  const alle = texte(baum).join(' ');

  assert.match(alle, /OpenStreetMap/, 'keine Attribution');
  assert.match(alle, /Open Database License/, 'keine Lizenzangabe');
  baum.unmount();
});

test('RechtlichesScreen rendert und listet alle vier Dokumente', async () => {
  // Der Bereich, den ein Store-Prüfer sucht. Fehlt eines der Dokumente, wird
  // die Einreichung abgelehnt — und zwar erst nach der Wartezeit.
  const baum = await rendere(createElement(RechtlichesScreen, {
    mode: 'tag' as const, onZurueck: () => {},
  }));
  const alle = texte(baum).join(' ');

  for (const titel of ['Nutzungsbedingungen', 'Datenschutzerklärung', 'Impressum', 'Quellen']) {
    assert.ok(alle.includes(titel), `"${titel}" fehlt im Rechtliches-Bereich`);
  }
  // Und die beiden Schaltflächen für die eigenen Daten.
  assert.ok(alle.includes('Meine Daten ausgeben'));
  assert.ok(alle.includes('löschen'));
  baum.unmount();
});

test('unvollständige Dokumente sind in der Übersicht markiert', async () => {
  // Impressum und Datenschutzerklärung warten auf Angaben des Betreibers.
  // Wer die App so einreicht, soll es beim Durchsehen bemerken.
  const baum = await rendere(createElement(RechtlichesScreen, {
    mode: 'tag' as const, onZurueck: () => {},
  }));
  const alle = texte(baum);
  const markierungen = alle.filter((t) => t === 'unvollständig').length;
  assert.equal(markierungen, 2, `${markierungen} Markierungen, erwartet 2`);
  baum.unmount();
});

// --- Die Wurzel und der Ablauf beim Öffnen --------------------------------

test('App rendert und zeigt zuerst den Rechtshinweis', async () => {
  // Der Ablauf beim Öffnen: Der Store lädt, danach entscheidet
  // `rechtshinweisBestaetigt`, was zu sehen ist. Unbestätigt heisst
  // Onboarding — und daran kommt niemand vorbei.
  await AsyncStorage.removeItem(ONBOARDING_KEY);
  useApp.setState({ geladen: false, rechtshinweisBestaetigt: false });

  const baum = await rendere(createElement(App));
  assert.ok(baum.toJSON() !== null, 'App rendert gar nichts');

  const alle = texte(baum).join(' ');
  assert.match(alle, /23 Abs\. 1c StVO|Static/, 'weder Ladebildschirm noch Onboarding');
  baum.unmount();
});

test('nach der Bestätigung erscheint der Fahrt-Screen', async () => {
  /*
   * Den Zustand über den SPEICHER herstellen, nicht über setState.
   *
   * Der erste Versuch setzte den Store direkt — und bekam trotzdem das
   * Onboarding. Zu Recht: App.tsx ruft im Effect `ladeAlles()`, das liest
   * AsyncStorage und überschreibt alles, was vorher im Store stand. Das ist
   * genau das Verhalten, das die App braucht, und ein Test, der es umgeht,
   * prüft einen Zustand, den es nie gibt.
   */
  await AsyncStorage.setItem(ONBOARDING_KEY, 'ja');

  const baum = await rendere(createElement(App));
  const alle = texte(baum).join(' ');

  // Der Fahrt-Screen ist am Tacho zu erkennen — er ist das einzige Element,
  // das dort und nirgends sonst steht.
  assert.ok(alle.includes('km/h'), `kein Fahrt-Screen. Gesehen: ${alle.slice(0, 200)}`);
  baum.unmount();
});

/*
 * Hier stand ein Test, der den Banner auf dem gerenderten Fahrt-Screen prüfen
 * sollte. Er ist entfernt, weil er nicht ging und dabei so tat, als ginge er:
 * Der Landzustand lebt modul-global im Hintergrund-Task und lässt sich von
 * aussen nicht setzen — nur über Positionen, die der Task selbst verarbeitet,
 * und `verarbeite()` ist nicht exportiert.
 *
 * Was der Banner-Pfad braucht, ist damit an zwei anderen Stellen abgedeckt:
 * tests/gate.test.ts prüft, dass für jedes Land mit hinweisBanner ein Text
 * existiert, und tests/kaltstart.test.ts fährt eine echte Anlage in
 * Deutschland an und prüft den Bannerinhalt. Was hier fehlt, ist allein die
 * Darstellung — und die zeigt das Gerät.
 */

// --- Keine Warnungen aus React --------------------------------------------

test('kein Screen erzeugt React-Warnungen beim Rendern', async () => {
  // Fehlende keys, Zustandsänderungen ausserhalb von act(), doppelte
  // Schlüssel: Alles davon meldet React auf der Konsole und stürzt nicht ab.
  // Auf dem Gerät sieht es niemand, weil dort niemand die Konsole liest.
  const gesammelt: string[] = [];
  const echtesError = console.error;
  const echtesWarn = console.warn;
  console.error = (...a: unknown[]) => { gesammelt.push(a.map(String).join(' ')); };
  console.warn = (...a: unknown[]) => { gesammelt.push(a.map(String).join(' ')); };

  try {
    for (const element of [
      createElement(OnboardingScreen, { mode: 'tag' as const }),
      createElement(SettingsScreen, {
        mode: 'tag' as const, onZurueck: () => {}, onOeffneRechtliches: () => {},
      }),
      createElement(InfoScreen, {
        mode: 'tag' as const, onZurueck: () => {}, onOeffneRechtliches: () => {},
      }),
      createElement(RechtlichesScreen, { mode: 'tag' as const, onZurueck: () => {} }),
      createElement(DriveScreen, {
        mode: 'tag' as const, onOeffneEinstellungen: () => {}, onOeffneInfo: () => {},
      }),
    ]) {
      const baum = await rendere(element);
      baum.unmount();
    }
  } finally {
    console.error = echtesError;
    console.warn = echtesWarn;
  }

  assert.deepEqual(gesammelt, [], `React meldet:\n${gesammelt.join('\n')}`);
});
