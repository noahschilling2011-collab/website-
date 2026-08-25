# Phase 10 — Betrieb

## Ziel
Läuft dauerhaft, überlebt einen Neustart, und ein Datenverlust ist kein
Totalverlust.

## Was gebaut wird
- Docker-Image und Compose-Datei. **Erst hier.**
- Backup und wiederhergestellter Restore — ungetesteter Restore zählt nicht.
- Logs und ein paar Kennzahlen: Anfragen, Fehler, Kosten pro Tag.

## Postgres/pgvector: nur nach Messung
Wird **nur** gewechselt, wenn eine Messung zeigt, dass SQLite mit FTS5 nicht
mehr reicht. Die Messung steht dann hier im Dokument, mit Zahlen. Ohne Messung
bleibt SQLite.

## Definition of Done
1. `docker compose up` startet JARVIS auf einem fremden Rechner.
2. Ein Backup wurde eingespielt und die Daten waren vollständig.
3. Neustart des Containers verliert keine Konversation.
4. Tagesgenaue Kostenzahl ist abrufbar.
