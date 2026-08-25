# PHASE 5 — Permissions & Bestätigung

> Auftrag für Phase 5. Wird von `/phase 5` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 4 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
- Vollständige Durchsetzung von `Permission` im Tool-Dispatcher.
- Bestätigungs-Flow: Ein Tool mit `requires_confirmation` setzt den Step auf `NEEDS_CONFIRMATION`, der Task pausiert, das UI zeigt **exakt** was passieren würde (Tool, Argumente, Auswirkung im Klartext), und wartet auf `POST /api/tasks/{id}/confirm`.
- Timeout für unbeantwortete Bestätigungen: 10 Minuten, danach `cancelled`.
- Audit-Log: jede Aktion ab `EXTERNAL` wird unveränderlich protokolliert.

**Definition of Done:**
1. Ein Test-Tool `send_email` (EXTERNAL, das nur in eine Datei schreibt) löst eine Rückfrage aus.
2. Die Rückfrage zeigt Empfänger, Betreff und Text vor dem Senden.
3. Ohne Bestätigung passiert nichts. Ich prüfe die Datei — leer.
4. Ein Agent mit `max_permission = READ` kann `send_email` **nicht** aufrufen, auch wenn ich das Tool in seine Liste schreibe. Der Test beweist das.
5. Das Audit-Log enthält jede bestätigte Aktion mit Zeitstempel.
