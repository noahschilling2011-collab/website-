---
name: status
description: Leitet den Projektstand von JARVIS aus STATUS.md und git ab und meldet Abweichungen. Nutze das bei "/status", "wo stehen wir?" oder "was ist der Stand?".
---

# Projektstand

## Reihenfolge

1. `STATUS.md` lesen — das ist die Behauptung.
2. Gegen die Wirklichkeit prüfen:
   ```bash
   git log --oneline -10
   git status --short
   pytest -q 2>&1 | tail -3
   ```
3. Abweichungen zwischen Behauptung und Wirklichkeit **benennen**. Genau dafür
   ist dieser Befehl da. Beispiele:
   - `STATUS.md` sagt fertig, aber `pytest` ist rot.
   - Es liegen Dateien im Baum, die in keiner Phase vorkommen.
   - Uncommittete Änderungen an Kerndateien.

## Ausgabe

Kurz. Kein Bericht, ein Lagebild:

```
AKTUELL:     Phase N — <Titel>
FERTIG:      Phasen 1..N-1
TESTS:       <Zahl> passed / failed
ARBEITSBAUM: sauber | <n> geänderte Dateien
OFFEN:       was der Nutzer selbst erledigen muss (Keys, Konten, Geld)
ABWEICHUNG:  wo STATUS.md und Wirklichkeit auseinandergehen — oder "keine"
```

Nichts bauen. Dieser Befehl schaut nur.
