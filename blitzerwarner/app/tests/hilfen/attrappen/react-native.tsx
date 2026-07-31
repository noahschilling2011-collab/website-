/**
 * Attrappe für react-native.
 *
 * WOZU
 *
 * `react-native` lässt sich unter Node nicht laden — die Datei enthält
 * Flow-Typen, die esbuild nicht übersetzt ("Unexpected typeof"). Damit war die
 * gesamte Oberfläche ungetestet: 347 Tests, und kein einziger hat je einen
 * Screen gerendert.
 *
 * Diese Attrappe ersetzt genau die elf Bausteine, die die Screens benutzen,
 * durch schlichte Host-Komponenten. Was sie NICHT prüft: Aussehen, Layout,
 * Touch-Ziele, Farben auf dem Display. Was sie prüft: dass der Screen ohne
 * Absturz rendert — also der Fall "App öffnet sich und ist sofort weg".
 *
 * Bewusst so klein wie möglich gehalten. Eine Attrappe, die mehr kann als
 * gebraucht wird, testet am Ende sich selbst.
 */
import { createElement, type ReactNode } from 'react';

type Props = Record<string, unknown> & { children?: ReactNode };

/** Eine Host-Komponente, die ihren Namen und ihre Props behält. */
function host(name: string) {
  const K = (props: Props) => createElement(name, props, props.children);
  K.displayName = name;
  return K;
}

export const View = host('View');
export const Text = host('Text');
export const ScrollView = host('ScrollView');
export const Pressable = host('Pressable');
export const Switch = host('Switch');
export const StatusBar = host('StatusBar');

/**
 * StyleSheet.create gibt die Objekte unverändert zurück.
 *
 * In React Native liefert es Zahlen (Registry-IDs). Für den Rendertest ist
 * das gleichgültig — und die Objekte durchzureichen macht sichtbar, welche
 * Stile gesetzt wurden.
 */
export const StyleSheet = {
  create: <T,>(stile: T): T => stile,
  flatten: (s: unknown) => s,
  absoluteFillObject: {},
  hairlineWidth: 1,
};

/**
 * Animated: die Werte rechnen nicht, sie merken sich nur.
 *
 * Der Fahrt-Screen lässt einen Punkt pulsieren. Für den Rendertest muss die
 * Animation nicht laufen — sie darf nur nicht werfen.
 */
class AnimatedValue {
  constructor(private wert: number) {}
  setValue(w: number): void { this.wert = w; }
  interpolate(): AnimatedValue { return this; }
  // react-test-renderer serialisiert Props; ohne das landet die Instanz roh
  // im Baum und der Vergleich wird unlesbar.
  toJSON(): number { return this.wert; }
}

const animation = { start: (cb?: () => void) => cb?.(), stop: () => {}, reset: () => {} };

export const Animated = {
  Value: AnimatedValue,
  View: host('Animated.View'),
  Text: host('Animated.Text'),
  timing: () => animation,
  sequence: () => animation,
  loop: () => animation,
  parallel: () => animation,
  delay: () => animation,
};

export const Easing = {
  linear: (t: number) => t,
  ease: (t: number) => t,
  inOut: (f: unknown) => f,
  in: (f: unknown) => f,
  out: (f: unknown) => f,
};

/**
 * Die drei Plattform-Dienste, die die Screens anfassen.
 *
 * Alle drei geben etwas Harmloses zurück und merken sich die Aufrufe, damit
 * ein Test prüfen kann, DASS geteilt oder geöffnet wurde — ohne dass dabei
 * wirklich etwas das Gerät verlässt.
 */
export const aufrufe: { share: unknown[]; openURL: string[] } = { share: [], openURL: [] };

export const Share = {
  share: async (inhalt: unknown) => {
    aufrufe.share.push(inhalt);
    return { action: 'sharedAction' as const };
  },
};

export const Linking = {
  openURL: async (url: string) => { aufrufe.openURL.push(url); },
  canOpenURL: async () => true,
};

export const AccessibilityInfo = {
  isReduceMotionEnabled: async () => false,
  addEventListener: () => ({ remove: () => {} }),
};

export const Platform = { OS: 'ios' as const, select: (o: Record<string, unknown>) => o.ios ?? o.default };
export const Vibration = { vibrate: () => {} };
export const Dimensions = { get: () => ({ width: 390, height: 844, scale: 3, fontScale: 1 }) };
