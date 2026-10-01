# Berichte

Ergebnisse echter Läufe, so wie sie entstanden sind (nichts nachträglich geglättet). Groß oder nur lokal nützlich und deshalb **nicht** hier:
Checkpoints (`*.zip`), `episoden.jsonl` (1 MB), Paritätsdaten (je Policy gut 1 MB). Die Policy des Laufs liegt in `ki/`.

| Ordner | Inhalt |
|---|---|
| `v9_lokal_1/` | Lauf `v9_lokal_1` auf Version 9 und seine Auswertung nach `training/AUSWERTUNG_V9.md` (Urteil: **nicht bestanden**) |
| `v9_uebertrag/` | Übertrag des KI-Teils auf Version 9: Bericht, Regression gegen 09083f5, Belohnungs-Audit, Durchsatz |
| `pruefung_2026-09-29/` | Korrekturen nach der unabhängigen Prüfung und ihre Nachprüfung aus einer frischen Kopie (Logs) |
| `etappe0/` | Bestandsaufnahme von Version 8 (Etappe 0) |
| `etappe2/` | Etappe 2 (Gedächtnis, Erfahrung und Pläne, Version 10): Noahs Entscheidungen, Entwurf, die Berichte aller Schritte und kleine Messtabellen; Übersicht in `etappe2/LIESMICH.md` |

## v9_lokal_1

| Datei | Was |
|---|---|
| `manifest.json` | Run-Manifest: Konfiguration, Code- und Sim-Hash, Schema, Seeds, Schritte, Laufzeit, Hardware, Versionen, Checkpoints (sha256), Belohnungsteile, Aktionsverteilung, PPO-Kennzahlen, Parameteränderung, Lernkurve |
| `normalisierung.json` | Normalisierung aus 128 Regel-Episoden auf Trainingsseeds (steht identisch in `ki/policy_v9_lokal_1.json`) |
| `validierung.jsonl`, `sb3_progress.csv`, `training_log.txt` | Validierung während des Trainings, PPO-Kennzahlen je Update, Ausgabe des Trainings |
| `export_*.txt`, `val_*.md/json`, `val_stadt_*`, `kandidatenwahl.txt` | Kandidatenwahl auf den Validierungsseeds 20016–20031 |
| `abschluss.md/json`, `abschluss_stadt.*`, `abschluss_stderr.txt` | Abschluss auf 30000–30031, einmal (Laufzeit und Speicher in `abschluss_stderr.txt`) |
| `paritaet*.txt`, `kipolicy_v9_lokal_1.txt`, `ki_liste.txt` | Parität Trainer ↔ JS (644 Fälle), `simtest --kipolicy` mit dieser Policy, Aufnahme in `ki/policies.json` |

Die Pfade in diesen Dateien stammen aus dem Arbeitsordner: `ausgaben/lokal_v9/` ist hier `berichte/v9_lokal_1/`, ebenso Manifest, Normalisierung
und Validierung aus `training/laeufe/v9_lokal_1/` (`sb3/progress.csv` heißt hier `sb3_progress.csv`, `training.log` heißt `training_log.txt`).
Nachrechnen ohne Checkpoint: `node tools/kandidat_waehlen.mjs bester=berichte/v9_lokal_1/val_bester.json letzter=berichte/v9_lokal_1/val_letzter.json`.

## v9_uebertrag

`UEBERTRAG.md` ist der Arbeitsbericht zum Übertrag auf Version 9 (Schema 2, Laden aus `ki/`, Regression, Smoke-Lauf, Durchsatz, Audit).
`SP/ml/v9` darin ist der damalige Arbeitsordner; `tools/v9_regression.sh` dort entspricht hier `tools/simtest_alle.sh`, `tools/browser_ki.cjs`
entspricht `tests/browser_ki.cjs`. Dazu die Rohausgaben: `regression_status.txt` und `vergleich_ohne_zeit.txt` (20 simtest-Modi gegen 09083f5),
`tagvergleich.txt`, `gepatcht_kipolicy.txt`, `kipolicy_mit_smoke_policy.txt`, `ki_fallen.txt` und `ki_fallen_kalibrieren.txt` (Belohnungs-Audit:
Belohnung v2 besteht auf Version 9 nur 6 von 8 Prüfungen), `durchsatz.txt`, `mess_lokal_v9.txt`, `gate_zeit.txt`.

## pruefung_2026-09-29

Nachprüfung der Korrekturen vom 29.09.2026 (`docs/FORTSCHRITT.md`, Abschnitt „Korrekturen nach der Prüfung“), jeweils aus einer frischen
Kopie dieses Ordners (`cp -r`, außerhalb des Repos, `STADT_GIT=<repo>`). Pfade: `SP` ist der Arbeitsordner der Sitzung, `<stadt>` die Kopie.

| Datei | Was |
|---|---|
| `simtest_alle.txt` | `bash tools/simtest_alle.sh`: 22 von 22 Läufen mit Exit 0, `--gate` allein am Ende; Ausgaben ohne Zeitangaben gleich zwei früheren Läufen |
| `regression.txt` | Policy aus gegen 09083f5: `tools/tagvergleich.mjs` (Seeds 1–6) und ein Tiefvergleich des ganzen Zustands je Tag (Seeds 7, 23, 41, 150 Tage, stündlich und per Tagesschritt) |
| `smoke_kette.txt` | Smoke-Lauf (L2 1,7266), gleicher `--name` abgelehnt, Fortsetzen, Export, Parität 644/644 |
| `paritaet_v9_lokal_1.txt` | Parität der Policy in `ki/` gegen ihren Checkpoint (aus dem Arbeitsordner, sha256 `aecd97d4c6c4a087`), Neuexport mit dem neuen `exportiere.py` |
| `abbruch.txt`, `abbruch_test.sh`, `pruef_manifest.py` | Strg+C, `kill -9`, Fortsetzen, Export: Manifest passt jedes Mal zu den Dateien |
| `abbruch_vorher.txt` | Derselbe Fall mit dem Stand vor der Korrektur: Manifest „fertig“ mit 2.048 Schritten, `bester.zip` hatte 7.168, Export schrieb 1.024 |
| `import_rueckmeldung.txt` | Rückmeldung beim Datei-Import vorher und nachher: Die Meldung liegt hinter dem offenen Fenster, neu steht das Ergebnis im Fenster |
| `ki_fallen_v9_lokal_1.txt` | Belohnungs-Audit mit dem neuen Trick Dauer-Freinehmen und der Policy `v9_lokal_1` als Info: 5 von 8, Exit 1 |
| `browser_alle.txt`, `browser_ki_echt.txt`, `browser_venv.txt` | `bash tests/alle.sh` (PORT 9066, 30 von 30, 499 OK), `browser_ki` mit der echten Policy aus `ki/` (`KI_ORDNER=ki`), `otest/breit` und `browser_ki` mit aktiver `.venv` |

## etappe0

`BESTAND.md`: Ausgangsstand Version 8 (31ce452) mit Basistests, Architektur, 16 Problemen mit Beleg und dem Plan für Etappe 1–6. Pfade dort
beziehen sich auf den damaligen Arbeitsordner.

## etappe2

Berichte der Etappe 2 in der Reihenfolge der Arbeit (`ENTSCHEIDUNGEN_NOAH.md`, `VERGLEICH.md`, `SCHRITT0.md` bis `SCHRITT4.md`,
`KALIBRIERUNG.md`, `OPTIMIEREN.md`, `SIM_FIX.md`, `VERBLASSEN.md`) und unter `mess/` die Messtabellen, auf die README und `docs/` verweisen.
Bereinigt sind nur Pfade des Arbeitsordners (`SP`) und des Repos (`<repo>`); sha256 der Originale in `etappe2/quellen.sha256`. Rohdaten wie
Gate-Ausgaben je Seed, Bildschirmfotos und Sicherungen sind nicht hier. Was wo steht und welche Werkzeuge in `tools/` die Zahlen nachrechnen:
`etappe2/LIESMICH.md`.
