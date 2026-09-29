# Experimente: trainieren, auswerten, exportieren

Alle Befehle laufen im Ordner `stadt/`. Jeder hier steht so, wie er in einer frischen Kopie dieses Ordners gelaufen ist (Linux-Container,
4 Kerne, keine GPU, Node 22.22.2, Python 3.11.15; Zeiten gemessen, der Rechner rechnete nebenher andere Prüfungen). Ein Smoke-Lauf prüft nur
die Kette, er ist kein Qualitätsbeleg.

## 1. Einmal: eigene Python-Umgebung

Das Spiel braucht nichts davon. Fürs Training: Node 18 oder neuer, **Python 3.11 bis 3.14** (nicht 3.14.1), git. Die Grenzen kommen aus den
Paketen: numpy 2.4.6 verlangt Python ≥ 3.11, networkx 3.6.1 (eine Abhängigkeit von torch) ≥ 3.11 und nicht 3.14.1 (`Requires-Python` der
installierten Pakete; numpy-Räder gibt es auf PyPI für 3.11 bis 3.14). Mit Python 3.10 scheitert die Installation.

```bash
cd stadt
mkdir -p ausgabe                                            # Ablage für Logs und Paritätsdaten (per .gitignore nicht im Repo)
python3 -m venv .venv                                       # eigene Umgebung im Ordner (ebenfalls nicht im Repo)
.venv/bin/python -m pip install -r training/requirements.txt
source .venv/bin/activate                                   # danach heißt Python einfach „python“
python -c "import torch, sb3_contrib; print(torch.__version__, sb3_contrib.__version__)"
```

`training/requirements.txt` nennt genau die Versionen, mit denen `v9_lokal_1` trainiert wurde (torch 2.14.0, sb3-contrib 2.9.0,
stable-baselines3 2.9.0, gymnasium 1.3.0, numpy 2.4.6). Auf Linux kommt torch als CPU-Paket aus dem Index von PyTorch. In einer frischen
Umgebung installiert ergibt das dieselbe `pip freeze`-Liste wie die Umgebung, mit der trainiert wurde (hier geprüft).

**Mac:** dieselben Befehle. Auf dem Mac nimmt die Datei das normale torch 2.14.0 von PyPI (es gibt dort kein „+cpu“); das gibt es nur
für Apple Silicon ab macOS 14 (Räder für Python 3.10 bis 3.14, laut PyPI). Zusammen mit numpy und networkx heißt das Python 3.11 bis 3.14.
Ist `python3 --version` älter als 3.11, zuerst ein neueres installieren (z. B. `brew install python@3.11`,
dann `python3.11 -m venv .venv`). Node kommt von nodejs.org oder `brew install node`. Auf einem Mac nicht geprüft.

Jeder Lauf landet in `training/laeufe/<name>/` (nicht im Repo): `manifest.json`, `normalisierung.json`, `letzter.zip`, `bester.zip`,
`episoden.jsonl`, `validierung.jsonl`, `sb3/progress.csv`.

## 2. Trainieren

| Profil | Schritte | Zeitgrenze | gemessen |
|---|---|---|---|
| `smoke` | 2.048 | 6 min | 35 s |
| `lokal_v9` | 155.648 | 26 min Training, mit `--wand-min 30` höchstens 30 min insgesamt | 25,0 min (`v9_lokal_1`) |
| `langlauf` | 3.000.000 | 600 min | nie zu Ende gelaufen (bei gut 100 Schritten/s rund 8 h) |

(`lokal` ist das ältere Profil von Version 8 mit 400.000 Schritten und 18 min Grenze.) Alle Profile: MaskablePPO, MLP 2 × 64 mit tanh,
Belohnung v2, Seed 1, Trainingsseeds 10000–10063, Validierung auf 20000 ff. (`training/konfig.json`, `training/seeds.json`).

```bash
python training/trainiere.py --profil smoke --name smoke_probe
python training/trainiere.py --profil lokal_v9 --name lokal_2 --wand-min 30
nohup python training/trainiere.py --profil langlauf --name lang_1 > ausgabe/lang_1.log 2>&1 &   # läuft weiter, wenn das Terminal zugeht
echo $! > ausgabe/lang_1.pid                                                                       # zum Stoppen (Abschnitt 3)
```

Jeder `--name` gilt nur einmal: Gibt es den Lauf schon, bricht `trainiere.py` mit „Lauf … gibt es schon: anderen --name wählen oder mit
--fortsetzen … weitermachen“ ab (Exit 2), bevor es etwas anlegt. Die Zeile „Training …: Ziel …“ nennt die PID des Laufs.

- Smoke: endet mit `Fertig: fertig, 2048 Schritte …, Parameteränderung (L2) 1.7266`. Der Lauf ist deterministisch: dieselbe Zahl kam auch
  beim ersten Smoke-Lauf auf Version 9 heraus.
- Zum Ausprobieren eines großen Profils: `--zeit-min 1` begrenzt das Training auf eine Minute. Hier so geprüft: `lokal_v9` 176 s,
  `langlauf` 281 s insgesamt, weil davor die Normalisierung aus 128 bzw. 256 Regel-Episoden und der Regelarm auf der Validierung laufen
  (Rechner mit Last 4–7). Das Manifest steht danach auf „abgebrochen: Zeitlimit erreicht“, `--fortsetzen` geht weiter.
- Ein zweiter Trainingsseed (die Freigabe verlangt 3 Läufe): in `training/konfig.json` unter `gemeinsam` den Wert `"seed"` ändern. Mit
  unverändertem Seed und Profil wiederholt ein Lauf den alten (geprüft: Smoke mit denselben Gewichten, `lokal_v9` mit derselben
  Normalisierung wie `v9_lokal_1`).
- Nebenher mitlesen: `tail -f ausgabe/lang_1.log`, Validierung in `training/laeufe/<name>/validierung.jsonl`.
- Mac: Ein Lauf über Stunden rechnet nur, solange der Rechner nicht einschläft. Direkt nach dem Start
  `nohup caffeinate -i -w $(cat ausgabe/lang_1.pid) > /dev/null 2>&1 &` hält ihn wach, bis der Lauf endet (`-i`: kein Ruhezustand bei
  Untätigkeit, `-w`: bis dieser Prozess endet). Ein zugeklapptes MacBook schläft trotzdem ein. Auf einem Mac nicht geprüft.

## 3. Stoppen und fortsetzen

Ein Lauf hört auf, wenn sein Zeitlimit erreicht ist (Profil, `--zeit-min`, `--wand-min`; Manifest „abgebrochen: Zeitlimit erreicht“) oder
wenn man ihn stoppt:

- **Strg+C** im Terminal oder `kill <pid>` (SIGTERM; bei `nohup`: `kill $(cat ausgabe/lang_1.pid)`): Das Training hört nach dem laufenden
  Schritt auf, schreibt `letzter.zip` und das Manifest („abgebrochen: von Hand gestoppt (SIGINT)“ bzw. „(SIGTERM)“) und endet nach wenigen
  Sekunden. Die Node-Prozesse der Umgebung laufen in einer eigenen Sitzung, das Strg+C des Terminals trifft nur Python.
- Ein **zweites** Strg+C, `kill -9` oder ein Absturz brechen hart ab. Auch dann passen Manifest und Checkpoints zusammen: Nach jedem
  Rollout schreibt der Lauf `letzter.zip` und sofort das Manifest (Status „läuft“, Schritte, sha256 beider Dateien, bisher beste
  Validierung), nach einer Validierung gegebenenfalls `bester.zip` und noch einmal das Manifest, jeweils erst unter einem Nebennamen und dann
  umbenannt. Verloren geht höchstens der laufende Rollout; fällt der Abbruch in eine Validierung, fehlt zusätzlich deren Ergebnis.
- Vor dem ersten Rollout (Normalisierung, Regelarm) gibt es noch keinen Checkpoint: dann mit neuem `--name` neu starten.

Weiter geht es in jedem Fall mit:

```bash
python training/trainiere.py --fortsetzen training/laeufe/smoke_probe --zusatz 2048
```

`--fortsetzen` setzt das Manifest sofort auf „läuft“, macht ab `letzter.zip` weiter und kennt die beste Validierung bisher; `bester.zip`
ersetzt nur eine bessere. `training/exportiere.py` nimmt die Trainingsschritte aus dem Checkpoint selbst (`num_timesteps`), nicht aus dem
Manifest, und die Validierung aus dem Manifest nur, wenn sha256 und Schritte zur Datei passen (sonst aus `validierung.jsonl`).

Geprüft (29.09.2026, aus einer frischen Kopie; Skript `berichte/pruefung_2026-09-29/abbruch_test.sh`, Ergebnis `abbruch.txt` daneben):
Smoke-Lauf `smoke_probe` ab 4.096 Schritten, jeweils `--fortsetzen --zusatz 16384`. Strg+C (SIGINT an die ganze Prozessgruppe, wie im
Terminal) nach zwei Validierungen → nach 3 s „abgebrochen: von Hand gestoppt (SIGINT)“ bei 6.267 Schritten, keine Node-Prozesse übrig,
Manifest und beide Dateien gleich (Schritte und sha256). `kill -9` nach zwei weiteren Validierungen → Manifest „läuft“ mit 8.571 Schritten,
genau dem Stand beider Dateien. Danach `--fortsetzen --zusatz 2048` bis 10.619 Schritte, „fertig“: Die Validierungen bei 9.339 und 10.363
Schritten (Defizit 65,39 und 69,05) waren schlechter als der bisherige `bester` (59,50 bei 8.315) und ersetzten ihn nicht, erst 10.619
(58,14). Der Export von `bester` schreibt 10.619 Trainingsschritte. Der alte Stand vor dieser Korrektur ließ das Manifest nach Strg+C beim
Fortsetzen auf „fertig“ mit altem `bester` (1.024 Schritte), während `bester.zip` schon 7.168 Schritte hatte; der Export schrieb dann 1.024
Trainingsschritte in die Policy (`abbruch_vorher.txt`).

## 4. Auswerten

Die Kriterien stehen vorab in `training/AUSWERTUNG_V9.md` (Teil A) und werden nach Sicht auf Ergebnisse nicht geändert. Wer andere will,
schreibt vor dem nächsten Lauf eine neue Fassung.

```bash
bash tools/auswertung.sh validierung smoke_probe          # Export bester + letzter, Stadtwirkung, Vergleich auf 20016–20031, Kandidatenwahl
bash tools/auswertung.sh abschluss smoke_probe bester     # EINMAL je Lauf, nur für den gewählten Kandidaten: Abschlussseeds 30000–30031
```

Ergebnisse in `berichte/<lauf>/` (`val_*.md`, `kandidatenwahl.txt`, `abschluss.md` mit dem Urteil). `abschluss` verweigert einen zweiten
Durchgang und einen nicht gewählten Kandidaten. Gemessen: `validierung` 150 s, `abschluss` 148 s, `export` 44 s. Für einen Smoke-Lauf ist
das nur eine Probe der Befehle; sein Urteil („nicht bestanden“) sagt nichts. Danach `berichte/smoke_probe/` wieder löschen (`.gitignore`
schließt `berichte/smoke_*/` aus, andere Namen nicht).

## 5. Exportieren und Parität

In einem Schritt (Export nach `ki/policy_<lauf>.json`, Parität Trainer ↔ JS, `ki/policies.json`, `simtest --kipolicy` mit der Policy):

```bash
STADT_GIT=<repo> bash tools/auswertung.sh export smoke_probe bester    # STADT_GIT nur außerhalb einer Git-Kopie nötig
```

Oder einzeln:

```bash
python training/exportiere.py --lauf training/laeufe/smoke_probe --checkpoint bester              # → ki/policy_smoke_probe_bester.json
python training/paritaet.py --lauf training/laeufe/smoke_probe --policy ki/policy_smoke_probe_bester.json --aus ausgabe/paritaet_smoke_probe.json
node tools/paritaet.mjs ki/policy_smoke_probe_bester.json ausgabe/paritaet_smoke_probe.json
node tools/ki_liste.mjs                                                                           # nimmt sie in ki/policies.json auf
```

Parität bestanden heißt: 644 Fälle (240 echte Entscheidungen, 150 künstliche, 10 nur warten, 244 Randfälle), normalisierte Eingaben gleich,
Logits höchstens 1e-4 auseinander, gleiche Aktion. Smoke-Probe hier: 644/644, Logits ≤ 6,2e-8. Die Policy im Repo (`v9_lokal_1`) hat keinen
Checkpoint im Repo; ihre Parität steht in `berichte/v9_lokal_1/paritaet.txt` (644/644, ≤ 9,6e-7).

Export und Liste ändern `ki/`. Ins Repo gehört eine Policy erst mit dokumentierter Auswertung; Smoke-Policies wieder löschen und
`node tools/ki_liste.mjs` neu laufen lassen (`.gitignore` schließt `ki/policy_smoke_*.json` aus, `ki/policies.json` aber nicht). Solange
eine Smoke-Policy in der Liste steht, ist sie alphabetisch die erste und wird beim Umschalten im Spiel gewählt.

## 6. Modell wechseln

- **Im Spiel eine andere Policy:** Datei nach `ki/` legen und `node tools/ki_liste.mjs`; im Fenster „Entscheidungen der Bewohner“ unter
  „Policy“ wählen (mit mehr als einer Datei). Oder „Policy-Datei laden …“. Standard bleiben die Regeln; eine Policy als Standard gibt es erst
  nach bestandener Auswertung, und der Weg dafür ist noch nicht gebaut.
- **Anderes Netz:** in `training/konfig.json` unter `gemeinsam` `"net_arch"` (z. B. `[32]` oder `[128, 128]`) und `"aktivierung"` (`tanh`
  oder `relu`) ändern, neu trainieren, exportieren. Spiel und Parität lesen die Schichten aus der Datei (das Spiel nimmt bis zu 6 Schichten
  mit je höchstens 512 Werten). Hier geprüft mit `[32]` und `relu` in einer eigenen Kopie: Smoke-Lauf, Export (2 Schichten, 31.680 Byte),
  Parität 644/644 (Logits ≤ 4,4e-8), `tools/auswertung.sh` mit allen drei Schritten. Danach `konfig.json` wieder zurückstellen; im Manifest
  jedes Laufs steht, mit welchem Netz er trainiert ist.
- **Anderes Sprachmodell für die Hauptfiguren:** Zahnrad → „KI für die Hauptfiguren“ → Modell (README, „Ollama für die Hauptfiguren“).

## 7. Weitere Werkzeuge

```bash
node tools/ki_fallen.mjs --policy ki/policy_v9_lokal_1.json     # Belohnungs-Audit (Tricks gegen Regeln, leere Treffen); Exit 1 = durchgefallen
node tools/ki_durchsatz.mjs --episoden 12 --seeds 10000,10001,10002,10003   # Umgebung im Prozess, Schritte/s
python training/durchsatz.py --episoden 20                      # über das Protokoll aus Python
node tools/ki_schema.mjs                                        # ki/schema_v2.json neu schreiben
bash tools/simtest_alle.sh                                      # 20 simtest-Modi + --kipolicy (Policy aus = bitgleich zu 09083f5)
git show 09083f5:stadt/stadt.html > ausgabe/stadt_09083f5.html  # Version 9 ohne KI-Teil (außerhalb einer Git-Kopie: git -C <repo> show …)
node tools/tagvergleich.mjs --a ausgabe/stadt_09083f5.html --b stadt.html --seeds 1,2,3,4,5,6 --tage 120 --tagschritt 60
```

Gemessen (Last 3–7): Audit 624 s, Exit 1 mit denselben 6 bestandenen und 2 durchgefallenen Prüfungen wie in `berichte/v9_uebertrag/ki_fallen.txt`
(seit dem 29.09.2026 mit dem Trick Dauer-Freinehmen: 5 von 8, 739 s, `berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt`); Umgebung 270 Schritte/s,
über das Protokoll 223 Schritte/s; `simtest_alle.sh` 12,5 min mit 2 Läufen gleichzeitig (22 von 22 grün); Tag für Tag Seeds 1–6 bitgleich
in 4 s.
