/**
 * Den Rendertest bündeln, bevor Node ihn ausführt.
 *
 * WARUM EIN EIGENER SCHRITT
 *
 * `react-native` lässt sich unter Node nicht laden: Die Datei enthält
 * Flow-Typen, und esbuild bricht mit `Unexpected "typeof"` ab. Damit war die
 * gesamte Oberfläche ungetestet.
 *
 * Der naheliegende Weg — ein Auflösungs-Hook von Node (`module.register`) —
 * funktioniert hier NICHT: `tsx` löst verschachtelte Importe intern auf, der
 * Hook bekommt nur die Einstiegsdatei zu sehen. Nachgeprüft: Bei einem
 * `import { View } from 'react-native'` im Test protokolliert der Hook
 * ausschliesslich die Testdatei selbst.
 *
 * Deshalb hier der direkte Weg: esbuild bündelt den Test samt Anwendungscode
 * und ersetzt dabei die Plattformmodule durch die Attrappen aus
 * ./attrappen/. Ersetzt wird ausschliesslich, was unter Node nicht ladbar
 * ist — Store, Datensatz, Länder-Gate und Textkatalog laufen echt.
 */
import { build } from 'esbuild';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const APP = join(HIER, '..', '..');
const ATTRAPPEN = join(HIER, 'attrappen');

const ALIAS = {
  'react-native': join(ATTRAPPEN, 'react-native.tsx'),
  'expo-location': join(ATTRAPPEN, 'expo-location.ts'),
  'expo-task-manager': join(ATTRAPPEN, 'expo-task-manager.ts'),
  'expo-av': join(ATTRAPPEN, 'expo-av.ts'),
  'expo-speech': join(ATTRAPPEN, 'expo-speech.ts'),
  'expo-constants': join(ATTRAPPEN, 'expo-constants.ts'),
  '@react-native-async-storage/async-storage': join(ATTRAPPEN, 'async-storage.ts'),
  'react-native-svg': join(ATTRAPPEN, 'react-native-svg.tsx'),
};

await build({
  entryPoints: [join(APP, 'tests', 'render.test.tsx')],
  outfile: join(HIER, '.gebaut', 'render.test.mjs'),
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node20',
  jsx: 'automatic',
  alias: ALIAS,
  // react und der Testrenderer bleiben aussen vor: Sie sind unter Node
  // ohnehin ladbar, und gebündelt gäbe es zwei React-Instanzen.
  external: ['react', 'react/jsx-runtime', 'react-test-renderer', 'node:*'],
  // Der Datensatz wird per require() geladen und muss mit ins Bündel.
  loader: { '.json': 'json' },
  logLevel: 'warning',
});

console.log('Rendertest gebaut.');
