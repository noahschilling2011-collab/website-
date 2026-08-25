# Phase 2 — Streaming und Kosten

## Ziel
Die Antwort erscheint Wort für Wort, lässt sich abbrechen, und man sieht, was
sie gekostet hat.

## Was gebaut wird
- `LLMProvider.stream()` gegen die SSE-Form der Messages-API
  (`message_start`, `content_block_delta`, `message_delta`, `message_stop`).
- SSE vom Backend zum Browser. Ein Abbruch stoppt auch die Anfrage nach oben.
- Eine abgebrochene Antwort wird als Fragment gespeichert und als solches
  markiert — nicht verworfen und nicht als vollständig ausgegeben.
- Token pro Nachricht, Kosten pro Konversation, aus einer Preistabelle in der
  Konfiguration gerechnet.
- Modellwahl in der Oberfläche.

## Definition of Done
1. Text erscheint sichtbar schrittweise, nicht in einem Block.
2. Abbrechen stoppt innerhalb einer Sekunde; das Fragment steht im Verlauf und
   ist als abgebrochen erkennbar.
3. `FakeLLMProvider` kann streamen; Streaming-Tests laufen ohne Netz.
4. Die Kostenanzeige stimmt mit `usage` aus der Antwort überein, nicht mit
   einer Schätzung.
