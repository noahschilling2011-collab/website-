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
- `tools/simtest.mjs` zieht diesen Block aus der HTML-Datei und prüft ihn zuerst statisch auf verbotene Namen
  (`window`, `document`, `fetch`, `THREE`, `Math.random`, `Date`, `Intl`, `performance`, `console` …). Danach führt es ihn in
  einem leeren `vm`-Kontext aus, in dem `Math.random`, `Date` und `Intl` gesperrt sind.

## Annahmen — Stellen, an denen die Spec nichts festlegt

| # | Annahme | Warum |
|---|---|---|
| 1 | Alles liegt in `stadt/`, nicht im Repo-Wurzelordner | Das Repo enthält schon das Blitzer-Projekt |
| 2 | 1 Lebensjahr = 10 Spieltage | Ohne Raffung würde in zwei Spieljahren niemand erwachsen, es gäbe keine Enkel (Phase-3-Gate) |
| 3 | Mit 67 endet die Anstellung, Rente 50/Tag aus dem Budget, solange es reicht | Die Spec nennt nur „job_suchen: 18–67“. Ohne feste Grenze wurde die Bevölkerungswelle getestet größer |
| 4 | Die Stadt besitzt die Wohnhäuser, Miete geht ins Budget. Budget = 10 % Steuer vom Lohn + Miete | Die Spec sagt „Miete raus“, aber nicht wohin |
| 5 | Werkstätten verkaufen ans Umland. Erlös je Arbeitstag = min(140, 50.000 / alle Werkstatt-Arbeitenden) | Einzige Geldquelle von außen und als Wachstumsgrenze gedacht (siehe „Bekannte Schwächen“) |
| 6 | Läden haben eine Kapazität: 5 Leute je Stelle (Besitzer zählt mit), also 35 pro Laden. Ist der Laden voll, geht man zum nächsten mit Platz in Reichweite. Die Hälfte des Ladenumsatzes geht an Lieferanten außerhalb der Stadt (Wareneinsatz) | Sonst schluckt ein Laden in der Mitte die ganze Stadt. Ohne Wareneinsatz entsteht pro Kopf eine halbe Ladenstelle, und die Stadt schaukelt sich auf (siehe Schwächen) |
| 7 | Stammladen: Man bleibt beim Laden, solange er offen, in Reichweite und nicht voll ist. Den nächstgelegenen sucht man beim ersten Einkauf oder wenn der eigene wegfällt | Weicht vom Wortlaut „Einkauf beim nächsten Laden“ ab. Ohne das nimmt jeder neue Laden dem Nachbarn sofort die Kundschaft weg |
| 8 | Wer Erspartes hat, gibt täglich bis 1 % davon (höchstens 15) zusätzlich aus, Sparsame weniger | Sonst sammelt sich das Geld bei den Leuten, und die Läden bekommen nichts ab |
| 9 | Besitzer zahlen Lohn nach Charakter: wenig sparsam = großzügiger (90–110 % vom Grundlohn) | Gibt `job_wechseln` einen Grund |
| 10 | Pleite-Betriebe stehen leer und können übernommen werden (40 % der Baukosten). Eine Übernahme zählt als Gründung | Die Spec sagt „Gebäude wird frei“ |
| 11 | Zuzug: freie Stellen zählen nur, soweit sie nicht schon Arbeitslose der Stadt besetzen könnten. Höchstens 1 + 1 % der Einwohner pro Tag | Sonst ziehen Leute für Stellen zu, die Einheimische ohnehin gleich nehmen, und Wellen schaukeln sich auf |
| 12 | „Wohnungssuchende“ fürs Bauamt = Leute ohne Wohnung oder mit erfolgloser Suche **plus** Anfragen von außen (Leute, die wegen freier Stellen kämen, aber keine Wohnung finden) | Sonst baut das Bauamt nie vorausschauend, und der Zuzug stockt |
| 13 | Zufriedenheit = 100 − gewichtetes Mittel 4. Grades der Dringlichkeiten. Das schlimmste Bedürfnis zählt am stärksten. Trauer −15, kein Einkauf −10. Der Zielwert wird alle 6 Spielstunden neu berechnet, die Zufriedenheit gleitet stündlich hin | Mit dem normalen Mittel fällt kaum jemand unter 20, dann zieht niemand weg |
| 14 | Wohnen = Enge der Wohnung (Haushaltsgröße gegen Wohnungsgröße der Hausstufe) plus Park in der Nähe. Umziehen nur, wenn die neue Wohnung spürbar besser ist. Nach einer erfolglosen Suche 5 Tage Pause | Vorher zogen Haushalte zweimal am Tag hin und her, weil ein Umzug das Problem nicht löste |
| 15 | Die Partnerwahl achtet nicht auf das Geschlecht (etwa die Hälfte der Paare ist gleichgeschlechtlich). Jedes Paar kann ein Kind bekommen, wenn beide unter 45 und beide über 60 zufrieden sind | Die Spec sagt zu beidem nichts. **Offene Frage an Noah**, ob das so bleiben soll |
| 16 | Bleiben nach einem Tod oder Wegzug nur Kinder im Haushalt, kommen sie zu Verwandten außerhalb | Kinder haben keine Aktionen und kein Einkommen |
| 17 | Gründen nur mit Aussicht: In der Nähe fehlt ein Laden bzw. in Reichweite gehen ≥ 20 Leute leer aus (dann Laden), oder eine Werkstatt lohnt sich laut Umlandpreis mit allen schon geplanten Werkstattstellen (dann Werkstatt). Läden im Bau zählen in ihrer Reichweite schon als Versorgung. Schwelle = Kosten des Betriebs (Bau oder Übernahme plus 300 Startkasse) | Sonst gründen alle am selben Tag in denselben Markt, und Läden ohne Kundschaft gehen mit 0 Leuten pleite |
| 18 | Wegziehen: Wert = (30 + wie tief unter 20 + wie lange schon im Elend) × (1,6 − 2,2 × Heimatliebe). Wer wenig Heimatliebe hat, geht gleich. Mittlere Heimatliebe geht, wenn das Elend anhält. Ab etwa 60 Heimatliebe bleibt man | Die Spec: „Heimatliebe hoch: bleibt auch in schlechten Zeiten“ |
| 19 | Die vier Gedächtnis-Wirkungen (Job verloren, Pleite, getrennt, Trauer) laufen über „zuletzt erlebt am Tag X“. Das wird beim Eintrag ins Gedächtnis gesetzt | Sonst verfallen sie früher als nach 30 bzw. 180 Tagen, wenn der 8er-Ring überschrieben wird |
| 20 | Nach einem Ereignis entscheiden die Betroffenen in der nächsten Stunde (auch Partner, Freund, Eltern). Wer das Ereignis selbst ausgelöst hat, hat gerade entschieden | Spec: „direkt nach einem Ereignis“ |
| 21 | `freunde_treffen` nur abends (ab 17 Uhr), `partner_suchen` nur unter 70, `laden_gruenden` nur unter 60, `freinehmen` nur morgens | Die Spec nennt keine Uhrzeiten und Altersgrenzen |
| 22 | Straßen auf einem 4er-Raster (Blöcke 3×3). Bauplätze sind Felder neben einer Straße, die nicht auf dem Raster liegen. Das Bauamt verlängert meist ein Ende geradeaus, biegt an Kreuzungen manchmal ab und legt in 30 % der Fälle eine Abzweigung an. **Straßen sind sofort fertig** (keine Baustelle), Häuser, Betriebe und Parks brauchen 2–4 Tage. Eine Aufstockung läuft 3 Tage (`g.auf`), das Haus bleibt dabei bewohnt | Neue Straßen werden nie von Häusern blockiert |
| 23 | Bauamt: Regel 1 baut höchstens 1 + Einwohner/300 Häuser pro Tag. Park nur in Vierteln mit ≥ 8 Bewohnern und weniger als 1 + Bewohner/60 Parks. Notbremse höchstens alle 14 Tage | Die Spec sagt „einmal pro Spieltag“, aber nicht wie viel |
| 24 | Betriebe bleiben auf Stufe 1. Die Formel „Stufe × Stellen“ ist vorbereitet | Die Spec sagt nicht, wer Betriebe aufstuft. Das Bauamt stuft laut Regel 4 nur Wohnhäuser auf |
| 25 | Stadtbuch: Die Zuzüge eines Tages stehen in einer Zeile (mit Grund), alles andere einzeln | Sonst füllen Zuzüge die 500 Zeilen allein |
| 26 | Gate 6 und 7 vergleichen mit **allen, die je als Erwachsene in der Stadt lebten**. Beim Wegzug zählt nur die Person, die entschieden hat, nicht ihre Familie | Die heutigen Erwachsenen sind schon gefiltert (die Heimatlosen sind weg), das würde den Unterschied schönen |
| 27 | Gate 4: „pendelt sich ein“ = die Einwohnerzahl bleibt in den letzten 180 Tagen (Tag 551–730) in einem Band von Faktor 1,15 (max/min). „Unterhalb der Kartengrenze“ = keine Straße hat die äußerste erlaubte Rasterlinie erreicht | Die Spec gibt keine Zahl |

## Bekannte Schwächen

**Gate 4 hält nur auf einem Teil der Seeds.** Mit Wareneinsatz, gedrosseltem Zuzug und Gründen nur mit Aussicht bleibt die
Einwohnerzahl bei Seed 3 im Band (Faktor 1,06). Seed 1 und 2 schwingen noch mit 1,37 und 1,23. Auf den Seeds 1–6 bestehen
3 von 6. Vorher verdoppelte sich die Stadt im zweiten Jahr (Faktor 1,9–2,2). Was bleibt, ist ein Echo der ersten
Generation: Die große Zuzugswelle aus Jahr 1 geht fast gleichzeitig in Rente und stirbt fast gleichzeitig. Dann fehlen
erst Arbeitskräfte (neuer Zuzug), danach Kundschaft (Pleiten). Getestet und verworfen: Zuzug halb so schnell, Zuzügler
18–60 statt 18–45, Zuzug über etwa 10 Tage geglättet (jeweils nicht besser auf 6 Seeds).

**Das Budget ist nie knapp.** Ab etwa Tag 60 übersteigen Steuern und Mieten alle Ausgaben um ein Vielfaches. Die
Budgetgrenzen des Bauamts greifen deshalb praktisch nie. Gate 3 hält, weil jede Ausgabe vorher geprüft wird, nicht weil
das Budget eng wäre.
