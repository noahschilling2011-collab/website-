# STADT

Eine Stadt, in der jeder Mensch selbst entscheidet. Projektname vorläufig.

**Stand: Phase 4 plus „richtige Arbeit“.** Simulation (Phase 0), 3D-Karte mit Tag und Nacht (1), Speichern und Aufholen (2),
laufende Figuren und Personenkarten (3), Hauptfiguren mit Ollama (4). Danach auf Noahs Wunsch: Bauarbeiter vom Bauhof
bauen die Häuser, Werkstätten machen Kisten für die Läden, und man sieht die Leute bei der Arbeit. Phase 4 ist nur gegen
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
| `?debug&umland=200000` | Größere Stadt (etwa 5.000 Einwohner an Tag 600) für den Leistungstest. Dieser Stand wird nicht gespeichert |

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

## Was die Leute arbeiten

Es gibt kein Feld „Beruf“ und keine neue Aktion. Der Beruf ergibt sich aus dem Arbeitsplatz:

- **Bauarbeiter/in** beim Bauhof (die Werkstatt der Stadt vom Start). Um 7 Uhr teilt der Bauhof seine Leute auf die
  Baustellen ein, älteste zuerst, höchstens 4 je Baustelle. Um Mitternacht bringt jede eingeteilte Person, die noch beim
  Bauhof ist und nicht frei hat, einen Arbeitstag. Ein Wohnhaus braucht 12 Arbeitstage, eine Aufstockung 12 bzw. 18, ein
  Laden 9, eine Werkstatt 12, ein Park 4. Ohne Bauarbeiter bleibt die Baustelle liegen. Wer keine Baustelle hat, macht Kisten.
- **Handwerker/in** in einer Werkstatt: 8 Kisten je Arbeitstag. Die Kisten gehen an die Läden der Stadt, der Rest ans Umland.
- **Verkäufer/in** im Laden: 5 Kunden je Kraft wie bisher. Ein Laden braucht eine Kiste je 38 Taler Umsatz und holt sie bei
  der nächsten Werkstatt der Stadt, die noch welche hat (bis 20 Felder weit), sonst teurer von außerhalb.
- **Theke** (Besitzer/in, sonst die erste anwesende Kraft) und **Träger/in** (reihum aus der Werkstatt, die liefert, um 9
  und 13 Uhr) sind nur zum Anschauen und wirken nicht auf die Simulation.

In der 3D-Ansicht wächst auf jeder Baustelle ein grauer Rohbau mit den geschafften Arbeitstagen. Das Gerüst wird dunkler,
solange niemand kommt, und lässt sich anklicken. Bauarbeiter (orange) stehen an den Ecken ihrer Baustelle, Handwerker
(blau) vor der Werkstatt. An Werkstätten stehen Kistenstapel, vor Läden eine Theke und eine Auslage (braun: Kisten aus der
Stadt, grau: von außerhalb). Personenkarten sagen „arbeitet als Bauarbeiterin beim Bauhof …“ und was die Person heute tut.

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
node tools/simtest.mjs --migrationstest        # Spielstand von Version 2 übernehmen (alte Datei aus git 39c405b), 60 Tage weiter
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
| 41 | Spielstand-Version 3 (2: Hauptfiguren und Tagebuch, 3: Bauhof und Kisten). Stände anderer Versionen lösen den Versionsdialog aus; Version 2 lässt sich übernehmen (Annahme 60) | Neue Felder |
| 42 | Bei 1× ist eine echte Minute eine Spielstunde | Folgt aus der Spec: 90 Spieltage entsprechen 36 Stunden Abwesenheit |
| 43 | Beim Aufholen (Tagesschritte) entscheiden alle nur um 7 und 18 Uhr; Ereignisse lösen keine zusätzliche Entscheidung aus. Der Bauhof teilt direkt nach der 7-Uhr-Entscheidung ein, wie stündlich | Sonst wäre der Tagesschritt nicht schneller. Abweichung gegen stündlich nach 90 Tagen (Seeds 1–10, Tag 200–290): im Mittel 0,0 % Einwohner, einzeln −6,0 % bis +4,0 % |
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
| 55 | Mehr als 5 Hauptfiguren erlaubt die App erst, wenn mindestens 5 KI-Antworten im Schnitt unter 5 Sekunden kamen. Die Messung wird mitgespeichert und beginnt bei einem Modellwechsel neu | Spec: „5 als Standard, bis 10 nur, wenn eine Entscheidung unter 5 Sekunden braucht“ |
| 56 | `zuletztGelaufen` ist der Moment, in dem die Stadt zuletzt lief: in einem versteckten Tab der Moment des Versteckens, mitten im Aufholen „jetzt minus die noch fehlenden Stunden“ | Sonst ginge die Zeit verloren, wenn der Browser mit dem Tab im Hintergrund geschlossen wird |
| 57 | Namen von Leuten, die nicht mehr in der Stadt sind (gestorben oder weggezogen), sind anklickbar und öffnen eine kurze Karte „nicht mehr in der Stadt“. Ob jemand starb oder wegzog, weiß die Karte nicht mehr, deshalb kein † | Spec: „Jeder Name auf der Personenkarte ist wieder anklickbar“; die Daten der Person sind nach dem Weggang frei |
| 58 | Bauhof: 10 Stellen plus eine je 4 offene Arbeitstage, höchstens 40. Lohn 95–120 Taler: +2 am Tag, wenn um 7 Uhr Leute fehlten, sonst −1. Schrumpfen die Stellen, bleibt niemand ohne Arbeit, es wird nur nicht nachbesetzt. Freie Stellen im Bauhof locken keinen Zuzug an, und Gründer rechnen den Bauhof mit seinen 10 festen Stellen | Die Stellen gehen mit den Baustellen auf und ab. Zählten sie beim Zuzug oder bei „Werkstatt lohnt sich“, würde jede Baustelle Leute in die Stadt holen bzw. Werkstätten verhindern (im Entwurf gemessen: die Stadt schaukelt sich auf). Mit festem Lohn lief der Bauhof leer |
| 59 | Kisten: Kistenpreis = Umlandpreis je Arbeitstag / 8 (etwa 15–17 Taler), von außerhalb 19 Taler. Die Werkstatt nimmt je Arbeitstag dasselbe ein wie vorher, egal ob ein Laden oder das Umland die Kisten nimmt. Gründer zahlen Bau oder Übernahme an die Stadtkasse, die Stadt zahlt dafür die Bauarbeiter | Noahs Entscheidung A: Kisten als Preisvorteil für Läden, keine echte Knappheit (siehe Schwächen). Mit „Umland kauft nur die Hälfte“ hatte die Stadt im Entwurf an Tag 365 im Schnitt 891 statt 1.170 Einwohner, ohne dass Gate 4 besser wurde |
| 60 | Ein Spielstand von Version 2 lässt sich im Versionsdialog mit „Stadt übernehmen“ umrechnen: Bauhof = Werkstatt der Stadt vom Start, laufende Baustellen bekommen 4 Arbeitstage je Resttag (höchstens so viele wie der ganze Bau), alles andere bleibt. Ein Import einer v2-Datei rechnet ohne Nachfrage um | **Abweichung von der Spec** (dort nur Export oder Neu), Noahs Entscheidung B: sonst wäre seine Stadt weg |
| 61 | Theke und Träger sind nur zum Anschauen. Wer heute trägt, ergibt sich aus Tag und Laden (reihum), nicht aus Zufall. Der Lieferant ist die Werkstatt, die gestern die meisten Kisten brachte | Die Kisten werden um Mitternacht in einem Schritt verteilt; die Träger zeigen das tagsüber |
| 62 | Die 120 Arbeitsplätze unter den Figuren werden um 8 Uhr nach Nähe zur Kamera vergeben (beim Öffnen mitten am Tag sofort) und bleiben bis zum nächsten Morgen | Alle Arbeitenden wären bei 5.000 Einwohnern über 2.000 Figuren. Fest statt kameraabhängig, damit keine Figur beim Drehen springt |
| 63 | Stadtbuch: fertige Bauten eines Abends in einer Zeile („Der Bauhof hat fertig gebaut: …“), Stillstand, wenn auf einer Baustelle 5 Tage niemand war, und wenn der Bauhof-Lohn über 100, 110 oder 120 steigt | Gemessen 0,2–0,3 Zeilen mehr am Tag (Seeds 1–3: 3,7–4,9 Zeilen am Tag) |

## Bekannte Schwächen

**Gate 4 hält nur auf einem Teil der Seeds.** Seit Bauhof und Kisten liegen Seed 1, 2 und 3 bei Faktor 1,23, 1,25 und 1,19
(vorher 1,37, 1,23 und 1,06): Seed 3 besteht nicht mehr, damit besteht keiner der drei offiziellen Seeds alle 7 Punkte.
Auf 40 Seeds (Noahs Entscheidung C, Maßstab „nicht schlechter als vorher“): Gate 4 bei 12 von 40 statt 9 von 40, Band im
Mittel 1,279 statt 1,285, Median beide 1,22. Seeds über 1,5: vier vorher, vier jetzt. Der schlimmste Seed ist schlechter:
2,36 (Seed 19) statt 1,96. Bei Seed 19 und 34 gibt es erst einen Ladenboom (37 → 177 bzw. 46 → 307 Läden in gut 100
Tagen: neue Läden bringen Stellen, Stellen bringen Zuzug), dann eine Pleitewelle. Läden verdienen mit den Kisten mehr,
deshalb gehen weniger früh pleite. Ganz am Anfang, vor Wareneinsatz, gedrosseltem Zuzug und Gründen nur mit Aussicht,
verdoppelte sich die Stadt im zweiten Jahr (Faktor 1,9–2,2). Was bleibt, ist ein Echo der ersten
Generation: Die große Zuzugswelle aus Jahr 1 geht fast gleichzeitig in Rente und stirbt fast gleichzeitig. Dann fehlen
erst Arbeitskräfte (neuer Zuzug), danach Kundschaft (Pleiten). Getestet und verworfen: Zuzug halb so schnell, Zuzügler
18–60 statt 18–45, Zuzug über etwa 10 Tage geglättet (jeweils nicht besser auf 6 Seeds).

**Die Kisten machen nichts knapp.** Die Werkstätten machen etwa fünfmal so viele Kisten, wie die Läden brauchen: Auf den
Seeds 1–3 gingen von Tag 100 bis 300 je 21 % der Kisten an Läden der Stadt, die Läden bekamen 100 % ihrer Kisten aus der
Stadt, der Rest ging ans Umland. Eine Werkstatt nimmt dasselbe ein, ob ein Laden ihre Kisten nimmt oder nicht. Im Ergebnis
zahlen Läden etwa 42–43 statt 50 % ihres Umsatzes für Ware (Kistenpreis Tag 100–730 im Schnitt 16,1–16,3 Taler, Seeds 1–3). Echte Knappheit (Umland kauft weniger) war im Entwurf getestet und
ist verworfen (Annahme 59).

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
10 fps. Gemessen sind Draw Calls (10–13 vor der Arbeit-Erweiterung, jetzt bis 15: Kisten-Mesh und Gerüst), Dreiecke
(unter 51.000) und die Rechenzeit pro Bild in JavaScript (5–11 ms). Mit 5.000 Einwohnern ist der neue Stand nicht nachgemessen.
