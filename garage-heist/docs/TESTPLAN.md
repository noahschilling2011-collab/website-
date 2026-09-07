# Abnahme pro Phase

Jede Phase hat genau ein Kriterium. Erfuellt oder nicht - dazwischen gibt es nichts.
Vorher in Studio: `Enable Studio Access to API Services` einschalten, sonst
testest du gegen den In-Memory-Fallback und Speichern beweist gar nichts.

Konsolen-Zeile beim Start pruefen: kommt `[SessionStore] Kein DataStore-Zugriff`,
laeuft der Fallback.

---

## Phase 1 - Fundament

**Fertig wenn:** Spieler joint, kauft ein Teil, verlaesst das Spiel, kommt zurueck -
Teil ist noch da, Cash stimmt. **Zweimal hintereinander.**

1. Studio > Test > Play. Menue geht von allein auf, Cash = 250.
2. Reifen T1 kaufen (100). Cash muss 150 sein, Zeile zeigt "wird eingebaut - noch Xs".
3. 6 Sekunden warten: Toast "Notrad-Satz ist eingebaut", Raeder am Auto sind nicht
   mehr durchsichtig, Billboard zeigt `$0,4/s`.
4. Stop. Erneut Play.
5. **Pruefen:** Reifen sind verbaut, Cash = 150 + Offline-Einnahmen der Pause.
6. Schritte 1-5 ein zweites Mal.

Fehlerbild, das zaehlt: Cash zurueck auf 250 oder Teil weg = Phase 1 nicht bestanden.

---

## Phase 2 - Passives Einkommen

**Fertig wenn:** Nach 10 Minuten Abwesenheit kommt die korrekte, auf dem Server
berechnete Summe an, und der Deckel greift nachweislich.

**Korrekte Summe:**
1. Teile kaufen, bis das HUD z.B. `$1,5/s` zeigt. Wert notieren.
2. Stop. 10 Minuten warten (echte Uhr). Play.
3. Erwartung: Toast `Offline-Einnahmen: ~900 fuer 10:00` (1,5 x 600 = 900).
   Abweichung nur, wenn waehrenddessen eine Reparatur fertig wurde - dann ist die
   Summe hoeher, weil `EconomyService:_applyOffline` in Abschnitte teilt.

**Deckel (ohne 8 Stunden zu warten):**
1. `Config.OFFLINE_CAP_SECONDS` voruebergehend auf `60` setzen.
2. Rate merken, Stop, 3 Minuten warten, Play.
3. Erwartung: Gutschrift = Rate x 60, Toast endet auf `(Deckel: 8h)`.
4. Wert zurueck auf `8 * 60 * 60`.

**Gegenprobe Server-Autoritaet:** In der **Client**-Konsole direkt Remotes feuern:

```lua
local R = require(game.ReplicatedStorage.Shared.Remotes)
R.Get("RequestBuyPart"):FireServer(99, "engine")     -- "Dieses Auto gehoert dir nicht."
R.Get("RequestBuyPart"):FireServer(1, "raketen")     -- "Unbekannter Teile-Slot."
R.Get("RequestSellLoosePart"):FireServer("egal")     -- "Das Teil liegt nicht in deiner Garage."
R.Get("RequestBuyPart"):FireServer(1, "turbo")       -- nur wenn das Cash wirklich reicht
```

Es gibt kein Remote, das einen Betrag entgegennimmt - der Client kann nur sagen,
*was* er will, nie *wie viel* es kostet.

---

## Phase 3 - Klau-Fenster

**Fertig wenn:** Zwei Test-Spieler klauen sich gegenseitig ein Teil, der
Bestohlene sieht eine Meldung, und nach dem Fenster ist alles korrekt gespeichert.

Studio > Test > **2 Players** starten.

1. Beide kaufen je ein Teil und warten den Einbau ab.
2. Warten bis das HUD `KLAU-FENSTER OFFEN` zeigt (erstes Fenster nach 45s,
   danach alle 3,5 Minuten).
3. Tore beider Garagen sind offen. Spieler A geht zu B, haelt `E` am Teil.
4. **Pruefen:** Balken laeuft 4 Sekunden. Geht A weiter als 16 Studs weg, bricht er ab.
5. **Pruefen:** B sieht `... schraubt an deinem Auto!` und danach
   `... hat dir <Teil> abmontiert!`.
6. A traegt das Teil (langsamer, Teil haengt vor der Brust), stellt sich auf das
   blaue Pad in der eigenen Box. Toast: eingebaut oder "liegt jetzt in deiner Garage".
7. Gegenprobe Rempeln: B rennt zu A und drueckt `F`, waehrend A traegt. Teil faellt
   zu Boden und ist per `E` fuer jeden aufhebbar.
8. Gegenprobe Fenster-Ende: ein Teil tragen und warten, bis das Fenster zugeht.
   Erwartung: Die Transit-Markierung faellt, das Teil ist beim Besitzer wieder
   in Betrieb, der Traeger sieht "Zu spaet abgeliefert".
9. Beide verlassen und rejoinen: Bestand stimmt bei beiden.

---

## Phase 4 - Robux-Layer

**Fertig wenn:** Kauf im Studio-Testmodus simuliert, Gutschrift kommt genau einmal
an, auch wenn `ProcessReceipt` mehrfach feuert.

Ohne echte Produkt-IDs laesst sich `ProcessReceipt` nur direkt aufrufen. In der
**Server**-Konsole (Studio, waehrend Play):

```lua
local Monetization = require(game.ServerScriptService.Server.Services.MonetizationService)
local receipt = {
    PlayerId = game.Players:GetPlayers()[1].UserId,
    PurchaseId = "TEST-123",
    ProductId = 987654321,   -- vorher PRODUCT_IDS.CashSmall auf diese Zahl setzen
    CurrencySpent = 25,
}
print(Monetization:_processReceipt(receipt))   -- PurchaseGranted, +5.000 Cash
print(Monetization:_processReceipt(receipt))   -- PurchaseGranted, KEINE zweite Gutschrift
```

**Pruefen:** Cash steigt genau einmal um 5.000. Der zweite Aufruf gibt ebenfalls
`PurchaseGranted` zurueck (so soll es sein - Roblox darf den Receipt nicht ewig
wiederholen), aber der Kontostand bleibt gleich.

Danach `PRODUCT_IDS.CashSmall` wieder auf `0` setzen, sonst zeigt der Shop ein
Produkt an, das es nicht gibt.

**Mit echten IDs:** Produkte laut `docs/SETUP.md` anlegen, IDs eintragen,
im Shop kaufen. Bei einem Gamepass muss die Rate sofort verdoppelt sein
(HUD `$x/s`), ohne Rejoin.

---

## Phase 5 - Retention

**Fertig wenn:** Ein neuer Spieler hat ohne Erklaerung nach einer Minute sein
erstes Teil verbaut.

1. DataStore-Eintrag des Testkontos loeschen oder ein zweites Konto nehmen.
2. Stoppuhr an, Play, **nichts erklaeren**.
3. Erwartung: Menue ist offen, Toast nennt den Preis, Reifen T1 = 100 bei 250
   Startkapital, Einbau 6 Sekunden. Realistisch: erstes Teil nach 15-25 Sekunden.

**Daily:** Knopf "Taeglich" ist gruen, wenn abholbar. Abholen gibt Tag 1 = 250.
Zum Testen der Kette `data.daily.lastDay` in der Server-Konsole auf
`Util.UtcDay() - 1` setzen (Kette laeuft weiter) bzw. `- 3` (Kette faellt auf 1).

**Leaderboard:** Tafel im Hof (Mitte, zwischen den Reihen) und der Knopf
"Rangliste" zeigen dieselben zwei Listen. Nach einem Klau muss "Geklaute Teile
heute" innerhalb von 5 Sekunden hochzaehlen.

---

# Ausbau-Stufe: die zehn Abnahmepunkte

Diese Liste gehoert zum zweiten Ausbau (Leerstand, Takt, Rebirth, Praesentation,
Mobile, Bugfixes, Telemetrie). Erst abhaken, wenn alles zutrifft.

### 1. Allein im Server klauen koennen

Studio > Test > Play (ein Spieler). Nach 45 Sekunden geht das erste Fenster auf.

- Mindestens eine freie Box zeigt am Schild **"Leerstand - offen"** und ein Auto.
- `E` am Teil -> Balken laeuft 4 Sekunden -> Teil haengt am Charakter.
- Auf das blaue Pad in der eigenen Box -> Rate steigt sichtbar.
- **Pruefen:** Die Rate steigt nur um 60 % des Katalogwerts
  (`Config.DERELICT_VALUE_MULT`). Ein Leerstand-Motor T1 bringt 0,36/s statt 0,6/s.

### 2. Rebirth

Testprofil in der Server-Konsole hochziehen:

```lua
local DataService = require(game.ServerScriptService.Server.Services.DataService)
local ProfileOps  = require(game.ServerScriptService.Server.Data.ProfileOps)
local player = game.Players:GetPlayers()[1]
local data = DataService:Get(player)
data.garageLevel = 5
for i in data.cars do
    for _, slot in {"engine","tires","paint","turbo"} do
        ProfileOps.SetPart(data, i, slot, { uid = "test"..i..slot, slotId = slot, tier = 4, subTier = 2, originalOwner = player.UserId })
    end
end
require(game.ServerScriptService.Server.Services.GarageService):Refresh(player, data)
```

- Im Werkstatt-Menue erscheint der Abschnitt **Rebirth** mit aktivem Knopf.
- Klick -> Bestaetigungsdialog -> "Ja, durchziehen".
- **Pruefen:** Cash zurueck auf 250, ein Schrottauto, Garage Stufe 1,
  aber die Rate traegt jetzt den Faktor 1,25. Nach dem zweiten Rebirth 1,5.
- **Pruefen:** Ab Rebirth 1 ist ein Stellplatz mehr frei als die Garagenstufe hergibt.

### 3. Zwischenstufen und Altprofile

- Ein Teil kaufen. Danach zeigt die Zeile als naechsten Kauf **"Fein …"**.
- Zwei Feinabstimmungen kaufen -> hinter dem Namen stehen `++`, die Rate steigt je +12 %.
- **Pruefen:** Der anschliessende Stufensprung kostet weniger als der Katalogpreis
  (`PartCatalog.TierUpgradeCost` zieht die gezahlten Feinstufen ab). Zusammen
  ergibt der Weg wieder genau den Katalogpreis.
- **Altprofil:** In der Konsole `data.cars[1].parts.engine.subTier = nil` setzen,
  Spiel verlassen, neu beitreten. Es darf kein Fehler kommen; die Anzeige steht
  auf 0 Feinstufen. (`SCHEMA_VERSION = 2`, gelesen wird ueberall `subTier or 0`.)

### 4. Beklaut und rausgeflogen - Teil bleibt

Zwei Test-Spieler.

1. Spieler B montiert waehrend des Fensters ein Teil von A ab und traegt es.
2. **Pruefen bei A:** Das Teil ist am Auto ausgeblendet, die Zeile sagt
   "wird gerade weggetragen", die Rate ist entsprechend niedriger.
3. Jetzt A das Spiel verlassen lassen, waehrend B noch traegt.
4. B liefert ab -> B bekommt nichts ("Der Besitzer ist weg").
5. A tritt neu bei: **Das Teil ist noch da und zaehlt wieder.**
6. Gegenprobe mit A online: B liefert ab -> A verliert das Teil und bekommt
   25 % des Werts als Versicherung mit eigener Meldung.

### 5. Hochformat

Studio > Test > Device > iPhone (390 x 844) oder Fenster entsprechend ziehen.

- Nichts ist abgeschnitten: Cash, Heist-Anzeige, die vier Knoepfe rechts,
  Kasse, Rempeln, Ablegen.
- Alle Aktionen ohne Tastatur erreichbar (die Tastenkuerzel sind Zugabe).
- Menues fuellen den Bildschirm, laufen aber nicht darueber hinaus.

### 6. Licht und Klang

- Beim Start: Abenddaemmerung, Nebel, jede Garage hat eine Neonleiste ueber dem Tor.
- Tor offen -> Leiste und Licht wechseln von Blau auf Rot.
- **Klaenge sind stumm, solange keine IDs eingetragen sind** - das ist der
  Auslieferungszustand. Liste in `docs/SETUP.md`, Abschnitt 4.
- Beim Abmontieren spruehen Funken, beim Abliefern gibt es einen Partikelstoss,
  das getragene Teil zieht eine Spur.

### 7. Bugs

| Bug | Gegenprobe |
|---|---|
| Teile vernichtet | Test 4 oben |
| Drosselung | In der Client-Konsole `for i=1,100 do R.Get("RequestCollect"):FireServer() end` - hoechstens eine Buchung |
| Ladehaenger | `Config.LOAD_TOTAL_BUDGET` auf 3 setzen, DataStore-Namen auf Unsinn aendern: sauberer Kick statt Haenger |
| Wandernde Garage | Beitreten, Boxnummer merken, verlassen, neu beitreten - dieselbe Box |
| Griefing | Test 4, Schritt 6: Versicherung kommt an |
| Nichts verkaeuflich | Shop oeffnen: alle acht Eintraege stehen auf "nicht eingerichtet" statt zu verschwinden |

### 8. Telemetrie

- Server-Konsole beim Beitreten: keine `[Telemetry]`-Warnung (in Studio ohne
  veroeffentlichtes Spiel koennen Warnungen kommen - das ist erwartbar und
  bricht nichts).
- Funnel-Schritte im Creator Dashboard unter Analytics > Funnels, sobald das
  Spiel veroeffentlicht ist: Profil geladen, erstes Teil, erstes Fenster,
  erstes Diebesgut.

### 9. Zehn Minuten am Stueck

Play druecken, zehn Minuten laufen lassen, dabei kaufen, klauen, abliefern.
**Kein roter Fehler und keine gelbe Warnung** in der Konsole - ausgenommen die
`[SessionStore]`-Meldung, wenn API Services aus sind.

### 10. Keine harten Zahlen im Code

```bash
grep -rnE "= [0-9]{3,}" src/Server src/Client --include=*.lua | grep -v Config
```

Treffer duerfen nur Bildschirmkoordinaten sein. Alles, was Spielbalance ist,
gehoert nach `src/Shared/Config.lua`.
