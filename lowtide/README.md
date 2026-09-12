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
node tools/regression.mjs                        # 96 Prüfungen, muss grün sein
node tools/abdeckung.mjs                         # Bauteile je 100-Meter-Zelle
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
waagerechte Flächen bei Nässe einen Strahl durch dieselbe Tiefe, die schon
die Verdeckung nutzt, und holt die Neonschilder und Laternen aus dem Bild
selbst. Auf einer waagerechten Fläche wird dabei nicht die aus den
Ableitungen gewonnene Normale benutzt, sondern Weltoben — die gerechnete
rauscht auf einer großen Ebene, und das Ergebnis waren Flecken statt der
Streifen, die nasser Asphalt tatsächlich zeigt.

`detail.js` hängt sich über `onBeforeCompile` in jedes Weltmaterial und legt
Farbflecken, Rauheitsschwankung und eine Normalenstörung darüber, dreifach
aus der Weltposition projiziert. Eine Textur ginge nicht: dieselbe
Kistengeometrie trägt eine 240-m-Platte und einen 20-cm-Poller.

Der Knopf „Grafik: sparsam" schaltet Nachbearbeitung, Schatten und
Pixelverhältnis zusammen ab.

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
