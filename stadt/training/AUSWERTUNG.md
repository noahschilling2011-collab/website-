# Auswertung: vorab festgelegt (Etappe 1, 28.09.2026)

Festgelegt, bevor ein Trainingslauf ausgewertet wurde. Änderungen nur mit neuer Version dieser Datei und Begründung, nie nach Sicht auf
Ergebnisse desselben Kandidaten. Werkzeug: `tools/werte_aus.mjs` (Node, dieselbe Simulation, die Policy rechnet wie im Browser).

## Daten

- Seed-Listen in `training/seeds.json` (Version 1), disjunkt: Training 10000–10063, Validierung 20000–20031, Abschluss 30000–30031.
  Alte Seeds 1–3 nur für die Regression (`simtest`).
- Validierung dient der Kandidatenwahl (Checkpoint `bester` im Training; Vergleich in dieser Etappe). Die Abschlussseeds werden erst
  benutzt, wenn ein Kandidat feststeht; `werte_aus.mjs` verweigert sie ohne `--abschluss-freigegeben`.
- Szenario `stabil` (Lehrplanstufe 1): Stadt nach 150–230 Tagen Regeln, Start 6 Uhr, 30 Tage je Episode.

## Vergleich

- Gepaart: Für jede Episode rechnen beide Arme von **derselben** Ausgangslage aus (gleicher Seed, gleiche Fokusperson nach
  `nr`, gleicher eigener Zufallsstrom der Fokusperson). Die übrige Stadt entscheidet nach Regeln.
- Arme: `regeln` (das normale Gehirn entscheidet an denselben Entscheidungszeitpunkten, Zeitpunkt der Ausführung wie bei der Policy),
  `policy` (exportierte Datei, maskierte Auswahl, deterministisch), optional `zufall` (gleichverteilt aus der Maske) als Plausibilitätsprüfung.
- Fünf Gruppen nach Ausgangslage, Auswahl nur nach Lage und Persönlichkeit: `ohne_arbeit`, `mit_kind` (erwerbstätig mit Kind),
  `wenig_kontakt` (ohne Partner, höchstens ein Freund), `gruendungsnah` (Ehrgeiz ≥ 70, kein Betrieb), `rentennah` (60–66 Jahre).

## Hauptmetrik

Mittleres Bedürfnisdefizit der Fokusperson je Stunde: `100 − Zufriedenheit`, gemittelt über alle Stunden der Episode. Nach einem
Wegzug zählen die fehlenden Stunden mit 100 (schlechtester Wert). Kleiner ist besser. Relative Verbesserung einer Gruppe =
(Regeln − Policy) / Regeln, gemittelt über die Paare.

## Nebenmetriken und Toleranzen

- Notstandsanteil (Stunden mit Zufriedenheit unter 20, fehlende Stunden nach Wegzug mitgezählt): Policy höchstens 2 Prozentpunkte über Regeln.
- Wegzüge: Policy höchstens so viele wie Regeln.
- Gültige Handlungen: Maskenverletzungen = 0, Rückfälle (Fehler der Policy) = 0. Ablehnungen (Lage geändert) und ohne Erfolg werden berichtet.
- Ziele erreicht und aufgegeben, Umkehrfälle, Aktionsverteilung: berichtet.
- Charakter bleibt: Korrelation (Pearson) zwischen Persönlichkeitsmerkmal und Anteil der passenden Aktionen (gesellig ~ Treffen und
  Partnersuche, ehrgeizig ~ Wechsel und Gründung, fleißig ~ Freinehmen, Heimatliebe ~ Wegziehen, sparsam ~ Kündigen). Wo die Regeln
  |r| ≥ 0,1 zeigen, muss die Policy dasselbe Vorzeichen und mindestens die Hälfte des Betrags haben.
- Kontrollmessung Herkunft: Defizit getrennt nach „zugezogen“ und „hier geboren“ (nur gemessen; die Policy sieht es nicht).

## Freigabe als Standard

Alle Bedingungen zugleich:

1. In mindestens 3 von 5 Gruppen ist die relative Verbesserung ≥ 10 % **und** das 95-%-Intervall der gepaarten Differenz liegt über 0.
2. Harte Invarianten nie verletzt (Maske, Rückfall, Invarianten der Umgebung).
3. Nebenmetriken in der Toleranz.
4. Charakter bleibt (siehe oben).
5. Mindestens 20 Paare je Gruppe, mindestens 3 Trainingsläufe mit verschiedenen Seeds (Streuung zwischen Läufen berichtet).
6. Danach derselbe Vergleich auf den Abschlussseeds, ohne weitere Änderung am Kandidaten.

Solange nicht alles erfüllt ist, bleibt „Regeln“ der Standard; die Policy heißt „experimentell“. Ergebnisse mit weniger Läufen oder
Episoden heißen „vorläufig“. Ein Smoke-Lauf ist nie ein Qualitätsbeleg.
