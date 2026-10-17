# Studio-Testliste – Stand 17.10.2026

Datei: `AIEmpire_Stand_2026-10-17.rbxlx (im Ordner ai-empire-roblox)`

Die Logik, das Geld, das Aufräumen und die Abstände der Autos und Flugzeuge haben wir schon ohne Studio getestet.
Hier steht nur, was **nur Roblox Studio oder ein echtes Gerät** zeigen kann. Das Wichtigste steht oben.

**So startest du:**
- Reise-Tests: **Test → Clients and Servers → 2 Spieler**, lokaler Server.
- Handy-Tests: **Device-Emulator „iPhone 14“ quer (844x390)**, dazu einmal ein Android-Tablet und wenn möglich auch dein echtes iPhone.
- Geld oder Gutscheine zum Testen gibt es im **Debug-Panel** (nur in Studio).

Jede Zeile sagt dir, **was du tun sollst (→ was passieren soll)**. Die Klammer am Ende zeigt, woher der Test kommt
(2b = Fahrer/Jet/Reisen, Menü = Anleitung + Menü, Shop = Robux-Shop).

## A. Zuerst testen (betrifft jeden Spieler)

1. Neuen Spielstand auf dem iPhone-Emulator starten: Intro → START, dann der Anleitung „First steps“ bis zur ersten KI folgen.
   → Jeder Schritt lässt sich antippen, Tippen geht durch die Abdunklung durch und der Ring sitzt genau auf dem richtigen Knopf. (Menü)
2. Mit dem Firmenwagen von der Firma zum City Airport fahren.
   → Du wirst am Bordstein **stehend** abgesetzt, nicht fallend, feststeckend oder weggeschleudert. Prüf das auch am Limo-Stand, am Helix-Turm und am Meridian Grand. (2b)
3. Handy: Das Reise-Banner benutzen (Go / Not this time / Cancel trip / Fly home now / Call car now).
   → Es ist am Anfang eingeklappt. Jeder Knopf ist mindestens 44 pt groß und reagiert schon beim ersten Tippen. (2b)
4. Menü → Shop in Studio öffnen und auf ein paar Sachen tippen.
   → Oben steht „OWNER PREVIEW · Studio only“ und alles zeigt „Not set up“. Es öffnet sich **nie** ein Roblox-Kauffenster. (Shop)
5. iPhone-Emulator (und echtes iPhone): Wo liegt der Sprung-Knopf rechts unten?
   → Die HUD-Spalte (Ziel-Karte, Geld) rückt links neben den Sprung-Knopf und wird nicht verdeckt. (Menü)
6. Handy: Die Assistentin ruft wegen einer Reise an.
   → Der Anruf erscheint über dem HUD. Annehmen und Ablehnen gehen per Tippen, und der Kalender zeigt die Reisepunkte. (2b)
7. Mittelklasse-Handy, beide Gründer gleichzeitig auf Reise (Autos, Limo, Jet, Shuttle, Passagiere, Hotelgäste im Bild).
   → Mindestens 30 FPS und weniger als 1,2 GB Speicher. (2b)
8. Developer Console → Server Jobs, mit 2 Gründern auf Reise.
   → ItineraryService, DriverService und JetService brauchen je weniger als 1 ms pro Heartbeat. Pro Spieler kommen weniger als 50 KB/s an. (2b)

## B. Wichtig

9. Jet: An der Treppe einsteigen und in Port Meridian landen, mit beiden Gründern gleichzeitig.
   → Beim Landen bekommt jeder einen eigenen Ankunftspunkt, und die beiden überlappen sich nicht. (2b)
10. Die Kollegen (Rep + Engineer) laufen auf der Reise mit.
    → Sie folgen durch Türen und Treppen, schweben und versinken nicht und laufen nicht durch Wände. An Gate A1 blenden sie aus. (2b)
11. Firmenwagen und Limo durch die Stadt fahren lassen.
    → Sie streifen keine Bordsteine, keine Deko am Founder Square, keine Stadtautos und keine Fußgänger. (2b)
12. Handy: Das Fahrt-Panel benutzen (Get in / Let me out / View).
    → Es verdeckt die Firmenkarte im HUD nicht, und das Reise-Banner rutscht darunter. (2b)
13. Handy: Mit dem eigenen Jet fliegen.
    → Fensteroval, Fluginfo unten und Handy-Knopf sind alle zu sehen und liegen nicht übereinander. (2b)
14. Handy-Chat mit einem eigenen veröffentlichten Modell.
    → In unter 5 s kommt eine echte Antwort im Stil des Modells. „Demo reply (offline)“ erscheint nur, wenn die API aus ist. (2b)
15. Mit beiden Spielern etwa 20 Chat-Nachrichten schnell hintereinander senden.
    → Die Antworten werden langsamer oder zeigen den ehrlichen Offline-Text. Im Server-Log steht kein Fehler. (2b)
16. Im ersten Anleitungs-Schritt auf den Leuchtstrahl zum Computer achten.
    → Er ist gut zu sehen. (Bekannt: Nach einem „Reset“ fehlt er noch. Das wird im Reparaturpaket behoben, Fehler R10.) (Menü)
17. Auf eine Meldung (Toast) tippen, die über einem Knopf liegt.
    → Der Knopf darunter reagiert trotzdem, denn die Meldung schluckt keine Taps. (Menü)

## C. Feinschliff

18. Mitfahren im Auto, auf dem Rücksitz („View“) und in der Limo.
    → Die Kamera läuft weich und ruckelt nicht. Nach der Fahrt hast du wieder die normale Kamera. (2b)
19. Im Jet am Fensterplatz sitzen und im Shuttle „Window seat“ nehmen.
    → Die Kamera geht nicht durch die Wand des Flugzeugs, und Meldungen und Handy bleiben sichtbar. (2b)
20. Beide Gründer gehen zum Meeting im Helix-Turm.
    → Das Kundenteam sitzt auf den richtigen Stühlen (zwei Sitzgruppen), und die Kamera sieht es. (2b)
21. Debug-Panel → „Shop: Headhunter voucher“, dann Shop → YOUR ITEMS → REDEEM. Im offenen Fenster B und L1/R1 (Gamepad) und Enter (Tastatur) drücken.
    → Das Fenster bleibt vorne. B bricht ab, L1/R1 tun nichts, Enter führt die Aktion aus. (Shop/Menü)
22. Mit dem Gamepad die Anleitung spielen und dabei laufen.
    → Du kannst laufen. L1 öffnet das Menü (im ersten Schritt gleich das Lab), danach drückt (A) die Anleitungs-Aktion. Ohne L1 springt (A) nur. Kein HUD-Knopf wird von selbst ausgewählt. (Menü)
23. Mit dem Gamepad durch das Menü gehen und einen gesperrten Bereich öffnen.
    → Die Auswahl springt auf die neue Seite. B schließt zuerst die gesperrte Karte und danach das Menü. (Menü)
24. Team → Settings → „Change colour & logo“ öffnen.
    → Die 6 Extra-Logos (✦ ⬢ ◆ ✚ ◐ ⌬) sind als Zeichen zu sehen, nicht als leere Kästchen. Sie haben ein Schloss und keinen Kauf-Knopf. (Shop, T24)
25. Debug-Panel → „Shop: VIP pass“ und „Shop: Limo pass“.
    → Über deiner Figur erscheint ein goldenes VIP-Schild, im Menü ein VIP-Abzeichen und in der Flotte eine Limousine. (Shop)
26. Nur falls du ein ExecutiveLimo-Modell unter ReplicatedStorage/Assets/Vehicles importiert hast:
    → Es sieht richtig aus, die Türen gehen zur Bordsteinseite auf, ab 150 Studs ist der Innenraum weg und nichts ruckelt. (2b)

## D. Erst später möglich

27. Erst wenn echte IDs eingetragen und das Spiel veröffentlicht ist: Ein Produkt auf „Unlisted“ (zum Beispiel Eureka) über unseren Knopf kaufen.
    → Der Kauf klappt. Wenn nicht, das Produkt auf „Listed“ stellen. (Shop, T22)
28. Feuerwerk und Team-Party auf dem Handy ansehen. Das geht erst mit echter ID oder einem neuen Debug-Knopf.
    → Nichts ruckelt (4 Abschussstellen, alle 1,1 s). (Shop, T23)
29. Server Glow mit „Reduced Motion“ testen (braucht den Pass, im Debug-Panel noch kein Knopf).
    → Die Racks leuchten dann ruhig statt in Wellen. (Shop, T24)
