/**
 * Die Android-Berechtigungen, die im ausgelieferten Build übrig bleiben.
 *
 * DER ANLASS
 *
 * Das erzeugte Manifest enthielt Berechtigungen, die niemand angefordert hat
 * und die dem Produktversprechen widersprechen. Gemessen an einem echten
 * `expo prebuild --platform android`:
 *
 *   INTERNET              von React Native gesetzt — in einer App, deren
 *                         Alleinstellungsmerkmal "keine Netzwerk-Requests zur
 *                         Laufzeit" ist
 *   RECORD_AUDIO          von expo-av gesetzt, weil dieselbe Bibliothek auch
 *                         aufnehmen kann. Mikrofonzugriff in einem
 *                         Blitzerwarner ist der schlechteste denkbare Anblick
 *   READ_/WRITE_EXTERNAL_STORAGE   aus denselben Abhängigkeiten
 *   SYSTEM_ALERT_WINDOW   Debug-Overlay von React Native
 *
 * Ein Nutzer, der im Store die Berechtigungsliste aufklappt, sieht davon
 * nichts vom "warum" — er sieht Mikrofon und Internet. Der Datenschutztext
 * daneben verspricht das Gegenteil, und dann steht Aussage gegen Liste.
 *
 * Dieser Test liest die tatsächliche Konfiguration, nicht eine Kopie davon.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const configModul = require(join(HIER, '..', 'app.config.js')) as {
  (arg: { config: Record<string, unknown> }): { android: { blockedPermissions: string[] }; extra: Record<string, unknown> };
  IMMER_ENTZOGEN: string[];
  NUR_ENTWICKLUNG: string[];
  istEntwicklung: () => boolean;
};

const appJson = require(join(HIER, '..', 'app.json')) as { expo: Record<string, unknown> };

/** Die Konfiguration für ein bestimmtes Build-Profil auswerten. */
function fuerProfil(profil: string | undefined): { blockiert: string[]; extra: Record<string, unknown> } {
  const vorher = process.env.EAS_BUILD_PROFILE;
  if (profil === undefined) delete process.env.EAS_BUILD_PROFILE;
  else process.env.EAS_BUILD_PROFILE = profil;
  try {
    const ergebnis = configModul({ config: appJson.expo });
    return { blockiert: ergebnis.android.blockedPermissions, extra: ergebnis.extra };
  } finally {
    if (vorher === undefined) delete process.env.EAS_BUILD_PROFILE;
    else process.env.EAS_BUILD_PROFILE = vorher;
  }
}

// --- Was immer weg muss ---------------------------------------------------

test('das Mikrofon ist in JEDEM Profil entzogen', () => {
  // Auch im Entwicklungsbuild. Es gibt keinen Fall, in dem diese App
  // aufnimmt: audio/player.ts setzt allowsRecordingIOS: false und ruft keine
  // Aufnahmefunktion auf.
  for (const profil of [undefined, 'development', 'preview', 'production']) {
    assert.ok(
      fuerProfil(profil).blockiert.includes('android.permission.RECORD_AUDIO'),
      `Profil ${profil ?? '(lokal)'}: RECORD_AUDIO ist nicht entzogen`,
    );
  }
});

test('Speicherzugriff ist in jedem Profil entzogen', () => {
  for (const profil of [undefined, 'development', 'preview', 'production']) {
    const b = fuerProfil(profil).blockiert;
    for (const recht of ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'ACCESS_MEDIA_LOCATION']) {
      assert.ok(
        b.includes(`android.permission.${recht}`),
        `Profil ${profil ?? '(lokal)'}: ${recht} ist nicht entzogen`,
      );
    }
  }
});

// --- Das Produktversprechen -----------------------------------------------

test('die ausgelieferten Profile haben KEINE Internet-Berechtigung', () => {
  // Das ist die Zusage, um die es geht. "Keine Netzwerk-Requests zur Laufzeit"
  // lässt sich behaupten oder beweisen — ohne die Berechtigung ist es
  // bewiesen, und zwar auf eine Art, die der Nutzer im Store selbst nachsehen
  // kann.
  for (const profil of ['preview', 'production']) {
    const { blockiert, extra } = fuerProfil(profil);
    assert.ok(
      blockiert.includes('android.permission.INTERNET'),
      `Profil ${profil}: INTERNET ist nicht entzogen — das Versprechen wäre nur behauptet`,
    );
    assert.equal(extra.internetEntzogen, true, `Profil ${profil}: extra sagt etwas anderes`);
  }
});

test('der Entwicklungsbetrieb behält Internet und Overlay', () => {
  // Die Gegenprobe, und sie ist nicht Formsache: Ohne INTERNET erreicht der
  // Dev-Client den Metro-Server nicht, und das Fehlerbild ("Netzwerkfehler")
  // bringt niemand mit der Manifest-Konfiguration in Verbindung.
  for (const profil of [undefined, 'development']) {
    const { blockiert, extra } = fuerProfil(profil);
    assert.ok(
      !blockiert.includes('android.permission.INTERNET'),
      `Profil ${profil ?? '(lokal)'}: INTERNET entzogen — der Dev-Client wäre unbrauchbar`,
    );
    assert.ok(
      !blockiert.includes('android.permission.SYSTEM_ALERT_WINDOW'),
      `Profil ${profil ?? '(lokal)'}: kein Debug-Overlay möglich`,
    );
    assert.equal(extra.internetEntzogen, false);
  }
});

test('ohne gesetztes Profil gilt Entwicklung, nicht Auslieferung', () => {
  // Die Richtung der Annahme. Ein Irrtum hier kostet eine Berechtigung zu
  // viel in einem Build, den nur der Entwickler installiert — der umgekehrte
  // Irrtum machte die Entwicklung unmöglich.
  const vorher = process.env.EAS_BUILD_PROFILE;
  delete process.env.EAS_BUILD_PROFILE;
  try {
    assert.equal(configModul.istEntwicklung(), true);
  } finally {
    if (vorher !== undefined) process.env.EAS_BUILD_PROFILE = vorher;
  }
});

// --- Was bleiben MUSS -----------------------------------------------------

test('die gebrauchten Berechtigungen werden nicht versehentlich mitentzogen', () => {
  // Die andere Richtung. Wer die Sperrliste erweitert, ohne zu prüfen, nimmt
  // der App im schlimmsten Fall den Hintergrundstandort — und dann warnt sie
  // bei ausgeschaltetem Display nicht mehr, also in genau dem Zustand, für
  // den sie gebaut ist.
  const gebraucht = [
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_BACKGROUND_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.WAKE_LOCK',
    'android.permission.VIBRATE',
    'android.permission.MODIFY_AUDIO_SETTINGS',
  ];

  for (const profil of [undefined, 'development', 'preview', 'production']) {
    const b = fuerProfil(profil).blockiert;
    for (const recht of gebraucht) {
      assert.ok(!b.includes(recht), `Profil ${profil ?? '(lokal)'}: ${recht} wurde entzogen`);
    }
  }
});

test('app.config.js überschreibt die statische Konfiguration nicht', () => {
  // Die Datei ergänzt app.json, sie ersetzt es nicht. Ginge dabei etwas
  // verloren — etwa die drei NSLocation-Texte oder die Android-Rechteliste —,
  // wäre das ein Absturz beim ersten Rechtedialog.
  const ergebnis = configModul({ config: appJson.expo }) as unknown as Record<string, unknown>;
  for (const schluessel of ['name', 'slug', 'scheme', 'ios', 'plugins', 'version']) {
    assert.deepEqual(
      ergebnis[schluessel], appJson.expo[schluessel],
      `${schluessel} wurde von app.config.js verändert`,
    );
  }

  // Die Android-Rechteliste bleibt erhalten, nur blockedPermissions kommt dazu.
  const android = ergebnis.android as Record<string, unknown>;
  const androidStatisch = appJson.expo.android as Record<string, unknown>;
  assert.deepEqual(android.permissions, androidStatisch.permissions);
  assert.deepEqual(android.package, androidStatisch.package);
});
