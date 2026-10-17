# AI Empire – Shop: Anleitung für den Besitzer (Stand Paket „shop“, SHOP_SPEC Phase 1 + 2)

Alle Kauf-Knöpfe im Spiel sind fertig, aber **jede ID steht noch auf `0`**. Mit `0` zeigt das Spiel keinen Kauf-Knopf
(im veröffentlichten Spiel) bzw. „Not set up“ (in Studio). Du legst die Produkte im Creator Hub an und trägst die IDs ein.
Niemand außer dir darf eine ID eintragen; der Code erfindet nie eine.

## 1. Was jetzt angelegt werden darf

| Was | Art im Creator Hub | Listed? | Wann | Vorschlag R$ | Suchtext in ShopConfig |
|---|---|---|---|---:|---|
| Eureka | Developer Product | **Unlisted** | jetzt | 15 | `key = "eureka", id = 0` |
| Last Epoch | Developer Product | **Unlisted** | jetzt | 9 | `key = "lastEpoch", id = 0` |
| Keynote Boost | Developer Product | **Unlisted** | jetzt | 35 | `key = "keynote", id = 0` |
| Overclock | Developer Product | **Unlisted** | jetzt | 19 | `key = "overclock", id = 0` |
| Rooftop Fireworks | Developer Product | Listed | jetzt (Phase 2 fertig) | 19 | `key = "fireworks", id = 0` |
| Seed round | Developer Product | Listed | jetzt (Entscheidung S1 umgesetzt) | 25 | `key = "seed", id = 0` |
| Series A | Developer Product | Listed | jetzt | 45 | `key = "seriesA", id = 0` |
| Series B | Developer Product | Listed | jetzt | 75 | `key = "seriesB", id = 0` |
| Headhunter | Developer Product | Listed | jetzt (arbeitet jetzt immer gleich: Fähigkeit 4) | 39 | `key = "headhunter", id = 0` |
| Identity Kit | Pass | (immer sichtbar) | jetzt | 59 | `key = "identityKit", id = 0` |
| Server Glow | Pass | (immer sichtbar) | jetzt (Phase 2 fertig) | 45 | `key = "serverGlow", id = 0` |
| Stage Lights | Pass | (immer sichtbar) | jetzt (Phase 2 fertig) | 39 | `key = "stageLights", id = 0` |
| Style Collection | Pass | (immer sichtbar) | jetzt (enthält die drei oben) | 109 | `key = "styleCollection", id = 0` |
| Team party, Supporter tip, Big supporter tip | Developer Product | Listed | jederzeit | 25 / 25 / 100 | `key = "party", id = 0` usw. |
| VIP Founder, Executive Limo, Founder Suite, Investor Relations | Pass | (immer sichtbar) | jederzeit | 149 / 199 / 199 / 349 | `key = "vip", id = 0` usw. |
| AI Gallery, Team Hoodies, Robo Buddy | Pass | – | **noch nicht** (Phase 3, im Code `ready = false`) | 65 / 75 / 95 | – |

Die Preise sind nur Vorschläge (stehen auch als Kommentar hinter jeder Zeile). Den echten Preis legst du im Creator Hub fest;
das Spiel liest ihn von Roblox und zeigt ihn als „R$ 15“.

## 2. Schritt für Schritt
1. Spiel veröffentlichen, dann **create.roblox.com → Creations → dein Spiel**.
2. **Developer Products**: Monetization → Developer Products → neues Produkt. Bild (höchstens 512×512) hochladen,
   **Name und Beschreibung genau aus SHOP_SPEC Abschnitt 2 kopieren** (dieselben Texte wie im Spiel), Preis setzen,
   speichern. ID kopieren: Maus aufs Bild → **⋯ → Copy Asset ID**.
   - Für die drei Geld-Pakete ist der Spieltext abhängig vom Büro („+$2,700 … 10 % of the Founder Headquarters price“).
     Im Creator Hub bitte diesen festen Text nehmen:
     - Seed round: „Company cash now: 10 % of your next office price. One per office.“
     - Series A: „Company cash now: 20 % of your next office price. One per office.“
     - Series B: „Company cash now: 30 % of your next office price. One per office.“
3. **Eureka, Last Epoch, Keynote Boost, Overclock auf „Unlisted“ stellen** (sie wirken nur im Spiel). Laut Roblox-Doku
   kann man sie trotzdem über unseren Knopf im Spiel kaufen – bitte einmal im veröffentlichten Spiel ausprobieren
   (Test T22 unten).
4. **Pässe**: Monetization → Passes → Create pass. Nur die Pässe aus der Tabelle mit „jetzt“/„jederzeit“.
5. Jede ID in **`ReplicatedStorage/Shared/Config/ShopConfig.module.luau`** eintragen: nach dem Suchtext suchen und die
   `0` hinter `id =` durch die ID ersetzen. Speichern, **neu veröffentlichen**.
6. **Nie** eine ID erfinden, nie eine alte ID für etwas anderes benutzen.

## 3. In Studio nachsehen (Besitzer-Vorschau)
In Studio zeigt der Shop oben „OWNER PREVIEW · Studio only“ und alle Sachen mit „Not set up“. Ein Druck darauf kauft nie
etwas, er erklärt nur, dass die ID fehlt. So siehst du, wo jeder Knopf sitzt, bevor du etwas anlegst. Gekauft wird nur im
veröffentlichten Spiel.

## 4. Was im Spiel wo erscheint (alles erst nach der Anleitung „Erste Schritte“ und nach dem ersten Start eines Modells)
- **Menü → Shop**: 5 Reiter (Home, Speed-ups, Boosts, Style, Extras). Ein Reiter erscheint erst, wenn darin etwas zu
  kaufen ist. Oben „YOUR ITEMS“ mit gekauften, noch nicht benutzten Sachen.
- **Lab → Research**: neben START ein Knopf „EUREKA“ (zeigt immer, wie viel Zeit er spart; unter 30 Sekunden kein
  Kauf-Knopf). **Lab-Karte**: „LEVEL UP · EUREKA“. **Model Studio**, wenn 7B nur noch Frontier Architecture braucht:
  „SKIP RESEARCH · EUREKA“. **Training**: „FINISH NOW · LAST EPOCH“ (ab 20 Sekunden Restzeit).
- **Team → Settings**: „Change colour & logo“ – kostenlos für alle; die 8 Extra-Farben und 6 Extra-Logos brauchen das
  Identity Kit (Schloss-Symbol, kein Kauf-Knopf dort).
- Vor jeder Benutzung kommt eine Frage („Use 1 Eureka on …?“). Nach einem Kauf aus so einem Knopf fragt das Spiel
  „Eureka received. Use it now?“ – es benutzt nie etwas von selbst.

## 5. Grenzen (damit niemand das Spiel „überspringt“)
- Geld-Pakete: jede Größe **einmal pro Büro**, 10 / 20 / 30 % des nächsten Büros (Garage: $2,700 / $5,400 / $8,100).
- Keynote Boost und Overclock: je 4 Starts pro Tag (UTC), höchstens 60 Minuten Restzeit. Last Epoch: 10 pro Tag.
- Eureka: höchstens so viele, wie es noch Forschung gibt (8 Projekte + 10 Lab-Stufen).
- Der Simulator (agents/shop2/sim) zeigt: Spieler ohne Käufe sind **bytegenau gleich** wie vorher; ein sehr
  kaufkräftiger Spieler (alle Pakete, alle Eurekas, alle Boosts) braucht für das letzte Büro 89–105 statt 165–169
  Minuten – also immer noch über anderthalb Stunden, nicht 6 Minuten wie mit den alten Paket-Größen. Ein Spieler ohne
  Käufe auf demselben Server ist dadurch nur 5 % langsamer.

## 6. Bitte im veröffentlichten Spiel / in Studio prüfen (kann ich hier nicht testen)
- **T22**: ein *Unlisted* Developer Product (z. B. Eureka) lässt sich über unseren Knopf kaufen.
- **T23**: Feuerwerk auf dem Handy: ruckelt es? (4 Abschussstellen, alle 1,1 s ein Schwall.)
- **T24**: Die 6 Extra-Logos (✦ ⬢ ◆ ✚ ◐ ⌬) werden in der Schrift angezeigt; Server Glow mit „Reduced Motion“ an
  (dann leuchten die Racks ruhig wie bisher).
- Ob „R$ 15“ mit dem echten Robux-Zeichen schöner wäre, entscheidest du nach einem Blick im echten Spiel.
