# PHASE 1 — Walking Skeleton

> Auftrag für Phase 1. Wird von `/phase 1` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.

**Auftrag:**
Baue das kleinstmögliche vollständige System.

- `main.py` mit FastAPI, Endpunkt `POST /api/chat` (nimmt `{message}`, gibt `{reply, task_id}`).
- `core/llm.py` mit einer Klasse `LLMProvider` (abstrakt) und **einer** konkreten Implementierung. Modell-ID kommt aus `.env`, wird nicht geraten.
- `core/db.py`: SQLite, Tabellen `messages(id, role, content, created_at)` und `llm_calls(id, model, in_tokens, out_tokens, cost_eur, duration_ms, ok, created_at)`.
- `index.html`: Chat-UI, Dark Theme + Glassmorphism, wird von FastAPI als Static File ausgeliefert. Kein Build-Step.
- `.env.example`, `.gitignore`, `README.md` mit exakt zwei Befehlen: Installation und Start.

**Definition of Done:**
1. `python -m uvicorn main:app --reload` startet ohne Fehler.
2. `http://127.0.0.1:8000` zeigt das Chat-Interface.
3. Ich tippe "Hallo, wer bist du?" und bekomme eine Antwort vom echten Modell.
4. Ich starte den Prozess neu — der Verlauf ist noch da.
5. In `llm_calls` steht nach dem ersten Chat genau eine Zeile mit echten Tokenzahlen.
6. Ein Request ohne `X-Jarvis-Token` gibt 401.
7. `grep -ri "sk-" index.html` findet nichts.

**Verboten:** Agents, Tools, Planner, Memory, Voice, Streaming.
