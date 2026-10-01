# STADT – Etappe 2, Schritt 3: Oberfläche (Personenkarte, „Warum?“, Liste „Heute anders entschieden“) (30.09.2026)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`, Port 9092.
Sicherung vor den Änderungen: `E/sicherung_schritt3_verblasst` (= Schlussstand von VERBLASSEN.md, `stadt.html` sha256 `5ec4b62d…`, Sim-Hash
`1009eec6c4b8d852`). Rohdaten `E/mess/schritt3b/` (erster Durchgang) und `E/mess/schritt3c/` (Fortsetzung), Werkzeuge `E/werkzeug/s3b_*`,
`E/werkzeug/s3c_*`. **Im Repo ist nichts geändert, nichts angelegt, nichts committet** (`git status` leer, HEAD `6c1741e`, vor und nach der
Fortsetzung geprüft).

**Ablauf:** Der erste Durchgang (laut Dateizeiten 21:14–22:14 UTC) hat Karte, Liste und Test gebaut und die Layout-, Leistungs- und Gleichheitsmessungen
gemacht. Ein Neustart des Containers hat ihn während des Vergleichs der bestehenden Browser-Tests abgebrochen. Die Fortsetzung (22:16 UTC –
23:40) hat nichts neu gebaut. Sie hat den Stand geprüft, den abgebrochenen Vergleich zu Ende geführt, die Browser-Leistungsmessung nachgeholt
(sie war im ersten Durchgang an einem offenen Fenster gescheitert), Gate T neu gemessen, die roten Tests gegen `6c1741e` und eine Kopie mit
ausgeschalteten Schaltern gegengeprüft, eine Prüfung im Test ergänzt und drei kleine Dinge in der Karte geändert (Abschnitt 1).

**Schlussstand:** `stadt/stadt.html` sha256 `ac899293429df032…`, Sim-Hash `386c5ec814feb302` (sim-Block Zeilen 988–8996), `VERSION = 10`,
`GED: 1, GED_STAERKE: 1.5, PLAN_RUECKLAGE: 1, ERF_HALB: 180` (unverändert). `tools/simtest.mjs` unverändert (sha256 `f5fc192374b72ac2…`).
`tests/gedaechtnis.cjs` sha256 `8350ffa7a76045c4…`, `tests/alle.sh` sha256 `214312ed73f7b085…`.
Alle Zahlen sind gemessen, außer wo „Annahme“ oder „nicht geprüft“ steht.

## 0. Ergebnis

Alle Punkte des Auftrags sind gebaut und im Browser geprüft. Der Browser-Test `tests/gedaechtnis.cjs` ist grün: 15 von 15 OK auf dem
Endstand (60 s, `mess/schritt3c/end2/`). Die Simulation rechnet unverändert (Tag für Tag gleich), Gate T ist nicht langsamer. Die
bestehenden Browser-Tests haben vorher und nachher dasselbe Ergebnis: 31 von 31 vergleichbaren Tests mit gleichem Urteil und gleicher OK-
und FEHL-Zahl. 12 davon sind rot, alle schon vor Schritt 3 und nicht durch die Oberfläche (Abschnitt 10). Offen ist eine Frage an Noah
(Abschnitt 11, Punkt 1: Soll die Liste auch Plan-Fälle zeigen?).

| Kriterium | Ergebnis | Rohdaten |
|---|---|---|
| (1) Personenkarte: Erinnerungen lang/kurz getrennt, Fakt und „weil …“ | ja: „Bleibt im Gedächtnis (Langzeit)“ und „Zuletzt erlebt (Kurzzeit, die letzten 3)“; z. B. „Werkstatt an der Hauptstraße ist pleite gegangen – bestand 39 Tage · weil: Gründung vor 39 Tagen“ | `mess/schritt3b/bilder/karte_94.png`, Test Prüfung 8 |
| (1) Erfahrung als Satz mit Zahl | „Gründen: 1-mal, Pleite nach 39 Tagen (Tag 163) → zählt −9,75 (wenn das Geld reicht – so ist es gerade)“ = `gedInfo` −9,75 | Test Prüfung 6 |
| (1) Plan mit Ziel, Schritt, Hindernis, Frist, letzter Plan und Grund | „Plan: eigener Laden · Schritt 1 von 2: Rücklage ansparen · Hindernis: wartet nach der Pleite bis Tag 461 · Frist: Tag 408 (noch 38 Tage)“, „Letzter Plan: besserer Job – Frist abgelaufen“; „spart: 1.448 von 1.700 Talern“ bei Person 90 | Test Prüfungen 6 und 12 (neu) |
| (1) Letzte Entscheidung mit Quelle, offene Folge | „Letzte Entscheidung, etwas zu tun: Tag 368, 7 Uhr: freinehmen · nach den Regeln · hat geklappt“; „Offene Folge: Stelle wechseln heute · wird noch 30 Tage beobachtet“ (Person 90) | Test Prüfungen 6 und 12 (neu) |
| (2) „Warum?“ mit Summanden je Handlung und „ohne diese Erfahrung hätte …“ | ja, Lage und Charakter, Plan, Erfahrung, Zufall (±5 bzw. „–“ = nicht gezogen); „Ohne diese Erfahrung hätte Anna **einen Betrieb gegründet**“; indirekte Fälle als „Zufall“ gekennzeichnet | Test Prüfungen 4, 9, 10 |
| (3) Liste „Heute anders entschieden“: Beobachter nur im Browser, je Spieltag, Obergrenze 50, Knopf mit Zahl, Klick öffnet die Karte, Kamera nur auf Klick | ja; Knopf im Kopf des Stadtbuchs („26 anders“), Handy quer bei den Hauptfiguren; Eintrag mit Uhrzeit, Name, Grund, „statt X → Y“, Summanden; Name öffnet die Karte genau dieser Person (Platz und Generation); Kamera: die neuen Zeilen rufen die 3D-Ansicht nicht auf (aus dem Code, nicht im Browser geprüft) | Test Prüfungen 2, 3, 5 |
| (3) Keine Sortierung oder Filter nach Name, Herkunft, Geschlecht | ja: Reihenfolge nur nach Uhrzeit (neueste oben); der Eintrag speichert nur Platz, Generation, Zeit, Handlungen, Grund und Rechnung | Code (Abschnitt 4), `mess/schritt3c/neue_zeilen.txt` |
| (3) Kein Einbruch bei 100× und beim Aufholen, große Stadt | Tempo 100×: fps und Frame-Zeit vorher/nachher innerhalb der Streuung (Median fps 1,84 / 1,84, mit offener Liste 1,89; Frame Ø 15,8 / 18,1 / 16,2 ms); Aufholen 90 Tage ×1,054 im Browser (3 Läufe), in Node ×1,028 (12 Runden) | Abschnitt 8 |
| (4) Texte deutsch, ehrlich | ja; Hinweise „Das sind Annahmen der Stadt, keine Messung an echten Menschen.“ und „Die Gewichte sind Annahmen der Stadt.“ | Bilder |
| (5) Browser-Test `tests/gedaechtnis.cjs` | 15 von 15 OK auf dem Endstand (60 s); dazu 14/14 vor Prüfung 12 und 15/15 im ganzen Lauf | `mess/schritt3c/end2/`, `ged1/`, `mess/schritt3b/browser_nachher/logs/gedaechtnis.log` |
| Kein Name in Erfahrung und Plan | 0 Namen (77 Wörter gegen 140 Namen der Stadt und den eigenen); ebenso in der Karte mit offener Folge | Test Prüfungen 7 und 12 |
| Handy 390 × 844 ohne seitliches Scrollen, Tastatur, Konsole | ja (Seite 390 px, Karte 372/372), Tab/Enter/Escape, Konsole ohne Fehler | Test Prüfungen 13–15 |
| Layout in 12 Bildschirmlagen vorher/nachher | Stadtbuch-Kopf gleich hoch, kein Überlappen, keine Fehler; Handy quer: Kopf der Hauptfiguren +2 px | `mess/schritt3b/layout3.txt`, Bilder `layout3/` |
| Mit Schaltern aus Tag für Tag gleich `6c1741e`; mit Gedächtnis gleich dem Stand vor Schritt 3 | je 730 von 730 Tagen, Seeds 1–3, stündlich und in Tagesschritten | `mess/schritt3b/gleich/` |
| Bestehende Browser-Tests vorher/nachher | 31 von 31 gleich (Urteil, OK, FEHL); die 7 unerklärten roten sind auf `6c1741e` und mit Schaltern aus grün | Abschnitt 10 |
| Beobachter und Liste ändern den Spielstand nicht | ja, im Browser (Test Prüfung 11) und in Node (Fingerabdruck mit = ohne Beobachter) | `leistung_node3.txt` |
| Gate T nicht langsamer (sim-Block geändert) | 20 Runden im Wechsel mit dem Stand vor Schritt 3: Median 1.216 zu 1.189,5 ms, Median der Paarverhältnisse 1,006, nachher in 11 von 20 Runden langsamer; gegen `6c1741e` 0,372 | `mess/schritt3c/gate_t_vorher/`, `gate_t/` |
| Harte Grenze, Namenstausch | statisch in Ordnung, Namenstausch Seeds 1 und 2 × 200 Tage jeden Tag gleich | `mess/schritt3c/harte_grenze.txt` |

## 1. Was geändert ist

Geändert sind genau diese Dateien (`diff -rq` gegen `sicherung_schritt3_verblasst`):

- `stadt.html`: +326/−8 Zeilen. Davon im sim-Block nur `personInfo` (+3/−1, siehe 9), sonst CSS, zwei Knöpfe im HTML und das Modul-Skript.
- neu: `tests/gedaechtnis.cjs` (242 Zeilen).
- `tests/alle.sh` (+2/−1: Test in der Liste, Soll 15) und `tests/LIESMICH.md` (+2/−1).

**In der Fortsetzung geändert.** Der Stand davor (`stadt.html` `655daec7…`) liegt rekonstruiert in `sicherung_schritt3_vor_fortsetzung/`,
siehe 11, Punkt 9. Alles nur im Modul-Skript und im Test, der Sim-Hash ist unverändert:

- `stadt.html`, `lebenslaufHtml`: Die lokale Variable hieß `G` und verdeckte damit die 3D-Ansicht `G` des Modul-Skripts. Sie heißt jetzt
  `mem` (reine Umbenennung).
- `stadt.html`, Zeile „Offene Folge“: Bei einer Handlung von heute stand „Stelle wechseln am selben Tag“, jetzt „Stelle wechseln heute“.
- `stadt.html`, Zeile „Letzte Entscheidung“: jetzt „Letzte Entscheidung, etwas zu tun:“, mit Kommentar. Die Simulation speichert dort nur
  ausgeführte Handlungen (`ausfuehren`), nie „nichts tun“. Vorher stand bei Anna „Letzte Entscheidung: Tag 368 … freinehmen“ direkt über
  einem „Warum?“, das ihre spätere Entscheidung „nichts tun“ von Tag 370 erklärt.
- `tests/gedaechtnis.cjs`: Prüfung 12 („4b“) neu (offene Folge, Hindernis „spart“, Quelle der letzten Entscheidung, kein Name). Diese Teile
  der Karte waren gebaut, aber nicht geprüft. Die zwei Muster für „Letzte Entscheidung“ sind an den neuen Text angepasst. Soll in
  `alle.sh` 14 → 15, `LIESMICH.md` ebenso.

## 2. Personenkarte (Auftrag 1)

Neuer Abschnitt **„Erfahrung und Plan“** vor dem Lebenslauf, nur für Erwachsene und nur mit `R.GED` (sonst sieht die Karte aus wie vorher).
Er liest `Sim.gedInfo` und zeigt je Zeile einen Satz:

- **Plan:** Ziel (`ZIELTEXT`), „Schritt s von n: …“, Hindernis („wartet nach der Pleite bis Tag …“ bzw. „spart: 1.448 von 1.700 Talern“),
  Frist mit Resttagen. Ohne Rücklagepflicht (vor der Stufe Stadt, Entscheidung 6) der Zusatz „(vor der Stufe Stadt braucht es keine
  Rücklage)“. Ohne Ziel: „gerade keiner (kein Ziel)“.
- **Letzter Plan:** Ziel und Grund („Frist abgelaufen“ usw., `PLAN_GRUND` der Simulation).
- **Erfahrung:** je Handlung (Gründen, Kündigen, Stelle wechseln, Zusammenziehen) und Lage ein Satz: Anzahl („1-mal“, „2-mal“, „3-mal oder
  öfter“), was geschah, „→ zählt −9,75“ (= Summand in `entscheide`: Wert × Sicherheit × Stärke), in welcher Lage sie gilt und ob das gerade
  die Lage ist. Bei 1-mal nennt der Satz die Folge aus der Erinnerung mit Verweis („Pleite nach 39 Tagen (Tag 163)“). Ohne Erfahrung:
  „noch keine (gelernt wird erst, wenn sich die Folge zeigt)“.
- **Offene Folge:** „Stelle wechseln heute · wird noch 30 Tage beobachtet (die neue Stelle in der Zeit zu verlieren zählt schlecht, sonst
  gut)“; bei älteren Handlungen z. B. „vor 25 Tagen“.
- **Letzte Entscheidung, etwas zu tun:** Tag, Uhrzeit, Handlung, Quelle („nach den Regeln“, „von der trainierten Policy“, „vom Sprachmodell (Hauptfigur)“),
  „hat geklappt“ / „klappte nicht“.
- Darunter leise die Rechnung: „Zählt = Wert der Erfahrung (−31 bis +31) × Sicherheit (1-mal 0,5, 2-mal 0,75, ab 3-mal 1) × Stärke 1,5.
  Eine Erfahrung verblasst alle 12 Tage um einen Punkt: eine Pleite (−30) zählt nach 180 Tagen halb so viel und ist nach 360 Tagen
  vergessen. Das sind Annahmen der Stadt, keine Messung an echten Menschen.“ Sicherheit, Stärke und Verblassen kommen aus `R` (`ERF_SICHER`,
  `GED_STAERKE`, `ERF_HALB`); „−31 bis +31“ und „(−30)“ stehen fest im Text.

**Lebenslauf:** Mit Gedächtnis getrennt in „Bleibt im Gedächtnis (Langzeit)“ und „Zuletzt erlebt (Kurzzeit, die letzten 3)“. Unter jeder
Erinnerung leise Fakt und Verweis, soweit vorhanden: „Lohn … Taler am Tag“, „bestand 39 Tage“, „Geld danach reichte für … Tage“, „Haus der
Stufe …“, „das erste Kind“, „danach 5 Freunde“ und „weil: Gründung vor 39 Tagen“. Namen stehen nur im Text der Erinnerung selbst, wie bisher
als anklickbare Marke aus Verweis + Generation (Schritt 2); Verstorbene heißen nach der Beziehung. Nach der Übernahme aus Version 9 sind Fakt
und Verweis 0 bzw. leer; dann steht nichts darunter.

Dafür liefert `personInfo` je Erinnerung zusätzlich `code`, `lang`, `fakt`, `ursacheVorTagen` (nur Zahlen; ohne `R.GED` `lang: null` und
kein Fakt, dann der alte ungeteilte Lebenslauf).

## 3. „Warum?“ (Auftrag 2)

Knopf „Warum?“ unter „Erfahrung und Plan“ (klappt auf und zu, `aria-expanded`, bleibt beim stündlichen Auffrischen offen und behält den
Tastaturfokus). Daneben steht, was er erklärt:

- Hat die Liste heute oder gestern einen Eintrag dieser Person, erklärt er **genau diese Entscheidung** („heute um 7 Uhr anders entschieden
  als ohne Erfahrung und Plan“). Die Rechnung dazu ist `Sim.warum(S, p, stunde, rsVor)` mit dem Zufallsstand vor der Entscheidung, sofort beim
  Melden gerechnet.
- Sonst **„was die Regeln jetzt rechnen würden“**, ausdrücklich „mit einer neuen Zufallszahl; entschieden wird um 7 und um 18 Uhr und nach
  einem Ereignis“.

Inhalt: je geprüfter Handlung die Summe und die Summanden „Lage und Charakter +71 · Plan −45 · Erfahrung −9,75 · Zufall –“, nach Summe
geordnet, die Wahl hervorgehoben, die Wahl ohne Erfahrung markiert („ohne Erfahrung gewählt“). Dann „Keine Handlung liegt über 25: **nichts
tun**“ bzw. „Gewählt: …“, „Ohne diese Erfahrung hätte Anna **einen Betrieb gegründet**“ (sonst „Ohne Erfahrung: dieselbe Wahl“), dazu ohne
Plan und ohne beides, wenn anders. Ist ein Unterschied nur durch eine andere Zufallszahl entstanden (`art = 'zufall'`), steht dahinter
„(Zufall: keine beteiligte Handlung hat Erfahrung oder Plan, nur eine andere Zufallszahl wurde gezogen)“. Schluss: „Summe = Lage und
Charakter (wie in Version 9, mit Zielbonus) + Plan + Erfahrung (beide × Stärke 1,5) + Zufall ±5 … Die Gewichte sind Annahmen der Stadt.“
Kam die letzte Entscheidung von der Policy oder dem Sprachmodell, sagt ein Satz, dass hier die Regeln stehen. Kinder und Menschen in Haft:
ein Satz statt der Rechnung. Im „Warum?“ steht nur der eigene Vorname der Person (die Karte nennt ihn ohnehin oben).

## 4. Liste „Heute anders entschieden“ (Auftrag 3, Entscheidung 4)

- **Beobachter:** `Sim.beobachter = erfBeobachten` nur im Browser und nur mit `R.GED`. Er liegt nicht in `S` und wird nicht gespeichert. Die
  Simulation meldet jede Entscheidung, die ohne Erfahrung und Plan **direkt** anders wäre (eine beteiligte Handlung ist eine, auf die
  Erfahrung oder Plan wirken). Grund „erfahrung“, „plan“, „erfahrung und plan“ oder „zufall“.
- **Sammeln:** je Spieltag, höchstens **50 Einträge** (`ERF_MAX`, die ältesten fallen raus), dazu der direkte Vortag. Neue Stadt, Laden oder
  Übernahme leeren die Liste. Beim Aufholen werden nur der letzte Tag und der Vortag gesammelt. Ein Eintrag enthält nur Platz, Generation,
  Tag, Stunde, die zwei Handlungen, den Grund und die Rechnung von `Sim.warum`; **keinen Namen, kein Geschlecht, keine Herkunft**. Der Name
  kommt erst beim Zeichnen und nur, solange diese Person (Platz und Generation) lebt; sonst „nicht mehr in der Stadt“.
- **Zugang:** Knopf im Kopf des Stadtbuchs rechts, Symbol „Weiche“ + Zahl von heute + „anders“ (schmal nur Symbol und Zahl; der volle Name
  „26 anders entschieden (heute) wegen Erfahrung oder Plan; Liste öffnen“ steht im `aria-label` und im `title`). Handy quer ist der Kopf des
  Stadtbuchs schon voll, dort steht derselbe Knopf in der ersten Zeile der Hauptfiguren. Die Zahl wird nur geschrieben, wenn sie sich ändert.
- **Liste** (als Karte, wie Personen- und Hauskarten, mit „‹ zurück“): Kopf „Heute anders entschieden · Tag 370 · 26 Entscheidungen“, ein
  Satz, was gezählt wird, die Zahl je Grund („Erfahrung 14 · Plan 10 · beides 2 · Zufall 0“). Je Eintrag: Uhrzeit, Name (Knopf), Grund
  (Erfahrung hervorgehoben), „statt „einen Betrieb gründen“ → „nichts tun““, die Summanden der beiden beteiligten Handlungen („Gründen:
  Erfahrung −9,75, Plan (Rücklage fehlt) −45“) und ein eigenes „Warum?“. Reihenfolge nur nach der Uhrzeit, neueste oben; keine Sortierung und
  kein Filter nach Name, Herkunft oder Geschlecht.
- **Klick auf den Namen** öffnet die Personenkarte dieser Person über den vorhandenen Weg (`button.name`, wie im Stadtbuch). Die Kamera bewegt
  sich dabei nicht (die neuen Zeilen rufen die 3D-Ansicht nicht auf); bewegen tut sie sich nur wie bisher über „Zeigen“ in der Hauskarte.
- **Fehler im Beobachter** schalten ihn ab (Simulation) und die Liste sagt „Liste angehalten: … Die Stadt rechnet trotzdem richtig weiter.“

**Zahlen:** Seed 1, Tage 250–400: 2.215 Meldungen an 150 Tagen, höchstens 52 an einem Tag, im Mittel 14,8 (Seed 2: 37 / 12,4; Seed 3: 23 /
7,9; `mess/schritt3b/faelle.txt`). In der großen Stadt (7.159 Einwohner) sind es 106–118 je Tag (`leistung_node*.txt`); dort greift die
Obergrenze 50.

## 5. Texte (Auftrag 4)

Deutsch. Die Personenkarte redet die spielende Person nirgends an („du“ kommt dort nicht vor); sie beschreibt die Figur in der dritten
Person. Die neuen Texte halten es genauso, im „Warum?“ mit dem Vornamen der Figur (siehe 11, Punkt 6). Zahlen im deutschen Format
(„−9,75“, „1.448“). Die Grenzen der Aussage stehen dabei: „Das sind Annahmen der Stadt, keine Messung an echten Menschen“, „Die Gewichte
sind Annahmen der Stadt“, „mit einer neuen Zufallszahl“, „(Zufall: …)“.

## 6. Browser-Test `tests/gedaechtnis.cjs` (Auftrag 5)

Relativ zum Ordner `stadt/`, über `umgebung.cjs`, Anfragen an 11434 werden im Browser abgebrochen. **Echter Fall:** In Node (derselbe
sim-Block) wird Seed 1 gerechnet und ab Tag 300 der erste Fall gesucht, in dem die Regeln ohne Erfahrung gegründet hätten, die Person etwas
anderes gewählt hat, der Unterschied direkt ist und sie eine Gründen-Erfahrung in ihrer heutigen Lage hat. Mit Stärke 1,5 und Verblassen
(180) ist das **Person 94 (Anna Busch), Generation 1, Tag 370, 7 Uhr**: Wahl „nichts“, ohne Erfahrung „laden_gruenden“, Grund „erfahrung und
plan“, Gründen-Erfahrung Wert −13 (Pleite −30 an Tag 163, seitdem 17-mal um einen Punkt verblasst) × 1 → −9,75. Der Stand um 0 Uhr dieses
Tages kommt als Spielstand der Version 10 in `localStorage`.

Prüfungen (15; Nummern wie im Log):

1. echter Fall gefunden (Node);
2. nach 8 Stunden: Knopf im Stadtbuch „26 anders“, `aria-label` beginnt mit dem sichtbaren Text, Beobachter gesetzt, kein Fehler;
3. Liste mit 26 Einträgen, darunter der Fall („statt „einen Betrieb gründen“ → „nichts tun““, Erfahrung);
4. „Warum?“ im Eintrag: aufgeklappt, nennt die Wahl ohne Erfahrung, Fokus bleibt auf dem Knopf;
5. Klick auf den Namen öffnet die Karte genau dieser Person, „‹ zurück“ führt zur Liste;
6. Karte: „Gründen: 1-mal, Pleite nach 39 Tagen (Tag 163) → zählt −9,75“ (gleich `gedInfo`), Plan, letzte Entscheidung;
7. kein Name in Erfahrung und Plan (Namenslisten der Stadt und der eigene Name);
8. Lebenslauf getrennt (5 Langzeit, 3 Kurzzeit), mit Verweis „weil: Gründung vor 39 Tagen“;
9. „Warum?“ in der Karte: Summanden, „Ohne diese Erfahrung hätte Anna einen Betrieb gegründet“, „um 7 Uhr“, kein fremder Name;
10. nach dem stündlichen Auffrischen bleibt „Warum?“ offen, der Fokus bleibt;
11. derselbe Stand in einer zweiten Seite ohne Beobachter: Spielstand nach 9 Stunden gleich (Einzelwerte, JSON-Teile, Arrays);
12. **neu:** Karte der ersten Person mit offener Folge und fehlender Rücklage: „wird noch … beobachtet“ und „spart: … von … Talern“ genau wie
    `gedInfo`, letzte Entscheidung mit Quelle „nach den Regeln“, kein Name;
13. Tastatur: Escape schließt; Tab vom Stadtbuch-Kopf auf den Knopf, Enter öffnet die Liste (Fokus auf der Überschrift), Tab zum Namen,
    Enter, Tab zu „Warum?“, Enter klappt auf, Escape schließt;
14. Handy 390 × 844 (Touch): Seite 390 px, Liste und Karte `scrollWidth` ≤ `clientWidth`, nichts ragt hinaus, Stadtbuch-Kopf eine Zeile (42 px);
15. Konsole ohne Fehler.

**Läufe:**

- allein 22:18 UTC (noch mit 14 Prüfungen, vor 4b): 14 von 14 OK, 67 s (`mess/schritt3c/ged1/`);
- im ganzen Nachher-Lauf (mit 4b): 15 von 15 OK, 61 s;
- nach der Änderung „heute“: 15 von 15, 63 s (`mess/schritt3c/end/`);
- auf dem Endstand nach allen Änderungen: 15 von 15, 60 s (`mess/schritt3c/end2/`).

Prüfung 12 fand Person 90 (Tag 370, 9 Uhr): „Offene Folge: Stelle wechseln heute · wird noch 30 Tage beobachtet“, „Hindernis: spart:
1.448 von 1.700 Talern“, „Letzte Entscheidung, etwas zu tun: Tag 370, 7 Uhr: die Stelle wechseln · nach den Regeln · hat geklappt“.

**Bilder angesehen** (`mess/schritt3c/ged1/bilder_gedaechtnis/`, `end/`, `end2/`, `mess/schritt3b/browser_nachher/bilder_gedaechtnis/`,
dazu die ganzen Karten `mess/schritt3b/bilder/karte_94.png`, `bilder5/karte_5.png` und `mess/schritt3c/bilder_end/`): Knopf im
Stadtbuch-Kopf, Liste breit und am Handy, Karte mit „Warum?“ breit und am Handy, Karte mit offener Folge (`g6_karte_offen.png`). Nichts
ragt hinaus, nichts überlappt, die Texte sind lesbar. Aufgefallen sind mir vier Dinge:

- „Offene Folge: Stelle wechseln am selben Tag“ – geändert in „heute“ (Abschnitt 1).
- „Letzte Entscheidung: Tag 368 … freinehmen“ direkt über einem „Warum?“, das Annas spätere Entscheidung „nichts tun“ von Tag 370 erklärt.
  Die Simulation speichert nur ausgeführte Handlungen. Geändert in „Letzte Entscheidung, etwas zu tun“ (Abschnitt 1).
- Im Handybild des ersten Durchgangs (`schritt3b/ausgabe/bilder_gedaechtnis/g4_handy_liste.png`) liegt ein blaues Rechteck genau dort, wo
  der angetippte Knopf sitzt (315–371 × 737–767). Die Seite setzt keine eigene Tipp-Markierung (kein `tap-highlight` im CSS), und in den
  späteren Läufen ist das Rechteck nicht mehr im Bild. Vermutlich ist es die Tipp-Markierung von Chromium im Handy-Modus (Annahme).
- Die alte Ganzkarte `bilder5/karte_5.png` (21:30 UTC) zeigt zwei Sätze hintereinander („Keine Handlung kommt gerade in Frage.“ und „Keine
  Handlung liegt über 25“). Das Bild stammt von einem älteren Code-Stand. Auf dem Endstand steht dort nur ein Satz („Keine Handlung kommt
  gerade in Frage: nichts tun.“, `mess/schritt3c/bilder_end_5.txt`).

## 7. Layout in 12 Bildschirmlagen (erster Durchgang, `werkzeug/s3b_layout.cjs`, `mess/schritt3b/layout3.txt`)

Stand Seed 1, Tag 370, 8 Uhr, vorher (`sicherung_schritt3_verblasst`) und nachher je Lage (1920 × 1080, 1280 × 800, 1024 × 768, 768 × 1024,
390 × 844, 360 × 740 und Handy quer 932 × 430, 915 × 412, 844 × 390, 680 × 345, 640 × 360, 568 × 320):

- Stadtbuch-Kopf in allen Lagen gleich hoch wie vorher (48/47/42/43/34 px), auch mit „99+ neu“; der Pfeil bleibt drin.
- Der Knopf sitzt im Kopf (breit 113–115 × 30 px mit Wort; bis 900 px Breite und am Handy 56–57 × 30 px, nur Symbol und Zahl); Handy quer
  `erf-knopf-quer` 45 × 24 px in der Zeile der Hauptfiguren.
- Keine Überlappung mit den Zahlen oder der Tempo-Leiste, keine Konsolenfehler, Seite nie breiter als das Fenster.
- **Einziger Unterschied:** Handy quer ist der Kopf der Hauptfiguren 2 px höher (z. B. 48 → 50 px), die rechte Spalte beginnt 2 px weiter
  oben (221 → 219). Das habe ich so gelassen.

## 8. Leistung (Auftrag 3: kein Einbruch bei 100× und beim Aufholen)

**Node** (erster Durchgang, `werkzeug/s3b_leistung.mjs`, große Stadt Seed 2, Umland 300.000, Tag 750, 7.159 Einwohner, 12 Runden im
Wechsel, `mess/schritt3b/leistung_node3.txt`):

| Weg | ohne Beobachter | mit Beobachter (jede Meldung mit `Sim.warum`) | wie die Seite (Aufholen: nur die letzten 2 Tage) |
|---|---|---|---|
| 240 Stunden stündlich (wie Tempo 100×) | Median 249 ms | 247 ms (**×0,993**), 1.109 Meldungen | – |
| 60 Tage in Tagesschritten (wie Aufholen) | Median 1.119 ms | 1.159 ms (×1,036), 7.065 Meldungen | 1.151 ms (**×1,028**), 130 Meldungen |

Fingerabdruck des Spielstands mit Beobachter = ohne, in jeder Runde.

**Browser** (Fortsetzung, `werkzeug/s3c_leistung.sh` → `s3b_bild_leistung.cjs`, 22:41–22:46 UTC direkt nach dem Vorher-Lauf, kein anderer
Rechenprozess; 3 Runden im Wechsel, derselbe Stand in der Seite mit `?debug&umland=300000`, 1280 × 800; Werte aus der Debug-Ecke;
`mess/schritt3c/leistung_browser.json` und `.txt`). Gemessen mit `stadt.html` `655daec7…`, also vor den Änderungen der Fortsetzung; die
betreffen nur einen Variablennamen und zwei Texte der Personenkarte:

| | fps (Median, je Runde) | Frame Ø ms (Median) | Frame max ms | Sim-Schritt ms | Spielstunden in 20 s |
|---|---|---|---|---|---|
| vorher, 20 s bei 100× | 1,84 (1,94 / 1,77 / 1,84) | 15,8 | 554–698 | 0,4–0,5 | 14–15 |
| nachher, 20 s bei 100× | 1,84 (1,83 / 1,88 / 1,84) | 18,1 | 574–674 | 0,4–0,5 | 14–15 |
| nachher, danach 20 s mit offener Liste (53 Einträge) | 1,89 (1,89 / 1,92 / 1,82) | 16,2 | 509–561 | 0,4–0,5 | 14–15 |
| Aufholen 90 Tage (Wandzeit) | vorher 2.858 ms (2.858 / 2.807 / 2.902) | nachher 3.012 ms (2.940 / 3.212 / 3.012) | **×1,054** | | |

Konsole ohne Fehler. **Einordnung:** Im Headless-Chromium zeichnet Software; die Grafik der großen Stadt begrenzt auf unter 2 Bilder je
Sekunde, darum laufen bei „100×“ nur 14–15 Spielstunden in 20 s. Die Unterschiede in fps und Frame-Zeit liegen innerhalb der Streuung der
Runden. Wie sich das auf einem Gerät mit Grafikkarte zeigt, ist nicht gemessen (Annahme: der Anteil des Beobachters ist dort nicht größer
als in Node, ×0,993 stündlich). Beim Aufholen kostet die Spur der Simulation (sie rechnet „ohne Erfahrung und Plan“ mit, solange ein
Beobachter gesetzt ist) etwa 3–5 %. Ein Einbruch ist das nicht; abschalten ließe sich das nur mit einem weiteren Eingriff in das Aufholen.

Im ersten Versuch (21:41 UTC) war nach dem Laden das Fenster „Eine Hauptfigur fehlt“ offen und fing den Klick auf den Knopf ab. Das Werkzeug
schließt offene Fenster jetzt vor dem Klick (`fensterZu: nachfolge-dialog` in jeder Runde). Das ist kein Fehler der Seite: Das Fenster
gehört zum Stand (eine Hauptfigur ist weggezogen).

## 9. Simulation unverändert, Gate T, harte Grenze

- **sim-Block:** geändert ist nur `personInfo` (die Anzeige-Funktion der Karte): je Erinnerung zusätzlich `code`, `lang`, `fakt`,
  `ursacheVorTagen`. Sie schreibt nichts und wird beim Rechnen nicht aufgerufen.
- **Gleichheit** (erster Durchgang, Sim-Hash `386c5ec814feb302` = Schlussstand, `mess/schritt3b/gleich/`):
  - alle Schalter aus gegen `6c1741e`: Seeds 1–3, 730 Tage, stündlich und in Tagesschritten, je **730 von 730 Tagen gleich** (bis auf memName
    und die Version);
  - mit Gedächtnis gegen `sicherung_schritt3_verblasst`: dieselben Seeds und Wege, je **730 von 730 Tagen gleich, ohne Ausnahme** (gelernte
    Erfahrungen gleich).
- **Gate T** (Fortsetzung, `mess/schritt3c/`, mit `stadt.html` `655daec7…`, derselbe sim-Block wie der Endstand; Rechner ruhig: Last
  1,2–2,5, keine fremden Rechenprozesse):
  - gegen `6c1741e`, 4 Runden im Wechsel (`werkzeug/gate_wechsel1.sh 4 1`, 22:19–22:21 UTC): neu 1.215 / 1.201 / 1.301 / 1.263 ms, Median
    1.239 ms, 4 von 4 unter 5.000; Basis 3.372 / 3.325 / 3.331 / 3.296 ms, Median 3.328 ms; **neu/Basis 0,372** (VERBLASSEN.md B.5: 0,352,
    KALIBRIERUNG.md Teil C: 0,370). `simtest --gate` Seed 1: „Gate Phase 0: BESTANDEN“, Gate 7 nicht gewertet (n < 15, Entscheidung 8).
  - Weil 0,372 über 0,352 liegt, habe ich direkt gegen den Stand vor Schritt 3 gemessen (20 Runden im Wechsel, 22:20–22:23 UTC,
    `gate_t_vorher/wechsel.txt`): vorher Median 1.189,5 ms, nachher 1.216 ms; **Median der Paarverhältnisse 1,006**; nachher in **11 von 20**
    Runden langsamer, im Mittel +13,5 ms. In den ersten 8 Runden war nachher 7-mal langsamer, in den folgenden 12 nur 4-mal. Das werte ich als
    Streuung; die Gate-Ausgaben (ohne Zeiten) sind gleich. Gate T ist damit nicht langsamer geworden.
- **Harte Grenze** (`werkzeug/vb_harte_grenze.mjs`, `mess/schritt3c/harte_grenze.txt`): statisch in Ordnung (30 Entscheidungs- und
  Lernfunktionen, `personInfo` nennt Namen nur lebender Personen über den Verweis, sonst die Beziehung). Namenstausch mit Stärke 1,5 und
  `PLAN_RUECKLAGE = 1`, Seeds 1 und 2 × 200 Tage: jeden Tag alles gleich.
- **Modul-Skript** (die 326 neuen Zeilen, `mess/schritt3c/neue_zeilen.txt`): kein Zugriff auf Geschlecht, Herkunft, Eltern, Einzugstag;
  `sort` nur nach der Summe im „Warum?“, `filter` nur nach Langzeit/Kurzzeit, Handlung und Erinnerungscode; Namen nur zur Anzeige über
  `Sim.name` (Liste, nur lebende Person gleicher Generation) und den eigenen Vornamen im „Warum?“; kein Aufruf der 3D-Ansicht.

## 10. Bestehende Browser-Tests vorher und nachher

**Vorher** = `sicherung_schritt3_verblasst` in zwei Teilläufen: 22:03–22:14 UTC (erster Durchgang, bis zum Neustart; `wachstum` abgebrochen,
`mess/schritt3b/browser_lauf.txt`, `browser_vorher/`) und 22:23–22:41 UTC (Fortsetzung: die fehlenden Tests ab `wachstum`,
`browser_lauf2_vorher.txt`, `browser_vorher2/`). `p6migration`, `p4test` und `autos_bild` fehlten in der Liste des ersten Durchgangs; ich habe
sie auf beiden Seiten dazugenommen. **Nachher** = Baukopie (`stadt.html` `5bce9c19…`, vor den zwei Textänderungen), alle 32 Tests in einem
Lauf, 22:46–23:13 UTC (`browser_lauf_nachher.txt`, `browser_nachher/`). Immer `tests/alle.sh` auf Port 9092, ein Test nach dem anderen; der
KI-Nachbau auf 11434 lief schon und blieb unberührt. Tabelle aus `werkzeug/s3c_vergleich.mjs` (`mess/schritt3c/vergleich_browser.txt`):

| Test | vorher | nachher | FEHL-Zeilen wörtlich gleich |
|---|---|---|---|
| `p3test` | grün, OK 12/12, FEHL 0 | grün, OK 12/12, FEHL 0 | ja |
| `p5neu` | grün, OK 10/10, FEHL 0 | grün, OK 10/10, FEHL 0 | ja |
| `p6migration` | ROT, OK 30/39, FEHL 9 | ROT, OK 30/39, FEHL 9 | ja |
| `p7figuren` | grün, OK 6/6, FEHL 0 | grün, OK 6/6, FEHL 0 | ja |
| `p8tech` | ROT, OK 3/15, FEHL 3 | ROT, OK 3/15, FEHL 3 | nein |
| `raute_klick` | ROT, OK 11/8, FEHL 0 | ROT, OK 11/8, FEHL 0 | ja |
| `ereignis` | ROT, OK 11/21, FEHL 2 | ROT, OK 11/21, FEHL 2 | ja |
| `t1_xss` | ROT, OK 0/5, FEHL 0 | ROT, OK 0/5, FEHL 0 | ja |
| `p4test` | grün, OK 29/29, FEHL 0 | grün, OK 29/29, FEHL 0 | ja |
| `s2karten` | grün, OK 22/22, FEHL 0 | grün, OK 22/22, FEHL 0 | ja |
| `kita` | grün, OK 22/22, FEHL 0 | grün, OK 22/22, FEHL 0 | ja |
| `befunde_s2` | grün, OK 27/27, FEHL 0 | grün, OK 27/27, FEHL 0 | ja |
| `erweiterung` | ROT, OK 10/20, FEHL 10 | ROT, OK 10/20, FEHL 10 | ja |
| `sicherheit` | grün, OK 12/12, FEHL 0 | grün, OK 12/12, FEHL 0 | ja |
| `militaer` | ROT, OK 15/16, FEHL 1 | ROT, OK 15/16, FEHL 1 | ja |
| `autos` | grün, OK 9/9, FEHL 0 | grün, OK 9/9, FEHL 0 | ja |
| `autos_bild` | ROT, OK 16/20, FEHL 4 | ROT, OK 16/20, FEHL 4 | ja |
| `rathaus` | grün, OK 15/15, FEHL 0 | grün, OK 15/15, FEHL 0 | ja |
| `schule` | grün, OK 8/8, FEHL 0 | grün, OK 8/8, FEHL 0 | ja |
| `haushalt` | grün, OK 18/18, FEHL 0 | grün, OK 18/18, FEHL 0 | ja |
| `wachstum` | grün, OK 29/29, FEHL 0 | grün, OK 29/29, FEHL 0 | ja |
| `techfrueh` | ROT, OK 16/17, FEHL 1 | ROT, OK 16/17, FEHL 1 | ja |
| `befunde_v9` | ROT, OK 19/20, FEHL 1 | ROT, OK 19/20, FEHL 1 | ja |
| `otest/befunde` | ROT, OK 19/21, FEHL 2 | ROT, OK 19/21, FEHL 2 | ja |
| `otest/handy` | grün, OK 11/11, FEHL 0 | grün, OK 11/11, FEHL 0 | ja |
| `otest/breit` | grün, OK 12/12, FEHL 0 | grün, OK 12/12, FEHL 0 | ja |
| `otest/tastatur` | grün, OK 4/4, FEHL 0 | grün, OK 4/4, FEHL 0 | ja |
| `otest/breiten` | grün, OK 20/20, FEHL 0 | grün, OK 20/20, FEHL 0 | ja |
| `otest/hilfehoehe` | grün, OK 1/1, FEHL 0 | grün, OK 1/1, FEHL 0 | ja |
| `p10speicher` | grün, OK 10/10, FEHL 0 | grün, OK 10/10, FEHL 0 | ja |
| `gedaechtnis` | – (neu) | grün, OK 15/15, FEHL 0 | – |
| `browser_ki` | ROT, OK 4/30, FEHL 17 | ROT, OK 4/30, FEHL 17 | ja |

- **31 von 31 vergleichbaren Tests: gleiches Urteil, gleiche OK- und FEHL-Zahl.** Die FEHL-Zeilen sind in 30 Tests wörtlich gleich. In
  `p8tech` unterscheiden sie sich nur in Zählungen („Programmierer-Figuren, die stehen“): vorher 28/19, nachher 30/20. Ein zweiter Lauf je
  Seite gab vorher 25/19 und nachher 32/22 (`mess/schritt3c/p8vorher/`, `end/`). Die Zahlen streuen also von Lauf zu Lauf; Urteil und
  FEHL-Zeilen bleiben gleich.
- Nachher grün: 20 von 32 (mit `gedaechtnis`). `alle.sh` meldet „13 ROT“, weil es das Scheitern von `basis.cjs` (Teststand) mitzählt.
- **Nach den zwei Textänderungen** (nur Zeilen im Abschnitt „Erfahrung und Plan“ der Personenkarte) liefen noch einmal auf dem Endstand:
  `gedaechtnis`, `otest/handy`, `otest/breiten`, `s2karten`, `befunde_s2` (alle grün, `mess/schritt3c/end2.txt`); `p8tech` lief nach der
  ersten der beiden (rot wie vorher, `end.txt`). Den ganzen Lauf habe ich dafür nicht wiederholt.

**Woher die roten Tests kommen** (alle waren schon vor Schritt 3 rot, also nicht durch die Oberfläche):

- **Erwarten Version 9** (bekannt aus SCHRITT2.md, Abschnitt 11): `p6migration`, `techfrueh`, `befunde_v9`; `basis.cjs` („Übernahme nach
  Version 9 gescheitert“), darum fehlt `basis_v9.json` und `t1_xss` bricht ab; `browser_ki` (Policies der Version 9 werden abgelehnt,
  Entscheidung 5).
- **Die Teststadt läuft anders:** `erweiterung`, `militaer`, `ereignis`, `p8tech`, `autos_bild`, `raute_klick`, `otest/befunde`. Neu gemessen:
  - Auf `6c1741e` (`sicherung_schritt0`, byte-gleich mit `git show 6c1741e`, auch die Testdateien) sind alle 7 grün (23:17–23:22 UTC,
    `mess/schritt3c/basis6c.txt`).
  - Auf einer Kopie des Endstands mit `GED: 0`, `OPFER_FREI: 0`, `HAFT_EROEFFNUNG: 0` (sonst gleich, auch die Oberfläche von Schritt 3) sind
    ebenfalls alle 7 grün (23:24–23:28 UTC, `mess/schritt3c/aus_browser.txt`, Kopie `tmp/kopie_aus_browser/`).
  - Der Unterschied kommt also nur aus dem neuen Verhalten. Die Tests suchen feste Momente und Orte der Teststadt, und die gibt es mit
    Gedächtnis nicht mehr. Beispiele aus den Logs: `ereignis` erwartet an Tag 423 um 0 Uhr drei Schließungen, jetzt ist es eine; danach
    bricht der Test ab (`TypeError` in Zeile 114, weil bei 20× kein Zeichen kam). `raute_klick` findet 10 statt 7 Figuren und schreibt darum 11
    statt 8 OK-Zeilen (exit 0, aber nicht die Soll-Zahl). In `militaer` liegt die Kaserne an anderer Stelle. In `otest/befunde` trifft das
    Tippen die Hauskarte nicht mehr, und die zweite Prüfung scheitert als Folge. Die anderen habe ich nicht im Einzelnen angesehen.
  - Das gehört zu Schritt 4 (neue Momente suchen, Vergleiche mit alten Fassungen über `R.GED = 0`).
- Nebenbei zeigt der zweite Lauf: Mit ausgeschalteten Schaltern stört die neue Oberfläche diese 7 Tests nicht.

## 11. Befunde und offene Punkte

1. **Die Liste zeigt auch Plan-Fälle.** Noahs Entscheidung 4 sagt „Heute anders entschieden wegen Erfahrung“. Der Beobachter meldet
   jeden direkten Fall, in dem Erfahrung **oder** Plan die Wahl geändert hat, und der Auftrag sagt „die direkten Fälle sammeln“. Die Liste
   heißt deshalb „wegen Erfahrung oder Plan“. Sie zählt je Grund und hebt Erfahrung hervor. In Seed 1, Tag 370, 7 Uhr sind es 14 Erfahrung,
   10 Plan und 2 beides; die ersten Einträge sind dort Plan-Fälle („Rücklage fehlt“). **Frage an Noah:** Soll die Liste nur Fälle mit
   Erfahrung zeigen (und zählen)? Das wäre ein Filter im Modul-Skript und nicht gebaut.
2. **Knopftext** „26 anders“ statt „Erfahrung wirkt: 12 heute“ (Beispiel im Auftrag): Im Kopf des Stadtbuchs ist nur Platz für Symbol, Zahl
   und ein Wort. Der volle Text steht im `aria-label` und im `title`.
3. **„Warum?“ ohne Eintrag in der Liste** rechnet mit einer neuen Zufallszahl, nicht mit der echten letzten Entscheidung, und sagt das.
   Eine echte Entscheidung erklärt es nur, wenn sie heute oder gestern in der Liste steht.
4. **Aufholen kostet etwa 3–5 %** mehr (Node ×1,028, Browser ×1,054 in 3 Läufen), weil die Simulation bei gesetztem Beobachter die Spur
   „ohne Erfahrung und Plan“ mitrechnet, auch für die Tage, deren Meldungen die Seite verwirft. Vermeiden ließe sich das, wenn das Aufholen
   den Beobachter erst für die letzten zwei Tage setzt. Das ist nicht gebaut.
5. **Leistung auf einem echten Gerät** ist nicht gemessen. Im Headless-Browser begrenzt die Software-Grafik auf unter 2 Bilder je Sekunde.
6. **du-Form:** Die Personenkarte redet die spielende Person nicht an, sie beschreibt die Figur in der dritten Person. Die neuen Texte
   machen es genauso (kein „du“, im „Warum?“ der Vorname der Figur). Falls „du-Form“ anders gemeint war (etwa „ohne diese Erfahrung
   hättest du …“), ist das offen.
7. **Handy quer:** Der Kopf der Hauptfiguren ist 2 px höher (48 → 50 px).
8. **Für Schritt 4:** 12 rote Browser-Tests (Abschnitt 10). 7 davon sind nachweislich nur „die Teststadt läuft anders“. Die übrigen 5
   erwarten Version 9. Dazu kommen die roten `simtest`-Läufe aus VERBLASSEN.md B.5.
9. **Sicherung der Fortsetzung:** Vor den kleinen Änderungen der Fortsetzung habe ich keine Sicherung angelegt. Den Stand davor habe ich
   nachträglich rekonstruiert, indem ich die Änderungen zurückgenommen habe: `sicherung_schritt3_vor_fortsetzung/`. Für `stadt.html`
   ist der sha256 gleich dem Stand vom Beginn der Fortsetzung (`655daec72066bede…`, um 22:16 UTC notiert). Die drei Testdateien haben
   dieselben Größen wie in der Liste vom Beginn (`gedaechtnis.cjs` 19.107, `alle.sh` 7.400, `LIESMICH.md` 14.700 Byte). Ihren sha256
   hatte ich vorher nicht notiert. Eine Zwischenfassung des Tests (mit 4b, vor den Textänderungen) ließ sich auf ihren notierten sha256
   `07659abf…` nachrechnen.

## 12. Nachprüfen

```bash
E=$SP/ml/e2bau
cd $E/stadt
# Browser-Test allein (startet und beendet den Seitenserver auf 9092; 11434 bleibt unberührt, wenn dort schon etwas antwortet)
PORT=9092 AUSGABE=$E/mess/x THREE_DIR=$E/../../three/package STADT_GIT=<repo> bash tests/alle.sh gedaechtnis
# Gate T im Wechsel mit 6c1741e (allein laufen lassen)
bash $E/werkzeug/gate_wechsel1.sh 4 1 $E/mess/x/gate_t
# Browser-Leistung vorher/nachher (große Stadt, eigener Server auf 9092)
bash $E/werkzeug/s3c_leistung.sh $E/mess/x/leistung.json 3 20
# harte Grenze und Namenstausch
cd $E/werkzeug && node vb_harte_grenze.mjs --seeds 1,2 --tage 200
```
