# Phase 6 — Agenten

## Ziel
Mehrere benannte Agenten mit eigenem Systemprompt, eigenem Werkzeugsatz und
eigenem Modell. Delegation zwischen ihnen.

## Was gebaut wird
- `Agent` nach `docs/contracts.md`, definiert in einer Datei, nicht im Code.
- Delegation: ein Agent gibt einen Teil seines Budgets ab. Es entsteht keines.
- Zusammenführung der Ergebnisse.
- Oberfläche: sichtbar, welcher Agent gerade was tut.

## Definition of Done
1. Zwei Agenten mit unterschiedlichen Werkzeugsätzen; keiner sieht die
   Werkzeuge des anderen.
2. Delegation summiert sich auf das Ausgangsbudget — Test rechnet nach.
3. Eine Delegationskette hat eine Tiefengrenze und schlägt sauber an.
