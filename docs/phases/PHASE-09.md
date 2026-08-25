# Phase 9 — Integrationen

## Ziel
JARVIS sieht Kalender, Mail und Dateien — als Werkzeuge, unter Freigabe.

## Regeln
- Jede Integration wird einzeln freigeschaltet.
- Erst lesend. Schreibend erst, wenn lesend eine Weile ohne Überraschung lief.
- Ein Integrations-Token liegt nie im Browser.

## Definition of Done
1. Mindestens eine Integration liest echte Daten.
2. Schreibende Aufrufe sind `ASK` und zeigen vorher genau, was passieren wird.
3. Ein Widerruf entfernt Token und zwischengespeicherte Daten.
4. Ohne Integration läuft JARVIS unverändert weiter.
