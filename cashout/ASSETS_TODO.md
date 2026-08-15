# Was ich besorgen muss

**Hier ist keine einzige Roblox-Id erfunden worden.** Sound-Ids stehen in
`src/ReplicatedStorage/Shared/SoundCatalog.lua` und sind alle `0`, Bild-Ids in
`src/ReplicatedStorage/Shared/Assets.lua` und alle `""`.

Der Code prüft vor jeder Verwendung und überspringt dann — das Spiel läuft mit
ausschließlich leeren Ids vollständig. Beim Serverstart kommt **eine** gesammelte
`warn()`-Zeile mit allen fehlenden Sounds, kein Spam pro Aufruf.

## Sounds (`SoundCatalog.Ids`)

### Phase 1 — jetzt schon verdrahtet

| Feld | Wo | Was da hin soll |
|---|---|---|
| `OrderAccepted` | `RoundHud.Notify("info", …)` | Kurzes Quittieren beim Annehmen eines Auftrags. Max. 0,3 s, trocken. |
| `OrderDelivered` | `RoundHud.Notify("good", …)` | Übergabe geschafft, Cash steigt. ~0,5 s, muss sich bei 10 Übergaben pro Runde nicht abnutzen. |
| `DepositComplete` | `RoundHud.Notify("banked", …)` | Der Belohnungsmoment: hier wird Geld unantastbar. Voller und deutlich hörbarer als `OrderDelivered`, ~0,8 s. |
| `ActionRefused` | `RoundHud.Notify("warn"/"bad", …)` | Leiser, neutraler Ton für „zu weit weg", „beschäftigt", „abgebrochen". Bewusst unauffällig. |
| `RoundStart` | noch nicht aufgerufen | Rundenstart-Signal. |
| `RoundEnd` | noch nicht aufgerufen | Rundenende, unter die Endtafel. |

### Phase 2 — Razzia (verdrahtet)

| Feld | Was da hin soll |
|---|---|
| `RaidAlarm` | Sirene zum Start des Fluchtfensters. Muss erschrecken, ~1 s. |
| `RaidEscaped` | Kurzer, heller Entlastungston beim Verlassen des Sperrkreises. |
| `RaidCaught` | Dumpfer Aufschlag beim Erwischtwerden. |

### Phase 3 — Abfangen (noch nicht abgespielt)

| Feld | Was da hin soll |
|---|---|
| `Intercept` | Moment des Abfangens, aus beiden Perspektiven brauchbar. |

### Phase 4 — Feel (verdrahtet)

| Feld | Was da hin soll |
|---|---|
| `Heartbeat` | Einzelner Herzschlag. Wird im Takt nach Heat abgespielt (bei Heat 30 alle 1,2 s, bei Heat 100 alle 0,45 s) — muss deshalb sehr kurz und schnittfest sein. Stärkster Feel-Hebel im ganzen Dokument. **Der Takt läuft schon**: er treibt den Vignetten-Puls, auch solange die Id 0 ist. |
| `SirenLoop` | Ferne Sirene als Loop ab Heat 60, lauter ab Heat 85. Nahtlos loopbar. |

## Bilder / Decals (`Assets.Images`)

| Feld | Wo | Was da hin soll |
|---|---|---|
| `TerminalScreen` | `MapBuilder`, Leuchtfläche des Terminals | Terminal-Optik, dunkel mit hellem Raster. Muss neben der Neon-Fläche lesbar bleiben. |
| `BankSign` | `MapBuilder`, Bank-Tresen | Muss quer über die Map als „das ist die Bank" erkennbar sein. |

## Bewusst ohne Asset gebaut

- **Map.** Boden, Bank und Terminals entstehen in `MapBuilder.lua` aus Parts, kein externes Modell.
- **Paket auf dem Rücken.** Ein eingefärbter Part, geschweißt an den Torso. Farbe = Auftragsstufe.
- **UI.** Alle Panels sind in Code gebaut (`UI/Theme.lua` hält Farben und Instanz-Helfer).
  Keine Bild-Assets, keine Fremdschriften — nur `Enum.Font.Gotham` / `GothamBold`.
- **Übergabepunkt.** Cyan-Pad plus Säule aus Parts, das eigene Ziel-Schild baut der Client dazu.
- **Nachtstadt.** Licht, Nebel und `Atmosphere` sind in `MapBuilder` gesetzt, der nasse Boden ist
  `Material.Slate` mit Reflectance — kein Regen-Partikelsystem, das auf schwacher Hardware kostet.
- **Vignette.** Vier Rand-Frames mit Verlauf statt eines radialen Vignetten-Bildes.
- **Bank-Ring.** 28 einzelne Segmente auf einem Kreis statt einer Ring-Textur.
- **Pfeil zum Übergabepunkt.** Ein gedrehtes Textzeichen, kein Icon.
- **Sperrkreis und Einzahl-Beam.** Neon-Parts.
