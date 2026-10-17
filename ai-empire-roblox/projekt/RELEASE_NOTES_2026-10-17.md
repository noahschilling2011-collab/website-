# AI Empire – neuer Stand vom 17.10.2026

**Datei:** `AIEmpire_Stand_2026-10-17.rbxlx (im Ordner ai-empire-roblox)`
(4,4 MB = 4.434.873 Bytes, 167 Skripte). Öffnen wie immer: Datei in Roblox Studio aufmachen.

**Vorher:** `AIEmpire_Stand_2026-10-11_ki-studio.rbxlx` (das war der Stand mit dem neuen KI-Studio).

> **Wichtig:** Diese Datei ist **zum Testen in Studio** gedacht. Bitte **noch nicht öffentlich veröffentlichen**.
> Die Reparaturen beim Speichern aus der Profi-Prüfung fehlen noch (siehe unten „Was noch NICHT drin ist“).
> Ohne sie können Spieler manchmal Fortschritt verlieren (zum Beispiel bis zu etwa 1,5 Minuten, wenn der Server ausgeht)
> und danach bis zu 3 Minuten nicht wieder ins Spiel kommen.

---

## Was ist neu?

### 1. Fahrer und VIP-Limousine
- Ab dem Founder Headquarters (Büro-Stufe 2) hast du einen **eigenen Firmenfahrer**, ab dem Innovation Campus (Stufe 4) zwei. Es sind genau die Fahrer, die du bezahlst.
- Über das Handy rufst du ein Auto. Es holt dich am nächsten Abholpunkt ab (deine Firma, der Flughafen, Gebäude in der
  Stadt) und fährt dich hin. Du siehst, wie lange es dauert. Sind alle Autos unterwegs, sagt das Spiel ehrlich, wann eins frei wird.
- **„Get in“, „Let me out“ und „View“** (Rücksitz-Kamera) gibt es während der Fahrt.
- Deine Mitarbeiter fahren sichtbar mit Firmenautos zu Kunden.
- In **Port Meridian** (im Ausland) gibt es einen **VIP-Limousinen-Service** am Limo-Stand. Er bringt dich zum Kunden und zum Hotel.

### 2. Hotelgäste und Firmen-Jet
- Im **Gästehaus** deiner Firma (ab dem Startup Campus, Stufe 3) wohnen jetzt **Hotelgäste** (bis zu 12). Sie kommen nachmittags mit Koffer
  an, checken ein und sitzen abends in der Lobby. Im **Flughafen-Terminal** laufen Passagiere herum.
- Wenn deine Firma den **Firmen-Jet** gekauft hat (ab dem Innovation Campus, 900.000 $), steht er in Hangar 1 am City Airport,
  mit zwei Piloten. Du kannst damit nach Port Meridian und zurück fliegen.
  Mitarbeiter auf Geschäftsreise fliegen mit, wenn Platz ist (bis zu 3 Reisende).

### 3. Geschäftsreisen mit der Assistentin
- Wenn ein wichtiger Kunde besucht wird, **ruft dich deine Assistentin an** und sagt dir den echten Plan:
  welcher Kunde, welche Stadt, welcher Flug (Shuttle oder dein Jet), welches Hotel und welche Kollegen mitkommen.
- **„Go“** heißt: Du reist mit. Dann fährt dich dein Fahrer mit den Kollegen zum Flughafen, ihr fliegt nach Port Meridian,
  die Limousine bringt euch zum Kunden, du drückst „Start meeting“, dann geht es ins Hotel und später nach Hause.
- **„Not this time“** heißt: Die Kollegen reisen allein. Das Geld ist in beiden Fällen gleich. Mitreisen ist ein Erlebnis
  und keine Pflicht. Es gibt auch **„Fly home now“** (früher heim) und „Cancel trip“.
- Im Handy kannst du „Join business trips automatically“ einschalten. Dann startet die Reise nach 10 Sekunden von selbst.
- Das Mitreisen kostet dich nichts extra. Die Reisekosten zahlt die Firma so wie vorher.

### 4. Anleitung für Anfänger und neues Menü
- Neue Spieler bekommen die Anleitung **„First steps“**. Sie zeigt Schritt für Schritt, wie man die **erste KI
  herausbringt**: Daten kaufen, trainieren, vorstellen, starten. Ein Ring zeigt auf den richtigen Knopf.
  Man kann die Anleitung **überspringen**. Sie gibt kein Extra-Geld, sie zeigt nur auf die normalen Belohnungen der Ziele.
- Der Firmenname geht jetzt auf **einem Bildschirm** (mit Namensideen und Würfel).
- Das **neue Menü** hat links eine Leiste: **Home, Lab, Market, Clients, Team, Shop**. Neue Bereiche schalten sich nach
  und nach frei, damit es am Anfang nicht zu viel ist. Home zeigt, was heute wichtig ist.
- Auf dem Handy ist die Anzeige (HUD) kompakter, die Schrift ist größer und die Knöpfe lassen sich leichter antippen.
  Mit „Collect“ holst du alle fertigen Belohnungen auf einmal ab.

### 5. Robux-Shop
- Im Menü gibt es den **Shop** mit 5 Reitern: Home, Speed-ups, Boosts, Style, Extras.
- **Forschung überspringen:** Mit **Eureka** ist eine Forschung oder eine Lab-Stufe sofort fertig, auch direkt im Model
  Studio beim 7B-Modell („SKIP · EUREKA“). Den $-Preis zahlst du trotzdem. Jeder Knopf zeigt, wie viel Zeit du sparst.
- **Last Epoch** beendet ein laufendes KI-Training sofort, mit denselben Chancen wie beim Warten.
- **Boosts:** Keynote Boost (+20 % auf App- und API-Einnahmen für 15 Minuten) und Overclock (Training 1,5× so schnell), je höchstens 4 pro Tag.
- **Kleine Geld-Pakete:** Seed round, Series A und Series B geben 10 %, 20 % oder 30 % vom Preis des **nächsten** Büros.
  Jede Größe gibt es nur **einmal pro Büro**. Kauft jemand eine Größe doppelt, bekommt er das Geld erst im nächsten Büro.
  So kann man das Spiel nicht in 6 Minuten durchkaufen (das war deine Entscheidung).
- Dazu kommen Sachen nur zum Aussehen (Identity Kit, Server Glow, Stage Lights, Feuerwerk, Party), Pässe (VIP Founder,
  Executive Limo, Founder Suite, Investor Relations; Investor Relations gibt +10 % auf App- und API-Einnahmen), ein Headhunter und Trinkgeld. Es gibt **keine Zufalls-Käufe** (keine Lootboxen).
- Vor jeder Benutzung fragt das Spiel nach. Es benutzt nie etwas von selbst.

> **Alle Produkt- und Pass-IDs stehen noch auf 0.** Deshalb kann **noch niemand etwas kaufen**. Im veröffentlichten
> Spiel steht „Shop coming soon“. In Studio siehst du alles mit „OWNER PREVIEW“ und „Not set up“, und ein Druck kauft nie etwas.
> Wie du die Produkte anlegst und die IDs einträgst, steht in `ReplicatedStorage/Shared/Config/ShopConfig` (oben im
> Kommentar) und in `projekt/design/OWNER_GUIDE_DE.md (Shop-Anleitung)`.
> Achtung: In dieser Anleitung steht noch, dass die Geld-Pakete „Listed“ sind. Richtig ist jetzt **„Unlisted“**
> (so steht es in ShopConfig). Eureka, Last Epoch, Keynote und Overclock sind auch Unlisted.

---

## Die Tests (alle ohne Studio, mit einem nachgebauten Roblox)

Getestet wurde genau der eingefrorene Stand, aus dem die Datei gebaut ist. In der Zeit hat sich am Stand nichts geändert.

| Test | Ergebnis |
|---|---|
| Alle Test-Gruppen (run_all) | **145 von 145 grün**, **239.287 Prüfungen bestanden, 0 Fehler** (27 Minuten) |
| Bürogebäude, alle 5 Stufen (Garage bis Global HQ) | alles baut ohne Fehler; jeder Arbeitsplatz, jede Tür, jeder Aufzug und jeder Punkt zum Interagieren ist erreichbar |
| Geschäftsreise mit 2 Spielern auf einem Server (Ada mit Shuttle, Ben mit eigenem Jet, einmal „Not this time“) | **113 bestanden, 0 Fehler** |
| Gegenprobe: 5 absichtlich eingebaute Fehler | **5 von 5 erkannt** (der Test merkt also wirklich, wenn etwas kaputt ist) |
| Wirtschafts-Simulator, Spieler ohne Käufe | Büro-Stufen nach **7,5 / 34,7 / 83,0 / 168,8 Minuten** (Founder HQ / Startup Campus / Innovation Campus / Global HQ), **genau gleich wie bei der letzten Prüfung** und genau gleich wie ohne Shop |
| Simulator, andere Zufallszahlen (Seed 7 und Seed 23) | 10,9 / 32,0 / 96,1 / 166,6 und 10,4 / 31,4 / 77,7 / 165,3 Minuten, auch genau gleich wie bei der letzten Prüfung |
| Simulator, jemand kauft sehr viel (jedes Geld-Paket einmal pro Büro, 16 Eurekas, 61 Last Epochs, 4 Keynote, 4 Overclock, Investor Relations) | Global HQ nach 104,7 statt 168,8 Minuten, also immer noch über 1,5 Stunden |
| Datei packen und wieder auslesen | **ROUNDTRIP OK**: Alle 167 Skripte in der Datei sind genau gleich wie im Quellcode |

Was das heißt: Wer nichts kauft, spielt genau so schnell wie ohne Shop. Nur wenn auf demselben Server jemand sehr viel kauft,
braucht er etwas länger: laut dem Simulator der Shop-Planung (SHOP_SPEC Abschnitt 10, für diesen Stand nicht neu gerechnet)
etwa 5 % bis zum Global HQ (182 statt 174 Minuten). Das ist weniger, als ein starker Gratis-Spieler auf dem Server ausmacht (7–9 %).

---

## Was noch NICHT drin ist

1. **Reparaturen beim Speichern aus der Profi-Prüfung (4 Fehler, DS-1 bis DS-4).** Zum Beispiel: Der Server geht aus,
   bevor das letzte Speichern fertig ist (bis zu etwa 1,5 Minuten Fortschritt weg). Oder ein alter Speicherstand
   überschreibt einen neueren, wenn die Roblox-Speicher gerade Probleme haben. Oder ein kleiner Fehler beim Serverstart
   schaltet das Speichern auf diesem Server ganz aus.
   Aus der zweiten Prüfung kommt dazu: Ein Cheater kann eine abgelehnte Reise trotzdem starten und mit Spam unnötige Daten
   an alle Spieler schicken (harmlos fürs Geld, soll aber vor dem Veröffentlichen repariert werden, R3).
   Kleinere Sachen: Der Tutorial-Strahl fehlt nach einem Reset (R10), der Deko-Jet im Hangar taucht wieder auf (R7),
   wer das Tutorial immer wieder neu startet, erzeugt falsche Einträge in der Roblox-Statistik (R6), und das Spiel merkt
   sich jedes gesehene Hotel für immer (etwas mehr Speicher nach Stunden, R8).
   Ein anderes Team baut das gerade (Reparaturpaket). **Deshalb noch nicht veröffentlichen.**
2. **Der Umbau des Hotels Meridian Grand** in Port Meridian. Das Hotel gibt es schon (dort checkt ihr auf der Reise ein),
   aber den großen Umbau gibt es bisher nur als Plan.
3. **Neue Flughäfen.** Sie sind auch nur geplant.
4. **Die Logik-Änderungen (Runde 2).** Dazu gehören zum Beispiel: Das Spiel geht nach dem Global HQ weiter, es gibt ein
   Büro in Port Meridian, die Automatik ist fairer, wenn man nichts tut, es gibt eine GPU-Warnung und kein Glücksspiel
   beim Training. Das ist geplant (die Planung wird gerade noch gegengeprüft, die Zusammenfassung kommt danach nach `zwischenstand_in_arbeit/design/logic2/`), aber noch **nicht** im Spiel.
5. **Shop Phase 3:** AI Gallery, Team Hoodies und Robo Buddy sind noch nicht fertig. Sie werden nicht verkauft.

## Was du in Studio testen solltest
Die Liste mit 29 Punkten (das Wichtigste oben) steht in
`projekt/STUDIO_TESTS_2026-10-17.md`.
Bilder vom Shop: `shop_bilder/`.
