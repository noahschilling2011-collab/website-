# STADT – Etappe 2, Schritt 0: Vorarbeiten

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

Stand 29.09.2026, 16:45 UTC. `SP` = Arbeitsordner der Sitzung (nicht im Repo).
Grundlage: Repo `<repo>`, HEAD `6c1741e`. **Im Repo ist nichts geändert, nichts angelegt, nichts committet**
(`git status` leer, vorher und nachher). Gelesen wurde dort nur, dazu `git show`.

Alle Zahlen hier sind gemessen, außer wo „gerechnet“ oder „Annahme“ steht.

## Ergebnis

- **Alle drei Vorarbeiten sind gebaut** (Abschnitt 2), und zwar im Bauort `SP/ml/e2bau/stadt`.
- **Alle Prüfungen sind grün** (Abschnitt 3):
  - `simtest_alle.sh`: **22 von 22** Läufen grün.
  - `--kita` und `--kitest` sind auf den drei Prototyp-Kopien grün. Auf der Kopie von `plaene` waren beide vorher rot.
  - **Schalter aus:** Die Stadt rechnet Tag für Tag bitgleich wie `6c1741e` (Seeds 1–3, 365 Tage, stündlich und in Tagesschritten).
  - **Schalter an:** `--gate` Seeds 1–3 ist dreimal grün, im Wechsel mit der Basis.
- **Wirkung von `R.OPFER_FREI` heute: keine** (Abschnitt 4).
  - In 20 Städten (Seeds 1–20, je 730 Tage, 1.500 Wohnungseinbrüche) traf auf `6c1741e` kein einziger Einbruch einen Vorstand in Haft.
  - Mit dem Schalter an wird kein Zug übersprungen, und alle 20 Städte bleiben 730 Tage lang bitgleich zu `6c1741e`.
  - Der Fehler tritt nur in einem anderen Verlauf auf, z. B. im Prototyp `plaene`, Seed 2, Tag 199. Und er lässt sich erzwingen: Mit
    Schalter aus trifft es den Vorstand beim 959. Einbruch, mit Schalter an in 20.000 Einbrüchen nie.
- **Zwei bestehende Tests habe ich begründet angepasst, nicht abgeschwächt.** Beide nutzten die float32-Lücke, um den Rückfall zur
  Laufzeit zu prüfen: `simtest --kipolicy` Abschnitt 7 und `tests/browser_ki.cjs` Punkt 12 (Abschnitt 2.3).
- **Nicht ausgeführt:** die Browser-Tests (Abschnitt 6).

## 1. Arbeitsort

- `SP/ml/e2bau/stadt` ist eine Kopie von `<repo>/stadt`. Kopiert wurde mit `tar` und ohne `.venv`, `ausgabe` und
  `training/laeufe`; diese drei gab es im Repo ohnehin nicht. Nach dem Kopieren war die Kopie gleich (`diff -r` leer bis auf den Link).
- `SP/ml/e2bau/stadt/.venv` ist ein Link auf `SP/ml/venv`.
- `SP/ml/e2bau/sicherung_schritt0` ist die Sicherung vor den Änderungen. Sie ist unverändert gleich `6c1741e`:
  - `stadt.html` sha256 `0b453bf1…`, genau wie im Repo;
  - sie dient auch als Basis im Gate-Wechsel.
- `SP/ml/e2bau/basis_6c1741e.html` ist `git show 6c1741e:stadt/stadt.html` (sha256 `0b453bf1…`).
- `SP/ml/e2bau/probe_{sparsam,erfahrung,plaene}` sind Kopien der drei Prototypen `SP/ml/e2/<name>/stadt`. Übertragen wurde dort **nur**
  die Fallauswahl der beiden Testfälle (Abschnitt 2.2).

## 2. Änderungen

Diffs: `mess/diff_stadt_html.txt`, `mess/diff_simtest.txt`, `mess/diff_browser_ki.txt`, `mess/diff_doku.txt`.

- **Geändert:** `stadt.html`, `tools/simtest.mjs`, `tests/browser_ki.cjs`, `README.md`, `docs/GRENZEN.md`, `ki/LIESMICH.md`.
- **Nicht angefasst:** `docs/FORTSCHRITT.md`. Das ist das Protokoll von Etappe 1; dort steht die float32-Lücke weiter als bekannt.
- **Hashes:**
  - `stadt.html` neu: sha256 `d028fab5…`.
  - Der sim-Block hat jetzt den Sim-Hash `4aeae2ba112f3d6c` (vorher `3b1a95e0e5ae9ea5`).
  - `VERSION` bleibt 9. Das Speicherformat ist unverändert, und es gibt kein neues Feld in `S`.

### 2.1 `opferWaehlen`: Ein Haushaltsvorstand in Haft ist kein Einbruchsopfer

- **Neuer Schalter in `R`:** `OPFER_FREI: 1` (Zeile 1161, im Abschnitt Sicherheit). 1 ist der Standard; 0 rechnet wie `6c1741e` und ist
  nur für Vergleiche gedacht.
- **`opferWaehlen`** (Zeile 5603 f.): Beim Wohnungseinbruch wird der Zug übersprungen, wenn der Vorstand in Haft ist:
  `if (k < 0 || (R.OPFER_FREI && P.haftBis[k]) || …) continue;`
  - Danach kommt der nächste der höchstens 12 Züge, wie bei jedem anderen übersprungenen Zug.
  - Mit `OPFER_FREI = 0` ist die Bedingung immer falsch. Der Code ist dann gleich dem alten, auch im Zufallsstrom.
- **Gelesen** werden nur `P.haftBis` und `R`. Keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein Einzugstag.
  - Die statische Prüfung in `--sicherheit` (erlaubte Felder je Regel; `opferWaehlen`: `geb, haftBis, hh, lebt, wohnung`) ist
    unverändert und grün.
- **Neuer Testfall in `simtest --sicherheit`, Abschnitt 3 m** (Zeile 2593 ff.), erzwungen nach `plaene/werkzeug/opfer_haft_basis.mjs`:
  - **Aufbau:** Die Stadt von Seed 2, Tag 300, 13 Uhr (derselbe Stand wie die übrigen erzwungenen Fälle). Der erste Vorstand mit einem
    freien anderen Erwachsenen im Haushalt kommt in Strafhaft. Ein freier Täter aus einem anderen Haushalt bricht 20.000-mal ein und ist
    nach jeder Tat wieder frei. Das Opfer liest der vorhandene Messpunkt in `tatBegehen` mit.
  - **Gegenprobe im selben Test:** Mit `R.OPFER_FREI = 0` muss es den Vorstand treffen. Grün ist der Test nur, wenn beides gilt:
    - mit Schalter aus mindestens ein Treffer;
    - mit Schalter an 0 Treffer über mindestens zehnmal so viele Einbrüche, wie der erste Treffer brauchte.
  - **Gemessen:** Vorstand Nr. 1, 20.000 Einbrüche, 0 Treffer; mit Schalter aus der erste Treffer beim 959. Einbruch.
  - Zum Vergleich: `plaene` hatte bei Tag 300, 0 Uhr, 961 gemessen.
- **README** (Abschnitt Sicherheit, „Opfer“): Ein Satz zum Vorstand in Haft und zu `R.OPFER_FREI` ist ergänzt.

### 2.2 Testfälle `--kita` (g) und `--kitest` 6: strengere Fallauswahl

Geändert ist nur die Auswahl; die Prüfungen selbst sind unverändert. In beiden Fällen gilt jetzt zusätzlich:

- **Keine Rolle beim Bund** (`P.bund` = 0) für die Person, der der Test die Stelle nimmt: `m` in (g), `pa` in 6.
  - Grund: Der Test nimmt die Stelle ohne `austreten`. Bei einem Soldaten entsteht so ein Stand, den es sonst nie gibt.
  - Genau daran ist `plaene` abgestürzt: „Spielstand beschädigt: Bund (Rolle)“.
- **Keine jüngeren oder gleich alten Geschwister** im Haushalt (`P.geb[x] >= P.geb[k]`).
  - Grund: Ein Kind unter 3 ohne Platz bringt Betreuungsgehalt („bleibt beim Kind zu Hause“) statt „kein Kita-Platz frei“. Daran ist
    `plaene` in `--kitest` gescheitert.
  - Zwillinge sind mit ausgeschlossen. Das ist etwas strenger als „jünger“, gleicht aber den Fall mit gleichem Geburtstag aus.

Die Auswahl ist nicht schwächer geworden:

- Auf der Baukopie wählen beide Tests dieselben Fälle wie vorher. Die ganze Ausgabe von `--kita` und `--kitest` ist Zeichen für Zeichen
  gleich der von `sicherung_schritt0` (`mess/basis_kita.txt` bzw. `mess/basis_kitest.txt` gegen `mess/einzeln_*.txt`).
- Übertragen wurde mit `werkzeug/testfall_patch.py`: genau diese 7 Zeilen, in jede der drei Prototyp-Kopien.

### 2.3 float32-Lücke in `Sim.KI.policyPruefen`

- **`kiPolicyPruefen`** (sim-Block, Zeile 8176 ff.) hat die neue Hilfe `endlich32(v)`: `v` ist eine endliche Zahl **und**
  `Math.fround(v)` ist endlich.
- **Geprüft werden damit** alle Gewichte und Bias sowie `clip`. Die Gründe lauten „Schicht k: Zahl über dem float32-Bereich“,
  „… Bias über dem float32-Bereich“ und „Normalisierung: clip über dem float32-Bereich“.
- **Warum auch `clip`** (nicht ausdrücklich verlangt, darum hier offen genannt): In `kiPolicyRechnen` wird die Eingabe auf ±clip begrenzt
  und dann mit `Math.fround` gerundet. Ein `clip` über dem float32-Bereich macht die Eingabe unendlich. Das ist dieselbe Lücke; echte
  Policies haben `clip` 5.
- **Grenze:** `3.4028235e38` wird angenommen. So schreibt `training/exportiere.py` den größten float32-Wert, und er rundet auf
  3.4028234663852886e38. `3.4028236e38` rundet auf unendlich und wird abgelehnt.
- **Folge (gerechnet, nicht gemessen):** Keine geprüfte Datei kann mehr überlaufen.
  - Eingaben sind höchstens 3,4e38, Gewichte und Bias ebenso.
  - Schicht 1 mit 57 Eingängen liegt damit bei höchstens ≈ 6,6e78. Jede weitere Schicht mit höchstens 512 Eingängen multipliziert mit
    ≈ 1,7e41.
  - Nach 6 Schichten sind das ≈ 1e285, also weniger als 1,8e308.
- **Kommentare** im sim-Block und im Modul-Skript (Zeile 14175 f.) sind angepasst, dazu `docs/GRENZEN.md` und `ki/LIESMICH.md`.
- **Neuer Testfall in `simtest --kipolicy`** (Abschnitt 6, Zeile 5579 ff.):
  - Fünf Dateien mit nachgerechnetem Hash, damit die Ablehnung von der Zahl kommt und nicht vom Hash: Gewicht `1e39`, Gewicht
    `−3.4028236e38`, Bias `1e39`, Gewichte `1e308` (die Datei des alten Rückfall-Tests) und `clip 1e39`.
  - Alle fünf müssen mit einem Grund abgelehnt werden, der „float32“ enthält.
  - Die Grenzdatei mit ±`3.4028235e38` in Gewicht, Bias und `clip` muss angenommen werden.
- **Gegenprobe** (`werkzeug/float32_probe.mjs`, `mess/float32_probe.txt`):
  - Die alte Fassung `6c1741e` nimmt alle fünf Dateien an; die Lücke ist also nachgewiesen.
  - Die neue lehnt alle fünf ab und nimmt die Grenzdatei an.
- **Angepasst: `simtest --kipolicy`, Abschnitt 7 (Rückfall zur Laufzeit).**
  - Der Test brauchte eine „gültige“ Datei mit Gewichten `1e308`. Die ist jetzt ungültig, und eine andere geprüfte Datei kann nicht mehr
    überlaufen (siehe oben).
  - Neu: dieselbe Policy wie vorher (verdeckte Schicht sättigt), geprüft. Danach wird die letzte Schicht im Speicher auf unendlich
    gesetzt. Das sind genau die Werte, die `Math.fround(1e308)` vorher ins Netz brachte.
  - Die Prüfung ist dieselbe: Policy aus, Grund „keine Zahl“, 40 Tage bitgleich zu Regeln. Ergebnis: „Policy: Logit warten ist keine
    Zahl“, Fingerabdruck `4bf74f8af061d3bb`.
- **Angepasst: `tests/browser_ki.cjs`, Punkt 12**, auf dieselbe Weise.
  - Dazu prüft Punkt 12 jetzt, dass die Datei mit `1e308` abgelehnt wird (Grund enthält „float32“).
  - Er bleibt eine einzige `ok`-Zeile. Die Soll-Zahl in `tests/alle.sh` ändert sich also nicht.
  - Im Browser nicht ausgeführt (Abschnitt 6). Der Ablauf ohne Oberfläche ist in `float32_probe.mjs` nachgebaut und läuft wie
    erwartet: Datei abgelehnt; nach 30 Stunden Policy aus, 1 Rückfall, Grund „Policy: Logit warten ist keine Zahl“, Stadt gleich wie
    mit Regeln.
- **Die Policy aus Etappe 1** (`ki/policy_v9_lokal_1.json`, `simVersion` 9) wird weiter angenommen: `kipolicy_datei` ist grün.
  - Sie ist aber auf den alten Sim-Hash `3b1a95e0e5ae9ea5` trainiert. Das prüft `policyPruefen` nicht; es steht nur in der Datei.
  - Mit Version 10 wird sie ohnehin abgelehnt (Entscheidung 5).

## 3. Prüfungen

| Prüfung | Befehl | Ergebnis | Rohdaten |
|---|---|---|---|
| alle simtest-Modi | `STADT_GIT=<repo> AUSGABE=… bash tools/simtest_alle.sh` (JOBS 2) | **22 von 22 grün**, 1.140 s; getestete `stadt.html` `d028fab5…` = die gelieferte | `mess/simtest_alle_1.txt`, `mess/simtest_alle_1/*.txt` |
| darin: Regression gegen `09083f5` | `--kipolicy --rev 09083f5` | Seeds 1–3, **730 Tage, jeden Tag bitgleich**, mit `OPFER_FREI` an | `mess/simtest_alle_1/kipolicy.txt` |
| darin: Vergleiche mit Version 8 / 6 / `31ce452` | `--rathaus`, `--schule`, `--techfrueh`, `--wachstum`, `--migrationstest`, `--erweiterung` | grün, mit `OPFER_FREI` an. Keine Vergleichsliste musste den neuen Schalter kennen, weil er in diesen Verläufen nie greift (Abschnitt 4) | wie oben |
| Einzelläufe während der Arbeit | `--sicherheit`, `--kita`, `--kitest`, `--kipolicy` | alle grün | `mess/einzeln_*.txt` |
| `--kita`/`--kitest` auf den Prototypen, vorher | Kopie von `plaene`, ungepatcht | `--kita` Absturz „Spielstand beschädigt: Bund (Rolle)“, `--kitest` FEHL („bleibt beim Kind zu Hause“) | `mess/probe_plaene_{kita,kitest}_vorher.txt` |
| `--kita`/`--kitest` auf den Prototypen, nachher | `probe_{plaene,sparsam,erfahrung}` | **6 von 6 grün** (plaene 25 s / 16 s, sparsam 22 s / 11 s, erfahrung 24 s / 20 s) | `mess/probe_<name>_{kita,kitest}.txt` |
| Schalter AUS = `6c1741e`, stündlich | `tools/tagvergleich.mjs --a basis_6c1741e.html --b mess/stadt_opfer_aus.html --seeds 1,2,3 --tage 365` | **365 von 365 Tagen bitgleich**, je Seed | `mess/tagvergleich_aus_s1-3_t365.{txt,tsv}` |
| Schalter AUS = `6c1741e`, Tagesschritte | dasselbe mit `--tage 0 --tagschritt 365` | **365 von 365 Tagen bitgleich**, je Seed | `mess/tagvergleich_aus_tagschritt365.txt` |
| Schalter AN = `6c1741e` (zur Information) | `--b stadt.html --tage 365 --tagschritt 365` | ebenfalls bitgleich, stündlich und in Tagesschritten | `mess/tagvergleich_an_s1-3_t365.txt` |
| Gate, Schalter AN | `werkzeug/gate_wechsel.sh 3` (`--gate`, Seeds 1–3, im Wechsel mit der Basis, nur ein Prozess) | **3 von 3 grün**; die Basis ebenfalls 3 von 3; Ausgabe ohne Zeiten neu = Basis | `mess/gate_wechsel.txt`, `mess/gate_{neu,basis}_{1,2,3}.txt` |
| Namenstausch | in `--sicherheit`, `--kipolicy` und weiteren Modi | grün | wie oben |
| float32-Gegenprobe | `werkzeug/float32_probe.mjs` | alt: 5 von 5 angenommen; neu: 5 von 5 abgelehnt, Grenze angenommen | `mess/float32_probe.txt` |

**Zu `mess/stadt_opfer_aus.html`:** Das ist die Baukopie mit `OPFER_FREI: 0` statt `1` und sonst gleich (per `sed`, `diff`: eine Zeile).
Ich habe diesen Weg gewählt, weil `tagvergleich.mjs` keine Schalter setzen kann.

## 4. Wirkung von `R.OPFER_FREI` (Schalter an)

Werkzeug `werkzeug/opfer_wirkung.mjs`, Ergebnis in `mess/opfer_wirkung_an_s1-20_t730.txt` (746 s).

- **Aufbau:** Je Seed laufen zwei Städte stündlich nebeneinander, `6c1741e` und die Baukopie mit Schalter an.
- **Gezählt wird** je Tat das Opfer (Messpunkt in `tatBegehen` wie in `--sicherheit`) und in der Baukopie jeder Zug, den der Schalter
  überspringt. Dazu kommt der erste Tag, an dem sich die Fingerabdrücke unterscheiden.

| Seeds 1–20, je 730 Tage | `6c1741e` | Baukopie, Schalter an |
|---|---|---|
| Wohnungseinbrüche | 1.500 (61–100 je Seed) | 1.500 |
| davon Opfer = Vorstand in Haft | **0** | 0 |
| Opfer in Haft bei Diebstahl/Betrug | 0 | 0 |
| Züge, die der Schalter übersprungen hat | – | **0** |
| Städte, die sich von `6c1741e` unterscheiden | – | **0 von 20** (alle 730 Tage bitgleich) |

**Heute trifft es also in diesen 20 Städten nie einen Häftling.** Mit dem Schalter ändert sich nichts. Damit sind für die Seeds 1–20 auch
alle Gate-Werte über 730 Tage gleich wie bei `6c1741e`. Die Seeds 21–80 habe ich nicht gemessen.

**Wann es passiert:**

- **Nur in einem anderen Verlauf.** Der Prototyp `plaene` (Seeds 1–3, 730 Tage, `mess/opfer_wirkung_plaene_s1-3_t730.txt`) hat genau
  1 Treffer: Seed 2, Tag 199, 1 von 93 Einbrüchen. Das ist der Fall aus dem Bericht von `plaene`.
- **Erzwungen:** mit Schalter aus beim 959. Einbruch, mit Schalter an nie in 20.000 Einbrüchen (Abschnitt 2.1).
- **Vermutete Ursache für die Seltenheit** (nicht gemessen): Es sitzen nur wenige zugleich in Haft. `--sicherheit`, Seed 1: 288
  Haftnächte in 730 Nächten.

## 5. Gate T (Wandzeit)

**Bedingungen:**

- Gemessen 16:38–16:43 UTC, nach `simtest_alle`. Es lief immer nur ein Prozess.
- Vor jedem Lauf: kein fremder Rechenprozess über 20 %. Last (1 min) 0,95–1,27; das ist der eigene Gate-Lauf davor.
- Reihenfolge: neu–Basis, Basis–neu, neu–Basis.

| T (ms), 365 Tage | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| neu, Runden 1 / 2 / 3 | 4.444 / 4.266 / 4.435 | 4.160 / 4.214 / 4.300 | 4.570 / 4.435 / 4.707 |
| Basis `6c1741e`, Runden 1 / 2 / 3 | 4.258 / 4.432 / 4.751 | 4.234 / 4.097 / 4.703 | 4.569 / 4.357 / 4.222 |

- **Kein messbarer Unterschied:** Median über alle 9 Werte 4.435 ms (neu) zu 4.357 ms (Basis). Die Basis allein streut schon von 4.097
  bis 4.751 ms.
- In `simtest_alle` (Gate allein am Ende, Last vorher noch um 2): 4.290 / 4.032 / 4.258 ms.
- **Auffällig:** Dieselbe Basis brauchte beim Vergleich der Prototypen (`VERGLEICH.md` 1.1) nur 3.067–3.596 ms (Seed 1). Heute braucht
  sie **4.258–4.751 ms**. Die Maschine ist jetzt also langsamer; die Ursache kenne ich nicht.
  - Der Abstand zur Grenze von 5.000 ms beträgt heute nur noch 250–900 ms.
  - Für Schritt 1 (Budget „Median ≤ +10 %“) heißt das: Gegen 4,4 s gemessen wären +10 % schon ≈ 4,85 s. Gate T ist dann ein echtes
    Risiko und muss unter ruhigen Bedingungen gemessen werden.

## 6. Was ich nicht geprüft habe

- **Browser-Tests (`tests/alle.sh`, auch `browser_ki.cjs`):** nicht ausgeführt.
  - Für diesen Schritt war kein Port genannt.
  - `alle.sh` startet außerdem einen KI-Nachbau auf 11434, wenn dort nichts antwortet. 11434 darf ich nicht anfassen.
  - Die Änderung an Punkt 12 von `browser_ki.cjs` ist deshalb **im Browser ungeprüft**. Geprüft sind nur die Syntax (`node --check`) und
    derselbe Ablauf ohne Oberfläche (Abschnitt 2.3).
  - Sonst ändert sich an der Oberfläche nichts: Das Modul-Skript hat nur einen Kommentar geändert.
- **Seeds 21–80:** nicht gemessen, weder die Wirkung noch die Gates. Für die Seeds 1–20 ist die Stadt 730 Tage lang bitgleich zu
  `6c1741e`.
- **Python-Seite** (`training/exportiere.py`, `paritaet.py`): nicht geändert und nicht ausgeführt. Der Exporter schreibt float32-Werte
  (Zeile 45–50); die sind nach der neuen Prüfung immer gültig.

## 7. Hinweise für Schritt 1

- **`R.OPFER_FREI` in Vergleichen:** Muss ein Vergleich „wie `6c1741e`“ laufen, gehören beide Schalter aus, `R.GED = 0` und
  `R.OPFER_FREI = 0`.
  - Heute greift `OPFER_FREI` in keinem Testverlauf. Deshalb habe ich die Listen der Vergleiche in `simtest.mjs` (`AUS`, `--rathaus` H,
    `--schule` usw.) **nicht** erweitert.
  - Sobald Etappe 2 den Verlauf ändert (Schalter `R.GED` an), kann der Fall auftreten, wie bei `plaene`. Dann trennt `R.OPFER_FREI`
    ihn sauber ab.
- **Gate T:** Die Basis liegt heute bei 4,1–4,75 s (Abschnitt 5). Messen nur im Wechsel und bei Ruhe.
- **Sim-Hash:** Der Sim-Hash ist jetzt `4aeae2ba112f3d6c`. Die Etappe-1-Policy bleibt bis Version 10 annehmbar, ist aber auf
  `3b1a95e0e5ae9ea5` trainiert.

## 8. Dateien

**Baukopie** `SP/ml/e2bau/stadt`:

- `stadt.html`
- `tools/simtest.mjs`
- `tests/browser_ki.cjs`
- `README.md`
- `docs/GRENZEN.md`
- `ki/LIESMICH.md`

**Sicherung** `SP/ml/e2bau/sicherung_schritt0`: unverändert gleich `6c1741e`.

**Prototyp-Kopien** `SP/ml/e2bau/probe_{sparsam,erfahrung,plaene}`:

- Nur `tools/simtest.mjs` ist geändert: die Fallauswahl.
- Die alte Fassung liegt als `mess/probe_<name>_simtest_vorher.mjs`.

**Werkzeuge** `SP/ml/e2bau/werkzeug/`:

- `opfer_wirkung.mjs`: Wirkung und Tagesgleichheit.
- `float32_probe.mjs`: Gegenprobe alt/neu und Ablauf von `browser_ki` 12 ohne Browser.
- `gate_wechsel.sh`: Gate im Wechsel mit der Basis.
- `testfall_patch.py`: Übertrag der Fallauswahl.

**Messungen** `SP/ml/e2bau/mess/`: alle Rohdaten, auf die oben verwiesen wird, dazu die Diffs `diff_*.txt`.
