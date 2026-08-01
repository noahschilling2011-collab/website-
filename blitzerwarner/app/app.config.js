/**
 * Dynamische Expo-Konfiguration.
 *
 * WOZU DIESE DATEI, WO ES DOCH app.json GIBT
 *
 * Zwei Android-Berechtigungen landen automatisch im Manifest, obwohl die App
 * sie nicht braucht — und eine davon widerspricht dem Produktversprechen
 * direkt:
 *
 *   INTERNET              von React Native gesetzt. Die App macht zur Laufzeit
 *                         keine Netzwerk-Requests; das ist ihr Alleinstellungs-
 *                         merkmal und steht so im README und im
 *                         Datenschutz-Screen. Eine App, die das verspricht und
 *                         die Berechtigung trotzdem hält, verlangt Vertrauen,
 *                         wo sie Beweis liefern könnte.
 *   SYSTEM_ALERT_WINDOW   von React Native für das Debug-Overlay gesetzt.
 *
 * Beide werden im Entwicklungsbetrieb GEBRAUCHT: Der Dev-Client lädt sein
 * JS-Bundle über das Netz vom Metro-Server, und das Debug-Menü ist ein
 * Overlay. Eine statische Sperre in app.json würde also die Entwicklung
 * unmöglich machen.
 *
 * Deshalb hier eine Fallunterscheidung nach Build-Profil statt einer festen
 * Liste. Die Profile, die bei Nutzern landen (preview, production), bekommen
 * beide Berechtigungen entzogen; der Entwicklungsbetrieb behält sie.
 *
 * Die statischen Werte stehen weiterhin in app.json. Diese Datei ergänzt sie
 * nur — sie schreibt nichts um, was dort steht.
 */

/**
 * Berechtigungen, die immer entfernt werden.
 *
 * Sie kommen aus Abhängigkeiten und beschreiben Fähigkeiten, die diese App
 * nachweislich nicht benutzt:
 *
 *   RECORD_AUDIO            expo-av bringt es mit, weil dieselbe Bibliothek
 *                           auch aufnehmen kann. Diese App spielt nur ab —
 *                           audio/player.ts setzt `allowsRecordingIOS: false`
 *                           und ruft keine einzige Aufnahmefunktion auf. Eine
 *                           Blitzerwarner-App, die das Mikrofon anfordert, ist
 *                           der denkbar schlechteste Anblick im Store.
 *   READ_/WRITE_EXTERNAL_STORAGE
 *                           ebenfalls aus den Medien-Abhängigkeiten. Die App
 *                           schreibt in den Speicher des Geräts nur über
 *                           AsyncStorage (Einstellungen, Fehlerprotokoll); das
 *                           Fahrtprotokoll lebt im Arbeitsspeicher und wird per
 *                           Share-Sheet weitergegeben, nicht selbst abgelegt.
 *   ACCESS_MEDIA_LOCATION   Standortdaten aus fremden Fotos. Stand schon
 *                           vorher auf der Liste.
 */
const IMMER_ENTZOGEN = [
  'android.permission.RECORD_AUDIO',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.ACCESS_MEDIA_LOCATION',
];

/**
 * Berechtigungen, die nur der Entwicklungsbetrieb braucht.
 *
 * Werden in allen anderen Profilen entzogen. Siehe Kopfkommentar.
 */
const NUR_ENTWICKLUNG = [
  'android.permission.INTERNET',
  'android.permission.SYSTEM_ALERT_WINDOW',
];

/**
 * Ist das ein Build für die Entwicklung?
 *
 * EAS_BUILD_PROFILE setzt EAS Build; lokal (`expo start`, `expo run:android`)
 * ist es nicht gesetzt. Die Regel lautet deshalb: Alles ohne Profil gilt als
 * Entwicklung, und von den EAS-Profilen nur 'development'.
 *
 * Die Richtung ist Absicht. Ein Irrtum in die eine Richtung kostet eine
 * Berechtigung zu viel in einem Build, den nur der Entwickler installiert.
 * Ein Irrtum in die andere Richtung machte den Dev-Client unbrauchbar, und
 * zwar mit einem Fehlerbild ("Netzwerkfehler"), das niemand mit der
 * Manifest-Konfiguration in Verbindung bringen würde.
 */
function istEntwicklung() {
  const profil = process.env.EAS_BUILD_PROFILE;
  return profil === undefined || profil === '' || profil === 'development';
}

module.exports = ({ config }) => {
  const entzogen = istEntwicklung()
    ? IMMER_ENTZOGEN
    : [...IMMER_ENTZOGEN, ...NUR_ENTWICKLUNG];

  return {
    ...config,
    android: {
      ...config.android,
      blockedPermissions: entzogen,
    },
    extra: {
      ...config.extra,
      /**
       * Für den Datenschutz-Screen und für den Test: Wurde die
       * Internet-Berechtigung diesem Build entzogen?
       *
       * Die App soll nicht behaupten, was sie nicht weiss. In einem
       * Entwicklungsbuild ist die Berechtigung da, und der Screen sagt das
       * dann auch.
       *
       * ACHTUNG, DAS GILT NUR FÜR ANDROID.
       *
       * blockedPermissions steht unter `android` und wirkt auch nur dort.
       * iOS kennt überhaupt keine Internet-Berechtigung: Jede App darf ins
       * Netz, es gibt nichts zu entziehen und nichts, was der Nutzer in den
       * Systemeinstellungen nachsehen könnte.
       *
       * Dieses Feld war vorher plattformblind, und der Datenschutz-Screen
       * hätte auf einem iPhone behauptet, die Berechtigung sei entzogen und
       * in den App-Informationen nachprüfbar. Beides falsch — auf genau der
       * Plattform, für die diese App zuerst gebaut wird. Der Screen fragt
       * deshalb zusätzlich Platform.OS ab.
       */
      internetEntzogen: !istEntwicklung(),
    },
  };
};

// Für den Test, damit er die Regel prüfen kann, ohne die Umgebung zu raten.
module.exports.IMMER_ENTZOGEN = IMMER_ENTZOGEN;
module.exports.NUR_ENTWICKLUNG = NUR_ENTWICKLUNG;
module.exports.istEntwicklung = istEntwicklung;
