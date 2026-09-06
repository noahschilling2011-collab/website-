# PHASE 8 — Satellite Intelligence Agent

> Auftrag für Phase 8. Wird von `/phase 8` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 7 in `STATUS.md` auf FERTIG steht.

Vollständige Spezifikation in **Anhang A**. Lies den Anhang, bevor du diese Phase startest — der Abschnitt korrigiert mehrere physikalisch nicht erfüllbare Annahmen aus dem alten Prompt.

**Definition of Done:**
1. "Zeig mir das aktuellste wolkenfreie Sentinel-2-Bild von Schwäbisch Gmünd" liefert ein Bild **mit** Aufnahmedatum, Sensor, Auflösung in m/px und Wolkenanteil in %.
2. Wenn kein Bild unter dem Wolken-Schwellwert existiert, sagt JARVIS das — und liefert nicht ersatzweise ein wolkiges Bild ohne Hinweis.
3. Ein Vergleich zweier Zeitpunkte zeigt beide Bilder nebeneinander plus eine Differenzdarstellung.
4. Jede Bildaussage folgt dem Schema `BEOBACHTET / INTERPRETATION / KONFIDENZ` und nennt die Bodenauflösung.
5. "Welche Satelliten überfliegen heute meine Position?" liefert Zeiten aus echten TLE-Daten, berechnet mit `skyfield`, nicht geschätzt.
6. Attribution der Datenquelle steht sichtbar am Bild.
