# PHASE 10 — Härten & Verpacken

> Auftrag für Phase 10. Wird von `/phase 10` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 9 in `STATUS.md` auf FERTIG steht.

Erst hier: Docker, ggf. Postgres-Migration (nur wenn SQLite nachweislich limitiert), Backup-Strategie, vollständige README, Migrationsskripte, CI mit `pytest`.

**Definition of Done:**
1. `docker compose up` startet alles auf einem frischen Rechner.
2. Ein neuer Nutzer kommt nur mit der README zum laufenden System.
3. Alle Tests laufen in CI grün.
4. Ein Backup der DB lässt sich einspielen und der Verlauf ist danach vollständig.
