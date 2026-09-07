# Garage Heist – Design-Teardown

Basis: `GarageHeist__3_.rbxlx`, 52 Skripte, ~7.300 Zeilen, komplett prozedural.
In der Place-Datei stehen nur ein Baseplate und ein leerer Workspace – die
gesamte Welt entsteht zur Laufzeit aus Code.

---

## Was das Spiel ist

Ein **Idle-Tycoon mit PvP-Fenster**. Zwei Loops, die ineinandergreifen:

**Loop A – Garage (90 % der Zeit)**
Du bekommst einen von 12 Plots und ein Schrottauto. Das Auto hat vier Slots:
Motor, Reifen, Lack, Turbo. Jeder Slot hat 4 Stufen plus 2 Zwischenstufen.
Jedes verbaute Teil erzeugt Cash pro Sekunde. Das Geld sammelt sich in der
Kasse (Deckel 4 h online, 8 h offline zu 60 %) und wird an der Kasse abgeholt.
Cash → bessere Teile → mehr Cash. Dazu: Autos kaufen (4 Stück, bis 75k),
Garage aufwerten (5 Stufen, bis 260k), Rebirth (+25 % pro Stück).

**Loop B – Heist (alle 3,5 min für 75 s)**
Alle Tore gehen gleichzeitig auf. Du kannst in fremde Garagen laufen, ein Teil
in 4 Sekunden abmontieren, es zu deinem Abgabe-Pad tragen (langsamer, 12 statt
16 WalkSpeed) und einbauen. Wer dich unterwegs rempelt, lässt dich das Teil
fallen. Das Opfer bekommt 25 % Versicherung. Leere Plots werden zu
Leerstand-Garagen, damit der Heist auch mit einem Spieler funktioniert.

**Monetarisierung:** VIP (×2 Rate), Cash-Packs, Auto-Collect, Garage-Lock
(eigenes Tor schließt nach 20 s), Radar. Alle Produkt-IDs stehen auf `0` – das
Spiel ist wirtschaftlich noch nicht scharf geschaltet.

**Der Code ist gut.** Server-autoritative Wirtschaft, Session-Locking im
DataStore, jedes Remote gedrosselt, Bootstrap in einzelnen pcalls, jede Zahl
zentral in `Config.lua`. Das ist deutlich sauberer als das, was du bei
PlanetForge und AirportJobSimulator hattest. Das Problem liegt woanders.

---

## Warum das Design nicht funktioniert

### 1. Fortschritt ist unsichtbar – das ist der Killer

`CarBuilder` baut jedes Auto aus **zwei Kisten und vier Zylindern**. Der
Unterschied zwischen dem Rostigen Reihenvierer (150 Cash) und dem
Prototyp-Hybrid (28.000 Cash) ist: die Kiste auf der Haube hat eine andere
Farbe. Sonst nichts. Gleiche Größe, gleiche Form, gleiche Silhouette.

Dasselbe bei der Garage: `Config.GARAGE_LEVELS` hat fünf Stufen bis 260.000
Cash – und **kein einziger Codepfad rendert die Stufe**. Ich habe den ganzen
Server durchsucht: `garageLevel` wird gelesen für Rate, Slots und Preis, nie
für Optik. Du zahlst 260k und die Garage sieht exakt aus wie am Anfang.

Bei einem Idle-Spiel ist das kein Schönheitsfehler, das ist der ganze Grund,
warum jemand weiterspielt. Belohnung, die man nicht sieht, ist keine Belohnung.

### 2. Fünf Grautöne sind kein Farbkonzept

Boden `70,70,76` · Wand `120,120,125` · Stellplatz `52,52,58` · Untergrund
`58,60,64` · Auto `120,116,110`. Das liegt alles innerhalb von 20 RGB-Punkten.
Es gibt keine Hierarchie: nichts sagt dem Auge, wo es hinschauen soll.

### 3. Die Garage ist ein Karton ohne Decke

Sieben Parts: Boden, Rückwand, zwei Seitenwände, zwei Pfeiler, Sturz. Kein
Dach, keine Innenbeleuchtung, keine Regale, kein Werkzeug, keine
Bodenmarkierung. Die einzige Lichtquelle ist ein PointLight **außen** über dem
Tor. Innen ist es ein grauer Kasten unter freiem Himmel.

### 4. Z-Fighting über die gesamte Karte (echter Bug)

Drei Flächen liegen exakt auf `y = 0`:

| Objekt | Größe | Position | Oberkante |
|---|---|---|---|
| Baseplate (in der .rbxlx) | 1024 × 16 × 1024 | y = −8 | **0** |
| Ground (`Server.lua:buildWorld`) | 900 × 2 × 620 | y = −1 | **0** |
| Plot-Floor (`PlotBuilder`) | 46 × 1 × 54 | y = −0,5 | **0** |

Das flimmert bei jeder Kamerabewegung. Fix steht unten.

### 5. Die Karte ist ein Parkplatz

12 Boxen in zwei Reihen à 6, 110 Studs Asphalt dazwischen, 900 × 620 Fläche
ohne irgendetwas darauf. Während des Heists rennst du 75 Sekunden lang über
ein leeres Feld ohne Deckung, ohne Abkürzung, ohne Sichtblocker. Das Rempeln
wird dadurch trivial: freie Sichtlinie über die ganze Karte. **Das ist ein
Level-Design-Problem, kein Grafikproblem** – und das teuerste zu beheben.

### 6. UI ist funktional, aber generisch

Gotham + `UICorner` + flache Rechtecke = Roblox-Standard-Look. Keine Kontur,
kein Verlauf, keine Icons, keine Zahlenanimation. Der Cash-Zähler springt von
1.240 auf 1.241 – bei einem Idle-Spiel ist der hochzählende Zähler *das*
Kernfeedback und er fehlt.

### 7. Der Heist-Moment ist zu leise

Das aufregendste Ereignis im Spiel bekommt: ein rotes Vollbild-Aufblitzen
(0,7 s) und eine Farb-Lerp auf der HUD-Pille. Keine Sirene, keine
Musikänderung, kein Kamerawackler, keine Vignette. Für den Moment, um den das
ganze Spiel gebaut ist, ist das zu wenig.

### Kleinigkeiten

- `slotParts` wird in `CarBuilder` gefüllt und **nirgends gelesen**. Toter Code.
- Das Auto-Billboard hängt neben dem Modell statt darin und muss überall extra
  zerstört werden – vier Stellen, an denen ein vergessener `Destroy()` leakt.
- `Config.HEIST_INTERVAL` ist 210 s, der Kommentar in `HeistService` sagt
  „alle 8 Minuten für 60 Sekunden". Kommentar ist veraltet.
- `Config.BADGE_IDS` und alle Produkt-IDs stehen auf `0`.

---

## Was in diesem Paket drin ist

Drei **Drop-in-Ersetzungen**. Gleiche öffentliche API, gleiche Rückgabewerte –
kein anderes Modul muss angefasst werden. Alle drei mit `luau-compile`
gegengeprüft.

### `PlotBuilder.lua` → `ServerScriptService/Server/World/PlotBuilder`

- Decke aus zwei Platten mit Lichtschacht in der Mitte. `CanCollide = false`
  (die Roblox-Kamera schiebt sich nur an kollidierende Parts heran, also
  bleibt der Blick von oben frei), aber `CastShadow = true` – dadurch wird
  der Raum innen dunkel und die Lampen haben eine Funktion.
- Zwei Deckenlampen mit `SurfaceLight`, Farbe und Helligkeit je Garagen-Stufe.
- Sockelband, Akzentleiste, Warnstreifen an der Torschwelle, Mittellinie,
  gemalte Rahmen um jeden Stellplatz.
- Werkzeugwand, Reifenstapel, Ölfässer, Ölfleck, Tresen um die Kasse,
  Werkbank-Korpus mit Schraubstock, Rahmen und „ABGABE"-Schild am Loot-Pad.
- Torschienen und mitfahrende Torunterkante.
- Plot-Nummer und Stufen-Plakette neben dem Tor.
- **`PlotBuilder.ApplyLevel(plot, level)`** – Akzentfarbe, Lichtfarbe,
  Lichtstärke und Bodenmarkierung pro Garagen-Stufe. Muss noch verdrahtet
  werden, siehe Patch 2.

### `CarBuilder.lua` → `ServerScriptService/Server/World/CarBuilder`

Stufe ist jetzt **am Auto** ablesbar:

| Slot | T1 | T2 | T3 | T4 |
|---|---|---|---|---|
| Motor | flacher Deckel | + Ventildeckel | + Ansaugtrichter | + leuchtende Ladeluftkühler |
| Reifen | Stahlfelge | + Speichen | Chromfelge, breiter | Neonfelge, am breitesten |
| Turbo | Lippe + Stützen | Flügel | Doppelflügel | + Chrom-Endrohre, leuchtend |
| Lack | matt/rostig | lackiert | Metallic + Reflexion | Chrom-Folie + Underglow |

Dazu Karosserie-Details, die vorher komplett fehlten: Schweller, Stoßfänger,
Front- und Heckscheibe aus Glas, Scheinwerfer und Rücklichter. Fehlende Teile
bleiben durchsichtige rote Platzhalter – das war vorher schon richtig.

### `Theme.lua` → `StarterPlayer/StarterPlayerScripts/Client/UI/Theme`

- Palette mit Blaustich statt Neutralgrau, `line`-Farbe für Konturen.
- Jedes Panel bekommt `UIStroke` + `UIGradient`, jeder Knopf `UIStroke` und
  einen Druckpunkt (0,96 → 1 mit Back-Easing).
  *Kein* Verlauf auf Knöpfen: `UIGradient` färbt bei TextButtons den Text mit.
- Michroma als Anzeigeschrift.
- Neu: `Theme.stroke`, `Theme.gradient`, `Theme.glow`, `Theme.pop`,
  `Theme.countTo(label, from, to, format, duration)`.

Alle alten Farbnamen und Funktionen bleiben – die neun anderen UI-Module
laufen unverändert weiter.

---

## Patches, die nicht in die drei Dateien passen

### Patch 1 – Z-Fighting (2 Minuten, größter Effekt pro Aufwand)

In `ServerScriptService/Server` (`Server.lua`), Funktion `buildWorld`, den
Ground eine Kleinigkeit tiefer setzen und das Baseplate entfernen:

```lua
local function buildWorld()
	-- Baseplate aus der Place-Datei liegt mit der Oberkante exakt auf y = 0,
	-- genau wie Ground und jeder Garagenboden. Drei koplanare Flaechen
	-- flimmern bei jeder Kamerabewegung.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(900, 2, 620)
	ground.CFrame = CFrame.new(0, -1.05, 0) -- Oberkante -0,05 statt 0
	ground.Color = Color3.fromRGB(38, 40, 45)
	ground.Material = Enum.Material.Asphalt
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace
	-- ... Rest unveraendert
end
```

### Patch 2 – Garagen-Stufe sichtbar machen (1 Zeile)

In `ServerScriptService/Server/Garage/GarageView`, in `UpdateSign`. Die
Funktion bekommt `data` schon übergeben, es fehlt nur der Aufruf:

```lua
local PlotBuilder = require(Server.World.PlotBuilder) -- oben ergaenzen

function GarageView.UpdateSign(view, player: Player, data, rate: number)
	PlotBuilder.ApplyLevel(view.plot, data.garageLevel or 1) -- NEU
	local sign = view.plot.sign
	sign.name.Text = player.DisplayName .. "s Garage"
	sign.value.Text = "Wert " .. Util.FormatCash(ProfileOps.GarageValue(data))
	sign.rate.Text = Util.FormatRate(rate)
end
```

Beim Freigeben eines Plots in `GarageService` (dort, wo schon
`view.plot.sign.name.Text = "Freie Box"` steht) `PlotBuilder.ApplyLevel(view.plot, 1)`
ergänzen, sonst behält ein freier Plot die Optik des letzten Besitzers.

### Patch 3 – Cash hochzählen statt springen

In `HUD.Update`, Zeile mit `refs.cash.Text = Util.FormatCash(cash.cash)`:

```lua
local previous = HUD._lastCash or cash.cash
if math.abs(cash.cash - previous) > 0.5 then
	Theme.countTo(refs.cash, previous, cash.cash, Util.FormatCash, 0.35)
	Theme.pop(refs.cash, 0.06)
else
	refs.cash.Text = Util.FormatCash(cash.cash)
end
HUD._lastCash = cash.cash
```

---

## Was ich bewusst NICHT gemacht habe

**Die Karte.** Punkt 5 oben ist das größte verbleibende Designproblem, und es
lässt sich nicht durch das Ersetzen einer Datei lösen. Ein 900 × 620 Studs
großer leerer Asphaltplatz macht den Heist – den einzigen Teil des Spiels, der
kein Idle-Tycoon ist – langweilig. Was es braucht: Container, Mauern, eine
Straße, Rampen, ein paar Sichtblocker zwischen den Reihen, damit Verfolgungen
Entscheidungen enthalten statt nur Laufzeit. Das ist ein eigener Arbeitsschritt
und der wäre der nächste, den ich machen würde.

**Sound und Heist-Drama.** `SoundCatalog` existiert, aber ohne echte Asset-IDs.

---

## Ein Nachteil, über den du Bescheid wissen musst

Ein Auto besteht jetzt aus ~45 Parts statt ~8. `GarageView.RenderCars` baut
bei **jeder** Zustandsänderung **alle** Autos eines Spielers neu – Kauf,
fertige Reparatur, geklautes Teil, abgeliefertes Teil. Der Rebuild kostet
dadurch grob das Fünffache.

Bei 12 Spielern mit je bis zu 4 Autos ist das noch unkritisch, aber während
eines Heist-Fensters mit vielen Diebstählen kann es kurz ruckeln. Der saubere
Fix wäre, `RenderCars` so umzubauen, dass nur das geänderte Auto neu gebaut
wird statt alle. Wenn du das im Test merkst, sag Bescheid – das ist ein
überschaubarer Eingriff in genau eine Funktion.
