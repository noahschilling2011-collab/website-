# STADT – Etappe 2, Schritt 1: Simulation (Gedächtnis, Erfahrung, Plan)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

Stand 30.09.2026, 10:45 UTC (dritter Durchgang, nach Noahs Entscheidung 6). `SP` = Arbeitsordner der Sitzung (nicht im Repo).
Grundlage: Baukopie `SP/ml/e2bau/stadt` nach Schritt 0. Sicherungen: vor Schritt 1 `SP/ml/e2bau/sicherung_schritt1`, vor dem Schalter
`R.PLAN_RUECKLAGE` `sicherung_schritt1_ruecklage`, vor dem Standardwechsel auf 1 `sicherung_schritt1_standard1`.
**Im Repo ist nichts geändert, nichts angelegt, nichts committet** (`git status` leer, HEAD `6c1741e`, vorher und nachher).

Alle Zahlen sind gemessen, außer wo „gerechnet“ oder „Annahme“ steht. Rohdaten: `SP/ml/e2bau/mess/schritt1/` (29.09., Einstellung 0) und
`SP/ml/e2bau/mess/ruecklage/` (Schalter, Standard 1, alle Einstellungen).

## Ergebnis

Geändert ist nur `stadt.html`, und darin nur der sim-Block (Zeilen 922–8790): 405 Zeilen neu oder geändert, davon 24 alte Zeilen ersetzt
(`mess/ruecklage/diff_stadt_html_gesamt.txt`). `VERSION` bleibt 9, das Speicherformat ist nicht angefasst. Sim-Hash `5475aede423a0000`,
`stadt.html` sha256 `50adf8fd1de8bf03…`.

**Heute (30.09.) gemacht:**

- **`R.PLAN_RUECKLAGE = 1` ist Standard** (Noahs Entscheidung 6: Rücklage vor der Gründung für alle Gründer, erst ab der Stufe Stadt).
  Geändert sind nur der Wert und drei Kommentare (`mess/ruecklage/diff_standard1.txt`). Beweis, dass damit nichts anderes wechselt: Der
  neue Stand rechnet Seeds 1–3, 730 Tage stündlich, Tag für Tag gleich wie der Stand davor mit gesetztem `R.PLAN_RUECKLAGE = 1`.
- Die Werkzeuge kennen den neuen Standard (`arbeitskopie.sh`, `gate_staerke.sh`, `varianten.mjs`, Phasen-Skripte).
- Nachgeholt: Anlauf für die Einstellungen 1 und 2 (neu gerechnet), Phase B (Gates, Gate T, Rechenzeit, Profil) und Phase C
  (`simtest_alle`) für alle drei Einstellungen, der Befund `--haushalt` C, `--wachstum` mit Standard 1.

**Fertig-Kriterien mit Standard 1 (`R.PLAN_RUECKLAGE = 1`, Stärke `R.GED_STAERKE = 1`):**

| Kriterium | Ergebnis Standard 1 | Rohdaten (`mess/ruecklage/`) |
|---|---|---|
| Schalter aus (`R.GED = 0`, `OPFER_FREI = 0`, `HAFT_EROEFFNUNG = 0`) = `6c1741e`, Seeds 1–3, 730 Tage **stündlich** | **730 von 730 Tagen** gleich, je Seed | `aus_gleich_stuendlich_end.txt` |
| ebenso in **Tagesschritten** | **730 von 730 Tagen** gleich, je Seed | `aus_gleich_tagschritt_end.txt` |
| Punkt 8: echte Wahl = Probe | **100 %** (1.254.672 / 1.270.595 / 1.276.712 Entscheidungen) | `probe8_r1_auswertung.txt` |
| Punkt 8: Fingerabdruck mit / ohne Probe | gleich in allen drei Seeds (auch nur mit Beobachter und ganz rein) | ebenso |
| Punkt 8: je Stadt ≥ 0,3 % anders | **0,733 / 0,937 / 0,620 %** | ebenso |
| Punkt 8: davon ≥ 85 % direkt | **90,9 / 92,1 / 89,6 %** | ebenso |
| Punkt 8: Löschen nur des einen Bytes stellt ≥ 99 % her | **99,83 / 99,82 / 99,82 %** | ebenso |
| Beobachter: Meldungen = direkte Unterschiede aus probe8 | **8.364 = 8.364, 10.962 = 10.962, 7.094 = 7.094**, 0 fehlend, 0 zu viel, 0 mit anderen Aktionen | ebenso |
| Beobachter: Fingerabdruck mit / ohne gleich | gleich (3 von 3) | ebenso |
| Beobachter: Kosten gepaart ≤ +3 % | **×0,999** (16 Paare, `beob@1/neu@1`) | `zeit_auswertung.txt` |
| Muster 20 Seeds: Wiedergründung nach Pleite | **2,7 %** statt 14,3 % | `folgen20_auswertung.txt` |
| Muster: sonstige Kündigungen | **2.074** statt 10.703 (−81 %) | ebenso |
| Muster: Kündigungen nach Art inkl. Elternzeit | Elternzeit **9.018** statt 39.231 (−77 %), Renteneintritt 17.738 statt 17.171 | ebenso |
| Muster: Charakterabstände behalten ihr Vorzeichen | Gründer-Ehrgeiz +20,3 (aus +19,5), Wegzieher-Heimat −25,3 (−26,3), Kündiger-Fleiß −33,3 (−35,6); alle 7 Abstände gleiches Vorzeichen | ebenso |
| Gates Seeds 1–3, 3 Läufe | **Gates 1–7: 3 von 3** Läufen in allen Seeds grün. **T:** 5 von 9 Seed-Läufen rot, die Basis im Wechsel 4 von 9 (Rechner heute langsamer, siehe unten) | `gate_r1/` |
| Rechenzeit „leer“ gepaart ≤ +3 % | **×1,019** (24 Paare, ruhige Nachmessung, 0,861 … 1,111). Die erste Reihe (16 Paare, lauter Rechner) gab ×1,040; die drei „leer“-Varianten 0 / 1 / 2 rechnen dort denselben Weg und lagen bei ×1,086 / ×1,040 / ×1,019, also Rauschen | `zeit_auswertung_ruhig.txt`, `zeit_auswertung.txt` |
| neue Funktionen im CPU-Profil ≤ 3 % | **1,72 %** | `profil_r1.txt` |
| Gate T Seed 1 im Wechsel mit `6c1741e`, 4 Runden, Median ≤ +10 % | **nicht erfüllt: +26,4 %** (8 Runden, Median 5.858 zu 4.635,5 ms; neu in 8 von 8 Runden über 5.000 ms, die Basis in 1 von 8). Erste Reihe mit 4 Runden: +18,5 % | `gate_t_r1_ruhig/`, `gate_t_r1/`, `gate_t_auswertung.txt` |
| harte Grenze statisch | keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein Einzugstag | `harte_grenze_end.txt` |
| Namenstausch 200 Tage bitgleich | Seeds 1 und 2: jeden Tag alle Arrays, Einzelwerte und Statistik gleich (258 bzw. 234 gelernte Erfahrungen) | ebenso |
| `--wachstum` D „schnell mehr als normal“ (Seed 5, Tag 150) | **grün:** 262 gegen 209 Einwohner (mit Einstellung 0 rot: 175 gegen 182) | `simtest_alle_r1/wachstum.txt` |

**Ein Kriterium ist mit Standard 1 nicht erfüllt, und es hängt an einem harten Gate: Gate T (365 Tage Seed 1 unter 5.000 ms).**

- **Gemessen:** Seed 1 braucht mit Standard 1 im Wechsel mit der Basis +26,4 % (8 Runden) bzw. ×1,254 gepaart (24 Runden). T lag in allen
  8 Runden über 5.000 ms (5.757–6.681 ms), die Basis in 7 von 8 darunter.
- **Ursache: die Stadt ist größer, nicht der Code langsamer.** Seed 1 hat an Tag 365 1.336 statt 1.169 Einwohner und in 365 Tagen
  192.937 statt 154.729 Personentage (+24,7 %). Je Personentag rechnet Standard 1 so schnell wie die Basis (30,77 zu 30,66 µs), die
  Buchführung allein kostet ×1,019, die neuen Funktionen 1,72 % im Profil.
- **Seed 1 ist dabei der ungünstigste Fall:** Über die Seeds 1–12 wächst die Zahl der Personentage mit Standard 1 im Median um ×1,05,
  in Seed 1 um ×1,28, dem größten Wert der 12 (gerechnet als Näherung aus den Einwohnern an Tag 60/100/150/300/365, Abschnitt 0.5).
- **Auch auf dem ruhigeren Rechner vom 29.09. wäre T rot** (gerechnet: 4.336,5 ms × 1,26 ≈ 5.470 ms).
- **Ich habe nichts geändert, um T zu retten** (keine Schwelle, kein Verhalten). Die Entscheidung liegt bei Noah; Möglichkeiten in
  Abschnitt 0.5. Mit Einstellung 0 war T in Ordnung (29.09. +2,2 %); dort hat Seed 1 fast genau so viele Personentage wie die Basis
  (+0,1 %), weil die Rücklage den Anlauf bremst.

**Wichtigste Befunde neben den Kriterien:**

- **Anlauf und „Wachstum: schnell“ wirken mit Standard 1 wieder** (Seeds 1–12): schnell an Tag 150 im Mittel 331 Einwohner (ohne
  Etappe 2: 334, Einstellung 0: 223), „schnell mehr als normal“ in 11 von 12 Städten (0: 6 von 12). `simtest --wachstum` D ist grün
  (Seed 5: 262 gegen 209 Einwohner). Abschnitt 0.3.
- **Wirtschaft (20 Seeds, gepaart):** Kasse an Tag 365 −4,1 % (Einstellung 0: −8,2 %), an Tag 730 aber **−19,1 %** (0: −11,1 %),
  Gründungen bis Tag 365 −13,8 %, Pleiten −16,5 %. Für die Kalibrierung Gate 3 (kleinstes Budget) über 80 Seeds beobachten; in den
  Seeds 1–3 liegt es bei 1.891 (Basis 2.405). Abschnitt 0.4.
- **`simtest_alle` mit Standard 1: 12 von 22 grün.** Alle 8 roten Vergleichs-Modi sind erwartet: Auf einer Kopie mit `R.GED = 0` und einem
  simtest, der die 10 neuen Arrays nicht mitvergleicht, sind sie alle grün (7 von 7, dazu `--schule` schon ohne diesen Eingriff).
  Rot bleiben der Befund `--haushalt` C (geklärt: Testvoraussetzung, Abschnitt 4.7) und in `--gate` nur T. `--militaer` und
  `--haushalt` F sind jetzt grün. Abschnitt 0.6.
- **Einstellung 2 (nicht Standard)** macht zusätzlich `--sicherheit` und `--regierung` rot; beides sind nach meiner Messung Voraussetzungen
  der Tests, die im anderen Verlauf nicht gelten (Abschnitt 0.6).
- **Nebenbefund aus Version 9:** Rund 40 % der Lehrkräfte verlassen eine Schule in den ersten 24 Stunden wieder (Basis 43 %, Standard 1
  36 %; Abschnitt 4.7).

## 0. Rücklage und Anlauf (`R.PLAN_RUECKLAGE`)

### 0.1 Der Schalter

| Wert | Für wen gilt die Rücklage (samt Wartezeit nach einer Pleite)? | Herkunft |
|---|---|---|
| 0 | jeden Gründer, immer | Noahs Entscheidung 2 (bis 30.09. Standard) |
| **1 (Standard)** | jeden Gründer, aber erst ab der Stufe `R.ANLAUF_STUFE` (Stadt, 160 Einwohner), also nach dem Anlauf | **Noahs Entscheidung 6** |
| 2 | nur nach eigener Pleite (`sperreBis` bleibt gesetzt) oder schlechter Gründungserfahrung | Vorschlag des Vergleichs |

- **Eine Stelle entscheidet:** `ruecklageGilt(S, p)` liest nur die Stufe der Stadt, die letzte Pleite und die Gründungserfahrung.
- **Sie wirkt überall, wo die Rücklage wirkt:** `ruecklageFehlt` → Bremse beim Gründen (`dP` in `entscheide`, auch in `Sim.warum` und in
  der Beobachter-Spur), Planschritt „Rücklage ansparen“ (`planSchrittVon`) und damit das Bleiben statt Kündigen (`PLAN_SPAREN`), Anzeige der
  Rücklage in `Sim.gedInfo`. Die Anzeige-Texte der Karte kommen in Schritt 3.
- **Gleichheit gemessen** (Seeds 1–3, 730 Tage, stündlich, alle Arrays, Einzelwerte, JSON-Teile):
  - Einstellung 0 = Stand vor dem Schalter (`sicherung_schritt1_ruecklage`): 730 von 730 Tagen je Seed (`vorher_gleich_r0.txt`).
  - Standard 1 = Stand vor dem Standardwechsel mit gesetztem Wert 1 (`sicherung_schritt1_standard1`): 730 von 730 Tagen je Seed
    (`standard1_gleich.txt`). Die Messungen vom Vormittag mit `PLAN_RUECKLAGE=1` aus der Umgebung gelten damit für den Standard.
  - Messungen mit gesetzter Einstellung 0 oder 2 rechnen in beiden Ständen denselben Code (der Unterschied sind nur der Standardwert und
    Kommentare).

### 0.2 Alle Kriterien je Einstellung (Stärke 1)

| | **1 (Standard)** | 0 | 2 |
|---|---|---|---|
| Punkt 8 anders, Seeds 1 / 2 / 3 | 0,733 / 0,937 / 0,620 % | 0,667 / 0,748 / 0,659 % | 0,511 / 0,984 / 0,693 % |
| davon direkt | 90,9 / 92,1 / 89,6 % | 89,9 / 90,5 / 90,0 % | 89,0 / 93,3 / 89,2 % |
| ein Byte gelöscht → wie ohne Erfahrung | 99,83 / 99,82 / 99,82 % | 99,98 / 99,92 / 99,84 % | 99,69 / 99,78 / 99,58 % |
| anders nur ohne Plan | 2.386 / 3.548 / 1.928 | 2.615 / 2.181 / 1.941 | 330 / 2.491 / 22 |
| echte Wahl = Probe, Fingerabdrücke gleich | ja (3 von 3) | ja | ja |
| Beobachter = direkte Unterschiede | 8.364 / 10.962 / 7.094, 0 fehlend, 0 zu viel | 7.172 / 7.587 / 7.189 | 5.748 / 11.350 / 7.446 |
| Beobachter-Kosten gepaart | ×0,999 | ×0,982 | ×0,965 |
| Wiedergründung nach Pleite (20 Seeds; aus 14,3 %) | 2,7 % | 4,9 % | 3,9 % |
| Elternzeit-Kündigungen (aus 39.231) | 9.018 (−77 %) | 8.655 (−78 %) | 9.493 (−76 %) |
| sonstige Kündigungen (aus 10.703) | 2.074 (−81 %) | 2.006 (−81 %) | 2.136 (−80 %) |
| Charakterabstände: Vorzeichen wie „aus“ | 7 von 7 | 7 von 7 | 7 von 7 |
| Gates 1–7, Seeds 1–3, 3 Läufe | 3 von 3 | 3 von 3 | 3 von 3 |
| Gate 4 Faktor Seeds 1 / 2 / 3 (Basis 1,07 / 1,06 / 1,06) | 1,07 / 1,10 / 1,06 | 1,12 / 1,06 / 1,03 | 1,05 / 1,04 / 1,06 |
| kleinstes Budget Seeds 1 / 2 / 3 (Basis 3.653 / 3.653 / 2.405) | 2.986 / 3.653 / 1.891 | 3.653 / 3.653 / 2.702 | 2.986 / 3.653 / 1.891 |
| Einwohner Seed 1 Tag 365 (Basis 1.169) | 1.336 | 1.219 | 1.377 |
| Personentage Seed 1, 365 Tage (Basis 154.729) | **192.937 (+24,7 %)** | 154.855 (+0,1 %) | 190.221 (+22,9 %) |
| Zeit je Personentag, Median (Basis 31,84 µs) | 31,71 µs | 33,67 µs | 33,57 µs |
| Rechenzeit Seed 1 gepaart zur Basis (16 Paare) | **×1,194** (ruhig, 24 Paare: ×1,254) | ×1,053 | ×1,257 |
| „leer“ gepaart zur Basis (16 Paare, derselbe Verlauf wie die Basis) | ×1,040 (ruhig, 24 Paare: ×1,019) | ×1,086 | ×1,019 |
| neue Funktionen im CPU-Profil | 1,72 % | 1,72 % | 0,66 % |
| Gate T Seed 1 im Wechsel, Median | 4 Runden 6.254 zu 5.278 ms (+18,5 %); ruhig 8 Runden 5.858 zu 4.635,5 ms (**+26,4 %**) | 5.004 zu 5.357 ms (−6,6 %) | nicht gemessen |
| harte Grenze statisch, Namenstausch Seeds 1–2 | ok | ok | ok |
| `--wachstum` D (Seed 5, Tag 150 schnell / normal) | 262 / 209 grün | 175 / 182 **rot** | 267 / 207 grün |
| `simtest_alle` | 12 von 22 grün (rot: 8 Vergleiche, `--haushalt` C, `--gate` nur T) | 13 von 22 grün (rot: 8 Vergleiche, `--haushalt` C; `--gate` grün, T 4.762 / 3.923 / 4.965 ms) | 10 von 22 grün (rot: 8 Vergleiche, `--haushalt` C, `--gate` nur T in Seed 1, dazu `--sicherheit`, `--regierung`) |

Rohdaten: `probe8_r*_auswertung.txt`, `folgen20_auswertung.txt` (aus = `mess/schritt1/folgen20_aus.json`), `gate_r*/`, `gate_t_r1/`,
`gate_t_r0/`, `zeit_reihe.jsonl`, `zeit_auswertung.txt`, `profil_r*.txt`, `harte_grenze_r*.txt`, `anlauf_*.jsonl`, `simtest_alle_r*/`.

### 0.3 Anlauf (Seeds 1–12, je 365 Tage, `werkzeug/anlauf.mjs`)

Einwohner an Tag 60 / 100 / 150 / 300 / 365, Mittel über die Seeds (darunter die kleinste Stadt). „Stadt“ = Tag, an dem die Stufe
`ANLAUF_STUFE` erreicht ist (Median).

| normal | Mittel | kleinste | Stadt | Gründungen | Kasse Tag 365 |
|---|---|---|---|---|---|
| aus (= `6c1741e`) | 57 / 129 / 239 / 1.007 / 1.240 | 26 / 101 / 209 / 863 / 1.166 | Tag 113,5 | 314 | 1.026.323 |
| **1 (Standard)** | 57 / 132 / 256 / 1.107 / 1.290 | 26 / 86 / 209 / 961 / 1.191 | Tag 113 | 267 | 975.635 |
| 0 | 45 / 103 / 222 / 997 / 1.274 | 25 / 65 / 167 / 759 / 1.202 | Tag 125,5 | 255 | 914.463 |
| 2 | 57 / 132 / 253 / 1.047 / 1.278 | 26 / 86 / 207 / 908 / 1.181 | Tag 113 | 312 | 981.402 |

| schnell | Mittel | kleinste | Stadt | Gründungen | Kasse Tag 365 |
|---|---|---|---|---|---|
| aus | 62 / 164 / 334 / 1.232 / 1.354 | 30 / 91 / 224 / 1.160 / 1.239 | Tag 94,5 | 261 | 1.158.942 |
| **1 (Standard)** | 66 / 167 / 331 / 1.220 / 1.351 | 31 / 89 / 205 / 1.149 / 1.284 | Tag 97,5 | 250 | 1.145.804 |
| 0 | 44 / 95 / 223 / 1.103 / 1.313 | 27 / 32 / 53 / 604 / 1.193 | Tag 123 | 264 | 989.919 |
| 2 | 66 / 166 / 332 / 1.218 / 1.400 | 31 / 89 / 209 / 1.154 / 1.281 | Tag 97,5 | 277 | 1.185.339 |

| | aus | **1** | 0 | 2 |
|---|---|---|---|---|
| schnell > normal an Tag 150 / 300 (Seeds) | 11 / 12 von 12 | **11 / 11** von 12 | 6 / 7 von 12 | 11 / 12 von 12 |
| gepaart zu aus, Tag 150, normal / schnell (Einwohner) | – | +17 / −3 | −17 / −110 | +14 / −2 |
| Seeds mit weniger Einwohnern als aus an Tag 150, schnell | – | 6 von 12 | 12 von 12 | 8 von 12 |

**Lesart:** Mit Standard 1 ist der Anlauf wie ohne die Etappe 2 (normal im Mittel sogar etwas schneller), und „Wachstum: schnell“ wirkt
wieder (11 von 12 Städten an Tag 150 größer als normal, vorher 6 von 12). Das deckt sich mit der Messung des Orchestrators
(`mess/anlauf/auswertung.txt`, dort mit Text-Ersetzungen statt Schalter: 322 Einwohner, 9 von 12); der Schalter wirkt zusätzlich auf
Planschritt und Sparen, daher die kleinen Abweichungen.

`anlauf_b.jsonl` ist nach dem Neustart vollständig neu gerechnet (48 Zeilen); der abgebrochene Lauf liegt als `anlauf_b_abgebrochen.jsonl`
daneben. Auswertung: `anlauf_auswertung.txt`.

### 0.4 Wirtschaft über 20 Seeds je Einstellung (gepaart zu „aus“, Mittel ± Standardfehler)

| | **1 (Standard)** | 0 | 2 |
|---|---|---|---|
| Einwohner Tag 365 (aus 1.242) | +41 ± 23 (+3,3 %) | +17 ± 18 (+1,3 %) | +18 ± 21 (+1,5 %) |
| Kasse Tag 365 (aus 1.007.375) | −41.797 ± 16.413 (**−4,1 %**), 15 von 20 niedriger | −82.698 ± 19.915 (−8,2 %) | −20.545 ± 16.449 (−2,0 %) |
| Gründungen bis Tag 365 (aus 313) | −43 ± 16 (−13,8 %) | −43 ± 15 (−13,8 %) | −9 ± 20 (−2,8 %) |
| Pleiten bis Tag 365 (aus 153) | −25 ± 11 (−16,5 %) | −27 ± 9 (−17,9 %) | −4 ± 13 (−2,9 %) |
| Einwohner Tag 730 (aus 1.480) | +20 ± 19 (+1,4 %) | +21 ± 22 (+1,4 %) | −5 ± 16 (−0,3 %) |
| **Kasse Tag 730** (aus 990.121) | **−188.671 ± 47.714 (−19,1 %)**, 16 von 20 niedriger | −110.214 ± 48.202 (−11,1 %) | −175.888 ± 44.891 (−17,8 %) |
| Gründungen bis Tag 730 (aus 523) | −70 ± 43 (−13,3 %) | −65 ± 38 (−12,5 %) | −66 ± 40 (−12,6 %) |
| Pleiten bis Tag 730 (aus 279) | −51 ± 37 (−18,3 %) | −49 ± 31 (−17,5 %) | −58 ± 36 (−20,7 %) |

Mit Standard 1 sinkt die Kasse an Tag 730 stärker als mit 0 (−19,1 statt −11,1 %). Das liegt nahe bei „nur Erfahrung“ vom 29.09.
(−23,3 %, Abschnitt 3). Die Ursache ist weiter nicht zerlegt; für die Kalibrierung heißt das: Gate 3 (kleinstes Budget ≥ 0) über 80 Seeds
beobachten. In den Seeds 1–3 bleibt das kleinste Budget bei 1.891 (Basis 2.405).

### 0.5 Rechenzeit und Gate T mit Standard 1

Immer nur ein Rechenprozess, vor jedem Lauf Last und fremde Prozesse notiert (fremde Rechenprozesse über 20 %: nie). **Der Rechner war am
30.09. langsamer als am 29.09.:** Basis in `zeit_reihe` Median 4.926,5 bzw. 4.743 ms (29.09.: 4.238 ms), Gate T der Basis Median 5.278
bzw. 4.635,5 ms (29.09.: 4.336,5 ms). Absolute Werte von T sind heute deshalb nur im Wechsel mit der Basis aussagekräftig.

| Reihe (Seed 1, 365 Tage) | Standard 1 | Basis `6c1741e` | Ergebnis |
|---|---|---|---|
| Gate T, 4 Runden im Wechsel (08:06–08:08) | 7.259 / 6.482 / 6.026 / 5.681, Median 6.254 | 5.343 / 4.634 / 5.213 / 5.486, Median 5.278 | +18,5 % |
| **Gate T, 8 Runden im Wechsel, ruhig (10:06–10:11)** | 5.757 … 6.681, Median **5.858**, 8 von 8 über 5.000 | 4.364 … 5.027, Median **4.635,5**, 1 von 8 über 5.000 | **+26,4 %** |
| zum Vergleich Einstellung 0, 4 Runden (08:08–08:11) | Median 5.004 | Median 5.357 | −6,6 % |
| Zeit wie Gate T gepaart, 16 Runden | ×1,194 (1,023 … 1,523) | – | – |
| ebenso ruhig, 24 Runden | **×1,254** (1,103 … 1,461) | – | – |
| „leer“ (Buchführung, dieselbe Stadt wie die Basis), 24 Runden | ×1,019 (0,861 … 1,111) | – | ≤ +3 % |
| µs je Personentag (24 Runden) | 30,77 | 30,66 | gleich |
| Personentage in 365 Tagen | 192.937 | 154.729 | **+24,7 %** |

**Näherung über die Seeds 1–12** (gerechnet aus `anlauf_*.jsonl`: Einwohner an Tag 0/60/100/150/300/365, Trapez; die Näherung trifft Seed 1
mit ×1,28 gegen gemessen ×1,25):

| Personentage / aus | Median | kleinster | größter | Seed 1 |
|---|---|---|---|---|
| Standard 1, normal | ×1,05 | ×0,89 | ×1,28 | ×1,28 |
| Einstellung 0, normal | ×1,00 | ×0,81 | ×1,28 | ×1,01 |
| Einstellung 2, normal | ×1,03 | ×0,87 | ×1,27 | ×1,26 |
| Standard 1, schnell | ×1,00 | ×0,93 | ×1,19 | ×1,02 |

**Wo die Zeit hingeht** (CPU-Profil Standard 1, Seed 1, 365 Tage, Eigenzeit; `prof/r1/`): `stunde` 10,3 %, `zufZiel` 7,0 %, `wirtschaft`
6,6 %, `zufall` 5,2 %, `entscheide` 4,9 %, `kleinkind` 3,7 %, `einkauf` 3,3 %, `kistenVerteilen` 3,0 %, Speicherbereinigung 3,0 % … Das
Profil ist flach, es gibt keine einzelne Stelle, die 20 % bringt.

**Möglichkeiten (Entscheidung Noah; nichts davon ist gebaut oder gemessen, außer wo es steht):**

1. Die Simulation bitgleich schneller machen: Für +25 % Personentage müsste jeder Personentag rund 20 % billiger werden (gerechnet:
   1 / 1,25 = 0,80). Eigene Phase, Ergebnis offen.
2. Die Rücklage früher greifen lassen, z. B. ab der Kleinstadt. Der Orchestrator hat das mit Text-Ersetzungen gemessen
   (`mess/anlauf/auswertung.txt`): schnell an Tag 150 im Mittel 289 Einwohner, 8 von 12 schneller als normal; Seed 1 normal an Tag 365
   1.235 (Standard 1: 1.287 dort). T ist dafür nicht gemessen.
3. Zurück zu Einstellung 0: T in Ordnung, aber Anlauf und „schnell“ gebremst (`--wachstum` D rot); das hat Noah abgelehnt.

### 0.6 simtest-Modi je Einstellung

`simtest_alle.sh` (20 Modi, `--kipolicy`, `--kipolicy_datei`; JOBS 2) je Einstellung (`simtest_alle_r1/`, `_r0/`, `_r2/`; 0 und 2 über
Arbeitskopien aus `arbeitskopie.sh`): **Standard 1: 12 von 22 grün**, Einstellung 0: 13 von 22, Einstellung 2: 10 von 22.

| Modus (rote Prüfung) | 1 | 0 | 2 | Grund | Art |
|---|---|---|---|---|---|
| `--rathaus` H „ohne Rathaus Tag für Tag wie Version 8“ | rot | rot | rot | Vergleich mit alter Fassung | erwartet |
| `--kipolicy`, `--kipolicy_datei` „Policy aus bitgleich zu `09083f5`“ | rot | rot | rot | ebenso | erwartet |
| `--schule` „`SCHULEN = 0` … wie Version 8“ (Seed 3 ab Tag 7) | rot | rot | rot | ebenso | erwartet |
| `--erweiterung` „wie die alte Fassung“, „Übernahme Version 6 … wie Version 6“ (7 Prüfungen) | rot | rot | rot | ebenso | erwartet |
| `--techfrueh` „ohne die übrigen Bausteine von Version 9“ | rot | rot | rot | ebenso | erwartet |
| `--migrationstest` „60 Tage weiter ohne Sicherheit (und) Autos“ (6 Prüfungen) | rot | rot | rot | ebenso | erwartet |
| `--wachstum` B „ohne Anlauf … wie Version 8“ | rot | rot | rot | ebenso | erwartet |
| `--wachstum` D „schnell mehr als normal“ (Seed 5, Tag 150) | grün | **rot** | grün | Rücklage bremst den Anlauf | echter Befund bei 0, Anlass von Entscheidung 6 |
| `--haushalt` C „Computer gestrichen“ | rot | rot | rot | die gefundene Schule hat keine Lehrkraft mehr | Testvoraussetzung (4.7) |
| `--haushalt` F „Übernahme älterer Stände“ | grün | grün | grün | 29.09. rot: Besitzer in Haft bei Eröffnung | behoben (4.6) |
| `--militaer` „Grenze der Dienststelle“ | grün | grün | grün | 29.09. rot: Funktionsname mit „beobacht…“ (laut Kommentar im Code umbenannt in `andersMelden`) | behoben |
| `--gate` | rot, nur T | grün | rot, nur T in Seed 1 | größere Stadt (0.5) | **echter Befund bei 1** |
| `--sicherheit` „halb bezahlt“ | grün | grün | **rot** | Kandidat des Tests (Seed 2, Tag 300) ist mit 2 ein 66-jähriger Frührentner: die Simulation rechnet den Tagessatz aus der Rente (1,81), der Test aus den Tageskosten (0,82) | Testvoraussetzung, nur bei 2 (`tmp/sicherheit_r2.mjs`) |
| `--regierung` „Betrag = Tagesbedarf“ | grün | grün | **rot** | 1 von 10 Nächten: Seed 2, Tag 175, der Tagesbedarf von Person 8 ist um 23 Uhr 35 und bei der Zahlung 30 Taler; warum er sich in dieser Stunde ändert, habe ich nicht weiter verfolgt | vermutlich Testvoraussetzung, nur bei 2, **nicht ganz geklärt** (`tmp/kopie_r2_dbg/`) |

**Beweis für „erwartet“** (Standard-Endstand, `werkzeug/aus_kopie_rot.sh`, `werkzeug/aus_blind.py`):

1. Dieselben 9 roten Modi auf einer Kopie mit `R.GED = 0` und `R.HAFT_EROEFFNUNG = 0` (`simtest_aus_rot/`): `--schule` und `--haushalt`
   werden grün. Die übrigen 7 bleiben rot, und zwar ab Tag 1: Ihre Fingerabdrücke hashen alle Personen-Arrays nach Namen, also auch die 10
   neuen (mit `GED = 0` überall 0), die es in den alten Fassungen nicht gibt.
2. Dieselbe Kopie mit einer simtest-Kopie, die diese 10 Arrays in den Vergleichen auslässt (13 Stellen: 9 × `isView`-Schleife, 1 × Schleife
   über `S.p`, 2 × `exportZustand(S).arrays`, dazu die Liste; `simtest_aus_blind/`): **7 von 7 grün**. Zum Beispiel ist die Regression
   gegen `09083f5` in den Seeds 1–3 alle 730 Tage bitgleich, `--wachstum` B 200 Tage wie Version 8, `--rathaus` H 365 Tage gleich.
3. Diese Modi sind also nur rot, weil das neue Verhalten an ist und die neuen Arrays in den Fingerabdrücken stehen. Die Anpassung ist
   Schritt 4: `GED` und `HAFT_EROEFFNUNG` in die Aus-Listen dieser Vergleiche, `PF_GED` aus den Fingerabdrücken. `aus_blind.py` ist dafür
   eine Vorlage; die Baukopie und ihr simtest sind nicht angefasst.

## 1. Was gebaut ist

### 1.1 Neue Personenfelder (`PF`, Liste `PF_GED`; nur mit `R.GED` geschrieben)

| Feld | Typ × Plätze | Byte | Inhalt |
|---|---|---|---|
| `memFakt` | Int16 × 8 | 16 | Fakt je Erinnerung: Lohn (Stelle, Stelle weg, gekündigt, Rente), Tage, die der Betrieb bestand (Pleite), Rücklage in Tageskosten nach der Gründung, Hausstufe beim Einzug, Zahl der Kinder bzw. Freunde danach (A) |
| `memVon` | Uint8 × 8 | 8 | Verweis der Folge auf ihre Ursache: Tage seit der Handlung + 1, 0 = keiner (A) |
| `erf` | Uint8 × 8 | 8 | Erfahrung je Handlung × Lage (Geld knapp / reicht), gepackt: Bits 0–1 Beobachtungen 0–3, Bits 2–7 Wert + 32 (C + A) |
| `offen`, `offRest` | Uint8, Uint8 | 2 | offene Handlung (Zelle + 1) und Tage bis zur Frist (C, mit Lage) |
| `planSchritt`, `planGrund` | Uint8, Uint8 | 2 | Schritt im Plan; letzter Plan = Ziel (Bits 0–2) + Grund des Endes (ab Bit 3) (C, Gründe aus B) |
| `entA`, `entArt`, `entZeit` | Uint8, Uint8, Int32 | 6 | letzte Entscheidung: Aktion, Quelle (1 Regeln, 2 Policy, 3 Sprachmodell, 4 Fokus) + Bit 3 geklappt, Zeit = Tag · 24 + Stunde (neu) |
| **zusammen** | | **42** | **413 statt 371 Byte je Person roh** (gemessen, `byteLength / pKap`) |

- **`memName`** (Name und Geschlecht der Bezugsperson, 32 Byte) **wird mit `R.GED` nicht mehr geschrieben** (immer 0), `memBehalten` kopiert es
  nicht mit. Das Array selbst bleibt bis Schritt 2 stehen, weil „Schalter aus = `6c1741e`“ es Byte für Byte braucht und das Speicherformat
  erst in Schritt 2 wechselt. Mit dem Streichen dort wird es +10 Byte je Person (gerechnet: 42 − 32).
- Feste Tabellen (0 Byte je Person): `M_BED` (Bedeutung je Code, Annahme aus C), `ERF_AKTION`, `GED_DIREKT`, `PG`, `PLAN_GRUND`,
  `PLAN_SCHRITTE`, `Q`, `QUELLEN`. Summen in `S.stat.ged` (gelernt, davon schlecht, je Handlung; Planenden je Grund), nur mit `R.GED`.
- Kein neuer Zufallsstrom, kein Zufall in der neuen Logik, nichts je Person und Stunde.

### 1.2 Bausteine und Andockstellen

| Baustein | Umsetzung | Stelle |
|---|---|---|
| Gedächtnis 3 kurz + 5 lang | Plätze 0–2 Ring (`memPos` % 3), 3–7 Langzeit; was aus der Kurzzeit fällt und `M_BED ≥ 30` hat, verdrängt dort den Platz mit kleinster Bedeutung − Alter × 0,1 (Gleichstand: der alte bleibt). Wie C | `erinnere`, `memBehalten` |
| Fakt + Verweis (Entscheidung 1) | `memFakt` bei jedem Eintrag; `memVon` setzt `erfLernen`, wenn eine Folge ihre Ursache hat (Pleite ← Gründung, Stelle weg ← Wechsel, Trennung ← Zusammenziehen, wieder Stelle ← Kündigung) | `memFakt`, `erfLernen` |
| Erfahrung × 2 Lagen | `laden_gruenden`, `kuendigen`, `job_wechseln`, `zusammenziehen` je Lage (Bedürfnis Geld < 50 = knapp); Werte, Fristen, Lernregel und Sicherheit wie C | `erfPunkte`, `erfLage` |
| gelernt erst nach der Folge | offene Handlung mit Zelle und Resttagen; schlechte Folge sofort (Pleite, Stelle weg, Trennung, wieder Arbeit gesucht), sonst gut nach der Frist, wenn das Ergebnis noch besteht; eine offene Gründung bleibt offen | `erfHandlung`, `erfFolge`, `erfTag` |
| Elternzeit (Entscheidung 3) | Elternzeit-Kündigungen werden gelernt wie jede Kündigung; nur der Renteneintritt nicht | `ausfuehren` (`rente`) |
| Plan | Ziel als Kopf (ID Ziel/`zielSeit`), Schritt je Nacht aus dem Zustand, Ende mit Ziel und Grund: erreicht, Frist, Pleite, zu alt, schlechte Erfahrung, **in Rente**, **anderes Ziel** (Ziel von außen) | `zielSetzen`, `zielPruefen`, `planSchrittVon`, `planAbbruch`, `planEnde`, `zielVonAussen` |
| Rücklage vor der Gründung (Entscheidungen 2 und 6) | Rücklage = Kosten der Gründung, die p jetzt machen würde + 20 Tageskosten (doppelt nach schlechter Gründungserfahrung, wie C). Fehlt sie, zählt `laden_gruenden` für **jeden** Gründer, für den sie gilt, 30 weniger; mit Ziel „eigener Laden“ ist das genau der Zielbonus (= C). **Für wen sie gilt, sagt `R.PLAN_RUECKLAGE` (Abschnitt 0.1); Standard 1: jeder Gründer ab der Stufe Stadt** | `ruecklageGilt`, `ruecklageFehlt`, `planZiel`, `entscheide` |
| Wartezeit nach Pleite nach Sparsamkeit | zusätzlich zur Sperre `120 × (0,5 + Sparsamkeit)` Tage ab dem Ende der Sperre (60–180 Tage, wie B mit einer Pleite); gilt als fehlende Rücklage, also nur, wenn die Rücklage gilt | `pleiteWarteBis` |
| Sparen bremst Kündigen | im Planschritt „Rücklage ansparen“ zählt Kündigen 15 weniger (C) | `entscheide` |
| Zielwahl | während der Sperre kein Ziel „eigener Laden“; die Gründungserfahrung der heutigen Lage zählt beim Ziel „Laden“ mit (C) | `zielWaehlen` |
| letzte Entscheidung | in `ausfuehren` mit Quelle aus dem Aufrufer: `entscheide` (Regeln), `kiHaken` (Policy), `kiEntscheidung` (Sprachmodell), `kiFokusAusfuehren` (Fokus) | `ausfuehren` |
| Gegenprobe als Parameter | `entscheide(S, p, h, probe)`: probe ≠ 0 nur wählen (keine Policy, nichts ausführen); Bit 2 ohne Erfahrung, Bit 4 ohne Plan, Bit 8 Summanden merken | `entscheide` |
| `Sim.warum(S, p, h)` | nur lesend, `S.rs` gesichert: je geprüfter Aktion Lage/Charakter (Wert wie Version 9 mit Zielbonus), Erfahrung, Plan, Zufall (null = nicht gezogen); Wahl mit allem, ohne Erfahrung, ohne Plan, ohne beides; Art je Vergleich `direkt` / `zufall` | `warum`, `warumMerken` |
| Stärke (Entscheidung 4a) | `R.GED_STAERKE` × Erfahrungs- und Plan-Summanden in `entscheide` und `zielWaehlen` (1 = Entwurf C) | `entscheide`, `zielWaehlen` |
| Beobachter (Entscheidung 4b) | `Sim.beobachter = fn` (Eigenschaft, liegt nicht in `S`); `fn(p, gen, tag, stunde, mit, ohne, grund)` mit Aktionscodes (0 = nichts) und `grund` `'erfahrung'`, `'plan'`, `'erfahrung und plan'` oder `'zufall'`. Die meldende Funktion heißt bewusst nicht „beobacht…“ (`simtest --militaer` verbietet solche Funktionsnamen als Grenze der Dienststelle; wie `kiEingabe` in Etappe 1) | `entscheide`, `spurAn`, `spurWert`, `andersMelden` |
| Haft bei Eröffnung (Befund, Abschnitt 4.6) | Schalter `R.HAFT_EROEFFNUNG` (Standard 1): Eröffnet ein Betrieb, während sein Besitzer in Haft ist, fängt der Besitzer erst nach der Entlassung dort an (`haftEnde` setzt die Arbeit); 0 = wie `6c1741e` | `eroeffnen` |
| Debug/Werkzeuge | `Sim.gedInfo(S, p)`: Erfahrung je Lage, offene Handlung, Plan (Schritt, „wartet bis Tag …“, Frist, Rücklagenziel, nur wenn die Rücklage gilt), letzter Plan und Grund, letzte Entscheidung, Gedächtnis mit Fakt und Verweis; nur Zahlen und Codes | `gedInfo` |
| Anzeige ohne `memName` | `personInfo`: Erinnerungen nach Tag sortiert; wer nicht mehr in der Stadt lebt, heißt nach der Beziehung („Der Partner ist gestorben“, „Ein Kind …“, „Jemand Nahes …“), Namen lebender Personen wie bisher nur live über Verweis + Generation | `personInfo`, `bezugWort` |
| sonst | `kiGespraech` findet den letzten Eintrag in der Kurzzeit; `menschenTag` ruft `erfTag`; `leererZustand` legt `S.stat.ged` an | – |

`exportZustand`/`importZustand` tragen die neuen Felder ohne Änderung mit (sie laufen über `PF`). Ein alter Stand ohne diese Arrays lädt mit
Nullen; `erinnere` rechnet `memPos` dann modulo 3. Die richtige Übernahme (`migriereGed`, Prüfung beschädigter Stände) ist Schritt 2.

### 1.3 Beobachter: wie „dieselbe Schleife, kein zusätzlicher Zufall“ umgesetzt ist

- `entscheide` bewertet jede Aktion wie bisher. Mit Beobachter führt es daneben eine **Spur „ohne Erfahrung und Plan“**: denselben Wert ohne
  die Summanden, mit eigenem Bestwert.
- Bis zur ersten Aktion mit Summand ≠ 0 ist die Spur mit der echten Wahl identisch und rechnet nichts. Ab dort übernimmt sie deren Stand.
- Ihre Zufallszahlen **zieht sie nicht** aus `S.rs`. Sie rechnet sie aus dem Zufallsstand an dieser Stelle nach (`zufallAn(rs, k)`:
  mulberry32 zählt den Stand nur weiter). Das sind genau die Zahlen, die ein zweiter Aufruf mit `probe 2 | 4` ab demselben `S.rs` ziehen würde.
  **`S.rs` ändert sich dadurch nicht.**
- **Meldung nur**, wenn die Spur anders wählt **und** eine der beiden Aktionen eine ist, auf die Erfahrung oder Plan wirken (`GED_DIREKT`:
  Gründen, Kündigen, Wechseln, Zusammenziehen). Das ist dieselbe Definition von „direkt“ wie in `VERGLEICH.md` 1.2.
- **Ohne Beobachter** kostet das je Aktion eine Abfrage `if (spur …)`, sonst nichts.
- **Deutung (Annahme, offen genannt):** „kein zusätzlicher Zufall“ lese ich als „der Zufallsstrom der Stadt wird nicht berührt“. Die Spur
  rechnet Zahlen aus dem Stand nach, zieht aber keine. Nur so trifft sie probe8 auf die Entscheidung genau; gemessen ist es mit Standard 1
  in 3,80 Mio. Entscheidungen (Seeds 1–3), mit Einstellung 0 in 3,53 Mio.

## 2. Punkt 8: Gegenprobe (`werkzeug/probe8.mjs`, angepasst aus `vergleich/werkzeug/probe8.mjs`)

Die ausführliche Tabelle unten ist die Messung vom 29.09. mit **Einstellung 0** (damals „Rücklage vor jeder Gründung“). Die Werte für
Standard 1 und Einstellung 2 stehen in Abschnitt 0.2; das Bild ist dasselbe.

**Methode:**

- Vor jeder echten Entscheidung (stündlich, Seeds 1–3, 730 Tage) wählt dieselbe Person im selben Zustand mit demselben `S.rs` noch einmal,
  und zwar „nur wählen“.
- **„ohne beides“:** die 8 Erfahrungs-Bytes der Person gelöscht (unabhängig vom Probe-Bit) und der Plan aus (`probe 4`). Der Plan ist eine
  Regel auf Geld und Tage, kein Byte, das sich löschen ließe.
- **Zusätzlich:** „nur Erfahrung“ (Bytes gelöscht), „nur Plan“ (`probe 1 | 4`) und die Parameter `probe 1 | 2 | 4` bzw. `1 | 2` zum Abgleich
  mit den Löschungen.
- Im selben Lauf ist ein Beobachter gesetzt. Danach laufen drei Kontrollläufe: ohne Haken, nur mit Beobachter, ganz rein.

| Seed, 730 Tage, Einstellung 0 | 1 | 2 | 3 |
|---|---|---|---|
| Entscheidungen / davon Person mit Erfahrung | 1.196.274 / 925.511 | 1.121.239 / 887.074 | 1.212.744 / 961.767 |
| echte Wahl = Probe „mit“ | 100 % | 100 % | 100 % |
| **anders ohne Erfahrung und Plan** | **7.974 (0,667 %)** | **8.387 (0,748 %)** | **7.991 (0,659 %)** |
| davon direkt / indirekt | 7.172 (89,9 %) / 802 | 7.587 (90,5 %) / 800 | 7.189 (90,0 %) / 802 |
| anders nur ohne Erfahrung (direkt) | 5.035 (4.474) | 5.979 (5.360) | 5.518 (4.919) |
| anders nur ohne Plan (direkt) | 2.615 (2.397) | 2.181 (2.032) | 1.941 (1.779) |
| nur das eine Byte gelöscht → wie ohne Erfahrung | 4.439 von 4.440 (99,98 %) | 5.326 von 5.330 (99,92 %) | 4.873 von 4.881 (99,84 %) |
| Parameter `2 | 4` = Löschen + `4` | 100 % | 100 % | 100 % |
| **Beobachter-Meldungen** | **7.172** | **7.587** | **7.189** |
| Meldungen mit anderen Aktionen als die Probe / fehlend / zu viel | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Gründe der Meldungen | Erfahrung 4.437, Plan 2.299, beides 425, Zufall 11 | 5.323 / 2.017 / 245 / 2 | 4.742 / 1.471 / 972 / 4 |
| Fingerabdruck Tag 730 (mit Haken + Beobachter = ohne = nur Beobachter = rein) | `59baa54b67bb1a77` | `7e1b6e20208522bb` | `fff1e62f47f21adc` |

**Standard 1, kurz** (`mess/ruecklage/probe8_r1_auswertung.txt`):

- Gründe der Meldungen: Erfahrung 5.856 / 6.645 / 5.077, Plan 2.148 / 2.839 / 1.774, beides 350 / 1.471 / 238, Zufall 10 / 7 / 5.
- Häufigste Paare Seed 1 (ohne → mit): `kuendigen → nichts` 2.810, `job_wechseln → nichts` 2.583, `laden_gruenden → nichts` 1.256,
  `kuendigen → freunde_treffen` 463.
- Kündigungen Seeds 1–3: Elternzeit 437 / 483 / 488, sonstige 126 / 94 / 112 (aus: 1.818 / 1.983 / 1.946 bzw. 492 / 575 / 727).

**Häufigste Paare** mit Einstellung 0 (ohne → mit), Seed 1:

- `kuendigen → nichts` 3.329;
- `job_wechseln → nichts` 1.392;
- `laden_gruenden → nichts` 1.027;
- `kuendigen → freunde_treffen` 463;
- `nichts → job_wechseln` 148 (gute Erfahrung).

**Gegenkontrolle mit Schalter aus** (`mess/schritt1/probe8_aus_auswertung.txt`): 0 Unterschiede, 0 Meldungen. Die Kündigungen nach Art dort
(Seeds 1–3, 730 Tage):

- **Elternzeit:** 1.818 / 1.983 / 1.946, davon binnen 1 Tag wieder Arbeit gesucht 89 %;
- **sonstige:** 492 / 575 / 727.

**Beispiel** (Einstellung 0, Seed 1, Person 43, Generation 1; nur Zahlen): 42 Jahre, Fleiß 21, Ehrgeiz 39, Sparsamkeit 98, 1.635 Taler.

- Sie hatte gekündigt und gleich wieder Arbeit gesucht. Gelernt ist deshalb Kündigen, Lage „Geld reicht“: −20 bei n = 1, das sind −10 Punkte.
- **Tag 82, 18 Uhr:** `Sim.warum` gibt `kuendigen` Lage 23,4 + Erfahrung −10 = 13,4. Das liegt unter der Schwelle 25; die Wahl ist „nichts“,
  ohne Erfahrung wäre es „kuendigen“ (Art `direkt`).
- **Tag 83, 7 Uhr:** Sie nimmt frei statt zu kündigen.

Rohdaten: `mess/schritt1/probe8_neu.json`, `beispiele`.

## 3. Muster über 20 Seeds (`werkzeug/folgen.mjs`, `folgen_auswertung.mjs`; Seeds 1–20, je 730 Tage)

„aus“ = `R.GED = 0`, `R.OPFER_FREI = 0` und `R.HAFT_EROEFFNUNG = 0`, rechnet Tag für Tag wie `6c1741e` (Abschnitt 4.1).

| Summe über 20 Seeds | aus | **Standard 1** | 0 | 2 |
|---|---|---|---|---|
| Gründungen | 10.454 | 9.064 | 9.145 | 9.135 |
| Personen mit Pleite / danach wieder gegründet | 5.148 / 734 (**14,3 %**) | 4.518 / 124 (**2,7 %**) | 4.473 / 218 (4,9 %) | 4.343 / 171 (3,9 %) |
| Median Tage Pleite → Wiedergründung (Median der Seeds) | 192 | 251 | 234 | 241 |
| Personen mit ≥ 2 Pleiten | 430 | 41 | 129 | 80 |
| Kündigung = Renteneintritt | 17.171 | 17.738 | 17.161 | 17.339 |
| **Kündigung für die Elternzeit** | **39.231** | **9.018 (−77 %)** | 8.655 (−78 %) | 9.493 (−76 %) |
| davon binnen 1 Tag / 30 Tagen wieder Arbeit gesucht | 89,5 % / 95,3 % | 74,0 % / 89,3 % | 73,7 % / 89,5 % | 73,3 % / 88,2 % |
| **sonstige Kündigung** | **10.703** | **2.074 (−81 %)** | 2.006 (−81 %) | 2.136 (−80 %) |
| davon binnen 1 Tag / 30 Tagen wieder Arbeit gesucht | 93,2 % / 98,1 % | 85,5 % / 96,5 % | 84,6 % / 96,6 % | 84,6 % / 96,0 % |
| Wechsel / Stelle binnen 30 Tagen weg | 153.152 / 9,2 % | 127.064 / 8,4 % | 120.919 / 8,5 % | 125.465 / 7,9 % |
| Zusammengezogen / binnen 60 Tagen getrennt | 16.678 / 2,0 % | 16.503 / 1,0 % | 16.111 / 1,1 % | 16.470 / 1,6 % |

**Charakterabstände:** Mittel der Handelnden minus Mittel aller Erwachsenen je Personentag; Mittel über die Seeds, in Klammern kleinster und
größter Seed. Alle Vorzeichen bleiben, in jeder Einstellung.

| Handlung | Merkmal | aus | **Standard 1** | 0 | 2 |
|---|---|---|---|---|---|
| Gründung | Ehrgeiz | +19,5 (+17,3 … +22,7) | **+20,3** (+17,7 … +22,3) | +20,4 | +19,4 |
| sonstige Kündigung | Fleiß | −35,6 (−39,1 … −30,4) | **−33,3** (−37,2 … −29,5) | −33,9 | −34,0 |
| Kündigung für die Elternzeit | Fleiß | −26,3 | −20,8 | −20,9 | −20,9 |
| Wegzug | Heimat | −26,3 (−30,4 … −22,8) | **−25,3** (−30,7 … −17,1) | −25,5 | −25,9 |
| Partnersuche | Geselligkeit | +10,5 | +10,2 | +10,4 | +10,2 |
| Stellensuche | Fleiß | −18,3 | −7,5 | −7,6 | −7,8 |
| Wechsel | Ehrgeiz | +4,6 | +4,4 | +4,3 | +4,4 |

Wie schon in C schrumpft der Fleiß-Abstand bei der Stellensuche stark. Der Grund: Wer nach einer Reue nicht mehr kündigt, muss danach auch
nicht wieder suchen. Die Wirtschaft je Einstellung steht in Abschnitt 0.4.

**Zerlegung** (29.09., Einstellung 0; `mess/schritt1/folgen20_zerlegung.txt`, gleiche 20 Seeds). „nur Erfahrung“ = Plan wirkt nicht (keine
Rücklage, kein Sparen, keine Sperre in der Zielwahl, keine Abbrüche); „nur Plan“ = Erfahrung wirkt nicht. Das Gedächtnis wirkt in beiden.

| Summe bzw. gepaart zu „aus“ | Einstellung 0 | nur Erfahrung | nur Plan |
|---|---|---|---|
| Wiedergründung nach Pleite | 4,9 % | 6,3 % | 7,6 % |
| Kündigungen Elternzeit / sonstige | 8.655 / 2.006 | 9.848 / 2.172 | 32.239 / 10.429 |
| Gründungen bis Tag 365 | −13,8 % | −0,3 % | −12,3 % |
| Kasse Tag 365 | −8,2 % (−82.698 ± 19.915) | −3,9 % (−39.351 ± 17.851) | −6,6 % (−66.713 ± 23.226) |
| **Kasse Tag 730** | −11,1 % (−110.214 ± 48.202) | **−23,3 % (−230.298 ± 47.549)**, 16 von 20 niedriger | −6,6 % (−65.697 ± 45.219) |
| Einwohner Tag 365 | +1,3 % | +4,1 % (+51 ± 21) | +0,6 % |

- Die **Kündigungen** lernt die Erfahrung ab.
- Die **Gründungen im ersten Jahr** sinken durch den Plan (Rücklage).
- **Auffällig:** Die Erfahrung allein senkt die Kasse an Tag 730 stärker als beide zusammen; Standard 1 (−19,1 %) liegt nahe daran.
  - Die Ursache habe ich nicht zerlegt. Plausibel (nicht gemessen) ist dieselbe Vermutung wie bei C: Mit weniger Elternzeit steigen die
    Kita-Kosten der Stadt.
  - Für die Kalibrierung heißt das: Eine stärkere Erfahrung kann die Kasse weiter drücken, also Gate 3 (kleinstes Budget ≥ 0) über 80 Seeds
    beobachten.

## 4. Weitere Prüfungen

### 4.1 Schalter aus (`werkzeug/aus_gleich.mjs`)

- **Verglichen wird** jeden Tag mit `basis_6c1741e.html`:
  - alle Arrays der Basis Byte für Byte, nach Namen;
  - alle Einzelwerte, alle JSON-Teile und die Schlüssel von `S`;
  - die 10 neuen Arrays müssen 0 bleiben, weitere Arrays darf es nicht geben.
- „Aus“ heißt `R.GED = 0`, `R.OPFER_FREI = 0` (Schritt 0) und `R.HAFT_EROEFFNUNG = 0` (Befund aus Schritt 1, Abschnitt 4.6).
  `R.PLAN_RUECKLAGE` wirkt nur mit `R.GED`.
- **Ergebnis mit dem Endstand** (Sim-Hash `5475aede423a0000`): Seeds 1–3, 730 Tage, stündlich und in Tagesschritten, **je 730 von 730 Tagen
  gleich** (`mess/ruecklage/aus_gleich_*_end.txt`).

### 4.2 Gates Seeds 1–3 (`werkzeug/gate_wechsel1.sh 3 1,2,3`, immer ein Prozess, im Wechsel mit `sicherung_schritt0`)

Mit jeder Einstellung sind in allen drei Läufen **alle sieben inhaltlichen Gates grün**, bei neu und bei der Basis; die Werte sind bis auf T
in jedem Lauf gleich (geprüft: gleiche Zeilen in allen drei Läufen). Werte je Einstellung: Abschnitt 0.2. T ist am 30.09. bei neu wie bei
der Basis oft rot (Abschnitt 0.5).

Die Messung vom 29.09. (Einstellung 0; `mess/schritt1/gate/`) zum Vergleich:

| Gate | Seed 1 Basis → neu | Seed 2 | Seed 3 |
|---|---|---|---|
| 1 Einwohner Tag 365 | 1.169 → 1.219 | 1.200 → 1.228 | 1.221 → 1.269 |
| 3 kleinstes Budget | 3.653 → 3.653 | 3.653 → 3.653 | 2.405 → 2.702 |
| 4 Faktor Tag 551–730 | 1,07 → **1,12** | 1,06 → 1,06 | 1,06 → 1,03 |
| 5 Gründungen bis Tag 365 | 308 → 266 | 292 → 223 | 256 → 247 |
| 6 Gründer-Ehrgeiz | +19,4 → +21,1 | +20,8 → +19,7 | +20,9 → +23,2 |
| 7 Wegzieher-Heimat | −24,0 → −28,3 (n 28) | −25,6 → −24,5 (n 18) | −22,4 → −22,8 (n 16) |

Mit **Standard 1**: Einwohner Tag 365 1.336 / 1.369 / 1.305, kleinstes Budget 2.986 / 3.653 / 1.891, Faktor 1,07 / 1,10 / 1,06,
Gründungen 287 / 319 / 306, Gründer-Ehrgeiz +21,8 / +20,8 / +19,8, Wegzieher-Heimat −24,5 (n 25) / −18,3 (n 23) / −28,9 (n 32).

### 4.3 Rechenzeit am 29.09. (Einstellung 0; ein Prozess, kein fremder Rechenprozess über 20 % vor einem Lauf)

**Gate T Seed 1, 4 Runden im Wechsel** (`gate_wechsel1.sh 4 1`, `mess/schritt1/gate_t/`):

| | Runde 1 | 2 | 3 | 4 | Median |
|---|---|---|---|---|---|
| neu (ms) | 4.391 | 4.394 | 4.470 | 4.510 | 4.432 |
| Basis (ms) | 4.135 | 4.384 | 4.411 | 4.289 | 4.336,5 |

Das sind **+2,2 %**. Die erste Messreihe mit dem Stand vor der Beobachter-Änderung ergab +8,2 % (`vor_spur_an/`).

**Gepaart, Seed 1, 365 Tage wie Gate T, 16 Runden je Variante** (`zeit_reihe.sh`, `mess/schritt1/zeit_auswertung.txt`):

| Variante | Median ms (min … max) | gepaart | Fingerabdruck alte Felder Tag 365 |
|---|---|---|---|
| basis (`6c1741e`) | 4.238 (4.043 … 4.523) | – | `0aef350be3e88ab9` |
| leer (Buchführung ohne Wirkung) | 4.338,5 (4.089 … 4.679) | **×1,023** zu basis (0,953 … 1,132) | `0aef350be3e88ab9` = basis |
| neu | 4.503,5 (4.274 … 4.696) | ×1,057 zu basis (0,986 … 1,109) | andere Stadt (1.219 Einwohner) |
| beob (neu + zählender Beobachter, 2.783 Meldungen) | 4.429 (4.246 … 4.772) | **×0,989** zu neu (0,946 … 1,068) | = neu |

- **„leer“** führt alles mit: Erfahrung, offene Handlung, Fristen, Planschritt samt Rücklagen-Rechnung, Langzeit-Suche, Fakt und letzte
  Entscheidung. Nichts davon wirkt: Stärke 0, keine Sperre in der Zielwahl, keine Abbrüche, Gedächtnis der Reihe nach. Die Stadt rechnet
  Zahl für Zahl wie die Basis (gleicher Fingerabdruck).
- **CPU-Profil** 29.09.: 2,04 % (größter Posten `ruecklageFehlt` 66 ms, darin `planZiel` 48 ms). Mit dem Endstand (30.09., `profil_r*.txt`):
  1,72 % (Standard 1), 1,72 % (0), 0,66 % (2). Funktionen, die V8 einbettet, sind darin nicht einzeln sichtbar.

### 4.4 Harte Grenze (`werkzeug/harte_grenze.mjs`)

**Statisch** geprüft sind 26 Entscheidungs- und Lernfunktionen (neu dazu `ruecklageGilt`), 2 Anzeigefunktionen (`bezugWort`, `gedInfo`)
und 89 neue Zeilen in bestehenden Funktionen (`mess/ruecklage/harte_grenze_end.txt`).

- **Berührte Personenfelder:** arbeit, bGeld, besitz, entA, entArt, entZeit, erf, geb, geld, gemein, gen (eigene Generation für den
  Beobachter), haftBis, hh, kinder, lebt, memCode, memFakt, memGen, memName, memPos, memRef, memTag, memVon, offRest, offen, partner,
  planGrund, planSchritt, spar, sperreBis, ziel, zielSeit.
- **Keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein Einzugstag**, keine Namens-Hilfen (`name`, `nr`, `namePack` …).
- **Ausnahmen mit Grund:**
  - `memBehalten` kopiert `memRef`/`memGen` beim Verschieben in die Langzeit mit, wertet sie nicht aus und setzt `memName` auf 0.
  - `erinnere` rechnet `namePack` nur für `R.GED = 0`, also wie `6c1741e`.
  - Die Anzeige (`personInfo`, `bezugWort`, `gedInfo`) liest `memRef`/`memGen`, um lebende Personen live zu nennen bzw. die Beziehung zu
    finden. Keine Entscheidung und keine Erfahrung hängt am Bezug einer Erinnerung.

**Namenstausch:** Alle Vor- und Nachnamen sind um einen Platz verschoben. Seeds 1 und 2, je 200 Tage, mit jeder Einstellung 0 / 1 / 2:
jeden Tag alle Arrays (auch Erfahrung, offene Handlung, Plan, Gedächtnis, letzte Entscheidung), Einzelwerte und Statistik gleich. Mit
Standard 1 wurden dabei 258 bzw. 234 Erfahrungen gelernt.

### 4.5 Quelle der letzten Entscheidung (`werkzeug/quelle_probe.mjs`, `mess/schritt1/quelle_probe.txt`, 29.09.)

Seed 1:

- **Sprachmodell** (Test-Beantworter): 6 von 6 beantworteten Figuren tragen Quelle `sprachmodell`, die Aktion und „geklappt“ wie die
  Antwort.
- **Policy** (`ki/policy_v9_lokal_1.json`, 2 Tage): 24 Personen mit Quelle `policy`, 5 mit `regeln` (Ältere und Figuren).
- **Fokus:** 30 von 30 Entscheidungen mit Quelle `fokus`, richtiger Aktion, „geklappt“ und Zeit.
- **Schalter aus**, 30 Tage: alle neuen Felder bleiben 0.

### 4.6 Befund: Besitzer in Haft bei der Eröffnung (`R.HAFT_EROEFFNUNG`, `werkzeug/haft_eroeffnung.mjs`)

- **Gefunden** in `simtest --haushalt` F (Übernahme eines Stands der Version 6, 29.09.): Eröffnete ein neu gebauter Betrieb, während sein
  Besitzer in Haft war, setzte `eroeffnen` die Arbeit des Besitzers auf den Betrieb. Der Stand verletzte damit die Haft-Invariante (in Haft
  ohne Arbeit), und `sicherheitPruefen` lehnte ihn beim Laden ab („Spielstand beschädigt: Sicherheit (Haft)“). Der Fehler steckt schon in
  `6c1741e`; er zeigt sich nur in einem Verlauf, den die neuen Bausteine erzeugen.
- **Behoben** mit Schalter `R.HAFT_EROEFFNUNG` (Standard 1): Der Besitzer fängt erst nach der Entlassung dort an; `haftEnde` setzt die
  Arbeit auf den eigenen Betrieb, wenn er offen ist. Liest nur `haftBis`. 0 = wie `6c1741e` (für „Schalter aus“).
- **Nachgestellt** wie `--haushalt` F (Version 6, Seed 4, Tag 150 übernommen, stündlich bis Tag 190; `mess/ruecklage/haft_nachstellen.txt`):
  Schalter 0 → 73 Stunden mit Besitzer in Haft und Arbeit, Laden abgelehnt; Schalter 1 → 0 Stunden, Laden ok.
- **Wirkung in neuen Städten:** Seeds 1–20, 730 Tage (29.09., Einstellung 0; `mess/schritt1/haft_eroeffnung_*.txt`): der Fall tritt nie auf,
  Fingerabdrücke mit Schalter 0 und 1 gleich. Mit Standard 1 wiederholt (30.09., Seeds 1–20, 730 Tage; `mess/ruecklage/haft_eroeffnung_r1_*.txt`): ebenfalls nie, Fingerabdrücke mit Schalter 0 und 1 gleich.
- `simtest --haushalt` F ist mit dem Endstand grün (`simtest_alle_r1/haushalt.txt`). Ein eigener Testfall in `--sicherheit` fehlt noch
  (Schritt 4).

### 4.7 Befund `simtest --haushalt` C „Computer gestrichen“ (geklärt: Testvoraussetzung, kein Fehler der neuen Bausteine)

- **Was der Test macht:** Er sucht in Seed 1 den ersten Tag mit freiem Bauhof, Computern an einer Schule, Lieferanten, ohne Bedarf und Rathaus
  ≥ 2, streicht dann alle Computer der Schulen und erwartet, dass der Haushalt zuerst Computer kauft.
- **Was passiert** (`werkzeug/haushalt_computer.mjs`, `mess/ruecklage/haushalt_computer_r*.txt`; Spuren `tmp/haushalt_spur*.mjs`):
  - Basis: Tag 206, die neue Schule hat 1 Lehrkraft, 15 Schüler; nach dem Streichen fehlt 1 Computer → Test grün.
  - Neu (Einstellung 0 / 1 / 2): Tag 194 / 177 / 179, die neue Schule hat **0 Lehrkräfte** und 14–16 Schüler der Stufe 1. Soll =
    Lehrkräfte × 1 + Schüler × 0 (`IT_JE_SCHUELER[1] = 0`) = 0, also nach dem Streichen kein Bedarf → Computer 0 → Test rot.
  - Warum 0 Lehrkräfte: In der Nacht ziehen zwei Lehrkräfte für die Schule zu, die Schule kauft 2 Computer, und in der ersten Stunde wechseln
    beide die Stelle (`job_wechseln`). `Sim.warum` für beide: Erfahrung 0, Plan 0, die Wahl kommt allein aus Lage und Charakter (Regeln von
    Version 9). In der Basis wechselt an diesem Tag eine der beiden.
- **Wie oft das auch ohne Etappe 2 passiert** (`werkzeug/haushalt_lehrer.mjs`, Seeds 1–3, 365 Tage): Lehrkräfte, die eine Schule binnen
  24 Stunden nach dem Anfangen wieder verlassen: Basis 63 von 145 (43,4 %), Standard 1 56 von 157 (35,7 %), Einstellung 0 39 von 111
  (35,1 %). Das ist ein Verhalten von `6c1741e`, das die neuen Bausteine nicht verstärken.
- **Folgerung:** Der Test findet mit dem anderen Verlauf einen Stand, in dem seine Voraussetzung („nach dem Streichen fehlen Computer“) nicht
  gilt. Anpassung in Schritt 4, ohne ihn abzuschwächen: Die Suche verlangt zusätzlich, dass nach dem Streichen Bedarf besteht; die Prüfung
  selbst bleibt.
- **Nebenbefund für Noah (nicht Teil dieses Schritts):** Rund 40 % der Lehrkräfte verlassen eine Schule in den ersten 24 Stunden wieder,
  schon in Version 9. Ob das gewollt ist, habe ich nicht untersucht.

### 4.8 `simtest_alle` mit Standard 1: rote Modi und Grund

Siehe Abschnitt 0.6: 8 Vergleiche mit alten Fassungen (erwartet, belegt), `--haushalt` C (Testvoraussetzung, 4.7), `--gate` nur T (0.5).

## 5. Was ich im Bau entschieden habe (Annahmen und Abweichungen)

1. **Rücklage vor der Gründung (Entscheidungen 2 und 6).** C bremste nur Personen mit Ziel „eigener Laden“ (in der Basis 79–84 % der
   Gründungsversuche, Seeds 1–3, 730 Tage, gemessen mit `tmp/gruender_ziel.mjs`). Hier gilt die Rücklage für jeden Gründer, für den sie nach
   `R.PLAN_RUECKLAGE` gilt (Standard 1: ab der Stufe Stadt). Fehlt sie, zählt Gründen 30 weniger. Sehr Ehrgeizige ohne Ziel und ohne
   Rücklage können dann noch gründen (90 × (Ehrgeiz − 0,5) + 20 × (1 − Sparsamkeit) − 30 > 25); der Charakter bleibt so sichtbar.
2. **Wartezeit nach Pleite:** B rechnete je Pleite (`lehrePleite`). Hier gilt sie für die letzte Pleite (`sperreBis` + 60–180 Tage), ohne
   neues Byte, und nur, wenn die Rücklage gilt. Mehrere Pleiten wirken über die Erfahrung (Wert, n) und die doppelte Rücklage.
3. **`memName`** bleibt als Array bis Schritt 2 und wird mit `R.GED` nicht mehr beschrieben (Abschnitt 1.1).
4. **Letzte Entscheidung** hält nur ausgeführte oder versuchte Aktionen fest, nicht „nichts“. Sonst stünde fast immer „nichts“ da; die
   meisten Einträge sind dennoch `freunde_treffen` (82 % aller Aktionen laut Bestand).
5. **`Sim.warum`** erklärt, was die Person **jetzt** (oder in Stunde h) nach Regeln wählen würde. Eine vergangene Entscheidung lässt sich ohne
   gespeicherten Zustand nicht nachrechnen. Für die Karte reicht das, wenn „Warum?“ neben der letzten Entscheidung steht; die Grenze ist dort
   zu nennen (Schritt 3).
6. **Beobachter nachgebessert** (erste Messung ×1,039 gegen +3 %).
   - Vorher: Die Spur lief ab dem Start jeder Entscheidung und setzte je Entscheidung zwei Hilfs-Arrays zurück.
   - Jetzt: Sie beginnt erst beim ersten Summanden ≠ 0 (`spurAn`).
   - Gleich blieb alles, was vorher stimmte: probe8 mit Endstand wiederholt, dieselben Meldungen, dieselben Fingerabdrücke.
7. **`probe` ≠ 0 heißt immer nur wählen.** Kein Bit führt aus, damit eine Probe nie wirkt.
8. **`R.HAFT_EROEFFNUNG`** ist ein eigener Schalter (nicht an `R.GED` gebunden), wie `R.OPFER_FREI` aus Schritt 0: Der Fehler steckt schon in
   `6c1741e`. „Schalter aus“ heißt deshalb `GED`, `OPFER_FREI` und `HAFT_EROEFFNUNG` auf 0.

## 6. Wiederverwendbare Werkzeuge (`SP/ml/e2bau/werkzeug/`)

**Kalibrierung** (Stärke als Zahl; Rücklage über die Umgebungsvariable `PLAN_RUECKLAGE` oder `@m`, sonst Standard 1):

| Werkzeug | Aufruf | liefert |
|---|---|---|
| `varianten.mjs` | Modul: `variante(name, { staerke, ruecklage, mehr })` | `basis`, `neu`, `aus`, `leer`, `nurErf`, `nurPlan` |
| `arbeitskopie.sh` | `bash arbeitskopie.sh <rücklage 0\|1\|2> [stärke]` | Arbeitskopie `tmp/kopie_r<m>_k<k>` mit gesetzten Standardwerten (für Läufe, die `stadt.html` von der Platte lesen) |
| `gate_staerke.sh` | `[PLAN_RUECKLAGE=m] bash gate_staerke.sh <stärke> <von> <bis> <ordner> [jobs 2]` | Gates für Seeds a–b mit Stärke k, danach `gate_auswertung.mjs` je Gate und Seed |
| `gate_auswertung.mjs` | `node gate_auswertung.mjs datei… [--tabelle]` | bestanden je Gate, rote Seeds, Faktor 4, Budget, Gate 6/7, T |
| `probe8.mjs` | `[PLAN_RUECKLAGE=m] node probe8.mjs [--variante neu] [--seeds 1,2,3] [--tage 730] [--staerke k] [--ohneKontrolle]` | Anteil geänderter Entscheidungen (ohne beides / nur Erfahrung / nur Plan), direkt, ein Byte, Beobachter, Kündigungen nach Art |
| `probe8_auswertung.mjs` | `node probe8_auswertung.mjs probe8.json` | Kriterien von Punkt 8 und Beobachter je Seed |
| `folgen.mjs` | `[PLAN_RUECKLAGE=m] node folgen.mjs <neu\|aus\|nurErf\|nurPlan> <1-20> [730] [stärke]` | Muster und Wirtschaft (Kasse, Gründungen, Pleiten, Einwohner an Tag 365/730) |
| `folgen_auswertung.mjs` | `node folgen_auswertung.mjs aus.json neu.json […]` | Summen, Charakterabstände, Wirtschaft gepaart (Mittel ± SE) |
| `anlauf.mjs`, `anlauf_auswertung.mjs` | `node anlauf.mjs aus,r0,r1,r2 1-12 [stärke]`; `node anlauf_auswertung.mjs a.jsonl …` | Anlauf normal/schnell: Einwohner Tag 60–365, Tag der Stufe Stadt, „schnell > normal“, Seed 5 wie `--wachstum` D |

**Prüfung und Rechenzeit:**

| Werkzeug | Aufruf | liefert |
|---|---|---|
| `aus_gleich.mjs` | `node aus_gleich.mjs [--seeds] [--tage] [--tagschritt]` | Schalter aus = `6c1741e` Tag für Tag |
| `vorher_gleich.mjs` | `node vorher_gleich.mjs --alt a.html [--neu b.html] [--setze NAME=wert]` | zwei Fassungen Tag für Tag gleich (z. B. Standard 1 = alter Stand mit 1) |
| `harte_grenze.mjs` | `[PLAN_RUECKLAGE=m] node harte_grenze.mjs [--seeds 1,2] [--tage 200] [--staerke]` | statische Leseliste, Namenstausch |
| `quelle_probe.mjs` | `node quelle_probe.mjs` | Quelle der letzten Entscheidung |
| `haft_eroeffnung.mjs` | `node haft_eroeffnung.mjs [--seeds] [--tage] [--nurNachstellen]` | Befund Haft bei Eröffnung: nachgestellt und Wirkung |
| `haushalt_computer.mjs`, `haushalt_lehrer.mjs` | `node haushalt_computer.mjs basis,aus,neu`; `node haushalt_lehrer.mjs basis,neu@1 1,2,3 365` | Befund `--haushalt` C; Lehrkräfte, die binnen 24 h gehen |
| `aus_kopie_rot.sh` | `bash aus_kopie_rot.sh <ordner> modus…` | rote simtest-Modi auf einer Kopie mit `GED = 0`, `HAFT_EROEFFNUNG = 0` (erwartet oder echter Befund?) |
| `zeit.mjs`, `zeit_reihe.sh`, `zeit_auswertung.mjs` | `bash zeit_reihe.sh 16 aus.jsonl 1 "basis leer@1 neu@1 beob@1"` | Zeit wie Gate T, gepaart, mit Personentagen |
| `gate_wechsel1.sh` | `bash gate_wechsel1.sh <runden> <seeds> <ordner> [neuer Ordner]` | Gates / Gate T im Wechsel mit der Basis |
| `profil.mjs` | `node --cpu-prof … zeit.mjs neu@1 1 365; node profil.mjs x.cpuprofile` | Anteil der neuen Funktionen |

**Abläufe:** `schritt1_phaseA.sh`, `schritt1_phaseA2.sh`, `schritt1_phaseB.sh`, `schritt1_phaseC.sh` (29.09.); `ruecklage_phaseA.sh`,
`ruecklage_phaseA3.sh` (Endstand-Prüfung), `ruecklage_phaseB.sh [andere Einstellung für Gate T]` (nur allein laufen lassen),
`ruecklage_phaseC.sh ["1 0 2"]`, `ruecklage_BC.sh` (B, dann C). `ruecklage_nachC.sh` (rote Modi auf der Aus-Kopie, Haft mit Standard 1, ruhige Nachmessung: 24 Runden Zeit, 8 Runden Gate T); `aus_blind.py` (Aus-Kopie mit einem simtest, der die neuen Arrays nicht vergleicht; Vorlage für Schritt 4).

## 7. Nicht geprüft / offen / für die nächsten Schritte

- **Gate T mit Standard 1 ist rot (Abschnitt 0.5).** Das muss vor der Kalibrierung entschieden werden; eine stärkere Erfahrung ändert
  den Verlauf weiter. Gates und Schwellen habe ich nicht angefasst.
- **Seeds 1–80** (Gates, Kasse und Gründungen gepaart): nicht gemessen, das ist die nächste Phase. Mit Standard 1 besonders Gate 3
  (Kasse an Tag 730 −19,1 %) und T.
- **Browser-Tests:** nicht ausgeführt. Die Oberfläche ist unverändert; `personInfo` liefert dieselben Felder, die Texte über Verstorbene nennen
  jetzt die Beziehung.
- **Speicherformat, Migration, beschädigte Stände, `memName` streichen:** Schritt 2.
  - Speichern und Laden tragen die neuen Felder heute schon mit.
  - Ein Stand der Version 9 lädt heute ohne Übernahme mit Nullen. Das wird mit Version 10 abgelehnt.
- **simtest anpassen (Schritt 4):** (1) die 8 Vergleichs-Modi wie in 0.6 (Aus-Listen, `PF_GED` aus den Fingerabdrücken); (2) `--haushalt` C:
  die Suche verlangt Bedarf nach dem Streichen; (3) ein Testfall für `R.HAFT_EROEFFNUNG` in `--sicherheit`; (4) `tools/kiepisode.mjs`
  Zielschlüssel ohne Platz (29.09. gefunden). Nur für Einstellung 2: `--sicherheit` „halb bezahlt“ (Tagessatz aus der Rente) und
  `--regierung` „Betrag = Tagesbedarf“ (Ursache nicht ganz geklärt).
- **Die Policy aus Etappe 1** wird in Schritt 1 noch angenommen (Version 9). Entscheidet sie, wirken Erfahrung und Plan nicht (`kiHaken`
  kehrt vorher zurück), gelernt wird aber auch aus ihren Handlungen. Die Ablehnung kommt mit Version 10 (Entscheidung 5).
- **Ergebnisse je Folge sind Annahmen** (Fristen, ±Punkte, Bedeutung je Code, Rücklage 20 Tage, Bremse 30, Wartezeit 120 × (0,5 + Sp)), wie in C.
- **Nicht zerlegt:** warum die Kasse an Tag 730 mit Erfahrung so stark sinkt (Vermutung: Kita-Kosten) und warum Seed 1 mit Standard 1 im
  Anlauf schneller wächst als ohne Etappe 2.
- **Nebenbefund Version 9:** Lehrkräfte, die eine Schule binnen 24 Stunden wieder verlassen (Abschnitt 4.7), nicht untersucht.

## 8. Dateien

- **Baukopie:** `SP/ml/e2bau/stadt/stadt.html` (einzige geänderte Datei). Sicherungen: `sicherung_schritt1/` (vor Schritt 1),
  `sicherung_schritt1_ruecklage/` (vor dem Schalter), `sicherung_schritt1_standard1/` (vor dem Standardwechsel). Der Bericht vor diesem
  Durchgang: `tmp/SCHRITT1_vor_standard1.md`.
- **Messungen 29.09.** `SP/ml/e2bau/mess/schritt1/` (Einstellung 0): `diff_stadt_html.txt`, `aus_gleich_*.txt`, `probe8_*`, `folgen20_*`,
  `harte_grenze.txt`, `quelle_probe.txt`, `gate/`, `gate_t/`, `zeit_*`, `prof/`, `profil.txt`, `simtest_alle*`, `haft_eroeffnung_*.txt`,
  Logs `phase*.log`.
- **Messungen Rücklage und Standard 1** `SP/ml/e2bau/mess/ruecklage/`:
  - Gleichheit: `vorher_gleich_r0.txt`, `standard1_gleich.txt`, `aus_gleich_*_end.txt` (Endstand), `aus_gleich_*.txt` (Stand davor),
    `diff_standard1.txt`, `diff_stadt_html_gesamt.txt`;
  - Punkt 8 und Muster: `probe8_r*.json` / `_auswertung.txt`, `folgen20_r*.json`, `folgen20_auswertung.txt`;
  - Anlauf: `anlauf_a.jsonl`, `anlauf_b.jsonl`, `anlauf_auswertung.txt`;
  - Grenze und Befunde: `harte_grenze_r*.txt`, `harte_grenze_end.txt`, `haft_nachstellen.txt`, `haushalt_computer_r*.txt`,
    `einzeln_r1/wachstum.txt`, `haft_eroeffnung_r1_*.txt`, `simtest_aus_rot*`, `simtest_aus_blind*`;
  - Rechenzeit: `gate_t_r1/`, `gate_t_r0/`, `gate_r1/`, `gate_r0/`, `gate_r2/`, `zeit_reihe.jsonl`, `zeit_auswertung.txt`, `prof/`,
    `profil_r*.txt`;
  - simtest: `simtest_alle_r1*`, `simtest_alle_r0*`, `simtest_alle_r2*`;
  - Logs: `phaseA.log`, `phaseA3.log`, `phaseB.log`, `phaseC.log`.
- **Werkzeuge:** `SP/ml/e2bau/werkzeug/` (Abschnitt 6); alte Fassungen vor dem Standardwechsel in `tmp/werkzeug_vor_standard1/`.
