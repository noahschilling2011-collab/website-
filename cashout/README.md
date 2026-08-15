# CASHOUT — Phase 1

Rundenbasiertes Entscheidungsspiel. Cash kann dir genommen werden, Banked nicht.
**Phase 1 ist der Solo-Loop:** Map, Terminals, Deals, Heat, Razzia, Bank.
Runden, Scoreboard, DataStore (Phase 2) und Abfangen (Phase 3) sind noch nicht gebaut.

## In Studio starten

1. `rojo serve` im Ordner `cashout/` starten, in Studio mit dem Rojo-Plugin verbinden, synchronisieren.
2. Ohne Rojo: Ordner 1:1 nachbauen — `src/ReplicatedStorage/Shared` → ReplicatedStorage.Shared,
   `src/ServerScriptService` → ServerScriptService, `src/StarterPlayer/StarterPlayerScripts` → StarterPlayerScripts.
   `*.server.lua` = Script, `*.client.lua` = LocalScript, alles andere = ModuleScript (ohne Endung im Namen).
3. Keine Map bauen — `MapBuilder` erzeugt Boden, 5 Terminals und die Bank beim Serverstart selbst.
4. Play drücken. In der Konsole steht `[CASHOUT] Phase 1 laeuft.`

## Spielen

**E** am Terminal öffnet drei Karten, Klick nimmt den Deal — bis er durch ist, am Terminal stehen bleiben.
**E** an der Bank zahlt 8 s lang ein: gesamter Cash wird Banked, Heat −20. Weglaufen bricht beides folgenlos ab.

Alle Zahlen stehen in `src/ReplicatedStorage/Shared/Balance.lua`, sonst nirgends.
Gemessene Erwartungswerte und das Simulationsskript: [BALANCE.md](BALANCE.md).
Fehlende Asset-Ids: [ASSETS_TODO.md](ASSETS_TODO.md).
