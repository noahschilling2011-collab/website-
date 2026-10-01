# STADT – Etappe 2: Vergleich der drei Prototypen und Empfehlung

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

Stand 29.09.2026, 13:40 UTC. Grundlage: Repo `<repo>`, HEAD `6c1741e`. **Im Repo ist nichts geändert, nichts committet**
(`git status` leer). `SP` = Arbeitsordner der Sitzung (nicht im Repo).

Verglichen werden die drei Entwürfe unter `SP/ml/e2/`:

- **A „Erfahrung zuerst“**: `erfahrung/`, Bericht `erfahrung/ENTWURF.md`
- **B „Pläne zuerst“**: `plaene/`, Bericht `plaene/ENTWURF.md`
- **C „Rechenzeit und Speicher zuerst“**: `sparsam/`, Bericht `sparsam/ENTWURF.md`

Grundlage war außerdem die Bestandsaufnahme `BESTAND_E2.md`. Meine eigenen Skripte liegen in `SP/ml/e2/vergleich/werkzeug/`, die Rohdaten in
`SP/ml/e2/vergleich/mess/`. Ich habe keinen Server gestartet und keine Ports benutzt; 8000 und 11434 blieben unberührt. Es liefen höchstens zwei
eigene Rechenprozesse gleichzeitig, und für die Zeitmessung immer nur einer.

Alle Zahlen hier sind gemessen, außer wo „gerechnet“, „geschätzt“ oder „laut Bericht“ steht.

---

## 0. Kurzfassung

**Empfehlung: Weg C als Gerüst, ergänzt um drei Teile aus A und B.**

- **Warum C:** Nur C deckt alle fünf Bausteine aus Abschnitt 4 ab (Gedächtnis kurz/lang, Erfahrung, offene Handlung, Plan,
  Beziehungsnetz), und das mit **8 Byte je Person**. Dazu ist C der einzige Entwurf, bei dem Gate T in meinen Läufen nicht messbar steigt.
- **Aus A kommen:**
  - die Situation (Geld knapp / Geld reicht) in der Erfahrung, so wie Abschnitt 4 es verlangt;
  - Fakt und Verweis je Erinnerung, bezahlt mit den Bytes von `memName`;
  - die Gegenprobe als Parameter von `entscheide`.
- **Aus B kommen:**
  - die Plan-Anzeige (Schritt, „wartet bis …“, Frist, warum der letzte Plan endete);
  - eine Lehre aus der Pleite, die vom Charakter abhängt;
  - die Nebenbefunde (`opferWaehlen`, zwei Testfälle), die vorab getrennt behoben werden.

**Nachgeprüft** habe ich je Prototyp Gate T (viermal im Wechsel mit der Basis), die Gegenprobe zu Punkt 8 (eigenes Skript, das die
Etappe-2-Daten der Person löscht statt die Probe-Schalter der Entwürfe zu nutzen) und die Spielstand-Größe (Seed 1 und große Stadt). Dazu kamen
die kritischen Gate-Seeds und die echte `localStorage`-Grenze in Chromium.

- **Punkt 8:** Die Zahlen von A und C stimmen auf die Entscheidung genau mit den Berichten überein. Bei B wirkt die Erfahrung auf einzelne
  Entscheidungen fast nur in einer von drei Städten.
- **Neu gefunden:** A und C lernen vor allem ein altes Muster ab: „für die Elternzeit kündigen, am nächsten Morgen wieder Arbeit suchen“.
  Elternzeit-Kündigungen fallen um 72 bzw. 79 %. Das ist eine Produktfrage an Noah (Abschnitt 7).

**Bauaufwand:** geschätzt etwa 5½ Arbeitstage, dazu rund 4 h Rechenzeit für zwei vollständige Prüfrunden.

---

## 1. Was ich selbst nachgeprüft habe

### 1.1 Gate T (Seed 1, 365 Tage)

- **Aufbau:** `vergleich/werkzeug/gate_t.sh` ruft `node tools/simtest.mjs --gate --seeds 1` in vier Runden in wechselnder Reihenfolge
  auf, immer nur ein Prozess.
- **Umgebung:** Last vorher 0,1–1,1, kein fremder Rechenprozess über 20 %.
- **Rohdaten:** `mess/gate_t.txt` und `mess/gate_<variante>_<runde>.txt`.

| | Basis `6c1741e` | A Erfahrung | B Pläne | C sparsam |
|---|---|---|---|---|
| T Runde 1 / 2 / 3 / 4 (ms) | 3.596 / 3.369 / 3.369 / 3.067 | 3.831 / 3.842 / 3.678 / 4.054 | 3.646 / 3.623 / 3.609 / 3.711 | 3.112 / 3.065 / 3.064 / 3.195 |
| Median | 3.369 | 3.837 (**×1,14**) | 3.635 (×1,08) | 3.089 (×0,92) |
| Einwohner Tag 365 (Seed 1) | 1.169 | 1.454 | 1.229 | 1.214 |
| Gates Seed 1 | alle bestanden | alle bestanden | alle bestanden | alle bestanden |

**Einordnung**

- Alle vier Fassungen liegen ruhig unter 5 s.
- A ist am knappsten. Der Grund ist nicht die Buchführung, sondern dass Seed 1 mit Erfahrung um 24 % größer wird; das sagen die
  „leer“-Messungen von A und C übereinstimmend.
- Unter der Last anderer Agenten hat A laut Bericht für Seed 1 bis 5,2 s und einmal 6,8 s erreicht.
- Einzelne Läufe streuen um ±10 %. Dass C schneller als die Basis erscheint, ist Rauschen bzw. ein anderer Stadtverlauf und kein Gewinn.

### 1.2 Punkt 8: eigene Gegenprobe (`vergleich/werkzeug/probe8.mjs`, `mess/probe8_*.json`)

**Methode**

- **Unabhängig von den Probe-Schaltern der Entwürfe.** In den sim-Block wird nur ein Haken eingefügt: „nur wählen, nicht ausführen“.
- **Ablauf:** Vor jeder echten Entscheidung jedes Erwachsenen wählt dieselbe Person im selben Zustand mit demselben `S.rs` zweimal:
  - mit ihren Daten;
  - nachdem genau ihre Etappe-2-Felder auf den neutralen Wert gesetzt wurden (Verhalten wie Version 9).

  Danach wird alles zurückgesetzt.
- **Gelöscht wird je Entwurf:**
  - A: `erfN`/`erfWert`;
  - B: alle zehn Planfelder;
  - C: `erf` (Erfahrung), Planschritt „ansparen“ → „gründen“ (Plan), bzw. beides.

**Kontrollen**

- Die echte Wahl war in **allen** 10,9 Mio. Entscheidungen der drei Entwürfe gleich der Wahl „mit“ (dazu 3,5 Mio. der Basis mit
  demselben Haken).
- Der Fingerabdruck am Ende ist in 12 von 12 Läufen gleich einem Lauf ohne Haken.

**Ergebnis** (Seeds 1–3, je 730 Tage, stündlich, jede Entscheidung):

| Entwurf | Entscheidungen (S1 / S2 / S3) | anders ohne die Daten der Person | Anteil aller | davon direkt (betroffene Handlung beteiligt) | Bericht |
|---|---|---|---|---|---|
| A | 1.309.905 / 1.158.188 / 1.199.447 | 8.005 / 5.674 / 5.552 | 0,61 / 0,49 / 0,46 % | 90 / 88 / 87 % | 8.005 / 5.674 / 5.552: **gleich** |
| B | 1.178.909 / 1.243.266 / 1.271.971 | **88** / 6.869 / **69** | 0,007 / 0,55 / 0,005 % | 98 / 100 / 93 % | andere Zählung (7 und 18 Uhr, Tag 300–730): 50 / 6.733 / 70, gleiche Größenordnung |
| C, beides | 1.184.219 / 1.130.360 / 1.251.968 | 6.907 / 5.973 / 12.878 | 0,58 / 0,53 / 1,03 % | 89 / 88 / 91 % | **gleich**, auch die Teile |
| C, nur Erfahrung | wie oben | 4.414 / 3.791 / 10.160 | 0,37 / 0,34 / 0,81 % | 87 / 86 / 91 % | gleich |
| C, nur Plan | wie oben | 2.195 / 1.974 / 2.424 | 0,19 / 0,17 / 0,19 % | 92 / 92 / 93 % | gleich |

**Häufigste Paare** (ohne → mit):

- A: `job_wechseln → nichts`, `kuendigen → nichts`.
- B: `laden_gruenden → nichts`.
- C: `kuendigen → nichts`, `job_wechseln → nichts`, `laden_gruenden → nichts`.

**Lesart**

- A und C belegen Punkt 8 in jeder der drei Städte, und das nachgerechnet bis auf die einzelne Entscheidung.
- B belegt ihn überzeugend nur auf Stadtebene: Wiedergründung nach einer Pleite 13,9 % → 2,7 % (laut Bericht, Seeds 1–10).
  Auf einzelne Entscheidungen wirkt B in zwei von drei Städten kaum (88 bzw. 69 von über 1,1 Mio.). Die Lehre greift nur, wenn eine
  Person nach einer Pleite wartet **und** gerade gründen könnte.
- Etwa 10 % der Unterschiede sind indirekt. `entscheide` zieht Zufall nur, wenn er die Reihenfolge ändern kann; ändert sich ein Wert,
  verschiebt sich deshalb die Reihe der Zufallszahlen. Eine „Warum?“-Anzeige muss solche Fälle als „Zufall“ kennzeichnen.

### 1.3 Nebenbefund: Wer lernt was? Kündigungen nach Art

Gleicher Lauf wie 1.2, Seeds 1–3 zusammen, 730 Tage.

| | Basis | A | B | C |
|---|---|---|---|---|
| Kündigung = Renteneintritt | 2.544 | 2.642 | 2.656 | 2.564 |
| Kündigung für die **Elternzeit** | **5.747** | 1.582 (**−72 %**) | 6.466 (+13 %) | 1.224 (**−79 %**) |
| davon binnen 1 Tag wieder Arbeit gesucht | 5.079 (**88 %**) | 1.165 (74 %) | 5.831 (90 %) | 875 (71 %) |
| sonstige Kündigung | 1.794 | 470 (−74 %) | 1.840 (+3 %) | 246 (−86 %) |
| davon binnen 1 Tag wieder Arbeit gesucht | 1.649 (92 %) | – | – | – |

**Lesart**

- Die „−75 %“ bzw. „−80 %“ echten Kündigungen, die A und C berichten, bestehen zum größten Teil aus Elternzeit-Kündigungen.
- Schon heute sind das fast nie echte Elternzeiten: 88 % der Eltern suchen am nächsten Morgen wieder Arbeit (das Pingpong, das B gefunden
  hat). A und C lernen das Pingpong ab und damit auch den größten Teil der Elternzeit.
- Das macht Punkt 8 nicht falsch. Die sichtbarste Lehre ist dann aber die Korrektur eines Regelfehlers und nicht die Lehre aus einem echten
  Fehlschlag. Die Elternzeit (Betreuungsgehalt der Stadtregierung) verschwindet dabei weitgehend.
- In der Kassen-Zerlegung von C steigen bis Tag 730 die Kita-Kosten (−62.329 ± 23.906 Taler, 20 Seeds, laut Bericht). Ein Zusammenhang
  ist plausibel, aber nicht zerlegt. Entscheidung 3 in Abschnitt 7.

### 1.4 Spielstand-Größe (`vergleich/werkzeug/groesse.mjs`, wie `spielstandText`; `mess/groesse_*.jsonl`)

| Stadt | Basis | A | B | C |
|---|---|---|---|---|
| Byte je Person roh | 371 | 428 (+57) | 390 (+19) | 379 (+8) |
| Seed 1, Tag 365 (eigene Stadt) | 841.259 | 1.138.365 (1.454 Einw.) | 904.934 (1.229) | 998.150 (1.214) |
| Große Stadt Tag 750, **gleiche Stadt** (Schalter aus) | 4.174.563 | 4.721.185 | 4.357.173 | 4.251.482 |
| ebenso ohne `memName` | 3.867.825 | 4.414.447 | 4.050.435 | **3.944.744** |
| Große Stadt Tag 750, Schalter an (eigene Stadt) | – | 4.695.429 (7.120 Einw.) | 4.372.490 (6.914) | 4.136.834 (7.033) |

- Alle Zahlen stimmen auf das Zeichen mit den Berichten überein. Bei B ist die „gleiche Stadt“ jetzt gemessen; im Bericht war sie gerechnet.
- **Echte Grenze im Browser**, neu gemessen mit `vergleich/werkzeug/localstorage.cjs` (Chromium 141 headless, `file://`, Playwright):
  - `localStorage` nimmt unter `stadt-save-v1` höchstens **5.242.867 Zeichen** an. Mit dem Schlüssel sind das 5 × 1.048.576 Zeichen, bei
    5.242.868 kommt `QuotaExceededError`.
  - Eine geladene Policy liegt in derselben Herkunft unter einem eigenen Schlüssel (`ki/policy_v9_lokal_1.json`: 107.411 Byte).
  - Firefox und Safari habe ich nicht gemessen.
- **Große Stadt:** A läge mit 4,72 MB 0,52 Mio. Zeichen unter der Chromium-Grenze. C läge ohne `memName` unter der eigenen Warnschwelle von 4 MB.

### 1.5 Kritische Gate-Seeds (`simtest --gate --seeds 31,71,79`, `mess/gate_krit_*.txt`)

| Seed | Basis | A | B | C |
|---|---|---|---|---|
| 31 | Gate 4: 1,08 | 1,08 | 1,04 | **✗ Gate 4: 1,16** |
| 71 | Gate 4: 1,05 | 1,08 | 1,05 | **✗ Gate 7: −14,7 (n = 20)** |
| 79 | **✗ Gate 4: 1,18** | 1,05 | 1,06 | 1,06 |

Das bestätigt die Berichte:

- C hat auf Seeds 1–80 bei Gate 4 dieselbe Zahl wie heute (79 von 80), aber einen neuen roten Seed bei Gate 7.
- A und B sind bei Gate 4 laut Bericht 80 von 80; die drei Stichproben hier sind bei beiden grün.

### 1.6 Weitere Stichproben

- **Schalter aus bei C:** `R.GED = 0` rechnet auf einem neuen Seed (4, 300 Tage, stündlich) jeden Tag gleich wie `6c1741e`
  (`mess/aus_gleich_sparsam_s4.txt`).
- **Harte Grenze:** Die Diffs aller drei Entwürfe habe ich gelesen.
  - Kein neues Feld speichert Namen, Geschlecht, Herkunft, Eltern oder den Einzugstag.
  - C kopiert beim Verschieben in die Langzeit `memName`/`memRef`/`memGen` mit, wertet sie aber nicht aus.
  - Das alte `memName` (Name und Geschlecht der Bezugsperson) bleibt in allen drei Entwürfen stehen. Bei A und C bleibt es sogar länger im
    Gedächtnis, weil wichtige Einträge länger behalten werden.
- **Nicht nachgeprüft** (nur aus den Berichten übernommen):
  - Seeds 1–80 komplett;
  - die Muster über 20 Seeds;
  - `simtest_alle`, Migration und Aufholen.
  - Browser-Tests hat keiner der Entwürfe ausgeführt, ich auch nicht.

---

## 2. Bewertung nach den Kriterien

| Kriterium | A Erfahrung | B Pläne | C sparsam |
|---|---|---|---|
| **Punkt 8 belegt?** | ja, in jeder Stadt (0,46–0,61 % aller Entscheidungen; nachgerechnet gleich) | auf Stadtebene ja (Wiedergründung 13,9 → 2,7 %), je Entscheidung nur in 1 von 3 Städten | ja, in jeder Stadt (0,53–1,03 %; nachgerechnet gleich); Plan und Erfahrung einzeln belegt |
| **Was gelernt wird** | vor allem Elternzeit-Pingpong (−72 %), Wechsel mit Stellenverlust, Pleite | Pleite → länger sparen (am Charakter: Sparsame 180, Verschwender 60 Tage); Kündigungs-Lehre wirkt fast nie | wie A (−79 % Elternzeit), dazu „erst ansparen, dann gründen“ |
| **Rechenzeit** | Buchführung ≈ 0; **T ×1,14** (Seed 1 wächst um 24 %), unter Last > 5 s gemessen | Planteil ≈ 1,5 % (Profil); T ×1,08 | Buchführung ≈ 0 (×0,992 gepaart, 16 Paare); T ×0,92 bis ×1,05 |
| **Speicher** | +57 B/Person; große Stadt 4,72 MB (nahe der Chromium-Grenze 5,24 Mio.) | +19 B; 4,36 MB | **+8 B; 4,25 MB, ohne `memName` 3,94 MB** |
| **Gates Seeds 1–3** | grün (T knapp) | grün | grün |
| **Gate 4, Seeds 1–80** | 80/80 (Bericht) | 80/80 (Bericht) | 79/80 (Bericht), Seed 31 rot (nachgeprüft) |
| **andere Gates, 1–80** | 80/80 | 80/80 | **Gate 7: 79/80** (Seed 71, nachgeprüft) |
| **Stadtwirkung (80 Seeds, Bericht)** | nichts über 2 SE; Kasse Tag 730 −34.944 ± 24.792 | Kasse Tag 730 −6,5 % (p = 0,033), Gründungen −6 % | **Kasse Tag 365 −9,1 %, Gründungen −12,3 %** (beide deutlich); Pleitequote 53 → 49 % |
| **Abschnitt 4 abgedeckt** | Gedächtnis voll (Fakt, Bedeutung, Verweis), Erfahrung Situation × Handlung; **kein Plan** | Plan voll (ID, Schritte, Status, Frist, Abbruchgrund, Bilanz); **kein Gedächtnis**, Erfahrung nur als Zähler | **alle fünf Bausteine**, knapp: kein Fakt/Verweis je Erinnerung, Erfahrung ohne Situation |
| **Etappe 3: Merkmale ohne Lecks** | gut: 5 Werte (Erfahrung × Sicherheit der aktuellen Situation); keine fremden Daten | mittel: 10+ Werte, teils aus Regeln abgeleitet (`gruendungWartet`); Plan-Frist über 60 Tage sättigt `ziel_alter` | **am kompaktesten**: 4 Erfahrungswerte + Planschritt + Rücklagen-Lücke; keine fremden Daten |
| **Etappe 4: Hauptfiguren-Prompt** | **am reichsten**: „Pleite, Betrieb bestand 36 Tage, gegründet vor 36 Tagen“, Erfahrung mit Zahl; aber kein Plan | Plan als Satz („wartet: gründen ab Tag 563“); Gedächtnis weiter von Ziel-Einträgen verdrängt | Langzeit hält Wichtiges (47 % wichtige Ereignisse statt 19 % an Tag 730); Plan-Schritt; Fakten fehlen |
| **Wartbarkeit im sim-Block** | 186 Diff-Zeilen (≈ 160 neu), ein Abschnitt; Probe als Parameter (sauber); `Int8`/`Int16` → `TYPEN` in Modul-Skript und simtest; verrutschter Kommentar in `importZustand` | 214 Diff-Zeilen; 13 Funktionen; `zielPruefen` hat mit `R.PLAENE` einen zweiten Pfad (`planTag`); handgesetzte Formeln; Kündigungs-Lehre fast toter Code; `_plan` exportiert Interna | 234 Diff-Zeilen; nur `Uint8` (keine `TYPEN`-Änderung), Bit-Packing mit Hilfsfunktionen; **globaler Probe-Schalter `GED_PROBE`**; Umverteilung des Gedächtnisses bei der Migration ist der heikelste Teil; Abbruch „Pleite/Erfahrung“ im Spiel tot; `tools/kiepisode.mjs` zählt Ziel-Einträge sonst doppelt |
| **bestehende Tests (Bericht)** | 13/22 grün; Rest gewollt (Schalter, Version 10) + Gate T unter Last | 11/22; zusätzlich drei, weil die Stadt anders läuft (`sicherheit` = alter Fehler, `kita`/`kitest` = zu lose Testfälle) | 14/22; mit Schalter aus und 7 Ausnahmen sind alle Vergleiche grün |

**Gesamturteil**

- **A** ist die sauberste Umsetzung von „Erfahrung“ und „strukturierter Erinnerung“. A ist aber zu teuer im Speicher und hat bei Gate T das
  größte Risiko; Pläne fehlen ganz.
- **B** ist die beste Umsetzung von „Plan“. Der Nachweis je Entscheidung ist aber schwach, und Gedächtnis und Erfahrung im Sinne von
  Abschnitt 4 fehlen.
- **C** erfüllt alle Bausteine im Budget und belegt Punkt 8 gleich stark wie A. Dafür zahlt C mit Wirtschaftswirkung und zwei roten
  Seeds: Beides kommt vom Plan „erst ansparen“ für **alle** Gründer bzw. vom Chaos, und daran lässt sich drehen.

---

## 3. Empfehlung: C als Gerüst, mit Teilen von A und B

| Teil | Herkunft | Byte je Person | warum |
|---|---|---|---|
| Gedächtnis: 3 Kurzzeit- + 5 Langzeit-Plätze in den vorhandenen 8, feste Bedeutung je Ereignisart, deterministisch | C | 0 | hält Pleite, Kind, Partner länger; kostet nichts |
| Erfahrung für `laden_gruenden`, `kuendigen`, `job_wechseln`, `zusammenziehen`, gepackt (Wert −31…31, n 0–3) | C | 4 | eindeutige Folgen; Wohnungs-, Stellen- und Partnersuche begründet ausgelassen (C 1.3) |
| **× 2 Situationen** (Geld knapp / reicht) | A | +4 | Abschnitt 4 verlangt „je Situation × Handlung“; bei A gemessen ohne Nachteil |
| offene Handlung + Resttage; gelernt erst nach der Folge | C | 2 | – |
| Plan: Ziel als Kopf (ID = Ziel/`zielSeit`), Schritt, Grund des letzten Endes | C | 2 | – |
| Plan-Anzeige wie `planInfo` (Schritt, „wartet bis Tag …“, Frist, letzter Plan und Grund); Gründe „in Rente“, „anderes Ziel“ | B | 0 | für Karte und Sprachmodell |
| Rücklage vor der Gründung: **Umfang nach Entscheidung 2**; Wartezeit nach einer Pleite abhängig von der Sparsamkeit | B/C | 0 | der Charakter bleibt in der Lehre sichtbar |
| **letzte Entscheidung** je Person: Aktion, Tag, Quelle (Regeln / Policy / Sprachmodell / Fokus), geklappt | neu | 6 | Master-Prompt 12; das hat keiner der drei |
| **Fakt + Verweis** je Erinnerung (`memFakt` Int16 × 8, `memVon` Uint8 × 8) | A | +24 | Abschnitt 4 („Fakten“, „Verweis auf Ereignis“), Etappe 4 |
| `memName` aus dem Gedächtnis | – | **−32** | harte Grenze (Entscheidung 1) |
| Gegenprobe als Parameter `entscheide(S, p, h, probe)` statt globalem `GED_PROBE`; `Sim.warum(S, p, h)` liefert die Summanden je Aktion und die Wahl ohne Erfahrung bzw. ohne Plan (nur lesend, `S.rs` gesichert) | A | 0 | sauberer; Grundlage für „Warum?“ |
| Elternzeit-Kündigung wird **nicht** als Kündigungs-Erfahrung gelernt (wie der Renteneintritt) | neu | 0 | Entscheidung 3 |

**Summe:** +10 Byte je Person gegen heute (+42 neu, −32 `memName`). Die große Stadt läge damit bei **≈ 4,27 MB** (gerechnet:
4.174.563 + 10 × 4/3 × 7.188).

- Ohne Streichen von `memName` und dann auch ohne Fakt/Verweis wären es +18 Byte, ≈ 4,35 MB (gerechnet).
- Beides liegt unter der gemessenen Chromium-Grenze von 5,24 Mio. Zeichen, auch mit gespeicherter Policy.

**Bewusst nicht übernommen**

- Die Bilanz in der Zielwahl aus B: Sie verschiebt Freunde-Pläne zu Ruhe und bringt mehr Kündigungen (B 8.3).
- Die Kündigungs-Lehre aus B: Sie greift bei etwa 1 % der Kündigungen.
- Die eigene Bedeutung je Erinnerung aus A (+8 Byte): Den Ausgang trägt schon das Erfahrungs-Byte.
- Stärke von Bindungen und Verpflichtungen: Die gehören zu Etappe 5, zusammen mit Parks und Treffen.

**Warum nicht A allein:** Pläne fehlen, der Speicher ist hoch (4,72 MB), und Gate T ist am knappsten. **Warum nicht B allein:** Gedächtnis
und Erfahrung nach Abschnitt 4 fehlen, und je Entscheidung ist B nur in einer von drei Städten sichtbar.

---

## 4. Bauplan in überprüfbaren Schritten

Jeder Schritt endet mit Messungen, die sich wiederholen lassen. Gearbeitet wird zuerst auf einer Kopie; ins Repo kommt ein Schritt erst,
wenn seine Prüfung grün ist. Der Schalter `R.GED` bleibt: Mit 0 rechnet die Stadt Tag für Tag wie `6c1741e`.

**Schritt 0 – Vorarbeiten, getrennt von Etappe 2**

1. `opferWaehlen`: Ein Haushaltsvorstand in Haft ist kein Einbruchsopfer. Die Änderung bekommt einen eigenen Schalter; als Test dient der
   erzwungene Fall aus `plaene/werkzeug/opfer_haft_basis.mjs`.
2. Die Testfälle `--kita` (g) und `--kitest` 6 wählen ihren Fall strenger: keine Bund-Rolle, keine jüngeren Geschwister.
3. Die float32-Lücke in der Policy-Prüfung wird geschlossen; das steht in `GRENZEN.md`, und der sim-Block ändert sich ohnehin.

*Fertig, wenn:*
- `simtest_alle` 22 von 22 grün ist;
- `--kita` und `--kitest` auch auf den drei Prototyp-Kopien grün sind;
- mit allen Schaltern aus die Stadt Tag für Tag wie `6c1741e` rechnet (`tools/tagvergleich.mjs`).

**Schritt 1 – Simulation** (sim-Block, Version 10, Ausgang `sparsam/stadt/stadt.html`, dazu die Tabelle aus Abschnitt 3)

*Fertig, wenn:*
- **Schalter aus:** Seeds 1–3 über 730 Tage stündlich und als Tagesschritte jeden Tag gleich `6c1741e` (`aus_gleich`).
- **Punkt 8** (`vergleich/werkzeug/probe8.mjs`, angepasst):
  - echte Wahl = Probe in 100 % der Fälle;
  - Fingerabdruck mit und ohne Probe gleich;
  - in **jedem** der Seeds 1–3 sind ≥ 0,3 % der Entscheidungen anders, davon ≥ 85 % direkt;
  - das Löschen nur des einen Bytes stellt in ≥ 99 % der Fälle die Wahl ohne Erfahrung her.
- **Muster über 20 Seeds:**
  - Wiedergründung nach einer Pleite und sonstige Kündigungen liegen unter „Schalter aus“;
  - die Charakterabstände (Gründer-Ehrgeiz, Wegzieher-Heimat, Kündiger-Fleiß) behalten ihr Vorzeichen.
- **Gates:**
  - Seeds 1–3 in 3 von 3 Läufen grün;
  - Seeds 1–80: Gate 4 ≥ 79 von 80, alle anderen Gates 80 von 80 (Seed 71 ausdrücklich prüfen);
  - Kasse und Gründungen an Tag 365 und 730 gepaart über 80 Seeds gemeldet.
- **Rechenzeit:**
  - „leer“ (Buchführung ohne Wirkung) gepaart ≤ +3 % (16 Paare);
  - neue Funktionen im CPU-Profil ≤ 3 %;
  - Gate T Seed 1 im Wechsel mit `6c1741e` (4 Runden, ruhig) im Median ≤ +10 %.
- **Harte Grenze:**
  - Die neuen Funktionen lesen statisch geprüft keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, keinen Einzugstag und keine
    `memRef`-Bezüge.
  - Ein Namenstausch über 200 Tage bleibt bitgleich.

**Schritt 2 – Speicherformat 10 und Migration von Version 9**

- `MIGRIERBAR` bekommt die 9; die alte Kette läuft nur noch für Stände bis Version 8.
- `migriereGed` verteilt das Gedächtnis neu, wirft `memName` weg und setzt Fakt und Verweis auf 0.
- `gedPruefen` erkennt beschädigte Stände; ab Version 10 gibt es Pflichtfelder.

*Fertig, wenn:*
- `--migrationstest` die Versionen 2–9 übernimmt;
- ein Stand der Version 9 ohne Übernahme abgelehnt wird;
- ein Stand der Version 10 in Version 9 abgelehnt wird;
- mindestens 10 beschädigte Fälle abgelehnt werden;
- Speichern und Laden mitten am Tag bitgleich sind;
- Aufholen 1 × 90 = 3 × 30 bitgleich ist;
- die Größe gemessen ist (Seed 1 Tag 365/730, große Stadt Tag 750 ≤ 4,4 MB);
- ein Browser-Test den Stand der großen Stadt in `localStorage` schreibt und wieder liest.

**Schritt 3 – Personenkarte** („Erinnerungen / Plan / letzte Entscheidung + warum“)

- **Erinnerungen:** kurz und lang getrennt, mit Fakt und „weil …“ (Verweis). Namen lebender Personen kommen nur aus der Anzeige.
- **Erfahrung:** ein Satz mit Zahl, z. B. „Gründen: 1-mal, Pleite nach 36 Tagen → zählt −15“.
- **Plan:** Ziel, Schritt, Hindernis („spart: 1.928 von 2.600 Talern“), Frist, letzter Plan und Grund.
- **Letzte Entscheidung:** Aktion, Tag, Quelle, geklappt, dazu die offene Folge („wird noch 23 Tage beobachtet“).
- **Knopf „Warum?“** über `Sim.warum`: Summanden aus Lage und Charakter, Plan, Erfahrung und Zufall ±5, dazu „ohne diese Erfahrung: …“;
  indirekte Fälle heißen „Zufall“.
- **Optional:** Für die geöffnete Person und die Hauptfiguren merkt ein Beobachter außerhalb von `S` die letzten 5 Fälle „ohne Erfahrung
  hätte sie …“. Er ändert nichts; der Fingerabdruck-Test beweist das.

*Fertig, wenn* ein neuer Browser-Test einen gespeicherten Stand mit einem echten Fall öffnet (wie Seed 1, Person 57, Tag 330) und prüft:
- die Karte zeigt die Erfahrung „Gründen“ mit Zahl;
- „Warum?“ nennt „ohne Erfahrung: laden_gruenden“;
- in Erfahrung und Plan steht kein Name;
- die Karte funktioniert in Handybreite.

**Schritt 4 – Tests**

- **Neuer Modus `simtest --gedaechtnis`** mit:
  - kurzer Gegenprobe (Seeds 1–3, 365 Tage);
  - Schalter aus;
  - Gedächtnisgrenzen;
  - erzwungenem Planabbruch (Alter, Pleite, Ziel von außen);
  - ID-Wiederverwendung mit Generation;
  - Migration und beschädigten Ständen;
  - Aufholen;
  - Namenstausch und statischer Leseliste.
- **Bestehende Modi:**
  - `GED` kommt in die Aus-Listen, `PF_GED`/`ged` in die Ausnahmelisten (7 Stellen wie `sparsam/stadt_aus/simtest_ausnahmen.diff`).
  - `--kipolicy` vergleicht mit `GED = 0`.
  - Dass die Policy aus Version 9 abgelehnt wird, wird ausdrücklich geprüft.
  - `tools/kiepisode.mjs` zählt Ziele mit einem Schlüssel ohne Platz.
- **Browser:**
  - `p6migration` (neue Version 10, Übernahme eines Stands der Version 9 mit Größe);
  - `basis.cjs` (Kette bis 10);
  - `umgebung.cjs` (Fassung `6c1741e`);
  - `browser_ki` (Version 10, Ablehnung der alten Policy sichtbar);
  - der neue Karten-Test.

*Fertig, wenn* aus einer frischen Kopie `simtest_alle` alle Läufe grün sind (22 + neuer Modus) und `tests/alle.sh` alle Tests grün hat
(30 + neu). Die Seeds 1–80 werden wie in Schritt 1 gemessen.

**Schritt 5 – Doku**

- **`README.md`:** Speicherformat 10; Gedächtnis, Erfahrung und Plan; harte Grenze.
- **`docs/ARCHITEKTUR.md`:** Andockstellen: `erinnere`, `ausfuehren`, `menschenTag`, `entscheide`.
- **`docs/GRENZEN.md`:**
  - Ergebnisse je Folge sind Annahmen;
  - Elternzeit;
  - Gate T ist eng;
  - Chromium-Grenze gemessen, andere Browser nicht.
- **`docs/EXPERIMENTE.md`:** Policy V9 ungültig, Schema 3 in Etappe 3.
- **`docs/FORTSCHRITT.md`:** Etappe 2 und Punkt 8 mit Belegen.

*Fertig, wenn* jede Zahl in der Doku auf eine Datei in `berichte/` zeigt.

**Danach, in Etappe 3:**

- KI-Schema 3 mit etwa 7 neuen Merkmalen:
  - die 4 Erfahrungswerte der aktuellen Situation × Sicherheit;
  - offene Handlung ja/nein;
  - Planschritt „ansparen“;
  - Rücklagen-Lücke in Tageskosten, begrenzt.
- Keine Personen-ID, keine Bezüge auf andere, keine Fakten anderer. Indirektes Wissen wird dokumentiert: Die Rücklage folgt aus den
  Gründungskosten am Markt, wie schon in der Maske.
- Dann wird die Policy neu trainiert.

---

## 5. Aufwand (geschätzt, nicht gemessen)

| Schritt | Arbeit | Rechenzeit je Prüfrunde |
|---|---|---|
| 0 Vorarbeiten | ½ Tag | `simtest_alle` 12 min |
| 1 Simulation | 1½ Tage | Gegenprobe 3 Seeds ≈ 2 min, 20 Seeds Muster ≈ 10 min, Seeds 1–80 ≈ 17 min (2 Prozesse), T 4 Runden ≈ 4 min |
| 2 Speicherformat, Migration | ½ Tag | große Stadt ≈ 2 min je Fassung |
| 3 Personenkarte | 1½ Tage | Browser-Test einzeln |
| 4 Tests | 1 Tag | `simtest_alle` 12 min, `tests/alle.sh` 25 min |
| 5 Doku | ½ Tag | – |
| **Summe** | **≈ 5½ Arbeitstage** | **≈ 2 h je vollständiger Prüfrunde, zwei Runden eingeplant** |

---

## 6. Risiken

1. **Chaos in einzelnen Städten.** Jede Verhaltensänderung mischt, wer wann Zufall zieht. In C sind dadurch Seed 31 (Gate 4) und Seed 71
   (Gate 7) rot geworden. Ob die gebaute Fassung ≥ 79/80 hält, zeigt erst die Messung. Nachregeln verschiebt die Städte erneut. Schwellen
   werden nicht geändert.
2. **Gate T.** T hängt an der Größe von Seed 1. A zeigt, dass eine Verhaltensänderung allein T um 14 % heben kann (ruhig 3,7–4,1 s, unter
   Last > 5 s). T wird nur ruhig und im Wechsel mit der Basis abgenommen.
3. **Wirtschaft.** Eine Rücklage vor jeder Gründung kostet −12 % Gründungen und −9 % Kasse im ersten Jahr (C). Das kleinste Budget fiel in
   C auf 770 (Seed 3), Gate 3 verlangt ≥ 0. Hängt an Entscheidung 2.
4. **Elternzeit.** A und C lernen das Pingpong ab und damit fast die ganze Elternzeit (−72 % / −79 %). Die Kita-Kosten steigen vermutlich.
   Hängt an Entscheidung 3.
5. **Speicher.**
   - Die große Stadt bleibt über der eigenen Warnschwelle von 4 MB, wenn `memName` bleibt.
   - Die Chromium-Grenze liegt bei 5,24 Mio. Zeichen (Schlüssel + Wert, mit einem Schlüssel gemessen); eine gespeicherte Policy
     (≈ 0,1 MB) zählt in derselben Herkunft mit.
   - Firefox und Safari sind ungemessen.
6. **Policy aus Etappe 1.** Mit Version 10 wird sie abgelehnt („neu trainieren“), bis Etappe 3 neu trainiert. Entscheidet eine Policy,
   wirken die Erfahrungs-Summanden nicht (`kiHaken` kehrt vorher zurück). Sie muss die Erfahrung als Merkmal sehen (Schema 3).
7. **Ergebnisse sind Annahmen.** Was als gute oder schlechte Folge gilt (Pleite binnen 180 Tagen, wieder suchen binnen 30 Tagen …), ist
   gesetzt und nicht gelernt. Das naive Maß „Zufriedenheit danach“ ist ausdrücklich verworfen, weil es Umzug und Gründung ablernen würde
   (Bestand 3.3).
8. **Sichtbarkeit.** Nur 0,5–1 % der Entscheidungen ändern sich. Ohne „Warum?“ und Beobachter findet Noah die Fälle nicht; für die Demo
   (Etappe 5) liefern die Gegenprobe-Werkzeuge echte Beispiele.
9. **Wartbarkeit.** Die Umverteilung des Gedächtnisses bei der Migration und das Bit-Packing sind die fehleranfälligsten Stellen. Beide
   brauchen eigene Tests (Schritt 2 und 4).

---

## 7. Entscheidungen für Noah (nur Produktfragen, je mit Empfehlung)

1. **Namen im Gedächtnis streichen?**
   - Heute speichert jede Erinnerung an eine Person auch deren Namen und Geschlecht (`memName`). Keine Regel liest das, aber es verträgt sich
     nicht mit der harten Grenze.
   - Folge des Streichens: Der Lebenslauf Verstorbener nennt die Beziehung („dein früherer Partner“, „ein Freund“) statt des Namens.
   - Die große Stadt wird um 0,3 MB kleiner; der Platz reicht für Fakten und Verweise („Pleite, 36 Tage nach der Gründung“).
   - **Empfehlung: streichen.**
2. **Wer spart vor einer Gründung?**
   - **Alle:** Gründungen −12 %, Kasse im ersten Jahr −9 %, weniger Pleiten (53 → 49 %), Gründer danach zufriedener (gemessen in C).
   - **Nur wer schon einmal pleite war:** Wiedergründung nach einer Pleite 13,9 % → 2,7 %, Gründungen −6 %, Kasse im ersten Jahr −1 %
     (gemessen in B).
   - **Empfehlung: nur nach eigener Pleite bzw. schlechter Gründungserfahrung.** Sparsame warten länger, Verschwender kürzer. Die Lehre ist
     so an eine erlebte Folge gebunden, und die Wirtschaft bleibt näher an Version 9. Diese Kombination ist noch nicht gemessen; das
     geschieht in Schritt 1.
3. **Elternzeit: lernen oder ausnehmen?**
   - Heute kündigen Eltern abends für das Betreuungsgehalt und suchen in 88 % der Fälle am nächsten Morgen wieder Arbeit.
   - Mit Erfahrung (A, C) lernen sie das ab: Elternzeit-Kündigungen −72 bis −79 %. Die Elternzeit verschwindet damit fast.
   - **Empfehlung:** Elternzeit von der Kündigungs-Erfahrung ausnehmen, wie den Renteneintritt. Das Pingpong später als eigenen Plan
     „Elternzeit“ lösen (zu Hause bis Kita-Platz oder 3. Geburtstag). Das ist eine eigene, sichtbare Änderung.
4. **Experimentelle Policy aus Etappe 1:**
   - Mit Version 10 lässt sie sich nicht mehr laden, bis sie in Etappe 3 neu trainiert ist. Im Spiel steht dann sichtbar „neu trainieren“,
     und es entscheiden die Regeln.
   - **Empfehlung: in Ordnung.** Sie hat ihre Auswertung ohnehin nicht bestanden, und die Regeln sind Standard.

---

## 8. Dateien

- **Werkzeuge** (`SP/ml/e2/vergleich/werkzeug/`):
  - `gate_t.sh`: Gate T im Wechsel;
  - `probe8.mjs`: Gegenprobe mit Datenlöschung, Kündigungen nach Art, Fingerabdruck-Kontrolle;
  - `groesse.mjs`: Spielstand wie `spielstandText`;
  - `localstorage.cjs`: Chromium-Grenze.
- **Rohdaten** (`SP/ml/e2/vergleich/mess/`):
  - `gate_t.txt`, `gate_<variante>_<1–4>.txt`;
  - `probe8_{basis,erfahrung,plaene,sparsam}.json`;
  - `groesse_s1.jsonl`, `groesse_gross_{a,b}.jsonl`;
  - `gate_krit_*.txt`, `aus_gleich_sparsam_s4.txt`.
- **Nachrechnen:**
  - `node vergleich/werkzeug/probe8.mjs sparsam 1,2,3 730` (etwa 1 min je Entwurf);
  - `bash vergleich/werkzeug/gate_t.sh` (etwa 4 min, nur auf ruhigem Rechner);
  - `node vergleich/werkzeug/groesse.mjs <variante> 2 750 300000 [1]` (etwa 1–2 min).
