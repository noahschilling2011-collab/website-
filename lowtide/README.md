# LOWTIDE

Open-World-Crime-Prototyp in Three.js. Solvara, Port Mercy, Eli Voss und Mara Quinn.
Eigene IP — keine fremden Assets, Modelle, Texturen, Sounds oder Marken.

## Aufbau

Der Spielcode liegt als normale ES-Module in `src/`. `build.mjs` bettet sie
base64-kodiert in `shell.html` ein und schreibt eine einzelne, komplett
eigenständige `LOWTIDE.html` — kein Server, kein CDN, kein Build-Tool nötig,
um sie zu spielen. Doppelklick genügt.

```
src/
  game.js           Einstiegspunkt: DOM, Eingabe, HUD, Dialoge, Karte
  simulation.js     Basis-Simulation ohne WebGL und DOM
  campaign.js       Kampagne, Fahrzeugphysik, Polizei, Aktivitäten
  world.js          Renderer, Basisgeometrie, Kamera, Licht
  expanded-world.js Erweiterte Welt: Gelände, Regionen, Fahrzeugmodelle
  sky.js            Sonnenstand, Himmelskuppel, Nebel, Belichtung
  water.js          Wellen, Spiegelung, Brandung, Sumpf
  street.js         Bordsteine, Laternen, Ampeln, Möblierung, Strand
  facades.js        Sockelgeschosse, Läden, Fensterlaibungen, Dachaufbauten
  regions.js        Vororte, Farm, Nationalpark, Sumpf, Flugfeld, Insel,
                    Industrie, Baulücken, Süd- und Nordflächen
  interiors.js      Begehbare Innenräume der acht Serviceorte
  radio.js          Prozedural erzeugte Radiosender
  lod.js            Grobe Silhouetten für ferne Figuren und Fahrzeuge
  wildlife.js       Möwen, Fische, Delfine, Alligatoren
  story.js          Akt 3 bis 5 der Kampagne
  post.js           Überstrahlen, Verdeckung, Farbkurve, Korn
  detail.js         Oberflächenstruktur aus der Weltposition
  grass.js          Bewuchs im Ring um den Spieler
  foliage.js        Baumkronen als gekreuzte Flächen mit Alphakarte
  bake.js           Backt ein Vorbild nach Material zu einer Geometrie
  art-direction.js  Materialien, Fahrzeug- und Figurenaufbau
  human-model.js    Anatomische Figurenmodelle, Gang und Ruhebewegung
  content.js        Weltdaten: Orte, Regionen, Fahrzeugtypen, Waffen
  navigation.js     A* auf Gitter für Polizei und Wachen
  vendor/           Three.js r185 (MIT), unverändert
```

## Bauen

```
node build.mjs                                   # schreibt LOWTIDE.html
node --experimental-vm-modules tools/check.mjs   # Syntax aller Module
node tools/smoke.mjs                             # Start, Konsolenfehler, Bilder
node tools/blicke.mjs --orte kreuzung --hours 22 # Vergleichsbild an einem Ort
node tools/messung.mjs                           # Draw Calls und Dreiecke
node tools/luftbild.mjs                          # Luftbilder über die Karte
node tools/regression.mjs                        # 153 Prüfungen, muss grün sein
node tools/abdeckung.mjs                         # Bauteile je 100-Meter-Zelle
node tools/wolken.mjs                            # wandert der Wolkenschatten
node tools/spiegelung.mjs                        # spiegelt Wasser die Stadt
node tools/statistik.mjs                         # Sättigung und örtlicher Kontrast
```

Die drei Werkzeuge in `tools/` mit Browser brauchen Playwright und Chromium.
Ohne die beiden lässt sich `LOWTIDE.html` trotzdem bauen und öffnen.

Zur Bildrate: diese Werkzeuge laufen hier gegen einen Software-Rasterizer.
Die dort gemessenen fps sagen nichts über echte Hardware. Aussagekräftig sind
Draw Calls und Dreiecke aus `messung.mjs` — die sind hardwareunabhängig.

## Debug

`window.LOWTIDE` gibt im Browser Zugriff auf `sim`, `world` und den Frame-Zähler.
F3 blendet die Messwerte ein: FPS, Draw Calls, Dreiecke, NPCs, Fahrzeuge.

Zum Prüfen von außen:

```js
LOWTIDE.sim.hour = 22                       // Tageszeit setzen
LOWTIDE.sim.weather = 'storm'               // clear | rain | fog | storm
LOWTIDE.view(x, z, gier, neigung)           // Figur und Kamera versetzen
LOWTIDE.luftbild(x, y, z, zx, zy, zz)       // freie Kamera für Luftbilder
LOWTIDE.radio.waehle(3)                     // Radiosender setzen
```

## Bild

Die Szene geht nicht mehr direkt auf den Bildschirm, sondern durch `post.js`:
Szene in ein Ziel, heller Anteil in ein halbes Ziel, Umgebungsverdeckung aus
der Tiefe desselben Durchgangs, am Ende zusammensetzen, tonwerten, graden,
Randabdunklung und Korn. Der Renderer selbst tonwertet dabei nicht mehr —
sonst würde zweimal komprimiert.

Nasser Asphalt spiegelt nicht nur den Himmel: `post.js` marschiert für
waagerechte Flächen einen Strahl durch dieselbe Tiefe, die schon die
Verdeckung nutzt, und holt die Neonschilder und Laternen aus dem Bild selbst.
Auf einer waagerechten Fläche wird dabei nicht die aus den Ableitungen
gewonnene Normale benutzt, sondern Weltoben — die gerechnete rauscht auf einer
großen Ebene, und das Ergebnis waren Flecken statt der Streifen, die nasser
Asphalt tatsächlich zeigt.

**Das Wasser hängt seit Kurzem im selben Durchgang.** Vorher spiegelte es nur
den Himmel, analytisch aus zwei Farben — in einer Hafenstadt steht damit die
halbe Skyline neben einer Fläche, die von ihr nichts weiß. Erkannt wird
Wasser an einer Marke im Alphakanal des Szenenziels: `water.js` schreibt dort
0,5, undurchsichtige Flächen schreiben 1,0, gelöscht wird auf 0,0. Über die
Höhe ginge es nicht — Kai, Strand und Uferstraße liegen ebenfalls fast auf
null. Auf Wasser bleibt mehr von der gerechneten Normale stehen als auf
Asphalt: dort ist die Störung keine Rauschquelle, sondern der Wellengang, und
ohne sie stünde die Skyline gestochen scharf im Hafenbecken.

Gemessen mit `tools/spiegelung.mjs`, das die Deckung im Spiegelziel auszählt:

| Blick | Wetter | Wasser im Bild | gespiegelt |
|---|---|---|---|
| Küste | klar | 68,6 % | 15,5 % |
| Strand | klar | 9,8 % | 4,7 % |
| Innenstadt | klar | 0,1 % | 0,0 % |
| Innenstadt | Regen | 0,1 % | 19,0 % |

Der erste Messversuch stand an der Hafenmessstelle aus `messung.mjs` und
meldete null — dort ist gar kein Wasser im Bild. Die Stelle war falsch, nicht
der Shader. Dass gespiegelte Fläche deutlich kleiner ist als Wasserfläche,
gehört dazu: der Strahlmarsch kommt aus dreißig Schritten rund hundert Meter
weit, und was aus dem Bild läuft, gibt es nicht.

`detail.js` hängt sich über `onBeforeCompile` in jedes Weltmaterial und legt
Farbflecken, Rauheitsschwankung und eine Normalenstörung darüber, dreifach
aus der Weltposition projiziert. Eine Textur ginge nicht: dieselbe
Kistengeometrie trägt eine 240-m-Platte und einen 20-cm-Poller.

Die kleinste Struktur war lange 0,74 m — aus zwei Metern Abstand ist das eine
glatte Fläche. Beziffern lässt sich das über den örtlichen Kontrast, den
mittleren Betrag der Helligkeitsdifferenz zu den Nachbarn zwei Bildpunkte
weiter — `tools/statistik.mjs` misst ihn: auf Straßenhöhe 6,45 von 255,
während ein Foto beim Doppelten bis Vierfachen liegt. Dazugekommen ist deshalb eine Oktave bei rund neun
Zentimetern, die bis 26 m läuft und dort ausgeblendet wird — mit eigenem
Relief, sonst schwankt die Farbe, aber das Licht wandert nicht.

| Blick | Kontrast vorher | nachher |
|---|---|---|
| Innenstadt 13 Uhr | 6,45 | 9,26 |
| Strand 13 Uhr | 6,99 | 10,12 |
| Küste 13 Uhr (fast nur Wasser) | 8,21 | 8,37 |
| Skyline aus 300 m | 17,84 | 17,84 |

Die letzten beiden Zeilen gehören dazu: Wasser hat seinen eigenen Shader, und
jenseits von 26 m ist das Korn aus. Wo es nicht wirken soll, wirkt es nicht.

Der Maßstab ist gemessen, nicht geschätzt. Bei einer Periode von 6,7 statt 9
Zentimetern steigt der Kontrast auf 23,3 — und die mittlere Helligkeit fällt
von 103 auf 87. Eine zu stark gestörte Normale kippt im Mittel von der Sonne
weg und frisst Licht. Kontrast allein ist deshalb kein Ziel.

Der Knopf „Grafik: sparsam" schaltet Nachbearbeitung, Schatten und
Pixelverhältnis zusammen ab.

## Grün

Bäume waren gestapelte Quader, drei bis vier übereinander. Aus zweihundert
Metern geht das durch, aus zwanzig sieht ein Wald damit aus wie ein Regal.

`foliage.js` setzt je Krone drei gekreuzte Flächen mit einer Alphakarte, die
zur Laufzeit auf ein Canvas gezeichnet wird: 260 gestreute Ellipsen, dichter
zur Mitte, ausgefranst am Rand. Es wird kein Bild geladen, die HTML bleibt
eigenständig. Der Wind steht im Vertexshader und bewegt nur die Krone, der
Stamm bleibt stehen. Rund dreitausend Bäume liegen am Ende in zwei
InstancedMeshes für die ganze Karte.

Zwei der drei Fehler dabei waren Wiederholungen aus dem Bewuchs: Kronen ohne
`color`-Attribut werden bei `vertexColors` schwarz gelesen, und eine
senkrechte Fläche mit waagerechter Normale bekommt von der Mittagssonne
keinen Diffusanteil. Der dritte war neu und der eigentliche Grund für die
schwarzen Kronen: bei `DoubleSide` dreht three die Normale für Rückseiten um,
und bei gekreuzten Flächen sieht man immer die Hälfte von hinten. Der
Fragmentshader setzt die Normale deshalb wieder auf `vNormal`.

`grass.js` streut zusätzlich 3400 Büschel im Ring um den Spieler, ein Draw
Call, Wind ebenfalls im Vertexshader. Verworfene Halme wandern auf y = -60 —
Skalierung null ergibt eine singuläre Matrix, daraus NaN in der
Normalenmatrix und daraus große schwarze Flächen statt nichts.

## Wolkenschatten

Über der ganzen Karte lag dasselbe Sonnenlicht. Draußen ist das nie so: an
einem Küstentag wandern Schattenfelder über Land und Wasser, und daran
erkennt das Auge, dass das Licht aus einem Himmel mit Wolken kommt und nicht
aus einer Lampe über der Szene.

Der Faktor greift nicht an der Albedo, sondern an `reflectedLight.direct*`
hinter `<lights_fragment_end>` — ein Feld im Wolkenschatten wird dunkler,
aber nicht schwarz, weil das Himmelslicht weiterläuft. Beim Klarlack der
Autos und beim Schimmer der Haut reicht das nicht: der Physical-Shader
addiert `clearcoatSpecularDirect` und `sheenSpecularDirect` erst danach
direkt auf das Ergebnis, die beiden werden getrennt gedämpft. Ohne das behielt
ein Autodach im Schatten seinen vollen Sonnenglanz.

Gesampelt wird nicht senkrecht unter der Wolke, sondern dort, wo der
Sonnenstrahl die Wolkenhöhe von 320 m schneidet. Sonst wanderte der Schatten
an einem hohen Haus nicht mit der Höhe, und bei tiefer Sonne läge er an der
falschen Stelle. Das Rauschen ist über 512 Zellen periodisch, damit der
Windversatz nach Stunden Spielzeit umlaufen kann, ohne dass das Feld springt
— sonst wüchse er in den Bereich, in dem `float` die Feinheit innerhalb einer
Zelle nicht mehr auflöst.

Die Stärke steht nicht einfach auf der Wolkendeckung:

| Wetter | Deckung | Dunst | Stärke |
|---|---|---|---|
| klar | 0,18 | 0,12 | 0,20 |
| Regen | 0,88 | 0,62 | 0,01 |
| Nebel | 0,55 | 0,95 | 0,01 |
| Gewitter | 0,97 | 0,70 | 0,00 |

Am stärksten ist der Effekt bei aufgelockerter Decke. Unter einer
geschlossenen zieht kein einzelnes Feld mehr durch — da liegt die ganze Stadt
im Schatten, und das erledigt schon `sonnenStaerke`. Dunst geht mit Exponent
1,4 ein: bei Sichtweite unter hundert Metern ist das Licht vollständig
gestreut, dann hat eine Wolkenlücke keinen Rand mehr. Linear abgezogen blieben
im Nebel noch acht Prozent stehen, was die Prüfung auch gemeldet hat.

Figuren und Fahrzeuge hängen über `wolkenAufsetzen()` im selben Feld, ohne die
Oberflächenstruktur: sie müssen mitdunkeln, brauchen aber weder Flecken noch
Relief, und die zwei Rauschoktaven der Struktur kosten auf Flächen, die den
halben Bildschirm füllen, deutlich mehr als das eine des Schattens. Vier
Materialien waren zuerst nicht dabei — Lack, Glas, Haut und das Umlackieren
zur Laufzeit legen `MeshPhysicalMaterial` an anderen Stellen an. Gefunden hat
sie nicht das Auge, sondern eine Prüfung, die je Figur und Wagen abzählt.

Draw Calls und Dreiecke ändern sich dadurch nicht; die Kosten liegen
vollständig im Fragmentshader. Unter dem Software-Rendering dieser Umgebung
ist darüber nichts Belastbares zu messen. Nachts kostet es nichts: unter einer
Stärke von 0,004 verlässt die Funktion sofort mit 1,0.

## Belichtung über den Tag

Die Nacht wurde einmal angehoben, damit sie zwischen den Lampen lesbar
bleibt. Der Tag ist dabei mitgezogen worden, ohne dass es jemand nachgemessen
hätte: eine sonnenbeschienene Innenstadt kam bei einer mittleren Helligkeit
von 81 von 255 heraus. Ein Mittelgrau wären rund 140.

Der Grund liegt nicht in der Kurve, sondern in der Rechnung davor. Albedo
durch π mal Sonnenstärke landet für eine Fahrbahn unter 0,18, und ACES
komprimiert das anschließend noch. Die Tagesstützstellen sind deshalb um
Faktor 1,35 angehoben.

Beim Nachmessen über den ganzen Tag kam ein zweiter Fehler heraus, den kein
einzelnes Bild gezeigt hätte: um 7 und um 18:30 lagen zwei Drittel des Bildes
unter 6 von 255 — die Dämmerung war dunkler als Mitternacht. Das liegt an
derselben angehobenen Nacht: sie zieht die Kurve an ihren Enden hoch, die
Dämmerung dazwischen aber nicht. Jetzt fällt die Belichtung monoton von der
Nacht in den Mittag und steigt monoton zurück, und das Himmelslicht bei
flacher Sonne ist mit angehoben — bei Sonnenaufgang ist der Himmel die große
Lichtquelle, nicht die Sonne.

| Uhr | mittlere Helligkeit | ausgefressen | abgesoffen |
|---|---|---|---|
| 1 | 49,0 | 0 % | 0 % |
| 7 | 40,7 | 0 % | 40,0 % |
| 9 | 82,4 | 0 % | 1,9 % |
| 13 | 105,2 | 0 % | 2,2 % |
| 16 | 87,7 | 0 % | 2,9 % |
| 18:30 | 27,9 | 0 % | 61,4 % |
| 20 | 53,2 | 0,03 % | 0 % |
| 22 | 50,9 | 0,02 % | 0 % |

Vorher: 13 Uhr 81,1 — 7 Uhr 28,6 bei 66,9 % abgesoffen. Was bei flacher Sonne
übrig bleibt, ist der Schatten der Häuserzeile über der Fahrbahn; den hebt
keine Belichtung mehr an, ohne das Bild flach zu machen. Es bleibt dunkel,
aber es ist nicht mehr dunkler als die Nacht.

## Was Zeichenaufrufe kostet

Draw Calls sind hier die knappe Größe, nicht Dreiecke. Drei Dinge halten sie
unten, und alle drei sind aus Messungen entstanden, nicht aus Vermutungen:

- **Detailstufe.** Figuren wechseln ab 34 m, Fahrzeuge ab 52 m auf eine
  Silhouette in einem gemeinsamen InstancedMesh. Bei 42 m kosteten dreißig
  Leute am Strand über vierhundert Draw Calls für Figuren von zwanzig
  Bildpunkten Höhe.
- **Entfernung.** Weltblöcke jenseits der Nebelgrenze werden verworfen;
  Geländekacheln, die vollständig unter Wasser liegen, nur beim Tauchen
  gezeichnet — der Wassershader ist undurchsichtig.
- **Geteilte Geometrie.** Fahrzeuge teilen sich elf Formen, Figuren neun;
  Gesichter gibt es fünfmal, einmal je Hautton.

## Kampagne

Fünf Akte. Akt 1 und 2 liegen in `simulation.js` und `campaign.js`, Akt 3 bis 5
in `story.js`:

1. **Das Lager** — Festplatte aus dem Caldera-Lager, drei Wege hinein.
2. **Die Ratsakte** — Mara schaltet das Relais ab, Eli holt die Akte, die
   Zeugin muss von Isla Serena zum Flughafen.
3. **Der Transport** — ein Konvoi fährt eine feste Route zur Luftfracht und
   lässt sich nur rammen; erreicht er das Ziel, fährt der nächste.
4. **Die Wäsche** — Tresor im Hinterzimmer des Undertow, nur nachts, nur
   geduckt, und die Wache davor bestimmt den Takt.
5. **Ebbe** — Verfolgung auf dem Wasser, drei Ausgänge: Übergabe, Abfindung
   oder Abrechnung.

## Stadt bei Nacht

Die Sockelgeschosse tragen Neonröhren unter den Markisen, ein Leuchtband über
jedem Schaufenster und auf jedem dritten Haus ein hochkantes Auslegerschild.
Alle diese Flächen liegen in `leuchtMaterialien` und werden in `world.js`
zentral mit dem Sonnenstand hochgefahren — tagsüber matte Röhren, nachts die
Beleuchtung der Straße.

Die Nachbearbeitung fährt nachts Kontrast, Randabdunklung, Korn und
Verdeckung zurück. Ohne das drückte dieselbe Kurve, die dem Tag Tiefe gibt,
die Nacht ins Schwarze.

## Die Stadt

Port Mercy war eine Innenstadt von etwa fünfhundert auf dreihundert Metern;
alles andere war Vorort, Feld oder Küste. Eine Stadt dieser Art lebt vom
zusammenhängenden bebauten Raum, nicht von der Gesamtfläche. Dazugekommen:

- **Nordquartier** — sechs Geschäftshäuser mittlerer Höhe über der Innenstadt,
  erschlossen über den Nordring bei z = -228.
- **Westviertel** — acht Wohnscheiben zwischen zwei neuen Nord-Süd-Achsen.

Die Blockmaße sind nachgerechnet, nicht geschätzt: die Längsstraßen stehen
alle sechzig Meter, ein 44 Meter breiter Block ragt damit in die Fahrbahn.
Zwei Prüfungen halten das fest — kein Gebäude in einer Fahrbahn, keine zwei
Gebäude ineinander. Die erste hat einen alten Fehler gefunden, der seit dem
ersten Ausbau der Karte drinsteckte.

## Der Westen

Die Karte war 970 auf 1000 Meter — knapp ein Quadratkilometer. Nach Westen
und Süden verdoppelt liegt sie bei 1490 auf 1440 Metern; das Meer im Osten
bleibt die Grenze, die Innenstadt bleibt, wo sie war.

- **Rosalind** — zweite Stadt: Hauptstraße mit Geschäftshäusern und Vordach,
  Wohnstraßen im Raster, Wasserturm, Kirche, Getreidesilos.
- **Mercy Reservoir** — Stausee mit befahrbarer Staumauer und Überläufen.
- **Talon Ridge** — Bergrücken auf 88 m mit Windpark und Steinbruch.
- **Cane Hollow** — Zuckerrohr, Gräben und drei Höfe im Süden.
- **Hinterland** — Gehölz, Findlinge, Weidezäune und Feldwege dazwischen.
  Eine breite dünne Streuung, damit keine Zelle leer bleibt.

Der Dunst nimmt mit der Höhe ab. Mit der bodennahen Dichte war der Blick vom
Talon Ridge eine weiße Fläche und aus dem Flugzeug sah man die Stadt nicht.

## Die Keys

Östlich der Küste lagen dreißig Kartenzellen blankes Wasser. Jetzt liegen
dort fünf Inseln und eine Sandbank: Pelican Key mit Stelzenhäusern, Halcyon
Key mit Marina, Sable Key mit Leuchtturm — alle drei über den Keys Highway
auf einem Damm erreichbar — sowie Windward Key und Bone Key, die nur mit dem
Boot zu erreichen sind. Die Rechtecke stehen in `content.js` unter `INSELN`
und `DAEMME`; `waterAt`, das Gelände, die Karte im Telefon und die Brandung
im Wassershader lesen dieselbe Liste.

## Musik

Die Radiosender in `radio.js` erzeugen ihre Musik zur Laufzeit aus Tempo,
Tonart, Akkordfolge und Instrumentierungsregeln. Es sind keine Aufnahmen
eingebunden — weder eigene noch fremde.
