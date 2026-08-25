# Phase 5 — Aufgaben

## Ziel
Ein Auftrag, der mehrere Schritte braucht, läuft ab, ist nachvollziehbar und
hört auf, wenn das Budget alle ist.

## Was gebaut wird
- `Task`, `Step`, `TaskBudget` nach `docs/contracts.md`, persistiert.
- Runner: Schritt persistieren, ausführen, Ergebnis schreiben. In dieser
  Reihenfolge, damit ein Absturz nachvollziehbar bleibt.
- Abbruch von außen.
- Oberfläche: laufende Aufgaben, Schrittliste, verbrauchtes Budget.

## Definition of Done
1. Ein Task über mindestens drei Schritte läuft durch, jeder Schritt steht
   einzeln in der Datenbank.
2. Jede der vier Grenzen (`max_steps`, `max_tokens`, `max_seconds`,
   `max_cost_usd`) beendet den Task nachweislich — je ein Test.
3. Ein beendeter Task erhöht sein Budget nicht selbst.
4. Nach einem Prozessabsturz ist am Datenbankstand erkennbar, welcher Schritt
   lief.
