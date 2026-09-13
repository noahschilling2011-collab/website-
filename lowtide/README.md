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
node tools/regression.mjs                        # 253 Prüfungen, muss grün sein
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

## Zwei Rennen führten über Land

Fünf Rennstrecken mit festen Kontrollpunkten, und die Karte hat sich seither
mehrfach geändert. Abgetastet werden Punkte und Strecke alle acht Meter.

Die drei Landrennen sind sauber. Die beiden Wasserrennen nicht:

- **RIPPLE SPRINT**, Kontrollpunkt zwei auf 170/60 — das liegt auf der
  **Anchor Bank**, einer Sandbank aus dem Kartenausbau. Ein Jetski kommt dort
  nicht hin, und weil die Punkte der Reihe nach zählen, endet das Rennen
  dort.
- **SERENA REGATTA**, zwei von dreiundneunzig Proben an Land: eine auf dem
  **Damm nach Isla Serena** bei z = 200, eine an der Südostecke der Insel.

Der Damm ist der interessantere Fall. Die Regatta umrundete die Insel, und
das geht nicht mehr: nördlich und südlich liegt Wasser, aber dazwischen gibt
es keinen Durchlass. Der Damm steht zwar auf Pfeilern — durchfahren kann man
ihn trotzdem nicht, weil `waterAt` sein Rechteck als Land führt. Das
auseinanderzunehmen hieße, befahrbare Fläche und Wasser darunter getrennt zu
behandeln; dafür ist der Kurs der kleinere Eingriff.

Er liegt jetzt ganz im nördlichen Becken, 530 statt 743 Meter, Zielzeit
entsprechend 86 statt 120 Sekunden. Der Jetski-Punkt liegt westlich der Bank,
im Kanal zwischen Küste und Sandbank.

## Zehn Ampeln standen doppelt

Die Kreuzungsliste ist gerechnet, nicht getippt: alle Längssegmente gegen
alle Quersegmente, Treffer, wo sich die Spannen überlappen. Das überlebt
jede neue Straße — nur zählt es dieselbe Kreuzung mehrfach, wenn eine Achse
aus zwei Segmenten besteht. Bei x = -100 und x = -340 liegt neben der kurzen
Rasterstraße der lange Boulevard, bei z = 200 und z = 400 stoßen Uferstraße
und Keys Highway aneinander.

Im laufenden Spiel gemessen: **76 gebaute Kreuzungen auf 66 Plätzen.** An
zehn davon steckten vier Masten, vier Ausleger, vier Gehäuse und zwölf
Lichtlinsen deckungsgleich ineinander — als Flimmern an den Gehäuseflächen
zu sehen, dazu 240 Instanzen umsonst. Jetzt werden die Treffer nach Position
zusammengefasst, mit der größeren der beiden Fahrbahnbreiten.

## Vier Läden und ein Lagerhaus standen auf der Straße

Die acht Servicegebäude sind keine Punkte, sondern Räume: sechzehn Meter
breit, sechzehn tief, von der Rückwand bis zur offenen Front. Der Marker
steht an der Front. Pike Customs, Supply & Style, die Klinik und die Wohnung
lagen drei Meter nördlich der Querstraßen bei z = 80, 20, -40 und -100 und
fünf Meter östlich der Nord-Süd-Achse bei x = -160 — bei sechzehn Metern
Raumtiefe liefen damit **beide** Fahrbahnen mitten durch das Gebäude. Auf dem
Luftbild steht der Laden als weißer Klotz zwischen zwei Fahrspuren, links und
rechts davon fährt Verkehr.

Gefunden hat es keine Sichtprüfung, sondern die Frage, warum ein Marker
`onRoad` meldet. Die bestehende Prüfung „Nichts Großes steht in einer
Fahrbahn" konnte es nicht finden: sie verlangt drei Meter Kantenlänge in
beiden Richtungen und testet den Mittelpunkt. Die Zimmerwände sind einen
Meter dick und sechzehn lang, ihr Mittelpunkt liegt neben der Fahrbahn, ihre
Fläche darin. Zusammen mit Club, Diner, Motel und Archiv waren es
**fünfundzwanzig Wandstücke in einer Fahrbahn**.

Die neuen Plätze sind gesucht, nicht geschätzt: für jeden Raum alle Punkte im
Umkreis von sechzig Metern, die mit zweieinhalb Metern Luft jede Fahrbahn
freilassen, sechs Meter offenen Vorplatz haben, kein anderes registriertes
Hindernis berühren und auf ebenem, trockenem Grund liegen — davon der
nächstgelegene. Vierzehn bis dreißig Meter Versatz, und in keinem der acht
Rechtecke steht danach noch stehende Kulisse. Die vier Innenstadthäuser
bilden weiterhin eine Reihe, jetzt an der Südseite ihrer Querstraße statt
darin. Dartscheibe und Billardtisch hängen jetzt am Gebäude statt an eigenen
Koordinaten, sonst wären sie beim Umzug stehengeblieben; der Schießstand lag
ohnehin schon in der Querstraße.

Das Lagerhaus des ersten Akts war der größte Fall: die Westwand lag
fünfeinhalb Meter tief in der achtzehn Meter breiten Nord-Süd-Achse — eine
dreiundvierzig Meter lange, sieben Meter hohe Wand quer über der Fahrspur.
Zwischen den Achsen bleiben 43,5 Meter frei und das Gebäude ist 43 Meter
breit; es passt, aber nur mit einem halben Meter Luft auf jeder Seite. Der
Gehweg bleibt dabei nicht frei — dafür wäre der Missionsraum auf dreißig
Meter zu schrumpfen. Frei ist, worauf gefahren wird. Verschoben wurde alles
mit: Wände, Tor, drei Kisten, Boden, Dachbinder, Schriftzug, Festplatte und
die drei Missionspunkte. Der Sicherungskasten hing an der Ostwand, wo jetzt
ein halber Meter Platz ist; er sitzt an der Südwand, wo drei Meter bleiben.

Der erste Akt hatte bis dahin **keine einzige Prüfung**. Er hat jetzt sechs:
alle vier Punkte betretbar, Wachmann am Tor, Sicherung öffnet und schaltet
weiter, Festplatte schaltet weiter, Bootshaus beendet den Akt, und der Weg
vom Tor zur Festplatte ist frei. Ohne die wäre das Verschieben ein Blindflug
gewesen.

Danach: **null Wandstücke in einer Fahrbahn**, 197 Prüfungen bestanden.

## Die Fahrprüfung fuhr in einen Laden

Nebenbefund und eigene Schuld: die Prüfung „Fahrzeug bricht bei voller
Lenkung aus" ließ den Wagen dort stehen, wo die Prüfungen davor ihn gelassen
hatten. Bei vollem Gas und vollem Einschlag sind das in drei Sekunden gut
sechzig Meter Bogen. Nach dem Umzug lag Supply & Style im Weg, der Wagen
blieb mit -0,7 m/s an der Wand kleben, und die Prüfung meldete einen
Fahrfehler, den es nicht gab. Der Wagen startet jetzt an einem festen Platz
auf der Südtangente: siebzig Meter in jede Richtung frei, trocken, eben.
Dieselbe Sorte Fehler wie beim Bremstest — ein Messplatz, der sich mit der
Karte ändert, misst irgendwann etwas anderes als gemeint.

## Ein Ort, der nur ein Name war

Nach dem Umzug der Gebäude die naheliegende nächste Frage: Welcher benannte
Ort hat überhaupt ein Bauwerk? Gezählt wurden stehende Instanzen — Oberkante
über 1,2 Meter — im Umkreis von achtzehn Metern um jeden der achtundzwanzig
Marker. Die Rangliste von unten:

| Ort | stehende Teile |
| --- | --- |
| Isla Serena (Fähre) | 0 |
| Luftfracht | 1 |
| Iron Tide Gym | 2 |
| Mercy Dragstrip | 3 |
| Basketball | 4 |
| **Northstar Fuel** | **5** |
| Relaisstation | 753 |

Die fünf bei Northstar Fuel gehörten zum Nachbarhaus. Tanken funktionierte,
der Ort hatte einen Namen, ein Menü und einen Preis — und kein Gebäude. Der
Marker lag neun Meter tief im achtzehn Meter breiten Boulevard: man tankte
auf der Fahrspur.

Jetzt steht dort eine Tankstelle: Vorplatz mit Bordkante, Vordach auf vier
Stützen mit drei Leuchtbändern, zwei Zapfinseln mit vier Säulen, Kiosk mit
Fensterband, Poller, Mülleimer und ein Preistotem zur Straße. **32 stehende
Teile** statt fünf. Zapfinseln und Kiosk sind auch Hindernisse, nicht nur
Bilder.

Zwei Dinge, die dabei auffielen und ohne Bild nicht aufgefallen wären:

Der Vorplatz lag zuerst in einem blaustichigen Grau. Im Schatten des Vordachs
beleuchtet ihn nur noch der Himmel — auf dem ersten Bild sah der Vorplatz aus
wie ein Schwimmbecken. Ein warmes Betongrau bleibt auch unter reinem
Himmelslicht Beton.

Und die Leuchtbänder unter dem Dach erhellten nichts. Leuchtende Flächen sind
in dieser Welt nur helle Flächen; der Vorplatz blieb nachts schwarz, während
das Dach hell war. Vier echte Punktlichter hängen jetzt am selben Vorrat, aus
dem sich die Innenräume bedienen. Nachts ist die Tankstelle damit das, was
eine Tankstelle nachts ist: eine helle Decke über hellem Beton in einer
dunklen Straße.

## Und die drei anderen

Iron Tide Gym, Mercy Air Cargo und der Fähranleger von Isla Serena, in
derselben Ordnung: Platz suchen, bauen, prüfen.

**Das Gym** steht jetzt als Halle mit Glasfront zur Straße, Dachschild,
Eingangsvordach, Klimmzuggerüst, zwei Bänken und einem Reifenstapel. Zwölf
stehende Teile statt zwei.

**Mercy Air Cargo** ist die Adresse, an die Akt 2 die Zeugin bringt, und
bestand aus einer einzigen Instanz. Jetzt: Halle mit Tonnendach und
segmentiertem Tor, Vorfeld mit Markierung, sechs Container in zwei Reihen,
Paletten, Waage, Zaun und Windsack. Siebzehn statt eins.

**Der Fähranleger** lag vierzig Meter im Landesinneren. Isla Serena ist das
Rechteck 235 bis 360, die Westküste eine gerade Linie bei x = 235 — der
Marker stand bei x = 275, mitten auf der Insel. Der erste Versuch bei z = 215
setzte die festgemachte Fähre quer über den Damm bei z = 200; sichtbar wurde
das erst auf dem Bild, auf dem Autos direkt neben dem Schiffsrumpf fuhren.
Gesucht wurde deshalb die z-Lage entlang der Küste, an der Landseite und
Wasserseite je drei Meter Abstand zu jeder Fahrbahn haben, die Landseite
trocken und die Wasserseite nass ist und keine Kulisse im Weg steht: von 121
geprüften Lagen bleiben drei übrig, alle bei z ≈ 171. Dort steht jetzt Kai,
zwei Stege auf Pfählen, Wartedach mit Bänken, Kassenhaus, Poller,
Fahrplantafel und eine festgemachte Fähre.

Zwei Dinge kamen dabei heraus, die nichts mit den drei Orten zu tun haben:

**Bäume wachsen durch spät gebaute Häuser.** Das Laubwerk sammelt seine
Einträge während `dressRegions` und pflanzt sie erst danach. Wer am Ende ein
Gebäude hinstellt, bekommt Stämme durchs Dach — auf dem ersten Bild der
Luftfracht war das gut zu sehen. Die vier Grundrisse räumen ihre Rechtecke
jetzt selbst frei. Der erste Versuch reichte nicht: die Funktionen liefen
mitten in `dressRegions`, und die Regionen danach pflanzten wieder hinein.
Drei Bäume blieben stehen. Jetzt laufen sie als Letzte.

**Jeder Ort trug seinen Namen zweimal.** Zehn Meter vor jedem Marker
schwebt eine Schrift mit dem Ortsnamen. Bei einem Gebäude mit eigenem
Schild stand der Name danach zweimal da, der schwebende schräg in der
Fassade. Die vier neuen Orte beschriften sich selbst.

202 Prüfungen bestanden, keine gefallen.

## Vier von fünf Rennen waren nicht zu starten

Der nächste Marker nach derselben Zählung war die Serena Regatta: achtzehn
Meter landeinwärts. Ein Bootsrennen verlangt, dass die Figur in einem Boot
sitzt, und ein Boot bewegt sich nur über Wasser — näher als neun Meter kam
man dem Marker mit einem Boot nie. Beim Nachsehen war der Fehler größer als
die Marke.

`action()` liefert den Dialog eines Ortes nur, wenn man **nicht** im Fahrzeug
sitzt; im Fahrzeug zählen ausgerechnet nur Werkstatt und Tankstelle.
`startActivity` verlangt umgekehrt ein Fahrzeug mit dem passenden Medium.
Beides zugleich geht nicht: **zu Fuß geht der Dialog auf und meldet „Du
brauchst ein Fahrzeug", im Fahrzeug geht er gar nicht auf.** Startbar war
allein der West Loop, und zwar über das H-Menü, weil dort ein eigener
Eintrag mit fester Prüfung auf genau diese eine Strecke steht.

Betroffen: Mercy Dragstrip, Cypress Enduro, Serena Regatta, Ripple Sprint.
Vier Strecken mit Kurs, Preisgeld, Richtzeit und Kontrollpunkten, die nie
jemand fahren konnte. Der Dialogtext sagt seit jeher „Rennen starten (im
Fahrzeug)".

Jetzt zählen Rennmarken auch im Fahrzeug, und der H-Eintrag startet die
nächstgelegene Strecke statt immer den West Loop. Alle fünf laufen, im
Spiel geprüft: Fahrzeug an den Marker, `action()`, Dialogeintrag.

## Die Marina lag an Land

Dabei aufgefallen: Serena Marina — Hauptsteg bei x = 250, Fingerstege bis
234, vertäute Boote bei 238. Die Westküste der Insel ist die Linie x = 235.
Die ganze Anlage stand auf Sand und Wiese, die Boote inklusive. Der Steg
liegt jetzt bei x = 226 im Wasser, über einen Landgang mit dem Ufer
verbunden; die Boote schwimmen bei 214, das Hafenhaus bleibt an Land.

205 Prüfungen bestanden, keine gefallen.

## Die Landebahn hatte Markierungen — und einen Belag, den ich übersehen habe

**Korrektur zum Abschnitt unten.** Die Behauptung „die Piste hatte keinen
Asphalt" war falsch. Sie hat einen, gebaut in `expanded-world.js`
(`box(-315, .09, 315, 25, .15, 155)`) samt Mittellinie. Ich hatte nur
`airfield()` in `regions.js` gelesen, dort Markierungen ohne Fahrbahn
gefunden und daraus geschlossen, es gäbe keine — statt nachzusehen, wo sonst
noch gebaut wird. Meine zweite Decke lag auf einem Zentimeter Abstand über
der ersten, mit einer zweiten Strichfolge in anderem Abstand: Flimmern und
doppelte Linien. Sie ist wieder draußen.

Was von dem Abschnitt bleibt: die flach liegenden Bahnkennungen (`text()` hat
jetzt einen `flach`-Parameter, vorher stand die „27" als drei Meter hohes
Brett quer über der Bahn), die Rennausstattung des Dragstrips und
`bahnRaeumen()`, das sieben Kulissenteile vom Asphalt geholt hat.

## Die Landebahn hatte Markierungen, aber keinen Belag

Mercy Dragstrip hatte drei stehende Teile im Umkreis von achtzehn Metern und
vier Kontrollpunkte auf einer Geraden von 124 Metern. Beim Nachsehen zeigte
sich: der Marker liegt an der Schwelle der Landebahn — das Rennen fährt über
die Piste, und das ist auch richtig so. Nur hatte die Piste Schwellenbalken,
Randbefeuerung und Grasschultern, **aber keinen Asphalt**. Die Markierungen
lagen auf der Wiese.

Und die Bahnkennung „27" stand als drei Meter hohes Brett quer über der Bahn,
weil `text()` nur senkrechte Tafeln kannte. Das ist jetzt ein Parameter: mit
`flach` liegt eine Schrift auf dem Boden. Kennungen an beiden Enden, 27 und 09.

Mein erster Versuch legte eine **zweite** Fahrbahn über die Piste, mit
Leitplanken auf der Randbefeuerung — doppelt gebaut, weil ich den fehlenden
Belag für einen fehlenden Dragstrip hielt. Der Belag gehört zur Bahn, die
Rennausstattung daneben. Jetzt: Asphalt und unterbrochene Mittellinie für die
Bahn; Startlinie, Startfelder und „1/8 MILE" aufgemalt; Startbaum,
Zeitnahmehütte, Tribüne, Reifenstapel und Zielpfosten für das Rennen.

Zwei Fehler dabei, beide von eigenen Prüfungen gefangen:

**Zeitnahme und Tribüne standen auf der Straße.** Westlich der Bahn läuft die
Nord-Süd-Achse bei x = -340 mit achtzehn Metern Breite; zwischen Bahnrand und
Fahrbahnrand sind vier Meter. Die Prüfung „Keine Hinderniswand liegt in einer
Fahrbahn", zwei Commits vorher für die Läden geschrieben, hat es sofort
gemeldet: 30 und 143 Quadratmeter. Alles Feste steht jetzt östlich, auf dem
Vorfeld.

**Auf dem Asphalt stand Kulisse.** Ein vierzehn Meter hoher Mast, fünf
Pfosten und ein Kasten, alle aus Funktionen, die nach `airfield()` laufen und
von der Bahn nichts wissen. Solange die Welt gebaut wird, liegen alle Klötze
noch als Liste in `world.groups` — erst `flush()` macht InstancedMeshes
daraus. Bis dahin lässt sich nachträglich aussortieren. Der erste Anlauf
filterte nach Bauteilhöhe und ließ zwei Bleche von zehn Zentimetern Stärke
stehen, die in anderthalb Metern Höhe über der Schwelle hingen. Maßgeblich
ist die Oberkante.

214 Prüfungen bestanden, keine gefallen.

## Die Landstraße war eine Stadtstraße mit Feldern daneben

Nach der Zählung der Parkplätze: **306 von 503 lagen weiter als 45 Meter vom
nächsten Gebäude entfernt**, 67 davon allein in Cane Hollow. Das Bild dazu
ist eindeutig — eine Landstraße durch Ackerland mit zwei durchgehenden
Parkreihen bis zum Horizont, dazu vier Meter Gehweg, Bordstein, Laternen alle
vierzig Meter, Hydranten, Mülltonnen, Zeitungskästen und Gullis.

Der Grund ist einfach: der Straßenbauer kannte nur eine Sorte Straße. Als die
Karte nach Westen und Süden verdoppelt wurde, bekam jede neue Fernstraße den
vollen Stadtausbau. Von 15,8 Kilometern Straße liegen 6,8 im freien Land —
also 43 Prozent.

`imStadtgebiet()` in `content.js` führt jetzt sieben Rechtecke: Innenstadt und
Hafen, Nordquartier, Westviertel, Sunset Suburbs, Rosalind, die Ringstraße von
Isla Serena und die Promenade an South Beach. Rechtecke statt Radien, weil die
bebauten Flächen rechteckig sind — es sind die Straßenraster selbst.

Daran hängen jetzt: Bordstein, Gehweg, Laternen, Gullis, Kleinkram und
Parkbuchten. Auf dem Land bekommt die Straße stattdessen ein Bankett aus
anderthalb Metern Schotter; ohne das läge sie als nacktes Asphaltband auf der
Wiese, und genau so sah Cane Hollow nach dem ersten Versuch aus. Laternen
stehen draußen nur noch im Umkreis von 34 Metern um eine Kreuzung.

Bordstein und Gehweg waren bisher **ein** Quader je Segment. Eine
Ausfallstraße beginnt aber in der Stadt und endet im Feld, also entstehen sie
jetzt in zusammenhängenden Läufen entlang der Strecke.

| | vorher | jetzt |
|---|---|---|
| Parkbuchten | 503 | 217 |
| davon ohne Gebäude im Umkreis von 45 m | 306 | 62 |
| Dreiecke Kreuzung Downtown 13 Uhr | 1.981.024 | 1.524.656 |
| Dreiecke Strand 13 Uhr | 1.499.858 | 1.043.238 |
| Draw Calls Kreuzung Downtown 13 Uhr | 1856 | 1817 |

Die 460.000 Dreiecke weniger sind kein Optimierungserfolg, sondern die Folge:
286 Wagen und einige Kilometer Gehweg, die dort nie hingehörten. Innerhalb
der Stadt ist die Dichte unverändert — dieselbe Regel, dieselbe Streuung.

Zwei Prüfungen dazu, und eine davon war zuerst falsch gestellt: „Die
Landstraße trägt keinen Gehweg" suchte nach Platten von 4,2 Metern Breite und
18 Zentimetern Höhe und meldete zwei Bootsstege in Pelican Key, die zufällig
dasselbe Maß haben. Auch die zusätzliche Bedingung „höchstens zwölf Meter
neben einer Fahrbahn" half nicht — die Stege liegen zehn Meter neben dem Keys
Highway. Der Erbauer führt seine Gehwegläufe jetzt selbst mit; über das Maß
allein ist eine Platte nicht sicher zu erkennen.

Die dritte Prüfung war die alte: „Es stehen genug Wagen am Bordstein" verlangte
mehr als 250 Plätze und fiel bei 217. Die Zahl allein sagt nichts über eine
Stadt, wenn die Hälfte davon auf dem Land stand. Sie verlangt jetzt 190 und
bekommt eine zweite Prüfung an die Seite: kein Wagen parkt an einer Landstraße.

216 Prüfungen bestanden, keine gefallen.

## Zweiundzwanzig Prozent des Verkehrs fuhren über die Wiese

Die Gegenprobe zur Landstraße: fährt dort überhaupt jemand? Vier von 34
Straßensegmenten hatten keinen Verkehr — die beiden Längsachsen des
Westviertels und seine zwei Querstraßen. Ein Wohnviertel, eigens für die
größere Karte gebaut, mit vier toten Straßen.

Die Runde dafür war schnell ergänzt. Die Prüfung, die dabei entstand, war der
eigentliche Fund: **716 von 3209 Proben entlang aller Verkehrsrouten lagen
neben der Fahrbahn.** Zwölf von fünfzehn Runden verließen mindestens einmal
die Straße. Drei Ursachen:

- Der Spurversatz war fest getippt, sechs bis zehn Meter. Auf der zwölf Meter
  breiten Uferstraße liegt ein Versatz von zehn Metern vier Meter **hinter**
  der Kante — 91 von 92 Proben einer Kante daneben.
- Die Rückfahrt einer Runde lief 408 Meter entlang x = -1050. Dort gibt es
  keine Straße; die Westumgehung und die Südtangente enden beide bei x = -1060,
  ohne Verbindung dazwischen.
- Zwei Runden schlossen sich über eine Diagonale durchs freie Feld, eine davon
  367 Meter lang.

Eine der fünfzehn Runden trug schon einen Kommentar dazu: „die Rückfahrt muss
innerhalb dieser Enden bleiben, sonst führt der Weg über die Wiese". Der Fall
war einmal gesehen und für diese eine Runde behoben worden.

Jetzt nennt eine Runde nur noch vier Achsen. `ring()` sucht die Straßen, die
den Bereich wirklich abdecken, und setzt die Ecken um eine Spurbreite nach
innen — überall so, dass 3,2 Meter Fahrbahn zwischen Wagenmitte und Kante
bleiben, unabhängig von der Breite. Findet es keine Straße, entsteht die Runde
gar nicht, statt Wagen über die Wiese zu schicken. Wo sich keine Runde
schließt — Keys Highway, Uferstraße nach Isla Serena, Ostteil der Südtangente
—, fährt der Verkehr hin und zurück, auf der einen Spur hin, auf der anderen
zurück.

| | vorher | jetzt |
|---|---|---|
| Runden | 15 | 17 |
| fahrende Wagen | 116 | 127 |
| Straßensegmente mit Verkehr | 30 von 34 | 34 von 34 |
| Proben neben der Fahrbahn | 716 von 3209 | 0 |

218 Prüfungen bestanden, keine gefallen.

## Der Verkehr fährt auch wirklich dort

Routen auf der Straße heißt nicht, dass die Wagen darauf bleiben. Dreißig
Sekunden Simulation, jede Sekunde jeder fahrende Wagen: **1905 Proben, null
neben der Fahrbahn, null stehengeblieben** — und vier im Wasser.

Die vier standen alle bei x = -815. Der Ridge Highway liegt bei x = -820 und
ist siebzehn Meter breit, seine Ostkante also bei -811,5. Der Stausee reichte
mit seiner Westspitze bis -818: sechseinhalb Meter Fahrbahn lagen über dem
See. Die Halbachse ist jetzt 106 statt 118, die Uferböschung in `regions.js`
zieht mit (sonst bliebe zwischen Wasserkante und Böschung ein trockener Ring),
und die Ellipse steht nur noch an einer Stelle — vorher einmal in `content.js`
für `waterAt()` und einmal in `water.js` für den Shader.

Beim Nachzählen fielen **sechzehn Fichten im See** auf. Sie kommen aus dem
Bewuchs von Talon Ridge: dessen Streubereich reicht im Südosten bis x = -570
und z = 90 und damit in den Stausee, und er prüfte auf Straße und Hindernis,
aber nicht auf Wasser.

Drei Prüfungen dazu. Die erste Fassung stand vor den Aktprüfungen und ließ
„Akt 4 zahlt aus und führt in Akt 5" fallen — dreißig Sekunden Simulation
bewegen Uhr, Wetter und Figurenzustände weiter. Dieselbe Sorte Fehler wie
damals bei der Bremsprüfung, nur diesmal von der neuen Prüfung verursacht
statt gefunden. Sie steht jetzt als letzte vor dem Schließen des Browsers.

221 Prüfungen bestanden, keine gefallen.

## Sechs Leute liefen ins Meer

Dieselbe Messung für die Figuren: 12.420 Proben über dreißig Sekunden.
**Null in einer Wand.** 6,9 Prozent auf einer Fahrbahn — das sind die
Überquerenden, die dort hingehören. Und **28 Proben im Wasser**, alle bei
x ≈ 120 am Ostufer, verteilt auf sechs Personen.

Der Grund steht in der Platzierung: Startpunkt und Ziel eines Rundgangs
werden beide geprüft, aber der Startpunkt gegen Straße, Hindernis **und**
Wasser, das Ziel nur gegen Straße und Hindernis. Wer am Ufer steht und
zwanzig Meter nach Osten läuft, läuft ins Meer.

Dazu ein zweiter Nachlauf, nach demselben Muster wie der für die Fahrbahnen:
die Figuren entstehen an vier Stellen mit unterschiedlicher Absicht, und die
Rundgänge aus `simulation.js` und die Menge führen über feste Strecken. Ein
Wegpunkt darin kann im Meer liegen, auch wenn niemand dort steht. Solche
Punkte werden jetzt durch die Standposition ersetzt — die Runde wird kürzer,
aber sie bleibt an Land.

223 Prüfungen bestanden, keine gefallen.

## Rosalind war eine Stadt aus Straßen ohne Häuser

Die Regionsvermessung führt Rosalind seit Langem in der Arbeitsliste. Das
Bild erklärt warum: ein Straßenraster mit Gehwegen, Laternen, Ampeln,
Leitungsmasten und parkenden Wagen — und leeren Blöcken dazwischen.

Der Grund war nicht fehlende Kulisse, sondern eine Bedingung. Die Ladenzeile
der Hauptstraße steht sechzehn Meter neben der Straßenachse und wird mit
`aufStrasse(x, z, 13)` gegen die Fahrbahn geprüft. Die Hauptstraße ist
sechzehn Meter breit, ihr Rand liegt also acht Meter von der Achse; mit einem
Zuschlag von dreizehn reicht die Prüfzone bis 21 Meter. **Alle zweiundzwanzig
Läden wurden übersprungen** — die zweite Stadt hatte nie ein einziges
Geschäft. Gefunden nicht am Bild, sondern beim Nachrechnen der Bedingung.

`passtNebenStrasse()` prüft jetzt die Grundfläche gegen die Fahrbahnen statt
einen Punkt mit geratenem Zuschlag, mit einem halben Meter Luft: in einer
Kleinstadt steht die Ladenzeile am Gehweg, und das Vordach ragt darüber.
Verboten ist die Fahrbahn, nicht der Bürgersteig.

Damit standen zwölf Läden — **und steckten in der Wohnhausreihe.** Der Block
zwischen z = 300 und z = 340 ist vierzig Meter tief; die Läden sitzen bei 324
und sind vierzehn Meter tief, die Häuser saßen bei 320 und sind zwölf tief.
Elf überlappende Paare. Vorher gab es das Problem nicht, weil es die Läden
nicht gab. Jetzt: Geschäfte an der Hauptstraße, Wohnen an den äußeren Seiten
der Nebenstraßen, und dazwischen Hinterhöfe mit Garage, Schuppen, Beet und
Zaun.

Die Prüfung dazu zählt nur Baukörper — mindestens drei Meter hoch, sieben
Meter in der kürzeren Kante, nicht flacher als ein Viertel davon, mit dem Fuß
auf dem Boden — und erst ab zwölf Metern Abstand der Mittelpunkte sind es
zwei Gebäude statt Sockel, Turm und Anbau desselben. Ohne diese beiden Filter
meldete sie 54 Paare, von denen 52 keine waren: Sockelgeschosse unter ihren
Türmen und sechs Betriebsgebäude, die auf der Sohle des Steinbruchs stehen.
Übrig bleiben zwei alte Fälle, beide gewollt.

Ein Ergebnis gegen die Erwartung: **der örtliche Kontrast von Rosalind ist
gesunken**, von 11,04 auf 10,74, obwohl die Stadt jetzt Häuser hat. Der
Schnitt über alle Regionen fiel von 13,93 auf 13,67. Das liegt nicht an
Rosalind, sondern an der Landstraße: parkende Wagen, Gehwegplatten und
Hydranten sind hochfrequente Kanten, und das Maß zählt Kanten. Cane Hollow
fiel von 14,36 auf 13,78, weil dort 67 Wagen weniger am Feldrand stehen. Das
Maß war gut darin, kahle Flächen zu finden — den glatten grünen Kuppelgipfel
auf Talon Ridge —, aber es ist keine Note für Qualität.

225 Prüfungen bestanden, keine gefallen.

## Vier Wetter, die man nicht auseinanderhalten konnte

Gemessen an derselben Kreuzung um 13 Uhr, mittlere Bildhelligkeit von 255:

| Wetter | vorher | jetzt |
|---|---|---|
| klar | 148,1 | 148,1 |
| Regen | 145,8 | 127,7 |
| Nebel | 136,2 | 131,0 |
| Gewitter | 139,5 | 116,0 |

**Zwölf von 255 lagen zwischen wolkenlosem Mittag und Gewitter.** Nicht, weil
das Wetter nichts täte — die Sonne wird bei Gewitter auf 22 Prozent gedämpft
—, sondern weil die Streuung im selben Atemzug auf das 1,3-fache steigt. Der
Kommentar dazu steht seit Langem im Code: „sonst wirkt jedes Schlechtwetter
wie Nacht". Der Ausgleich war nur zu genau; er hob die Dämpfung fast
vollständig auf.

Jedes Wetter hat jetzt zusätzlich einen Faktor auf die Belichtung: Regen
0,80, Nebel 0,93, Gewitter 0,73. Nebel bleibt fast so hell wie klar, und das
ist richtig so — Nebel streut das Licht, er nimmt es nicht weg. Er kostet
Sicht und Kontrast, nicht Helligkeit.

Der Regen selbst war zu dünn: 1900 Striche in einem Feld von 74 auf 74 Metern
sind 0,35 Tropfen je Quadratmeter, und die Hälfte davon fiel jenseits der
Sichtgrenze. Jetzt 2600 Striche auf 46 auf 46 Meter — 1,23 je Quadratmeter —,
kürzer, und bei Regen werden zwei Drittel davon gezeichnet, bei Gewitter alle.

Drei Prüfungen dazu. Sie stehen am Ende des Laufs, weil sie Uhrzeit, Wetter
und Kamera umstellen: weiter oben eingesetzt ließen sie „Akt 4 zahlt aus und
führt in Akt 5" fallen, weil der vierte Akt bei Nacht spielt. Das ist
innerhalb einer Sitzung der zweite Fall derselben Sorte.

228 Prüfungen bestanden, keine gefallen.

## Das Spiel begann im dunkelsten Moment des Tages

LOWTIDE startet um 18:40 Uhr am Hafen. Gemessen an genau dieser Stelle über
den ganzen Tag:

| Uhrzeit | Mittel vorher | unter 10/255 | Mittel jetzt | unter 10/255 |
|---|---|---|---|---|
| 6:00 | 71,1 | 4,2 % | 81,8 | 0,0 % |
| 7:00 | 71,3 | 19,2 % | 99,4 | 0,3 % |
| 13:00 | 111,9 | 5,5 % | 111,9 | 5,5 % |
| 18:00 | 64,6 | 21,6 % | 77,7 | 6,8 % |
| **18:40** | **48,2** | **38,9 %** | **80,9** | **1,8 %** |
| 19:30 | 60,7 | 10,0 % | 75,4 | 0,0 % |
| 23:00 | 64,2 | 0,0 % | 64,2 | 0,0 % |

Der Startzeitpunkt war der dunkelste Moment des ganzen Tages — dunkler als
Mitternacht, mit **fast vierzig Prozent der Bildfläche unter 10 von 255**.
Ein früherer Anlauf hatte die Belichtungskurve schon monoton gemacht; das
war nötig, aber nicht die Ursache.

Die Ursache ist `nacht`. Der Wert steuert Sterne, Himmelsfarbe **und** alles
künstliche Licht, und er ist bei null, solange die Sonne höher als etwa
sieben Grad steht. Um 18:40 steht sie bei acht Grad: zu tief, um zwischen den
Häusern die Straße zu erreichen, und zu hoch, um die Laternen einzuschalten.
Eine halbe Stunde ohne Sonne und ohne Licht.

`lampen` ist derselbe Gedanke, nur früher: der Wert steigt, sobald die Sonne
unter fünfundzwanzig Grad fällt, und daran hängt jetzt alles Künstliche —
Straßenlaternen, Fenster, Scheinwerfer, Rücklichter, Ampeln, ferne Fahrzeuge
und die Schattenaufhellung der Nachbearbeitung. Sterne und Himmelsfarbe
bleiben an `nacht`. Straßenbeleuchtung geht in Wirklichkeit auch vor
Sonnenuntergang an.

Der Startbildschirm: mittlere Helligkeit 67,5 → 89,7, abgesoffene Fläche
28 % → 3,7 %, Sättigung 54,6 % → 36,2 %. Dieselbe Dämmerungsstimmung, nur
lesbar.

Drei Prüfungen: keine Stunde dunkler als Mitternacht, nirgends säuft ein
Fünftel des Bildes ab, und am Mittag brennt keine Laterne.

231 Prüfungen bestanden, keine gefallen.

## Streifenwagen fuhren über Plätze und Grünflächen

Dieselbe Frage wie beim Verkehr, jetzt für die Polizei: eine Straftat, zwanzig
Sekunden Verfolgung, alle halbe Sekunde jeder aktive Streifenwagen geprüft.
**Elf von fünfundneunzig Proben lagen neben jeder Fahrbahn.**

`findPath()` kannte nur zwei Zustände, frei und blockiert. Für Fußgänger
reicht das; ein Wagen quert damit jeden Platz, jede Wiese und jeden Vorhof,
solange nichts darauf steht. Die Funktion nimmt jetzt eine dritte Angabe: ein
Gewicht je Feld. Straße kostet 1, alles andere 3,5. Der Wagen nimmt den Umweg
über die Straße, solange er nicht ein Vielfaches länger ist — und kann eine
Grünfläche immer noch überqueren, wenn es keinen anderen Weg gibt. Die
A*-Heuristik bleibt zulässig, weil kein Feld weniger als 1 kostet.

Danach: null von fünfundneunzig. Die Annäherung dauert dafür etwas länger —
nach zwanzig Sekunden ist der nächste Wagen 131,8 statt 116,5 Meter entfernt.
Das ist der Preis dafür, dass er die Straße nimmt.

Was in Ordnung war: vier Streifen rücken aus, die Fahndung steigt auf zwei
Sterne, kein Wagen fährt ins Wasser, und weit genug weg endet sie wieder.

234 Prüfungen bestanden, keine gefallen.

## Aus hundert Sachen in fünf Metern zum Stehen

Das Fahren ist der Kern des Spiels und war nie gemessen. Fünfzehn Fahrzeuge,
je Höchstgeschwindigkeit, Beschleunigung, Bremsweg und Wendekreis:

| | Spitze | 0–100 km/h | Wendekreis |
|---|---|---|---|
| Finch (compact) | 90 km/h | — | 7 m |
| Kestrel S (sedan) | 108 | 2,4 s | 12 m |
| Banshee 68 (muscle) | 133 | 1,9 s | 16 m |
| Vesper R (super) | 176 | 1,6 s | 8 m |
| Wraith (motorcycle) | 151 | 1,6 s | 8 m |
| Atlas Hauler (truck) | 83 | — | 20 m |
| Cormorant (plane) | 234 | 3,3 s | — |

Spitzen und Wendekreise sind stimmig, die Beschleunigung ist arcadehaft
schnell — das ist eine Entscheidung, keine Panne, und sie bleibt.

Der Bremsweg war eine Panne. **Aus 100 km/h stand der Kestrel nach 5,2
Metern**, der Banshee nach 6,4, der Atlas Hauler nach 9,8. Und ohne Gas
rollte jedes Fahrzeug in 41 Metern aus. Beides kam aus derselben Zeile: Tempo
mal einem Exponentialfaktor je Bild, mit `brake/5` als Rate. Ein
Exponentialabfall bremst am Anfang brutal und am Ende gar nicht — das genaue
Gegenteil einer Bremse.

Jetzt ist beides eine Verzögerung in Metern je Sekundenquadrat. `brake` aus
`content.js` bleibt die Kennzahl, mal 0,39 ergibt die Verzögerung: Kestrel
9,0 m/s², Vesper 11,7, Atlas Hauler 4,7. Nasse Fahrbahn und abgefahrene
Reifen verlängern den Weg. Das Ausrollen ist Rollwiderstand plus
Luftwiderstand, quadratisch mit dem Tempo.

| aus 100 km/h | vorher | jetzt |
|---|---|---|
| Kestrel, Vollbremsung | 5,2 m | 42,3 m |
| Banshee, Vollbremsung | 6,4 m | 51,4 m |
| Atlas Hauler, Vollbremsung | 9,8 m | 57 m (aus 83 km/h) |
| Kestrel, ohne Gas ausrollen | 41 m | 133 m |

Der Verkehr und die Polizei fahren nicht über `driveVehicle`; die Änderung
betrifft nur das Fahrzeug unter dem Spieler.

236 Prüfungen bestanden, keine gefallen.

## Die Karosserie stand starr auf der Straße

Mit ehrlichen Bremswegen fiel auf, dass sich beim Bremsen nichts bewegt. Der
Wagen hatte genau eine Neigung: ein Wackeln um die Längsachse, proportional
zum Tempo, plus fünf Hundertstel Schräglage bei unter vierzig Prozent
Fahrzeugzustand. Kein Nicken, kein Wanken.

Beides kommt jetzt aus der Bewegung selbst: die Längsbeschleunigung kippt die
Nase, Gierrate mal Tempo legt den Wagen in die Kurve, beides geglättet, damit
ein einzelner Schlag nicht zuckt. Gemessen am Kestrel:

| | Nicken | Wanken |
|---|---|---|
| Vollgas aus dem Stand | -3,4° (Nase hoch) | 0 |
| Vollbremsung aus 100 km/h | +3,0° (Nase runter) | 0 |
| Rechtskurve bei 60 km/h | | -4,0° (rechts runter) |
| Linkskurve bei 60 km/h | | +4,0° |
| Stand | 0,00° | 0,00° |

Motorräder und Jetskis legen sich mit dem 2,2-fachen Winkel.

Dabei fiel eine Prüfung, die nichts damit zu tun hatte: „Die Kamera erkennt
Tiere im Bild". Sie setzte die Figur zwölf Meter vor einen Alligator, zählte
die Tiere im Blickfeld nach vorn und nach hinten und verlangte, dass vorn
mehr sind. Das stimmt nur, solange hinter der Figur zufällig weniger Möwen
und Fische liegen als davor — mein Abschnitt ließ die Tierwelt sechs Sekunden
weiterlaufen, und die Verteilung kippte. Für die Dauer der Prüfung bleibt
jetzt genau ein Alligator übrig; zusätzlich muss er aus neunzig Metern
Entfernung nicht mehr zählen. Das ist innerhalb dieser Sitzung die dritte
Prüfung, die selbst falsch gestellt war.

239 Prüfungen bestanden, keine gefallen.

## Der Sumpf war ein Lagerplatz für grüne Paletten

Ein Bilddurchgang über fünf Gegenden, so wie er vorher die Marina und
Rosalind gefunden hat. Der Salt Marsh: hunderte flacher grüner Kisten auf
dünnen Stelzen, dicht an dicht über dem Wasser. Aus der Ferne geht das als
Mangrovendickicht durch, aus zwanzig Metern nicht.

Drei Quellen, alle mit demselben Muster — Pfosten plus Kiste:

| Ort | Zahl | Krone vorher |
|---|---|---|
| `saltMarsh()` in regions.js | 260 | eine Kiste, h·0,95 × h·0,5 × h·0,9 |
| `mangrove()` in regions.js (Keys) | ~90 | drei gestapelte Platten |
| `build()` in expanded-world.js, Sumpf | 45 | eine Kiste 4 × 1 × 4 |
| `build()` in expanded-world.js, Nationalpark | 155 | ein Würfel 4 × 4 × 4 |

Alle vier gehen jetzt über dasselbe Laubwerk wie jeder andere Baum: gekreuzte
Flächen mit zur Laufzeit gezeichneter Alphakarte, zwei Instanzennetze für die
ganze Karte. Das kostet **keinen** zusätzlichen Draw Call — die Bäume liefen
schon vorher über diese beiden Netze, es kommen nur Einträge dazu. Gemessen
an der Kreuzung: 1817 → 1802 Draw Calls, 1.524.656 → 1.543.028 Dreiecke.

Die Art heißt bei Mangroven `'mangrove'`, damit die Prüfung „kein Baum steht
im Wasser" sie auslässt — ein Mangrovenwald steht genau dort.

Der Bilddurchgang hat außerdem die falsche Landebahn-Behauptung ans Licht
gebracht (siehe Korrektur weiter unten).

239 Prüfungen bestanden, keine gefallen.

## Die Straße über den Rücken war eine Treppe

Derselbe Bilddurchgang, Talon Ridge: die Straße den Hang hinauf besteht aus
einer Reihe dunkler Platten mit Lücken dazwischen. Die Fahrbahn wird seit
Langem in Zwölf-Meter-Stücken gebaut, damit sie dem Gelände folgt — aber
jedes Stück liegt **waagerecht**. Am Hang steht damit die eine Kante in der
Luft und die andere im Boden.

Die vorhandene Prüfung „Fahrbahnen liegen auf dem Gelände" fand nichts, weil
sie die Mitte jedes Stücks misst, und die Mitte stimmt. Erst der Blick aus
zweihundert Metern zeigt die Treppe.

Jedes Stück nimmt jetzt die Neigung aus seinen eigenen beiden Enden —
Nord-Süd-Straßen kippen um die x-Achse, Ost-West um die z-Achse. Berme,
Leitplanke und Decke kippen mit. Dieselbe Behandlung bekommen die Feldwege
im Hinterland und die Schotterpiste zur Leitungstrasse: zweiunddreißig
Platten, die als schwebende Rhomben den Hang hinunterliefen, liegen jetzt
mit bis zu dreißig Grad Neigung auf.

Die neue Prüfung zählt Deckenstücke über sechs Meter Geländehöhe und
verlangt, dass die geneigten überwiegen.

240 Prüfungen bestanden, keine gefallen.

## Der Boden war überall gleich grün

Die Farbe des Geländes kam aus einer einzigen Frage: in welchem Rechteck der
Karte liegt der Punkt. Vier Rechtecke, dazu Wasser und ein Sandsaum — das war
alles. Jeder Scheitelpunkt einer Region bekam damit denselben Wert: eine
Kachel von hundert Metern trug 169 Punkte in exakt einem Grün, die Kuppe von
TALON RIDGE auf 88 Metern dasselbe Grün wie die Wiese auf Meereshöhe, und
eine Steilflanke dasselbe wie der Acker davor. Der Boden ist die größte
Fläche in jedem Bild draußen.

Drei Größen kommen dazu, alle rein aus der Weltposition gerechnet, damit zwei
aneinandergrenzende Kacheln am gemeinsamen Rand denselben Wert bekommen und
keine Naht entsteht:

* **Höhe** — über 40 Metern wird die Wiese trocken, über 72 Metern ist sie Fels.
* **Neigung** — was steiler als etwa fünfzehn Grad steht, hält keine Grasnarbe.
* **Rauschen** — grob (34 Meter Wellenlänge) für Flecken aus Fels und Moos,
  fein für ±8,5 Prozent Helligkeit von Punkt zu Punkt.

Nachgemessen an den Scheitelfarben, nicht am Bild — das ist von Grafikkarte
und Uhrzeit unabhängig. Innerhalb desselben Farbrechtecks (x < -600, z > -230,
also der Rücken und sein Fuß) hat der Boden oben einen Grünstich von **-0,0072**
und unten von **+0,0302**; oben ist er außerdem heller (0,144 gegen 0,081).
Von Punkt zu Punkt gleich sind noch 18 Prozent aller Nachbarpaare — das sind
die Wasserkacheln, die absichtlich einfarbig bleiben.

**Zwei Fehler dabei, beide von der Messung gefangen.**

Das Rauschen lief zuerst über `offsetHSL(0, 0, ±0,05)`. Das rechnet im
linearen Arbeitsraum, und dort hebt +0,05 einen dunklen Ton in sRGB weit
stärker, als -0,05 ihn senkt. SALT MARSH ist die dunkelste Gegend der Karte
und sprang dadurch von 128,7 auf **155,8** mittlere Helligkeit, die Sättigung
fiel von 39,4 auf **23,0** Prozent — aus einem Sumpf wurde eine helle Fläche.
Ein Faktor statt eines Summanden lässt Farbton und Sättigung, wo sie sind:
128,7 und 39,4 Prozent, unverändert.

Der erste Felston war `0x8b8377` — fast genau die Farbe der Findlinge, die
darauf liegen (`0x8a8175`). Die Kuppe war damit richtig steinig statt grün,
aber Block und Boden waren gleich hell, und der örtliche Kontrast blieb bei
9,75 stehen. Farbe richtig, Wirkung null. Jetzt ist der Boden mit `0x6e685d`
dunkler als das, was darauf liegt, und `0x5c6046` setzt Moosflecken dazwischen.

**Und ein Befund über das Werkzeug selbst.** TALON RIDGE steht in
`tools/schwachstellen.mjs` ganz oben auf der Arbeitsliste, aber sein Wert hat
sich über vier Umbauten des Bodens nicht bewegt: 9,73 → 9,71 → 9,75 → 9,74,
und die mittlere Helligkeit blieb in allen vier Läufen bei **185,2**, auf die
Stelle genau. Das ist keine Messung der Kuppe. Die Sonde steht sechzehn Meter
über dem Ankerpunkt und blickt fünfundvierzig Meter voraus; von einem
88-Meter-Gipfel fällt der Boden dabei so schnell weg, dass die untere
Bildhälfte Ferne im Dunst zeigt statt Gelände. Von zwei Richtungen wird die
mit dem höheren Kontrast gewertet, und das ist zuverlässig die Panoramaseite.
Der oberste Eintrag der Arbeitsliste misst also etwas anderes als die Gegend,
die er benennt. Das steht hier als Befund, nicht als behobene Sache — geändert
ist am Werkzeug nichts.

Im Bild ist der Unterschied da, wo man ihn erwartet: die Kuppe ist nicht mehr
Wiesengrün, sondern trockener Fels mit Flecken. Der Schnitt über alle fünfzehn
Gegenden geht von 13,76 auf 13,79; ROSALIND von 10,61 auf 10,80. Das ist
wenig, und es ist ehrlicher, das so zu schreiben, als eine Zahl zu suchen, die
besser aussieht.

246 Prüfungen bestanden, keine gefallen.

## Acht Puppenstuben ohne vordere Wand

Vom Gehweg aus sah man in den Undertow hinein wie in ein aufgeschnittenes
Modell: Tanzfläche, Tresen, Möbel, kein Stück Fassade davor. Dasselbe bei
allen acht Servicegebäuden. Das war kein Versehen — es steht so in
`interiors.js`: „Die Vorderseite bleibt offen: eine Schnittdarstellung statt
Ladetüren. Der Spieler läuft ohne Übergang hinein, die Kamera hat freie
Sicht."

Der Grund trägt. Eine volle Wand mit Tür wäre der ehrlichere Bau, kostet aber
genau das, was der Satz nennt: die Verfolgerkamera prüft Solids nur bis
Kopfhöhe (`y < b.h + .2`) und würde, sobald man drinnen in einer Ecke steht,
gegen eine fünf Meter hohe Front gedrückt.

Der Mittelweg steht jetzt da: eine **Brüstung von 1,1 Metern** links und
rechts einer **mittigen Tür von 4,5 Metern**. Hoch genug, dass niemand mehr
durch das Schaufenster spaziert; niedrig genug, dass die Kamera darüber
hinwegsieht. Dazu Türpfosten, ein Kämpfer und Sprossen alle 1,6 Meter — als
Kulisse, die nichts blockiert.

**Glas gibt es nicht.** `w.box` kann keine Durchsicht. Eine undurchsichtige
Scheibe würde den Raum zumauern, den sie zeigen soll, und eine Scheibe, durch
die man hindurchläuft, wäre schlechter als gar keine. Ein Rahmen ohne Scheibe
liest sich als sehr sauber geputztes Schaufenster.

Nachgemessen an allen acht Räumen:

| | Ergebnis |
|---|---|
| Freier Weg von draußen bis in die Raummitte | 0 blockierte Schritte, 8 von 8 |
| Durch das Schaufenster bei ±4 und ±6 Metern | 0 Durchgänge, 8 von 8 |
| Durch die Tür bei ±1,5 Metern | 3 von 3 Proben frei, 8 von 8 |
| Höhe der Brüstung | 1,1 m, zwei Stück je Raum |

Die Brüstung kommt als Solid aus `campaign.js` und wird von der Schleife in
`expanded-world.js` mitgezeichnet, die schon vorher alle Raumwände zeichnet —
eine Stelle geändert, zwei Wirkungen.

253 Prüfungen bestanden, keine gefallen.

## Der Boden war die einzige Fläche ohne Oberfläche

`world.js` hängt jedem Material der Welt `detailAufsetzen()` an: Flecken in
Farbe und Rauheit, Korn in den ersten Metern, eine gestörte Normale, nasser
Glanz bei Regen. Jede Kiste, jede Wand, jeder Findling trägt das. Der Boden
nicht — die Geländekacheln bekamen ein nacktes `MeshStandardMaterial` und
waren damit die einzige große Fläche im Bild, auf der nichts passiert.

Das erklärt auch, warum die Höhen- und Neigungsregel des vorigen Abschnitts
so wenig gebracht hat. Scheitel liegen 8,33 Meter auseinander; über
Scheitelfarben ist unterhalb von rund siebzehn Metern gar keine Struktur
darstellbar, egal wie fein man das Rauschen macht. Der Shader rechnet je
Bildpunkt und kann genau das, was dem Netz fehlt.

Eine Zeile, und dazu ein Material für alle 225 Kacheln statt 225 gleicher.
Die Kosten sind messbar null:

| | vorher | nachher |
|---|---|---|
| Kreuzung Downtown, 13 Uhr | 1802 Draw Calls | 1802 |
| Hafen, 13 Uhr | 1639 | 1639 |
| Strand, 13 Uhr | 1287 | 1287 |

**Und zwei Dinge, die die Zahlen nicht zeigen.** Der Schnitt in
`tools/schwachstellen.mjs` geht von 13,80 auf 13,84 — fast nichts, obwohl der
Unterschied im Bild sofort auffällt. Der Grund steht im Shader selbst: das
Korn wird zwischen sechs und sechsundzwanzig Metern ausgeblendet, weil es in
der Ferne flimmert. Die Sonde steht sechzehn Meter hoch und blickt
fünfundvierzig Meter voraus — der größte Teil der gemessenen Bildhälfte liegt
jenseits dieser Grenze. Gemessen wird also gerade das, was der Shader
absichtlich nicht anfasst.

Dasselbe gilt für die Flecken, die die ebene Wiese seit diesem Abschnitt
bekommt: 34 Meter Wellenlänge, weich verlaufend. Der örtliche Kontrast
vergleicht benachbarte Bildpunkte, und ein weicher Verlauf über 34 Meter
hinterlässt dort nichts. Sichtbar ist er aus der Höhe, messbar mit diesem
Werkzeug nicht.

250 Prüfungen bestanden, keine gefallen.

## Sieben Windräder, die ineinander fuhren

Vom Kamm aus stand im Bild ein Lattenzaun aus vier weißen Säulen. Nachgesehen
waren es die Türme des Windparks: sieben Stück auf einer Diagonalen quer über
die Flanke, alle 35,4 Meter einer. Ein Blatt ist vierundzwanzig Meter lang und
sitzt mit der Wurzel an der Nabe — der Rotor hat damit **achtundvierzig Meter
Durchmesser**. Die Kreise zweier Nachbarn überlappten sich um dreizehn Meter;
die Blätter fuhren durcheinander hindurch. Gedreht hat sich außerdem keines:
sie steckten als gebackene Klötze in der Blockliste, so unbeweglich wie ein
Zaunpfahl.

Zuerst gemessen, wie viel Platz da überhaupt ist. Der Kamm läuft auf x = -900
und liegt zwischen z = -370 und z = +40 über fünfundzwanzig Metern, das sind
rund 410 Meter Länge; über siebzig Metern bleiben nur noch 190. Quer zum Wind
ist der übliche Abstand einer Reihe drei Rotordurchmesser. Das sind hier 144
Meter — und damit passen **drei** Anlagen auf den Kamm, nicht sieben.

Jetzt stehen sie auf -900 bei z = -300, -156 und -12, die Naben auf 105,8,
140,0 und 102,4 Metern. Die Reihe läuft in z, die Nabenachse zeigt deshalb in
x: quer zum Kamm, nicht die Reihe entlang, sonst stünde jede Anlage im
Windschatten der davor.

Der Turm bleibt gebacken, denn er bewegt sich nicht. Die neun Blätter liegen
in einer eigenen `InstancedMesh` — ein Draw Call, egal wie viele Anlagen
dazukommen. Die Matrix je Blatt ist

    T(Nabe) · Ry(Achse) · T(0,0,2.6) · Rz(Winkel) · T(12,0,0) · S(24, 1.4, .35)

von rechts gelesen: Würfel auf Blattmaß strecken, Wurzel an die Nabe schieben,
um die Achse drehen, vor den Turm setzen, ausrichten, absetzen. Die Drehzahl
hängt am Wetter — 0,95 rad/s bei Klar sind gut neun Umdrehungen je Minute, im
Sturm 2,15 rad/s und damit gut zwanzig.

Zwei Dinge, die dabei leicht schiefgehen und hier ausdrücklich mitgebaut sind:
die einmal berechnete Hüllkugel bekommt einen Blattradius Zuschlag, weil sich
die Instanzmatrizen jedes Bild ändern und die Kugel den ganzen überstrichenen
Kreis fassen muss statt der Stellung von jetzt; und die Rotor-Mesh steht mit
in `world.bloecke`, damit `bloeckeSichten()` sie an derselben Nebelgrenze
ausblendet wie die Türme. Ohne das hätten aus der Innenstadt heraus neun
Blätter ohne Turm in der Luft gehangen.

**Einmal falsch gemessen.** Der erste Prüflauf las den Rotorwinkel nach
anderthalb Sekunden und bekam exakt null zurück; die zweite Probe hängte sich
in `updateExtras` und zählte null Aufrufe. Es sah nach totem Code aus. In
Wirklichkeit rendert SwiftShader diese Szene mit rund einem Bild alle sechs
Sekunden — in anderthalb Sekunden passiert schlicht kein Bild. Über sieben
Sekunden gemessen wuchs der Winkel um **0,0475 rad**, und das ist auf die
Stelle genau dt = 0,05 mal 0,95. Der Code war die ganze Zeit richtig, die
Wartezeit war falsch.

249 Prüfungen bestanden, keine gefallen.

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

**Die Tierwelt** kennt die neuen Dämme durch den Sumpf nicht — ihr Revier ist
ein festes Rechteck. Trotzdem liegt kein Tier an Land, und das ist kein
Zufall: Alligatoren werden nur auf Wasser gesetzt (`while(!waterAt)` neu
würfeln), und ihre Bewegung prüft vor jedem Schritt `waterAt` und dreht ab,
statt an Land zu kriechen. Über vier Beobachtungsrunden mit 106 Tieren:
keiner. Hier war der Code schon vorher richtig gebaut.

**Die vier Waffen** treffen innerhalb ihrer Reichweite und dahinter nicht.
Vierzig Schuss je Entfernung auf ein Ziel genau voraus:

| | 10 m | 30 m | 60 m | Reichweite laut Tabelle |
|---|---|---|---|---|
| Pistole | 40/40 | 40/40 | 40/40 | 65 m |
| Karabiner | 40/40 | 40/40 | 40/40 | 110 m |
| Schrotflinte | 40/40 | 0/40 | 0/40 | 23 m |
| Taser | 40/40 | 0/40 | 0/40 | 12 m |

Der erste Durchgang hielt den Taser für wirkungslos — er richtet keinen
Schaden an, er betäubt, und die Messung sah nur auf Lebenspunkte. Vierte
Prüfung in dieser Sitzung, die falsch gestellt war, diesmal vor dem
Eintragen bemerkt.

**Das Telefon** war das letzte Teilsystem, das in dieser Sitzung noch keiner
nachgemessen hatte — Verdacht: eine der elf Kacheln führt auf eine leere
Seite. Tut sie nicht. Alle elf (Karte, Nachrichten, Tideline, Bank, Wetter,
Kamera, Kontakte, Aufträge, Galerie, Radio, Besitz) zeigen echten Inhalt:
die Karte eine gezeichnete Leinwand, das Radio sieben Sender, Besitz acht
Immobilien, der Rest Text. Auch der Weg Kamera → Galerie schließt sich:
`sim.fotos` wächst von 0 auf 1, und in der Galerie steht die Aufnahme mit
Ort, Uhrzeit und dem Knopf zum Posten. Zwei Prüfungen halten das jetzt fest,
weil eine App, die niemand aufruft, still kaputtgehen kann.

**Der Spielstand** überlebt den vollen Rundlauf. Die Prüfung stand auf einem
einzigen Feld — Geld —; jetzt auf achtundzwanzig: Ort, Leben, Waffe mit
Magazin und Reserve, Kleidung, Haar, Tattoo, Fitness, Fänge, Uhrzeit, Wetter,
Vertrauen, Mission, Aktstufe, Relaisschalter, Besitz, Bestwerte, Kontoauszug,
Bergungsstand, Fahrzeugtuning, Fahrzeugzustand, Tankfüllung und die Frage, ob
die Figur beim Laden wieder in demselben Wagen sitzt. Kein Feld geht
verloren; ein Spielstand ist 203 KB groß.

Zusätzlich außerhalb der Prüfliste einmal von Hand nachgestellt, weil der
Rundlauf im Speicher nicht dasselbe ist wie einer über die Platte: Zustand
setzen, Seite neu laden, Spiel starten. Geld, Ort, Leben, Waffe, Kleidung,
Uhrzeit, Mission, Aktstufe, Vertrauen, Motelbesitz und Bestwerte kommen alle
zurück.

**Das Fensterraster der Innenstadthäuser**: vermutet fest verdrahtet und
damit bei breiten Wänden lückenhaft. Nachgemessen sind alle sechzehn Häuser
18,8 mal 38,8 Meter, das Raster deckt 14 von 18,8 und 32 von 38,8 — kein
Fenster ragt über eine Kante.

244 Prüfungen bestanden, keine gefallen.

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
