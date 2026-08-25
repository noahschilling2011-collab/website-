---
name: dod
description: Prüft die Definition of Done der aktuellen JARVIS-Phase ehrlich nach — jedes Kriterium einzeln, mit Ausführung statt Behauptung. Nutze das bei "/dod", "ist die Phase fertig?" oder "prüf das mal nach".
---

# Definition of Done prüfen

Der Zweck ist, eine Phase **durchfallen zu lassen**, wenn sie nicht fertig ist.
Ein DoD-Check, der immer grün ist, ist wertlos.

## Reihenfolge

1. `STATUS.md` lesen: welche Phase steht auf `AKTUELL`.
2. `docs/phases/PHASE-XX.md` lesen, Abschnitt *Definition of Done*.
3. Jedes Kriterium **einzeln** durchgehen. Für jedes:
   - Welcher Befehl oder welche Beobachtung weist es nach?
   - Den Befehl **ausführen**. Ausgabe zeigen.
   - Bewerten: ✓ oder ✗.

## Bewertungsregeln

- **Nicht ausgeführt = nicht erfüllt.** Schreib `NICHT AUSGEFÜHRT` und ✗.
- „Der Code sieht richtig aus" ist kein Nachweis. Ausführen.
- Ein Kriterium, das nur mit einem echten API-Key prüfbar ist, ist **nicht**
  von dir erfüllbar. Markier es als offen für den Nutzer und sag genau, welcher
  Befehl es abschließt.
- Wenn du einen Test angepasst hast, damit er grün wird: sag das. Ein
  angepasstes Kriterium ist kein erfülltes Kriterium.
- Budgets, Limits und Grenzwerte werden nicht erhöht, um durchzukommen.

## Ausgabe

Eine Tabelle: Kriterium, Nachweis (Befehl), Ergebnis (✓/✗), Anmerkung.

Darunter ein klares Urteil:

- **FERTIG** — alle Kriterien ✓.
- **NICHT FERTIG** — mit der Liste dessen, was fehlt, und was als Nächstes zu
  tun ist.

Bei FERTIG: `STATUS.md` aktualisieren. Bei NICHT FERTIG: `STATUS.md` nicht
anfassen.
