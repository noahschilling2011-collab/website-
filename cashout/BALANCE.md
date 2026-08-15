# Balancing — gemessen, nicht geschätzt

**Keine Konstante wurde angefasst.** In `Balance.lua` stehen exakt die Zahlen aus der
Spezifikation. Was hier steht, ist das Messergebnis dazu.

Reproduzieren: `tools/balance_sim.sh [pfad/zu/luau]` (Standalone-Luau-CLI nötig, siehe
Kopf des Skripts). Das Skript liest `Balance.lua` direkt ein und hält keine eigene
Kopie der Zahlen.

## Methode

Pro Stufe eine Strategie: „immer diese Stufe spielen, ab Heat X zur Bank". Simuliert
werden 600 s Runde, Laufweg Terminal ↔ Bank (150 Studs = 9,4 s pro Richtung bei
WalkSpeed 16), 8 s Einzahlen, Heat-Zerfall, Razzia-Würfe alle 15 s und der 3-s-Stun.
Nicht eingezahlter Cash zählt nicht. Für jede Stufe ist X von 10 bis 100 durchprobiert
und der beste Wert ausgewiesen — also *optimales* Spiel auf jeder Stufe, 3000 Durchläufe.
Für „Extrem" spielt der Simulierte „Groß", solange Heat < 50 ist, weil Extrem-Karten
sonst gar nicht im Angebot wären.

## Ergebnis

| Stufe | Bank ab Heat | Banked ⌀ | vs. Klein | Razzien/Runde |
|---|---|---|---|---|
| Klein | (nie erreicht) | 5584 | 1,00× | 0,00 |
| Mittel | 40 | 7673 | 1,37× | 0,57 |
| Groß | 50 | 10266 | **1,84×** | 1,19 |
| Extrem | 95 | 13767 | 2,47× | 4,46 |

## Die drei Abweichungen

**1. Groß bringt 1,84×, nicht ~2,5×.**
Die Spezifikation erwartet für Dauer-Groß-Spiel ca. das 2,5-fache von Dauer-Klein-Spiel.
Gemessen sind 1,84×. Der Unterschied ist real und liegt an Punkt 2.

**2. Klein hat null Risiko — strukturell, nicht zufällig.**
Ein kleiner Deal gibt +1 Heat in 6 s. Der Zerfall nimmt in denselben 6 s zwei Punkte
weg. Netto **−1 Heat pro Deal**: wer nur Klein spielt, bleibt für immer bei Heat 0 und
wird in 3000 simulierten Runden kein einziges Mal erwischt. Die Heat-Mechanik ist auf
der untersten Stufe abgeschaltet, nicht bloß entschärft. Heat pro Sekunde gegen den
Zerfall von 0,33/s gerechnet: Klein 0,17 · Mittel 0,60 · Groß 1,00 · Extrem 1,36.
Nur Klein liegt darunter.

**3. Extrem lohnt sich, ohne je einzuzahlen.**
Der beste Einzahl-Schwellwert für Extrem ist 95 — praktisch „nie einzahlen, bis die
Runde endet". Bei ⌀ 4,46 Razzien pro Runde ist Extrem trotzdem die stärkste Strategie.
Der 60-%-Verlust ist gegen 900–1600 pro 22 s zu billig. Damit fällt für die stärkste
Stufe genau die Entscheidung weg, um die das Spiel gebaut ist.

## Zwei Stellschrauben, gemessen statt geraten

Beides ist **nicht** eingebaut — die Zahlen unten kommen aus Probeläufen.

- **Klein-Payout 40–80 → 30–58** ergibt Groß = **2,51×**, also exakt die erwartete Größe.
  Weil Klein risikofrei ist, wirkt sein Payout streng linear, die Zahl ist damit
  belastbar. Nebenwirkung: Extrem steigt auf 3,36×.
- **`RaidChanceScale` 0,25 → 0,40** drückt Extrems besten Schwellwert von 95 auf 75 —
  Einzahlen wird dort wieder zu einer echten Entscheidung — und Extrems Vorsprung von
  2,47× auf 2,05×. Groß bleibt bei 1,78×.

Welche davon (oder ob überhaupt) ist eine Design-Entscheidung, keine Bugfix-Frage.
