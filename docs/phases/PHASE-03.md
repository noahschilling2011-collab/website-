# Phase 3 — Gedächtnis

## Ziel
JARVIS findet wieder, was vor Wochen gesagt wurde, und weiß Fakten über den
Nutzer, ohne dass sie jedes Mal mitgeschickt werden.

## Was gebaut wird
- SQLite-FTS5-Index über `messages`, per Trigger aktuell gehalten.
- Tabelle `facts`: Aussage, Quelle (Nachrichten-ID), Zeitpunkt, Gültigkeit.
- Retrieval: zur Anfrage passende Treffer werden in den Kontext gehoben, mit
  sichtbarer Herkunft.
- Oberfläche: Suche über alles, und eine Ansicht „was JARVIS über mich weiß"
  mit Löschmöglichkeit.

## Warum FTS5 und keine Vektoren
Bei der Datenmenge einer Person ist BM25 nicht messbar schlechter und kostet
keine Embedding-Aufrufe. Ein Vektorindex kommt erst, wenn eine Messung zeigt,
dass FTS5 nicht reicht — nicht vorher.

## Definition of Done
1. Suche über 10 000 synthetische Nachrichten antwortet unter 50 ms.
2. Ein Fakt aus Konversation A ist in Konversation B verfügbar.
3. Jeder eingespielte Kontext ist auf seine Quellnachricht zurückführbar.
4. Löschen eines Fakts entfernt ihn aus Index und Kontext.
