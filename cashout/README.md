# CASHOUT v2 — Phase 1

Rundenbasiertes Entscheidungsspiel. Cash kann dir genommen werden, Banked nicht.
**Phase 1 ist der Loop:** Runde, Terminals, Aufträge mit Übergabepunkten, Cash, Heat, Zerfall, Banking, Endtafel.
Razzia (Phase 2), Abfangen und Late Join (Phase 3), Design und Feel (Phase 4) sind noch nicht gebaut.

## In Studio starten

1. `rojo serve` im Ordner `cashout/` starten, in Studio mit dem Rojo-Plugin verbinden, synchronisieren.
2. Ohne Rojo: Ordner 1:1 nachbauen — `src/ReplicatedStorage/Shared` → ReplicatedStorage.Shared,
   `src/ServerScriptService` → ServerScriptService, `src/StarterPlayer/StarterPlayerScripts` → StarterPlayerScripts.
   `*.server.lua` = Script, `*.client.lua` = LocalScript, alles andere = ModuleScript (ohne Endung im Namen).
3. Keine Map bauen — `MapBuilder` erzeugt Boden, Bank und fünf Terminals beim Serverstart selbst.
4. Play drücken. In der Konsole steht `[CASHOUT] v2 Phase 1 laeuft.` plus eine Sammelzeile der fehlenden Sound-Ids.

## Spielen

**E** am Terminal öffnet drei Auftragskarten, Klick nimmt einen an (1 s stehen bleiben).
Danach erscheint ein Übergabepunkt im Abstand der Stufe — hinlaufen, **E**, 2 s: Cash + Heat.
**E** an der Bank zahlt 8 s lang ein: gesamter Cash wird Banked, Heat −25.
Heat kühlt **nur ohne getragenen Auftrag** ab. Die letzten 60 s der Runde zahlen doppelt.

## Prüfen ohne Studio

`tools/harness/run.sh [pfad/zu/luau]` lädt die echten Servermodule gegen gestubbte Roblox-APIs
und eine virtuelle Uhr: eine volle 300-s-Runde plus die Grenzfälle. Läuft auch in CI.

Alle Zahlen stehen in `src/ReplicatedStorage/Shared/Balance.lua`, sonst nirgends.
Fehlende Asset- und Sound-Ids: [ASSETS_TODO.md](ASSETS_TODO.md).
