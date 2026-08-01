/**
 * Attrappe für react-native-svg.
 *
 * Dieselbe Begründung wie bei der react-native-Attrappe: Die echte
 * Bibliothek hat einen nativen Teil und lässt sich unter Node nicht laden.
 * Ohne Ersatz wäre das Kartenbild ungetestet — und das Kartenbild ist der
 * einzige Ort in der App, an dem etwas gezeichnet statt beschriftet wird.
 *
 * Die Elemente behalten ihren Namen und ihre Props. Mehr braucht der Test
 * nicht: Er zählt, was gezeichnet wurde, und liest die Koordinaten. Er prüft
 * NICHT, wie es aussieht — dafür gibt es kein Node-Äquivalent, und eine
 * Attrappe, die zu rendern versucht, testet am Ende sich selbst.
 */
import { createElement, type ReactNode } from 'react';

type Props = Record<string, unknown> & { children?: ReactNode };

function host(name: string) {
  const K = (props: Props) => createElement(name, props, props.children);
  K.displayName = name;
  return K;
}

export const Svg = host('Svg');
export const G = host('G');
export const Circle = host('Circle');
export const Line = host('Line');
export const Polyline = host('Polyline');
export const Path = host('Path');
export const Rect = host('Rect');
export const Text = host('SvgText');

export default Svg;
