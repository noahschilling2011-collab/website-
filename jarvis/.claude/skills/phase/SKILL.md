---
name: phase
description: Lädt genau eine JARVIS-Bauphase und arbeitet sie ab. Nutze das, wenn eine Phase gebaut, fortgesetzt oder neu gestartet werden soll.
argument-hint: "<phasennummer>"
disable-model-invocation: true
---

# Phase bauen

Argument: `$ARGUMENTS` (die Phasennummer). Ohne Argument nimmst du die Phase, die in `STATUS.md` als `AKTUELL` steht.

## Ablauf — in dieser Reihenfolge, ohne Abkürzung

1. Lies `STATUS.md`.
   - Ist die angeforderte Phase `GESPERRT`, weil die vorherige nicht `FERTIG` ist: **brich ab** und sag welche Phase zuerst dran ist. Baue sie nicht trotzdem.
2. Lies `docs/phases/PHASE-XX.md` für **genau diese** Nummer. Keine anderen Phasendateien.
3. Lies `docs/contracts.md` nur, wenn du in dieser Phase Datentypen anfasst.
   Bei Phase 8 zusätzlich `docs/satellite.md`.
4. Sieh dir an, was schon existiert (`git status`, Verzeichnisbaum). Bau nichts neu, was schon da ist.
5. Nenne **vor** dem ersten Code in maximal fünf Zeilen:
   - was du bauen wirst
   - welche Dateien entstehen oder sich ändern
   - welche Blocker es gibt (Keys, Konten, Kosten, fehlende Doku)
6. Bauen. Nach jeder größeren Datei: ausführen und die echte Ausgabe zeigen.
7. Tests schreiben, wo die Phase es verlangt. Tests laufen gegen `FakeLLMProvider`, **nie** gegen ein echtes Modell.
8. `/dod` gedanklich durchgehen und im Antwortformat aus `CLAUDE.md` abschließen.
9. `STATUS.md` aktualisieren: Phase auf `IN ARBEIT`, offene Blocker eintragen.
   **Erst `/dod` darf eine Phase auf `FERTIG` setzen — du nicht.**

## Verboten in diesem Skill

- Dateien anlegen, die zu einer späteren Phase gehören.
- Klassenrümpfe mit `pass` in Pfaden, die die Definition of Done betreffen.
- Ordnerstrukturen ohne eine einzige lauffähige Datei darin.
- Behaupten, etwas funktioniere, ohne es ausgeführt zu haben.
- Ein Limit, Timeout oder Budget erhöhen, damit etwas durchläuft. Stattdessen melden.

## Wenn du blockiert bist

Sag es sofort und konkret: welche Information fehlt, wo sie herkäme, was du in der Zwischenzeit bauen kannst. Rate nicht, um weiterzukommen.
