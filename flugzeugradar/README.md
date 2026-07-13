# 🕵️ Geheimagent, oder was? — Flugzeugradar mit ESP32 und Display

> Kurs **IT.3-M.26/1** · Mittelstufe Klasse 8–10 · Dietrich-Bonhoeffer-Schule

Baue dein eigenes **Flugzeugradar**: Ein ESP32 holt sich über WLAN echte
Live-Flugdaten und zeigt alle Flugzeuge in deiner Umgebung auf einem Display
an — wie bei der Flugsicherung, mit grünem Suchstrahl, Entfernungsringen und
Rufzeichen. 100 % legal, denn die Daten sind öffentlich!

```
┌────────────────────────┬──────────┐
│      N                 │ GEHEIM   │
│   ╭──────────╮         │ RADAR    │
│  ╱  ○    ▲DLH4KA  ╲    │──────────│
│ │   ╱ ring    ○    │   │ ZIELE: 7 │
│ W  │    ◉━━━━ sweep│ O │ RADIUS:  │
│ │   ╲    ▲RYR81T  ╱│   │  40 NM   │
│  ╲   ○           ╱     │──────────│
│   ╰──────────╯         │ KONTAKT: │
│      S                 │ DLH4KA   │
└────────────────────────┴──────────┘
```

---

## 🧠 Wie funktioniert das überhaupt? (ADS-B)

Fast jedes Flugzeug sendet ununterbrochen per Funk seine Position, Höhe,
Geschwindigkeit und sein Rufzeichen aus — das nennt man **ADS-B**
(*Automatic Dependent Surveillance – Broadcast*). Tausende Hobby-Antennen
weltweit empfangen diese Signale und speisen sie in freie Datenbanken ein.

Unser ESP32 fragt so eine Datenbank ab: **[api.adsb.lol](https://api.adsb.lol)**
— kostenlos, ohne Anmeldung, ohne API-Key. Die Abfrage lautet einfach:

```
https://api.adsb.lol/v2/lat/<Breitengrad>/lon/<Längengrad>/dist/<Radius in NM>
```

Zum Ausprobieren im Browser (Beispiel Leipzig, 40 NM):
<https://api.adsb.lol/v2/lat/51.3397/lon/12.3731/dist/40>

Zurück kommt eine JSON-Liste (Feld `ac`) aller Flugzeuge im Umkreis. Die rechnen wir in
Bildschirm-Koordinaten um und zeichnen sie aufs Radar. Geheimagenten-Mathe:

- 1 Breitengrad ≈ 110,6 km (Nord/Süd)
- 1 Längengrad ≈ 111,3 km × cos(Breitengrad) (Ost/West — die Erde ist rund!)

---

## 🛒 Einkaufsliste

**Empfohlen: das „Cheap Yellow Display" (CYD)** — ESP32 und Display fertig
auf einer Platine, nichts zu löten:

| Teil | Bezeichnung | Preis ca. |
|---|---|---|
| ESP32 + 2,8"-Touch-Display | **ESP32-2432S028R** („Cheap Yellow Display") | 12–15 € |
| USB-Kabel | Micro-USB, Datenkabel (kein reines Ladekabel!) | 3 € |

**Alternative: ESP32-Board + separates Display** (mit Verkabelung):

| Teil | Bezeichnung | Preis ca. |
|---|---|---|
| ESP32 DevKit V1 | 30-Pin-Board | 6–8 € |
| Display | 2,8" TFT **ILI9341**, 320×240, SPI | 8–10 € |
| Steckbrett + Kabel | Breadboard, Jumper-Kabel m/w | 5 € |

### Verkabelung (nur bei der Alternative nötig)

| ILI9341-Display | ESP32 DevKit |
|---|---|
| VCC | 3V3 |
| GND | GND |
| CS | GPIO 15 |
| RESET | GPIO 4 |
| DC | GPIO 2 |
| SDI (MOSI) | GPIO 23 |
| SCK | GPIO 18 |
| LED | 3V3 |
| SDO (MISO) | GPIO 19 |

---

## 🔧 Schritt-für-Schritt-Anleitung

### 1. Arduino IDE vorbereiten

1. [Arduino IDE](https://www.arduino.cc/en/software) installieren (Version 2.x).
2. **ESP32-Boards** hinzufügen: *Datei → Einstellungen → Zusätzliche Boardverwalter-URLs*:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
   Dann *Werkzeuge → Board → Boardverwalter* → „**esp32**" (von Espressif) installieren.
3. **Bibliotheken** installieren (*Werkzeuge → Bibliotheken verwalten*):
   - `TFT_eSPI` (von Bodmer)
   - `ArduinoJson` (von Benoît Blanchon, Version 7)

### 2. Display konfigurieren

Die Bibliothek TFT_eSPI muss wissen, wie dein Display angeschlossen ist:

- **CYD-Board:** Kopiere [`hardware/User_Setup_CYD.h`](hardware/User_Setup_CYD.h)
  in den Bibliotheks-Ordner `Arduino/libraries/TFT_eSPI/` und benenne sie dort
  in `User_Setup.h` um (die alte Datei vorher sichern). Genaue Anleitung steht
  oben in der Datei selbst.
- **DevKit + ILI9341:** Öffne `Arduino/libraries/TFT_eSPI/User_Setup.h` und
  aktiviere `#define ILI9341_DRIVER` sowie die Pins aus der Tabelle oben
  (`TFT_CS 15`, `TFT_DC 2`, `TFT_RST 4`, `TFT_MOSI 23`, `TFT_SCLK 18`, `TFT_MISO 19`).

### 3. Projekt einstellen

Öffne `flugzeugradar/flugzeugradar.ino` in der Arduino IDE und trage in der
Datei **`config.h`** ein:

- dein **WLAN** (Name + Passwort — Achtung: ESP32 kann nur 2,4 GHz!)
- deinen **Standort** (Google Maps → Rechtsklick → Koordinaten kopieren)
- den **Radar-Radius** (Standard: 40 NM ≈ 74 km)

### 4. Hochladen

1. ESP32 per USB anschließen.
2. *Werkzeuge → Board*: „**ESP32 Dev Module**" · *Werkzeuge → Port*: den neuen COM-Port wählen.
3. Auf **Hochladen** (→) klicken. Falls „Connecting…" hängen bleibt: die
   **BOOT-Taste** am ESP32 gedrückt halten, bis der Upload startet.
4. Fertig! Nach dem Start verbindet sich das Radar mit dem WLAN und zeigt
   nach wenigen Sekunden die ersten Flugzeuge. 🛩️

---

## 🖥️ Ohne Hardware testen: der Simulator

Im Ordner [`simulator/`](simulator/) liegt eine Webseite, die **dasselbe Radar
im Browser** zeigt — mit denselben Live-Daten und derselben Mathematik wie der
ESP32. Einfach `simulator/index.html` doppelklicken, Koordinaten eintragen
(oder „📍 Mein Standort") und „▶ Radar starten".

Kein Internet? Häkchen bei **Demo-Modus** setzen — dann fliegen erfundene
Flugzeuge über den Schirm.

---

## 🎨 Was die Anzeige bedeutet

| Anzeige | Bedeutung |
|---|---|
| 🟠 Orange Dreiecke | Flugzeug unter 10.000 ft (~3 km) — startet oder landet |
| 🟡 Gelbe Dreiecke | 10.000–25.000 ft — steigt oder sinkt |
| 🟢 Grüne Dreiecke | über 25.000 ft — Reiseflughöhe |
| Dreiecksspitze | zeigt die Flugrichtung |
| 4 Ringe | Entfernung: je ¼ des Radius (bei 40 NM also alle ~18,5 km) |
| KONTAKT | das nächste Flugzeug mit Entfernung, Höhe (ft) und Tempo (kt) |

---

## 🆘 Fehlersuche

| Problem | Lösung |
|---|---|
| Display bleibt weiß/schwarz | `User_Setup.h` falsch → Schritt 2 wiederholen, IDE neu starten |
| Farben sehen falsch aus | In `User_Setup_CYD.h`: `TFT_BGR` ↔ `TFT_RGB` tauschen |
| „KEIN WLAN" | Name/Passwort in `config.h` prüfen; 2,4-GHz-WLAN nötig |
| „SERVER?" | Internet prüfen; Schul-WLANs blockieren manchmal — Handy-Hotspot testen |
| Keine Flugzeuge (ZIELE: 0) | Radius vergrößern (z. B. 80 NM); nachts fliegt weniger |
| Upload schlägt fehl | BOOT-Taste gedrückt halten; anderes USB-Kabel (Datenkabel!) testen |

Der **Serielle Monitor** (Werkzeuge → Serieller Monitor, 115200 Baud) zeigt
dir genau, was der ESP32 gerade macht — perfekt zum Debuggen.

---

## 🚀 Erweiterungsideen für echte Geheimagenten

- **Alarm-Buzzer:** Piepton, wenn ein Flugzeug näher als 5 km kommt
- **Touch:** Flugzeug antippen → Details anzeigen (das CYD hat Touchscreen!)
- **Filter:** nur Militärflugzeuge oder nur eine Airline anzeigen
- **Zoom-Tasten:** Radius per Knopfdruck ändern
- **Eigene Antenne:** mit einem DVB-T-Stick (~15 €) und `dump1090` die
  ADS-B-Signale selbst empfangen — dann ohne Internet!
