# Garage Heist

Tycoon-Werkstatt mit Klau-Fenster. Du reparierst Schrottautos Teil fuer Teil,
verbaute Teile werfen Cash pro Sekunde ab - auch offline. Alle 3,5 Minuten gehen
fuer 75 Sekunden alle Garagentore auf und jeder kann jedem Teile abmontieren und
wegschleppen. Freie Boxen werden dabei zu Leerstand-Garagen, damit der Heist auch
bei einem einzigen Spieler im Server stattfindet.

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

Das Skript prueft dabei, dass jede Quelldatei unveraendert in der Place-Datei
steckt, und bricht ab, wenn etwas nicht passt.

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
ReplicatedStorage/Shared/                (Folder, alle Dateien aus src/Shared)
ServerScriptService/Server               (Script, Inhalt src/Server/init.server.lua)
  Data/ Garage/ Heist/ Monetization/ Services/ World/   (Folder je Unterordner)
StarterPlayer/StarterPlayerScripts/Client (LocalScript, src/Client/init.client.lua)
  Store (ModuleScript), Controllers/, UI/
```

Jede `.lua`-Datei wird zum ModuleScript gleichen Namens, jeder Ordner zum Folder.
Die Module finden sich ueber `script.Parent`, deshalb muss die Schachtelung
stimmen. Der Generator oben macht genau das - von Hand ist es reine Fleissarbeit.

**Vor dem ersten Test:**

1. `Game Settings > Security > Enable Studio Access to API Services` einschalten.
   Ohne das laeuft der Store im In-Memory-Modus - das Spiel funktioniert, aber
   nichts wird gespeichert. Die Konsole schreibt das laut hin.
2. `Game Settings > Places > Max Players` auf **12 oder weniger** setzen. Es gibt
   `Config.PLOT_COUNT = 12` Garagen; wer keine bekommt, wird gekickt.

## Die Welt entsteht beim Play, nicht im Editor

**Im Bearbeitungsmodus siehst du nur eine Grundplatte - das ist richtig so.**
Boden, die zwoelf Garagen, Tore, Schilder, Autos und die Ranglisten-Tafel baut
der Server beim Start aus Code (`World/PlotBuilder.lua`, `World/CarBuilder.lua`).
Es gibt bewusst keine vorgebaute Map: der Zustand kommt aus dem Profil, und die
Welt wird daraus gezeichnet - nicht umgekehrt.

Druecke **Play**. Danach steht in der Konsole (View > Output) genau eine Zeile:

```
[Garage Heist] Server bereit: 10/10 Services, 12 Garagen gebaut.
```

### Wenn nichts kommt

| Was in der Konsole steht | Was los ist |
|---|---|
| gar keine `[Garage Heist]`-Zeile | Das Server-Skript laeuft nicht. Liegt `Server` wirklich in `ServerScriptService` und ist es ein `Script` (nicht LocalScript, nicht deaktiviert)? |
| `... 12 Garagen gebaut`, aber du siehst nichts | Du stehst woanders. Der Spawn liegt bei `0, 0, 26`, die Garagen links und rechts davon. Kamera zuruecksetzen oder neu spawnen. |
| `[Garage Heist] <Service>:Start() ist gescheitert: …` | Genau dieser Service ist ausgefallen, der Rest laeuft weiter. Die Meldung nennt Datei und Zeile. |
| `0 Garagen gebaut` | `GarageService:Start()` ist gescheitert - die Zeile darueber sagt warum. |
| `[SessionStore] Kein DataStore-Zugriff` | API Services sind aus (Punkt 1 oben). Das Spiel laeuft, speichert aber nicht. |

Jeder Startschritt laeuft in einem eigenen `pcall`: ein Fehler in einem Service
nimmt die anderen nicht mit, und der Boden wird als Allererstes gebaut - damit
niemand ins Leere faellt, egal was danach schiefgeht.

## Der Loop

1. Schrottauto steht in der eigenen Box. Vier leere Slots: Motor, Reifen, Lack, Turbo.
2. An der Werkbank (oder Taste `G`) Teile kaufen. Jedes kostet Cash und braucht Zeit.
   Zwischen zwei Stufen liegen je zwei kleine Feinabstimmungen, damit der Kauftakt
   dicht bleibt - sie sind Ratenzahlung, kein Aufpreis: der Stufensprung wird
   entsprechend guenstiger.
3. Verbaute Teile bringen Cash/Sekunde in die Garagenkasse. Kasse leeren am gruenen Pult.
4. Alle 3,5 Minuten: 75 Sekunden Klau-Fenster, das erste 45 Sekunden nach Serverstart.
   Fremdes Teil 4 Sekunden abmontieren, tragen, auf das blaue Pad in der eigenen
   Box stellen. Wer getroffen wird (`F`), verliert es an den Boden.
   **Freie Boxen sind waehrend des Fensters Leerstand-Garagen** mit bestuecktem
   Auto - deshalb funktioniert der Heist auch, wenn du allein im Server bist.
   Leerstand-Teile bringen nur 60 % ihres Werts, echte Spieler bleiben lohnender.
5. Cash geht in bessere Teile, mehr Autos, groessere Garage. Zurueck zu 2.
6. Garage voll ausgebaut und alle Teile auf Stufe 4? Dann **Rebirth**: alles zurueck
   auf Anfang, dauerhaft +25 % Rate pro Durchgang, ab dem ersten ein Stellplatz mehr.

**Steuerung:** `E` Prompts, `G` Werkstatt, `F` Rempeln, `Q` Teil ablegen.

## Architektur

- **Server-authoritativ.** Cash, Teile-Besitz, Fenster-Timer und Offline-Earnings
  entstehen ausschliesslich auf dem Server. `src/Client` enthaelt keine einzige
  Zeile, die einen Geldbetrag berechnet - der Client zeigt an, was ankommt, und
  schickt Absichten.
- **Ein Zustand, eine Quelle.** Das Profil ist die Wahrheit; die Welt wird daraus
  neu gezeichnet (`GarageView`), nie umgekehrt.
- **Getrennte Zustaendigkeiten.** Kein Service, der zwei Dinge tut; jede Datei
  ausser den beiden Geometrie-Buildern bleibt unter 300 Zeilen. Reine Datenoperationen liegen in `Data/ProfileOps.lua`, damit
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
| Alle Zahlen (Preise, Zeiten, Fenster, Deckel, Rebirth, Badges) | `src/Shared/Config.lua` |
| Teile-Stufen, Kosten, Raten, Aussehen | `src/Shared/PartCatalog.lua` |
| Autos | `src/Shared/CarCatalog.lua` |
| Produkt-IDs | oben in `src/Server/Services/MonetizationService.lua` |
| Klang-IDs (alle leer) | `src/Shared/SoundCatalog.lua` |
| **Jede ID, die du selbst anlegen musst** | `docs/SETUP.md` |
| Warum die Preise so stehen | `docs/MONETIZATION.md` |
| Abnahme-Tests | `docs/TESTPLAN.md` |
| Design-Teardown und was als Naechstes ansteht | `docs/DESIGN.md` |

**Bekannte Abweichung von der 300-Zeilen-Regel:** `World/PlotBuilder.lua` (749)
und `World/CarBuilder.lua` (566) sind Geometrie-Dateien - eine lange Liste von
Parts, keine Logik. Sie liegen bewusst ueber dem Limit, weil ein Aufteilen die
Bauanleitung auseinanderreissen wuerde, ohne etwas lesbarer zu machen. Jede
andere Datei bleibt unter 300.

## Wie ein Teil den Besitzer wechselt

Der heikelste Pfad des Spiels, deshalb an einer Stelle (`Garage/TheftOps.lua`):

1. **Abmontiert** - das Teil bleibt im Profil des Opfers stehen und wird nur als
   `inTransit` markiert. Es zaehlt nicht mehr zur Rate, ist aber nicht weg.
2. **Abgeliefert** - jetzt wird es beim Opfer entfernt, und das Opfer bekommt
   25 % des Werts als Versicherung sofort gutgeschrieben.
3. **Nicht abgeliefert** (Fenster vorbei, gerempelt, jemand fliegt raus) - die
   Markierung faellt, das Teil laeuft wieder normal.

Dadurch kann ein Teil weder verschwinden noch doppelt existieren. Ist das Opfer
beim Abliefern nicht mehr im Server, geht der Dieb leer aus - das ist der Preis
dafuer, dass es beim Opfer garantiert erhalten bleibt.

## Bewusst weggelassen

- Cross-Server-Rangliste (OrderedDataStore): die Rangliste ist serverlokal.
- Klauen bei Offline-Spielern: dafuer gibt es die Leerstand-Garagen.
- Fahrbare Autos, Charakter-Customizing, Quests, Story, NPCs, Map.
- Teams, Chat-Filter-Umgehungen, eigene Kamera - nichts davon dient dem Loop.
