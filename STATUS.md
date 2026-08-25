# STATUS

Einzige Wahrheit über den Projektstand. Wird nach jeder abgeschlossenen Phase
aktualisiert. Was hier nicht steht, ist nicht fertig.

**Stand:** 2026-08-25 · Branch `claude/jarvis-ai-os-1u7ied`

---

## Phase 1 — Fundament — ✅ FERTIG

Auftrag: `docs/phases/PHASE-01.md`

### Fertig und ausgeführt

- [x] `core/config.py` — pydantic-settings, `.env`, Provider/Modell/Effort/DB-Pfad.
      API-Key wird maskiert, nie geloggt.
- [x] `core/schema.sql` + `core/db.py` — SQLite aus der Stdlib, `conversations`
      und `messages`, Fremdschlüssel an, WAL an, Löschen kaskadiert.
- [x] `core/llm.py` — `LLMProvider`-Protokoll, `FakeLLMProvider` (ohne Netz),
      `AnthropicProvider` (httpx gegen `POST /v1/messages`, Wiederholung bei
      429/500/529, verständliche Fehler bei 400/401/403/404/413).
- [x] `api/` + `main.py` — `/api/health`, Konversationen (CRUD), `/api/chat`,
      `GET /` liefert die Oberfläche. Modellfehler → 502, fehlender Key → 503.
- [x] `web/index.html` — eine Datei, Vanilla JS, kein Build. Dunkel, Glas,
      eine Akzentfarbe. Lädt nichts aus dem Netz.
- [x] `tests/` — 72 Tests, grün. Echtes Netz ist in der Testsitzung gesperrt.
- [x] `scripts/smoke.py` — End-zu-End, läuft durch.

### Gemessen, nicht behauptet

| Was | Ergebnis |
|---|---|
| `pytest -q` | 72 passed |
| `python -m scripts.smoke` | bestanden, Exitcode 0 |
| `uvicorn main:app --reload` + echtes HTTP | Health, Chat und `GET /` geliefert |
| echter Browser gegen den laufenden Server | getippt, gesendet, neu geladen — Konversation stand noch da, keine JS-Fehler, keine 404 |
| Oberfläche headless in 360/768/1440 px | keine JS-Fehler, kein seitliches Scrollen |
| Kontrast an echten Pixeln gemessen | schlechtester Wert 4.70:1 (AA verlangt 4.5:1) |

### Bewusst nicht gebaut

- Streaming — Phase 2. Die Antwort erscheint am Stück.
- Kostenanzeige — Token werden gespeichert, aber nicht in Euro umgerechnet.
- Gedächtnis über Konversationen hinweg — Phase 3. Aktuell ein hartes
  Verlaufsfenster von 40 Nachrichten.
- Tools, Aufgaben, Agenten — Phasen 4 bis 6. Die Verträge stehen in
  `docs/contracts.md`, es gibt noch keinen Code dazu.

### Offen — dein Teil

- [ ] `ANTHROPIC_API_KEY` besorgen (console.anthropic.com), `.env` anlegen,
      `JARVIS_PROVIDER=anthropic` setzen. **Ab dann kostet jeder Aufruf Geld:**
      claude-opus-5 liegt bei 5 $ / 25 $ je Million Token (Eingabe/Ausgabe).
- [ ] `python -m scripts.smoke --real` einmal laufen lassen — das ist der
      einzige Punkt aus Phase 1, den ich nicht für dich prüfen kann.

---

## Phase 2 — Streaming und Kosten — 🔜 AKTUELL

Auftrag: `docs/phases/PHASE-02.md`. Noch nicht begonnen.

---

## Später

| Phase | Thema | Zustand |
|---|---|---|
| 3 | Gedächtnis (SQLite FTS5) | geplant |
| 4 | Werkzeuge und Freigaben | geplant |
| 5 | Aufgaben und Budgets | geplant |
| 6 | Agenten | geplant |
| 7 | Oberfläche neu (Build-Step ab hier erlaubt) | geplant |
| 8 | Sprache | geplant, Anbieter noch offen |
| 9 | Integrationen | geplant |
| 10 | Betrieb (Docker, Backup) | geplant |

---

## Bekannte Grenzen

- Ein Modellaufruf blockiert die Anfrage, bis er fertig ist. Bei
  `claude-opus-5` mit Effort `high` können das zehn Sekunden und mehr sein.
  Die Oberfläche zeigt derweil eine Denkanzeige. Abbrechen geht erst in Phase 2.
- Das Verlaufsfenster schneidet hart ab. Wer in einer langen Konversation etwas
  von ganz oben braucht, bekommt es nicht. Das löst Phase 3.
- Kein Zugriffsschutz. JARVIS gehört an `127.0.0.1` und sonst nirgendwohin.
- SQLite mit WAL verträgt genau einen Schreiber. Für einen Nutzer reicht das;
  ein zweiter gleichzeitiger Client ist nicht getestet.
