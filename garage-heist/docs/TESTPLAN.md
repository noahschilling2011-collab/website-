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
2. Warten bis das HUD `KLAU-FENSTER OFFEN` zeigt (erstes Fenster nach 150s;
   fuer den Test `Config.HEIST_FIRST_DELAY` auf 15 setzen).
3. Tore beider Garagen sind offen. Spieler A geht zu B, haelt `E` am Teil.
4. **Pruefen:** Balken laeuft 4 Sekunden. Geht A weiter als 16 Studs weg, bricht er ab.
5. **Pruefen:** B sieht `... schraubt an deinem Auto!` und danach
   `... hat dir <Teil> abmontiert!`.
6. A traegt das Teil (langsamer, Teil haengt vor der Brust), stellt sich auf das
   blaue Pad in der eigenen Box. Toast: eingebaut oder "liegt jetzt in deiner Garage".
7. Gegenprobe Rempeln: B rennt zu A und drueckt `F`, waehrend A traegt. Teil faellt
   zu Boden und ist per `E` fuer jeden aufhebbar.
8. Gegenprobe Fenster-Ende: ein Teil tragen und warten, bis das Fenster zugeht.
   Erwartung: Teil geht an den Besitzer zurueck, beide sehen eine Meldung.
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

**Mit echten IDs:** Produkte laut `docs/MONETIZATION.md` anlegen, IDs eintragen,
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
