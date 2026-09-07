# Einrichtung — jede ID, die du selbst eintragen musst

Nichts hiervon ist geraten. Wo im Code `0` oder `""` steht, ist die ID
absichtlich leer: eine erfundene Asset-ID wäre schlimmer als gar keine, weil sie
im Zweifel fremde Inhalte lädt oder einen Kauf ins Leere schickt.

Solange eine ID leer ist, passiert schlicht nichts — kein Fehler, kein Absturz.
Produkte erscheinen im Shop als **"nicht eingerichtet"** und sind nicht
anklickbar, Klänge bleiben stumm, Badges werden nicht vergeben.

---

## 1. Gamepasses

Creator Dashboard → Experience → Monetization → **Passes**

| Name im Dashboard | Preis (Empfehlung) | Zeile im Code |
|---|---|---|
| `VIP` | 199 R$ | `MonetizationService.lua`, `GAMEPASS_IDS.VIP` |
| `Auto-Collect` | 149 R$ | `MonetizationService.lua`, `GAMEPASS_IDS.AutoCollect` |
| `Garage Lock` | 249 R$ | `MonetizationService.lua`, `GAMEPASS_IDS.GarageLock` |

Der Anzeigepreis im Shop steht zusätzlich in der `CATALOG`-Tabelle derselben
Datei. Änderst du den Preis im Dashboard, ändere ihn dort mit — der Server
verkauft nichts selbst, der Text ist reine Anzeige.

## 2. Developer Products

Creator Dashboard → Experience → Monetization → **Developer Products**

| Name im Dashboard | Preis (Empfehlung) | Zeile im Code |
|---|---|---|
| `Cash-Paket S` | 25 R$ | `MonetizationService.lua`, `PRODUCT_IDS.CashSmall` |
| `Cash-Paket M` | 99 R$ | `MonetizationService.lua`, `PRODUCT_IDS.CashMedium` |
| `Cash-Paket L` | 399 R$ | `MonetizationService.lua`, `PRODUCT_IDS.CashLarge` |
| `Instant Repair` | 19 R$ | `MonetizationService.lua`, `PRODUCT_IDS.InstantRepair` |
| `Heist Radar` | 49 R$ | `MonetizationService.lua`, `PRODUCT_IDS.HeistRadar` |

Was die Produkte tun und warum sie die Balance nicht kippen: `docs/MONETIZATION.md`.

## 3. Badges

Creator Dashboard → Experience → **Badges**. Alle drei Zeilen stehen in
`src/Shared/Config.lua` unter `Config.BADGE_IDS`.

| Name im Dashboard | Wofür | Schlüssel in `Config.BADGE_IDS` |
|---|---|---|
| `Erster Coup` | Erstes abgeliefertes Diebesgut | `FirstSteal` |
| `Sechsstellig` | 100.000 Cash auf dem Konto | `Rich` |
| `Neuanfang` | Erster Rebirth | `FirstRebirth` |

## 4. Klänge

Alle IDs stehen in `src/Shared/SoundCatalog.lua` und sind **leer**. Such dir im
Creator Store passende Sounds (Filter: Audio, kostenlos, „Distribute" erlaubt)
und trage die `rbxassetid://…` ein.

| Schlüssel | Wann er spielt | Art |
|---|---|---|
| `doorOpen` | Garagentor fährt hoch oder runter | räumlich |
| `dismount` | Während der 4 Sekunden Abmontieren (Ratsche/Schrauber) | räumlich |
| `deposit` | Diebesgut auf dem Abgabe-Pad (Registrierkasse) | räumlich |
| `tackle` | Rempler-Treffer | räumlich |
| `countdown` | Jede der letzten 5 Sekunden vor dem Fenster | lokal |
| `windowOpen` | Klau-Fenster geht auf (Alarm/Hupe) | lokal, alle Spieler |
| `purchase` | Teil gekauft | lokal |
| `repairDone` | Teil ist eingebaut | lokal |

Ohne ID passiert nichts. `SoundCatalog.Missing()` gibt dir zur Laufzeit die
Liste der noch leeren Schlüssel zurück.

## 5. Place-Einstellungen

| Einstellung | Wert | Warum |
|---|---|---|
| `Game Settings > Security > Enable Studio Access to API Services` | **an** | Sonst läuft der Speicher im In-Memory-Fallback und nichts wird gesichert. Die Konsole schreibt das laut hin. |
| `Game Settings > Places > Max Players` | **≤ 12** | Es gibt `Config.PLOT_COUNT = 12` Garagen. Wer keine bekommt, wird gekickt. |

---

## Prüfliste vor dem Veröffentlichen

- [ ] Acht Produkt-IDs eingetragen, keine steht mehr auf `0`
- [ ] Drei Badge-IDs in `Config.BADGE_IDS` eingetragen
- [ ] Acht Sound-IDs in `SoundCatalog.lua` eingetragen
- [ ] API Services aktiviert, Max Players ≤ 12
- [ ] `docs/TESTPLAN.md` einmal komplett durchgelaufen
