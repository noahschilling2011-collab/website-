# Nexus Design-System

Single Source of Truth: `app/lib/core/theme/tokens.dart` (`NexusTokens`)
und `app_theme.dart` (`NexusTheme`).

## Farben

| Token | Wert | Verwendung |
|---|---|---|
| `primary` | `#5B5FEF` | Markenfarbe, CTAs, aktive Zustände |
| `primaryDark` | `#8B8DF5` | Primary auf dunklen Flächen |
| `accent` | `#00C2A8` | Erfolg, Fortschritt, Hervorhebungen |
| `danger` | `#E5484D` | Fehler, destruktive Aktionen |
| `warning` | `#F5A623` | Warnungen, hohe Priorität |
| `surfaceLight/Dark` | `#F7F7FA` / `#101014` | App-Hintergrund |
| `cardLight/Dark` | `#FFFFFF` / `#1A1A21` | Karten, Eingabefelder, Navigation |

Alle weiteren Farben werden aus dem Seed (`primary`) per Material-3
`ColorScheme.fromSeed` abgeleitet — hell und dunkel bleiben automatisch
konsistent.

## Abstände & Radien

- 4-pt-Raster: `s1=4 · s2=8 · s3=12 · s4=16 · s5=24 · s6=32 · s7=48`
- Radien: `radiusS=8` (Snackbar, kleine Chips), `radiusM=14`
  (Karten, Buttons, Inputs), `radiusL=22` (Chat-Bubbles, Sheets)

## Motion

Apple-orientierte Kurven und Dauern:

| Token | Wert | Einsatz |
|---|---|---|
| `fast` | 180 ms | Micro-Interactions (Checkbox, Icon-Wechsel) |
| `normal` | 300 ms | Einblendungen, Bubble-Entrance |
| `slow` | 500 ms | Screen-Intros (Login) |
| `easeOutExpo` | cubic(0.16, 1, 0.3, 1) | Standard-Easing für Eintritt |
| `easeSpring` | cubic(0.34, 1.56, 0.64, 1) | Überschwingende, „federnde" Effekte |

Muster in der App: Fade + Slide beim Login-Intro, gestaffelte
Bubble-Entrances im Chat (`TweenAnimationBuilder`), `AnimatedSwitcher`
für Senden-Button ↔ Spinner, `AnimatedDefaultTextStyle` beim Abhaken.

## Plattform-Anmutung

- **Material 3** als Basis (NavigationBar, FilledButton, Cards, InkSparkle).
- **iOS:** Cupertino-Page-Transitions auf iOS/macOS, Predictive Back auf
  Android — Navigation fühlt sich auf jeder Plattform nativ an.
- **Adaptiv:** unter 800 px Bottom-Navigation, darüber NavigationRail.

## Komponenten-Konventionen

- Buttons: `FilledButton` (primär), `FilledButton.tonal` (sekundär),
  `TextButton` (tertiär); Mindesthöhe 48 px (Touch-Target).
- Eingaben: gefüllte Felder ohne Rahmen, Radius M.
- Karten: Elevation 0 + Flächenfarbe statt Schatten (ruhigeres Bild,
  besser im Dark Mode).
- Dark/Light Mode: nie Farben hart kodieren — immer über
  `Theme.of(context).colorScheme` bzw. Tokens.
