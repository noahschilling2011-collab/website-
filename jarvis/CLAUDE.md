# JARVIS

Persönliches AI-Operating-System. Wird **phasenweise** gebaut. Sprache: Deutsch, du-Form.

> Diese Datei wird jede Session geladen und ist deshalb absichtlich kurz.
> Details stehen in `docs/` und werden nur geladen, wenn sie gebraucht werden.

## Wo wir stehen

`STATUS.md` ist die einzige Wahrheit über den Projektstand. **Lies sie, bevor du irgendetwas baust.**
Nach jeder abgeschlossenen Phase aktualisierst du sie.

## Arbeitsweise

- Es wird genau **eine Phase** bearbeitet — die in `STATUS.md` als `AKTUELL` markierte.
- Phasenauftrag steht in `docs/phases/PHASE-XX.md`. Lies **nur** die aktuelle.
- Eine Phase ist fertig, wenn ihre Definition of Done erfüllt ist — geprüft mit `/dod`, nicht behauptet.
- Kein Vorgriff auf spätere Phasen. Auch nicht „schon mal vorbereitet".

## Harte Regeln

1. **Keine erfundenen APIs.** Keine Endpunkte, Parameter, Modell-IDs oder Bibliotheks-Signaturen aus dem Gedächtnis. Bei Unsicherheit: Doku nachschlagen oder `UNSICHER:` schreiben. Lieber nachfragen als raten.
2. **Kein Code ohne Ausführung.** Schreiben, starten, echte Ausgabe zeigen. Was du nicht ausgeführt hast, markierst du mit `NICHT AUSGEFÜHRT`.
3. **Blocker in den ersten drei Sätzen.** API-Key nötig, kostet Geld, geht technisch nicht → sofort sagen, nicht nach 800 Wörtern.
4. **Der LLM-API-Key gehört nie ins Frontend.** Kein Modellaufruf aus dem Browser. Alles über das eigene Backend.
5. **Kein `eval`, kein `exec`, kein `shell=True`** mit Eingaben, die aus einem Modell oder vom Nutzer kommen.
6. **Budgets werden nicht stillschweigend erhöht**, um einen Test grün zu bekommen. Wenn ein Limit stört: melden.

## Stack (nicht verhandeln)

Python 3.11+ · FastAPI · uvicorn · SQLite (Stdlib) · httpx · pydantic-settings · pytest
Frontend: **eine** `index.html`, Vanilla JS, kein Build-Step (bis Phase 7).
Frontend-Stil: Dark Theme, Glassmorphism (echtes `backdrop-filter`), ruhige Animationen 200–400 ms, eine Akzentfarbe.

## Non-Goals (bis die jeweilige Phase es freigibt)

Docker (Phase 10) · Postgres / pgvector (Phase 10, nur nach Messung) · React / Next.js / Build-Step (Phase 7) · Vektor-DB (nicht vor Phase 3, dort erst FTS5) · Wake Word · Nutzerverwaltung · Deployment · **Computer Agent, der Programme oder UI steuert — dauerhaft gestrichen.**

## Verträge

`docs/contracts.md` enthält `Tool`, `ToolResult`, `Agent`, `Task`, `Step`, `Permission`, `TaskBudget`.
Diese Typen werden **nicht umbenannt und nicht umgebaut.** Wenn ein Vertrag nicht passt: erst melden, dann ändern — nie einfach danebenbauen.

## Testen kostet kein Geld

Es gibt `FakeLLMProvider` in `core/llm.py`. **Tests laufen ausschließlich dagegen.**
`pytest` darf niemals einen echten Modellaufruf machen. Wenn ein Test einen echten Key braucht, ist der Test falsch gebaut.

Du selbst (Claude Code) bist **nicht** JARVIS' Modell-Backend. JARVIS ruft seinen eigenen Provider mit eigenem Key. Bau keine Brücke von JARVIS zurück zu deiner eigenen Session.

## Befehle

```bash
uvicorn main:app --reload          # starten
pytest -q                          # Tests
python -m scripts.smoke            # End-to-End-Rauchtest der aktuellen Phase
```

## Eigene Skills

- `/phase <n>` — Phase n laden und bauen
- `/dod` — Definition of Done der aktuellen Phase ehrlich prüfen
- `/status` — Projektstand aus STATUS.md + git ableiten

## Antwortformat am Ende jeder Phase

```
GEBAUT:        was jetzt existiert
GETESTET:      was wirklich lief, mit echter Ausgabe
NICHT GETESTET: was ungeprüft ist
START:         exakter Startbefehl
DoD-CHECK:     jedes Kriterium einzeln ✓ / ✗
BLOCKER:       was ich besorgen muss (Keys, Konten, Geld)
```
