# PHASE 4 — Planner + erster echter Agent

> Auftrag für Phase 4. Wird von `/phase 4` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 3 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
- `core/planner.py`: zerlegt ein Ziel in `Step`s. **Regel: Wenn ein Ziel in einem Schritt lösbar ist, erzeugt der Planner genau einen Schritt.** Kein Zwang zu zehn Schritten.
- Ausführungsschleife: Schritt laufen lassen → verifizieren → bei Fehler max. `max_attempts` Versuche, dann Schritt `FAILED` und Entscheidung: abbrechen oder mit Teilergebnis weiter.
- **Verifikation ist ein eigener, billiger Schritt**, nicht dasselbe Modell, das sich selbst auf die Schulter klopft: prüfe konkrete Bedingungen (Datei existiert? Ergebnis hat das erwartete Feld? Quelle vorhanden?), nicht "sieht gut aus".
- Ein Agent: **Research Agent** (`max_permission = READ`, Tools: `web_search`, `fetch_url`). Muss Quellen mitliefern; eine Behauptung ohne Quelle gilt als fehlgeschlagener Schritt.
- `GET /api/tasks/{id}` liefert den Plan mit Live-Status.

**Definition of Done:**
1. "Wie hoch ist die aktuelle Grundsteuer in Baden-Württemberg?" erzeugt einen Plan, den ich im UI Schritt für Schritt fortschreiten sehe.
2. Jede Faktenbehauptung in der Endantwort hat eine anklickbare Quelle.
3. Ich baue absichtlich einen Fehler ein (falsche URL) → Retry sichtbar, danach sauberes Scheitern, kein Endlos-Loop.
4. "Wie spät ist es?" erzeugt einen Plan mit **einem** Schritt.
5. Das Budget greift: Ich setze `max_steps=2` und ein größeres Ziel endet mit `aborted_budget` und Teilergebnis.
