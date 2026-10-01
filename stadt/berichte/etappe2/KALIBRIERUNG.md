# STADT – Etappe 2: Kalibrierung der Stärke (`R.GED_STAERKE`, Noahs Entscheidung 4 „stärkere Wirkung“)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo). Baukopie `SP/ml/e2bau/stadt`, Rohdaten
`SP/ml/e2bau/mess/kalibrierung/`, Werkzeuge `SP/ml/e2bau/werkzeug/`. Im Repo wird nichts geändert.

## Teil A – Festlegung vor dem Messen

**Festgelegt am 2026-09-30 um 10:31 UTC, vor der ersten Messung dieser Phase. Teil A wird danach nicht mehr geändert.** Eine Kopie mit
sha256 liegt in `mess/kalibrierung/teilA.md` bzw. `teilA.sha256`.

**Ausgangsstand:** Baukopie nach Schritt 1 mit Noahs Entscheidung 6. Standard ist `R.PLAN_RUECKLAGE = 1` und `R.GED_STAERKE = 1`.
`stadt.html` hat sha256 `50adf8fd1de8bf03…` und Sim-Hash `5475aede423a0000`. Die Basis `6c1741e` ist `SP/ml/e2bau/sicherung_schritt0`
(sha256 `0b453bf1…`, gleich `git show 6c1741e:stadt/stadt.html`).

### A.1 Was die Stärke tut

`R.GED_STAERKE = k` ist ein Faktor auf alle Summanden aus Erfahrung und Plan:

- In `entscheide` wirkt er auf die Erfahrung beim Wechseln, Kündigen, Zusammenziehen und Gründen, auf die Rücklagen-Bremse (−k × 30) und
  auf das Sparen beim Kündigen (−k × 15).
- In `zielWaehlen` wirkt er auf die Gründungserfahrung beim Ziel „eigener Laden“.

Werte je Folge, Fristen, Lernregel, Rücklage und Wartezeit bleiben, wie sie sind. Die Stärke braucht also keine neue Annahme über Ergebnisse.

### A.2 Stufen: k = 1 · 1,5 · 2 · 3 · 4

- **1** ist der heutige Standard und der Rückfall.
- **Größenordnung:** Bei k = 1 sind die größten Summanden ±31 (Erfahrung mit 3 Beobachtungen) und −30 (Bremse). Das ist etwa so viel wie
  die Schwelle 25 oder ein Zielbonus (20–30).
- **Abstände:** Die Stufen wachsen ungefähr geometrisch (×1,5, ×1,33, ×1,5, ×1,33). Jede Stufe prüft so eine merklich stärkere Wirkung, und
  fünf Stufen bleiben bezahlbar (je Stufe 80 Seeds Gates, mit 2 Prozessen etwa 15 min).
- **Obergrenze 4:** Die Summanden reichen dann bis ±124 bzw. −120 (Bremse). Das liegt über dem ganzen Bereich der Werte aus Lage und
  Charakter der vier betroffenen Handlungen. Gerechnet aus den Formeln in `entscheide`: Gründen höchstens 95, Kündigen 100,
  Zusammenziehen 100, Wechseln 115. Schon eine schlechte Erfahrung mit 2 Beobachtungen (Kündigen: 4 × 0,75 × −20 = −60) entscheidet dann
  fast allein. Ein größeres k kann den Anteil kaum weiter heben, würde aber die Gates weiter belasten.
  - **Annahme:** Die Wirkung steigt mit k und flacht oben ab. Gemessen wird es.
- **Keine Stufe unter 1**, denn Noah will eine stärkere Wirkung.
- **Weiterer Hebel „schnellere Sättigung“** (`ERF_SICHER` 0,5 / 0,75 / 1 z. B. auf 1 / 1 / 1): **nicht als eigene Stufe.**
  - Er wirkt nur auf die Erfahrung, nicht auf den Plan, und nur auf das Gewicht der ersten beiden Beobachtungen. Er geht also in dieselbe
    Richtung wie k, nur ungleichmäßig.
  - Eine zweite Achse verdoppelt die Messungen und macht „die stärkste Stufe“ mehrdeutig.
  - Er wird nicht gemessen.

### A.3 Zielgröße (je Stufe gemessen und gemeldet)

- **Z1:** Anteil der Entscheidungen, die ohne Erfahrung und Plan anders wären. Gemessen mit `werkzeug/probe8.mjs --staerke k`: Seeds 1, 2, 3,
  je 730 Tage, stündlich, mit Kontrollläufen. Gemeldet je Seed und als Mittel der drei.
- **Z2:** direkte Beobachter-Fälle je Stadt und Tag, also Beobachter-Meldungen / 730. Gemeldet je Seed und als Mittel.
- **Kandidat:** Eine Stufe k > 1 ist nur dann Kandidat, wenn Z1 (Mittel der Seeds 1–3) über dem Wert von Stufe 1 liegt. Sonst ist sie keine
  stärkere Wirkung.
- **Mitgemeldet, keine Auswahl:** die Punkt-8-Kriterien aus Schritt 1 (je Seed ≥ 0,3 %, davon ≥ 85 % direkt; ein Byte ≥ 99 %; echte
  Wahl = Probe; Beobachter = direkte Unterschiede; Fingerabdrücke gleich). Verletzt die gewählte Stufe eines davon, steht das ausdrücklich
  in Teil B.

### A.4 Nebenbedingungen

- **N1 Gates:** `simtest --gate` (730 Tage) auf den Seeds 1–80, ungerade und gerade in 2 Prozessen.
  - Gate 4 muss in mindestens 79 von 80 Seeds bestehen, die Gates 1, 2, 3, 5, 6 und 7 in 80 von 80; kein Absturz.
  - T wird in diesen Läufen nicht gewertet (2 Prozesse, nicht ruhig).
  - B wird nur gemeldet (laut simtest „kein Spec-Gate“).
- **N2 Gate T:** Seed 1, `simtest --gate --seeds 1`, 4 Runden.
  - Jede Runde rechnet die Basis `6c1741e` und alle 5 Stufen; die Reihenfolge wird je Runde verschoben.
  - Es läuft immer nur ein Prozess und sonst kein Rechenprozess. Vor jedem Lauf werden Uhrzeit, uptime und fremde Rechenprozesse notiert.
  - Bedingung: Median T(k) / Median T(Basis) − 1 ≤ +10 %.
- **N3 kleinstes Budget ≥ 0 auf allen Seeds 1–80.** Das ist Gate 3 aus N1 und steht hier nur der Vollständigkeit halber.
- **N4 Charakterabstände:** `werkzeug/folgen.mjs neu 1-20 730 k` gegen `aus` (Seeds 1–20). Alle 7 Abstände müssen im Mittel über die 20
  Seeds dasselbe Vorzeichen haben wie bei „aus“:
  - Gründung/Ehrgeiz, sonstige Kündigung/Fleiß, Elternzeit-Kündigung/Fleiß;
  - Wegzug/Heimat, Partnersuche/Geselligkeit, Stellensuche/Fleiß, Wechsel/Ehrgeiz.
- **Gemeldet, keine Bedingung:**
  - **Wirtschaft gepaart gegen `R.GED = 0`:** eine Kopie der Baukopie, in der nur `GED: 0` gesetzt ist, sonst alles Standard. Einwohner,
    Kasse (Budget) und Gründungen an Tag 365 und 730, Seeds 1–80, aus den Gate-Ausgaben; als Mittel ± Standardfehler und in Prozent.
  - Die 20-Seed-Muster gegen „aus“: Wiedergründung nach einer Pleite, Kündigungen nach Art.
  - Gate 4 größter Faktor und kleinstes Budget über die 80 Seeds, Gate B.
  - Personentage von Seed 1 in 365 Tagen (`zeit.mjs`); die Zahl hängt nicht vom Rechner ab.
  - T absolut.

### A.5 Auswahlregel

1. Gewählt wird die stärkste Kandidat-Stufe (größtes k, A.3), die N1–N4 auf den Seeds 1–80 erfüllt.
2. Diese Stufe wird **einmal** auf den Seeds 81–160 bestätigt: `simtest --gate` wie in N1, also Gate 4 ≥ 79 von 80, die Gates 1, 2, 3, 5, 6
   und 7 je 80 von 80, kein Absturz.
3. Fällt die Bestätigung durch, wird die nächstschwächere Stufe, die auf 1–80 bestanden hat, ebenso bestätigt. Es gibt höchstens zwei
   Bestätigungen.
4. Besteht keine Stufe über 1 (oder keine Bestätigung), **bleibt der Standard 1**. Das wird ehrlich gemeldet, mit dem Grund je Stufe.
5. Die Schwellen der Gates werden nicht geändert, keine Seeds ausgelassen, keine Stufe nachträglich ergänzt.
6. Ein Absturz der Simulation zählt als „N1 nicht erfüllt“. Ein Fehler in einem Messwerkzeug wird am Werkzeug behoben (nicht an der
   Simulation) und die Messung wiederholt, höchstens zweimal.

### A.6 Was vorher schon feststeht: Gate T

**Stufe 1, der heutige Standard, erfüllt N2 schon jetzt nicht.**

- Gemessen in Schritt 1: +18,5 % (4 Runden) bzw. +26,4 % (8 Runden, ruhig) gegen `6c1741e`.
- Grund: Seed 1 wird mit Entscheidung 6 größer (+24,7 % Personentage); der Code ist nicht langsamer (SCHRITT1.md, Abschnitt 0.5).
- **Folge:** Nach A.5 kann eine stärkere Stufe nur gewählt werden, wenn sie Seed 1 so klein macht, dass T wieder ≤ +10 % liegt. Die
  Bedingung wird nicht aufgeweicht.

**Zusätzlich, vorab festgelegt – nur als Entscheidungsgrundlage für Noah, wird nicht als Standard gesetzt:**

- **E1 „T gegen Stufe 1“:** Median T(k) / Median T(1) − 1, aus denselben 4 Runden wie N2; dazu die Personentage.
- **E2 „Auswahl ohne die T-Bedingung gegen `6c1741e`“:**
  - Gewählt wird die stärkste Kandidat-Stufe, die N1, N3 und N4 erfüllt und bei der E1 ≤ +10 % ist.
  - Sie wird wie in A.5 auf 81–160 bestätigt (höchstens zweimal).
  - Führen A.5 und E2 auf dieselbe Stufe, gibt es nur eine Bestätigung.

### A.7 Danach

1. Vor jeder Änderung an der Baukopie eine Sicherung `SP/ml/e2bau/sicherung_kalibrierung`.
2. Die nach A.5 gewählte Stufe wird Standard `R.GED_STAERKE` in `stadt/stadt.html`. Geändert werden nur dieser Wert und sein Kommentar; bei
   Stufe 1 ändert sich die Datei nicht.
3. Mit genau diesem Stand (sha256 notiert) werden noch einmal gemessen:
   - probe8, Seeds 1–3, 730 Tage, mit Kontrollen;
   - Gate T, 4 Runden im Wechsel mit `6c1741e` (`gate_wechsel1.sh 4 1`, allein);
   - `simtest --gate` (Seeds 1, 2, 3).
4. Ändert sich der Standard, prüfe ich zusätzlich, dass „Schalter aus“ weiter Tag für Tag gleich `6c1741e` rechnet (`aus_gleich.mjs`,
   Seeds 1–3, 730 Tage).

### A.8 Rechner

- Höchstens zwei Rechenprozesse gleichzeitig: eine Warteschlange mit 2 Plätzen.
- Gate T läuft allein.
- Last und fremde Rechenprozesse werden vor jedem Abschnitt notiert. Die Server auf 8000 und 11434 werden nicht angefasst.

## Teil B – Ergebnisse

Stand 30.09.2026, 13:15 UTC. Messungen 10:33–13:09 UTC. Alle Zahlen sind gemessen, außer wo „gerechnet“ oder „Vermutung“ steht.
Rohdaten liegen in `mess/kalibrierung/`; die Gesamtauswertung ist `tabelle_nach_bestaetigung.txt` (erzeugt mit `werkzeug/kal_tabelle.mjs`).
Teil A ist unverändert; sein sha256 `11482f4f…` wurde nach dem Schreiben von Teil B noch einmal geprüft.

### B.0 Ergebnis

**Die Stärke bleibt 1. Keine stärkere Stufe erfüllt die Regel aus Teil A.** Die Baukopie ist unverändert: `stadt.html` hat weiter
sha256 `50adf8fd1de8bf03…`, `R.GED_STAERKE: 1`.

- **Stärkere Stufen wirken deutlich stärker.** Der Anteil anders entschiedener Entscheidungen (Z1) steigt von 0,76 % (Stufe 1) über
  0,89 % (1,5), 1,32 % (2) und 2,09 % (3) auf 2,62 % (4). Die direkten Beobachter-Fälle (Z2) steigen von 12 auf 44 je Stadt und Tag.
- **Alle Stufen scheitern an Gate T (N2), auch Stufe 1.** Gegen `6c1741e` liegen sie zwischen +13,6 % und +27,8 % (erlaubt: +10 %).
- **Die Stufen 3 und 4 scheitern schon auf den Seeds 1–80 an Gate 7 (N1):** je ein Seed, und zwar Seed 35 bzw. 40.
- **Die Zusatzauswahl E2 (T gegen Stufe 1 statt gegen `6c1741e`) findet ebenfalls keine Stufe.** Stufe 2 und Stufe 1,5 bestehen auf 1–80
  alles, fallen aber bei der Bestätigung auf 81–160 an Gate 7 durch. Das waren beide erlaubten Bestätigungen.
- **Ursache für Gate 7:** Je stärker die Erfahrung wirkt, desto weniger Menschen ziehen im ersten Jahr weg. Gate 7 mittelt dann über sehr
  wenige Wegzieher, und einzelne Städte kippen (B.4). An den Schwellen und am Verhalten habe ich nichts geändert.

### B.1 Tabelle je Stufe

„Bezug“ ist `R.GED = 0` in einer Kopie der Baukopie, sonst Standard. Die Wirtschaftszahlen sind gepaart über die Seeds 1–80: Mittel der
Differenz ± Standardfehler, dahinter der Anteil am Bezug.

| | **1 (Standard)** | 1,5 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| **Z1** anders ohne Erfahrung und Plan, Seeds 1 / 2 / 3 | 0,733 / 0,937 / 0,620 % | 0,838 / 1,015 / 0,825 % | 1,014 / 1,099 / 1,838 % | 1,957 / 1,881 / 2,425 % | 2,454 / 2,140 / 3,275 % |
| Z1, Mittel | **0,763 %** | **0,893 %** | **1,317 %** | **2,088 %** | **2,623 %** |
| davon direkt | 90,9 / 92,1 / 89,6 % | 92,0 / 91,1 / 90,5 % | 92,7 / 93,0 / 95,7 % | 95,6 / 95,9 / 96,3 % | 96,6 / 95,2 / 97,3 % |
| **Z2** direkte Beobachter-Fälle je Stadt und Tag (Mittel) | 11,5 / 15,0 / 9,7 (**12,1**) | 13,5 / 15,9 / 13,4 (**14,3**) | 15,9 / 16,3 / 31,9 (**21,4**) | 32,3 / 28,5 / 40,6 (**33,8**) | 40,7 / 35,7 / 56,9 (**44,5**) |
| ein Byte gelöscht → wie ohne Erfahrung | 99,83 / 99,82 / 99,82 % | 99,94 / 99,85 / 99,67 % | 99,70 / 99,88 / 99,94 % | 99,89 / 99,83 / 99,90 % | 99,94 / 99,91 / 99,91 % |
| Kontrollen (echte Wahl = Probe, Fingerabdrücke), Beobachter = direkt, Punkt 8 | ok | ok | ok | ok | ok |
| Kandidat (Z1 über Stufe 1) | – | ja | ja | ja | ja |
| **N1 Gates 1–7, Seeds 1–80** | **erfüllt** (Gate 4 80/80, alle 80/80) | **erfüllt** | **erfüllt** | **nicht:** Gate 7 79/80 (Seed 35: −7,8, n = 3) | **nicht:** Gate 7 79/80 (Seed 40: −14,5, n = 5) |
| Gate 4 größter Faktor (Bezug 1,18) | 1,14 | 1,13 | 1,14 | 1,14 | 1,14 |
| Gate 7 kleinster Abstand; Wegzieher je Stadt (Median n) | 15,0; 24 | 19,4; 18 | 18,9; 13 | 7,8; 12 | 14,5; 12 |
| **N2 Gate T**, Median (Runden) | 5.454 ms (5.567, 5.504, 5.392, 5.404) | 5.792 (6.173, 5.794, 5.790, 5.492) | 5.497,5 (5.800, 5.427, 5.533, 5.462) | 5.568,5 (5.480, 5.650, 5.729, 5.487) | 5.146,5 (5.201, 5.065, 5.092, 5.456) |
| gegen `6c1741e` (Median 4.532 ms) | **+20,3 % nicht** | **+27,8 % nicht** | **+21,3 % nicht** | **+22,9 % nicht** | **+13,6 % nicht** |
| E1 gegen Stufe 1 | 0 | +6,2 % | +0,8 % | +2,1 % | −5,6 % |
| Personentage Seed 1, 365 Tage (`6c1741e`: 154.729) | 192.937 (+24,7 %) | 201.042 (+29,9 %) | 196.349 (+26,9 %) | 199.379 (+28,9 %) | 179.073 (+15,7 %) |
| **N3** kleinstes Budget, Seeds 1–80 (Bezug 1.710) | 1.741 | 1.741 | 1.741 | 1.741 | 1.741 |
| **N4** Charakterabstände (7) mit gleichem Vorzeichen | 7 von 7 | 7 von 7 | 7 von 7 | 7 von 7 | 7 von 7 |
| Wiedergründung nach Pleite (20 Seeds; „aus“ 14,3 %) | 2,7 % | 1,4 % | 0,6 % | 0,2 % | 0,1 % |
| Kündigungen Elternzeit (aus 39.231) | 9.018 (−77 %) | 7.918 (−80 %) | 7.788 (−80 %) | 7.444 (−81 %) | 7.556 (−81 %) |
| sonstige Kündigungen (aus 10.703) | 2.074 (−81 %) | 1.837 (−83 %) | 1.667 (−84 %) | 1.736 (−84 %) | 1.986 (−81 %) |
| Einwohner Tag 365 gegen Bezug | +20 ± 9 (+1,6 %) | +28 ± 9 (+2,2 %) | +43 ± 9 (+3,4 %) | +39 ± 10 (+3,1 %) | +43 ± 9 (+3,4 %) |
| Kasse Tag 365 | −41.317 ± 11.732 (−4,0 %) | −43.749 ± 11.330 (−4,3 %) | −24.861 ± 11.783 (−2,4 %) | −47.833 ± 11.421 (−4,7 %) | −35.709 ± 10.643 (−3,5 %) |
| Gründungen bis Tag 365 | −36 ± 8 (−11,3 %) | −54 ± 9 (−17,0 %) | −72 ± 8 (−22,6 %) | −76 ± 7 (−23,9 %) | −68 ± 8 (−21,5 %) |
| Einwohner Tag 730 | +15 ± 9 (+1,0 %) | +16 ± 9 (+1,1 %) | +15 ± 8 (+1,0 %) | +43 ± 9 (+2,9 %) | +61 ± 10 (+4,2 %) |
| **Kasse Tag 730** | −129.103 ± 24.057 (**−13,6 %**) | −135.181 ± 21.665 (−14,2 %) | −170.817 ± 23.805 (**−18,0 %**) | −152.826 ± 21.509 (−16,1 %) | −127.891 ± 20.014 (−13,5 %) |
| Gründungen bis Tag 730 | −40 ± 18 (−8,0 %) | −81 ± 16 (−16,3 %) | −91 ± 17 (−18,4 %) | −96 ± 16 (−19,3 %) | −67 ± 16 (−13,5 %) |
| **Bestätigung Seeds 81–160** | zusätzlich gemessen (B.3): Gates 1–7 bestanden, Gate 4 79/80 (Seed 154: 1,17) | **nicht bestanden:** Gate 7 78/80 (Seed 103: −10,1, n = 5; Seed 154: −14,9, n = 11) | **nicht bestanden:** Gate 7 79/80 (Seed 157: −14,9, n = 6) | – | – |

**Charakterabstände im Einzelnen** (Mittel über die Seeds 1–20, 730 Tage; Handelnde minus alle Erwachsenen):

| Handlung / Merkmal | aus | 1 | 1,5 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|
| Gründung / Ehrgeiz | +19,5 | +20,3 | +19,6 | +19,5 | +19,2 | +18,6 |
| sonstige Kündigung / Fleiß | −35,6 | −33,3 | −32,3 | −31,3 | −31,8 | −31,5 |
| Elternzeit-Kündigung / Fleiß | −26,3 | −20,8 | −20,2 | −18,7 | −19,1 | −18,8 |
| Wegzug / Heimat | −26,3 | −25,3 | −26,5 | −26,3 | −26,1 | −25,0 |
| Partnersuche / Geselligkeit | +10,5 | +10,2 | +10,3 | +10,4 | +10,6 | +10,4 |
| Stellensuche / Fleiß | −18,3 | −7,5 | −6,8 | −6,2 | −6,4 | −6,2 |
| Wechsel / Ehrgeiz | +4,6 | +4,4 | +4,2 | +4,3 | +3,7 | +3,8 |

**Wie gemessen:**

- **probe8:** mit `--staerke k`, Seeds 1–3, 730 Tage, mit Kontrollläufen. Stufe 1 ist Zahl für Zahl gleich der Messung aus Schritt 1
  (`mess/ruecklage/probe8_r1.json`).
- **Gates:** `simtest --gate` auf Arbeitskopien `tmp/kal/k<k>`, in denen nur `GED_STAERKE` geändert ist
  (`werkzeug/kal_kopien.sh`). Ungerade und gerade Seeds liefen als je ein Prozess, höchstens zwei zugleich
  (`werkzeug/kal_schlange.sh`, `phase1.log`); fremde Rechenprozesse: nie.
- **folgen:** 20 Seeds, 730 Tage. Stufe 1 und „aus“ sind Zahl für Zahl gleich den Messungen aus Schritt 1.
- **Wirtschaft:** aus den Gate-Ausgaben, Zeilen Tag 365 und 730.

**Bezug `R.GED = 0` auf den Seeds 1–80:** Gate 4 79/80 (Seed 79, Faktor 1,18), alle anderen inhaltlichen Gates 80/80. Das ist derselbe
Stand wie `6c1741e` laut Bestand.

- Einwohner, Kasse und Gründungen sind in 79 von 80 Seeds gleich denen von `6c1741e` (`e2/bestand/mess/gate4_*.txt`).
- In Seed 37 weicht der Bezug nach Tag 365 ab: an Tag 730 1.631 statt 1.502 Einwohner.
- **Vermutung, nicht untersucht:** Das kommt von `R.OPFER_FREI` oder `R.HAFT_EROEFFNUNG`, die im Bezug auf Standard 1 stehen.
  - **Nachtrag 30.09. (Sim-Fix, Teil C.6), gemessen:** Es ist `R.OPFER_FREI`. Mit `GED` und `OPFER_FREI` aus rechnet Seed 37 alle 730 Tage
    gleich wie `6c1741e`, mit nur `GED` aus ab Tag 451 nicht. „Derselbe Stand wie `6c1741e`“ gilt darum nur für den Bezug mit allen drei
    Schaltern aus; der Bezug dieser Kalibrierung („`GED` aus, die Befund-Korrekturen `OPFER_FREI`/`HAFT_EROEFFNUNG` an“) weicht in Seed 37 ab.

### B.2 Auswahl nach A.5

1. Kandidaten sind die Stufen 1,5, 2, 3 und 4; alle liegen bei Z1 über Stufe 1.
2. N1 erfüllen 1,5 und 2. Die Stufen 3 und 4 fallen an Gate 7 durch, je in einem Seed.
3. N2 erfüllt keine Stufe (+13,6 % bis +27,8 % gegen `6c1741e`).
4. N3 und N4 erfüllen alle Stufen.
5. **Daher besteht keine Stufe über 1 auf den Seeds 1–80, und der Standard bleibt 1.** Eine Bestätigung nach A.5 war deshalb nicht nötig.

### B.3 Zusatzauswahl E2 und Bestätigungen auf den Seeds 81–160

- **E2 auf 1–80:** Mit E1 ≤ +10 % statt N2 bestehen die Stufen 2 und 1,5. E1 ist +0,8 % bzw. +6,2 %. Die Stufen 3 und 4 fallen weiter an
  N1 durch.
- **Bestätigung Stufe 2** (`bestaetigung/gate_k2_*.txt`): Gates 1–6 je 80/80, Gate 4 80/80, aber Gate 7 nur 79/80. Rot ist Seed 157
  (−14,9 bei n = 6, Schwelle 15). **Nicht bestanden.**
- **Bestätigung Stufe 1,5**, die nächstschwächere (`bestaetigung/gate_k1.5_*.txt`): Gate 7 nur 78/80. Rot sind Seed 103 (−10,1, n = 5) und
  Seed 154 (−14,9, n = 11). **Nicht bestanden.**
- Damit sind beide erlaubten Bestätigungen verbraucht, und auch **E2 ergibt Stufe 1**.
- **Zusätzlich, nicht vorab festgelegt** (ändert keine Auswahl): Standard 1 auf den Seeds 81–160 (`bestaetigung/gate_k1_*.txt`). Gate 4
  79/80 (Seed 154, Faktor 1,17), alle anderen Gates 1–7 80/80, kleinstes Budget 772. **Der Standard hält also auch auf 81–160.**

### B.4 Warum Gate 7 bei stärkerer Erfahrung kippt

Gate 7 vergleicht die Heimatliebe der Menschen, die bis Tag 365 weggezogen sind, mit der aller Erwachsenen. Mit steigender Stärke ziehen
weniger Menschen weg:

| über 80 Seeds (1–80) | Bezug | 1 | 1,5 | 2 | 3 | 4 |
|---|---|---|---|---|---|---|
| Wegzieher bis Tag 365, Summe | 2.543 | 1.900 | 1.454 | 1.076 | 1.008 | 1.025 |
| je Stadt: Median (kleinster Wert) | 30 (9) | 24 (9) | 18 (5) | 13 (3) | 12 (3) | 12 (5) |
| Gate 7: Median des Abstands | 25,2 | 25,4 | 26,9 | 26,7 | 26,8 | 25,3 |

- Der typische Abstand bleibt bei 25–27. Das Merkmal geht also nicht verloren; auch N4 über 20 Seeds und 730 Tage behält das Vorzeichen.
- Alle fünf roten Gate-7-Fälle haben wenige Wegzieher (n = 3, 5, 5, 6, 11). In denselben Städten waren es bei Stufe 1 10 bis 44
  (Seed 40: 10, Seed 35: 28, Seeds 103 und 154: je 21, Seed 157: 44). Mit so wenigen Personen streut der Mittelwert stark.
- Über 730 Tage und 20 Seeds sinken die Wegzüge ebenso: aus 951, Stufe 1 589, 1,5 510, 2 421, 3 372, 4 456.
- **Vermutung, nicht zerlegt:** Wer seltener kündigt und seltener eine Pleite erlebt, landet seltener im Elend, das zum Wegzug führt.

### B.5 Gate T

- **Protokoll:** 4 Runden, 12:15–12:23 UTC, jede Runde mit der Basis und allen 5 Stufen, Reihenfolge je Runde verschoben
  (`gate_t/wechsel.txt`). Immer ein Prozess; die Last über 1 Minute lag bei 0,85–1,23, fremde Rechenprozesse: 0.
- **Basis `6c1741e`:** 4.559, 4.893, 4.505 und 4.334 ms, Median 4.532 ms.
- **Stufe 1 liegt in dieser Messung bei +20,3 %.** In Schritt 1 waren es +18,5 % bzw. +26,4 %.
- **Keine Stufe kommt auf +10 %.** Am nächsten liegt Stufe 4 mit +13,6 %; dort wächst Seed 1 am wenigsten (+15,7 % Personentage), aber
  Stufe 4 scheitert an N1.
- **Die Zeit folgt der Stadtgröße.** Die Mediane stehen in derselben Reihenfolge wie die Personentage von Seed 1 (4 < 1 < 2 < 3 < 1,5).
  Das deckt sich mit Schritt 1: Die Rechenzeit je Personentag ist gleich.

### B.6 Schlussmessung mit genau dem gewählten Stand

Der gewählte Stand ist Stufe 1 und damit die unveränderte Baukopie: `stadt.html` sha256 `50adf8fd1de8bf03…`, Sim-Hash
`5475aede423a0000`, `GED_STAERKE: 1`. Das Protokoll mit sha256 vor jedem Abschnitt steht in `schluss/schluss.log`. Alles lief als ein
Prozess, fremde Rechenprozesse: 0.

- **probe8, Seeds 1–3, 730 Tage, mit Kontrollen** (`schluss/probe8_auswertung.txt`):
  - „alle Kriterien erfüllt“;
  - anders 0,733 / 0,937 / 0,620 %, davon direkt 90,9 / 92,1 / 89,6 %;
  - ein Byte 99,83 / 99,82 / 99,82 %;
  - Beobachter 8.364 / 10.962 / 7.094 = direkte Unterschiede;
  - `erg` Zahl für Zahl gleich `probe8_k1.json`.
- **Gate T, 4 Runden im Wechsel mit `6c1741e`** (`gate_wechsel1.sh 4 1`, 13:05–13:08 UTC, `schluss/gate_t/`):
  - neu 6.255, 5.882, 6.322 und 5.968 ms, Median 6.111,5 ms, 4 von 4 über 5.000;
  - Basis 4.666, 5.103, 4.846 und 4.671 ms, Median 4.758,5 ms, 1 von 4 über 5.000;
  - **+28,4 %** (je Runde gepaart ×1,29). **Gate T bleibt rot**, wie seit Schritt 1 bekannt.
- **`simtest --gate`, Seeds 1, 2, 3** (`schluss/gate.txt`): Die Gates 1–7 und B sind in allen drei Seeds grün, T ist rot (6.024 / 5.053 /
  5.312 ms). „Gate Phase 0: NICHT BESTANDEN“ kommt allein von T.
  - Seed 1 ist 1.336 Einwohner groß. Die Seeds 2 und 3 liegen am 30.09. knapp über 5.000 ms; auch die Basis lag in dieser Stunde bei
    4,7–5,1 s.

### B.7 Geändert und angelegt

- **Baukopie `stadt/`: nichts geändert** (Vergleich mit `sicherung_kalibrierung/`: gleich).
- **Im Repo nichts geändert, nichts angelegt, nichts committet:** `git status` ist leer, HEAD `6c1741e`.
- **Neue Werkzeuge** in `werkzeug/`:
  - `kal_kopien.sh`: Arbeitskopien je Stufe und `R.GED = 0`;
  - `kal_schlange.sh`: Warteschlange mit 2 Plätzen, mit Last-Protokoll;
  - `kal_gate_t.sh`: Gate T für die Basis und alle Stufen, rotierend;
  - `kal_lese.mjs`: liest die Gate-Ausgaben samt Tag 365/730;
  - `kal_tabelle.mjs`: alle Kriterien, Auswahl A.5 und E2;
  - `kal_schluss.sh`: Schlussmessung.
- **Kleine Änderungen an zwei Werkzeugen** (alte Fassungen in `tmp/probe8_vor_kal.mjs` und `tmp/zeit_vor_kal.mjs`):
  - `zeit.mjs` schreibt zusätzlich `staerke` in seine Zeile.
  - `probe8.mjs` nimmt ohne `--staerke` den Standard der Datei (vorher fest 1) und schreibt die tatsächlich benutzte Stärke. Mit
    `--staerke` rechnet es wie vorher; die Messungen dieser Phase lagen alle mit `--staerke` vor der Änderung oder mit Standard 1 danach.
- **Hinweis für einen späteren Standardwechsel:** `arbeitskopie.sh`, `gate_staerke.sh`, `aus_kopie_rot.sh` und `aus_blind.py` suchen die
  Zeile wörtlich als `GED: 1, GED_STAERKE: 1,`. Bei einem anderen Standard müssten sie angepasst werden; mit Stufe 1 ist das nicht nötig.

### B.8 Was das für Noahs Entscheidung 4 heißt (Einordnung, keine Messung)

- „Stärkere Wirkung, Gates dürfen nicht leiden“ ist mit einem **gemeinsamen** Faktor auf Erfahrung und Plan unter den heutigen Gates nicht
  erreichbar.
  - Schon 1,5 lässt Gate 7 auf 81–160 in zwei Städten kippen, weil weniger Menschen wegziehen.
  - Gate T ist unabhängig davon schon mit Stufe 1 rot (Entscheidung 6).
- Die Stufe 1 liefert heute 0,62–0,94 % der Entscheidungen (12 direkte Fälle je Stadt und Tag). Das ist der Bereich des Entwurfs
  (0,5–1 %), über den Noah mit Entscheidung 4 hinaus wollte.
- **Offene Wege, alle nicht gebaut und nicht gemessen:**
  - Die Stärke nur auf einzelne Handlungen legen, etwa auf Gründen und Wechseln, nicht auf Kündigen. Das braucht eine neue Festlegung und
    eine eigene Messung.
  - Die Sichtbarkeit (Knopf „Warum?“, Liste „Heute anders entschieden“) mit Stufe 1 bauen.
  - Gate T und Gate 7 als Befund an Noah geben. Die Schwellen bleiben, wie sie sind.

## Teil D – Festlegung vor dem Nachkalibrieren (Noahs Entscheidung 8)

**Festgelegt am 2026-09-30 um 15:47 UTC, vor jeder Rechnung und jeder neuen Auswertung dieser Phase. Teil D wird danach nicht mehr geändert.**
Eine Kopie mit sha256 liegt in `mess/nachkal/teilD.md` bzw. `teilD.sha256`. (Einen Teil C gibt es nicht; die Buchstaben folgen dem Auftrag.)

**Ausgangsstand:** Baukopie nach „Optimieren“ (OPTIMIEREN.md): `stadt.html` sha256 `0e1667c8a79e57c9…`, Sim-Hash `5eae81848b5e6552`,
`R.GED_STAERKE: 1`, `R.PLAN_RUECKLAGE: 1`. Sie rechnet laut OPTIMIEREN.md Tag für Tag bitgleich wie der Kalibrierstand `50adf8fd…`, mit dem
alle Rohdaten aus Teil B entstanden sind. Sicherung vor jeder Änderung: `SP/ml/e2bau/sicherung_nachkalibrieren` (gleich `stadt/`).

### D.1 Das neue Gate 7 (Entscheidung 8)

- Gate 7 (Tag 365: Wegzieher haben im Schnitt mindestens 15 Punkte weniger Heimatliebe als alle Erwachsenen) wird **nur gewertet, wenn bis
  Tag 365 mindestens `G7_MIN_N = 15` Menschen weggezogen sind.** `n` ist das `n` der Gate-Zeile: die Menschen, die selbst den Wegzug
  entschieden haben und deren Heimatliebe in den Schnitt eingeht (`S.stat.wegzuege`; mitziehende Partner und Kinder zählen nicht).
- Sonst gibt `simtest --gate` die Zeile `– 7  nicht gewertet: nur n Wegzieher (< 15)` aus (der Abstand wird dahinter nur gemeldet). Sie zählt
  weder als rot noch als grün, wird aber in jeder Auswertung getrennt gezählt und gemeldet („nicht gewertet: x von 80, Seeds …“).
- Gespeicherte Ausgaben alter Form werden gleich behandelt: `n < 15` → nicht gewertet, sonst gilt das gespeicherte ✓/✗ (nicht aus der
  gerundeten Zahl neu gerechnet).
- Die Schwelle 15 Punkte und alle anderen Gates bleiben unverändert.

### D.2 Stufen, Zielgrößen, Kandidaten

Wie Teil A: Stufen k = 1 · 1,5 · 2 · 3 · 4; Z1 und Z2 wie A.3; Kandidat ist eine Stufe k > 1 mit Z1 (Mittel der Seeds 1–3) über Stufe 1.
Z1 und Z2 kommen aus den gespeicherten `probe8_k<k>.json` (Teil B); sie hängen weder von Gate 7 noch vom Rechner ab.

### D.3 Nebenbedingungen

- **N1 Gates, Seeds 1–80** (`simtest --gate`, 730 Tage): Gate 4 in mindestens 79 von 80 Seeds, die Gates 1, 2, 3, 5 und 6 in 80 von 80;
  **Gate 7: kein gewerteter Seed rot** (gewertet und bestanden + nicht gewertet = 80); kein Absturz. T wird in diesen Läufen nicht gewertet,
  B nur gemeldet.
  - Daten: die gespeicherten Ausgaben `mess/kalibrierung/gate_<v>_{u,g}.txt` (v = ged0, k1, k1.5, k2, k3, k4), neu ausgewertet mit D.1.
  - **Stichprobe vor der Verwendung:** Für jede Stufe und für `R.GED = 0` rechne ich die Seeds **1, 35 und 40** neu mit dem optimierten Code
    (Arbeitskopien `tmp/nachkal/<v>`, in denen nur `GED_STAERKE` bzw. `GED` geändert ist, mit dem neuen `tools/simtest.mjs`). Alle Zeilen der
    Tabelle (Tag 30 bis 730, alle Spalten außer der Laufzeit) und alle Zahlen der Gate-Zeilen außer T müssen gleich den gespeicherten sein
    (Gate 7 nur in der neuen Schreibweise). Weicht ein Seed ab, verwende ich die gespeicherten Daten dieser Stufe nicht, sondern rechne die
    Seeds 1–80 der Stufe neu und melde das.
  - (Seeds 35 und 40 sind die zwei Seeds, in denen Gate 7 in Teil B rot war; Seed 1 ist der Seed von Gate T.)
- **N2 Gate T, echt, mit dem optimierten Code:** `simtest --gate --seeds 1` in den Arbeitskopien, 4 Runden. Jede Runde rechnet alle 5 Stufen
  (Stufe 1 ist der Vergleich) und dazu die Basis `6c1741e` (`sicherung_schritt0`, nur zur Information, Nachtrag 7); die Reihenfolge wird je
  Runde verschoben wie in `kal_gate_t.sh`. Es läuft immer nur ein Prozess und sonst kein Rechenprozess; vor jedem Lauf werden Uhrzeit, uptime
  und fremde Rechenprozesse notiert. **Bedingung: Median T(k) der 4 Runden < 5.000 ms.**
- **N3** kleinstes Budget ≥ 0 auf allen Seeds 1–80 (Gate 3 aus N1).
- **N4** Charakterabstände wie A.4, aus den gespeicherten `folgen20_*.json` (Teil B).

### D.4 Auswahlregel (wie A.5)

1. Gewählt wird die stärkste Kandidat-Stufe (größtes k), die N1–N4 auf den Seeds 1–80 erfüllt.
2. Diese Stufe wird **einmal** auf den Seeds 81–160 bestätigt: `simtest --gate` wie N1, also Gate 4 ≥ 79 von 80, die Gates 1, 2, 3, 5, 6
   je 80 von 80, Gate 7 nach D.1 ohne roten gewerteten Seed, kein Absturz.
3. Fällt die Bestätigung durch, wird die nächstschwächere Stufe, die auf 1–80 bestanden hat, ebenso bestätigt. **Höchstens zwei
   Bestätigungen.**
4. Besteht keine Stufe über 1 oder keine Bestätigung, **bleibt der Standard 1** (Rückfall), mit dem Grund je Stufe.
5. Die Schwellen der Gates werden nicht geändert, keine Seeds ausgelassen, keine Stufe nachträglich ergänzt.
6. Ein Absturz der Simulation zählt als „nicht erfüllt“. Ein Fehler in einem Messwerkzeug wird am Werkzeug behoben und die Messung wiederholt,
   höchstens zweimal.
7. **Vorhandene Bestätigungen:** Für die Stufen 1,5 und 2 liegen die Seeds 81–160 schon vor (Teil B.3, `mess/kalibrierung/bestaetigung/`).
   Erreicht die Regel eine dieser Stufen, werden diese Ausgaben mit D.1 neu ausgewertet und zählen als eine der zwei Bestätigungen von Teil D
   (vorher Stichprobe wie in N1 mit den Seeds **103, 154 und 157**). Die Bestätigungen aus Teil B zählen nicht gegen die Grenze von Teil D.
   Fehlende Bestätigungen (Stufen 3 und 4) rechne ich nur, wenn die Regel sie erreicht, in der Reihenfolge der Regel.

### D.5 Gemeldet, keine Bedingung

- Je Stufe und je Seed-Bereich: wie viele Städte Gate 7 „nicht gewertet“ haben (mit Seeds und der Verteilung von n), wie viele gewertet und
  bestanden, der kleinste gewertete Abstand.
- Gate 7 über alle Wegzieher der 80 Städte zusammen (Abstand je Stadt, gewichtet mit n), nur als Einordnung.
- Wirtschaft gepaart gegen `R.GED = 0` (Seeds 1–80, aus den gespeicherten Gate-Ausgaben): Einwohner, Kasse, Gründungen an Tag 365 und 730.
- T gegen Stufe 1 und gegen `6c1741e` aus den N2-Runden; Personentage aus Teil B.

### D.6 Was vorher schon feststeht (aus Teil B und OPTIMIEREN.md, nicht neu gerechnet)

- In Teil B waren alle fünf roten Gate-7-Fälle Städte mit n = 3, 5, 5, 6 und 11 Wegziehern, also unter 15; alle anderen Gates erfüllten
  die Stufen 1–4 auf 1–80. **Erwartet (noch nicht ausgewertet):** Mit D.1 erfüllen alle Stufen N1 auf 1–80.
- T lag mit dem optimierten Code für Stufe 1 bei 1.470 ms (Median, OPTIMIEREN.md), die Stufen lagen in Teil B zwischen −6 % und +6 % von
  Stufe 1. **Erwartet (noch nicht gemessen):** Alle Stufen erfüllen N2.
- Damit läuft die Regel **voraussichtlich auf Stufe 4 zu, falls deren Bestätigung auf 81–160 hält**; die ist noch nicht gerechnet.
- **Folge von D.1, die ich ausdrücklich melde:** In Teil B lag der Median der Wegzieher je Stadt bei Stufe 3 und 4 bei 12. Bei diesen Stufen
  wird Gate 7 also voraussichtlich in mehr als der Hälfte der Städte nicht gewertet. Das ist Noahs Regel und keine Bedingung; das Merkmal
  Wegzug/Heimat prüft weiter N4 (20 Seeds, 730 Tage).

### D.7 Danach (Teil E)

1. Die nach D.4 gewählte Stufe wird Standard `R.GED_STAERKE` in `stadt/stadt.html`; geändert werden nur dieser Wert und sein Kommentar.
2. Mit genau diesem Stand (sha256 notiert), immer nur ein Prozess:
   - probe8, Seeds 1–3, 730 Tage, mit Kontrollen (Stärke aus der Datei); muss Zahl für Zahl gleich `probe8_k<k>.json` sein;
   - `simtest --gate` (Seeds 1, 2, 3);
   - Gate T, 4 Runden im Wechsel mit `6c1741e` (`gate_wechsel1.sh 4 1`, allein).
3. Ändert sich der Standard, zusätzlich: „Schalter aus“ Tag für Tag gleich `6c1741e` (`aus_gleich.mjs`, Seeds 1–3, 730 Tage), Namenstausch
   (`harte_grenze.mjs` mit der neuen Stärke) und `simtest_alle` (verglichen mit `mess/optimieren/simtest_alle2/neu` ohne Zeitangaben; wird ein
   Test durch die gewollte Änderung rot, melde ich ihn mit Grund).
4. Gemeldet in Teil E: Wirtschaft (Kasse und Gründungen gepaart gegen `R.GED = 0`, 80 Seeds) und wie viele Städte Gate 7 „nicht gewertet“
   haben (1–80, 81–160, Seeds 1–3 der Schlussmessung).
5. Werkzeuge, die die Zeile `GED: 1, GED_STAERKE: 1,` wörtlich suchen, passe ich an jeden Wert an (nur die Suche, nicht die Wirkung).

## Teil E – Ergebnisse des Nachkalibrierens

Stand 30.09.2026, 16:12 UTC. Rechnungen 15:50–16:09 UTC, der Rechner war ruhig (kein anderer Agent; vor jedem Lauf Last und fremde
Rechenprozesse in den Logs, fremde Rechenprozesse: 0). Alle Zahlen sind gemessen, außer wo „Vermutung“ steht. Rohdaten `mess/nachkal/`,
Gesamtauswertung `mess/nachkal/tabelle_nach_bestaetigung.txt` (`werkzeug/nachkal_tabelle.mjs`). Teil D ist unverändert (sha256 `1978d313…`
= `mess/nachkal/teilD.sha256`, nach dem Schreiben von Teil E geprüft, ohne die Leerzeile vor Teil E), Teil A ebenso (`11482f4f…`).

### E.0 Ergebnis

**Neuer Standard: `R.GED_STAERKE = 4`.** Nach Regel D.4 erfüllen mit dem neuen Gate 7 alle Stufen N1–N4 auf den Seeds 1–80; die stärkste,
Stufe 4, hat ihre einzige Bestätigung auf den Seeds 81–160 bestanden. `stadt/stadt.html` hat jetzt sha256 `4af68c77056332ab…`, Sim-Hash
`f7819e60363db727`; geändert sind nur dieser Wert und sein Kommentar (Diff unten).

- **Wirkung:** 2,62 % der Entscheidungen sind ohne Erfahrung und Plan anders (Seeds 1–3: 2,454 / 2,140 / 3,275 %), gegen 0,76 % mit Stufe 1;
  44,5 direkte Beobachter-Fälle je Stadt und Tag statt 12,1.
- **Gates:** Seeds 1–80: Gates 1–6 je 80/80 (Gate 4 80/80), Gate 7 26 gewertet und alle bestanden, **54 nicht gewertet**. Seeds 81–160:
  Gate 4 79/80 (Seed 137, Faktor 1,16), die übrigen 80/80, Gate 7 25 gewertet und bestanden, **55 nicht gewertet**.
- **Gate T** (echt, optimierter Code): 1.575 ms Median (4 Runden im Wechsel mit `6c1741e`, Basis 4.602,5 ms), weit unter 5.000 ms.
- **Wichtigste Folge, ausdrücklich:** Mit Stufe 4 wird Gate 7 in etwa zwei Dritteln der Städte **nicht gewertet** (54 von 80 bzw. 55 von 80),
  weil bis Tag 365 nur 4–14 Menschen wegziehen. Das Merkmal selbst bleibt sichtbar: über alle Wegzieher gewichtet liegt der Abstand bei
  25,1 (1–80) bzw. 26,4 (81–160) Punkten, wie beim Bezug `R.GED = 0` (25,1), und N4 (20 Seeds, 730 Tage) behält das Vorzeichen (−25,0 gegen
  −26,3 ohne Erfahrung). Gate 7 prüft bei Stufe 4 aber nur noch ein Drittel der Städte.

### E.1 Entscheidung 8 umgesetzt, Leser geprüft

- **`tools/simtest.mjs`** (einzige geänderte Datei außer `stadt.html`): Konstante `G7_MIN_N = 15` mit Kommentar „Noahs Entscheidung 8“.
  Gate 7 wird nur mit `n ≥ 15` gewertet; sonst die Zeile `– 7  nicht gewertet: nur n Wegzieher (< 15); Wegzieher-Heimatliebe … (nur
  gemeldet)`, die weder rot noch grün zählt. Am Ende steht immer `Gate 7 nicht gewertet (…): x von y Seeds (…)`. Die übrigen Gates, ihre
  Schwellen und die Zeile eines gewerteten Gate 7 sind Zeichen für Zeichen wie vorher.
- **Werkzeuge:** `kal_lese.mjs` (Gate 7 nach D.1, beide Schreibweisen, `g7min`), `gate_auswertung.mjs` (jetzt auf `kal_lese.mjs`, zählt
  „nicht gewertet“ getrennt), `kal_tabelle.mjs` (`--g7min`), neu `nachkal_tabelle.mjs` (Regel D.4). `opt_gate_auswertung.mjs` zählt nur
  ✗-Zeilen und braucht keine Änderung.
- **Dieselben Zahlen gelesen** (`mess/nachkal/leser/`):
  - Alle 57 Auswertungen der gespeicherten Gate-Ausgaben (51 Dateien einzeln und je Stufe zusammen) sind mit `gate_auswertung.mjs --g7min 0`
    Byte für Byte gleich der alten Fassung; `kal_tabelle.mjs --g7min 0` gibt Byte für Byte `tabelle_nach_bestaetigung.txt` aus Teil B.
  - Feld für Feld (`nachkal_lese_pruef.mjs`): 755 Seed-Ausgaben, alle Werte (Einwohner, Budget, Faktor 4, Gründungen, Abstände 6/7, n, T,
    Tabelle Tag 365/730) und Gates 1–6, T, B gleich; Gate 7 gleich bei n ≥ 15, „nicht gewertet“ bei n < 15 (291 Fälle).
  - Aus neuen Ausgaben (neue Schreibweise) liest der Leser für 27 Stichproben-Seeds dieselben Zahlen wie aus den gespeicherten
    (`stichprobe/leser_neu_alt.txt`).

### E.2 Stichprobe: die gespeicherten Rohdaten gelten

Für jede Stufe und `R.GED = 0` die Seeds 1, 35, 40, für die Stufen 1, 1,5, 2 zusätzlich 103, 154, 157, neu gerechnet mit dem optimierten Code
(`tmp/nachkal/<v>`, nur `GED_STAERKE` bzw. `GED` geändert): **alle 27 Seeds gleich** – je 46 Zeilen (Tabelle Tag 30–730 ohne Laufzeit,
Gate-Zeilen außer T, Tech, Sicherheit, Bund, Charakter Tag 730), also auch die Einwohner an Tag 365 und 730 (`stichprobe/vergleich.txt`).
Beispiele: Stufe 4 Seed 40: 1.296 / 1.553 Einwohner, Gate 7 vorher ✗ (−14,5), jetzt „nicht gewertet“ (n = 5); Stufe 3 Seed 35:
1.231 / 1.431, vorher ✗ (−7,8), jetzt „nicht gewertet“ (n = 3).

### E.3 Tabelle je Stufe (Teil D)

Z1, Z2, N3, N4 und Wirtschaft stehen unverändert in Teil B.1; hier das, was sich mit Entscheidung 8 und dem optimierten Code ändert.

| | Bezug `GED = 0` | **1** | 1,5 | 2 | 3 | **4** |
|---|---|---|---|---|---|---|
| Kandidat (Z1 über Stufe 1; Z1 Mittel) | – | – (0,763 %) | ja (0,893 %) | ja (1,317 %) | ja (2,088 %) | ja (2,623 %) |
| **N1** Seeds 1–80 | Gate 4 79/80 | **erfüllt** | **erfüllt** | **erfüllt** | **erfüllt** | **erfüllt** |
| Gate 7 1–80: gewertet (alle bestanden) / nicht gewertet | 78 / 2 | 71 / 9 | 58 / 22 | 29 / 51 | 24 / 56 | 26 / **54** |
| davon mit n < 10 | 1 | 3 | 5 | 17 | 21 | 25 |
| Wegzieher je Stadt bis Tag 365, Median (Spanne) | 30 (9–62) | 23,5 (9–46) | 18 (5–36) | 13 (3–27) | 12 (3–27) | 12 (5–34) |
| kleinster gewerteter Abstand | 17,6 | 15,0 | 19,4 | 21,7 | 18,4 | 18,8 |
| Abstand über alle Wegzieher (gewichtet mit n) | 25,1 | 25,2 | 26,2 | 26,7 | 26,4 | 25,1 |
| **N2** Gate T, Runden (ms) | Basis `6c1741e`: 4.359, 4.253, 4.234, 4.190 | 1.441, 1.361, 1.410, 1.399 | 1.591, 1.499, 1.597, 1.674 | 1.566, 1.547, 1.556, 1.777 | 1.570, 1.639, 1.522, 1.538 | 1.443, 1.524, 1.503, 1.641 |
| Median; gegen Stufe 1; gegen `6c1741e` | 4.243,5 | **1.404,5** (erfüllt) | 1.594 (erfüllt), +13,5 %, −62,4 % | 1.561 (erfüllt), +11,1 %, −63,2 % | 1.554 (erfüllt), +10,6 %, −63,4 % | **1.513,5 (erfüllt), +7,8 %, −64,3 %** |
| N3 kleinstes Budget / N4 | 1.710 / – | 1.741 / 7 von 7 | 1.741 / 7 von 7 | 1.741 / 7 von 7 | 1.741 / 7 von 7 | 1.741 / 7 von 7 |
| **Seeds 81–160** | – | gespeichert: bestanden (Gate 4 79/80, Seed 154); Gate 7 72 / 8 | gespeichert: bestanden; Gate 7 49 / 31 | gespeichert: bestanden; Gate 7 34 / 46 | nicht gerechnet | **neu: bestanden** (Gate 4 79/80, Seed 137, 1,16); Gate 7 25 / **55** |

N2 lief 15:52–15:54 UTC allein (`mess/nachkal/gate_t/`), 4 Runden mit der Basis und allen Stufen, Reihenfolge je Runde verschoben; Last über
1 Minute 0,74–1,82 (die gemessenen Prozesse selbst), fremde Rechenprozesse 0. **Beobachtung, Ursache nicht untersucht:** Mit dem optimierten
Code rechnen alle stärkeren Stufen Seed 1 langsamer als Stufe 1 (+7,8 bis +13,5 %), obwohl Stufe 4 weniger Personentage hat (179.073 gegen
192.937, Teil B); vor der Optimierung folgte die Zeit den Personentagen.

Die gespeicherten Bestätigungen 81–160 der Stufen 1, 1,5 und 2 habe ich nur zur Information neu ausgewertet; die Regel hat sie nicht gebraucht.
Unter dem alten Gate 7 rote Seeds sind jetzt „nicht gewertet“: Stufe 2 Seed 157 (n = 6), Stufe 1,5 Seeds 103 (n = 5) und 154 (n = 11).

### E.4 Auswahl nach D.4

1. Kandidaten: 1,5, 2, 3, 4. Alle erfüllen N1, N2, N3 und N4 auf den Seeds 1–80.
2. Stärkste: **Stufe 4.** Bestätigung 1 von höchstens 2 auf den Seeds 81–160 (`mess/nachkal/bestaetigung/`, 15:55–15:57 UTC, 2 Prozesse,
   `tmp/nachkal/k4`): Gates 1, 2, 3, 5, 6 je 80/80, Gate 4 79/80 (Seed 137, Faktor 1,16), Gate 7 ohne roten gewerteten Seed (25 gewertet,
   kleinster Abstand 17,9; 55 nicht gewertet), kein Absturz, kleinstes Budget 772. **Bestanden.**
3. Damit ist Stufe 4 gewählt; Stufe 3 brauchte keine Bestätigung.

### E.5 Neuer Standard und Schlussmessung mit genau diesem Stand

Diff gegen `sicherung_nachkalibrieren/stadt.html`:

```
-  // (zusammen mit OPFER_FREI 0). GED_STAERKE: Faktor auf die Summanden aus Erfahrung und Plan in entscheide und zielWaehlen (1 = Entwurf C).
+  // (zusammen mit OPFER_FREI 0). GED_STAERKE: Faktor auf die Summanden aus Erfahrung und Plan in entscheide und zielWaehlen (1 = Entwurf C;
+  // Standard 4: die stärkste der geprüften Stufen 1–4, die alle Gates hält; Noahs Entscheidungen 4 und 8, KALIBRIERUNG.md Teil D/E).
-  GED: 1, GED_STAERKE: 1,
+  GED: 1, GED_STAERKE: 4,
```

Schlussmessung `werkzeug/kal_schluss.sh mess/nachkal/schluss` (15:59–16:01 UTC, immer ein Prozess, vor jedem Abschnitt sha256 `4af68c77…`
und `GED_STAERKE: 4` im Log):

- **probe8, Seeds 1–3, 730 Tage, mit Kontrollen** (Stärke aus der Datei): „alle Kriterien erfüllt“; `erg` **Zahl für Zahl gleich**
  `mess/kalibrierung/probe8_k4.json`. Anders 2,454 / 2,140 / 3,275 % (Mittel 2,623 %), davon direkt 96,6 / 95,2 / 97,3 %; ein Byte gelöscht →
  wie ohne Erfahrung 99,94 / 99,91 / 99,91 %; Beobachter 29.739 / 26.062 / 41.570 Meldungen = direkte Unterschiede (40,7 / 35,7 / 56,9 je
  Tag); echte Wahl = Probe, Fingerabdrücke gleich.
- **`simtest --gate` (Seeds 1, 2, 3):** „Gate Phase 0: BESTANDEN“. Gates 1–6, T und B grün in allen drei Seeds; **Gate 7 in allen drei nicht
  gewertet** (n = 14, 14, 9; Abstand −23,4, −20,3, −22,4, nur gemeldet); T 1.550 / 942 / 797 ms. Alle Zeilen ohne Wandzeiten gleich den
  gespeicherten Stufe-4-Ausgaben (`schluss/gate_gegen_k4.txt`); Einwohner Tag 365 / 730: 1.237 / 1.556, 1.299 / 1.603, 1.276 / 1.625.
- **Gate T, 4 Runden im Wechsel mit `6c1741e`** (`gate_wechsel1.sh 4 1`, 16:00–16:01 UTC): neu 1.705, 1.502, 1.570, 1.580 ms, **Median
  1.575 ms**, 4 von 4 unter 5.000; Basis 4.912, 4.529, 4.480, 4.676 ms, Median 4.602,5 ms; neu/Basis 0,342 (−65,8 %).
  Gegen den optimierten Stand mit Stufe 1 (N2-Runden, 1.404,5 ms) ist das langsamer (N2: +7,8 %); der Code ist derselbe, nur die Stadt
  entscheidet anders (siehe E.3).
- **Schalter aus** (`aus_gleich.mjs`, Seeds 1–3, 730 Tage, stündlich): Tag für Tag gleich `6c1741e` (Einwohner 1.449 / 1.509 / 1.515).
- **Harte Grenze** (`harte_grenze.mjs`, jetzt mit der Stärke der Datei): statisch keine Namen, kein Geschlecht, keine Herkunft, keine Eltern,
  kein Einzugstag; **Namenstausch mit `GED_STAERKE = 4`** Seeds 1 und 2, 200 Tage: jeden Tag alle Arrays, Einzelwerte und Statistik gleich.
- **simtest_alle:** `STADT_GIT=<repo> bash tools/simtest_alle.sh` (2 gleichzeitig, 16:03–16:09 UTC,
  `mess/nachkal/simtest_alle/neu/`), verglichen mit dem Lauf nach „Optimieren“ (`mess/optimieren/simtest_alle2/neu/`):
  - **13 von 22 Läufen mit Exit 0, dieselben wie vorher**; die 9 roten sind dieselben (die 8 erwarteten Vergleiche mit alten Fassungen und
    `--haushalt` C, SCHRITT1.md; Anpassung in Schritt 4), jeweils mit derselben Zahl roter Prüfungen.
  - Nach Prüfergebnis (`werkzeug/nachkal_status_vergleich.mjs`, `status_vergleich.txt`): **keine Prüfung kippt** zwischen ok und FEHL. Gewollt
    geändert: in `--gate` ist Gate 7 in den Seeds 1–3 „nicht gewertet“ statt ✓. `--autos` hat eine Prüfung mehr: „Faire Reihenfolge
    (natürlich, Tage mit Werk)“ wird nur ab 50 Käufen von außen gewertet (vorher 47, nur gemessen; jetzt 80, ok).
  - Sonst unterscheiden sich nur Zahlen und die Namen der Beispielpersonen, weil die Stadt anders entscheidet (ohne Zeitangaben sind 22 von
    23 Dateien verschieden, `status.txt` ist gleich).
  - **`--wachstum` D bleibt grün** (Entscheidung 6): schnell 277 gegen normal 242 Einwohner (Seed 5, Tag 150; vorher 262 gegen 209).
  - Kein Test ist angepasst oder abgeschwächt.

### E.6 Wirtschaft mit Stufe 4 (gepaart gegen `R.GED = 0`, Seeds 1–80)

Aus den gespeicherten Gate-Ausgaben (Mittel der Differenz ± Standardfehler, Anteil am Bezug; in Klammern Stufe 1 zum Vergleich):

| | Tag 365 | Tag 730 |
|---|---|---|
| **Kasse** | −35.709 ± 10.643 (−3,5 %; Stufe 1: −4,0 %) | **−127.891 ± 20.014 (−13,5 %; Stufe 1: −13,6 %)**; in 62 Städten niedriger, in 18 höher |
| **Gründungen** (bis zum Tag) | **−68 ± 8 (−21,5 %; Stufe 1: −11,3 %)**; in 68 niedriger, in 12 höher | −67 ± 16 (−13,5 %; Stufe 1: −8,0 %) |
| Einwohner | +43 ± 9 (+3,4 %) | +61 ± 10 (+4,2 %) |

Aus Teil B (20 Seeds, 730 Tage, gegen „aus“): Wiedergründung nach einer Pleite 0,1 % (aus 14,3 %, Stufe 1 2,7 %), Elternzeit-Kündigungen
−81 %, sonstige Kündigungen −81 %, Stellensuche/Fleiß −6,2 (aus −18,3).

### E.7 Gate 7 „nicht gewertet“ – Zählung

| | Seeds 1–80 | Seeds 81–160 | Schlussmessung Seeds 1–3 |
|---|---|---|---|
| Stufe 4 (Standard) | **54 von 80** | **55 von 80** | **3 von 3** |
| Stufe 1 (bisher) | 9 von 80 | 8 von 80 | – |
| Bezug `R.GED = 0` | 2 von 80 | nicht gerechnet | – |

Keine Stadt, in der Gate 7 gewertet wurde, ist rot (Stufe 4: 26 + 25 gewertet, kleinster Abstand 18,8 bzw. 17,9).

### E.8 Geändert und angelegt

- **Baukopie `stadt/`:** `stadt.html` (Wert und Kommentar, E.5) und `tools/simtest.mjs` (E.1). Sonst nichts (`diff -rq` gegen
  `sicherung_nachkalibrieren/`). Sicherung vor den Änderungen: `sicherung_nachkalibrieren/` (Stand nach „Optimieren“).
- **Im Repo nichts geändert, nichts angelegt, nichts committet:** `git status` leer, HEAD `6c1741e`.
- **Werkzeuge** (alte Fassungen in `tmp/nachkal_werkzeug_vorher/`): `kal_lese.mjs`, `kal_tabelle.mjs`, `gate_auswertung.mjs` (E.1);
  `kal_kopien.sh` (Zielordner, jede Stärke), `kal_gate_t.sh` (Ordner der Kopien), `arbeitskopie.sh`, `gate_staerke.sh`, `aus_kopie_rot.sh`,
  `aus_blind.py` (finden die Zeile mit jedem Wert; `arbeitskopie.sh` ohne Angabe mit der Stärke der Datei), `harte_grenze.mjs` (ohne
  `--staerke` die Stärke der Datei statt fest 1), `gate_wechsel.sh`, `gate_wechsel1.sh`, `kal_gate_t.sh` (Log-grep mit UTF-8, sonst fehlten
  die T-Zeilen im Log; die Messdateien selbst waren vollständig). Neu: `nachkal_tabelle.mjs`, `nachkal_stichprobe.mjs`,
  `nachkal_lese_pruef.mjs`, `nachkal_lese_neu_alt.mjs`.
- **Hinweis:** In den Logs `mess/nachkal/gate_t/wechsel.txt` und `mess/nachkal/schluss/gate_t/wechsel.txt` fehlen deshalb die T-Zeilen; die
  Zeiten stehen in den `gate_*.txt` daneben.
- **Nicht geprüft:** Browser-Tests (`tests/alle.sh`), weil für diese Phase kein Port angegeben war; die Doku (`docs/`, `README.md`) nennt
  Gate 7 noch ohne Entscheidung 8 und die Stärke nicht – das gehört in eine spätere Phase.

## Teil F – Noahs Entscheidung 9 (30.09.2026, ~16:30 UTC)

Nach Teil E (Stufe 4 gewählt) hat Noah entschieden: **Stärke 1,5** statt 4. Grund: Mit Stufe 4 wird Gate 7 nur noch in 26 von 80 Städten
gewertet (54 nicht gewertet, zu wenige Wegzieher), mit Stufe 1,5 in 58 von 80 (22 nicht gewertet). Stufe 1,5 hat nach Teil D auf den Seeds
1–80 alle Nebenbedingungen erfüllt und die Bestätigung auf den Seeds 81–160 bestanden (Tabelle `mess/nachkal/tabelle_nach_bestaetigung.txt`:
Gate 7 dort 49 gewertet und bestanden, 31 nicht gewertet; Gate T mit optimiertem Code Median 1.594 ms). Gesetzt vom Orchestrator:
`GED_STAERKE: 1.5` in `stadt/stadt.html` (Sicherung mit Stufe 4: `sicherung_staerke4`). Die Schlussmessung mit genau diesem Stand (probe8
Seeds 1–3, simtest --gate Seeds 1–3, Gate T im Wechsel) macht die nächste Phase (Sim prüfen B).

### F.1 Schlussmessung mit genau dem Stand 1,5 (Sim prüfen B, 16:55–17:00 UTC)

**Stand:** `stadt/stadt.html` sha256 `33d726b580e9e341…`, Sim-Hash `dc4b652a7629ba40`, `GED: 1, GED_STAERKE: 1.5`, `PLAN_RUECKLAGE: 1`;
`tools/simtest.mjs` sha256 `0031ab81…` (wie nach Teil E). Gegen `sicherung_staerke4/` unterscheidet sich nur `stadt.html`: der Wert und der
Kommentar (jetzt zwei Zeilen). Protokoll mit sha256 und Stärke vor jedem Abschnitt: `mess/staerke15/schluss/schluss.log`
(`werkzeug/kal_schluss.sh`). Immer nur ein Prozess; vor jedem Abschnitt und jedem Gate-T-Lauf fremde Rechenprozesse 0, Last über 1 Minute
0,34–1,30 (die Messprozesse selbst).

- **probe8, Seeds 1–3, 730 Tage, mit Kontrollen** (Stärke aus der Datei, `schluss/probe8_auswertung.txt`): „alle Kriterien erfüllt“; `erg`
  **Zahl für Zahl gleich** `mess/kalibrierung/probe8_k1.5.json` (Teil B). Anders ohne Erfahrung und Plan 0,838 / 1,015 / 0,825 % (Mittel
  0,893 %), davon direkt 92,0 / 91,1 / 90,5 %; ein Byte gelöscht → wie ohne Erfahrung 99,94 / 99,85 / 99,67 %; Beobachter 9.842 / 11.626 /
  9.786 Meldungen = direkte Unterschiede (13,5 / 15,9 / 13,4 je Tag), fehlend 0, zu viel 0; echte Wahl = Probe, Fingerabdrücke gleich.
- **`simtest --gate` (Seeds 1, 2, 3)** (`schluss/gate.txt`): „Gate Phase 0: BESTANDEN“. Gates 1–6, T und B grün in allen drei Seeds.
  Gate 7: Seed 1 ✓ (−22,1 bei n = 18), Seed 2 ✓ (−27,4 bei n = 15), **Seed 3 nicht gewertet** (n = 11; −34,9 nur gemeldet). T 1.710 / 959 /
  746 ms. Einwohner Tag 365 / 730: 1.395 / 1.480, 1.287 / 1.516, 1.380 / 1.455. Je Seed alle 46 Zeilen ohne Wandzeiten gleich den
  gespeicherten Stufe-1,5-Ausgaben aus Teil B (`schluss/gate_gegen_k1.5.txt`, `werkzeug/nachkal_stichprobe.mjs`).
- **Gate T, 4 Runden im Wechsel mit `6c1741e`** (`gate_wechsel1.sh 4 1`, 16:57–16:59 UTC, `schluss/gate_t/`): neu 1.655, 1.710, 1.665,
  1.727 ms, **Median 1.687,5 ms**, 4 von 4 unter 5.000; Basis 4.710, 4.538, 4.364, 4.302 ms, Median 4.451 ms; neu/Basis 0,379 (−62,1 %).
  Gegen die N2-Runden aus Teil E (1,5: 1.594 ms, Basis 4.243,5 ms) sind beide etwas langsamer (+5,9 % bzw. +4,9 %), der Rechner also auch.
- **Zusätzlich nach D.7.3** (schnell, ein Prozess): Schalter aus (`aus_gleich.mjs`, Seeds 1–3, 730 Tage, stündlich) Tag für Tag gleich
  `6c1741e` (Einwohner 1.449 / 1.509 / 1.515, `schluss/aus_gleich.txt`); harte Grenze statisch in Ordnung, **Namenstausch mit
  `GED_STAERKE = 1.5`** Seeds 1 und 2, 200 Tage: jeden Tag alle Arrays, Einzelwerte und Statistik gleich (`schluss/harte_grenze.txt`).
- **Nicht in dieser Schlussmessung:** `simtest_alle` mit 1,5 (D.7.3) und die Browser-Tests. `simtest_alle` ohne `--gate` lief danach in
  der Gegenprüfung B (Kopie `pruef_b/stadt`, gleich der Baukopie, 1 Prozess, `pruef_b/mess/simtest_alle/`): 12 von 21 Läufen mit Exit 0.
  Gegen den Lauf mit Stufe 4 (`mess/nachkal/simtest_alle/neu`) kippt je eine Prüfung: `--haushalt` „Computer gestrichen“ FEHL → ok,
  `--regierung` Seed 3 „Beitragstage über 8 Mitternächte“ ok → FEHL (1 Fehler: im Haushalt von Person 384 kommt an Tag 250 ein Kind zur Welt, Person 384 übernimmt ab derselben
  Nacht die Betreuung und bekommt den Beitragstag, den der Test aus dem Stand um 23 Uhr nicht erwartet; eine Testvoraussetzung, Anpassung in
  Schritt 4). Browser-Tests bleiben offen.

**Gate 7 „nicht gewertet“ mit Stufe 1,5** (aus `mess/nachkal/tabelle_nach_bestaetigung.txt` und dieser Messung): Seeds 1–80 **22 von 80**
(58 gewertet, alle bestanden, kleinster Abstand 19,4); Seeds 81–160 **31 von 80** (49 gewertet, alle bestanden, kleinster Abstand 18,8);
Schlussmessung Seeds 1–3 **1 von 3** (Seed 3).

## Teil C – Nachmessung nach „Sim-Fix“ (30.09.2026, 17:45–18:40 UTC)

Der Buchstabe C folgt dem Auftrag; Teil C steht hinter Teil F, weil er zeitlich danach kommt. Teil A und Teil D sind unverändert (sha256
`11482f4f…` bzw. `1978d313…`, nach dem Schreiben von Teil C geprüft). Einzelheiten zu den Korrekturen: `SP/ml/e2bau/SIM_FIX.md`. Rohdaten
`mess/simfix/`, die Schlussmessung `mess/simfix/schluss/` (Protokoll mit sha256 vor jedem Abschnitt: `schluss.log`).

**Stand:** `stadt/stadt.html` sha256 `6cc9f5333a40444e…`, Sim-Hash `aa03039229cca193`, `GED: 1, GED_STAERKE: 1.5`, `PLAN_RUECKLAGE: 1`;
`tools/simtest.mjs` sha256 `da7b3648409e8a95…`. Vorher (Teil F): `33d726b5…`, Sim-Hash `dc4b652a7629ba40`.

### C.1 Was sich mit `R.GED = 1` ändert

- **Verhalten geändert, gewollt (Befund „Haft“):** Kostet ein Haftantritt die Stelle, zählt das nicht mehr als schlechte Folge eines offenen
  Wechsels. Der offene Wechsel wird verworfen (`erfHaft`). Über 20 Seeds × 730 Tage: vorher 508 schlechte Wechsel-Erfahrungen aus einem
  Stellenverlust durch Haft, jetzt 0; 570 offene Wechsel verworfen, 791 Stellenverluste durch Haft.
- **Ohne Wirkung auf den Lauf:** Der Beobachter-Fehler wird gefangen, `warum` kennt Kinder und einen Zufallsstand (`rsVor`). Sie lesen nur
  oder wirken nur mit gesetztem Beobachter; Fingerabdrücke mit und ohne Beobachter sind gleich (C.3).
- **Schalter aus:** Mit `GED`, `OPFER_FREI` und `HAFT_EROEFFNUNG` aus rechnet die Baukopie Tag für Tag gleich `6c1741e` (`aus_gleich.mjs`,
  Seeds 1–3, 730 Tage, stündlich und in Tagesschritten).

Weil sich das Verhalten mit `R.GED = 1` ändert, sind die Messungen der gewählten Stufe 1,5 wiederholt: Gates auf den Seeds 1–80 und 81–160,
probe8 auf den Seeds 1–3, Gate T im Wechsel mit `6c1741e`. Die Stufe bleibt 1,5 (Entscheidung 9); gewählt wird hier nichts neu.

### C.2 Gates (`simtest --gate`, 730 Tage, 2 Prozesse)

| Stärke 1,5 | vorher 1–80 (Teil B/E) | **nachher 1–80** | vorher 81–160 (Teil B/E) | **nachher 81–160** |
|---|---|---|---|---|
| Gates 1, 2, 3, 5, 6 | je 80/80 | **je 80/80** | je 80/80 | **je 80/80** |
| Gate 4 (≥ 79/80) | 80/80 (größter Faktor 1,13) | **79/80** (Seed 19: Faktor 1,17, Grenze 1,15) | 80/80 (1,10) | **80/80** (1,11) |
| Gate 7 gewertet, alle bestanden / nicht gewertet | 58 / 22 | **64 / 16** | 49 / 31 | **47 / 33** |
| kleinster gewerteter Abstand | 19,4 | 16,8 | 18,8 | 18,4 |
| Wegzieher je Stadt bis Tag 365: Median (Spanne); Summe | 18 (5–36); 1.454 | 18 (7–47); 1.563 | 16 (4–40); 1.368 | 16 (4–35); 1.366 |
| Abstand über alle Wegzieher (gewichtet mit n) | 26,2 | 26,1 | 25,4 | 25,5 |
| kleinstes Budget | 1.741 | 1.741 | 772 | 772 |
| Abstürze | 0 | 0 | 0 | 0 |

- **Bedingungen erfüllt** (Gate 4 ≥ 79/80, die übrigen 80/80, Gate 7 ohne roten gewerteten Seed, kein Absturz), auf beiden Seed-Bereichen.
- Nicht gewertet (n < 15): Seeds 1–80: 4, 7, 10, 11, 24, 25, 33, 34, 36, 37, 41, 61, 64, 73, 76, 77. Seeds 81–160: 81, 84, 85, 86, 91, 92,
  100, 103, 104, 105, 107, 108, 110, 111, 112, 114, 119, 121, 123, 125, 126, 127, 135, 137, 138, 142, 143, 145, 148, 151, 154, 157, 159.
- `simtest --gate` (Seeds 1, 2, 3, in `simtest_alle`, allein): „Gate Phase 0: BESTANDEN“; Gate 7 in allen drei gewertet und grün (−24,0 bei
  n = 23, −26,9 bei n = 18, −29,9 bei n = 18), also **0 von 3 nicht gewertet**; T 1.446 / 950 / 739 ms.
- In keinem der 160 Seeds sind die Tabellenzeilen an Tag 365 und 730 gleich wie vorher: Die Korrektur verschiebt jede Stadt (Stellenverluste
  durch Haft gibt es überall).
- Der erste Lauf mit der Korrektur (Fassung mit den zwei Zeilen direkt in `haftAntritt`, `mess/simfix/gate_*`) und der Schlussstand geben
  dieselben Gate-Ausgaben (ohne Zeiten); beide Fassungen rechnen auf den Seeds 1–5 Tag für Tag gleich (`mess/simfix/fix1_gegen_fix2.txt`).

**Wirtschaft gepaart gegen `R.GED = 0`** (Seeds 1–80, Mittel der Differenz ± Standardfehler, Anteil am Bezug; Bezug wie Teil B):

| | vorher (Teil B) | **nachher** |
|---|---|---|
| Einwohner Tag 365 / 730 | +28 ± 9 (+2,2 %) / +16 ± 9 (+1,1 %) | +42 ± 10 (+3,3 %) / +20 ± 9 (+1,4 %) |
| Kasse Tag 365 / 730 | −43.749 ± 11.330 (−4,3 %) / −135.181 ± 21.665 (−14,2 %) | −37.232 ± 12.190 (−3,6 %) / −140.240 ± 25.215 (−14,8 %) |
| Gründungen bis Tag 365 / 730 | −54 ± 9 (−17,0 %) / −81 ± 16 (−16,3 %) | −46 ± 8 (−14,4 %) / −64 ± 17 (−12,9 %) |

### C.3 probe8 (Seeds 1–3, 730 Tage, mit Kontrollen, Stärke aus der Datei, 1 Prozess)

„Alle Kriterien erfüllt“ (`schluss/probe8_auswertung.txt`).

| | vorher (Teil F.1) | **nachher** |
|---|---|---|
| Z1 anders ohne Erfahrung und Plan, Seeds 1 / 2 / 3 | 0,838 / 1,015 / 0,825 % | 1,453 / 0,973 / 0,837 % |
| Z1 Mittel | 0,893 % | **1,088 %** |
| davon direkt | 92,0 / 91,1 / 90,5 % | 94,1 / 93,0 / 90,6 % |
| ein Byte gelöscht → wie ohne Erfahrung | 99,94 / 99,85 / 99,67 % | 99,83 / 99,82 / 99,87 % |
| Z2 Beobachter-Meldungen = direkte Unterschiede, je Stadt und Tag | 13,5 / 15,9 / 13,4 (14,3) | 24,8 / 15,1 / 13,4 (**17,7**) |
| echte Wahl = Probe; Fingerabdrücke mit/ohne Haken, nur Beobachter, rein | gleich | gleich |

Die Zunahme kommt fast ganz aus Seed 1 (0,84 → 1,45 %); die Seeds 2 und 3 liegen wie vorher. Ursache nicht zerlegt.

### C.4 Gate T (Seed 1, 4 Runden im Wechsel mit `6c1741e`, `gate_wechsel1.sh 4 1`, allein, fremde Rechenprozesse 0)

| | neu (ms) | Median | Basis `6c1741e` (ms) | Median | neu / Basis |
|---|---|---|---|---|---|
| vorher (Teil F.1, 16:57 UTC) | 1.655, 1.710, 1.665, 1.727 | 1.687,5 | 4.710, 4.538, 4.364, 4.302 | 4.451 | 0,379 |
| erster Fix-Lauf (18:08 UTC, Last 0,0–1,2) | 1.661, 1.571, 1.539, 1.434 | 1.555 | 4.438, 4.383, 4.238, 4.450 | 4.410,5 | 0,353 |
| **Schlussstand** (18:26 UTC, Last 1,5–1,7 aus den Läufen davor) | 1.604, 1.742, 1.659, 1.903 | **1.700,5** | 4.487, 4.820, 4.643, 4.555 | 4.599 | **0,370** |

- **Nicht langsamer:** neu/Basis 0,353 bzw. 0,370 gegen 0,379 vorher; alle Runden weit unter 5.000 ms.
- Seed 1 hat jetzt 187.153 Personentage in 365 Tagen (Teil B für 1,5: 201.042). `zeit.mjs` (3 Läufe je mit und ohne Beobachter): 1.464–1.850 ms,
  7,8–9,9 µs je Personentag, mit Beobachter (3.128 Meldungen) nicht langsamer als ohne.

### C.5 simtest_alle (`STADT_GIT=<repo> JOBS=2`, 18:28–18:33 UTC)

- 14 von 22 Läufen mit Exit 0 (mit `--gate`); ohne `--gate` 13 von 21 statt 12 von 21 in der Gegenprüfung B (`pruef_b/mess/simtest_alle`).
- Nach Prüfergebnis (`nachkal_status_vergleich.mjs`) kippt nur `--regierung` „Beitragstage über 8 Mitternächte“ FEHL → ok (Testvoraussetzung
  begründet angepasst, SIM_FIX.md). Die 8 roten Läufe sind dieselben wie vorher mit derselben Zahl roter Prüfungen: die Vergleiche mit alten
  Fassungen (`erweiterung`, `kipolicy`, `kipolicy_datei`, `migrationstest`, `rathaus`, `schule`, `techfrueh`, `wachstum`; Anpassung in Schritt 4).
- `--wachstum` D bleibt grün: schnell 249 gegen normal 226 Einwohner (Seed 5, Tag 150).
- Im ersten Fix-Lauf waren `--sicherheit` (statische Feldliste von `haftAntritt`) und `--militaer` („Zivil mit Verpflichtung“ angenommen) rot;
  beide sind behoben, Gründe in SIM_FIX.md.

### C.6 Seed 37 (Nachtrag zu B.1, gemessen)

Tiefvergleich des ganzen Zustands gegen `6c1741e` (`pruef_a/werkzeug/tief.mjs`, Seed 37, 730 Tage stündlich, `mess/simfix/seed37/`):
nur `GED` aus → ab Tag 451 verschieden (erste Abweichung `S.p.geld[192]` 5.429 ≠ 5.489); `GED` und `OPFER_FREI` aus → 730 von 730 Tagen
gleich; alle drei Schalter aus → 730 von 730 Tagen gleich. Die Abweichung des Kalibrier-Bezugs kommt also von `R.OPFER_FREI`. Den Hergang (in
`6c1741e` wird in der Nacht auf Tag 451 ein Haushalt ausgeraubt, dessen Vorstand in Haft ist) hat die Gegenprüfung A beschrieben
(`pruef_a/mess/seed37/haft.txt`); ich habe ihn nicht selbst nachverfolgt. Für Vergleiche mit alten Fassungen gelten immer alle drei Schalter aus.

### C.7 Was das für die späteren Phasen heißt

- Texte, Doku und Tests nennen für Stufe 1,5 ab jetzt die Zahlen aus Teil C: Gate 7 gewertet 64 von 80 (1–80) bzw. 47 von 80 (81–160),
  nicht gewertet 16 bzw. 33; Z1 1,09 %; Z2 17,7 direkte Fälle je Stadt und Tag. Die Zahlen aus Teil F (58 von 80, 0,89 %, ~14) gelten für den
  Stand vor dem Fix.
- Noahs Entscheidung 9 (Stärke 1,5) bleibt, wie sie ist; die Stufe hat mit dem Fix alle Bedingungen auf 1–80 und 81–160 erfüllt.

## Teil G – Erfahrung verblasst (`R.ERF_HALB`, Noahs Entscheidung 10; 30.09.2026, 20:16–21:05 UTC)

Kurzfassung; Einzelheiten, Festlegung vorab (Teil A, 20:16 UTC) und alle Zahlen in `SP/ml/e2bau/VERBLASSEN.md`. Rohdaten
`mess/verblassen/`. Die Stärke bleibt 1,5 (Entscheidung 9).

- **Form (VERBLASSEN.md A.1):** Alle `ERF_HALB / 15` Tage (je Person versetzt) verliert jede Erfahrung einen Punkt zur 0 hin, bei 0 ist sie
  vergessen. Eine Pleite (−30) ist nach H Tagen halb so stark und nach 2 H vergessen. Das gilt für alle Erfahrungen gleich, ohne neues
  Speicherfeld (Format 10, Übernahme und `gedPruefen` unverändert). Mit `R.GED = 0` läuft es nie.
- **Kandidaten 180, 360, 540:** Alle erfüllen N1–N5 (Gates 1–80, probe8, Gate T, Budget, Charakterabstände). Keiner erreicht das Ziel
  W(1.460) ≥ ½ · 16,96 % = 8,48 %: gemessen 5,48 / 2,77 / 3,30 %. H0 (kein Verblassen) liegt bei 2,32 %, die Obergrenze „sofort vergessen“ bei
  7,25 %.
- **Gewählt: `ERF_HALB = 180`**, nach der Regel „höchste W(1.460) unter den erfüllten“. Bestätigung auf den Seeds 81–160 bestanden:
  - Gates 1, 2, 3, 5, 6 je 80/80; Gate 4 80/80;
  - Gate 7: 57 gewertet und bestanden, 23 nicht gewertet;
  - 0 Abstürze.
- **Wirkung:** Nach einer Pleite gründen 2,4-mal so viele wieder wie ohne Verblassen (5,48 % gegen 2,32 %; ohne Erfahrung 16,96 %). Sparsame
  warten im Mittel 26,6 Tage länger als Verschwender (85 / 207 Wiedergründer).
- **Zielverfehlung, Frage an Noah:**
  - Verblassen allein reicht nicht; Rücklagen-Bremse, Wartezeit und Sperre bleiben.
  - Wiedergründung kommt in allen Varianten 180–358 Tage nach der Pleite, auch ohne Erfahrung. Grund: Ein Lebensjahr dauert 10 Spieltage,
    Gründen ist nur unter 60 möglich, und die Sperre nach einer Pleite dauert 180 Tage (VERBLASSEN.md B.8).
- **probe8 mit 180** (Seeds 1–3): „alle Kriterien erfüllt“. Z1 1,332 / 0,886 / 0,654 % (Mittel 0,957 %, vorher 1,088 %); Z2 15,5 direkte Fälle
  je Stadt und Tag (vorher 17,7).
- **Gate T im Wechsel mit `6c1741e`:** Median 1.598 ms gegen 4.544,5 ms, Verhältnis 0,352 (Teil C: 0,370). Je Personentag gleich schnell;
  die Stadt ist bei Seed 1 etwa 8 % größer.
- **Tests:**
  - `simtest --gate` Seeds 1–3 bestanden; `--speichertest`, `--aufholtest` und `--migrationstest` grün;
  - „Schalter aus“ Tag für Tag gleich `6c1741e`; harte Grenze und Namenstausch in Ordnung;
  - `simtest_alle` 15 von 22 wie Schritt 2, nach einer begründeten Anpassung des Tests „halb bezahlt“ in `--sicherheit`. Dem Test fehlte
    der Rentenzweig des Tagessatzes, Gegenprobe gemacht (VERBLASSEN.md B.6).
- **Wirtschaft (H = 180 gepaart gegen `R.GED = 0`, Seeds 1–80):**

  | | Tag 365 | Tag 730 |
  |---|---|---|
  | Einwohner | +22 ± 9 (+1,7 %) | −0 ± 8 (−0,0 %) |
  | Kasse | −48.330 ± 10.226 (−4,7 %) | −162.364 ± 21.940 (−17,1 %) |
  | Gründungen | −49 ± 8 (−15,5 %) | −59 ± 17 (−11,9 %) |

  Gegen H0: Kasse und Gründungen innerhalb von etwa 1,2 Standardfehlern, Einwohner −1,4 bis −1,6 %.
- **Gate 7 „nicht gewertet“ mit 180:** Seeds 1–80: **25 von 80** (55 gewertet, alle bestanden). Seeds 81–160: **23 von 80**. Schlussmessung
  Seeds 1–3: **3 von 3**, im Standardlauf `simtest --gate` wird Gate 7 also nicht gewertet. H0 hatte 16 bzw. 33, über 160 Seeds sind es 48
  gegen 49.
- **Für spätere Phasen:** Texte, Doku und Tests nennen ab jetzt `ERF_HALB = 180` und diese Zahlen. Z1 und Z2 aus Teil C gelten für den Stand
  ohne Verblassen.
