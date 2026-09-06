---
name: status
description: Zeigt den echten JARVIS-Projektstand aus STATUS.md, git und dem Dateisystem. Nutze das am Anfang jeder Session oder nach einem /clear.
---

# Projektstand

## Automatisch eingelesener Kontext

- STATUS.md: !`sed -n '1,40p' STATUS.md 2>/dev/null || echo "STATUS.md fehlt"`
- Letzte Commits: !`git log --oneline -8 2>/dev/null || echo "kein git-Repo"`
- Uncommitted: !`git status --porcelain 2>/dev/null | head -20`
- Vorhandene Module: !`find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" 2>/dev/null | head -30`
- Tests: !`pytest -q 2>&1 | tail -3`

> Hinweis: Die `!`-Syntax für Kontext-Injektion ist eine Claude-Code-Erweiterung.
> Falls sie in deiner Version nicht greift, führ die Befehle einfach selbst aus.

## Deine Aufgabe

Gleiche ab, was `STATUS.md` behauptet, mit dem, was wirklich im Repo liegt.

Antworte in **maximal 12 Zeilen**:

1. Welche Phase ist laut STATUS.md aktuell, und ist das plausibel angesichts des Codes?
2. Widersprüche zwischen STATUS.md und Realität — beim Namen nennen.
3. Läuft das Projekt gerade? (Tests grün? Startet der Server?)
4. Offene Blocker aus STATUS.md.
5. Der eine nächste Schritt.

Keine Zusammenfassung des Projekts, keine Wiederholung der Architektur. Der Nutzer kennt sein Projekt. Er will wissen, wo er stehengeblieben ist.

Wenn STATUS.md und Code auseinanderlaufen: **sag es deutlich.** Eine als `FERTIG` markierte Phase ohne passenden Code ist das häufigste Problem in diesem Projekt.
