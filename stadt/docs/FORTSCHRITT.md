# Fortschritt (Master-Prompt vom 28.09.2026)

Stand 01.10.2026, nach Etappe 2 (Gedächtnis, Erfahrung und Pläne der Bewohner; Spielstand-Version 10). Grundlage: Version 9 (Commit
09083f5), der KI-Teil aus Etappe 1 (6c1741e) und Etappe 2. Mit ausgeschaltetem Gedächtnis (`R.GED = 0`, `R.OPFER_FREI = 0`,
`R.HAFT_EROEFFNUNG = 0`) rechnet die Stadt Tag für Tag wie 6c1741e, bis auf `memName` und die Versionsnummer (Seeds 1–3 × 365 Tage, stündlich
und in Tagesschritten; `berichte/etappe2/mess/schritt4/frisch2/simtest_alle/gedaechtnis.txt`, Teil B), ohne Policy und mit ausgeschaltetem
Gedächtnis wie 09083f5 (Seeds 1–3 × 730 Tage, `berichte/etappe2/mess/schritt4/frisch2/simtest_alle/kipolicy.txt`). Diese Datei ist der
Einstieg für eine neue Sitzung: erst lesen, dann „Weitermachen“ unten.

## Etappen

| Etappe | Stand | Beleg |
|---|---|---|
| 0 Ausgangsstand | erledigt (auf Version 8, vor Version 9): Basistests, Architektur, 16 Probleme mit Beleg, Plan | `berichte/etappe0/BESTAND.md` |
| 1 Durchstich lernende KI | erledigt auf Version 9: Schema 2, Env-Server (JSONL), MaskablePPO-Trainer, Smoke- und lokaler Lauf, Checkpoints, Export, Parität, Laden im Browser aus `ki/`, Tests. Seit Version 10 ist die Policy aus diesem Lauf ungültig (neu trainieren) | `berichte/v9_uebertrag/UEBERTRAG.md`, `berichte/v9_lokal_1/`, `tests/browser_ki.cjs` |
| 2 Gedächtnis, Erfahrungen, Pläne | erledigt (Version 10) nach Noahs Entscheidungen 1–10: Gedächtnis mit Kurz- und Langzeit, Fakt und Verweis je Erinnerung, Erfahrung je Handlung und Lage (gelernt erst nach der Folge, verblasst), Pläne mit Schritt, Hindernis, Frist und Abbruchgrund, Rücklage vor der Gründung, Personenkarte mit „Warum?“, Liste „Heute anders entschieden“, Speicherformat 10 mit Übernahme, Tests. Punkt 8 bestanden (unten). Nach der Schlussprüfung (Technik, Texte, Bedienung) korrigiert, die Stadt rechnet dabei Tag für Tag gleich (unten). Offen: Fragen an Noah (unten); die Stärke von Bindungen und die Verpflichtungen (Master-Prompt Abschnitt 4, Pläne „Freunde + Verpflichtungen“) sind bewusst nach Etappe 5 verschoben (`berichte/etappe2/VERGLEICH.md` Abschnitt 3, „Bewusst nicht übernommen“) | `berichte/etappe2/` (Übersicht `LIESMICH.md`), README „Gedächtnis, Erfahrung und Pläne (Etappe 2)“ |
| 3 Belastbares Training | begonnen auf Version 9: Belohnungs-Audit (Belohnung v2 besteht es auf Version 9 nicht, 5 von 8), ein lokaler Lauf mit vorab festgelegter Auswertung (nicht bestanden). Es fehlen Belohnung v3, drei Trainingsseeds, Lehrplanstufen 2–6, und seit Version 10 ein neues Training mit Beobachtungsschema 3 (Erfahrung und Plan als Merkmale, `docs/EXPERIMENTE.md` Abschnitt 8) | `training/BELOHNUNG.md`, `training/AUSWERTUNG_V9.md`, `berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt` |
| 4 Hauptfiguren mit echten Modellen | nicht begonnen (Ollama nur gegen einen Nachbau getestet) | README, „Bekannte Schwächen“ |
| 5 Stadtleben, Produktqualität | begonnen mit Etappe 2: Personenkarte mit Plan, letzter Entscheidung samt Quelle und „Warum?“. Offen: KI-Werkstatt, Stadtansichten, Parks, Verkehr, Aufholen exakt oder gekennzeichnet, Stärke von Bindungen und Verpflichtungen (aus Etappe 2 verschoben) | `berichte/etappe2/SCHRITT3.md` |
| 6 Auslieferung | begonnen: Ordner `stadt/` mit Doku, Tests und Berichten; Etappe 1 zweimal unabhängig geprüft und korrigiert (unten), Etappe 2 aus einer frischen Kopie geprüft (`simtest_alle` 23 von 23, `tests/alle.sh` 32 von 32), in drei Schlussprüfungen geprüft und korrigiert, danach wieder aus einer frischen Kopie 23 von 23 und 32 von 32. Offen: Noahs Rückmeldung, Auslieferung einer freigegebenen Policy | `berichte/etappe2/SCHRITT4.md`, `berichte/etappe2/FIX.md` |

## Die 14 Punkte aus Abschnitt 16

| Nr. | Punkt | Stand | Beleg |
|---|---|---|---|
| 1 | Neue Stadt und alter Stand starten | bestanden | `tests/p6migration.cjs` (Stände der Versionen 2, 4–9 im Browser übernehmen, seit Version 10 44 Prüfungen), `tests/p10speicher.cjs` (große Stadt der Version 10 in `localStorage` und zurück), `tests/browser_ki.cjs` (neue Stadt), `simtest --migrationstest` (2–9 → 10, 368 ok, das Gedächtnis je Person unabhängig nachgerechnet), `--speichertest`, `--gedaechtnis` F (`berichte/etappe2/mess/schritt4/frisch2/simtest_alle/`, `berichte/etappe2/mess/schritt4/frisch/browser.txt`) |
| 2 | Ohne Sprachmodell spielbar | bestanden | `tests/browser_ki.cjs`, `tests/gedaechtnis.cjs` (seit Version 10) und die Prüfung von `docs/START.md` (Etappe 1) brechen jede Anfrage an Ollama ab und spielen weiter; simtest braucht kein Modell |
| 3 | Training nutzt denselben Kern | bestanden für Version 9; auf Version 10 kein Training ausgeführt | `tools/simkern.mjs` lädt den sim-Block aus `stadt.html`; Sim-Hash im Manifest von `v9_lokal_1` = `3b1a95e0e5ae9ea5` = sim-Block von 6c1741e (seit Etappe 2 `386c5ec814feb302`, nach den Korrekturen der Schlussprüfung `0b5f143bb948bcbb`: nur `warum` und ein Kommentar, gleiches Rechnen); auf Version 10 läuft die Episode (`tools/kiepisode.mjs`) in `simtest --kipolicy` mit (`berichte/etappe2/SCHRITT4.md` Abschnitt 3 und 5); Python rechnet nichts nach |
| 4 | Echter Lauf hat Parameter verändert, Checkpoint ladbar | bestanden (Version 9) | `v9_lokal_1`: 155.648 Schritte, L2-Änderung 14,49 (`berichte/v9_lokal_1/manifest.json`); Smoke aus frischer Kopie: L2 1,7266, Checkpoint von Export, Parität und `--fortsetzen` geladen (`berichte/pruefung_2026-09-29/smoke_kette.txt`). Die Policy gilt seit Version 10 nicht mehr |
| 5 | Export stimmt mit Trainer überein | bestanden (Version 9) | Parität 644/644, Logits ≤ 9,58e-7, am 29.09. aus frischer Kopie gegen den Checkpoint von `v9_lokal_1` neu gerechnet (`berichte/pruefung_2026-09-29/paritaet_v9_lokal_1.txt`); Smoke 644/644, ≤ 6,23e-8; Neuexport mit dem korrigierten `exportiere.py` gibt denselben Inhalts-Hash `28385759bed1db02` |
| 6 | Qualität gegen Regeln auf getrennten Daten gemessen | bestanden (die Messung, Version 9); die Policy selbst fällt durch | Kriterien vorab (`training/AUSWERTUNG_V9_vorab.md`, sha256 in `.sha256`, Teil A unverändert), Kandidatenwahl auf 20016–20031, Abschluss einmal auf 30000–30031: Hauptmetrik 5/5 Gruppen besser, Nebenprüfungen 16/26 → nicht bestanden (`berichte/v9_lokal_1/abschluss.md`) |
| 7 | Standard nur mit geprüftem Kandidaten | bestanden | Regeln sind Standard, `stadt.html` enthält keine Policy (`tests/browser_ki.cjs` prüft das). Seit Version 10 wird die Policy aus Etappe 1 sichtbar abgelehnt, beim Umschalten, beim Datei-Import und in einem übernommenen Stand der Version 9 („neu trainieren“, Regeln; `tests/browser_ki.cjs`, `tests/p10speicher.cjs`, `simtest --kipolicy` Teil 0; `berichte/etappe2/SCHRITT4.md` Abschnitt 3 und 6.1) |
| 8 | Erinnerungen und Pläne verändern nachweisbar spätere Entscheidungen | **bestanden** | Gegenprobe vor jeder echten Entscheidung (dieselbe Person, derselbe Zustand, derselbe Zufallsstand, nur ohne Erfahrung und Plan) nach vorab festgelegten Kriterien (`berichte/etappe2/VERGLEICH.md` Abschnitt 4, Schritt 1): Seeds 1, 2, 3 über 365 Tage 1,174 / 1,034 / 0,832 % der Entscheidungen anders (Soll ≥ 0,3 %), davon 92,5 / 89,9 / 89,3 % direkt (Soll ≥ 85 %); nur das Erfahrungs-Byte zu löschen stellt in 99,82 / 99,85 / 99,92 % die Wahl ohne Erfahrung her (Soll ≥ 99 %); echte Wahl = Probe in 100 % (`simtest --gedaechtnis` A, `berichte/etappe2/mess/schritt4/frisch2/simtest_alle/gedaechtnis.txt`). Über 730 Tage 1,332 / 0,886 / 0,654 % (`berichte/etappe2/mess/verblassen/schluss/probe8_auswertung.txt`); gegen Entwurf C (0,58 / 0,53 / 1,03 %) im Mittel etwa ein Drittel stärker (0,957 gegen 0,713 %), aber in den Seeds 2 und 3 noch im Bereich 0,5–1 %, über den Noah mit Entscheidung 4 hinaus wollte; die Erfahrung allein ändert 0,46–0,61 % (Folge der Entscheidungen 9 und 10, `docs/GRENZEN.md`). Muster über 20 Seeds: Kündigungen für die Elternzeit 8.000 statt 39.231, sonstige 2.059 statt 10.703 (`berichte/etappe2/mess/schritt5/folgen_aus_h180.txt`). Im Browser ein echter Fall: „Ohne diese Erfahrung hätte Anna einen Betrieb gegründet (in dieser Rechnung: … = +26,4)“ (`tests/gedaechtnis.cjs` 17/17, `berichte/etappe2/mess/fix/frisch/browser/logs/gedaechtnis.log`) |
| 9 | Ungültige oder veraltete KI-Antworten beschädigen nichts | bestanden für die Policy und das nachgebaute Sprachmodell; mit echtem Modell nicht ausgeführt | `tests/browser_ki.cjs` (beschädigte, fremde, Version-8- und Version-9-Dateien, abgeschnittenes JSON, falscher Hash, NaN, Rückfall zur Laufzeit), `simtest --kipolicy` (beschädigte Dateien, Rückfall, Zahlen über dem float32-Bereich; die Lücke ist seit der Vorarbeit zu Etappe 2 geschlossen, `berichte/etappe2/SCHRITT0.md` 2.3), `simtest --kitest`, `tests/t1_xss.cjs`, `tests/p4test.cjs` (späte Antworten, Ausfall). Ein werfender Beobachter bricht die Stunde nicht ab (`berichte/etappe2/SIM_FIX.md` 2.1) |
| 10 | Wiederholung, Speicherung, Migration mit definierter Semantik | Speichern und Migration bestanden; Aufholen an Tagesgrenzen und stündlich bestanden, mitten am Tag eine ungekennzeichnete Näherung; Replay nicht ausgeführt | Speichern und Laden mitten am Tag bitgleich, auch mit 384 offenen Handlungen 60 Tage lang (`simtest --speichertest`); Migration 2–9 → 10 und 23 beschädigte Stände der Version 10 abgelehnt (`--migrationstest`, `--gedaechtnis` F; Logs in `berichte/etappe2/mess/schritt4/frisch2/simtest_alle/`); Aufholen 1 × 30 = 3 × 10 bitgleich an Grenzen um Mitternacht und rein stündlich, über offene Handlungen hinweg (`--aufholtest`, `--gedaechtnis` G); Stücke mitten am Tag in Tagesschritten nicht (gemessen auf 6c1741e und Version 10, `berichte/etappe2/SCHRITT2.md` Abschnitt 5; Optionen A/B offen); kein Ereignisprotokoll mit Replay |
| 11 | Browsertests aus dem Repo reproduzierbar | bestanden | `bash tests/alle.sh` aus einer frischen Kopie mit relativen Pfaden: 32 von 32 grün, 534 OK-Prüfungen (`berichte/etappe2/mess/schritt4/frisch/browser.txt`), nach den Korrekturen der Schlussprüfung 32 von 32, 537 (`berichte/etappe2/mess/fix/frisch/browser.txt`); in Etappe 1 30 von 30, 499 (`berichte/pruefung_2026-09-29/browser_alle.txt`) |
| 12 | Leistungsaussagen mit Messumgebung | bestanden für Umgebung, Training und Simulation; Bildrate mit Policy und auf einem Gerät mit Grafikkarte nicht ausgeführt | Durchsatz 332/226/111 Schritte/s mit Rechner und Last (`berichte/v9_uebertrag/durchsatz.txt`, Manifest `hardware`); Gate T im Wechsel mit 6c1741e, Median 1.239 gegen 3.328 ms (`berichte/etappe2/SCHRITT3.md` Abschnitt 9), nach den Korrekturen der Schlussprüfung 1.265 gegen 3.448 ms (`berichte/etappe2/FIX.md` Abschnitt 3), Optimierung bitgleich (`berichte/etappe2/OPTIMIEREN.md`); Kosten des Beobachters in Node und im Headless-Chromium mit Software-Grafik (`berichte/etappe2/SCHRITT3.md` Abschnitt 8); Größe des Spielstands (`berichte/etappe2/SCHRITT2.md` Abschnitt 6). Alles auf einem Linux-Container mit 4 Kernen ohne GPU |
| 13 | Zentrale Schaltflächen funktionieren | bestanden, soweit die Browser-Tests klicken | 32 Browser-Tests mit echten Klicks und Tasten (Fenster, Karten, Handy, Tastatur, Hilfe, Entscheidungen, Datei laden und entfernen; neu der Knopf „… anders“, die Liste, „Warum?“, Name → Personenkarte, Import eines Stands der Version 9); kein vollständiger Durchgang von Hand. Die Schlussprüfung „Bedienung“ hat die neue Oberfläche wie Noah benutzt (breit, Handy, Tastatur); ihre Befunde sind korrigiert (unten) |
| 14 | Doku erklärt Start, Training, Auswertung, Modellwechsel, Fortsetzung | bestanden für Version 9 (aus einer frischen Kopie geprüft, 29.09.); für Version 10 aktualisiert (01.10.), die Trainingsbefehle auf Version 10 nicht ausgeführt | `docs/START.md` (neu: Personenkarte, „Warum?“, Liste), `docs/EXPERIMENTE.md` (Policy aus Etappe 1 ungültig, Schema 3), `docs/ARCHITEKTUR.md` (Andockstellen von Etappe 2), `docs/GRENZEN.md`, README, `berichte/etappe2/LIESMICH.md` |

## Etappe 2: Gedächtnis, Erfahrungen, Pläne (29.09.–01.10.2026)

Gebaut in einer Kopie dieses Ordners nach dem Bauplan des Entwurfs (Weg C mit Teilen aus A und B) und nach Noahs Entscheidungen, Schritt für
Schritt mit Bericht. Alle Berichte und Messtabellen: `berichte/etappe2/`.

| Phase | Ergebnis | Bericht |
|---|---|---|
| Entwurf | drei Prototypen verglichen, Empfehlung C mit Teilen aus A und B, Bauplan | `VERGLEICH.md` |
| Noahs Entscheidungen | 1 kein Name im Gedächtnis, 2 Rücklage für alle Gründer, 3 Elternzeit wird gelernt, 4 „Warum?“, Liste und stärkere Wirkung, 5 Policy aus Etappe 1 ungültig; danach 6 Rücklage erst ab der Stufe Stadt, 7 schneller statt Grenze ändern, 8 Gate 7 erst ab 15 Wegziehern, 9 Stärke 1,5, 10 Erfahrung verblasst | `ENTSCHEIDUNGEN_NOAH.md` |
| Schritt 0, Vorarbeiten | `R.OPFER_FREI`, Fallauswahl in zwei Tests, float32-Lücke geschlossen | `SCHRITT0.md` |
| Schritt 1, Simulation | Bausteine im sim-Block, Gegenprobe zu Punkt 8, Beobachter, `Sim.warum`; Gate T danach rot (+26,4 %, die Stadt wird größer) | `SCHRITT1.md` |
| Kalibrierung der Stärke | vorab festgelegt; Stufe 1 (Teil B), nach Entscheidung 8 Stufe 4 (Teil E), Noah wählt 1,5 (Teil F); Nachmessung nach dem Sim-Fix (Teil C) | `KALIBRIERUNG.md` |
| Optimieren | Gate T 5.640,5 → 1.470 ms, Tag für Tag bitgleich | `OPTIMIEREN.md` |
| Sim-Fix | Beobachter-Fehler, Haft ist keine Wechselfolge, `warum` für Kinder und mit Zufallsstand; Befund „nach einer Pleite gründet fast niemand mehr“ | `SIM_FIX.md` |
| Schritt 2, Speicherformat 10 | `memName` gestrichen, Übernahme aus Version 9, `gedPruefen`, Policy aus Etappe 1 abgelehnt | `SCHRITT2.md` |
| Verblassen | H = 180 gewählt (vorab festgelegte Regel), Ziel „halb so viele Wiedergründungen wie ohne Erfahrung“ verfehlt | `VERBLASSEN.md` |
| Schritt 3, Oberfläche | Personenkarte, „Warum?“, Liste, Browser-Test `gedaechtnis` | `SCHRITT3.md` |
| Schritt 4, Tests | `simtest --gedaechtnis`, Vergleiche über `R.GED = 0`, Browser-Tests auf Version 10; frische Kopie 23/23 und 32/32; Gates Seeds 1–80 | `SCHRITT4.md` |
| Schritt 5, Doku | README, `docs/`, `berichte/etappe2/`, vier Messwerkzeuge nach `tools/` (geprüft) | `berichte/etappe2/LIESMICH.md` |
| Schlussprüfung und Korrekturen | drei Prüfungen (Technik, Texte, Bedienung) aus frischen Kopien, kein Befund „blockiert“; alle „mittel“ und die kleinen korrigiert (unten), Tag für Tag gleich gerechnet | `berichte/etappe2/FIX.md` |

Gates mit dem Endstand (Seeds 1–80, `berichte/etappe2/mess/schritt4/gates_1_80/auswertung.txt`): Gates 1, 2, 3, 4, 5, 6, T und B je 80 von
80; Gate 7 55 gewertet und bestanden, 25 nicht gewertet (Entscheidung 8). Die Seeds 1–80 sind Seed für Seed gleich der Messung der Phase
„Verblassen“, die auch die Seeds 81–160 bestätigt hat (Gate 4 80 von 80, Gate 7 57 gewertet und bestanden, 23 nicht gewertet;
`berichte/etappe2/SCHRITT4.md` Abschnitt 8, `VERBLASSEN.md` B.4). Keine Schwelle ist geändert; Gate 7 zählt nach Noahs Entscheidung 8 erst ab
15 Wegziehern.

### Offene Fragen an Noah (Etappe 2)

1. Soll die Liste „Heute anders entschieden“ nur Fälle mit Erfahrung zeigen? Heute zeigt und zählt sie auch Plan-Fälle, getrennt nach Grund
   (`berichte/etappe2/SCHRITT3.md` Abschnitt 11).
2. „Nach einer Pleite nach 1–2 Jahren wieder denkbar“: Spieltage oder Lebensjahre? In Spieltagen ist es für niemanden möglich (Sperre,
   Altersgrenze 60, ein Lebensjahr = 10 Spieltage); das vorab gesetzte Ziel für die Wiedergründung ist verfehlt (`berichte/etappe2/VERBLASSEN.md`
   B.0, B.8).
3. Eine Pleite, während der Besitzer in Haft ist: der Gründung oder der Haft zurechnen? (`berichte/etappe2/SIM_FIX.md` 4.2)
4. `tests/p8tech.cjs` prüft jetzt die größte Tech-Firma ohne Autowerk; oder den Test auf Autowerke erweitern? (`berichte/etappe2/SCHRITT4.md` 9)
5. Die Personenkarte beschreibt die Figur in der dritten Person (kein „du“); war die du-Form anders gemeint? (`berichte/etappe2/SCHRITT3.md` 11)
6. Aufholen exakt oder gekennzeichnet (Optionen A/B, Etappe 5); der Beobachter kostet beim Aufholen 3–5 % (`berichte/etappe2/SCHRITT3.md` 11).

## Etappe 2: Korrekturen nach der Schlussprüfung (01.10.2026)

Drei Prüfungen (Technik, Texte, Bedienung) haben den Endstand von Etappe 2 aus frischen Kopien geprüft. Kein Befund war „blockiert“. Jeder
Befund wurde vor der Korrektur selbst nachgeprüft; alle „mittel“ sind bestätigt und behoben, ebenso die kleinen. Die Stadt rechnet danach Tag
für Tag gleich (Seeds 1–10 × 730 Tage stündlich, Seeds 1–3 × 730 Tagesschritte; Gates 1–80 und probe8 je Seed gleich). Bericht und Belege:
`berichte/etappe2/FIX.md`, `berichte/etappe2/mess/fix/`. Die Berichte „Texte“ und „Bedienung“ lagen dem Nachbessern nur bis zu einer
abgeschnittenen Stelle vor; die zwei fehlenden Befunde der Bedienung und der Rest aus der Nachprüfung sind danach behoben (`FIX.md` 10).

| Befund (Schwere) | nachgeprüft | Stand |
|---|---|---|
| „Warum?“: „Ohne … hätte …“ oft nicht nachrechenbar (mittel) | bestätigt: 415 von 1.787 Sätzen (Seeds 1–3, Tag 200–260) | behoben: `Sim.warum` gibt je Vergleich seine Rechnung zurück, die Karte zeigt sie in Klammern; nachrechenbar 102.230 von 102.230 (Seeds 1–10 × 730 Tage); `simtest --gedaechtnis` und `tests/gedaechtnis.cjs` prüfen es |
| Policy-Meldung nach Übernahme/Import eines Stands der Version 9 rät „wieder in ki/ legen“ (mittel) | bestätigt | behoben: „stammt aus Version 9 und gilt in Version 10 nicht mehr (neu trainieren)“; `p10speicher` prüft Übernahme und Import |
| Einordnung der „stärkeren Wirkung“ (Entscheidung 4) fehlt (mittel) | bestätigt, Zahlen nachgerechnet | behoben in README, `docs/GRENZEN.md` und Punkt 8 oben |
| Kommentar zu `GED_STAERKE` falsch (klein) | bestätigt | behoben (sim-Block, nur Kommentar) |
| Liste: „jede Entscheidung“ übertreibt (klein) | bestätigt | behoben in der Liste und in `docs/START.md` („… beteiligt ist, etwa 9 von 10“) |
| „gleich wieder Arbeit gesucht“ (klein) | bestätigt (Frist 30 Tage) | behoben in README und `docs/GRENZEN.md` |
| roher englischer Fehlertext in der Liste (klein) | bestätigt | behoben (deutscher Satz, Fehlertext nur im `title`) |
| FORTSCHRITT nennt Verschobenes nicht (klein) | bestätigt | behoben (Etappe 2 und 5 oben) |
| `tests/LIESMICH.md`: Zeit von `p6migration` aus einem roten Lauf (klein) | bestätigt | behoben |
| Pläne außer der Rücklage sind nur Anzeige (klein) | bestätigt | dokumentiert (`docs/GRENZEN.md`) |
| Kopf von `ki/policies.json` veraltet (klein) | bestätigt | gelassen wie vorgeschlagen, Warnung in `tools/ki_liste.mjs` |
| Beobachter gilt modulweit (klein) | bestätigt (Code) | dokumentiert (`docs/ARCHITEKTUR.md`) |
| Liste verschiebt sich unter Auge und Maus (klein) | bestätigt | behoben: unverändert nicht neu eingesetzt, oberster sichtbarer Eintrag bleibt an seiner Stelle (Browser-Test mit Gegenprobe) |
| Liste lebt nur im Fenster, sagt es nicht (klein) | bestätigt | behoben: „Gezählt erst, seit die Stadt in diesem Fenster läuft (Tag X, Y Uhr)“ |
| Handy: Knopf nur Symbol und Zahl, Hilfe erklärt ihn nicht (klein) | bestätigt | behoben: Zeile in der Hilfe, nur wo der Knopf nur Symbol und Zahl zeigt; Hilfe bei 1280 × 800 weiter ohne Scrollen |
| Wörter mit Vorwissen („wie in Version 9, mit Zielbonus“; gelernte schlechte Folge ohne Maßstab) (klein, Bedienung) | bestätigt | behoben: „Lage und Charakter (wie dringend es ist, Persönlichkeit, Ziel, Erinnerungen)“; hinter der gelernten schlechten Folge steht der Maßstab, z. B. „(wieder Arbeit suchen zählt schlecht)“ (`FIX.md` 10) |
| Escape schließt Liste und Karte, Fokus landet auf body (klein, Bedienung) | bestätigt | behoben: Schließen gibt den Fokus dem Knopf zurück, der die Karte geöffnet hat; `gedaechtnis` prüft es (`FIX.md` 10) |
| Nachprüfung: gerundeter Gleichstand in 13 von 102.230 Sätzen „Ohne …“ nicht entscheidbar (klein) | bestätigt (`simtest --gedaechtnis`: Seeds 2 und 3 je 1) | behoben: die Karte sagt bei der genannten Handlung „knapp vorn“; `simtest --gedaechtnis` zählt die Fälle (`FIX.md` 10) |

Gate T im Wechsel (sim-Block geändert, Nachtrag 7): 12 Runden allein, Median neu 1.265, vorher 1.247,5, Basis 6c1741e 3.448 ms (neu/Basis
0,367); A/B 10 Runden: nachher/vorher Wandzeit 1,005, CPU 1,018 – innerhalb der Streuung (`berichte/etappe2/FIX.md` 3). Aus einer frischen
Kopie: `simtest_alle` 23 von 23 (5 min), `tests/alle.sh` 32 von 32 mit 537 OK-Prüfungen, „ALLES GRÜN“ (27 min).

## Etappe 1: Korrekturen nach der unabhängigen Prüfung (29.09.2026)

Die folgenden drei Abschnitte beschreiben den Stand von Etappe 1 (Version 9, 29.09.2026) und bleiben als Protokoll so stehen.

Zwei Prüfungen (Technik, Bedienung) haben den Ordner aus frischen Kopien geprüft. Jeder Befund wurde vor der Korrektur selbst nachgeprüft.
Keiner war „blockierend“; alle „mittel“ sind bestätigt und behoben, die kleinen, wo es ohne Risiko ging.

| Befund (Schwere) | nachgeprüft | Stand |
|---|---|---|
| Belohnungs-Audit kennt Dauer-Freinehmen nicht (mittel) | bestätigt: „jeden Morgen frei, sonst Regeln“ schlägt in `alle` die Regeln, 17,23 gegen 17,00, Geldbedarf 34,1 gegen 20,0 | im Audit ergänzt (`frei_sonst_regel`, `frei_sonst_warten` in `tools/ki_fallen.mjs`): v2 besteht jetzt 5 statt 6 von 8. Belohnung v3 (Lohnverlust zählen) ist offen, sie braucht neues Training |
| Rückmeldung beim Datei-Import unsichtbar (mittel) | bestätigt: Die Meldung liegt hinter den offenen Fenstern (`elementFromPoint` trifft das Fenster), der Status bleibt „Es entscheiden die Regeln.“ (`import_rueckmeldung.txt`) | behoben: Ergebnis steht im Status des Fensters (angenommen, oder abgelehnt mit Grund), alter Hinweis gelöscht, Status wird ins Bild gescrollt; `browser_ki` prüft die Sichtbarkeit |
| Falsche Python-Mindestversion (mittel) | bestätigt: numpy 2.4.6 `Requires-Python >=3.11`, networkx 3.6.1 `!=3.14.1,>=3.11` (installierte Metadaten, PyPI) | behoben in `docs/EXPERIMENTE.md` und `training/requirements.txt`: Python 3.11 bis 3.14, nicht 3.14.1 |
| Browser-Tests rot mit aktiver venv, Pillow (mittel) | bestätigt: `python3` der venv hat kein PIL | behoben: `otest/breit` liest die Pixel in Node (eigener PNG-Leser, auf 3 Bildern pixelgleich mit Pillow); kein Pillow mehr nötig; mit aktiver venv geprüft |
| Strg+C beim Fortsetzen macht Manifest und Herkunft falsch (mittel) | bestätigt: Manifest „fertig“, 2.048 Schritte, `bester` 1.024; Datei hatte 7.168; Export schrieb 1.024 (`abbruch_vorher.txt`) | behoben: Strg+C/SIGTERM stoppen geordnet, Node-Prozesse in eigener Sitzung, Manifest und Checkpoints nach jedem Rollout (atomar), `--fortsetzen` setzt „läuft“ und vergisst alte Abbruchgründe, Export nimmt die Schritte aus dem Checkpoint (`abbruch.txt`) |
| Endlichkeit vor `Math.fround` geprüft (klein) | bestätigt: `1e39` wird angenommen, `tanh` sättigt still | nicht behoben: liegt im sim-Block, eine Änderung dort ändert den Sim-Hash, auf den `v9_lokal_1` trainiert ist; dokumentiert (`docs/GRENZEN.md`, `ki/LIESMICH.md`, Kommentar in `stadt.html`), Korrektur mit der nächsten Änderung am sim-Block (Etappe 2) |
| Nach Rückfall wird die Wahl „Regeln“ gespeichert (klein) | bestätigt (so auch in `browser_ki`) | dokumentiert (`docs/START.md`, `ki/LIESMICH.md`, `docs/GRENZEN.md`), im Spiel sagt der Hinweis jetzt „im Fenster neu wählen“ |
| Stadtwirkung im Spiel nicht sichtbar (klein) | bestätigt | behoben: „Auswertung laut Datei“ mit `hinweis` der Policy (neue Stadt Tag 90: 45–53 statt 107–128 Einwohner); allgemeiner Satz „Eine Policy wirkt auf die ganze Stadt“ |
| Das Spiel zeigt nicht, dass genau diese Policy durchgefallen ist (klein) | bestätigt | behoben (wie oben); der fest eingebaute Satz „Keine Policy hat … bestanden“ ist ersetzt durch „Experimentell heißt: nicht freigegeben“ |
| Doppelte oder englische Texte im Fenster (klein) | bestätigt (404-Satz doppelt, „– Der Ordner“, `file://` doppelt, JSON-Fehler englisch) | behoben, `browser_ki` prüft „jeder Satz einmal“; „Schicht 0: Zahl“ kommt aus dem sim-Block und bleibt |
| Zeit-Gate T unter Last rot (klein) | plausibel (Wandzeit-Grenze) | `--gate` läuft in `simtest_alle.sh` allein am Ende; Hinweis in `START.md` und im Skriptkopf |
| `berichte/smoke_*` nicht in `.gitignore` (klein) | bestätigt | `.gitignore` schließt `berichte/smoke_*/` und `ki/policy_smoke_*.json` aus, Doku sagt es; `.venv` jetzt auch als Verweis ausgeschlossen |
| Gleicher `--name` gibt Traceback (klein) | bestätigt | freundliche Meldung, Exit 2 |
| „68,50 ersetzte 68,21“ ohne Beleg (klein) | Log nicht auffindbar | Satz ersetzt durch den neu geprüften Ablauf mit den Zahlen aus `berichte/pruefung_2026-09-29/abbruch.txt` (wiederholbar mit `abbruch_test.sh` daneben); alle Belege dieser Nachprüfung liegen in diesem Ordner |
| GRENZEN: „203 statt 471“ missverständlich (klein) | bestätigt | „je Stadt 45–53 statt 107–128, zusammen 203 statt 471“ |
| `tools/messe.py`: Pfad, macOS-Einheit (klein) | bestätigt | Pfad korrigiert, auf macOS Byte statt KiB (auf keinem Mac geprüft) |
| Bei der Nachprüfung selbst gefunden: `KI_ORDNER=ki` für `browser_ki` mit der echten Policy (so in `tests/LIESMICH.md`) lief nicht | bestätigt: Abbruch mit ENOENT, der Test suchte die Version-8-Datei in `KI_ORDNER` und löste `ki` gegen `tests/` auf | behoben in `tests/browser_ki.cjs`: Version-8-Datei immer aus `tests/ki_testdaten/v8/`, `KI_ORDNER` relativ zu `stadt/`; mit den Testdaten und mit `KI_ORDNER=ki` je 30 von 30 (unten) |
| Kleinere Lücken beim Bedienen (klein): geladene Datei nicht entfernbar; Server ohne `--bind`; kein Mac-Hinweis zum Ruhezustand beim Langlauf; Kommentar in `stadt.html` verweist auf `tools/ki_patch.mjs`, das hier nicht liegt | alle vier bestätigt | Knopf „Geladene Datei entfernen“ (`browser_ki` prüft ihn); `--bind 127.0.0.1` in `START.md`, `README.md` und `ki/LIESMICH.md`; `caffeinate -i -w <pid>` in `EXPERIMENTE.md` §2 (auf keinem Mac geprüft); Kommentar sagt jetzt, dass das Patch-Werkzeug aus dem Übertrag nicht im Ordner liegt, und nennt die float32-Lücke (nur Kommentarzeilen, sim-Block gleich) |

Die Oberflächenteile sind in den Patch-Quellen im Arbeitsordner geändert (`SP/ml/v9/tools/kipatch/ui_ki.js`, `einst_ki.html`) und
`stadt.html` daraus neu erzeugt (zweimal gleich, sha256 `0b453bf1…`, vorher `48732527…`; der Zwischenstand `d2663b36…` unterschied sich nur
in den Kommentarzeilen zu `ki_patch.mjs`); der sim-Block ist bytegleich (`3b1a95e0e5ae9ea5`). Geändert sind außerdem
`training/trainiere.py`, `stadt_env.py` und `exportiere.py` (neue Code-Hashes für neue Läufe; das Rechnen ist gleich, Smoke-Lauf mit
denselben Validierungen und L2 1,7266).

## Etappe 1: Nachprüfung aus einer frischen Kopie (29.09.2026, nach den Korrekturen)

`cp -r` dieses Ordners nach `SP/ml/frisch_fix/stadt`, nach allen Korrekturen, außerhalb des Repos (`STADT_GIT=<repo>`), Linux-Container
mit 4 Kernen, eigener Port 9066 (Server per PID beendet; der Server auf 8000 und der KI-Nachbau auf 11434 blieben unberührt). Danach sind in
diesem Ordner nur noch diese Datei und `berichte/` (die Belege unten) geändert worden. Logs in `berichte/pruefung_2026-09-29/`. Training und
Belohnungs-Audit liefen in einer ersten frischen Kopie am selben Tag; `training/` und `tools/` sind seitdem unverändert (danach geändert:
zwei Kommentarzeilen in `stadt.html`, `tests/browser_ki.cjs` wegen `KI_ORDNER`, Doku).

| Prüfung | Ergebnis |
|---|---|
| `bash tools/simtest_alle.sh` | 22 von 22 mit Exit 0 in 12,3 min (20 Modi, `--kipolicy` mit 26 ok, `--kipolicy` mit `ki/policy_v9_lokal_1.json` mit 27 ok, 0 FEHL); `--gate` allein am Ende, T 3.132 / 2.643 / 2.736 ms; Speichertest `ca60551e5b316d33`, Migration 324 ok; Ausgaben ohne Zeitangaben gleich zwei früheren Läufen aus frischen Kopien am selben Tag (`simtest_alle.txt`) |
| Regression Policy aus gegen 09083f5 | `tools/tagvergleich.mjs` Seeds 1–6: 12 von 12 Läufen Tag für Tag bitgleich (120 Tage stündlich, 60 Tagesschritte); ganzer Zustand je Tag, Seeds 7, 23, 41, 150 Tage stündlich und per Tagesschritt: 150 von 150 Tagen gleich (`regression.txt`); `simtest --kipolicy` prüft dasselbe über 730 Tage |
| Parität | `v9_lokal_1` gegen ihren Checkpoint (`bester.zip` sha256 `aecd97d4…`) 644/644, Logits ≤ 9,58e-7, normalisierte Eingaben gleich; Neuexport mit dem neuen `exportiere.py` bis auf `hinweis` und `auswertung` gleich der Datei in `ki/` (Hash `28385759bed1db02`, 155.648 Schritte) (`paritaet_v9_lokal_1.txt`); Smoke 644/644, ≤ 6,23e-8 (erste Kopie, `smoke_kette.txt`) |
| Training (erste Kopie) | Smoke L2 1,7266, gleicher Name abgelehnt, Fortsetzen auf 4.096, Export; Strg+C, `kill -9`, Fortsetzen, Export: Manifest passt jedes Mal zu den Dateien (`abbruch.txt`) |
| Belohnungs-Audit (erste Kopie) | 5 von 8, Exit 1, 739 s (`ki_fallen_v9_lokal_1.txt`) |
| `bash tests/alle.sh` (PORT 9066) | 30 von 30 grün, 499 OK-Prüfungen (jeder Test genau seine Soll-Zahl, 0 FEHL), „ALLES GRÜN“, Exit 0, 24,6 min; Seitenserver per PID beendet (`browser_alle.txt`) |
| `browser_ki` mit der echten Policy (`KI_ORDNER=ki`) | `KI_ORDNER=ki bash tests/alle.sh browser_ki`: 30 von 30 mit `v9_lokal_1` aus `ki/` (155.648 Trainingsschritte, im Fenster „Auswertung laut Datei: nicht bestanden“) (`browser_ki_echt.txt`) |
| Tests mit aktiver `.venv` (`otest/breit`, `browser_ki`) | `source .venv/bin/activate` (`python3` ist das der venv, ohne PIL): `otest/breit` 12 von 12, `browser_ki` 30 von 30 (`browser_venv.txt`); der PNG-Leser in Node gibt auf 3 Bildschirmfotos dieselben Pixel wie Pillow |
| `.gitignore` | mit `git init` und `git add -A --dry-run` nachgestellt, dazu künstliche Läufe, Smoke-Berichte, Smoke-Policies, Ausgaben und `.venv` als Verweis (15 künstliche Dateien): 140 Dateien, genau die dieses Ordners, nur `stadt.html` über 1 MB, keine künstliche dabei |

Die Prüfung davor (vor den Korrekturen, ebenfalls aus frischen Kopien): `simtest_alle.sh` zweimal 22/22, `tests/alle.sh` 30/30 mit 493 OK in
25 min, Befehle aus `docs/EXPERIMENTE.md` einschließlich Modellwechsel auf 1 × 32 mit relu und kurzer `lokal_v9`/`langlauf`-Läufe,
`training/requirements.txt` in frischer venv (`pip freeze` gleich, `pip check` ohne Fehler), `docs/START.md` im Browser. Dabei gefunden und
behoben: Endete eine Episode schon beim `reset` (Seed 10023, `nr` 1151), brach die Python-Seite ab (Nachtrag B9 in `training/AUSWERTUNG_V9.md`).

## Etappe 1: Letzte Korrekturen und Endprüfung vor dem Commit (29.09.2026)

Die Nachprüfung fand zwei kleine neue Fehler, beide behoben:
- `trainiere.py`: Das Manifest wird jetzt direkt nach `letzter.zip` geschrieben und nach der Validierung noch einmal. Vorher passte es nach
  einem `kill -9` mitten in einer Validierung nicht zu `letzter.zip`. Geprüft: `kill -9` während einer Validierung → Manifest und Datei
  3.328 Schritte, gleiche sha256. Smoke danach mit denselben Gewichten wie vorher (L2 1,7266).
- `tools/simtest_alle.sh gate` startete unter Linux zusätzlich einen leeren Lauf (GNU xargs mit leerer Liste). Jetzt 1 von 1 Läufen.

Endprüfung aus einer frischen Kopie: `simtest_alle.sh` 22 von 22 mit Exit 0, `tests/alle.sh` 30 von 30 grün (499 OK-Prüfungen, 24 min).

## Weitermachen

Zuerst prüfen, dass alles noch steht (im Ordner `stadt/` einer vollständigen Git-Kopie, sonst `STADT_GIT=<repo>`):

```bash
bash tools/simtest_alle.sh          # 21 Modi + --kipolicy, gut 5 min mit 2 Läufen gleichzeitig
bash tests/alle.sh                  # 32 Browser-Tests, rund 28 min (Voraussetzungen: tests/LIESMICH.md)
```

Nächste Schritte, in dieser Reihenfolge:

1. **Noahs offene Fragen zu Etappe 2** (oben) klären; jede Antwort, die das Verhalten ändert, braucht eine neue Festlegung vorab und eine
   Messung wie in `berichte/etappe2/VERBLASSEN.md` Teil A (Gates Seeds 1–80 und 81–160, Gate T im Wechsel mit 6c1741e).
2. **Etappe 3 auf Version 10:** Beobachtungsschema 3 mit Erfahrung und Plan (`docs/EXPERIMENTE.md` Abschnitt 8); Belohnung v3: mit
   `node tools/ki_fallen.mjs --kalibrieren` die Beträge für leere Treffen neu setzen und entgangenen Lohn bzw. die Rücklage am Episodenende
   zählen (sonst lohnt Dauer-Freinehmen), als neue Version in `tools/kiepisode.mjs` (`BELOHNUNGEN`) und `training/BELOHNUNG.md`, dann
   `node tools/ki_fallen.mjs --belohnung belohnung_v3` bis 8 von 8 (auf Version 10 nicht ausgeführt).
3. **Kriterien vor dem Lauf festlegen:** eine neue Fassung von `training/AUSWERTUNG_V9.md` für Version 10 schreiben und einfrieren, bevor
   trainiert wird (sollen Gründungen, Kinder und Stadtwirkung stärker zählen?). Die alte bleibt, wie sie ist.
4. **Drei Trainingsseeds:** `lokal_v9` mit `"seed"` 1, 2, 3 in `training/konfig.json` (je rund 25 min auf Version 9 gemessen), dann je Lauf
   `bash tools/auswertung.sh validierung|abschluss|export`. Wie drei Läufe zu einem Urteil zusammengehen, gehört in Schritt 3. Vorher
   Durchsatz messen, der Rechner kann anders sein. Danach `ki/policies.json` neu schreiben (`node tools/ki_liste.mjs`).
5. **Etappe 4 und 5:** echte Modelle für die Hauptfiguren (Testreihe auf Noahs Mac), Aufholen exakt oder gekennzeichnet, KI-Werkstatt,
   Stadtansichten, Parks, Verkehr.

Was nicht im Repo liegt: die Checkpoints von `v9_lokal_1` (`bester.zip` sha256 `aecd97d4c6c4a087…`, `letzter.zip` `8509b211c7239ae6…`)
und die Arbeitsordner der Sitzungen (für Etappe 2: Sicherungen, Prototypen, Gate-Ausgaben je Seed, Bildschirmfotos, Messwerkzeuge, die
die Doku nicht braucht). Die Ergebnisse stehen in `berichte/`. Wer die Policy weiter trainieren will, trainiert neu. Nachgeprüft ist, dass
ein neuer Lauf mit denselben Einstellungen dasselbe rechnet, für den Smoke-Lauf (gleiche Gewichte) und für die Normalisierung von `lokal_v9`
(gleiche Bytes), beides auf Version 9; den ganzen lokalen Lauf habe ich nicht wiederholt.
