# Fehlende Assets

Alle Felder stehen gesammelt in `src/ReplicatedStorage/Shared/Assets.lua` und sind
auf `""` gesetzt. **Hier ist keine einzige Asset-Id erfunden worden.**

Der Code prüft vor jeder Verwendung auf `""` und überspringt das Asset dann. Eine Id
eintragen genügt — es ist keine Code-Änderung nötig.

## Sounds

| Feld | Wo es abgespielt wird | Was da hin soll |
|---|---|---|
| `Sounds.DealComplete` | `UI/RoundHud.lua` → `Notify("good", …)` | Kurzer, trockener Bestätigungston, wenn ein Deal auszahlt. Max. 0,4 s, darf sich bei 10 Deals/Minute nicht abnutzen. |
| `Sounds.DepositComplete` | `UI/RoundHud.lua` → `Notify("banked", …)` | Der Belohnungsmoment des Spiels. Voller, satter Ton, deutlich hörbarer als DealComplete — hier wird Geld unantastbar. ~0,8 s. |
| `Sounds.RaidSiren` | `UI/RoundHud.lua` → `FlashRaid()` | Kurze, harte Sirene/Alarm zum roten Bildschirmblitz. ~1 s, muss den Spieler erschrecken, ohne zu nerven. |
| `Sounds.Warning` | `UI/RoundHud.lua` → `Notify("warn"/"bad", …)` | Leiser, neutraler Fehlerton für „zu weit weg", „beschäftigt", „Deal abgebrochen". Bewusst unauffällig. |

## Bilder / Decals

| Feld | Wo es gesetzt wird | Was da hin soll |
|---|---|---|
| `Images.TerminalScreen` | `Modules/MapBuilder.lua` → `addDecal(screen, …)` | Decal für die Leuchtfläche des Terminals (`NormalId.Right`). Terminal-Optik, dunkel mit hellem Raster — muss neben der Neon-Fläche noch lesbar sein. |
| `Images.BankSign` | `Modules/MapBuilder.lua` → `addDecal(counter, …)` | Decal für den Bank-Tresen (`NormalId.Left`). Muss aus 150 Studs Entfernung als „das ist die Bank" erkennbar sein — das ist der Orientierungspunkt quer über die Map. |

## Bewusst ohne Asset gebaut

- **Map.** Boden, Terminals und Bank entstehen in `MapBuilder.lua` aus Parts. Kein
  externes Modell wird referenziert. Grau und beschriftet, aber vollständig spielbar.
- **UI.** Alle Panels, Leisten und Karten sind in Code gebaut (`UI/Theme.lua` hält
  Farben und Instanz-Helfer). Keine Bild-Assets, keine Fremdschriften — nur
  `Enum.Font.Gotham` / `GothamBold`.
- **Razzia-Effekt.** Der rote Vollbild-Blitz ist ein getweentes `Frame`, kein
  ParticleEmitter und kein PostEffect.
