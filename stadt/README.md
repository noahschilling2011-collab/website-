# STADT

Eine Stadt, in der jeder Mensch selbst entscheidet. Projektname vorläufig.

**Stand: Phase 0.** Die Simulation läuft ohne Grafik und wird in Node getestet. Grafik folgt in Phase 1.

## Starten

```bash
cd stadt
node tools/simtest.mjs --seed 1 --tage 365     # Tabelle alle 30 Tage, am Ende Charakter-Auswertung
node tools/simtest.mjs --gate                  # Phase-0-Gate: Seeds 1, 2, 3, je 730 Tage
node tools/simtest.mjs --gate --seeds 4,5,6    # dasselbe mit anderen Seeds
```

Weitere Schalter für `--seed`: `--alle 60` (Zeilenabstand), `--fluss` (Zu-/Wegzüge, Geburten, Tode je Zeile),
`--diag` (Zufriedenheit und Bedürfnisse), `--aktionen` (wie oft jede Aktion gewählt wurde), `--buch 20`
(die letzten Stadtbuch-Einträge).

Ab Phase 1 im Browser: `python3 -m http.server 8000` **im Ordner `stadt/`**, dann
`http://localhost:8000/stadt.html`. Immer Port 8000, weil der Spielstand daran hängt.

## Aufbau

- `stadt.html` enthält den Block `<script id="sim">`: reine Simulation, kein DOM, kein `window`, kein `fetch`,
  kein `Math.random`, keine Uhrzeit. Er legt `globalThis.StadtSim` an: `neueStadt(seed)`, `stunde(S)`, `kennzahlen(S)`.
  Alle Personendaten liegen als typisierte Arrays (eine pro Feld, Index = Personen-ID) in `S.p`, die Gebäude in `S.g`.
  Alle Stellschrauben stehen gesammelt im Objekt `R` am Anfang des Blocks.
- `tools/simtest.mjs` zieht diesen Block aus der HTML-Datei und führt ihn in einem leeren `vm`-Kontext aus.
  `Math.random` und `Date` sind dort gesperrt, `window` und `document` gibt es nicht. Benutzt die Simulation
  eines davon, bricht der Test mit einem Fehler ab.

## Annahmen — Stellen, an denen die Spec nichts festlegt

| # | Annahme | Warum |
|---|---|---|
| 1 | Alles liegt in `stadt/`, nicht im Repo-Wurzelordner | Das Repo enthält schon das Blitzer-Projekt |
| 2 | 1 Lebensjahr = 10 Spieltage | Ohne Raffung würde in zwei Spieljahren niemand erwachsen, es gäbe keine Enkel (Phase-3-Gate) |
| 3 | Mit 67 endet die Anstellung, Rente 50/Tag aus dem Budget, solange es reicht | Die Spec nennt nur „job_suchen: 18–67“. Ohne feste Grenze wurde die Bevölkerungswelle getestet größer |
| 4 | Die Stadt besitzt die Wohnhäuser, Miete geht ins Budget. Budget = 10 % Steuer vom Lohn + Miete | Die Spec sagt „Miete raus“, aber nicht wohin |
| 5 | Werkstätten verkaufen ans Umland. Erlös je Arbeitstag = min(140, 50.000 / alle Werkstatt-Arbeitenden) | Einzige Geldquelle von außen und zugleich die Wachstumsgrenze. Ohne sie wächst die Stadt endlos |
| 6 | Läden haben eine Kapazität: 2,5 Leute je Stelle (Besitzer zählt mit), also 17 pro Laden. Ist der Laden voll, geht man zum nächsten mit Platz in Reichweite | Sonst schluckt ein Laden in der Mitte die ganze Stadt, und Ladenjobs wachsen nicht mit der Kundschaft |
| 7 | Stammladen: Man bleibt beim Laden, solange er offen, in Reichweite und nicht voll ist. Den nächstgelegenen sucht man beim ersten Einkauf oder wenn der eigene wegfällt | Weicht vom Wortlaut „Einkauf beim nächsten Laden“ ab. Ohne das nimmt jeder neue Laden dem Nachbarn sofort die Kundschaft weg. Gemessen (Seed 1, 730 Tage, zusammen mit einer zweiten Änderung): 73 % der Gründungen pleite ohne, 62 % mit Stammladen |
| 8 | Wer Erspartes hat, gibt täglich bis 1 % davon (höchstens 15) zusätzlich aus, Sparsame weniger | Sonst sammelt sich das Geld bei den Leuten, und die Läden bekommen nichts ab |
| 9 | Besitzer zahlen Lohn nach Charakter: wenig sparsam = großzügiger (90–110 % vom Grundlohn) | Gibt `job_wechseln` einen Grund |
| 10 | Pleite-Betriebe stehen leer und können übernommen werden (40 % der Baukosten) | Die Spec sagt „Gebäude wird frei“ |
| 11 | Zuzug: freie Stellen zählen nur, soweit sie nicht schon Arbeitslose der Stadt besetzen könnten | Sonst ziehen Leute für Stellen zu, die Einheimische ohnehin gleich nehmen, und die Stadt wächst über ihre Arbeit hinaus |
| 12 | „Wohnungssuchende“ fürs Bauamt = Leute ohne Wohnung oder mit erfolgloser Suche **plus** Anfragen von außen (Leute, die wegen freier Stellen kämen, aber keine Wohnung finden) | Sonst baut das Bauamt nie vorausschauend, und der Zuzug stockt |
| 13 | Zufriedenheit = 100 − gewichtetes Mittel 4. Grades der Dringlichkeiten. Das schlimmste Bedürfnis zählt am stärksten. Trauer −15, kein Einkauf −10 | Mit dem normalen Mittel fällt kaum jemand unter 20, dann zieht niemand weg |
| 14 | Straßen liegen auf einem 4er-Raster (Blöcke 3×3). Bauplätze sind Felder neben einer Straße, die nicht auf dem Raster liegen | Neue Straßen werden nie von Häusern blockiert |
| 15 | Die Partnerwahl achtet nicht auf das Geschlecht (etwa die Hälfte der Paare ist gleichgeschlechtlich). Jedes Paar kann ein Kind bekommen, wenn beide unter 45 sind. Der Wert sinkt pro vorhandenem Kind und bei enger Wohnung | Die Spec sagt zu beidem nichts. Offene Frage an Noah, ob das so bleiben soll |
| 16 | Bleiben nach einem Tod oder Wegzug nur Kinder im Haushalt, kommen sie zu Verwandten außerhalb | Kinder haben keine Aktionen und kein Einkommen |
| 17 | Gründer sehen den Markt: Einen Laden gibt es, wenn in Reichweite ≥ 10 Leute leer ausgehen oder gar kein Laden da ist. Eine Werkstatt, wenn der Umlandpreis mit allen schon geplanten Werkstattstellen noch ≥ Lohn + 8 ist. Ohne Aussicht sinkt der Gründungswert (Risikofreudige lassen sich weniger abschrecken) | Sonst gründen alle am selben Tag in denselben Markt (Herdentrieb) |
| 18 | Bauamt: Regel 1 baut höchstens 1 + Einwohner/300 Häuser pro Tag. Park nur, wenn das Viertel weniger als 1 + Bewohner/60 Parks hat. Notbremse höchstens alle 14 Tage | Die Spec sagt „einmal pro Spieltag“, aber nicht wie viel |
| 19 | Gate 6 und 7 vergleichen mit **allen, die je als Erwachsene in der Stadt lebten** (nicht nur den heutigen). Beim Wegzug zählt nur die Person, die entschieden hat, nicht ihre Familie | Die heutigen Erwachsenen sind schon gefiltert (die Heimatlosen sind weg), das würde den Unterschied schönen |
| 20 | Gate 4 „pendelt sich ein“ = Einwohner Tag 640 → 730 ändern sich um höchstens 10 %, und die Bebauung bleibt ≥ 2 Felder vom Kartenrand | Die Spec gibt keine Zahl |

## Bekannte Schwäche

Gate 4 besteht auf den vorgeschriebenen Seeds 1, 2 und 3. Auf ungesehenen Seeds hält es nicht immer: Bei 4 von 9 Seeds
(9–12) wächst die Stadt zwischen Tag 640 und 730 noch um 15–49 %. Ursache ist eine demografische Welle. Die große
Zuzugswelle aus Jahr 1 geht um Tag 600–700 in Rente, kauft aber weiter ein. Es fehlen Arbeitskräfte, der Zuzug öffnet
sich wieder. Lösungsvorschläge stehen in der Lieferung von Phase 0.
