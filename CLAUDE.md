# CLAUDE.md — Garage Heist (Roblox)

Diese Datei ist für Claude Code (oder jeden anderen Agenten), der an diesem
bestehenden Projekt arbeitet. Sie ist keine Bauanleitung für ein neues Spiel —
das Spiel existiert, läuft und ist sauber gebaut. Die Aufgabe ist, es zu
erweitern, ohne die Struktur zu zerstören.

Wenn du nur eine Zeile liest, dann diese: **Nichts hier neu schreiben, was
schon funktioniert. Bei Unsicherheit die betroffene Datei lesen, nicht
ersetzen.**

Das Projekt liegt im Unterordner `garage-heist/`. Alle Pfadangaben unten sind
relativ dazu.

---

## Was das Spiel ist

Idle-Tycoon mit PvP-Fenster. Jeder Spieler bekommt eine von 12 Garagenboxen und
bis zu 4 Deko-Autos. Jedes Auto hat 4 Slots (Motor, Reifen, Lack, Turbo) mit je
4 Stufen und 2 Zwischenstufen. Verbaute Teile erzeugen Cash pro Sekunde, das
sich in der Garagenkasse sammelt und dort abgeholt wird.

Alle 210 Sekunden gehen für 75 Sekunden alle Tore auf. In diesem Fenster kann
man in fremde Garagen laufen, ein Teil in ~4 Sekunden abmontieren, es zum
eigenen Abgabe-Pad tragen (langsamer als normal) und einbauen. Wer den Träger
rempelt, lässt ihn das Teil fallen. Das Opfer bekommt 25 % Versicherung.

Fortschritt: bessere Teile → mehr Autos (bis 75 k) → Garagenstufe (bis 260 k) →
Rebirth (+25 % dauerhaft).

Neue Spieler landen in einer Werkhalle am Westende des Hofs (`World/SpawnHall`)
und laufen von dort selbst los. Wer schon etwas verbaut hat, kommt direkt an
seiner Box heraus.

Umfang: ~10.400 Zeilen Luau, 57 ModuleScripts, 1 Server-Script, 1 LocalScript.
Die gesamte Welt entsteht zur Laufzeit aus Code — in der `.rbxlx` liegt nur ein
Baseplate.

---

## Harte Regeln

Diese sind keine Stilfragen. Wer eine davon bricht, macht das Spiel kaputt oder
exploitbar.

1. **Der Server rechnet, der Client zeigt an.** Kein Cash-Betrag, kein Preis,
   keine Rate und keine Berechtigung wird jemals auf dem Client bestimmt.
   `Store.lua` hält ausschließlich Kopien von Server-Daten. Wenn ein Client
   etwas will, schickt er eine Absicht über ein Remote und wartet auf das
   nächste Update.
2. **Jedes Remote ist gedrosselt.** `Server/Garage/Throttle.lua` und die
   `*_COOLDOWN`-Werte in `Config.lua`. Neue Remotes bekommen einen Cooldown,
   *bevor* sie eingebaut werden, nicht danach.
3. **Alle Zahlen leben in `Shared/Config.lua`.** Keine Preise, Zeiten, Raten
   oder Deckel irgendwo hartkodieren. Wenn du einen Zahlenwert im Code brauchst,
   der noch nicht in Config steht, füge ihn dort hinzu.
4. **Ein Modul, eine Aufgabe.** Der Grund, warum dieses Projekt bei 9.000+
   Zeilen noch lesbar ist. `GarageService` orchestriert; `Snapshot` liest nur;
   `ProfileOps` rechnet auf Profildaten; `GarageView` baut Welt-Objekte;
   `PlotBuilder`/`CarBuilder` bauen Geometrie. Wenn eine Datei über ~350 Zeilen
   wächst, ist das ein Signal zum Aufteilen, nicht zum Weiterschreiben.
5. **Der Bootstrap darf nicht komplett sterben.** `Server.lua` führt jeden
   Schritt in einem eigenen `pcall` mit Namen aus. Neue Bootstrap-Schritte
   gehen genauso in `step("Name", fn)`. Ein Fehler in der Deko darf nicht die
   Wirtschaft mitreißen.
6. **DataStore-Zugriffe nur über `DataService`/`SessionStore`.** Session-Locking
   ist implementiert (`Config.SESSION_LOCK_TIMEOUT`). Kein zweiter Pfad zum
   Speichern.
7. **Deutsch im Code.** Kommentare und Spielertexte sind deutsch, Bezeichner
   englisch. Kommentare erklären *warum*, nicht *was*.

---

## Wo was liegt

```
ReplicatedStorage/Shared/
  Config          alle Zahlen des Spiels
  PartCatalog     Slots, Stufen, Preise, Raten, Reparaturzeiten
  CarCatalog      4 Autos: Maße, Farbe, Preis, Ratenmultiplikator
  TrackPath       Rennstrecken-Kurve (Mathematik, von Server und Client genutzt)
  Remotes         zentrale Anlage aller RemoteEvents/Functions
  Util, Signal, Audio, SoundCatalog

ServerScriptService/Server.lua        Bootstrap: Welt, Lighting, Services
ServerScriptService/Server/
  Data/       ProfileTemplate, ProfileOps (reine Rechnungen), PartOps, SessionStore
  Services/   11 Services, Startreihenfolge steht in Server.lua (START_ORDER)
  Garage/     Snapshot, GarageView, RepairView, GarageRequests, RequestRouter,
              GarageTicks, TheftOps, Throttle
  Heist/      CarryManager, DismountManager, StealTarget, PartVisual
  World/      PlotBuilder, CarBuilder, DoorController, RaceTrack, SpawnHall

StarterPlayerScripts/Client.lua       Bootstrap: UI, Remote-Handler
StarterPlayerScripts/Client/
  Store           einzige Zustandskopie auf dem Client
  UI/             Theme, HUD, GarageMenu, GarageRows, ShopMenu, DailyPanel,
                  DismountBar, InfoPanel, Toast, Onboarding, AdminPanel
  Controllers/    InputController, EffectController, TrafficController
```

Startreihenfolge der Services ist bedeutsam: `GarageService` **vor**
`HeistService` (der Heist braucht die Plots), `DataService` **zuletzt** (alle
anderen hängen erst an `ProfileLoaded`).

---

## Invarianten, die beim Ändern leicht kaputtgehen

- `PlotBuilder.Build` gibt ein Tabellenformat zurück, auf das `GarageService`,
  `GarageView`, `DoorController` und `DerelictService` zugreifen. Felder nur
  ergänzen, nie umbenennen oder entfernen.
- `CarBuilder.Build` liefert
  `{ model, body, prompts, slotParts, anchors, billboard, carIndex }`.
  `anchors[slotId]` ist der Part, an dem der Reparaturbalken hängt;
  `prompts[slotId]` wird von `GarageService` verbunden. (`slotParts` wird
  derzeit von niemandem gelesen — toter Code, darf weg.)
- `Theme.Colors` und `Theme.create/corner/padding/list/label/button/panel/
  constrain/Root` werden von zehn UI-Modulen benutzt. Erweitern ist frei,
  Entfernen bricht die Oberfläche.
- Reparaturbalken (`RepairView`) werden in das Auto-Modell geparented und
  sterben mit ihm. Der Schlüssel ist `ProfileOps.RepairKey(carIndex, slotId)`
  = `"1:engine"`. Wer die Auto-Lebensdauer ändert, muss `view.repairBars`
  passend mitpflegen.
- Der Verkehr auf der Rennstrecke (`TrafficController`) läuft rein
  clientseitig und wird nie repliziert. Nicht auf den Server verschieben,
  ohne die Anzahl drastisch zu senken.
- `AdminService:IsAdmin` entscheidet **auf dem Server** (Studio, `game.CreatorId`,
  `Config.ADMIN_USER_IDS`). Das Panel auf dem Client ist reine Anzeige; jeder
  Befehl wird noch einmal geprüft.
- Der `LobbySpawn` liegt **in** der Werkhalle (`-243, 0.5, 0` =
  `SpawnHall.SPAWN_CFRAME`). `GarageService:_placeCharacter` lässt genau dann
  jemanden dort stehen, wenn `ProfileOps.GarageValue(data) <= 0` ist und
  `view.leftHall` noch nicht gesetzt wurde. Wer den Spawn verschiebt, muss die
  Halle mitverschieben — sonst spawnen Neulinge im Nichts. Das Warp-Pad ruft
  `GarageService:SendToPlot` auf; verdrahtet wird es im Bootstrap **nach** der
  `Start()`-Schleife, weil `GarageService` die Plots vorher nicht kennt.
- Die Halle belegt `x = -252..-178`, `z = ±62`. Der Hof-Aufbau in `RaceTrack`
  (Container, Rampen, Lichtmasten) muss um diesen Block herum passen — beim
  Einbau der Halle standen ein Lichtmast mitten darin und ein Container 5 Studs
  vor dem Ausgang.

---

## Stand: erledigt / offen

**Erledigt:** Wirtschaft, Speichern mit Session-Lock, Heist-Schleife, Diebstahl
und Versicherung, Leerstandsgaragen, Tagesbelohnung, Rangliste, Rebirth,
Garagenoptik nach Stufe, erhöhte Rennstrecke mit clientseitigem Verkehr,
Deckung im Hof, Spawn-Werkhalle mit Drei-Stationen-Erklärung und Warp-Pad,
Onboarding-Ziele, Admin-Werkzeuge.

**Offen, nach Wirkung sortiert:**

1. **Keine Sound-IDs.** `SoundCatalog` ist verdrahtet, aber alle IDs fehlen.
   Sirene beim Heist-Start und ein leiser Verkehrsteppich sind die zwei Zahlen
   mit dem besten Aufwand-Wirkung-Verhältnis im ganzen Projekt.
2. **`GarageView.RenderCars` baut bei jeder Zustandsänderung ALLE Autos eines
   Spielers neu.** Bei ~63 Parts pro Auto ist das ein spürbarer Ruckler während
   eines Klau-Fensters. Der Fix ist eine Signatur pro Auto
   (`carId` + je Slot `tier`/`subTier`/`uid`/`inTransit`) und nur die
   Unterschiede neu bauen. **Stolperstein:** `view.repairBars` wird in
   `GarageService:Refresh` pauschal auf `nil` gesetzt, weil die Balken bisher
   mit den Modellen starben. Wer diffed, muss stattdessen gezielt die Einträge
   mit Präfix `carIndex .. ":"` löschen.
3. **Alle Produkt- und Badge-IDs stehen auf 0.** Monetarisierung ist
   implementiert, aber nicht scharf.
4. **Tutorial-Fortschritt wird nicht gespeichert.** `Onboarding` merkt sich den
   Stand nur für die Sitzung. Sauber wäre ein Feld `tutorialDone` in
   `ProfileTemplate`.
5. **Tutorial-Fortschritt der Halle ist nicht gespeichert.** `view.leftHall`
   lebt nur in der Sitzung. Wer noch nichts verbaut hat und stirbt, landet
   wieder in der Halle — inhaltlich richtig, aber ein Feld im Profil wäre
   sauberer (siehe Punkt 4).
6. **Rennstrecke ist nicht betretbar.** Reine Kulisse. Wenn sie bespielbar
   werden soll (hochkommen, oben klauen), braucht es Zugang, Kollision und
   serverseitigen Verkehr — das ist ein eigenes Projekt.

---

## Definition of Done für jede Änderung

Eine Aufgabe ist fertig, wenn alle Punkte zutreffen:

- [ ] Kein Cash-, Preis- oder Berechtigungswert wird auf dem Client bestimmt.
- [ ] Jedes neue Remote hat einen Cooldown in `Config`.
- [ ] Jede neue Zahl steht in `Config`, nicht im Code.
- [ ] Keine bestehende öffentliche Modul-API wurde umbenannt oder entfernt.
- [ ] Neue Bootstrap-Schritte laufen in `step(...)`.
- [ ] Die Datei bleibt unter ~350 Zeilen oder wurde aufgeteilt.
- [ ] Kommentare erklären *warum*, auf Deutsch.
- [ ] In Studio gestartet, Konsole zeigt
      `[Garage Heist] Server bereit: 11/11 Services, 12 Garagen gebaut.`
      und keine Warnungen.
- [ ] Mit zwei Spielern getestet, falls die Änderung Heist, Diebstahl oder
      Plots berührt.

---

## Was du NICHT tun sollst

- Kein Umbau auf ein einzelnes großes Skript, auch nicht „vorübergehend".
- Keine neue Datenhaltung neben `DataService`.
- Keine Berechnung von Raten oder Preisen im Client, auch nicht „nur zur
  Anzeige" — die Anzeige kommt aus dem Snapshot.
- Keine externen Asset-IDs erfinden. Wenn eine ID fehlt, `0` lassen und
  benennen.
- Keine Rewrites von `PlotBuilder`, `CarBuilder` oder `Theme` ohne konkreten
  Anlass — an denen hängt jeweils der halbe Rest.
