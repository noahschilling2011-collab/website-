# AI Empire – Prüfung vor dem Veröffentlichen (einfach erklärt)

**Kurz gesagt:** Dein Spiel ist bei den wichtigen Sachen sicher. Niemand kann sich Geld, Robux-Käufe oder Items ercheaten. Beim Speichern gibt es aber 4 Fehler, die du vor dem Veröffentlichen reparieren solltest. Sonst können Spieler manchmal Fortschritt verlieren. Die Reparatur dafür ist schon fertig geschrieben und getestet.

## Das ist sicher
- **Robux-Käufe:** Du bekommst die Sache erst, wenn sie sicher gespeichert ist. Nichts wird doppelt gegeben und nichts geht verloren.
- **Geld:** Alle Preise kommen vom Server. Ein Spieler kann keine Preise fälschen.
- **Server-Leitungen (Remotes):** Jede hat eine Bremse gegen Spam und prüft, was der Spieler schickt.
- **Fremde Firmen:** Niemand kommt an deine Modelle, Mitarbeiter, Türen oder deinen Aufzug.
- **Namen** werden gefiltert.
- **Admin über den Benutzernamen** ist so gewollt und nicht ausnutzbar.
- **Alte Spielstände** laden weiter. Der Spielstand ist klein genug (3,6 % vom Limit).

## Muss vor dem Veröffentlichen repariert werden (Speichern)
1. **Server geht aus, bevor fertig gespeichert ist (DS-1, wichtigster Fehler):** Wenn der letzte Spieler geht, schaltet Roblox den Server ab. Das Spiel wartet aber nicht auf das letzte Speichern. Dann ist bis zu etwa 1,5 Minuten Fortschritt weg. Wer schnell wieder reinkommt, wird bis zu 3 Minuten rausgeworfen.
2. **Ein alter Autosave überschreibt den neuen Stand (DS-3):** Das passiert nur, wenn die Roblox-Speicher gerade Probleme haben.
3. **Gleichen Server neu betreten lädt einen alten Stand (DS-2):** Zum Beispiel, wenn man einem Freund hinterherjoint. Der neue Fortschritt wird dann überschrieben.
4. **Ein kleiner Fehler beim Serverstart schaltet das Speichern ganz aus (DS-4):** Alle auf diesem Server werden rausgeworfen.

Die Reparatur für alle 4 steht in `agents/robloxreview/fix.diff`. Sie ändert nichts am Spielstand-Format.

## Sehr empfohlen (Handy-Leistung)
- **Mitarbeiter auf allen Stockwerken (P1):** Sie werden 30-mal pro Sekunde bewegt, auch wenn man sie gar nicht sieht. In großen Büros kann das Handy ruckeln oder warm werden. Eine kleine Änderung spart 79 % dieser Arbeit.

## Schön zu haben (nächstes Update)
- **Großes Büro (P4):** Es wird in einem Rutsch gebaut. Beim Beitreten oder Upgraden ruckelt es kurz für alle.
- **Ladebereich (P2):** Er ist sehr groß. Auf schwachen Handys kann man nach dem Spawnen kurz feststecken.
- **NPCs (P3):** Sie „denken" weiter, obwohl sie nur stehen. Das kostet Server-Leistung.
- **Teleport-Cheat (F2):** Ein Cheater kann zu Meetings im Ausland teleportieren und spart so das $700-Ticket. Das schadet nur der Fairness, nicht anderen Spielern.
- **Auto parken (F3):** Ein Cheater kann sein Auto in ein fremdes Büro parken. Stehlen kann er dort nichts.
- **Rezeption blockieren (F5):** Ein Besucher kann deine Rezeptionistin dauernd besetzen.
- **Gästekarten (F4):** Jemand kann dir immer wieder Gästekarten schicken (nervig, aber harmlos).
- **Kleinkram (P5, P6, P7):** Bildschirme, Türen und Suchen im Büro kosten etwas Server-Leistung.

## Das kannst nur du in Roblox Studio oder auf dem Handy testen
- **Speichern:** Allein spielen, Geld verdienen, rausgehen und sofort wieder rein. Ist das Geld noch da? Teste vor und nach der Reparatur.
- **Ruckeln:** Auf deinem Handy im großen Büro (Stufe 3/4) mit dem MicroProfiler prüfen.
- **Ladebereich:** Wie lange man nach dem Beitreten feststeckt, wenn der Bereich kleiner eingestellt ist.
- **Sitzen:** Ob sitzende Mitarbeiter mit der NPC-Änderung noch richtig sitzen.
- **Gamepässe:** Bevor du echte Gamepass-IDs einträgst, noch einmal prüfen lassen.

## Nachtrag: Handy-Bedienung (dieser Teil fehlte im ersten Bericht)
- **Alte Computer-Apps waren auf dem Handy winzig (UI-1, wichtig):** Schrift 5–9 pt, Knöpfe zu klein. Das neue Menü ersetzt das zum großen Teil; die alten Tabs im neuen Menü sind jetzt 11,2 pt. Wird nach dem Shop noch einmal am aktuellen Stand geprüft.
- **CCTV nach Flug/Shuttle (UI-2):** Die Kamera kann danach hängen bleiben.
- **Campus-Kameras hinter dem Computer-Fenster (UI-5):** Man sieht die Kameras nicht richtig.
- **Kleinkram:** GPS-Liste beim Fahren läuft unten aus dem Bildschirm (City Airport nicht antippbar), Bordkarte verdeckt den HUD, manche Panels sitzen unter der Roblox-Leiste.
