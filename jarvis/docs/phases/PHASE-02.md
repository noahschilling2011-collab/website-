# PHASE 2 — Tool-System

> Auftrag für Phase 2. Wird von `/phase 2` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 1 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
- `core/tools/registry.py`: Registry mit `@register` Decorator, liefert JSON-Schemas fürs Modell.
- Tool-Loop im Core: Modell schlägt Tool vor → Permission prüfen → ausführen → Ergebnis zurück ins Modell → maximal `max_tool_calls` Runden.
- Drei echte Tools: `clock` (Permission INFO), `calculator` (INFO, kein `eval` — nutze eine sichere Ausdrucksauswertung), `web_search` (READ, echte API, Doku vorher nachschlagen).
- `pytest`-Tests: Registry, Permission-Verweigerung, Timeout, kaputtes Tool-JSON.

**Definition of Done:**
1. "Was ist 17 % von 4380?" → Antwort 744,6, und im Log steht ein `calculator`-Aufruf. Nicht im Kopf gerechnet.
2. "Wie spät ist es?" → korrekte lokale Zeit über `clock`.
3. Eine Websuche liefert ein Ergebnis **mit Quellen-URLs** in `ToolResult.sources`.
4. Ein Tool, das absichtlich 40 s braucht, wird nach seinem Timeout abgebrochen und der Task läuft weiter.
5. `pytest` läuft grün, mindestens 6 Tests.
6. Im UI ist pro Antwort aufklappbar sichtbar, welche Tools mit welchen Argumenten liefen.

**Verboten:** Agents, Planner, Memory.
