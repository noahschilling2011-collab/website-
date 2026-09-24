# STADT

Eine Stadt, in der jeder Mensch selbst entscheidet. Projektname vorläufig.

**Stand: Phase 4 plus „richtige Arbeit“ und Tech-Firmen.** Simulation (Phase 0), 3D-Karte mit Tag und Nacht (1), Speichern
und Aufholen (2), laufende Figuren und Personenkarten (3), Hauptfiguren mit Ollama (4). Danach auf Noahs Wunsch: Bauarbeiter
vom Bauhof bauen die Häuser, Werkstätten machen Kisten für die Läden, man sieht die Leute bei der Arbeit, und Bewohner gründen
Tech-Firmen für Software, Handys oder Computer; Hauptfiguren, die dort programmieren, schreiben über Ollama echten Code. Phase 4 ist nur gegen
einen nachgebauten Ollama-Server getestet, nicht gegen ein echtes Sprachmodell (siehe „Bekannte Schwächen“).

## Starten

```bash
cd stadt
python3 -m http.server 8000
```

Dann `http://localhost:8000/stadt.html` öffnen. **Immer Port 8000 und `localhost`**: Der Spielstand hängt an der Adresse,
und Ollama erlaubt ohne Einstellung nur Seiten von `localhost` und `127.0.0.1`. Per Doppelklick (`file://`) lädt Three.js nicht.

Schalter in der Adresse (alle optional):

| Schalter | Wirkung |
|---|---|
| `?neu` | Neue Stadt statt den Spielstand zu laden (der alte wird beim nächsten Speichern überschrieben) |
| `?seed=7` | Seed für eine neue Stadt (sonst zufällig) |
| `?debug` | Debug-Ecke unten links: fps, Frame-Zeit, Draw Calls, Dreiecke, KI-Aufrufe (gültig in %, Dauer, Fehler) und Knöpfe „Zeit vorspulen“ |
| `?debug&tage=400` | Neue Stadt vorab 400 Tage rechnen |
| `?debug&umland=300000&tage=750` | Größere Stadt für den Leistungstest (Seed 2: etwa 5.900 Einwohner). Dieser Stand wird nicht gespeichert |

## Ollama für die Hauptfiguren (Phase 4)

Ohne Ollama läuft alles, die Hauptfiguren entscheiden dann mit dem normalen Gehirn, oben rechts steht „KI nicht erreichbar“.

1. Ollama installieren und starten (App oder `ollama serve`).
2. `ollama list` zeigt die installierten Modelle. Ist die Liste leer: `ollama pull <modell>`. Welches Modell, entscheidest du;
   die App schreibt keinen Modellnamen fest.
3. Seite über `http://localhost:8000/stadt.html` öffnen. Die App fragt `http://localhost:11434/api/tags` und nimmt das erste
   Modell aus der Liste. Ändern: Zahnrad unten rechts → „KI für die Hauptfiguren“ → Modell.
4. Nur falls die Seite von einer anderen Adresse kommt (z. B. über das Netzwerk): Ollama mit der Umgebungsvariable
   `OLLAMA_ORIGINS` starten, etwa `OLLAMA_ORIGINS=http://192.168.1.20:8000 ollama serve`. Für `localhost`, `127.0.0.1` und
   `0.0.0.0` ist das laut Ollama-Quellcode (`envconfig/config.go`) nicht nötig.

Was passiert: Um 7 und 18 Uhr und nach Ereignissen fragt eine Hauptfigur das Modell (höchstens 3-mal pro Spieltag). Die
Stadt wartet nicht. Kommt in 2 Spielstunden keine gültige Antwort, entscheidet das normale Gehirn. Bei 20× gibt es keine
KI-Entscheidungen, Gespräche gehen trotzdem. Jeder Gedanke landet im Tagebuch der Figur (die letzten 30).
Hauptfiguren, die in einer Tech-Firma programmieren, bitten das Modell außerdem einmal am Spieltag um ein kleines Stück Code
für ihre Arbeit. Es steht dann im Tagebuch und wird nie ausgeführt.

## Was die Leute arbeiten

Es gibt kein Feld „Beruf“ und keine neue Aktion. Der Beruf ergibt sich aus dem Arbeitsplatz:

- **Bauarbeiter/in** beim Bauhof (die Werkstatt der Stadt vom Start). Um 7 Uhr teilt der Bauhof seine Leute auf die
  Baustellen ein, älteste zuerst, höchstens 4 je Baustelle. Um Mitternacht bringt jede eingeteilte Person, die noch beim
  Bauhof ist und nicht frei hat, einen Arbeitstag. Ein Wohnhaus braucht 12 Arbeitstage, eine Aufstockung 12 bzw. 18, ein
  Laden 9, eine Werkstatt 12, ein Park 4. Ohne Bauarbeiter bleibt die Baustelle liegen. Wer keine Baustelle hat, macht Kisten.
- **Handwerker/in** in einer Werkstatt: 8 Kisten je Arbeitstag. Die Kisten gehen an die Läden der Stadt, der Rest ans Umland.
- **Verkäufer/in** im Laden: 5 Kunden je Kraft wie bisher. Ein Laden braucht eine Kiste je 38 Taler Umsatz und holt sie bei
  der nächsten Werkstatt der Stadt, die noch welche hat (bis 20 Felder weit), sonst teurer von außerhalb. Wer zuzieht,
  fängt in einer Werkstatt oder Tech-Firma an; Läden finden ihre Leute nur in der Stadt (Annahme 11).
- **Programmierer/in** in einer Tech-Firma: Jede anwesende Person (auch der Besitzer) bringt um Mitternacht einen Arbeitstag an
  der nächsten Version. Eine Version braucht bei Software 40, beim Handy 60, beim Computer 50 Arbeitstage, danach erscheint sie
  („Nova 3“). Die Firma verkauft ans Umland (derselbe Topf wie die Werkstätten) und über die Läden an die Leute in der Stadt.
- **Theke** (Besitzer/in, sonst die erste anwesende Kraft) und **Träger/in** (reihum aus der Werkstatt, die liefert, um 9
  und 13 Uhr) sind nur zum Anschauen und wirken nicht auf die Simulation.

**Tech-Firmen.** Wer fleißig und ehrgeizig ist, gründet über dieselbe Aktion wie bisher (`laden_gruenden`) statt einer
Werkstatt eine Tech-Firma, solange Tech-Firmen weniger als 40 % der Stellen haben, die fürs Umland arbeiten. Sie macht das, was
in der Stadt am seltensten gemacht wird: Software, Handys oder Computer. Die Leute kaufen beim täglichen Einkauf im Laden die
neueste Version, wenn danach genug Geld übrig bleibt: erst ein Gerät, dann ab und zu Software. Ein Kauf hebt die Freizeit. Läuft
eine Firma gut (alle Stellen besetzt, 20 Tage in Folge Gewinn), spart sie für einen Anbau und gibt dem Bauhof den Auftrag, sobald
das Umland Platz hat und genug Leute Arbeit suchen. Hauptfiguren, die in einer Tech-Firma programmieren, schreiben einmal am
Spieltag über Ollama ein echtes kleines Stück Code in ihr Tagebuch. Es wird nur angezeigt und nie ausgeführt.

**Aussehen (Design-Runde 1).** Häuser haben einzelne Fenster je Geschoss, Haustür und Sockel. Kleine Häuser (Stufe 1)
tragen ein Satteldach, größere ein Flachdach mit Attika, Treppenhaus und Lüftern. Werkstätten sind Hallen mit Sägezahndach und
Tor, Läden zeigen Schaufenster und Tür zur Straße. Straßen haben Gehwege mit Bordstein, Mittellinie und Zebrastreifen vor
Kreuzungen. Straßenlaternen stehen an geraden Straßen; nachts leuchten sie mit einem warmen Lichtfleck, aber nur dort, wo
daneben gebaut ist. Leere Stichstraßen bleiben dunkel. Um die Karte liegen Felder, flache Hügel und ein Waldrand, der im
Nebel verschwindet. Parks und Gärten neben Wohnhäusern haben Laubbäume. Bei flachem Blick sieht man einen Himmel mit
Farbverlauf, nachts mit Sternen und Mond. Alles ist Deko ohne Wirkung auf die Simulation.

**Design-Runde 2.** Aus den Schloten arbeitender Werkstätten steigt tagsüber Rauch (8–17 Uhr, nur wenn heute jemand da ist).
Weiche Wolkenschatten ziehen langsam über Boden, Häuser und Bäume (tagsüber, höchstens etwa 20 % dunkler). Links hinter der
Stadt liegt ein See mit Schilf und Steinen im Feldring. Wohntürme haben Balkone zur Straße, und nachts leuchten die Fenster je
Haus leicht verschieden warm. Die Oberfläche hat Symbole im Kennzahlen-Panel, Sonne oder Mond an der Uhr und ein Symbol je
Stadtbuch-Eintrag. Die Karten haben einen klareren Kopf. Auf dem Handy ist das Stadtbuch eingeklappt und zeigt, wie viele
Einträge neu sind. Bei reduzierter Bewegung steht der Rauch still, und es gibt keine Wolkenschatten.

In der 3D-Ansicht wächst auf jeder Baustelle ein grauer Rohbau mit den geschafften Arbeitstagen. Das Gerüst wird dunkler,
solange niemand kommt, und lässt sich anklicken. Bauarbeiter (orange) stehen an den Ecken ihrer Baustelle, Handwerker
(blau) vor der Werkstatt. An Werkstätten stehen Kistenstapel, vor Läden eine Theke und eine Auslage (braun: Kisten aus der
Stadt, grau: von außerhalb). Tech-Firmen sind Glasbauten in der Farbe ihres Produkts; tagsüber leuchten so viele Fenster wie
Leute programmieren, nachts der Serverraum. Programmierer (lila) stehen mit einem leuchtenden Bildschirm vor der Firma, wer ein
Handy hat, trägt es unterwegs in der Hand (höchstens 80 gleichzeitig, fest je Stunde vergeben). Vor einem Gebäude stehen höchstens 14 Leute
in zwei Reihen, wer mehr ist, ist drinnen. Personenkarten sagen „arbeitet als Bauarbeiterin beim
Bauhof …“ bzw. „arbeitet als Programmiererin bei Nova Handys …“, was die Person heute tut und was sie gekauft hat.

## Aufbau

- `stadt.html` enthält den Block `<script id="sim">`: reine Simulation, kein DOM, kein `window`, kein `fetch`,
  kein `Math.random`, keine Uhrzeit. Er legt `globalThis.StadtSim` an. Alle Personendaten liegen als typisierte Arrays
  (eine pro Feld, Index = Personen-ID) in `S.p`, die Gebäude in `S.g`, die Hauptfiguren in `S.ki`.
  Alle Stellschrauben stehen gesammelt im Objekt `R` am Anfang des Blocks.
- Der `<script type="module">`-Block macht Darstellung, Oberfläche, Speichern und die Ollama-Aufrufe. Er ändert den
  Sim-Zustand nur über Funktionen aus `StadtSim` (`stunde`, `tagSchritt`, `hauptSetzen`, `kiSchalten`, `kiEntscheidung`,
  `kiVerwerfen`, `kiGespraech`, `kiTagebuch`, `verlustErledigt`, `importZustand`). `theke`, `traeger` und `bauGesamt` lesen nur. Einzige Ausnahme ist die Testhilfe
  `?debug&umland=…`, die `R.UMLAND` vor dem Start umstellt (solche Stände werden nicht gespeichert).
- `tools/simtest.mjs` zieht den sim-Block aus der HTML-Datei und prüft ihn zuerst statisch auf verbotene Namen
  (`window`, `document`, `fetch`, `THREE`, `Math.random`, `Date`, `Intl`, `performance`, `console` …). Danach führt es ihn in
  einem leeren `vm`-Kontext aus, in dem `Math.random`, `Date` und `Intl` gesperrt sind.

```bash
node tools/simtest.mjs --seed 1 --tage 365     # Tabelle alle 30 Tage, am Ende Charakter-Auswertung
node tools/simtest.mjs --gate                  # Phase-0-Gate: Seeds 1, 2, 3, je 730 Tage
node tools/simtest.mjs --gate --seeds 4,5,6    # dasselbe mit anderen Seeds
node tools/simtest.mjs --speichertest          # Speichern/Laden mitten am Tag: läuft danach bitgleich weiter?
node tools/simtest.mjs --aufholtest            # 90 Tage stündlich gegen 90 Tagesschritte
node tools/simtest.mjs --kitest                # Hauptfiguren: erlaubte Aktionen, Anfragen, Fristen, Tagebuch, Nachfolge
node tools/simtest.mjs --bau                   # Bauhof: Einteilung um 7, Fortschritt je Person, jede Baustelle wird fertig
node tools/simtest.mjs --waren                 # Kisten: geliefert ≤ gemacht, Werkstatt-Einnahmen wie vorher
node tools/simtest.mjs --tech                  # Tech-Firmen: Arbeitstage je Version, Käufe im Laden, Anbau (Seeds 1–3, 730 Tage)
node tools/simtest.mjs --migrationstest        # Spielstand von Version 2 übernehmen (alte Datei aus git 39c405b), 60 Tage weiter
node tools/simtest.mjs --migrationstest --alt <stadt.html von Version 3>   # dasselbe für Version 3
```

Weitere Schalter für `--seed`: `--alle 60` (Zeilenabstand), `--fluss` (Zu-/Wegzüge, Geburten, Tode je Zeile),
`--diag` (Zufriedenheit und Bedürfnisse), `--aktionen` (wie oft jede Aktion gewählt wurde), `--buch 20`
(die letzten Stadtbuch-Einträge).

## Annahmen — Stellen, an denen die Spec nichts festlegt

| # | Annahme | Warum |
|---|---|---|
| 1 | Alles liegt in `stadt/`, nicht im Repo-Wurzelordner | Das Repo enthält schon das Blitzer-Projekt |
| 2 | 1 Lebensjahr = 10 Spieltage | Ohne Raffung würde in zwei Spieljahren niemand erwachsen, es gäbe keine Enkel (Phase-3-Gate) |
| 3 | Mit 67 endet die Anstellung, Rente 50/Tag aus dem Budget, solange es reicht | Die Spec nennt nur „job_suchen: 18–67“. Ohne feste Grenze wurde die Bevölkerungswelle getestet größer |
| 4 | Die Stadt besitzt die Wohnhäuser, Miete geht ins Budget. Budget = 10 % Steuer vom Lohn + Miete | Die Spec sagt „Miete raus“, aber nicht wohin |
| 5 | Werkstätten verkaufen ans Umland. Erlös je Arbeitstag = min(140, 50.000 / alle Werkstatt-Arbeitenden) | Einzige Geldquelle von außen und als Wachstumsgrenze gedacht (siehe „Bekannte Schwächen“) |
| 6 | Läden haben eine Kapazität: 5 Leute je Stelle (Besitzer zählt mit), also 35 pro Laden. Ist der Laden voll, geht man zum nächsten mit Platz in Reichweite. Der Laden kauft Ware ein: eine Kiste je 38 Taler Umsatz (Annahme 59; bis zur Arbeit-Erweiterung pauschal die Hälfte des Umsatzes nach außen) | Sonst schluckt ein Laden in der Mitte die ganze Stadt. Ohne Wareneinsatz entsteht pro Kopf eine halbe Ladenstelle, und die Stadt schaukelt sich auf (siehe Schwächen) |
| 7 | Stammladen: Man bleibt beim Laden, solange er offen, in Reichweite und nicht voll ist. Den nächstgelegenen sucht man beim ersten Einkauf oder wenn der eigene wegfällt | Weicht vom Wortlaut „Einkauf beim nächsten Laden“ ab. Ohne das nimmt jeder neue Laden dem Nachbarn sofort die Kundschaft weg |
| 8 | Wer Erspartes hat, gibt täglich bis 1 % davon (höchstens 15) zusätzlich aus, Sparsame weniger | Sonst sammelt sich das Geld bei den Leuten, und die Läden bekommen nichts ab |
| 9 | Besitzer zahlen Lohn nach Charakter: wenig sparsam = großzügiger (90–110 % vom Grundlohn) | Gibt `job_wechseln` einen Grund |
| 10 | Pleite-Betriebe stehen leer und können übernommen werden (40 % der Baukosten). Eine Übernahme zählt als Gründung | Die Spec sagt „Gebäude wird frei“ |
| 11 | Zuzug: Als „freie Stellen“ zählen nur freie Stellen in Werkstätten und Tech-Firmen (nicht im Bauhof, nicht in Läden), abzüglich der Arbeitslosen der Stadt. Wer zuzieht, tritt sofort die nächste solche Stelle an; ist keine mehr frei, kommt an diesem Tag niemand mehr. Zuzügler sind 18–60 Jahre alt (bis zur Gate-4-Änderung 18–45). Höchstens 1 + 1 % der Einwohner pro Tag | **Weicht vom Wortlaut der Spec ab** („freie Stellen“); Noahs Entscheidung für Gate 4. Zählten Ladenstellen, holte jeder neue Laden Leute von außen, die wieder neue Läden brauchen: Ladenboom, danach Pleitewelle. Läden stellen deshalb nur Leute aus der Stadt ein. Mit 18–45 ging die erste Generation fast gleichzeitig in Rente. Arbeitslose abziehen: sonst ziehen Leute für Stellen zu, die Einheimische ohnehin gleich nehmen |
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
| 22 | Straßen auf einem 4er-Raster (Blöcke 3×3). Bauplätze sind Felder neben einer Straße, die nicht auf dem Raster liegen. Das Bauamt verlängert meist ein Ende geradeaus, biegt an Kreuzungen manchmal ab und legt in 30 % der Fälle eine Abzweigung an. **Straßen sind sofort fertig** (keine Baustelle). Häuser, Betriebe, Parks und Aufstockungen brauchen Arbeitstage vom Bauhof (Annahme 58); bei einer Aufstockung (`g.auf`) bleibt das Haus bewohnt | Neue Straßen werden nie von Häusern blockiert |
| 23 | Bauamt: Regel 1 baut höchstens 1 + Einwohner/300 Häuser pro Tag. Park nur in Vierteln mit ≥ 8 Bewohnern und weniger als 1 + Bewohner/60 Parks. Notbremse höchstens alle 14 Tage | Die Spec sagt „einmal pro Spieltag“, aber nicht wie viel |
| 24 | Betriebe bleiben auf Stufe 1. Die Formel „Stufe × Stellen“ ist vorbereitet | Die Spec sagt nicht, wer Betriebe aufstuft. Das Bauamt stuft laut Regel 4 nur Wohnhäuser auf |
| 25 | Stadtbuch: Die Zuzüge eines Tages stehen in einer Zeile (mit Grund), alles andere einzeln | Sonst füllen Zuzüge die 500 Zeilen allein |
| 26 | Gate 6 und 7 vergleichen mit **allen, die je als Erwachsene in der Stadt lebten**. Beim Wegzug zählt nur die Person, die entschieden hat, nicht ihre Familie | Die heutigen Erwachsenen sind schon gefiltert (die Heimatlosen sind weg), das würde den Unterschied schönen |
| 27 | Gate 4: „pendelt sich ein“ = die Einwohnerzahl bleibt in den letzten 180 Tagen (Tag 551–730) in einem Band von Faktor 1,15 (max/min). „Unterhalb der Kartengrenze“ = keine Straße hat die äußerste erlaubte Rasterlinie erreicht | Die Spec gibt keine Zahl |
| 28 | Die Stadt hat noch keinen Namen. In der Anweisung ans Modell steht „Neustadt“ (Konstante `STADTNAME`) | Die Spec nennt `{Stadtname}`, aber keinen |
| 29 | Kein Modellname im Code. Die App nimmt das erste Modell aus Ollamas eigener Liste (`/api/tags`), Noah kann in den Einstellungen wechseln | Spec: „Kein Modellname aus dem Gedächtnis“. Noah konnte ich heute Nacht nicht fragen |
| 30 | Anfrage mit `format: "json"` (erzwingt gültiges JSON), `stream: false`, `think: false`, `keep_alive: "30m"`. Kein JSON-Schema. Die Anweisung geht als `system`-Nachricht, dazu eine kurze `user`-Nachricht („Es ist Tag 12, 7 Uhr. Was tust du?“ bzw. Noahs Satz). Lehnt ein Modell das Feld `think` mit HTTP 400 ab, wiederholt die App den Aufruf einmal ohne es | Alles laut Ollama-Doku. Ein Schema mit Aufzählung der Aktionen wäre strenger, ist aber ungetestet. `keep_alive` 30 Minuten, weil zwischen 7 und 18 Uhr bei 1× gut 11 Minuten liegen (Standard 5 Minuten → Modell würde jedes Mal neu geladen) |
| 31 | `neues_ziel`: `null`, fehlend, `""` und `"null"` gelten als „kein neues Ziel“. Ohne `gedanke` (leer oder fehlend) ist eine Antwort ungültig | Kleine Modelle schreiben das oft so; es ist eindeutig gemeint. Ohne Gedanken gäbe es keinen Tagebucheintrag |
| 32 | Hauptfigur werden nur Erwachsene | Kinder haben keine Aktionen |
| 33 | Eine KI-Figur wählt immer eine der erlaubten Aktionen. „Nichts tun“ gibt es nicht | Die Spec hat keine solche Aktion, und neue Aktionen sind verboten. Folge: Hauptfiguren handeln öfter als das normale Gehirn (das unter der Schwelle nichts tut) |
| 34 | „Erlaubte Aktionen“ = Voraussetzungen wie im Gehirn. Zwei Gedächtnis-Wirkungen gelten dabei als Voraussetzung: kein zweites Kind innerhalb von 30 Tagen, Trennen nur, wenn beide seit 14 Tagen unzufrieden sind (ohne den 3-%-Zufall) | Im Gehirn sperren sie praktisch; sonst könnte ein Modell täglich ein Kind wählen. `simtest --kitest` prüft, dass das Gehirn nie etwas wählt, das in der Liste fehlt |
| 35 | Im Gespräch bekommt das Modell dieselbe Beschreibung der Person (Name, Charakter, Ziel, Erlebtes, Befinden), aber nicht die Aktionsliste und nicht deren JSON-Format, sondern das Gesprächsformat | Beide Formate zusammen widersprechen sich |
| 36 | „Wie es dir geht“ enthält außer den Bedürfnissen einen Satz zur Lage: Arbeit, Partner, Kinder, Zahl der Freunde | Ohne das kann das Modell „job_wechseln“ oder „zusammenziehen“ nicht sinnvoll wählen |
| 37 | Ein Gespräch löst keine eigene Entscheidung aus. Es wirkt über die Erinnerung „mit Noah geredet“ (mit Noahs Worten in der nächsten Anweisung) und ein neues Ziel bei der nächsten Entscheidung um 7 oder 18 Uhr. Höchstens eine solche Erinnerung pro Tag. Ein Ziel, das schon erreicht ist (eigene Wohnung, eigener Laden, Ruhe), übernimmt die Figur nicht, weder aus dem Gespräch noch aus einer KI-Entscheidung | Spec: „Mehr kann ein Gespräch nicht ändern.“ Sonst verbrauchte jedes Gespräch eine der 3 KI-Entscheidungen des Tages, und mehrere Gespräche drängten das übrige Gedächtnis hinaus. Ein schon erreichtes Ziel würde sofort als „erreicht“ gezählt und ersetzt |
| 38 | Ist Ollama nicht erreichbar, entscheiden wartende Hauptfiguren sofort normal, nicht erst nach 2 Spielstunden. Kommt eine Antwort später als in der Stunde nach der Anfrage, wird sie gegen die aktuelle Uhrzeit geprüft (kein „freinehmen“ mehr um 9 Uhr). Geht die gewählte Aktion nicht mehr, entscheidet das normale Gehirn; im Tagebuch steht dann „(klappte nicht)“ | Spec: „Ollama aus: Hauptfiguren entscheiden normal“. Ein Tag frei ab 9 Uhr kostete den ganzen Tageslohn |
| 39 | Die Anweisung für den Tagebucheintrag nach dem Aufholen habe ich formuliert (Beschreibung wie oben, Erlebtes nur aus der Zeit der Abwesenheit, Antwort `{"eintrag": "…"}`) | Die Spec gibt keinen Wortlaut |
| 40 | Stirbt oder geht eine Hauptfigur, verschwindet ihr Tagebuch mit ihr. Vorschläge für die Nachfolge: Partner und erwachsene Kinder, die noch in der Stadt leben | Die Spec sagt „schlägt ein Kind oder den Partner vor“ |
| 41 | Spielstand-Version 4 (2: Hauptfiguren und Tagebuch, 3: Bauhof und Kisten, 4: Tech-Firmen). Stände anderer Versionen lösen den Versionsdialog aus; Version 2 und 3 lassen sich übernehmen (Annahme 60) | Neue Felder |
| 42 | Bei 1× ist eine echte Minute eine Spielstunde | Folgt aus der Spec: 90 Spieltage entsprechen 36 Stunden Abwesenheit |
| 43 | Beim Aufholen (Tagesschritte) entscheiden alle nur um 7 und 18 Uhr; Ereignisse lösen keine zusätzliche Entscheidung aus. Der Bauhof teilt direkt nach der 7-Uhr-Entscheidung ein, wie stündlich | Sonst wäre der Tagesschritt nicht schneller. Abweichung gegen stündlich nach 90 Tagen (Seeds 1–10, Tag 200–290): im Mittel +0,7 % Einwohner, einzeln −5,8 % bis +10,8 % (vor der Zuzug-Regel −1,7 %, einzeln −8,6 % bis +8,1 %) |
| 44 | Grundregel: Eine Figur steht oder geht nur dort, wo die Simulation die Person in dieser Stunde hat. Arbeit 8–17 Uhr (Bauarbeiter auf ihrer Baustelle), abends bei Freunden 19–22 Uhr (wer „freunde_treffen“ gewählt hat), wer frei hat um 10 Uhr einkaufen, sonst zu Hause. Ändert sich der Ort, geht die Figur dorthin. Von den 300 Figuren sind bis zu 120 Leute bei der Arbeit (Annahme 62), die übrigen zufällige Erwachsene, die nur unterwegs zu sehen sind. Hauptfiguren sind immer zu sehen: wenn sie nicht laufen, stehen sie vor dem Gebäude, in dem sie gerade sind. Ihre Markierung ist gelb, weiß solange sie „überlegen“. Jede sichtbare Figur ist anklickbar | Die Spec sagt „morgens zur Arbeit, abends heim oder zu Freunden“ und „plus immer alle Hauptfiguren“ |
| 45 | Fenster: Abends (ab 18–19:30 Uhr, je Haus verschieden) sind so viele Geschosse hell, wie das Haus belegt ist; spät in der Nacht etwa ein Drittel davon, aber jedes bewohnte Haus mindestens eins; morgens von 5:30 bis etwa 7 Uhr die Hälfte. Leere Häuser bleiben dunkel. Die Fenster sind unbeleuchtetes Material (`MeshBasicMaterial`) mit Lichtfarbe, das wirkt wie „emissive“ | Ein Haus, in dem um 2 Uhr alles an ist, sah unecht aus |
| 46 | Ist der Spielstand pausiert gespeichert, holt die Stadt beim Öffnen nichts auf | Pause heißt, dass die Stadt nicht weiterläuft |
| 47 | Aufgeholt wird auch, wenn ein Tab mindestens eine Minute versteckt war und wieder sichtbar wird. Die Karte „Während du weg warst“ und die Tagebucheinträge danach gibt es erst ab einem ganzen verpassten Spieltag | Browser halten die Animation in versteckten Tabs an; ohne Aufholen stünde die Stadt dann still |
| 48 | „Hochzeit“ im Stadtbuch heißt: ein Paar zieht zusammen | Die Aktionsliste der Spec kennt kein Heiraten, nur `zusammenziehen` |
| 49 | Unter 720 px Breite stehen Hauptfiguren und Stadtbuch unten; die Leiste zeigt dann nur die Initialen (Tippen öffnet die Karte mit Name und Tagebuch) | Auf dem Handy ist oben rechts kein Platz für zwei Panels |
| 50 | Die Personenkarte zeigt außer Charakter, Ziel, Gedächtnis, Familie und Freunden auch Befinden, Geld, Arbeit und Wohnung; Häuser, Läden und Werkstätten haben eine Karte mit Bewohnern bzw. Belegschaft. Leertaste = Pause | Die Spec verlangt Hausklick → Bewohner; der Rest macht die Karten erklärbar (Phase-3-Gate: „warum hat die eine einen Laden und die andere nicht“) |
| 51 | Geld und Wohnen ändern sich einmal am Tag (mit Lohn, Miete und Einkauf um Mitternacht), Kontakt und Freizeit stündlich. Nach einem Umzug am Morgen gilt die neue Wohnung also erst ab Mitternacht | Spec: alle vier „verändern sich stündlich“. Geld fließt nur täglich; die Umstellung hätte die getesteten Gate-Zahlen verändert. **Frage an Noah**, ob Wohnen stündlich nachziehen soll |
| 52 | Vier Aktionen addieren Dringlichkeit und Charakter statt sie zu multiplizieren: job_wechseln (45·Ehrgeiz + 0,3·Geldnot), partner_suchen, zusammenziehen, kind_bekommen | So beim Abstimmen der Gate-Werte in Phase 0 entstanden. Die Spec-Formel ist bei diesen vier nicht eingehalten; eine Umstellung verändert die Gate-Zahlen und ist nicht getestet |
| 53 | Betriebe haben laufende Kosten (Laden 30, Werkstatt 40 Taler am Tag), und der Besitzer lässt 400 Taler als Polster in der Kasse, erst darüber bekommt er etwas | Die Spec sagt nur „Besitzer bekommt Umsatz minus Löhne“. Kosten und Polster kamen beim Abstimmen der Wirtschaft in Phase 0 dazu. Seit Phase 4 nennt das Stadtbuch bei vollen Läden die Kosten als Pleitegrund |
| 54 | „Jemand Nahes gestorben → Heimatliebe zählt stärker“ wirkt beim Wegziehen (Heimatliebe × 1,5), nicht beim Umziehen innerhalb der Stadt | Die Spec knüpft Heimatliebe an „zieht schnell weg oder um“. Beim Umziehen fehlt die Trauer-Wirkung, das ist eine Lücke, keine bewusste Entscheidung |
| 55 | Mehr als 5 Hauptfiguren erlaubt die App erst, wenn mindestens 5 KI-Entscheidungen im Schnitt unter 5 Sekunden kamen (Gespräche, Tagebucheinträge und Code-Stücke zählen nicht mit). Die Messung wird mitgespeichert und beginnt bei einem Modellwechsel neu | Spec: „5 als Standard, bis 10 nur, wenn eine Entscheidung unter 5 Sekunden braucht“ |
| 56 | `zuletztGelaufen` ist der Moment, in dem die Stadt zuletzt lief: in einem versteckten Tab der Moment des Versteckens, mitten im Aufholen „jetzt minus die noch fehlenden Stunden“ | Sonst ginge die Zeit verloren, wenn der Browser mit dem Tab im Hintergrund geschlossen wird |
| 57 | Namen von Leuten, die nicht mehr in der Stadt sind (gestorben oder weggezogen), sind anklickbar und öffnen eine kurze Karte „nicht mehr in der Stadt“. Ob jemand starb oder wegzog, weiß die Karte nicht mehr, deshalb kein † | Spec: „Jeder Name auf der Personenkarte ist wieder anklickbar“; die Daten der Person sind nach dem Weggang frei |
| 58 | Bauhof: 10 Stellen plus eine je 4 offene Arbeitstage, höchstens 40; neu gerechnet, sobald eine Baustelle dazukommt (Gründung, Bauamt) und jede Nacht. Lohn 95–120 Taler: +2 am Tag, wenn um 7 Uhr Leute fehlten, sonst −1. Schrumpfen die Stellen, bleibt niemand ohne Arbeit, es wird nur nicht nachbesetzt. Freie Stellen im Bauhof locken keinen Zuzug an, und Gründer rechnen den Bauhof mit seinen 10 festen Stellen | Die Stellen gehen mit den Baustellen auf und ab. Zählten sie beim Zuzug oder bei „Werkstatt lohnt sich“, würde jede Baustelle Leute in die Stadt holen bzw. Werkstätten verhindern (im Entwurf gemessen: die Stadt schaukelt sich auf). Mit festem Lohn lief der Bauhof leer |
| 59 | Kisten: Kistenpreis = Umlandpreis je Arbeitstag / 8 (etwa 15–17 Taler), von außerhalb 19 Taler. Die Werkstatt nimmt je Arbeitstag dasselbe ein wie vorher, egal ob ein Laden oder das Umland die Kisten nimmt. Gründer zahlen Bau oder Übernahme an die Stadtkasse, die Stadt zahlt dafür die Bauarbeiter | Noahs Entscheidung A: Kisten als Preisvorteil für Läden, keine echte Knappheit (siehe Schwächen). Mit „Umland kauft nur die Hälfte“ hatte die Stadt im Entwurf an Tag 365 im Schnitt 891 statt 1.170 Einwohner, ohne dass Gate 4 besser wurde |
| 60 | Ein Spielstand von Version 2 oder 3 lässt sich im Versionsdialog mit „Stadt übernehmen“ umrechnen. Von 2: Bauhof = Werkstatt der Stadt vom Start, laufende Baustellen bekommen 4 Arbeitstage je Resttag (höchstens so viele wie der ganze Bau). Von 3: Tech-Firmen entstehen danach von selbst, niemand hat schon ein Gerät. Alles andere bleibt. Ein Import einer alten Datei rechnet ohne Nachfrage um | **Abweichung von der Spec** (dort nur Export oder Neu), Noahs Entscheidung B: sonst wäre seine Stadt weg |
| 61 | Theke und Träger sind nur zum Anschauen. Wer heute trägt, ergibt sich aus Tag und Laden (reihum), nicht aus Zufall. Der Lieferant ist die Werkstatt, die gestern die meisten Kisten brachte | Die Kisten werden um Mitternacht in einem Schritt verteilt; die Träger zeigen das tagsüber |
| 62 | Die 120 Arbeitsplätze unter den Figuren werden um 8 Uhr nach Nähe zur Kamera vergeben (beim Öffnen mitten am Tag sofort) und bleiben bis zum nächsten Morgen | Alle Arbeitenden wären bei 5.000 Einwohnern über 2.000 Figuren. Fest statt kameraabhängig, damit keine Figur beim Drehen springt |
| 63 | Stadtbuch: fertige Bauten eines Abends in einer Zeile („Der Bauhof hat fertig gebaut: …“), Stillstand, wenn auf einer Baustelle 5 Tage niemand war, und wenn der Bauhof-Lohn über 100, 110 oder 120 steigt | Mit Tech-Firmen kommen die neuen Versionen dazu (im Schnitt 0,48 Zeilen am Tag): auf 40 Seeds 5,50 Zeilen am Tag, 7 Seeds über 6,5, höchstens 8,60. Ohne Tech-Firmen: auf 40 Seeds (730 Tage) im Schnitt 0,26 neue Zeilen am Tag. Insgesamt 5,25 statt 4,86 Zeilen am Tag. **Die Plan-Grenze von 6,5 Zeilen am Tag hält nicht überall:** 5 von 40 Seeds liegen darüber (vorher 5), darunter der offizielle Seed 1 mit 6,79 (vorher 4,94). Ohne die neuen Zeilen wären es bei Seed 1 immer noch 6,50; der Rest kommt daher, dass die Stadt sich anders entwickelt (mehr Hochzeiten und Trennungen) |
| 64 | Tech-Firma statt Werkstatt gründet, wer Fleiß + Ehrgeiz ≥ 120 hat, solange die Tech-Stellen danach höchstens 40 % der Umland-Stellen sind (Werkstätten plus Tech) und das Geld reicht (Bau 2.000 + Startkasse 300, leere Tech-Firma übernehmen 1.100). Fehlt ein Laden, wird wie bisher ein Laden gegründet. Ob es sich lohnt, prüft wie bei der Werkstatt der Umlandpreis; die Tech-Stellen zählen dort mit. Produkt: das in der Stadt seltenste. Firmenname aus 30 Marken (Seed-Zufall), Versionen heißen „Marke Nummer“ | Noahs Entscheidung: eine Betriebsart über die vorhandene Aktion, keine neue Aktion. Ohne Obergrenze würden Tech-Firmen die Werkstätten verdrängen (beide teilen sich das Umland) |
| 65 | Tech-Firma: 4 Stellen je Stufe, Lohn 105 (90–110 % je nach Sparsamkeit des Besitzers), laufende Kosten 45 am Tag. Einnahmen: anwesende Angestellte × Umlandpreis (derselbe Topf von 50.000 wie bei den Werkstätten) plus 80 % der Verkäufe in der Stadt | Das Umland als gemeinsame Grenze hält das Wachstum im Rahmen |
| 66 | Käufe beim täglichen Einkauf: nur wer heute eingekauft hat und danach über 600 Taler hat. Erst ein Gerät (Fleißige ab 60 wollen einen Computer, alle anderen ein Handy; gibt es das nicht, das andere; nach 120 Tagen ein neues), mit Gerät alle 40 Tage Software, dazwischen mindestens 20 Tage. Preise 180 (Handy), 320 (Computer), 60 (Software). Chance am Tag 4 % × (1,3 − Sparsamkeit/100), doppelt so hoch, wenn die Version höchstens 15 Tage alt ist. 20 % behält der Laden, 80 % bekommt die Firma. Freizeit sofort +12 / +15 / +6, keine Dauerwirkung | Noahs Entscheidung „auch die Leute in der Stadt kaufen“, ohne neue Aktion. Im Entwurf hob eine Dauerwirkung am Abend die Zufriedenheit und damit den Zuzug; sie ist wieder raus |
| 67 | Anbau: Läuft eine Tech-Firma gut (alle Stellen besetzt, 20 Tage in Folge Gewinn), gehen 50 % des Gewinns über dem Polster in eine Rücklage, bis der Anbau bezahlt ist (Stufe 2: 1.800, Stufe 3: 3.000). Den Auftrag an den Bauhof gibt sie erst, wenn das Umland Platz hat (dieselbe Grenze wie für eine neue Werkstatt) und mindestens 4 Leute Arbeit suchen. Der Bauhof baut 12 bzw. 16 Arbeitstage, danach 8 bzw. 12 Stellen. Schließt die Firma, bekommt der Besitzer die Rücklage | Noahs Entscheidung „Bauauftrag an den Bauhof“. Ohne die Umland-Grenze schuf jeder Anbau Stellen über das Gleichgewicht hinaus |
| 68 | Echte Code-Stücke: eine Hauptfigur, die gerade (9–16 Uhr) in ihrer Tech-Firma arbeitet, schreibt höchstens einmal je Spieltag. Nicht bei 20×, nicht ohne Ollama, immer nur ein Aufruf gleichzeitig; die Stadt wartet nicht. Antwort `{"titel", "sprache", "code", "gedanke"}`; der Code wird gekürzt (höchstens 20 Zeilen zu 100 Zeichen, 1.500 Zeichen), nur als Text angezeigt und nie ausgeführt. Wer heute schon Code geschrieben hat, merkt sich die Seite nur bis zum Neuladen | Noahs Entscheidung „beides“. Der Code ist Ausdruck der Figur, er wirkt nicht auf die Simulation |
| 69 | Stadtbuch: Gründung einer Tech-Firma (mit Fleiß und Ehrgeiz), alle neuen Versionen eines Tages in einer Zeile (erscheinen zwei vom selben Produkt am selben Tag, liegt nur die der ersten Firma im Regal; die andere steht als „am selben Tag fertig, aber nicht im Regal“ dabei), Bauaufträge für Anbauten, fertige Anbauten in der Fertig-Zeile des Bauhofs | Sonst füllten die Versionen das Stadtbuch |

## Bekannte Schwächen

**Gate 4 hält jetzt fast immer, dafür wächst die Stadt langsamer an.** Seit der Zuzug-Regel (Annahme 11) liegen die offiziellen
Seeds 1, 2 und 3 bei Faktor 1,09, 1,10 und 1,09 (vorher 1,30, 1,23 und 1,18: keiner bestand). Gemessen über 80 Seeds
(simtest --gate je Seed, Band Tag 551–730):

| Stand | Gate 4 besteht | Band im Mittel | Median | Seeds über 1,5 | schlimmster |
|---|---|---|---|---|---|
| vor Bauhof und Kisten | 21 von 80 | 1,286 | 1,22 | 10 | 2,20 |
| mit Bauhof und Kisten | 26 von 80 | 1,255 | 1,21 | 5 | 2,15 |
| dazu Tech-Firmen | 24 von 80 | 1,275 | 1,20 | 13 | 2,02 |
| Placebo: Bauhof und Kisten plus eine Zufallszahl am Tag, sonst nichts | 22 von 80 | 1,303 | 1,25 | 12 | 2,28 |
| **dazu Zuzug nur für Werkstatt- und Tech-Stellen (heute)** | **76 von 80** | **1,076** | **1,07** | **0** | **1,21** |
| Placebo dazu: heute plus eine Zufallszahl am Tag | 77 von 80 | 1,070 | 1,06 | 0 | 1,17 |
| heute auf frischen Seeds 81–160 | 79 von 80 | 1,074 | 1,06 | 0 | 1,15 |
| Tech-Firmen ohne Zuzug-Regel auf den Seeds 81–160 | 22 von 80 | 1,308 | 1,23 | 11 | 2,62 |

Vorher war Gate 4 Glückssache: Unterschiede zwischen den Ständen waren kleiner als das Placebo, das keine Regel ändert. Gate 4
hing davon ab, wann zufällig ein Ladenboom mit Pleitewelle einsetzte (Beispiel Seed 15 ohne Tech: die Läden stiegen von Tag 600
bis 720 von 69 auf 184, die Stadt von 1.181 auf 2.414 Einwohner, danach standen 103 Betriebe leer). Die Ursache: Jede freie
Ladenstelle lockte Zuzug an, die Zuzügler brauchten neue Läden, deren Stellen lockten wieder Zuzug an. Dazu kam ein Echo der
ersten Generation: Die große Zuzugswelle aus Jahr 1 ging fast gleichzeitig in Rente. Die drei Teile der Regel wirken nur
zusammen; die Zuzügler 18–60 statt 18–45 allein waren früher auf 6 Seeds nicht besser, mit den beiden anderen Teilen bestehen
auf den Seeds 1–20 mit 18–60 19 von 20, mit 18–45 nur 12. Getestet und verworfen: Zuzug halb so schnell, Zuzug über etwa
10 Tage geglättet.

**Die Stadt wächst langsamer und bleibt kleiner.** Über die Seeds 1–80 hat sie im Mittel an Tag 180 177 statt 276 Einwohner,
an Tag 365 840 statt 1.141 (kleinster Wert 526 statt 959), an Tag 730 1.045 statt 1.551. Gate 1 (mindestens 300 an Tag 365)
hält trotzdem auf allen 160 Seeds. Dafür gibt es kaum noch Arbeitslose: an Tag 365 im Mittel 0,6 % statt 10,2 %, an Tag 730
3,8 % statt 11,3 %.

**Das Panel zeigt mehr freie Stellen, als Zuzug anlocken.** Die Zahl „freie Stellen“ im Panel zählt alle freien Stellen, auch
Läden und Bauhof. Für den Zuzug zählen nur Werkstätten und Tech-Firmen (Annahme 11). An Tag 730 zeigt das Panel im Median
121 freie Stellen (vorher 5), davon sind nur 12 in Werkstätten und Tech-Firmen. Wer das Panel liest, erwartet Zuzug, der nicht
kommt. Die Anzeige ist unverändert.

**Läden sind meist unterbesetzt.** An Tag 365 und 730 sind im Mittel 32 % und 33 % der Ladenstellen besetzt (vorher 99 %
und 95 %), weil Zuzügler nur in Werkstätten und Tech-Firmen anfangen. Ein Laden bedient trotzdem seine volle Kundschaft, denn
die Kapazität hängt an den Stellen, nicht an den Leuten (Annahme 6). Er spart nur Löhne. Das ist unrealistisch: Ein Laden mit
zwei von sechs Kräften bedient so viele Leute wie ein voller.

**Gate 7 ist knapp.** Es zählt nur die Leute, die bis Tag 730 wegziehen (auf Seed 1 sind es 19). Mit der Zuzug-Regel fiel
Gate 7 im Placebo auf 5 von 160 Seeds durch, ohne sie in den Seeds 81–160 auf 2 von 80. Auf den Seeds 1–160 ohne Placebo
fällt es nicht durch.

**Die Kisten machen nichts knapp.** Die Werkstätten machen etwa fünfmal so viele Kisten, wie die Läden brauchen: Auf den
Seeds 1–3 gingen von Tag 100 bis 300 je 21–22 % der Kisten an Läden der Stadt, die Läden bekamen 100 % ihrer Kisten aus der
Stadt, der Rest ging ans Umland. Eine Werkstatt nimmt dasselbe ein, ob ein Laden ihre Kisten nimmt oder nicht. Im Ergebnis
zahlen Läden etwa 42–43 statt 50 % ihres Umsatzes für Ware (Kistenpreis Tag 100–730 im Schnitt 16,0–16,4 Taler, Seeds 1–3). Echte Knappheit (Umland kauft weniger) war im Entwurf getestet und
ist verworfen (Annahme 59).

**Tech-Firmen kommen in einer ausgewachsenen Stadt nur langsam.** Sie teilen sich das Umland mit den Werkstätten und werden
nur gegründet, wenn dort Platz ist. Im Entwurf gab es nach dem Übernehmen einer Stadt von Tag 300 bzw. 400 in den 60 Tagen
danach keine Gründung, bei Tag 150 drei. In einer neuen Stadt entstehen auf den Seeds 1–3 in 730 Tagen 17–26 Tech-Firmen.

**Die echten Code-Stücke sind nur mit einem nachgebauten Ollama getestet.** Ob ein kleines Modell zuverlässig gültiges JSON mit
Code liefert (oder Code-Zäune und Erklärungen dazuschreibt), ist nicht gemessen. Ungültige Antworten zählen als ungültig und
landen nicht im Tagebuch.

**Viele Handys.** Auf den Seeds 1–3 haben an Tag 730 93–94 % der Erwachsenen ein Gerät; unterwegs leuchten deshalb bis zu 80 Handys.

**Das Budget ist nie knapp.** Ab etwa Tag 60 übersteigen Steuern und Mieten alle Ausgaben um ein Vielfaches. Die
Budgetgrenzen des Bauamts greifen deshalb praktisch nie. Gate 3 hält, weil jede Ausgabe vorher geprüft wird, nicht weil
das Budget eng wäre.

**Phase 4 ist nicht mit einem echten Sprachmodell getestet.** Im Container gibt es kein Ollama und keinen Download dafür.
Getestet ist gegen einen nachgebauten Server mit dem Request- und Antwortformat aus der Ollama-Doku: Anfragen, Fristen,
ungültige und kaputte Antworten, Zeitüberschreitung, Ollama aus, 20×, Gespräche, Tagebuch nach dem Aufholen. Offen sind
genau die Gate-Punkte, die ein echtes Modell brauchen: Anteil gültiger Antworten über 7 Spieltage, Dauer pro Antwort
(entscheidet, ob mehr als 5 Hauptfiguren gehen), und ob zwei verschiedene Charaktere erkennbar anders handeln.

**Frame-Zeit mit und ohne KI** (gegen den nachgebauten Server, im Wechsel gemessen, 3 Runden, mit Bauhof, Kisten und
Figuren bei der Arbeit): JavaScript pro Bild 7,5–11,1 ms mit KI und 7,5–8,9 ms ohne (vorher 5,7–9,1 und 7,8–9,2). Ein
Unterschied ist im Messrauschen nicht zu sehen; das Bildtempo begrenzt hier die Software-Grafik.

**60 Bilder pro Sekunde sind nicht gemessen.** Im Container rendert Chromium ohne Grafikkarte (SwiftShader) mit etwa
10 fps. Gemessen sind Draw Calls, Dreiecke und die Rechenzeit pro Bild in JavaScript. Nach der Design-Runde 2: Teststadt
(Seed 2, Tag 400) 19–21 Draw Calls, etwa 40.000 Dreiecke; große Stadt (`?debug&umland=300000&tage=750&seed=2`, 5.894
Einwohner) 20–22 Draw Calls, etwa 130.000 Dreiecke (nach Runde 1: 165.000–172.000, davor 102.742), 3–12 ms JavaScript pro
Bild, Konsole leer. Die Spec verlangt unter 100 Draw Calls; für Dreiecke gibt sie keine Grenze.

**Fensterreihen mit Alpha-to-Coverage sind auf echter Grafikhardware ungeprüft.** Seit Runde 2 ist jede Fensterreihe ein
Rechteck je Seite mit einer Textur, die Zwischenräume sind durchsichtig. Mit Kantenglättung (Multisampling) glättet
Alpha-to-Coverage die Kanten; ohne greift ein Alpha-Test. Manche Treiber zeigen Alpha-to-Coverage als feines Punktraster.
Im Container (SwiftShader) sieht es sauber aus.

**Der See liegt im Startblick der kleinen Teststadt außerhalb des Bildes.** In größeren Städten sieht man ihn links hinten.
