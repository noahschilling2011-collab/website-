---
name: dod
description: Prüft die Definition of Done der aktuellen JARVIS-Phase durch echtes Ausführen und entscheidet, ob die Phase abgenommen wird. Nutze das vor jedem Phasenwechsel.
disable-model-invocation: true
---

# Abnahme

Du prüfst jetzt, ob die aktuelle Phase wirklich fertig ist. **Du bist hier nicht der Baumeister, sondern der Prüfer.** Deine Aufgabe ist es, Lücken zu finden — nicht, die eigene Arbeit zu bestätigen.

## Regeln

1. Lies die Definition of Done aus `docs/phases/PHASE-XX.md` der Phase, die in `STATUS.md` als `AKTUELL` steht.
2. **Jedes** Kriterium wird einzeln geprüft. Kein Sammelurteil.
3. Ein Kriterium bekommt ✓ **nur**, wenn du dafür einen Befehl ausgeführt hast und die echte Ausgabe zeigst. Codelesen reicht nicht. „Sollte funktionieren" ist ✗.
4. Kannst du ein Kriterium nicht automatisch prüfen, weil ein Mensch draufschauen muss (z. B. „das UI zeigt X"): markiere es `MANUELL` mit einer präzisen Anweisung, was der Nutzer anklicken und sehen soll. Nicht ✓.
5. **Ein einziges ✗ heißt: Phase nicht bestanden.** Keine Teilabnahmen, kein „im Wesentlichen fertig".
6. Du darfst während der Prüfung **nichts reparieren**. Erst prüfen, Ergebnis melden, dann fragt der Nutzer nach einem Fix.

## Zusätzliche Prüfungen, unabhängig von der Phase

Diese laufen jedes Mal:

```bash
grep -rn "sk-\|api[_-]key\|Bearer " --include="*.html" --include="*.js" . || echo "kein Key im Frontend"
grep -rn "TODO\|FIXME\|NotImplementedError\|pass  # " --include="*.py" . | head -20
grep -rn "eval(\|exec(\|shell=True" --include="*.py" . || echo "keine gefaehrlichen Aufrufe"
git status --porcelain
pytest -q 2>&1 | tail -5
```

Zusätzlich prüfst du inhaltlich:

- Steht `.env` in `.gitignore` und ist keine echte `.env` eingecheckt?
- Bindet der Server an `127.0.0.1`, nicht an `0.0.0.0`?
- Gibt ein Request ohne `X-Jarvis-Token` wirklich 401? Führ es mit `curl` aus.
- Wurde etwas gebaut, das laut `CLAUDE.md` in dieser Phase ein Non-Goal ist? Das ist ein ✗, auch wenn es funktioniert.
- Rufen die Tests irgendwo ein echtes Modell? Das ist ein ✗.

## Ausgabeformat

```
PHASE X — ABNAHME

1. <Kriterium>            ✓ / ✗ / MANUELL
   Befehl:   <was du ausgeführt hast>
   Ausgabe:  <echte Ausgabe, gekürzt>
   ...

QUERPRÜFUNGEN
   Key im Frontend:       sauber / GEFUNDEN in <datei:zeile>
   Platzhalter im Code:   <anzahl> Stellen
   Non-Goals verletzt:    nein / <was>
   Tests gegen echtes Modell: nein / JA

ERGEBNIS: BESTANDEN / NICHT BESTANDEN
FEHLT NOCH: <Liste, konkret, jeweils eine Zeile>
```

Bei BESTANDEN: `STATUS.md` aktualisieren — Phase auf `FERTIG` mit Datum, die nächste von `GESPERRT` auf `OFFEN`.
Bei NICHT BESTANDEN: `STATUS.md` bleibt unverändert.
