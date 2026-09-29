# Grenzen

Was nicht geht, was nicht belegt ist und was nie geprüft wurde. Stand 29.09.2026.

## Die trainierte Policy

- **Nicht freigegeben.** `v9_lokal_1` ist nach den vorab festgelegten Kriterien durchgefallen (`training/AUSWERTUNG_V9.md`): Das
  Bedürfnisdefizit der Fokusperson sinkt in 5 von 5 Gruppen, aber nur 16 von 26 Nebenprüfungen halten. Sie nimmt viel öfter frei, kündigt,
  wechselt und gründet kaum, bekommt keine Kinder, erreicht weniger Ziele, und „gesellig“ wirkt umgekehrt (Regeln r = +0,32, Policy −0,11).
  Für alle eingeschaltet wächst die Stadt deutlich langsamer: Eine neue Stadt hat an Tag 90 je Stadt 45–53 statt 107–128 Einwohner
  (4 Seeds, zusammen 203 statt 471; `berichte/v9_lokal_1/abschluss_stadt.txt`). Das Spiel zeigt das seit dem 29.09.2026 im Fenster
  („Auswertung laut Datei“, aus dem Feld `hinweis` der Policy).
- Ein Trainingslauf mit einem Seed. Die Kriterien verlangen 3 Läufe mit verschiedenen Seeds; mehr als „vorläufig“ ging so nie.
- Nur Lehrplanstufe 1 (Szenario `stabil`: Stadt nach 150–230 Tagen, 30 Tage, übrige Stadt nach Regeln). Stufen 2–6 (Löhne und Mieten,
  Verpflichtungen, Störungen, Gründungsrisiko, größere Stadt mit anderen Policies) gibt es nicht.
- **Belohnung v2 besteht das Audit auf Version 9 nicht:** 5 von 8 Prüfungen (`berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt`;
  vorher 6 von 8 ohne den Trick Dauer-Freinehmen, `berichte/v9_uebertrag/ki_fallen.txt`). Treffen ohne Gegenüber lohnen sich zu oft,
  „jeden Abend treffen“ schlägt die Regeln in `ohne_arbeit`, und „jeden Morgen frei, sonst Regeln“ schlägt sie in `alle` (17,23 gegen
  17,00), obwohl der Geldbedarf von 20,0 auf 34,1 steigt: In 30 Tagen je Episode zählt der Lohnverlust kaum. Das passt zum Muster der
  Policy (1.310 gegen 342 Mal freinehmen im Abschluss). Der Lauf ist trotzdem mit v2 trainiert (so beauftragt); eine auf Version 9
  kalibrierte v3, die auch entgangenen Lohn bzw. die Rücklage am Episodenende zählt, fehlt.
- Warum die Policy so handelt, ist gemessen, aber nicht getrennt untersucht (etwa ob die Belohnung Gründen, Kinder und Stadtwirkung
  schlicht nicht abbildet).
- Die Maske (`erlaubteAktionen`) nutzt Wissen, das die Person nicht hat (Marktdaten, Zufriedenheit des Partners, Weltmarkt bei
  Gründungen). Die Policy sieht davon nur, welche Aktionen erlaubt sind.
- Zeitpunkt: Im Spiel führt die Policy ihre Wahl sofort aus, in der Trainingsumgebung am Ende der Stunde. Wie stark das die Übertragung
  vom Training ins Spiel verändert, ist nicht gemessen.
- Eine Policy zum Standard machen (einbetten oder vorauswählen) geht noch nicht; es gab bisher auch keine, die bestanden hat. Das Werkzeug
  aus dem Übertrag (`ki_patch.mjs`) arbeitete nur auf 09083f5 und liegt nicht hier.
- Nicht gemessen: Erholung nach Jobverlust, Gedächtnis und Pläne (gibt es noch nicht), Policy zusammen mit echtem Ollama, Bildrate mit
  eingeschalteter Policy.

## Training und Werkzeuge

- **Nur auf Linux (x86_64, 4 Kerne, keine GPU) ausgeführt.** Die Anleitung für den Mac folgt aus den Versionen, ist aber auf keinem Mac
  geprüft. torch 2.14.0 gibt es für den Mac nur für Apple Silicon ab macOS 14 (PyPI); für Intel-Macs gibt es dieses Paket nicht.
- Der Langlauf (Profil `langlauf`, 3 Mio. Schritte, bei gemessen gut 100 Schritten/s rund 8 h) ist nie zu Ende gelaufen; geprüft ist nur,
  dass er startet und nach einem kurzen Zeitlimit sauber aufhört.
- Stoppen: Strg+C oder SIGTERM beenden einen Lauf geordnet (seit 29.09.2026, `docs/EXPERIMENTE.md` Abschnitt 3). Nach einem harten
  Abbruch (zweites Strg+C, `kill -9`) steht das Manifest auf „läuft“ mit dem Stand des letzten Rollouts; der laufende Rollout ist verloren, und fällt der Abbruch in eine
  Validierung, auch deren Ergebnis.
  Geprüft nur mit dem Smoke-Profil, nicht mit einem langen Lauf. Unter Windows nicht geprüft (dort gibt es kein SIGTERM wie hier).
- Die Code-Hashes im Manifest von `v9_lokal_1` gelten für den Trainingscode vor den Korrekturen vom 29.09.2026 (Episode schon im `reset`
  vorbei; Stoppen und Manifest); das Rechnen hat sich nicht geändert (Smoke-Lauf mit denselben Validierungen und derselben L2-Änderung).
- `simtest --kipolicy` und `tools/simtest_alle.sh` vergleichen „Policy aus“ mit 09083f5 (Version 9 ohne KI-Teil). Sobald sich der sim-Block
  gewollt ändert, `ALT=<neuer Vergleichsstand>` setzen, sonst wird der Vergleich rot.
- Beide Skripte und `tests/alle.sh` brauchen die Git-Geschichte des Repos (Versionen 2–9 per `git show`), keine flache Kopie.
- In `ki/policy_v9_lokal_1.json` zeigt `herkunft.manifest` auf den Laufordner, der nicht im Repo liegt (das Manifest steht in
  `berichte/v9_lokal_1/`). Der Checkpoint selbst ist nicht im Repo; ohne ihn lässt sich die Parität dieser Policy nicht neu rechnen,
  nur nachlesen (`berichte/v9_lokal_1/paritaet.txt`).

## Spiel

- `Sim.KI.policyPruefen` prüft „endliche Zahl“ vor dem Runden auf float32: Ein Gewicht oder Bias über dem float32-Bereich (z. B. `1e39`)
  wird angenommen und im Netz zu ±Unendlich (nachgeprüft: angenommen, Logits danach endlich, weil `tanh` sättigt). Harmlos für die
  Sicherheit (die Maske gilt, NaN führt zum Rückfall), aber eine solche Datei gilt als gültig. Nicht behoben: Die Prüfung liegt im
  sim-Block, eine Änderung dort änderte den Sim-Hash `3b1a95e0e5ae9ea5`, auf den `v9_lokal_1` trainiert und ausgewertet ist.
  `simtest --kipolicy` nutzt genau diese Lücke (Gewichte `1e308`), um den Rückfall zur Laufzeit zu prüfen.
- Nach einem Rückfall beim Laden (Policy fehlt oder passt nicht) speichert das Spiel „Regeln“ als Wahl. Liegt die Policy später wieder in
  `ki/`, muss man sie im Fenster neu wählen; das Spiel versucht es nicht von selbst (so auch in `docs/START.md`).

- Start mit einer Policy im Spielstand wartet auf `ki/`: höchstens 8 s je Anfrage (Liste und bis zu 12 Dateien). Eine gemeinsame Frist für
  alles fehlt; bei einem hängenden Server kann der Start also lange dauern. Lokal dauert es Millisekunden.
- Als `file://` geöffnet gibt es keine Policy aus `ki/` (Browser erlauben das nicht) und kein Three.js; über einen Server öffnen.
- Nur in Chromium geprüft (Playwright 1.56.1, Chromium 141, SwiftShader). Firefox und Safari nicht.
- Hauptfiguren mit Ollama: nur gegen einen Nachbau getestet, nie gegen ein echtes Sprachmodell (README, „Bekannte Schwächen“).
- Aufholen in Stücken ist eine Näherung: 1 × 90 Tage ist nicht bitgleich zu 3 × 30 Tagen, wenn die Stücke mitten am Tag beginnen
  (gemessen auf Version 8, `berichte/etappe0/BESTAND.md`, Abschnitt 5; auf Version 9 nicht neu gemessen). Stündlich gerechnet und mit
  Speichern und Laden zwischen den Stücken war es bitgleich. Im Spiel ist die Näherung nicht gekennzeichnet.
- Nicht begonnen sind Etappe 2 (strukturierte Erinnerungen, Erfahrungen und Pläne der Bewohner), 4 (Hauptfiguren mit echten Modellen)
  und 5 (Stadtleben und Oberfläche, etwa „Warum diese Entscheidung?“ in der Personenkarte, KI-Werkstatt, Parks, Verkehr). Von Etappe 3 gibt
  es nur das Belohnungs-Audit und einen ausgewerteten Lauf. Stand je Etappe in `docs/FORTSCHRITT.md`.
