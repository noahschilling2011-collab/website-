# STADT

Eine Stadt, in der jeder Mensch selbst entscheidet. Projektname vorläufig.

**Stand: Phase 4 plus „richtige Arbeit“, Tech-Firmen, Stadtregierung, „Stadt erweitern“ Teil 1 bis 3 und „Tech-Firmen und Autos“ Teil 1 und 2, Simulation und Darstellung, mit den Befunden der Schlussprüfung (Spielstand-Version 8).** Simulation (Phase 0), 3D-Karte mit Tag und Nacht (1), Speichern
und Aufholen (2), laufende Figuren und Personenkarten (3), Hauptfiguren mit Ollama (4). Danach auf Noahs Wunsch: Bauarbeiter
vom Bauhof bauen die Häuser, Werkstätten machen Kisten für die Läden, man sieht die Leute bei der Arbeit, und Bewohner gründen
Tech-Firmen für Software, Handys oder Computer; Hauptfiguren, die dort programmieren, schreiben über Ollama echten Code. Von Anfang
an regiert die AfD nach ihrem Programm zur Bundestagswahl 2025, soweit es sich auf die Stadt übertragen lässt (Abschnitt
„Stadtregierung“); in einem zweiten Schritt kamen der Mieterkauf, der flexible Renteneintritt mit Rentner-Freibetrag und Kitas in Wohnraumnähe dazu.
Seit Version 7 wächst die Karte mit der Stadt: Sie beginnt mit 56 × 56 Feldern und wächst ringsum, bevor eine Straße an den Rand
kommt, die Landschaft rückt mit. Die Stadt hat eine Stufe (Dorf, Kleinstadt, Stadt, Großstadt) und ab der Kleinstadt Stadtteile
mit Namen (Abschnitt „Stadt erweitern“). In Teil 2 kamen Kriminalität, Polizei, Gericht und Gefängnis dazu: Erwachsene können
nachts Diebstahl, Wohnungseinbruch oder Betrug begehen (eine Regel der Stadt, eingestellt auf die Kriminalstatistik 2024); das Land
baut ab der Kleinstadt eine Polizeiwache und ab der Stadt eine Justizvollzugsanstalt für die Region und zahlt die Löhne (Abschnitt
„Sicherheit“). In Teil 3 kamen Militär und Nachrichtendienst dazu, als Einrichtungen des Bundes: ab der Stadt eine Kaserne der
Bundeswehr am Stadtrand mit Soldaten, Zivilbeschäftigten und Wehrpflicht für alle, die 18 werden (Wehr- oder Ersatzdienst), ab der
Großstadt eine Dienststelle des Bundesnachrichtendienstes, die niemanden in der Stadt überwacht (Abschnitt „Bund“). Danach sind die Befunde
der Schlussprüfung (Technik, Texte, Bedienung) und der Nachprüfung umgesetzt (Abschnitte „Befunde der Schlussprüfung“ und „Befunde der
Nachprüfung“). In Version 8 wachsen Tech-Firmen bis zum Campus und zum Hochhaus, große Handy- und Computerfirmen bauen ab der Stadt ein
Autowerk am Stadtrand und ziehen um, und Bewohner kaufen Autos, von Anfang an bei einem Autohaus im Umland und dann auch aus den Werken der
Stadt, und fahren damit zur Arbeit (Abschnitt „Tech-Firmen und Autos (Version 8)“). Im Bild fährt ein Auto rechts, sobald sein Besitzer laut
Simulation mit ihm den Ort wechselt, sonst steht es vor dem Haus, auf dem Werksparkplatz oder in der Garage; Campus und Glas-Hochhaus tragen
Leuchtlogos, das Werk hat Hallen, Showroom, Teststrecke und einen Turm mit Neuwagen, und am Abend einer Eröffnung steht ein ruhiger Lichtkegel
über der Firma. Nach der Schlussprüfung fährt ein Auto im Bild nur noch, wenn sein Besitzer genau diesen Weg damit macht (sonst springt es,
etwa beim Umzug), die Käufer kommen jeden Tag in gemischter Reihenfolge dran, und Karten und Fenster sind nachgezogen (Abschnitt „Befunde der
Schlussprüfung (Version 8)“). Phase 4 ist nur gegen einen nachgebauten Ollama-Server getestet, nicht gegen ein echtes Sprachmodell (siehe „Bekannte Schwächen“).

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
| `?debug&umland=300000&tage=750` | Größere Stadt für den Leistungstest (Seed 2: etwa 5.850 Einwohner, Karte 144 × 144). Dieser Stand wird nicht gespeichert |

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
die Leute gegen ihren Willen aus der Stadt nimmt, gibt es nicht, außer auf Zeit und für alle gleich (seit „Stadt erweitern“ Teil 2):
Haft in einer Anstalt des Landes außerhalb (solange die Anstalt in der Stadt fehlt oder voll ist) und Kinder, die das Jugendamt in
einer Pflegefamilie außerhalb unterbringt. Beide bleiben Bewohner, Wohnung und Haushalt bleiben; wegziehen bleibt die eigene
Entscheidung (wie im Kopftext des Fensters, Befund X3). Keine neue Regel liest Namen, den Einzugstag, die Eltern oder
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

## Stadt erweitern (Version 7)

Noahs Auftrag: „Jz machen wir noch das die statd eigen Militär basen hat Waffen und alles kann Geheimdienst und alles wie in Amerika
so macht und so Gefängnis also kann man die Stadt erweitern“. Auf Rückfrage: Erweitern heißt alles, ausdrücklich „Karte wächst
wirklich“, dazu Stufen und Stadtteile. Das hier ist Teil 1 von 3: Karte, Stufen, Stadtteile und eine Schnittstelle für große
Gelände. Kriminalität, Gefängnis, Kaserne und Wehrdienst kommen in Teil 2 und 3. Bis dahin meldet das Stadtbuch nur die Stufe, das
Wachsen der Karte und die Stadtteile, keine Einrichtung, die es noch nicht gibt.

Alles hier ist eine **Spielregel der Stadt, keine Forderung des Programms**. Keine Stadt hat eigenes Militär oder einen Nachrichtendienst
als eigene Behörde (große US-Stadtpolizeien haben eigene Aufklärungsabteilungen, Abschnitt „Bund“); das gilt für Teil 2 und 3.

### Die Karte wächst

- **Start 56 × 56 Felder** (bis Version 6 fest 96 × 96). Kommt eine Straße oder ein Gelände näher als **16 Felder** an den erlaubten
  Rand (2 Felder vor der Kante, `RAND`), also näher als **18 Felder an den Rand der Karte** (so sagen es Fenster und Stadtbuch), bekommt
  die Karte ringsum **4 Felder** (einen Block) dazu. Das wiederholt sich, bis wieder 16 Felder Platz sind. Mehrere Ringe auf einmal und
  mehrmaliges Wachsen in einer Nacht (etwa mit Anstalt und Kaserne) ergeben eine Zeile im Stadtbuch. Die größte Karte hat **256 × 256** Felder,
  denn Gebäude speichern ihre Lage als `Uint8`. Ab dort hält der Rand die Stadt wie früher auf. Die große Stadt (`umland=300000`, Seed 2, 750 Tage) kommt bis 120 × 120.
- **Stadtbuch** (Art „Bauland“, Symbol Karte): „Im Osten reicht die Stadt bis 15 Felder an den Rand der Karte. Die Stadt weist
  ringsum neues Bauland aus: Die Karte wächst von 56 × 56 auf 64 × 64 Felder.“ Der Abstand zählt bis zum Rand der Karte. Wächst sie in
  einer Nacht mehrmals, steht das in derselben Zeile: „Die Stadt reicht in dieser Nacht zweimal nah an den Rand der Karte: zuerst im
  Norden bis 17 Felder, dann im Osten bis 12 Felder. … Die Karte wächst von 56 × 56 auf 80 × 80 Felder.“ (Seed 2, Tag 197). Die
  Startzeile nennt die Größe („Die Karte ist 56 × 56 Felder groß und wächst mit der Stadt.“).
- **Umrechnung** (`karteWachsen`, nach dem Vorbild von `erweiterung/mess/umbau.mjs`): Alle Felder (`feld`, `feldGeb`, `feldStr`,
  `platz`) wandern in das größere Raster, jede Gebäudelage, Kreuzung und jedes Straßenende rückt um 4 Felder. Die Viertel (12 × 12
  Felder, fürs Bauamt, Parks und Läden) liegen fest um die Mitte: Eine Viertelgrenze läuft durch die Mitte, weitere je 12 Felder daneben
  (`S.vo` ist der Versatz). Ihre Listen und Zahlen wandern mit. Personen, Wege und Hauptfiguren hängen an Gebäudenummern, sie
  ändern sich nicht. Alle Regeln rechnen relativ zur Mitte (`S.mitte`). Deshalb geht die Stadt **Tag für Tag genau so weiter wie
  mit der festen Karte**, mit denselben Zufallszahlen (gemessen, unten).
- **Die Grenze hält nichts auf.** Neue Straßen entstehen nach dem Start nur in `strasseVerlaengern` (Regel 2 des Bauamts; die
  anderen Regeln rufen sie auf). Dort wächst die Karte zuerst, falls nötig (`karteRand`), und reicht danach mindestens 16 Felder
  über jede Straße hinaus. Eine Verlängerung geht höchstens 4 Felder (ein Block) weiter, Abbiegen und Abzweigen prüfen ein Feld daneben.
  Also stößt keine Straße an den Rand. Bauplätze liegen neben Straßen, Baustellen und Gründungen auf Bauplätzen, also stoßen auch sie
  nie an. `karteRand` läuft außerdem nach dem Bauamt, nach jedem Gelände (unten) und am Ende jedes Tages. Gemessen mit einem Zähler, der
  jede vom Rand verhinderte Verlängerung, Abbiegung oder Abzweigung zählt: 0 auf den Seeds 1–3 (730 Tage), 0 in der großen Stadt
  (750 Tage), 0 in 60 Tagen nach einem großen Gelände am Rand (`simtest --erweiterung`).
- **Darstellung.** Weltkoordinate = Feld − Mitte + 0,5: Beim Wachsen bleibt die Stadt, wo sie ist, und die Kamera bewegt sich nicht.
  Die Landschaft liegt relativ zum Kartenrand. `V = H − 48` (H = halbe Kartengröße) ist der Versatz gegenüber der alten Karte 96. Boden,
  Wald, Ufer, See (Mitte bei x = −(H + 13), z = −(H − 12)), Felderraster, Landstraßen, Höfe und Umland rücken um V nach außen. Bei H = 48
  ist alles wie in Version 6. `landschaft()`, `umlandFest()` und `kameraGrenzen()` laufen beim Start und je Wachsen einmal
  (`karteNeu`), nie je Bild. Grenzen: Blickpunkt höchstens H + 12 von der Mitte, Kamera-Abstand bis 160 + 2V, Nebel 70 + V bis
  190 + 2V, Sichtweite 600 + 2V, Himmelskuppel 500 + 2V (bei 96 wie vorher 60, 160, 70–190, 600, 500). Auf der Startkarte 56 heißt
  das: Abstand bis 120, Nebel 50–150. Beim Wachsen werden die Grenzen nur weiter.
  Neue Meshes gibt es nicht. Das Straßen-Mesh bekommt mehr Platz, wenn die Karte ihn braucht: ein neues `InstancedMesh`, das alte wird
  mit `dispose()` freigegeben. Verzierungen je Feld (Parkmuster, Büsche, Laternenseite) hängen an der Lage zur Mitte (`feldHash`),
  sonst sähe ein Park nach dem Wachsen anders aus. Das fiel im eigenen Test auf: Draw Calls 25 → 27 über ein Wachsen hinweg.
  Three.js 0.186.0 im Quellcode nachgesehen: `BufferGeometry.dispose`, `Texture.dispose`, `InstancedMesh.dispose` (gibt die
  Instanzpuffer über `WebGLObjects` frei), `Object3D.remove`, `Vector3.setScalar`, `PerspectiveCamera.far` mit
  `updateProjectionMatrix` (behält `setViewOffset`), `Fog.near`/`far`, `OrbitControls.maxDistance`/`maxTargetRadius`.

### Stufen

| Stufe | ab Einwohnern | BBSR (Deutschland) | geteilt durch 125 |
|---|---|---|---|
| Dorf | 0 | Landgemeinde: unter 5.000 | – |
| Kleinstadt | 40 | Kleinstadt: 5.000 bis unter 20.000 | 40 |
| Stadt | 160 | Mittelstadt: 20.000 bis unter 100.000 | 160 |
| Großstadt | 800 | Großstadt: 100.000 und mehr | 800 |

Quelle der Schwellen: BBSR, „Stadt- und Gemeindetypen in Deutschland“
(https://www.bbsr.bund.de/BBSR/DE/forschung/raumbeobachtung/Raumabgrenzungen/deutschland/gemeinden/StadtGemeindetyp/StadtGemeindetyp.html,
abgerufen im September 2026). Maßgeblich sind dort die Einwohnerzahl **und** die zentralörtliche Funktion: „Gemeinden mit oberzentraler
Funktion werden bereits ab 9.000 Einwohnern als Mittelstadt eingeordnet.“ Als Stadt gilt eine Gemeinde auch unter 5.000 Einwohnern,
wenn sie mindestens eine grundzentrale Funktion erfüllt (Wortlaut der Seite beim Abruf am 26.09.2026 nachgelesen).
Die Stadt nimmt nur die Einwohnerzahl (alle Menschen, auch Kinder) und nennt die Mittelstadt kurz „Stadt“.

- **Maßstab 125:** Die Städte haben an Tag 730 im Mittel 1.110 Einwohner (Seeds 1–80). Mit 125 erreichen alle drei Stufen ihren
  Aufstieg innerhalb von 400 Tagen, und jeder Aufstieg ist ein eigener Moment im Spiel (Seeds 1–80: Kleinstadt an Tag 53–113, Stadt
  139–222, Großstadt 294–385). Das ist ein Spielmaßstab, keine Aussage über echte Größen.
- **Kein Abstieg:** Eine erreichte Stufe bleibt. Die Einwohnerzahl schwankt um bis zu 15 % (Gate 4), und Einrichtungen aus Teil 2
  und 3 sollen nicht verschwinden und wiederkommen.
- **Stadtbuch** (Art „Stufe“): „Die Stadt hat jetzt 40 Einwohner und ist eine Kleinstadt. Als Kleinstädte zählt das BBSR in
  Deutschland Gemeinden mit 5.000 bis unter 20.000 Einwohnern; die Stadt zählt jeden Menschen hier für 125. Neu: Stadtteile mit
  Namen.“ „Neu:“ nennt nur, was der Code auf dieser Stufe wirklich freischaltet (`STUFE_NEU`). Heute ist das bei der Kleinstadt
  „Stadtteile mit Namen“, bei Stadt und Großstadt nichts. Teil 2 und 3 tragen ihre Einrichtungen selbst dort ein (seit Teil 3: Kleinstadt
  dazu die Polizeiwache, Stadt die Justizvollzugsanstalt und die Kaserne mit Wehrpflicht, Großstadt die Dienststelle). Die Reihenfolge
  wird dann als Spielregel begründet (Größe der Einrichtung zur Stadt, Zeitpunkt), nicht mit Realismus.
- **Anzeige:** In den Zahlen oben links steht die Zeile „Stufe“. Ihr Hinweis nennt die nächste Schwelle („Stadt ab 160 Einwohnern
  (die Stadt zählt jeden Menschen für 125)“). Die Zahlen werden dadurch eine Zeile höher (400 × 820: Unterkante 231 statt 211 px).
  Am Handy quer (bis 500 px hoch) fehlt dafür der Platz. Dort gibt es keine eigene Zeile, und die Stufe steht nur für Screenreader hinter
  „Einwohner“. Sichtbar machte sie die Zahlen 10 px breiter, und daneben liegen Karten und die Stadtbuch-Liste. Die Zahlen sind dort so
  hoch und breit wie in Version 6 (`tests/kennzahlen_hoehe.cjs`: 156, 156, 157, 158 und 216 px bei 568 × 320 bis 926 × 428).

### Stadtteile

- **Nur aus der Lage.** Ringe aus Vierteln um die Mitte (je 12 Felder breit) mal vier Himmelsrichtungen (NW, NO, SW, SO). Ring 0 sind
  die vier Viertel an der Mitte. Die Grenzen liegen auf Viertelgrenzen, also auf Rasterlinien, wo nie ein Gebäude steht. Bis zu 44
  Stadtteile auf der größten Karte, dafür 44 Namen aus einer festen Liste von Orts- und Flurnamen (Altstadt, Marktviertel,
  Lindenhof, Birkenfeld, Mühlenviertel, Eichholz, Rosenau, Wiesengrund, Buchenried …). Sie werden in der Reihenfolge des ersten
  Gebäudes vergeben.
- **Ab der Kleinstadt.** Beim Aufstieg bekommen alle bebauten Stadtteile ihren Namen („Die Stadt hat jetzt Stadtteile: Altstadt (im
  Nordwesten), Marktviertel (im Nordosten), Lindenhof (im Südwesten) und Birkenfeld (im Südosten). Ihre Grenzen laufen an Straßen
  entlang; ein neuer Stadtteil bekommt seinen Namen mit dem ersten Gebäude.“). Danach bekommt jeder neue seinen Namen mit dem ersten Gebäude,
  ohne Personennamen: „Ein neuer Stadtteil entsteht im Nordosten: Mühlenviertel. Das erste Gebäude dort: ein Wohnhaus an der
  Hauptstraße.“
- **Zu sehen:** Hauskarte (über dem Titel), Personenkarte („… an der Hauptstraße · Altstadt“), Fenster „Stadtregierung“ (Live-Zeile)
  und die Karte. Die Namen stehen dort nur weit herausgezoomt: ab Kameraabstand 35, mit derselben Grenze und demselben Spielraum wie
  die Straßennamen. Sie erscheinen erst, wenn kein Straßenname mehr zu sehen ist oder ausblendet, **also nie beide zugleich**. Je
  Stadtteil steht der Name über der Mitte seiner Gebäude, höchstens 12, nicht unter Panels und nicht übereinander. Es sind feste
  Schilder in der Ebene der Straßennamen, die nur mit den Straßennamen neu gesetzt werden (Kamera bewegt, stündlich). Das kostet
  keine Draw Calls und keine Allokation je Bild. Bei reduzierter Bewegung erscheinen sie ohne Übergang.
- **Harte Grenze.** Stadtteile kennen nur ihre Lage. `stadtteilZaehlen` zählt je Stadtteil Einwohner (nach Wohnung), Wohnhäuser,
  Wohnungen, Betriebe und Parks. Keine Taten, keine Herkunft, keine Namen, keine Rangliste, keine Einstufung, und keine Regel wählt
  Personen nach ihrem Stadtteil aus. `simtest --erweiterung` prüft das statisch. Der ganze Abschnitt liest von Personen nur `lebt` und
  `wohnung` (auch in der Form `S.p.…`), hat keinen Zufall und liest keine Namen. `teilVon`/`teilName` stehen außerhalb nur beim Benennen
  (`neuesGebaeude`) und in den Karten (`personInfo`, `gebaeudeInfo`).

### Schnittstelle für Teil 2 und 3: Gelände aus mehreren Blöcken

- `gelaendeSuchen(S, bw, bh, amRand)`: ein freies Rechteck aus bw × bh Blöcken (4·bw − 1 × 4·bh − 1 Felder, die Rasterlinien dazwischen
  gehören dazu). Alle Felder sind leer (Bauplätze darf es überdecken), und an einer Seite liegt eine Straße. Das Tor ist das Feld an der
  Straße, das der Mitte dieser Seite am nächsten liegt; die Seite zur Stadtmitte geht vor. Mit `amRand` nimmt es das Rechteck, dessen
  Mitte am weitesten von der Stadtmitte liegt, sonst das nächste. Liest nur. Findet es nichts, kommt `null`. Das passiert, wenn an keiner
  Straße ein ganzer freier Block liegt (Seed 2, Tag 300, 1 × 1). Der Aufrufer wartet dann, bis das Bauamt eine Straße verlängert.
  Im Test dauerte das 10 Tage (er wartet höchstens 60).
- **Ein Block** (Wache, Dienststelle; Befund B1 der Schlussprüfung): Endet eine Straße an der Rasterlinie zwischen zwei freien Blöcken
  (sie liefe auf dieser Linie weiter), liegt an keinem der beiden eine Straße, und `gelaendeSuchen(S, 1, 1, …)` fand vorher nichts,
  während größere Gelände genau dort Platz fanden. Jetzt sucht es dann im Rahmen von zwei Blöcken (`gelaendeRechteck(S, 2, 1)` bzw.
  `(1, 2)`); das Tor liegt auf der Rasterlinie an der Straßenspitze, belegt werden nur 3 × 3 Felder um das Tor (die Linie und je eine
  Reihe der beiden Blöcke daneben). Findet die Suche einen ganzen Block an einer Straße, bleibt alles wie vorher (Seed 2 Tag für Tag
  gleich). Nach einer Übernahme kann die Wache so eine Stelle nehmen, die sonst Anstalt oder Kaserne bekämen; dann wartet die Kaserne
  (Annahme 78, „Bekannte Schwächen“).
- `gelaendeBauen(S, r, typ, arbeit, besitzer)`: Das Gebäude kommt aufs Tor (Baustelle mit `arbeit` Arbeitstagen, `neuesGebaeude`). Die
  übrigen Felder werden belegt (`feld = typ`, `feldGeb = Gebäude`): Straßen wachsen nicht hinein, Bauamt und Gründer finden dort
  keinen Bauplatz. Danach wächst die Karte, falls das Gelände dem Rand zu nahe kommt. Weil die Karte immer 16 Felder über die
  äußerste Straße reicht, passen Gelände bis 4 Blöcke tief auch vor der äußersten Straße.
- Gespeichert in `S.erweiterung.gelaende` ([x0, y0, x1, y1, Gebäude]). `STUFE_NEU` nimmt die Einrichtungen je Stufe auf,
  `erweiterungInfo` gibt alles für Karten und Fenster.
- Getestet: ein Park als Gelände 3 × 2 Blöcke am Rand (Seed 2, Tag 310, 77 Felder, Tor zur Straße im Westen). Die Karte wächst
  dafür von 104 auf 128. Danach 60 Tage ohne Grenzstopp, Speichern und Laden bitgleich. Dazu 1 × 1 nah an der Mitte.

### Fenster „Stadtregierung“

Neue Gruppe „Stadt erweitern (Spielregel, nicht aus dem Programm)“ mit der Karte „Die Stadt wächst: Bauland, Stufen, Stadtteile“
im Stil der anderen: Status „Spielregel“, kein Zitat, „In der Stadt“, „Annahme“, Live-Zeile („Heute eine Stadt mit 620 Einwohnern,
Großstadt ab 800. Erreicht: …, Karte 104 × 104 Felder, 1-mal gewachsen …“). Aufklappbar: Stadtteile, Wirklichkeit, Rand. Wirklichkeit:
In Deutschland weist eine Gemeinde neues Bauland mit einem Bebauungsplan aus, den sie als Satzung beschließt (§ 10 Abs. 1 BauGB,
„Die Gemeinde beschließt den Bebauungsplan als Satzung.“, nachgelesen auf dejure.org/gesetze/BauGB/10.html; gesetze-im-internet.de
war beim Abruf nicht erreichbar). Die Karte zeigt, wo gebaut werden darf, nicht die Grenze der Gemeinde; wie weit deren Gebiet reicht,
rechnet die Stadt nicht. Dass die Karte ringsum wächst, auch wo die Stadt nicht an den Rand kommt, ist eine Vereinfachung. Eine
Aussage darüber, ob ein Bebauungsplan das Gemeindegebiet ändert, steht bewusst nicht im Fenster (nicht nachgeprüft).

Nicht übernommen, neu oder mit neuem Grund (alle Zitate mit `zitatpruef.py` und `zitate_genau.py` geprüft):

- S. 122, zwei Sätze: „Nicht nur in deutschen Großstädten sind mittlerweile muslimisch geprägte Stadtteile mit entsprechenden
  Parallelgesellschaften entstanden […]“ und „Es sind weiter die erforderlichen Mittel bereitzustellen und Maßnahmen (wie z. B. Razzien
  und Kontrollstellen) durchzuführen, damit der Rechtsstaat in den sogenannten No-go-Areas wieder durchgesetzt werden kann.“ Grund: Das
  Programm beschreibt diese Stadtteile über die Religion ihrer Bewohner (harte Grenze). Die Stadtteile der Stadt entstehen nur aus der
  Lage. Es gibt keine Razzien und keine Kontrollstellen nach Stadtteilen und keine Liste von Stadtteilen nach Taten oder Bewohnern.
  (Die kürzere Fassung des zweiten Satzes stand schon in Version 6 in der Liste; ihr Grund „die Stadt hat zudem keine Polizei“ ist
  entfallen, weil Teil 2 eine Polizei bringen kann.)
- S. 109: „Angesichts der massiven Entfremdung in unseren Städten und gewachsenen Parallelgesellschaften muss die Integrationsfähigkeit
  unseres Landes erst wiederhergestellt werden.“ Grund: setzt Herkunft voraus.
- S. 111 („Gegengesellschaften von über 25 % Nicht-EU-Migranten“): Grund ergänzt, die Stadtteile kennen nur ihre Lage.
- S. 39, zwei Sätze zum Bauen im Außenbereich (neu in der Gruppe „Kein Gegenstück“): Die Stadt baut nur an ihren Straßen und kennt
  keine Baugenehmigungen.
- S. 74, der ganze Satz: „Flankierend dazu stellen wir uns gegen die Abnahme der landwirtschaftlichen Nutzfläche und werden
  außerlandwirtschaftlichen Investoren den Zugang zum Bodenmarkt erschweren.“ Die Stadt wächst auf Felder, das widerspricht der
  Richtung des Satzes. Die Felder sind aber nur Landschaft, und das Programm nennt für Gemeinden kein Mittel.
- S. 36 („Wir werden den Wohnungsbau von diesen Fesseln befreien …“): Grund ergänzt. Gemeint sind Vorschriften, nicht Bauland.
- Gilt schon, S. 171 (Umbenennung von Straßen): „Die Stadt reißt nichts ab und benennt keine Straßen und keine Stadtteile um.“

### Gemessen

Seeds 1–3 (`simtest --gate`, 730 Tage stündlich): Alle Kennzahlen und Gates sind **zahlengleich mit bc7247a**. Nur die
Stadtbuch-Zeilen je Tag steigen durch die neuen Zeilen: 4,26 / 4,35 / 4,80 statt 4,25 / 4,33 / 4,78. `--erweiterung` vergleicht
jeden Tag mit der alten Fassung: Kennzahlen, Zufallszustand, Felder und Gebäude relativ zur Mitte, alle Personenfelder, alle
Gebäudefelder außer der Lage, Statistik, Hauptfiguren und Stadtregierung. Gleich an allen 730 Tagen.

| Seed | Einwohner Tag 730 | Karte | gewachsen an Tag | Kleinstadt / Stadt / Großstadt an Tag | Stadtteile | Abstand zur Baugrenze (auf der alten Karte 96) |
|---|---|---|---|---|---|---|
| 1 | 1.065 | 56 → 80 (3-mal) | 168, 204, 309 | 78 / 173 / 325 | 8 | 16 (24) |
| 2 (Teststadt) | 1.122 | 56 → 104 (6-mal) | 108, 128, 168, 211, 235, 251 | 72 / 166 / 327 | 9 | 16 (12) |
| 3 | 1.082 | 56 → 80 (3-mal) | 98, 131, 221 | 64 / 161 / 311 | 8 | 16 (24) |
| 2, `umland=300000`, 750 Tage | 5.920 | 56 → 120 (8-mal) | 108, 128, 168, 211, 235, 572, 645, 688 | Großstadt | 16 | nicht gemessen, Grenzstopp 0 |

Seeds 1–80 (730 Tage stündlich, `mess/mess7.mjs` über `mess/lauf80.sh`, Vergleich `mess/vergleich80.py` gegen dieselbe Messung auf
bc7247a): **0 Abweichungen** in allen Kennzahlen außer den neuen Feldern und den Stadtbuch-Zeilen. Gates bestehen auf **77 von 80**
(bc7247a: 77 von 80), Gate 4 fällt auf denselben Seeds 11, 23 und 45 wegen des Bandes (Faktor über 1,15). Band im Mittel 1,077, Median
1,073, schlimmster 1,155, wie vorher. Die Karte wächst 1- bis 6-mal (Median 3) auf 64 bis 104 Felder (Median 80; 38 Städte bei 80,
27 bei 72). Der kleinste Abstand zum Rand ist 16 Felder, auf der alten Karte 96 wären es mindestens 12. Stadtteile 4 bis 11
(Median 8). Stufen: Kleinstadt an Tag 53–113 (Median 67), Stadt an Tag 139–222 (168), Großstadt an Tag 294–385 (327), alle 80
Städte erreichen alle drei. Stadtbuch: im Mittel 4,468 statt 4,454 Zeilen am Tag (höchstens +0,03 je Stadt, schlimmste Stadt
6,18 statt 6,17). Spielstand an Tag 150 (Seed 1): 0,15 MB statt 0,21 MB, weil die Karte dort erst 56 × 56 groß ist.

**Wahl von Start, Ring und Vorlauf** (`mess/ausdehnung.mjs`, `mess/wahl.py`): Die Straßen der Städte reichen bis Tag 730 von der Mitte
aus 12 bis 40 Felder weit (Entwurf); eine Karte, die erst am alten Rand 96 wächst, würde fast nie wachsen. Gerechnet über die
Ausdehnung je Tag auf den Seeds 1–80 und der großen Stadt. Start 56 ist die kleinste Größe in Achterschritten, in der die Startstraße
(8 Felder zu jeder Seite der Mitte) mit 16 Feldern Vorlauf und 2 Feldern Rand Platz hat; bei 48 müsste die Karte schon beim Start
wachsen. Ring 4 ist ein Block, so wächst die Karte in kleinen Schritten und oft. Vorlauf 16 ist mehr als eine Verlängerung (4) plus ein
Feld und lässt Platz für Gelände bis 4 Blöcke tief. Damit wächst die Karte auf den Seeds 1–3 3-, 6- und 3-mal und in der großen Stadt
auf 120.

### Speicherformat 7

Neu: `S.karte` (Kartengröße, Vielfaches von 8, 24 bis 256), `S.mitte`, `S.vn`, `S.vo` (Maße der Viertel) und `S.erweiterung` mit
`stufe`, `stufenTage` (Tag je erreichter Stufe), `ausdehnung` ([x0, x1, y0, y1] aller Straßen und Gelände), `teile` ([Stadtteil, Tag]
in der Reihenfolge der Namen), `gelaende` und `wachsen` ([Tag, neue Größe]). Die Felder sind so lang wie die Karte. Alles ist Pflicht
und wird beim Laden nach `jsonPruefen` in `erweiterungPruefen` geprüft, für jeden Stand, auch nach einer Übernahme:
Kartengröße falsch → „Spielstand beschädigt: Kartengröße“, Maße → „… Kartenmaße“, Längen der Felder oder Viertel → „… Karte (feld)“
bzw. „… Viertel (…)“, Kreuzungen und Straßenenden außerhalb → „… Kreuzungen“/„… Straßenenden“, alles in `S.erweiterung` (Stufe
0–3, so viele Tage wie Stufen, aufsteigend, nicht nach heute; Ausdehnung in der Karte; Stadtteile erst ab der Kleinstadt, jeder
höchstens einmal, höchstens 44; Gelände in der Karte mit gültigem Gebäude; Wachsen nicht größer als die Karte) → „… Stadt
erweitern“. Seit der Schlussprüfung (Befund T1) dazu die Lage jedes Gebäudes (auf der Karte, das Feld zeigt auf das Gebäude → „… Lage
der Gebäude“) und jedes Gelände (Gebäude im Rechteck, jedes Feld zeigt auf das Gebäude und trägt seinen Typ oder ist Baustelle →
„… Gelände“). `simtest --erweiterung` prüft 15 beschädigte Stände.

**Übernahme.** Ein Stand der Version 6 zeigt den Versionsdialog: „Dein Spielstand ist von Version 6. Seit Version 7 wächst die Karte
mit der Stadt: Kommt die Stadt an ihren Rand, weist sie neues Bauland aus. Die Stadt hat eine Stufe (Dorf, Kleinstadt, Stadt,
Großstadt) und ab der Kleinstadt Stadtteile mit Namen.“ „Stadt übernehmen“ behält alles. Die Karte bleibt 96 × 96 (wächst gleich,
wenn eine Straße näher als 16 Felder am erlaubten Rand liegt), die Ausdehnung kommt aus den Straßen, die Stufe aus den heutigen Einwohnern
(ohne Zeilen für übersprungene Stufen), die Stadtteile bekommen ab der Kleinstadt ihre Namen in der Reihenfolge ihres ersten Gebäudes.
Im Stadtbuch steht „Ab heute zählt die Stadt ihre Größe: 620 Einwohner, sie ist eine Stadt. Ihre Stadtteile heißen … Die Karte ist
von 96 × 96 auf 104 × 104 Felder gewachsen und wächst weiter, wenn die Stadt näher als 18 Felder an ihren Rand kommt.“ (bis zur
Schlussprüfung stand hier 16, gemeint war der erlaubte Rand; jetzt zählt die Zeile wie Fenster und Stadtbuch bis zum Rand der Karte). Danach läuft
die Stadt genau so weiter wie in Version 6, solange dort keine Straße am alten Rand endete (gemessen: Seeds 1/Tag 15, 1/150, 2/300,
3/400, je 60 Tage Tag für Tag gleich). Versionen 2 bis 5 laufen über die Kette (`MIGRIERBAR = [2, 3, 4, 5, 6]`) und bekommen einen
Satz dazu („Seit Version 7 wächst die Karte …“). `--speichertest` läuft bitgleich; **Fingerabdruck `d918da4702073bbb`** (Seed 1,
gespeichert an Tag 150 um 13 Uhr, 60 Tage weiter; vorher `a23e00a5306658b3`). Er ist neu, weil der Fingerabdruck jetzt auch Kartengröße,
Stadt erweitern, Straßenenden und Kreuzungen enthält; die Stadt selbst läuft gleich. `--erweiterung` speichert an Tag 107 um 13 Uhr (Karte 56), lädt und
rechnet weiter: Beide wachsen an denselben Tagen (108 auf 64, 128 auf 72) und sind 30 Tage später bitgleich.
Teststand für `tests/t1_xss.cjs`: `tests/basis_v7.json` (aus `tests/basis_v6.json` über „Stadt übernehmen“, Tag 420, 2.186
Einwohner, Karte 96, Großstadt; `tests/basis_v7.cjs`), `tests/hilfe.cjs` zeigt darauf; das Original bleibt.

### Tests

- `simtest --erweiterung` (neu): statische Prüfung des Abschnitts (oben). Seeds 1–3 je 730 Tage gegen die alte Fassung, Tag für Tag
  gleich (wie oben unter „Gemessen“). Grenzstopp-Zähler 0. Vorlauf jeden Tag mindestens 16 Felder, Ausdehnung = Straßen, Maße stimmen. Wachsen mit Tag und Größe und
  je Nacht eine Zeile (Größe vor dem ersten und nach dem letzten Wachsen der Nacht, Abstand unter 18; seit der Schlussprüfung). Stufe jeden Tag richtig **und genau am ersten Tag über der Schwelle** (Befund 14). Stadtteile jeden Tag richtig benannt,
  Zähler gegen eine eigene Zählung, Karten. Stadtbuch ohne Personennamen, keine Stadtteilzeile vor der Kleinstadt. Speichern und Laden
  über ein Wachsen hinweg bitgleich. 15 beschädigte Stände abgelehnt (seit der Schlussprüfung auch Gebäude außerhalb der Karte und
  falsche Gelände-Felder). Seed 2 wächst an Tag 197 zweimal: eine Zeile. Übernahme von Version 6 an vier Ständen, darunter einer unter 40
  Einwohnern („ein Dorf“, Befund 7), je 60 Tage gleich wie Version 6. Gelände 3 × 2 am Rand und 1 × 1 an der Mitte. Mit `--gross`
  die große Stadt.
- `simtest --migrationstest --git /home/user/website-`: Versionen 2–6 (bc7247a als Version 6), 60 Tage weiter, Zeilen, Stufe, Karte.
- Browser: `tests/erweiterung.cjs` (neu, in `tests/alle.sh`), normal und mit reduzierter Bewegung. Teststadt bis Tag 108, 23 Uhr, dann
  das Wachsen in der Nacht (56 → 64): Kamera, Blickpunkt und Gebäude bleiben, See, Boden und Grenzen rücken nach außen, Objekte in der
  Szene gleich, Draw Calls nicht mehr. Dazu die Stadtbuch-Zeile, die Zeile „Stufe“ mit Hinweis, der Stadtteil in Haus- und
  Personenkarte, Namen nah (Straßen) und fern (Stadtteile), nie beide zugleich. Wachsen mitten am Tag: jede Instanz jedes Meshes
  gleich. Konsole leer. `tests/p6migration.cjs` hat einen neuen Fall Version 6 → 7 (bc7247a per Route aus `afd/stadt_v6.html`,
  Version 5 jetzt aus `afd/stadt_v5.html`). `tests/befunde_s2.cjs` prüft den Versionsdialog am Handy jetzt für Version 5 (per Route) und 6
  und zählt vier aufklappbare Karten im Fenster statt drei (neu: „Die Stadt wächst“). `tests/pruef_v5.cjs` erzeugt den Stand der
  Version 5 per Route aus `afd/stadt_v5.html`, erwartet nach der Übernahme Version 7 und prüft dazu Karte, Stufe und Stadtteile.
  `tests/p8tech.cjs`, `tests/raute_klick.cjs` und `tests/otest/h.cjs` rechnen Weltkoordinaten mit der Mitte der Stadt statt mit 47,5.
  Keine Prüfung ist schwächer geworden.
- **Ergebnis** auf dem Endstand (Server auf 8713, `tests/alle.sh`, KI-Nachbau auf 11434): p3test 12, p5neu 10, p6migration 24 (vorher
  18), p7figuren 6, p8tech 14, raute_klick 10 von 10 Klicks, ereignis 21, t1_xss 5, p4test 25, s2karten 22, kita 22, befunde_s2 27
  (vorher 22), erweiterung 20 (je 10 normal und mit reduzierter Bewegung), alle ohne Fehler. `tests/otest`: befunde 21, handy 11, breit 12,
  tastatur 4, breiten 20, hilfehoehe ohne Überlauf (Hilfe bei 1280 × 800 745 von 745 px), alle ohne Fehler. Konsole leer, außer den
  absichtlichen Verbindungsfehlern zum KI-Nachbau in p4test und den abgebrochenen KI-Anfragen in `blick.cjs`. Dazu `tests/pruef_v5.cjs`
  17 ohne Fehler und `tests/kennzahlen_hoehe.cjs` (oben). Alle `simtest`-Modi auf dem Endstand ohne Fehler: `--gate` (Seeds 1–3 alle
  Gates), `--speichertest`, `--aufholtest` (Werte wie bc7247a), `--kitest` 45, `--bau` 15, `--waren` 15, `--tech` 16, `--regierung` 155,
  `--kita` 40, `--migrationstest --git /home/user/website-` 251, `--erweiterung --gross` 33 Prüfungen. Zitate: 133 im Fenster,
  `zitatpruef.py` 133 gefunden, `zitate_genau.py` 133 auf der genannten Seite, 0 Fehler.
- **Bilder** (`tests/blick.cjs`, Endstand, selbst angesehen): `nachher/` (Teststadt Seed 2, Tag 400: 935 Einwohner, Großstadt, Karte
  104 × 104, 25 bis 28 Draw Calls, 44.400 bis 45.500 Dreiecke; bc7247a: 25 bis 28, 44.400 bis 45.400). Herausgezoomt stehen die
  Stadtteile (Altstadt, Birkenfeld, Rosenau, Mühlenviertel, Wiesengrund), nah nur Straßennamen. `gross/` (`&umland=300000`, Seed 2, Tag
  750: 5.928 Einwohner, Karte 120 × 120, 24 bis 27 Draw Calls, 140.000 bis 146.600 Dreiecke; bc7247a: 24 bis 27, 140.000 bis 146.000).
  Der See liegt links hinten, Wald, Felder und Landstraßen reichen bis in den Nebel. Neue Draw Calls: keine.

### Befunde der Gegenprüfung „erweiterung“

Befund 1 (Karte bleibt 96) ist durch Noahs Entscheidung „Karte wächst wirklich“ ersetzt. Umgesetzt:

2. S. 122 (beide Sätze) und S. 109 mit Zitat unter „Nicht übernommen“. Keine Kriminalitätszahlen, Razzien, Kontrollstellen oder
   Auswahl je Stadtteil. Statischer Test, dass Stadtteile außerhalb nur benannt und angezeigt werden.
3. Nichts dem Programm zugeschrieben. Die einzige Rechtsaussage (§ 10 Abs. 1 BauGB) ist nachgelesen, die Stufen haben die
   BBSR-Quelle. Zuständigkeiten für Polizei, Justizvollzug, Bundeswehr und Nachrichtendienste kommen erst mit Teil 2 und 3 ins Fenster;
   dort gilt der Befund weiter.
4. Die USA-Hinweise gehören zu Teil 2 und 3 (Polizei, Jails, Nachrichtendienst). In Teil 1 steht kein Satz dazu.
5. Die Grenze gilt für jede Straße, nicht nur für Regel 2. `karteRand` läuft vor jeder Verlängerung, nach dem Bauamt, nach jedem
   Gelände und am Tagesende. Geprüft über den Zähler und nach einem Gelände.
6. „Neu:“ nennt nur, was wirklich kommt (`STUFE_NEU`, heute nur „Stadtteile mit Namen“).
7. Artikel je Stufe (`STUFE_MIT`: „ein Dorf“ … „eine Großstadt“), getestet mit einem Stand unter 40 Einwohnern.
8. Die Stadtteilnamen rechnen mit der aktuellen Kameramatrix (`camera.updateMatrixWorld()` am Anfang von `strassenNamen`, das sie setzt).
9. Nie beide zugleich: Die Stadtteile hängen an `namenAn` (dieselbe Grenze und derselbe Spielraum) und warten, bis kein Straßenname
   mehr ausblendet. Im Browser gemessen: 0-mal beide zugleich.
10. „Die Stadt weist neues Bauland aus“ statt Stadtgebiet oder Stadtgrenze; Hinweis auf den Bebauungsplan (§ 10 BauGB).
11. Keine Realismus-Begründung für eine Reihenfolge von Einrichtungen. Die Stufen sind als Spielmaßstab begründet. Die JVA-Aussage des
    Entwurfs ist nicht übernommen.
12. S. 74 mit dem ganzen Satz. Der Teil zu S. 138 gehört zu Teil 3.
13. Keine Reste des Prototyps (kein `GEBIET_MODUS`, kein Zähler `gebietStopp` im Produktcode; der Zähler steckt nur im Test).
    README-Abschnitt und Fenster sind da.
14. Der Test ist schärfer: Aufstieg genau am ersten Tag über der Schwelle, statischer Test auch für `S.p.…`, Stadtbuch-Zeile ohne
    Personennamen.

Eigene Befunde beim Bauen und Prüfen, alle behoben:

- In `neueStadt` hieß die Mitte `M`. Damit war die Liste der Gedächtnis-Arten (`M.EINGEZOGEN`) verdeckt, und die zehn ersten Bewohner
  hatten kein „eingezogen“ im Gedächtnis. Die Kennzahlen merkten das nicht, der Tagesvergleich damals auch nicht. Er vergleicht jetzt
  zusätzlich alle Personenfelder, alle Gebäudefelder außer der Lage, Statistik, Hauptfiguren und Stadtregierung. Mit dem alten Fehler
  schlägt er an Tag 1 an, nach der Korrektur ist er auf den Seeds 1–3 an allen 730 Tagen gleich.
- Die Zeile „Stufe“ sollte am Handy quer fehlen. `#kennzahlen dl div` gewann aber gegen `#k-stufe-zeile`, und die Zahlen reichten
  bei 568 × 320 7 px in die Spalte darunter (`tests/kennzahlen_hoehe.cjs`: 172 statt 156 px). Jetzt steht der Selektor genauer da.
- Die Hilfe war bei 1280 × 800 mit den neuen Sätzen 25 px zu hoch und musste scrollen (`tests/otest/befunde.cjs`). Die Sätze sind
  jetzt kürzer: „Straßennamen nah, Stadtteile weit herausgezoomt.“ und „Wächst die Karte, rückt die Landschaft mit.“ Die Hilfe ist
  wieder genau so hoch wie in Version 6 (745 px).
- Parks, Büsche und Laternen richteten sich nach der Lage auf der Karte. Nach dem Wachsen sah ein Park anders aus (Draw Calls 25 → 27).
  Jetzt hängen sie an der Lage zur Mitte (`feldHash`).
- Die Browser-Tests `p8tech`, `raute_klick` und `otest/h.cjs` rechneten Weltkoordinaten mit der festen Mitte 47,5. Jetzt nehmen sie die
  Mitte der Stadt (`S.mitte`). Vorher fand `p8tech` keine Programmierer am richtigen Ort.

## Sicherheit: Kriminalität, Polizei, Gericht, Gefängnis (Version 7, Teil 2)

Teil 2 von „Stadt erweitern“. Noahs Entscheidungen: **Kriminalität ist eine Regel der Stadt**, keine Aussage des Programms; die
**Justizvollzugsanstalt ist eine Anstalt für die Region**: Sie hat mehr Plätze, als die Stadt braucht, die übrigen belegt das Land
mit Gefangenen von außerhalb. Diese gibt es nur als Zahl (sie werden nicht simuliert und nicht gezeigt), nach ihnen richten sich
aber das Personal und die Stellen. Hauskarte und Fenster sagen das. Polizei, Gerichte und Gefängnisse gehören dem **Land**; keine
Stadt in Deutschland hat eine eigene Vollzugspolizei oder ein eigenes Gefängnis. Die Löhne zahlt das Land, sichtbar als Geld „von außen“.

Umgesetzt im sim-Block im Abschnitt „Sicherheit (Version 7)“ (bis „Ende Sicherheit“), jede Nacht nach `menschenTag` in `sicherheit(S)`:
Entlassungen → Urteile → Taten → Obhut für Kinder → Bauten des Landes → Stellen des Landes → Jahreszeile → Geld vom Land für „gestern“.
Zufall nur aus einem eigenen Strom `S.rsSich`; mit `R.KRIM_BASIS = 0` und `R.LAND_BAUT = 0` läuft die Stadt genau wie ohne (so vergleichen
`--erweiterung` und `--migrationstest` mit Version 6). Grundlage war der Prototyp in `scratchpad/erweiterung/sicherheit/` (auf 414ebab);
die Logik ist auf den Stand nach Teil 1 übertragen, nicht die Patches.

### Regeln

- **Taten.** Jede erwachsene Person, die nicht in Haft ist, begeht nachts mit der Wahrscheinlichkeit
  q = 0,0032 × (1 + 8 · Not · (0,5 + Ehrgeiz/100) + 2 · erwerbslos + 3 · Unzufriedenheit) eine Tat (`tatTeile`, `tatRisiko`).
  Not = 1 − Geld / (5 × Tageskosten), Unzufriedenheit = (50 − Zufriedenheit) / 30, beide auf 0 … 1 begrenzt; erwerbslos wie in der
  Arbeitslosenzahl. Die Tatneigung liest **nur Geld, Tageskosten, Stelle, Zufriedenheit und Ehrgeiz**; die eigenen Vorstrafen liest sie
  nicht (erst das Gericht), Rückfälle entstehen über die Folgen der Haft. Art: Diebstahl 69,4 %, Wohnungseinbruch 2,9 %, Betrug 27,7 %;
  keine Gewalt.
- **Opfer** zufällig unter allen Erwachsenen außerhalb des eigenen Haushalts, nicht in Haft (liest Alter, Haushalt, Wohnung, Haft); beim
  Einbruch alle Erwachsenen des Haushalts. Beute höchstens 10 / 60 / 20 Taler und was das Opfer hat. Folgen: Gedächtnis („wurde
  bestohlen“ …, danach eine Entscheidung wie nach jedem Ereignis), eine Weile weniger Zufriedenheit, nach einem Einbruch Wohnen −20 für
  20 Tage.
- **Anzeige und Aufklärung.** Jede Tat wird angezeigt. Aufgeklärt mit min(0,9; Quote × Faktor): Diebstahl 31,4 %, Wohnungseinbruch
  15,3 %, Betrug 58 %. Faktor = 2d/(d + 1) mit d = max(1, 1,2 × besetzt / Stellen): voll besetzt 1,09, fehlen Leute, nie unter 1 (ohne
  Wache 1, Polizei aus dem Nachbarort). Die Wache ist für einen Bezirk zuständig, in der kleinen Stadt auch für das Umland: Ihre
  Mindeststellen erhöhen die Aufklärung nicht (Befund 7). Die Polizei findet dann immer die richtige Person.
  Einbrüche stehen im Stadtbuch mit Straße, ohne Namen; am nächsten Tag um 10 Uhr nimmt je Anzeige eine Kraft der Wache sie vor Ort
  auf (`polizeiEinsatz`, nur für Figuren und Karten).
- **Verfahren.** Urteil 3 Tage nach der Aufklärung. Untersuchungshaft bis zum Urteil (S4, S6) bei Wohnungseinbruch oder mit 2 nicht
  getilgten Verurteilungen. Stirbt die Person oder zieht weg, wird das Verfahren eingestellt.
- **Urteil** (Amtsgericht des Landes, `urteilen`): Tilgung abgelaufener Einträge, Einziehung der Beute an das Opfer (S3, § 73 StGB,
  § 459h StPO), Widerruf einer laufenden Bewährung. Diebstahl und Betrug: 30 Tagessätze, beim zweiten Mal 90; ein Tagessatz ist das
  Nettoeinkommen eines echten Tages (Tagesnetto / 36,5, § 40 StGB). Nicht bezahlbar: **Ersatzfreiheitsstrafe, 2 Tagessätze = 1 Tag**
  (§ 43 StGB in der Fassung seit 1. 2. 2024), auf ganze Spieltage aufgerundet, mindestens 1 (Befund 2). Ab 2 Vorstrafen 6 Monate,
  Wohnungseinbruch 1 Jahr Freiheitsstrafe (Mindeststrafe, § 244 Abs. 4 StGB). Keine Aussetzung schon im Urteil (S5): beim ersten Mal
  die Hälfte absitzen, wenn das mindestens 6 Monate sind, sonst zwei Drittel; der Rest ist 30 Tage (3 Jahre) zur Bewährung ausgesetzt
  (§ 57 StGB als Mindestverbüßung, § 56a StGB). Untersuchungshaft wird angerechnet (§ 51 StGB; bei einer Geldstrafe 1 Tag =
  1 Tagessatz, Abs. 4). Stadtbuch ohne Namen, mit Alter.
- **Register** (Tilgung nach § 46 BZRG, vereinfacht, Befund 6): 5 Jahre für eine Geldstrafe bis 90 Tagessätze, wenn keine
  Freiheitsstrafe eingetragen ist (Abs. 1 Nr. 1a); 10 Jahre für eine Geldstrafe neben einer eingetragenen Freiheitsstrafe (Nr. 2a) und
  für eine erste Freiheitsstrafe bis 1 Jahr mit Bewährung (Nr. 2b); 15 Jahre für alle anderen plus die Dauer der Freiheitsstrafe
  (Nr. 4, Abs. 3); getilgt erst, wenn alle Einträge tilgbar sind (§ 47 Abs. 3).
- **Haft** (`haftAntritt`): Die Stelle ist weg (ein eigener Betrieb läuft weiter), Grundsicherung endet (§ 7 Abs. 4 SGB II). Platz in der
  Anstalt in der Stadt (sie gehört dem Land), sonst in einer Anstalt des Landes außerhalb. Wohnung, Haushalt, Partner und Miete bleiben. Keine Entscheidungen,
  keine Anfragen ans Sprachmodell, kein Einkauf, Wohnen 30, Zufriedenheit −20; in Strafhaft und kurzer Haft 7 Taler Arbeitsentgelt am
  Tag vom Land, in Untersuchungshaft nicht. Rente läuft weiter, Beitragstage (Schritt 2) sammelt in Haft niemand. Zählt nicht als
  erwerbsfähig oder arbeitslos, begeht keine Taten, wird nicht Opfer, wird nicht neuer Partner; zieht der Partner weg, bleibt die Person
  in Haft. Kommt eine Strafe dazu, wird sie angehängt; kommt während der Untersuchungshaft eine Ersatzfreiheitsstrafe aus einem anderen
  Verfahren, bleibt die Untersuchungshaft bis zum Urteil, die Strafe folgt danach (`haftNach`, Befund 9).
- **Entlassung** am Ende der Strafe: Gedächtnis „aus der Haft entlassen“, der eigene Betrieb ist wieder da. Rückfall wird nur gezählt
  (neue Verurteilung binnen 3 Jahren).
- **Kinder** (Befund 3, `obhutPruefen`): Hat ein Haushalt keinen Erwachsenen mehr, der nicht in Haft ist, leben die Kinder bis zur
  Entlassung beim anderen Elternteil, bei den Großeltern oder bei erwachsenen Geschwistern in der Stadt (Familie vor Pflegefamilie nach
  S. 155 des Programms; die Reihenfolge innerhalb der Familie ist eine Annahme der Stadt, das Programm nennt nur „zum Beispiel die
  Großeltern“); gibt es niemanden, nimmt das Jugendamt sie in Obhut und bringt sie in einer Pflegefamilie außerhalb der Stadt unter (§ 42
  SGB VIII, eine vorläufige Unterbringung; für längere Zeit in einer anderen Familie sieht das Gesetz die Vollzeitpflege vor, § 33 SGB VIII,
  die Stadt unterscheidet das nicht; der Kita-Platz wird frei). Das Stadtbuch sagt „einziger Erwachsener“ nur, wenn es einer war, sonst
  „alle 2 Erwachsenen“. Das liest nur die Eltern-Verweise, keine Namen. Stadtbuch ohne Namen, Personen- und Hauskarte
  zeigen, wo das Kind ist. Kein Kind bleibt allein (`--sicherheit` prüft jede Nacht).
- **Land.** Die **Polizeiwache** baut das Land ab der Stufe Kleinstadt auf einem Block nah an der Mitte, die **Justizvollzugsanstalt** ab
  der Stufe Stadt auf zwei Blöcken am Stadtrand, beide über die Gelände-Schnittstelle aus Teil 1 (`gelaendeSuchen`, `gelaendeBauen`).
  Das Land zahlt den Bau an die Stadtkasse (1.500 und 8.000 Taler), der Bauhof baut (10 und 40 Arbeitstage). Findet sich kein freier
  Block, versucht es das Land in der nächsten Nacht wieder. Stellen der Wache: 3,2 je 1.000 Einwohner mal 1,2 (S1), mindestens 2; Lohn
  100 + 5 Zulage (S2). Anstalt: 12 Plätze; die Plätze, die die Stadt nicht braucht, belegt das Land bis zur mittleren Auslastung in
  Deutschland (82 %) mit Gefangenen von außerhalb; Stellen 0,65 je Gefangenem (auch je Gefangenem von außerhalb), Lohn 100. Offene
  Stellen des Landes nehmen Arbeitsuchende der Stadt; ziehen Leute für Arbeit zu, besetzt das Land seine offenen Stellen zuerst
  (Versetzung, S-A19). Die Löhne zahlt das Land (Zweig `istLand` in `wirtschaft`, nie aus dem Budget); die Lohnsteuer geht wie jede
  Lohnsteuer an die Stadt.
- **Grenze der Stadt.** Keine Regel liest Namen, Geschlecht (außer für die Grammatik), Herkunft, Einzugstag, Eltern (außer der Suche nach
  Angehörigen für ein Kind), Gedächtnis oder Stadtteil; Staatsangehörigkeit, Religion und Sprache kennt die Stadt nicht. `--sicherheit`
  prüft das je Funktion statisch (erlaubte Personenfelder), und mit getauschten Namen läuft die Stadt bitgleich. Die Polizei ermittelt
  nur angezeigte Taten, ohne Kameras und Überwachung, und kontrolliert keinen Stadtteil. Frauen und Männer sitzen in derselben
  Abteilung (in Wirklichkeit getrennt, § 140 Abs. 2 StVollzG); die Stadt trennt nicht, weil keine Regel das Geschlecht liest.

### Programmpunkte (Fenster „Stadtregierung“, Gruppe „Innere Sicherheit (Einrichtungen des Landes)“)

Elf Karten im Stil der übrigen (Titel, Status, wörtliche Zitate mit Seite, „In der Stadt“, Annahme, aufklappbarer Teil, Zahlen):
„Taten, Anzeige und Aufklärung“ (Spielregel), **S1** „Mehr Polizei: 20 % über der üblichen Dichte“ (S. 117, 118; steht im Abschnitt über
Clan- und Bandenkriminalität, übernommen ist nur die Personalstärke), **S2** „Gefährdungszulage“ (S. 119; eine Zulage gibt es schon, BBesG
Anlage I Vorbemerkung Nr. 9), **S3** „Beute wird eingezogen“ (galt schon, S. 117, § 73 StGB, § 459h StPO; Abschnitt organisierte und
Clan-Kriminalität), **S4/S6** „Mehrfachtäter und Wohnungseinbruch: gleich in Untersuchungshaft“ (S. 118, 119; S4 steht unter
Jugendstrafrecht, die Stadt überträgt es auf Erwachsene, Deutung der Stadt; vorher §§ 112, 112a StPO), „Jugendstrafrecht nur bis 18“ (wirkt;
heute § 105 JGG für Heranwachsende; nicht mehr unter „gilt schon“, Befund 6), **S5** „Bewährung erst nach Mindestverbüßung“ (S. 119, §§ 56,
56a, 57 StGB), **S7** „Kurze Haft, Ersatzfreiheitsstrafe und Untersuchungshaft getrennt“ (S. 119; drei Abteilungen, U-Haft mit eigenem Hof,
§ 3 Abs. 1 UVollzG NRW, Befund 5; Frauen und Männer nicht getrennt, § 140 Abs. 2 StVollzG, als Vereinfachung genannt), „Gericht, Strafen und
Register“ (Spielregel, geltendes Recht vereinfacht), „Justizvollzugsanstalt für die Region“ (Annahme der Stadt; Auslastung, Personal, USA),
„Kinder, deren Erwachsene alle in Haft sind“ (Annahme der Stadt, S. 155; bis zur Schlussprüfung „Kinder, deren einziger Erwachsener in Haft ist“). Sechs Karten haben eine Zeile mit Zahlen (`regLive`: taten,
polizei, haft, gericht, jva, obhut), fünf einen aufklappbaren Teil.

**Wirklichkeit** (Befund 6, Befunde 2 und 3 von „erweiterung“, Befund X7 der Schlussprüfung): Die Polizei (außer Bundespolizei und
Bundeskriminalamt), Gerichte und Gefängnisse sind Sache der Länder (Art. 30 und 92 GG; den Strafvollzug regeln die Länder seit der
Föderalismusreform 2006, Art. 74 Abs. 1 Nr. 1 GG nennt ihn nicht mehr). Städte haben Ordnungsämter, in Hessen auch Ordnungspolizei:
Hilfspolizeibeamte der Gemeinden, die im Rahmen ihrer Aufgaben die Befugnisse von Polizeivollzugsbeamten haben (§ 99 HSOG, auf anwalt24.de
und gesetze.co nachgelesen); manche nennen sie Stadtpolizei. (Bis zur Schlussprüfung stand hier „keine eigene Vollzugspolizei“ ohne diese
Befugnisse.) In den USA haben Städte eine eigene Polizei; Jails gehören meist Counties oder
Städten und nehmen Untersuchungshaft und Strafen bis etwa 1 Jahr auf, Prisons gehören den Bundesstaaten oder dem Bund (Bureau of Justice
Statistics). Das Fenster sagt das an der Wache und an der Anstalt.

Hinweiskasten (Befund 8): Die Polizei ermittelt ohne Kameras und Überwachung, eine Grenze der Stadt, die S. 124 stützt; für den Grenzschutz
fordert das Programm dagegen „elektronischer Überwachungssysteme“ (S. 125), für „No-go-Areas“ „Razzien und Kontrollstellen“ (S. 122), beides
nicht übernommen. „Geld von außen“ hat zwei Zeilen „Land, gestern“ und „Land seit dem Start“, „Von außen, gestern“ oben links enthält das Land.

Nicht übernommen (Befund 1, vollständig für das Kapitel Innere Sicherheit S. 116–125 und die Stellen S. 101, 107, 134, 138; Abdeckung aller
Sätze des Kapitels mit `mess/abdeckung.py` geprüft; übrig sind nur Beschreibungen und Erläuterungen zu gelisteten Punkten, `mess/abdeckung.txt`): „Grenze der Stadt“ +32 (Ausländerkriminalität und ausländerrechtliche Mittel,
Aufenthaltsrecht, Ausweisung, Präventivhaft, Einbürgerung, Subkulturen nach Herkunft und „Erscheinungsformen … sind zu zerschlagen“,
Abschiebung, Migrationshintergrund, Strafvollzug in Drittstaaten, politischer Islam, Kalifat und Abschiebung der Teilnehmer, Koranschulen,
Friedensrichter und ihre Rechtsfolgen, S. 123 Körperschaftsstatus, Moscheegemeinden, Moscheefinanzierung, Islamkritik, „Jüdisches Leben …“,
Imame mit Zertifikat C1 (Sprache), Lehrstühle, Minarette, S. 124 Personenstandsregister, Eheverträge nach deutschem Recht, Ehen von Muslimen
(„Sie sind zu annullieren.“), Unterdrückung muslimischer Frauen, S. 125 Burka, Vermummungsverbot und Kopftuchverbot, S. 101 und 107);
„Kein Gegenstück“ +24 (Grenzkontrolle, Unterwanderung, Steueranteil der Justiz, Dienst- und Disziplinarrecht, Prozessordnung, Waffenrecht
(S. 120, beide Sätze), Linksextremismus, Antifa, Klimaextremisten, Extremisten-Vereine, Al-Quds-Tage, Bundespolizei mit Besoldung, Ruhestand
mit 60, Überwachungssysteme und § 71 AufenthG, politische Beamte S. 134, Staatsanwaltschaft S. 138); „Keine Zahl, keine Mechanik oder kein
Fall“ +6 (Strafmündigkeit 12, Altersfeststellung, Justizpersonal, Befugnisse, Nachweispflicht für Familienmitglieder, antisemitische Angriffe
und Beleidigungen: kein Fall). Geänderte Gründe: „No-go-Areas“ (die Polizei des Landes ermittelt nur angezeigte Taten, in jedem Stadtteil
gleich) und „Videoüberwachung“ unter „Gilt schon“. Der Satz „Zur Vollständigkeit“ nennt jetzt auch die innere Sicherheit.
Alle Zitate im Fenster: **209**, `zitatpruef.py` 209 gefunden, `zitate_genau.py` 209 auf der genannten Seite, 0 Fehler (gesammelt mit
`mess/zitate_sammeln.mjs`, jetzt mit dem Hinweiskasten zur Sicherheit; Teil 1: 133).

### Annahmen (S-A1 … S-A28)

| # | Annahme | Wert | Begründung, Quelle |
|---|---|---|---|
| S-A1 | Grundneigung | 0,0032 je Erwachsenem und Nacht | Eingestellt auf die PKS 2024 des BKA: Diebstahl „etwas mehr als 1,94 Millionen“ Fälle, darin 78.436 Wohnungseinbrüche, Betrug 743.472 (Inland). Bei rund 83,6 Mio. Einwohnern (Annahme) je 1.000 und Jahr 22,3 / 0,94 / 8,9, zusammen 32,1. Gemessen (unten): Seeds 1–80 22,35 / 0,95 / 8,92 = 32,2 |
| S-A2 | Treiber der Tatneigung | Geldnot bis ×8·(0,5 + Ehrgeiz), ohne Stelle +2, Unzufriedenheit +3 | Die Stadt kennt Geld, Arbeit, Zufriedenheit und Charakter; Ehrgeiz verstärkt nur die Not (Anomie- bzw. Strain-Theorie). Heimatliebe bewusst nicht. Vorstrafen nicht (Befund 10: Beschreibung und Code stimmen überein) |
| S-A3 | Art der Tat | 69,4 / 2,9 / 27,7 % | Anteile der drei Delikte an den angezeigten Fällen der PKS 2024 |
| S-A4 | Beute | 10 / 60 / 20 Taler | Größenordnung (etwa 520 / 3.100 / 1.000 € nach U1), nicht nachgeschlagen |
| S-A5 | Aufklärungsquoten | 31,4 / 15,3 / 58 % | PKS 2024 (BKA-Meldung vom 23. 4. 2025: Diebstahl 31,4 %, alle Straftaten 58 %; BKA-Factsheet Wohnungseinbruch 15,3 %); für Betrug die Quote aller Straftaten, eine eigene Betrugsquote ist nicht nachgeschlagen |
| S-A6 | Polizeidichte und Wirkung | 320 je 100.000 (0,0032); Faktor 2d/(d + 1), Bezirk | Eurostat `crim_just_job`, Deutschland 2024: 320,38 Polizeibeamte je 100.000. Der Nutzen nimmt ab; die Wache einer kleinen Stadt ist auch für das Umland da (Befund 7). Eurostat zählt alle Polizeibeamten, auch Bundespolizei und Bundeskriminalamt; die Wache ist Landespolizei und nimmt die ganze Dichte (vereinfacht, im Fenster gesagt, Befund X7 der Schlussprüfung) |
| S-A7 | „Erhebliche Aufstockung“ (S1) | +20 % | Das Programm nennt keine Zahl |
| S-A8 | Löhne | Polizei 100 + 5 Zulage, Vollzug 100 | Standardstelle; die heutige Zulage steckt in den 100 (BBesG Anlage I Vorbemerkung Nr. 9), die 5 sind die Gefährdungszulage (S2, Höhe nicht im Programm) |
| S-A9 | Polizeiwache | ab Kleinstadt, 1 Block nah an der Mitte, mindestens 2 Stellen, 1.500 Taler, 10 Arbeitstage | Damit man sie sieht; kleine Orte teilen sich in Wirklichkeit eine Wache (Fenster sagt das). Die Stufe ist ein Spielmaßstab, keine Aussage darüber, wo Wachen stehen. Bau durch den Bauhof ist eine Vereinfachung: In Wirklichkeit baut das Land über seine Bauverwaltung, Firmen bauen nach Ausschreibung (Wissen, nicht einzeln nachgeschlagen); im Fenster als Hinweis (Befund X14) |
| S-A10 | Justizvollzugsanstalt | ab Stadt, 2 Blöcke am Rand, 12 Plätze, Auslastung 82 %, 0,65 Bedienstete je Gefangenem, 8.000 Taler, 40 Arbeitstage | Noahs Entscheidung „Anstalt für die Region“. 58.798 Gefangene auf 72.096 Plätzen am 30. 11. 2024 (Destatis, nach REITOX-Bericht 2025, Workbook Gefängnis; Eurostat `crim_pris_cap` gleich); Personal 37.557 in Anstalten für Erwachsene, 57.465 Gefangene (Eurostat 2022). Größe und Stufe sind Spielmaßstab. Bau durch den Bauhof: Vereinfachung wie bei S-A9, im Fenster als Hinweis |
| S-A11 | Arbeitsentgelt in Haft | 7 Taler am Tag vom Land (nicht in U-Haft) | Arbeitspflicht § 41 StVollzG, Entgelt § 43 mit Eckvergütung 9 % der Bezugsgröße (§ 200); Bezugsgröße 2024 42.420 € (§ 1 SvBezGrV 2024) → 3.817,80 € im Jahr ≈ 7 Taler je Spieltag nach U1. Bundesrecht; die Landesgesetze nicht einzeln geprüft. Das Fenster sagt: nach dem Strafvollzugsgesetz des Bundes; heute regeln das die Strafvollzugsgesetze der Länder, teils anders (nicht einzeln geprüft; Befund X9) |
| S-A12 | Verfahrensdauer | 3 Spieltage (etwa 4 Monate) | Nicht nachgeschlagen |
| S-A13 | Mehrfachtäter (S4) | ab 2 nicht getilgten eigenen Verurteilungen | Das Programm definiert den Begriff nicht |
| S-A14 | Strafmaß | 30 / 90 Tagessätze, 6 Monate, 1 Jahr (Einbruch); Tagessatz = Tagesnetto / 36,5; EFS 2 TS = 1 Tag | Wie üblich zuerst Geldstrafe; § 40, § 43, § 244 Abs. 4 StGB nachgelesen |
| S-A15 | Mindestverbüßung (S5) und Bewährung | Hälfte (erstes Mal, ≥ 6 Monate) sonst zwei Drittel; Bewährung 3 Jahre | § 57 StGB als Mindestverbüßung, § 56a StGB (2–5 Jahre). Vorher-Modus (`R.S5_MINDEST = 0`): erste Freiheitsstrafe bis 1 Jahr ganz zur Bewährung (§ 56) |
| S-A16 | Kurze Haft (S7) | bis 3 Spieltage | Das Programm bestimmt „Kurzzeithäftling“ nicht |
| S-A17 | Leben in Haft | Wohnen 30, Zufriedenheit −20, keine Entscheidungen, kein Einkauf; Miete und Rente laufen | Freiheitsentzug ohne Gewalt; Rente läuft (ihre-vorsorge.de, nicht amtlich), keine Rentenbeiträge aus Gefangenenarbeit (§ 198 Abs. 3 StVollzG: die Vorschriften §§ 190–193 sind nie in Kraft gesetzt) |
| S-A18 | Folgen für Opfer | Zufriedenheit −5 / −10 / −5 für 10 / 20 / 10 Tage; Einbruch Wohnen −20 für 20 Tage | Ein Einbruch trifft das Sicherheitsgefühl zu Hause am stärksten. Gemessen: Opfer ziehen öfter weg (unten) |
| S-A19 | Stellen des Landes | zuerst aus der Stadt, sonst Zuzug („das Land versetzt Beamte“) | Ohne Zuzug blieben Wache und Anstalt oft 200 Tage unbesetzt |
| S-A20 | Haftantritt | Stelle weg, Betrieb bleibt, Partner in Haft wird beim Wegzug nicht mitgenommen | Einfachste konsistente Lösung |
| S-A21 | Tilgung | 5 / 10 / 15 Jahre (+ Dauer) | § 46, § 47 Abs. 3 BZRG nachgelesen, vereinfacht (Befund 6) |
| S-A22 | Kein Dunkelfeld | alle Taten angezeigt | Einfach und ehrlich benannt (Fenster) |
| S-A23 | Keine Falschverdächtigung, kein Freispruch | aufgeklärt = richtige Person | Justizirrtümer sind nicht abgebildet (Schwächen) |
| S-A24 | Eigener Zufallsstrom | `S.rsSich` = seed ^ 0x9E3779B9 (Übernahme: ^ Tag) | Deterministisch und speicherbar; die übrige Stadt zieht dieselben Zahlen |
| S-A25 | Stadtbuch ohne Namen | Alter und „Einwohner/Einwohnerin“ | Wie in Berichten über Strafverfahren; die Personenkarte zeigt die eigene Lage |
| S-A26 | Hofzeiten | Strafhaft 10 und 15, kurze Haft und EFS 11 und 16, U-Haft 9 und 14 Uhr | Getrennte Abteilungen (S7, § 3 Abs. 1 UVollzG NRW); nur dann sind Gefangene zu sehen |
| S-A27 | Steuer | Landeslöhne voll lohnsteuerpflichtig (an die Stadt), Arbeitsentgelt in Haft steuerfrei | Die Lohnsteuer geht in der Stadt schon ganz an die Stadt (Stadtregierung) |
| S-A28 | Kinder, deren Erwachsene alle in Haft sind | Angehörige in der Stadt (anderer Elternteil, Großeltern, erwachsene Geschwister), sonst Jugendamt (Pflegefamilie außerhalb) | Familie vor Pflegefamilie nach S. 155 des Programms; die Reihenfolge innerhalb der Familie ist eine Annahme der Stadt (Befund X5 der Schlussprüfung). § 42 SGB VIII (vorläufig); Vollzeitpflege (§ 33 SGB VIII) im Fenster genannt, nicht abgebildet; Aufschub (§ 456 StPO, höchstens 4 Monate) nicht abgebildet |

**Quellen** (abgerufen September 2026; Kopien in `scratchpad/erw7/recht/`): Gesetze auf gesetze-im-internet.de (StGB §§ 40, 42, 43, 51, 56,
56a, 56f, 57, 73, 244; EGStGB Art. 293; StPO §§ 112, 112a, 456, 459h; BZRG §§ 36, 46, 47; JGG § 105; SGB II § 7; SGB VIII § 42; StVollzG
§§ 41, 43, 140, 198, 200; SvBezGrV 2024 § 1; BBesG Anlage I; GG Art. 30, 74, 92), UVollzG NRW § 3 (recht.nrw.de, PDF Stand 1. 4. 2026),
§ 99 HSOG (gesetze.co und Wikipedia „Ordnungspolizei (Hessen)“), Gesetz zur Überarbeitung des Sanktionenrechts (BMJ-Pressemitteilung, LTO),
BKA-Kurzmeldungen vom 23. 4. und 25. 4. 2025 zur PKS 2024 (Diebstahl, Betrug; am 27. 9. 2026 noch einmal gelesen), BKA-Factsheet PKS 2024
Wohnungseinbruchdiebstahl, Eurostat `crim_just_job` und `crim_pris_cap` (API), REITOX-Bericht 2025 Workbook Gefängnis (dhs.de), berlin.de
Justizvollzug „Zahlen und Fakten“ (Gefangenenrate 69 nach World Prison Brief), Bureau of Justice Statistics „Correctional Institutions“ und
„Local Police Departments: Personnel, 2020“ (bjs.ojp.gov), DRV-Meldung vom 19. 7. 2022, ihre-vorsorge.de (Rente in Haft).
Die Föderalismusreform 2006 als Zeitpunkt ist Wissen; geprüft ist nur, dass Art. 74 Abs. 1 Nr. 1 GG heute den Strafvollzug nicht nennt.
Neu mit der Schlussprüfung (27. 9. 2026): § 33 SGB VIII (Vollzeitpflege) auf gesetze-im-internet.de (per curl, Kopie
`scratchpad/erw7/recht/sgb_8___33.html`; WebFetch bekam dort 503), § 99 HSOG noch einmal auf anwalt24.de (Befugnisse der
Hilfspolizeibeamten, in Gemeinden „Ordnungspolizeibeamte“). Dass die Länder den Bau über ihre Bauverwaltungen vergeben, ist Wissen, nicht
nachgeschlagen.

### Darstellung

Keine neuen Meshes: Wache und Anstalt liegen in `teil`, `tech`, `fenster`, `schlot`, `bau` und `baum` (Helfer `teilUV`, `techUV`,
`fensterUV`, `mastUV` in einem Rahmen je Gelände; `gelaendeRahmen`, `jvaPlan`). **Wache** (ein Block): gepflasterter Hof, zwei Geschosse
hellgrau mit blauem Band, Fensterbänder (nachts unten Licht), leuchtendes blaues Schild, Tür mit Lampe, Funkantenne, Parkplatz mit bis zu
zwei stillstehenden Streifenwagen, ein Baum. **Anstalt** (zwei Blöcke): dunkle Grundfläche, Mauer mit Krone, Pforte am Tor (nachts Licht),
Hafthaus mit drei Geschossen, schmalen Fensterbändern und Gittern (abends 18–22 Uhr gedämpftes Zellenlicht), Verwaltung mit Werkstätten,
drei Höfe mit Zäunen und je einem Lichtmast, zwei Türme. Liegt die Straße an der Längsseite, steht die Verwaltung hinter der Pforte und die
Höfe liegen links und rechts, sonst an der Schmalseite. Im Bau wachsen Rohbau (und Mauer) mit Gerüst. Klick irgendwo aufs Gelände öffnet
die Hauskarte; Auswahlrahmen, „Zeigen“, Bildausschnitt, Straßennamen und Ereignis-Ring nehmen das ganze Gelände (`gelaendeVon`, `gebFlaeche`).
**Figuren:** Polizei dunkelblau (`POLIZEI_F` #2c4c86), Justizvollzug graugrün (`VOLLZUG_F` #5a6d56), als Arbeitende vor ihrem Gebäude; um
10 Uhr geht, wer eine Anzeige aufnimmt, zum Tatort und zurück (wie die Kistenträger; die Simulation nennt die Anzeige). Gefangene sieht man
**nur zu ihrer Hofzeit im Hof ihrer Abteilung** (`simOrt` liefert sonst −1), auf freien Figurenplätzen, fester Platz je Person. Hilfe: eine
Zeile „Dunkelblau: Polizei … Graugrün: Justizvollzug. Gefangene sieht man nur zu ihrer Hofzeit im Hof der Anstalt.“ (Hilfe bei
1280 × 800 weiter ohne Überlauf, 745 von 745 px). Stadtbuch: Art „Sicherheit“ mit Schild-Symbol. Hauskarte: Symbole Schild und Gitter,
im Wohnhaus „in Haft“, „zur Zeit bei Angehörigen“, „zur Zeit beim Jugendamt“. Personenkarte: Haft (Art, bis, Anstalt als Knopf,
Hofgang), Strafverfahren, Register und Bewährung, bei wem Kinder in Obhut leben. Keine Allokation je Bild (alles stündlich in `stadt()`
und `figurenPlanen`), reduzierte Bewegung ohne Neues, die Kamera bewegt sich nicht von selbst.

**Sprachmodell** (Befund 4): Die Anweisung nennt nur Tatsachen der Figur (Haft mit Ort und Ende, Strafverfahren mit Urteilstag,
Bewährung, Kinder in Obhut). Wer Opfer war, bekommt „Wer dich bestohlen, betrogen oder bei dir eingebrochen hat, weißt du nicht, und du
verdächtigst niemanden.“, jede Figur „Du weißt nur, was du selbst erlebt hast, und beurteilst niemanden nach Name, Herkunft, Sprache oder
Religion.“ `--kitest` führt den Code der Anweisungen mit der echten Simulation aus und prüft das, auch dass der Name des Täters nie in der
Anweisung des Opfers steht und keine Anweisung die Stadtregierung nennt.

### Gemessen

**Seeds 1–3** (`simtest --gate`, 730 Tage stündlich, alle Gates bestanden; in Klammern bc7247a):

| Seed | Einwohner Tag 365 / 730 | Band Gate 4 | Gate 6 / Gate 7 | Stadtbuch je Tag | Taten (D / E / B) | aufgeklärt | Urteile (Geldstrafe / EFS / Freiheitsstrafe) | Haftantritte (außerhalb) | Wache / Anstalt ab Tag |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 802 / 1.146 (886 / 1.065) | 1,09 (1,06) | +18,5 / −23,1 (+20,8 / −29,3) | 4,78 (4,25) | 1.237 / 63 / 467 | 41 % | 707 (670 / 104 / 37) | 142 (31) | 79 / 190 |
| 2 (Teststadt) | 753 / 1.157 (858 / 1.122) | 1,13 (1,08) | +20,4 / −23,0 (+20,0 / −22,9) | 5,08 (4,33) | 1.196 / 55 / 471 | 43 % | 728 (709 / 114 / 19) | 131 (40) | 71 / 198 |
| 3 | 905 / 1.118 (944 / 1.082) | 1,05 (1,11) | +17,7 / −23,3 (+20,0 / −29,1) | 4,54 (4,78) | 1.223 / 44 / 476 | 43 % | 738 (722 / 87 / 16) | 104 (29) | 64 / 167 |

Mit dem Baustein läuft die Stadt anders (Taten verschieben Geld, Stellen und Entscheidungen), deshalb sind einzelne Seeds nicht vergleichbar.
Verglichen wird über viele Seeds, mit derselben Messung (`mess/mess8.mjs` über `mess/lauf80_8.sh` und `mess/lauf160_8.sh`, Auswertung
`mess/vergleich_sich.py` und `mess/vergleich_sich160.py`, Ausgabe `mess/vergleich_sich160.txt`), 730 Tage stündlich, **gegen bc7247a**:

| Seeds | Stand | alle Gates | fällt | Band Ø / Median / schlimmster | Gate 7 kleinster Abstand | Einwohner Tag 365 / 730 | Wegzüge (Personen) | Zuzüge |
|---|---|---|---|---|---|---|---|---|
| 1–80 | bc7247a | 77 von 80 | G4: 11, 23, 45 | 1,077 / 1,073 / 1,155 | 16,5 | 896 / 1.110 | 40,2 | 1.028 |
| 1–80 | Teil 2 | 76 von 80 | G4: 22, 34, 57, 71 | 1,082 / 1,078 / 1,210 | 18,1 | 892 / 1.138 | 62,9 | 1.066 |
| 81–160 | bc7247a | 76 von 80 | G7: 108; G4: 112, 130, 140 | 1,075 / 1,065 / 1,185 | 13,9 | 891 / 1.110 | 40,0 | 1.028 |
| 81–160 | Teil 2 | 78 von 80 | G4: 153, 155 | 1,073 / 1,067 / 1,168 | 15,5 | 896 / 1.136 | 61,2 | 1.067 |

Zusammen 154 von 160 gegen 153 von 160: **kein Unterschied über das Rauschen hinaus** (Befund 11; ein „besser“ gibt es nicht). Teil 1
lag auf den Seeds 1–80 zahlengleich mit bc7247a. Die Karte wächst im Median weiter auf 80 × 80 (64 bis 112).

- **Taten** je 1.000 Einwohner und Jahr (Tag 366–730): Seeds 1–80 Diebstahl 22,35, Wohnungseinbruch 0,95, Betrug 8,92, zusammen 32,2
  (kleinste Stadt 28,9, größte 41,2); Seeds 81–160 zusammen 32,1; PKS 2024: 22,3 / 0,94 / 8,9 = 32,1. Aufgeklärt 34 % / 17 % / 63 %
  (PKS 31,4 / 15,3 / 58; mehr wegen S1).
- **Haft:** im Mittel 0,24 Leute aus der Stadt in Haft (höchstens 6 zugleich), 24 je 100.000 Einwohner; Deutschland 69 (World Prison
  Brief, nach berlin.de), dort mit allen Delikten. Je Stadt und 730 Tage: 730 Urteile, 103 Ersatzfreiheitsstrafen, 23 Freiheitsstrafen,
  23 Untersuchungshaften, 127 Haftantritte (26 außerhalb, meist bevor es die Anstalt gab), 2,9 Widerrufe, 32 Verurteilungen binnen 3 Jahren nach
  einer Entlassung. Die Anstalt ist durch die Gefangenen von außerhalb meist mit 10 von 12 Plätzen belegt.
- **Kinder:** In 65 von 80 Städten kam mindestens einmal ein Kind in Obhut, im Mittel 2,2-mal bei Angehörigen und 0,2-mal beim Jugendamt
  (11 Städte), zusammen 4,6 Kindertage je Stadt. Kein Kind war je allein (`--sicherheit`, jede Nacht).
- **Land:** Wache im Mittel ab Tag 73 (58–115), Anstalt ab Tag 176 (148–225), etwa 5 bzw. 3 Tage nach der Stufe; das Land zahlt im Mittel
  719 Taler am Tag Löhne und Arbeitsentgelt, dazu 9.500 Taler für die Bauten.
- **Wegzüge** (neu gemessen, `mess/dbg/wegzug_mess.mjs`, Seeds 1–6): Mit dem Baustein ziehen etwa doppelt so viele Erwachsene weg (312 gegen
  159 mit abgeschalteter Sicherheit), fast alle im ersten Jahr (274 gegen 137). 82 davon waren in den 20 Tagen davor Opfer, 66 in den
  30 Tagen davor aus der Haft entlassen; der Grund im Stadtbuch ist fast immer „Das Geld reicht nicht“. In der jungen Stadt haben viele wenig
  Erspartes: Beute, Geldstrafe und eine verlorene Stelle treffen sie, und das Ereignis löst eine Entscheidung aus. Gate 7 hält (Abstand
  eher größer), die Zuzüge gleichen es aus (Einwohner an Tag 730 sogar höher, auch durch die Stellen des Landes). Das steht unter
  „Bekannte Schwächen“.
- **Nach Gruppen** (`simtest --sicherheit`, Seeds 1–6, Tag 200–730, verurteilt bzw. Opfer je Erwachsenen-Nacht relativ zu allen, nur
  gemessen): in der Stadt geboren 1,13 / 0,95, zugezogen oder vom Start 0,98 / 1,01, Nachnamen Kaya bis Kowalski (Namensliste 31–37)
  1,01 / 1,06, übrige Nachnamen 1,00 / 0,99, Frauen 1,03 / 1,00, Männer 0,97 / 1,00, 18–24 Jahre 1,40 / 1,04, 67+ 0,80 / 0,92. Die
  Unterschiede kommen aus Alter und Geld (mit 18 ohne Erspartes und Stelle), nicht aus Namen oder Herkunft; mit getauschten Namen läuft die
  Stadt bitgleich.
- **Sonst** (Seeds 1–80, gegen bc7247a): Zufriedenheit im Mittel 70,58 statt 70,95, Arbeitslose an Tag 730 4,97 statt 4,67 %, Stadtbuch
  4,93 statt 4,45 Zeilen am Tag (Einbrüche, Urteile mit Freiheitsstrafe, Obhut, Jahreszeile, Aufträge des Landes), schlimmster
  30-Tage-Einbruch 12,5 statt 18,8 %, kleinstes Budget gleich.
- **Leistung:** `--gate` Zeit-Check T 1,3–1,9 s für 365 Tage (< 5 s; zwei Läufe, im zweiten liefen die Browser-Tests gleichzeitig). Draw Calls im Browser 22–27 (Teststadt, Tag 400; bc7247a 25 bis 28),
  große Stadt 23–26 (bc7247a 24 bis 27). Neue Draw Calls: keine.
- **Große Stadt** (`&umland=300000`, Seed 2, Tag 750): 5.703 Einwohner (Teil 1: 5.928), Karte 104 × 104 (Teil 1: 120), Dreiecke
  129.500 bis 134.800.

### Speicherformat 7 (Sicherheit)

Neu je Person (`PF_SICHERHEIT`, Pflicht in jedem Stand der Version 7): `haftBis`, `haftArt` (1 Strafhaft, 2 kurze Haft oder EFS, 3 U-Haft),
`haftOrt` (1 Anstalt in der Stadt, 2 außerhalb), `haftNach`, `vorstrafen`, `tilgungBis`, `freiheitReg`, `bewaehrungBis`, `bewaehrungRest`,
`opferTag`, `opferArt`, `entlassenTag`, `obhut` (1 Angehörige, 2 Jugendamt), `obhutBei`, `obhutGen`. Dazu `S.rsSich` (Zahl), `S.sicherheit`
(Start, Wache, Anstalt, Stellen, von außerhalb, Verfahren, Tatorte, Jahreszahlen, Geld vom Land) und `S.stat.sicherheit` (Summen).
Gedächtnis-Codes OPFER 17 … OBHUT 21, Gebäudetypen WACHE 9 und JVA 10. `sicherheitPruefen` lehnt beschädigte Stände ab („Spielstand
beschädigt: Sicherheit (…)“; `--sicherheit` prüft 11 Fälle), ein fehlendes Personenfeld lehnt `jsonPruefen` ab („Spielstand unvollständig:
p.…“). **Übernahme** aus Version 2–6 (`migriereSicherheit`, vor „Stadt erweitern“): eigener Zufallsstrom, niemand vorbestraft, in Haft oder
Opfer, Summen 0, Stadtbuch „Ab heute gibt es in der Stadt Diebstahl, Wohnungseinbruch und Betrug …“ (vorletzte Zeile, vor der Zeile „Stadt
erweitern“); Wache und Anstalt bestellt das Land in den folgenden Nächten. Versionsdialog und Meldung nach der Übernahme sagen es. Mit
abgeschalteter Sicherheit läuft ein übernommener Stand der Version 6 60 Tage lang Tag für Tag wie in Version 6 (`--migrationstest`);
mit eingeschalteter Sicherheit beginnen ab dem Übernahmetag die Taten. `--speichertest`: **Fingerabdruck `cb0ce3e6a26986c7`** (Seed 1, Tag 150, 13 Uhr,
60 Tage weiter; Teil 1 `d918da4702073bbb`), neu, weil die Stadt jetzt Taten hat und der Fingerabdruck `S.sicherheit` enthält; dazu ein Stand
mit U-Haft, Gefangenen in der Anstalt, offenen Verfahren und einem Kind in Obhut (Tag 257): 60 Tage bitgleich, auch über sortierte Schlüssel
(`c26760c7c7d427ce`, sortiert `ecd31d017e4093a4`). Teststand `tests/basis_v7.json` neu aus `tests/basis_v6.json` über „Stadt übernehmen“
(`tests/basis_v7.cjs`; Tag 420, 2.186 Einwohner), jetzt mit den Feldern der Sicherheit; das Original bleibt.

### Tests

- `simtest --sicherheit` (neu, 28 Prüfungen): statisch (der Abschnitt zieht Zufall nur aus dem eigenen Strom; je Regel nur die erlaubten
  Personenfelder, keine Namen, Geschlecht nur fürs Pronomen im Urteil; der Zweig der Landeslöhne berührt das Budget nicht), Namenstausch
  (365 Tage bitgleich mit anderen Namen), Seeds 1–3 je 730 Nächte mit Invarianten nach jeder Nacht (Täter erwachsen und frei, Opfer aus
  einem anderen Haushalt, U-Haft nur mit offenem Verfahren, Plätze der Anstalt, Hof nur zur eigenen Zeit, kein Kind allein, Wache ab
  Kleinstadt und Anstalt ab Stadt auf eigenem Gelände, Stadtbuch ohne Namen, Landeslöhne nie aus dem Budget), erzwungene Urteile
  (30 und 90 Tagessätze ohne Geld, bezahlt, halb bezahlt, Einbruch mit U-Haft, Widerruf, Tilgung, Anrechnung, Randfall U-Haft mit
  Ersatzfreiheitsstrafe), volle Anstalt, Obhut (Angehörige, Jugendamt, Ende), Grundsicherung und Arbeitsentgelt in Haft, Speichern mit
  Haft, 11 beschädigte Stände, Messung gegen die PKS 2024 und nach Gruppen.
- `simtest --kitest` prüft dazu die Anweisungen ans Sprachmodell (Befund 4), `--speichertest` einen Stand mit Haft (Befund 11),
  `--migrationstest` und `--erweiterung` vergleichen mit Version 6 bei abgeschalteter Sicherheit, `--regierung` rechnet Haft und
  Landeslöhne mit.
- Browser: `tests/sicherheit.cjs` (neu, in `tests/alle.sh`): Wache und Anstalt auf eigenem Gelände, Gefangene nur zur Hofzeit im Hof ihrer
  Abteilung (jede Stunde 8–17 Uhr: sichtbar = im Hof, nie woanders), Polizei um 10 Uhr zum Tatort und zurück, Klick aufs Gelände öffnet die
  Hauskarte (Anstalt „nur als Zahl“, drei Abteilungen; Wache „Lohn 105 Taler am Tag vom Land“), Personenkarten für Strafhaft, U-Haft und ein
  Kind in Obhut, Hauskarte „in Haft“, Fenster (11 Karten, 6 mit Zahlen, Geld vom Land, Hinweis mit S. 125 und S. 122), Hilfe, Draw Calls
  ≤ 30, Konsole leer. `tests/p6migration.cjs` prüft die Sicherheit nach der Übernahme von Version 5 und 6 und dass das Land danach Anstalt
  und Wache baut; `tests/p7figuren.cjs` lässt Figuren auf dem ganzen Gelände von Wache und Anstalt zu (Grundregel sonst unverändert).
- **Angepasst an den neuen Verlauf der Teststadt** (feste Momente haben sich verschoben; keine Prüfung ist schwächer): `tests/ereignis.cjs`
  Momente neu gesucht (`mess/momente7.mjs`, mit wachsender Karte): Tag 572 (elf Übernahmen), 612 (sieben Schließungen), 617, 683; bei
  sieben Schließungen beginnt das siebte Zeichen erst bei 1,2 s, gezählt wird deshalb bei 1,3 s statt 1,1 s. `tests/erweiterung.cjs`: Die
  Teststadt wächst zuerst an Tag 198, in derselben Stunde bestellt das Land am Rand die Anstalt (neue Baustelle, ein Draw Call); geprüft
  wird jetzt das zweite Wachsen an Tag 230 (64 → 72, allein in seiner Stunde), die Stufe ist dort „Stadt“ (Hinweis „Großstadt ab 800 …“,
  jetzt der ganze Text), und vor beiden Messungen vergehen die Ereignis-Zeichen. `tests/kita.cjs`: Die Kamera steht auf der Kita, bevor die
  Figuren der Stunde geplant werden (die 120 Arbeitsplätze gehen nach Nähe zur Kamera; vom Startblick lag die Kita bei 1280 × 800 knapp
  dahinter), und die Personenkarte nimmt das erste Kind, das nicht gerade seinen letzten Kita-Tag hat (den prüft `befunde_s2`).
  `tests/befunde_s2.cjs` erwartet neun aufklappbare Karten mit Titel (vier bisher, fünf der inneren Sicherheit) statt vier.
- **Ergebnis** auf dem Endstand (`stadt.html` md5 `6affd7fb3de135433fa5da5ab064ac3e`, Server auf 8713, `tests/alle.sh`, KI-Nachbau auf
  11434): p3test 12, p5neu 10, p6migration 25, p7figuren 6, p8tech 14, raute_klick 8 von 8 Klicks, ereignis 21, t1_xss 5, p4test 25,
  s2karten 22, kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, alle ohne Fehler. `tests/otest`: befunde 21, handy 11, breit 12,
  tastatur 4, breiten 20, hilfehoehe ohne Überlauf (745 von 745 px). Dazu `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs` ohne
  Fehler. Konsole leer, außer den absichtlichen Verbindungsfehlern zum KI-Nachbau in p4test und den abgebrochenen KI-Anfragen in
  `blick.cjs`. Alle `simtest`-Modi auf dem Endstand ohne Fehler (`mess/s3_*.txt`): `--gate` (Seeds 1–3 alle Gates), `--speichertest`
  (bitgleich, beide Stände), `--aufholtest` (Vergleich, keine Prüfung), `--kitest` 46, `--bau` 15, `--waren` 15, `--tech` 16,
  `--regierung` 154 (Teil 1: 155; eine Person weniger im Fall „Bauhof voll“, keine Prüfung entfernt), `--kita` 40, `--sicherheit` 28,
  `--migrationstest --git /home/user/website-` 266, `--erweiterung --gross --git /home/user/website-` 33. Der sim-Block ist seit dem
  ersten Lauf der Suite unverändert (`mess/s2_*.txt` und `mess/s3_*.txt` gleich bis auf die Laufzeiten).
- **Bilder** (Endstand, selbst angesehen): `nachher/` (`tests/blick.cjs`, Teststadt Seed 2, Tag 400: 918 Einwohner, Großstadt, Karte
  80 × 80, 25 bis 27 Draw Calls, 44.800 bis 45.300 Dreiecke) und `nachher/sicherheit/` (`sich/sicht.cjs` und `mess/dbg/hof_bild.cjs`:
  Wache am Tag und in der Nacht, Anstalt am Tag, zur Hofzeit und in der Nacht, von oben um 10 Uhr mit vier Gefangenen im Hof der Strafhaft
  und dem Personal vor der Pforte, Hauskarten, Fenster). `gross/` (`&umland=300000`, Seed 2, Tag 750: 5.703 Einwohner, Karte 104 × 104,
  23 bis 26 Draw Calls). Die Bilder aus Teil 1 liegen in `scratchpad/erw7/sich/bilder_teil1/`.

### Befunde der Gegenprüfung „sicherheit“

Alle umgesetzt:

0. Zusammenhang: S4 steht unter Jugendstrafrecht („die Stadt überträgt sie auf alle Erwachsenen, … Deutung der Stadt“), S3 und S1 im
   Abschnitt Clan- und Bandenkriminalität; die Karten sagen es.
1. „Nicht übernommen“ vollständig (oben), mit S. 123, S. 124 Eheverträge, S. 125 § 71 AufenthG, S. 121 Kalifat-Abschiebung, S. 120 Waffenrecht;
   beim Nachprüfen aller Sätze des Kapitels kamen S. 116 („sämtliche ausländerrechtlichen Möglichkeiten“) und S. 117 („Erscheinungsformen …
   zu zerschlagen“) dazu.
2. Ersatzfreiheitsstrafe nach § 43 StGB (2 Tagessätze = 1 Tag); `--sicherheit` rechnet 30 und 90 Tagessätze und eine halb bezahlte Strafe nach.
   Das Aufrunden auf Spieltage steht in der Annahme („in der Stadt deshalb eher länger“).
3. Kinder bleiben nicht allein: Angehörige oder Jugendamt (oben), jede Nacht geprüft, im Stadtbuch und auf Personen- und Hauskarte.
4. Das Sprachmodell erfindet keine Verdächtigen: Sätze in der Anweisung, `--kitest` prüft sie.
5. Untersuchungshaft hat eine eigene Abteilung mit eigenem Hof (9 und 14 Uhr), nach § 3 Abs. 1 UVollzG NRW.
6. Tilgung nach § 46 BZRG (5/10/15 Jahre), Jugendstrafrecht als wirkende Regel mit § 105 JGG, Polizeizulage gibt es schon (BBesG), Städte haben
   Ordnungsdienste (§ 99 HSOG, Stadtpolizei), USA (Städte mit Polizei, Counties mit Jails, Staaten mit Prisons; BJS). Alle Rechtsnormen
   nachgelesen (Quellen oben).
7. Polizeidichte in kleinen Städten: Bezirk (Aufklärung nie über das Übliche mal der Aufstockung), Fenster sagt, dass kleine Orte sich eine Wache teilen.
8. „Keine Überwachung“ nicht einseitig: Hinweiskasten mit S. 125 und S. 122; die Grenze ist eine Regel der Stadt, S. 124 stützt sie.
9. Randfall `haftAntritt`: U-Haft bleibt bis zum Urteil, die Ersatzfreiheitsstrafe folgt danach (`haftNach`), in `--sicherheit` erzwungen.
10. Beschreibung und Code stimmen: Die Tatneigung liest keine Vorstrafen (Kommentar an `R`, Fenster, README); README-Abschnitt und Hilfe sind da.
11. Testwerkzeuge fertig: `--regierung` grün (Haft und Landeslöhne in den unabhängigen Erwartungen, Nächte mit Haftantritt einer erzwungenen
    Person zählen nicht, Bauhof-Fall überspringt Haft), `--speichertest` mit Haft (oben), „40/40“ gibt es nicht mehr: Die Gates werden neutral
    gegen bc7247a gezählt (oben, kein Unterschied über das Rauschen hinaus).

Aus der Gegenprüfung „erweiterung“ galten für Teil 2 weiter: Befund 2 (Zuständigkeiten als eigene Sachaussage mit Quelle, Art. 30 und 92 GG,
nicht dem Programm zugeschrieben), Befund 3 (USA-Hinweise zu Polizei und Jails) und Befund 10 (Stufen als Spielmaßstab, nicht als
Realismus-Aussage). Umgesetzt.

**Weitergeführt nach dem Abbruch** (Teil 2 lief zweimal; der erste Lauf endete am Sitzungslimit, nachdem die simtest-Suite gelaufen war):
Die Suite stimmte mit dem Stand überein (Prüfsumme). Neu danach nur Texte im Fenster (`sich/patch_fenster2.py`: zwei Sätze S. 116 und 117,
§ 46 Abs. 1 Nr. 2a BZRG richtig wiedergegeben, § 140 StVollzG, Zuständigkeit mit Art. 30 und 92 GG), der sim-Block ist unverändert.
Vier Browser-Tests hingen an festen Momenten der Teststadt, die sich mit der Sicherheit verschoben haben (unten).

### Für Teil 3

Gebäudetypen 11 und 12 sind frei, Gedächtnis-Codes ab 22. Gelände: Die Anstalt nutzt `gelaendeSuchen(S, 2, 1, true) || (1, 2, true)`,
die Wache `(1, 1, false)`. `STUFE_NEU` nennt Wache (Kleinstadt) und Anstalt (Stadt). Zeichen-Helfer für Gelände (`gelaendeRahmen`, `teilUV`
usw.) liegen in der Darstellung und lassen sich für Kaserne und Dienstgebäude nutzen. Wehrdienst gibt 18-Jährigen eine Stelle und trifft
damit die Gruppe mit der höchsten Tatneigung (18–24: 1,40); danach die Kalibrierung (S-A1) neu messen. Die Grenze „keine Überwachung von
Bewohnern“ gilt auch für den Nachrichtendienst. (Umgesetzt in Teil 3, Abschnitt „Bund“: Gebäudetypen 11 und 12, Gedächtnis-Code 22; die
Tatneigung der 18- bis 24-Jährigen sank nicht, gemessen 1,51; die Taten liegen bei 32,8 statt 32,2 je 1.000, nicht neu kalibriert.)

## Bund: Kaserne, Wehrpflicht, Nachrichtendienst (Version 7, Teil 3)

Teil 3 von „Stadt erweitern“. Noahs Wunsch: „Jz machen wir noch das die statd eigen Militär basen hat Waffen und alles kann Geheimdienst
und alles wie in Amerika so macht und so Gefängnis also kann man die Stadt erweitern“. Das Gefängnis kam in Teil 2. Hier kommen Militär und
Nachrichtendienst dazu, mit Noahs Entscheidungen: **Militär heißt alles**: eine Kaserne als Arbeitgeber, Wehrdienst und eine sichtbare Anlage.
Die **Wehrpflicht gilt für alle, die 18 werden**. Zwei Abweichungen sind im Fenster markiert: die Beschränkung auf Deutsche, die das Programm
(S. 88) und das geltende Recht kennen (§ 1 Abs. 1 WPflG: „alle Männer …, die Deutsche im Sinne des Grundgesetzes sind“; für Soldaten auf Zeit
§ 37 Abs. 1 Nr. 1 SG), und das Geschlecht im Gesetz (Art. 12a Abs. 1 GG, § 1 WPflG). Bis zur Schlussprüfung nannte das Fenster die
Beschränkung auf Deutsche nur als Forderung des Programms (Befund X1, blockierend, behoben).

**Wirklichkeit:** Keine Stadt hat eigenes Militär, weder in Deutschland noch in den USA, und keine hat einen Nachrichtendienst als eigene
Behörde. Große US-Stadtpolizeien haben aber eigene Aufklärungsabteilungen: Zum Intelligence Bureau der New Yorker Polizei gehörte die
„Demographics Unit“ (Befund X8 der Schlussprüfung; en.wikipedia.org „New York City Police Department Intelligence Bureau“, CNN 15. 4. 2014). Streitkräfte
stellt der Bund auf (Art. 87a Abs. 1 GG). Die Verteidigung ist seine ausschließliche Gesetzgebung (Art. 73 Abs. 1 Nr. 1 GG). In den USA
stellt der Kongress die Armeen auf (Verfassung Art. I Abschn. 8). Ein Bundesstaat darf in Friedenszeiten ohne Zustimmung des Kongresses keine
Truppen halten (Art. I Abschn. 10). Seine National Guard untersteht im Dienst für den Staat dem Gouverneur (National Guard Bureau).
Deshalb sind Kaserne und Dienststelle in der Stadt **Einrichtungen des Bundes**: Er baut sie und zahlt Bau, Löhne und Sold. Im Spiel ist
das Geld „von außen“. „Wie in Amerika“ ist nur das Aussehen: ein großes Gelände mit Zaun, Wachtürmen, Hangar und Hubschrauberplatz.

Umgesetzt im sim-Block im Abschnitt „Bund (Version 7, Teil 3)“ (bis „Ende Bund“). `bundTag(S)` läuft jede Nacht nach dem Bauamt: Bau →
Eröffnung → Besetzung zählen → Jahreszeile → Geld vom Bund für „gestern“. Diensttage, Dienstende und Einberufung laufen in `menschenTag`. Löhne
und Sold zahlt ein eigener Zweig `istBund` in `wirtschaft`, den Sold im Ersatzdienst der Zweig des Bauhofs. Der Abschnitt zieht **keinen
Zufall**. Mit `R.BUND_BAUT = 0` und `R.WEHRPFLICHT = 0` läuft die Stadt genau wie ohne den Bund (nachgeprüft gegen den Stand von Teil 2 mit
`mil/mess/ohne_bund.mjs`: Seeds 1–3 je 730 Tage, jeden Tag gleich). So vergleichen `--erweiterung` und
`--migrationstest` mit Version 6 (`sicherheitAus` schaltet jetzt auch den Bund aus). Grundlage war der Entwurf `scratchpad/erw7/mil_entwurf.txt`
(Prototyp auf 414ebab) mit der Gegenprüfung `mil_pruefung.txt`. Übertragen ist die Logik auf den Stand nach Teil 2, nicht die Patches.

### Regeln

- **Kaserne.** Ab der Stufe Stadt (160 Einwohner) lässt der Bund eine Kaserne auf einem Gelände von 3 × 2 Blöcken (11 × 7 Felder) am
  Stadtrand bauen. Das Gelände kommt aus der Schnittstelle von Teil 1: `gelaendeSuchen(S, 3, 2, true) || (2, 3, true)`, `gelaendeBauen`. Er
  zahlt 9.600 Taler an die Stadtkasse, der Bauhof baut 48 Arbeitstage. Das ist als Vereinfachung markiert: In Wirklichkeit planen die
  Bauverwaltungen von Bund und Ländern, und Firmen bauen. Findet sich kein Gelände (ganz freie Blöcke an einer Straße), sucht der Bund in der
  nächsten Nacht wieder. Eine Zufahrt legt er nicht an. Offen ist die Kaserne ab dem Tag nach der Fertigstellung (`S.bund.kOffen`). Das
  Stadtbuch meldet Auftrag und Eröffnung ohne Namen.
- **Stellen der Kaserne:** 8 für Soldatinnen und Soldaten, 4 für Zivilbeschäftigte, 92 Taler Lohn am Tag vom Bund, darauf die Lohnsteuer wie
  bei jedem Lohn. Ob jemand Soldat oder Zivil wird, entscheidet **nur die freie Stelle**: Solange weniger als 8 Soldaten da sind, wird man
  Soldat (`anstellen`). Die Funktion liest nichts von der Person. **Soldaten auf Zeit sind 4 Jahre (40 Spieltage) gebunden** (`verpflichtet`):
  Sie wechseln die Stelle nicht, kündigen nicht und gründen nichts. Sie hören auch nicht wegen eines fehlenden Kita-Platzes auf (Befund 6,
  siehe unten). Freinehmen und wegziehen dürfen sie. Mit Rentenanspruch endet die Bindung. Sind Stellen des Bundes frei, besetzt sie der
  Zuzug nach den Stellen des Landes (Versetzung, B11; Kaserne vor Dienststelle).
- **Wehrpflicht** (`einberufen`, W1). Wer 18 wird, wird in der Nacht seines Geburtstags einberufen. Das gilt ab dem **Tag nach der
  Eröffnung** der Kaserne, vorher nicht und auch nicht nachträglich (Befund 9). Die Regel gilt für alle: Die Stadt kennt keine
  Staatsangehörigkeit, und das Geschlecht spielt keine Rolle. Nicht einberufen wird, wer in Haft ist oder schon Stelle oder Betrieb hat (mit 18
  kommt das nicht vor). **Wehr- oder Ersatzdienst** legt ein fester Wert je Person fest (`dienstWahl`, B8): ein Hash aus Seed, Personennummer,
  Generation des Speicherplatzes und Geburtstag, kein Zug aus dem Zufallsstrom. Liegt er unter 0,7, wird es Ersatzdienst. Die
  Gewissensentscheidung (Art. 4 Abs. 3 GG) bildet die Stadt nicht ab.
- **Dienst.** Er dauert 5 Spieltage (6 Monate, B6): Wehrdienst in der Kaserne, Ersatzdienst im Bauhof. **60 Taler Sold** am Tag brutto vom
  Bund, darauf die Lohnsteuer wie bei jedem Lohn (Befund 5). Betrag und Steuer kommen aus derselben Regelung, dem heutigen Wehrdienst (B7).
  Der Dienst ist **keine Stelle**: Er kommt zu den Stellen dazu, auch im Bauhof, und nimmt niemandem eine bezahlte Stelle weg. Im Bauhof
  zählt er **nicht zur Obergrenze von 40** (Befund 2): `stellen = 10 + Zuschlag + gemeinnützig + Ersatzdienst`, der Zuschlag rechnet ohne
  Ersatzdienst, und bei der Heranziehung zu gemeinnütziger Arbeit zieht `grundsicherung` ihn ab. Im Dienst gibt es keinen Stellenwechsel,
  keine Kündigung, keinen freien Tag, keine Gründung und keinen Wegzug aus eigenem Antrieb (entscheide und erlaubteAktionen gleich). Die
  Person wohnt weiter zu Hause (B13). Diensttage zählen ab der Nacht nach der Einberufung (Befund 9). In der Nacht des letzten Tages endet der
  Dienst (`dienstEnde`, der Sold dieses Tages ist bezahlt), und die Person entscheidet in der nächsten Stunde neu. Früher endet er nur durch
  Tod, Haft (vereinfacht) oder den Wegzug des Haushalts. Das zählt als „abgebrochen“, auch am letzten Tag. Einmal im Jahr schreibt das
  Stadtbuch, wie viele einberufen wurden.
- **Ersatzdienst im Bauhof** (B12): Er arbeitet auf den Baustellen wie alle im Bauhof. Ohne Baustelle macht er **Landschaftspflege für die
  Stadt und keine Kisten zum Verkauf**. Er zählt nicht beim Umlandpreis (`exportArbeiter`), nicht bei den Kisten der Werkstatt (`da`, in
  `wirtschaft` und `kistenVerteilen`) und trägt keine Kisten (`traeger`). Zivildienst dient dem Allgemeinwohl (§ 1 ZDG), § 4 Abs. 1 Nr. 1
  ZDG nennt auch die Landschaftspflege. Den Sold zahlt der Bund, nicht das Budget.
- **Dienststelle des Bundesnachrichtendienstes.** Ab der Stufe Großstadt (800 Einwohner) lässt der Bund einen Block am Stadtrand bebauen
  (`gelaendeSuchen(S, 1, 1, true)`, 3.200 Taler, 16 Arbeitstage). Sie hat 4 Stellen mit 92 Taler Lohn vom Bund. Sie ist **nur Arbeitgeber**:
  Keine Funktion beobachtet Bewohner, stuft sie ein oder legt Akten an. `--militaer` prüft statisch, dass nur 16 festgelegte Funktionen die
  Dienststelle überhaupt nennen (Bau, Stellen, Texte, Prüfung). Die Begründung ist eine **Grenze der Stadt, keine Aussage des Programms**
  (Befund 3). Das Programm lehnt den Überwachungsstaat ab (S. 124). Es fordert aber elektronische Überwachung an den Grenzen (S. 125) und
  weist Terrorabwehr und den Schutz vor Spionage und Sabotage dem BND und den Polizeibehörden zu (S. 138, im Abschnitt zur Reform des
  Verfassungsschutzes; dass damit Aufgaben im Inland gemeint sind, ist eine Deutung der Stadt, Befund X4). Nach geltendem Recht sammelt der
  BND Informationen über das Ausland (§ 1 Abs. 2 BNDG). Seit der Schlussprüfung sucht `gelaendeSuchen` einen Block auch im Rahmen von zwei
  Blöcken (Abschnitt „Stadt erweitern“, Schnittstelle); vorher gab es in einem dichten Stadtkern oft lange keinen Platz, und die Dienststelle wartete,
  bis das Bauamt eine Straße verlängert (gemessen unten).
- **Grenze der Stadt.** Keine Regel des Bundes liest Namen, Geschlecht, Herkunft, Einzugstag, Eltern, Gedächtnis oder Heimatliebe.
  `--militaer` prüft je Funktion die gelesenen Personenfelder (`verpflichtet`, `dienstZahl`, `dienstWahl`, `einberufen`, `dienstEnde`,
  `bundStelleFrei`, `bundTag`, `anstellen`, `austreten` und die Bund-Zeilen in `entscheide` und `erlaubteAktionen`). Mit getauschten
  Namenslisten läuft die Stadt bitgleich (Seed 2, 400 Tage, mit Einberufungen). Gemessen, nicht geregelt: Auf den Seeds 1–12 leisten 70,3 %
  der Männer und 68,7 % der Frauen Ersatzdienst (1.455 von 2.069 und 1.430 von 2.083).

### Programmpunkte (Fenster „Stadtregierung“, Gruppe „Bund in der Stadt (Einrichtungen des Bundes)“)

Drei Karten im Stil der übrigen, jede mit Zitaten, Zahlen (`regLive`) und einem aufklappbaren Teil:

- **„Kaserne der Bundeswehr“** (Annahme der Stadt). Zitate S. 88: „Die deutschen Streitkräfte sind nicht verteidigungsfähig.“, „Es fehlt an
  Personal und einsatzfähiger Ausrüstung.“ und der Satz zur Ausstattung (Befund 8; das Zitat von S. 86 ist weg). Größe als Spielmaßstab, die
  Bau-Vereinfachung als Hinweis (Befund 7a), Wirklichkeit mit Art. 87a und 73 GG, USA mit National Guard (Befund 7c). Fahrzeuge: Weitreichende
  US-Waffensysteme stehen nicht auf dem Gelände, ihre Stationierung lehnt das Programm ab (S. 91). Raketen und Drohnen der Bundeswehr lässt die
  Darstellung weg. Das ist eine Annahme für den Look, keine Aussage des Programms (Befund 4).
- **„Wehrpflicht für alle, die 18 werden, mit Ersatzdienst“** (wirkt · Abweichung). Zitate S. 88: „Daher wollen wir die Wehrpflicht wieder
  einsetzen. Diese beinhaltet gemäß aktueller Gesetzeslage auch den Ersatzdienst.“ und „Um Loyalitätskonflikte zu vermeiden, soll der Dienst in
  den Streitkräften ausschließlich deutschen Staatsbürgern vorbehalten bleiben.“ Beide Abweichungen sind benannt: Programm (S. 88) und
  geltendes Recht beschränken den Dienst auf Deutsche (§ 1 Abs. 1 WPflG, § 37 Abs. 1 Nr. 1 SG), das Gesetz verpflichtet zudem nur Männer
  (Art. 12a Abs. 1 GG); die Stadt kennt keine Staatsangehörigkeit und beruft alle ein. Die Hauskarte der Kaserne sagt es kurz („Programm und
  Gesetz: nur Deutsche, das Gesetz nur Männer; die Stadt kennt keine Staatsangehörigkeit und beruft alle ein.“). Dauer (§ 5 Abs. 2 WPflG,
  heute mindestens 6 Monate in der Truppe) und Sold (brutto wie im heutigen Wehrdienst; § 3 Nr. 5 Buchst. a EStG nur als Gegenüberstellung
  für den Pflichtdienst) stehen in der Karte, ebenso der heutige Stand (§§ 2, 2a WPflG; seit 2026 bekommen alle Deutschen ab Jahrgang 2008
  nach dem 18. Geburtstag einen Fragebogen, deutsche Männer müssen ihn beantworten und werden gemustert, für Frauen ist er freiwillig;
  bundeswehr.de „Fragebogen zur Wehrerfassung“ und „Musterung“, bmvg.de, am 27. 9. 2026 gelesen). Vereinfacht sind: keine Musterung, zu Hause
  wohnen (§ 18 SG), Beginn ab der Eröffnung, Ende durch Haft, Bauhof statt Pflege.
- **„Dienststelle des Bundesnachrichtendienstes, keine Überwachung der Bewohner“** (Annahme der Stadt). Zitate S. 138 (Verfassungsschutz;
  Terrorabwehr beim BND) und S. 124 (Überwachungsstaat). Die Annahme sagt, dass „niemand wird überwacht“ die Grenze der Stadt ist, und
  dass „im Inland“ bei S. 138 eine Deutung der Stadt ist. In den USA hat keine Stadt einen Nachrichtendienst als eigene Behörde, große
  Stadtpolizeien aber Aufklärungsabteilungen: Zum Intelligence Bureau der New Yorker Polizei gehörte die „Demographics Unit“, die
  muslimische Viertel kartierte, bis April 2014 (ACLU). Genau das schließt die Grenze aus.

Dazu ein Hinweiskasten zu Kaserne und Nachrichtendienst (S. 91). „Geld von außen“ hat zwei Zeilen „Bund für Kaserne und Nachrichtendienst,
gestern“ und „… seit dem Start“. „Von außen, gestern“ oben links enthält den Bund. **Nicht übernommen**, ergänzt für die Kapitel
Außen- und Sicherheitspolitik (S. 86–91) und die Stellen S. 124 und 138: „Grenze der Stadt“ mit Terrorabwehr und Schutz vor Spionage und
Sabotage durch den BND (S. 138, Befund 3; dass der Satz das Inland meint, ist als Deutung der Stadt gekennzeichnet, Befund X4 der Schlussprüfung). „Kein Gegenstück in der Stadt“ mit 12 Punkten: GASP (S. 86), Bündnisse (S. 87), wehrtechnische Industrie,
Privatisierungen, Führungsverantwortung (S. 88), Cyber-Fähigkeiten, Korpsgeist, Liedgut, Schutzräume (S. 89), Rüstungskontrolle (S. 90),
US-Waffensysteme (S. 91) und parlamentarische Kontrolle (S. 138). S. 88 und das Waffenrecht (S. 120) haben neue Begründungen. Alle Zitate im
Fenster: **234**. `zitatpruef.py` findet 231, `zitate_genau.py` findet dieselben 231 wörtlich auf der genannten Seite, 0 Fehler. Die übrigen
3 sind keine Programmzitate: Noahs „Wie in Amerika“ (zweimal) und der Name „Demographics Unit“. Gesammelt mit `mil/mess/zitate_sammeln.mjs`,
jetzt mit dem Hinweis zum Bund. Neu in Teil 3 sind 22 Programmzitate (Teil 2: 209). Stand nach der Schlussprüfung: 235 Zitate, 232 aus
dem Programm (S. 124 ist geteilt, Abschnitt „Befunde der Schlussprüfung“).

### Annahmen (B1 … B21)

| # | Annahme | Wert | Begründung, Quelle |
|---|---|---|---|
| B1 | Wann der Bund baut | Kaserne ab der Stufe Stadt (160), Dienststelle ab der Großstadt (800) | Stufen aus Teil 1 (Spielmaßstab 125); `STUFE_NEU` nennt beides |
| B2 | Größe des Geländes | Kaserne 3 × 2 Blöcke (11 × 7 Felder), Dienststelle 1 Block | Stilisiert wie die Häuser; echte Kasernen sind viel größer |
| B3 | Stellen | Kaserne 8 Soldaten + 4 Zivil, Dienststelle 4 | Bundeswehr am 31. 8. 2026: 186.356 in Uniform, 81.751 in Zivil (bundeswehr.de, Personalzahlen), also ein Drittel zivil. 12 Stellen stehen mit dem Maßstab 125 für etwa 1.500 Dienstposten. Für den BND gibt es keine öffentliche Zahl je Dienststelle; 4 sind geschätzt |
| B4 | Lohn beim Bund | 92 Taler am Tag (Soldaten, Zivil, BND) | Destatis, durchschnittlicher Bruttojahresverdienst Vollzeit 2025: insgesamt 64.441 €, Abschnitt O (Öffentliche Verwaltung, Verteidigung; Sozialversicherung) 59.350 €; 0,921 × 100 |
| B5 | Bau | Kaserne 9.600 Taler und 48 Arbeitstage, Dienststelle 3.200 und 16 | 200 Taler je Arbeitstag wie beim Wohnhaus. Der Bauhof baut (Vereinfachung, im Fenster markiert) |
| B6 | Dauer des Dienstes | 6 Monate = 5 Spieltage | § 5 Abs. 2 WPflG (Grundwehrdienst 6 Monate); bundeswehr.de, Neuer Wehrdienst: „Mindestens sechs Monate verbringen die Wehrdienstleistenden in der Truppe.“ Ersatzdienst gleich lang |
| B7 | Sold | 60 Taler am Tag brutto, Lohnsteuer wie jeder Lohn; Ersatzdienst gleich | bundeswehr.de, Neuer Wehrdienst: „Grundgehalt von etwa 2.600 Euro brutto monatlich“ = 31.200 € im Jahr; nach U1 (100 Taler ≙ 52.159 €) 59,8. Dieser Bezug ist steuerpflichtig. Nur Pflicht-Wehrdienstleistende nach § 4 WPflG wären steuerfrei (§ 3 Nr. 5 Buchst. a EStG); die Stadt nimmt Betrag und Steuer aus derselben Regelung (Befund 5). Zivildienstleistende bekamen dieselben Bezüge (Wikipedia „Zivildienst in Deutschland“) |
| B8 | Anteil Ersatzdienst | 70 %, fest je Person (Hash aus Seed, Nummer, Generation, Geburtstag) | Im März 2010 leisteten 77.437 Männer Zivildienst und 32.673 Grundwehrdienst (Wikipedia „Zivildienst in Deutschland“; Primärquelle nicht geprüft). Kein Zug aus dem Zufallsstrom, damit die Einberufung die übrige Stadt nicht verschiebt |
| B9 | Einberufung erst ab der Eröffnung | ab dem Tag nach der Eröffnung, nicht nachträglich | Dienst anderswo müsste die Stadt als Abwesenheit abbilden. Gemessen: Kaserne offen im Mittel ab Tag 191, erster Dienst an Tag 204 |
| B10 | Soldaten auf Zeit | 4 Jahre gebunden: kein Wechsel, keine Kündigung, keine Gründung, kein Aufhören wegen der Kita; freinehmen und wegziehen erlaubt; endet mit Rentenanspruch | bundeswehr.de: ab 12 Monaten Soldat auf Zeit (etwa 2.700 € brutto). Die 4 Jahre sind eine Annahme. Ohne Bindung wechselten Soldaten sofort in besser bezahlte Werkstätten |
| B11 | Versetzung beim Zuzug | Freie Stellen des Bundes gehen beim Zuzug nach denen des Landes vor | Soldaten werden an einen Standort versetzt. Ohne das bliebe die Kaserne fast leer (Entwurf: 2,3 Soldaten im Mittel) |
| B12 | Ersatzdienst im Bauhof | Baustellen, sonst Landschaftspflege, keine Kisten; nicht in der Obergrenze von 40; Sold vom Bund | Art. 12a Abs. 2 GG: Ersatzdienst ohne Bezug zu den Streitkräften. § 1 und § 4 Abs. 1 Nr. 1 ZDG. Mit den Kitas wäre eine soziale Einsatzstelle näher dran (offene Frage) |
| B13 | Wohnen im Dienst | zu Hause, Wohnen und Kontakt unverändert | § 18 SG erlaubt eine Pflicht zur Gemeinschaftsunterkunft auf Anordnung; die Stadt bildet sie nicht ab. So stimmen Simulation und Figuren überein: tagsüber in der Kaserne, nachts zu Hause |
| B14 | Geschlecht und Staatsangehörigkeit | spielen keine Rolle | Harte Grenze (Staatsangehörigkeit) und Annahme 15 (Geschlecht). Zwei Abweichungen, im Fenster markiert: Programm (S. 88) und geltendes Recht beschränken den Dienst auf Deutsche (§ 1 Abs. 1 WPflG, § 37 Abs. 1 Nr. 1 SG), das Gesetz verpflichtet nur Männer (Art. 12a Abs. 1 GG) |
| B15 | Freinehmen | Soldaten und Zivil ja (Tageslohn fällt weg wie überall), im Dienst nicht | Einheitliche Regel der Stadt; in Wirklichkeit ist Urlaub bezahlt |
| B16 | Rente | Die Bindung endet mit dem Rentenanspruch (Schritt 2) | Berufssoldaten gehen früher in Ruhestand; das bildet die Stadt nicht ab |
| B17 | Lage | Gelände am Stadtrand (weitester freier Platz an einer Straße); ohne Gelände warten | Schnittstelle aus Teil 1. Eine eigene Zufahrt legt der Bund nicht an; die Dienststelle wartet deshalb in dichten Städten (unten) |
| B18 | Nachrichtendienst | nur Arbeitgeber, keine Wirkung auf Bewohner | § 1 Abs. 2 BNDG. Grenze der Stadt, keine Aussage des Programms (S. 124, 125, 138) |
| B19 | Fahrzeuge und Waffen | Kampf- und Schützenpanzer vor der Fahrzeughalle, ein Panzer und drei Lkw am Übungsplatz, ein Hubschrauber; alles steht still. Schießbahn mit Erdwall und drei Scheiben | Nur zum Ansehen. Keine weitreichenden US-Waffensysteme (S. 91); Raketen und Drohnen der Bundeswehr weggelassen als Annahme für den Look |
| B20 | Maßstab für die Begründung | 1 Bewohner ≙ 125 Menschen | Aus Teil 1 (`STUFE_MASSSTAB`), nur zur Begründung der Stellenzahl |
| B21 | Alter beim Anstellen | spielt keine Rolle (auch ein 53-Jähriger wird Soldat auf Zeit, Seed 2, Tag 460) | `anstellen` liest bewusst nichts von der Person. Die Bundeswehr hat Altersgrenzen (nicht nachgeschlagen); im Fenster als Vereinfachung genannt (Befund X18 der Schlussprüfung) |

**Quellen** (abgerufen September 2026; Kopien der Gesetze in `scratchpad/erw7/mil/recht/`): gesetze-im-internet.de: GG Art. 4, 12a, 73,
87a; WPflG §§ 1, 2, 2a, 4, 5; ZDG §§ 1, 4, 35; SG §§ 18, 37; EStG § 3; BNDG § 1. bundeswehr.de: „Personalzahlen der Bundeswehr“ (Stand
31. 8. 2026) und „Neuer Wehrdienst“ (Grundgehalt, mindestens sechs Monate, Wehrerfassung ab Jahrgang 2008, Wohnen in der Kaserne).
destatis.de: „Durchschnittliche Bruttojahresverdienste von Vollzeitbeschäftigten im Jahr 2025“. Wikipedia „Zivildienst in Deutschland“
(Zahlen März 2010, gleiche Bezüge). ACLU-Pressemitteilung „NYPD Shuts Unit That Mapped Muslim Communities“ (April 2014). US-Verfassung
(archives.gov, Art. I Abschn. 8 und 10). National Guard Bureau, Fact Sheet „National Guard Duty Statuses“ (Gouverneur, Title 32). Das
Programm „Zeit für Deutschland“ S. 86–91, 124, 125 und 138 selbst gelesen. Neu mit der Schlussprüfung (27. 9. 2026): § 1 Abs. 1 WPflG und
§ 37 Abs. 1 Nr. 1 SG aus den Kopien in `mil/recht/` (Deutsche; § 37 Abs. 2 SG erlaubt Ausnahmen), bundeswehr.de „Fragebogen zur
Wehrerfassung“ („Männer müssen den Fragebogen beantworten, für Frauen ist dieses freiwillig.“) und „Musterung“ (verpflichtend für
wehrpflichtige Männer ab Jahrgang 2008), bmvg.de „Neuer Wehrdienst tritt ab 1. Januar in Kraft“, en.wikipedia.org „New York City Police
Department Intelligence Bureau“, CNN vom 15. 4. 2014 zur Auflösung der Demographics- bzw. Zone Assessment Unit.

### Darstellung

**Ein Draw Call mehr** (`bundMesh`, nur solange es Kaserne oder Dienststelle gibt: 25 statt 24 in der Teststadt an Tag 400, gemessen mit
und ohne das Mesh). Kästen (Unterkünfte, Stabsgebäude, Fahrzeughalle, Wachtürme, Zaun, Tor mit Schranke, Bürobau, Fenster) liegen wie bei
Wache und Anstalt in `teil`, `tech`, `fenster` und `schlot`. Sie sind klickbar, tönbar und werden stündlich geschrieben. Runde und schräge
Teile liegen im Bund-Mesh: Rundbogen-Hangar mit Rippen, Hubschrauberplatz mit Ring und „H“, Hubschrauber mit stehendem Rotor, Panzer, Lkw,
Erdwall mit Scheiben, Fahnenmast mit Bundesflagge, zwei Radome, zwei Schüsseln und ein roter Gittermast. Das Mesh hat 1.656 Dreiecke in festen
Puffern (höchstens 12.000). Es wird **nur bei neuem Schlüssel** neu geschrieben (Gelände, Tor, Baufortschritt im Viertel, Eröffnung),
stündlich geprüft: keine Allokation je Bild. **Nichts bewegt sich von selbst.** Nur die **Warnlichter am Mast** leuchten nachts und
blinken (1 s an, 1 s aus). Das ist eine Uniform je Bild, im Lambert-Shader über `emissivemap_fragment` (three 0.186.0 geprüft). Bei
reduzierter Bewegung leuchten sie stetig. Im Bau wachsen Rohbau und Gerüst; das Runde erscheint mit der Eröffnung. Klick irgendwo aufs
Gelände öffnet die Hauskarte (`gelaendeVon`).
**Figuren:** Soldaten und Wehrdienst in Oliv (`BUNDESWEHR_F` #6f7a45) stehen zur Arbeitszeit in Reihen zu 6 auf dem Antreteplatz, mit
Blick zum Fahnenmast. Das Gelände ist ihr Arbeitsplatz in der Simulation (Grundregel). Zivilbeschäftigte und Nachrichtendienst tragen die
Farben aller anderen. Der Ersatzdienst trägt Warnweste wie der Bauhof. Hilfe: „Lila: Tech-Firma. Oliv: Bundeswehr in der Kaserne.“ (eine
Zeile, bei 1280 × 800 weiter 745 von 745 px ohne Überlauf). Stadtbuch: Art „Bund“ mit Hallen-Symbol. Hauskarte: Stellen, Lohn vom Bund,
Wehrdienst, „Panzer, Lkw und der Hubschrauber stehen still und sind nur zu sehen“. Bei der Dienststelle: „In der Stadt überwacht niemand
die Bewohner“. Personenkarte: „leistet Wehrdienst in der Kaserne … bis Tag X (60 Taler Sold am Tag vom Bund)“ bzw. Ersatzdienst, bei
Soldaten „verpflichtet bis Tag X“. „Heute“ im Ersatzdienst ohne Baustelle: „Landschaftspflege für die Stadt“. Sprachmodell: Der Lagesatz
sagt „Du leistest Wehrdienst …“ (nur Tatsachen der Figur). `--kitest` prüft, dass der Arbeitstext mit „leistet Wehrdienst“ oder
„leistet Ersatzdienst“ beginnt.

### Gemessen

**Seeds 1–3** (`simtest --gate`, 730 Tage stündlich, alle Gates bestanden; in Klammern Teil 2):

| Seed | Einwohner Tag 365 / 730 | Band Gate 4 | Gate 6 / Gate 7 | Stadtbuch je Tag | Kaserne / Dienststelle offen ab Tag | Wehr- / Ersatzdienst | Diensttage (beendet / abgebrochen) | Taten (D / E / B) |
|---|---|---|---|---|---|---|---|---|
| 1 | 819 / 1.145 (802 / 1.146) | 1,10 (1,09) | +19,5 / −23,0 (+18,5 / −23,1) | 5,64 (4,78) | 206 / 368 | 103 / 227 | 1.620 (319 / 2) | 1.363 / 65 / 522 |
| 2 (Teststadt) | 792 / 1.169 (753 / 1.157) | 1,08 (1,13) | +21,8 / −23,2 (+20,4 / −23,0) | 5,29 (5,08) | 211 / 371 | 101 / 208 | 1.519 (298 / 3) | 1.299 / 49 / 504 |
| 3 | 951 / 1.148 (905 / 1.118) | 1,03 (1,05) | +19,7 / −27,1 (+17,7 / −23,3) | 4,82 (4,54) | 184 / 432 | 107 / 272 | 1.866 (369 / 3) | 1.234 / 43 / 455 |

(Stand Teil 3. Seit der Schlussprüfung sucht `gelaendeSuchen` einen Block auch im Rahmen von zwei Blöcken: Auf Seed 3 öffnet die
Dienststelle an Tag 333 ohne eine Nacht zu warten, auf Seed 1 eine Nacht früher als vorher; Seed 2 ist gleich.) Auf Seed 3 ist die Stadt seit
Tag 327 eine Großstadt. 99 Nächte lang gab es keinen ganz freien Block an einer Straße: Die Häuser säumen alle
Straßen, und die freien Blöcke vor den Straßenenden haben keine Straße an einer Seite. Erst nach einer neuen Straße des Bauamts findet der Bund
Platz. `--militaer` prüft jede dieser Nächte: Der Bund wartet nur, wenn `gelaendeSuchen` wirklich nichts findet.

Über viele Seeds mit derselben Messung (`mil/mess/mess9.mjs` = `mess/mess8.mjs` plus Bund, über `mil/mess/lauf80.sh`, Auswertung
`mil/mess/vergleich_mil.py` und `vergleich_mil160.py`), 730 Tage stündlich, **gegen bc7247a** und Teil 2. Gemessen mit `mil/mess/stadt_v3.html`;
der sim-Block des Endstands unterscheidet sich davon nur in einem Feld, das `bundInfo` liest (`stufe`, für das Fenster):

| Seeds | Stand | alle Gates | fällt | Band Ø / Median / schlimmster | Gate 7 kleinster Abstand | Einwohner Tag 365 / 730 | Wegzüge (Personen) | Zuzüge |
|---|---|---|---|---|---|---|---|---|
| 1–80 | bc7247a | 77 von 80 | G4: 11, 23, 45 | 1,077 / 1,073 / 1,155 | 16,5 | 896 / 1.110 | 40,2 | 1.028 |
| 1–80 | Teil 2 | 76 von 80 | G4: 22, 34, 57, 71 | 1,082 / 1,078 / 1,210 | 18,1 | 892 / 1.138 | 62,9 | 1.066 |
| 1–80 | Teil 3 | 76 von 80 | G4: 44, 73, 77, 79 | 1,086 / 1,080 / 1,213 | 15,2 | 912 / 1.189 | 64,7 | 1.112 |
| 81–160 | bc7247a | 76 von 80 | G7: 108; G4: 112, 130, 140 | 1,075 / 1,065 / 1,185 | 13,9 | 891 / 1.110 | 40,0 | 1.028 |
| 81–160 | Teil 2 | 78 von 80 | G4: 153, 155 | 1,073 / 1,067 / 1,168 | 15,5 | 896 / 1.136 | 61,2 | 1.067 |
| 81–160 | Teil 3 | 76 von 80 | G4: 91, 93, 101, 112 | 1,078 / 1,070 / 1,196 | 15,9 | 916 / 1.186 | 55,0 | 1.109 |

Zusammen 152 von 160, gegen 153 (bc7247a) und 154 (Teil 2): **kein Unterschied über das Rauschen hinaus**, und kein „besser“. Welche Seeds
an Gate 4 fallen, wechselt mit jeder Änderung. Eine Zwischenfassung ohne die Bindung bei der Kita-Lücke (Befund 6 unten) bestand auf den Seeds
1–80 78 von 80 (G4: 44, 79). Das Band von Gate 4 liegt nie über 1,22. Gate 6 und 7 halten auf allen 160 Seeds.

- **Bund** (Seeds 1–80; 81–160 fast gleich): Kaserne offen im Mittel ab Tag 191 (162–238), Dienststelle ab Tag 369 (320–584, in allen
  80 Städten bis Tag 730; Seeds 81–160: 314–685), erster Dienst an Tag 204. Tag 366–730 im Mittel 7,40 von 8 Soldaten, 3,33 von 4 Zivil,
  3,27 von 4 im Nachrichtendienst; zugleich 1,34 im Wehr- und 3,06 im Ersatzdienst. Bis Tag 730 je Stadt 106 Wehrdienste und
  243 Ersatzdienste (69,5 %), 3,9 abgebrochen. Der Bund zahlt im Mittel 791 Taler am Tag Löhne und 141 Sold, dazu 12.800 Taler für die
  Bauten. 18- bis 24-Jährige ohne Arbeit: 5,9 %.
- **Taten** je 1.000 Einwohner und Jahr (Tag 366–730): Seeds 1–80 22,73 / 0,96 / 9,08 = **32,8**, Seeds 81–160 32,6 (Teil 2: 32,2 und 32,1;
  PKS 2024: 32,1). Das sind etwa 2 % mehr als das Ziel und mehr als der Unterschied zwischen den Seed-Hälften, also eine Wirkung des Bundes,
  keine Streuung. Die Tatneigung liest den Dienst nicht; sie steigt über Geld und Stelle (60 Taler Sold statt eines Lohns, danach wieder
  ohne Stelle). Neu kalibriert ist nichts (S-A1 bleibt 0,0032, offene Frage unten). Nach Gruppen (`--sicherheit`, Seeds 1–6, Tag 200–730,
  nur gemessen): 18–24 Jahre verurteilt 1,51 (Teil 2: 1,40). Die Vermutung aus Teil 2, Wehrdienst gebe 18-Jährigen Arbeit und senke das,
  hält nicht. In der Stadt geboren 1,19, Nachnamen Kaya bis Kowalski 0,97, Frauen 0,98, Männer 1,02.
- **Sonst** (Seeds 1–80, gegen Teil 2): Einwohner an Tag 730 1.189 statt 1.138 (Stellen des Bundes, Zuzug), Arbeitslose an Tag 730
  5,11 statt 4,97 %, Zufriedenheit 70,55 statt 70,58, Stadtbuch 5,11 statt 4,93 Zeilen am Tag, kleinstes Budget gleich.
- **Leistung:** `--gate` Zeit-Check T 1,4 bis 1,7 s für 365 Tage (< 5 s; allein gelaufen, im Parallellauf mit sechs anderen Modi bis
  4,9 s). Draw Calls im Browser 24 bis 29 (Teststadt, Tag 400; Teil 2: 22 bis 27), im Lauf 26; neu ist genau einer (das Bund-Mesh).
- **Große Stadt** (`&umland=300000`, Seed 2, Tag 750): 5.852 Einwohner (Teil 2: 5.703), Karte 144 × 144 (Teil 2: 104), 25 bis 28 Draw
  Calls (Teil 2: 23 bis 26), Dreiecke 141.300 bis 146.400 (Teil 2: 129.500 bis 134.800). Die Kaserne stand bei der Bestellung am Rand,
  die Stadt ist um sie herum gewachsen.

### Speicherformat 7 (Bund)

Neu je Person (`PF_BUND`, Pflicht in jedem Stand der Version 7): `bund` (1 Soldat, 2 Zivil, 3 Wehrdienst, 4 Ersatzdienst, 0 keine) und
`dienstBis` (letzter Diensttag, bei Soldaten das Ende der Verpflichtung). Dazu `S.bund` (Start, Kaserne, Dienststelle, Eröffnungstage,
Einberufungen im laufenden Jahr, Geld vom Bund gestern und die Summe dazu) und `S.stat.bund` (13 Summen: Löhne Kaserne und Dienststelle,
Sold Wehr- und Ersatzdienst, Bau, Einberufungen, Diensttage, beendet, abgebrochen, Personentage je Stellenart). Gedächtnis-Code DIENST 22,
Gebäudetypen KASERNE 11 und DIENSTSTELLE 12. `bundPruefen` lehnt beschädigte Stände ab („Spielstand beschädigt: Bund (…)“). Geprüft werden
Zustand, Gebäude und Gelände, Eröffnung, Summen, Rollen (Rolle nur mit der passenden Arbeit, kein Dienst mit gemeinnütziger Arbeit, niemand in
der Kaserne ohne Rolle) und Dienst (Dienst endet heute oder später, höchstens in 5 Tagen, Soldaten mit Verpflichtung, sonst 0). `--militaer`
prüft 16 Fälle. **Übernahme** aus Version 2–6 (`migriereBund`, nach der Sicherheit, vor „Stadt erweitern“): Niemand dient, Summen 0, Zeile „Ab
heute baut der Bund in der Stadt …“ (vorletzte, vor der Zeile „Stadt erweitern“). Die Kaserne bestellt der Bund in der nächsten Nacht, wenn
die Stadt schon eine Stadt ist. Versionsdialog und Meldung sagen es („Einberufen wird erst ab der Eröffnung der Kaserne.“). Mit
abgeschaltetem Bund und abgeschalteter Sicherheit läuft ein übernommener Stand der Version 6 60 Tage lang Tag für Tag wie in Version 6
(`--migrationstest`). `--speichertest`: **Fingerabdruck `5ba8d43e5bd37135`** (Seed 1, Tag 150, 13 Uhr, 60 Tage weiter; Teil 2 `cb0ce3e6a26986c7`).
Er ist neu, weil die Stadt jetzt den Bund hat und der Fingerabdruck `S.bund` enthält. Dazu kommen der Stand mit Haft und Obhut (jetzt Tag 262,
`140e8b5469cc51a0`, sortiert `6aa189486bef189a`) und neu ein Stand mit Wehr- und Ersatzdienst, verpflichteten Soldaten und offener Dienststelle (Tag 400, `2a9aac381084e59d`, sortiert
`23716e6b002bf2b3`), 60 Tage bitgleich (Befund 1). Der Teststand `tests/basis_v7.json` ist neu aus `tests/basis_v6.json` über „Stadt übernehmen“
entstanden (`tests/basis_v7.cjs`; Tag 420, 2.186 Einwohner, jetzt mit den Feldern des Bundes). Das Original bleibt.

### Tests

- `simtest --militaer` (neu, 24 Prüfungen): statisch (kein Zufall im Abschnitt; je Regel nur die erlaubten Personenfelder, keine
  Namen, kein Geschlecht; Löhne und Sold nie aus dem Budget; Ersatzdienst an allen drei Stellen ohne Kisten; Grenze der Dienststelle),
  Namenstausch (bitgleich). Dazu Seeds 1–3 je 730 Nächte mit Invarianten nach jeder Nacht: Gelände 77 und 9 Felder, der Bund wartet nur ohne
  Gelände, Rollen passen zur Arbeit, Obergrenzen, offene Stellen, Bauhof ohne Ersatzdienst höchstens 40, jede Einberufung mit 18 in der Nacht
  des Geburtstags ab dem Tag nach der Eröffnung, niemand verpasst, niemand vorher, genau 5 Diensttage, Diensttage nachgezählt, Einberufene =
  beendet + abgebrochen + im Dienst, verpflichtete Soldaten bleiben, erlaubte Aktionen um 7 und 18 Uhr, im Dienst nie frei, Geld von gestern =
  Zuwachs der Summen, Stadtbuch ohne Namen. Erzwungen: Tod im Wehrdienst, Haft im Ersatzdienst, Wegzug, Bindung (auch mit Rentenanspruch),
  Gehirn im Dienst (48 Stunden), Kita-Lücke, Einberufung vor der Eröffnung, ohne Wehrpflicht, in Haft, bei vollem Bauhof, leeres Budget
  (der Bund zahlt nachgerechnet), abgeschalteter Bund. Speichern und Laden (60 Tage bitgleich), 16 beschädigte Stände. Messung:
  Ersatzdienst-Anteil 60–80 % (69,4 %), nach Geschlecht, Besetzung.
- Angepasst (Befund 1; keine Prüfung ist schwächer): `--regierung` rechnet Kaserne, Dienststelle und den Sold im Wehr- und Ersatzdienst in
  den unabhängigen Erwartungen mit. Die Bauhof-Formel enthält den Ersatzdienst, die Obergrenze gilt ohne ihn. Der erzwungene Fall der
  gemeinnützigen Arbeit hängt nicht mehr an Tag 400: Abschnitt 1 läuft bis 30 Nächte ohne Wechsel dabei sind, auf Seed 2 jetzt über Tag 400
  hinaus. Die Person begeht in dem Fall keine Tat (Testhilfe `__ohneTat`, wie `__ohneJob`). Kaserne und Dienst sind als Kandidaten
  ausgeschlossen, und die Arbeitslosenzahl in Abschnitt 3 zählt Haft nicht mit, wie die Stadt und Abschnitt 6. `--kitest` lässt „leistet
  Wehrdienst“ und „leistet Ersatzdienst“ zu und prüft den Text. `--sicherheit` misst die Landeslöhne am richtigen Zweig; `haftAntritt` und
  `einkommenTag` dürfen `bund` lesen. Der Obhut-Fall sucht bei Bedarf einen späteren Tag. `--waren`: Der Ersatzdienst macht keine Kisten.
  `--speichertest`: Bund-Stand dazu. Der Obhut-Haushalt braucht ein Kind unter 18 und einen Erwachsenen (`hhKinder` zählt von der letzten
  Nacht). `--migrationstest`: die Bund-Zeile, drei statt zwei neue Zeilen aus Version 6, Kaserne nach 60 Tagen. `--erweiterung`: `STUFE_NEU`
  nennt Kaserne und Dienststelle. Fingerabdruck, `spurRelativ` und `sicherheitAus` kennen den Bund.
- Browser: `tests/militaer.cjs` (neu, in `tests/alle.sh`). Kaserne und Dienststelle auf eigenem Gelände. Stunde für Stunde 6–18 Uhr steht auf
  dem Gelände nur, wer dort arbeitet, Soldaten und Wehrdienst in Oliv, nie in Oliv außerhalb. Klick aufs Gelände öffnet die Hauskarte.
  Personenkarten für Soldat auf Zeit, Wehrdienst und Ersatzdienst. Fenster mit 3 Karten, Abweichungen, Grenze und S. 138, Vereinfachung, USA,
  Geld vom Bund. Hilfe. Draw Calls genau +1, Puffer ohne Stundenschritt unverändert. Warnlichter tagsüber aus, nachts im Takt, reduziert stetig
  an. Konsole leer. `tests/p6migration.cjs` prüft den Bund nach der Übernahme von Version 5 und 6: Zeile, Start, niemand im Dienst, Kaserne in
  der ersten Nacht, niemand vor der Eröffnung. Nach dem Neuladen gilt die Karte vom Speichern; sie wächst nach der Übernahme mit der Kaserne am
  Rand noch einmal. `tests/befunde_s2.cjs` erwartet zwölf aufklappbare Karten. `tests/sicherheit.cjs` zählt die Karten seiner Gruppe bis zur
  nächsten. `tests/p7figuren.cjs`: nur der Kommentar (Gelände galt schon allgemein).
- **Angepasst an den neuen Verlauf der Teststadt** (keine Prüfung ist schwächer): `tests/ereignis.cjs` mit neuen Momenten (`mess/momente7.mjs`):
  Tag 599 um 8 Uhr sieben Übernahmen, Tag 639 vier Schließungen, Tag 683 ein Bau fertig, Tag 721 ein Bau fertig und eine Schließung. Gezählt
  wird 0,1 s nach dem letzten Zeichen, allgemein statt fest. `tests/erweiterung.cjs`: Seed 2 wächst jetzt nur noch einmal, an Tag 198 von 56 auf
  80, in der Nacht, in der Land und Bund am Rand Anstalt und Kaserne bestellen. Geprüft wird deshalb Seed 5, Tag 314, 88 → 96: allein in
  seiner Stunde, Stufe Stadt (gesucht mit `mil/mess/wachsen_allein.mjs`).
- **Ergebnis** auf dem Endstand: `stadt.html` md5 `5390692f24e0cf4665f257bad3fd2940`, Server auf 8713,
  `tests/alle.sh`, KI-Nachbau auf 11434: p3test 12, p5neu 10, p7figuren 6, p8tech 14, raute_klick 6 von 6 Klicks, t1_xss 5, p4test 25,
  s2karten 22, kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16, alle ohne Fehler. p6migration und ereignis fielen im
  ersten Lauf an den verschobenen Momenten (oben). Nach der Anpassung liefen sie einzeln auf demselben Stand: p6migration 26, ereignis 21,
  ohne Fehler. militaer lief nach einer Änderung an seinen Bildnamen noch einmal (16). `tests/otest`: befunde 21, handy 11, breit 12,
  tastatur 4, breiten 20, hilfehoehe ohne Überlauf (745 von 745 px). Dazu `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs`
  ohne Fehler. Die Konsole ist leer, außer den absichtlichen Verbindungsfehlern zum KI-Nachbau in p4test und den abgebrochenen KI-Anfragen
  in `blick.cjs`. Alle `simtest`-Modi auf dem Endstand ohne Fehler (`mil/lauf/*.txt`, `tools/simtest.mjs` md5
  `503719a86816f2aaeacc6f67cbe706a2`): `--gate` (Seeds 1–3 alle Gates), `--speichertest` (bitgleich, alle drei Stände), `--aufholtest`
  (Vergleich, keine Prüfung), `--kitest` 46, `--bau` 15, `--waren` 15, `--tech` 16, `--regierung` 154, `--kita` 40, `--sicherheit` 28,
  `--militaer` 24, `--migrationstest --git /home/user/website-` 293 (Teil 2: 266; neu die Bund-Prüfungen), `--erweiterung --gross --git
  /home/user/website-` 33
- **Bilder** (Endstand, selbst angesehen): `nachher/` (`tests/blick.cjs`, Teststadt Seed 2, Tag 400: 943 Einwohner,
  Großstadt, Karte 80 × 80, 27 bis 29 Draw Calls, 52.200 bis 52.700 Dreiecke; die Kaserne liegt rechts unten am Rand) und `nachher/militaer/`
  (`mil/sicht.cjs`, `mil/bilder_bund.cjs`, `mil/antreten.cjs`, `tests/militaer.cjs`): Kaserne bei Tag und Nacht, von nah und fern; Antreten
  um 10 Uhr mit acht Figuren in Oliv vor dem Fahnenmast, Wachturm und Schranke; Dienststelle mit Radomen und Mast, nachts mit roten
  Warnlichtern; Hauskarten von Kaserne (ausgewählt, das ganze Gelände hell) und Dienststelle; Personenkarte im Ersatzdienst; Fenster.
  `gross/` (`&umland=300000`, Seed 2, Tag 750: 5.852 Einwohner, Karte 144 × 144, 25 bis 28 Draw Calls). Die Bilder aus Teil 2 liegen in
  `scratchpad/erw7/mil/vor/bilder_teil2/`

### Befunde der Gegenprüfung „militaer“

Alle umgesetzt:

1. Testwerkzeuge im Baustein: `--regierung` und `--kitest` grün (siehe Tests), eigener Modus `--militaer` statt des vorgeschlagenen
   `--bund`, Fingerabdruck mit `S.bund`. `--speichertest` speichert zusätzlich an einem Tag mit Kaserne, Dienststelle und Leuten im Dienst.
   Alle Modi stehen mit Ergebnis oben.
2. Bauhof-Obergrenze: Text und Code stimmen. Der Ersatzdienst zählt nicht zu den 40, der Zuschlag rechnet ohne ihn, und die Heranziehung zu
   gemeinnütziger Arbeit zieht ihn ab. Ersatzdienst verdrängt keine bezahlte Stelle. `--regierung` und `--militaer` prüfen das.
3. Dienststelle: „niemand wird überwacht“ ist die Grenze der Stadt, nicht das Programm. Die Karte nennt S. 124, S. 125 und S. 138 und § 1
   BNDG. Unter „Nicht übernommen / Grenze der Stadt“ steht Terrorabwehr und Spionageschutz durch den BND (S. 138; „im Inland“ ist seit der
   Schlussprüfung als Deutung der Stadt gekennzeichnet).
4. S. 91 nur für weitreichende US-Waffensysteme. Raketen und Drohnen der Bundeswehr fehlen als Annahme für den Look (Karte, Kommentar im
   Modul, B19).
5. Sold: 60 Taler brutto mit der normalen Lohnsteuer, Betrag und Steuer aus derselben Regelung (heutiger Wehrdienst). § 3 Nr. 5 Buchst. a
   EStG steht nur als Gegenüberstellung für den Pflichtdienst.
6. Bindung: Text und Mechanik stimmen. „4 Jahre gebunden: wechselt und kündigt die Stelle nicht (außer in Rente) und gründet nichts;
   freinehmen und wegziehen darf er“. Im Dienst „zieht nicht selbst weg“. Beim Nachprüfen fand sich eine Lücke: Die Betreuungslücke der Kitas
   ließ Leute im Dienst und verpflichtete Soldaten aufhören. Jetzt nicht mehr (`kitaTag`, geprüft in `--militaer`; Annahme: der Dienst regelt
   die Betreuung).
7. Realismus: Der Bau durch den Bauhof ist als Vereinfachung markiert (Bauverwaltungen von Bund und Ländern). USA mit National Guard und der
   „Demographics Unit“ der New Yorker Polizei. Die Kita als Ersatzdienst-Ort ist eine offene Frage (unten).
8. Zitate: S. 88 („nicht verteidigungsfähig“, „Personal und einsatzfähiger Ausrüstung“, Ausstattung) statt S. 86.
9. Nacht-Reihenfolge: Einberufen wird ab dem Tag nach der Eröffnung (`kOffen = Tag + 1`), Diensttage zählen ab der Nacht nach der
   Einberufung. `--militaer` prüft beides jede Nacht (niemand vorher, genau 5 Diensttage, nachgezählt).

Dazu beim Umsetzen: Stirbt oder geht jemand am letzten Diensttag, zählte das weder als beendet noch als abgebrochen. Jetzt zählt es als
abgebrochen (`dienstEnde` löscht `dienstBis` vorher), und `--militaer` prüft die Bilanz jede Nacht. Im Stadtbuch und im Fenster steht,
dass der Bund auf Gelände wartet.

### Offene Fragen an Noah

- Ersatzdienst in der **Kita** statt im Bauhof (Pflege und Soziales waren früher der Normalfall)?
- Sollen Wehrdienstleistende in der Kaserne **wohnen** (Gemeinschaftsunterkunft, § 18 SG), nachts auch als Figur dort?
- Soll der Bund eine **Zufahrt** bauen dürfen, wenn in der dichten Stadt kein Gelände frei ist? Für einen Block ist das seit der
  Schlussprüfung gelöst (Suche im Rahmen von zwei Blöcken; auf den Seeds 1–80 öffnet die Dienststelle zwischen Tag 313 und 395, vorher
  320 bis 584). Die Kaserne (3 × 2 Blöcke) wartet nach einer Übernahme manchmal, weil die Wache vorher eine der Stellen nimmt (Seed 2,
  V6-Stand von Tag 260: 15 Nächte bis zur Bestellung; Abschnitt „Befunde der Nachprüfung“, N1).
- **Wer zuerst**, wenn nach einer Übernahme nur zwei Stellen an Straßenenden frei sind: die Wache (so ist es, sie gehört zur Stufe
  Kleinstadt; die Kaserne wartet auf Seed 2 an Tag 200, 230, 260, 330 in dieser Reihenfolge 14, 4, 15 und 67 Nächte) oder die Kaserne (dann
  wartet die Wache: auf Seed 2 9, 5, 19 und 73 Nächte, auf Seed 8 an Tag 200 8, und in 19 der übrigen 27 Fälle eine Nacht länger, weil
  das Land vor dem Bund baut; Gegenprobe der Nachprüfung, `nb/mess/b1_warten.mjs`)?
- **Schutzräume** (S. 89) und Zivilschutz: nicht übernommen, weil es in der Stadt keine Katastrophe gibt.
- Die Tatneigung ist mit dem Bund 2 % über der PKS. **Neu kalibrieren** (S-A1) oder so lassen?

## Befunde der Schlussprüfung (Technik, Texte, Bedienung)

Nach Teil 3 haben drei Gegenprüfungen den Stand gelesen, nachgerechnet und bedient (`scratchpad/erw7/pruef_technik/`,
`pruef_bedienung/` und die Textprüfung). Ausgang war `stadt.html` md5 `5390692f24e0cf4665f257bad3fd2940`. Jeder Befund ist hier erst
nachgeprüft und dann umgesetzt; alle sind erledigt, keiner ist offen geblieben (was dabei offen bleibt, steht unter „Bekannte Schwächen“).
Die Simulation ändert sich nur in einem Punkt (B1, die Suche nach einem Block); die Teststadt (Seed 2) läuft dadurch Tag für Tag genau wie
vorher (`befunde/vergleich.mjs`: 730 Tage gleich in Kennzahlen, Zufall, Anlagen und Karte), Seed 1 ab Tag 363 und Seed 3 ab Tag 329 anders,
weil die Dienststelle früher Platz findet. Alles andere sind Texte, Prüfungen beim Laden, die Prüfung der Antworten des Sprachmodells und die
Oberfläche. Arbeitsdateien: `scratchpad/erw7/befunde/` (Läufe, Messungen, Bilder, eigene Prüfskripte).

### Technik

- **T1 Lage der Gebäude beim Laden.** Ein Stand mit einem Gebäude außerhalb der Karte wurde angenommen (auch in bc7247a). Jetzt prüft
  `erweiterungPruefen` jedes Gebäude (`g.x`, `g.y` auf der Karte, `feldGeb` am eigenen Feld → „Spielstand beschädigt: Lage der Gebäude“)
  und jedes Gelände (Gebäude im Rechteck, jedes Feld zeigt auf das Gebäude und trägt seinen Typ oder ist Baustelle → „… Gelände“).
  `--erweiterung` hat vier neue beschädigte Stände (Gebäude außerhalb, Feld zeigt auf ein anderes Gebäude, Gelände-Feld leer, Gelände-Feld
  ohne Gebäude) und prüft die Meldung. `pruef_technik/mess/kaputt2.mjs` meldet jetzt „abgelehnt Spielstand beschädigt: Lage der
  Gebäude“, `kaputt.mjs` lehnt weiter alle ab.
- **T2 Auswertung von `tests/alle.sh`.** `tests/raute_klick.cjs` schreibt je Klick eine Zeile mit „OK“ oder „FEHL“ vorn und endet mit
  exit 1 bei einem Fehlklick, weniger als 4 Klicks oder Fehlern auf der Seite. `tests/otest/hilfehoehe.cjs` prüft `scrollHeight ≤
  clientHeight` („OK Hilfe bei 1280 × 800 ohne Überlauf …“) und endet sonst mit exit 1.
- **T3 Bilder der Tests im Arbeitsordner.** p3test, p4test, p5neu, p6migration und p7figuren legen ihre Bilder in `tests/bilder_p3/` …
  `tests/bilder_p7/`, p8tech in `tests/bilder_p8/`, `tests/otest` in `tests/otest/bilder/` (vorher direkt im scratchpad, in
  `scratchpad/tech/sichtbar/werk/` und `scratchpad/design/r6/otest/bilder/`). Auch `v2import.json` von p6migration liegt jetzt dort.

### Texte

- **X1 Staatsbürger-Klausel (blockierend).** Das Fenster nannte die Beschränkung auf Deutsche nur als Forderung des Programms, obwohl das
  geltende Recht sie schon enthält. Jetzt (Karte „Wehrpflicht“, Annahme): „Zwei Abweichungen. Programm (S. 88) und geltendes Recht
  beschränken den Dienst auf Deutsche: Das Programm will ihn nur für deutsche Staatsbürger, und nach § 1 Abs. 1 WPflG sind alle Männer
  wehrpflichtig, die Deutsche im Sinne des Grundgesetzes sind (für Soldaten auf Zeit § 37 Abs. 1 Nr. 1 SG). Das Gesetz verpflichtet zudem
  nur Männer (Art. 12a Abs. 1 GG). Die Stadt kennt keine Staatsangehörigkeit, und das Geschlecht spielt keine Rolle: Sie beruft alle ein.“
  Hauskarte der Kaserne: „Programm und Gesetz: nur Deutsche, das Gesetz nur Männer; die Stadt kennt keine Staatsangehörigkeit und beruft
  alle ein.“ „Heute“: „Seit 2026 bekommen alle Deutschen ab dem Jahrgang 2008 nach dem 18. Geburtstag einen Fragebogen: Deutsche Männer
  müssen ihn beantworten und werden gemustert, für Frauen ist er freiwillig“ (bundeswehr.de, am 27. 9. 2026 gelesen). Der Grund unter
  „Nicht übernommen“ (S. 88) sagt, dass auch das geltende Recht die Beschränkung kennt. Kommentare an `R` und `einberufen` ebenso.
  `tests/militaer.cjs` prüft § 1 Abs. 1 WPflG, § 37 Abs. 1 Nr. 1 SG und „Deutsche Männer müssen ihn beantworten“. README Abschnitt „Bund“
  und B14 angeglichen.
- **X2 Untersuchungshaft in echten Tagen.** Die Urteilszeile schrieb „3 Tage Untersuchungshaft werden angerechnet“ (Spieltage). Jetzt wie bei
  der Ersatzfreiheitsstrafe: „110 Tage Untersuchungshaft (in der Stadt 3 Spieltage) werden angerechnet“. `--sicherheit` prüft den Wortlaut.
- **X3 Kopftext „Grenze der Stadt“.** Ergänzt: „… außer auf Zeit und für alle gleich: Haft in einer Anstalt des Landes außerhalb (solange die
  Anstalt in der Stadt fehlt oder voll ist) und Kinder, die das Jugendamt in einer Pflegefamilie außerhalb unterbringt. Beide bleiben
  Bewohner, Wohnung und Haushalt bleiben.“
- **X4 S. 138.** Das Programm sagt nicht „im Inland“. Karte, Grund unter „Nicht übernommen“ und README sagen jetzt: weist Terrorabwehr und
  den Schutz vor Spionage und Sabotage dem BND und den Polizeibehörden zu (S. 138, im Abschnitt zur Reform des Verfassungsschutzes; dass
  damit Aufgaben im Inland gemeint sind, ist eine Deutung der Stadt).
- **X5 S. 155.** Kommentar in `obhutKandidat`/`obhutSuchen` und README: Familie vor Pflegefamilie nach S. 155; die Reihenfolge innerhalb der
  Familie ist eine Annahme der Stadt. Die Karte sagt es auch.
- **X6 Das Sprachmodell verdächtigt niemanden.** Neu im Abschnitt „Antworten prüfen“: `verdachtFrei(text, i)` verwirft (wie ungültiges
  JSON) jeden Satz, der ein Wort des Verdachts oder einer Tat mit einem Wort zu Herkunft oder Religion verbindet, bei Opfern auch mit einem
  Vor- oder Nachnamen aus den festen Namenslisten der Stadt außer dem eigenen (Annahme 77). Das gilt für Entscheidungen (`gedanke`),
  Gespräche (`antwort`), Tagebuch (`eintrag`) und Code (`gedanke`). Der Satz in jeder Anweisung ist neutral: „Du weißt nur, was du selbst
  erlebt hast, und beurteilst andere nur nach dem, was du mit ihnen erlebt hast.“ (vorher mit der Aufzählung „Name, Herkunft, Sprache oder
  Religion“). `--kitest` prüft 11 Antworten, darunter „Ich glaube, Mehmet Koch hat mich bestohlen.“ (verworfen, auch als Entscheidung),
  „Das waren sicher Ausländer, …“ und „Die Zugezogenen sind schuld …“ (verworfen), dagegen „Ich weiß nicht, wer mich bestohlen hat …“,
  zwei Sätze mit Namen ohne Verdacht und den eigenen Namen (bleiben), und dass keine Anweisung „Herkunft“, „Religion“ oder „Sprache“ nennt.
  Die Wirkung des neuen Satzes an einem echten Modell ist nicht gemessen (hier gibt es nur den KI-Nachbau). Die Nachprüfung fand
  Wortformen, die durchgingen (Einbrecher, klaut, stahl, „fremd“, „<Name> ist ein Dieb“); nachgebessert im Abschnitt „Befunde der
  Nachprüfung“ (N2).
- **X7 Wache, Wirklichkeit.** § 99 HSOG mit den Befugnissen: „in Hessen auch Ordnungspolizei: Hilfspolizeibeamte der Gemeinden mit den
  Befugnissen der Polizei für ihre Aufgaben“ (anwalt24.de nachgelesen). Dichte: „alle Polizeibeamten, auch Bundespolizei und
  Bundeskriminalamt, die Wache ist Landespolizei: vereinfacht“.
- **X8 Nachrichtendienst in den USA.** „Keine Stadt hat einen Nachrichtendienst als eigene Behörde“; große US-Stadtpolizeien haben eigene
  Aufklärungsabteilungen, zum Intelligence Bureau der New Yorker Polizei gehörte die „Demographics Unit“ (Karte „Dienststelle“, Hinweis
  zum Bund, README).
- **X9 Leben in Haft.** „Das folgt dem Strafvollzugsgesetz des Bundes … Heute regeln das die Strafvollzugsgesetze der Länder, teils anders
  (nicht einzeln geprüft).“ Ebenso bei § 140 Abs. 2 StVollzG (Karte S7) und in S-A11.
- **X10 Obhut.** „Die Inobhutnahme ist eine vorläufige Unterbringung; für eine längere Zeit in einer anderen Familie sieht das Gesetz die
  Vollzeitpflege vor (§ 33 SGB VIII). Die Stadt unterscheidet das nicht.“ § 33 SGB VIII auf gesetze-im-internet.de nachgelesen.
- **X11 Grammatik.** „Im letzten Jahr wurde 1 Tat angezeigt“; Anweisung: „Zur Zeit lebt Mia bei dir, weil der einzige Erwachsene in ihrem
  Haushalt in Haft ist.“ (mit mehreren: „alle Erwachsenen in ihrem Haushalt“, mehrere Haushalte „ihren Haushalten“; `obhutGrund`, von
  `--kitest` geprüft). Die Personenkarte sagt dasselbe statt „ihr Haushalt ist in Haft“.
- **X12 und B9 Abstand beim Wachsen.** Fenster, Versionsmeldung und Zeile zählen jetzt einheitlich bis zum Rand der Karte: Die Karte wächst,
  wenn die Stadt „näher als 18 Felder an den Rand der Karte“ kommt (vorher „16“, gemeint war der erlaubte Rand zwei Felder weiter innen).
  Wächst die Karte in einer Nacht mehrmals, bleibt es eine Zeile („Die Stadt reicht in dieser Nacht zweimal nah an den Rand der Karte:
  zuerst im Norden bis 17 Felder, dann im Osten bis 12 Felder. … von 56 × 56 auf 80 × 80 Felder.“). `--erweiterung` prüft je Nacht eine
  Zeile mit beiden Größen und Abständen unter 18, dazu die doppelte Nacht auf Seed 2 (Tag 197).
- **X13 Zur Vollständigkeit.** „Beim Bund übernommen ist die Wehrpflicht mit Ersatzdienst (für alle, zwei Abweichungen). Kaserne und
  Dienststelle sind eine Annahme der Stadt (Arbeitgeber des Bundes), keine Forderung des Programms; …“
- **X14 Bau durch den Bauhof bei Wache und Anstalt.** Beide Karten haben jetzt den Hinweis „Vereinfacht: Das Land zahlt den Bau an die
  Stadtkasse, und der Bauhof der Stadt baut. In Wirklichkeit baut das Land über seine Bauverwaltung, Firmen bauen nach Ausschreibung.“
  (S-A9, S-A10.)
- **X15 Ersatzfreiheitsstrafen neu gemessen.** Seeds 1–80: 8.767 von 59.204 Geldstrafen = 14,8 % (je Stadt 9,5–25,2 %). „Etwa jede siebte“
  stimmt über 80 Seeds; die 18,1 % der Gegenprüfung kommen von den Seeds 1–6 (Bekannte Schwächen).
- **X16 Hinweis auf der Karte „Taten“.** „Keine Regel liest Namen, Herkunft, Zuzug oder Stadtteil, das Geschlecht nur für die Grammatik. Den
  Haushalt liest nur die Wahl des Opfers (nie im eigenen Haushalt; ein Einbruch trifft alle Erwachsenen dort), die Eltern-Verweise nur die
  Suche nach Angehörigen für Kinder.“
- **X17 S. 124 geteilt.** „Der Unterdrückung muslimischer Frauen stellt sich die AfD entgegen“ steht unter „Grenze der Stadt“ (Religion),
  „fordert in allen Bereichen die Gleichberechtigung von Mann und Frau.“ unter „Gilt schon“. Beide Teile mit `zitatpruef.py` und
  `zitate_genau.py` geprüft.
- **X18 Alter beim Anstellen.** Als Vereinfachung in der Karte „Kaserne“ („Das Alter spielt beim Anstellen keine Rolle; die Bundeswehr hat
  Altersgrenzen (nicht nachgeschlagen).“) und als B21.

### Bedienung

- **B1 Ein Block findet keinen Platz vor einem Straßenende (mittel).** Nachgeprüft: Nach der Übernahme der Seeds 1–6 (Version 6, Tag 260)
  bestellte das Land die Wache auf Seed 3, 4 und 5 erst 6, 11 und 17 Nächte nach Anstalt und Kaserne, auf Seed 2 nicht in 30 Nächten.
  Jetzt sucht `gelaendeSuchen` für einen Block, wenn kein ganzer Block an einer Straße frei ist, im Rahmen von zwei Blöcken und belegt 3 × 3
  Felder um das Tor auf der Rasterlinie (Annahme 78, Abschnitt „Stadt erweitern“): Die Wache kommt auf allen sechs in der ersten Nacht
  (`befunde/wache_mig.mjs`), die Dienststelle öffnet auf Seed 3 an Tag 333 statt 432. Die Zeile im Fenster sagt „kam“ nur für Anlagen, die
  offen sind; sonst „kam (noch im Bau)“ oder „kommt, sobald ein Platz frei ist“ (`erweiterungInfo().neuStand`). `tests/p6migration.cjs`
  verlangt die Wache jetzt in der ersten Nacht (vorher bis 60 Tage). Die Invarianten der Technik-Prüfung (`pruef_technik/mess/inv.mjs`,
  Seeds 1–3 je 730 Tage; `inv_mig.mjs`, Übernahme von drei V6-Ständen an Tag 300 und 200 Tage weiter) laufen ohne Fehler.
  **Nebenwirkung** (von der Nachprüfung gefunden, hier zuerst nicht genannt): Wo nach einer Übernahme an Straßen nur zwei freie Stellen
  an Straßenenden liegen, nimmt die Wache jetzt eine davon, und die Kaserne wartet statt der Wache (Seed 2 an Tag 200, 230, 260 und 330:
  14, 4, 15 und 67 Nächte, vorher je 1; Seed 8 an Tag 200: 7). Zahlen und Entscheidung im Abschnitt „Befunde der Nachprüfung“ (N1).
- **B2 Kind beim Jugendamt.** Der Lebenslauf sagte „lebt bei jemand“: Das Gedächtnis speichert −1, die Karte setzte „jemand“ ein. Jetzt
  „in Obhut des Jugendamts, weil zu Hause kein Erwachsener war“; die Wohnzeile sagt „gemeldet an der Hauptstraße, zur Zeit in einer
  Pflegefamilie außerhalb“ (bei Angehörigen „zur Zeit bei Angehörigen“). Mit echten Klicks nachgesehen (`befunde/bed/e2_obhut.cjs`).
- **B3 Hauskarte des Bauhofs.** „60 Leute bei 60 Stellen, Lohn 95 Taler am Tag; davon 20 leisten Ersatzdienst mit Sold vom Bund. Diese
  Plätze kommen zu den 40 bezahlten Stellen dazu“, mit Einzahl („1 leistet“, „Dieser Platz kommt“), ebenso für gemeinnützige Arbeit
  (`bauhofZeile`).
- **B4 Einzahl und Resttage.** Fenster „Taten“: „1 Tat angezeigt: 0 Diebstähle, 0 Wohnungseinbrüche, 1 Betrugsfall“ (vorher „1 Betrugsfälle“,
  jetzt mit `anz`), ebenso „1 Freiheitsstrafe“ und „1 Geldstrafe“ in den Zeilen „Bewährung“ und „Gericht“; Stadtbuch „wurde 1 Tat“;
  Personenkarte am letzten Diensttag „heute der letzte Diensttag“ statt „noch 0 Tage“.
- **B5 „Anstalt der Stadt“.** Stadtbuch: „alle in der Justizvollzugsanstalt an der Nordstraße“; Anweisung: „in der Justizvollzugsanstalt in
  der Stadt“; Grund S. 107: „die Anstalt in der Stadt“. Auch in Kommentaren und in `tools/simtest.mjs`.
- **B6 „einziger Erwachsener“.** Stadtbuch und Karte sagen „einziger Erwachsener“ nur, wenn es einer war, sonst „in dessen Haushalt alle 2
  Erwachsenen in Haft sind“; die Karte heißt „Kinder, deren Erwachsene alle in Haft sind“.
- **B7 Fenster lang.** Die Zeile der Karte „Die Stadt wächst“ ist kurz (Stufe, Karte, Zahl der Stadtteile, was die Stufen bringen); die
  Liste der Stadtteile steht im aufklappbaren Teil („Stadtteile heute: …“, eigene Live-Zeile). Oben unter „Was in der Stadt gilt“ stehen
  Sprunglinks zu allen neun Gruppen (Steuern … Bund in der Stadt, „Nicht übernommen“): ohne Übergang, der Fokus geht auf die Überschrift der
  Gruppe, `scroll-padding-top` (Höhe des festen Kopfes, beim Öffnen gemessen) hält sie unter dem Kopf. Gemessen (`befunde/bed/q_live_gross.cjs`,
  `f2_laenge.cjs`): Die Zeile hat in der großen Stadt am 360er-Handy 526 Zeichen und 232 px (vorher 1.459 Zeichen, 645 px). Das Fenster ist
  mit den Textbefunden etwas länger geworden: 25.945 px am 360er-Handy und 15.409 px bei 1280 × 800 (Teil 3: 25.174 und 14.980, bc7247a:
  13.156 und 7.954), 30 Karten, 16 mit aufklappbarem Teil.
- **B8 Stadtteilnamen im Nebel und nachts.** Die Deckkraft eines Namens ist 0,62 × (1 − Nebel an seiner Stelle), mit derselben Formel wie
  der lineare Nebel von three.js 0.186.0 (`smoothstep(near, far, Tiefe)`, `fog_fragment.glsl.js` nachgesehen), in 20 Stufen über eine
  CSS-Variable (feste Texte, keine Allokation). Ganz im Nebel steht kein Name. Nachts (18 bis 7 Uhr) liegt ein leiser Grund wie bei den
  Straßennamen darunter (`::before`, ändert die gemessene Größe nicht). Gemessen in der großen Stadt (Tag 750, `befunde/namen_nacht.cjs`): um 11, 19 und 23 Uhr je 10 Namen, Sicht 0,8 bis 1
  (hinten 0,8); nachts mit Grund (Bild `befunde/bild/namen_gross_23h.png`, Teststadt `nachher/breit_23h_fern.png`).
- **B10 Vorbestehend.** (1) Nach einem Mausklick auf ein Tempo ist die Leertaste wieder Pause und weiter (der Knopf merkt sich, dass er
  seinen Fokus von der Maus hat; `:focus-visible` taugt dafür nicht, die Taste schaltet es selbst ein, gemessen). Mit der Tastatur
  angesteuert drückt die Leertaste den Knopf wie jeden anderen. (2) Umschalt+Tab im Fenster „Stadtregierung“ bei 568 × 320: kein Fokus mehr
  unter dem festen Kopf (`scroll-padding-top`, 52 Schritte gemessen). (3) Aufholen in 3 × 30 Tagen ergibt eine andere Stadt als 1 × 90: So
  gebaut (Annahme 43: ganze Tage im Tagesschritt, bis Mitternacht und nach Mitternacht stündlich; drei Stücke haben andere Übergänge), nicht
  geändert, unter „Bekannte Schwächen“. (4) Versionsdialog quer: Die Knopfleiste reicht bis an den unteren Rand, kein Text läuft sichtbar
  darunter weiter; bei höchstens 500 px Höhe ist der Dialog breiter und flacher gesetzt (Titel kleiner, Knöpfe in einer Reihe). Gemessen
  (`befunde/bed/h2_dialog_vergleich.cjs`, Stand der Version 5): bei 568 × 320 sind 199 px Text zu sehen (bc7247a 69 px), zu scrollen 136 px
  (bc7247a 202 px); bei 844 × 390 267 px Text (bc7247a 135 px). „Stadt übernehmen“ bleibt im Bild (`tests/befunde_s2.cjs`).
  `befunde/bedien.cjs` prüft (1) und (2).

### Gemessen (Endstand)

**Seeds 1–3** (`simtest --gate`, 730 Tage stündlich, alle Gates bestanden; in Klammern Teil 3):

| Seed | Einwohner Tag 365 / 730 | Band Gate 4 | Gate 6 / Gate 7 | Stadtbuch je Tag | Kaserne / Dienststelle offen ab Tag | Wehr- / Ersatzdienst | Diensttage (beendet / abgebrochen) | Taten (D / E / B) |
|---|---|---|---|---|---|---|---|---|
| 1 | 820 / 1.148 (819 / 1.145) | 1,10 (1,10) | +19,4 / −23,1 (+19,5 / −23,0) | 5,55 (5,64) | 206 / 367 (206 / 368) | 101 / 217 | 1.566 (312 / 2) | 1.366 / 70 / 514 |
| 2 (Teststadt) | 792 / 1.169 (gleich) | 1,08 (gleich) | +21,8 / −23,2 (gleich) | 5,29 (gleich) | 211 / 371 (gleich) | 101 / 208 | 1.519 (298 / 3) | 1.299 / 49 / 504 |
| 3 | 967 / 1.181 (951 / 1.148) | 1,09 (1,03) | +20,7 / −26,8 (+19,7 / −27,1) | 4,99 (4,82) | 184 / 333 (184 / 432) | 102 / 288 | 1.925 (379 / 6) | 1.316 / 48 / 475 |

Seed 2 ist Tag für Tag dieselbe Stadt wie in Teil 3; auf Seed 1 und 3 öffnet die Dienststelle früher (B1), danach laufen die Städte
anders. Das Stadtbuch hat auf Seed 1 weniger Zeilen, weil zwei Wachstumszeilen einer Nacht jetzt eine sind.

**Seeds 1–80** (`befunde/mess/mess10.mjs` = `mil/mess/mess9.mjs` plus Zahl der Geldstrafen, `befunde/mess/lauf80.sh`, Auswertung
`befunde/mess/auswertung.py`, 730 Tage stündlich, gegen dieselbe Messung auf bc7247a und auf Teil 3):

| Stand | alle Gates | fällt | Band Ø / Median / schlimmster | Gate 7 kleinster Abstand | Einwohner Tag 365 / 730 | Wegzüge (Personen) | Zuzüge | Taten je 1.000 und Jahr | Dienststelle offen ab Tag |
|---|---|---|---|---|---|---|---|---|---|
| bc7247a | 77 von 80 | G4: 11, 23, 45 | 1,077 / 1,073 / 1,155 | 16,5 | 896 / 1.110 | 40,2 | 1.028 | – | – |
| Teil 3 | 76 von 80 | G4: 44, 73, 77, 79 | 1,086 / 1,080 / 1,213 | 15,2 | 912 / 1.189 | 64,7 | 1.112 | 32,78 | Ø 369 (320–584) |
| Endstand | **78 von 80** | G4: 44, 77 | 1,081 / 1,074 / 1,177 | 16,8 | 917 / 1.186 | 63,0 | 1.108 | 32,82 | Ø 342 (313–395) |

Nach der Nachprüfung neu gerechnet: alle 80 Zeilen gleich (die Simulation hat sich nicht geändert), bc7247a ebenso gleich 77 von 80.
Welche Seeds an Gate 4 fallen, wechselt mit jeder Änderung (Teil 3); 78 gegen 77 ist kein „besser“ über das Rauschen hinaus. Gate 6 und 7
halten auf allen 80 Seeds, Gate 4 nie über 1,18. Taten 22,76 / 0,959 / 9,10 je 1.000 Einwohner und Jahr (Ziel 32,1). Ersatzfreiheitsstrafen
8.767 von 59.204 Geldstrafen = 14,8 % (X15). Kaserne offen im Mittel ab Tag 191 (162–238) wie in Teil 3; Tag 366–730 im Mittel 7,43 von 8
Soldaten, 3,32 von 4 Zivil, 3,48 von 4 im Nachrichtendienst (Teil 3: 3,27, die Dienststelle öffnet früher). Karte 80 bis 120 Felder,
2- bis 8-mal gewachsen.

**Übernahmen und Invarianten.** `befunde/wache_mig.mjs` (Seeds 1–6, Version 6 an Tag 260 übernommen, 30 Tage): Die Wache kommt in der
ersten Nacht, vorher auf Seed 2 nicht in 30 Tagen und auf Seed 3, 4, 5 nach 6, 11 und 17 Tagen. `pruef_technik/mess/inv.mjs` (Seeds 1–3,
730 Tage, Invarianten nach jeder Nacht und stündlich: Feld ↔ Gebäude, Gelände, Bauplätze, Viertel, Kreuzungen, Haft, Obhut, Bund) und
`inv_mig.mjs` (drei V6-Stände an Tag 300, 200 Tage weiter): 0 Fehler, 7 und 2 Wachsen.

**Browser.** Teststadt (Seed 2, Tag 400, `tests/blick.cjs` nach `nachher/`): 943 bis 944 Einwohner, Großstadt, Karte 80 × 80, 26 bis 29
Draw Calls, 52.100 bis 53.000 Dreiecke (Teil 3: 27 bis 29, 52.200 bis 52.700). Große Stadt (`&umland=300000`, Seed 2, Tag 750, nach
`gross/`): 5.850 bis 5.852 Einwohner, Karte 144 × 144, 25 bis 28 Draw Calls, 141.300 bis 146.400 Dreiecke (Teil 3: 5.852, 144, 25 bis 28,
141.300 bis 146.400). Neue Draw Calls: keine. Bilder selbst angesehen: nachts stehen die Stadtteilnamen auf einem leisen Grund über den
hellen Fenstern, bei Tag unverändert; in der großen Stadt sind die hinteren Namen (Erlenbruch, Heideland) blasser. In `gross/` fehlen die
Namen auf den Bildern um 19 und 23 Uhr: `blick.cjs` war vorher nah an der Straße (Straßennamen) und fotografiert, bevor die Stadtteile
wieder eingeblendet sind; `befunde/namen_nacht.cjs` zählt auf demselben Stand nach 1 s um 11, 19 und 23 Uhr je 10 Namen (auch in Teil 3).

### Speicherformat

Unverändert Version 7, keine neuen Felder. Neu sind nur die Prüfungen beim Laden (T1). `--speichertest`: bitgleich, **Fingerabdruck `6277f264ccaf83c3`** (Seed 1, Tag 150, 13 Uhr, 60 Tage weiter; Teil 3 `5ba8d43e5bd37135`),
Stand mit Haft und Obhut `32021f94c3f14a09` (sortiert `14257e0eb4f2720c`), Stand mit dem Bund `8561f07316321917` (sortiert
`d32219e512e09f1d`), je 60 Tage bitgleich. Die Abdrücke sind neu, weil sie das Stadtbuch enthalten (Urteilszeile mit echten Tagen,
Wachstumszeilen); die Stadt selbst läuft bis Tag 362 gleich (`befunde/vergleich.mjs`). `tests/basis_v7.json` (Teststand für t1_xss)
besteht auch die neuen Prüfungen beim Laden.

### Tests auf dem Endstand

Endstand `stadt.html` md5 `47d45ed0f50f5e7a7905b2712c802961`, `tools/simtest.mjs` md5 `3e9e135db527a9281fa92b609d0c7648`, KI-Nachbau
auf 11434. Die simtest-Modi liefen auf `7613e1bc32ee24bd21475388af719317`; danach änderten sich nur drei Live-Zeilen im Fenster (Einzahl in
„Taten“, „Bewährung“, „Gericht“). sim-Block, der Abschnitt für `--kitest` und `REGIERUNG` sind gleich (verglichen), `--kitest` lief auf dem
Endstand noch einmal. Die Browser-Tests liefen auf dem Endstand (Server auf 8713, PID 9511, danach beendet; der erste Lauf mit PID 535). Läufe in `scratchpad/erw7/befunde/lauf/` (`fin_*.txt`) und `tests/alle_end.log`.

- `simtest`: `--gate` (Seeds 1–3 alle Gates, T 3,0 bis 3,7 s im Parallellauf), `--speichertest` (bitgleich, drei Stände), `--aufholtest`
  (Vergleich, keine Prüfung), `--kitest` 47 (neu: Antworten ans Sprachmodell, Obhut-Satz; vorher 46), `--bau` 15, `--waren` 15, `--tech` 16,
  `--regierung` 154, `--kita` 40, `--sicherheit` 28 (Urteilszeile mit echten Tagen), `--militaer` 24, `--migrationstest --git
  /home/user/website-` 293 (Version 2–6, bc7247a als 6), `--erweiterung --gross --git /home/user/website-` 34 (neu: doppelte Nacht als eine
  Zeile, vier beschädigte Stände mehr; vorher 33). Alle ohne Fehler.
- Browser (`tests/alle.sh`): p3test 12, p5neu 10, p6migration 26 (Wache jetzt in der ersten Nacht verlangt, Stadtteile im aufklappbaren
  Teil), p7figuren 6, p8tech 14, raute_klick 6 von 6 Klicks (jetzt mit exit-Code), ereignis 21, t1_xss 5, p4test 25, s2karten 22, kita 22,
  befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16 (Staatsbürger in Programm und Gesetz, § 1 Abs. 1 WPflG, § 37 SG, „Deutsche Männer
  müssen ihn beantworten“, S. 138 als Deutung, Intelligence Bureau), `otest` befunde 21, handy 11, breit 12, tastatur 4, breiten 20,
  hilfehoehe 1 (745 von 745 px, jetzt als Prüfung). Alle exit 0. Die Konsole ist leer bis auf die absichtlichen Verbindungsfehler zum
  KI-Nachbau in p4test und die abgebrochenen KI-Anfragen in `blick.cjs`. Dazu `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs`
  (wie Teil 1: quer 156 bis 216 px wie bc7247a, hochkant 231 statt 211 px).
- Eigene Prüfungen: `befunde/bedien.cjs` (Leertaste nach Mausklick, Tastatur auf 5×, Umschalt+Tab quer; mit `ALT=1` gegen Teil 3: zwei
  FEHL, also vorher wirklich kaputt), `befunde/bed/e2_obhut.cjs` (Kind beim Jugendamt, echte Klicks), `befunde/wache_mig.mjs`,
  `befunde/vergleich.mjs`, `befunde/namen_nacht.cjs`, `pruef_technik/mess/inv.mjs` und `inv_mig.mjs`, `kaputt.mjs` und `kaputt2.mjs`.
- Zitate: 235 im Fenster, davon 232 aus dem Programm; `zitatpruef.py` findet 232, `zitate_genau.py` findet dieselben 232 wörtlich auf der
  genannten Seite, 0 Fehler. Die übrigen 3 sind Noahs „Wie in Amerika“ (zweimal) und der Name „Demographics Unit“. Neu sind die zwei Teile
  von S. 124 (vorher ein Satz); den Zusammenhang von S. 124 und S. 138 habe ich auf den Seiten nachgelesen (Abschnitt „Polygamie,
  Zwangsheirat und Kinderehen“ bzw. „Verfassungsschutz grundsätzlich reformieren“). § 1 Abs. 1 WPflG steht im Fenster nicht als Zitat,
  sondern umschrieben, damit die Zitatliste nur Programmzitate enthält.
- Bilder: `nachher/` (Teststadt) und `gross/` (große Stadt), selbst angesehen (oben); `scratchpad/erw7/befunde/bild/` (Fenster,
  Versionsdialog, Obhut, Stadtteilnamen).

## Befunde der Nachprüfung

Eine Nachprüfung hat den Endstand der Schlussprüfung (`stadt.html` md5 `47d45ed0f50f5e7a7905b2712c802961`) noch einmal gelesen,
nachgerechnet und bedient (`scratchpad/erw7/nachpruef/`). X1 bis X5, die Wache aus B1 und B2 waren behoben; offen oder neu waren drei
Punkte. Jeder ist hier erst nachgeprüft und dann umgesetzt. **Die Simulation ist unverändert** (sim-Block gleich, Fingerabdrücke gleich,
Seeds 1–80 Zeile für Zeile gleich); geändert sind die Prüfung der Antworten des Sprachmodells (module-Block), `--kitest`,
`tests/p6migration.cjs` und dieses README. Arbeitsdateien: `scratchpad/erw7/nb/` (`vorher/` = Stand vor der Nachbesserung, `mess/`,
`lauf/`, `zitate/`).

- **N1 Nebenwirkung von B1: Nach einer Übernahme wartet manchmal die Kaserne (mittel).** Nachgeprüft mit `nb/mess/b1_warten.mjs`:
  V6-Stände (bc7247a) der Seeds 1–8 an Tag 200, 230, 260 und 330 übernommen, höchstens 100 Nächte weiter; der Endstand gegen die
  Gegenprobe der Nachprüfung (Rückfall der Wache erst, wenn Anstalt und Kaserne stehen) und gegen den Stand vor B1. Zahlen: Nacht der
  Bestellung nach der Übernahme (1 = erste Nacht; die Dienststelle ab der Nacht, in der die Stadt Großstadt ist; – = nicht fällig):

  | Übernahme | Endstand: Wache / Anstalt / Kaserne / Dienststelle | Gegenprobe | vor B1 |
  |---|---|---|---|
  | Seed 2, Tag 200 | 1 / 1 / **14** / – | 9 / 1 / 1 / – | 33 / 1 / 1 / – |
  | Seed 2, Tag 230 | 1 / 1 / **4** / – | 5 / 1 / 1 / 1 | 31 / 1 / 1 / über 4 |
  | Seed 2, Tag 260 | 1 / 1 / **15** / 1 | 19 / 1 / 1 / 1 | 43 / 1 / 1 / über 24 |
  | Seed 2, Tag 330 | 1 / 1 / **67** / **90** | 73 / 1 / 1 / 13 | 76 / 1 / 1 / 72 |
  | Seed 8, Tag 200 | 1 / 1 / **7** / – | 8 / 1 / 1 / – | 8 / 1 / 1 / – |
  | übrige 27 Fälle | Wache, Anstalt, Kaserne 1; Dienststelle 1, wo in 100 Nächten fällig (Seed 5, Tag 330: 2) | Wache in 19 Fällen 2, sonst 1; Dienststelle Seed 5, Tag 330: 71 | Wache 1 bis über 100 |

  Die Nachprüfung nannte Seed 8 unauffällig; an Tag 200 wartet dort die Kaserne 6 Nächte länger als vorher. Ursache (Karte nachgesehen,
  `nb/mess/b1_karte.mjs`, Seed 2, Tag 260): Die Stadt ist ein schmales L aus zwei Straßen, jeder Block an einer Straße hat schon
  Häuser. Frei sind nur die beiden Straßenenden. Die Wache nimmt das südliche (Rückfall, 3 × 3 Felder um das Tor), die Anstalt findet
  dort keine zwei Blöcke mehr und nimmt das östliche (1 × 2), wo vorher die Kaserne stand. Die Kaserne wartet, bis das Bauamt eine
  Straße verlängert.

  **Entscheidung: Die Wache bleibt zuerst.** (1) Sie gehört zur Stufe Kleinstadt; in einer Stadt, die mit Version 7 wächst, steht sie
  immer vor Anstalt und Kaserne (Seeds 1–80: Wache im Mittel ab Tag 73, Kaserne offen ab Tag 191). Eine übernommene Stadt sieht danach
  aus wie eine gewachsene. (2) Taten gibt es ab dem Übernahmetag, die Wache gehört dazu. (3) Die Gegenprobe zeigt: Es fehlt wirklich
  Platz, die andere Reihenfolge verschiebt nur, wer wartet, und sie ließe die Wache auf den meisten Seeds eine Nacht länger warten, weil
  das Land vor dem Bund baut. (4) Die geprüfte Simulation bleibt, wie sie ist. Noah kann es anders wollen (offene Frage im Abschnitt
  „Bund“). Solange die Kaserne wartet, sagt das Fenster ehrlich „Mit der Stufe Stadt kommt, sobald ein Platz frei ist: eine Kaserne der
  Bundeswehr mit Wehrpflicht.“; einberufen wird erst ab der Eröffnung.

  Nachgetragen: B1 in „Befunde der Schlussprüfung“, Annahme 78, Schnittstelle „Ein Block“, „Bekannte Schwächen“ (Gelände, Wache,
  Dienststelle), offene Fragen im Abschnitt „Bund“. `tests/p6migration.cjs` hat einen neuen Fall: Version 6 von Seed 2, Tag 260
  übernehmen; Wache und Anstalt in der ersten Nacht; die Kaserne kommt in Nacht 15 (die Zeile im Test nennt die Wartezeit), solange
  sie wartet, steht die Zeile oben im Fenster, niemand wird vorher einberufen, und sie muss innerhalb von 60 Nächten kommen (wie früher
  die Wache). 3 Prüfungen mehr, 29 statt 26.
- **N2 Wortformen in der Prüfung gegen Verdacht (mittel).** Nachgeprüft mit dem Skript der Nachprüfung (`nachpruef/mess/x6_verdacht.mjs`):
  Alle sieben Sätze gingen durch, die zwei harmlosen wurden verworfen. Jetzt drei Wortlisten und eine Herkunftsliste (Annahme 77):
  - TAT, bei jeder Figur zusammen mit einem anderen Namen der Stadt verworfen: verdächtig, Verdacht, gestohlen, bestohlen, stehlen,
    stiehlt, bestiehlt, stahl, klaut, klauen, geklaut, beklaut, Einbrecher, einbrechen, einbrach, eingebrochen, Einbruch, Dieb, Täter,
    Raub, geraubt, Räuber, Überfall, kriminell, Kriminalität, Verbrecher, Gauner, Betrüger. „klau“ ist so begrenzt, dass „Klaus“ (ein
    Vorname der Stadt) nicht zählt.
  - VERDACHT (beim Opfer mit einem Namen, bei allen mit Herkunft): war es, waren es, betrogen, betrügen, Betrug, abgezockt, schuld,
    schuldig. OPFER (nur beim Opfer): vermute, vermutlich, steckt dahinter, weggenommen, „mein … genommen“ („Ich habe mir frei
    genommen“ bleibt).
  - HERKUNFT neu: fremd (Fremde, Fremden, nicht „fremdgehen“), Ausland, Abstammung, „nicht von hier“, „woanders her“, Einwanderer,
    zugereist, deutsch, einige Herkunftsbezeichnungen (südländisch, osteuropäisch, orientalisch, afrikanisch, syrisch, afghanisch,
    albanisch, rumänisch, bulgarisch, polnisch, russisch, kurdisch), Hautfarbe, Rasse, ethnisch, Kultur, Moslem, Christen, Religion,
    Kopftuch, Sprache, Akzent, „mit … Namen“.
  - Neu ist auch: Figuren, die kein Opfer sind, dürfen niemanden der Stadt mit einem Wort einer Tat verbinden („Ich glaube, Mehmet Koch
    ist ein Dieb.“, „Mia Weber stiehlt.“). „X hat mich beim Kartenspiel betrogen, aber wir sind Freunde“ bleibt (kein Wort aus TAT).
  - Komma: Die Prüfung trennt bewusst nicht am Komma. Mit Trennung gingen „Es war Elias Müller, der mich bestohlen hat.“ und „Das waren
    sicher Ausländer, die bei mir eingebrochen haben.“ durch. „Ich wurde bestohlen, Lea Lange hat mich getröstet.“ wird deshalb weiter
    verworfen (bewusste Vorsicht; Kommentar im Code, Annahme 77, „Bekannte Schwächen“).
  - Nachnamen, die auch gewöhnliche Wörter sind (26, etwa Richter, Koch, Klein, Lange, Winter, Sommer), zählen nur nach einem Vornamen
    oder „Herr“, „Frau“, „Familie“. So bleiben „Klein war der Schaden nicht, bestohlen zu werden tut weh.“ und „Der Richter hat mich wegen
    Diebstahls verurteilt.“ (wichtig für Figuren im Verfahren); „Herr Koch ist verdächtig.“ wird weiter verworfen. Grenze: „Koch war es.“
    mit dem Nachnamen allein geht durch.
  - `--kitest` prüft jetzt 29 Sätze statt 11: die sieben der Nachprüfung, „Es war …, der mich bestohlen hat“, „… stiehlt“, „Leute mit
    komischen Namen klauen“, „Wer kein Deutsch spricht, stiehlt eher“ (verworfen), dazu harmlose Sätze: „Klein war der Schaden nicht …“,
    „Ich habe mir frei genommen und treffe …“, „Der Richter hat mich …“, „Mit … war es heute lustig“, „Er ist fremdgegangen und hat mich
    betrogen“, „Klaus hilft mir heute beim Umzug“ (bleiben). Die gewählten Namen im Test (etwa Mehmet Koch) trägt weder das Opfer noch die andere Figur.
    Gegenprobe: dasselbe `--kitest` auf dem Stand vor der Nachbesserung meldet 12 falsch beurteilte Sätze. 44 Sätze in
    `nb/mess/x6_neu.mjs`, alle wie erwartet (darunter „Die Russen klauen alles.“, „Auf der Terrasse wurde mir das Fahrrad geklaut.“).
- **N3 README „Grenze“ (klein).** Der Absatz „Grenze“ im Abschnitt „Stadtregierung“ sagt jetzt wie das Fenster: „… außer auf Zeit und
  für alle gleich …: Haft in einer Anstalt des Landes außerhalb (solange die Anstalt in der Stadt fehlt oder voll ist) und Kinder, die
  das Jugendamt in einer Pflegefamilie außerhalb unterbringt. Beide bleiben Bewohner …“.

### Geprüft (Nachprüfung)

Endstand `stadt.html` md5 `0db3cba9aabd46364ab9251fc3702ba3`, `tools/simtest.mjs` md5 `3ff93c8f86835d6be45b021952cd9c22`,
`tests/p6migration.cjs` md5 `574972cce5c24dd0c3a355512ba9aa25`. Alle Läufe auf genau diesem Stand (Logs in `scratchpad/erw7/nb/lauf/`,
`nb/mess/`, `tests/alle_nb.log`). Server auf 8713 (PID 16845, danach per PID beendet), KI-Nachbau auf 11434 unverändert.

- `simtest`: `--gate` (Seeds 1–3 alle Gates, T 1,4 bis 1,9 s), `--speichertest` bitgleich mit denselben Fingerabdrücken wie vorher
  (`6277f264ccaf83c3`, Haft `32021f94c3f14a09`, Bund `8561f07316321917`), `--aufholtest` (Vergleich, keine Prüfung), `--kitest` 47 (die
  Prüfung „Antworten ans Sprachmodell“ hat jetzt 29 Fälle statt 11), `--bau` 15, `--waren` 15, `--tech` 16, `--regierung` 154, `--kita` 40,
  `--sicherheit` 28, `--militaer` 24, `--migrationstest --git /home/user/website-` 293 (Version 2–6, bc7247a als 6), `--erweiterung --gross
  --git /home/user/website-` 34. Alle exit 0, kein FEHL.
- **Seeds 1–80** (`befunde/mess/mess10.mjs` über `nb/mess/lauf80.sh`, 730 Tage stündlich): 78 von 80 (G4 fällt auf 44 und 77), Band Ø 1,081,
  schlimmster 1,177, Gate 7 kleinster Abstand 16,8; alle 80 Zeilen gleich wie in „Gemessen (Endstand)“ (die Simulation ist unverändert).
  bc7247a mit demselben Skript neu gerechnet (`nb/mess/lauf80b.sh`): 77 von 80 (G4: 11, 23, 45), Zeile für Zeile gleich wie die
  gespeicherte Basis.
- **Browser** (`tests/alle.sh`, Start 13:03): p3test 12, p5neu 10, p6migration 29 (neu: Seed 2, Tag 260, Kaserne in Nacht 15, bis dahin
  „kommt, sobald ein Platz frei ist“), p7figuren 6, p8tech 14, raute_klick 6 von 6 Klicks, ereignis 21, t1_xss 5, p4test 25, s2karten 22,
  kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16, `otest` befunde 21, handy 11, breit 12, tastatur 4, breiten 20,
  hilfehoehe 1. Alle exit 0. Dazu `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs` (quer 156 bis 216 px wie bc7247a, hochkant
  231 px wie vorher). Die Konsole ist leer bis auf die absichtlichen Verbindungsfehler zum KI-Nachbau in p4test und die abgebrochenen
  KI-Anfragen in `blick.cjs`. In p4test stehen „gültig 3, ungültig 1“ statt „4, 0“: Der Nachbau liefert jede 25. Antwort kaputt, sein
  Zähler läuft über alle Tests; keiner seiner Sätze wird von der neuen Prüfung verworfen (`nb/mess/mock_saetze.mjs`, 34 Prüfungen).
- **Bilder** (`tests/blick.cjs`, selbst angesehen): Teststadt (Seed 2, Tag 400, `nachher/`) 943 bis 944 Einwohner, Großstadt, Karte
  80 × 80, Kaserne mit Hangar, Hubschrauberplatz und Übungsplatz am Rand, Stadtteilnamen bei Tag, Straßennamen nah; 26 bis 29 Draw Calls,
  52.093 bis 53.109 Dreiecke (Debug-Ecke der angesehenen Bilder und `blick.log`). Große Stadt (`&umland=300000`, Seed 2, Tag 750, `gross/`):
  5.850 bis 5.852 Einwohner, Karte 144 × 144, Stadtteilnamen um 11 und 19 Uhr, 25 bis 28 Draw Calls, 141.303 bis 146.447 Dreiecke. Wie
  vorher, keine neuen Draw Calls.
- **Zitate**: 235 im Fenster gesammelt (`mil/mess/zitate_sammeln.mjs`), `zitatpruef.py` findet 232 wörtlich, `zitate_genau.py` dieselben
  232 auf der genannten Seite, 0 Fehler; die übrigen 3 sind Noahs „Wie in Amerika“ (zweimal) und „Demographics Unit“. Außerhalb von
  `REGIERUNG` (`nachpruef/zitate/alle_html.py`) wie vorher. `REGIERUNG` ist in dieser Runde nicht geändert.
- **Speicherformat**: unverändert Version 7, keine neuen Felder (Fingerabdrücke oben).
- Git in `/home/user/website-` unverändert (`git status` leer).

## Tech-Firmen und Autos (Version 8)

Noahs Wunsch: „Mach noch das die tech Firmen also wenn die gegründet werden richtig krass sind und auch eigen Autos und alles gebaut
werden“. Seine Entscheidungen: **echte Autos** (Autofirmen entstehen aus Tech-Firmen, Bewohner kaufen Autos und fahren sichtbar,
Tech-Firmen wachsen zu Campus und Hochhaus); **Autos auch von außerhalb**: von Anfang an bei einem Autohaus im Umland, mit neutralen
Typen und gedeckten Farben, dazu die eigene Marke, sobald die Stadt ein Werk hat; **Erbe**: ein Autowerk ist ein Betrieb wie jeder andere
(es schließt, wenn der Besitz stirbt, das leere Werk kann übernommen werden).

Eingebaut in zwei Teilen: **Teil 1, die Simulation** (Regeln, Geld, Speicherformat), und **Teil 2, die Darstellung** (Autos auf der Straße,
Campus, Hochhaus, Autowerk, Lichtkegel, Karten, Hilfe; Abschnitt „Darstellung (Teil 2)“ unten). Die Darstellung entscheidet nichts selbst:
wo ein Auto steht oder hinfährt, ob sein Besitzer fährt, wer den Prototyp fährt, wann eine Firma eröffnet, Marke, Modell und Farbe kommen aus
der Simulation.

Umgesetzt im sim-Block im Abschnitt „Tech-Firmen wachsen, Autowerke, Autos der Bewohner (Version 8)“ (bis „Ende Autos“), dazu Stellen in
`stellen`, `stellenBuchen`, `schliessen`, `sterben`, `aktGruenden`, `techArbeit`, `wirtschaft`, `kistenVerteilen`, `kennzahlenRechnen`, in den
Karten- und Stadtbuchtexten und im Speicherformat. Der Abschnitt zieht Zufall nur aus einem eigenen Strom `S.rsAuto`; keine Regel liest
Namen, Geschlecht, Herkunft, Einzugstag, Eltern oder das Gedächtnis (`--autos` prüft das statisch je Funktion und mit einem Namenstausch).
Grundlage waren der Entwurf in `scratchpad/techautos/entwuerfe.json` (Prototyp auf 414ebab/bc7247a) und seine Gegenprüfung „sim“; übertragen
ist die Logik auf ffa1d88 (Version 7), nicht die Patches. Die Darstellung steht im Modul im Abschnitt „Tech-Firmen und Autos (Version 8,
Darstellung)“ (vor „Klicken“), dazu Stellen in `stadt()`, `karteNeu`, `figurenPlanen`, `figurenBewegen`, `treffen`, `toenenAlle`, `hoehenMerken`,
`gebHoehe`, `licht`, `render`, in der Personenkarte und der Hilfe; Grundlage war der Prototyp der Darstellung (`scratchpad/techautos/darstellung/`)
mit seiner Gegenprüfung „darstellung“, neu geschrieben auf den Stand von Teil 1 (Koordinaten zu `S.mitte`, wachsende Karte, Werk auf dem
Gelände der Simulation), nicht der Patch.

### Regeln

- **Tech-Firmen wachsen weiter (A1).** Stellen je Stufe 4, 8, 12, 16, 20; Stufe 4 heißt **Campus**, Stufe 5 **Hochhaus** (mit Leuchtlogo in
  Teil 2). Jeder Schritt wie der Anbau vorher: 20 Tage in Folge Gewinn, alle Stellen besetzt, die Rücklage reicht (Stufe 4: 5.000 Taler,
  20 Arbeitstage; Stufe 5: 8.000 Taler, 24 Arbeitstage), Platz im Umland und genug Arbeitssuchende, und die **40-%-Grenze** der Tech-Stellen an
  den Umland-Stellen mit den Stellen danach. Neu: Die Grenze gilt auch bei jeder Übernahme (auch eines großen leeren Hauses) und **nach dem
  Auftrag**. Steigt der Anteil nachts über 40 % (etwa weil Werkstätten schließen), **ruhen** Stellen in Tech-Firmen, zuerst freie, sonst
  besetzte (wer eine hat, behält sie; wer geht, wird nicht ersetzt, wie im Bauhof); ist wieder Platz, werden sie wieder Stellen
  (`techGrenzeHalten`, nach Gebäudenummer, nie nach Personen). `R.TECH_GRENZE_HALTEN = 0` schaltet das für Vergleiche ab.
- **Eröffnung als Ereignis.** Jede Tech-Firma trägt den Tag und die Art ihrer Eröffnung (`g.eroeffnet`, `g.eroeffnetArt`: Gründung,
  Übernahme, Autowerk, Campus, Hochhaus), auch nach dem Neuladen (im Spielstand). Für die Darstellung und die Hauskarte.
- **Autowerk (A2, A3).** Ab der Stufe **Stadt** baut eine Handy- oder Computerfirma ab Stufe 3 mit ehrgeizigem Besitz (Ehrgeiz ab 70) statt
  des nächsten Ausbaus ein Autowerk, **höchstens 2 Werke** in Betrieb oder im Bau (`AUTO_MAX`, auch bei Übernahmen: eine Gründung übernimmt
  ein leeres Werk nur unter `AUTO_MAX`, eine Firma zieht nur dann um). Steht ein Werk leer, übernimmt die Firma es für 40 % (8.000 Taler);
  sonst lässt sie es auf einem freien Block am Stadtrand bauen, über die Gelände-Schnittstelle aus „Stadt erweitern“ (`gelaendeSuchen(S, 1, 1,
  true)`, `gelaendeBauen`), 20.000 Taler aus Rücklage und eigenem Geld des Besitzes über 2.000 Taler, alles an die Stadtkasse, der Bauhof
  baut 48 Arbeitstage. Findet sich kein Block, sucht sie in der nächsten Nacht wieder. Ist das Werk fertig, **zieht die Firma um** (Belegschaft,
  Kasse, Rücklage, Marke); das alte Haus steht leer und kann übernommen werden. Mit weiteren Hallen wächst das Werk bis Stufe 6 (24 Stellen);
  eine Halle kostet wie die Stufe, auf die sie führt (Stufe 6: 10.000 Taler, 24 Arbeitstage), mit denselben Grenzen. Das Werk kostet 120 Taler am Tag. Stirbt der Besitz, schließt es wie jeder Betrieb.
- **Fertigung (A5, A6, A16).** Jede anwesende Kraft baut am Tag 0,575 Autos (Rest in Tausendsteln). Das erste Modell hat die Firma vor dem
  Umzug entwickelt, jedes weitere braucht 480 Arbeitstage (A6). Was die Stadt nicht kauft, geht ins Umland, bezahlt wie jede Tech-Firma je
  Arbeitstag (A16). Wer im Werk arbeitet, baut Autos und schreibt keinen Code (A17).
- **Teile (A7).** Je Auto, das in der Stadt verkauft wird, kauft das Werk 24 Kisten, zuerst bei Werkstätten der Stadt (`kistenVerteilen`,
  `g.kistenWerk`). Die Werkstattkarte sagt, wie viele davon als Teile ins Werk gingen. Einen Kistenträger zum Werk gibt es nicht: Träger
  laufen nur zu Läden, und nur das sagt der Text (Befund 8).
- **Autokauf (A4, A10, A18).** Keine neue Aktion, eine Regel wie bei den Geräten: Wer nach dem Kauf noch 600 Taler hat, kauft mit einer
  Chance von 4 % am Tag × Bedarf × (1,3 − Sparsamkeit). Bedarf: Arbeitsweg / 12 Felder, mindestens 0,35 (Einkauf, Besuche, Rente), × 0,7,
  wenn im Haushalt schon ein Auto steht. Wer für einen eigenen Betrieb spart (Ziel), kauft vorher keins (`AUTO_ZIEL_BETRIEB`, siehe Gemessen).
  **Von Anfang an** gibt es Autos bei einem Autohaus im Umland (A18: Kleinwagen, Kompaktwagen, Kombi oder Van, gedeckte Farbe, Marke
  `AUSSEN = 255`; Farbe nur gedeckt, verteilt wie die Neuzulassungen 2025: A19). Hat ein Werk der Stadt an diesem Tag noch ein Auto, nimmt man
  das (Annahme A4: gleicher Preis, kürzerer Weg; das Geld bleibt dann in der Stadt; so steht es auch im Fenster), mit Marke, Modell und Version des Werks und einer von 8 Farben (4 gedeckt, 4 der Modellreihe). Preis 636 Taler, aus der Stadt und von außen gleich. **Geldfluss:** Ein Auto aus dem Werk
  bezahlt das Werk (Löhne, Teile); ein Auto von außen ist Geld, das die Stadt verlässt. **Reihenfolge (A20):** Die Käufer kommen jeden Tag in
  einer anders gemischten Reihenfolge dran, `p = (a · i + b) mod pMax` mit `a = mischSchritt(pMax, Tag)` teilerfremd zu `pMax` (jede Nummer genau
  einmal) und `b = mischStart(pMax, Tag)`, ohne Zufallszug. So ist an einem ausverkauften Tag weder immer dieselbe Nummer noch ein Block
  benachbarter Nummern (oft zusammen Zugezogene) zuerst dran (Befund 9 der Gegenprüfung „sim“; Schlussprüfung Technik 6: vorher nur ein
  rotierender Start, benachbarte Nummern blieben zusammen). Personennummern hängen am Einzug.
- **Laufende Kosten, CO₂ (A8, R-A2).** 7,31 Taler am Tag (7,68 mit den CO₂-Abgaben, die in der Stadt nach R-A2 wegfallen). Sie gehen aus der
  Stadt hinaus. Wer in Haft ist, zahlt nichts, das Auto ruht an der Wohnung (A15).
- **Verschrotten (A9).** Jedes Auto hält gleichverteilt 50–150 % von 201 Tagen, dann ist es weg (keine Gebrauchtwagen).
- **Erbe (A13).** Stirbt jemand, erbt der Partner das Auto, wenn er selbst keins hat, mit Marke, Modell, Farbe und Lebensdauer; sonst geht es
  mit dem Nachlass aus der Stadt.
- **Geldnot (A14).** Wer 5 Nächte in Folge nach allen Zahlungen im Minus ist, verkauft das Auto an einen Händler außerhalb für die Hälfte des
  Zeitwerts (linear über die Lebensdauer) und zahlt nichts mehr (Befund 10).
- **Fahren (A11), die Grundregel.** Die einzige Entscheidung ist `mitAuto(S, p, a, b)`: p hat ein Auto, ist nicht in Haft, und der Weg von
  Gebäude a nach b ist mindestens 3 Felder lang (wer sparsam ist, erst ab 4 oder 5). `pendeltMitAuto(S, p)` ist dieselbe Entscheidung für den
  Arbeitsweg heute. Statistik, Personenkarte („Fährt mit dem Nova Pfeil 3 zur Arbeit.“) und die Darstellung rufen sie auf; die Darstellung hat
  keine eigene Grenze (Befund 2). `ortZurStunde(S, p, H)` (vorher `simOrt` in der Darstellung, jetzt in der Simulation) sagt, wo p in Stunde H
  ist; `autoOrt(S, p, H)` ist ohne Zustand: das Ziel, wenn p von der Wohnung dorthin mit dem Auto fährt, sonst die Wohnung. Weil alle Wege über
  die Wohnung führen, fährt ein Auto nur, wenn sein Besitzer in dieser Stunde den Ort wechselt und damit fährt; sonst steht es dort, wo der
  Besitzer ist, oder zu Hause. Wer zu Fuß zur Arbeit geht (kurzer Weg), lässt es zu Hause (Befund 3: so steht es jetzt ausdrücklich in der
  Regel). Den Abendbesuch hält die Simulation ab 19 Uhr fest (`besuch`), damit kein Auto abends ohne Ortswechsel springt; auf den Lauf der Stadt
  wirkt das nicht (`besuch` liest nur `ortZurStunde`; die Gates auf Seeds 1–80 sind mit und ohne das Festhalten Zeile für Zeile gleich).
  **Fährt das Auto im Bild?** (blockierender Befund der Schlussprüfung) `autoFaehrt(S, p, a, vorher, H)`: nur, wenn der Besitzer diesen Weg
  selbst macht, also in der Vorstunde dort war, wo das Auto stand (`vorher`, die Darstellung merkt sich `ortZurStunde` je Person), jetzt am
  Ziel des Autos ist (`autoOrt` = `ortZurStunde`) und `mitAuto` ja sagt. Sonst wechselt das Auto den Ort **ohne Fahrt** (Sprung): beim Umzug in
  der Stunde, in der der Besitzer zur Arbeit geht (Auto an die neue Wohnung, Besitzer von der alten zur Arbeit), und bei einer neuen Stelle
  mitten am Tag (Auto von zu Hause zur neuen Stelle, Besitzer von der alten; oder, liegt die neue nah an der Wohnung, Auto von der alten Stelle
  nach Hause). Vorher entschied die Darstellung nur mit `mitAuto(altOrt, neuOrt)`: Dann fuhr das Auto in diesen Fällen sichtbar allein, und die
  Figur des Besitzers war währenddessen unsichtbar. Gemessen (Seeds 1–12, je 730 Tage stündlich, `--autos`): 5,4 Mio. Fahrten, alle mit
  Abfahrt und Ziel beim Besitzer; 32 Sprünge (30 Umzug, 2 neue Stelle). Für Karten gibt es dieselbe Frage ohne Zustand
  (`autoFaehrtJetzt`, `autoFahrtWohin`: die Vorstunde nach dem heutigen Stand).
- **Teststrecke** (nur zum Anschauen, blockierender Befund der Gegenprüfung der Darstellung). `testfahrer(S, w)`: eine heute anwesende Kraft
  des Werks, jeden Tag eine andere (reihum nach dem Tag); `testfahrtStunde(S, w, H)` nennt sie nur um 10 und 14 Uhr. Sie ist in dieser Stunde
  laut `ortZurStunde` im Werk bei der Arbeit, also nie zugleich an anderer Stelle. Ohne anwesende Kraft fährt niemand. Im Bild fährt der
  Prototyp nur dann (Teil 2, unten), die Figur dieser Kraft ist in der Stunde nicht zu sehen. **Karten** (Befund der Schlussprüfung,
  Bedienung): Wer frei nimmt, entscheidet das bis 7 Uhr; deshalb nennen Werks- und Personenkarte den Testfahrer erst ab 8 Uhr
  (`testStundenRest`: vorher „Wer heute um 10 und 14 Uhr den Prototyp … fährt, steht um 8 Uhr fest.“), danach nur die Teststunden, die heute noch
  kommen. Vorher nannten die Karten zwischen 0 und 7 Uhr an 79 bis 93 % der Werkstage eine andere Person als die, die um 10 Uhr fuhr.
- **Stadtbuch.** Aufträge (Campus, Hochhaus, Hallen, Autowerk, Übernahme eines Werks), Umzug ins Werk, das erste Auto der Stadt (aus dem
  Umland) und das erste aus einem Werk der Stadt, neue Modelle. **Karten:** `personInfo(…).auto` (Name, Marke, von außen, Farbe, Kauftag,
  Alter, Verschrottung, Preis, Weggrenze, pendelt, Ort, ruht, Kosten), `.werk` (Autowerk, in dem p arbeitet); `gebaeudeInfo` für Tech-Firmen:
  `werk`, `umzug`, `eroeffnet`, `eroeffnetArt`, `stufeName`, `testfahrer`, `ruht`, Zeile „Stufe 5 (Hochhaus)“ bzw. „4 Hallen“ (Stufe − 1, so viele
  Hallenteile wie im Bild), im Werk die Rolle „Autobauerin“/„Autobauer“ und „Besitz, baut mit“, „Hauptlieferant ist …“. Personenkarte: „fährt um
  8 Uhr zur Arbeit“ in der Stunde, in der der Besitzer damit fährt (`auto.faehrt`), sonst „steht zu Hause“ usw.; bei Autos aus dem Umland steht
  „aus dem Umland“ nur einmal. Das Fenster „Stadtregierung“ bekommt die Live-Zahlen aus `regierungInfo(…).autos`.

### Annahmen und Quellen

Umrechnung wie überall: U1, 1 Taler ≙ 52,159 €.

| | Annahme | Wert im Spiel | Quelle, Rechnung |
|---|---|---|---|
| A1 | Tech-Stufen 4 und 5, je 4 Stellen mehr, Werk bis Stufe 6 | 16 / 20 / 24 Stellen | Spielannahme, wie der Anbau bis Stufe 3 |
| A2 | Wer ein Werk baut | Handy/Computer, Stufe ≥ 3, Ehrgeiz ≥ 70, ab Stufe Stadt, höchstens 2 | Spielannahme |
| A3 | Werk | 20.000 Taler, 48 Arbeitstage, 120 Taler am Tag | Spielannahme (größter Auftrag der Stadt; Kaserne 9.600) |
| A4 | Preis, gleich aus Werk und Umland | 636 Taler | DAT-Report 2026: neuer Benziner 2025 im Schnitt 33.150 € / 52,159 (Befund 11: Benziner-Preis passend zu den Benziner-Kosten, nicht der Mittelwert aller Antriebe 44.560 €) |
| A5 | Autos je Kraft und Tag | 0,575 | VDA: 4,15 Mio. Pkw 2025 in Deutschland; Destatis: 721.400 Beschäftigte der Automobilindustrie Ende September 2025 (Pressemitteilung vom 20. 11. 2025; passt zeitlich zur Produktion 2025, einen neueren Wert fürs 1. Halbjahr 2026 gibt es); 5,75 Pkw je Beschäftigtem und Jahr, ein Spieltag ≙ ein Zehntel Jahr (`R.JAHR` = 10) |
| A6 | Neues Modell | 480 Arbeitstage | Spielannahme (Handy 60, Computer 50) |
| A7 | Teile | 24 Kisten je Auto für die Stadt | Spielannahme |
| A8 | Laufende Kosten | 7,68 Taler am Tag (mit CO₂) | ADAC Autokosten 2026, VW Golf 1.5 TSI: 334 € im Monat ohne Wertverlust, 15.000 km im Jahr; **ein Modell, kein Mittelwert** (Befund 11) |
| A9 | Lebensdauer | 201 Tage im Mittel, je Auto 50–150 % | KBA: Pkw-Bestand am 1. 1. 2026 im Mittel 10,9 Jahre alt. Rechnung (Befund 12): Bei gleichverteilter Lebensdauer L zwischen 0,5 und 1,5 · M ist das mittlere Alter im Bestand E[L²] / (2 E[L]) = (13/12 · M²) / (2 M) ≈ 0,54 · M; 0,54 × 201 Tage = 109 Tage ≙ 10,9 Jahre. **Gemessen** (Seeds 1–6, Tage 550–700): 91–106 Tage, im Mittel 100 Tage ≙ etwa 10 Jahre, weil Geldnot und Nachlass Autos früher herausnehmen; das Fenster sagt jetzt „rechnerisch … 10,9 Jahre; gemessen etwa 10“ (Schlussprüfung Texte) |
| A10 | Kaufregel | 4 %/Tag × Bedarf × (1,3 − Sparsamkeit), 600 Taler Rest, Sparer für einen Betrieb warten | Spielannahme; Kaufchance und Bedarf eingestellt auf Pkw-Dichte und Anteil der Haushalte mit Auto (unten), die Regel für Betriebssparer auf Gate 4 |
| A11 | Ab wann man fährt | 3 Feldern, Sparsame 4–5 | Spielannahme (R-A1: jeder wählt selbst) |
| A12 | Freizeit beim Kauf | +15 | wie ein Computer |
| A13 | Erbe | Partner ohne eigenes Auto | Spielannahme |
| A14 | Geldnot | 5 Nächte im Minus → Verkauf für 50 % des Zeitwerts nach außen | Spielannahme (Befund 10) |
| A15 | Haft | Auto ruht, keine Kosten | Spielannahme (abgemeldet) |
| A16 | Export | wie jede Tech-Firma je Arbeitstag | Spielannahme |
| A17 | Werk ohne Code | Autobauer schreiben keinen Code | Spielannahme |
| A18 | Autohaus im Umland ab Tag 0 | vier Typen, gedeckte Farben | Noahs Entscheidung; Geld verlässt die Stadt |
| A20 | Reihenfolge der Käufer | jeden Tag gemischt: `(a · i + b) mod pMax`, a teilerfremd | Spielannahme (neutral: kein Merkmal, keine Nummernfolge; Schlussprüfung Technik 6). Die Konstanten der Mischung sind eine von vier gleich neutralen Varianten (Gemessen) |
| A19 | Farben der Autos aus dem Umland | Silber 16,2, Dunkelgrau 16,2, Schwarz 26,8, Weiß 18,6 (Gewichte, `R.AUSSEN_FARBEN`) | KBA, Pressemitteilung 01/2026 (6. 1. 2026), Pkw-Neuzulassungen 2025: Grau 32,4 %, Schwarz 26,8 %, Weiß 18,6 %; nur diese drei gedeckten Farben, Grau je zur Hälfte hell (Silber) und dunkel (Annahme). Ein Zug aus dem eigenen Strom wie vorher (vorher gleich verteilt über vier Töne); der Lauf der Stadt bleibt gleich, nur `autoFarbe` ändert sich |

Vergleichswerte. **Eingestellt** (A10: Kaufchance und Bedarf) wurde auf Destatis (22. 7. 2026) 593 Pkw je 1.000 Einwohner und Destatis LWR
2024: 77,9 % der Haushalte mit Pkw (111,5 Pkw je 100 Haushalte). **Nur gemessen, nicht eingestellt:** Mikrozensus/Pendeln 2024: 65 % der
Pendler mit dem Auto; VDA 2025: 76 % der Pkw gehen in den Export (Schlussprüfung Texte: vorher hieß es, alle Vergleichswerte seien nur
gemessen).

### Darstellung (Teil 2)

**Was man sieht.**
- **Autos:** Low-Poly, 28 Dreiecke (vorher 36: Scheinwerfer und Rücklichter malt jetzt der Shader auf Front und Heck, gleiche Farben und
  gleiches Licht; Befund der Schlussprüfung, Dreiecke der großen Stadt), alle in einem InstancedMesh (`M.auto`, ein Draw Call). Lack nach der Simulation (`autoFarbe`): Autos aus
  dem Umland gedeckt (Silber, Dunkelgrau, Schwarz, Weiß; A19), Autos aus der Stadt zur Hälfte gedeckt, zur Hälfte in einer der vier Farben
  ihrer Modellreihe (fest je Marke und Modell, `lackNr`), je Auto etwas heller oder dunkler. Wer fährt, fährt rechts (Spur 0,12 neben der
  Straßenmitte), biegt mit abgeschrägten Ecken ab, fährt gleichmäßig an und bremst; nachts leuchten Scheinwerfer und Rücklichter, und vor
  dem Auto liegt ein warmweißer Lichtfleck (im Lichtfleck-Mesh der Laternen, kein Draw Call). Ein Tipp auf ein Auto öffnet die Karte seines
  Besitzers.
- **Campus (Stufe 4):** Riegel mit Dachterrasse (4 Geschosse), zwei Flügel mit Solardach (3), Hof mit Baum, Brücke; zwei Leuchtlogos am
  Riegel. **Glas-Hochhaus (Stufe 5):** Scheibe mit 14 Geschossen, Krone mit vier Leuchtlogos (Anfangsbuchstabe der Marke), Mast mit rotem
  Licht, das nachts ruhig leuchtet. Fensterbänder wie beim Glasbau: tagsüber hell nach dem Anteil der Leute, die heute da sind, nachts oben
  der Serverraum. Anbau zu Stufe 4 oder 5: Der Rohbau der neuen Form wächst mit Gerüst.
- **Autowerk** auf seinem Gelände (3 × 3 Felder aus `gelaendeSuchen`/`gelaendeBauen`, erkannt an `g.werk`, nicht am Produkt): Zaun mit Tor,
  Zufahrt, Pförtner, offene Schranke; vorn links die Teststrecke auf Rasen, vorn rechts der Showroom (zwei Geschosse Glas, Leuchtlogo zur
  Straße, nachts unten hell), dahinter der Werksparkplatz mit 12 Plätzen, hinten die Montagehalle aus Hallenteilen mit Sägezahndach, rechts
  hinten der Autoturm (offenes Regal mit Leuchtkrone). **Die Stufe ist zu sehen:** Stufe 3 bis 6 hat 2 bis 5 Hallenteile und 3 bis 6
  Turmebenen; eine neue Halle wächst als Rohbau mit Gerüst. Im Turm stehen die Neuwagen von gestern (eins je Ebene, `g.gebaut`, in den Farben
  der Modellreihe). Im Bau: Werksboden, Zaun, Rohbau der ersten Hallen mit Gerüst. Leer (nach der Schließung): gedämpft, ohne Logos, Neuwagen
  und Prototyp. Liegt das Tor neben der Mitte, ist der Plan gespiegelt, und eine Querspur hinter dem Zaun führt zur Zufahrt. Wer im Werk
  arbeitet, trägt Blaumann (wie in der Werkstatt, ohne Bildschirm) und steht zur Arbeitszeit in zwei Reihen vor der Halle.
- **Lichtkegel:** Am Abend einer Eröffnung (`g.eroeffnet` der Simulation: Gründung, Übernahme, Umzug ins Autowerk, Campus, Hochhaus; für
  **jede** Tech-Firma, auch auf Stufe 1 bis 3) steht über dem Gebäude ein ruhiger Lichtkegel in der Farbe des Logos, von 18:30 bis 1 Uhr,
  weich ein- und ausgeblendet nach Spielzeit. Er bewegt sich nicht, die Fläche dreht sich nur zur Kamera. Weil der Tag im Spielstand steht,
  ist er nach dem Neuladen am selben Abend wieder da. Leuchtlogos und Kegel liegen in einem Mesh (`M.leucht`, ein Draw Call, additiv, Bild
  aus einem Canvas); tagsüber sind die Logos gedämpft.
- **Karten und Hilfe:** Personenkarte mit dem Auto („Lumen Weite 2 in Schwarz (aus der Stadt, gekauft an Tag 700) · steht zu Hause · fährt
  ab 3 Feldern Weg“; in der Stunde, in der der Besitzer damit fährt, „fährt um 8 Uhr zur Arbeit“), bei der Kraft, die heute den Prototyp fährt,
  ab 8 Uhr „Testfahrt mit dem Prototyp heute um 10 und 14 Uhr auf der Teststrecke“ (Schlussprüfung: vorher auch vor 8 Uhr, oft mit der falschen Kraft).
  Hauskarten von Werk, Campus und Hochhaus mit den Texten der Simulation (Klick auf Halle, Turm, Showroom, Logo, Neuwagen). Auswahlrahmen des
  Werks ums ganze Gelände. Stadtbuch-Einträge der Autos mit eigenem Symbol. Hilfe: Autos und Lichtkegel in der Legende, Werkstatt und Autowerk
  im Blaumann (gleich hoch wie vorher: zwei Einträge zusammengefasst, bei 1280 × 800 ohne Scrollen).

**Grundregel im Bild.** Jede Stunde fragt die Darstellung für jedes Auto `Sim.autoOrt(S, p, H)`. Steht das Auto dort schon, bleibt es, wo es
steht (auch wenn der Platz inzwischen nicht mehr erlaubt wäre: kein Umstellen ohne Fahrt). Sonst entscheidet `Sim.autoFaehrt(S, p, alt,
vorher, H)` mit dem Ort, an dem die Simulation den Besitzer in der Vorstunde hatte (je Person gemerkt, `pVor`): Macht der Besitzer genau
diesen Weg mit dem Auto, fährt es; sonst springt es ohne Fahrt (Umzug, neue Stelle mitten am Tag; der Besitzer bleibt dabei zu sehen und geht
seinen Weg, eine Hauptfigur behält ihre Raute über sich). Eine eigene Grenze hat die Darstellung nicht (blockierender Befund der
Schlussprüfung: vorher `Sim.mitAuto(alt, neu)` allein, dann fuhr das Auto in diesen Fällen allein). Solange das Auto fährt, ist die Figur des
Fahrers nicht zu sehen; die Raute einer Hauptfigur schwebt über dem Auto. Neue Autos (Kauf, Erbe) und alle nach Laden, Aufholen und Import
werden nur aufgestellt, dort, wo die Simulation sie hat; wächst die Karte, bleiben sie stehen (Plätze umgerechnet).

**Wer zuerst parkt.** Die Plätze vergibt die Darstellung in einer jede Stunde gemischten Reihenfolge der Personen (`Sim.mischSchritt`, wie
bei den Käufern), nicht nach Personennummer (Befund der Schlussprüfung, Texte: vorher standen früh Eingezogene eher sichtbar am Bordstein).

**Parken, eine ehrliche Regel (Abweichung).** Ein Auto parkt am Bordstein des Straßenfelds vor dem Gebäude, bei dem es laut Simulation steht,
oder höchstens ein Straßenfeld weiter (`PARK_WEIT = 1`, also höchstens 2 Felder vom Gebäude; gemessen nie weiter), rechts in Fahrtrichtung,
oder auf dem Werksparkplatz. Je gerades Straßenfeld gibt es 2 × 2 Plätze; keine vor Läden (Theke und Auslage), vor dem Tor eines Geländes, am
Zebrastreifen und vor dem Haus einer Hauptfigur, die dort steht (nur für neu parkende Autos). Ist nichts frei, steht das Auto in der Garage des
Hauses (nicht zu sehen: es fährt an der Grundstückskante hinein und heraus). **Deshalb ist nur ein Teil der Autos sichtbar geparkt:**
Teststadt (Tag 730) nachts 17 %, tagsüber 29 % und dazu der Werksparkplatz, große Stadt nachts 15 %, tagsüber 33 %; vor einem Wohnturm mit
30 Bewohnern liegen 4 bis 12 Plätze. Der Prototyp suchte bis zu 5 Straßenfelder weit (Befund: 229 von 581 Autos standen 4 bis 6 Felder weg);
mehr Stellfläche hätte Bauplätze oder Gärten gekostet. Noahs Wunsch „nachts stehen sie geparkt“ ist damit nur für eine Minderheit zu sehen.

**Sichtbar gefahren oder gesprungen.** Geplant wird jede Stunde: Hauptfiguren zuerst (ihre Fahrt sofort, sie fährt auch ohne Lücke im
Verkehr), dann nach Nähe zur Kamera, höchstens `FAHR_MAX = 1.500` Fahrten mit Weg, verteilt über die Bilder der Stunde (bis dahin wartet das
Auto am alten Platz). Das Budget je Bild richtet sich nach der Spielzeit (Befund der Schlussprüfung, Bedienung): 3 ms, aber mehr (höchstens
10 ms), wenn die Bilder bis 0,85 der Stunde sonst nicht reichen (geschätzt aus dem Spielzeit-Schritt je Bild); bleiben weniger als zwei
Bilder, springen die übrigen Fahrten gleich (gezählt `spaet`), statt die ganze Stunde zu stehen und am Stundenwechsel versetzt zu werden.
Ein Auto fährt erst los, wenn es keinem schon geplanten näher kommt als eine Wagenlänge und etwas Luft (0,46 Felder Fahrzeit, Kacheln 0,25 ×
0,25 mit Zeitschlitzen). Findet es so keine Lücke, fährt es mit dem engen Abstand von 0,34 Feldern (gut eine Wagenlänge, eigenes Bitfeld;
gezählt `eng`; Befund der Schlussprüfung, Bedienung: große Stadt um 8 und 17 Uhr je gut 50 Fahrten mehr sichtbar, gleich viele Überlappungen
wie vorher). Findet eine Fahrt auch so keine Lücke, liegt sie über `FAHR_MAX` oder hat sie keinen Weg, **springt** sie: Das Auto steht am
alten Platz bis zur Abfahrt, ist unterwegs nicht zu sehen (wie sein Fahrer) und steht nach der Ankunftszeit am neuen Platz; es ist dieselbe
Fahrt des Besitzers, keine ohne Ortswechsel. Ausprobiert und verworfen: Fahrten nahe der Kamera (6 Felder) ohne Lücke trotzdem fahren zu
lassen; dann fuhren Autos durcheinander (große Stadt: 34 und 90 statt 3 und 9 Paare näher als 0,16 um 8 und 17 Uhr). Deshalb springen auch
nahe der Kamera noch Fahrten (unten, Gemessen und Bekannte Schwächen). Gemessen: Teststadt um 8 Uhr 257 von 262 Fahrten sichtbar, große Stadt
1.126 von 1.672 (374 wegen voller Straße, 172 über `FAHR_MAX`); um 22 Uhr 150 von 150 und 628 von 655. Ist bei sehr hohem Tempo die Planung
einer Stunde nicht fertig, wenn die nächste beginnt, stehen die übrigen Autos danach am Ziel (gezählt als `rest`, gemessen 0).

**Teststrecke (blockierender Befund).** Der Prototyp mit Tarnfolie fährt nur in einer Stunde, für die `Sim.testfahrtStunde` jemanden nennt
(10 und 14 Uhr: eine Kraft, die laut Simulation in dieser Stunde genau in diesem Werk arbeitet). Deren Figur ist in dieser Stunde nirgends zu
sehen; ist sie eine Hauptfigur, schwebt ihre Raute über dem Prototyp; ein Tipp auf ihn öffnet ihre Karte. Er fährt über 90 % der Spielstunde,
Weg `Runden · (τ − sin 2πτ / 2π)`: an der Startlinie weich an und am Ende weich wieder dort, ohne Sprung, auch wenn sich das Tempo in der Stunde
ändert; die Zahl der Runden legt die Stunde nach dem Tempo fest (eine Runde gut 8 echte Sekunden, höchstens 8, bei reduzierter Bewegung 1).
Sonst steht er an der Startlinie.

**Reduzierte Bewegung.** Lichtkegel und Leuchtlogos stehen (der Kegel wird nur nach Spielzeit heller und dunkler, das rote Licht blinkt nie);
Autos und Prototyp fahren weiter, weil die Simulation ihre Besitzer bewegt (Inhalt wie die Figuren).

**Umland.** Kommt ein Gelände dazu (Autowerk am Stadtrand, ebenso Anstalt und Kaserne), werden Landstraßen und Felder neu gelegt. Vorher lief
eine Landstraße, die vor dem Gelände angelegt war, bis zur nächsten neuen Straße quer darüber (gesehen beim Bau des ersten Werks der
Teststadt an Tag 229).

**Annahmen der Darstellung.**

| | Annahme | Wert | Warum |
|---|---|---|---|
| D1 | Autogröße | 0,32 × 0,14 × 0,14 (Figur 0,24 hoch) | maßstäblich wären es 0,62 × 0,25; dann passten auf die Fahrbahn (0,6) keine zwei Spuren und kein Parken. Verkleinert wie Häuser und Figuren |
| D2 | Querschnitt einer Straßenseite | Spur 0,05–0,19, geparkt 0,20–0,34 (leicht gekippt, rechte Räder auf dem Bordstein), stehende Figuren 0,6 und 0,5 von der Hausmitte, Fußgänger 0,45 neben der Straßenmitte | nur so überlappt nichts, ohne Gehweg und Fahrbahn zu ändern |
| D3 | Reisetempo | 120 Felder je Spielstunde (Fußgänger 22) | Verhältnis 5,5, real 30 zu 5 km/h = 6; auch der längste Weg der großen Stadt endet in der Stunde |
| D4 | Sichtbar gefahren | höchstens 1.500 Fahrten je Stunde, die der Kamera nächsten zuerst; Planung 3 ms je Bild | wie Annahme 62 bei den Figuren (Nähe zur Kamera) |
| D5 | Abstand | 0,46 Felder Fahrzeit, Kacheln 0,25 | kein Durcheinander auf Kreuzungen |
| D6 | Parken | 2 × 2 Plätze je gerades Straßenfeld, höchstens ein Straßenfeld weiter, sonst Garage | oben, „Parken“ |
| D7 | Werksparkplatz | 12 Plätze | passt auf den Block; ein Werk hat bis 24 Stellen |
| D8 | Lack der Stadt | Farbe 0–3 gedeckt, 4–7 vier Farben der Modellreihe aus 8 (Blau, Petrol, Rot, Grün, Sand, Orange, Bordeaux, Taubenblau), je Auto ±8 % Helligkeit | Modelle erkennt man an der Farbe (Umland: A19) |
| D9 | Lichtkegel | 18:30 bis 1 Uhr am Abend der Eröffnung, höchstens 16 zugleich | ruhiges Ereignis, steht im Spielstand |
| D10 | Leuchtlogo | Anfangsbuchstabe der Marke in Kreis, Quadrat oder Sechseck (Markennummer mod 3); Tech in der Farbe des Produkts, Autowerk aus 5 Tönen; tagsüber 55 %, nachts voll | nur aus dem Firmennamen, nichts erfunden; Schrift system-ui (je Gerät etwas anders) |
| D11 | Hochhaus, Campus | 14 Geschosse (5,9) plus Krone und Mast; Campus 4 und 3 Geschosse; je auf einem Feld | doppelt so hoch wie ein Wohnturm: das Wahrzeichen |
| D12 | Werk je Stufe | 2 bis 5 Hallen (Stufe − 1; die Hauskarte zählt genauso), 3 bis 6 Turmebenen | die Stufe soll man sehen |
| D13 | Prototyp | Teststunden der Simulation (10, 14 Uhr), 90 % der Stunde, eine Runde gut 8 echte Sekunden | „gelegentlich“, weich, ohne Sprung |
| D14 | Fußgänger | auf dem rechten Gehweg, queren am Anfang oder Ende die Straße | die Fahrbahn gehört den Autos; beim Queren kann eine Figur ein Auto berühren (keine Kollisionsprüfung) |


### Stadtregierung (Fenster, Gruppe „Verkehr, Tech-Firmen und Autos“)

- **Spielregel „Tech-Firmen wachsen, Autowerke, Autos“** mit Live-Zeile (Autos, von außen, je 1.000 Einwohner, Haushalte, Werke).
- **R-A1 Freie Wahl des Verkehrsmittels** (Auslegung; S. 42 zweimal): Die Stadt schreibt nichts vor und bevorzugt nichts; jeder entscheidet
  selbst, ob er ein Auto kauft, und fährt, wenn es sich für ihn lohnt (A11). Die Leute wählen wirklich (Kauf und Weggrenze hängen an
  Sparsamkeit und Weg); S. 42 begründet also keine feste Regel (Korrektur der Prüfung). Annahme: außer Auto und Fußweg gibt es kein
  Verkehrsmittel.
- **R-A2 Keine CO₂-Abgaben aufs Auto** (wirkt; S. 13, S. 57 zweimal): CO₂-Preis im Kraftstoff (ADAC 2026 rund 17 ct/l, 5,4 l/100 km,
  810 l im Jahr, 138 €) **und** CO₂-Teil der Kfz-Steuer (§ 9 Abs. 1 Nr. 2 Buchst. c KraftStG, 122 g/km: 55,40 € von 85 €) fallen beide weg,
  weil S. 57 unter „Abschaffung aller CO₂-Abgaben“ die Steuer nach „Emissionspotential“ nennt (Befund 5: einheitlich; das Argument
  „Bundessteuer“ ist gestrichen). 193 € im Jahr = 0,37 Taler am Tag. S. 13 steht nicht mehr zusätzlich unter „gilt schon“ (Befund 4).
- **R-A3 Keine Bevorzugung der E-Mobilität, keine Ladesäulen aus Steuergeld** (galt schon; S. 43): „Alle Autos sind gleich und kosten wie ein
  Benziner (R-A2). E-Autos und Ladesäulen gibt es nicht“ (vorher „Die Stadt kennt keine Antriebe“, das widersprach R-A2; Schlussprüfung
  Texte).
- **R-A4 Kein Verbrennerverbot** (galt schon; S. 14, S. 41), mit dem Hinweis, dass Verbot und Flottengrenzwerte EU-Recht sind (Verordnung (EU)
  2019/631, geändert 2023), mit Stand: Im Dezember 2025 hat die EU-Kommission vorgeschlagen, das Ziel für 2035 von 100 auf 90 % weniger CO₂ zu
  senken (geprüft: Kommission, „Automotive Package“ vom 16. 12. 2025; ob es beschlossen ist, habe ich nicht geprüft).
- **R-A5 Keine Subventionen für Techniken** (galt schon; S. 164 zweimal, „S. 164 f.“ über den Seitenwechsel): Tech-Firmen bezahlen Ausbau
  und Werk selbst; mit dem Zusammenhang (Befund 13): Die Stadt wendet die Ausnahme „strategische Unabhängigkeit“ nicht an (jetzt als
  Auslegung gekennzeichnet, Schlussprüfung Texte), das Programm zählt die
  Autoindustrie dort nicht dazu; ihre „strategische Bedeutung“ (S. 43) macht es zur Aufgabe der Bundesregierung. Ein Werk steht an einer
  vorhandenen Straße, eine eigene baut die Stadt nicht.
- Nachgezogen: „Kein Gegenstück“ nennt jetzt „Energie, Bahn, Bus und Flugverkehr“ statt „Verkehr“; die Einträge S. 14 (Verbrenner) und
  S. 42 (Fahrspuren/Parkraum) mit „Keine Fahrzeuge“ sind weg; S. 13 (CO₂) und S. 164 (Subvention) stehen nicht mehr unter „gilt schon“, dafür
  S. 43 (synthetische Kraftstoffe: „Alle Autos sind gleich und kosten wie ein Benziner …“). Neue Gruppe „nicht“: „Verkehr und Autos“ (10 Punkte von
  S. 11, 42, 43, 44; die Energiesteuer, S. 13, steht seit der Schlussprüfung unter „Keine Zahl, keine Mechanik oder kein Fall“: „Keine Zahl für
  die Energiesteuer … nimmt keine Senkung an (Auslegung)“, und der Absatz „Zur Vollständigkeit“ nennt ihre Senkung unter „es fehlen“); u. a. Parkraum: „hat in der
  Simulation keine Wirkung“, Befund 14). `--regierung` prüft jetzt, dass jedes Programmzitat im Fenster nur an einer Stelle steht (Befund 4;
  erlaubt sind nur die zwei Sätze, die seit Version 7 in „Grenze der Stadt“ die Bund-Karten wiederholen).
- Zitate: 254 im Fenster, `zitatpruef.py` und `zitate_genau.py` finden 249 wörtlich auf der genannten Seite. Die übrigen: „S. 164 f.“ über den
  Seitenwechsel (Seitenfuß dazwischen; selbst gelesen: S. 164 „Technologien, die den Bedürfnissen der Bevölkerung entsprechen,“, S. 165
  „setzen sich von selbst durch, wie das Internet, Smartphones und der motorisierte Individualverkehr beweisen.“), zwei Zitate im Fließtext
  ohne Seitenangabe (S. 42 „unterstützt und fördert“, S. 43 „auf nationaler und europäischer Ebene für eine technologieoffene Gesetzgebung zu
  sorgen“, beide dort gefunden) und aus Version 7 Noahs „Wie in Amerika“ und „Demographics Unit“.

### Gemessen

Alle Zahlen hier sind auf dem Endstand nach der Schlussprüfung gemessen (gemischte Reihenfolge der Käufer, Grundregel mit `autoFaehrt`,
Autos mit 28 Dreiecken). Die Stadt verläuft dadurch anders als in Teil 1 und 2; deren Zahlen stehen nur noch zum Vergleich in der ersten Tabelle.

**Seeds 1–80** (`v8/mess/mess_v8.mjs` = `mess10.mjs` plus Autos, `lauf80.sh`, `auswert.py`, 730 Tage stündlich, gegen dieselbe Messung
auf ffa1d88; Logs `v8/mess/v9b_*.txt`):

| Stand | alle Gates | fällt | Band Ø / schlimmster | Einwohner Tag 365 / 730 | Gründungen bis 365 | Gate 6 / 7 Ø | Mieterkäufe | Geld je Erwachsenem Tag 730 |
|---|---|---|---|---|---|---|---|---|
| ffa1d88 | 78 von 80 | G4: 44, 77 | 1,081 / 1,177 | 917 / 1.186 | 235 | 19,4 / 25,6 | 776 | 12.609 |
| Version 8 bis zur Schlussprüfung (rotierender Start) | 79 von 80 | G4: 30 | 1,075 / 1,159 | 914 / 1.176 | 226 | 19,4 / 26,0 | 746 | 11.152 |
| **Version 8, Endstand** (gemischte Reihenfolge, Variante b) | **78 von 80** | G4: 47, 54 | 1,077 / 1,165 | 917 / 1.187 | 229 | 19,3 / 25,8 | 751 | 11.068 |

**Die Zahl der bestandenen Seeds hängt am Zufall der Reihenfolge.** Die Mischung der Käufer (A20) hat zwei freie Konstanten. Vier gleich
neutrale Varianten ergaben 76, 78, 78 und 76 von 80 (Band Ø 1,076 bis 1,080; Logs `v9a` bis `v9d`); ausgeliefert ist Variante b
(`t · 40503 + 12345`, `t · 7919 + 4711`). **Ich habe b nach diesem Ergebnis gewählt**; die Wahl ändert an der Neutralität nichts, und der
Unterschied zu ffa1d88 (78) liegt in dieser Streuung. Gate 4 fällt nur knapp (Band 1,15 bis 1,17). Der erste Einbau ohne `AUTO_ZIEL_BETRIEB`
bestand 74 von 80 (A10). Die Mieterkäufe sinken um 3,2 % (Befund 6). Tage Erwachsener im Minus je Stadt 6.521, davon 133 mit Auto (A14).

Autos an Tag 730 (Mittel über 80 Städte): 604 Autos, **509 je 1.000 Einwohner** (468–544; Destatis 593), **76,5 % der Haushalte** (Destatis
77,9 %), 104,4 je 100 Haushalte (111,5), **42,9 % der Arbeitstage mit dem Auto** (Pendeln 2024: 65 %), davon 156 von außen. Ein Werk bestellt
oder übernommen in 74 von 80 Städten (Median Tag 493), an Tag 730 in 74 Städten eins oder zwei (Ø 1,56), leere Werke Ø 0,13. Tech-Firmen je
Stufe an Tag 730 (Ø): Stufe 1 6,9, 2 1,2, 3 1,1, **Campus 0,75, Hochhaus 2,2**. Gebaut bis Tag 730 zusammen 222.679 Autos, **Export 70,4 %**
(Summe über alle Städte; Mittel je Stadt über die 74 Städte mit Werk 66,8 %; VDA 76 %). Käufe: 65.857 aus Werken der Stadt, 65.703 von außen
(49,9 %). Je Stadt verschrottet 762, geerbt 42, in Geldnot verkauft 28. Laufende Kosten Ø 2.299 Taler am Tag, CO₂-Abgaben, die entfallen,
116 Taler am Tag. Größter Tech-Anteil an den Umland-Stellen 40,0 %, ruhende Stellen an Ø 0,1 Nächten (erzwungen geprüft: `--autos`, 3b).
Alter der Autos im Bestand (Seeds 1–6, Tage 550–700): 91 bis 106 Tage, im Mittel 100 Tage ≙ 10 Jahre (A9).

**Seeds 1–3** (`--autos`, Tag 730):

| Seed | Autos | je 1.000 | Haushalte | je 100 HH | Arbeitstage mit Auto | erstes Auto / erstes Werk | Werke bestellt / übernommen / Umzüge | gebaut, davon Export | von außen gekauft | Stufen 1–5 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 629 | 529 | 80,2 % | 109 | 43,1 % | Tag 19 / 452 | 1 / 0 / 1 | 1.817, 48 % | 727 | 9/1/0/0/2 |
| 2 (Teststadt) | 618 | 506 | 78,4 % | 107 | 43,5 % | Tag 43 / 271 | 2 / 1 / 2 | 3.281, 57 % | 319 | 12/2/0/2/2 |
| 3 | 585 | 493 | 76,9 % | 103 | 43,9 % | Tag 44 / 591 | 1 / 1 / 2 | 813, 48 % | 1.253 | 6/3/1/1/3 |

**Grundregel über 12 Seeds** (`--autos`, 2b, je 730 Tage stündlich, wie im Bild mit dem Ort des Autos und des Besitzers aus der Vorstunde):
5.401.819 Fahrten, alle mit Abfahrt und Ziel beim Besitzer, 164 davon in Umzugsstunden; 32 Sprünge ohne Fahrt (30 Umzug, 2 neue Stelle
mitten am Tag); 10.582 Testfahrten, nie zugleich mit dem eigenen Auto. Vor der Schlussprüfung wären auf denselben Seeds im alten Verlauf 6
Fahrten ohne Besitzer am Ziel und 1 Abfahrt ohne Besitzer gewesen (Prüfer Technik); im neuen Verlauf findet `mess2/fall_suche.mjs` auf Seeds
1–14 fünf solche Stunden (Seed 2 Tag 305, Seed 4 Tag 623, Seed 8 Tag 690, Seed 13 Tag 412, Seed 14 Tag 137), die jetzt alle Sprünge sind.

**Browser, 8 Uhr** (`v8/mess2/leistung2.cjs` und `leistung3.cjs`: laden, bis 8 Uhr, Tempo 1, 4 s warten, dann 5 s bzw. in der großen
Stadt 20 s lang jedes Bild; Heap per CDP nach einer Speicherbereinigung; SwiftShader ohne Grafikkarte; Logs `mess2/leistung2_end.log`,
`leistung3_end.log`). Die Spalte „JS-Zeit“ ist `__stadtDebug.frameMs` (Zeit des Skripts je Bild), „Bildabstand“ der Abstand zweier
`requestAnimationFrame` (das, was man sieht; Befund der Schlussprüfung, Bedienung: vorher hieß die JS-Zeit „Bildzeit“). **Die Zeiten sind
unsicher:** Während der Endmessung liefen auf demselben Rechner andere Tests (Last 7 bis 9 auf 4 Kernen); Draw Calls, Dreiecke und Heap hängen
daran nicht.

| Stadt | Stand | Einwohner | Draw Calls | Dreiecke | JS-Zeit (Median) | Bildabstand (Median) | Heap |
|---|---|---|---|---|---|---|---|
| Teststadt Tag 400 | ffa1d88 | 943 | 26 | 53.165–53.505 | 9,8 ms | 214 ms | 8,6 MB |
| | Version 8 | 1.031 | 28 | 61.952–62.122 | 10,5 ms | 317 ms | 9,6 MB |
| Teststadt Tag 730 | ffa1d88 | 1.169 | 24 | 55.664–55.904 | 6,0 ms | 535 ms | 8,8 MB |
| | Version 8 | 1.224 | 26 | 69.609–69.729 | 9,7 ms | 411 ms | 10,0 MB |
| große Stadt Tag 750 (`&umland=300000`, 20 s) | ffa1d88 | 5.850 | 25 | 146.557–147.037 | 13,4 ms | 889 ms | 9,3 MB |
| | Version 8 | 6.412 | 27 | 228.079–228.249 | 17,6 ms | 930 ms | 10,5 MB |

Eine erste Messung derselben großen Stadt (20 s, vor dem Entfernen der erzwungenen Fahrten, Rechner ruhiger) ergab 471 → 555 ms Bildabstand
(+18 %) und 9,8 → 11,9 ms JS-Zeit; die Endmessung 889 → 930 ms (+5 %). Mehr als „etwas langsamer“ lässt sich daraus nicht sagen.

**Draw Calls: +2** in allen Szenen, genau `M.auto` und `M.leucht` (Objektliste je Bild, `t2/mess/calls.cjs`: Teststadt Tag 400 26 → 28 um
8 Uhr, 27 → 29 um 21 Uhr; große Stadt 25 → 27 und 26 → 28). Vom Budget +3 ist also einer frei; in Teil 2 kam in der Teststadt Tag 730 durch den
anderen Verlauf ein dritter Mesh dazu (`dach`), das ist im neuen Verlauf nicht mehr so. **Dreiecke der großen Stadt:** +81.500 (+56 %), davon
rund 60.000 Autos zu 28 Dreiecken (2.158 Instanzen um 8 Uhr: 234 stehende, 1.910 Fahrten, Neuwagen und Prototypen), der Rest kommt vom anderen
Verlauf (562 Einwohner mehr). Mit 36 Dreiecken je Auto wären es 17.000 mehr. Der Bildabstand steigt in SwiftShader um 5 bis 18 % (oben);
auf einer Grafikkarte nicht gemessen.

Stundenschritt und die ersten Bilder einer Stunde (`v8/mess2/t2m/leistung.cjs`, Kopie von `t2/mess/leistung.cjs` mit den neuen Funktionen:
zwei Tage aufgewärmt mit je 150 Bildern je Stunde, dann die Stunde und 240 Bilder bei 1×):

| | ffa1d88, 8 Uhr / 17 Uhr | Version 8, 8 Uhr / 17 Uhr |
|---|---|---|
| Teststadt: Figuren und Autos planen (stündlich) | 1,4 / 0,3 ms | 5,0 / 3,9 ms |
| Teststadt: je Bild Median, Max | 0 und 0,3 / 0,1 und 7,2 ms | 0,1 und 3,2 / 0,1 und 3,1 ms |
| große Stadt: Figuren und Autos planen | 2,3 / 0,3 ms | 17,1 / 12,7 ms |
| große Stadt: je Bild Median, Max | 0,1 und 0,3 / 0,1 und 0,5 ms | 0,1 und 10,2 / 0,2 und 10,4 ms |

Das Planungsbudget richtet sich jetzt nach der Spielzeit: In der großen Stadt kosten die ersten vier Bilder einer Stunde je 10 ms, wenn die
Bilder selten sind (hier: aufgewärmt mit 150 Bildern je Spielstunde), danach 3 ms; bei 60 Bildern in der Sekunde bleibt es bei 3 ms.
**Keine Allokation je Bild:** Heap-Stichprobe (CDP, alle 128 Byte) über diese 240 Bilder: 0,0 bis 0,1 KB (eine Zahl in `fahrtenWeiter`); die
neuen Funktionen `probenBauen`, `lueckeSuchen` und `belegen` legen nichts an (feste Puffer; das zweite Bitfeld `kachelKern` wächst wie das
erste nur mit der Karte).

**Verkehr** (`v8/mess2/t2m/kennzahlen.cjs`, nach der ganzen Planung): Teststadt Tag 730, 616 Autos: nachts 105 am Straßenrand (17,0 %), tagsüber
189 (30,7 %) und 8 auf dem Werksparkplatz; um 8 / 17 / 22 Uhr 304 / 304 / 170 Fahrten, sichtbar gefahren 274 / 287 / 170, gesprungen (Straße
voll) 30 / 17 / 0. Große Stadt Tag 750, 3.248 Autos: nachts 507 (15,6 %), tagsüber 1.012 (31,2 %) und 24; um 8 / 17 / 22 Uhr 1.926 / 1.926 / 759
Fahrten, sichtbar 1.013 / 873 / 676, gesprungen wegen voller Straße 487 / 627 / 83, über `FAHR_MAX` 426 / 426 / 0.

**20× bei wenigen Bildern** (`v8/mess2/br/t_rest20.cjs`, Kopie des Prüfskripts): große Stadt bei 1,6 Bildern in der Sekunde um 8 Uhr 1.910
Fahrten, 597 sichtbar, 1.313 gesprungen, **nicht rechtzeitig geplant (`rest`) 0** (vorher 689 von 1.706: diese Autos standen die ganze Stunde zu
Hause und dann ohne Fahrt bei der Arbeit); Teststadt bei 2,9 Bildern: 267 Fahrten, 262 sichtbar, `rest` 0.

**Überlappen** (`v8/mess2/br/ueberlapp.cjs`: alles geplant, alle 0,002 Spielstunden die fahrenden Autos in der Mitte ihrer Strecke, Paare
näher als 0,16; Kamera über der Mitte, Abstand 14): große Stadt um 8 / 17 Uhr 3 / 9 Paare in 108.000 / 120.000 Proben (Version 8 vor der
Schlussprüfung im alten Verlauf ebenso 3 / 9), Teststadt 1 / 0. Fahrten, die Start oder Ziel höchstens 6 Felder vom Blickpunkt haben: in der
großen Stadt springen 27 von 253 (8 Uhr) und 92 von 253 (17 Uhr), in der Teststadt 6 und 8 von 136 (Bekannte Schwächen).
**Live-Beobachter** (`v8/mess2/br/t_gross.cjs` mit `sampler.cjs`, Kopien der Prüfskripte, große Stadt, 16–19 Uhr bei 5×; Log
`mess2/br/mess/gross_end.log`): 2.668 Fahrten, Grundregel ohne Fehler, Fahrer nie sichtbar, kein Sprung eines sichtbaren Autos, nichts durch
Häuser oder über Rasen, links 0 / rechts 8.397, 0 Überlappungen in 10.226 Proben, geparkt beim Besitzer 2.252 Proben ohne Fehler, Konsole leer
(mit den wieder entfernten erzwungenen Fahrten nahe der Kamera war es 1 Überlappung in 10.652 Proben).

Bilder (`tests/blick.cjs`): `scratchpad/v8/nachher/` (Teststadt Tag 400, 1.031 Einwohner) und `scratchpad/v8/gross/` (große Stadt Tag 750,
6.413 Einwohner), selbst angesehen: Hochhäuser mit Leuchtlogos, Autos am Straßenrand und abends mit Scheinwerfern in der Straßenansicht,
Stadtteilnamen, Handyansicht; die Nah- und Straßenansichten der großen Stadt zeigen wie vorher die (leere) Kartenmitte, weil die Stadt dort
ringförmig gewachsen ist. In der Konsole nur die absichtlich abgebrochenen KI-Anfragen.


### Speicherformat 8

`VERSION = 8`. Neue Personenfelder (`PF_AUTO`): `auto`, `autoTag`, `autoMarke` (255 = von außen), `autoModell`, `autoVersion`, `autoFarbe`,
`autoBis`, `autoMinus`. Neue Gebäudefelder (`GF_AUTO`): `werk`, `werkVon`, `umzug`, `modell`, `gebaut`, `fertigRest`, `autosGesamt`,
`kistenWerk`, `ruht`, `eroeffnet`, `eroeffnetArt`. Dazu `S.rsAuto` und `S.stat.auto`, `S.stat.regierung.co2`. Ein Stand der Version 8 muss
alle diese Felder haben (sonst „Spielstand beschädigt“); `autoPruefen` prüft Grenzen und Zusammenhänge (Marke, Modell, Werk ↔ Gelände,
Umzug ↔ Werk, höchstens `AUTO_MAX` Werke, Stufen, ruhende Stellen, Eröffnung; seit der Schlussprüfung auch `g.werk` nur 0 oder 1, weil die
Darstellung ein Werk an `=== 1` erkennt). **Übernahme:** Version 7 im Versionsdialog (eigener Text:
„Dein Spielstand ist von Version 7 …“, „Autos gibt es ab dem Übernahmetag; noch hat niemand eins“), Version 2–6 über die Kette
(`migriereSicherheit`, `migriereBund`, `migriereV6`, dann `migriereV7`). Ab dem Übernahmetag: niemand hat ein Auto, kein Werk, Summen 0,
eigener Zufallsstrom aus dem Seed; bestehende Tech-Firmen haben keine Eröffnung (`eroeffnet = 0`: nie, sie wurden vorher gegründet); eine
Zeile im Stadtbuch („Ab heute wachsen Tech-Firmen weiter … Auf Autos fallen in der Stadt keine CO₂-Abgaben an. …“).
`--speichertest`: bitgleich, **Fingerabdruck `0cdd15796669ff3a`** (Seed 1, Tag 150, 13 Uhr, 60 Tage weiter; Version 7 `6277f264ccaf83c3`),
Stand mit Haft und Obhut `e4b73877b3e467f7` (sortiert `5d385fd960857369`), Stand mit dem Bund `a3e921eeaffeb5bc` (sortiert
`8e22519fde0bead2`). Neu nach der Schlussprüfung, weil die Käufer jetzt in gemischter Reihenfolge kaufen (A20) und die Stadt dadurch anders
verläuft; das Format ist gleich. Frühere Stände: Teil 2 `c46162fb1914a2b5`, `87e58db1c4f91dcc`/`79030e12d3adf918`,
`8b951d0a34eb730c`/`d451fe9746e09114`; Teil 1 `7b3ad863b7b0f553`, `ab5b0b75c1f1d9c6`/`ee2fba8821b1fb5f`, `6766dae013abe517`/`3b230e197a0069d5`.
`tests/basis_v8.json` ist `tests/basis_v7.json` über „Stadt übernehmen“ (`tests/basis_v8.cjs`, nach der Schlussprüfung neu erzeugt, weil sich
die Zeile im Stadtbuch geändert hat), `tests/hilfe.cjs` zeigt darauf.

### Tests

- `node tools/simtest.mjs --autos` (neu): statisch (Zufall nur aus `zufallAuto`, gelesene Personenfelder je Regel für 33 Funktionen, keine
  Namen, Geschlecht nur fürs Pronomen im Stadtbuch, Namenstausch bitgleich); Seeds 1–3 je 730 Nächte und 17.496 Stunden mit Invarianten
  nach jeder Nacht und Stunde: Werke auf eigenem Gelände, höchstens `AUTO_MAX`, Stufen und Stellen, 40-%-Grenze nach jeder Nacht, Umzug,
  Fertigung (je anwesender Kraft genau 0,575 Autos, auf Tausendstel; verkauft ≤ gebaut; Teile = verkaufte Autos × 24 Kisten), jeder Kauf (Reserve, Preis, Werk vor Umland, Marke nur mit freiem Auto, Lebensdauer), Teile, laufende
  Kosten und CO₂ genau je zahlendem Auto, Verschrotten pünktlich, kein Auto länger als 5 Nächte im Minus, keine Kinder mit Auto, Eröffnung
  jeder neuen oder übernommenen Tech-Firma am selben Abend; **Grundregel** jede Stunde für jedes Auto (Ortswechsel nur mit
  Ortswechsel des Besitzers und `mitAuto`, sonst beim Besitzer oder zu Hause; Umzüge gezählt); Testfahrer nur in den Teststunden und im Werk;
  Autos von außen ab Tag 0, lange vor dem ersten Werk. **Faire Reihenfolge:** Im natürlichen Lauf sind ausverkaufte Tage selten (46 Käufe von
  außen an Tagen mit Werk, zu wenig für eine Aussage, nur gemessen); deshalb erzwungen (je 150 Tage ab dem ersten Werk, fünffache Kaufchance, ein
  Viertel der Fertigung), Endstand: Seed 2 mittlere Personennummer aus dem Werk 0,534 (244 Käufe), von außen 0,564 (455); Seed 4 0,605 (352)
  und 0,586 (315); erlaubt ±0,08. Erzwungen: Erbe, Geldnot, Haft, `AUTO_MAX` bei Übernahme (Gründung und Umzug); Speichern mitten im Werksbau und
  60 Tage über den Umzug hinweg bitgleich; 11 beschädigte Stände (seit der Schlussprüfung auch `g.werk = 2`).
- Angepasst (feste Momente verschoben, keine Prüfung schwächer): `--erweiterung` (Seed 2 wächst jetzt an Tag 172 zweimal in einer Nacht, die
  erste Nacht mit zwei Ringen statt der ersten überhaupt; Stadtbuchzeilen der Stufen beim Entstehen gesammelt, weil 500 Zeilen mit Autos
  früher voll sind; bei der Übernahme von Version 6 ist die Zeile der Stufe die vorletzte), `--militaer` (der Arbeitstext steht in
  `heuteArbeit`, `heuteText` hängt die Autofahrt an), `--migrationstest` (Version 7 = ffa1d88 dazu, je eine Zeile „Autos“; siehe unten).
- **Prüfung in `--migrationstest` („Kein Kündigungsschock nach der Frist“)**: In Teil 1 war sie gelockert (erste Nacht nur Kinder, die vor
  dem Ende der Frist lebten, Schwelle 2; alle Nächte ≤ 4), weil nach der Übernahme von Version 3 (Seed 3, Tag 400) in der ersten Nacht 3 Eltern
  aufhörten, zwei davon für Kinder, die am Tag nach der Frist geboren wurden. **Seit der Schlussprüfung gilt wieder die Prüfung von ffa1d88**
  (erste Nacht ≤ 2, Nächte 2–11 ≤ 4); dazu neu, strenger: Jede Stellenaufgabe der ersten Nacht muss ihr Kind im Gedächtnis haben. Im neuen
  Verlauf sind es in allen fünf Übernahmen in der ersten Nacht 0.
- Browser: `tests/autos.cjs` (neu): Hochhaus und Autowerk werden gezeichnet (Klick aufs Dach öffnet die Hauskarte „Stufe 5 (Hochhaus)“ bzw.
  „Autowerk … 4 Hallen“), alle mit Eröffnung; Grundregel 24 Stunden an der Schnittstelle, die die Darstellung nutzt (577 Autos, 1.142 Fahrten,
  0 ohne Ortswechsel, 0 ohne `mitAuto`, 0-mal weder beim Besitzer noch zu Hause); Teststrecke (4 Testfahrten um 10 und 14 Uhr, alle mit
  Testfahrer im Werk); Hauptfigur mit Auto: Raute sichtbar auf dem ganzen Weg; Personenkarte „fährt mit dem Lumen Weite 2 zur Arbeit“; Draw
  Calls 26 (≤ 32); Konsole leer. Mit Teil 2 angepasst: Die Hauptfigur fährt jetzt im Auto, geprüft wird, dass ihre Figur dann nicht zu sehen
  ist und die Raute über ihrem Auto steht (vorher: Raute über der gehenden Figur).
- Browser angepasst: `p6migration` (Version 7 → 8 mit `afd/stadt_v7.html` per Route: Dialog, übernehmen, Karte/Stufe/Stadtteile/Sicherheit/Bund
  bleiben, erstes Auto aus dem Umland, Fenster, Neuladen), `ereignis` (neue Momente: Tag 405, 446, 466, 478; erst Pleiten, dann 20×),
  `erweiterung` (Seed 9, Tag 235 → 236, 72 → 80; Stadtteil der Personenkarte = Stadtteil der eigenen Wohnung), `p8tech` (Dachhöhe für Stufe
  4/5), `befunde_s2` (13 aufklappbare Karten mit der Spielregel der Autos), `hilfe.cjs` (`basis_v8.json`).

**Auf dem Endstand** (`stadt.html` md5 `f2c932a538e9d75bc9a3ef1ad770c7a6`, `tools/simtest.mjs` md5 `a13b9ae6eddbc5669c2f99b7c8db7b64`, Server auf 8714, KI-Nachbau
auf 11434; Logs in `scratchpad/v8/logs/final_*.log` und `alle_end.log`):

- `simtest`: `--gate` (Seeds 1–3 alle Gates), `--speichertest` (bitgleich, drei Stände), `--aufholtest` (Vergleich), `--kitest` 47, `--bau` 15,
  `--waren` 15, `--tech` 16, `--regierung` 155, `--kita` 40, `--sicherheit` 28, `--militaer` 24, `--autos` 17, `--migrationstest --git
  /home/user/website-` 324 (Version 2–7, ffa1d88 als 7), `--erweiterung --git /home/user/website-` 33, dazu `--gross` 34. Alle ohne Fehler.
- Browser (`tests/alle.sh`): p3test 12, p5neu 10, p6migration 34, p7figuren 6, p8tech 14, raute_klick 9, ereignis 21, t1_xss 5, p4test 25,
  s2karten 22, kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16, autos 9; `otest` befunde 21, handy 11, breit 12,
  tastatur 4, breiten 20, hilfehoehe 1. Alle exit 0. Dazu `tests/pruef_v5.cjs` 17 (erwartet jetzt Version 8) und `tests/kennzahlen_hoehe.cjs`
  (Kennzahlen gleich hoch wie ffa1d88: quer 156 bis 216 px, hochkant 231 px).

**Teil 2 (Darstellung), Tests:**

- Browser `tests/autos_bild.cjs` (neu, in `tests/alle.sh`): Teststadt Seed 2, 24 Stunden je 9 Zeitpunkte: **Grundregel im Bild** (1.142 Fahrten,
  0 ohne Ortswechsel des Besitzers, 0 ohne `Sim.mitAuto`, 0 Umzüge ohne Wohnungswechsel), **kein Sprung** (Weg beginnt am alten Platz und endet
  am neuen, 0 stehende Autos ohne Fahrt bewegt), stehende Autos höchstens 2 Felder vom Gebäude, das `Sim.autoOrt` nennt, **Fahrer unsichtbar**
  (0 von 459 Figur-Zeitpunkten), **Rechtsverkehr** (1.065 Proben rechts, 0 links), **Teststrecke nur mit Testfahrer** (Prototyp bewegt sich nur
  in den Stunden 10 und 14 mit dem Testfahrer der Simulation, der dann laut Simulation im Werk arbeitet; 0-mal zugleich zu Fuß zu sehen; Klick
  auf den Prototyp öffnet ihn), **Hauptfigur im Auto** (Figur weg, Raute genau über dem Auto bei 20, 50, 80 % der Fahrt), **Tech-Stufen**
  (Hochhäuser 6,98 hoch, Turmebenen je Stufe des Werks, Campus in Seed 3), Klick auf ein parkendes Auto öffnet den Besitzer mit seinem Auto,
  **Lichtkegel** an einer echten Eröffnung der Simulation (Tag 734, Übernahme: mittags 0, abends 1, nach dem Neuaufbau wieder 1, um 2 Uhr 0),
  Draw Calls ≤ 29, Konsole leer.
- `tests/autos.cjs` (Teil 1) angepasst: Die Hauptfigur fährt jetzt, geprüft wird die Raute über dem Auto und die unsichtbare Figur.
- Die Hilfe ist gleich hoch wie vorher (745 von 745 px bei 1280 × 800, `otest/hilfehoehe`); `otest/befunde` findet „Offene Läden leuchten von
  17 bis 22 Uhr“ weiter, `militaer` und `sicherheit` ihre Farben.
- Nur Messung (nicht in `alle.sh`, `scratchpad/v8/t2/mess/`): `leistung.cjs`, `kennzahlen.cjs`, `calls.cjs`, `bilder.cjs`, `zustaende.cjs`
  (Werk im Bau, mit neuer Halle, leer; Umbau zum Campus), `karte.cjs`, `reduziert.cjs` (reduzierte Bewegung: Autos fahren weiter 5,2 Felder,
  Prototyp eine Runde), `wachsen.cjs` (Karte wächst 64 → 88: alle stehenden Autos an derselben Stelle der Welt).

**Auf dem Endstand von Teil 2** (`stadt.html` md5 `211010f8c8ddd8a2baaf13ae41d4f5e6`, `tools/simtest.mjs` unverändert md5 `a13b9ae6eddbc5669c2f99b7c8db7b64`; Server auf 8714, KI-Nachbau auf 11434; Logs in `scratchpad/v8/t2/logs/` und `t2/alle_end.log`):

- `simtest` (Datei unverändert): `--gate` (Seeds 1–3 alle Gates), `--speichertest` (bitgleich, drei Stände, Fingerabdrücke unten), `--aufholtest`,
  `--kitest` 47, `--bau` 15, `--waren` 15, `--tech` 16, `--regierung` 155, `--kita` 40, `--sicherheit` 28, `--militaer` 24, `--autos` 17,
  `--migrationstest --git /home/user/website-` 324, `--erweiterung --git /home/user/website-` 33, dazu `--gross` 34. Alle ohne Fehler.
- Browser (`tests/alle.sh`): p3test 12, p5neu 10, p6migration 34, p7figuren 6, p8tech 14, raute_klick 9, ereignis 21, t1_xss 5, p4test 25,
  s2karten 22, kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16, autos 9, **autos_bild 14**; `otest` befunde 21, handy 11,
  breit 12, tastatur 4, breiten 20, hilfehoehe 1. Alle exit 0. Dazu `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs` (Kennzahlen gleich
  hoch wie ffa1d88: quer 156 bis 216 px, hochkant 231 px).
- Zitate im Fenster: dieselben 254 wie in Teil 1 (Teil 2 bringt keine), `zitatpruef.py` 249 ok, 2 auf der Seite im Fließtext gefunden (S. 42,
  S. 43), 3 nicht als Ganzes: „S. 164 f.“ über den Seitenwechsel (selbst gelesen: S. 164 „Technologien, die den Bedürfnissen der Bevölkerung
  entsprechen,“, Seitenfuß, S. 165 „setzen sich von selbst durch, wie das Internet, Smartphones und der motorisierte Individualverkehr
  beweisen.“) und Noahs „Wie in Amerika“ und „Demographics Unit“ aus Version 7 (keine Programmzitate).


**Nach der Schlussprüfung, Tests:**

- `--autos` (21 Prüfungen): neu 2b (Grundregel wie im Bild über 12 Seeds, Abfahrt und Ziel beim Besitzer, Sprünge nach Grund, Testfahrer ohne
  eigenes Auto), 3b (ruhende Stellen erzwungen, mit Speichern), der elfte beschädigte Stand (`g.werk = 2`), die gemischte Reihenfolge statisch
  (jede Nummer genau einmal; `mischSchritt` in `autosTag`) und erzwungen auf Seeds 2 und 4, Werkskarten (Lieferant, Hallen wie im Bild); die
  Invarianten-Schleife prüft Fahrten mit `autoFaehrt` (eine eng begrenzte Ausnahme: neue Stelle mitten am Tag nah an der Wohnung, gezählt).
- `autos_bild.cjs` (20): Abfahrt beim Besitzer, Sprünge nur, wenn der Besitzer den Weg nicht mit dem Auto macht, drei echte Sprung-Fälle (Seed 2
  Tag 305, Seed 14 Tag 137, Seed 8 Tag 690: Figur die ganze Stunde zu sehen, Raute über ihr), Karten (Testfahrer um 5, 8 und 10 Uhr, Werkskarte,
  „fährt um 8 Uhr …“), Turmebenen nur für fertige, offene Werke.
- Angepasst an den neuen Verlauf (keine Prüfung schwächer; Liste oben unter „Befunde der Schlussprüfung“): `--bau`, `--kita`, `--sicherheit`,
  `ereignis`, `erweiterung`, `p8tech`, `autos`; `raute_klick` setzt den Blick vor dem Messen der Rauten noch einmal (im Endlauf von `alle.sh`
  lag er einmal woanders, 4 von 8 Klicks trafen Häuser; allein lief der Test vor der Änderung dreimal und danach einmal mit 8 von 8).

**Endstand nach der Schlussprüfung** (`stadt.html` md5 `dbc106d795426d7711a9ab04c4ec21f5`, `tools/simtest.mjs` md5
`4ad5a052079ff96e940aeb32be895e89`; Server auf 8714, KI-Nachbau auf 11434; Logs in `scratchpad/v8/logs2/final_*.log` und `alle_end.log`):

- `simtest`: `--gate` (Seeds 1–3 alle Gates; im Lauf mit vier Modi gleichzeitig fiel auf Seed 1 nur die Laufzeit T mit 6,5 s, allein 1,9 bis
  2,3 s), `--speichertest` (bitgleich, drei Stände), `--aufholtest` (Vergleich), `--kitest` 47, `--bau` 15, `--waren` 15, `--tech` 16,
  `--regierung` 155, `--kita` 40, `--sicherheit` 28, `--militaer` 24, `--autos` 21, `--migrationstest --git /home/user/website-` 324 (Version 2–7,
  ffa1d88 als 7), `--erweiterung --git /home/user/website-` 33, dazu `--gross` 34. Alle ohne Fehler.
- Browser (`tests/alle.sh`): p3test 12, p5neu 10, p6migration 34, p7figuren 6, p8tech 14, raute_klick 9 (nach der Änderung oben), ereignis 21,
  t1_xss 5, p4test 25, s2karten 22, kita 22, befunde_s2 27, erweiterung 20, sicherheit 12, militaer 16, autos 9, autos_bild 20; `otest` befunde 21,
  handy 11, breit 12, tastatur 4, breiten 20, hilfehoehe 1 (die Hilfe ist mit dem neuen Satz zum Lichtkegel gleich hoch). Dazu
  `tests/pruef_v5.cjs` 17 und `tests/kennzahlen_hoehe.cjs` (gleich hoch wie ffa1d88: quer 156 bis 216 px, hochkant 231 px).
- Zitate im Fenster: 254 (`zitate_sammeln.mjs`), `zitatpruef.py` 251 gefunden, `zitate_genau.py` 249 genau auf der Seite; die übrigen wie oben
  unter „Stadtregierung“ (S. 164 f. über den Seitenwechsel selbst gelesen; S. 42 und S. 43 im Fließtext auf der Seite gefunden; „Wie in Amerika“
  und „Demographics Unit“ sind keine Programmzitate). Die neuen Texte der Schlussprüfung bringen kein neues Zitat.
- Im Git-Repo ist nichts geändert, `stadt.orig.html` ist gleich ffa1d88 (per `cmp` geprüft).

### Befunde der Gegenprüfung „sim“

1. `AUTO_MAX` umgangen (Übernahme leerer Werke): `uebernehmbar` und `wachsZiel` prüfen `werkeZahl < AUTO_MAX`; `--autos` zählt jede Nacht
   und prüft den Fall erzwungen. Leere Werke: Ø 0,08 je Stadt an Tag 730 (bekannte Folge, unten).
2. Verschiedene Grenzen fürs Fahren: nur noch `Sim.mitAuto`; Autos von außen ab Tag 0 (Noahs Entscheidung), Marke 255.
3. Grundregel nach Wortlaut: umformuliert und festgehalten (oben, „Fahren“); `autoOrt` ohne Zustand.
4. Stadtregierung: R-A1–R-A5 im Code, Listen nachgezogen, jedes Zitat an einer Stelle (`--regierung`).
5. CO₂ einheitlich: beide Teile fallen weg, belegt.
6. Einbau zusammen und auf Version 7: Notbehelf in der Darstellung (kein Absturz, `tests/autos.cjs`), Migration V2–V7, Mieterkäufe gemessen.
7. Export nachrechenbar: 72,6 % als Summe, 70,1 % als Mittel je Stadt (oben).
8. Kistentragen: kein Träger zum Werk, Text nur für Läden; die Werkstattkarte nennt die Teile fürs Werk.
9. Reihenfolge: zuerst ein rotierender Start je Tag, seit der Schlussprüfung jeden Tag gemischt (A20); `--autos` prüft sie erzwungen (Seeds 2 und 4).
10. Geldnot: Verkauf nach 5 Nächten im Minus (A14).
11. Preis und Kosten: beide Benziner, „ein Modell, kein Mittelwert“.
12. Lebensdauer: Rechnung gezeigt, KBA 10,9 Jahre (1. 1. 2026).
13. S. 164: Zusammenhang und „S. 164 f.“ einheitlich.
14. Parkraum „hat in der Simulation keine Wirkung“; 40-%-Grenze auch nach dem Auftrag (ruhende Stellen); `arbeitsOrtHeute` und `ortZurStunde`
    folgen derselben Regel: die Stelle (`arbeit`) oder die Baustelle, auf die der Bauhof jemanden eingeteilt hat, nie `besitz`.

### Befunde der Gegenprüfung „darstellung“

1. **Prototyp gegen die Grundregel (blockierend):** Er fährt nur mit dem Testfahrer der Simulation (`Sim.testfahrtStunde`: 10 und 14 Uhr, eine
   Kraft, die in dieser Stunde laut `ortZurStunde` genau in diesem Werk arbeitet); deren Figur ist dann nirgends zu sehen (als Hauptfigur die
   Raute über dem Prototyp), ein Tipp auf ihn öffnet ihre Karte. Weich an- und ausgefahren über die Stunde, ohne Sprung; sonst steht er an der
   Startlinie. `tests/autos_bild.cjs` prüft es 24 Stunden lang je Bild.
2. **Gründung als Ereignis:** Lichtkegel für jede Tech-Firma (auch Stufe 1–3), nach `g.eroeffnet` der Simulation (Abend des Tages, 18:30–1 Uhr,
   weich), also auch nach dem Neuladen; geprüft mit einer echten Eröffnung der Simulation (Teststadt, Tag 734), nicht mit einer Testhilfe.
3. **Zuschreibungen ans Programm:** Die Darstellung bringt keine Zitate und keine Regeln ins Fenster; die 3-Felder-Grenze ist keine Regel der
   Darstellung mehr (sie fragt `Sim.mitAuto`, R-A1 ist dort eine echte Wahl der Leute). Die Liste des Fensters kommt aus Teil 1 (ein Satz je
   Zitat, `--regierung`).
4. **Hauptfiguren:** Raute über dem fahrenden Auto (und über dem Prototyp); Annahme 44 nachgezogen.
5. **Allokation in der Planung:** feste Puffer statt `new Int32Array` je Weg, Ring aus festen Abstandsfeldern statt `new Uint8Array(F)` je Ziel,
   keine Map je Weg; Heap-Stichprobe in den Bildern nach 8 Uhr gemessen (oben).
6. **Parken:** höchstens ein Straßenfeld weiter (vorher 5); die Regel und der Anteil sichtbar geparkter Autos stehen oben als Abweichung.
7. **Springende Autos ohne Fahrt:** Ein stehendes Auto bleibt stehen, bis sein Besitzer fährt; ein Platz, der nicht mehr erlaubt ist, gilt nur
   für neu parkende Autos. Geprüft: 0 bewegte stehende Autos in 24 Stunden.
8. **Lücke über `TRIP_MAX`:** Jede Fahrt der Stunde wird geführt (Puffer so groß wie die Personen); über `FAHR_MAX` springt sie mit Ort und
   Platz am Ziel.
9. **Schnittstelle:** Werk an `g.werk` erkannt, Stufe sichtbar (Hallen, Turmebenen), Gelände aus der Simulation; die Testhilfe `autoTest` des
   Prototyps gibt es nicht mehr (nichts in der Darstellung schreibt in `S`).
10. **Leistung und Doku:** Stundenschritt um 8 und 17 Uhr gemessen und begrenzt (Planung verteilt, 3 ms je Bild), Standreihen und Gehweg in
    Annahme 44 und D2 beschrieben.


### Befunde der Schlussprüfung (Version 8)

Drei Prüfungen (Technik, Texte, Bedienung), 26 Befunde. Jeder ist nachgeprüft und umgesetzt, wo nicht anders gesagt (Rest unter „Bekannte
Schwächen“). Scratchpad-Skripte: `v8/mess2/`.

**Technik**
1. **Grundregel beim Umzug um 8 Uhr und bei einer neuen Stelle mitten am Tag (blockierend):** Das Auto fuhr sichtbar ohne seinen Besitzer,
   dessen Figur währenddessen unsichtbar war. Jetzt entscheidet `Sim.autoFaehrt` (Besitzer in der Vorstunde beim Auto, jetzt an dessen Ziel,
   `mitAuto`), die Darstellung merkt sich dazu je Person, wo die Simulation den Besitzer in der Vorstunde hatte (`pVor`); sonst springt das
   Auto ohne Fahrt, der Besitzer bleibt sichtbar. `--autos` prüft das wie im Bild über 12 Seeds (2b) und in der Invarianten-Schleife;
   `autos_bild.cjs` prüft die Abfahrt beim Besitzer und drei echte Fälle im Browser (Umzug um 8 Uhr, neue Stelle nah und weit).
2. **Ruhende Stellen ohne Test (mittel):** `--autos` 3b erzwingt sie (Seed 2, Tag 400–460, Grenze 70 % des Anteils der Stadt): Grenze nach
   jeder Nacht, offene und freie Stellen, niemand in einer ruhenden Stelle, Rückkehr, Speichern bitgleich.
3. **`--migrationstest` gelockert:** wieder die Prüfung von ffa1d88 (erste Nacht ≤ 2), dazu die Gedächtnis-Prüfung.
4. **`g.werk = 2` lud ohne Fehler:** `autoPruefen` lehnt es ab; elfter beschädigter Stand in `--autos`.
5. **Draw-Call-Budget:** gemessen +2 (`M.auto`, `M.leucht`), einer vom Budget +3 ist frei (oben, Gemessen).
6. **Reihenfolge nur rotiert:** jetzt jeden Tag gemischt (A20), statisch und erzwungen geprüft (Seeds 2 und 4).
7. **`tests/erweiterung.cjs` unter Last:** wartet jetzt bis zu 15 s, bis die Namen stehen (die Prüfung selbst ist gleich).

**Texte**
1. **S. 42, „Den motorisierten Individualverkehr schützen“ (blockierend):** Der Punkt sagt jetzt, dass das Programm Mittel nennt
   (intelligente Technik, stauvermeidende Verkehrsführung, Erhalt und Ausbau von Fahrspuren und Parkraum; gegen Dieselfahrverbote und Tempo 30),
   aber kein Geld.
2. **README 7,31/7,68 verdreht (blockierend):** „7,31 Taler am Tag (7,68 mit den CO₂-Abgaben, die … wegfallen)“.
3. **Antriebe (mittel):** R-A3, R-A4 und „gilt schon“ S. 43: „Alle Autos sind gleich und kosten wie ein Benziner (R-A2) …“; S. 13
   (Kohlekraftwerke): „Keine Stromerzeugung und keine Heizung …; Energie steckt nur im Sprit der Autos“; S. 79 verweist auf R-A2; die Gruppe
   „Kein Gegenstück“ nennt „Strom und Heizung“ statt „Energie“.
4. **„kamen von die Werkstatt …“:** „Hauptlieferant ist …“ (wie in der Werkstattkarte), geprüft in `--autos` und `autos_bild.cjs`.
5. **Hallen in Karte und Bild:** die Karte zählt jetzt Stufe − 1 Hallen wie das Bild (D12).
6. **Stadtbuch:** „alles aus eigenem Geld“, Anbau-Aufträge mit Tausenderpunkt, jedes Werk „den größten Auftrag, den eine Firma geben kann“.
7. **Personenkarte doppelt „aus dem Umland“:** bei Autos von außen nur „(gekauft an Tag …)“.
8. **10,9 Jahre:** „rechnerisch … 10,9 Jahre; gemessen sind es etwa 10“ (A9 mit der Messung).
9. **Auslegungen:** R-A5 „Die Stadt wendet die Ausnahme … nicht an (Auslegung)“; R-A2 „sagt der Satz auf S. 13 nicht eindeutig“; der
   Energiesteuer-Punkt steht unter „Keine Zahl …“ und ist als Auslegung gekennzeichnet; „Zur Vollständigkeit“ nennt die Senkung der
   Energiesteuer unter „es fehlen“.
10. **Kleine Ungenauigkeiten:** Hilfe „neu, umgezogen oder jetzt Campus/Hochhaus“ (gleich hoch, `otest/hilfehoehe`); Fahrspuren „In der
   Simulation haben Straßen keine Spuren …“; „keine Tempolimits“; Lkw-Maut „die in der Stadt auf Autos anfielen“; Stadtbuch der Übernahme „Auf
   Autos fallen in der Stadt keine CO₂-Abgaben an“.
11. **Wahl zwischen Werk und Umland ohne Beleg im Fenster:** „Kauf:“ nennt jetzt die Annahme (gleicher Preis, kürzerer Weg, das Geld bleibt in
   der Stadt).
12. **README Vergleichswerte, Stände:** was eingestellt und was nur gemessen ist; Destatis „Ende September 2025“ (auch im Fenster); R-A4 mit
   Stand Dezember 2025 (Vorschlag der EU-Kommission, 90 % statt 100 %).
13. **Parkplätze nach Personennummer:** die Darstellung vergibt sie in jeder Stunde gemischter Reihenfolge (`Sim.mischSchritt`).

**Bedienung**
1. **Testfahrer vor 8 Uhr falsch (mittel):** Karten nennen ihn erst ab 8 Uhr (`testStundenRest`), davor „… steht um 8 Uhr fest“, danach nur
   die Teststunden, die noch kommen; `autos_bild.cjs` prüft um 5, 8 und 10 Uhr.
2. **20× bei wenigen Bildern:** Planungsbudget nach Spielzeit, `rest` gemessen 0 statt 689; im README steht nicht mehr „gemessen 0“ ohne
   Bedingung.
3. **Dreiecke der großen Stadt:** Autos mit 28 statt 36 Dreiecken (Lichter im Shader); die Spalten heißen jetzt „JS-Zeit“ und „Bildabstand“.
   Eine Begrenzung stehender Autos nach Abstand habe ich nicht gebaut (sie würden beim Schwenken fehlen); dazu unten.
4. **Autos verschwinden statt zu fahren:** zweite Stufe mit engem Abstand (je Stunde gut 50 Fahrten mehr sichtbar, keine Überlappung mehr als
   vorher). Nahe der Kamera trotzdem zu fahren, führte zu Überlappungen und ist wieder entfernt; dort springen weiter Fahrten (unten).
5. **Grammatik der Werkskarte:** wie Texte 4.
6. **„steht …“ bei einem fahrenden Auto:** „fährt um 8 Uhr zur Arbeit“ (auch „nach Hause“, „zu Besuch“, „zum Einkaufen“) in der Stunde, in
   der der Besitzer damit fährt (`autoFahrtWohin`, ohne Zustand).

Außerdem nach dem neuen Verlauf angepasst (keine Prüfung schwächer): `--bau` zieht Ersatzdienst von der Obergrenze des Bauhofs ab (so steht es
in der Regel; im neuen Verlauf hat Seed 1 schon vor Tag 365 Ersatzdienst im Bauhof), `--kita` zählt Eltern im Dienst des Bundes wie die Regel
(B10) und sucht den erzwungenen Fall (h) bis zu 60 Abende weiter, `--sicherheit` sucht den Obhut-Fall auch in Seed 1 und 3 (Seed 2 hat bis Tag
730 keinen Haushalt mit nur einem Erwachsenen und Kindern), `--autos` misst die faire Reihenfolge ab dem ersten Werk und auf zwei Seeds;
im Browser neue Momente in `ereignis.cjs` (Tag 422, 449, 452, 490) und `erweiterung.cjs` (Seed 12, Tag 243 → 244, 80 → 88), in `p8tech.cjs`
die erste Kraft, die noch keine Hauptfigur ist, in `autos.cjs` das Werk steil von oben (ein Hochhaus stand davor).

### Bekannte Schwächen (Version 8)

- **Weniger Pendler mit dem Auto als in Deutschland:** 43 % der Arbeitstage gegen 65 %. Die Stadt ist klein (Wege von wenigen Feldern), und
  wer weniger als 3 Felder hat, geht zu Fuß. Eine kürzere Grenze würde auch 1-Feld-Wege fahren.
- **Gate 4 hängt am Geld der ersten Monate und am Zufall der Reihenfolge.** Ohne die Regel für Betriebssparer fielen 6 von 80 Städten. Mit
  ihr ergeben vier gleich neutrale Mischungen der Käufer 76 bis 78 von 80 (ausgeliefert 78, nach dem Ergebnis gewählt; ffa1d88 78).
- **Sprung statt Fahrt bei Umzug und neuer Stelle mitten am Tag:** Das Auto verschwindet am alten Platz und steht am neuen, ohne zu fahren
  (in 12 Städten × 730 Tagen 32-mal). Liegt eine neue Stelle nah an der Wohnung, steht das Auto ab dann zu Hause, obwohl der Besitzer es an der
  alten Stelle stehen hatte (`autoOrt` hat keinen Zustand).
- **Leere Werke:** Schließt ein Werk (Tod des Besitzes), bleibt ein ganzer Block leer, bis eine Tech-Gründung oder eine große Firma es
  übernimmt (Ø 0,13 je Stadt an Tag 730).
- **Die meisten Autos stehen unsichtbar in der Garage:** nachts 16 bis 17 % sichtbar am Straßenrand, tagsüber knapp ein Drittel (oben,
  „Parken“). Mehr sichtbare Stellfläche bräuchte Parkflächen auf Bauplätzen oder in Gärten.
- **Springende Autos, auch nahe der Kamera:** In der großen Stadt fährt um 8 und 17 Uhr knapp die Hälfte der Fahrten nicht sichtbar (Straße
  voll oder über `FAHR_MAX`): am alten Platz bis zur Abfahrt, dann erst am Ziel. Von den Fahrten mit Start oder Ziel höchstens 6 Felder vom
  Blickpunkt springen um 17 Uhr 92 von 253 (Teststadt 8 von 136). Sie trotzdem fahren zu lassen, führte zu Autos, die durcheinander fahren;
  es bräuchte Stau (Autos, die hintereinander warten) oder mehr Spuren.
- **Leistung und Dreiecke:** Die große Stadt hat um 8 Uhr 228.000 statt 147.000 Dreiecke (60.000 davon Autos), der Bildabstand steigt in
  SwiftShader um 5 bis 18 % (zwei Messungen, Rechner geteilt). Die ersten Bilder einer Stunde mit vielen Abfahrten kosten 3 ms mehr, in der großen Stadt bei wenigen Bildern bis 10 ms;
  der Stundenschritt der großen Stadt 10 bis 15 ms mehr; nur unter SwiftShader gemessen, nicht auf einem Handy. Vom Draw-Call-Budget (+3) ist
  noch einer frei.
- **Autos kleiner als maßstäblich** (D1), keine Kollisionsprüfung mit Fußgängern, die die Straße queren; kein Stau, Autos warten nur beim
  Losfahren. Wenige fahrende Autos kommen sich trotzdem näher als 0,16 (große Stadt 3 bis 9 Paare je Stunde, gleich viele wie vor der
  Schlussprüfung; die Ursache habe ich nicht untersucht).
- **Karten ohne Zustand:** „fährt um 8 Uhr zur Arbeit“ steht die ganze Stunde da, auch wenn das Auto schon angekommen ist; der Testfahrer
  stimmt ab 8 Uhr, nimmt jemand erst später frei (späte KI-Antwort), ab der nächsten Stunde.
- **Kein Gebrauchtwagenmarkt, keine Unfälle, kein Parkraum als Regel der Stadt;** nur Benziner; Kosten und Preis sind ein Modell.

## Aufbau

- `stadt.html` enthält den Block `<script id="sim">`: reine Simulation, kein DOM, kein `window`, kein `fetch`,
  kein `Math.random`, keine Uhrzeit. Er legt `globalThis.StadtSim` an. Alle Personendaten liegen als typisierte Arrays
  (eine pro Feld, Index = Personen-ID) in `S.p`, die Gebäude in `S.g`, die Hauptfiguren in `S.ki`.
  Alle Stellschrauben stehen gesammelt im Objekt `R` am Anfang des Blocks.
- Der `<script type="module">`-Block macht Darstellung, Oberfläche, Speichern und die Ollama-Aufrufe. Er ändert den
  Sim-Zustand nur über Funktionen aus `StadtSim` (`stunde`, `tagSchritt`, `hauptSetzen`, `kiSchalten`, `kiEntscheidung`,
  `kiVerwerfen`, `kiGespraech`, `kiTagebuch`, `verlustErledigt`, `importZustand`). `theke`, `traeger`, `bauGesamt`, `regierungInfo`,
  `erweiterungInfo`, `stadtteilZaehlen`, `teilVon`, `teilName`, `sicherheitInfo`, `polizeiEinsatz`, `imHof`, `hofZeiten`, `abteilung`,
  `bundInfo`, `dienstWahl` und `verpflichtet` lesen nur. Version 8: `mitAuto`, `pendeltMitAuto`, `ortZurStunde`, `arbeitsOrtHeute`,
  `autoOrt`, `autoWegMin`, `testfahrer`, `testfahrtStunde`, `autoFirmaVon`, `autoName`, `autoInfo`, `autoKennzahlen`, `techPlaetzeVon` und
  `werkeZahl` lesen nur; `mitAuto` ist die einzige Entscheidung übers Fahren, auch für die Darstellung (sie fragt `autoOrt`, `mitAuto` und
  `testfahrtStunde` jede Stunde und merkt sich nur, wo sie jedes Auto gezeichnet hat; im Spielstand steht davon nichts). `StadtSim._auto` (Kauf, Nacht der
  Autos, Erbe, Geldnot, Werk, Übernahme gezielt auslösen) ist nur für `tools/simtest.mjs --autos` da.
  `StadtSim._sich` (Urteil, Haftantritt, Haftende, Tat, Obhut, Stellen des Landes gezielt auslösen) ist nur für `tools/simtest.mjs --sicherheit`
  und die Browser-Tests da, `StadtSim._bund` (Einberufung, Dienstende, Nacht des Bundes, Prüfung, Anstellen, Austreten) nur für
  `tools/simtest.mjs --militaer`. `gelaendeSuchen` und `gelaendeBauen` sind die Schnittstelle
  für Teil 2 und 3 von „Stadt erweitern“, `karteRand` ist nur für Tests da; die Oberfläche benutzt diese drei nicht. Wächst die Karte, baut
  die Oberfläche beim nächsten stündlichen Neuaufbau der Stadt einmal Landschaft, Umland und Grenzen neu (`karteNeu` am Anfang von
  `stadt()`).
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
node tools/simtest.mjs --migrationstest        # Spielstände von Version 2 bis 7 übernehmen (alte Dateien aus git 39c405b, 2b821c2,
                                               #   1c8d40b, 414ebab, bc7247a und ffa1d88), 60 Tage weiter, Kita-Übergangsfrist und die
                                               #   Nächte danach (Schwelle), beschädigte Stände der Version 5; aus Version 6 60 Tage genau
                                               #   wie dort; --git <ordner>: anderes Repository
node tools/simtest.mjs --migrationstest --alt <alte stadt.html>   # nur diese alte Datei
node tools/simtest.mjs --erweiterung           # Stadt erweitern (Version 7): statisch, Seeds 1–3 je 730 Tage Tag für Tag wie
                                               #   Version 6 (git bc7247a), Grenze hält nie eine Straße auf, Wachsen, Stufen,
                                               #   Stadtteile, Speichern über ein Wachsen, beschädigte Stände, Übernahme von 6,
                                               #   Gelände; --gross: dazu die große Stadt (umland=300000, 750 Tage)
node tools/simtest.mjs --sicherheit            # Sicherheit (Version 7): statisch (Zufall, Personenfelder je Regel, Landeslöhne),
                                               #   Namenstausch bitgleich, Invarianten jede Nacht (Haft, U-Haft, Plätze, Hof, Obhut,
                                               #   Wache und Anstalt), erzwungene Urteile und Randfälle, Speichern mit Haft,
                                               #   beschädigte Stände, Messung gegen die PKS 2024 und nach Gruppen (Seeds 1–3)
node tools/simtest.mjs --militaer              # Bund (Version 7, Teil 3): statisch (kein Zufall, Personenfelder je Regel, keine Namen,
                                               #   kein Geschlecht, Löhne und Sold nicht aus dem Budget, Ersatzdienst ohne Kisten,
                                               #   die Dienststelle liest niemanden), Namenstausch bitgleich, Invarianten jede Nacht
                                               #   (Gelände, Rollen, Stellen, Einberufung mit 18 ab dem Tag nach der Eröffnung, genau
                                               #   5 Diensttage, Bindung, Geld vom Bund), erzwungene Fälle, Speichern, beschädigte
                                               #   Stände, Messung nach Geschlecht (Seeds 1–3)
node tools/simtest.mjs --autos                 # Tech-Firmen und Autos (Version 8): statisch (Zufall nur aus S.rsAuto, Personenfelder je
                                               #   Regel, keine Namen), Namenstausch bitgleich, Invarianten jede Nacht und Stunde (Werke,
                                               #   AUTO_MAX, 40-%-Grenze, Käufe, Kosten, CO₂, Grundregel, Testfahrt), faire Reihenfolge
                                               #   (erzwungen ausverkauft), Erbe, Geldnot, Haft, AUTO_MAX bei Übernahme, Speichern mitten
                                               #   im Werksbau, beschädigte Stände, Messung (Seeds 1–3; --seeds 1,2); Grundregel wie im Bild
                                               #   über --regelseeds (1–12), faire Reihenfolge über --reiheseeds (2,4), ruhende Stellen
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
| 11 | Zuzug: Als „freie Stellen“ zählen nur freie Stellen in Werkstätten und Tech-Firmen (nicht im Bauhof, nicht in Läden, seit Schritt 2 nicht in Kitas), abzüglich der Arbeitslosen der Stadt. Wer zuzieht, tritt sofort die nächste solche Stelle an; ist keine mehr frei, kommt an diesem Tag niemand mehr. Zuzügler sind 18–60 Jahre alt (bis zur Gate-4-Änderung 18–45). Höchstens 1 + 1 % der Einwohner pro Tag | **Weicht vom Wortlaut der Spec ab** („freie Stellen“); Noahs Entscheidung für Gate 4. Zählten Ladenstellen, holte jeder neue Laden Leute von außen, die wieder neue Läden brauchen: Ladenboom, danach Pleitewelle. Läden stellen deshalb nur Leute aus der Stadt ein. Mit 18–45 ging die erste Generation fast gleichzeitig in Rente. Arbeitslose abziehen: sonst ziehen Leute für Stellen zu, die Einheimische ohnehin gleich nehmen. Seit der Stadtregierung zählen Leute in gemeinnütziger Arbeit als arbeitslos, Eltern mit Betreuungsgehalt nicht, seit den Kitas auch Eltern nicht, die ohne Kita-Platz keine Stelle antreten können; die Stadtregierung weist die Regel als R10 aus (galt schon), dazu R09. Seit Teil 2 (Sicherheit) besetzt, wer zuzieht, zuerst offene Stellen des Landes (Wache, Anstalt; S-A19), seit Teil 3 danach die des Bundes (Kaserne, Dienststelle; B11) |
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
| 27 | Gate 4: „pendelt sich ein“ = die Einwohnerzahl bleibt in den letzten 180 Tagen (Tag 551–730) in einem Band von Faktor 1,15 (max/min). „Unterhalb der Kartengrenze“ = keine Straße hat die äußerste erlaubte Rasterlinie erreicht. Seit Version 7 wächst die Karte vorher (Annahme 70), dieser Teil hält also immer (Abstand zur Baugrenze der heutigen Karte mindestens 16). `--gate` druckt deshalb dazu die Lage auf der alten Karte 96 und den Abstand zur alten Baugrenze (Seeds 1–3: 24, 12, 24; Seeds 1–80 mindestens 12): Keine Stadt hätte die alte Karte gesprengt | Die Spec gibt keine Zahl. Die Spec kennt nur die feste Karte; Noahs Entscheidung „Karte wächst wirklich“ |
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
| 41 | Spielstand-Version 7 (2: Hauptfiguren und Tagebuch, 3: Bauhof und Kisten, 4: Tech-Firmen, 5: Stadtregierung mit den Personenfeldern `gsTage` und `gemein`, `S.regierung` mit Start und Tageswerten `gestern`/`tagStart`, und `S.stat.regierung`; 6: Schritt 2 mit den Personenfeldern `eigen`, `kaufPreis`, `schuld`, `beitrag` und `kita`, dem Gebäudefeld `soll`, `S.regierung.schritt2` und `kitaAb` und der Zahl `S.stat.bauamt.kitas`; 7: Kartengröße `S.karte` mit `mitte`, `vn`, `vo`, Felder so groß wie die Karte, und `S.erweiterung` mit Stufe, Stufentagen, Ausdehnung, Stadtteilen, Geländen und Wachsen, Abschnitt „Stadt erweitern“; dazu die Personenfelder `PF_SICHERHEIT`, `S.rsSich`, `S.sicherheit` und `S.stat.sicherheit`, Abschnitt „Sicherheit“; dazu die Personenfelder `PF_BUND` (`bund`, `dienstBis`), `S.bund` und `S.stat.bund`, Abschnitt „Bund“). Stände anderer Versionen lösen den Versionsdialog aus; Version 2 bis 6 lassen sich übernehmen (Annahme 60). Ein Stand der Version 7 mit falscher Kartengröße oder falschen Maßen, Feldern anderer Länge, einem unvollständigen `S.erweiterung`, einer unvollständigen oder unmöglichen Sicherheit (Haft, Verfahren, Summen, Wache und Anstalt) oder einem unvollständigen oder unmöglichen Bund (Kaserne, Dienststelle, Eröffnung, Summen, Rollen, Dienst) wird abgelehnt. Ein Stand der Version 6 ohne die neuen Personen- und Gebäudefelder, ohne gültige Stadtregierung (Start, Schritt 2 und Ende der Kita-Frist als ganze Tage, alle Summen, die vom Tagesende und die von gestern als Zahlen, gestern auch leer), mit Wohneigentum, das es so nicht gibt, oder mit Kita-Plätzen und -Stellen, die es so nicht gibt, wird abgelehnt | Neue Felder. Ein Stand der Version 4 liefe sonst still unter den neuen Regeln weiter; ohne die Prüfung stürzte ein beschädigter Stand um Mitternacht ab |
| 42 | Bei 1× ist eine echte Minute eine Spielstunde | Folgt aus der Spec: 90 Spieltage entsprechen 36 Stunden Abwesenheit |
| 43 | Beim Aufholen (Tagesschritte) entscheiden alle nur um 7 und 18 Uhr; Ereignisse lösen keine zusätzliche Entscheidung aus. Der Bauhof teilt direkt nach der 7-Uhr-Entscheidung ein, wie stündlich | Sonst wäre der Tagesschritt nicht schneller. Abweichung gegen stündlich nach 90 Tagen (Tag 200–290) mit der Stadtregierung: Seeds 1–10 im Mittel −0,3 % Einwohner, einzeln −17,2 % bis +10,7 %; Seeds 1–20 im Mittel +0,2 %, 10 von 20 höher. Vorher auf den Seeds 1–10 +0,7 %, einzeln −5,8 % bis +10,8 % (vor der Zuzug-Regel −1,7 %, einzeln −8,6 % bis +8,1 %). Der Ausreißer Seed 10 wächst in diesen Tagen stark (stündlich 246 → 623 Einwohner); in Tagesschritten kamen weniger Geburten (90 statt 120) und weniger Zuzüge, der Unterschied wächst von Tag zu Tag. Nicht einseitig: Vorher lag derselbe Seed 10,8 % darüber |
| 44 | Grundregel: Eine Figur steht oder geht nur dort, wo die Simulation die Person in dieser Stunde hat. Arbeit 8–17 Uhr (Bauarbeiter auf ihrer Baustelle), abends bei Freunden 19–22 Uhr (wer „freunde_treffen“ gewählt hat), wer frei hat um 10 Uhr einkaufen, sonst zu Hause. Ändert sich der Ort, geht die Figur dorthin. Von den 300 Figuren sind bis zu 120 Leute bei der Arbeit (Annahme 62), die übrigen zufällige Erwachsene, die nur unterwegs zu sehen sind. Hauptfiguren sind immer zu sehen: wenn sie nicht laufen, stehen sie vor dem Gebäude, in dem sie gerade sind. Fährt eine Hauptfigur mit dem Auto (Version 8), ist ihre Figur so lange nicht zu sehen, ihre Raute schwebt über dem Auto (auch über dem Prototyp auf der Teststrecke). Ihre Markierung ist gelb, weiß solange sie „überlegen“. Jede sichtbare Figur ist anklickbar. Seit Version 8 gehen Figuren auf dem rechten Gehweg (die Fahrbahn gehört den Autos) und stehen vor einem Gebäude in Reihen 0,6 und 0,5 von der Hausmitte (vorher 0,68 und 0,84, die zweite Reihe stand auf der Fahrbahn), im Autowerk auf dem Gelände vor der Montagehalle | Die Spec sagt „morgens zur Arbeit, abends heim oder zu Freunden“ und „plus immer alle Hauptfiguren“ |
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
| 58 | Bauhof: 10 Stellen plus eine je 4 offene Arbeitstage, höchstens 40 (gemeinnützige Arbeit und, seit Teil 3, Ersatzdienst kommen dazu; der Ersatzdienst zählt nicht zu den 40, B12); neu gerechnet, sobald eine Baustelle dazukommt (Gründung, Bauamt) und jede Nacht. Lohn 95–120 Taler: +2 am Tag, wenn um 7 Uhr Leute fehlten, sonst −1. Schrumpfen die Stellen, bleibt niemand ohne Arbeit, es wird nur nicht nachbesetzt. Freie Stellen im Bauhof locken keinen Zuzug an, und Gründer rechnen den Bauhof mit seinen 10 festen Stellen | Die Stellen gehen mit den Baustellen auf und ab. Zählten sie beim Zuzug oder bei „Werkstatt lohnt sich“, würde jede Baustelle Leute in die Stadt holen bzw. Werkstätten verhindern (im Entwurf gemessen: die Stadt schaukelt sich auf). Mit festem Lohn lief der Bauhof leer |
| 59 | Kisten: Kistenpreis = Umlandpreis je Arbeitstag / 8 (etwa 15–17 Taler), von außerhalb 19 Taler. Die Werkstatt nimmt je Arbeitstag dasselbe ein wie vorher, egal ob ein Laden oder das Umland die Kisten nimmt. Gründer zahlen Bau oder Übernahme an die Stadtkasse, die Stadt zahlt dafür die Bauarbeiter | Noahs Entscheidung A: Kisten als Preisvorteil für Läden, keine echte Knappheit (siehe Schwächen). Mit „Umland kauft nur die Hälfte“ hatte die Stadt im Entwurf an Tag 365 im Schnitt 891 statt 1.170 Einwohner, ohne dass Gate 4 besser wurde |
| 60 | Ein Spielstand von Version 2, 3, 4, 5 oder 6 lässt sich im Versionsdialog mit „Stadt übernehmen“ umrechnen (Text je Version). Von 6: Die Karte bleibt 96 × 96 und wächst gleich, wenn eine Straße näher als 16 Felder am Rand liegt; Stufe aus den heutigen Einwohnern, Stadtteile ab der Kleinstadt in der Reihenfolge ihres ersten Gebäudes, eine Zeile „Ab heute zählt die Stadt ihre Größe …“; Sicherheit ab dem Übernahmetag (niemand vorbestraft oder in Haft, eine Zeile „Ab heute gibt es in der Stadt Diebstahl …“, Wache und Anstalt bestellt das Land in den folgenden Nächten); Bund ab dem Übernahmetag (niemand dient, eine Zeile „Ab heute baut der Bund …“, die Kaserne bestellt der Bund in der nächsten Nacht, einberufen wird erst ab ihrer Eröffnung). Ohne Sicherheit und Bund liefe die Stadt danach genau wie in Version 6 (so prüft es `--migrationstest`). Alle älteren Versionen bekommen dasselbe über die Kette. Von 5: Schritt 2 gilt ab dem Übernahmetag, niemand besitzt schon eine Wohnung, Beitragsjahre für alle aus dem Alter, Summen und „gestern“ der Stadtregierung bleiben (fehlt dort eine Summe, wird der Stand abgelehnt), Kitas mit Übergangsfrist. Von 2: Bauhof = Werkstatt der Stadt vom Start, laufende Baustellen bekommen 4 Arbeitstage je Resttag (höchstens so viele wie der ganze Bau). Von 3: Tech-Firmen entstehen danach von selbst, niemand hat schon ein Gerät. Von 2, 3 und 4: Die Stadtregierung mit Schritt 2 gilt ab dem Übernahmetag (Rentenstufen von da an, Stadtbuch „Ab heute regiert die AfD …“ mit Mieterkauf, Rente, Kitas und Frist, im Fenster „seit Tag X, Spielstand übernommen“), niemand bezieht schon Grundsicherung. Alles andere bleibt. Ein Import einer alten Datei rechnet ohne Nachfrage um | **Abweichung von der Spec** (dort nur Export oder Neu), Noahs Entscheidung B: sonst wäre seine Stadt weg |
| 61 | Theke und Träger sind nur zum Anschauen. Wer heute trägt, ergibt sich aus Tag und Laden (reihum), nicht aus Zufall. Der Lieferant ist die Werkstatt, die gestern die meisten Kisten brachte | Die Kisten werden um Mitternacht in einem Schritt verteilt; die Träger zeigen das tagsüber |
| 62 | Die 120 Arbeitsplätze unter den Figuren werden um 8 Uhr nach Nähe zur Kamera vergeben (beim Öffnen mitten am Tag sofort) und bleiben bis zum nächsten Morgen | Alle Arbeitenden wären bei 5.000 Einwohnern über 2.000 Figuren. Fest statt kameraabhängig, damit keine Figur beim Drehen springt |
| 63 | Stadtbuch: fertige Bauten eines Abends in einer Zeile („Der Bauhof hat fertig gebaut: …“), Stillstand, wenn auf einer Baustelle 5 Tage niemand war, und wenn der Bauhof-Lohn über 100, 110 oder 120 steigt | Mit Tech-Firmen kamen die neuen Versionen dazu (damals im Schnitt 0,48 Zeilen am Tag: auf 40 Seeds 5,50 Zeilen am Tag, 7 Seeds über 6,5, höchstens 8,60; das war vor der Zuzug-Regel). Heute gemessen (Seeds 1–80, 730 Tage): vor der Stadtregierung 4,11 Zeilen am Tag (höchstens 5,47), davon Bauhof 0,24 und Tech 0,50; mit der Stadtregierung 4,31 (höchstens 5,80), Bauhof 0,25, Tech 0,55. Die Stadtregierung schreibt selbst 3 Zeilen je Stadt (Tag 0 und die beiden Rentenstufen), den Rest macht die größere Stadt. Die Plan-Grenze von 6,5 Zeilen am Tag hält auf allen 160 Seeds |
| 64 | Tech-Firma statt Werkstatt gründet, wer Fleiß + Ehrgeiz ≥ 120 hat, solange die Tech-Stellen danach höchstens 40 % der Umland-Stellen sind (Werkstätten plus Tech) und das Geld reicht (Bau 2.000 + Startkasse 300, leere Tech-Firma übernehmen 1.100). Fehlt ein Laden, wird wie bisher ein Laden gegründet. Ob es sich lohnt, prüft wie bei der Werkstatt der Umlandpreis; die Tech-Stellen zählen dort mit. Produkt: das in der Stadt seltenste. Firmenname aus 30 Marken (Seed-Zufall), Versionen heißen „Marke Nummer“ | Noahs Entscheidung: eine Betriebsart über die vorhandene Aktion, keine neue Aktion. Ohne Obergrenze würden Tech-Firmen die Werkstätten verdrängen (beide teilen sich das Umland). Gemessen (Seeds 1–80, Tag 730): vor der Stadtregierung 23,9 Gründungen je Stadt, Anteil an den Umland-Stellen im Mittel 25,0 % (höchstens 39 %); mit der Stadtregierung 27,4 und 29,3 % (höchstens 39,6 %), weil mehr Leute genug Erspartes haben. Seeds 1/2/3 (`--gate`): 29/46/21 gegründet, Anteil 33,8/33,8/23,4 % (vorher 17/26/26 und 21,6/27,5/25,1 %) |
| 65 | Tech-Firma: 4 Stellen je Stufe, Lohn 105 (90–110 % je nach Sparsamkeit des Besitzers), laufende Kosten 45 am Tag. Einnahmen: anwesende Angestellte × Umlandpreis (derselbe Topf von 50.000 wie bei den Werkstätten) plus 80 % der Verkäufe in der Stadt | Das Umland als gemeinsame Grenze hält das Wachstum im Rahmen |
| 66 | Käufe beim täglichen Einkauf: nur wer heute eingekauft hat und danach über 600 Taler hat. Erst ein Gerät (Fleißige ab 60 wollen einen Computer, alle anderen ein Handy; gibt es das nicht, das andere; nach 120 Tagen ein neues), mit Gerät alle 40 Tage Software, dazwischen mindestens 20 Tage. Preise 180 (Handy), 320 (Computer), 60 (Software). Chance am Tag 4 % × (1,3 − Sparsamkeit/100), doppelt so hoch, wenn die Version höchstens 15 Tage alt ist. 20 % behält der Laden, 80 % bekommt die Firma. Freizeit sofort +12 / +15 / +6, keine Dauerwirkung | Noahs Entscheidung „auch die Leute in der Stadt kaufen“, ohne neue Aktion. Im Entwurf hob eine Dauerwirkung am Abend die Zufriedenheit und damit den Zuzug; sie ist wieder raus |
| 67 | Anbau: Läuft eine Tech-Firma gut (alle Stellen besetzt, 20 Tage in Folge Gewinn), gehen 50 % des Gewinns über dem Polster in eine Rücklage, bis der Anbau bezahlt ist (Stufe 2: 1.800, Stufe 3: 3.000). Den Auftrag an den Bauhof gibt sie erst, wenn das Umland Platz hat (dieselbe Grenze wie für eine neue Werkstatt) und mindestens 4 Leute Arbeit suchen. Der Bauhof baut 12 bzw. 16 Arbeitstage, danach 8 bzw. 12 Stellen. Schließt die Firma, bekommt der Besitzer die Rücklage | Noahs Entscheidung „Bauauftrag an den Bauhof“. Ohne die Umland-Grenze schuf jeder Anbau Stellen über das Gleichgewicht hinaus |
| 68 | Echte Code-Stücke: eine Hauptfigur, die gerade (9–16 Uhr) in ihrer Tech-Firma arbeitet, schreibt höchstens einmal je Spieltag. Nicht bei 20×, nicht ohne Ollama, immer nur ein Aufruf gleichzeitig; die Stadt wartet nicht. Antwort `{"titel", "sprache", "code", "gedanke"}`; der Code wird gekürzt (höchstens 20 Zeilen zu 100 Zeichen, 1.500 Zeichen), nur als Text angezeigt und nie ausgeführt. Wer heute schon Code geschrieben hat, merkt sich die Seite nur bis zum Neuladen | Noahs Entscheidung „beides“. Der Code ist Ausdruck der Figur, er wirkt nicht auf die Simulation |
| 69 | Stadtbuch: Gründung einer Tech-Firma (mit Fleiß und Ehrgeiz), alle neuen Versionen eines Tages in einer Zeile (erscheinen zwei vom selben Produkt am selben Tag, liegt nur die der ersten Firma im Regal; die andere steht als „am selben Tag fertig, aber nicht im Regal“ dabei), Bauaufträge für Anbauten, fertige Anbauten in der Fertig-Zeile des Bauhofs | Sonst füllten die Versionen das Stadtbuch |
| 70 | Die Karte beginnt mit 56 × 56 Feldern und wächst ringsum um 4 Felder (einen Block), sobald eine Straße oder ein Gelände näher als 16 Felder am erlaubten Rand liegt (18 bis zum Rand der Karte, so nennen es Fenster und Stadtbuch), höchstens bis 256 × 256. Die Prüfung läuft vor jeder Straßenverlängerung, nach dem Bauamt, nach jedem Gelände und am Tagesende | Noahs Entscheidung „Karte wächst wirklich“. Die Werte sind so gewählt, dass man das Wachsen im normalen Spiel sieht (Seeds 1–3: 3-, 6- und 3-mal in 730 Tagen) und die Grenze nie eine Straße aufhält (Abschnitt „Stadt erweitern“). 256: Gebäude speichern ihre Lage als `Uint8` |
| 71 | Stufen nach allen Einwohnern: Dorf, Kleinstadt ab 40, Stadt ab 160, Großstadt ab 800 = BBSR-Schwellen (5.000, 20.000, 100.000) geteilt durch 125; kein Abstieg | Spielmaßstab: Die Städte erreichen im Mittel gut 1.100 Einwohner, so kommt jede Stufe in den ersten 400 Tagen. Das BBSR zählt auch die zentralörtliche Funktion, die Stadt nicht. Kein Abstieg, weil die Einwohner um bis zu 15 % schwanken (Gate 4) |
| 72 | Stadtteile: Ringe aus 12 Feldern um die Mitte mal vier Himmelsrichtungen, Namen aus einer festen Liste (44) in der Reihenfolge des ersten Gebäudes, ab der Kleinstadt | Nur aus der Lage, damit niemand nach seinem Stadtteil behandelt wird (Grenze der Stadtregierung). Die Grenzen liegen auf Rasterlinien, also nie mitten durch ein Haus |
| 73 | Die Landschaft liegt relativ zum Kartenrand: Versatz V = halbe Kartengröße − 48, Kamera-Abstand bis 160 + 2V, Nebel 70 + V bis 190 + 2V, Blickpunkt höchstens halbe Karte + 12 von der Mitte. Auf der Startkarte also enger als in Version 6 (Abstand bis 120, Nebel 50–150) | Bei 96 wie bisher. Die Stadt bleibt beim Wachsen an ihrem Platz, die Grenzen werden nur weiter |
| 74 | Stadtteilnamen auf der Karte nur weit herausgezoomt (Kameraabstand ab 35, wie die Straßennamen mit 2 Einheiten Spielraum), erst wenn kein Straßenname mehr zu sehen ist, höchstens 12 | Nie beide zugleich (Befund 9 der Gegenprüfung). Mehr als 12 Schilder überdecken die Stadt |
| 75 | Kriminalität, Polizei, Gericht und Gefängnis: Annahmen S-A1 bis S-A28 im Abschnitt „Sicherheit“ (Tatneigung, Kalibrierung an der PKS 2024, Aufklärung, Strafmaß, Register, Haft, Obhut für Kinder, Wache und Anstalt des Landes, Gefangene von außerhalb nur als Zahl) | Noahs Entscheidungen „Kriminalität als Regel“ und „Anstalt für die Region“; Quellen dort |
| 76 | Kaserne, Wehrpflicht und Nachrichtendienst: Annahmen B1 bis B20 im Abschnitt „Bund“ (Stufen, Gelände, Stellen, Lohn und Sold vom Bund, Dauer, Anteil Ersatzdienst aus einem festen Wert je Person, Bindung der Soldaten auf Zeit, Ersatzdienst im Bauhof ohne Kisten und außerhalb der 40, Wohnen zu Hause, Nachrichtendienst nur als Arbeitgeber, Aussehen) | Noahs Entscheidungen „Militär = alles“ und „Wehrpflicht für alle 18-Jährigen“ (zwei Abweichungen markiert); Quellen dort |
| 77 | Antworten des Sprachmodells werden verworfen (wie ungültiges JSON), wenn ein Satz ein Wort einer Tat (TAT: verdächtig, gestohlen, stehlen, stiehlt, stahl, klaut, geklaut, Einbrecher, eingebrochen, Dieb, Täter, Raub, kriminell, Verbrecher, Betrüger …) oder des Verdachts (VERDACHT: war es, betrogen, schuld …; beim Opfer auch OPFER: vermute, steckt dahinter, mein … genommen) mit einem Wort zu Herkunft, Religion oder Sprache verbindet (HERKUNFT, auch „fremd“, „deutsch“, „mit … Namen“), bei Opfern auch mit einem Vor- oder Nachnamen aus den festen Namenslisten der Stadt außer dem eigenen, bei allen anderen Figuren mit einem solchen Namen, wenn der Satz ein Wort aus TAT enthält. Nachnamen, die auch gewöhnliche Wörter sind (Richter, Koch, Winter, Klein …), zählen nur nach einem Vornamen oder „Herr“, „Frau“, „Familie“. Geprüft wird je Satz, nicht je Komma. Die Anweisung sagt „du beurteilst andere nur nach dem, was du mit ihnen erlebt hast“ statt Merkmale aufzuzählen | Befund X6 der Schlussprüfung und N2 der Nachprüfung: Die Anweisung allein hält ein Modell nicht auf. Wortlisten sind grob: Sie verwerfen auch harmlose Sätze („Ich wurde bestohlen, Lea hat mich getröstet“ in einem Satz; bei Figuren, die kein Opfer sind, auch „Mein Freund Elias wurde bestohlen“) und fangen Umschreibungen und einen Nachnamen allein, der auch ein Wort ist („Koch war es“), nicht. Das Komma trennt bewusst nicht: sonst ginge „Es war Elias Müller, der mich bestohlen hat“ durch. Die Listen dienen nur der Prüfung von Texten, keine Regel der Stadt liest sie. Die Wirkung an einem echten Modell ist nicht gemessen |
| 78 | Ein Block (Wache, Dienststelle) findet auch Platz, wo eine Straße an der Rasterlinie zwischen zwei freien Blöcken endet: Suche im Rahmen von zwei Blöcken, das Tor auf der Rasterlinie an der Straßenspitze, belegt werden 3 × 3 Felder um das Tor. In einer Nacht baut zuerst das Land (Wache, dann Anstalt), dann der Bund (Kaserne, Dienststelle) | Befund B1 der Schlussprüfung. Vorher bestellte das Land nach einer Übernahme die Wache bis 18 Nächte später als Anstalt und Kaserne, auf Seed 3 wartete die Dienststelle 99 Nächte. Die Straße kann auf dieser Linie nicht weiterwachsen (wie bei den großen Geländen). Nebenwirkung (Nachprüfung, N1): Gibt es nach einer Übernahme nur zwei solche Stellen, wartet jetzt die Kaserne statt der Wache (Seed 2: 4 bis 67 Nächte, Seed 8 an Tag 200: 7). So entschieden, weil die Wache zur Stufe Kleinstadt gehört und in einer Stadt, die mit Version 7 wächst, immer vor Anstalt und Kaserne steht (Seeds 1–80: Wache im Mittel ab Tag 73, Kaserne offen ab Tag 191); Taten gibt es ab dem Übernahmetag. Die umgekehrte Reihenfolge verschiebt nur, wer wartet (offene Frage an Noah) |

## Bekannte Schwächen

**Version 8 (Tech-Firmen und Autos):** siehe „Bekannte Schwächen (Version 8)“ im Abschnitt „Tech-Firmen und Autos“: weniger Pendler mit dem
Auto als in Deutschland (43 % gegen 65 %), Gate 4 hängt am Geld der ersten Monate (ohne die Regel für Betriebssparer 74 von 80), leere Werke,
die Autos auf der Straße zeichnet erst Teil 2.

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

**Stadt erweitern: Die Karte wächst ringsum.** Kommt die Stadt nur im Osten an den Rand, wächst die Karte trotzdem auf allen vier
Seiten (Seed 2 wächst sechsmal, jedes Mal wegen des Ostens). Einfacher und für die Grenze gleichwertig. Die Landschaft rückt dabei
überall nach außen, und ein Streifen Felder wird ohne Übergang zur Wiese der Karte. Wächst die Karte, während man hinschaut, springen
die Felder am Rand. Die Stadt selbst, Figuren und Kamera bleiben, wo sie sind (`tests/erweiterung.cjs`, auch mitten am Tag).

**Stadt erweitern: Am Handy quer ist die Stufe nicht zu sehen.** Bis 500 px Höhe fehlt in den Zahlen der Platz. Die Stufe steht dort
nur für Screenreader hinter „Einwohner“, sichtbar im Stadtbuch und im Fenster „Stadtregierung“. Hochkant und breit sind die Zahlen
eine Zeile höher als in Version 6.

**Stadt erweitern: Gate 4 prüft die Kartengrenze nur noch auf der alten Karte sinnvoll.** Auf der wachsenden Karte hat die Stadt immer
mindestens 16 Felder Platz, der Teil hält immer (Annahme 27). Was er früher maß, druckt `--gate` als Abstand zur alten Baugrenze 96.

**Stadt erweitern: Gelände in der Mitte brauchen oft eine neue Straße.** `gelaendeSuchen` findet nur ganz freie Blöcke an einer
Straße. Häuser säumen die Straßen, deshalb gibt es solche Blöcke erst, wenn das Bauamt eine Straße verlängert. Im Test (Seed 2, Tag 300,
1 × 1 Block) fand sich 10 Tage lang keiner. Vor der äußersten Straße ist Platz. Seit der Schlussprüfung auch vor einem Straßenende, das
auf die Rasterlinie zwischen zwei freien Blöcken zuläuft: Ein Block sucht dann im Rahmen von zwei Blöcken (Annahme 78). Damit wartet die
Dienststelle nicht mehr 99 Nächte (Seed 3, jetzt 0), und nach einer Übernahme bestellt das Land die Wache in der ersten Nacht. Die Kaserne
(3 × 2 Blöcke) wartet dafür nach manchen Übernahmen: Die Wache nimmt eine der Stellen an einem Straßenende, die Anstalt die andere
(Nachprüfung, N1). Übernahmen der Seeds 1–8 an Tag 200, 230, 260 und 330 (32 Fälle, `nb/mess/b1_warten.mjs`): Wache und Anstalt werden
in allen 32 Fällen in der ersten Nacht bestellt, die Kaserne in 27; auf Seed 2 erst in Nacht 14, 4, 15 und 67 (vorher je in Nacht 1), auf
Seed 8 an Tag 200 in Nacht 7. Auf Seed 2 an Tag 330 kommt dadurch auch die Dienststelle später (Nacht 90 statt 72). `tests/p6migration.cjs` zeigt den Fall
Seed 2, Tag 260 im Browser (Kaserne in Nacht 15, bis dahin sagt das Fenster „kommt, sobald ein Platz frei ist“).

**Stadt erweitern: Großstadt ab 800 Einwohnern.** Der Maßstab 125 macht aus 800 Leuten eine Großstadt. Das ist ein Spielmaßstab (Annahme
71); das Stadtbuch nennt ihn bei jedem Aufstieg.

**Stadt erweitern: Stadtteilnamen nur mit Software-Grafik geprüft.** Lage, Abstand zu Panels, nie zugleich mit Straßennamen und
reduzierte Bewegung sind im Container (SwiftShader) getestet. Seit der Schlussprüfung verblassen die Namen mit dem Nebel an ihrer Stelle
(ganz im Nebel stehen sie nicht mehr da) und haben nachts (18 bis 7 Uhr) einen leisen Grund wie die Straßennamen. Auf echten Geräten ist die Lesbarkeit über hellen Dächern bei Tag nicht
angesehen. Die Schilder dürfen über niedrigen Häusern liegen, wie die Straßennamen.

**Stadt erweitern: Größte Karte 256 × 256.** Gebäude speichern ihre Lage als `Uint8`. Wächst eine Stadt so weit, hält der Rand sie wie
früher auf. Gemessen ist das nicht: Die größte Stadt (`umland=300000`, 750 Tage, 5.920 Einwohner) kommt auf 120 × 120.

**Sicherheit: In der Stadt sitzen wenige in Haft.** Im Mittel 0,24 von gut 1.000 Einwohnern (Seeds 1–80, Tag 366–730), höchstens 6
zugleich; in Deutschland sind es 0,69 je 1.000. Die Stadt kennt nur Diebstahl, Wohnungseinbruch und Betrug und rechnet Haft in ganzen
Spieltagen. Die Anstalt ist deshalb vor allem mit Gefangenen von außerhalb belegt, die es nur als Zahl gibt (Noahs Entscheidung).

**Sicherheit: Kein Dunkelfeld, keine Irrtümer.** Jede Tat wird angezeigt, und wer ermittelt wird, war es (S-A22, S-A23). Freisprüche,
Einstellungen außer bei Tod oder Wegzug, Ratenzahlung und freie Arbeit statt Ersatzfreiheitsstrafe gibt es nicht. Die
Ersatzfreiheitsstrafe wird auf ganze Spieltage aufgerundet: 15 echte Tage werden 36,5.

**Sicherheit: Die Wache wartete auf einen freien Block** (behoben mit der Schlussprüfung, Befund B1). In einer dichten Stadt fand
`gelaendeSuchen(S, 1, 1, false)` erst dann einen ganzen Block nah an der Mitte, wenn das Bauamt eine Straße verlängert. Nach einer Übernahme
von Version 6 dauerte das 1 bis 54 Tage; so lange kam die Polizei aus dem Nachbarort. Jetzt sucht ein Block auch im Rahmen von zwei Blöcken:
Nach der Übernahme der Seeds 1–6 an Tag 260 bestellt das Land die Wache in der ersten Nacht (vorher auf Seed 3, 4, 5 erst 6, 11 und 17
Nächte später, auf Seed 2 nicht in 30 Nächten; `befunde/wache_mig.mjs`). In neuen Städten steht die Wache im Mittel an Tag 73 wie vorher.
Dafür wartet auf Seed 2 (und Seed 8 an Tag 200) die Kaserne (oben, „Gelände in der Mitte“).

**Sicherheit: Gefangene sieht man selten.** Nur zu den Hofzeiten ihrer Abteilung (je zwei Stunden am Tag) und nur die Gefangenen aus
der Stadt; meist sitzt niemand aus der Stadt in Haft. Die Höfe sind dann leer, obwohl die Anstalt als Zahl voll belegt ist.

**Sicherheit: Die Figuren der Polizei gehen um 10 Uhr zum Tatort, nicht in der Nacht.** Die Tat geschieht nachts ohne Figur; am Morgen
nimmt die Polizei die Anzeige auf. Wer eine Tat begangen hat, steht nur auf der eigenen Personenkarte (Verfahren, Haft), nie mit Namen
im Stadtbuch.

**Sicherheit: Mit Kriminalität ziehen mehr Leute weg.** Über 80 Seeds ziehen in 730 Tagen im Mittel 62,9 statt 40,2 Menschen weg (+56 %),
fast alle im ersten Jahr. Wer gerade Opfer war oder aus der Haft kommt, hat in der jungen Stadt oft zu wenig Geld und entscheidet nach dem
Ereignis neu (Abschnitt „Sicherheit“, Gemessen). Die Gates halten, Zuzug und Stellen des Landes gleichen es aus; ob Opfer so oft gehen
sollen, ist eine offene Frage an Noah (dann Folgen für Opfer, S-A18, schwächer machen und neu messen).

**Sicherheit: Frauen und Männer in derselben Abteilung.** In Wirklichkeit sind sie getrennt untergebracht (§ 140 Abs. 2 StVollzG des Bundes,
heute Landesrecht, nicht einzeln geprüft; § 3 Abs. 1 UVollzG NRW). Die Stadt trennt nicht, weil keine Regel das Geschlecht liest; das Fenster sagt es bei S7.

**Sicherheit: Viele Ersatzfreiheitsstrafen.** Etwa jede siebte Geldstrafe endet als Ersatzfreiheitsstrafe: auf dem Endstand über die Seeds
1–80 (730 Tage) 8.767 von 59.204 = 14,8 %, je Stadt im Mittel 110 von 740, einzeln 9,5 bis 25,2 % (Median 14,4 %; `befunde/mess/mess10.mjs`,
Befund X15 der Schlussprüfung). Auf den Seeds 1–6 allein sind es 18,1 % (Gegenprüfung), die Streuung ist groß. In der jungen Stadt mehr, weil
viele wenig Erspartes haben. Ratenzahlung (§ 42 StGB) und freie Arbeit statt Haft (Art. 293 EGStGB) gibt es
in der Stadt nicht, obwohl sie in Wirklichkeit viele Ersatzfreiheitsstrafen verhindern.

**Bund: Die Dienststelle wartete in dichten Städten lange** (für einen Block behoben mit der Schlussprüfung). Der Bund baut nur auf ganz
freien Blöcken an einer Straße und legt keine Zufahrt an (B17). Auf Seed 3 wartete die Dienststelle 99 Nächte (Großstadt ab Tag 327, offen
ab Tag 432), über 160 Seeds öffnete sie zwischen Tag 314 und 685. Jetzt sucht ein Block auch im Rahmen von zwei Blöcken (Annahme 78): Seed 3
öffnet an Tag 333, die Seeds 1–80 zwischen Tag 313 und 395 (Mittel 342 statt 369). `--militaer` prüft weiter, dass der Bund nur ohne Gelände
wartet; Stadtbuch und Fenster sagen, dass er sucht. Die Kaserne kann nach einer Übernahme warten (oben), auf Seed 2 an Tag 330 dann
auch die Dienststelle (Nacht 90 statt 72).

**Bund: Wehrdienst senkt die Tatneigung der Jungen nicht.** 18- bis 24-Jährige werden 1,51-mal so oft verurteilt wie alle (Teil 2: 1,40).
Der Dienst dauert 5 Spieltage mit 60 Taler Sold, danach suchen sie Arbeit wie vorher. Die Taten liegen mit dem Bund bei 32,8 je 1.000
Einwohner und Jahr (Ziel 32,1); neu kalibriert ist nichts (offene Frage im Abschnitt „Bund“).

**Bund: Gerechtigkeit nur vereinfacht.** Keine Musterung, alle gelten als tauglich; die Gewissensentscheidung ersetzt ein fester Wert je
Person; wer in Haft kommt, beendet den Dienst; Wehrdienstleistende wohnen zu Hause; das Alter spielt beim Anstellen keine Rolle (B21). Frauen und Nicht-Deutsche werden einberufen,
anders als nach Gesetz und Programm (beides im Fenster als Abweichung markiert).

**Bund: Die Karte springt mit der Kaserne.** Das Gelände von 3 × 2 Blöcken am Rand lässt die Karte in der Nacht der Bestellung oft um
mehrere Ringe wachsen (Seed 2: 56 → 80, Seed 1: 72 → 96), zusammen mit der Anstalt des Landes. Die Stadt selbst ändert sich dabei nicht
(Teil 1), die Landschaft rückt aber sichtbar weiter nach außen.

**Bund: Radome, Mast und Fahrzeuge nur mit Software-Grafik angesehen.** Das Bund-Mesh ist beidseitig beleuchtet (DoubleSide dreht die
Normale); auf echter Grafikhardware ist das Aussehen nicht geprüft.

**Sprachmodell: Die Prüfung gegen Verdacht arbeitet mit Wortlisten** (Annahme 77, Schlussprüfung, Nachprüfung N2). Sie verwirft auch
harmlose Sätze eines Opfers, wenn im selben Satz ein Name und ein Wort wie „bestohlen“ stehen („Ich wurde bestohlen, aber Lea hat mir
geholfen.“; das Komma trennt bewusst nicht), bei anderen Figuren einen Namen mit einem Wort einer Tat („Mein Freund Elias wurde
bestohlen“), und sie fängt Umschreibungen nicht („der Nachbar von gegenüber …“, „Koch war es“ mit dem Nachnamen allein, andere
Nationalitäten als die in der Liste). Verworfen heißt: Die Figur entscheidet mit dem normalen Gehirn, ein Gespräch
zeigt „Die Antwort war nicht zu verstehen“. Geprüft ist das nur mit festen Sätzen in `--kitest`; ob ein echtes Modell mit dem neuen,
neutralen Satz („beurteilst andere nur nach dem, was du mit ihnen erlebt hast“) seltener Verdacht äußert, ist nicht gemessen.

**Aufholen in Stücken ergibt eine andere Stadt.** 3 × 30 Tage aufgeholt ist nicht dieselbe Stadt wie 1 × 90 (Bedienprüfung: 63 statt 54
Einwohner; in bc7247a 49 statt 47). Das ist so gebaut: Aufholen rechnet ganze Tage im Tagesschritt (Annahme 43) und nur die Stunden bis
Mitternacht und nach Mitternacht stündlich; drei Stücke haben drei solche Übergänge. Nicht geändert.

**Das Fenster „Stadtregierung“ ist lang.** Mit Teil 1 bis 3 hat es doppelt so viele Karten wie in bc7247a (Bedienprüfung: 30 statt 15,
am 360er-Handy etwa 25.000 px). Seit der Schlussprüfung führen Sprunglinks oben zu jeder Gruppe; die Gruppen selbst lassen sich nicht
einklappen, die neuen stehen weiter am Ende.

**Leertaste auf einem Tempo-Knopf.** Nach einem Mausklick (oder Tippen) auf ein Tempo ist die Leertaste Pause und weiter; wer den Knopf
mit Tab ansteuert, drückt ihn mit der Leertaste. Wer erst klickt und dann ohne Tab die Leertaste als Knopfdruck erwartet, bekommt die Pause.
