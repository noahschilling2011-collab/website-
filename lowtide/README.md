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
node tools/regression.mjs                        # 185 Prüfungen, muss grün sein
node tools/abdeckung.mjs                         # Bauteile je 100-Meter-Zelle
node tools/wolken.mjs                            # wandert der Wolkenschatten
node tools/spiegelung.mjs                        # spiegelt Wasser die Stadt
node tools/statistik.mjs                         # Sättigung und örtlicher Kontrast
node tools/schwachstellen.mjs                    # welche Region ist am flachsten
```

Die drei Werkzeuge in `tools/` mit Browser brauchen Playwright und Chromium.
Ohne die beiden lässt sich `LOWTIDE.html` trotzdem bauen und öffnen.

Zur Bildrate: diese Werkzeuge laufen hier gegen einen Software-Rasterizer.
Die dort gemessenen fps sagen nichts über echte Hardware. Aussagekräftig sind
Draw Calls und Dreiecke aus `messung.mjs` — die sind hardwareunabhängig.

## Debug

`window.LOWTIDE` gibt im Browser Zugriff auf `sim`, `world` und den Frame-Zähler.
Unter der Minikarte stand die Gegend fest in `shell.html` — auf dem Talon
Ridge, im Nationalpark und in Rosalind meldete sie HARBOR DISTRICT. Sie steht
auf jedem Bildschirmfoto dieser Sitzung, und aufgefallen ist sie erst, als
eines davon offensichtlich danebenlag. Zwei Prüfungen halten jetzt fest, dass
Kopfzeile und Minikarte dieselbe Gegend nennen und dass sie sich beim
Ortswechsel ändert.

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

## Wo die Karte noch nach Prototyp aussieht

Bis hierher habe ich Mängel durch Hinsehen gesucht. Die Trefferquote war
schlecht: auf fünf belegte Verbesserungen kamen sieben widerlegte
Vermutungen. `tools/schwachstellen.mjs` dreht das um — es fährt jede der
fünfzehn Regionen an, misst dort örtlichen Kontrast, Sättigung und
Helligkeit und sortiert nach dem schwächsten Wert. Niedriger Kontrast heißt
große glatte Flächen: unfertig.

Der erste Lauf war eindeutig. TALON RIDGE stand bei **6,03** gegen 13,25 im
Schnitt, mit Abstand die flachste Gegend. Von dort rückwärts kamen vier
Fehler heraus, von denen keiner beim Spielen aufgefallen war:

**Oberhalb von 62 Metern stand nichts.** Die Regel „über der Baumgrenze
wächst kein Baum" war als `continue` umgesetzt, also als gar nichts. Die
obersten sechsundzwanzig Meter des Rückens waren eine glatte grüne Kuppel.
Jetzt stehen dort Findlinge, Felsrippen, Geröllfelder und Krüppelsträucher.

**Die Dichte reichte nicht.** Der erste Anlauf hängte den Fels an den
vorhandenen Streuwurf: 620 Stück auf 520 mal 620 Meter, eines je 520
Quadratmeter. Der Kontrast blieb bei 6,04. Deshalb ein eigener Wurf nur für
die Kuppe, 900 Stück auf 35.000 Quadratmeter.

**Fahrbahnen lagen auf Meereshöhe.** Jedes Straßensegment war ein einziger
Quader auf y = 0,03 — auf ebener Karte richtig, unter einem
achtundachtzig Meter hohen Rücken nicht. Die Zufahrt bei z = -160 lag damit
sechsundachtzig Meter unter der Kuppe: unsichtbar, aber `aufStrasse()`
rechnet in der Ebene und hielt den Bewuchs trotzdem von einem Streifen fern,
auf dem nichts lag. Fahrbahnen werden jetzt in Zwölf-Meter-Stücke geteilt und
folgen dem Gelände, am Hang mit Berme.

**Fünf Bauwerke standen in Fahrbahnen.** Die Höhenprüfung fand ein flaches
breites Teil fünfzehn Meter über einer Straße — den Kirchturm von Rosalind.
Die Kirche stand mit ihrer nördlichen Hälfte in der Hauptstraße, der
Wasserturm mit allen vier Stelzen mittendrin. Eine daraus abgeleitete
Prüfung fand drei weitere: die Abfertigung des Flugfelds (46 mal 16 Meter
quer über der Achse bei z = 400), eine Resortvilla auf Isla Serena im Damm,
und das Vereinsheim der Vororte im Nordring. `sim.blocked` kennt nur
registrierte Gebäude; alles, was `regions.js` als Kulisse setzt, ist durch
jedes bisherige Netz gefallen.

Dazu kam eine Leitplanke, wo es neben der Fahrbahn hinuntergeht: gesetzt nur
dort, wo der Boden zehn Meter neben der Achse mehr als anderthalb Meter
tiefer liegt. In der Ebene entsteht dadurch keine einzige Kiste, und zwei
Prüfungen halten beides fest.

**Und das Werkzeug selbst hatte zwei Fehler**, beide erst beim Nachsehen
aufgefallen. Es maß aus der dritten Person; an einer Wand schiebt die
Federung die Kamera in die Figur, und bei HARBOR DISTRICT waren die
gemessenen 9,38 der Pullover des Spielers. Danach maß es waagerecht aus neun
Metern — da lag die halbe Bildhöhe voller Ferne im Dunst, und der Schnitt
fiel von 13,25 auf 7,73, ohne dass sich an der Karte etwas geändert hätte.
Jetzt sechzehn Meter hoch, Ziel fünfundvierzig Meter voraus auf Bodenhöhe.

Die Rangliste danach, und damit die Arbeitsliste:

| Region | örtl. Kontrast | Sättigung | Mittel |
|---|---|---|---|
| TALON RIDGE | 4,65 | 7,2 % | 205,0 |
| MERCY RESERVOIR | 5,52 | 26,7 % | 143,6 |
| CYPRESS NATIONAL PARK | 7,92 | 10,8 % | 189,0 |
| … | | | |
| DOWNTOWN | 14,24 | 27,7 % | 139,3 |
| SOUTH BEACH | 15,54 | 12,8 % | 200,3 |
| THE LOWER KEYS | 17,67 | 15,5 % | 191,6 |

Ein Wert taugt hier nur im Vergleich unter gleicher Rahmung. Dass TALON
RIDGE auch nach den Felsen und der Leitplanke bei 4,65 steht, liegt zum Teil
am Blick selbst: von der Kuppe aus füllt die dunstige Ferne die untere
Bildhälfte, und Dunst ist hell und farblos. Ein Werkzeug, das auf den Wert
optimiert würde, hätte hier ein leichtes Ziel — deshalb steht daneben immer
die Helligkeit.

## Der Stausee war keiner

`schwachstellen.mjs` hatte MERCY RESERVOIR als zweitflachste Gegend
ausgewiesen. Der Grund war nicht die Umgebung: der See selbst war eine
bemalte Platte von 206 mal 155 Metern mit ein paar helleren Kisten darauf,
die aus der Nähe genau danach aussahen. Kein Wellengang, keine Spiegelung,
kein Ufersaum.

Jetzt ist es Wasser, über dasselbe Muster wie der Salzsumpf: eine dritte
Fläche mit eigenem `art`-Wert. Ein Binnensee hat keine Küstenlinie im Sinne
des Ozeans, sein Ufer ist der Rand des eigenen Rechtecks von innen gesehen —
dafür bekam `kuestenAbstand()` einen Zweig. Nachgerechnet: Mitte 77 m,
Uferkante 7 m, Ecke 3 m.

**Zweimal daneben geraten, bis die Messung es geklärt hat.** Die neue
Wasserfläche lag bei Tag unter einer weißen Decke. Erste Vermutung: Gischt.
Zweite: Sonnenglitzer, also einen Glitzerpfad eingebaut — der ist physikalisch
richtig und bleibt drin, war aber nicht die Ursache. Der Nachtblick hat es
entschieden: nachts war der See sauber, das Weiße hing also an der Sonne,
aber nicht an ihrer Spiegelkeule. Es war die Fresnelzahl. Die Kräuselung hatte
einen fest verdrahteten Steigungsfaktor von 1,5 für jedes Gewässer; bei so
steilen Normalen springt Fresnel zwischen 0,03 und 1, und damit wechselt
jeder zweite Bildpunkt zwischen Wasserkörper und hellem Himmel.

Die Steigung hängt jetzt am Gewässer: See 0,34, Sumpf 0,6, offene See 0,8.
Auch das Meer war zu steil.

| Region | vorher | nachher |
|---|---|---|
| MERCY RESERVOIR | 5,52 | 7,31 |
| OUTER KEYS | 14,75 | 12,38 |
| SOUTH BEACH | 15,54 | 13,64 |
| THE LOWER KEYS | 17,67 | 14,74 |

Die drei unteren Zeilen sind der Preis, und er ist gewollt: die ruhigere
Kräuselung nimmt dem Wasser genau das hochfrequente Flimmern, das den
Kontrastwert hochgetrieben hat. Der Schnitt über alle Regionen fällt von
11,14 auf 10,72. Das ist der Fall, vor dem im Kopf von `statistik.mjs` steht,
dass Kontrast allein kein Ziel ist.

**Und dann bis zu Ende gebaut.** Im ersten Anlauf war der See nur optisch
Wasser: `waterAt()` kannte ihn nicht, man lief darüber wie über die alte
Platte. Etwas, das wie Wasser aussieht und trockener Boden ist, ist genau die
Art halbes Feature, die dieses Projekt nicht haben soll. Jetzt steht er in
`waterAt()` — als Ellipse, weil sein Ufer als Ellipse gebaut ist; ein Rechteck
ragte an den Diagonalen über die Böschung hinaus und schnitt als gerade Kante
durch den Uferbewuchs. Die Fläche verwirft im Shader, was außerhalb liegt.

Gemessen an der Seemitte: `waterAt` wahr, `groundAt` −1,2, die Figur sackt auf
y = −0,5 und schwimmt, die Geländekachel darunter bildet eine Wanne bis −3,4,
und fünfzehn Meter vor der Böschung ist wieder Land. Vier Prüfungen halten
das fest. Die Karte hat dadurch 182 → 178 Landzellen: die vier fehlenden sind
jetzt See.

| | vorher | nachher |
|---|---|---|
| MERCY RESERVOIR, örtl. Kontrast | 5,52 | 10,28 |

## Die Sichtweite war der teuerste Kompromiss, den niemand bezahlt hat

Bei klarem Wetter stand die Nebeldichte auf 0,0022: die Hälfte des Lichts
war nach **391 Metern** verschluckt. Für einen klaren Küstentag ist das viel
zu viel — die Skyline stand als blasse Ahnung hinter Dunst, jeder weite Blick
war ein Wisch, und vom Talon Ridge sah man die Stadt praktisch nicht.

Die naheliegende Annahme war, dass der Dunst die Zeichenlast deckelt: die
Entfernungsverwerfung leitet ihre Reichweite aus der Nebeldichte ab. Nur
stimmt sie nicht. Gemessen mit sinkender Dichte an drei Standorten:

| Faktor | Sicht (50 %) | Draw Calls Innenstadt | Strand | Bergrücken |
|---|---|---|---|---|
| 1,00 | 391 m | 1954 | 3582 | 4594 |
| 0,42 | 930 m | — | 3585 | 4594 |
| 0,25 | 1565 m | 1977 | — | — |

Dreiecke blieben in allen Fällen gleich. Die Verwerfung greift schon vorher,
der Dunst kostet nichts und deckt nichts — er hat nur das Bild zugezogen.

Jetzt 0,0009, rund 925 Meter. Schlechtes Wetter bleibt dicht, da gehört es
hin: Regen 0,0075, Nebel 0,0135, Gewitter 0,0090.

Was das über die ganze Karte ausmacht, in derselben Rangliste wie oben:

| Region | vorher | nachher |
|---|---|---|
| TALON RIDGE | 4,75 | 10,38 |
| MERCY RESERVOIR | 10,28 | 11,69 |
| Schnitt über alle fünfzehn | 10,93 | 13,93 |

TALON RIDGE stand die ganze Zeit auf Platz eins der Arbeitsliste, und ich
habe Felsen, Leitplanken und Fahrbahnen dorthin gebaut. Der größte Anteil an
seinem schlechten Wert war aber gar nicht die Gegend, sondern der Dunst über
allem, was man von dort aus sieht. Das ist der Grund, warum die Liste
Arbeitsliste heißt und nicht Urteil.

Mit der besseren Sicht kam die Frage nach der Schattenreichweite zurück: das
erste Nein dazu war bei 391 Metern Sichtweite gemessen, könnte also vom Dunst
verdeckt gewesen sein. Es war es nicht. In der Spielansicht bei 925 Metern:

| Schattenweite | Karte | Mittel | dunkler als 40 % | Draw Calls |
|---|---|---|---|---|
| 130 m | 2048 | 96,2 | 69,5 % | 2094 |
| 300 m | 2048 | 96,3 | 69,6 % | 3107 |
| 300 m | 4096 | 96,2 | 69,5 % | 3107 |
| 520 m | 4096 | 96,3 | 69,6 % | 3753 |

Achtundvierzig Prozent mehr Draw Calls für ein Bild, das sich in der zweiten
Nachkommastelle unterscheidet. Bleibt bei 130 Metern.

## Eine Innenstadt, in der jemand geht

Gemessen standen an der Hauptkreuzung **vier** Leute im Umkreis von sechzig
Metern, am Strand vierundzwanzig. Eine Stadt, in der niemand zu Fuß
unterwegs ist, ist der auffälligste Unterschied zu jeder Aufnahme einer
echten Stadt — und er war nie Absicht, nur nie nachgezählt.

Der erste Versuch rasterte den Kern in Dreizehnmeterschritten ab und nahm,
was neben einer Fahrbahn liegt. Er fand dort **null** Stellen: das Gehwegband
ist sieben Meter breit, das Raster war doppelt so grob und ist immer daran
vorbeigesprungen. Nachgezählt an fünfundvierzig Proben im Kern —
einundzwanzig auf der Fahrbahn, vierundzwanzig zu weit weg, keine einzige
dazwischen.

Jetzt wird nicht gerastert, sondern die Fahrbahnen werden entlanggegangen:
alle achtzehn Meter, beidseitig, drei Meter hinter der Bordsteinkante. Der
Gehweg kommt damit aus der Straße selbst und stimmt auch dann noch, wenn sich
das Raster der Stadt ändert.

| | vorher | jetzt |
|---|---|---|
| Figuren gesamt | 157 | 413 |
| an der Kreuzung, Umkreis 60 m | 4 | 17 |
| Draw Calls Kreuzung 13 Uhr | 1697 | 1790 |
| Dreiecke Kreuzung 13 Uhr | 1.933.960 | 1.986.664 |

Gedeckelt ist es bei 260 zusätzlichen Figuren, also 413 insgesamt. Der erste
Deckel lag bei 140, begründet mit der Simulationslast beim Tageswechsel — und
**diese Begründung war geraten, nicht gemessen.** Nachgemessen:

| | |
|---|---|
| Simulationsschritt bei 413 Figuren und 133 Wagen | 0,30 ms |
| Anteil an einem Sechzehntelsekunden-Bild | 1,8 % |
| teuerster Fall, Tageswechsel um 8, 17, 20 Uhr | 1,4–1,7 ms |

Der Grund steht in `tick()`: verarbeitet wird nur, wer näher als 180 Meter
ist, alle anderen nur jeden zwölften Tick. Die Zahl der Figuren geht deshalb
kaum in die Kosten ein. Was tatsächlich mitwächst, ist die Zeichenlast — an
der Kreuzung 1839 auf 1902 Draw Calls.

**Und ein alter Fehler kam dabei heraus.** Die neue Prüfung fragte, wer auf
einer Fahrbahn steht, und meldete dreiundzwanzig. Die stammten aus den
älteren Mengen-Schleifen, die nie gegen Straßen geprüft haben —
Handtuchreihen, die über die Uferstraße reichen, und von Hand gesetzte
Gehwegpunkte. Die Figuren entstehen an vier Stellen mit unterschiedlicher
Absicht; statt dieselbe Prüfung viermal einzubauen, schiebt jetzt ein
Nachlauf an einer Stelle jeden aus der Spur.

Die Prüfung selbst musste dreimal umformuliert werden, und das ist der
lehrreiche Teil: „niemand steht auf der Fahrbahn" ist die falsche Frage, denn
ein Fußgänger, der eine Straße überquert, tut genau das. Erst gegen `path[0]`
geprüft — trifft die Rundgänge falsch, die auf `path[i%4]` starten. Dann
gegen die Position zu einem beliebigen Zeitpunkt — meldet jeden
Überquerenden. Tragfähig ist der Anteil: ein paar Prozent sind Verkehr, ein
Drittel wäre eine Menge, die in den Fahrspuren wohnt.

## Licht auch in der Ferne

Die Scheinwerfer des vollen Fahrzeugmodells fahren mit dem Sonnenstand hoch.
Jenseits von zweiundfünfzig Metern gibt es dieses Modell aber nicht mehr,
dort steht die Silhouette aus `lod.js` — und die hatte keine Lampen. Eine
nächtliche Straße war damit ab dieser Entfernung unbeleuchtet, obwohl
achtundsiebzig Wagen darauf fuhren. Bei Nacht ist von fernem Verkehr fast nur
das Licht zu sehen; ohne es wirkt die Stadt tot.

Das grobe Vorbild hat jetzt zwei Lampenpaare. Zwei zusätzliche Materialien
heißen zwei zusätzliche Draw Calls für die **gesamte** ferne Flotte,
unabhängig von ihrer Zahl — gemessen 3254 auf 3258.

Ob eine Lampenfläche Rücklicht oder Scheinwerfer ist, entscheidet der
Blauanteil und nicht Rot gegen Grün: das warme Scheinwerferweiß 0xffd9a4 hat
linear r = 1,00 und g = 0,71 und wäre über diesen Vergleich ebenfalls „rot"
gewesen. Über Blau trennt es sauber, 0,37 gegen 0,03.

## Verkehr, der einander sieht

Vierundvierzig fahrende Wagen auf 15.728 Metern Straßennetz sind einer alle
**357 Meter**. Dazu klumpten sie: der Startpunkt war ein Wegpunkt der Runde,
also standen drei Wagen je Runde auf drei Ecken. Jetzt werden sie über den
Umfang verteilt, neun je Runde.

| | vorher | jetzt |
|---|---|---|
| fahrende Wagen | 44 | 116 |
| ein Wagen alle | 357 m | 136 m |
| im Umkreis 120 m der Kreuzung | 8 | 19 |
| Draw Calls Kreuzung 13 Uhr | 1790 | 1836 |

**Die Grenze war nicht die Zeichenlast, sondern dass die Wagen einander nicht
sahen.** Sie sind ineinander gefahren, sobald mehrere an derselben Ampel
standen — bei vierundvierzig über die ganze Karte verteilt fiel das kaum auf,
bei hundertsechzehn schon: fünf Paare mit weniger als 3,6 Metern Abstand, bei
4,4 Metern Wagenlänge also echte Durchdringung.

`wagenVoraus()` prüft jetzt, was voraus und in der eigenen Spur liegt: bis
sieben Meter nach vorn, gut zwei Meter seitlich, mit einer billigen
Vorabschätzung über die Manhattan-Distanz. Der Wagen des Spielers zählt mit,
sonst schöbe der Verkehr ihn von hinten an.

Danach: **null Paare** unter 3,6 Metern, engster Abstand 4,97 Meter. Zwei
Prüfungen halten Dichte und Abstand fest.

## Was geprüft wurde und in Ordnung war

Nicht jede Messung findet etwas, und das gehört genauso hierher.

**Die acht Innenräume** sind alle begehbar: kein blockierter Schritt auf dem
Weg von draußen bis in die Raummitte, Mitte frei, in sieben von acht Räumen
auch der Ring von drei Metern. Im Motel sind fünf von acht Richtungen frei —
das sind die Betten. Zwei Prüfungen halten es jetzt fest, weil sich die Karte
laufend ändert und ein Solid vor der offenen Front einen Laden aussperren
würde, ohne dass es irgendetwas meldet.

**Die Karte im Telefon** baut ihr Wasser aus derselben `waterAt`-Funktion wie
das Gelände. Stausee und Sumpfdämme erscheinen darauf automatisch; eine
Abweichung zwischen Karte und Welt kann es gar nicht geben.

**Geparkte Wagen in Gebäuden oder ineinander**: nein. Der Erzeuger prüft
freien Grund, ebenen Boden, Abstand zu Kreuzungen und 5,8 Meter zum nächsten
Platz.

**Das Fensterraster der Innenstadthäuser**: vermutet fest verdrahtet und
damit bei breiten Wänden lückenhaft. Nachgemessen sind alle sechzehn Häuser
18,8 mal 38,8 Meter, das Raster deckt 14 von 18,8 und 32 von 38,8 — kein
Fenster ragt über eine Kante.

## Eine Fundstelle, an die man nicht herankam

Nach Stausee, Dämmen und geländefolgenden Straßen die Gegenprobe: liegt noch
jeder Ort, jede Immobilie und jeder Missionspunkt auf begehbarem Boden?
Zweiundvierzig Punkte abgefragt. Drei liegen im Wasser — Tauchplatz,
Jetskiverleih und eine Fundstelle, alle drei absichtlich. Zwei liegen in
Gebäuden — Pool und Schießstand, beide in ihrem Gebäude, wo sie hingehören.

Einer nicht: die **vierte Fundstelle der Schatzsuche** lag auf -360/352 und
damit in einem Haus von 33 mal 25 Metern. Geborgen wird bei einem Abstand
unter fünf Metern; der nächste Punkt, an dem man überhaupt stehen kann, war
exakt **fünf Meter** entfernt. Knapp zu weit — und weil die Fundstellen der
Reihe nach kommen, hätte das die ganze Kette abgebrochen.

Jetzt auf -351/352, mit freiem Ring von zweieinhalb Metern ringsum.

**Zwei Fehlmessungen dabei.** Die erste meldete zwei übereinanderstehende
Häuser an dieser Stelle — es war eines, doppelt gezählt: der Test verkettete
`solids`, `buildings` und `worldBuildings`, und ein Haus steht in zweien
davon. Die zweite war die neue Prüfung selbst: sie zählte Wasser als
unerreichbar und meldete prompt die Fundstelle im Meer, die bewusst dort
liegt. Man schwimmt hin.

## Masten in der Fahrspur

Aus derselben Auszählung wie die Straßen über dem Wasser: von den 340 dünnen,
hohen Dingen in einer Fahrbahn blieben nach den Dämmen 139 übrig. Wie tief
stehen sie darin?

| Tiefe in der Fahrbahn | Anzahl |
|---|---|
| 0–2 m | 55 |
| 3–5 m | 33 |
| 5–9 m | 51 |

Bis zwei Meter ist Bordstein. Ab drei Metern steht ein Mast in einer Spur,
und der tiefste stand mit neun Metern genau auf der Mittellinie einer
achtzehn Meter breiten Straße.

Zwei Ursachen. Die Laternen werden an fünf verschiedenen Stellen gesetzt —
Straßenzug, Steg, Damm, Strandpromenade, Uferstraße — und nur die erste
rechnet mit der Fahrbahn. Die Leitungsmasten stehen 4,2 Meter hinter der
Kante **ihrer eigenen** Straße; an einer Kreuzung liegt das mitten in der
querenden.

`World.nebenDerFahrbahn()` schiebt heraus, was hineinragt, und lässt alles
andere stehen. Einmal an einer Stelle statt sechsmal an den Aufrufstellen —
dasselbe Muster wie beim Wegschieben der Figuren von der Straße.

| | vorher | nach den Dämmen | nach dem Schutz |
|---|---|---|---|
| dünne Pfosten in einer Fahrbahn | 340 | 139 | 75 |
| davon drei Meter oder tiefer | — | 84 | 28 |

Die restlichen 28 sind Zaunpfähle und Stegpfähle: ein Zaun, der eine Straße
quert, ist am Flugfeld gewollt, und die Pfähle unter einem Damm gehören unter
die Fahrbahn. Die Prüfung nimmt deshalb nur Laternen und Masten.

## Drei Straßen liefen über offenes Wasser

Gefunden über eine Frage, die zunächst nichts damit zu tun hatte: stehen
dünne, hohe Dinge — Laternen, Pfähle, Stämme — in einer Fahrbahn? Die
Auszählung meldete 340, davon 202 in derselben braunen Farbe. Das sind die
Stelzen der Mangroven im Salzsumpf, und die stehen dort, wo `waterAt` wahr
ist. Beides zugleich kann nicht sein.

Es war beides zugleich. Drei Straßensegmente laufen durch den Sumpf:

| Segment | über Wasser |
|---|---|
| x = -462, z = -228 … 150 | 146 m (39 %) |
| x = -402, z = -228 … 150 | 146 m (39 %) |
| z = 62, x = -480 … -348 | 82 m (62 %) |

Sichtbar war davon nichts: `groundAt` liefert über Wasser -1,2, die Fahrbahn
lag damit unter der Sumpffläche. Geblockt hat sie trotzdem — der Bewuchs mied
einen Streifen, auf dem nichts lag, und der Verkehr fuhr über das Wasser.
Dieselbe Bauart Fehler wie beim Talon Ridge, nur unter statt über dem Boden.

Die Straßen bekommen jetzt einen Damm: drei Rechtecke, zwei Meter breiter als
die Fahrbahn, die dem Sumpf diesen Streifen nehmen. Der Sumpfshader verwirft,
was darin liegt, sonst stünde die Wasserfläche über der Straße.

Nachgemessen an sechs Punkten: auf dem Damm kein Wasser und Boden 0, zwanzig
Meter daneben Wasser und Boden -1,2. Eine Prüfung tastet jetzt jedes Segment
alle vier Meter ab.

**Und eine Prüfung daneben war zu schwach.** „Der Wassershader kennt alle
Küsten" verglich mit einer hart notierten Neun. Als die drei Dämme dazukamen,
meldete sie nur, dass sich etwas geändert hat — nicht, ob es zusammenpasst.
Sie rechnet die Sollzahl jetzt aus den Daten.

## Der Verkehr fuhr durch die geparkten Wagen

Geparkte Wagen stehen zwei Meter innerhalb der Fahrbahnkante — das ist
richtig so, dort parkt man. Wo eine Verkehrsroute genau dort entlanglief,
fuhr der Verkehr durch sie hindurch, und `wagenVoraus()` konnte davon nichts
wissen: die Kulisse steht nicht in `sim.cars`.

Gemessen: **1304 Fälle** in fünfzehn Sekunden, **147 von 519 Plätzen**
betroffen, engster Abstand **0,11 Meter**. Nachgerechnet an der Geometrie
statt an der Bewegung: 200 der 519 Plätze liegen näher als zwei Meter an
einer Fahrlinie, der engste bei 0,10 — sie stehen auf der Fahrspur, nicht
daneben.

Behoben nicht durch eine Ausweichlogik, sondern bei der Erzeugung: ein Platz,
der näher als 2,6 Meter an einer Fahrlinie liegt, wird verworfen. Das sind
zwei halbe Wagenbreiten plus eine Handbreit.

Das kostete zunächst 218 Plätze, 519 auf 301. Der Grund war aber nicht die
neue Bedingung, sondern eine alte Schwäche daneben: der Erzeuger würfelt eine
Straßenseite und gibt bei Kollision auf, statt die andere zu versuchen. Mit
beiden Seiten kommen 496 der 519 zurück — und keiner davon steht auf einer
Fahrlinie.

| | vorher | nur verworfen | beide Seiten |
|---|---|---|---|
| Parkplätze | 519 | 301 | 496 |
| Durchfahrten in fünfzehn Sekunden | 1304 | 0 | 0 |
| engster Abstand | 0,11 m | 4,34 m | 3,60 m |

Die verworfenen Plätze sind kein Verlust: es waren genau die, die in einer
Fahrspur standen.

## Einundfünfzig Paare standen ineinander

Dieselbe Frage wie beim Verkehr, eine Ebene tiefer: stehen die Figuren
ineinander? Bei 413 auf schmalen Gehwegen keine müßige Frage. Gemessen
**einundfünfzig Paare** näher als 0,55 Meter, engster Abstand **0,00** —
einige standen exakt auf demselben Punkt.

Der Grund ist derselbe wie bei den Bauwerken in den Fahrbahnen: die Figuren
kommen aus fünf Quellen — Rundgänge aus `simulation.js`, Blöcke aus
`campaign.js`, Wachen, Strandmenge, Gehwege —, und keine kennt die Stellen
der anderen. Wo zwei Straßensegmente kreuzen, erzeugt der Gehwegwurf denselben
Punkt zweimal.

Ein Nachlauf beim Aufbau schiebt sie auseinander, quadratisch über 413
Figuren, also hundertsiebzigtausend Vergleiche — beim Aufbau nicht der Rede
wert, zur Laufzeit sehr wohl. Wachen bleiben, wo sie stehen.

| | vorher | nachher |
|---|---|---|
| Paare unter 0,55 m beim Start | 51 | 0 |
| engster Abstand beim Start | 0,00 m | 1,30 m |
| engster Abstand nach zehn Sekunden | 0,00 m | 0,98 m |

Die 0,98 Meter nach zehn Sekunden sind zwei Leute, die aneinander
vorbeigehen. Deshalb prüft die Regression auch nicht auf null, sondern auf
weniger als fünf Paare: sie läuft mitten im Spiel, nicht beim Aufbau.

## Der Verkehr sieht jetzt auch Fußgänger

Nach dem Abstand zwischen den Wagen die nächste Frage: fahren sie durch die
Menge? Gemessen ja — in zehn Sekunden einunddreißig Fälle, in denen ein
fahrender Wagen einen Fußgänger auf der Fahrbahn näher als 1,8 Meter vor sich
hatte, engster Abstand 0,66 Meter. Keine Figur nahm dabei Schaden, keine
Kollision wurde gezählt: die Simulation hat es nicht einmal bemerkt.

`fussgaengerVoraus()` bremst jetzt, mit derselben Kegelprüfung wie beim
Abstand zwischen Wagen. Die Liste der Leute auf der Fahrbahn wird alle
Zehntelsekunde neu gebildet — der Verkehr gegen alle Figuren zu prüfen wären
bei 116 Wagen und 413 Figuren achtundvierzigtausend Abstände je Bild.

**Drei Fehlmessungen auf dem Weg dahin**, und sie sind der eigentliche Ertrag:

1. Die erste Zählung nahm jeden Wagen, der einer Figur nahe kam — auch die,
   die dicht an Leuten auf dem **Gehweg** vorbeifahren. Das ist normal, der
   Bordstein liegt einen halben Meter neben der Spur.
2. Die zweite zählte stehende Wagen mit. Ein bremsender Wagen behält seine
   gespeicherte Geschwindigkeit und bewegt sich trotzdem nicht; die Fälle mit
   `laengs` 1,3 und wachsendem Abstand waren wartende Wagen, also genau das
   gewünschte Verhalten.
3. Die dritte zählte Figuren **hinter** dem Wagen mit.

Übrig bleiben einunddreißig echte Fälle in zehn Sekunden bei 116 Wagen —
0,018 je Wagen und Sekunde, gegen 210 Bremsungen im selben Zeitraum. Es sind
Leute, die von der Seite in einen anfahrenden Wagen laufen. Ich habe das
nicht auf null gebracht und schreibe es hin, statt die Zahl wegzudefinieren.

**Und die Prüfung dazu musste vom statistischen auf den gezielten Test
umgestellt werden.** Über sechshundert Ticks gezählt meldete sie im
Regressionslauf null Bremsungen, während derselbe Code einzeln zweihundertzehn
ergab — der Unterschied war der Zustand, den die vorherigen Prüfungen
hinterlassen. Jetzt steht ein Wagen auf einer freien Geraden, einmal mit und
einmal ohne jemanden vier Meter voraus: ohne fährt er, mit hält er.

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
