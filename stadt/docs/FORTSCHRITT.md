# Fortschritt (Master-Prompt vom 28.09.2026)

Stand 29.09.2026, nach den Korrekturen aus der unabhängigen Prüfung (Abschnitt unten). Grundlage: Version 9 (Commit 09083f5) plus der
KI-Teil aus Etappe 1. Mit ausgeschalteter Policy rechnet die Stadt Tag für Tag bitgleich wie 09083f5 (geprüft: Seeds 1–3 über 730 Tage,
Seeds 1–6 über 120 Tage stündlich und 60 Tagesschritte, dazu der ganze Zustand je Tag für die Seeds 7, 23 und 41 über 150 Tage). Diese
Datei ist der Einstieg für eine neue Sitzung: erst lesen, dann „Weitermachen“ unten.

## Etappen

| Etappe | Stand | Beleg |
|---|---|---|
| 0 Ausgangsstand | erledigt (auf Version 8, vor Version 9): Basistests, Architektur, 16 Probleme mit Beleg, Plan | `berichte/etappe0/BESTAND.md` |
| 1 Durchstich lernende KI | erledigt auf Version 9: Schema 2, Env-Server (JSONL), MaskablePPO-Trainer, Smoke- und lokaler Lauf, Checkpoints, Export, Parität, Laden im Browser aus `ki/`, Tests | `berichte/v9_uebertrag/UEBERTRAG.md`, `berichte/v9_lokal_1/`, `tests/browser_ki.cjs` |
| 2 Gedächtnis, Erfahrungen, Pläne | nicht begonnen | – |
| 3 Belastbares Training | begonnen: Belohnungs-Audit (Belohnung v2 besteht es auf Version 9 nicht, 5 von 8), ein lokaler Lauf mit vorab festgelegter Auswertung (nicht bestanden). Es fehlen Belohnung v3, drei Trainingsseeds, Lehrplanstufen 2–6 | `training/BELOHNUNG.md`, `training/AUSWERTUNG_V9.md`, `berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt` |
| 4 Hauptfiguren mit echten Modellen | nicht begonnen (Ollama nur gegen einen Nachbau getestet) | README, „Bekannte Schwächen“ |
| 5 Stadtleben, Produktqualität | nicht begonnen | – |
| 6 Auslieferung | begonnen: Ordner `stadt/` mit Doku, Tests und Berichten, zweimal unabhängig geprüft, die Befunde korrigiert und aus einer frischen Kopie nachgeprüft (unten). Offen: Noahs Rückmeldung, Auslieferung einer freigegebenen Policy | dieser Ordner |

## Die 14 Punkte aus Abschnitt 16

| Nr. | Punkt | Stand | Beleg |
|---|---|---|---|
| 1 | Neue Stadt und alter Stand starten | bestanden | `tests/p6migration.cjs` (Stände der Versionen 2, 4–8 im Browser übernehmen), `tests/browser_ki.cjs` (neue Stadt; Stand ohne Policy-Verweis wie 09083f5), `simtest --migrationstest`, `--speichertest` |
| 2 | Ohne Sprachmodell spielbar | bestanden | `tests/browser_ki.cjs` und die Prüfung von `docs/START.md` brechen jede Anfrage an Ollama ab und spielen weiter; simtest braucht kein Modell |
| 3 | Training nutzt denselben Kern | bestanden | `tools/simkern.mjs` lädt den sim-Block aus `stadt.html`; Sim-Hash im Manifest von `v9_lokal_1` = `3b1a95e0e5ae9ea5` = sim-Block dieser `stadt.html` (die Korrekturen vom 29.09. ändern nur die Oberfläche, der sim-Block ist gleich); Python rechnet nichts nach |
| 4 | Echter Lauf hat Parameter verändert, Checkpoint ladbar | bestanden | `v9_lokal_1`: 155.648 Schritte, L2-Änderung 14,49 (`berichte/v9_lokal_1/manifest.json`); Smoke aus frischer Kopie: L2 1,7266, Checkpoint von Export, Parität und `--fortsetzen` geladen (`berichte/pruefung_2026-09-29/smoke_kette.txt`) |
| 5 | Export stimmt mit Trainer überein | bestanden | Parität 644/644, Logits ≤ 9,58e-7, am 29.09. aus frischer Kopie gegen den Checkpoint von `v9_lokal_1` neu gerechnet (`berichte/pruefung_2026-09-29/paritaet_v9_lokal_1.txt`); Smoke 644/644, ≤ 6,23e-8; Neuexport mit dem korrigierten `exportiere.py` gibt denselben Inhalts-Hash `28385759bed1db02` |
| 6 | Qualität gegen Regeln auf getrennten Daten gemessen | bestanden (die Messung); die Policy selbst fällt durch | Kriterien vorab (`training/AUSWERTUNG_V9_vorab.md`, sha256 in `.sha256`, Teil A unverändert), Kandidatenwahl auf 20016–20031, Abschluss einmal auf 30000–30031: Hauptmetrik 5/5 Gruppen besser, Nebenprüfungen 16/26 → nicht bestanden (`berichte/v9_lokal_1/abschluss.md`) |
| 7 | Standard nur mit geprüftem Kandidaten | bestanden | Regeln sind Standard, `stadt.html` enthält keine Policy (`tests/browser_ki.cjs` prüft das), Policy-Status „experimentell“; das Fenster zeigt jetzt das Urteil der Datei („Auswertung laut Datei: nicht bestanden“) und die gemessene Stadtwirkung |
| 8 | Erinnerungen und Pläne verändern nachweisbar spätere Entscheidungen | nicht ausgeführt | Etappe 2 |
| 9 | Ungültige oder veraltete KI-Antworten beschädigen nichts | bestanden für die Policy und das nachgebaute Sprachmodell; mit echtem Modell nicht ausgeführt | `tests/browser_ki.cjs` (beschädigte, fremde, Version-8-Dateien, abgeschnittenes JSON, falscher Hash, NaN, Rückfall zur Laufzeit), `simtest --kipolicy` (beschädigte Dateien, Rückfall), `simtest --kitest`, `tests/t1_xss.cjs`, `tests/p4test.cjs` (späte Antworten, Ausfall). Bekannte Lücke: Zahlen über dem float32-Bereich gelten als gültig (`docs/GRENZEN.md`) |
| 10 | Wiederholung, Speicherung, Migration mit definierter Semantik | Speichern und Migration bestanden; Aufholen und Replay nicht ausgeführt | Speichertest bitgleich (`ca60551e5b316d33`), Speichern und Laden mitten am Tag mit Policy bitgleich (`--kipolicy`), Migration 2–8; Aufholen in Stücken ist eine ungekennzeichnete Näherung (`berichte/etappe0/BESTAND.md` Abschnitt 5, Optionen A/B offen), kein Ereignisprotokoll mit Replay |
| 11 | Browsertests aus dem Repo reproduzierbar | bestanden | `bash tests/alle.sh` aus einer frischen Kopie mit relativen Pfaden: 30 von 30 grün, 499 OK-Prüfungen (unten, `berichte/pruefung_2026-09-29/browser_alle.txt`) |
| 12 | Leistungsaussagen mit Messumgebung | bestanden für Umgebung, Training und Simulation; Bildrate mit Policy nicht ausgeführt | Durchsatz 332/226/111 Schritte/s mit Rechner und Last (`berichte/v9_uebertrag/durchsatz.txt`, Manifest `hardware`), Zeit-Gate T gepatcht 2.523 ms gegen 2.626 ms (`gate_zeit.txt`) |
| 13 | Zentrale Schaltflächen funktionieren | bestanden, soweit die Browser-Tests klicken | 30 Browser-Tests mit echten Klicks und Tasten (Fenster, Karten, Handy, Tastatur, Hilfe, Entscheidungen, Datei laden und entfernen); kein vollständiger Durchgang von Hand |
| 14 | Doku erklärt Start, Training, Auswertung, Modellwechsel, Fortsetzung | bestanden | `docs/START.md`, `docs/EXPERIMENTE.md` (Stoppen und Fortsetzen neu beschrieben und geprüft), `docs/ARCHITEKTUR.md`, `docs/GRENZEN.md` |

## Korrekturen nach der unabhängigen Prüfung (29.09.2026)

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

## Nachprüfung aus einer frischen Kopie (29.09.2026, nach den Korrekturen)

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

## Letzte Korrekturen und Endprüfung vor dem Commit (29.09.2026)

Die Nachprüfung fand zwei kleine neue Fehler, beide behoben:
- `trainiere.py`: Das Manifest wird jetzt direkt nach `letzter.zip` geschrieben und nach der Validierung noch einmal. Vorher passte es nach
  einem `kill -9` mitten in einer Validierung nicht zu `letzter.zip`. Geprüft: `kill -9` während einer Validierung → Manifest und Datei
  3.328 Schritte, gleiche sha256. Smoke danach mit denselben Gewichten wie vorher (L2 1,7266).
- `tools/simtest_alle.sh gate` startete unter Linux zusätzlich einen leeren Lauf (GNU xargs mit leerer Liste). Jetzt 1 von 1 Läufen.

Endprüfung aus einer frischen Kopie: `simtest_alle.sh` 22 von 22 mit Exit 0, `tests/alle.sh` 30 von 30 grün (499 OK-Prüfungen, 24 min).

## Weitermachen

Zuerst prüfen, dass alles noch steht (im Ordner `stadt/` einer vollständigen Git-Kopie):

```bash
bash tools/simtest_alle.sh          # 20 Modi + --kipolicy, rund 12 min
bash tests/alle.sh                  # 30 Browser-Tests, rund 25 min (Voraussetzungen: tests/LIESMICH.md)
```

Nächste Schritte, in dieser Reihenfolge:

1. **Belohnung v3 für Version 9:** mit `node tools/ki_fallen.mjs --kalibrieren` die Beträge für leere Treffen auf Version 9 setzen und
   entgangenen Lohn bzw. die Rücklage am Episodenende zählen (sonst lohnt Dauer-Freinehmen), als neue Version in `tools/kiepisode.mjs`
   (`BELOHNUNGEN`) und `training/BELOHNUNG.md`, dann `node tools/ki_fallen.mjs --belohnung belohnung_v3` bis 8 von 8.
2. **Kriterien vor dem Lauf festlegen:** Sollen Gründungen, Kinder und Stadtwirkung stärker zählen, eine neue Fassung von
   `training/AUSWERTUNG_V9.md` schreiben und einfrieren, bevor trainiert wird. Die alte bleibt, wie sie ist.
3. **Drei Trainingsseeds:** `lokal_v9` mit `"seed"` 1, 2, 3 in `training/konfig.json` (je rund 25 min), dann je Lauf
   `bash tools/auswertung.sh validierung|abschluss|export`. Wie drei Läufe zu einem Urteil zusammengehen (jeder für sich, oder der beste
   nach Validierung), sagen die Kriterien heute nicht genau; das gehört in Schritt 2. Vorher Durchsatz messen, der Rechner kann anders sein.
4. **Etappe 2:** Gedächtnis, Erfahrungen und Pläne der Bewohner (Master-Prompt Abschnitt 4), mit eigenem Zufallsstrom und neuem
   Beobachtungsschema (Version 3). Danach Punkt 8 messen. Dabei auch die float32-Prüfung in `policyPruefen` korrigieren (der sim-Block
   ändert sich dann ohnehin, neu trainieren).
5. **Etappe 4 und 5:** echte Modelle für die Hauptfiguren (Testreihe auf Noahs Mac), Aufholen exakt oder gekennzeichnet, Personenkarte mit
   „Warum diese Entscheidung?“, KI-Werkstatt.

Was nicht im Repo liegt: die Checkpoints von `v9_lokal_1` (`bester.zip` sha256 `aecd97d4c6c4a087…`, `letzter.zip` `8509b211c7239ae6…`)
und die Arbeitsordner der Sitzungen. Die Ergebnisse stehen in `berichte/`. Wer die Policy weiter trainieren will, trainiert neu. Nachgeprüft
ist, dass ein neuer Lauf mit denselben Einstellungen dasselbe rechnet, für den Smoke-Lauf (gleiche Gewichte) und für die Normalisierung von
`lokal_v9` (gleiche Bytes); den ganzen lokalen Lauf habe ich nicht wiederholt.
