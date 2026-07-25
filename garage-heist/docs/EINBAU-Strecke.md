# Garage Heist – Rennstrecke, Verkehr, Onboarding

Basis: `GarageHeist__4_.rbxlx`. Alle Patches aus der letzten Runde sind drin
und korrekt – Z-Fighting weg, `ApplyLevel` verdrahtet, Cash zählt hoch.

**Prüfstand:** alle vier Dateien mit `luau-compile` übersetzt (Syntax und
Bytecode sauber). Die Streckenmathematik habe ich numerisch gegengeprüft:
200.000 Abtastungen, größter Positionssprung 0,0075 Studs bei 0,0075 Studs
Schrittweite, größter Richtungssprung 0,0001 – die Kurve ist an den acht
Segmentgrenzen stetig, keine Knicke. **In Studio getestet habe ich nichts.**

---

## Vier neue Dateien

| Datei | Ort in der Hierarchie |
|---|---|
| `TrackPath.lua` | `ReplicatedStorage/Shared/TrackPath` (ModuleScript) |
| `RaceTrack.lua` | `ServerScriptService/Server/World/RaceTrack` (ModuleScript) |
| `TrafficController.lua` | `StarterPlayerScripts/Client/Controllers/TrafficController` |
| `Onboarding.lua` | `StarterPlayerScripts/Client/UI/Onboarding` |

### TrackPath – die Kurve als Mathematik

Ein Stadionoval: zwei Geraden à 390 Studs in X, zwei à 140 in Z, vier
Viertelkreise mit Radius 70. Gesamtlänge 1.500 Studs. Liegt in `Shared`, weil
zwei Seiten dieselbe Kurve brauchen – der Server baut die Geometrie darauf, der
Client fährt den Verkehr darauf. Eine Quelle, keine Abweichung.

**Die Höhe 44 ist gerechnet, nicht geschätzt.** Von der Hofmitte aus (Augenhöhe
5) streift die Sichtlinie über ein 18 Studs hohes Garagendach bei z = 55 auf
Höhe 38,1, wenn sie z = 140 erreicht. Alles unter 38 wäre hinterm Dach
versteckt. Bei 44 siehst du die Autos von überall im Hof – das war der ganze
Punkt der Übung.

Ausdehnung x ±265, z ±140. Der Boden ist 900 × 620, passt mit 185 Studs Luft.
Zu den Garagen bleiben 31 Studs Abstand in Z, 102 in X – kein Pfeiler landet
auf einem Dach.

### RaceTrack – die Geometrie

Fahrbahn, Leitplanken mit leuchtender Oberkante (außen bernstein, innen cyan),
dunkler Unterzug, Randmarkierung, Mittelstriche auf den Geraden, 24
Stützpfeiler mit Leuchtstreifen.

Dazu **zwei Torbogen bei x = ±265 mit „GARAGE HEIST" in Michroma**. Die stehen
genau dort, weil der Hof in X verläuft: wer im Hof steht und nach links oder
rechts schaut, blickt die Achse entlang und sieht am Ende den Schriftzug mit
der Strecke darüber. Das ist der Blick, der das Spiel verkauft.

**Und der Teil, der wirklich zählt:** Deckung im Hof. Zehn Container (teils
gestapelt), fünf Rampen, vier Betonsperren, vier Lichtmasten mit echtem Licht.
Alles bleibt bei |z| ≤ 22, damit vor jedem Tor 30 Studs frei sind.

### TrafficController – 24 Autos, Serverkosten null

Drei Spuren mit je acht Autos, Grundtempo 74 / 96 / 122 Studs pro Sekunde.
Jedes Auto hält Abstand zum Vordermann und bremst unter 30 Studs Lücke – dadurch
entstehen Pulks und Lücken statt einer Perlenkette. In den Kurven legen sich die
Autos nach innen (aus dem Vergleich mit einem Punkt vier Studs voraus). Jedes
zieht eine Leuchtspur in seiner Farbe hinter sich her.

**Der Verkehr läuft komplett auf dem Client.** Vom Client erzeugte Instanzen
werden nie zum Server repliziert: 24 dauerhaft fahrende Autos kosten den Server
exakt null und das Netzwerk exakt null Bytes.

Preis dafür, und das ist kein Detail: **der Verkehr ist zwischen Spielern nicht
synchron.** Zwei Spieler sehen die Autos an verschiedenen Stellen. Für Kulisse
egal. Sobald die Autos je etwas *tun* sollen – Hindernis, Verfolgung, drauf
springen – muss das auf den Server, und dann mit deutlich weniger Autos.

### Onboarding – das Spiel erklärt sich

Vorher: zwei Toasts beim Erststart. Toasts sind nach vier Sekunden weg. Wer in
dem Moment woanders hinschaut, hat nie erfahren, worum es geht.

Jetzt drei Stufen:

1. **Intro-Karte** beim ersten Beitritt. Drei Sätze, ein Knopf. Teile machen
   Geld pro Sekunde → alle 3 Minuten gehen alle Tore auf → wer dich rempelt,
   kriegt das Teil.
2. **Zielbalken** unten mittig mit genau *einer* Aufgabe, die mit dem Spielstand
   weiterschaltet: Werkbank → Kasse → Klau-Fenster → weg. Verschwindet dauerhaft
   ab drei verbauten Teilen.
3. **Weltmarker** über dem gemeinten Objekt, durch Wände sichtbar, pulsierend.
   „Geh zur Werkbank" nützt nichts, wenn man die Werkbank suchen muss.

Der Balken sitzt unten mittig und nicht oben, weil oben auf einem 390-px-Handy
schon Cash links, Heist-Pille mittig und die Knopfleiste rechts stehen – für
einen 260 Studs breiten Balken bleiben in der Mitte 158 px.

---

## Einbau

### Patch 1 – `ServerScriptService/Server` (Server.lua)

Oben bei den Requires:

```lua
local RaceTrack = require(script.World.RaceTrack)
```

Und direkt nach `step("Welt bauen", buildWorld)`:

```lua
step("Welt bauen", buildWorld)
step("Rennstrecke bauen", function()
	RaceTrack.Build(Workspace)
end)
step("Lighting einstellen", setupLighting)
```

### Patch 2 – `StarterPlayerScripts/Client` (Client.lua)

Oben bei den Requires:

```lua
local TrafficController = require(script.Controllers.TrafficController)
local Onboarding = require(script.UI.Onboarding)
```

Nach `DismountBar.Init(root)`:

```lua
Onboarding.Init(root)
TrafficController.Start()
```

Und ganz unten den Erststart-Block **löschen** – die Intro-Karte ersetzt ihn:

```lua
		if looksBrandNew(snapshot) then
			GarageMenu.SetVisible(true)
			Toast.Show("Deine Karre ist Schrott. ...", "cash")
			Toast.Show("Verbaute Teile bringen Cash ...", "info")
		end
```

Die Funktion `looksBrandNew` wird dadurch tot und kann mit weg. Ein Menü, das
sich von allein über die Intro-Karte legt, ist schlechter als ein Marker, der
auf die Werkbank zeigt.

### Patch 3 – Lighting (optional, in `setupLighting`)

Die Szene hat jetzt deutlich mehr Neon als vorher:

```lua
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.85 -- war 0.5
	bloom.Size = 24
	bloom.Threshold = 0.95
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.9
	rays.Parent = Lighting
```

---

## Was das kostet

Aus den Schleifen gerechnet, nicht geschätzt:

| Posten | Parts |
|---|---|
| Fahrbahn, Planken, Neonkante, Unterzug (60 Abschnitte × 8) | 480 |
| Mittelstriche | 80 |
| Stützpfeiler (24 × 4) | 96 |
| Torbogen | 10 |
| Hof: Container, Rippen, Rampen, Sperren, Masten | 133 |
| **Neu auf dem Server** | **799** |
| Verkehr (nur Client, nicht repliziert) | 288 |

799 statische, verankerte Parts sind für Roblox unkritisch – sie werden einmal
repliziert und bewegen sich nie.

**Der Engpass sind die Lichter, nicht die Parts.** Mit den vier Lichtmasten
stehen jetzt rund 40 Lichtquellen in der Szene (12 Garagen × 2 Deckenlampen,
12 Torlampen, 4 Masten) unter Future-Lighting. Wenn es auf Handys einbricht, in
dieser Reihenfolge drehen:

1. `TrafficController.CARS_PER_LANE` von 8 auf 5
2. In `PlotBuilder` die zweite Deckenlampe raus (eine reicht)
3. `light.Shadows = false` steht schon überall – als Nächstes die Torlampe
   (`PointLight` am `NeonStrip`) ganz weg, der Neonstreifen bleibt sichtbar
4. `Lighting.Technology` von Future auf ShadowMap

---

## Was weiterhin offen ist

Die Strecke ist Kulisse. Sie macht den Hof nicht spielbarer – das machen die
Container und Rampen. Wenn du die Strecke später *bespielbar* willst
(hochkommen, oben klauen, runterspringen), braucht es eine Rampe oder einen
Aufzug vom Hof nach oben, eine Kollisionsentscheidung für die Fahrbahn und
serverseitigen Verkehr. Das ist ein eigenes Projekt, kein Zusatz.

Ebenfalls offen und billiger: der Heist-Moment hat immer noch keinen Ton. Eine
Sirene beim Öffnen und ein leiser Verkehrsteppich von der Strecke wären die
zwei Asset-IDs mit dem besten Verhältnis von Aufwand zu Wirkung im ganzen
Projekt. `SoundCatalog` wartet nur auf Zahlen.
