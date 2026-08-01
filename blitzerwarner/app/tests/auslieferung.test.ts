/**
 * Was im ausgelieferten Paket steckt — und was nicht drin sein darf.
 *
 * DER ANLASS
 *
 * tests/berechtigungen.test.ts beweist "keine Netzwerk-Requests" über den
 * Entzug der INTERNET-Berechtigung. Das ist ein guter Beweis, aber er gilt nur
 * auf Android: `blockedPermissions` steht unter `android` und wirkt auch nur
 * dort. iOS kennt keine Internet-Berechtigung — jede App darf ins Netz, es
 * gibt nichts zu entziehen.
 *
 * Für iOS bleibt genau ein Beweis übrig, und es ist der grundlegendere: Die
 * App enthält keinen Aufruf, der eine Verbindung herstellen würde. Das lässt
 * sich am Quelltext prüfen, und genau das passiert hier.
 *
 * WAS DIESER TEST NICHT KANN
 *
 * Er sieht nur den eigenen Quelltext, nicht node_modules. Eine Bibliothek, die
 * im Hintergrund telefoniert, fällt hier nicht auf — dagegen hilft auf Android
 * der Berechtigungsentzug und auf iOS nur, keine solche Bibliothek
 * einzubinden. Deshalb steht die Abhängigkeitsliste weiter unten mit im Test.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const APP = join(HIER, '..');
const SRC = join(APP, 'src');

/** Jede TypeScript-Datei der App, ausser den Tests und dem Replay-Werkzeug. */
function quelldateien(wurzel: string): string[] {
  const raus: string[] = [];
  for (const eintrag of readdirSync(wurzel)) {
    const pfad = join(wurzel, eintrag);
    if (statSync(pfad).isDirectory()) {
      // replay/ läuft in Node, nie auf dem Gerät — es gehört nicht ins Paket.
      if (eintrag === 'replay') continue;
      raus.push(...quelldateien(pfad));
    } else if (['.ts', '.tsx'].includes(extname(eintrag))) {
      raus.push(pfad);
    }
  }
  return raus;
}

const QUELLEN = [...quelldateien(SRC), join(APP, 'App.tsx'), join(APP, 'index.ts')]
  .map((pfad) => ({ name: relative(APP, pfad), text: readFileSync(pfad, 'utf8') }));

/**
 * Kommentare wegwerfen, bevor gesucht wird.
 *
 * Ohne das schlägt der Test bei jedem Kommentar an, der das Wort erklärt — und
 * dieses Repo erklärt viel. Ein Test, der sich an seiner eigenen Begründung
 * stört, wird abgeschaltet statt beachtet.
 */
function ohneKommentare(text: string): string {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1 ');
}

// --- Der Beweis, der auf beiden Plattformen gilt ---------------------------

test('kein Aufruf im Quelltext stellt eine Netzwerkverbindung her', () => {
  // Das ist das Produktversprechen, und auf iOS ist es der einzige Beweis
  // dafür. Gesucht wird nach dem, womit man in React Native überhaupt ins
  // Netz kommt.
  const VERBOTEN: { muster: RegExp; was: string }[] = [
    { muster: /\bfetch\s*\(/, was: 'fetch()' },
    { muster: /\bXMLHttpRequest\b/, was: 'XMLHttpRequest' },
    { muster: /\bnew\s+WebSocket\b/, was: 'WebSocket' },
    { muster: /\bnavigator\.sendBeacon\b/, was: 'sendBeacon' },
    { muster: /\bEventSource\b/, was: 'EventSource' },
    { muster: /\baxios\b/, was: 'axios' },
    { muster: /\bfrom\s+['"]node:https?['"]/, was: 'node:http(s)' },
    // expo-updates lädt beim Start ein neues JS-Bündel — das ist ein
    // Netzwerk-Request zur Laufzeit, auch wenn niemand ihn programmiert hat.
    { muster: /\bexpo-updates\b/, was: 'expo-updates' },
  ];

  const funde: string[] = [];
  for (const { name, text } of QUELLEN) {
    const nackt = ohneKommentare(text);
    for (const { muster, was } of VERBOTEN) {
      if (muster.test(nackt)) funde.push(`${name}: ${was}`);
    }
  }

  assert.deepEqual(
    funde, [],
    `Netzwerk-Aufrufe im Quelltext:\n  ${funde.join('\n  ')}\n` +
    'Die Datenpipeline gehört nach scripts/ und läuft vor dem Build.',
  );
});

test('Linking.openURL ist die einzige Ausnahme — und sie verbindet nicht selbst', () => {
  // Der Lizenzlink im Info-Screen. Die App übergibt eine Adresse an das
  // System und der Browser übernimmt; sie stellt selbst keine Verbindung her.
  // Die Ausnahme steht hier namentlich, damit eine zweite auffällt.
  const mitOpenUrl = QUELLEN
    .filter((q) => /\bLinking\.openURL\b/.test(ohneKommentare(q.text)))
    .map((q) => q.name);

  assert.deepEqual(
    mitOpenUrl, ['src/ui/InfoScreen.tsx'],
    'Es gibt eine zweite Stelle, die den Nutzer aus der App schickt',
  );
});

// --- Keine Schlüssel, keine Geheimnisse ------------------------------------

test('im Quelltext steht kein Schlüssel und kein Zugangsdatum', () => {
  // Aus dem Video: "niemand soll deine privaten Schlüssel sehen". Hier gibt
  // es keinen Dienst, für den ein Schlüssel nötig wäre — aber genau deshalb
  // fällt ein hineingeratener auch niemandem auf.
  //
  // Gesucht wird nach Zuweisungen, nicht nach dem blossen Wort: "Schlüssel"
  // kommt in den Kommentaren dieses Repos vor, ein API-Schlüssel nicht.
  const VERBOTEN: { muster: RegExp; was: string }[] = [
    { muster: /(api[_-]?key|apikey)\s*[:=]\s*['"][^'"]{8,}/i, was: 'API-Schlüssel' },
    { muster: /(secret|password|passwd)\s*[:=]\s*['"][^'"]{6,}/i, was: 'Geheimnis' },
    { muster: /Bearer\s+[A-Za-z0-9._-]{16,}/, was: 'Bearer-Token' },
    { muster: /\bsk-[A-Za-z0-9]{16,}/, was: 'OpenAI-artiger Schlüssel' },
    { muster: /\bAIza[A-Za-z0-9_-]{30,}/, was: 'Google-Schlüssel' },
    { muster: /-----BEGIN [A-Z ]*PRIVATE KEY-----/, was: 'privater Schlüssel' },
  ];

  const funde: string[] = [];
  for (const { name, text } of QUELLEN) {
    const nackt = ohneKommentare(text);
    for (const { muster, was } of VERBOTEN) {
      if (muster.test(nackt)) funde.push(`${name}: ${was}`);
    }
  }
  assert.deepEqual(funde, [], `Zugangsdaten im Quelltext:\n  ${funde.join('\n  ')}`);
});

// --- Keine Bibliothek, die von sich aus telefoniert ------------------------

/**
 * Jede direkte Abhängigkeit, mit dem Grund, warum sie da ist.
 *
 * WARUM ERLAUBNISLISTE UND NICHT VERBOTSLISTE
 *
 * Zuerst stand hier eine Liste verdächtiger Namen — Sentry, Firebase,
 * Analyse, Werbung. Die fängt genau die Pakete, an die jemand schon gedacht
 * hat, und keines der anderen. Ein Analysedienst mit einem Namen, der nicht
 * auf der Liste steht, wäre stillschweigend durchgegangen.
 *
 * Umgekehrt herum kann nichts durchrutschen: Wer eine Abhängigkeit
 * hinzufügt, bekommt einen roten Test, bis er hier aufschreibt, wofür sie da
 * ist. Das ist kein Misstrauen gegen Bibliotheken, sondern die Umsetzung des
 * Produktversprechens — "keine Netzwerk-Requests zur Laufzeit" hält nur, wenn
 * bekannt ist, was überhaupt mitläuft.
 *
 * Der Aufwand ist die eine Zeile, die man beim Hinzufügen schreibt.
 */
const ERLAUBTE_ABHAENGIGKEITEN: Record<string, string> = {
  'expo': 'Das Gerüst: Build-Konfiguration, Prebuild, die expo-* Module darunter.',
  'react': 'Die Komponentenbibliothek, auf der React Native aufsetzt.',
  'react-native': 'Die Laufzeit selbst — ohne sie gibt es keine App.',
  'expo-status-bar': 'Statusleiste einfärben.',
  'expo-system-ui': 'Hintergrundfarbe des Systemfensters — sonst blitzt beim Start Weiss auf.',
  'expo-asset': 'Lädt die gebündelten Dateien. Direkt eingetragen, weil der Metro-Start sie sonst nicht auflöst.',
  'expo-font': 'Wie expo-asset: direkte Abhängigkeit, damit der Start durchläuft.',
  'expo-file-system': 'Wie expo-asset und expo-font: direkte Abhängigkeit, damit Metro sie auflöst.',
  'expo-dev-client': 'Nur für den Entwicklungsbuild; Expo Go kann keinen Hintergrundstandort.',
  'expo-constants': 'Liest extra.internetEntzogen aus der Build-Konfiguration.',
  'expo-location': 'Die Positionen. Ohne sie gibt es keine App.',
  'expo-task-manager': 'Der Hintergrund-Task — warnen bei ausgeschaltetem Display.',
  'expo-av': 'Die Audio-Sitzung: Musik leiser stellen statt stoppen.',
  'expo-speech': 'Die Ansage.',
  'expo-haptics': 'Vibration als zweiter Kanal zur Ansage.',
  'expo-notifications': 'Die Pflicht-Benachrichtigung des Vordergrunddienstes.',
  'expo-keep-awake': 'Display an lassen, solange die App im Vordergrund fährt.',
  '@react-native-async-storage/async-storage': 'Einstellungen und Rechtshinweis auf dem Gerät.',
  'zustand': 'Der Zustandsspeicher der Oberfläche.',
  'react-native-svg':
    'Das Kartenbild: Linienzüge der Landesumrisse, Anlagenzeichen, ' +
    'Massstabsbalken. Rendert nativ und stellt keine Verbindung her — die ' +
    'erste Fassung zeichnete mit Views, was für hundert Umriss-Abschnitte ' +
    'hundert einzeln gedrehte Views bedeutet hätte.',
};

test('jede Abhängigkeit steht mit Begründung in der Erlaubnisliste', () => {
  const paket = JSON.parse(readFileSync(join(APP, 'package.json'), 'utf8')) as {
    dependencies: Record<string, string>;
  };

  const unerklaert = Object.keys(paket.dependencies)
    .filter((name) => ERLAUBTE_ABHAENGIGKEITEN[name] === undefined);

  assert.deepEqual(
    unerklaert, [],
    `Abhängigkeiten ohne Begründung: ${unerklaert.join(', ')}\n` +
    'Eintragen in ERLAUBTE_ABHAENGIGKEITEN mit einem Satz, wofür sie da ist. ' +
    '"Keine Netzwerk-Requests zur Laufzeit" hält nur, wenn bekannt ist, was ' +
    'überhaupt mitläuft.',
  );

  // Und andersherum: Was hier steht und nicht mehr installiert ist, ist eine
  // Notiz über einen Zustand von gestern.
  const verwaist = Object.keys(ERLAUBTE_ABHAENGIGKEITEN)
    .filter((name) => paket.dependencies[name] === undefined);
  assert.deepEqual(verwaist, [], `Nicht mehr installiert: ${verwaist.join(', ')}`);

  for (const [name, grund] of Object.entries(ERLAUBTE_ABHAENGIGKEITEN)) {
    assert.ok(grund.length > 10, `${name}: die Begründung ist keine`);
  }
});

test('kein Paket, das bekanntermassen nach Hause telefoniert', () => {
  // Zusätzlich zur Erlaubnisliste, und nicht statt ihrer: Diese Namen sollen
  // auch dann auffallen, wenn jemand sie mit einer Begründung einträgt.
  const paket = JSON.parse(readFileSync(join(APP, 'package.json'), 'utf8')) as {
    dependencies: Record<string, string>;
    devDependencies?: Record<string, string>;
  };
  const alle = [...Object.keys(paket.dependencies), ...Object.keys(paket.devDependencies ?? {})];

  const VERDAECHTIG = [
    /^@sentry\//, /^@bugsnag\//, /^expo-updates$/, /^expo-analytics/,
    /firebase/, /amplitude/, /mixpanel/, /segment/, /posthog/,
    /^react-native-google-mobile-ads$/, /^axios$/, /^@react-native-firebase\//,
  ];

  const funde = alle.filter((name) => VERDAECHTIG.some((m) => m.test(name)));
  assert.deepEqual(
    funde, [],
    `Abhängigkeiten, die zur Laufzeit senden könnten: ${funde.join(', ')}`,
  );
});

// --- Die Datenpipeline bleibt draussen -------------------------------------

test('die App importiert nichts aus scripts/', () => {
  // scripts/ redet mit Overpass und Natural Earth. Ein Import von dort ins
  // App-Paket wäre der stillste denkbare Weg, das Versprechen zu brechen:
  // Der Code liefe erst, wenn ihn jemand aufruft, und bis dahin fiele nichts
  // auf.
  const funde = QUELLEN
    .filter((q) => /from\s+['"][^'"]*\/scripts\//.test(ohneKommentare(q.text)))
    .map((q) => q.name);
  assert.deepEqual(funde, [], `Import aus scripts/: ${funde.join(', ')}`);
});
