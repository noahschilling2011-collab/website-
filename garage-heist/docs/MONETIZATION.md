# Was du im Creator Dashboard anlegen musst

Alle IDs stehen als `0` oben in `src/Server/Services/MonetizationService.lua`.
Solange dort `0` steht, erscheint der Eintrag im Shop als **"nicht eingerichtet"**
und ist nicht anklickbar. Nichts stuerzt ab, nichts wird verschenkt.

Anlegen, ID kopieren, oben eintragen - fertig. Sonst musst du keine Datei anfassen.

## Gamepasses (Creator Dashboard > Experience > Monetization > Passes)

| Name im Dashboard | Preis (Empfehlung) | Konstante in `GAMEPASS_IDS` | Wirkung im Code |
|---|---|---|---|
| `VIP` | 199 R$ | `VIP` | `Config.VIP_RATE_MULT` (x2) auf die Cash-Rate, online wie offline. Dazu ein goldenes Garagentor - reine Optik, und genau so steht es auch im Shop-Text. |
| `Auto-Collect` | 149 R$ | `AutoCollect` | Einnahmen gehen direkt aufs Konto statt in die Kasse; der Kassen-Deckel (2h) entfaellt damit. |
| `Garage Lock` | 249 R$ | `GarageLock` | Das eigene Tor faellt `Config.GARAGE_LOCK_WINDOW` (20s) nach Fensteroeffnung wieder zu, Klau-Prompts gehen aus. |

## Developer Products (Creator Dashboard > Experience > Monetization > Developer Products)

| Name im Dashboard | Preis (Empfehlung) | Konstante in `PRODUCT_IDS` | Wirkung im Code |
|---|---|---|---|
| `Cash-Paket S` | 25 R$ | `CashSmall` | +5.000 Cash |
| `Cash-Paket M` | 99 R$ | `CashMedium` | +30.000 Cash |
| `Cash-Paket L` | 399 R$ | `CashLarge` | +150.000 Cash |
| `Instant Repair` | 19 R$ | `InstantRepair` | Setzt die laufende Reparatur auf "fertig". Ohne laufende Reparatur wird der Kauf nicht verbucht (`NotProcessedYet`) und Roblox bucht nicht ab. |
| `Heist Radar` | 49 R$ | `HeistRadar` | Eine Ladung: zeigt beim naechsten (oder laufenden) Fenster die 5 wertvollsten Teile im Server. Die Ladung liegt im Profil und ueberlebt einen Rejoin. |

Die Preise stehen zusaetzlich als Anzeigetext in der `CATALOG`-Tabelle im
`MonetizationService`. Aenderst du den Preis im Dashboard, aendere ihn dort mit -
der Server verkauft nichts selbst, der Text ist reine Anzeige.

## Warum diese Zahlen die Balance nicht kippen

- Das teuerste Garagen-Upgrade kostet 260.000, der Supersportler 75.000. Das
  groesste Cash-Paket (150.000) ist ein Vorsprung, kein Endstand.
- Cash kauft keine Reparaturzeit. Wer alles kauft, wartet trotzdem 200 Sekunden
  auf ein Anti-Lag-Kit - ausser er kauft zusaetzlich Instant Repair, einzeln,
  pro Reparatur.
- Gekaufte Teile sind waehrend des Klau-Fensters genauso abmontierbar wie
  erspielte. Robux kaufen keinen Schutz, ausser Garage Lock - und der verkuerzt
  das Fenster, er schliesst es nicht.
- VIP verdoppelt die Rate, aber nicht den Diebstahl-Ertrag. Ein Nicht-Zahler
  holt sich den Unterschied im Fenster zurueck.

## Was bewusst nicht drin ist

- **Robux-Kauf von Teilen direkt**: wuerde den Loop ersetzen statt beschleunigen.
- **Schutz vor dem Klau-Fenster fuer Geld**: Garage Lock verkuerzt das Fenster
  auf 20 Sekunden, aber niemand kann es ganz abkaufen.

## ProcessReceipt

`MonetizationService:_processReceipt` haelt jede verarbeitete `PurchaseId` im
Profil (`data.receipts`, FIFO-begrenzt auf 60 Eintraege). Feuert Roblox denselben
Receipt erneut, wird er erkannt und mit `PurchaseGranted` bestaetigt, ohne noch
einmal gutzuschreiben.

Gutgeschrieben wird erst, wenn das Profil auch gespeichert wurde. Scheitert das
Speichern, wird die Receipt-Markierung zurueckgenommen und `NotProcessedYet`
zurueckgegeben - Roblox liefert den Receipt dann spaeter erneut aus.
