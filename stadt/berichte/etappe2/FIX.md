# STADT – Etappe 2: Korrekturen nach der Schlussprüfung (FIX, 01.10.2026, 02:35–03:46 UTC)

> **Ablage im Repo (01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des Originals in
> `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`. `E` = `SP/ml/e2bau`
> liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/fix/…` hier liegt, steht unter
> `mess/fix/…` neben diesem Bericht (Liste in `LIESMICH.md`); Bilder, Rohdaten, Sicherungen und die Werkzeuge aus `E/werkzeug/…` sind nicht
> mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`, Port 9096.
Sicherung vor den Änderungen: `E/sicherung_fix` (= Stand der Schlussprüfung: `stadt.html` sha256 `ac899293429df032…`, Sim-Hash
`386c5ec814feb302`; sha256 aller Dateien in `E/sicherung_fix.sha256`). Rohdaten `E/mess/fix/`, Werkzeuge `E/werkzeug/fix_*`.
**Im Repo ist nichts geändert, nichts angelegt, nichts committet** (`git status` leer, HEAD `6c1741e`, vor und nach der Arbeit geprüft).

**Endstand:** `stadt/stadt.html` sha256 `e8dc1bc1894d52f59de0295a5137cc12d351dc922906c487397b756d8dd1fbae`, Sim-Hash `0b5f143bb948bcbb`,
`VERSION = 10`, `GED: 1, GED_STAERKE: 1.5, PLAN_RUECKLAGE: 1, ERF_HALB: 180`. Im sim-Block geändert sind nur `warum` (gibt zusätzlich die
Rechnung je Vergleich zurück, nur lesend) und ein Kommentar. **Die Stadt rechnet mit `R.GED = 1` Tag für Tag gleich wie vorher** (Abschnitt 2);
darum waren Gates 1–80 und probe8 nicht nötig, ich habe beide trotzdem wiederholt: je Seed gleich (Abschnitt 6).

Alles hier ist gemessen, außer wo „Annahme“ oder „nicht geprüft“ steht.

**Hinweis zu den Befunden:** Die Berichte „Texte“ und „Bedienung“ kamen in der Aufgabe abgeschnitten an (Texte nach dem 7. Befund mitten im
Satz, Bedienung mitten im 5. Befund). Bearbeitet habe ich alle Befunde, die lesbar waren. Ob danach noch weitere folgten, weiß ich nicht. Den
5. Befund „Bedienung“ habe ich aus seinem lesbaren Teil und der Messung (`mess/pB/protokoll.txt`) ergänzt: Der Knopf zeigt am Handy nur
Symbol und Zahl, die Hilfe erklärte ihn nicht (selbst nachgeprüft).

## 0. Ergebnis

Kein Befund war „blockiert“. Alle drei „mittel“ habe ich nachgeprüft und bestätigt und behoben, ebenso alle lesbaren kleinen Befunde (zwei
davon nur in Doku oder Kommentar, wie vorgeschlagen). Zurückgewiesen habe ich keinen.

| Befund (Prüfung, Schwere) | nachgeprüft | Stand |
|---|---|---|
| B1 „Warum?“: „Ohne … hätte …“ oft nicht nachrechenbar (Bedienung, mittel) | bestätigt: mit dem Werkzeug der Prüfung (`werkzeug/pB/warum_leser.mjs`, Sim-Block `ac899293`) 415 von 1.787 Sätzen (Seeds 1–3, Tag 200–260), 411 davon mit „Zufall –“ (`mess/fix/warum_leser_vorher.txt`) | behoben: `Sim.warum` gibt je Vergleich mit anderer Wahl dessen Rechnung zurück (`rechnung.erfahrung/.plan/.beides`), die Karte schreibt sie in Klammern hinter den Satz (genannte Handlung und echte Wahl, je mit ihrer Zufallszahl). Nachrechenbar jetzt 102.230 von 102.230 Sätzen (Seeds 1–10 × 730 Tage) und 49.982 von 49.982 (Seeds 1–3 × 730 Tagesschritte); dabei gefunden: in 56 bzw. 26 dieser Sätze steht die gewählte Summe gerundet genau auf 25 → jetzt „knapp über 25“ (Abschnitt 2) |
| B2 Policy-Meldung nach Übernahme oder Import eines Stands der Version 9 rät „Liegt sie wieder in ki/ …“ (Bedienung, mittel) | bestätigt (Code `kiWahlAusUi`, Meldungen in `mess/pB/protokoll.txt`) | behoben: Für einen übernommenen oder importierten älteren Stand sagt die Meldung „Die gespeicherte Policy „v9_lokal_1“ stammt aus Version 9 und gilt in Version 10 nicht mehr (neu trainieren). Es entscheiden die Regeln (Rückfall).“, ohne Hash und ohne den Rat. Beim Umschalten auf „Trainierte Policy“ nennt die Meldung „(die vorhandene ist auf eine ältere Stadt-Version trainiert: neu trainieren)“. `p10speicher` prüft beides, Import neu (Abschnitt 4) |
| X1 Doku ordnet die „stärkere Wirkung“ (Entscheidung 4) nicht ein (Texte, mittel) | bestätigt: Zahlen aus `VERGLEICH.md` 1.2, `VERBLASSEN.md` B.3, `probe8_auswertung.txt`, `KALIBRIERUNG.md` B.1 selbst nachgelesen und nachgerechnet | behoben in README („Wie stark“), `docs/GRENZEN.md`, `docs/FORTSCHRITT.md` Punkt 8: im Mittel etwa ein Drittel stärker als Entwurf C (0,957 gegen 0,713 %), in den Seeds 2 und 3 noch im Bereich 0,5–1 %, Seed 3 unter Entwurf C, Erfahrung allein 0,46–0,61 %; Folge der Entscheidungen 9 und 10 |
| X2 Kommentar zu `GED_STAERKE` falsch (Texte, klein) | bestätigt (Stufe 1 hatte 71 von 80 gewertet; 58 ist die Zahl vor dem Verblassen) | behoben im sim-Block: „von den stärkeren Stufen (1,5–4, …) die, bei der Gate 7 in den meisten Städten gewertet wird (damals 58 von 80 statt 26 bei Stufe 4; mit Verblassen 55 von 80)“. Den Sim-Hash ändert ohnehin B1; alle Nennungen sind nachgezogen |
| X3 Hinweis der Liste übertreibt, was gezählt wird (Texte, klein) | bestätigt (`andersMelden` nur bei `GED_DIREKT`) | behoben in der Liste und in `docs/START.md`: „… und an der Gründen, Kündigen, Stelle wechseln oder Zusammenziehen beteiligt ist (etwa 9 von 10 solcher Entscheidungen)“; dazu `docs/GRENZEN.md` |
| X4 „gleich wieder Arbeit gesucht“ (Texte, klein) | bestätigt (`erfHandlung`: jede Stellensuche in der Frist von 30 Tagen; gemessen bei Elternzeit 71,5 % binnen 1 Tag, 88,9 % binnen 30 Tagen) | behoben: „innerhalb von 30 Tagen“ in README (3 Stellen) und `docs/GRENZEN.md`, dort mit den Zahlen |
| X5 roher englischer Fehlertext in der Liste (Texte, klein) | bestätigt (Code) | behoben: „Liste angehalten (interner Fehler der Anzeige). Die Stadt rechnet trotzdem richtig weiter.“; der rohe Text nur im `title` (Abschnitt 4) |
| X6 FORTSCHRITT nennt Verschobenes nicht (Texte, klein) | bestätigt (`VERGLEICH.md` Abschnitt 3 „Bewusst nicht übernommen“) | behoben: Etappe 2 und Etappe 5 nennen Stärke von Bindungen und Verpflichtungen als nach Etappe 5 verschoben |
| X7 `tests/LIESMICH.md`: p6migration „Version 10: 344 s“ aus rotem Lauf (Texte, klein) | bestätigt (`mess/schritt4/…`: 344 s bei OK 43 / Soll 39; grün: 300, 329, 346 s) | behoben: „300 bis 346 s in grünen Läufen“; Laufzeit dieses Laufs in Abschnitt 6 |
| T1 Pläne außer der Rücklage sind nur Anzeige (Technik, klein) | bestätigt (`planSchritt` in `entscheide` nur beim Kündigen gelesen) | dokumentiert in `docs/GRENZEN.md` (eigener Punkt), wie vorgeschlagen; Verhalten unverändert |
| T2 Kopf von `ki/policies.json` veraltet, `ki_liste.mjs` schriebe die Liste leer (Technik, klein) | bestätigt | wie vorgeschlagen gelassen; Warnung im Kopfkommentar von `tools/ki_liste.mjs` |
| T3 Beobachter gilt modulweit (Technik, klein) | bestätigt (Code, `BEOB`) | dokumentiert in `docs/ARCHITEKTUR.md` beim Beobachter |
| B3 Liste verschiebt sich unter Auge und Maus (Bedienung, klein) | bestätigt (Code: jede Stunde `innerHTML` neu) | behoben: unveränderte Liste wird nicht neu eingesetzt; sonst bleibt der oberste sichtbare Eintrag an seiner Stelle (Anker über `data-nr`). Browser: dasselbe Element nach einer Stunde, nach dem Tageswechsel 0 px verschoben; Gegenprobe ohne die Änderung: 871 px verschoben, Test rot (Abschnitt 4) |
| B4 Liste lebt nur im offenen Tab, sagt es nicht (Bedienung, klein) | bestätigt (Code `erfListeTag`) | behoben: „Gezählt erst, seit die Stadt in diesem Fenster läuft (Tag X, Y Uhr); was davor entschieden wurde, steht nicht hier.“ und „Seit Y Uhr noch keine.“; Browser-Test prüft den Satz |
| B5 Handy: Knopf nur Symbol und Zahl, Hilfe erklärt ihn nicht (Bedienung, klein) | bestätigt (Hilfe-Text; CSS bis 900 px nur Symbol und Zahl) | behoben: Zeile „Weiche mit Zahl beim Stadtbuch …“ in der Hilfe, nur sichtbar, wo der Knopf nur Symbol und Zahl zeigt; die Hilfe bei 1280 × 800 bleibt ohne Scrollen (745 von 745 px, `otest/hilfehoehe`) |

## 1. Was geändert ist

`diff -rq E/sicherung_fix E/stadt` (Diff von `stadt.html`: `mess/fix/diff_stadt_html.txt`):

| Datei | Änderung |
|---|---|
| `stadt.html`, sim-Block | `warum`: dieselben vier Aufrufe von `entscheide`, die drei Vergleiche jetzt auch mit Bit 8 (Summanden merken) in eigene Listen; neues Feld `rechnung`. Kommentar zu `GED_STAERKE` (X2) |
| `stadt.html`, Modul-Skript und CSS | `warumTeile`, `vergleichHtml`, `knapp` (B1); `kiWahlAusUi(ui, still, vonVersion)` und die Umschalt-Meldung (B2); `karteRendern`: Liste nur bei Änderung neu, Anker (B3); `erfListe.seit`, `erfListe.html`, Hinweistexte (B4, X3, X5); `data-nr` je Eintrag; Hilfe-Zeile `.nur-schmal` (B5) |
| `tools/simtest.mjs` | `--gedaechtnis` A: der Beobachter ruft `warum` wie die Oberfläche auf, neue Prüfung je Seed (39 → 42 Prüfungen), Kopfkommentar |
| `tools/ki_liste.mjs` | Kopfkommentar (T2) |
| `tests/gedaechtnis.cjs` | +2 Prüfungen (5b Warum nachrechenbar, 11 Liste beim Auffrischen); Kopf |
| `tests/p10speicher.cjs` | Prüfung 2 strenger (Meldung „stammt aus Version 9 … (neu trainieren)“, kein „Liegt sie wieder“), neu 2b Import (+1) |
| `tests/alle.sh` | Soll `gedaechtnis` 15 → 17, `p10speicher` 10 → 11, mit Kommentar |
| `README.md`, `docs/GRENZEN.md`, `docs/START.md`, `docs/ARCHITEKTUR.md`, `docs/FORTSCHRITT.md`, `tests/LIESMICH.md`, `ki/LIESMICH.md`, `berichte/etappe2/LIESMICH.md` | Abschnitt 7 |
| neu: `berichte/etappe2/FIX.md` (dieser Bericht, Pfade bereinigt), `berichte/etappe2/mess/fix/` (53 Textdateien, 484 KB, Pfade bereinigt mit `werkzeug/fix_belege.sh`; sha256 der Originale in `quellen.sha256`; Bilder nicht mitgeliefert) | |

Kein Test ist abgeschwächt: Geändert sind nur Soll-Zahlen nach oben und eine Prüfung, die strenger wurde.

## 2. „Warum?“ nachrechenbar, Stadt rechnet gleich

**Ursache (B1):** `warum` rechnete die drei Vergleiche „ohne Erfahrung“, „ohne Plan“, „ohne beides“ ab demselben Zufallsstand, gab aber nur
deren Wahl zurück. Ohne die Summanden liegen andere Handlungen vorn, darum werden dort andere Zufallszahlen gezogen; die Karte zeigte nur die
Zahlen der echten Entscheidung (dort oft „Zufall –“). **Änderung:** Die drei Aufrufe laufen jetzt mit Bit 8 (merken) in eigene Listen, `warum`
gibt sie als `rechnung` zurück, wenn die Wahl anders ist. Bit 8 schiebt nur in eine Liste außerhalb von S; S.rs wird wie bisher gesichert und
zurückgesetzt.

**Gleichheit** (`werkzeug/fix_gleich.mjs`, drei Städte im Gleichschritt: vorher ohne Beobachter, vorher mit Beobachter + `warum`, nachher mit
Beobachter + `warum`; nach jedem Tag alle Arrays, Einzelwerte, JSON-Teile und `S.rs`):

| Lauf | Tage gleich | Meldungen; `warum` ohne `rechnung` gleich der alten Fassung | Sätze „Ohne …“; in der Rechnung vorn; aus den zwei gezeigten Zeilen nachrechenbar (davon „knapp über“) | Beleg |
|---|---|---|---|---|
| Seeds 1–10 × 730 Tage, stündlich | 10 × 730 von 730 | 101.383; 101.383 | 102.230; 102.230; 102.230 (56) | `mess/fix/gleich_stuendlich.txt` |
| Seeds 1–3 × 730 Tage, Tagesschritte | 3 × 730 von 730 | 49.426; 49.426 | 49.982; 49.982; 49.982 (26) | `mess/fix/gleich_tagschritt.txt` |

- **Erster Durchgang** (`…_lauf1_ohne_knapp.txt`): gleich gerechnet wie oben, aber 56 bzw. 26 Sätze nicht nachrechenbar. Ursache: Die Summen
  sind auf zwei Stellen gerundet; eine gewählte Summe von z. B. 25,002 steht als „25“ da, und „über 25“ ist dann nicht zu sehen. Seitdem
  schreibt die Karte bei einer gewählten Handlung mit gerundeter Summe genau auf der Schwelle „(knapp über 25)“, im Vergleich und in der
  Haupttabelle; das Werkzeug zählt das als nachrechenbar. Danach der zweite Durchgang (Tabelle).
- **Gegenproben des Werkzeugs** (`tmp/fix_gegen/`): Stärke 1,6 statt 1,5 → „FEHL“ (Städte verschieden); `rechnung.erfahrung` aus der falschen
  Liste → 1.748 von 2.057 nachrechenbar, „FEHL“.
- **Vorher** (Werkzeug der Prüfung, Leser sieht nur die Haupttabelle): 415 von 1.787 Sätzen nicht nachrechenbar, Seeds 1–3, Tag 200–260
  (`mess/fix/warum_leser_vorher.txt`, gleich der Messung der Prüfung).
- **Im Browser** (`tests/gedaechtnis.cjs` 5b, echter Fall Seed 1, Tag 370, 7 Uhr): „Ohne diese Erfahrung hätte Anna einen Betrieb gegründet (in
  dieser Rechnung: einen Betrieb gründen: Lage und Charakter +71 · Plan −45 · Zufall +0,4 = +26,4)“; die Teile ergeben die Summe, sie liegt
  über 25; Karte und Eintrag gleich. Bild `mess/fix/browser_einzeln/bilder_gedaechtnis/g5_handy_karte_warum.png` (selbst angesehen).
- **simtest** `--gedaechtnis` A prüft das jetzt je Seed (Seeds 1–3, 365 Tage, mit dem echten Beobachter): Seed 1 3.634 Meldungen, 3.639
  Sätze, alle vorn und nachrechenbar (2 knapp); Seed 2 2.662 / 2.668 (1); Seed 3 2.538 / 2.546 (6). Gegenprobe mit falscher Liste: „FEHL“, 2.496
  von 3.639 (`mess/fix/gegenprobe_simtest_warum.txt`). Der Fingerabdruck „mit Probe und Beobachter = ohne“ schließt die `warum`-Aufrufe jetzt
  ein und ist gleich.

## 3. Gate T (Noahs Nachtrag 7: sim-Block geändert → im Wechsel mit der Basis)

Allein gemessen (kein fremder Rechenprozess, Last je Lauf in `wechsel.txt`), drei Fassungen im Wechsel: neu, vorher (`sicherung_fix`), Basis
6c1741e (`werkzeug/fix_gate_t.sh`).

| Lauf | neu (Median) | vorher | Basis | neu/Basis | vorher/Basis | neu/vorher |
|---|---|---|---|---|---|---|
| 1: 4 Runden, 03:03–03:04, direkt nach einem Browser-Test (Last 1,9–3,1) | 1.280 ms (1.173–1.318) | 1.230 (1.180–1.256) | 3.365,5 | 0,380 | 0,365 | 1,041 |
| 2: 8 Runden, 03:04–03:07 | 1.264 ms (1.197–1.391) | 1.253,5 (1.185–1.459) | 3.448 | 0,367 | 0,364 | 1,008 |
| beide zusammen (12 Runden) | 1.265 | 1.247,5 | 3.448 | 0,367 | 0,362 | 1,014 |

Zusätzlich A/B im Wechsel (`werkzeug/opt_ab.mjs`, 10 Runden, Seed 1, 365 Tage, ein Prozess je Lauf): Wandzeit nachher/vorher 1,005 (Spannen
1.162–1.336 gegen 1.166–1.408 ms), CPU-Zeit 1,018, Fingerabdruck in allen 20 Läufen gleich (`mess/fix/ab_zeit.txt`). **Bewertung:** Die
Unterschiede liegen innerhalb der Streuung derselben Fassung; die heiße Schleife (`entscheide` ohne Probe) ist unverändert, `warum` läuft im
Gate nicht. Eine Verlangsamung ist nicht messbar; ganz ausschließen kann ich 1–2 % mit diesen Läufen nicht. T bleibt mit 1.265 ms weit unter
5.000 ms (12 von 12).

## 4. Oberfläche

- **B2** (`kiWahlAusUi`): Der dritte Parameter ist die Version des übernommenen Stands (`vonVersion` beim „Stadt übernehmen“, `migriert` beim
  Import). Ein Stand der Version 9 kann nur eine auf Version 9 trainierte Policy nennen (die Fassung 6c1741e nimmt nur ihre eigene Version an),
  darum ist der Satz „stammt aus Version 9 und gilt in Version 10 nicht mehr (neu trainieren)“ in diesem Fall immer richtig. Für Stände der
  Version 10 bleibt der alte Text (dort ist „wieder in ki/ legen“ der richtige Rat). Gemessen (`p10speicher`): Meldung nach „Stadt übernehmen“
  und nach dem Import wörtlich wie oben, Fenster „… Abgelehnt: ki/policy_v9_lokal_1.json: … (neu trainieren). …“, kein „Liegt sie wieder“.
- **B3** (`karteRendern`): Ist die Karte die Liste und ihr HTML gleich dem zuletzt eingesetzten, wird nichts neu eingesetzt. Sonst merkt sie
  den obersten (teilweise) sichtbaren Eintrag (`li[data-nr]`) und seine Lage im Bild und korrigiert nach dem Neusetzen `scrollTop` um seine
  Verschiebung. Ganz oben (Scroll 0) bleibt die Liste oben, dort erscheinen die neuen. Browser (`gedaechtnis` 11, 1280 × 800, Seed 1, Tag 370,
  19 Uhr, auf 1.835 von 3.669 px gescrollt): eine Stunde später dasselbe Element bei y 187; am nächsten Tag um 8 Uhr (neue Einträge oben,
  „heute“ ist „gestern“) bei y 187, Scroll jetzt 2.706 px. **Gegenprobe** (beide Änderungen abgeschaltet, `mess/fix/gegenprobe_anker.txt`):
  „neu gesetzt“ und y 187 → 1.058, der Test ist rot (16 von 17). Nicht gemessen: Klicks bei 100× wie in der Prüfung (die Ursache, das Neusetzen
  zwischen Drücken und Loslassen, entfällt ohne Änderung; mit neuen Einträgen wird weiter neu gesetzt).
- **B4:** `erfListe.seit` (Tag und Stunde, als die Liste für diese Stadt begann). Liegt das heute oder gestern, sagt die Liste es; leer: „Seit
  Y Uhr noch keine.“ Browser: „Gezählt erst, seit die Stadt in diesem Fenster läuft (Tag 370, 0 Uhr)“.
- **B5:** Hilfe, Abschnitt Bedienung: „Weiche ⑂ mit Zahl beim Stadtbuch (Handy quer: bei den Hauptfiguren): So oft haben Bewohner heute wegen
  Erfahrung oder Plan anders entschieden. Tippen öffnet die Liste mit „Warum?“.“ Sichtbar nur bis 900 px Breite und am Handy quer (dieselbe
  Regel, nach der der Knopf nur Symbol und Zahl zeigt). Bild bei 360 × 740 selbst angesehen (`mess/fix/browser_einzeln/otest_bilder/breiten_360x740_hilfe.png`).
  Breit unverändert: `otest/hilfehoehe` 745 von 745 px.
- **X3, X5:** Texte der Liste wie in Abschnitt 0. X5 im Browser geprüft (`werkzeug/fix_x5.cjs`, eigener Server auf 9096, danach per PID beendet): neue Stadt, Beobachter durch einen werfenden ersetzt, nach 709 Stunden (Tag 29) abgeschaltet; die Liste zeigt genau „Liste angehalten (interner Fehler der Anzeige). Die Stadt rechnet trotzdem richtig weiter.“, der `title` „TypeError: Cannot read properties of undefined (reading 'x')“, der Knopf „… Liste angehalten (Fehler); Liste öffnen“, Konsole ohne Fehler (`mess/fix/x5.txt`, Bild `mess/fix/x5_bilder/x5_liste_angehalten.png`, selbst angesehen).

## 5. Tests

- `simtest --gedaechtnis`: 42 Prüfungen (vorher 39), allein 42 s; neue Prüfung je Seed in A (Abschnitt 2), mit Gegenprobe.
- `tests/gedaechtnis.cjs`: 17 (vorher 15): 5b „Ohne diese Erfahrung …“ nachrechenbar (Karte und Eintrag), 11 Liste (Zählbeginn, kein
  Neusetzen ohne Änderung, Anker über den Tageswechsel), mit Gegenprobe (B3).
- `tests/p10speicher.cjs`: 11 (vorher 10): Prüfung 2 verlangt jetzt den neuen Satz und kein „Liegt sie wieder“; neu 2b Import desselben Stands.
- Einzeln vor dem frischen Lauf (`mess/fix/browser_einzeln.txt`, 02:57–03:01): `gedaechtnis` 17/17 (71 s), `p10speicher` 11/11 (69 s),
  `otest/hilfehoehe` 1/1, `otest/breiten` 20/20, `otest/befunde` 21/21.

## 6. Aus einer frischen Kopie (`E/frisch_fix`, `cp -r` der Baukopie, `werkzeug/fix_frisch.sh`)

- **`simtest_alle.sh`** (JOBS 2, 03:08:40–03:13:53, kein fremder Rechenprozess): **23 von 23 Läufen mit Exit 0.** Zahl der ok-Prüfungen je
  Modus gleich Schritt 4 außer `--gedaechtnis` 39 → 42 (`frisch/okzahlen_vergleich.txt`); alle Logs inhaltlich gleich denen aus Schritt 4 bis
  auf Zeiten, Temp-Pfade und die drei neuen Zeilen (`frisch/logvergleich.txt`). `--gate`: „Gate Phase 0: BESTANDEN“, T 1.297 / 649 / 555 ms,
  Gate 7 in Seeds 1–3 nicht gewertet (Entscheidung 8, wie vorher).
- **Gates Seeds 1–80** (`werkzeug/vb_gates.sh`, 2 Prozesse, 03:14–03:15): Gates 1–6, T, B je 80/80, Gate 4 80/80, Gate 7 55 gewertet (alle
  bestanden), 25 nicht gewertet; **je Seed gleich Schritt 4** bis auf die Wandzeit, 0 von 80 verschieden (`gates_1_80/vergleich_schritt4.txt`).
- **probe8** Seeds 1–3 × 730 Tage (`werkzeug/pT_probe8.mjs`, das Werkzeug der Schlussprüfung Technik): alle Kriterien erfüllt, Z1 1,332 / 0,886 /
  0,654 %; Ausgabe Zeile für Zeile gleich der Schlussprüfung bis auf den Kopf (`mess/fix/probe8.txt`).
- **`PORT=9096 bash tests/alle.sh`** (03:16:24–03:44:21 UTC, 27 min, allein, kein fremder Rechenprozess): **32 von 32 Tests grün, „ALLES GRÜN“, 537 OK-Prüfungen (534 + 2 `gedaechtnis` + 1 `p10speicher`), jeder Test genau seine Soll-Zahl, 0 FEHL**. Der Seitenserver auf 9096 wurde von `alle.sh` per PID beendet;
  auf 11434 lief schon der KI-Nachbau („test-modell“) und blieb unberührt; 8000 nicht angefasst. `p6migration` 307 s.
- **Nach den Läufen** habe ich nur noch Doku und `berichte/` geändert: `diff -rq E/frisch_fix E/stadt` nennt nur `docs/FORTSCHRITT.md`,
  `docs/GRENZEN.md`, `docs/START.md`, `ki/LIESMICH.md`, `tests/LIESMICH.md`, `berichte/etappe2/LIESMICH.md`, `quellen.sha256` und die neuen
  Belege; `stadt.html`, `tools/` und `tests/` (Code) sind byte-gleich.

## 7. Doku

- **README:** „innerhalb von 30 Tagen“ (3 Stellen), Einordnung der Wirkung gegen den Entwurf („Wie stark“), „Warum?“ mit Rechnung, Prüfzahlen
  42 / 17 und Belege dieses Laufs.
- **`docs/GRENZEN.md`:** Elternzeit mit „innerhalb von 30 Tagen“ und den Anteilen, neu „Wie stark, gemessen am Entwurf“, neu „Pläne
  entscheiden nur beim eigenen Laden mit“ (T1), Gate T mit den Zahlen aus Abschnitt 3, „Warum?“ mit Rechnung und den Zahlen vorher/nachher, Liste:
  „direkt“ erklärt, lebt nur im Fenster.
- **`docs/START.md`:** „Warum?“ mit Klammer-Beispiel, Liste (was gezählt wird, Hilfe am Handy, lebt nur im Fenster, Eintrag bleibt an seiner
  Stelle), Policy aus einem Stand der Version 9, 17 Prüfungen.
- **`docs/ARCHITEKTUR.md`:** `Sim.warum` mit `rechnung`; Beobachter modulweit (T3).
- **`docs/FORTSCHRITT.md`:** Etappe 2 und 5 (verschoben: Bindungen, Verpflichtungen), Punkt 3 (Sim-Hash), 8 (Einordnung, 17/17), 11, 12, 13,
  Phasentabelle, neuer Abschnitt „Etappe 2: Korrekturen nach der Schlussprüfung“.
- **`tests/LIESMICH.md`:** Soll und Beschreibung von `gedaechtnis` und `p10speicher`, Laufzeit `p6migration`, Gesamtlauf.
- **`ki/LIESMICH.md`:** Satz zur Policy aus einem Stand der Version 9.
- **`berichte/etappe2/`:** `FIX.md` (dieser Bericht, Pfade bereinigt wie die anderen), `mess/fix/` (Belege), `LIESMICH.md` (Endstand, Tabelle).

## 8. Nicht gemacht, offen

- Befunde jenseits der abgeschnittenen Stelle der Berichte „Texte“ und „Bedienung“: nicht bekannt, nicht bearbeitet.
- Klicks „wie ein Mensch“ bei 100× (Bedienung B3) habe ich nicht wiederholt; geprüft ist das Verhalten, das die Fehlklicks verursachte.
- Firefox und Safari nicht geprüft (wie bisher nur Chromium mit SwiftShader).
- Gate T: 1–2 % Unterschied zwischen vorher und nachher sind mit 12 Runden nicht auszuschließen (Abschnitt 3).
- Die Liste zählt weiter nur „direkte“ Fälle und auch Plan-Fälle (offene Frage 1 an Noah in FORTSCHRITT, unverändert).
- `ki/policies.json` bleibt wie es ist (T2, Vorschlag der Prüfung).

## 9. Nachprüfen

```bash
E=$SP/ml/e2bau
SP=<arbeitsordner>
cd $E/stadt
node tools/simtest.mjs --gedaechtnis --git <repo>                  # 42 Prüfungen, etwa 45 s
node $E/werkzeug/fix_gleich.mjs $E/sicherung_fix/stadt.html $E/stadt/stadt.html 1-10 730 stunde
bash $E/werkzeug/fix_gate_t.sh 8 $E/mess/x/gate_t                               # nur allein laufen lassen
PORT=9096 THREE_DIR=$SP/three/package STADT_GIT=<repo> TMPDIR=$E/tmp/tb AUSGABE=$E/mess/x bash tests/alle.sh gedaechtnis p10speicher
bash $E/werkzeug/fix_frisch.sh $E/mess/x beides                                   # frische Kopie, simtest_alle und tests/alle.sh
```

## 10. Nachtrag nach der Nachprüfung (Hauptsitzung, 01.10.2026, 04:30–05:15 UTC)

Die Berichte „Texte“ und „Bedienung“ lagen dem Nachbessern nur abgeschnitten vor (oben). Die Hauptsitzung hat sie danach vollständig gelesen:
Bei „Texte“ fehlte nichts (7 Befunde, alle oben), bei „Bedienung“ fehlten B6 und B7. Dazu kam der Rest aus der unabhängigen Nachprüfung.
Alle drei sind klein, betreffen nur die Oberfläche und sind behoben. **Der sim-Block ist unverändert** (Sim-Hash `0b5f143bb948bcbb`), also
rechnet die Stadt genau wie oben.

| Befund (Schwere) | nachgeprüft | Stand |
|---|---|---|
| Nachprüfung: In 13 von 102.230 Sätzen „Ohne … hätte …“ (Seeds 1–10 × 730 Tage) stehen die genannte Handlung und die echte Wahl gerundet gleich da; wer vorn lag, ist nicht zu sehen (klein) | bestätigt: `simtest --gedaechtnis` zählt in Seed 2 und 3 je einen solchen Satz | behoben: `vergleichHtml` hängt bei Gleichstand an die genannte Handlung „(knapp vorn)“ an, nach dem Muster von „knapp über 25“; `simtest --gedaechtnis` zählt die Fälle („gerundet gleich mit „knapp vorn““) |
| B6 Wörter mit Vorwissen: „Lage und Charakter (wie in Version 9, mit Zielbonus)“; eine gelernte schlechte Folge („nach 1 Tag wieder Arbeit gesucht“) wirkt neben „Job bekommen“ wie ein Erfolg (Bedienung, klein) | bestätigt (Text in `warumHtml`, `erfSaetze`) | behoben: „Lage und Charakter (wie dringend es ist, Persönlichkeit, Ziel, Erinnerungen)“; hinter der gelernten schlechten Folge steht der Maßstab, z. B. „(wieder Arbeit suchen zählt schlecht)“, „(Tag 163; eine Pleite zählt schlecht)“ |
| B7 Escape schließt Liste und Karte, der Fokus landet auf body, der nächste Tab springt zur Hilfe (Bedienung, klein) | bestätigt (`karteZu` setzte keinen Fokus) | behoben: `karteRendern` merkt sich beim Öffnen das fokussierte Element außerhalb der Karte, `karteZu` gibt ihm den Fokus zurück, wenn er in der Karte oder nirgends stand; `tests/gedaechtnis.cjs` prüft es in der Tastatur-Prüfung („Fokus zurück auf „erf-knopf““) |

**Endstand:** `stadt/stadt.html` sha256 `aad98691cb6893612333ac4f7ff234252451553fc70580a90894efaf4417ea9b`, Sim-Hash `0b5f143bb948bcbb`
(unverändert). Sicherung davor: `E/sicherung_gleichstand` (= Endstand von Abschnitt 0).

**Aus einer frischen Kopie** (`cp -a` der Baukopie nach `E/frisch_ich`, danach `diff -rq` leer; Belege in `mess/fix/nachtrag/`):

- `simtest_alle.sh` (JOBS 2): 23 von 23 Läufen mit Exit 0, darin `--gedaechtnis` 42 ok (Seed 1–3: „knapp vorn“ 0 / 1 / 1) und `--gate`
  „BESTANDEN“ (`simtest_alle.txt`, `simtest_alle/`).
- Gates Seeds 1–80 (2 Prozesse, gleichzeitig mit `simtest_alle`): Gates 1–6, T und B je 80 von 80, Gate 7 55 gewertet und bestanden,
  25 nicht gewertet; Seed für Seed gleich `mess/schritt4/gates_1_80/auswertung.txt` (Vergleich ohne die Spalte T) (`gates_1_80/`).
- `PORT=9098 bash tests/alle.sh`: 32 von 32, 537 OK-Prüfungen, „ALLES GRÜN“, 29 min (`browser.txt`, Logs von `gedaechtnis`, `befunde_v9`,
  `haushalt`, `otest_breit`, `p10speicher`, `browser_ki` in `browser_logs/`). Die Zahl der Prüfungen ist gleich wie in Abschnitt 6; B7 ist
  Teil einer bestehenden Prüfung.
- Gate T im Wechsel, allein (`fix_gate_t.sh 4`): Median neu 1.350,5 ms, vorher (`sicherung_fix`) 1.393,5 ms, Basis 6c1741e 3.594 ms;
  4 von 4 unter 5.000 ms (`gate_t/`).
- Bilder angesehen (`g5_handy_karte_ged.png`, `g5_handy_karte_warum.png`, nicht mitgeliefert): Maßstab und neuer Erklärsatz sind am Handy
  lesbar, die Rechnung „71 − 45 + 0,4 = +26,4“ stimmt.

**Nicht geprüft:** Ein echter Gleichstandsfall im Browser (in den Browser-Tests kommt keiner vor). Geprüft ist die Ausgabe von
`vergleichHtml` in Node mit den Zahlen des Beispiels der Nachprüfung (Seed 2, Tag 202, 18 Uhr: +30,49 gegen +30,49 → „(knapp vorn)“) und das
Zählen in `simtest --gedaechtnis`.
