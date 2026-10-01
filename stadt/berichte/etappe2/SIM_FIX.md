# STADT – Etappe 2: Sim-Fix nach „Sim prüfen“ (30.09.2026, 17:44–18:45 UTC)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`, Sicherung
vor den Änderungen `E/sicherung_simfix` (= Stand nach Teil F, `stadt.html` `33d726b5…`). Rohdaten `E/mess/simfix/`, Schlussmessung
`E/mess/simfix/schluss/`. Werkzeuge `E/werkzeug/simfix_*`. **Im Repo nichts geändert, nichts angelegt, nichts committet** (`git status` leer,
HEAD `6c1741e`).

**Schlussstand:** `stadt/stadt.html` sha256 `6cc9f5333a40444eaf0c558572979a844111fb27c73ccdbfac90e8f31049bf3b`, Sim-Hash `aa03039229cca193`,
`GED: 1, GED_STAERKE: 1.5`, `PLAN_RUECKLAGE: 1`; `tools/simtest.mjs` sha256 `da7b3648409e8a9549d50a7f14ae01dcee2062313bdffd5ea741e59e64bda54f`.
Geändert sind nur diese zwei Dateien (`diff -rq` gegen `sicherung_simfix`; Diffs in `mess/simfix/diff_stadt_html.txt`, `diff_simtest.txt`).

## 0. Ergebnis

- **Behoben:** alle drei Befunde „mittel“, die Fehler sind (Beobachter wirft, Haft als Wechselfolge, Test „Beitragstage“), und die drei
  kleinen, die sicher gingen (`warum` für Kinder, `warum` erklärt die gemeldete Entscheidung, Seed 37 in KALIBRIERUNG.md).
- **Nicht behoben, weil es kein Fehler ist, sondern eine Produktfrage:** „Nach einer Pleite gründet fast niemand mehr“. Nachgeprüft und
  zerlegt (Abschnitt 4.1). Das muss Noah entscheiden.
- **Nicht hier, weil es die nächste Phase ist:** memName/Version 10/Übernahme und die Wertebereichs-Prüfung beim Laden (Schritt 2).
- **Verhalten mit `R.GED = 1` geändert** (nur der Haft-Fix). Darum habe ich die Kalibrierung der Stufe 1,5 nachgemessen
  (KALIBRIERUNG.md **Teil C**). Alle Gates halten auf 1–80 und 81–160, probe8 erfüllt alle Kriterien, Gate T ist nicht langsamer
  (Median 1.700,5 ms gegen Basis 4.599 ms). Mit allen Schaltern aus rechnet die Stadt Tag für Tag wie `6c1741e`.
- **Neue Zahlen für Stufe 1,5,** die Doku und Tests ab jetzt nennen müssen: Gate 7 gewertet 64/80 (Seeds 1–80) und 47/80 (81–160),
  Z1 1,09 %, Z2 17,7 Fälle je Stadt und Tag. Vorher waren es 58/80, 49/80, 0,89 % und 14,3.

## 1. Befunde: nachgeprüft und was ich gemacht habe

| Befund (Schwere) | selbst nachgeprüft | Maßnahme |
|---|---|---|
| Beobachter wirft → Stunde bricht ab (mittel) | **stimmt.** Vorher, Seeds 1 und 7 ab Tag 150: Die Stunde bricht ab. An Tag 200 sind die Fingerabdrücke verschieden, Seed 7 hat 542 statt 569 Einwohner (`beob_fehler_vorher.txt`). | behoben (2.1) |
| Haft → Stellenverlust als schlechte Wechsel-Erfahrung, dazu Verweis „weil Wechsel“ (mittel) | **stimmt.** Im Code: `haftAntritt` → `erinnere(JOB_WEG)` → `erfFolge` → `erfLernen` setzt Erfahrung und `memVon`. Die Messung der Gegenprüfung B (508 von 6.637) lief mit genau dem Stand `dc4b652a`. | behoben (2.2) |
| `--regierung` Seed 3 „Beitragstage“ rot mit 1,5 (mittel) | **stimmt, und es ist eine Testvoraussetzung.** Nachgebaut: Kind 865 kommt an Tag 250 zur Welt. `haushalteZaehlen` zählt es erst in der Nacht. Um 23 Uhr ist `betreuer` darum −1, in der Nacht zahlt `bundesGeld` an Person 384 Betreuungsgehalt samt Beitragstag. Die Simulation rechnet richtig. | Test begründet angepasst (2.4) |
| Pleite ≈ lebenslanges Gründungsverbot (mittel) | **stimmt** (20 Seeds × 730 Tage: 1,4 % gegen 14,3 % ohne Erfahrung). Im Code verblasst `erf` nie und ändert sich nur in `erfLernen`. | **nicht geändert, Frage an Noah**, mit Zerlegung (4.1) |
| Seed 37: Bezug weicht ab (klein) | **stimmt.** Nur `GED` aus: ab Tag 451 verschieden. `GED` und `OPFER_FREI` aus: 730/730 Tage gleich. Alle drei aus: gleich (`mess/simfix/seed37/`). | KALIBRIERUNG.md B.1 (Nachtrag) und C.6 |
| memName/VERSION 9/`stat.ged` bei alten Ständen, irreführende Meldung in 6c1741e (klein) | nicht neu gemessen; es ist der geplante Inhalt von Schritt 2 | **nicht hier:** Schritt 2 (5.1) |
| Wertebereiche beim Laden nicht geprüft (klein) | nicht neu gemessen; betrifft nur von Hand veränderte Stände | **nicht hier:** `gedPruefen` in Schritt 2, Bedingungen in 5.1 |
| `warum` gibt für Kinder eine Wahl (klein) | **stimmt.** `stunde`/`tagSchritt` überspringen `P.geb[p] >= S.tag − ERWACHSEN · JAHR` | behoben (2.3) |
| `warum` erklärt nicht die getroffene Entscheidung (klein; der Vorschlag im Auftrag ist abgeschnitten) | **stimmt.** Ohne Zufallsstand weicht die Wahl in 184 von 1.810 / 181 von 1.419 / 81 von 628 Meldungen ab (Seeds 7/23/41, 200 Tage) | Simulationsteil behoben (2.3); Anzeige in Schritt 3 (5.2) |

Der Auftragstext bricht beim letzten kleinen Befund ab („vorschlag: In …“). Ob danach noch weitere Befunde kamen, weiß ich nicht. Bearbeitet
habe ich alle, die im Auftrag lesbar sind.

## 2. Änderungen im Einzelnen

### 2.1 Beobachter wirft (`stadt.html`, `andersMelden`, Export)

- `andersMelden` ruft den Beobachter in `try`/`catch`. Wirft er, wird er abgeschaltet (`BEOB.fn = null`) und der Text in `BEOB.fehler`
  gemerkt. Das liegt außerhalb von S. Die Stunde läuft zu Ende wie ohne Beobachter.
- Neu `Sim.beobachterFehler` (nur lesen). Setzt man `Sim.beobachter` neu, wird er gelöscht.
- **Geprüft** (`werkzeug/simfix_beob_fehler.mjs`, Seeds 1, 7, 23, Wurf an Tag 150): Aus `Sim.stunde` kommt kein Fehler mehr. Die Uhr und
  `S.rs` sind in jeder Stunde bis Tag 200 gleich wie im Lauf ohne Beobachter, der Fingerabdruck an Tag 200 ebenfalls
  (`schluss/beob_fehler.txt`).

### 2.2 Haft kostet die Stelle, nicht der Wechsel (`stadt.html`, `haftAntritt`, neu `erfHaft`)

- **Neu:** `erfHaft(S, p)` im Etappe-2-Teil hinter `erfFolge`. Ist ein Wechsel offen, wird er verworfen (`offen = 0`, `offRest = 0`): keine
  Erfahrung, kein Verweis. Das ist dieselbe Regel wie in `erfTag`, wenn das Ergebnis am Ende der Frist nicht mehr besteht.
- `haftAntritt` ruft `if (R.GED) erfHaft(S, p);` nach `austreten`, vor `erinnere(S, p, M.JOB_WEG, b)`. Die Erinnerung „Job verloren“ bleibt,
  bekommt aber keinen Verweis mehr auf den Wechsel (`memVon` bleibt 0, denn nur `erfLernen` setzt es).
- **Warum eine eigene Funktion:**
  - In der ersten Fassung standen die zwei Zeilen direkt in `haftAntritt`. Dann war `simtest --sicherheit` rot: Die statische Liste der
    Personenfelder je Sicherheitsregel kennt für `haftAntritt` kein `P.offen`/`P.offRest`.
  - Die Etappe-2-Buchführung gehört in den Etappe-2-Teil. So hält es auch `erinnere`/`erfFolge`, die `haftAntritt` schon vorher aufrief.
  - `harte_grenze.mjs` prüft `erfHaft` jetzt mit (Liste ergänzt). Es liest nur `offen`/`offRest`.
  - Beide Fassungen rechnen auf den Seeds 1–5 × 730 Tage Tag für Tag gleich (`mess/simfix/fix1_gegen_fix2.txt`).
- **Geprüft** (`werkzeug/simfix_wirkung.mjs`, Kopie von `pruef_b/werkzeug/wirkung.mjs` mit Haken an der neuen Stelle, 20 Seeds × 730 Tage,
  `schluss/wirkung_neu.json`):
  - Schlechte Wechsel-Erfahrungen aus einem Stellenverlust durch Haft: **0** (vorher 508).
  - 570 offene Wechsel verworfen, 791 Stellenverluste durch Haft.
- **Nicht geändert, aber gemessen** (`werkzeug/simfix_haft_andere.mjs`): 52 von 3.986 schlechten Gründungs-Erfahrungen (1,3 %) entstehen
  aus der Pleite des eigenen Betriebs, während der Besitzer in Haft ist. Ob die Haft die Pleite verursacht, habe ich nicht untersucht. Der
  Betrieb läuft laut Kommentar „ohne den Besitzer weiter“. Alle anderen Lernfälle in Haft sind 0 (bis auf eine gute Gründung).

### 2.3 `warum` (`stadt.html`)

- **Kinder:** Für `P.geb[p] >= S.tag − R.ERWACHSEN · R.JAHR` (dieselbe Grenze wie in `stunde`/`tagSchritt`) gibt `warum` nur
  `{ stunde, kind: true }` zurück. Die Karte kann dann „entscheidet noch nicht“ zeigen.
- **Die gemeldete Entscheidung erklären:**
  - Die Spur merkt sich den Zufallsstand vor der Entscheidung (`SPUR.rsVor`, nur mit Beobachter).
  - Der Beobachter bekommt ihn als 8. Argument: `fn(p, gen, tag, stunde, mit, ohne, grund, rsVor)`. Bisherige Beobachter mit 7 Argumenten
    laufen unverändert.
  - `warum(S, p, h, rs)` rechnet mit `rs` ab genau diesem Stand und stellt `S.rs` danach wieder her. Ohne `rs` ist es wie bisher eine neue
    Wahl ab dem jetzigen `S.rs` (steht jetzt im Kommentar).
  - Im Beobachter aufgerufen, erklärt `warum(S, p, stunde, rsVor)` genau die gemeldete Entscheidung: Bis zur Meldung ist in `entscheide` nur
    `S.rs` weitergelaufen, und die Probe zieht dieselben Zahlen wie die echte Wahl („echte Wahl = Probe“ in probe8).
- **Geprüft** (`werkzeug/simfix_warum.mjs`, `schluss/warum.txt`):
  - Seeds 7/23/41, 200 Tage: In allen 1.810 / 1.419 / 628 Meldungen ist `wahl` gleich der ausgeführten Aktion und `ohneBeides` gleich der
    gemeldeten „ohne“. Ohne `rs` weicht die Wahl in 184 / 181 / 81 Meldungen ab.
  - Der Fingerabdruck mit `warum` im Beobachter ist gleich dem Lauf ohne Beobachter.
  - Seed 2, Tag 300, 19 Uhr: 212 von 212 Kindern `{ kind: true }`, 906 von 906 Erwachsenen mit einer Wahl, `S.rs` unverändert.

### 2.4 Tests (`tools/simtest.mjs`), begründet angepasst, nichts gelöscht

- **`--regierung` 6a „Beitragstage über 8 Mitternächte“:**
  - Personen, deren Betreuer-Status sich über die Mitternacht ändert, werden ausgelassen und gezählt; die Zahl steht in der Zeile.
  - Grund: `bundesGeld` zahlt mit dem Stand mitten in der Nacht. Die Kinderzahl kommt aus `haushalteZaehlen` derselben Nacht, die
    Kita-Plätze erst aus `kitaTag` danach. Von außen (23 Uhr und 0 Uhr) ist dann nicht bestimmbar, was gilt. Das ist dieselbe Art Auslassung
    wie die vorhandene „im Haushalt Stelle weg“.
  - Gegen den alten Stand (`sicherung_simfix`, Seed 3) mit dem neuen Test: 0 Fehler, 5 ausgelassen, darunter der Fall 384; vorher 1 Fehler.
  - Im Schlussstand: Seeds 1/2/3 mit 3/1/4 ausgelassenen Fällen, 0 Fehlern, Betreuung 46/44/28-mal geprüft.
- **`--militaer` 4 „beschädigte Stände abgelehnt“ (im ersten Fix-Lauf rot):**
  - Der Fall „Zivil mit Verpflichtung“ sucht die erste Person mit Rolle ZIVIL. Mit dem Fix hat Seed 2 an Tag 400 keine (`tmp/simfix/zivil.mjs`:
    vorher 3, jetzt 0). Der „beschädigte“ Stand war dann unverändert und wurde zu Recht angenommen.
  - Die Wartebedingung `da` verlangt jetzt zusätzlich `zivil ≥ 1`. Das verschärft die Voraussetzung und schwächt den Test nicht ab.
  - Im alten Stand ist sie schon an Tag 400 erfüllt, dort ändert sich also nichts. Im neuen Stand ist es Tag 406 (`tmp/simfix/zivil2.mjs`).
    Danach ist `--militaer` grün, und der Fall wird mit „Bund (Dienst)“ abgelehnt.

## 3. Messungen mit dem Schlussstand

Alles steht in KALIBRIERUNG.md **Teil C**, kurz:

- **Gates, Seeds 1–80:** Gates 1, 2, 3, 5 und 6 je 80/80. Gate 4 79/80 (Seed 19, Faktor 1,17). Gate 7: 64 gewertet und bestanden, 16 nicht
  gewertet. Kein Absturz.
- **Gates, Seeds 81–160:** alle 80/80. Gate 7: 47 gewertet und bestanden, 33 nicht gewertet.
- **`simtest --gate`, Seeds 1–3:** bestanden, Gate 7 in 0 von 3 nicht gewertet.
- **probe8, Seeds 1–3:** „alle Kriterien erfüllt“. Z1 1,453 / 0,973 / 0,837 % (Mittel 1,088 %), Z2 im Mittel 17,7 je Stadt und Tag.
- **Gate T im Wechsel mit `6c1741e`:** Median 1.700,5 gegen 4.599 ms, neu/Basis 0,370. Im ersten Fix-Lauf 0,353, vorher 0,379. Nicht
  langsamer.
- **Schalter aus** (`GED`, `OPFER_FREI`, `HAFT_EROEFFNUNG`): Seeds 1–3, 730 Tage, stündlich und in Tagesschritten Tag für Tag gleich
  `6c1741e`.
- **Harte Grenze:** Die statische Prüfung ist in Ordnung (27 Entscheidungs- und Lernfunktionen, neu mit `erfHaft`). Namenstausch mit
  Stärke 1,5, Seeds 1 und 2, 200 Tage: jeden Tag alles gleich.
- **simtest_alle:** 14 von 22 Läufen mit Exit 0. Nur `--regierung` kippt, und zwar zu ok. Die 8 roten Läufe sind die bekannten Vergleiche mit
  alten Fassungen, mit derselben Zahl roter Prüfungen.
- **Rechner:** nie mehr als zwei Rechenprozesse. Gate T lief allein, fremde Rechenprozesse 0. Die Server 8000 und 11434 habe ich nicht
  angefasst.

## 4. Offen, an Noah

### 4.1 Nach einer Pleite gründet fast niemand mehr (Befund mittel, Produktfrage)

**Nachgeprüft:** Über 20 Seeds × 730 Tage gründen von den Personen mit einer Pleite danach wieder 1,4 % (Schlussstand 56 von 3.992). Mit
`R.GED = 0` sind es 14,3 % (734 von 5.148). Die Gegenprüfung B hat über 1.460 Tage 1,8 % gegen 16,3 % gemessen; das habe ich nicht
wiederholt.

**Zerlegung** (nur gemessen, am Standard nichts geändert): Varianten der Baukopie, in denen je ein Mechanismus aus ist
(`werkzeug/simfix_zerlegung.py`, `tmp/simfix/zerlegung/`; gemessen mit `simfix_wirkung.mjs`, 20 Seeds × 730 Tage; `schluss/zerlegung.txt`):

| Variante | Personen mit Pleite | danach wieder gegründet |
|---|---|---|
| `R.GED = 0` (Bezug, Gegenprüfung B) | 5.148 | 734 (**14,3 %**) |
| Standard 1,5 (Schlussstand) | 3.992 | 56 (**1,4 %**) |
| Erfahrung wirkt beim Gründen nicht (entscheide und Zielwahl; Sperre bleibt) | 3.733 | 146 (3,9 %) |
| Bremse fest 30 statt 30 × Stärke | 4.676 | 146 (3,1 %) |
| keine Wartezeit über die Sperre hinaus | 4.168 | 203 (4,9 %) |
| Rücklage nach schlechter Erfahrung nicht doppelt | 3.992 | 56 (1,4 %), **alle gemeldeten Zahlen gleich dem Standard** |
| die vier zusammen | 4.891 | 678 (13,9 %) |

- **Kein Mechanismus allein ist schuld.** Erfahrung, Bremse und Wartezeit wirken zusammen. Nimmt man je einen weg, steigt die Quote nur auf
  3–5 %; erst ohne alle vier liegt sie wieder beim Bezug.
- Die doppelte Rücklage hat in diesen 20 Seeds × 730 Tagen keine messbare Wirkung. Warum, habe ich nicht untersucht.
  - **Vermutung:** Wartezeit und Bremse halten die Leute ohnehin länger ab, als das Sparen dauert.
- **Frage an Noah:** Soll eine Pleite praktisch ein Gründungsverbot für immer sein? Falls nein, gibt es zum Beispiel diese Wege:
  - Erfahrung verblasst mit der Zeit.
  - Die Bremse wächst nicht mit der Stärke.
  - Die Wartezeit fällt weg, wenn die Rücklage steht.

  Jeder dieser Wege braucht eine neue Festlegung vorab und eine eigene Messung (Gates 1–80/81–160). Gebaut habe ich keinen.

### 4.2 Pleite während der Haft (nur gemessen)

52 von 3.986 schlechten Gründungs-Erfahrungen entstehen, während der Besitzer in Haft ist (2.2). Das ist faktisch eine Pleite. Ob sie der
Gründung oder der Haft zuzurechnen ist, ist eine Annahme, die Noah festlegen könnte. Nicht geändert.

## 5. Übergabe an die nächsten Phasen

### 5.1 Schritt 2 (Speicherformat)

Die zwei kleinen Befunde der Gegenprüfung A bleiben dort:

- VERSION 10, MIGRIERBAR mit 9, `migriereGed` (memName weg, Plätze neu verteilen, `stat.ged` anlegen), memName aus PF streichen. Test: Nach
  der Übernahme eines Stands der Version 9 nennt keine Erinnerung an Verstorbene einen Namen.
- `gedPruefen` mit diesen Bedingungen (sonst „Spielstand beschädigt“), aus dem Befund übernommen, nicht selbst gebaut:
  - `offen` 0–8; `offRest` 0 ohne offene Handlung, sonst 1…Frist;
  - ein erf-Byte mit n = 0 muss 0 sein;
  - `planSchritt` kleiner als die Zahl der Schritte, `planGrund`-Teile gültig;
  - `entA`/`entArt` im Bereich;
  - `memPos` < MEM.

### 5.2 Schritt 3 (Oberfläche)

- **Liste „Heute anders entschieden“:** Im Beobachter sofort `Sim.warum(S, p, stunde, rsVor)` aufrufen und das Ergebnis im Eintrag speichern
  (Oberflächen-Zustand, nicht in S). Dann erklärt der Knopf „Warum?“ am Eintrag genau diese Entscheidung.
- **Knopf „Warum?“ in der Personenkarte:** Ohne gespeicherten Eintrag gibt `Sim.warum(S, p)` nur „so würde X jetzt entscheiden“ und muss so
  beschriftet werden, nicht als die letzte Entscheidung.
- **Kinder:** `{ kind: true }` → „entscheidet noch nicht“.
- **Fehler des Beobachters:** `Sim.beobachterFehler` zeigen (z. B. „Liste angehalten: …“). Die Stadt rechnet trotzdem richtig weiter.

### 5.3 Schritt 4 (Tests) und Doku

- **In `simtest --gedaechtnis` aufnehmen** (Vorlagen: `werkzeug/simfix_beob_fehler.mjs`, `simfix_warum.mjs`, `simfix_wirkung.mjs`):
  - ein werfender Beobachter ergibt denselben Fingerabdruck wie keiner, und `beobachterFehler` ist gesetzt;
  - `warum(…, rsVor)` = gemeldete Wahl in jeder Meldung;
  - Kinder → `{ kind: true }`;
  - kein Lernen eines Wechsels aus einem Stellenverlust durch Haft.
- Die Anpassungen an `--regierung` und `--militaer` (2.4) gehören in die Testliste und Doku.
- Die 8 roten Vergleiche mit alten Fassungen bleiben für Schritt 4 (über alle drei Schalter aus).
- Doku und Tests nennen für Stufe 1,5 die Zahlen aus KALIBRIERUNG.md Teil C (C.7), nicht die aus Teil F.

## 6. Geprüft / nicht geprüft

- **Geprüft:** Alles in Abschnitt 3 und in Teil C, mit genau dem Schlussstand (sha256 vor jedem Abschnitt in `schluss/schluss.log`).
  Ausnahme: Den Seed-37-Tiefvergleich (C.6) habe ich mit der ersten Fix-Fassung gerechnet (Sim `c2080f5b`). Mit `GED` aus rechnet sie
  genau wie der Schlussstand, denn `erfHaft` läuft nur mit `R.GED`.
- **Nicht geprüft:**
  - Browser-Tests (`tests/alle.sh`): Für diese Phase war kein Port angegeben. Das Modul-Skript (Oberfläche) ist unverändert und benutzt
    `beobachter`/`warum` noch nicht.
  - Die Wiedergründung über 1.460 Tage mit dem Schlussstand.
  - Die Ursache für den Anstieg von Z1 in Seed 1 (0,84 → 1,45 %).
  - Warum die doppelte Rücklage nichts ändert.
  - Den Hergang in Seed 37 habe ich nicht selbst nachverfolgt (Gegenprüfung A, `pruef_a/mess/seed37/haft.txt`).
- **Selbst nachsehen, in 10 Sekunden:** `node E/werkzeug/simfix_beob_fehler.mjs E/stadt/stadt.html 1` muss „ERGEBNIS: gleich wie ohne
  Beobachter“ ausgeben. Mit `E/sicherung_simfix/stadt.html` gibt es „weicht ab“.

## 7. Dateien

- **Geändert:**
  - `E/stadt/stadt.html`: `entscheide` (rsVor), `BEOB`/`SPUR`, `andersMelden`, `warum`, neu `erfHaft`, `haftAntritt`, Export
    `beobachterFehler`;
  - `E/stadt/tools/simtest.mjs`: `--regierung` 6a, `--militaer` 4;
  - `E/KALIBRIERUNG.md`: B.1 Nachtrag, neuer Teil C.
- **Werkzeuge:**
  - geändert: `werkzeug/harte_grenze.mjs` (Liste um `erfHaft`);
  - neu: `simfix_beob_fehler.mjs`, `simfix_warum.mjs`, `simfix_wirkung.mjs`, `simfix_vergleich.mjs`, `simfix_gleich.mjs`,
    `simfix_seed37.sh`, `simfix_zerlegung.py`, `simfix_zerlegung_aus.mjs`, `simfix_haft_andere.mjs`, `simfix_schluss.sh`;
  - Hilfen: `tmp/simfix/zivil.mjs`, `zivil2.mjs`.
- **Sicherungen:** `E/sicherung_simfix/` (vor dem Fix), `tmp/simfix/stadt_fix1.html` und `simtest_fix1.mjs` (erste Fix-Fassung),
  `tmp/simfix/KALIBRIERUNG_vor_simfix.md`.
