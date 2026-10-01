# STADT – Etappe 2: Erfahrung verblasst (`R.ERF_HALB`, Noahs Entscheidung 10)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`, Sicherung
vor den Änderungen `E/sicherung_verblassen` (= Schlussstand von SCHRITT2.md, `stadt.html` sha256 `6340538f…`, Sim-Hash `1d16a3626d8fb495`).
Rohdaten `E/mess/verblassen/`, Werkzeuge `E/werkzeug/vb_*`. Im Repo wird nichts geändert.

## Teil A – Festlegung vor dem Messen

**Festgelegt am 2026-09-30 um 20:16 UTC, vor der ersten Messung eines Kandidaten. Teil A wird danach nicht mehr geändert.** Eine Kopie mit
sha256 liegt in `mess/verblassen/teilA.md` bzw. `teilA.sha256`.

**Befund (SIM_FIX.md 4.1, gemessen):** Nach einer Pleite gründen mit Erfahrung 1,4 % wieder (20 Seeds × 730 Tage), ohne Erfahrung
(`R.GED = 0`) 14,3 %. Die Gegenprüfung B maß über 1.460 Tage 1,8 % gegen 16,3 %. `P.erf` verblasst bisher nie.

**Noahs Wunsch (Entscheidung 10):** Eine Erfahrung wird mit der Zeit schwächer. Wer pleite war, zögert lange, versucht es aber irgendwann
wieder (nach 1–2 Jahren wieder denkbar), Sparsame später als Verschwender.

**Ausgangsstand für die Messung:** `stadt/stadt.html` sha256 `5cb5ab12d6e60ce0…`, Sim-Hash `8a6edacb927463e3`, `GED: 1, GED_STAERKE: 1.5`,
`PLAN_RUECKLAGE: 1`, neu `ERF_HALB: 0` (kein Verblassen). Gebaut ist nur die Form aus A.1; gemessen ist bisher nur, dass sie gebaut ist wie
beschrieben (`mess/verblassen/bau/`): mit `ERF_HALB = 0` Tag für Tag gleich `sicherung_verblassen` (Seeds 1–3, 730 Tage, stündlich und in
Tagesschritten, `h0_gleich_*.txt`) und die Bauprüfung `werkzeug/vb_einheit.mjs` (`einheit.txt`). Keine Wiedergründung, keine Gates, kein
probe8 mit Verblassen.

### A.1 Form des Verblassens

- **Parameter** `R.ERF_HALB = H` (Tage). `H = 0`: kein Verblassen (bisheriges Verhalten).
- **Takt** `T = round(H / 15)` Tage. In der Nacht (`menschenTag`) verblassen bei jedem lebenden Erwachsenen `p` mit `(Tag + p) mod T = 0`
  alle 8 Erfahrungszellen (alle vier Handlungen, beide Lagen) um **einen Punkt zur 0 hin** (`erfVerblassen`). Die Zahl der Beobachtungen
  bleibt. Ist der Wert danach 0 (also vorher −1, 0 oder +1), ist die Erfahrung **vergessen**: Zelle 0, auch keine Beobachtungen mehr; das
  nächste Ergebnis zählt wie eine erste Erfahrung.
- **Folge:** Eine Pleite (−30) ist nach H Tagen halb so stark und nach 2 H Tagen vergessen; eine gute Gründung (+12) ist nach 12 T vergessen.
  Gilt für alle Erfahrungen gleich (Gründen, Kündigen, Wechseln, Zusammenziehen, beide Lagen, gute und schlechte).
- **Warum linear und kein neues Feld:** Der Wert steht als ganze Zahl im Erfahrungs-Byte. Ein exakter Verlauf `Wert × 0,5^(Alter/H)` bräuchte
  den Tag der letzten Beobachtung je Zelle (8 × 2 Byte je Person mehr: Speicherformat, Übernahme, `gedPruefen`, große Stadt ≈ 4,34 statt
  4,19 Mio. Zeichen). Ein Faktor je Takt auf die ganze Zahl wird durch Runden ohnehin fast überall zu „ein Punkt je Takt“ (gerechnet, nicht
  simuliert: `tmp/verblassen/kurve.mjs`, Takt H/12, Faktor 0,5^(T/H), gerundet und mindestens 1 Punkt – unter 27 fällt der Wert in jedem Takt
  um genau 1; ohne „mindestens 1 Punkt“ bliebe er unter etwa 9 für immer stehen). Darum gleich linear, ohne neues Speicherfeld. Speicherformat 10, Übernahme und `gedPruefen` bleiben, wie sie sind (verblasste Zellen sind gültige Zellen).
- **Weil der gespeicherte Wert selbst verblasst,** wirkt das überall, wo er zählt: `entscheide`, `zielWaehlen`, `planAbbruch` (Abbruch ab −20
  bei ≥ 2 Beobachtungen), die doppelte Rücklage nach schlechter Gründungserfahrung und die Karte. Eine neue Beobachtung mischt sich nach der
  unveränderten Lernregel mit dem verblassten Wert.
- **Reihenfolge in der Nacht:** vor der Frist der offenen Handlung (`erfTag`) derselben Nacht.
- **Annahme (gemeldet, nicht gemessen):** Weil der Takt je Person fest liegt, verblasst eine frische Erfahrung zum ersten Mal nach 1 bis T
  Tagen, im Mittel also etwa T/2 früher als „genau alle T Tage ab der Beobachtung“.
- Kein Zufall, liest und schreibt nur `P.erf`; keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein Einzugstag. Mit `R.GED = 0`
  läuft es nie; „Schalter aus“ bleibt damit Tag für Tag `6c1741e`.

### A.2 Kandidaten

**H = 180, 360, 540 Tage** (T = 12, 24, 36). Eine Pleite-Erfahrung ist dann nach einem halben, einem ganzen bzw. anderthalb Jahren halb so
stark und nach 1, 2 bzw. 3 Jahren vergessen. 360 statt 365, damit T ganzzahlig ist.

Dazu, **nur gemeldet** (keine Kandidaten):

- **H0:** der heutige Stand ohne Verblassen (`ERF_HALB = 0`);
- **sofort:** Messvariante, in der `erfLernen` nichts speichert (die Grenze H → 0: Erfahrung wirkt nie, alle Buchführung sonst gleich). Das
  ist die Obergrenze dessen, was Verblassen allein erreichen kann;
- **Bezug `R.GED = 0`** („ohne Erfahrung“).

### A.3 Zielgrößen

- **W(X): Wiedergründung nach Pleite.** Von den Personen (Platz + Generation, wie `folgen.mjs`) mit mindestens einer Pleite bis Tag X der
  Anteil, der nach seiner ersten Pleite bis Tag X wieder gegründet hat (ausgeführte Gründung). Seeds 1–20 zusammengezählt, X = 730 und 1.460.
  Beide aus demselben Lauf über 1.460 Tage je Seed (die ersten 730 Tage sind derselbe Lauf wie einer über 730 Tage). Werkzeug
  `werkzeug/vb_wieder.mjs`, Auswertung `vb_wieder_auswertung.mjs`.
- **Ziel erreicht:** W(1.460) des Kandidaten ≥ ½ · W(1.460) des Bezugs `R.GED = 0` (gleiches Werkzeug, gleiche Seeds).
- **Wartezeit nach Charakter** (Zielgröße, gemeldet, keine Bedingung, weil die Auswahlregel des Auftrags sie nicht enthält): Unter denen, die
  bis Tag 1.460 nach der ersten Pleite wieder gegründet haben, die mittlere Wartezeit (Tag der ersten Gründung nach der ersten Pleite minus Tag
  der ersten Pleite) der **Sparsamen** (Sparsamkeit ≥ 50) minus die der **Verschwender** (< 50). Erwartetes Vorzeichen: **> 0** (Sparsame
  später). Dazu je Gruppe die Zahl der Wiedergründer und W(1.460). Weicht beim gewählten H das Vorzeichen ab oder hat eine Gruppe weniger als
  10 Wiedergründer, steht das ausdrücklich in Teil B.

### A.4 Nebenbedingungen (je Kandidat)

- **N1 Gates** `simtest --gate` (730 Tage), Seeds 1–80, 2 Prozesse (Arbeitskopien `tmp/verblassen/h<H>`, in denen nur `ERF_HALB` gesetzt
  ist): Gate 4 in mindestens 79 von 80, Gates 1, 2, 3, 5, 6 je 80 von 80, **Gate 7 nach Entscheidung 8** (kein gewerteter Seed rot; nicht
  gewertet bei weniger als 15 Wegziehern, getrennt gezählt und gemeldet), kein Absturz. T wird in diesen Läufen nicht gewertet, B nur gemeldet.
  Auswertung mit `kal_lese.mjs` (`n1`).
- **N2 Punkt 8** mit probe8 (`werkzeug/vb_probe8.mjs` = `probe8.mjs`, liest die Datei der Arbeitskopie), Seeds 1–3, 730 Tage, mit Kontrollen:
  `probe8_auswertung.mjs` meldet „alle Kriterien erfüllt“ (jede Stadt ≥ 0,3 % anders ohne Erfahrung und Plan, davon ≥ 85 % direkt; ein Byte
  gelöscht ≥ 99 % wie ohne Erfahrung; echte Wahl = Probe; Beobachter = direkte Unterschiede; Fingerabdrücke gleich).
- **N3 Gate T:** Seed 1, `simtest --gate --seeds 1`, 4 Runden; jede Runde rechnet die Basis `6c1741e` (`sicherung_schritt0`), H0 und die drei
  Kandidaten, Reihenfolge je Runde verschoben (wie `kal_gate_t.sh`), immer nur ein Prozess und sonst kein Rechenprozess; vor jedem Lauf
  Uhrzeit, uptime und fremde Rechenprozesse. **Bedingung: Median T(H) der 4 Runden < 5.000 ms.** Gemeldet: gegen die Basis und gegen H0
  (Nachtrag 7: nicht wieder langsamer).
- **N4 kleinstes Budget ≥ 0** auf allen Seeds 1–80 (Gate 3 aus N1; der Vollständigkeit halber).
- **N5 Charakterabstände:** `werkzeug/vb_folgen.mjs neu 1-20 730` (= `folgen.mjs`, liest die Datei der Arbeitskopie) gegen `aus` (Seeds 1–20,
  730 Tage, im selben Werkzeug neu gerechnet): Alle 7 Abstände haben im Mittel über die 20 Seeds dasselbe Vorzeichen wie bei `aus`
  (Gründung/Ehrgeiz, sonstige Kündigung/Fleiß, Elternzeit-Kündigung/Fleiß, Wegzug/Heimat, Partnersuche/Geselligkeit, Stellensuche/Fleiß,
  Wechsel/Ehrgeiz).
- **Gemeldet, keine Bedingung:** Wirtschaft gepaart gegen `R.GED = 0` (Seeds 1–80 aus den Gate-Ausgaben: Einwohner, Kasse, Gründungen an Tag
  365 und 730; Mittel ± Standardfehler, in Prozent; `R.GED = 0` in einer Arbeitskopie `tmp/verblassen/ged0` neu gerechnet), Gate 4 größter
  Faktor, kleinstes Budget, Gate B, Z1/Z2 aus probe8, W(730), die Folgen-Muster (Kündigungen nach Art, Wiedergründung) und T absolut.

### A.5 Auswahlregel

1. **Erfüllt** ist ein Kandidat, der N1–N5 erfüllt.
2. **Gewählt wird das größte H** (das schwächste Verblassen, damit Erfahrung möglichst lange wirkt), **das das Ziel erreicht (A.3) und
   erfüllt ist.**
3. **Erreicht kein erfüllter Kandidat das Ziel:** Gewählt wird der erfüllte Kandidat mit der höchsten W(1.460) (Gleichstand: das größere H).
   Die Zielverfehlung steht dann ausdrücklich in Teil B, mit W von „sofort“ (Obergrenze des Verblassens) zur Einordnung, als Frage an Noah.
4. **Ist kein Kandidat erfüllt,** bleibt `ERF_HALB = 0` (kein Verblassen), mit dem Grund je Kandidat.
5. Der gewählte Kandidat wird **einmal** auf den Seeds 81–160 bestätigt (`simtest --gate` wie N1: Gate 4 ≥ 79 von 80, Gates 1, 2, 3, 5, 6 je
   80 von 80, Gate 7 ohne roten gewerteten Seed, kein Absturz). Fällt die Bestätigung durch, bleibt `ERF_HALB = 0`; eine zweite Bestätigung
   gibt es nicht.
6. Die Schwellen der Gates werden nicht geändert, keine Seeds ausgelassen, keine Kandidaten nachträglich ergänzt. Ein Absturz der Simulation
   zählt als „nicht erfüllt“. Ein Fehler in einem Messwerkzeug wird am Werkzeug behoben (nicht an der Simulation) und die Messung wiederholt,
   höchstens zweimal.

### A.6 Erwartung vorab (nicht gemessen, nur zur Einordnung)

- Aus der Zerlegung in SIM_FIX.md 4.1 (730 Tage): Wirkt die Erfahrung beim Gründen gar nicht, gründen 3,9 % wieder (statt 1,4 %, Bezug
  14,3 %). Bremse (fehlende Rücklage) und Wartezeit bleiben mit Verblassen bestehen. **Vermutung:** Verblassen allein erreicht die Hälfte des
  Bezugs über 1.460 Tage nicht; dann greift A.5 Punkt 3. „sofort“ zeigt, wie weit Verblassen überhaupt kommen kann.
- Verblassen wirkt auf alle vier Handlungen. Z1 (Anteil anders entschiedener Entscheidungen) sinkt voraussichtlich; N2 verlangt je Stadt
  weiterhin ≥ 0,3 %.

### A.7 Danach (Teil B)

1. Vor jeder Änderung an der Baukopie liegt die Sicherung `E/sicherung_verblassen` (vor dem Bau). Das gewählte H wird Standard `R.ERF_HALB` in
   `stadt/stadt.html`; geändert werden nur dieser Wert und sein Kommentar.
2. Mit genau diesem Stand (sha256 im Protokoll), immer nur ein Prozess, soweit nicht anders gesagt:
   - probe8 Seeds 1–3, 730 Tage, mit Kontrollen (Zahl für Zahl gleich der Messung des Kandidaten);
   - `simtest --gate` (Seeds 1, 2, 3; alle Zeilen ohne Wandzeiten gleich den Ausgaben des Kandidaten);
   - Gate T 4 Runden im Wechsel mit `6c1741e` (`gate_wechsel1.sh 4 1`, allein);
   - `simtest --speichertest`, `--aufholtest`, `--migrationstest --git <repo>`;
   - „Schalter aus“ Tag für Tag gleich `6c1741e` (`s2_gleich.mjs --gegen basis --aus`, Seeds 1–3, 730 Tage, stündlich und in Tagesschritten);
   - harte Grenze (statisch mit `erfVerblassen`, Namenstausch Seeds 1 und 2 × 200 Tage);
   - `simtest_alle` (`JOBS=2`), verglichen mit dem Lauf aus Schritt 2 (`mess/schritt2/simtest_alle`) nach Prüfergebnis.
3. Gemeldet in Teil B: Wirtschaft gepaart gegen `R.GED = 0` (Seeds 1–80) und wie viele Städte Gate 7 „nicht gewertet“ haben (1–80, 81–160,
   Seeds 1–3 der Schlussmessung). Kurzfassung in KALIBRIERUNG.md Teil G.

### A.8 Rechner

Höchstens zwei Rechenprozesse gleichzeitig. Gate T läuft allein. Last und fremde Rechenprozesse werden vor jedem Abschnitt notiert. Die
Server auf 8000 und 11434 werden nicht angefasst; der fremde Seitenserver auf 9092 (PID 29108, aus dem begonnenen Schritt 3) ebenfalls nicht.

## Teil B – Ergebnisse (geschrieben am 2026-09-30, 21:05 UTC)

Teil A ist unverändert (Abschnitt gleich `mess/verblassen/teilA.md`, sha256 `15f1aa32…`, nach dem Schreiben von Teil B geprüft). Die Messungen
liefen 20:18–21:01 UTC. Die Sitzung wurde um 20:48 UTC neu gestartet. Danach wurde nichts neu gemessen, was schon vorlag. Nachgerechnet
bzw. neu sind nur: Diagnose und Anpassung des Tests „halb bezahlt“ (B.6), `simtest_alle` mit dem endgültigen Stand, die unabhängige
Nachrechnung der Wirtschaft (`werkzeug/vb_wirtschaft_nach.py`) und die zusätzlichen Auswertungen in B.2 und B.8 aus vorhandenen Rohdaten.

### B.0 Ergebnis

- **Gebaut wie A.1:** `R.ERF_HALB`, `erfVerblassen` und der Takt in `menschenTag`, ohne neues Speicherfeld. Die Bauprüfung
  `vb_einheit.mjs` ist grün (256 Zellwerte, richtige Nächte, nur lebende Erwachsene, mit `ERF_HALB = 0` und `R.GED = 0` kein Aufruf).
- **Alle drei Kandidaten 180, 360, 540 erfüllen N1–N5.**
- **Keiner erreicht das Ziel.** Verlangt war W(1.460) ≥ ½ · 16,96 % = 8,48 %. Gemessen: 180 → 5,48 %, 360 → 2,77 %, 540 → 3,30 %.
- **Gewählt nach A.5 Punkt 3:** Keiner erreicht das Ziel, also der erfüllte Kandidat mit der höchsten W(1.460). Das ist **H = 180**.
- **Bestätigung auf den Seeds 81–160 bestanden.** `ERF_HALB: 180` ist Standard in `stadt/stadt.html`.
- **Zielverfehlung, Frage an Noah:** Selbst „sofort vergessen“ (Erfahrung wirkt nie) kommt nur auf 7,25 %. Verblassen allein kann das Ziel
  also nicht erreichen. Die Hälfte des Werts ohne Erfahrung verhindern Rücklagen-Bremse, Wartezeit und Sperre, die bleiben (A.6).
- **Die Zeitskala** (B.8) macht „nach 1–2 Jahren wieder“ in Spieltagen für niemanden möglich, auch ohne Erfahrung.
- **Endstand:** `stadt/stadt.html` sha256 `5ec4b62d68f2399b…`, Sim-Hash `1009eec6c4b8d852`; `tools/simtest.mjs` sha256 `f5fc192374b72ac2…`.
  Mit allen Schaltern aus rechnet die Stadt Tag für Tag gleich `6c1741e`. Im Repo ist nichts geändert (`git status` leer, HEAD `6c1741e`).

### B.1 Wiedergründung nach Pleite (A.3; Seeds 1–20 × 1.460 Tage, `vb_wieder.mjs`, `mess/verblassen/kand/wieder_*.json`, `tabelle.txt`)

| Variante | W(730) | **W(1.460)** | Ziel ≥ 8,48 % | Wartezeit Ø Sparsame / Verschwender (Tage) | Sparsame − Verschwender | Wiedergründer Sparsame / Verschwender |
|---|---|---|---|---|---|---|
| Bezug `R.GED = 0` | 734/5.150 = 14,3 % | 1.059/6.245 = **16,96 %** | – | 210,5 / 206,7 | +3,9 | 500 / 559 |
| H0 (kein Verblassen) | 56/3.999 = 1,4 % | 110/4.743 = 2,32 % | nein | 313,7 / 270,3 | +43,5 | 27 / 83 |
| **H = 180** | 127/4.172 = 3,0 % | 292/5.328 = **5,48 %** | nein | 290,7 / 264,0 | **+26,6** | 85 / 207 |
| H = 360 | 75/3.929 = 1,9 % | 127/4.590 = 2,77 % | nein | 316,0 / 269,2 | +46,8 | 28 / 99 |
| H = 540 | 96/4.395 = 2,2 % | 165/5.007 = 3,30 % | nein | 291,6 / 261,0 | +30,6 | 39 / 126 |
| „sofort“ (Obergrenze) | 248/4.968 = 5,0 % | 486/6.707 = 7,25 % | nein | 267,2 / 253,2 | +14,1 | 181 / 305 |

- **Mit H = 180 gründen nach einer Pleite 2,4-mal so viele wieder wie ohne Verblassen** (5,48 % gegen 2,32 %). Das ist etwa ein Drittel des
  Werts ohne Erfahrung (32 %), die Obergrenze „sofort“ liegt bei 43 %.
- **Sparsame später als Verschwender:** Das Vorzeichen stimmt bei allen Varianten. Mit H = 180 warten Sparsame im Mittel 26,6 Tage länger,
  beide Gruppen haben mindestens 10 Wiedergründer. Sparsame gründen auch seltener wieder: 3,1 % gegen 8,1 %.
- **360 liegt unter 540** (2,77 % gegen 3,30 %). Personen als unabhängig gerechnet, ist der Standardfehler je etwa 0,25 Prozentpunkte, der
  Abstand also etwa 1,5 Standardfehler; die Städte streuen zusätzlich. Das werte ich als Streuung, nicht als Wirkung (Annahme, nicht
  zerlegt). H = 180 liegt mit 5,48 % deutlich über beiden.
- **Warum nur H = 180 viel bewirkt** (aus der Regel gerechnet, nicht simuliert): Nach der Pleite ist Gründen 180 Tage gesperrt. Am Ende der
  Sperre steht die Pleite (−30) bei H = 180 auf etwa −15 (15 Takte zu 12 Tagen), bei H = 360 auf etwa −22 (7–8 Takte zu 24 Tagen), bei
  H = 540 auf etwa −25 (5 Takte zu 36 Tagen). Das Fenster zum Wiedergründen schließt spätestens etwa 420 Tage nach der Pleite (B.8).

### B.2 Wiedergründung in einem Jahr nach der Pleite (zusätzliche Auswertung, nicht in Teil A, nur gemeldet)

Aus denselben Rohdaten (`werkzeug/vb_wieder_fenster.py`, `mess/verblassen/wieder_fenster.txt`) werden nur Personen mit erster Pleite bis
Tag 730 gezählt, die also mindestens 730 Tage beobachtet sind. Gezählt wird, wer innerhalb von 365 Tagen nach der Pleite wieder gründet.
Innerhalb von 730 Tagen sind es **genau dieselben Zahlen**: Nach mehr als 365 Tagen gründet niemand wieder.

| | `R.GED = 0` | H0 | **H = 180** | H = 360 | H = 540 | „sofort“ |
|---|---|---|---|---|---|---|
| wieder gegründet in 365 Tagen | 17,5 % | 2,4 % | **5,8 %** | 2,8 % | 3,4 % | 7,6 % |
| Sparsame / Verschwender | 16,7 / 18,4 % | 1,1 / 3,8 % | **3,1 / 8,9 %** | 1,1 / 4,8 % | 1,6 / 5,5 % | 5,0 / 10,6 % |

Die Wartezeit bis zur Wiedergründung liegt in allen Varianten zwischen 180 und 358 Tagen (`R.GED = 0`: 180–356, Median 188; H = 180:
186–357, Median 276).

### B.3 Nebenbedingungen je Kandidat (A.4, Seeds 1–80 bzw. 1–3 bzw. 1–20)

| | H = 180 | H = 360 | H = 540 | zum Vergleich H0 (KALIBRIERUNG.md Teil C) | `R.GED = 0` |
|---|---|---|---|---|---|
| **N1** Gates 1, 2, 3, 5, 6 | je 80/80 | je 80/80 | je 80/80 | je 80/80 | je 80/80 |
| **N1** Gate 4 (≥ 79/80), größter Faktor | 80/80, 1,11 | 79/80 (Seed 67), 1,18 | 80/80, 1,13 | 79/80 | 79/80 (Seed 79) |
| **N1** Gate 7 gewertet (alle bestanden) / nicht gewertet | 55 / **25** | 61 / 19 | 55 / 25 | 64 / 16 | 78 / 2 |
| kleinster gewerteter Abstand Gate 7 | 20,2 | 18,8 | 18,5 | 16,8 | – |
| Abstürze | 0 | 0 | 0 | 0 | 0 |
| **N2** probe8 Z1 Seeds 1 / 2 / 3 (jede ≥ 0,3 %) | 1,332 / 0,886 / 0,654 % | 0,993 / 0,624 / 0,552 % | 1,449 / 1,262 / 0,646 % | 1,453 / 0,973 / 0,837 % | – |
| Z1 Mittel; Z2 je Stadt und Tag | 0,957 %; 15,5 | 0,723 %; 11,1 | 1,119 %; 17,5 | 1,088 %; 17,7 | – |
| probe8 „alle Kriterien erfüllt“ | ja | ja | ja | ja | – |
| **N3** Gate T Median (4 Runden, allein) | 1.796 ms | 1.748 ms | 1.665,5 ms | 1.586 ms | – |
| **N4** kleinstes Budget | 1.741 | 1.741 | 1.741 | 1.741 | 1.710 |
| **N5** 7 Charakterabstände, Vorzeichen wie `aus` | 7 von 7 | 7 von 7 | 7 von 7 | – | – |
| **erfüllt / Ziel** | **ja / nein** | ja / nein | ja / nein | | |

- **N3 im selben Wechsel:** Basis `6c1741e` 5.618, 4.459, 4.594, 5.058 ms, Median 4.826 ms. H0 1.429, 1.548, 1.624, 1.681 ms. H = 180 1.838,
  1.754, 1.844, 1.576 ms, gegen die Basis 0,372, gegen H0 +13,2 %.
- **Je Personentag rechnet H = 180 so schnell wie H0:** Seed 1 hat bis Tag 365 grob 201.000 Personentage gegen 186.000 bei H0 (+8 %; Trapez
  über die 30-Tage-Zeilen der Gate-Ausgabe). Das ergibt 8,9 gegen 8,5 µs je Personentag, H = 360 und 540 liegen bei 8,5 und 8,7 µs.
- **N5 Abstände (H = 180, Mittel über 20 Seeds, in Klammern `aus`):**
  - Gründung/Ehrgeiz +19,8 (+19,5), sonstige Kündigung/Fleiß −32,8 (−35,6), Elternzeit-Kündigung/Fleiß −20,3 (−26,3);
  - Wegzug/Heimat −26,7 (−26,3), Partnersuche/Geselligkeit +10,4 (+10,5), Stellensuche/Fleiß −6,9 (−18,3), Wechsel/Ehrgeiz +4,1 (+4,6).
  - Die Stellensuche ist schwächer als bei `aus`, aber bei allen drei Kandidaten gleich (−6,5 bis −6,9), hängt also nicht an H. H0 ist in
    dieser Phase nicht mit `vb_folgen.mjs` gerechnet.

### B.4 Auswahl (A.5) und Bestätigung

- Erfüllt sind 180, 360 und 540. Erfüllt und mit erreichtem Ziel ist keiner. Nach Punkt 3 wird der erfüllte Kandidat mit der höchsten
  W(1.460) gewählt: **H = 180** (5,48 % gegen 2,77 % und 3,30 %).
- **Bestätigung Seeds 81–160** (einmal, `mess/verblassen/bestaetigung_h180/`, 20:36–20:38 UTC, 2 Prozesse, fremde Rechenprozesse 0):
  - Gates 1, 2, 3, 5, 6 je 80/80; Gate 4 **80/80** (größter Faktor 1,14);
  - Gate 7 **57 gewertet, alle bestanden** (kleinster Abstand 17,9), **23 nicht gewertet**;
  - kleinstes Budget 772, 0 Abstürze. **Bestanden.**
  - Nicht gewertet: Seeds 85, 87, 94, 103, 105, 107, 111, 112, 113, 115, 116, 119, 121, 126, 127, 131, 133, 136, 137, 138, 139, 142, 151.
- **Standard:** In `stadt/stadt.html` stehen `ERF_HALB: 180` und der Kommentar (zwei Zeilen mehr). Gegen die Kandidatenkopie
  `tmp/verblassen/h180` unterscheidet sich nur der Kommentar, darum ein anderer Sim-Hash (`1009eec6…` gegen `ce0a6794…`) bei gleichen
  Ergebnissen (B.5).

### B.5 Schlussmessung mit genau diesem Stand (A.7.2; `mess/verblassen/schluss/`, Protokoll mit sha256 vor jedem Abschnitt `schluss.log`)

Stand: `stadt.html` `5ec4b62d…`, `ERF_HALB: 180`, `GED: 1, GED_STAERKE: 1.5`. Immer ein Prozess, `simtest_alle` mit zwei. Vor jedem
Abschnitt war die Zahl fremder Rechenprozesse 0, die Last lag zwischen 1,1 und 1,4.

- **probe8, Seeds 1–3, 730 Tage, mit Kontrollen:** „alle Kriterien erfüllt“.
  - `erg` ist Zahl für Zahl gleich der Kandidatenmessung H = 180.
  - Z1 1,332 / 0,886 / 0,654 % (Mittel 0,957 %), davon direkt 94,8 / 91,3 / 90,1 %.
  - Ein Byte gelöscht, danach wie ohne Erfahrung: 99,95 / 99,86 / 99,98 %.
  - Beobachter 16.940 / 9.553 / 7.457 Meldungen = direkte Unterschiede, fehlend 0, zu viel 0.
  - Echte Wahl = Probe, Fingerabdrücke gleich.
- **`simtest --gate` (Seeds 1, 2, 3):** „Gate Phase 0: BESTANDEN“. Je Seed sind alle 46 Zeilen ohne Wandzeiten gleich der Kandidatenmessung.
  - Gates 1–6, T und B grün.
  - **Gate 7 in allen drei Seeds nicht gewertet:** n = 13 / 7 / 13; Abstände −33,3 / −20,9 / −32,7, nur gemeldet.
  - Einwohner Tag 365 / 730: 1.307 / 1.625, 1.219 / 1.402, 1.292 / 1.460. T 1.531 / 760 / 689 ms.
- **Gate T, 4 Runden im Wechsel mit `6c1741e`** (`gate_wechsel1.sh 4 1`, 20:39–20:41 UTC, allein):
  - neu 1.725, 1.672, 1.480, 1.524 ms, **Median 1.598 ms**, 4 von 4 unter 5.000;
  - Basis 4.640, 4.449, 4.431, 4.694 ms, Median 4.544,5 ms;
  - **neu/Basis 0,352.** In KALIBRIERUNG.md Teil C (Stand vor dem Verblassen) war das Verhältnis 0,370, also **nicht langsamer**
    (Nachtrag 7). Je Personentag 7,9 µs.
- **`--speichertest`:** grün.
  - Gedächtnis Version 10 mitten am Tag (384 offene Handlungen, 678 Erfahrungen) ist 60 Tage später bitgleich.
  - 23 beschädigte Stände werden abgelehnt.
- **`--aufholtest`:** grün. (a) und (b) sind bitgleich; (c) bleibt die bekannte Näherung (Hinweis, keine Prüfung).
- **`--migrationstest --git <repo>`:** grün, 368 ok, 0 FEHL.
- **Schalter aus = `6c1741e`** (`s2_gleich.mjs --gegen basis --aus`, Seeds 1–3, 730 Tage): stündlich und in Tagesschritten je 730 von 730
  Tagen gleich (bis auf memName und die Version).
- **Harte Grenze** (`vb_harte_grenze.mjs`):
  - statisch in Ordnung: `erfVerblassen` liest und schreibt nur `P.erf`; keine Namen, kein Geschlecht, keine Herkunft, keine Eltern, kein
    Einzugstag;
  - Namenstausch mit Stärke 1,5 und `PLAN_RUECKLAGE = 1`, Seeds 1 und 2 × 200 Tage: jeden Tag alles gleich.
- **`simtest_alle`, erster Lauf** (20:44–20:49 UTC, alter Test): 14 von 22 mit Exit 0. Neu rot war `--sicherheit` „halb bezahlt“, siehe B.6.
- **`simtest_alle` nach der Testanpassung** (20:55–21:01 UTC, `mess/verblassen/testfix/simtest_alle/`): **15 von 22 mit Exit 0, wie
  Schritt 2.**
  - Nach Prüfergebnis (`nachkal_status_vergleich.mjs` gegen `mess/schritt2/simtest_alle`) kippen nur die drei Gate-7-Zeilen der Seeds 1–3
    von ✓ auf „nicht gewertet“ (Entscheidung 8, nicht rot).
  - Die roten Läufe sind dieselben wie in Schritt 2, mit derselben Zahl roter Prüfungen: `erweiterung` 7, `kipolicy` 3,
    `kipolicy_datei` (Ablehnung), `rathaus` 2, `schule` 1, `techfrueh` 3, `wachstum` 3. Es sind die Vergleiche mit alten Fassungen, die in
    Schritt 4 angepasst werden.
  - `--wachstum` D ist grün: schnell 258 gegen normal 215 Einwohner (Seed 5, Tag 150).

### B.6 Test „halb bezahlt“ (`simtest --sicherheit`) begründet angepasst

- **Befund:** Mit H = 180 ist Seed 2 an Tag 300 eine andere Stadt. Der Test nimmt die erste passende Person; das ist jetzt Person 6: 65 Jahre,
  keine Stelle, 46,3 Beitragsjahre, also in Rente vor 67.
  - Die Simulation rechnet den Tagessatz nach § 40 StGB aus der Rente (`einkommenTag`: 1,808 je Tagessatz).
  - Der Test kannte nur „Stelle“ oder „Lebenshaltung“ und rechnete 0,740. Deshalb erwartete er 15 offene Tagessätze, das Urteil nannte 24.
  - Vorher (Stand vor dem Verblassen) war es eine 50-Jährige mit Stelle; dort rechnen beide 2,603 (`werkzeug/vb_sich_fall.mjs`).
  - Die Simulation ist richtig, dem Test fehlte ein Fall.
- **Anpassung** in `tools/simtest.mjs`, nur in diesem Fall:
  - Der Test rechnet das Tagesnetto selbst, mit denselben Fällen wie die Simulation: Stelle zum heutigen Steuersatz (im Dienst der Sold),
    sonst Rente der heutigen Stufe (ab 67 oder vor 67 ohne Stelle nach 45 Beitragsjahren), sonst Lebenshaltung.
  - Die Zeile nennt zusätzlich „Tagessatz aus …“. Nichts ist gelöscht, keine Schwelle geändert.
  - Sicherung vorher: `sicherung_verblassen_testfix/` (simtest `bdf42513…`).
- **Nachgewiesen** (`mess/verblassen/testfix/`, Kopien `tmp/verblassen/testfix/`):
  - `R.GED = 0`: alter und neuer Test geben Zeile für Zeile dasselbe (bis auf „Tagessatz aus Lohn“); beide grün.
  - Stand vor dem Verblassen mit neuem Test: gleich dem Lauf aus Schritt 2 (bis auf den Zusatz).
  - Baukopie: 29 ok, 0 FEHL, „Tagessatz aus Rente“, „15 davon nicht“.
  - **Gegenprobe:** In einer Kopie ist der Rentenzweig aus `einkommenTag` entfernt. Der neue Test ist dort rot. Er erkennt also einen
    falschen Tagessatz und ist nicht schwächer geworden.

### B.7 Wirtschaft gepaart und Gate 7 „nicht gewertet“ (A.7.3)

**Wirtschaft mit H = 180, gepaart gegen `R.GED = 0`**, Seeds 1–80 aus den Gate-Ausgaben: Mittel der Differenz ± Standardfehler, Anteil am
Mittel des Bezugs, Seeds höher / niedriger. „Kasse“ ist die Spalte Budget der Stadt. Mit eigenem Skript nachgerechnet
(`werkzeug/vb_wirtschaft_nach.py`), Zahl für Zahl gleich `tabelle.txt`.

| | **H = 180 gegen `R.GED = 0`** | H0 gegen `R.GED = 0` (Teil C) | H = 180 gegen H0 |
|---|---|---|---|
| Einwohner Tag 365 | +22 ± 9 (+1,7 %, ↑50/↓30) | +42 ± 10 (+3,3 %) | −20 ± 9 (−1,6 %) |
| Einwohner Tag 730 | −0 ± 8 (−0,0 %, ↑40/↓40) | +20 ± 9 (+1,4 %) | −20 ± 8 (−1,4 %) |
| Kasse Tag 365 | −48.330 ± 10.226 (−4,7 %, ↑21/↓59) | −37.232 ± 12.190 (−3,6 %) | −11.098 ± 8.959 (−1,1 %) |
| Kasse Tag 730 | −162.364 ± 21.940 (−17,1 %, ↑17/↓63) | −140.240 ± 25.215 (−14,8 %) | −22.124 ± 22.589 (−2,7 %) |
| Gründungen bis Tag 365 | −49 ± 8 (−15,5 %, ↑18/↓60) | −46 ± 8 (−14,4 %) | −3 ± 8 (−1,2 %) |
| Gründungen bis Tag 730 | −59 ± 17 (−11,9 %, ↑27/↓53) | −64 ± 17 (−12,9 %) | +5 ± 14 (+1,2 %) |

Gegen H0 liegen die Unterschiede bei Kasse und Gründungen innerhalb von etwa 1,2 Standardfehlern. Bei den Einwohnern sind es gut 2
Standardfehler weniger (−1,4 bis −1,6 %).

**Gate 7 „nicht gewertet“ (weniger als 15 Wegzieher bis Tag 365, Entscheidung 8) mit H = 180:**

| | nicht gewertet | gewertet (alle bestanden) | Wegzieher je Stadt: Median (Spanne); Summe |
|---|---|---|---|
| Seeds 1–80 | **25 von 80** | 55 | 18 (6–39); 1.563 |
| Seeds 81–160 | **23 von 80** | 57 | 18 (5–40); 1.472 |
| Schlussmessung Seeds 1–3 | **3 von 3** | 0 | 13 / 7 / 13 |
| zum Vergleich H0 (Teil C): 1–80 / 81–160 | 16 / 33 | 64 / 47 | 18 / 16; 1.563 / 1.366 |
| zum Vergleich `R.GED = 0`: 1–80 | 2 | 78 | 30 (9–62); 2.543 |

- Über 160 Seeds sind es 48 nicht gewertete Städte gegen 49 bei H0. Auf 1–80 ist die Wegzieher-Summe gleich (1.563). Die Verschiebung zwischen
  den Seed-Bereichen werte ich als Streuung um die Schwelle 15.
- **Zu beachten:** Im Standardlauf `simtest --gate` (Seeds 1–3) wird Gate 7 jetzt in keinem Seed gewertet.
- Nicht gewertet auf 1–80: Seeds 1, 2, 3, 4, 6, 7, 9, 10, 17, 20, 25, 27, 32, 34, 35, 36, 46, 55, 56, 64, 67, 68, 71, 74, 77.

### B.8 Einordnung für Noah: Zeitskala „1–2 Jahre“ (aus dem Code gelesen und an den Rohdaten geprüft)

- **Zwei Uhren:** Ein Lebensjahr dauert 10 Spieltage (`R.JAHR = 10`). Der Auftrag und Teil A rechnen ein Jahr als 365 Spieltage.
- **Gegründet wird nur unter 60 Lebensjahren** (`entscheide`: `alter < 60`). Nach einer Pleite ist Gründen 180 Spieltage gesperrt
  (`PLEITE_SPERRE`), das sind 18 Lebensjahre.
- **Folge:** Wiedergründen kann nur, wer bei der Pleite jünger als 42 war, und nur bis (60 − Alter bei der Pleite) × 10 Tage danach, höchstens
  etwa 420 Tage.
- **Gemessen passt das:** In allen Varianten, auch ohne Erfahrung, kommt die Wiedergründung 180–358 Tage nach der Pleite, nie später (B.2).
- **„Nach 1–2 Jahren wieder denkbar“** ist in Spieltagen (365–730) also für niemanden möglich, unabhängig von der Erfahrung. In Lebensjahren
  (10–20 Spieltage) wäre es kürzer als die Sperre selbst.
- Welche Uhr Noah meint, entscheide ich nicht. Teil A bleibt, wie er ist. Wenn Noah Lebensjahre meint, müssten Sperre, Altersgrenze und H
  zusammen neu betrachtet werden. Das wäre eine neue Entscheidung.

### B.9 Geändert und angelegt

- **`stadt/stadt.html`** (nur sim-Block, 19 Zeilen gegen `sicherung_verblassen`):
  - `R.ERF_HALB: 180` mit Kommentar;
  - `erfVerblassen(S, p)`;
  - der Takt `vT` und der Aufruf in `menschenTag` vor `erfTag`.
  - Kein neues Speicherfeld; Speicherformat 10, Übernahme und `gedPruefen` unverändert.
- **`stadt/tools/simtest.mjs`:** nur der Fall „halb bezahlt“ in `--sicherheit` (B.6).
- **Sicherungen:** `sicherung_verblassen/` (vor dem Bau), `sicherung_verblassen_testfix/` (vor der Testanpassung).
- **Werkzeuge** (`werkzeug/`):
  - aus dem ersten Durchgang: `vb_einheit.mjs`, `vb_gleich.mjs`, `vb_kopien.sh`, `vb_gates.sh`, `vb_messung.sh`, `vb_wieder.mjs`,
    `vb_wieder_auswertung.mjs`, `vb_folgen.mjs`, `vb_probe8.mjs`, `vb_gate_t.sh`, `vb_tabelle.mjs`, `vb_varianten.mjs`,
    `vb_harte_grenze.mjs`, `vb_schluss.sh`;
  - neu in diesem Durchgang: `vb_sich_fall.mjs`, `vb_wirtschaft_nach.py`, `vb_wieder_fenster.py`.
- **Rohdaten:** `mess/verblassen/` (`bau/`, `kand/`, `bestaetigung_h180/`, `schluss/`, `testfix/`, `wieder_fenster.txt`).
- **Im Repo nichts geändert.**
