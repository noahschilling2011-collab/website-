# MiniCity — Roblox-Prototyp v0.3

Diorama-Städtebauer: Jeder Spieler baut auf seinem 128×128-Plot eine Miniatur-Stadt
aus Fertiggebäuden. Der Spieler läuft als „Riese" über seine Ministadt
(Hochhaus ≈ 25 Studs hoch).

**Core-Loop:** Straßen legen → Gebäude mit Straßenanschluss platzieren →
Einkommen und Einwohner wachsen → neue Gebäudetypen schalten sich frei →
auf den Flughafen sparen.

## Projektstruktur (Rojo)

```
default.project.json
src/
  server/   Main, PlotService, PlacementService, EconomyService, UnlockService, DataService
  client/   Main, PlacementController, BuildMenuUI, HUD
  shared/   Config (alle globalen Zahlen), Items (Katalog + Model-Builder), Remotes
```

Der Rojo-Baum bildet ab:
- `src/server`  → `ServerScriptService/MiniCity`
- `src/shared`  → `ReplicatedStorage/MiniCity`
- `src/client`  → `StarterPlayer/StarterPlayerScripts/MiniCity`

## Bauen / Ausführen

Voraussetzung: [Rojo](https://rojo.space) + Roblox Studio.

```bash
rojo serve            # oder: rojo build -o MiniCity.rbxlx
```

In Studio: Rojo-Plugin verbinden → Play. Persistenz braucht ein veröffentlichtes
Spiel oder aktiviertes „Studio Access to API Services". Schlägt das **Laden**
fehl, startet die Sitzung mit leerer Stadt und das Speichern bleibt für diese
Sitzung deaktiviert — so wird ein echter Spielstand nie mit einer leeren Stadt
überschrieben.

## Katalog (v0.3)

| Item | Footprint | Preis | Einkommen/Tick | Einwohner | Freischaltung |
|---|---|---|---|---|---|
| Straße | 1×1 | 10 $ | — | — | ab Start |
| Wohnhaus | 2×2 | 100 $ | +5 $ | +4 | ab Start |
| Park | 1×1 | 75 $ | — | +2 | ab Start |
| Geschäft | 2×2 | 250 $ | +15 $ | — | ab 10 Einwohnern |
| Hochhaus | 3×3 | 1 000 $ | +30 $ | +20 | ab 25 Einwohnern |
| U-Bahn-Station | 2×1 | 750 $ | +25 $ | — | ab 35 Einwohnern |
| Autobahn-Segment | 1×2 | 150 $ | — | — | ab 50 Einwohnern |
| Fabrik | 3×2 | 2 000 $ | +70 $ | — | ab 60 Einwohnern |
| Flughafen | 8×5 | 10 000 $ | +250 $ | — | ab 100 Einwohnern |

v0.3 ergänzt Park, U-Bahn-Station und Fabrik als reine Katalog-Einträge —
gleiche Mechanik, keine neuen Systeme. Die U-Bahn-Station ist (wie Autobahn
und Flughafen) ein Prestige-/Einkommensobjekt: keine fahrenden Züge.

Startgeld 500 $, Einkommens-Tick alle 10 s (nur serverseitig).
Neues Item = neuer Eintrag in `src/shared/Items.luau`, kein neuer Code.

## Steuerung

- Item im Baumenü (unten) wählen → Ghost folgt der Maus/dem Finger.
- **R** oder „Drehen"-Knopf = 90° drehen.
- Klick/Tap = platzieren. Der Ghost spiegelt die Server-Regeln:
  grün = gültig, rot = Zelle belegt, kein Straßenanschluss oder zu wenig Geld.
- **Abriss**-Knopf → eigenes Gebäude anklicken (50 % Rückerstattung).
- **Abbrechen** verlässt Bau-/Abriss-Modus.

Siehe [`IDEEN.md`](IDEEN.md) für bewusst ausgelassene Features.
