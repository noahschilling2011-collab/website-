# Garage Heist

Tycoon-Werkstatt mit Klau-Fenster. Du reparierst Schrottautos Teil fuer Teil,
verbaute Teile werfen Cash pro Sekunde ab - auch offline. Alle 8 Minuten gehen
fuer 60 Sekunden alle Garagentore auf und jeder kann jedem Teile abmontieren und
wegschleppen.

Kein Fahrverhalten, keine Quests, keine NPCs, keine Map ausserhalb des
Garagenhofs. Autos sind Deko-Objekte mit Werten.

## In Studio bekommen

**Der schnelle Weg - eine Datei:** `GarageHeist.rbxlx` in Studio oeffnen
(Doppelklick oder `File > Open from File`). Alles liegt sofort an der richtigen
Stelle, kein Rojo noetig. Danach `File > Publish to Roblox As...`.

Die Datei wird aus `src/` erzeugt. Nach Aenderungen am Code neu bauen:

```bash
python3 tools/build_rbxlx.py
```

Das Skript prueft dabei, dass jede der 40 Quelldateien unveraendert in der
Place-Datei steckt, und bricht ab, wenn etwas nicht passt.

**Mit Rojo (besser, wenn du weiterentwickelst):**

```bash
# einmalig
aftman add rojo-rbx/rojo   # oder: cargo install rojo

cd garage-heist
rojo serve
```

In Studio das Rojo-Plugin oeffnen, `Connect`. Fertig - `src/` landet in
ReplicatedStorage / ServerScriptService / StarterPlayerScripts.

**Von Hand nachbauen** (falls du beides nicht willst): Die Struktur muss exakt so
aussehen, weil die Module sich ueber `script.Parent` finden:

```
ReplicatedStorage/
  Shared/                      (Folder)
    Config, CarCatalog, PartCatalog, Remotes, Signal, Util   (ModuleScripts)

ServerScriptService/
  Server                       (Script,  Inhalt: src/Server/init.server.lua)
    Data/     ProfileTemplate, ProfileOps, SessionStore
    Garage/   GarageRequests, GarageView, RequestRouter, Snapshot
    Heist/    CarryManager, DismountManager
    Monetization/ PurchaseEffects
    Services/ DataService, EconomyService, GarageService, HeistService,
              MonetizationService, DailyRewardService, LeaderboardService
    World/    CarBuilder, DoorController, PlotBuilder

StarterPlayer/StarterPlayerScripts/
  Client                       (LocalScript, Inhalt: src/Client/init.client.lua)
    Store                      (ModuleScript)
    Controllers/ InputController
    UI/       Theme, Toast, HUD, GarageMenu, ShopMenu, DailyPanel,
              DismountBar, InfoPanel
```

**Vor dem ersten Test:**

1. `Game Settings > Security > Enable Studio Access to API Services` einschalten.
   Ohne das laeuft der Store im In-Memory-Modus - das Spiel funktioniert, aber
   nichts wird gespeichert. Die Konsole schreibt das laut hin.
2. `Game Settings > Places > Max Players` auf **12 oder weniger** setzen. Es gibt
   `Config.PLOT_COUNT = 12` Garagen; wer keine bekommt, wird gekickt.

## Der Loop

1. Schrottauto steht in der eigenen Box. Vier leere Slots: Motor, Reifen, Lack, Turbo.
2. An der Werkbank (oder Taste `G`) Teile kaufen. Jedes kostet Cash und braucht Zeit.
3. Verbaute Teile bringen Cash/Sekunde in die Garagenkasse. Kasse leeren am gruenen Pult.
4. Alle 8 Minuten: 60 Sekunden Klau-Fenster. Fremdes Teil 4 Sekunden abmontieren,
   tragen, auf das blaue Pad in der eigenen Box stellen. Wer getroffen wird (`F`),
   verliert es an den Boden.
5. Cash geht in bessere Teile, mehr Autos, groessere Garage. Zurueck zu 2.

**Steuerung:** `E` Prompts, `G` Werkstatt, `F` Rempeln, `Q` Teil ablegen.

## Architektur

- **Server-authoritativ.** Cash, Teile-Besitz, Fenster-Timer und Offline-Earnings
  entstehen ausschliesslich auf dem Server. `src/Client` enthaelt keine einzige
  Zeile, die einen Geldbetrag berechnet - der Client zeigt an, was ankommt, und
  schickt Absichten.
- **Ein Zustand, eine Quelle.** Das Profil ist die Wahrheit; die Welt wird daraus
  neu gezeichnet (`GarageView`), nie umgekehrt.
- **Getrennte Zustaendigkeiten.** Keine Datei ueber 300 Zeilen, kein Service, der
  zwei Dinge tut. Reine Datenoperationen liegen in `Data/ProfileOps.lua`, damit
  Online- und Offline-Rechnung nachweislich dieselbe Formel benutzen.
- **DataStore mit Session-Lock.** `Data/SessionStore.lua` nimmt beim Laden einen
  Lock (`UpdateAsync`), schreibt nur, solange er ihm gehoert, und gibt ihn beim
  Verlassen frei. Retry mit Backoff, `BindToClose` wartet aufs Speichern. Scheitert
  das Laden, wird gekickt statt mit leerem Profil ueberschrieben.
- **Jede Client-Anfrage wird geprueft**: Gehoert ihm das? Reicht das Cash? Ist das
  Fenster offen? Ist er nah genug dran? Ist die Garage nicht verriegelt?

## Wo geschraubt wird

| Was | Wo |
|---|---|
| Alle Zahlen (Preise, Zeiten, Fenster, Deckel) | `src/Shared/Config.lua` |
| Teile-Stufen, Kosten, Raten, Aussehen | `src/Shared/PartCatalog.lua` |
| Autos | `src/Shared/CarCatalog.lua` |
| Produkt-IDs | oben in `src/Server/Services/MonetizationService.lua` |
| Was im Dashboard anzulegen ist | `docs/MONETIZATION.md` |
| Abnahme-Tests pro Phase | `docs/TESTPLAN.md` |

## Bewusst weggelassen

- Cross-Server-Rangliste (OrderedDataStore): die Rangliste ist serverlokal.
- Klauen bei Offline-Spielern: nur wer im Server ist, hat eine Garage im Server.
- Fahrbare Autos, Charakter-Customizing, Quests, Story, NPCs, Map.
- Teams, Chat-Filter-Umgehungen, eigene Kamera - nichts davon dient dem Loop.
