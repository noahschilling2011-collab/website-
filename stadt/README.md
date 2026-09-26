# STADT

Eine Stadt, in der jeder Mensch selbst entscheidet. Projektname vorläufig.

**Stand: Phase 4 plus „richtige Arbeit“, Tech-Firmen und Stadtregierung.** Simulation (Phase 0), 3D-Karte mit Tag und Nacht (1), Speichern
und Aufholen (2), laufende Figuren und Personenkarten (3), Hauptfiguren mit Ollama (4). Danach auf Noahs Wunsch: Bauarbeiter
vom Bauhof bauen die Häuser, Werkstätten machen Kisten für die Läden, man sieht die Leute bei der Arbeit, und Bewohner gründen
Tech-Firmen für Software, Handys oder Computer; Hauptfiguren, die dort programmieren, schreiben über Ollama echten Code. Von Anfang
an regiert die AfD nach ihrem Programm zur Bundestagswahl 2025, soweit es sich auf die Stadt übertragen lässt (Abschnitt
„Stadtregierung“); in einem zweiten Schritt kamen der Mieterkauf, der flexible Renteneintritt mit Rentner-Freibetrag und Kitas in Wohnraumnähe dazu. Phase 4 ist nur gegen einen nachgebauten Ollama-Server getestet, nicht gegen ein echtes Sprachmodell (siehe
„Bekannte Schwächen“).

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
| `?debug&umland=300000&tage=750` | Größere Stadt für den Leistungstest (Seed 2: etwa 6.000 Einwohner). Dieser Stand wird nicht gespeichert |

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
  fängt in einer Werkstatt oder Tech-Firma an; Läden (und seit Schritt 2 Kitas) finden ihre Leute nur in der Stadt (Annahme 11).
- **Programmierer/in** in einer Tech-Firma: Jede anwesende Person (auch der Besitzer) bringt um Mitternacht einen Arbeitstag an
  der nächsten Version. Eine Version braucht bei Software 40, beim Handy 60, beim Computer 50 Arbeitstage, danach erscheint sie
  („Nova 3“). Die Firma verkauft ans Umland (derselbe Topf wie die Werkstätten) und über die Läden an die Leute in der Stadt.
- **Erzieher/in** in einer Kita (seit Schritt 2, Abschnitt „Kitas in Wohnraumnähe“): Die Kita stellt nach Bedarf ein, eine
  Fachkraft je 8 belegte oder gewünschte Platzeinheiten und eine als Reserve, höchstens 5; je Fachkraft kann sie 8 Einheiten
  anbieten. Die Stadt zahlt den Lohn (95 bis 120 Taler). Während der Arbeit stehen sie auf dem Spielplatz vor dem Haus.
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

**Design-Runde 3.**
- Parks haben helle Wege, entweder als Kreuz mit Platz oder als Bogen, dazu Bänke und Beete. Manche haben einen Brunnen oder
  einen Teich mit Schilf. Nachts ist ihr Wasser dunkel wie der See, auch neben einer Laterne: Ihr Lichtfleck hellt nur den
  Rasen auf.
- Parks bleiben leer. Die Simulation schickt niemanden in einen Park: Er wirkt nur über Wohnhäuser in der Nähe (`g.parkNah`).
  Deren Bewohner haben abends mehr Freizeit (`R.FREIZEIT_PARK`), und die Wohnungen zählen beim Umziehen als besser (Annahme 14).
  Es gilt die Grundregel der Spec: Eine Figur steht nur dort, wo die Simulation die Person hat. Nur solange ein Park gebaut
  wird, stehen dort Bauarbeiter.
- Gärten sind mit niedrigen Hecken eingefasst.
- Leere Felder zwischen Häusern bekommen Büsche und hohes Gras.
- Die Leute sind kleine Figuren mit Beinen, Rumpf und Kopf statt Kapseln. Beim Gehen wippen sie leicht, bei reduzierter
  Bewegung nicht.
- Bauarbeiter tragen einen Helm.
- Hauptfiguren haben eine ruhigere goldene Raute.
- Der Startblick berücksichtigt die Panels, auf dem Handy liegt die Stadt zwischen ihnen.
- Das aktive Tempo ist getönt statt voll gelb.
- Das Stadtbuch zeigt das Symbol in der Tageszeile, dadurch hat der Text die volle Breite.
- Auf Tablets und quergehaltenen Handys liegen Karten und Spalten so, dass die Kennzahlen frei bleiben.

**Auswahl und Orientierung.**
- Klicks: Eine Figur zählt nur, wenn keine Wand deutlich näher davor liegt; ein Klick auf die Raute einer Hauptfigur öffnet diese
  Hauptfigur.
- Der Startblick misst jedes Gebäude als ganzes Feld bis zur Dachkante (vorher nur die Feldmitte). Die Stadt hält dadurch
  mindestens 12 px Abstand zu den Panels; öffnet sich eine Karte, rückt sie nur von ihr weg.
- Solange eine Hauskarte offen ist, ist das Gebäude leicht goldgetönt (nachts etwas stärker) und hat einen goldenen Rahmen am
  Boden und einen zweiten oben: auf der Dachkante oder an der Traufe (auch nachts zu sehen). So bleibt die Auswahl auch zu
  erkennen, wenn ein Hochhaus davor den Boden verdeckt. Eine Personenkarte markiert nichts. Schließen oder Escape nimmt die
  Markierung weg.
- Mit der Maus wird der Zeiger über Gebäuden und Figuren zur Hand, das Gebäude darunter wird etwas heller (nachts etwas mehr).
  Auf Touch nicht.
- Nah herangezoomt (Kameraabstand unter 35) stehen Straßennamen auf dunklen Schildern, höchstens 12, je Straße einer, in der
  Mitte eines Blocks. Namen hinter hohen Häusern, unter Panels oder übereinander werden weggelassen, auch wenn ein Panel bei
  ruhender Kamera größer wird (Stadtbuch aufgeklappt, Meldung). Sie blenden weich ein und aus, bei reduzierter Bewegung ohne
  Übergang.
- Die goldene Raute über Hauptfiguren ist im Startblick etwa 9 px hoch (sie wächst mit dem Abstand), hat einen dunklen Rand
  und ist aus der Ferne (Kameraabstand über 25) auch hinter Hochhäusern zu sehen.

**Feinschliff 2.**
- Straßennamen blitzen beim schnellen Drehen und beim Pinch nicht mehr kurz auf: Ein neues Schild erscheint erst, wenn seine
  Straße etwa 150 ms lang gewählt bleibt, und ein gezeigtes Schild wechselt erst dann an einen neuen Platz. Fällt die Wahl
  vorher weg, ändert sich nichts. Am alten Platz wartet ein Schild nur, solange er noch taugt (ganz im Bild, nicht unter
  Panels oder dem ausgewählten Gebäude, nicht verdeckt), und hält ihn so lange für sich frei; sonst blendet es dort gleich aus.
  Steht die Kamera, wird nichts nachgerechnet; ein Zeitgeber holt Wartende einmal nach.
- Die Schilder sind durchsichtiger, Figuren dahinter scheinen durch. Der Text hat vor reinem Weiß noch 5,1:1 Kontrast
  (gemessen hinter allen Schildern bei Tag, Abend und Nacht: mindestens 5,2:1).
- Der goldene Rahmen der Auswahl wird ab etwa 18 Einheiten Abstand zwischen Kamera und Gebäude mit dem Abstand breiter (höchstens 2,6-fach) und satter gold. Im
  Startblick ist das ausgewählte Hochhaus nachts auch zwischen erleuchteten Türmen zu finden. Nah bleibt er wie bisher.
- Liegt das ausgewählte Gebäude unter der Hauskarte, und auf dem Handy immer, gibt es oben in der Karte den Knopf „Zeigen“.
  Er rückt Blickpunkt und Kamera gleich weit, bis das Gebäude mitten in der freien Fläche neben oder über der Karte liegt. Die
  Fahrt dauert etwa 400 ms, bei reduzierter Bewegung springt die Kamera. Dreht oder zoomt man dabei selbst, bricht die Fahrt
  ab. Von selbst bewegt sich die Kamera weiterhin nie. Ob der Knopf gebraucht wird, prüft die Seite auch, wenn die Kamera nach
  dem Loslassen ausgeglitten ist. Er ist so hoch wie das Schließen daneben und hat 8 px Abstand dazu.
- Nach einem Import ist nichts mehr ausgewählt (Tönung und Rahmen weg). Der Datei-Import schließt die Karte wie bisher
  selbst, beim Übernehmen eines alten Stands bleibt sie, wie sie war. Nach dem stündlichen Neuaufbau prüft der Mauszeiger immer
  neu, was unter ihm liegt, auch wenn er vorher über leerem Boden stand oder gerade ein Drehen beendet hat.

**Ereignisse auf der Karte.** Was das Stadtbuch als fertig gebaut, Gründung (Übernahme eines leeren Betriebs), Pleite oder
Schließung meldet, sieht man auch am Gebäude: Um das Grundstück zieht ein flacher, weicher Ring am Boden einmal weit und
verblasst (gut 2,5 Sekunden echte Zeit). Fertig gebaut (auch Aufstockung und Anbau) und eröffnet im Akzent. Pleite und
Schließung gedämpft rot, und der Ring zieht sich dabei zusammen statt weit: So unterscheiden sich beide auch nachts, wenn fast
alle Pleiten und Fertigstellungen (0 Uhr) fallen und die Farben sich angleichen. Aus der Ferne (große Stadt) wird der Ring im
Bild etwa 20 px Radius groß (Pleite und Schließung ziehen sich auf etwa 10 px zusammen, bei reduzierter Bewegung etwa
16 px; auf niedrigen Bildschirmen wie dem Handy quer wird er von fern etwas kleiner) und rückt auf dem Sehstrahl zur Kamera: Im Bild liegt er an derselben Stelle, wird
aber nicht mehr von den Nachbarhäusern verdeckt. Nah (Ring weniger als 45 Einheiten von der Kamera) bleibt er am Boden. Die Simulation meldet
dafür nichts: Die Karte vergleicht stündlich jedes Gebäude mit der Stunde davor (Baustelle → fertig, Stufe, leer/offen). Eine
Gründung auf freiem Bauplatz zeigt sich also erst, wenn der Bau fertig ist. Höchstens 12 Ringe zugleich, mehrere leicht
nacheinander, bei 20× höchstens 3 je Stunde (das Gebäude der offenen Karte zuerst); keine beim Start, nach Import oder Aufholen und nach Sprüngen über mehr als 3
Stunden. Bei reduzierter Bewegung steht der Ring still und ist nach 3 Sekunden ohne Übergang weg. Nicht klickbar; solange ein
Ring läuft, 1 Draw Call und 2 Dreiecke je Ring mehr, sonst nichts (ein Shader-Programm mehr, schon beim Start übersetzt).
Im Browser geprüft (Lage, Farbe, Draw Calls, Drosselung, reduzierte Bewegung).

**Stadtrand und Umland.** Aus der Stadt führen vier Landstraßen ins Umland: schmaler als die Stadtstraßen (0,42 statt 0,6
Fahrbahn), etwas dunkler, ohne Gehweg und Laternen. Draußen liegen sie fest: Von vier Ausfahrten am Kartenrand, je auf einer
Rasterlinie, laufen sie in weiten Bögen bis 400 hinaus, drehen sich zu tieferem Gelände hin, liegen auf den Hügeln auf und
führen südlich um den See herum. Im Wald haben sie eine Schneise (7 Bäume, meist geht es durch lichten Wald). Das Stück in der
Stadt legt die Karte nur neu, wenn Straßen dazukommen: Es beginnt an einem Straßenende, das zur Ausfahrt zeigt, oder an einem
Rasterpunkt am Rand, wo auch die Simulation abzweigen würde (das kostet bei der Wahl mehr), geht ein Feld geradeaus und dann in
einem Bogen (Radius mindestens 3) zur Ausfahrt. Es führt nur über leere Felder ohne Bauplatz, und dort legt die Karte keinen
Garten und keine Brache an; Gebäude entstehen nur auf Bauplätzen und Bauplätze nur mit neuen Straßen, so bleibt der Weg frei.
Wächst die Stadt, rückt der Anfang mit, und das Stück kann an ein anderes Ende springen. In einer jungen Stadt mit einer
Straße wird daraus ein Dorf an einer Kreuzung. Auf den Seeds 1 bis 8 sind an den Tagen 2, 30, 60, 120, 200, 300, 400, 600 und
750 immer alle vier Ausfahrten verbunden; neu legen dauert dort 0,7 bis 7,1 ms (je Stand der schnellste von 6 Läufen).
Zwischen Stadt und Wald liegen Felder: Parzellen von 12 × 12 in ein bis drei Stücken, Acker, reifes, junges und dunkles Feld
mit Reihen, dazwischen Wiese und schmale Raine, nur leicht gegen die Wiese abgesetzt. Sie sind kein eigenes Mesh, der Boden färbt sie im Shader und ist nachts so dunkel wie
sonst. Die Stadt verdrängt sie blockweise (4 × 4 zwischen den Rasterlinien): kein Feld auf oder direkt neben Straße, Bauplatz
oder Gebäude. In der Teststadt sind 520 von 558 möglichen Blöcken Feld, in der großen Stadt 352. Nachts leuchten an den
Landstraßen 32 schwache warme Lichtpunkte von Höfen und zwei Dörfern, 60 bis 173 von der Mitte, ohne Blinken, mit der
Dämmerung ein- und ausgeblendet. Keine Figuren oder Fahrzeuge auf den Landstraßen; nichts davon ist klickbar oder wirkt auf
die Simulation. Kosten: 1 Draw Call mehr, nachts 2 (Teststadt 23 bzw. 24 statt 22, große Stadt 24 bzw. 25 statt 23);
Dreiecke um 11 Uhr in der Teststadt 44.186–44.236 statt 42.568–42.598, in der großen Stadt 143.297–143.347 statt
142.063–142.093. Gemessen im Startblick um 11 und 23 Uhr, alte und neue Fassung im Wechsel, auf einer geteilten Maschine: Die
JS-Zeit pro Bild streut in beiden Fassungen (Teststadt neu 10,3–37,5 ms, vorher 10,6–34,7 ms; große Stadt neu 9,8–54,3 ms,
vorher 8,7–22,5 ms), ein Unterschied ist darin nicht sicher zu sehen. Die Software-Grafik (SwiftShader) schafft in 9 von 10
Messpaaren etwas weniger Bilder je Sekunde, im Mittel 8 % (Teststadt 1,2–2,9 statt 1,5–2,5, große Stadt 1,1–1,3 statt
1,2–1,5); der Boden rechnet für die Felder je Bildpunkt einen Texturabruf und etwas mehr, auch wo gerade keine Felder im Bild sind
(nur der Boden gemessen: etwa 11–13 ms mehr je Bild bei 1280 × 800 in SwiftShader; ein früherer Ausstieg brachte dort nichts).
Auf echter Grafikhardware ungeprüft.

**Handy-Karte und Hilfe.**
- Auf dem Handy (bis 720 px breit, quer bis 500 px hoch) deckte eine offene Hauskarte 57 % (360 × 740) bzw. 58 % (400 × 820)
  des Bildes. Ein Pfeil im Kartenkopf (32 × 32 px, `aria-expanded`) klappt sie auf ihre Kopfleiste zusammen: 46 px hoch, 5,9 %
  bzw. 5,4 % des Bildes. Dort stehen dann der Titel, „Zeigen“ und das Schließen; der Inhalt ist verborgen, auch für Tab und
  Screenreader. Höhe und Inhalt gleiten 250 ms, bei reduzierter Bewegung ohne Übergang. Eine neue Karte öffnet aufgeklappt.
- „Zeigen“ klappt die Karte am Handy erst ein und rückt das Gebäude dann in die frei gewordene Fläche. Gemessen bei 400 × 820:
  von (198, 419) unter der Karte nach (204, 450), mitten zwischen Kennzahlen (Unterkante 211; vor der Zeile „Von außen“ und dem
  Knopf „Stadtregierung“ 162) und Kopfleiste (Oberkante 704); bei 360 × 740 von (178, 378) nach (183, 410). `zeigen()` misst die Karte schon in ihrer Endgröße. Das Einklappen allein bewegt die Kamera
  nicht. Bei reduzierter Bewegung ließ die allgemeine Regel (0,01 ms Übergang für jede Eigenschaft) die Karte beim Messen noch
  groß erscheinen, das Gebäude landete bei (295, 156) am oberen Rand; die Karte hat dort jetzt keinen Übergang.
- Neben dem Einstellungs-Knopf öffnet „?“ den Dialog „So liest du die Stadt“: Bedienung mit Maus, Touch und Tasten, die Farben
  der Figuren und die Zeichen in der Stadt (Auswahlrahmen, die beiden Ringe, Baustelle, Rauch, leere Betriebe, Licht in
  Wohnhäusern und offenen Läden, Straßennamen). Jede Aussage ist aus dem Code abgeleitet, die Muster nutzen dieselben Farben wie
  die Szene. Breit stehen Figuren und Zeichen nebeneinander (1280 × 800: 746 px hoch, ohne Scrollen), am Handy scrollt er.
  Escape oder „Schließen“, danach steht der Fokus wieder auf „?“. Die Leertaste pausiert in Dialogen nicht mehr.
- Nur bei einer neuen Stadt, nicht nach dem Laden, steht über dem Tempo leise „Ziehen dreht · Rad zoomt · Klick öffnet“ (Touch:
  „Wischen dreht · Zwei Finger zoomen · Tippen öffnet“). Die Zeile verschwindet beim ersten Drehen, Zoomen oder Verschieben,
  beim ersten Klick oder nach 12 s (im Container nach 13,4 bis 28,2 s, je nach Last: lange Bilder halten den Zeitgeber auf).
  Nichts wird gespeichert. Kontrast vor der Szene um 6, 11, 19 und 23 Uhr (1280 × 800, 400 × 820, 844 × 390) mindestens
  7,15:1, gerechnet vor reinem Weiß 6,3:1.
- Quer liegt das Tempo zwischen Spalte und den beiden Knöpfen. Bei 568 × 320 sind die Tempo-Knöpfe dafür 40 statt 44 px breit:
  je 10 px Luft. Kein seitliches Überlaufen bei 360, 400, 568, 640, 768, 844 und 1280 px Breite.
- Nach der Prüfung nachgebessert: Die Legende sagte „Licht in den Fenstern: Dort wohnen Leute“. Offene Läden leuchten aber auch
  (`stadt()`: 17 bis 22 Uhr), das steht jetzt dabei. Bei reduzierter Bewegung stehen die Ringe still; dort nennt die Hilfe nur
  ihre Farbe. Das Muster für „alle anderen“ zeigt Beige und Blassblau, die Werkstatt heißt „kräftiges Blau“. Eingeklappt ist die
  Karte 46 statt 42 px hoch: Der Fokusring der Knöpfe reichte bis 751, die Karte innen bis 749; jetzt 747 zu 749, der Knopf
  sitzt mittig. Eine neue Karte während des Einklappens bricht den Übergang ab (vorher liefen drei Animationen weiter). Breit ist
  die Karte immer aufgeklappt, auch zurück am Handy. Die Spalten der Hilfe sind bei 320 px 238 statt 260 px breit und ragen nicht
  mehr in den Rand.
- Alles davon ist HTML und CSS: Im selben Zustand zeichnen Original und neue Datei gleich viel (gemessen am Stand vor dem
  Stadtrand: Teststadt 22 Draw Calls, 41.428 Dreiecke, Startblick und Instanzzahlen gleich). JavaScript je Bild im Wechsel mit dem Original gemessen (je 3 Läufe, Last 3–4):
  1280 × 800 neu 7,7–10,2 ms, Original 8,6–9,7 ms; 400 × 820 neu 7,8–9,1 ms, Original 7,7–9,3 ms.
- Nach der Gegenprüfung: Ein Tippen auf ein Haus öffnet die Karte erst mit dem Klick danach. Vorher traf dieser Klick den Knopf
  der gerade geöffneten Karte (Pfeil, „Zeigen“, X oder einen Namen), und die Kamera konnte ohne Druck auf „Zeigen“ losfahren.
  Nach dem Schließen von Hilfe oder Einstellungen mit Maus oder Finger bleibt kein Fokus auf dem Knopf, die Leertaste pausiert
  also wieder. Die Hilfe schließt auch mit einem Tipp daneben, eingeklappt klappt ein Tipp auf den Titel die Karte auf, und
  „Zeigen“ ist dort nur noch das Symbol (mehr Platz für den Titel). Der erste Hinweis verschwindet auch bei Tasten und hält
  Straßennamen frei. Die Legende sagt jetzt, dass auch Bauhof-Leute Kisten tragen, nennt das blaue Serverlicht und dass draußen
  niemand wohnt.

In der 3D-Ansicht wächst auf jeder Baustelle ein grauer Rohbau mit den geschafften Arbeitstagen. Das Gerüst wird dunkler,
solange niemand kommt, und lässt sich anklicken. Bauarbeiter (orange) stehen an den Ecken ihrer Baustelle, Handwerker
(blau) vor der Werkstatt. An Werkstätten stehen Kistenstapel, vor Läden eine Theke und eine Auslage (braun: Kisten aus der
Stadt, grau: von außerhalb). Tech-Firmen sind Glasbauten in der Farbe ihres Produkts; tagsüber leuchten so viele Fenster wie
Leute programmieren, nachts der Serverraum. Programmierer (lila) stehen mit einem leuchtenden Bildschirm vor der Firma, wer ein
Handy hat, trägt es unterwegs in der Hand (höchstens 80 gleichzeitig, fest je Stunde vergeben). Vor einem Gebäude stehen höchstens 14 Leute
in zwei Reihen, wer mehr ist, ist drinnen. Personenkarten sagen „arbeitet als Bauarbeiterin beim
Bauhof …“ bzw. „arbeitet als Programmiererin bei Nova Handys …“, was die Person heute tut und was sie gekauft hat.

## Stadtregierung

Auf Noahs Wunsch regiert in der Stadt von Anfang an die AfD: Was in ihrem Programm zur Bundestagswahl 2025 („Zeit für
Deutschland“, afd.de, gedruckte Seitenzahlen) steht und sich auf die Stadt übertragen lässt, gilt hier. In den Zahlen oben links
steht unter dem Budget die Zeile „Von außen, gestern“ (Renten aus der Rentenkasse und Geld vom Bund, am Handy nur „Von außen“),
darunter der Knopf „Stadtregierung: AfD · seit Tag 0 ›“ (am Handy quer als Symbol neben Tag und Uhr). Er öffnet ein Fenster wie die Hilfe: jede Regel als Karte mit Status
(wirkt, galt schon, Auslegung, Modellkorrektur), wörtlichem Zitat mit Seite, Umsetzung in der Stadt und Zahlen; das Geld von
außen mit Summen je Quelle; aufklappbar, was nicht übernommen ist (die Gruppe „Grenze der Stadt“ zuerst) und was schon galt.
Im Stadtbuch steht an Tag 0 eine Zeile „Von Anfang an regiert die AfD …“ (Art „Stadtregierung“), dazu die beiden Rentenstufen und
seit Schritt 2 der erste Wohnungskauf, je Sim-Jahr eine Zeile zum Mieterkauf, jeder Kita-Bau des Bauamts und je Nacht höchstens eine
Zeile „Kein Kita-Platz frei: …“, wenn Eltern deshalb ihre Stelle aufgeben.

**Grenze.** Die Stadt kennt keine Herkunft, keine Staatsangehörigkeit, keinen Aufenthaltsstatus, keine Religion und keine
Sprache und bekommt sie nicht. Niemand, der in der Stadt lebt, wird danach behandelt, eingestuft oder entfernt; eine Funktion,
die Leute gegen ihren Willen aus der Stadt nimmt, gibt es nicht. Keine neue Regel liest Namen, den Einzugstag, die Eltern oder
das Gedächtnis „eingezogen“, also auch nicht, ob jemand hier geboren oder zugezogen ist. Migration kommt nur als Regel für den
Zuzug neuer Leute vor (in `zuzug()`, bevor jemand Bewohner ist). Gelesen werden Alter, Haushalt, Partner, Stelle, eigener
Betrieb, Geld und die Wohnungssuche, seit Schritt 2 auch Wohnung, Wohnen, Hausstufe und Beitragstage; die Kitas lesen Alter,
Haushalt, Partner, Wohnung (Entfernung zur Kita), Stelle und ihren Lohn, eigenen Betrieb, gemeinnützige Arbeit und Rente.

| Regel | Status | Quelle | In der Stadt |
|---|---|---|---|
| R01 Grundfreibetrag | wirkt | S. 58 | Die ersten 29 Taler Tageslohn je Familienmitglied sind steuerfrei, vom Rest gehen wie bisher 10 % an die Stadt (100 Taler: 7 statt 10) |
| R02 Familiensplitting | wirkt | S. 59 | Steuerhaushalt = Vorstand und Partner im selben Haushalt mit den Kindern unter 18 dort; Steuer = 10 % von (Löhne − 29 × Köpfe) (Paar, beide 100, zwei Kinder: 8 statt 20) |
| R03 Bundesleistungen zahlt der Bund | wirkt | S. 55, dazu S. 17 und S. 20 | Willkommensprämie, Betreuungsgehalt und Grundsicherung kommen von außen, nicht aus dem Budget; die Kitas (R14) zahlt die Stadt |
| Rente aus der Rentenkasse | Modellkorrektur, keine Programmforderung | (S. 17) | Renten kommen immer voll von außen. Vorher zahlte die Stadt sie aus dem Budget (Annahme 3), in Wirklichkeit zahlt keine Stadt Renten |
| R04 Rente in Stufen | wirkt | S. 17, S. 18 | Für alle Rentner gleich (ab 67 oder nach 45 Beitragsjahren, R12): 55 Taler, ab Tag 40 der Stadtregierung 60, ab Tag 80 66 (gut 70 % eines Nettolohns von 93); vorher 50 |
| R05 Willkommensprämie | wirkt | S. 20 (S. 147) | 383 Taler je Geburt vom Bund, halb an jeden Elternteil |
| R06 Betreuungsgehalt | wirkt | S. 147, S. 148, S. 20 | 93 Taler am Tag vom Bund, bis das Kind 3 ist (30 Spieltage), seit den Kitas nur, solange es keinen Kita-Platz hat, für die Person, auf die der Haushalt läuft, oder ihren Partner, wenn sie ohne Stelle ist (gemeinnützige Arbeit ist keine Stelle) |
| R07 Grundsicherung, gemeinnützige Arbeit | wirkt | S. 25 | Tagesbedarf vom Bund; nach 5 Spieltagen (6 Monaten) gemeinnützige Arbeit im Bauhof, ohne Lohn |
| R08 Keine Werkstatt der Stadt als Notbremse | Auslegung | S. 13 | Regel 5 des Bauamts entfällt |
| R09 Einheimischen-Modell | wirkt | S. 37 (S. 112) | Suchen Leute, die schon hier wohnen, eine Wohnung, bleiben so viele freie Wohnungen für sie frei |
| R10 Zuzug nur für eine freie Stelle | galt schon | S. 113 (S. 20, S. 100) | Unverändert (Annahme 11); die „heimischen Potenziale“ sind alle, die in der Stadt wohnen |
| R11 Mieter kaufen ihre Wohnung (Schritt 2) | wirkt | S. 37 (S. 36, S. 60) | Für 20 Jahresmieten (2.400/2.800/3.200 Taler), mindestens 20 % angezahlt, Rest zinslos in Raten so hoch wie die Miete; Rückkauf beim Auszug zum bezahlten Betrag, Erbe im Haushalt |
| R12 Rente ohne Abschlag nach 45 Beitragsjahren (Schritt 2) | wirkt | S. 18 | Wer mit 45 Beitragsjahren angestellt ist, kann jederzeit mit voller Rente aufhören; wer einen eigenen Betrieb hat, kann ihn nicht aufgeben und bekommt vor 67 Rente nur, wenn der Betrieb schließt; wer mit 45 Beitragsjahren die Stelle verliert, ist damit in Rente; ab 67 Rente für jeden, auch neben Arbeit oder Betrieb. Dass niemand mehr mit 67 aufhören muss, ist eine Modellkorrektur der Stadt |
| R13 Rentner-Freibetrag (Schritt 2) | wirkt | S. 20 (S. 15) | Rentner mit Lohn haben 23 Taler am Tag zusätzlich steuerfrei (12.000 €), höchstens den eigenen Lohn |
| R14 Kitas in Wohnraumnähe, Vorrang für arbeitende Eltern (Schritt 2) | wirkt | S. 20 (S. 152) | Das Bauamt baut Kitas höchstens 12 Felder von den Wohnungen wartender Kinder (sonst baut es leere Läden und Werkstätten um), die Stadt bezahlt sie. Kinder unter 6 bekommen Plätze, zuerst aus Haushalten, in denen beide Eltern bzw. der alleinerziehende Elternteil arbeiten. Ohne Platz und ohne Erwachsenen zu Hause gibt ein Elternteil die Stelle auf, wo in der Nähe eine Kita Plätze anbietet (Annahme der Stadt) |

Die Zitate stehen im Fenster. Geprüft (Stand nach der zweiten Gegenprüfung von Schritt 2): alle 128 Zitate des Fensters, also die
Zitate der Karten und Listen und die Zitate mit „…“ in ihren Texten, auch im aufklappbaren Teil der Karten (gesammelt mit
`mess/zitate_sammeln.mjs`, einer Kopie des Sammelskripts mit dem aufklappbaren Teil), mit dem Zitatprüfer gegen den Programmtext je
gedruckter Seite (alle „ok“) und genau auf der angegebenen Seite (`zitate_genau.py`, alle „genau“); die Zitate dieses Abschnitts ebenso.
Vorher stand hier, `mess/zitate_alle.py` prüfe auch die Zitate in den Texten des Fensters; es prüfte aber nur die Zitate der Karten und
Listen und 9 fest eingetragene Zitate des README. Zitierweise: Trennstriche am Zeilenende
zusammengezogen, Anführungszeichen im Zitat einfach, Auslassungen mit […]. Bei der gemeinnützigen Arbeit (S. 25) stehen der
Grundsatz und der Listenpunkt als zwei Zitate, weil dazwischen nur ein Aufzählungszeichen steht. Drei Stellen sind so gekürzt, dass der
Prüfer sie findet: Beim Betreuungsgehalt endet das Zitat vor dem letzten Wort (erhalten), das über den Seitenwechsel von S. 147 auf S. 148 getrennt ist; beim Ehe-Start-Kredit steht
der zweite Satz („Mit jedem Kind wird ein Teil des Kredits erlassen.“, S. 148), bei den Kosten der Zuwanderung die Überschrift
(„Wahre Kosten der Asylpolitik freilegen“, S. 55); im Text des PDF sind dort Trennstriche und Leerzeichen verschoben.

**Umrechnung U1 (Annahme, nicht aus dem Programm).** 1 Lebensjahr = 10 Spieltage (Annahme 2). 100 Taler Tageslohn (Werkstatt,
gemessener Durchschnittslohn 100–103) entsprechen dem mittleren Bruttojahresverdienst in Vollzeit 2024 von 52.159 € (Statistisches
Bundesamt, Pressemitteilung Nr. 134 vom April 2025,
https://www.destatis.de/DE/Presse/Pressemitteilungen/2025/04/PD25_134_621.html). Daraus: Freibetrag 15.000 € / 52.159 € × 100 =
28,8 → 29 Taler am Tag; Prämie 20.000 € / 52.159 € = 0,383 Jahreslöhne = 0,383 × 10 Spieltage × 100 Taler = 383 Taler.
Nettolohn einer Standardstelle: 100 − 7 Lohnsteuer = 93 Taler (Maß für Rente und Betreuungsgehalt).

**Geld von außen.** Rentenkasse und Bund zahlen, was in Deutschland sie und nicht eine Stadt zahlen würden, in der Höhe, die das
Programm vorsieht bzw. die die Stadt annimmt; Willkommensprämie und Betreuungsgehalt gibt es in Wirklichkeit nicht, und Renten von
gut 70 % des Nettolohns sind ein Ziel des Programms. Die Stadt bildet aber nicht ab, woher
das Geld kommt: Sie führt keine Rentenbeiträge und keine Bundessteuern ab, und die Finanzierungswege des Programms (mehr
Beitragszahler, Bundesmittel) gibt es hier nicht. Das Fenster sagt deshalb fest: „Die Verbesserungen in der Stadt beruhen zu einem
großen Teil auf Geld von außen, dessen Finanzierung die Stadt nicht abbildet (keine Rentenbeiträge, keine Bundessteuern); das
Programm selbst rechnet mit steigenden Rentenbeiträgen (S. 19).“ Beleg auf S. 19: „die anstehenden Rentenbeitragsanhebungen durch
Steuersenkungen für Beschäftigte und Unternehmen ausgleichen“. Gemessen (Seeds 1–80, 730 Tage, Mittel je Tag): Rentenkasse
8.316 Taler, Bund 775 (Prämien 272, Betreuungsgehalt 500, Grundsicherung 3); die Lohnsteuer bringt der Stadt 1.859 Taler statt
3.160 nach der alten Regel. **Die Unterschiede zu vorher (Gates, Budget, Erspartes, Zufriedenheit, Zuzug) sind kein Urteil über
das Programm:** Die Stadt zahlt die Leistungen nicht selbst, und von den einschränkenden Teilen fehlen die meisten wegen der Grenze.

**Annahmen der Stadtregierung** (alle Zahlen in `R`, Abschnitt Stadtregierung):
- Steuer, einfache Variante: Der Satz bleibt 10 %, dazu 29 Taler Freibetrag je Kopf im Familiensplitting; je Person auf ganze
  Taler gerundet und nach Lohnanteil verteilt. Die Lohnsteuer der Stadt hatte vorher gar keinen Freibetrag (in Deutschland galt 2025
  schon einer von 12.096 €, nicht aus dem Programm), die Entlastung ist hier größer als der Schritt, den das Programm vorsieht.
  In Deutschland regelt der Bund die Einkommensteuer, ihr Aufkommen teilen sich Bund, Länder und Gemeinden; in der Stadt geht die
  ganze Lohnsteuer an die Stadt, deshalb trifft sie der höhere Freibetrag voll. **Weicht vom Wortlaut der Spec ab** („Budget aus Steuern (fester Anteil vom Lohn)“): Die Steuer ist kein fester Anteil vom Lohn
  mehr. Entscheidung des Nutzers.
- Familie = Paar im selben Haushalt mit den Kindern unter 18 dort; erwachsene Kinder und andere Erwachsene zahlen allein. Wer einen
  offenen Betrieb hat, zählt nicht mit (sein Gewinn ist steuerfrei, Annahme 4); solange sein Betrieb gebaut wird und er im Bauhof
  gegen Lohn arbeitet, zählt er mit. Das Geschlecht spielt keine Rolle (Annahme 15).
- Rente: drei Stufen, 55, 60 und 66 Taler, je 40 Spieltage (eine Wahlperiode) ab dem Start, bei übernommenen Ständen ab dem
  Übernahmetag, für alle Rentner gleich (nicht je Person ab dem 67. Geburtstag). Das Programm nennt die 70 % ein „ferneres Ziel“ (S. 17) und nennt weder Höhe noch Tempo der Schritte.
- Willkommensprämie: Im Programm ist sie eine Rückzahlung von Rentenbeiträgen oder eine Gutschrift auf künftige (S. 20, S. 147).
  Die Stadt kennt keine Beiträge und zahlt deshalb immer bar aus, halb an jeden Elternteil. Die bestehende Geburtszeile im Stadtbuch nennt sie.
- Betreuungsgehalt: S. 148 („dem durchschnittlichen Nettolohn vor Geburt des ersten Kindes“) kann den eigenen früheren Nettolohn
  meinen; die Stadt nimmt den durchschnittlichen (93), weil sie keinen früheren Lohn speichert. Je Haushalt eine Person, der
  Vorstand, sonst sein Partner, 18 bis 66, ohne Stelle und ohne Betrieb. Gemeinnützige Arbeit ist keine Stelle: Wer sie leistet
  und ein Kind unter 3 im Haushalt hat, bekommt Betreuungsgehalt, und die gemeinnützige Arbeit endet in derselben Nacht (in
  übernommenen Städten gemessen nie vorgekommen, `--regierung` prüft es erzwungen). Wunsch-Bonus 20 auf „kündigen“, wenn man dafür beim Kind bleiben kann
  (Verhaltensannahme, sonst hätte die Wahlfreiheit keine Wirkung: ohne ihn im Mittel 0,6 Haushalte am Tag). Wer Betreuungsgehalt
  bekommt, zählt nicht als erwerbsfähig und nicht als arbeitslos (Quote und Zuzug) und hat nicht den Geldnot-Faktor „ohne Arbeit“.
  Großeltern (S. 148: „Eltern bzw. Großeltern“) gemessen: Auf 40 Seeds je 730 Tage (594.050 Haushaltstage mit Kleinkind) lebten
  Eltern mit Kleinkind nie im Haushalt anderer, und das Betreuungsgehalt bekam immer ein Elternteil. Möglich wäre der Fall nur,
  wenn zwei nicht verwandte Erwachsene, deren Eltern zusammengezogen sind, ein Paar werden. `betreuer()` bleibt deshalb bei Vorstand
  und Partner. Seit den Kitas (Schritt 2) gibt es das Betreuungsgehalt nur, solange das Kind unter 3 keinen Kita-Platz hat: Lesart
  der Stadt, gestützt auf „ein Erziehungsgeld, das Eltern die Eigenbetreuung ihrer Kinder in den ersten drei Lebensjahren finanziell
  erleichtert“ (S. 20). Wer seine Stelle aufgibt oder verliert: In der ersten Nacht gibt das Kind seinen Krippenplatz ab, ab der zweiten
  kommt das Betreuungsgehalt (`--kita`, Prüfung g).
- Grundsicherung: Höhe = was die Stadt als Tageskosten rechnet (Einkauf, beim Vorstand Miete und 15 je Kind); nur mit weniger als
  10 Tagesbedarfen Geld; Bedarfsgemeinschaft = Haushalt (niemand sonst dort hat Lohn, Betrieb, Rente oder Betreuungsgehalt). Wer sie
  5 Spieltage in Folge bezieht, wird zu gemeinnütziger Arbeit im Bauhof herangezogen (Annahme: volle Arbeitszeit, ohne Lohn), solange
  der Bauhof unter 40 Leuten ist. Wer das tut, zählt zu den Stellen des Bauhofs dazu (nimmt also niemandem eine Stelle), zählt als
  arbeitslos, darf nur eine richtige Stelle suchen (nicht kündigen, freinehmen oder wechseln; in `entscheide()` und
  `erlaubteAktionen()` gleich) und hört auf mit einer Stelle, dem Ende der Grundsicherung oder mit 67. Sie ist keine Stelle: Sie
  erfüllt nicht das Ziel „besserer Job“ (der Ausgangswert bleibt 0, und das Ziel „besserer Job“ wiegt wie ohne Arbeit), und wer
  daraus wegzieht, hat „Keine bezahlte Arbeit“. Wer einen eigenen Betrieb hat, auch solange er gebaut wird, bekommt keine
  Grundsicherung, und niemand in seinem Haushalt (Annahme: das Geld steckt im Betrieb; die Lohnsteuer zählt dagegen nur offene
  Betriebe, weil nur sie Gewinn bringen; betrifft auf den Seeds 4–80 etwa 8 Personentage je Stadt, gemessen in der Gegenprüfung). Vorher gab es in der Stadt
  keine Grundsicherung; Geld konnte ins Minus fallen. Das Programm setzt die Grundsicherung voraus („Für eine funktionierende
  Grundsicherung für Arbeitssuchende“, S. 25) und will das Bürgergeld „unattraktiver“ machen (S. 20); eine Höhe nennt es nicht.
- Keine Notbremse: **Weicht vom Wortlaut der Spec ab** (Bauamt, Regel 5: 14 Tage keine Gründung und über 20 % ohne Arbeit → Werkstatt
  der Stadt). Entscheidung des Nutzers, Auslegung von S. 13; ein Minimum ist nicht null. Den Laden der Stadt vom Start gibt es
  weiter (offene Frage). Auf den Seeds 1–160 hat die Notbremse auch vorher nie ausgelöst (gemessen, 0 Werkstätten).
- Einheimisch = wohnt heute in der Stadt: Vorbehalten werden so viele freie Wohnungen, wie Erwachsene in der Stadt keine Wohnung
  haben oder erfolglos suchen (`wohnungSuchende`), keine Wohndauer. An anderen Stellen stellt das Programm „einheimisch“ und
  „ausländisch“ gegenüber (S. 112); die Lesart der Stadt ist bewusst enger.
- Zuzug (R10): Das Programm meint Einwanderung nach Deutschland, vor allem von außerhalb Europas (S. 113: „Geeignete
  außereuropäische Arbeitskräfte werden wir danach bedarfsgerecht nach strikten Kriterien auswählen.“); die Freizügigkeit in der
  EU soll unberührt bleiben (S. 100: „Die Freizügigkeitsregelungen innerhalb der EU bleiben davon unberührt.“). Wer in die Stadt
  zieht, kann auch aus dem Nachbarort kommen. Die Stadt wendet die Regel auf jeden Zuzug an: für Umzüge im Inland strenger als
  das Programm, für Einwanderung von außerhalb Europas lockerer (kein Punktesystem, keine Sprachprüfung). Keine Altersgrenze (das Programm nennt keine), die Grenze von 1 + 1 % der Einwohner
  am Tag bleibt (S. 109 nennt keine Zahl).
- Nicht übernommen, unter anderem: Junior-Spardepot (nur für Kinder mit deutscher Staatsangehörigkeit, S. 19), alles zu
  Abschiebung, Status, Sprache und Religion, Arbeitslosengeld, Wohngeld, Ehe-Start-Kredit. Mieterkauf (S. 37), flexibler
  Renteneintritt (S. 18) und Kitas (S. 20) kamen im zweiten Schritt dazu (unten). Die Liste mit Gründen steht im Fenster.
- Hauptfiguren: Die Anweisung ans Sprachmodell nennt nur Tatsachen der Figur („Du bleibst beim Kind zu Hause und bekommst
  Betreuungsgehalt …“, „Du bekommst Grundsicherung …“, bei „kündigen“ das Betreuungsgehalt, seit den Kitas „Für dein Kind … ist in
  der Nähe kein Kita-Platz frei; bis dahin bleibst du zu Hause.“), nie die Stadtregierung.
- „Gestern“ im Fenster und in der Zeile „Von außen“ führt die Simulation selbst: Am Ende jedes Tagesabschlusses ist
  `S.regierung.gestern` = Summen in `S.stat.regierung` minus die Summen am Ende des Vortags (`S.regierung.tagStart`). Beides wird
  gespeichert, die Zeile hat also gleich nach Laden, Import oder Aufholen ihre Zahl. Nur in einer neuen Stadt und nach einer
  Übernahme steht bis zur ersten Nacht „–“ (im Fenster „ab morgen“); der erste Tag einer übernommenen Stadt zählt ab dem
  Übernahmezeitpunkt. Vorher rechnete die Oberfläche die Werte nur im Speicher aus, nach jedem Laden fehlten sie bis zu 35
  Spielstunden. Das Fenster ändert den Zustand nie.

**Gemessen** (je 730 Tage stündlich, Gates wie `--gate` ohne T; `vorher` = Stand vor der Stadtregierung):

| Seeds | Stand | alle Gates | Gate 4 | Band Ø / Median / höchstens | Gate 7: kleinster Abstand | Einwohner Tag 365 Ø (kleinster) |
|---|---|---|---|---|---|---|
| 1–80 | vorher | 76 von 80 | 76 (fällt: 19, 27, 37, 65) | 1,076 / 1,068 / 1,209 | 15,4 | 840 (526, Seed 65) |
| 1–80 | Stadtregierung | 77 von 80 | 77 (fällt: 19, 27, 44) | 1,077 / 1,069 / 1,201 | 15,7 | 875 (562, Seed 62) |
| 81–160 | vorher | 79 von 80 | 79 (fällt: 87) | 1,074 / 1,065 / 1,154 | 15,9 | 852 (711) |
| 81–160 | Stadtregierung | 75 von 80 | 76 (fällt: 92, 103, 118, 134) | 1,076 / 1,067 / 1,187 | 10,0 (Seed 81 fällt) | 874 (762) |

Weitere Werte (Seeds 1–80, Mittel, vorher in Klammern): Einwohner an Tag 730 1.068 (1.045), Geburten 519 (489), Zuzüge 1.000
(985), Wegzüge 41 (42), ohne Arbeit an Tag 730 5,1 % (3,8 %), Budget an Tag 730 5,75 Mio. (2,15 Mio.), Erspartes je Erwachsenem
11.902 (10.525), Zufriedenheit 70,3 (68,8). An im Mittel 51 von 730 Tagen bleiben Wohnungen für Leute aus der Stadt frei,
zusammen 62 Wohnungstage. Grundsicherung bezogen im Mittel 0,07 Leute am Tag, höchstens 12 zugleich; gemeinnützige Arbeit kam auf
den Seeds 1–160 nie vor (in übernommenen Städten der Version 2 schon, siehe `--migrationstest`), deshalb der erzwungene Test
`--regierung`. Seed 65, vorher der langsamste (526 Einwohner an Tag 365, Gate 4 Band 1,154), hat mit der Stadtregierung 768 und
besteht Gate 4 (1,053). Gate 4 bleibt im Rauschen der Zuzug-Regel (Placebo 77 von 80, siehe „Bekannte Schwächen“), einzelne
Seeds kippen in beide Richtungen. Gate 7 bleibt das knappste Gate: Auf Seed 81 ziehen bis Tag 365 11 Leute weg, mit nur 10 Punkten
weniger Heimatliebe als alle (vorher 21,6, im Prototyp 25,4).

`--gate` (Seeds 1, 2, 3, je 730 Tage) besteht wie vorher; in Klammern der Stand vor der Stadtregierung:

| Gate | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| 1 Einwohner an Tag 365 | 861 (864) | 902 (882) | 919 (899) |
| 2 schlimmster 30-Tage-Einbruch | 2,9 % (3,4 %) | 4,7 % (6,7 %) | 3,6 % (4,0 %) |
| 3 kleinstes Budget | 6.731 (6.751) | 6.743 (6.763) | 6.538 (6.557) |
| 4 Band Tag 551–730, Abstand zur Baugrenze | 1,05, 28 (1,09, 28) | 1,04, 24 (1,10, 28) | 1,07, 28 (1,09, 24) |
| 5 Gründungen bis Tag 365 | 194 (189) | 193 (167) | 201 (223) |
| 6 Gründer-Ehrgeiz | +18,0 (+19,3) | +17,7 (+20,6) | +22,4 (+18,7) |
| 7 Wegzieher-Heimatliebe | −29,1, n = 17 (−25,8, n = 15) | −17,1, n = 11 (−18,5, n = 12) | −33,0, n = 13 (−27,6, n = 19) |
| T 365 Tage | 1,4 s (1,3 s) | 1,6 s (1,1 s) | 1,5 s (1,2 s) |
| B Stadtbuch, Zeilen am Tag (davon Bauhof) | 4,12 (0,23) | 4,38 (0,25) | 4,26 (0,24) |
| Lohnsteuer am Tag, Tag 700–730 (nach der alten Regel) | 2.364 (4.303) | 2.602 (4.591) | 2.574 (4.559) |
| von außen am Tag, Tag 700–730: Rentenkasse, Bund | 17.382, 1.089 | 17.186, 904 | 18.069, 1.411 |

Vorher B: 4,13 (0,25), 4,12 (0,24), 4,28 (0,25). T schwankt mit der Last der Maschine.

Speicherformat 5: `--speichertest` (Seed 1, gespeichert an Tag 150 um 13 Uhr, 60 Tage weiter 265 Einwohner) läuft bitgleich
weiter, Fingerabdruck `c549d3c8fbb35f2e` (vorher `0c277c92552696a9`, die Stadt läuft seit der Stadtregierung anders; seit der
Gegenprüfung zählen `S.regierung` mit „gestern“ und die Summen am Tagesende zum Fingerabdruck, ohne sie wäre er weiter
`21afa786ba10a5df`: Der Verlauf ist gleich geblieben, alle 160 Seeds der Messtabelle liefern dieselben Werte). Die
Browser-Tests mit festen Momenten der Teststadt (Seed 2) sind an den neuen Verlauf angepasst: `tests/ereignis.cjs` (Pleiten an
Tag 499, Übernahmen an Tag 609, Aufholen bis Tag 682, Fernblick an Tag 703) und `tests/p8tech.cjs` (öffnet die erste Person der
Liste, die heute programmiert; die zweite hatte frei).

Fenster, geprüft im Browser (1280 × 800, 400 × 820, 844 × 390, 568 × 320, Tastatur, reduzierte Bewegung): Kontrast aller Texte
mindestens 5,81:1 (leiser Text im Hinweis), am Handy füllt es das Bild, der Kopf mit dem X bleibt beim Scrollen oben. Ein Klick
schließt das Fenster nur, wenn er auf den abgedunkelten Rand geht: Enter auf einer aufklappbaren Liste löst einen Klick bei 0,0 aus
und schloss das Fenster sonst mit (gilt genauso für die Hilfe).

Befunde der Gegenprüfung, behoben und nachgemessen:
- Gemeinnützige Arbeit erfüllte das Ziel „besserer Job“ (Lebenslauf, Anweisung ans Sprachmodell, Statistik). In übernommenen
  Städten der Version 2 (39c405b, 60 Tage) vorher bei 41 von 61 (Seed 2) und 22 von 39 (Seed 3) Herangezogenen, jetzt bei 0 von 56
  und 0 von 26. Ohne gemeinnützige Arbeit (alle neuen Städte) ändert sich nichts.
- „Von außen“ nach dem Laden sofort da (Browser: Stand gespeichert, neu geladen, gleiche Zahl), nach einer Übernahme ab der ersten
  Nacht.
- Nach dem Schließen per Finger oder Maus (X, „Schließen“, daneben) und sofort Leertaste: pausiert, das Fenster bleibt zu, in 33
  von 33 Fällen (360 × 740, 768 × 1024 Finger, 1280 × 800 Maus; Leertaste nach 0, 40 und 300 ms; Stadtregierung und Hilfe). Nach
  Escape oder „Schließen“ per Tastatur steht der Fokus mit Ring auf dem Knopf (2 von 2). Die Fassung vor der Korrektur fiel in
  derselben Prüfung bei 25 der 35 Fälle durch.
- Meldung nach „Stadt übernehmen“: 360 × 740 jetzt 328 × 120 px (vorher 180 × 270), der Knopf „Stadtregierung“ darunter lässt
  sich antippen; 1280 × 800 560 px breit, mittig.

### Schritt 2: Mieterkauf, flexibler Renteneintritt, Rentner-Freibetrag

Auf Noahs Wunsch der zweite Schritt: Mieter kaufen ihre Wohnung (S. 36–38), Rente ohne Abschlag nach 45 Beitragsjahren und ein
Rentner-Freibetrag (S. 18, S. 20). Grundlage sind die Entwürfe mit Prototyp und Messung und ihre Gegenprüfungen (Scratchpad,
`afd/schritt2_entwuerfe.json`); die Prototypen bauten auf einem älteren Kern-Prototyp auf, eingebaut ist ihre Logik auf dem
fertigen Kern. Alle Befunde der Gegenprüfungen sind umgesetzt (Liste am Ende). Die Kitas kamen danach dazu (Abschnitt „Kitas in
Wohnraumnähe“ am Ende); Messungen, Fingerabdruck und Tests bis dorthin beschreiben den Stand ohne Kitas. Wie im Kern liest keine neue
Regel Namen, Herkunft, Einzugstag oder Eltern: Der Kauf liest Leben, Haushalt, Partner, Wohnung, Geld, Wohnen, Hausstufe, Eigentum
und über die Tageskosten Sparsamkeit und Kinderzahl im Haushalt; die Weitergabe liest wie bisher Partner und Alter; die Rente liest
Alter, Arbeitsplatz, eigenen Betrieb, gemeinnützige Arbeit, Betreuungsgehalt und Beitragstage. Leistungen, die der Bund veranlasst, kommen weiter sichtbar
von außen (auch die neuen Renten); Kaufpreise und Raten gehen ins Budget der Stadt.

**R11 Mieter kaufen ihre Wohnung (S. 37).** Im Fenster: „Zur Förderung der Eigentumsbildung werden wir einen Rahmen schaffen, in dem
Mieter ihre Wohnungen von öffentlichen Wohnungsbauunternehmen zu vergünstigten Bedingungen erwerben können.“ und „Mieter sollen beim
Kauf von selbstgenutztem Wohneigentum z. B. durch Eigenkapitalersatz unterstützt werden.“ (beide S. 37).
- Die Stadt besitzt alle Wohnhäuser (Annahme 4). Eigentum hat ein Haushalt; gespeichert am Vorstand (`eigen` = Gebäude + 1,
  `kaufPreis`, `schuld`), der in diesem Haus wohnt.
- Jede Nacht nach allen Zahlungen (Ende von `wirtschaft`) kauft, wer kann: Vorstand und Partner im selben Haushalt legen zusammen, was
  jedem über 40 Tageskosten bleibt, zuerst das Geld des Vorstands. Mindestens 20 % des Preises, höchstens der ganze Preis gehen als
  Anzahlung ins Budget; den Rest stundet die Stadt ohne Zinsen, die Rate ist die Miete beim Kauf, abbezahlt zahlt der Haushalt nichts
  mehr. Wer umziehen will (Wohnen unter 40) oder in einem Haus im Bau wohnt, kauft nicht. Fester Ablauf nach Personen-ID, kein Zufall.
- Rückkauf zum bezahlten Betrag (Kaufpreis minus Rest, der Rest entfällt): wenn der Haushalt umzieht, wenn er beim Zusammenziehen
  aufgelöst wird und wenn er sich auflöst (Tod oder Wegzug, niemand Erwachsenes bleibt; das Geld geht mit dem Weggehenden bzw. an die
  Erben außerhalb). Wer den Haushalt übernimmt (Partner, sonst ältestes erwachsenes Mitglied, die bestehende Regel `mieterWechsel`),
  übernimmt die Wohnung samt Rest und Rate, ohne Steuer. Haben beim Zusammenziehen beide einen Haushalt und gehört nur einem die
  Wohnung, zieht das Paar dorthin; gehört beiden eine, behält der Haushalt die des Handelnden, die andere kauft die Stadt zurück.
- Tageskosten, Grundsicherung, Geldbedürfnis und die Kündigungsgrenze rechnen mit der Rate bzw. 0 statt der Miete. Aufstockungen gehen
  weiter; Preis und Rate gekaufter Wohnungen bleiben, Mieter zahlen nach einer Aufstockung mehr.
- Stadtbuch (Art „Stadtregierung“): der erste Kauf einer Stadt mit Namen („Als erster Haushalt kauft …“, bei mehreren „Als erste
  Haushalte kaufen …“), danach je Sim-Jahr eine Zeile („Im letzten Jahr haben 28 Haushalte ihre Wohnung von der Stadt gekauft, 3 Wohnungen
  hat die Stadt zurückgekauft. Jetzt wohnen …“), in übernommenen Städten „In der ersten Nacht nach der Übernahme kaufen …“. Keine Zeile
  je Kauf, sonst wäre fast jeden Tag eine.
- Karten: Hauskarte „26 von 26 Wohnungen belegt, 21 davon gehören ihren Bewohnern. Kaufpreis je Wohnung 3.200 Taler“, in der Liste
  „· Eigentum“; Personenkarte „wohnt in der eigenen Wohnung … (gekauft für 3.200 Taler, noch 240 abzuzahlen)“ bzw. „wohnt zur Miete
  …“; Hauptfiguren bekommen als Tatsache „Die Wohnung gehört dir (euch), du zahlst (ihr zahlt) sie in Raten ab“ bzw. „… ist abbezahlt“.
  Keine neue KI-Aktion, kein neues Gebäude, kein Draw Call.

| Annahme (Werte in `R`, `EIGEN_*`) | Wert | Warum |
|---|---|---|
| Wert einer Wohnung | 25 Jahresmieten (1 Jahr = 10 Spieltage) | Das Programm nennt keinen Preis. Immobilienportale nennen für Eigentumswohnungen einen Kaufpreis von etwa 20 bis 30 Jahresmieten (per Websuche im Entwurf, keine amtliche Statistik); 25 ist die Mitte |
| Vergünstigung | 20 %: Preis 20 Jahresmieten = 200 Tagesmieten, also 2.400 / 2.800 / 3.200 Taler je Hausstufe | „vergünstigt“ ohne Zahl, mittlerer Wert (Noahs Entscheidung). Im Prototyp änderte der Nachlass die Eigentümerquote kaum, vor allem Restschuld und Budget |
| Mindestanzahlung | 20 % des Preises aus Erspartem | Noahs Entscheidung. Das Programm nennt als Beispiel Eigenkapitalersatz, also Hilfe beim Eigenanteil; die Stadt ist hier strenger als die Richtung des Programms. Das ist eine Annahme der Stadt, kein Programminhalt. Grund: Ohne Anzahlung kauft jeder Haushalt sofort, und beim Zusammenziehen kauft die Stadt dauernd zurück (Prototyp: 98 % Eigentümer nach 180 Tagen, 2,7-mal so viele Rückkäufe) |
| Stundung | Rest zinslos, Rate = Miete beim Kauf | Banken gibt es in der Stadt nicht, die Stadt übernimmt die Rolle der Bank; Zinsen gibt es in der Stadt nirgends. Die täglichen Kosten ändern sich bis zur Tilgung nicht |
| Rücklage | Käufer und Partner behalten je 40 Tageskosten (`EIGEN_RESERVE`) | Bei 40 Tageskosten ist das Geldbedürfnis voll (Geld / Tageskosten × 2,5), ein Kauf macht niemanden unzufrieden. Eigener Name: Der Prototyp hieß `KAUF_RESERVE` und senkte damit nebenbei die Reserve beim Gerätekauf von 600 auf 40 Taler (Blocker der Gegenprüfung); `--regierung` prüft, dass sie 600 bleibt |
| Kaufentscheidung | automatisch, sobald leistbar, außer wer umziehen will | Noahs Entscheidung, keine neue KI-Aktion. Eigentum kostet in der Stadt nur den Kaufpreis |
| Rückkauf | zum bezahlten Betrag | Annahme des Modells (keine privaten Käufer, keine private Vermietung, keine Preissteigerung), keine Aussage des Programms: S. 37 beschränkt die Förderung auf selbstgenutztes Eigentum, sagt aber nichts zum Auszug |
| Weitergabe | an den, der den Haushalt übernimmt, ohne Steuer | Die Regel, die schon für Mietwohnungen gilt; ohne Steuer, weil S. 60 die Erbschaftsteuer abschaffen will. Erwachsene Kinder mit eigener Wohnung erben nicht: Geld wird in der Stadt auch sonst nicht vererbt, eine Erbfolge außerhalb des Haushalts wäre eine eigene Regel (Verwandtschaft ist keine Herkunft, die Grenze verlangt das nicht) |
| Trennung | die Wohnung bleibt, auf wen der Haushalt läuft; der andere bekommt seinen Anteil nicht zurück | Vereinfachung, Trennungen sind selten |
| Grundsicherung | zahlt als Tagesbedarf auch die Rate | Folgt aus den Tageskosten; im echten SGB II wird Tilgung meist nicht übernommen. Die eigene Wohnung zählt nicht als Vermögen |
| Aufstockung | ohne Zustimmung der Eigentümer | Die Stadt bleibt Eigentümerin des Hauses; das Programm sagt dazu nichts |

Wirkung, gemessen (Seeds 1–160, 730 Tage stündlich, `mess/mess2.mjs`): Eigentümer-Haushalte im Mittel 56 % an Tag 180, 83 % an Tag
365, 89,5 % an Tag 730 (je Stadt 81–93 %); abbezahlt sind an Tag 730 64 % aller Haushalte. Von den Haushalten ab 67 besitzen 98 % ihre
Wohnung, 91 % schuldenfrei. Je Stadt 712 Käufe (0,4 ganz bar), Anzahlung im Mittel 684 Taler, 241 Rückkäufe (232 bei Auflösung, 9 beim
Zusammenziehen, fast nie beim Umzug, weil Eigentümer kaum unter Wohnen 40 kommen), 89 Erbfälle; der Rückkauf war nie durch das Budget begrenzt. An
Tag 700–730 je Tag: 887 Taler Miete, 2.193 Taler Raten, 5.345 Taler Miete zahlen abbezahlte Eigentümer nicht mehr. Budget an Tag 730
3,76 statt 5,75 Mio. Taler. Zur Miete wohnen danach fast nur Haushalte mit Stelle (93 %), die noch nicht genug angespart haben. Ein
Wohngeld (S. 37) nach der Regel des Kern-Prototyps (Einkommen über 0, aber unter dem Tagesbedarf, keine Grundsicherung) hätte im
Mittel 0,1 Haushaltstage je Stadt in 730 Tagen gehabt (höchstens 3, nur gezählt): kein Fall, deshalb weiter „nicht übernommen“.
Die Quote liegt über den „Siebzig Prozent aller EU-Bürger“, die das Programm als Vergleich nennt (S. 36, kein Ziel). Das folgt aus der
Mechanik der Stadt (keine Zinsen, keine Nebenkosten, kein Wertverlust, Rückkauf zum bezahlten Betrag); das Fenster sagt das.

**R12 Rente ohne Abschlag nach 45 Beitragsjahren (S. 18) und R13 Rentner-Freibetrag (S. 20).** Im Fenster: „Wir wollen der
Rentenversicherung mehr Beitragszahler zuführen, die Verrentung flexibler und gerechter gestalten und Anreize für eine freiwillige
Verlängerung der Lebensarbeitszeit setzen“ und „ein flexibles Renteneintrittsalter, abschlagsfrei nach 45 beitragsberechtigten
Arbeitsjahren, ermöglichen“ (beide S. 18); „Schaffung von Arbeitsanreizen für Rentner durch einen zusätzlichen Steuergrundfreibetrag in
Höhe von 12.000 €“ (S. 20) und „die Bereitstellung eines zusätzlichen Steuerfreibetrags für Rentner, um Senioren im Arbeitsmarkt zu
halten“ (S. 15).
- Neues Personenfeld `beitrag` (Beitragstage, 10 = 1 Beitragsjahr): jede Nacht +1 für jeden mit Arbeitsplatz (angestellt, auch an
  freien Tagen, oder im eigenen, offenen Betrieb) und für wer Betreuungsgehalt bekommt; nicht für gemeinnützige Arbeit, Grundsicherung
  oder ohne Arbeit.
- Anspruch: ab 67 oder mit 45 Beitragsjahren. Rente bekommt ab 67 jeder, auch mit Stelle oder eigenem Betrieb; vor 67, wer mit Anspruch
  keinen Arbeitsplatz und keinen Betrieb mehr hat. Höhe nach R04, ohne Abschlag, von außen aus der Rentenkasse.
- Kündigen mit Anspruch heißt in Rente gehen: auch ohne Erspartes erlaubt, dazu der Ruhestandswunsch; im Lebenslauf „in Rente gegangen
  (vorher …)“. Wer einen eigenen Betrieb hat, kann nicht kündigen, und eine Aktion zum Aufgeben des Betriebs gibt es nicht: Vor 67 bekommt
  er Rente nur, wenn der Betrieb schließt (etwa 12 % der 63- bis 66-Jährigen haben einen Betrieb). Wer mit 45 Beitragsjahren die Stelle
  verliert (der Betrieb schließt, selten ein Elternteil ohne Kita-Platz), ist damit in Rente und sucht keine neue; das Fenster sagt beides. Wer vor 67 in Rente ist, sucht keine Stelle mehr, bekommt kein Betreuungsgehalt, zählt nicht als arbeitslos und hat
  nicht den Geldnot-Faktor „ohne Arbeit“, wie bisher ab 67. Die Anstellung endet nicht mehr mit 67.
- Lohnsteuer: Je Rentner mit Lohn kommen im Steuerhaushalt höchstens 23 Taler, höchstens sein Lohn, zum Freibetrag dazu (allein, 100
  Taler Lohn: 5 statt 7 Taler Steuer).
- Karten: Personenkarte „Rente: 66 Taler am Tag (46 Beitragsjahre)“ bzw. „Beitragsjahre: 22 von 45“, ab dem Anspruch „Beitragsjahre: 46
  (45 nötig) · darf ohne Abschlag in Rente“, bei Besitzern „… · Rente ab 67 oder wenn der Betrieb schließt“ (vorher „46 von 45“), Kopf
  „66 Jahre · in Rente“ auch vor 67. Hauptfiguren: Satz zu „kündigen“ mit Anspruch („Du gehst in Rente: Du hast 45 Beitragsjahre und
  bekommst die volle Rente ohne Abschlag …“) und „Du bekommst schon Rente“ bei Arbeit ab 67; die Regierung wird nicht erwähnt.
- Stadtbuch: Die Zeile von Tag 0 sagt „Mieter können ihre Wohnung kaufen, nach 45 Beitragsjahren kann man ohne Abschlag in Rente gehen,
  und die Stadt baut Kitas mit Vorrang für arbeitende Eltern.“ (ein Angebot, keine Automatik; seit der zweiten Gegenprüfung kürzer, die
  ganze Zeile hat 920 statt 1.114 Zeichen, im Kern 763). Keine Zeile je Renteneintritt (rund 0,8 am Tag).

| Annahme (Werte in `R`) | Wert | Warum |
|---|---|---|
| Kein Zwangsende mit 67 | fällt weg | Annahme der Stadt, keine Aussage des Programms (Noahs Entscheidung): Die feste Grenze war Annahme 3 der Stadt; sie fällt, weil das Programm freiwillig längeres Arbeiten will (S. 18) und Rentner im Arbeitsmarkt halten will (S. 15, S. 20). Modellkorrektur |
| Beitragstag | Tag mit Arbeitsplatz, auch im eigenen Betrieb; Tag mit Betreuungsgehalt | Die Stadt kennt keine Beiträge. Das Programm spricht von „beitragsberechtigten Arbeitsjahren“ und sagt nicht, ob Selbstständige oder Erziehungszeiten mitzählen; beides zählt als Annahme (Noahs Entscheidung). Zur Elternschaft sagt es nur „die Elternschaft bei der Rente höher vergüten.“ (S. 19). Freie Tage beenden die Anstellung nicht und zählen mit |
| Beitragsjahre von außen | `round(0,95 × Tage seit dem 18. Geburtstag)` (`BEITRAG_START`) | Startbevölkerung, Zuzug, übernommene Stände: Die Vorgeschichte ist unbekannt, für alle gilt dieselbe Regel nach dem Alter. So viel sammelt im Mittel, wer hier lebt (Neutralitätsmessung unten) |
| Rentenhöhe | voll nach R04, kein Abschlag, kein Zuschlag | „abschlagsfrei“ (S. 18). Abschläge ohne 45 Jahre oder Zuschläge für späteres Aufhören nennt das Programm nicht; vor 67 ohne 45 Beitragsjahre gibt es keinen Renteneintritt |
| Rente ab 67 auch mit offenem Betrieb | ja | Noahs Entscheidung: eine Regel für alle (kostet die Rentenkasse im Prototyp etwa 1.250 Taler am Tag) |
| Besitzer vor 67 | kein Renteneintritt, solange der Betrieb offen ist; Rente, wenn er schließt | Einen Betrieb aufgeben kann man in der Stadt nicht, dafür bräuchte es eine neue Aktion. Fenster, Tag-0-Zeile und Personenkarte sagten vorher, jeder mit 45 Beitragsjahren könne aufhören (Befund der zweiten Gegenprüfung); jetzt steht die Einschränkung dort |
| Stelle verloren mit 45 Beitragsjahren | in Rente, keine neue Stellensuche | Wie bisher ab 67: Mit Anspruch und ohne Arbeitsplatz bekommt man Rente. Betrifft vor allem Schließungen (22 je Stadt), selten einen Elternteil ohne Kita-Platz; im Fenster als Annahme genannt |
| Frühe Rente heißt aufhören | ja | Nach geltendem Recht darf man neben einer vorgezogenen Rente hinzuverdienen (Deutsche Rentenversicherung, per Websuche im Entwurf); die Stadt bildet das nicht ab, sonst bekäme fast jeder ab etwa 65 Rente und Lohn zugleich |
| Kein Wiedereinstieg, kein Betreuungsgehalt in Rente | wie bisher ab 67 | S. 148 nennt beim Betreuungsgehalt auch Großeltern; in der Stadt bekommen es die Eltern (Kern) |
| Ruhestandswunsch | 10 Punkte auf „kündigen“ je angefangenem Jahr seit dem Anspruch (`RUHE_WUNSCH`) | Gesetzt, nicht kalibriert (Begründung korrigiert, unten). Ohne ihn arbeiteten Leute mit Anspruch bis zum Tod, weil „kündigen“ nicht am Alter hängt |
| Rentner-Freibetrag | 23 Taler am Tag (12.000 € / 52.159 € × 100 = 23,0, U1), höchstens der eigene Lohn | S. 20. Die Rente ist in der Stadt steuerfrei, deshalb nur auf Lohn; ohne Deckel entlastete er beim Familiensplitting den Lohn des Partners eines Rentners ohne Arbeit. Eine Anreizwirkung bildet die Stadt nicht ab: Wann jemand aufhört, hängt am Charakter, nicht am Nettolohn (wie bei R01) |

Ruhestandswunsch, Begründung korrigiert: Der Entwurf verglich die Stadt bei 67–69 Jahren mit 23 % Erwerbstätigen bei 65–69 Jahren
(Destatis: „Im Jahr 2025 lag der Anteil bei 23 %“). Das waren verschiedene Altersgruppen, denn 65- und 66-Jährige haben die
Regelaltersgrenze noch nicht erreicht. Für die einzelnen Jahre nennt der DIW-Wochenbericht 48/2025 (Mikrozensus 2022) 16,4 % bei 67,
15,1 % bei 68 und 12,1 % bei 69 Jahren; viele davon arbeiten wenige Stunden (ab 66 sind 3,0 % der Altersgruppe geringfügig beschäftigt,
im Mittel 8,9 Stunden in der Woche), und 37,4 % der Erwerbstätigen ab 66 sind selbstständig (beides per Websuche nachgelesen,
diw.de). Die Stadt kennt nur volle Stellen. An Tag 730 sind bei 67–69 Jahren 11,4 % angestellt und 12,0 % haben einen eigenen
Betrieb, zusammen 23,4 % (Seeds 1–80); Besitzer können nicht aufhören, weil es keine Aktion „Betrieb aufgeben“ gibt. Die Angestellten
liegen damit in derselben Größenordnung wie die abhängig Beschäftigten dieser Jahre in Deutschland, mit den Besitzern liegt die Stadt
darüber. 10 bleibt ein gesetzter Wert. Im Prototyp (ohne Mieterkauf) ergab 20 nur 4,8 % Angestellte bei 67–69, 5 dagegen 41,8 % und
öfter fallende Gates.

Wirkung, gemessen (Seeds 1–160): je Stadt 610 Renteneintritte durch Kündigung, davon 400 vor 67 (im Mittel mit 66,0 Jahren), dazu 22 vor
67, weil der Betrieb schloss. An Tag 730 (Seeds 1–80) sind bei 63–66 Jahren 64,5 % angestellt, 11,9 % Besitzer und 19,6 % in Rente, bei
67–69 11,4 % angestellt, 12,0 % Besitzer, 76,6 % in Rente. Weil man in der Stadt ab 18 fast ohne Lücke arbeitet, hat fast jeder mit gut 65
Jahren seine 45 Beitragsjahre. Die Rentenkasse zahlt im Mittel 9.760 statt 8.316 Taler am Tag (+17 %, Seeds 1–80). Der Freibetrag
betrifft im Mittel 1,8 Rentner mit Lohn am Tag und spart der ganzen Stadt 4,0 Taler Steuer am Tag: Er ändert fast nichts.

Neutralität der Beitragsjahre (nur im Messskript `mess/neutral.mjs` getrennt, die Stadt kennt die Trennung nicht): Beitragsdichte
(Beitragstage je Tag seit 18) von Leuten mit Eltern in der Stadt 0,956–0,984, von Zugezogenen 0,945–0,969 (Seeds 1–8, Altersgruppen
23–59 mit mindestens 10 Leuten). Über 1.100 Tage gingen von den Austritten ab 60 bei hier Geborenen 50,7 % vor 67 (1.792 Austritte,
mittleres Alter 65,84), bei Zugezogenen 53,7 % (8.181, mittleres Alter 66,13). Keine Gruppe ist durchweg im Vorteil: Zugezogene gehen
etwas öfter vor 67, hier Geborene im Mittel etwas früher. 0,95 bleibt; im Prototyp ohne Mieterkauf waren es 55,4 % gegen 53,5 %.

**Speicherformat 6.** Neu je Person `eigen`, `kaufPreis`, `schuld`, `beitrag` (8 Bytes), in `S.regierung` der Tag `schritt2`, ab dem
Schritt 2 gilt, in `S.stat.regierung` die Summen von Mieterkauf und Rente. Ein Stand der Version 6 muss alles haben: fehlt ein neues
Personenfeld, heißt es „Spielstand unvollständig“; die Prüfung der Stadtregierung verlangt `schritt2` als ganzen Tag zwischen Start
und heute und alle Summen als Zahlen; Wohneigentum muss einem lebenden Vorstand gehören, der in dieser Wohnung eines Wohnhauses wohnt,
mit Rest höchstens gleich dem Kaufpreis („Spielstand beschädigt: Wohneigentum“). Ein Stand der Version 5 löst den Versionsdialog aus
(„Dein Spielstand ist von Version 5. Seit Version 6 können Mieter …“); „Stadt übernehmen“ behält alles, auch Start, Summen und
„gestern“ der Stadtregierung, und setzt Schritt 2 ab dem Übernahmetag: niemand besitzt schon eine Wohnung, Beitragsjahre für alle aus
dem Alter (dieselbe Regel wie beim Zuzug), eine Zeile im Stadtbuch („Ab heute können Mieter ihre Wohnung …“). Versionen 2 bis 4 laufen
über dieselbe Kette (2 → 3 → 4 → 5 → 6); dort gilt Schritt 2 wie die ganze Stadtregierung ab dem Übernahmetag. In der ersten Nacht nach
der Übernahme kauft, wer kann: gemessen 32 von 151 (Seed 1, Tag 155), 272 von 441 (Seed 2, Tag 300), 414 von 498 Haushalten (Seed 3,
Tag 403). Ein Stand der Version 6 in einer älteren Datei der Version 5 zeigt dort den Versionsdialog („Neu anfangen“ oder „Export
behalten“) statt abzustürzen (Befund der Gegenprüfung). `--speichertest` läuft bitgleich; Fingerabdruck `c0b355a809870ef1` (Seed 1, Tag 210,
13 Uhr, 170 Einwohner; im Kern `c549d3c8fbb35f2e`, er hängt auch am Wortlaut der Stadtbuch-Zeilen und ist kein Sollwert). Spielstand bei
Seed 1, Tag 150: 0,20 MB.

**Gemessen** (je 730 Tage stündlich, Gates wie `--gate` ohne T, `mess/mess2.mjs`; Kern = Stand vor Schritt 2):

| Seeds | Stand | alle Gates | Gate 4 | Band Ø / Median / höchstens | Gate 7: kleinster Abstand, fällt | Einwohner Tag 365 Ø (kleinster) |
|---|---|---|---|---|---|---|
| 1–80 | Kern | 77 von 80 | 77 (fällt: 19, 27, 44) | 1,077 / 1,069 / 1,201 | 15,7, nie | 875 (562) |
| 1–80 | Schritt 2 | 76 von 80 | 78 (fällt: 12, 59) | 1,074 / 1,065 / 1,192 | 12,9; fällt: 30, 49 | 862 (693) |
| 81–160 | Kern | 75 von 80 | 76 (fällt: 92, 103, 118, 134) | 1,076 / 1,067 / 1,187 | 10,0; fällt: 81 | 874 (762) |
| 81–160 | Schritt 2 | 74 von 80 | 76 (fällt: 87, 120, 141, 145) | 1,074 / 1,068 / 1,212 | 11,4; fällt: 97, 130 | 876 (691) |

Weitere Werte (Seeds 1–80, Mittel, Kern in Klammern): Einwohner an Tag 730 1.085 (1.068), Geburten 518 (519), Zuzüge 1.001 (1.000),
Wegzüge 40 (41), ohne Arbeit an Tag 730 5,1 % (5,1 %), Budget an Tag 730 3,76 Mio. (5,75 Mio.), Erspartes je Erwachsenem 12.960
(11.902), Zufriedenheit 70,8 (70,3), Tech-Gründungen 22,9 (27,4; Erspartes geht erst in die Wohnung), Lohnsteuer 1.803 (1.859) und
Rentenkasse 9.760 (8.316) Taler am Tag, Stadtbuch 4,28 Zeilen am Tag (4,31), davon Stadtregierung 74 Zeilen je Stadt (3).

**Gate 7 wird knapper, ehrlich gesagt:** Es fällt auf 4 von 160 Seeds (30, 49, 97, 130) statt auf 1 (81); der kleinste Abstand ist 11,4
statt 10,0 (81–160) bzw. 12,9 statt 15,7 (1–80). Im Mittel sinkt der Abstand um 0,7 (Standardfehler 0,7, Seeds 1–80), die Ausläufer
werden dünner. Die Vermutung der Gegenprüfung (weniger Wegzüge wegen Geld, weil Eigentümer keine Miete zahlen) trägt nicht: Bis Tag 365
ziehen im Mittel 17,7 statt 16,1 Leute weg, und wie im Kern fast alle wegen Geld (17,4 gegen 15,8 je Stadt, aus den Stadtbuch-Gründen).
Gate 4 liegt im Rauschen der Zuzug-Regel (Placebo 77 von 80, „Bekannte Schwächen“). Kein Urteil über das Programm: Die Stadt bildet
Zinsen, Nebenkosten und die Finanzierung der Renten nicht ab.

`--gate` (Seeds 1, 2, 3, je 730 Tage) besteht; in Klammern der Kern:

| Gate | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| 1 Einwohner an Tag 365 | 765 (861) | 966 (902) | 847 (919) |
| 2 schlimmster 30-Tage-Einbruch | 3,0 % (2,9 %) | 2,7 % (4,7 %) | 2,1 % (3,6 %) |
| 3 kleinstes Budget | 6.731 (6.731) | 6.743 (6.743) | 6.538 (6.538) |
| 4 Band Tag 551–730, Abstand zur Baugrenze | 1,08, 24 (1,05, 28) | 1,03, 20 (1,04, 24) | 1,06, 28 (1,07, 28) |
| 5 Gründungen bis Tag 365 | 208 (194) | 278 (193) | 211 (201) |
| 6 Gründer-Ehrgeiz | +18,6 (+18,0) | +20,2 (+17,7) | +19,6 (+22,4) |
| 7 Wegzieher-Heimatliebe | −21,7, n = 12 (−29,1, n = 17) | −25,1, n = 26 (−17,1, n = 11) | −25,7, n = 19 (−33,0, n = 13) |
| T 365 Tage | 1,3 s (1,4 s) | 1,5 s (1,6 s) | 1,3 s (1,5 s) |
| B Stadtbuch, Zeilen am Tag (davon Bauhof) | 3,89 (0,24) | 4,66 (0,28) | 4,04 (0,24) |
| Lohnsteuer am Tag, Tag 700–730 (alte Regel) | 2.458 (4.344) | 2.499 (4.500) | 2.408 (4.368) |
| von außen am Tag, Tag 700–730: Rentenkasse, Bund | 22.266, 887 | 22.389, 968 | 22.244, 844 |

Im Kern waren es an Tag 700–730 17.382 / 17.186 / 18.069 Taler Rentenkasse am Tag. T schwankt mit der Last der Maschine.

Weitere Prüfungen: `--kitest` (Gehirn ⊆ erlaubte Aktionen, 28.736 Entscheidungen, 0 abweichend), `--bau`, `--waren`, `--tech`,
`--regierung`, `--migrationstest --git <repo>` (Versionen 2, 3, 4 und 5), `--speichertest` grün. `--aufholtest` (nur Ausgabe): Seed 1,
Tag 200 → 290, stündlich 377 Einwohner, in Tagesschritten 370.

Befunde der Gegenprüfungen, umgesetzt:
- Mieterkauf: Namenskollision mit der Gerätereserve (Blocker) → eigene Namen `EIGEN_*`, Test auf 600 Taler; Gate 7 ehrlich (oben);
  „Mietsteigerungen gibt es nicht“ war falsch (Aufstockungen erhöhen die Miete, Eigentümer zahlen weiter dieselbe Rate), Rentnerhaushalte
  „besitzen“ und „schuldenfrei“ getrennt gemessen (98 % / 91 %), Mieter heißen „Haushalte mit Stelle“, ohne Rahmen „Zugezogene“;
  Eigenkapitalersatz ehrlich zugeordnet (Mindestanzahlung als Annahme, strenger als die Richtung des Programms); Rückkauf als Annahme des
  Modells, S. 60 nur dafür, dass beim Erbe keine Steuer anfällt, Weitergabe mit der Regel des Haushalts begründet; die Zeile „In der ersten Nacht …“ nur nach einer
  Übernahme (Marke `schritt2`), sonst „Als erste Haushalte kaufen …“; Fenster-Listen nachgezogen (Mieterkauf, Wohngeld, Grunderwerbsteuer
  für Selbstnutzer, Erbschaftsteuer, Grunderwerbsteuer für Käufer außerhalb der EU), das Einwanderungs-Zitat von S. 36 nicht beim Kauf;
  Begründung zum Erbe der Kinder ohne die Grenze; Zusammenziehen in die gekaufte Wohnung; Grundsicherung zahlt die Rate (als Annahme
  genannt); ein Stand von Schritt 2 in einer alten Datei: Versionsdialog statt TypeError (Version 6); Integritätsprüfung beim Laden.
- Renteneintritt: Kalibrierung korrigiert (oben); Speicherformat unabhängig von der Reihenfolge (Version 6 mit Übernahme, Beitragsjahre
  aus dem Alter, alle Summen ergänzt, Test „Stand der Version 5 laden, 60 Tage, speichern, laden“ in `--migrationstest`); Zwangsende,
  Betriebs- und Betreuungstage als Annahmen der Stadt ausgewiesen, nicht als Programminhalt; das Österreich-Zitat (S. 18) und das Zitat zu
  versicherungsfremden Leistungen (S. 17) und zur Zuwanderung (S. 20) stützen den Baustein nicht mehr; Renteneintritte vor 67 durch
  Schließung eines Betriebs werden mitgezählt; Kommentare korrigiert, keine Schalter; Stadtbuch „kann … gehen“ (Angebot). Ein
  Wohngeld-Zweig, in dem die Rente nur ohne Arbeit zählte, gibt es im fertigen Kern nicht.

Tests: `--regierung` prüft zusätzlich Beitragstage über Mitternacht, Beitragsjahre am Start und am Ankunftstag, den Renteneintritt mit
64 (449 gegen 450 Beitragstage, das Gehirn wählt „kündigen“, danach keine Stellensuche, Rente, nicht arbeitslos), 67 mit Stelle (Rente,
Rentner-Freibetrag genau nachgerechnet), den Rentner-Freibetrag in jeder nachgerechneten Nacht, und den Mieterkauf (Anzahlung, Rate,
Erbe, Auflösung, Umzug, Zusammenziehen, Wegzug der Eltern mit erwachsenem Kind, Invariante jede Nacht, keine NaN, jede Budgetbuchung
des Mieterkaufs gegen die Summen), dazu kaputte Stände der Version 6. `--migrationstest` übernimmt auch Version 5 (git 414ebab).
Browser: `tests/s2karten.cjs` (Fenster, Personen- und Hauskarte, breit und Handy), `tests/p6migration.cjs` mit Version 5,
`tests/ereignis.cjs` mit neuen Momenten der Teststadt (Tag 619 vier Pleiten, Tag 679 elf Übernahmen, Tag 689 ein Bau fertig, Tag 695
ein Bau fertig und eine Schließung; gesucht mit `mess/momente.mjs`; die Schleife zum Vorspulen durfte nur 5.000 Stunden, jetzt 20.000),
`tests/t1_xss.cjs` mit dem Teststand in Version 6 (`tests/basis_v6.json`, aus dem Stand der Version 5 über „Stadt übernehmen“,
`tests/basis_v6.cjs`; das Original bleibt). Ergebnis (Server auf 8712, `tests/alle.sh`): p3test 12, p4test 25, p5neu 10, p6migration
18, p7figuren 6, p8tech 14, raute_klick 10, ereignis 21, t1_xss 5 und s2karten 22 Prüfungen ohne Fehler, Konsole leer; `tests/otest`
(befunde, handy, breit, tastatur, breiten) ohne Fehler. otest/befunde fiel im ersten Lauf unter Last einmal: Nach dem Wechsel auf
1280 × 800 war die Karte nach 300 ms noch eingeklappt; im Einzellauf grün, Schritt 2 ändert an der Karte nichts (Ursache unten bei
den Kitas). Die Kennzahlen sind
nicht höher geworden (`tests/kennzahlen_hoehe.cjs`, Unterkante wie vorher: 156 bis 158 px bei 568 × 320 bis 844 × 390, 211 px bei
400 × 820). Bilder: `nachher/` (Teststadt) und `gross/` (`&umland=300000`, Seed 2, Tag 750: 5.694 Einwohner, 24–26 Draw Calls,
etwa 124.400 Dreiecke).

#### Kitas in Wohnraumnähe (S. 20)

Auf Noahs Wunsch der dritte Baustein von Schritt 2: der Entwurf „B0“ mit allen Korrekturen seiner Gegenprüfung (Scratchpad,
`afd/schritt2_entwuerfe.json`, Baustein `kita`; Liste unten), eingebaut auf dem Stand mit Mieterkauf und Renteneintritt. Im Fenster
(Karte „Kitas in Wohnraumnähe, Vorrang für arbeitende Eltern“, Gruppe „Familie und Bund“): „Bereitstellung von ausreichend
Kindergarten- und Kitaplätzen in Wohnraumnähe mit Vorrang für Familien, in denen beide Eltern arbeiten, sowie für arbeitende
Alleinerziehende“ (S. 20) und „Krippen und Kitas sind personell ausreichend und qualifiziert zu besetzen.“ (S. 152). Die Forderung
steht auf S. 20 in der Liste „Weitere Bausteine, die die Rente langfristig stabilisieren“; dass ein Platz Eltern das Arbeiten
ermöglichen soll, ist die Lesart der Stadt. Wie überall liest keine Regel Namen, Herkunft, Staatsangehörigkeit, Sprache, Religion,
Einzugstag oder Eltern außerhalb des Haushalts. Gelesen werden Alter, Haushalt, Partner, Wohnung (Entfernung zur Kita), Stelle und ihr
Lohn, eigener Betrieb, gemeinnützige Arbeit und Rente, bei Gleichstand die Personennummer. Die Deutschpflicht in Kitas (S. 152) bleibt
ausgelassen (Fenster, „Grenze der Stadt“).

Wie es läuft:
- **Gebäude.** Neuer Typ Kita (`KITA = 8`). Das Bauamt baut sie (Regel 6), der Bauhof braucht 12 Arbeitstage, die Stadt zahlt 1.600
  Taler. Regel 6 greift, wenn Kinder auf einen Platz warten oder Eltern ohne Platz keine Stelle antreten können, im Budget mindestens
  4.000 Taler sind (eine Kita und ein Wohnhaus) und gerade keine Kita im Bau ist. Das Bauamt verteilt die Wartenden in
  Vorrang-Reihenfolge auf die freien Räume der Kitas in ihrer Reichweite (eine Kita im Bau zählt mit 40). Für das erste Kind ohne
  Raum baut es höchstens 12 Felder von dessen Wohnung, auf einem freien Bauplatz, sonst in einem leerstehenden Laden oder einer
  leerstehenden Werkstatt (Umbau, gleiche Kosten und Bauzeit). Stadtbuch: „Das Bauamt baut eine Kita … In der Nähe fehlen für 9
  Kinder Plätze.“ bzw. „Das Bauamt baut den leeren Laden … zur Kita um. …“; die Zeile von Tag 0 sagt seit der zweiten Gegenprüfung
  kürzer „… und die Stadt baut Kitas mit Vorrang für arbeitende Eltern.“ (Einzelheiten im Fenster). Eine Kita steht nie leer,
  hat keinen Besitzer und keine Einnahmen.
- **Plätze.** Räume für 40 Platzeinheiten, ein Kind unter 3 belegt zwei (Krippe), ab 3 eine. Anbieten kann die Kita 8 Einheiten je
  Fachkraft, höchstens 40.
- **Personal.** Stellen nach Bedarf (`g.soll`): eine je angefangene 8 Einheiten (belegt plus Wartende, für die diese Kita die nächste
  ist) und eine Reserve, höchstens 5. Wer schon da ist, bleibt, auch wenn der Bedarf sinkt. Lohn anfangs 95 (was die Stadt zahlt), +2
  am Tag, solange weniger Leute da sind als Stellen, −1 nur, solange mehr Leute da sind als Stellen, zwischen 95 und 120 (seit der
  zweiten Gegenprüfung; vorher sank er bei voller Besetzung jeden Tag um 1 bis 95, und die Fachkräfte wechselten zu besser bezahlten
  Stellen). Besetzt werden die Stellen über „Stelle suchen“ und „Stelle wechseln“; sie locken keinen Zuzug (wie Ladenstellen,
  Annahme 11). Löhne und 30 Taler Fixkosten am Tag zahlt die Stadt.
- **Vergabe**, jede Nacht nach der Wirtschaft (`kitaTag`): Angemeldet ist jedes Kind unter 6 (60 Spieltage) mit Wohnung, außer einem
  Kind unter 3 in einem Haushalt, in dem ein Erwachsener ohne Stelle ist; das betreut der Haushalt selbst. Zuerst kommen Kinder aus
  Haushalten, in denen der Vorstand arbeitet und, falls ein Partner im Haushalt lebt, auch dieser (beide Eltern oder der
  alleinerziehende Elternteil; als Arbeit zählen eine Stelle, der eigene offene Betrieb und gemeinnützige Arbeit), dann alle übrigen;
  darin das ältere Kind zuerst, dann die Nummer. Wer einen Platz hat, behält ihn, solange die Kita offen, höchstens 12 Felder
  entfernt und nicht zu voll ist; neue Plätze gibt die nächste Kita in Reichweite, die mit ihrem Personal genug Einheiten frei hat.
  Gehen Fachkräfte, fallen je Nacht höchstens 8 belegte Einheiten weg (eine Fachkraft), solange noch jemand da ist; darüber kommt
  niemand neu dazu (Bestand, Annahme wie eine Kündigungsfrist). Die Plätze gelten für die ganze Nacht: Wer in der Nacht wegen eines
  fehlenden Platzes aufhört und selbst in einer Kita arbeitet, fehlt ihr ab der nächsten Nacht (`--kita` prüft beides am Ende der Nacht).
- **Betreuungspflicht (Annahme der Stadt).** Ein Kind unter 6 braucht einen Kita-Platz oder einen Erwachsenen des Haushalts ohne
  Stelle zu Hause (Eltern, Großeltern, erwachsene Geschwister, auch in Rente; wer seinen Betrieb gerade bauen lässt und keine Stelle
  hat, ist auch zu Hause). Hat ein Kind keinen Platz, ist niemand zu Hause und bietet in der Nähe eine Kita Plätze an (offen und letzte
  Nacht mit Personal; auch wenn sie gerade voll ist), gibt von Vorstand und
  Partner mit Stelle auf, wer weniger verdient; bei Gleichstand der Vorstand (eine Haushaltsrolle, das Geschlecht liest die Stadt
  nicht). Lebenslauf „Stelle aufgegeben: kein Kita-Platz für … frei“, im Stadtbuch je Nacht höchstens eine Zeile „Kein Kita-Platz
  frei: …“ mit dem Grund beim ersten Haushalt: „Die Kita an der Nordstraße ist voll.“ (alle Räume belegt) oder „… ist voll, sie hat
  nur 1 Fachkraft.“ (seit der Nachprüfung der zweiten Gegenprüfung; der Grund stand vorher nicht da). Nur gezählt, nicht erzwungen: Wer einen eigenen Betrieb hat oder gemeinnützige Arbeit leistet, muss nicht aufhören; wo in
  der Nähe keine Kita Plätze anbietet (noch im Bau, kein Platz dafür oder ohne Fachkraft), verlangt die Stadt nichts. Vorher zählte eine
  Kita ohne Fachkraft als Angebot; weil eine neue Kita immer ohne Personal öffnet, mussten in der Nacht der Eröffnung Eltern aufhören
  (Blocker der zweiten Gegenprüfung).
- **Gebunden.** Wer so zu Hause bleibt (Vorstand oder Partner ohne Stelle, Betrieb und Rente, einziger Erwachsener ohne Stelle im
  Haushalt, und in den Kitas der Nähe ist für die Kinder ohne Platz nicht genug frei), kann keine Stelle suchen, nichts gründen und
  wird nicht zu gemeinnütziger Arbeit herangezogen, in `entscheide()` und `erlaubteAktionen()` gleich. Gebundene zählen nicht als
  erwerbsfähig und nicht als arbeitslos (wie die Elternzeit). Die Kinder unter 3 solcher Eltern zählen fürs Bauamt als Bedarf.
  Personenkarte: „Kann gerade keine Stelle antreten: Für ‹Kind› ist in der Nähe kein Kita-Platz frei, und sonst ist niemand zu
  Hause.“, Hauptfiguren bekommen den Satz als Tatsache.
- **Betreuungsgehalt (R06)** gibt es nur noch, solange das Kind unter 3 keinen Platz hat (Lesart „Eigenbetreuung“, S. 20, oben bei
  den Annahmen der Stadtregierung). Eltern eines Krippenkinds können weiter kündigen, um beim Kind zu bleiben (Wunsch-Bonus 20); das
  Kind gibt den Platz dann ab.
- **Renteneintritt (R12).** Wer in Rente ist, auch vor 67, zählt im Haushalt als zu Hause und ist selbst nie gebunden. Eine
  Kita-Stelle bringt Beitragstage wie jede Stelle; Gebundene sammeln keine (weder Stelle noch Betreuungsgehalt).
- **Übergangsfrist.** Nach einer Übernahme (Version 5, Versionen 2 bis 4 über die Kette) gibt es Plätze und Bauamt, aber keine Pflicht,
  mindestens 30 Tage (`KITA_FRIST`) und bis in einer Nacht kein Kind mehr auf einen Platz wartet, höchstens 90 Tage (`KITA_FRIST_MAX`;
  seit der zweiten Gegenprüfung, vorher fest 30 Tage). Gespeichert ist das Ende in `S.regierung.kitaAb` (−1, solange die Frist läuft).
  Die Zeile der Übernahme sagt „bis kein Kind mehr auf einen Platz wartet (mindestens bis Tag …, höchstens bis Tag …), muss niemand
  wegen eines fehlenden Platzes zu Hause bleiben“, am letzten Tag folgt „Die Übergangsfrist für die Kitas endet, kein Kind wartet mehr
  auf einen Platz: …“ bzw. „… endet nach 90 Tagen: …“ mit der Zahl der Wartenden. Neue Städte haben keine Frist (`kitaAb` 0): Das Bauamt
  beginnt die erste Kita im Mittel an Tag 9 (spätestens Tag 38, Seeds 1–80), vorher sind kaum Kinder da.

Darstellung: ein eingeschossiges gelbes Haus mit Ziegel-Satteldach, Tür und Fenstern im hinteren Teil des Grundstücks, davor ein
eingezäunter Spielplatz mit Rasen, Weg, Sandkasten, Kletterturm mit Rutsche, Schaukel und Baum. Das Haus ist ein eigenes Mesh
(+1 Draw Call: 26 statt 25 bei 1280 × 800, 25 statt 24 bei 400 × 820), der Spielplatz liegt in den Meshes von Parks und Bauteilen. Ein
Klick aufs Dach öffnet die Hauskarte. Die Erzieherinnen und Erzieher (Arbeitskleidung grün, in der Hilfe „Kräftiges Grün: Kita, steht
bei der Arbeit auf dem Spielplatz.“) stehen während der Arbeit auf dem Spielplatz.
Hauskarte: Kopf „gehört der Stadt, 4 Fachkräfte (Bedarf 3), Lohn 97 Taler am Tag“ (Personal und Bedarf getrennt; vorher „4 von 3
Stellen besetzt“), im Bau „gehört der Stadt; Fachkräfte stellt sie ein, sobald die Kita offen ist“; darunter „‹n› Kinder (‹k› unter 3),
‹belegt› von ‹möglich› Platzeinheiten belegt; ein Kind unter 3 braucht zwei.“ mit dem Grund, wenn die Kita keine oder weniger Plätze
anbietet, als belegt sind („Noch keine Plätze: Letzte Nacht war keine Fachkraft da …“, „Keine Plätze: Die Kita hat keine Fachkraft …“,
„Es fehlen Fachkräfte: Die Kinder behalten ihre Plätze vorerst …“), dann „Die Kita stellt nach Bedarf ein: …“, der Vorrang mit Hinweis
auf die Annahme, das Personal unter „Hier arbeiten“, die Kinder im Abschnitt „Kinder“ (wer heute 6 geworden ist, mit „· letzter Tag“).
Personenkarte eines Kindes: „Kind, geht in die Kita …“, am Tag, an dem es 6 wird, „Kind, letzter Tag in der Kita …“ (vorher stand es in
der Liste der Kita, auf seiner Karte aber ohne Kita), „Kind, wird zu Hause betreut“ oder „Kind, wartet auf einen Kita-Platz“, mit Knopf
zur Kita. Im Fenster zeigt die Karte live offene Kitas und Kitas im Bau, Fachkräfte und Bedarf („18 Fachkräfte (Bedarf 16)“), Lohn, Kinder
mit Platz (davon unter 3), Wartende (davon ohne Kita-Angebot in der Nähe), zu Hause betreute Kinder unter 3, Gebundene, die
Übergangsfrist, die Kosten von gestern und die Summen seit Schritt 2 (gebaute Kitas, aufgegebene Stellen, nur gezählte Haushaltstage,
Kosten). Die Karte zeigt Titel, Zitate, „In der Stadt“, die Kern-Annahme (Betreuungspflicht, Träger), den Hinweis mit S. 147 und S. 152
und die Live-Zahl; die übrigen Annahmen stehen im aufklappbaren Teil „Weitere Annahmen und Folgen“ (auch bei den Karten zu R11 und R12).

| Annahme (Werte in `R`, `KITA_*`) | Wert | Warum |
|---|---|---|
| Betreuungspflicht | Kind unter 6 braucht einen Platz oder einen Erwachsenen des Haushalts ohne Stelle zu Hause | Annahme der Stadt, nicht aus dem Programm (Noahs Entscheidung). Ohne sie hätte der Vorrang keine Wirkung: Vorher brauchten Kinder in der Stadt keine Betreuung |
| Kita-Alter | unter 6 Jahren (60 Spieltage), Krippe unter 3 (30) | Schule ab 6 (Annahme, ein Alter nennt das Programm nicht); die Krippengrenze 3 folgt dem Betreuungsgehalt „bis zum 3. Geburtstag“ (S. 147) |
| Krippe nur ohne jemanden zu Hause | Kind unter 3 bekommt nur einen Platz, wenn niemand aus dem Haushalt ohne Stelle ist | Spielvereinfachung der Stadt, kein Ausschluss aus dem Programm: Es nennt Vorrang (S. 20) und „Wahlfreiheit zwischen Fremd- und Selbstbetreuung“ (S. 147). Enger als § 24 SGB VIII: Ab 1 Jahr besteht der Anspruch unabhängig von der Erwerbstätigkeit (Abs. 2), unter 1 zählt auch Arbeitssuche (Abs. 1) |
| Zu Hause | jeder Erwachsene des Haushalts ohne Stelle, auch Großeltern, erwachsene Geschwister und Rentner; der eigene offene Betrieb und gemeinnützige Arbeit zählen als Arbeit | S. 148 nennt beim Betreuungsgehalt „Eltern bzw. Großeltern“; erwachsene Geschwister deckt kein Zitat, das ist Annahme. Betreuungsgehalt bekommen weiter nur Vorstand und Partner: Selbst betreute Kindtage ohne Betreuungsgehalt gemessen 16,7 je Stadt in 730 Tagen, 0,4 % aller selbst betreuten Kindtage (Seeds 1–10) |
| Platzeinheiten | Kind unter 3 zwei, ab 3 eine; 8 Einheiten je Fachkraft | Übliche Schlüssel Krippe 1:4, Kindergarten 1:8, als Größenordnung gesetzt; S. 152 nennt keine Zahl („personell ausreichend“) |
| Räume | 40 Einheiten je Kita | Gesetzt: eine mittlere Einrichtung; bei 5 Fachkräften voll |
| Personal | eine Stelle je angefangene 8 Einheiten Bedarf und eine Reserve, höchstens 5; wer da ist, bleibt | Mit festen 5 Stellen je Kita sank das Budget in den ersten Tagen bis auf 43 Taler, und die Stadt konnte Löhne nicht mehr voll zahlen; nach Bedarf ist das kleinste Budget 5.645 (Seeds 1–80). Die Reserve deckt freie Tage |
| Lohn | 95 bis 120, +2 am Tag bei offenen Stellen, −1 nur mit mehr Leuten als Stellen | Annahme der Stadt, keine Aussage des Programms: „personell ausreichend“ (S. 152) heißt hier, dass die Stadt mehr zahlt, bis die Stellen besetzt sind; eine Qualifikation kennt die Stadt nicht. Vorher sank der Lohn wie im Bauhof bei voller Besetzung jeden Tag um 1 und blieb fast immer bei 95 (Ø 95,5), dem niedrigsten Lohn der Stadt; die Fachkräfte wechselten deshalb laufend zu besser bezahlten Stellen (Befund der zweiten Gegenprüfung). Jetzt Ø 97,8 (Tag 366–730, je Stadt 95,9 bis 99,9, Seeds 1–80) |
| Kosten | Bau 1.600 Taler und 12 Arbeitstage wie eine Werkstatt, 30 Taler Fixkosten am Tag wie ein Laden, dazu die Löhne | Das Programm sagt nicht, wer Kitas bezahlt; die Stadt nimmt die Kommune als Träger an (Noahs Entscheidung). Keine Elternbeiträge (das Programm nennt keine) |
| Umbau | leerstehender Laden oder leerstehende Werkstatt, wenn in Reichweite kein Bauplatz frei ist; Kosten und Bauzeit wie ein Neubau | Sonst fand das Bauamt in dichten Vierteln keinen Platz, und dort blieb die Pflicht ohne Angebot (Befund beim Bau, unten) |
| Wohnraumnähe | höchstens 12 Felder (Manhattan) | Dieselbe Reichweite wie beim Einkauf (`REICH_LADEN`) |
| Vorrang | Stufe 1: Vorstand arbeitet und, falls im Haushalt, sein Partner; Stufe 2: alle übrigen; darin älter vor jünger | S. 20. „Arbeiten“ heißt Stelle, eigener offener Betrieb oder gemeinnützige Arbeit (tagsüber weg); das ältere Kind zuerst ist eine Annahme (es braucht den Platz nur noch kürzer) |
| Bestand | wer einen Platz hat, behält ihn vor jeder Neuvergabe | Annahme: Kein Kind verliert seinen Platz an ein Kind der Stufe 1, das später kommt |
| Bestand bei Personalabgang | je Nacht höchstens 8 belegte Einheiten weniger, solange noch eine Fachkraft da ist; neue Plätze nur nach dem Personal | Annahme wie eine Kündigungsfrist: Vorher verloren Kinder in derselben Nacht den Platz, in der Fachkräfte gingen, und mehrere Eltern mussten zugleich aufhören (Befund der zweiten Gegenprüfung). Ohne Fachkraft bietet die Kita nichts an |
| Wer aufhört | von Vorstand und Partner mit Stelle, wer weniger verdient; bei Gleichstand der Vorstand | Annahme der Stadt; Haushaltsrolle statt Geschlecht (Annahme 15) |
| Besitzer, gemeinnützige Arbeit | müssen nicht aufhören, wird nur gezählt | Annahme: Wer einen Betrieb hat, teilt sich die Zeit ein; gemeinnützige Arbeit hat eigene Regeln (R07). Gemessen 10,6 Haushaltsnächte je Stadt in 730 Tagen |
| Keine Kita mit Plätzen in der Nähe | keine Pflicht, wird nur gezählt | Wo die Stadt nichts anbieten kann, verlangt sie nichts. Anbieten heißt: offen und letzte Nacht mit Personal (seit der zweiten Gegenprüfung; vorher zählte jede offene Kita, auch eine neue ohne Fachkraft). Gemessen 53,8 Haushaltsnächte je Stadt in 730 Tagen (vorher 34,1), höchstens 281 (Seed 39); auf Seed 54 188 (vorher 655, dort fand das Bauamt zwischen Tag 300 und 450 in einem Teil der Stadt weder Bauplatz noch leeres Gebäude in Reichweite) |
| Gebundene | nicht arbeitslos, keine Stellensuche, keine Gründung, keine gemeinnützige Arbeit | Wie die Elternzeit; sie können keine Stelle antreten, bis in der Nähe genug frei ist |
| Bedarf fürs Bauamt | Wartende und Kinder unter 3 gebundener Eltern | Befund der Gegenprüfung: Ohne das plante das Bauamt nie für sie |
| Übergangsfrist | nach einer Übernahme mindestens 30 Tage und bis in einer Nacht kein Kind mehr wartet, höchstens 90 | Befund der ersten Gegenprüfung (Kündigungsschock); fest 30 Tage reichten nicht, wenn die Kitas am Ende der Frist voll waren (Befund der zweiten Gegenprüfung, Messung unten) |
| Kita-Stellen locken keinen Zuzug | wie Laden- und Bauhofstellen | Annahme 11; sonst zögen Leute für Stellen zu, deren Kinder wieder Plätze brauchen |

**Wirkung, gemessen** (Seeds 1–80, 730 Tage stündlich, `mess/mess3.mjs` auf `mess/stadt.v3.html`, dem Stand nach der zweiten
Gegenprüfung; Tageswerte im Mittel über Tag 366–730, Summen bis Tag 730 je Stadt; in Klammern der Stand davor):
- Kinder unter 6 im Mittel 55,5, davon mit Platz 48,4 (20,2 unter 3), auf der Warteliste 0,31 (in keiner Stadt im Mittel über 0,53;
  vorher 0,36 und 1,66), ohne Kita-Angebot in der Nähe 0,01, unter 3 zu Hause betreut 6,7. Gebunden 0,02 Personen am Tag (0,09;
  höchstens 0,12 im Mittel einer Stadt).
- Kitas: 6,1 gebaut, davon 2,1 als Umbau (in 77 von 80 Städten mindestens einer), 5,8 offen; 17,6 Fachkräfte bei Lohn 97,8 (16,8 bei
  95,5). Kosten der Stadt im Mittel 1.201 Taler am Tag (1.106), an Tag 700–730 1.759 (1.664; Lohnsteuer im Vergleich: 1.866).
- Stelle aufgegeben, weil kein Platz frei war: 14,0-mal je Stadt in 730 Tagen, 1 bis 69 (vorher 75,7, 35 bis 125); 72 gebundene
  Personentage (328). Kindtage auf der Warteliste 72 (160), Kindtage unter 3 gebundener Eltern (Bedarf fürs Bauamt) 57 (225), Haushaltsnächte
  ohne Kita-Angebot in der Nähe 53,8 (34,1), nur mit Besitzern 0,9 (10,6). Stadtbuch: 8,2 Zeilen „Kita“ (34) und 6 Zeilen des Bauamts
  je Stadt.
- Wellen (`mess/wellen4.mjs neu`, dieselben Seeds 1–80): Nächte, in denen 4 oder mehr Eltern aufhören, 56 zusammen (29 mit 5 oder
  mehr), in 32 von 80 Städten, meist eine; die größte Nacht 10. Auf den Seeds 1–20 vorher 121 solche Nächte (66 mit 5 oder mehr, größte
  11), 99 davon nach einer Nacht, in der mindestens 2 Fachkräfte gegangen waren; jetzt 6 (größte 5). Was bleibt, ist die Regel selbst:
  Eine volle Kita bietet Plätze an, und wo das Bauamt daneben weder Bauplatz noch leeres Gebäude findet, hören Eltern in Schüben auf.
  Am deutlichsten auf Seed 30 (Tag 326–349 sieben Nächte mit 4 bis 9 Aufgaben neben einer vollen Kita mit 5 Fachkräften; 69 Aufgaben in
  730 Tagen), Seed 54 (5 Nächte, größte 10) und Seed 57 (4 Nächte, größte 7).
- Eltern (Vorstand und Partner 18–66 mit Kind unter 6, Tag 366–730): 89,0 % arbeiten (88,5), 6,4 % bekommen Betreuungsgehalt (6,8),
  4,6 % sind sonst ohne Arbeit (4,7), 0,00 % gebunden (0,01; höchstens 0,03 % in einer Stadt). Auf den Seeds 1–20 vor den Kitas: 88,2 %,
  7,0 %, 4,8 %. Die Kitas ändern den Anteil arbeitender Eltern kaum: Vorher brauchten Kinder gar keine Betreuung, Eltern konnten
  ohnehin arbeiten.
- Krippe (gemessen vor der zweiten Gegenprüfung): Weil Eltern jederzeit für das Betreuungsgehalt kündigen können (R06, Wunsch-Bonus 20),
  wechseln Kinder unter 3 oft zwischen Krippe und zu Hause: je Stadt 703 Platzverluste unter 3 bei 330 von 543 Kindern, einzelne bis zu
  12-mal (Seeds 1–10, `mess/krippe.mjs`). Das Hin und Her gab es im Kern schon beim Betreuungsgehalt; die Kita macht es auf den Karten sichtbar.
- S. 152 (gemessen vor der zweiten Gegenprüfung): Das Programm erwartet vom Betreuungsgehalt, dass es „die Nachfrage nach Kita-Plätzen
  deutlich senken wird“ (S. 152, im Fenster als Hinweis). Die Stadt prüft die Aussage nicht. Sie zeigt nur, was aus ihrer eigenen Verhaltensannahme folgt, dem Wunsch-Bonus 20 auf
  „kündigen“ (R06, nicht aus dem Programm). Ohne ihn (Seeds 1–20) werden zu Hause 0,8 statt 7,1 Kinder unter 3 betreut, 25,5 statt
  20,2 haben einen Krippenplatz, das Personal ist 19,2 statt 17,0, die Kosten 1.237 statt 1.102 Taler am Tag; Eltern arbeiten zu 98,1
  statt 88,5 %.

Übernahme einer Stadt ohne Kitas, Messung der ersten Gegenprüfung (`mess/uebernahme.mjs`: Kern-Stände der Version 5, git 414ebab,
Seeds 1–3 an Tag 150, 300 und 400, danach 120 Tage; je Tag im Mittel der neun Städte; die neue Messung steht darunter):

| Übergangsfrist | in der Frist | erste Nacht danach | Tag 2–10 danach | Tag 11–30 | Tag 31–60 | Rest |
|---|---|---|---|---|---|---|
| keine: Stelle aufgegeben / gebunden / wartend | – | 0 / 0 / 39,6 | 3,48 / 13,3 / 26,4 | 0,51 / 3,4 / 5,2 | 0,19 / 0,8 / 3,4 | 0,14 / 0,6 / 1,3 |
| 30 Tage | 0 / 0 / 13,7 | 0 / 0,2 / 3,4 | 0,17 / 0,5 / 3,4 | 0,21 / 1,0 / 2,9 | 0,26 / 1,2 / 1,5 | 0,15 / 0,5 / 0,3 |

Ohne Frist hören in den ersten zehn Tagen bis zu 51 Eltern einer Stadt auf (Seed 1 und 2, Tag 300); in der ersten Nacht noch keiner, weil
dort nirgends eine Kita offen ist. Mit der Frist stehen die ersten Kitas, bevor die Pflicht beginnt; danach geben 0,15 bis 0,26 Eltern am
Tag ihre Stelle auf (neue Städte: 0,10 im Mittel über 730 Tage). Die Gegenprüfung hatte im Entwurf ohne Frist 32 Kündigungen in der
ersten Nacht gemessen (Seed 2, Tag 400).

Der Satz „danach 0 Kündigungen in der ersten Nacht“ (unten, Befunde der ersten Gegenprüfung) war zu stark, er galt nur für diese neun
Städte. Die zweite Gegenprüfung fand auf 24 Übernahmen (Seeds 1–12, Tag 300 und 400) erste Nächte mit 9 und 12 Aufgaben und später
einzelne Nächte mit bis zu 14. Neu gemessen auf 80 Übernahmen (`mess/wellen4.mjs ueb`: Stände der Version 5 aus `stadt.orig.html`,
Seeds 1–20 je an Tag 150, 300, 400 und 500, übernommen und 100 Nächte gerechnet; Stellenaufgaben wegen eines fehlenden Platzes je Nacht):

| Stand | Frist (Tage) | in der Frist | erste Nacht danach: Ø, höchstens | größte Nacht der 100: Ø, höchstens | Nächte mit ≥ 4 (in Übernahmen) | nach der Frist je Übernahme: Ø, höchstens |
|---|---|---|---|---|---|---|
| vor der zweiten Gegenprüfung | 30 | 0 | 1,15, 12 | 4,94, 22 | 82 (40 von 80) | 12,7, 58 |
| Plätze nur mit Personal, Lohn, Bestand; Frist fest 30 | 30 | 0 | 0,24, 11 | 1,30, 13 | 20 (9) | 3,2, 62 |
| **dazu Frist bis kein Kind wartet (heute)** | **30 in 56, 31–47 in 15, 62–90 in 9 Übernahmen** | **0** | **0,05, 1** | **0,86, 5** | **8 (6)** | **2,0, 22** |

Mit fester Frist blieben zwei Schocks: Seed 17, Tag 300 (11 in der ersten Nacht, 62 in den 70 Nächten danach; am Frist-Ende warteten
14 Kinder) und Seed 13, Tag 300 (13 in einer Nacht, 25 wartende Kinder). Mit der Frist bis kein Kind mehr wartet hört in der ersten
Nacht danach in 76 von 80 Übernahmen niemand auf, sonst einer; die größten Nächte (5) liegen in kleinen Städten, übernommen an Tag
150, die danach so schnell wachsen wie eine neue Stadt im ersten Jahr (Seeds 6 und 7), und auf Seed 17, Tag 400. Die 90 Tage erreichte
eine Übernahme. Weil die 100 Nächte ab der Übernahme zählen, ist das Stück nach einer langen Frist kürzer.

**Speicherformat 6, erweitert.** Die Version bleibt 6 (Noahs Entscheidung; der Stand ohne Kitas wurde nie veröffentlicht). Seit der
zweiten Gegenprüfung gehört dazu `S.regierung.kitaAb` (Ende der Kita-Frist: −1, solange sie läuft, sonst ein ganzer Tag zwischen Schritt 2
und heute, in neuen Städten 0); fehlt es oder passt es nicht, heißt es „Spielstand beschädigt: Stadtregierung“. Stände der Fassung davor
(ohne `kitaAb`, nie veröffentlicht) gelten damit als beschädigt; `tests/basis_v6.json` ist neu erzeugt (Tag 420, `kitaAb` −1). Neu je Person
`kita` (Kita + 1, 2 Bytes), je Gebäude `soll` (Kita-Stellen, 1 Byte), in `S.stat.regierung` die Summen der Kitas (Kindtage mit Platz
und wartend, neue Plätze, aufgegebene Stellen, nur gezählte Haushalte mit Besitzern und ohne Kita in der Nähe, gebundene Personentage,
Kindtage unter 3 gebundener Eltern, Kosten), in `S.stat.bauamt` die Zahl `kitas`. Alles ist Pflicht: Fehlt `p.kita` oder `g.soll`, heißt es „Spielstand
unvollständig“; fehlt eine Summe, „Spielstand beschädigt: Regierungs-Statistik“; `bauamt.kitas` muss eine ganze Zahl ab 0 sein
(„… Bauamt“), `soll` höchstens 5 bei einer Kita und sonst 0 („… Kita-Stellen“), und jeder Kita-Platz eines lebenden Kindes muss in
einer Kita liegen („… Kita-Platz“). Ein Stand der Version 5 geht über „Stadt übernehmen“ wie bisher auf 6; dazu setzt die Übernahme die
Kita-Summen und `bauamt.kitas` auf 0, die Zeile im Stadtbuch nennt die Kitas und die Frist, der Versionsdialog sagt „… und die Stadt baut
Kitas“. Versionen 2 bis 4 laufen über dieselbe Kette. Ein Stand der Zwischenfassung ohne Kitas (Version 6 ohne `p.kita`) gilt als
unvollständig. Der Teststand für `tests/t1_xss.cjs` ist neu erzeugt (`tests/basis_v6.json`, Version 5 über „Stadt übernehmen“, Tag 420).
`--speichertest` läuft bitgleich; Fingerabdruck `a23e00a5306658b3` (Seed 1, gespeichert an Tag 150 um 13 Uhr, 60 Tage weiter 261
Einwohner; nach der zweiten Gegenprüfung, mit `kitaAb` und dem Grund in der Stadtbuch-Zeile „Kein Kita-Platz frei“; ohne den Grund
`0b9eb10c476998bc`, bei gleichem Verlauf; vorher `19f490070fdf9352` bei 219, vor den Kitas `c0b355a809870ef1` bei 170 Einwohnern,
kein Sollwert). Spielstand bei Seed 1, Tag 150: 0,21 MB.

**Gemessen** (je 730 Tage stündlich, Gates wie `--gate` ohne T; `mess/mess2.mjs` und `mess/mess3.mjs`):

| Seeds | Stand | alle Gates | Gate 4 | Band Ø / Median / höchstens | Gate 7: kleinster Abstand, fällt | Einwohner Tag 365 Ø (kleinster) |
|---|---|---|---|---|---|---|
| 1–80 | Kern | 77 von 80 | 77 (fällt: 19, 27, 44) | 1,077 / 1,069 / 1,201 | 15,7, nie | 875 (562) |
| 1–80 | Mieterkauf und Rente | 76 von 80 | 78 (fällt: 12, 59) | 1,074 / 1,065 / 1,192 | 12,9; fällt: 30, 49 | 862 (693) |
| 1–80 | dazu Kitas | 77 von 80 | 77 (fällt: 21, 48, 62) | 1,073 / 1,069 / 1,241 | 16,3, nie | 887 (789) |
| 1–80 | **nach der zweiten Gegenprüfung (heute)** | **77 von 80** | **77 (fällt: 11, 23, 45)** | **1,077 / 1,073 / 1,155** | **16,5, nie** | **896 (670)** |
| 81–160 | Kern | 75 von 80 | 76 (fällt: 92, 103, 118, 134) | 1,076 / 1,067 / 1,187 | 10,0; fällt: 81 | 874 (762) |
| 81–160 | Mieterkauf und Rente | 74 von 80 | 76 (fällt: 87, 120, 141, 145) | 1,074 / 1,068 / 1,212 | 11,4; fällt: 97, 130 | 876 (691) |
| 81–160 | dazu Kitas | 77 von 80 | 77 (fällt: 88, 112, 136) | 1,073 / 1,069 / 1,164 | 15,3, nie | 900 (793) |
| 81–160 | **nach der zweiten Gegenprüfung (heute)** | **76 von 80** | **77 (fällt: 112, 130, 140)** | **1,075 / 1,065 / 1,185** | **13,9; fällt: 108** | **891 (792)** |

Weitere Werte (Seeds 1–80, Mittel, ohne Kitas in Klammern): Einwohner an Tag 730 1.110 (1.085), Geburten 528 (518), Zuzüge 1.025
(1.001), Wegzüge 40 (40), ohne Arbeit an Tag 730 5,1 % (5,1 %), Budget an Tag 730 3,01 Mio. (3,76 Mio.; die Kitas kosten in 730 Tagen
etwa 0,81 Mio.), kleinstes Budget 5.645 (6.432), Erspartes je Erwachsenem 13.068 (12.960), Zufriedenheit 70,9 (70,8), Tech-Gründungen
24,4 (22,9), Lohnsteuer 1.847 (1.803), Rentenkasse 9.963 (9.760) und Betreuungsgehalt 451 (502) Taler am Tag, Haushalte mit
Betreuungsgehalt 4,8 (5,4), Stadtbuch 4,45 Zeilen am Tag (4,28). Die Stadt wird etwas größer; warum, ist nicht getrennt gemessen.
Gate 7 fiel mit den Kitas auf keinem der 160 Seeds (vorher auf 4), Gate 4 liegt weiter im Rauschen der Zuzug-Regel (Placebo 77 von 80,
„Bekannte Schwächen“). Kein Urteil über das Programm: Die Betreuungspflicht, die Schlüssel, die Kosten und das Verhalten der Eltern sind
Annahmen der Stadt, und die Finanzierung der Leistungen von außen bildet sie nicht ab.

Nach der zweiten Gegenprüfung (Plätze nur mit Personal, Kita-Lohn, Bestand, Frist; `mess/bef_*.txt`) bestehen 153 von 160 Seeds alle Gates
(vorher 154, im Kern 152). Gate 4 fällt auf 11, 23 und 45 knapp (1,155, 1,154, 1,151), auf 112, 130 und 140; Gate 7 fällt auf Seed 108
(Abstand 13,9, n = 17). Einzelne Seeds kippen in beide Richtungen, wie bei jeder Änderung an Geld und Entscheidungen; die Ursache ist nicht
getrennt gemessen. Weitere Werte (Seeds 1–80, Mittel, Stand davor in Klammern): Einwohner an Tag 730 1.110 (1.110), Geburten 531 (528),
Zuzüge 1.028 (1.025), Wegzüge 40 (40), ohne Arbeit an Tag 730 4,7 % (5,1 %), Budget an Tag 730 2,97 Mio. (3,01 Mio.), kleinstes Budget
5.645 (5.645), Erspartes je Erwachsenem 12.946 (13.068), Zufriedenheit 70,9 (70,9), Tech-Gründungen 24,5 (24,4), Lohnsteuer 1.866
(1.847), Rentenkasse 10.062 (9.963) und Betreuungsgehalt 398 (451) Taler am Tag, Haushalte mit Betreuungsgehalt 4,3 (4,8),
Stadtbuch 4,45 Zeilen am Tag (4,45).

`--gate` (Seeds 1, 2, 3, je 730 Tage) besteht; Stand nach der zweiten Gegenprüfung, in Klammern der Stand mit Kitas davor:

| Gate | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| 1 Einwohner an Tag 365 | 886 (874) | 858 (929) | 944 (938) |
| 2 schlimmster 30-Tage-Einbruch | 2,5 % (2,3 %) | 2,3 % (3,7 %) | 4,5 % (2,4 %) |
| 3 kleinstes Budget | 6.731 (6.731) | 6.743 (6.743) | 6.538 (6.538) |
| 4 Band Tag 551–730, Abstand zur Baugrenze | 1,06, 24 (1,05, 24) | 1,08, 12 (1,06, 24) | 1,11, 24 (1,07, 20) |
| 5 Gründungen bis Tag 365 | 204 (211) | 199 (242) | 236 (203) |
| 6 Gründer-Ehrgeiz | +20,8 (+21,2) | +20,0 (+20,5) | +20,0 (+20,6) |
| 7 Wegzieher-Heimatliebe | −29,3, n = 18 (−27,1, n = 13) | −22,9, n = 21 (−24,6, n = 23) | −29,1, n = 12 (−21,6, n = 14) |
| T 365 Tage | 2,0 s | 1,5 s | 1,6 s |
| B Stadtbuch, Zeilen am Tag (davon Bauhof) | 4,25, 0,25 (4,31, 0,26) | 4,33, 0,25 (4,62, 0,28) | 4,78, 0,25 (4,47, 0,26) |
| Lohnsteuer am Tag, Tag 700–730 (alte Regel) | 2.405 (4.280) | 2.534 (4.595) | 2.451 (4.408) |
| von außen am Tag, Tag 700–730: Rentenkasse, Bund | 22.152, 1.221 | 22.810, 801 | 23.694, 632 |
| Kitas an Tag 730: offen, Kinder mit Platz; Stelle aufgegeben bis Tag 730 | 5, 56; 13 (7, 56; 53) | 7, 46; 2 (7, 52; 73) | 9, 46; 16 (8, 62; 81) |

T schwankt mit der Last der Maschine; hintereinander auf derselben Maschine gemessen (`mess/zeit.mjs`, unter Last durch andere
Prozesse) brauchten 365 Tage 2,0 s (1,9 s), 2,1 s (2,1 s) und 2,6 s (2,1 s), etwa so viel mehr, wie die Stadt größer ist.

Befunde der Gegenprüfung des Entwurfs, umgesetzt:
- Spielstände der Version 5 bekamen im Entwurf NaN in den neuen Summen → Version 6 mit Pflichtfeldern und Übernahme, die die Summen
  anlegt; `--migrationstest` lädt Version 5, rechnet 60 Tage, speichert und lädt wieder.
- Kündigungsschock nach einer Übernahme → Übergangsfrist von 30 Tagen mit eigener Zeile im Stadtbuch (Messung oben). Beim Bau zeigte
  sich ein zweiter Schock nach der Frist (im Mittel 7,8 Kündigungen in der ersten Nacht): In dichten Vierteln fand das Bauamt keinen
  Bauplatz, und es plante nur für das erste wartende Kind. Jetzt verteilt es alle Wartenden auf freie Räume, baut leere Läden und
  Werkstätten um, und ohne offene Kita in der Nähe gibt es keine Pflicht; danach 0 Kündigungen in der ersten Nacht (nur auf den neun
  Städten der Seeds 1–3 gemessen; das war zu stark, siehe die Befunde der zweiten Gegenprüfung unten).
- Die Krippenregel ist als Spielvereinfachung und Annahme der Stadt gekennzeichnet, nicht als Programmfolge; der Satz zu § 24 SGB
  VIII ist berichtigt (die Regel ist enger als das Recht). S. 145, 147 und 148 begründen keine Zugangsregel mehr.
- Gebundene Eltern mit Kind unter 3 waren für das Bauamt unsichtbar → Bedarf-Liste (`kitaTag` gibt `bedarf` zurück).
- Die Messung zu S. 152 gibt nur die Verhaltensannahme wieder → so im Fenster und hier beschrieben, mit dem Vergleich ohne
  Wunsch-Bonus.
- Nebenwirkungen genannt (aufgegebene Stellen, Gebundene, Stadtbuch-Zeilen, nur gezählte Haushalte), der Anteil arbeitender Eltern
  über 80 Seeds und gegen den Stand ohne Kitas gemessen; Gates „wie vorher“, nicht „besser“.
- Die Schalter des Prototyps (Pflicht, Kita-Lohn, Baby, Bund, Startalter) gibt es nicht mehr: B0 ist fest eingebaut, die Zahl zum
  Schalter „Bund“ entfällt.
- Das Hin und Her der Krippenplätze ist als Folge von R06 im Fenster genannt und gemessen (oben).
- Gleichstand beim Lohn: „bei Gleichstand der Vorstand“ in Code, Fenster und README gleich; die nur gezählten Haushalte heißen
  „Besitzer oder gemeinnützige Arbeit“; Großeltern und Geschwister zu Hause als Annahme mit ihrer Größe (Tabelle).
- Das Bauamt prüfte nur den Umkreis des ersten Wartenden → alle Wartenden der Reihe nach (oben).
- Die Personenkarte eines gebundenen Elternteils zeigte nur „ohne Arbeit“ → eigener Satz, dazu der Grund im Lebenslauf.
- Die Listen im Fenster sind nachgezogen: Die Kita-Forderung ist nicht mehr „nicht übernommen“; neu in den Listen Vorschule, „Angst
  und Hysterie“, Indoktrination (S. 152, S. 159), Fachaufsichten bei der Grenze, Betriebskindergärten unter „keine Zahl“. Die Datei
  `afd/gesamt.json` außerhalb dieses Ordners ist nicht geändert.

Befunde der zweiten Gegenprüfung (Technik, Texte, Bedienung), jeden selbst nachgeprüft und umgesetzt:
- **Blocker: Pflicht ohne Angebot.** `kitaFrei()` zählte jede offene Kita, auch ohne Personal; eine neue Kita öffnet immer ohne
  Fachkraft, und in der Nacht der Eröffnung mussten Eltern aufhören (nachgeprüft: Seed 4, Tag 7). Jetzt bietet eine Kita nur an, wenn
  sie letzte Nacht Personal hatte; sonst gilt die Stelle der Stadt als „keine Kita mit Plätzen in der Nähe“ (nur gezählt).
- **Personalflucht.** Der Kita-Lohn sank bei voller Besetzung jeden Tag auf 95, die Fachkräfte wechselten zu besser bezahlten Stellen,
  und die Plätze hingen noch in derselben Nacht am Personal. Jetzt sinkt der Lohn nur mit mehr Leuten als Stellen, und je Nacht fallen
  höchstens 8 belegte Einheiten weg (Tabelle oben). Abgänge des Kita-Personals je Stadt in 730 Tagen: 245 statt 441, Kita-Lohn im Mittel 100,1 statt
  97,0 (Seeds 1–20, `mess/wellen4.mjs neu`).
- **Frist und Wellen danach.** Übergangsfrist bis kein Kind mehr wartet (mindestens 30, höchstens 90 Tage) und neue Messung auf 80
  Übernahmen (oben); `--migrationstest` prüft die Nächte nach der Frist gegen eine Schwelle (erste Nacht höchstens 2, die zehn danach
  höchstens 4).
- Die Plätze einer Nacht stehen fest, bevor Eltern aufhören; wer dabei eine Kita-Stelle aufgibt, fehlt ab der nächsten Nacht (so
  dokumentiert, `--kita` prüft die Plätze jetzt auch am Ende der Nacht).
- Übernahme aus Version 2 bis 4: Die Meldung und die Stadtbuch-Zeile nennen jetzt auch Mieterkauf, Renteneintritt, Kitas und die Frist.
  Ein beschädigter Stand der Version 5 (fehlende oder falsche Summe des Kerns) wird abgelehnt statt still mit 0 ergänzt
  (`--migrationstest`: drei Fälle).
- Renteneintritt (Texte): Besitzer können vor 67 nicht in Rente gehen, solange der Betrieb offen ist; wer mit 45 Beitragsjahren die
  Stelle verliert, ist in Rente (Karte R12, Personenkarte, README). Der Eintrag zu S. 25 nennt jetzt auch Betreuungsgehalt und Eltern ohne
  Kita-Platz. Die Kita-Karte nennt die Lohnregel als Annahme (keine Qualifikation in der Stadt), was als Arbeit zählt, den Bestand vor der
  Neuvergabe, kein Betreuungsgehalt und keine Beitragstage für Eltern ohne Kita-Platz mit Kind ab 3, warum die Stadt die Kitas trägt
  (SGB VIII) und den Satz von S. 147 („Familien sollten idealerweise von einem Gehalt leben können und nicht auf eine
  Doppelberufstätigkeit angewiesen sein.“). Im Fenster: Wohneigentum in „Zur Vollständigkeit“, beim Wohngeld ein Halbsatz zum kommunalen
  Wohngeld (S. 37). Versionsdialog: „… und arbeitende Alleinerziehende“; Frist-Zeile: „… und in der Nähe eine Kita Plätze anbietet“.
- Bedienung: „Während du weg warst“ nimmt Kita-Zeilen (Gewicht 5 wie Wegzug); das Kind am letzten Kita-Tag steht auf Karte und Liste
  gleich; Fachkräfte und Bedarf getrennt, Grund bei fehlenden Plätzen, Kita im Bau ohne Stellenzeile; lange Karten mit aufklappbarem
  Teil (am Handy 360 × 740 jetzt höchstens 1.208 px statt 1.809; die längste Karte vorher war 884 px); Versionsdialog mit angehefteter
  Knopfzeile und kürzerem Text (Hauptknopf bei 360 × 740, 568 × 320, 844 × 390 und 1280 × 800 im Bild, Textanfang sichtbar); Tag-0-Zeile
  kürzer; Tausenderpunkt in den Texten des Mieterkaufs („Kaufpreis je Wohnung 3.200 Taler“); „Beitragsjahre: 46 (45 nötig)“ statt
  „46 von 45“; Live-Zeile „18 Fachkräfte (Bedarf 16)“ und „Haushaltstage ohne Kita-Angebot“. Die Zeile „Kein Kita-Platz frei: …“ nennt
  den Grund („Die Kita … ist voll.“ bzw. „… ist voll, sie hat nur 1 Fachkraft.“), wie die Bedienungsprüfung vorschlug.
- Nachprüfung auf dem Endstand (Skripte der Gegenprüfung und `mess/nach/`): Stellenaufgaben, bei denen keine Kita in Reichweite
  Plätze anbot, auf den Seeds 1–10 in 730 Tagen 0 von 93 (vorher auf Seed 4 allein 29 von 116, 14 davon an Kitas, die am selben Tag
  öffneten; `pruefB_technik/mess/leer_kita.mjs`). Die Übernahmen, die die Gegenprüfung nannte (Seed 4 an Tag 300 und 400, Seed 10 an Tag
  300, Seed 12 an Tag 400, Seed 5 an Tag 300, Seed 2 an Tag 400, Seed 11 an Tag 180; dazu Seed 13 und 17 an Tag 300): in der Frist und in
  der ersten Nacht danach niemand, in den 60 Nächten danach zusammen 15 Aufgaben, alle neben einer vollen Kita mit Personal, die größte
  Nacht 4 (Seed 5, Tag 300; `mess/nach/uebernahme_fall.mjs`, `mess/nach/ueb_*.txt`).

Tests: `--kita` (Seeds 1–3, je 400 Tage, nach jeder Nacht und am Ende der Nacht): Plätze nur unter 6 und höchstens 12 Felder weit; je
Kita möglich ≤ min(40, 8 × Personal) und belegt ≤ max(möglich, belegt gestern − 8) (Bestand), Personal und Stellen ≤ 5, Lohn 95–120; Betreuungsgehalt nur mit Kind unter 3 ohne Platz; jedes Kind ohne Platz hat
jemanden zu Hause, sonst nur Besitzer-Eltern oder keine Kita mit Plätzen in der Nähe (je gegen die Zähler der Stadt); Gebundene dürfen um 7 und 18
Uhr nie „Stelle suchen“ oder gründen; Vorrang: kein wartendes Kind der Stufe 1 hinter einem neuen Platz der Stufe 2; höchstens eine
Stadtbuch-Zeile „Kita“ je Nacht; Speichern und Laden mit Kita-Plätzen 20 Tage bitgleich; erzwungen: Elternteil verliert die Stelle →
Platz weg, am nächsten Tag Betreuungsgehalt; Kitas ohne Personal → Kinder ohne Platz, aber niemand muss deshalb aufhören (seit der
zweiten Gegenprüfung; vorher gaben Eltern auf); alle Fachkräfte bis auf eine weg → je Nacht höchstens 8 Einheiten weniger; Besitzer-Eltern
bei vollen Kitas behalten den Betrieb. `--regierung` rechnet die Kita-Löhne in der Lohnsteuer nach und prüft das Betreuungsgehalt nur ohne Platz, `--kitest` die
Anweisung einer gebundenen Hauptfigur, `--migrationstest` Frist, Zeilen und 60 Tage nach der Übernahme, `--gate` druckt die Kitas.
Browser: `tests/kita.cjs` (1280 × 800 und 400 × 820, Teststadt Seed 2, Tag 300: Draw Calls +1, Erzieher auf dem Spielplatz, Klick aufs
Dach, Hauskarte, Kind, gebundener Elternteil, Fenster, Konsole leer; Bilder in `tests/bilder_kita/`), in `tests/alle.sh` aufgenommen.
Angepasst an den neuen Verlauf der Teststadt: `tests/ereignis.cjs` (Tag 447 vier Pleiten, Tag 401 acht Übernahmen, Aufholen bis Tag
607, Fernblick an Tag 698; gesucht mit `mess/momente.mjs`), `tests/p8tech.cjs` (Kamera steiler: Vor der Firma steht jetzt ein Wohnturm,
der flache Blick traf ihn statt des Dachs der Firma), `tests/basis_v6.json` neu erzeugt (oben). Die Hilfe nennt die grüne Kleidung der
Kita. Ergebnis auf dem Endstand nach der zweiten Gegenprüfung (Server auf 8712, `tests/alle.sh`): p3test 12, p5neu 10, p6migration 18,
p7figuren 6, p8tech 14, raute_klick 10 von 10 Klicks, ereignis 21, t1_xss 5, s2karten 22, kita 22 und befunde_s2 22 Prüfungen ohne Fehler;
p4test 25 im Einzellauf, im Gesamtlauf einmal 22: „Anfragen um 7 Uhr“ war 0, und es gab gar keinen Aufruf. Vermutlich ein Wettlauf im
Test: Ob die KI fragt (`S.ki.an`), setzt erst das nächste Bild, der Test rechnete die Stunde 7 aber gleich nach dem Wechsel auf 1×. Der
Test wartet jetzt darauf; danach zweimal 25 (die Ursache ist nicht weiter nachgewiesen). Konsole leer, außer den absichtlichen Verbindungsfehlern
zum KI-Nachbau in p4test. `tests/otest` (befunde 21, handy 11, breit 12, tastatur 4, breiten 20, hilfehoehe ohne Überlauf) ohne Fehler;
otest/befunde fiel vor der Nachprüfung in einem Nachlauf unter Last durch andere Prozesse bei „Karte nach dem Wechsel auf 1280 × 800
aufgeklappt“ (nach 300 ms noch eingeklappt) und bestand im Einzellauf; bei der Abnahme fiel es unter Last noch einmal (vorher
12-mal grün, 2-mal rot). Ursache im Test: Eine Medienabfrage meldet ihre Änderung erst beim nächsten gezeichneten Bild, und unter
Last kommt das später als 300 ms. Die Seite klappt die Karte bei diesem Ereignis auf, das ist richtig. Der Test wartet jetzt nach der
Zeit noch auf zwei Bilder (`requestAnimationFrame`) und war danach im Lauf unter Last grün (21 Prüfungen). Geht ein Fenster innerhalb
eines einzigen Bildes auf breit und wieder zurück, meldet die Abfrage nichts, und die Karte bleibt, wie sie war. Dazu `tests/pruef_v5.cjs` (Kopie aus der Technikprüfung): echter
Stand der Version 5 (Seed 5, Tag 400, 937 Einwohner), Versionsdialog, übernehmen, 45 Tage ohne Stellenaufgabe, Fenster ohne NaN,
Karten, Neuladen als Version 6, Import als Datei, Konsole leer. Die Kennzahlen sind nicht höher geworden
(`tests/kennzahlen_hoehe.cjs`: 156 bis 158 px bei 568 × 320 bis 844 × 390, 216 px bei 926 × 428, 211 px bei 400 × 820, wie
`stadt.orig.html`). Bilder: `nachher/` (Teststadt Seed 2, Tag 400: 935 Einwohner, 25 bis 28 Draw Calls, 44.400 bis 45.400 Dreiecke;
vor der zweiten Gegenprüfung 994 Einwohner, 24 bis 27 Draw Calls, etwa 49.000 Dreiecke) und `gross/` (`&umland=300000`, Seed 2, Tag
750: 5.928 Einwohner, 24 bis 27 Draw Calls, 140.000 bis 146.000 Dreiecke; vorher 5.986 Einwohner, 134.000 bis 140.000 Dreiecke; vor den
Kitas 5.694 Einwohner, 24 bis 26 Draw Calls, etwa 124.400 Dreiecke).

## Aufbau

- `stadt.html` enthält den Block `<script id="sim">`: reine Simulation, kein DOM, kein `window`, kein `fetch`,
  kein `Math.random`, keine Uhrzeit. Er legt `globalThis.StadtSim` an. Alle Personendaten liegen als typisierte Arrays
  (eine pro Feld, Index = Personen-ID) in `S.p`, die Gebäude in `S.g`, die Hauptfiguren in `S.ki`.
  Alle Stellschrauben stehen gesammelt im Objekt `R` am Anfang des Blocks.
- Der `<script type="module">`-Block macht Darstellung, Oberfläche, Speichern und die Ollama-Aufrufe. Er ändert den
  Sim-Zustand nur über Funktionen aus `StadtSim` (`stunde`, `tagSchritt`, `hauptSetzen`, `kiSchalten`, `kiEntscheidung`,
  `kiVerwerfen`, `kiGespraech`, `kiTagebuch`, `verlustErledigt`, `importZustand`). `theke`, `traeger`, `bauGesamt` und `regierungInfo` lesen nur.
  `StadtSim._pruef` (Ereignisse gezielt auslösen: sterben, wegziehen, zusammenziehen, kündigen, umziehen) ist nur für
  `tools/simtest.mjs --regierung` da; die Oberfläche benutzt es nicht. Einzige Ausnahme ist die Testhilfe
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
node tools/simtest.mjs --regierung             # Stadtregierung: Lohnsteuer, Rentenkasse, Betreuungsgehalt, Grundsicherung und
                                               #   gemeinnützige Arbeit (erzwungen, auch Bauhof voll und mit Kleinkind), Prämie,
                                               #   Wohnungsvorbehalt, „gestern“, Speicherformat; Schritt 2: Beitragstage,
                                               #   Renteneintritt, Rentner-Freibetrag, Mieterkauf (erzwungen), Kita-Löhne in der
                                               #   Lohnsteuer, Betreuungsgehalt nur ohne Kita-Platz (Seeds 1–3)
node tools/simtest.mjs --kita                  # Kitas: Plätze (auch am Ende der Nacht), Bestand, Personal, Lohn, Vorrang,
                                               #   Betreuungspflicht, Gebundene, Stadtbuch, Speichern; erzwungen: Kitas ohne Personal
                                               #   verlangen nichts, Personalabgang (höchstens 8 Einheiten je Nacht), Elternteil ohne
                                               #   Stelle, Besitzer-Eltern bei vollen Kitas (Seeds 1–3)
node tools/simtest.mjs --migrationstest        # Spielstände von Version 2, 3, 4 und 5 übernehmen (alte Dateien aus git 39c405b,
                                               #   2b821c2, 1c8d40b und 414ebab), 60 Tage weiter, Kita-Übergangsfrist und die
                                               #   Nächte danach (Schwelle), beschädigte Stände der Version 5; --git <ordner>: anderes Repository
node tools/simtest.mjs --migrationstest --alt <alte stadt.html>   # nur diese alte Datei
```

Weitere Schalter für `--seed`: `--alle 60` (Zeilenabstand), `--fluss` (Zu-/Wegzüge, Geburten, Tode je Zeile),
`--diag` (Zufriedenheit und Bedürfnisse), `--aktionen` (wie oft jede Aktion gewählt wurde), `--buch 20`
(die letzten Stadtbuch-Einträge).

Nur `tools/simtest.mjs` liegt im Repo. Die Browser-Tests, die diese README nennt (`tests/…`, `tests/otest/…`, Playwright mit
Chromium), und die Messskripte (`mess/…`) liegen im Arbeitsordner der Sitzung, in der gebaut wurde: Sie hängen an festen Pfaden
dieser Umgebung (Three.js aus einer lokalen Kopie, KI-Nachbau auf Port 11434) und sind deshalb nicht eingecheckt. Ihre Ergebnisse
stehen hier als Bericht, nachprüfbar im Repo ist nur `simtest`.

## Annahmen — Stellen, an denen die Spec nichts festlegt

| # | Annahme | Warum |
|---|---|---|
| 1 | Alles liegt in `stadt/`, nicht im Repo-Wurzelordner | Das Repo enthält schon das Blitzer-Projekt |
| 2 | 1 Lebensjahr = 10 Spieltage | Ohne Raffung würde in zwei Spieljahren niemand erwachsen, es gäbe keine Enkel (Phase-3-Gate) |
| 3 | Rente ab 67 oder nach 45 Beitragsjahren (Schritt 2), von außen aus der Rentenkasse, immer voll: 55 Taler am Tag, in zwei Stufen 66 (vorher 50/Tag aus dem Budget, solange es reichte). Bis Schritt 2 endete mit 67 die Anstellung; seitdem entscheidet jeder Angestellte selbst, wann er aufhört (Ruhestandswunsch, Abschnitt Stadtregierung). Wer einen eigenen Betrieb hat, kann ihn nicht aufgeben und bekommt vor 67 Rente nur, wenn der Betrieb schließt; wer mit 45 Beitragsjahren die Stelle verliert, ist in Rente | Die Spec nennt nur „job_suchen: 18–67“; das gilt weiter. Die feste Grenze kam, weil ohne sie die Bevölkerungswelle getestet größer wurde; sie fällt als Modellkorrektur der Stadt, weil das Programm freiwillig längeres Arbeiten und Rentner im Arbeitsmarkt will (S. 18, S. 15, S. 20). Die Rentenkasse ist eine Modellkorrektur, keine Forderung des Programms |
| 4 | Die Stadt besitzt die Wohnhäuser, Miete geht ins Budget. Budget = Lohnsteuer + Miete. Lohnsteuer seit der Stadtregierung: 10 % vom Lohn über 29 Taler Freibetrag je Familienmitglied (Familiensplitting); Gewinne der Besitzer bleiben steuerfrei. Renten, Prämien, Betreuungsgehalt und Grundsicherung zahlt nicht das Budget | Die Spec sagt „Miete raus“, aber nicht wohin. **Weicht vom Wortlaut der Spec ab** („fester Anteil vom Lohn“): Entscheidung des Nutzers, Abschnitt Stadtregierung |
| 5 | Werkstätten verkaufen ans Umland. Erlös je Arbeitstag = min(140, 50.000 / alle Werkstatt-Arbeitenden) | Einzige Geldquelle von außen und als Wachstumsgrenze gedacht (siehe „Bekannte Schwächen“) |
| 6 | Läden haben eine Kapazität: 5 Leute je Stelle (Besitzer zählt mit), also 35 pro Laden. Ist der Laden voll, geht man zum nächsten mit Platz in Reichweite. Der Laden kauft Ware ein: eine Kiste je 38 Taler Umsatz (Annahme 59; bis zur Arbeit-Erweiterung pauschal die Hälfte des Umsatzes nach außen) | Sonst schluckt ein Laden in der Mitte die ganze Stadt. Ohne Wareneinsatz entsteht pro Kopf eine halbe Ladenstelle, und die Stadt schaukelt sich auf (siehe Schwächen) |
| 7 | Stammladen: Man bleibt beim Laden, solange er offen, in Reichweite und nicht voll ist. Den nächstgelegenen sucht man beim ersten Einkauf oder wenn der eigene wegfällt | Weicht vom Wortlaut „Einkauf beim nächsten Laden“ ab. Ohne das nimmt jeder neue Laden dem Nachbarn sofort die Kundschaft weg |
| 8 | Wer Erspartes hat, gibt täglich bis 1 % davon (höchstens 15) zusätzlich aus, Sparsame weniger | Sonst sammelt sich das Geld bei den Leuten, und die Läden bekommen nichts ab |
| 9 | Besitzer zahlen Lohn nach Charakter: wenig sparsam = großzügiger (90–110 % vom Grundlohn) | Gibt `job_wechseln` einen Grund |
| 10 | Pleite-Betriebe stehen leer und können übernommen werden (40 % der Baukosten). Eine Übernahme zählt als Gründung | Die Spec sagt „Gebäude wird frei“ |
| 11 | Zuzug: Als „freie Stellen“ zählen nur freie Stellen in Werkstätten und Tech-Firmen (nicht im Bauhof, nicht in Läden, seit Schritt 2 nicht in Kitas), abzüglich der Arbeitslosen der Stadt. Wer zuzieht, tritt sofort die nächste solche Stelle an; ist keine mehr frei, kommt an diesem Tag niemand mehr. Zuzügler sind 18–60 Jahre alt (bis zur Gate-4-Änderung 18–45). Höchstens 1 + 1 % der Einwohner pro Tag | **Weicht vom Wortlaut der Spec ab** („freie Stellen“); Noahs Entscheidung für Gate 4. Zählten Ladenstellen, holte jeder neue Laden Leute von außen, die wieder neue Läden brauchen: Ladenboom, danach Pleitewelle. Läden stellen deshalb nur Leute aus der Stadt ein. Mit 18–45 ging die erste Generation fast gleichzeitig in Rente. Arbeitslose abziehen: sonst ziehen Leute für Stellen zu, die Einheimische ohnehin gleich nehmen. Seit der Stadtregierung zählen Leute in gemeinnütziger Arbeit als arbeitslos, Eltern mit Betreuungsgehalt nicht, seit den Kitas auch Eltern nicht, die ohne Kita-Platz keine Stelle antreten können; die Stadtregierung weist die Regel als R10 aus (galt schon), dazu R09 |
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
| 23 | Bauamt: Regel 1 baut höchstens 1 + Einwohner/300 Häuser pro Tag. Park nur in Vierteln mit ≥ 8 Bewohnern und weniger als 1 + Bewohner/60 Parks. Die Notbremse (Regel 5, vorher höchstens alle 14 Tage) entfällt seit der Stadtregierung | Die Spec sagt „einmal pro Spieltag“, aber nicht wie viel. **Weicht vom Wortlaut der Spec ab** (Regel 5): Entscheidung des Nutzers, Auslegung von S. 13 des Programms (R08). Auf den Seeds 1–160 hat die Notbremse auch vorher nie ausgelöst |
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
| 41 | Spielstand-Version 6 (2: Hauptfiguren und Tagebuch, 3: Bauhof und Kisten, 4: Tech-Firmen, 5: Stadtregierung mit den Personenfeldern `gsTage` und `gemein`, `S.regierung` mit Start und Tageswerten `gestern`/`tagStart`, und `S.stat.regierung`; 6: Schritt 2 mit den Personenfeldern `eigen`, `kaufPreis`, `schuld`, `beitrag` und `kita`, dem Gebäudefeld `soll`, `S.regierung.schritt2` und `kitaAb` und der Zahl `S.stat.bauamt.kitas`). Stände anderer Versionen lösen den Versionsdialog aus; Version 2 bis 5 lassen sich übernehmen (Annahme 60). Ein Stand der Version 6 ohne die neuen Personen- und Gebäudefelder, ohne gültige Stadtregierung (Start, Schritt 2 und Ende der Kita-Frist als ganze Tage, alle Summen, die vom Tagesende und die von gestern als Zahlen, gestern auch leer), mit Wohneigentum, das es so nicht gibt, oder mit Kita-Plätzen und -Stellen, die es so nicht gibt, wird abgelehnt | Neue Felder. Ein Stand der Version 4 liefe sonst still unter den neuen Regeln weiter; ohne die Prüfung stürzte ein beschädigter Stand um Mitternacht ab |
| 42 | Bei 1× ist eine echte Minute eine Spielstunde | Folgt aus der Spec: 90 Spieltage entsprechen 36 Stunden Abwesenheit |
| 43 | Beim Aufholen (Tagesschritte) entscheiden alle nur um 7 und 18 Uhr; Ereignisse lösen keine zusätzliche Entscheidung aus. Der Bauhof teilt direkt nach der 7-Uhr-Entscheidung ein, wie stündlich | Sonst wäre der Tagesschritt nicht schneller. Abweichung gegen stündlich nach 90 Tagen (Tag 200–290) mit der Stadtregierung: Seeds 1–10 im Mittel −0,3 % Einwohner, einzeln −17,2 % bis +10,7 %; Seeds 1–20 im Mittel +0,2 %, 10 von 20 höher. Vorher auf den Seeds 1–10 +0,7 %, einzeln −5,8 % bis +10,8 % (vor der Zuzug-Regel −1,7 %, einzeln −8,6 % bis +8,1 %). Der Ausreißer Seed 10 wächst in diesen Tagen stark (stündlich 246 → 623 Einwohner); in Tagesschritten kamen weniger Geburten (90 statt 120) und weniger Zuzüge, der Unterschied wächst von Tag zu Tag. Nicht einseitig: Vorher lag derselbe Seed 10,8 % darüber |
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
| 60 | Ein Spielstand von Version 2, 3, 4 oder 5 lässt sich im Versionsdialog mit „Stadt übernehmen“ umrechnen (Text je Version). Von 5: Schritt 2 gilt ab dem Übernahmetag, niemand besitzt schon eine Wohnung, Beitragsjahre für alle aus dem Alter, Summen und „gestern“ der Stadtregierung bleiben (fehlt dort eine Summe, wird der Stand abgelehnt), Kitas mit Übergangsfrist. Von 2: Bauhof = Werkstatt der Stadt vom Start, laufende Baustellen bekommen 4 Arbeitstage je Resttag (höchstens so viele wie der ganze Bau). Von 3: Tech-Firmen entstehen danach von selbst, niemand hat schon ein Gerät. Von 2, 3 und 4: Die Stadtregierung mit Schritt 2 gilt ab dem Übernahmetag (Rentenstufen von da an, Stadtbuch „Ab heute regiert die AfD …“ mit Mieterkauf, Rente, Kitas und Frist, im Fenster „seit Tag X, Spielstand übernommen“), niemand bezieht schon Grundsicherung. Alles andere bleibt. Ein Import einer alten Datei rechnet ohne Nachfrage um | **Abweichung von der Spec** (dort nur Export oder Neu), Noahs Entscheidung B: sonst wäre seine Stadt weg |
| 61 | Theke und Träger sind nur zum Anschauen. Wer heute trägt, ergibt sich aus Tag und Laden (reihum), nicht aus Zufall. Der Lieferant ist die Werkstatt, die gestern die meisten Kisten brachte | Die Kisten werden um Mitternacht in einem Schritt verteilt; die Träger zeigen das tagsüber |
| 62 | Die 120 Arbeitsplätze unter den Figuren werden um 8 Uhr nach Nähe zur Kamera vergeben (beim Öffnen mitten am Tag sofort) und bleiben bis zum nächsten Morgen | Alle Arbeitenden wären bei 5.000 Einwohnern über 2.000 Figuren. Fest statt kameraabhängig, damit keine Figur beim Drehen springt |
| 63 | Stadtbuch: fertige Bauten eines Abends in einer Zeile („Der Bauhof hat fertig gebaut: …“), Stillstand, wenn auf einer Baustelle 5 Tage niemand war, und wenn der Bauhof-Lohn über 100, 110 oder 120 steigt | Mit Tech-Firmen kamen die neuen Versionen dazu (damals im Schnitt 0,48 Zeilen am Tag: auf 40 Seeds 5,50 Zeilen am Tag, 7 Seeds über 6,5, höchstens 8,60; das war vor der Zuzug-Regel). Heute gemessen (Seeds 1–80, 730 Tage): vor der Stadtregierung 4,11 Zeilen am Tag (höchstens 5,47), davon Bauhof 0,24 und Tech 0,50; mit der Stadtregierung 4,31 (höchstens 5,80), Bauhof 0,25, Tech 0,55. Die Stadtregierung schreibt selbst 3 Zeilen je Stadt (Tag 0 und die beiden Rentenstufen), den Rest macht die größere Stadt. Die Plan-Grenze von 6,5 Zeilen am Tag hält auf allen 160 Seeds |
| 64 | Tech-Firma statt Werkstatt gründet, wer Fleiß + Ehrgeiz ≥ 120 hat, solange die Tech-Stellen danach höchstens 40 % der Umland-Stellen sind (Werkstätten plus Tech) und das Geld reicht (Bau 2.000 + Startkasse 300, leere Tech-Firma übernehmen 1.100). Fehlt ein Laden, wird wie bisher ein Laden gegründet. Ob es sich lohnt, prüft wie bei der Werkstatt der Umlandpreis; die Tech-Stellen zählen dort mit. Produkt: das in der Stadt seltenste. Firmenname aus 30 Marken (Seed-Zufall), Versionen heißen „Marke Nummer“ | Noahs Entscheidung: eine Betriebsart über die vorhandene Aktion, keine neue Aktion. Ohne Obergrenze würden Tech-Firmen die Werkstätten verdrängen (beide teilen sich das Umland). Gemessen (Seeds 1–80, Tag 730): vor der Stadtregierung 23,9 Gründungen je Stadt, Anteil an den Umland-Stellen im Mittel 25,0 % (höchstens 39 %); mit der Stadtregierung 27,4 und 29,3 % (höchstens 39,6 %), weil mehr Leute genug Erspartes haben. Seeds 1/2/3 (`--gate`): 29/46/21 gegründet, Anteil 33,8/33,8/23,4 % (vorher 17/26/26 und 21,6/27,5/25,1 %) |
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
| dazu Zuzug nur für Werkstatt- und Tech-Stellen (bis zur Stadtregierung) | 76 von 80 | 1,076 | 1,07 | 0 | 1,21 |
| Placebo dazu: plus eine Zufallszahl am Tag | 77 von 80 | 1,070 | 1,06 | 0 | 1,17 |
| dasselbe auf frischen Seeds 81–160 | 79 von 80 | 1,074 | 1,06 | 0 | 1,15 |
| Tech-Firmen ohne Zuzug-Regel auf den Seeds 81–160 | 22 von 80 | 1,308 | 1,23 | 11 | 2,62 |
| dazu Stadtregierung | 77 von 80 | 1,077 | 1,07 | 0 | 1,20 |
| Stadtregierung auf den Seeds 81–160 | 76 von 80 | 1,076 | 1,07 | 0 | 1,19 |
| dazu Mieterkauf und Renteneintritt (Schritt 2) | 78 von 80 | 1,074 | 1,07 | 0 | 1,19 |
| dazu Kitas | 77 von 80 | 1,073 | 1,07 | 0 | 1,24 |
| Kitas auf den Seeds 81–160 | 77 von 80 | 1,073 | 1,07 | 0 | 1,16 |
| **nach der zweiten Gegenprüfung von Schritt 2 (heute)** | **77 von 80** | **1,077** | **1,07** | **0** | **1,155** |
| dasselbe auf den Seeds 81–160 | 77 von 80 | 1,075 | 1,07 | 0 | 1,19 |

Mit der Stadtregierung fällt Gate 4 auf den Seeds 1–80 auf 19, 27 und 44 durch (vorher 19, 27, 37, 65), auf den Seeds 81–160
auf 92, 103, 118 und 134 (vorher 87). Das liegt im Rauschen der Zuzug-Regel (das Placebo ändert 1 von 80): Jede Änderung an
Geld und Entscheidungen verschiebt, welche Seeds zufällig kippen. Kein Urteil über das Programm (Abschnitt Stadtregierung).

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
Läden, Bauhof und seit Schritt 2 Kitas. Für den Zuzug zählen nur Werkstätten und Tech-Firmen (Annahme 11). An Tag 730 zeigt das Panel im Median
121 freie Stellen (vorher 5), davon sind nur 12 in Werkstätten und Tech-Firmen. Wer das Panel liest, erwartet Zuzug, der nicht
kommt. Die Anzeige ist unverändert.

**Läden sind meist unterbesetzt.** An Tag 365 und 730 sind im Mittel 32 % und 33 % der Ladenstellen besetzt (vorher 99 %
und 95 %), weil Zuzügler nur in Werkstätten und Tech-Firmen anfangen. Ein Laden bedient trotzdem seine volle Kundschaft, denn
die Kapazität hängt an den Stellen, nicht an den Leuten (Annahme 6). Er spart nur Löhne. Das ist unrealistisch: Ein Laden mit
zwei von sechs Kräften bedient so viele Leute wie ein voller.

**Gate 7 ist knapp.** Es zählt nur die Leute, die bis Tag 365 wegziehen (auf Seed 1 sind es 17). Mit der Zuzug-Regel fiel
Gate 7 im Placebo auf 5 von 160 Seeds durch, ohne sie in den Seeds 81–160 auf 2 von 80. Auf den Seeds 1–160 ohne Placebo
fiel es vor der Stadtregierung nicht durch; mit ihr fällt es auf Seed 81 durch (11 Wegzüge, nur 10 Punkte weniger Heimatliebe
als alle; vorher 21,6), sonst ist der kleinste Abstand 15,7. Seit Schritt 2 fiel es auf 4 von 160 Seeds (30, 49, 97, 130; kleinster
Abstand 11,4), Seed 81 bestand (Abschnitt Stadtregierung, Schritt 2). Mit den Kitas fiel es auf keinem der 160 Seeds (kleinster Abstand
15,3); ein Grund dafür ist nicht getrennt gemessen, einzelne Seeds kippen hier wie bei Gate 4 in beide Richtungen. Nach der zweiten
Gegenprüfung fällt es auf Seed 108 (Abstand 13,9, n = 17), sonst ist der kleinste Abstand 16,3.

**Die Kisten machen nichts knapp.** Die Werkstätten machen etwa fünfmal so viele Kisten, wie die Läden brauchen: Auf den
Seeds 1–3 gingen von Tag 100 bis 300 je 21–22 % der Kisten an Läden der Stadt, die Läden bekamen 100 % ihrer Kisten aus der
Stadt, der Rest ging ans Umland. Eine Werkstatt nimmt dasselbe ein, ob ein Laden ihre Kisten nimmt oder nicht. Im Ergebnis
zahlen Läden etwa 42–43 statt 50 % ihres Umsatzes für Ware (Kistenpreis Tag 100–730 im Schnitt 16,0–16,4 Taler, Seeds 1–3). Echte Knappheit (Umland kauft weniger) war im Entwurf getestet und
ist verworfen (Annahme 59).

**Tech-Firmen kommen in einer ausgewachsenen Stadt nur langsam.** Sie teilen sich das Umland mit den Werkstätten und werden
nur gegründet, wenn dort Platz ist. Im Entwurf gab es nach dem Übernehmen einer Stadt von Tag 300 bzw. 400 in den 60 Tagen
danach keine Gründung, bei Tag 150 drei. In einer neuen Stadt entstehen auf den Seeds 1–3 in 730 Tagen 21–46 Tech-Firmen (vor
der Stadtregierung 17–26: mit mehr Erspartem gründen mehr Leute).

**Die echten Code-Stücke sind nur mit einem nachgebauten Ollama getestet.** Ob ein kleines Modell zuverlässig gültiges JSON mit
Code liefert (oder Code-Zäune und Erklärungen dazuschreibt), ist nicht gemessen. Ungültige Antworten zählen als ungültig und
landen nicht im Tagebuch.

**Viele Handys.** Auf den Seeds 1–3 haben an Tag 730 93–94 % der Erwachsenen ein Gerät; unterwegs leuchten deshalb bis zu 80 Handys.

**Das Budget ist nie knapp.** Ab etwa Tag 60 übersteigen Steuern und Mieten alle Ausgaben um ein Vielfaches. Die
Budgetgrenzen des Bauamts greifen deshalb praktisch nie. Gate 3 hält, weil jede Ausgabe vorher geprüft wird, nicht weil
das Budget eng wäre. Seit der Stadtregierung zahlt die Stadt keine Renten mehr (sie kommen aus der Rentenkasse), bekommt aber
weniger Lohnsteuer: An Tag 730 hat sie im Mittel 5,75 statt 2,15 Mio. Taler (Seeds 1–80), seit dem Mieterkauf 3,76 Mio. (abbezahlte
Eigentümer zahlen keine Miete, Rückkäufe bei Tod oder Wegzug gehen aus der Stadt), mit den Kitas 2,97 Mio. (sie kosten die Stadt im
Mittel 1.201 Taler am Tag, in 730 Tagen etwa 0,88 Mio.; das kleinste Budget ist 5.645, in den ersten Tagen). Das zeigt nur, wer zahlt,
nicht was die Stadt sich leisten kann.

**Geld von außen ohne Gegenfinanzierung.** Rentenkasse und Bund zahlen im Mittel knapp 10.800 Taler am Tag in die Stadt
(Seeds 1–80, heute: Rentenkasse 10.062, Bund 679; im Kern 8.316 und 775), die Stadt zahlt dafür keine Beiträge und keine
Bundessteuern. Mehr Erspartes (heute 12.946, im Kern 11.902, vorher 10.525 je Erwachsenem), höhere Zufriedenheit (70,9; 70,3; 68,8)
und mehr Tech-Gründungen kommen zum großen Teil daher. Das
Fenster „Stadtregierung“ und die Zeile „Von außen“ sagen das; die Stadt bildet die Kostenseite des Programms (etwa steigende
Rentenbeiträge, S. 19) nicht ab.

**Mehr Leute ohne Arbeit.** An Tag 730 sind im Mittel 4,7 % ohne Arbeit (im Kern 5,1 %, vorher 3,8 %). Eltern in Elternzeit zählen
nicht mit; der Zuzug besetzt ihre Stellen, und wenn das Kind 3 ist, suchen sie neu. Ebenso Eltern, die ohne Kita-Platz zu Hause bleiben
müssen (gebunden, im Mittel 0,02 Personen am Tag, Tag 366–730), und wer vor 67 in Rente ist.

**Gemeinnützige Arbeit kommt fast nie vor.** Auf den Seeds 1–160 hat nie jemand 5 Tage in Folge Grundsicherung bezogen: Läden
suchen fast immer Leute, und wer Arbeit sucht, findet sofort eine. Grundsicherung gab es im Mittel für 0,07 Leute am Tag. Nur
in übernommenen Städten der Version 2 mit vielen Arbeitslosen kam gemeinnützige Arbeit vor (`--migrationstest`). Deshalb prüft
`--regierung` sie erzwungen.

**Handy quer (bis 420 px hoch): Stadtregierung nur als Symbol.** Mit der Zeile „Von außen“ und dem Knopf reichten die Zahlen
sonst in die Spalte darunter (gemessen bis 37 px bei 680 × 345; dort ließ sich der Knopf nicht antippen). Bis 420 px Höhe steht
der Knopf deshalb als Symbol (Rathaus, 32 × 32 px) neben Tag und Uhr, sein Name steht im aria-label, und die Zeilen sind etwas
enger. Die Marke am Stadtbuch zeigt in der schmalen Spalte nur die Zahl („99+“, „neu“ nur für Screenreader), zweizeilig schob sie
die Spalte in die Zahlen. Gemessen (Luft zwischen Zahlen und Spalte, mit der Marke „99+“): 568 × 320 9 px, 700 × 330 17 px,
680 × 345 21 px, 740 × 360 35 px, 844 × 390 63 px, 926 × 428 (volle Zeilen) 42 px; der Tipp auf die Mitte des Knopfs öffnet das
Fenster in allen 13 gemessenen Größen. Am Handy hochkant heißen Zeile und Knopf kürzer („Von außen“, „Stadtregierung: AfD“);
„gestern“ und „seit Tag …“ stehen im Fenster.

**Phase 4 ist nicht mit einem echten Sprachmodell getestet.** Im Container gibt es kein Ollama und keinen Download dafür.
Getestet ist gegen einen nachgebauten Server mit dem Request- und Antwortformat aus der Ollama-Doku: Anfragen, Fristen,
ungültige und kaputte Antworten, Zeitüberschreitung, Ollama aus, 20×, Gespräche, Tagebuch nach dem Aufholen. Offen sind
genau die Gate-Punkte, die ein echtes Modell brauchen: Anteil gültiger Antworten über 7 Spieltage, Dauer pro Antwort
(entscheidet, ob mehr als 5 Hauptfiguren gehen), und ob zwei verschiedene Charaktere erkennbar anders handeln.

**Frame-Zeit mit und ohne KI** (gegen den nachgebauten Server, im Wechsel gemessen, 3 Runden, mit Bauhof, Kisten und
Figuren bei der Arbeit): JavaScript pro Bild 7,5–11,1 ms mit KI und 7,5–8,9 ms ohne (vorher 5,7–9,1 und 7,8–9,2). Ein
Unterschied ist im Messrauschen nicht zu sehen; das Bildtempo begrenzt hier die Software-Grafik.

**60 Bilder pro Sekunde sind nicht gemessen.** Im Container rendert Chromium ohne Grafikkarte (SwiftShader) mit etwa
10 fps. Gemessen sind Draw Calls, Dreiecke und die Rechenzeit pro Bild in JavaScript. Nach der Design-Runde 3: Teststadt
(Seed 2, Tag 400) 22–24 Draw Calls, etwa 42.000 Dreiecke; große Stadt (`?debug&umland=300000&tage=750&seed=2`, 5.894
Einwohner) 23–25 Draw Calls, etwa 137.000 Dreiecke (nach Runde 1: 165.000–172.000, davor 102.742), 5–12 ms JavaScript pro
Bild, Konsole leer. Die Spec verlangt unter 100 Draw Calls; für Dreiecke gibt sie keine Grenze.

**Fensterreihen mit Alpha-to-Coverage sind auf echter Grafikhardware ungeprüft.** Seit Runde 2 ist jede Fensterreihe ein
Rechteck je Seite mit einer Textur, die Zwischenräume sind durchsichtig. Mit Kantenglättung (Multisampling) glättet
Alpha-to-Coverage die Kanten; ohne greift ein Alpha-Test. Manche Treiber zeigen Alpha-to-Coverage als feines Punktraster.
Im Container (SwiftShader) sieht es sauber aus.

**Der See liegt im Startblick der kleinen Teststadt außerhalb des Bildes.** In größeren Städten sieht man ihn links hinten.

**Landstraßen beginnen hinter dem Bordstein.** Am Straßenende oder Abzweig läuft der Gehweg der Stadtstraße quer davor; die
Landstraße setzt direkt dahinter an. Die Höfe im Umland liegen meist im Nebel oder hinter den Panels: Im Startblick um 23 Uhr
sieht man in der Teststadt einen, in der großen Stadt zwei.

**Beim Übernehmen sehr alter Stände fehlt ein Stadtbuch-Eintrag.** Das Stadtbuch hält höchstens 500 Einträge (sim-Block).
Holt eine übernommene Stadt sehr viel auf (gemessen: ein Stand von Version 2 mit 221 Einwohnern, 90 Tage aufgeholt), fällt
der Eintrag „Ab heute baut der Bauhof …“ vom Übernahmetag heraus. Die Meldung nach dem Übernehmen sagt dasselbe, sie bleibt.
Bemerkt, weil der Test dafür einen festen Zeitstempel hatte und mit jedem echten Tag mehr aufholte.
