---
name: phase
description: Lädt den Auftrag einer JARVIS-Phase und baut sie. Nutze das, wenn der Nutzer "/phase 2", "bau Phase 3" oder "mach mit der nächsten Phase weiter" sagt.
---

# Phase bauen

Argument ist die Phasennummer. Ohne Argument: die in `STATUS.md` als `AKTUELL`
markierte Phase.

## Reihenfolge

1. **`STATUS.md` lesen.** Ohne Ausnahme, vor allem anderen. Dort steht, was
   wirklich existiert — nicht in deinem Gedächtnis.
2. Wenn die gewünschte Phase nicht die aktuelle ist: **sagen und stoppen.**
   Kein Vorgriff. Wenn eine frühere Phase offene Punkte hat, zuerst die.
3. `docs/phases/PHASE-XX.md` lesen. **Nur die eine.** Andere Phasendateien
   bleiben zu.
4. `docs/contracts.md` lesen, wenn die Phase einen der Verträge berührt.
5. Bauen. Regeln aus `CLAUDE.md` gelten dabei ausnahmslos.
6. `pytest -q` und `python -m scripts.smoke` laufen lassen. **Echte Ausgabe
   zeigen**, nicht zusammenfassen.
7. Definition of Done einzeln durchgehen — wie bei `/dod`.
8. `STATUS.md` aktualisieren: Phase auf FERTIG, nächste auf AKTUELL, gemessene
   Zahlen eintragen, bekannte Grenzen ergänzen.

## Woran du dich nicht vorbeimogelst

- Ein Kriterium, das du nicht geprüft hast, ist nicht erfüllt. Schreib
  `NICHT AUSGEFÜHRT` hin.
- Wenn ein Vertrag aus `docs/contracts.md` nicht passt: melden, nicht
  danebenbauen.
- Wenn du einen API-Key, ein Konto oder Geld brauchst: in den ersten drei
  Sätzen sagen.
- Keine Modell-IDs, Endpunkte oder Signaturen aus dem Gedächtnis. Nachschlagen
  oder `UNSICHER:` schreiben.

## Am Ende

Antworte im Format aus `CLAUDE.md`: GEBAUT / GETESTET / NICHT GETESTET /
START / DoD-CHECK / BLOCKER.
