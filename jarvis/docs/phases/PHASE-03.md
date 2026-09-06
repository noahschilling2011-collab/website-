# PHASE 3 — Memory

> Auftrag für Phase 3. Wird von `/phase 3` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 2 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
Vier Schichten, aber ehrlich implementiert:

| Schicht | Umsetzung | Lebensdauer |
|---|---|---|
| Short-Term | letzte N Nachrichten aus `messages` | Session |
| Working | Zwischenergebnisse im `Task`-Objekt | Task-Laufzeit |
| Long-Term | Tabelle `facts(id, text, category, source_message_id, created_at, confirmed)` | dauerhaft |
| Episodic | Tabelle `task_log(task_id, goal, outcome, summary, created_at)` | dauerhaft |

- **Erst Keyword-Suche (SQLite FTS5), keine Embeddings.** Embeddings erst, wenn FTS5 nachweislich zu schlecht ist — das ist eine Messung, keine Annahme.
- Ein Fakt wird nur gespeichert, wenn das Modell ihn explizit als merkenswert markiert. Kein automatisches Absaugen des ganzen Chats.
- Endpunkte: `GET /api/memory`, `POST /api/memory`, `DELETE /api/memory/{id}`.
- Im UI: eine Memory-Ansicht, in der jeder Eintrag sichtbar, editierbar und löschbar ist.

**Definition of Done:**
1. "Merk dir: ich fahre Downhill und mein Rad ist ein Santa Cruz V10." → ein `facts`-Eintrag.
2. Prozess neu starten, "Was für ein Rad fahre ich?" → korrekte Antwort, und im Log ist der Memory-Lookup sichtbar.
3. Ich lösche den Eintrag im UI, frage erneut → das Modell sagt, dass es das nicht weiß. Es halluziniert die Antwort nicht.
4. `task_log` enthält nach drei Tasks drei Zeilen.
5. Ein Fakt, der einem älteren Fakt widerspricht, wird als Konflikt angezeigt, nicht stumm überschrieben.

**Verboten:** Vektor-DB, pgvector, Postgres.
