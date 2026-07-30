/**
 * Audio-Routen: CarPlay, Bluetooth-Headset, Telefonlautsprecher.
 *
 * Warum diese Datei existiert: Die App ist audio-first. Wo der Ton landet,
 * entscheidet darüber, ob eine Warnung ankommt — und die Route wechselt
 * während der Fahrt, wenn ein Headset einschläft, das Auto CarPlay verbindet
 * oder ein Anruf dazwischenkommt.
 *
 * Die Entscheidungslogik steht hier als reine Funktion. Das ERKENNEN der
 * Route braucht dagegen nativen Code (siehe RouteErkenner unten) — Expo legt
 * AVAudioSession.currentRoute nicht offen. Diese Trennung ist Absicht: So ist
 * das Verhalten testbar, auch solange die Erkennung noch nicht steht.
 */
import { AUDIO } from '../config';

export type Route =
  /** CarPlay: Ton über die Autoanlage, Display im Armaturenbrett. */
  | 'carplay'
  /** Bluetooth-Freisprecheinrichtung oder A2DP im Auto. */
  | 'bluetooth_auto'
  /** Bluetooth-Headset, typisch Motorradhelm. */
  | 'bluetooth_headset'
  /** Kabelgebundene Kopfhörer. */
  | 'kabel'
  /** Telefonlautsprecher. */
  | 'lautsprecher'
  /** Noch nicht bestimmt — solange die native Erkennung fehlt. */
  | 'unbekannt';

/**
 * Schnittstelle für die Routen-Erkennung.
 *
 * Muss von einem nativen Modul erfüllt werden. Bis dahin liefert die
 * Attrappe 'unbekannt', und die App verhält sich wie bisher — statt eine
 * Erkennung vorzutäuschen, die es nicht gibt.
 */
export interface RouteErkenner {
  aktuelleRoute(): Route;
  /** Rückruf bei Routenwechsel. Gibt eine Abmeldefunktion zurück. */
  beiWechsel(hoerer: (neu: Route) => void): () => void;
}

/** Platzhalter, solange kein natives Modul eingebunden ist. */
export const KEINE_ERKENNUNG: RouteErkenner = {
  aktuelleRoute: () => 'unbekannt',
  beiWechsel: () => () => {},
};

/**
 * Gibt diese Route Anlass zur Annahme, dass der FAHRER das Gerät bedient?
 *
 * Das ist keine Spielerei, sondern der rechtlich heikle Punkt. CarPlay bringt
 * die App auf den eingebauten Bildschirm des Fahrzeugs. Dieser Bildschirm
 * wird vom Fahrer bedient — das ist der Zweck von CarPlay, nicht ein
 * Nebeneffekt.
 *
 * § 23 Abs. 1c StVO richtet sich an den Fahrzeugführer. Das OLG Karlsruhe hat
 * mit Beschluss vom 07.02.2023, Az. 2 ORbs 35 Ss 9/23, entschieden, dass eine
 * Ordnungswidrigkeit des Fahrers selbst dann vorliegt, wenn der Beifahrer die
 * App bedient und der Fahrer sich die Warnung zunutze macht. Eine Anzeige im
 * Armaturenbrett ist demgegenüber der eindeutigere Fall.
 *
 * Die Konsequenz ist deshalb bewusst restriktiv: Eine erkannte CarPlay-
 * Verbindung VERSCHÄRFT das Länder-Gate, sie lockert es nicht. Ein
 * Motorradhelm-Headset dagegen sagt über die Bedienung nichts aus.
 */
export function deutetAufFahrerbedienung(route: Route): boolean {
  return route === 'carplay';
}

/**
 * Lautstärkefaktor je Route.
 *
 * Ein Motorradhelm bei 100 km/h ist ein anderer Ort als ein Autoinnenraum.
 * Die Werte sind Ausgangswerte und gehören am Gerät nachgemessen — hier
 * stehen sie, damit sie an einer Stelle stehen und nicht im Code verstreut.
 */
export function lautstaerkeFaktor(route: Route, motorradModus: boolean): number {
  // Motorradmodus: Fahrtwind übertönt alles, hier wird nicht gedämpft.
  // Auch nicht über die Autoanlage — wer den Modus einschaltet, sitzt nicht
  // im Auto, und eine erkannte Auto-Route ist dann eher ein Irrtum der
  // Erkennung als ein Grund, leiser zu werden.
  if (motorradModus) return 1;

  switch (route) {
    // Die Autoanlage ist laut genug; volle Aussteuerung wirkt dort schrill.
    case 'carplay':
    case 'bluetooth_auto':
      return 0.8;
    case 'kabel':
      return 0.7;
    // Der Telefonlautsprecher ist der schwächste Weg und muss gegen
    // Fahrgeräusch ankommen.
    case 'lautsprecher':
      return 1;
    default:
      return 0.9;
  }
}

/**
 * Braucht diese Route die Aufwach-Pause vor der Sprachansage?
 *
 * Bluetooth-Geräte gehen nach einigen Sekunden Stille in einen Ruhezustand.
 * Startet man direkt mit Sprache, weckt der erste Laut die Verbindung und die
 * ersten Silben sind verloren — der Nutzer hört "...zer in vierhundert
 * Metern". Kabel und Telefonlautsprecher haben dieses Problem nicht, aber
 * die Pause kostet dort nur Millisekunden. Bei 'unbekannt' wird gewartet:
 * Eine überflüssige Pause ist harmlos, eine fehlende kostet die Warnung.
 */
export function brauchtAufwachPause(route: Route): boolean {
  return route !== 'kabel' && route !== 'lautsprecher';
}

export function aufwachPauseMs(route: Route): number {
  return brauchtAufwachPause(route) ? AUDIO.WAKEUP_DELAY_MS : 0;
}

/**
 * Soll ein Routenwechsel angesagt werden?
 *
 * Nur wenn er die Hörbarkeit verschlechtert. Wer vom Telefonlautsprecher auf
 * CarPlay wechselt, merkt das ohnehin und braucht keine Meldung. Wer
 * umgekehrt mitten in der Fahrt sein Headset verliert, muss es erfahren —
 * sonst verlässt er sich auf eine Warnung, die er nicht mehr hören wird.
 */
export function wechselAnsagen(vorher: Route, nachher: Route): boolean {
  if (vorher === nachher) return false;
  if (vorher === 'unbekannt') return false; // erster Start, kein Wechsel
  const rang: Record<Route, number> = {
    carplay: 4,
    bluetooth_auto: 3,
    bluetooth_headset: 3,
    kabel: 2,
    lautsprecher: 1,
    unbekannt: 0,
  };
  return rang[nachher] < rang[vorher];
}
