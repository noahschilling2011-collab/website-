# PHASE 7 — Observability-Dashboard

> Auftrag für Phase 7. Wird von `/phase 7` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 6 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
Jetzt — und erst jetzt — darf das Frontend wachsen. Immer noch kein Build-Step erforderlich, aber mehrere Views.

Ansichten: laufende Tasks, Task-Historie mit Baumansicht, Tool-Call-Log, Kosten pro Tag/Woche, Fehlerrate, Modellverbrauch.

**Definition of Done:**
1. Ich sehe live, was gerade läuft (SSE oder WebSocket, nicht Polling im Sekundentakt).
2. Ich kann einen alten Task öffnen und jeden Schritt inkl. Prompt und Antwort nachlesen.
3. Die Kostenanzeige stimmt mit der Summe aus `llm_calls` überein — nachgerechnet, nicht geschätzt.
4. Ein laufender Task lässt sich über einen Button abbrechen und stoppt tatsächlich.
