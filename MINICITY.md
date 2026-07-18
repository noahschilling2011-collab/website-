# MiniCity — Roblox-Prototyp v0.2

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
Spiel oder aktiviertes „Studio Access to API Services" (sonst startet man mit
leerer Stadt, ohne Fehler).

## Katalog (v0.2)

| Item | Footprint | Preis | Einkommen/Tick | Einwohner | Freischaltung |
|---|---|---|---|---|---|
| Straße | 1×1 | 10 $ | — | — | ab Start |
| Wohnhaus | 2×2 | 100 $ | +5 $ | +4 | ab Start |
| Geschäft | 2×2 | 250 $ | +15 $ | — | ab 10 Einwohnern |
| Hochhaus | 3×3 | 1 000 $ | +30 $ | +20 | ab 25 Einwohnern |
| Autobahn-Segment | 1×2 | 150 $ | — | — | ab 50 Einwohnern |
| Flughafen | 8×5 | 10 000 $ | +250 $ | — | ab 100 Einwohnern |

Startgeld 500 $, Einkommens-Tick alle 10 s (nur serverseitig).
Neues Item = neuer Eintrag in `src/shared/Items.luau`, kein neuer Code.

## Steuerung

- Item im Baumenü (unten) wählen → Ghost folgt der Maus/dem Finger.
- **R** = 90° drehen.
- Klick/Tap = platzieren (grün gültig, rot ungültig).
- **Abriss**-Knopf → eigenes Gebäude anklicken (50 % Rückerstattung).
- **Abbrechen** verlässt Bau-/Abriss-Modus.

Siehe [`IDEEN.md`](IDEEN.md) für bewusst ausgelassene Features.
