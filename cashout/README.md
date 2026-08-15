# CASHOUT v2

Rundenbasiertes Entscheidungsspiel für Roblox. Cash kann dir genommen werden, Banked nicht.
**Alle vier Phasen sind gebaut:** Loop, Razzia, PvP und Late Join, Design und Feel.

## In Studio starten

**Der kurze Weg:** [`CASHOUT.rbxlx`](CASHOUT.rbxlx) in Studio über *Datei > Öffnen* laden, Play drücken.
Fertig — kein Rojo, kein Plugin, keine Map bauen. `MapBuilder` erzeugt Boden, Bank, fünf Terminals,
Deckungen und das Nachtlicht beim Serverstart selbst. In der Konsole steht dann
`[CASHOUT] v2 Phase 4 laeuft.` plus eine Sammelzeile der fehlenden Sound-Ids.

Die Place-Datei wird aus `src/` erzeugt und ist deshalb immer nur so aktuell wie ihr letzter Bau:

    python3 tools/build_place.py

**Zum Weiterentwickeln** ist Rojo der bessere Weg, weil Änderungen live synchronisieren:
`rojo serve` im Ordner `cashout/`, in Studio mit dem Rojo-Plugin verbinden.

Von Hand geht es auch: `src/ReplicatedStorage/Shared` → ReplicatedStorage.Shared,
`src/ServerScriptService` → ServerScriptService, `src/StarterPlayer/StarterPlayerScripts` →
StarterPlayerScripts. `*.server.lua` = Script, `*.client.lua` = LocalScript, alles andere =
ModuleScript (ohne Endung im Namen).

## Spielen

**E** am Terminal öffnet drei Auftragskarten, Klick nimmt einen an (1 s stehen bleiben).
Danach erscheint ein Übergabepunkt im Abstand der Stufe — hinlaufen, **E**, 2 s: Cash + Heat.
Der Payout ist `Basis × (1 + Heat/100)`, in den letzten 60 s der Runde zusätzlich ×2.
**E** an der Bank zahlt 8 s lang ein: Cash wird Banked, Heat −25. Wer einzahlt, leuchtet weiß —
andere können mit **F** die Hälfte abfangen. Heat kühlt **nur ohne getragenen Auftrag** ab.
Bei einer Razzia hast du 5 Sekunden, um 40 Studs weit aus dem roten Kreis zu kommen.

## Prüfen ohne Studio

`tools/harness/run.sh [pfad/zu/luau]` lädt die echten Servermodule gegen gestubbte Roblox-APIs
und eine virtuelle Uhr: volle Runde, Grenzfälle, Razzia, PvP und ein Rauchtest des Simulators.
Läuft auch in CI.

`require(game.ServerScriptService.Dev.BalanceSim).Run()` rechnet in Studio 32 Strategien
× 5000 Runden gegen `Balance.lua` durch und prüft den Zielkorridor.

Alle Zahlen stehen in `src/ReplicatedStorage/Shared/Balance.lua`, sonst nirgends.
Fehlende Asset- und Sound-Ids: [ASSETS_TODO.md](ASSETS_TODO.md).
