# Grenzen

Was nicht geht, was nicht belegt ist und was nie geprüft wurde. Stand 01.10.2026 (Version 10, nach Etappe 2).

## Gedächtnis, Erfahrung und Pläne (Etappe 2)

Belege: `berichte/etappe2/` (Übersicht `berichte/etappe2/LIESMICH.md`); Dateinamen ohne Pfad und `mess/…` meinen in diesem Abschnitt
diesen Ordner. Gemessen ist, was die Bausteine in der Stadt bewirken; was davon glaubwürdig ist, ist eine Frage an Noah, keine Messung.

- **Die Ergebnisse je Folge sind Annahmen.** Welche Folge als gut oder schlecht zählt und wie viel (Gründen +12 / −30, Kündigen +8 / −20,
  Wechseln +8 / −24, Zusammenziehen +10 / −20 Punkte), die Fristen (180 / 30 / 30 / 60 Tage), die Sicherheit (0,5 / 0,75 / 1), die Bedeutung je
  Erinnerung (`M_BED`), die Rücklage (Gründungskosten + 20 Tageskosten), die Bremse (30) und das Sparen beim Kündigen (15), die Wartezeit nach
  einer Pleite (120 × (0,5 + Sparsamkeit) Tage), das Verblassen (`R.ERF_HALB = 180`) und die Stärke (`R.GED_STAERKE = 1,5`): Das sind
  Annahmen der Stadt (die Werte stehen in `R` im sim-Block, Abschnitt „Etappe 2“; Herkunft: Entwurf C und Noahs Entscheidungen,
  `berichte/etappe2/VERGLEICH.md` Abschnitt 3, `SCHRITT1.md` Abschnitt 1.2), nicht an echten Menschen gemessen. Die Personenkarte
  sagt das („Das sind Annahmen der Stadt, keine Messung an echten Menschen.“). Kalibriert ist nur die Stärke und das Verblassen, und zwar auf
  die Gates und die Wirkung in der Stadt (`KALIBRIERUNG.md`, `VERBLASSEN.md`).
- **Elternzeit wird gelernt (Noahs Entscheidung 3, gegen die Empfehlung „ausnehmen“).** Wer für die Elternzeit kündigt und innerhalb von 30
  Tagen wieder Arbeit sucht (Frist `R.ERF_FRIST`; jede Stellensuche in der Frist zählt, auch eine erfolglose), lernt das wie jede Kündigung als
  schlechte Erfahrung. Folge über die Seeds 1–20 × 730 Tage: 8.000 statt 39.231 Kündigungen für die Elternzeit (−80 %); von ihnen suchen 71,5 %
  binnen 1 Tag und 88,9 % binnen 30 Tagen wieder Arbeit (ohne Erfahrung 89,5 / 95,3 %); der Fleiß-Abstand dieser Kündiger −20,3 statt −26,3
  (`berichte/etappe2/mess/schritt5/folgen_aus_h180.txt`). Ob
  dadurch die Kita-Kosten steigen und die Kasse der Stadt sinkt (an Tag 730 −17,1 % gegen `R.GED = 0`,
  `berichte/etappe2/mess/schritt4/gates_1_80/wirtschaft_gegen_ged0.txt`), ist eine Vermutung; die Ursache ist nicht zerlegt
  (`berichte/etappe2/SCHRITT1.md` Abschnitt 3).
- **Wie stark, gemessen am Entwurf (Noahs Entscheidung 4: stärker als dessen 0,5–1 %).** Über 730 Tage ändern Erfahrung und Plan zusammen in
  den Seeds 1 / 2 / 3 1,332 / 0,886 / 0,654 % der Entscheidungen (Mittel 0,957 %), Entwurf C 0,58 / 0,53 / 1,03 % (Mittel 0,713 %): im
  Mittel etwa ein Drittel stärker, aber in den Seeds 2 und 3 noch im Bereich 0,5–1 %, in Seed 3 unter Entwurf C. Die Erfahrung allein ändert
  0,46–0,61 % (Entwurf C 0,34–0,81 %). Das folgt aus den Entscheidungen 9 (Stärke 1,5 statt 4: Stufe 4 änderte in derselben Messung vor dem
  Sim-Fix 2,623 %, Stufe 1,5 0,893 %, `KALIBRIERUNG.md` B.1) und 10 (das Verblassen senkt 1,088 % auf 0,957 %, `VERBLASSEN.md` B.3); Belege
  `VERGLEICH.md` 1.2, `mess/verblassen/schluss/probe8_auswertung.txt`. Ob das „stärker“ genug ist, entscheidet Noah.
- **Pläne entscheiden nur beim eigenen Laden mit.** In `entscheide` wirkt ein Plan an genau zwei Stellen: fehlt die Rücklage vor einer
  Gründung, zählt Gründen weniger (für jeden Gründer, für den die Rücklage gilt), und wer für den eigenen Laden spart (Planschritt „Rücklage
  ansparen“), kündigt ungern. Die Schritte der übrigen Ziele (besserer Job, Familie, Wohnung, Freunde, Ruhe; `PLAN_SCHRITTE`) zeigt nur die
  Personenkarte; dort entscheidet weiter der Zielbonus wie in Version 9 (Befund der Schlussprüfung Technik; `planSchritt` wird in
  `entscheide` nur beim Kündigen gelesen).
- **Gate T ist eng, weil es Wandzeit auf einem Rechner misst.** Dieselbe Basis 6c1741e brauchte für 365 Tage Seed 1 auf diesem Rechner je nach
  Tag 3.067 bis 5.618 ms (`berichte/etappe2/VERGLEICH.md` 1.1, `VERBLASSEN.md` B.3), die Grenze ist 5.000 ms. Nach Schritt 1 war T rot (5.858
  gegen 4.635,5 ms der Basis, +26,4 %; die Stadt wird mit der Rücklage größer, je Personentag gleich schnell; `SCHRITT1.md` 0.5). Grün wurde
  es durch die bitgleiche Optimierung (Noahs Entscheidung 7: 5.640,5 → 1.470 ms, `OPTIMIEREN.md` 0). Mit dem sim-Block des Endstands:
  Median 1.239 gegen 3.328 ms der Basis im Wechsel, Verhältnis 0,372 (`SCHRITT3.md` 9, `mess/schritt3c/gate_t/wechsel.txt`); nach den
  Korrekturen der Schlussprüfung (nur `warum` und ein Kommentar im sim-Block) 1.265 gegen 3.448 ms, Verhältnis 0,367 (12 Runden, `FIX.md` 3,
  `mess/fix/gate_t/wechsel.txt`). Wie viel Abstand
  ein anderer Rechner hat, ist nicht gemessen. Wer den sim-Block ändert, misst T allein und im Wechsel mit 6c1741e
  (`bash tools/gate_t_wechsel.sh 4 1`); in `simtest_alle` mit zwei Läufen gleichzeitig ist T nur ein Hinweis.
- **Die Grenze von `localStorage` ist nur in Chromium gemessen.** Chromium 141 (headless) nimmt höchstens 5.242.867 Zeichen
  (`VERGLEICH.md` 1.4). Die große Stadt (Umland 300.000, Seed 2, Tag 750) braucht mit dem Endstand 4.277.380 Zeichen und wird im Browser
  geschrieben und wieder gelesen (`mess/schritt4/frisch/browser/logs/p10speicher.log`; Node: `mess/schritt5/groesse_gross_endstand.jsonl`;
  mit dem Stand von Schritt 2 waren es 4.190.777, `SCHRITT2.md` 6–7). Firefox und Safari sind nicht gemessen; dort
  kann die Grenze anders liegen. Die eigene Warnschwelle des Spiels (4 MB) überschreitet die große Stadt, wie schon in Version 9 (4.174.643
  Zeichen, `mess/schritt2/groesse_gross.jsonl`).
- **Kalibriert auf einem Rechner und auf festen Seeds.** Stärke und Verblassen sind nach vorab festgelegten Regeln gewählt, auf den Seeds 1–80
  gemessen und einmal auf den Seeds 81–160 bestätigt, alles in einem Linux-Container mit 4 Kernen ohne GPU (`KALIBRIERUNG.md` Teil A und D,
  `VERBLASSEN.md` Teil A). Die Stärke hat Noah danach selbst gewählt: 1,5 statt der nach der Regel gewählten 4 (Entscheidung 9). Die Gates
  hängen nicht am Rechner, T schon. Gate 4 hält auf 1–80 (Endstand) und 81–160 (Stand der Phase „Verblassen“) je 80 von 80, mit dem Stand
  ohne Verblassen waren es auf 1–80 79 von 80 (`mess/schritt4/gates_1_80/auswertung.txt`, `VERBLASSEN.md` B.3–B.4): Einzelne Seeds kippen bei jeder Änderung in beide Richtungen.
- **Gate 7 wird oft nicht gewertet (Noahs Entscheidung 8).** Mit Erfahrung ziehen weniger Menschen weg; Gate 7 zählt nur mit mindestens 15
  Wegziehern bis Tag 365. Mit dem Endstand: Seeds 1–80 25 nicht gewertet, 55 gewertet und alle bestanden (kleinster Abstand 20,2); Seeds
  81–160 (Stand „Verblassen“) 23 nicht gewertet; im Standardlauf `simtest --gate` (Seeds 1–3) in keinem Seed gewertet (n = 13 / 7 / 13). Mit `R.GED = 0` waren es
  2 von 80 (`mess/schritt4/gates_1_80/auswertung.txt`, `VERBLASSEN.md` B.7). Das Merkmal selbst bleibt: Über die Seeds 1–20 × 730 Tage haben
  die Wegzieher −26,7 Punkte Heimatliebe gegenüber allen Erwachsenen, ohne Erfahrung −26,3 (`mess/schritt5/folgen_aus_h180.txt`).
- **Nach einer Pleite gründen wenige wieder, auch mit Verblassen (Ziel verfehlt, Frage an Noah).** Vorab verlangt war mindestens die Hälfte
  des Werts ohne Erfahrung (8,48 %). Erreicht sind 5,48 % bis Tag 1.460 (ohne Verblassen 2,32 %); selbst „sofort vergessen“ käme nur auf
  7,25 %, weil Rücklagen-Bremse, Wartezeit und Sperre weiter wirken (`VERBLASSEN.md` B.0–B.1, `mess/verblassen/kand/tabelle.txt`). „Nach 1–2
  Jahren wieder denkbar“ geht in Spieltagen für niemanden, auch ohne Erfahrung: Ein Lebensjahr dauert 10 Spieltage, gegründet wird nur unter
  60 Jahren, die Sperre nach einer Pleite dauert 180 Tage; wieder gegründet wird in allen Varianten 180 bis 358 Tage nach der Pleite
  (`VERBLASSEN.md` B.2, B.8). Welche Uhr Noah meint, ist offen.
- **„Warum?“ erklärt nur Entscheidungen aus der Liste genau.** Steht die Person heute oder gestern in der Liste, erklärt „Warum?“ genau diese
  Entscheidung; sonst rechnet es, was die Regeln jetzt mit einer neuen Zufallszahl wählen würden, und sagt das (`SCHRITT3.md` 3). Die
  Personenkarte zeigt nur ausgeführte Entscheidungen als „letzte Entscheidung, etwas zu tun“, nie „nichts tun“. Ohne Erfahrung oder Plan liegen
  andere Handlungen vorn, darum zieht jeder Vergleich andere Zufallszahlen; seit den Korrekturen der Schlussprüfung steht hinter jedem Satz
  „Ohne … hätte …“ die Rechnung dieses Vergleichs (die genannte Handlung und die echte Wahl). Vorher ließen sich 415 von 1.787 dieser Sätze aus
  den gezeigten Zahlen nicht nachrechnen (Seeds 1–3, Tag 200–260), jetzt jeder (Seeds 1–10 × 730 Tage: 102.230 von 102.230; `FIX.md` 2).
  Summen sind auf zwei Stellen gerundet; steht eine gewählte Handlung dadurch genau auf 25, sagt die Karte „knapp über 25“. Stehen die
  genannte Handlung und die echte Wahl gerundet gleich da, sagt sie bei der genannten „knapp vorn“ (Nachprüfung: 13 von 102.230 Sätzen).
- **Die Liste zeigt auch Plan-Fälle, und sie ist begrenzt.** Noahs Entscheidung 4 sagt „wegen Erfahrung“; die Liste zählt jede direkte
  Änderung durch Erfahrung oder Plan, getrennt nach Grund (Seed 1, Tag 370, 7 Uhr: Erfahrung 14, Plan 10, beides 2). Ob nur Erfahrung zählen soll,
  ist eine offene Frage an Noah (`SCHRITT3.md` 11). „Direkt“ heißt: Gründen, Kündigen, Stelle wechseln oder Zusammenziehen ist beteiligt; das
  sind 89–93 % aller Entscheidungen, die ohne Erfahrung und Plan anders wären (365 Tage), die übrigen zählt die Liste nicht. Je Tag hält sie
  höchstens 50 Einträge und den Vortag; in der großen Stadt kommen 106 bis 118 am Tag (`SCHRITT3.md` 4). Sie lebt nur im offenen Fenster:
  Nach Neuladen, Laden oder Übernehmen beginnt sie leer und sagt, seit wann sie zählt.
- **Leistung.** Beim Aufholen kostet der Beobachter etwa 3–5 % (Node ×1,028, Browser ×1,054); stündlich nichts Messbares. Gemessen ist nur im
  Headless-Chromium mit Software-Grafik (große Stadt unter 2 Bilder je Sekunde, vorher wie nachher); auf einem Gerät mit Grafikkarte nicht
  (`SCHRITT3.md` 8).
- **Wirtschaft.** Gepaart über die Seeds 1–80 gegen `R.GED = 0`: Kasse an Tag 730 −17,1 %, Gründungen bis Tag 730 −11,9 %, Einwohner an Tag
  730 gleich (`mess/schritt4/gates_1_80/wirtschaft_gegen_ged0.txt`). Das kleinste Budget bleibt positiv (Gate 3, 80 von 80).
- **Tests, die feste Momente der Teststadt suchen.** Sieben Browser-Tests suchen bestimmte Momente (eine Erweiterung, Schließungen, einen
  Campus …); für Version 10 sind sie neu gesucht (`SCHRITT4.md` 6.2). Jede weitere Verhaltensänderung verlangt wieder eine neue Suche.
  `--alt <datei>` in `simtest --wachstum` und `--techfrueh` (Vergleich mit Zwischenständen von Version 9) ist nicht an Version 10 angepasst
  (`SCHRITT4.md` 9).
- **KI und Etappe 2.** Beobachtungsschema 2 enthält weder Erfahrung noch Plan; entscheidet eine Policy, wirken beide nicht (gelernt wird aus
  ihren Handlungen trotzdem). Die Policy aus Etappe 1 ist mit Version 10 ungültig. `tests/browser_ki.cjs` prüft den Ablauf mit einer zur
  Laufzeit umgeschriebenen Kopie seiner Testdatei (Stadt-Version 10, gleiche Gewichte); das ist kein Training. Ein Trainingslauf auf Version 10
  ist nicht ausgeführt.
- **Nebenbefunde aus Version 9, nicht untersucht:** Rund 40 % der Lehrkräfte verlassen eine Schule in den ersten 24 Stunden wieder (in
  6c1741e 63 von 145; `SCHRITT1.md` 4.7). 52 von 3.986 schlechten Gründungserfahrungen entstehen aus einer Pleite, während der Besitzer in Haft
  ist; ob sie der Gründung oder der Haft zuzurechnen ist, hat Noah nicht festgelegt (`SIM_FIX.md` 4.2).

## Die trainierte Policy

- **Seit Version 10 ungültig (Noahs Entscheidung 5).** `v9_lokal_1` ist auf Stadt-Version 9 trainiert; das Spiel lehnt sie ab („Policy
  ungültig: trainiert auf Stadt-Version 9, diese Stadt ist Version 10 (neu trainieren)“), es entscheiden die Regeln (`berichte/etappe2/SCHRITT2.md`
  Abschnitt 8, `SCHRITT4.md` Abschnitt 3). Die Datei bleibt als Beleg in `ki/`. Was unten über sie steht, gilt für Version 9.
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
- Nicht gemessen: Erholung nach Jobverlust, eine Policy zusammen mit Gedächtnis und Plan (Schema 2 sieht beides nicht), Policy zusammen mit
  echtem Ollama, Bildrate mit eingeschalteter Policy.

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
- `simtest --kipolicy` und `tools/simtest_alle.sh` vergleichen „Policy aus“ mit 09083f5 (Version 9 ohne KI-Teil); seit Version 10 mit
  ausgeschaltetem Gedächtnis (`R.GED`, `R.OPFER_FREI`, `R.HAFT_EROEFFNUNG` = 0) und ohne `memName` und Versionsnummer. Sobald sich der
  sim-Block mit diesen Schaltern gewollt ändert, `ALT=<neuer Vergleichsstand>` setzen, sonst wird der Vergleich rot.
- Beide Skripte, `tests/alle.sh` und `tools/gate_t_wechsel.sh` brauchen die Git-Geschichte des Repos (Versionen 2–9, 09083f5 und 6c1741e
  per `git show` bzw. `git archive`), keine flache Kopie.
- In `ki/policy_v9_lokal_1.json` zeigt `herkunft.manifest` auf den Laufordner, der nicht im Repo liegt (das Manifest steht in
  `berichte/v9_lokal_1/`). Der Checkpoint selbst ist nicht im Repo; ohne ihn lässt sich die Parität dieser Policy nicht neu rechnen,
  nur nachlesen (`berichte/v9_lokal_1/paritaet.txt`).

## Spiel

- Behoben (Vorarbeit Etappe 2): `Sim.KI.policyPruefen` prüfte „endliche Zahl“ vor dem Runden auf float32, ein Gewicht oder Bias über dem
  float32-Bereich (z. B. `1e39`) galt als gültig und wurde im Netz zu ±Unendlich. Jetzt prüft es Gewichte, Bias und `clip` auch nach
  `Math.fround` und lehnt solche Dateien mit Grund ab („… über dem float32-Bereich“; `simtest --kipolicy`, Abschnitt 6, mit der Grenze
  `3.4028235e38` gültig, `3.4028236e38` nicht). Damit kann keine geprüfte Datei mehr überlaufen (gerechnet: höchstens etwa `1e285` bei
  6 Schichten zu 512). Den Rückfall zur Laufzeit prüfen `simtest --kipolicy` (Abschnitt 7) und `tests/browser_ki.cjs` (12) deshalb mit
  einer geprüften Policy, deren letzte Schicht erst danach im Speicher unendlich wird. Der sim-Block hat sich dabei geändert; `v9_lokal_1`
  ist auf den Sim-Hash `3b1a95e0e5ae9ea5` trainiert und ausgewertet.
- Nach einem Rückfall beim Laden (Policy fehlt oder passt nicht) speichert das Spiel „Regeln“ als Wahl. Liegt die Policy später wieder in
  `ki/`, muss man sie im Fenster neu wählen; das Spiel versucht es nicht von selbst (so auch in `docs/START.md`).

- Start mit einer Policy im Spielstand wartet auf `ki/`: höchstens 8 s je Anfrage (Liste und bis zu 12 Dateien). Eine gemeinsame Frist für
  alles fehlt; bei einem hängenden Server kann der Start also lange dauern. Lokal dauert es Millisekunden.
- Als `file://` geöffnet gibt es keine Policy aus `ki/` (Browser erlauben das nicht) und kein Three.js; über einen Server öffnen.
- Nur in Chromium geprüft (Playwright 1.56.1, Chromium 141, SwiftShader). Firefox und Safari nicht.
- Hauptfiguren mit Ollama: nur gegen einen Nachbau getestet, nie gegen ein echtes Sprachmodell (README, „Bekannte Schwächen“).
- Aufholen in Stücken ist eine Näherung: 1 × 90 Tage ist nicht bitgleich zu 3 × 30 Tagen, wenn die Stücke mitten am Tag beginnen und wie
  `aufholen()` den Rest in Tagesschritten rechnen (gemessen auf Version 8, `berichte/etappe0/BESTAND.md`, Abschnitt 5; neu gemessen auf
  6c1741e und Version 10 in den Seeds 1–3, z. B. 6c1741e Seed 2 mit 940 gegen 989, Version 10 Seed 3 mit 1.222 gegen 1.141 Einwohnern;
  `berichte/etappe2/SCHRITT2.md` Abschnitt 5, `berichte/etappe2/mess/schritt2/aufholen_basis_neu.txt`). Bitgleich sind Stücke mit Grenzen um Mitternacht und rein stündlich gerechnete,
  auch mit Speichern und Laden zwischen den Stücken und über offene Handlungen hinweg (`simtest --aufholtest`, `--gedaechtnis` G). Im Spiel
  ist die Näherung nicht gekennzeichnet; exakt oder gekennzeichnet ist eine Entscheidung für Etappe 5.
- Etappe 2 ist gebaut (Abschnitt oben). Nicht begonnen sind Etappe 4 (Hauptfiguren mit echten Modellen) und 5 (Stadtleben und Oberfläche:
  KI-Werkstatt, Parks, Verkehr; „Warum?“ in der Personenkarte gibt es seit Etappe 2). Von Etappe 3 gibt es nur das Belohnungs-Audit und
  einen ausgewerteten Lauf auf Version 9. Stand je Etappe in `docs/FORTSCHRITT.md`.
