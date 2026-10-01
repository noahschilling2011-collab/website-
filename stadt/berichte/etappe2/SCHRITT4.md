# STADT – Etappe 2, Schritt 4: Tests (30.09./01.10.2026, 23:40–01:10 UTC)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

`SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`. Baukopie `E/stadt`, Port 9093.
Sicherung vor den Änderungen: `E/sicherung_schritt4` (= Schlussstand von SCHRITT3.md; sha256 der Dateien in `E/sicherung_schritt4.sha256`).
Rohdaten `E/mess/schritt4/`, Werkzeuge `E/werkzeug/s4_*`. **Im Repo ist nichts geändert, nichts angelegt, nichts committet** (`git status`
leer, HEAD `6c1741e`, vor und nach der Arbeit geprüft).

**Die Simulation ist unverändert.** `stadt/stadt.html` ist byte-gleich mit dem Stand vor Schritt 4 (sha256 `ac899293429df032…`, Sim-Hash
`386c5ec814feb302`, `VERSION = 10`, `GED: 1, GED_STAERKE: 1.5, PLAN_RUECKLAGE: 1, ERF_HALB: 180`). Geändert sind nur Werkzeuge, Tests und
`tests/LIESMICH.md`. Eine Messung von Gate T im Wechsel mit der Basis war deshalb nicht nötig (Nachtrag 7 gilt für Änderungen am sim-Block);
Gate T steht trotzdem in jedem `simtest --gate` und in den Seeds 1–80 (Abschnitt 8).

Alle Zahlen sind gemessen, außer wo „Annahme“ oder „nicht geprüft“ steht.

## 0. Ergebnis

Alle Punkte von VERGLEICH.md Schritt 4 sind gebaut. Aus einer frischen Kopie (`E/frisch_tests`) sind **`simtest_alle.sh` 23 von 23 Läufen
grün** (22 bisherige + `--gedaechtnis`) und **`PORT=9093 bash tests/alle.sh` 32 von 32 Tests grün („ALLES GRÜN“, 534 OK-Prüfungen)**. Die
Gates der Seeds 1–80 mit dem Endstand sind Seed für Seed gleich der Messung aus VERBLASSEN.md (bis auf die Wandzeit).

| Kriterium | Ergebnis | Rohdaten (`E/mess/schritt4/`) |
|---|---|---|
| neuer Modus `simtest --gedaechtnis` (Gegenprobe, Schalter aus, Gedächtnisgrenzen, Planabbruch, ID mit Generation, Migration, beschädigte Stände, Aufholen, Namenstausch, Leseliste, Beobachter) | **39 Prüfungen, alle ok**, 45 s im Lauf mit 2 Prozessen | `frisch2/simtest_alle/gedaechtnis.txt` |
| in `simtest_alle.sh` aufgenommen | ja (mit `--git`), 23 Läufe | `frisch2/simtest_alle.txt` |
| `GED` in den Aus-Listen, `PF_GED` in den Ausnahmelisten der Vergleichsmodi | 5 Modi vorher rot, jetzt grün mit **derselben Zahl an Prüfungen wie in Schritt 0**; Gegenprobe: ein Feld aus `PF_GED`, das mit `R.GED = 0` geschrieben wird, macht sie rot | `okzahlen_vergleich.txt`, `gegenprobe_pfged.txt` |
| `--kipolicy` vergleicht mit `R.GED = 0` | Seeds 1–3 × 730 Tage jeden Tag bitgleich zu `09083f5` (ohne memName, `PF_GED` 0, ohne Versionsnummer) | `frisch2/simtest_alle/kipolicy.txt` |
| Ablehnung der Policy aus Version 9 ausdrücklich geprüft | Node: künstliche Policy mit Version 9 und `ki/policy_v9_lokal_1.json` abgelehnt mit „… (neu trainieren)“, Gegenprobe mit Version 10 angenommen, setzen nicht möglich; Browser: in `ki/` und beim Datei-Import sichtbar abgelehnt | `…/kipolicy_datei_policy_v9_lokal_1.txt`, `frisch/browser/logs/browser_ki.log` |
| `tools/kiepisode.mjs` zählt Ziele ohne Platz im Schlüssel | ja; Prüfung I in `--gedaechtnis`: ein Eintrag, der in die Langzeit rückt, zählt einmal (mit Platz wären es 2) | ebenso |
| Browser `p6migration` (Version 10, Übernahme eines Stands der Version 9 mit Größe) | 44 von 44 (vorher 39, +5) | `frisch/browser/logs/p6migration.log` |
| `basis.cjs` (Kette bis 10), `umgebung.cjs` (Fassung `6c1741e` als v9) | Teststand über 6c1741e → 10; `t1_xss`, `befunde_v9`, `techfrueh` grün | `frisch/browser/logs/basis.log` |
| `browser_ki` (Version 10, Ablehnung sichtbar) | 32 von 32 (vorher 30, +2) | `frisch/browser/logs/browser_ki.log` |
| `gedaechtnis.cjs` in `alle.sh` mit Soll-Zahl | schon in Schritt 3 (Soll 15); 15 von 15 | `frisch/browser/logs/gedaechtnis.log` |
| die 7 Tests „Teststadt läuft anders“ | neue Momente bzw. robustere Suche, je begründet (Abschnitt 6.2); alle grün | `browser2.txt`, `frisch/browser.txt` |
| frische Kopie: `simtest_alle` | **23 / 23** (zweimal: vor und nach der letzten Änderung an `simtest.mjs`) | `frisch/`, `frisch2/` |
| frische Kopie: `tests/alle.sh` | **32 / 32, ALLES GRÜN**, 28 min | `frisch/browser.txt`, `frisch/lauf.txt` |
| Seeds 1–80 (Gates) mit dem Endstand | Gates 1, 2, 3, 5, 6, T, B je 80/80, **Gate 4 80/80**, Gate 7 **55 gewertet (alle bestanden), 25 nicht gewertet**, 0 Abstürze; je Seed gleich VERBLASSEN.md | `gates_1_80/` |
| Schalter aus = 6c1741e | `--gedaechtnis` B: Seeds 1–3 × 365 Tage stündlich und in Tagesschritten je 365/365 Tage gleich | `frisch2/simtest_alle/gedaechtnis.txt` |
| harte Grenze, Namenstausch | `--gedaechtnis` H: 32 Funktionen und 99 Zeilen statisch in Ordnung (mit Gegenprobe), Namenstausch Seeds 1 und 2 × 200 Tage jeden Tag gleich | ebenso |

## 1. Was geändert ist

Geändert sind genau diese Dateien (`diff -rq` gegen `sicherung_schritt4`; keine Datei neu oder gelöscht). Diffs in `mess/schritt4/diffs/`,
sha256 des Endstands in `mess/schritt4/endstand.sha256`.

| Datei | Änderung |
|---|---|
| `tools/simtest.mjs` (6.116 → 6.706 Zeilen, sha256 `bfb99a3452216aa7…`) | Aus- und Ausnahmelisten (2), `--kipolicy` (3), `--gedaechtnis` (4, 503 Zeilen), `gedBeschaedigt` (gemeinsam mit `--speichertest`, 4.F), Kopf der Datei |
| `tools/simtest_alle.sh` | `gedaechtnis` in der Liste, mit `--git`; prüft, dass `6c1741e` in der Git-Geschichte ist; Kopfkommentar (21 Modi) |
| `tools/kiepisode.mjs` | Schlüssel in `zieleZaehlen` ohne Platz (5) |
| `tests/umgebung.cjs` | Fassung `v9` = `6c1741e` (Commit und Git-Blob `abe1a2f6…`) |
| `tests/basis.cjs`, `tests/hilfe.cjs` | Kette bis 10; Teststand `basis_v10.json` |
| `tests/p6migration.cjs`, `browser_ki.cjs`, `techfrueh.cjs`, `befunde_v9.cjs` | Version 10 (6.1) |
| `tests/erweiterung.cjs`, `militaer.cjs`, `ereignis.cjs`, `p8tech.cjs`, `autos_bild.cjs`, `otest/befunde.cjs` | Teststadt läuft anders (6.2) |
| `tests/alle.sh` | Soll `p6migration` 39 → 44, `browser_ki` 30 → 32, `raute_klick` 8 → 11, mit Kommentar |
| `tests/LIESMICH.md` | Fassung v9, Teststand, Soll-Zahlen, KI-Test seit Version 10 |

## 2. Bestehende Vergleichsmodi: `GED` aus, `PF_GED` ausgenommen

Rot waren vor Schritt 4 (VERBLASSEN.md B.5): `--schule` (1), `--rathaus` (2), `--techfrueh` (3), `--erweiterung` (7), `--wachstum` (3),
`--kipolicy` (3) und `--kipolicy` mit der Policy-Datei (Abbruch beim Laden). Alle sind Vergleiche mit älteren Fassungen, die mit `R.GED = 1`
liefen.

**Änderung** (oben in `simtest.mjs`, für alle Modi gemeinsam):

- `GED_AUS = ['GED', 'OPFER_FREI', 'HAFT_EROEFFNUNG']` und `gedAus(X)` (setzt die drei auf 0 und gibt eine Funktion zurück, die sie wieder
  setzt). Diese Liste hängt jetzt auch an `AUS` (alle Bausteine aus für Vergleiche mit Version 6/7: `sicherheitAus`, damit `--erweiterung`
  und `--migrationstest`), an der Liste der Version-9-Bausteine in `--techfrueh` B, und wird in `--rathaus` H, `--schule` G, `--wachstum` B
  und `--kipolicy` gesetzt und danach zurückgesetzt.
- `OHNE_GED` = Felder aus `PF_GED` und `memName`: Die Spuren der Vergleiche lassen sie aus (die alte Fassung hat kein `PF_GED`, die neue kein
  `memName`; memName war nur Anzeige). **Damit nichts schwächer wird**, geht `gedNichtNull(S)` in jede Spur ein: Jedes Feld aus `PF_GED`, das
  nicht 0 ist, macht die Spur anders. Mit `R.GED = 0` schreibt sie niemand; die Vergleiche prüfen also zusätzlich, dass das so bleibt.
- `S.stat.ged` habe ich **nicht** ausgenommen: Mit `R.GED = 0` gibt es das Feld nicht; gäbe es es, wäre der Vergleich rot (strenger als die
  Ausnahme aus `sparsam/stadt_aus/simtest_ausnahmen.diff`).
- Für `--kipolicy` gibt es `fingerabdruckVergleich` (wie `fingerabdruck`, ohne `p.memName` und `PF_GED`, mit `gedNichtNull`, Einzelwerte ohne
  die Versionsnummer).

**Belege, dass nichts abgeschwächt ist:**

- Gleiche Zahl an Prüfungen wie in Schritt 0 (`mess/simtest_alle_1/`, dort mit `6c1741e` + Vorarbeiten 22/22 grün) in allen Modi außer denen,
  die seitdem bewusst Prüfungen dazubekommen haben: `--migrationstest` 324 → 368, `--aufholtest` 0 → 3, `--speichertest` 0 → 1 (Schritt 2),
  `--kipolicy` 27 → 28 und mit Policy-Datei 28 → 30 (dieser Schritt). Alle anderen gleich, z. B. `--rathaus` 74, `--schule` 48,
  `--erweiterung` 33, `--wachstum` 26, `--techfrueh` 22 (`mess/schritt4/okzahlen_vergleich.txt`).
- **Gegenprobe** (`mess/schritt4/gegenprobe_pfged.txt`, Kopie `tmp/gegenprobe_ged`): In einer Kopie schreibt `ausfuehren` ein Feld aus
  `PF_GED` (`entZeit`) auch mit `R.GED = 0`. Dann sind `--wachstum` B (3 FEHL), `--techfrueh` B (3 FEHL) und die Regression in `--kipolicy`
  (3 FEHL) rot. Die Ausnahme verdeckt also keinen Unterschied.

## 3. `--kipolicy`: Vergleich mit `R.GED = 0` und Ablehnung der Policy aus Version 9

- **Regression** (Teil 1): Policy aus, `R.GED`, `OPFER_FREI`, `HAFT_EROEFFNUNG` = 0, jeden Tag `fingerabdruckVergleich` gegen `09083f5`
  (Version 9 ohne KI-Teil, wie bisher). Seeds 1–3 × 730 Tage jeden Tag bitgleich (1.449 / 1.509 / 1.515 Einwohner), S hat dieselben Schlüssel.
- **Neu, Teil 0: Ablehnung** (Noahs Entscheidung 5):
  - eine künstliche Policy mit Stadt-Version 9 (Hash passend) wird abgelehnt mit genau „Policy ungültig: trainiert auf Stadt-Version 9, diese
    Stadt ist Version 10 (neu trainieren)“;
  - jede Datei aus `ki/policies.json` bzw. `--policy` mit älterer Version ebenso (`policy_v9_lokal_1.json`, „v9_lokal_1“);
  - **Gegenprobe:** dieselbe Datei mit Stadt-Version 10 (Hash neu gerechnet) wird angenommen, abgelehnt wird also nur wegen der Version;
  - sie lässt sich nicht setzen (`policySetzen` wirft), es entscheiden die Regeln.
- **`--policy` mit einer Datei älterer Version** (der Lauf `kipolicy_datei` in `simtest_alle`): Der Modus prüft ihre Ablehnung und alles
  Übrige mit der künstlichen Policy (vorher brach er beim Laden ab). Eine Datei, die aus einem **anderen** Grund abgelehnt wird, bleibt ein
  Abbruch (rot).
- Hinweis: `simtest_alle` kopiert `ki/` nicht in seinen Temp-Ordner; im Lauf `kipolicy` (ohne `--policy`) wird deshalb nur die künstliche
  Policy der Version 9 geprüft („ki/policies.json nicht gelesen“), die echte Datei im Lauf `kipolicy_datei`.

## 4. Neuer Modus `simtest --gedaechtnis`

`node tools/simtest.mjs --gedaechtnis [--git ordner] [--tage 365] [--seeds 1,2,3]`, 39 Prüfungen, 45 s (im Lauf mit 2 Prozessen). Er lädt
eine Prüf-Fassung derselben Simulation mit zwei Haken in `entscheide` (nur aktiv, wenn gesetzt) und mehr Innereien in `_ged` (zum Erzwingen);
die Datei selbst bleibt, wie sie ist (wie `ladeSimMit` der anderen Modi). Ergebnisse aus `mess/schritt4/frisch2/simtest_alle/gedaechtnis.txt`:

**A Gegenprobe, Beobachter, Gedächtnisgrenzen** (Seeds 1–3, 365 Tage, stündlich; Kriterien von Schritt 1, Punkt 8, hier auf 365 Tagen):

| | Seed 1 | Seed 2 | Seed 3 | Soll |
|---|---|---|---|---|
| Entscheidungen; echte Wahl = Probe | 334.866; 334.866 | 286.341; 286.341 | 341.672; 341.672 | immer |
| ohne Erfahrung und Plan anders | 3.930 = 1,174 % | 2.961 = 1,034 % | 2.843 = 0,832 % | ≥ 0,3 % |
| davon direkt | 92,5 % | 89,9 % | 89,3 % | ≥ 85 % |
| ein Byte gelöscht → Wahl ohne Erfahrung | 1.128 / 1.130 = 99,82 % | 1.342 / 1.344 = 99,85 % | 1.327 / 1.328 = 99,92 % | ≥ 99 % |
| Beobachter-Meldungen = direkte Unterschiede | 3.634 = 3.634 | 2.662 = 2.662 | 2.538 = 2.538 | fehlend 0, zu viel 0 |
| Fingerabdruck mit Probe und Beobachter = ohne | gleich | gleich | gleich | gleich |
| Gedächtnisgrenzen in 365 Nächten | 0 Fehler | 0 Fehler | 0 Fehler | 0 |

Gedächtnisgrenzen je Nacht: `gedPruefen` (alle Wertebereiche wie beim Laden), Langzeit nur mit Bedeutung ab `MEM_SCHWELLE`, Langzeit nur bei
voller Kurzzeit, Langzeit nie jünger als die Kurzzeit. Häufigste Unterschiede: „laden_gruenden → nichts“ und „kuendigen → nichts“.

**B Schalter aus** (`R.GED`, `OPFER_FREI`, `HAFT_EROEFFNUNG` = 0) gegen `git show 6c1741e`: Seeds 1–3 × 365 Tage, stündlich und in
Tagesschritten, jeden Tag alle Arrays, Einzelwerte, JSON-Teile und Schlüssel von S gleich; ausgenommen nur `memName` (nur in 6c1741e, dort an
365 von 365 Tagen ≠ 0) und die Versionsnummer; `PF_GED` bleibt 0. **6 × 365 von 365 Tagen gleich.**

**C Gedächtnisgrenzen erzwungen** (Seed 1, Tag 300, eine Person mit geleertem Gedächtnis, Ereignisse über `erinnere`):

- Kurzzeit der Reihe nach; nach dem 4. Ereignis rückt nur das älteste in die Langzeit; Ereignisse mit Bedeutung unter 30 (Codes 1, 11) nie.
- Langzeit voll (5 × Bedeutung 60, gleich alt): ein weiterer gleicher Eintrag verdrängt nichts (Gleichstand: der alte bleibt), einer mit
  Bedeutung 85 verdrängt einen; ein 100 Tage alter (Wert 60 − 10 = 50) weicht einem heutigen.
- 1.000 Ereignisse aller Codes: Kurzzeit-Platz immer < 3, die Nachbarn im Speicher unverändert, Langzeit 5 Einträge, alle ab der Schwelle,
  `gedPruefen` ohne Fehler.

**D Planabbruch erzwungen** (je auf einer Kopie von Seed 1, Tag 300): Der Plan endet mit genau dem erwarteten Grund, nur dieser wird in
`S.stat.ged.planEnde` gezählt, „Ziel aufgegeben“ steht im Gedächtnis (außer bei „anderes Ziel“), der Planschritt des neuen Ziels kommt aus dem
Zustand.

- **Alter:** Ziel „eigener Laden“ von außen, dann 60 Jahre → „zu alt“.
- **Pleite:** echte Pleite des eigenen Betriebs (`pleite`): Erinnerung „pleite“ mit Fakt 208 (= Tage, die der Betrieb bestand), Sperre bis Tag
  480; dann „eigener Laden“ von außen → „Pleite, Gründung gesperrt“.
- **Ziel von außen:** „besserer Job“ → „Freunde“ endet als „anderes Ziel“; dasselbe Ziel noch einmal wird abgelehnt und ändert nichts.
- dazu **Erfahrung** (Gründen 2-mal, Wert −20, beide Lagen) → „schlechte Erfahrung“ und **Rente** (Plan „besserer Job“, 67 Jahre) → „in Rente“.

**E ID-Wiederverwendung mit Generation** (Seed 2, ab Tag 250): Person 5 (Generation 1, mit letzter Entscheidung) stirbt (`sterben`); ihr Platz
ist nach 11 Stunden neu vergeben (Generation 2). Die neue Person erbt nichts (keine Erfahrung, kein letzter Plan, keine Erinnerung von vorher,
keine alte letzte Entscheidung). Ihr Partner (Person 4) erinnert sich 2-mal an Generation 1; seine Karte nennt weder die neue Person noch die
alte beim Namen („mit dem damaligen Partner zusammengekommen | Der Partner ist gestorben“). **Gegenprobe:** `personInfo` ohne den Vergleich der
Generation nennt die neue Person; die Prüfung erkennt das.

**F Migration und beschädigte Stände:**

- Stand der Version 9 (`6c1741e`, Seed 3, Tag 400, 13 Uhr, 1.376 Einwohner): ohne Übernehmen abgelehnt („Spielstand ist von Version 9, diese
  Datei ist Version 10.“, als übernehmbar markiert); übernommen: Version 10, kein memName, 9.031 Erinnerungen neu verteilt (4.033 in der
  Langzeit), **unabhängig nachgerechnet 0 Personen falsch**, neue Felder 0, Planschritt wie `planSchrittVon` (0 falsch), Summen leer.
- 169 Erinnerungen an Menschen, die nicht mehr in der Stadt leben: Name darin 0-mal als Marke und 0-mal im Klartext; **Gegenprobe:** 6c1741e
  nennt im selben Stand alle 169 mit Namen (gleiche Zahl wie in SCHRITT2.md 2.2).
- 10 Tage weiter, gespeichert und geladen, 5 Tage später bitgleich; ein Stand der Version 10 wird von 6c1741e abgelehnt, auch mit Übernehmen.
- 23 beschädigte Stände der Version 10 (dieselbe Liste wie `--speichertest`, jetzt die gemeinsame Funktion `gedBeschaedigt`) am übernommenen
  Stand: alle mit ihrem Grund abgelehnt, 0 falsch; der unveränderte Stand wird angenommen, in einer Fassung mit `R.GED = 0` abgelehnt.
- `gedBeschaedigt` ist aus `--speichertest` herausgezogen; dessen Ausgabe ist danach **Zeile für Zeile gleich** der Ausgabe vor der Änderung
  (`mess/schritt4/speichertest_refaktor.txt` gegen `mess/verblassen/testfix/simtest_alle/speichertest.txt`).

**G Aufholen** (Seed 2 ab Tag 300, mit Speichern und Laden an den Grenzen): 1 × 30 = 3 × 10 Tage bitgleich (a) ab 0 Uhr in Tagesschritten wie
`aufholen()` und (b) ab 13 Uhr stündlich; an den Grenzen 415 / 350 bzw. 419 / 365 Handlungen offen, in jedem Stück wird gelernt
(65 / 121 / 72 bzw. 65 / 116 / 80). **Neu:** dieselben 3 × 10 Tage mit gesetztem Beobachter (wie in der Seite beim Aufholen, 410 bzw. 299
Meldungen) sind gleich.

**H Harte Grenze:**

- Statisch: 30 Entscheidungs- und Lernfunktionen, 2 Anzeigefunktionen und 99 neue Zeilen in bestehenden Funktionen lesen keine Namen, kein
  Geschlecht, keine Herkunft, keine Eltern, keinen Einzugstag; `memRef`/`memGen` nur zum Kopieren (`memBehalten`, `migriereGed`) und in der
  Anzeige (Liste wie `werkzeug/vb_harte_grenze.mjs`).
- **Gegenprobe:** In eine Kopie des Codes eingeschmuggelt `S.p.weib[p]` in `erfLernen` und `name(S, p)` in `planSchrittVon`: beide gefunden.
- Namenstausch (alle Vor- und Nachnamen um einen Platz verschoben), Seeds 1 und 2 × 200 Tage: jeden Tag alle Arrays (auch Gedächtnis,
  Erfahrung, Plan), Einzelwerte und Summen gleich; 255 bzw. 200 Erfahrungen gelernt.

**I kiepisode** (Abschnitt 5).

## 5. `tools/kiepisode.mjs`: Ziele ohne Platz im Schlüssel

`zieleZaehlen` zählte jeden Eintrag „Ziel erreicht“/„Ziel aufgegeben“ der Fokusperson unter dem Schlüssel Platz:Tag:Art:Ziel. Seit Etappe 2
kopiert `memBehalten` einen Eintrag aus der Kurzzeit auf einen Langzeit-Platz, er zählte dann zweimal. Der Schlüssel ist jetzt Tag:Art:Ziel
(`zielPruefen` schreibt je Person und Nacht höchstens einen dieser Einträge). Geprüft in `--gedaechtnis` I: „Ziel aufgegeben“ (Bedeutung 30)
rückt in die Langzeit und zählt einmal (mit dem alten Schlüssel nachgerechnet: 2), „Ziel erreicht“ (Bedeutung 20) wird vergessen und zählt
einmal. `--kipolicy` (nutzt `kiepisode.mjs`) bleibt grün.

## 6. Browser-Tests

### 6.1 Version 10

- **`umgebung.cjs`:** Fassung `v9` = `6c1741ec…` mit Blob `abe1a2f6…` (wie die anderen Fassungen geprüft).
- **`basis.cjs`:** Kette 797107a → 414ebab → bc7247a → ffa1d88 → 31ce452 → **6c1741e (9)** → `stadt.html` (**10**); `hilfe.cjs` nimmt
  `basis_v10.json`. `basis.log`: „stadt.html: Dialog true, Version 10, Tag 420 8 Uhr, 2186 Einwohner“. `t1_xss` 5/5.
- **`p6migration`** (NEU = 10), neu Abschnitt 9: Stand der Version 9 aus `6c1741e` (Seed 2, Tag 400, 1.278 Einwohner, 8.519 Erinnerungen):
  Dialog „Dein Spielstand ist von Version 9. Seit Version 10 lernen die Bewohner …“ mit Hinweis „Erfahrungen und Pläne beginnen am
  Übernahmetag“, „Beziehung statt des Namens“, „neu trainieren“; nach der Übernahme Version 10, Einwohner, Gebäude, Bürgermeister und Stadtbuch
  gleich, 7.262 von 8.519 Erinnerungen behalten (3.838 in der Langzeit, keine unter der Schwelle), neue Felder 0, Summen leer, kein memName,
  Meldung „… Neu: Bewohner mit Erfahrung und Plänen.“; **Größe** 906.168 → 923.723 Zeichen (+17.555), erwartet +10 Byte je Platz in Base64 =
  +17.040 bei 1.278 Plätzen, Abweichung 515 (Soll ±1.000; Rest: Kopfzeilen der 10 neuen Arrays und `stat.ged`); nach dem Neuladen kein Dialog.
  „Mit Größe“ habe ich als „mit der Größe des Spielstands“ gelesen (Annahme); die große Stadt prüft weiter `p10speicher`.
- **`browser_ki`:** Die Testdatei aus `tests/ki_testdaten/` ist von Version 9 und wird jetzt abgelehnt. Neu geprüft: (1b) sie liegt in `ki/`,
  „Trainierte Policy“ gewählt → im Fenster sichtbar „Abgelehnt: ki/policy_smoke_v9_2_bester.json: Policy ungültig: trainiert auf Stadt-Version
  9, diese Stadt ist Version 10 (neu trainieren)“, Regeln, Warnung; (9) Datei-Import derselben Datei → abgelehnt, Grund im Fenster sichtbar.
  Für alle übrigen Prüfungen legt der Test **eine Kopie mit Stadt-Version 10** in den Temp-Ordner `ki/` (`policy_test_v10.json`, gleiche
  Gewichte, Name `smoke_v9_2_bester_test_v10`, Hinweis „Nur Testdaten für den Ablauf … nicht neu trainiert“, Hash vom sim-Block neu gerechnet).
  Das ist kein Training auf Version 10 und kein Qualitätsbeleg, nur Testdaten für den Ablauf; die Dateien in `tests/ki_testdaten/` bleiben
  unverändert. Spielstand-Version im Test jetzt 10. 32/32.
- **`techfrueh`:** übernommen wird in Version 10 (`u.v === 10`). 17/17.
- **`befunde_v9`** und **`p6migration`** (Übernahme von Version 8): Die Meldung nach der Übernahme nennt seit Schritt 2 zusätzlich „; Bewohner
  mit Erfahrung und Plänen“ (gewollt). Die Grenze für ihre Länge (200 Zeichen, Befund Bedienung) wächst **genau um diesen Punkt** (35 Zeichen),
  und der Test verlangt jetzt, dass der Punkt darin steht. Gemessen: 208 Zeichen.

### 6.2 Die Teststadt läuft anders (alle 7 waren in SCHRITT3.md rot, auf 6c1741e und mit ausgeschalteten Schaltern grün)

Die Momente sind mit den Suchskripten der früheren Versionen neu gesucht (Kopien in `E/werkzeug/s4_*`, Protokolle in
`mess/schritt4/momente/`), wie bei jeder früheren Verhaltensänderung. Die Prüfungen selbst sind unverändert, außer wo genannt.

| Test | vorher | jetzt | Grund |
|---|---|---|---|
| `erweiterung` | Seed 40, Tag 242 → 243, 72 → 80 | **Seed 2, Tag 266 → 267, 72 → 80** | Seed 40 wächst nicht mehr allein; in Seeds 1–30 allein in der Stufe Stadt: Seed 2 (Tag 267), 5 (236), 8 (198) (`wachsen_1_30.txt`) |
| `militaer` | Suche am Abend, dann bis 10 Uhr | **Suche um 10 Uhr** (erster Tag, an dem es um 10 Uhr Soldat auf Zeit, Wehr- und Ersatzdienst gibt) | Wer am Abend von Tag 400 Wehrdienst leistet, ist am nächsten Morgen fertig (5 Diensttage); in Node um 10 Uhr alle drei zuerst wieder an Tag 407 (`werkzeug/s4_militaer.mjs`). Die Prüfung der Karte ist gleich |
| `ereignis` | Seed 4: 423, 457, 460, 474 | **Seed 3: 401, 519, 520, 549** (3 Schließungen; 4 Übernahmen; 1 fertig; 1 fertig + 1 Schließung) | In Seed 4 und 2 gibt es nach den Schließungen keine Stunde mit vier Übernahmen mehr (`ereignis.txt`, Seeds 4, 2, 3, 5) |
| `p8tech` | größte Tech-Firma | **größte Tech-Firma ohne Autowerk** (Luchs Handys, 8 Leute) | Die größte ist jetzt ein Autowerk (Vega Autos, 12 Leute); dessen Leute stehen auf dem Werksgelände (nur 20 von 30 „am Ort“), seine Karte sagt „Baut …“ statt „Arbeitet an …“. Auf 6c1741e war die größte keine Werk (Iris Handys, 16; `werkzeug/s4_p8tech.mjs`). Autowerke prüft `autos_bild`. Jetzt 14 von 14 Programmierern am Ort |
| `autos_bild` | Campus Seed 1; Fälle [21, 58, 8], [63, 172, 9], [16, 72, 9] | **Campus Seed 2** (Gebäude 10); **[64, 93, 8], [31, 118, 9], [19, 242, 9]** | Seed 1 hat an Tag 730 keinen Campus mehr (Seeds 1–8: Campus in 2, 3, 5, 8); Fälle neu gesucht auf Seeds 1–80 bis Tag 400: 23 Umzüge um 8 Uhr, 4 Stellenwechsel ohne Umzug (je der kürzeste genommen) |
| `raute_klick` | Soll 8 | **Soll 11** | 10 statt 7 Rauten im Bild (+ Summenzeile); das Kriterium des Tests (mindestens 4 Klicks, keiner daneben) ist unverändert. Deterministisch: vorher und nachher in Schritt 3 und hier je 11 |
| `otest/befunde` | Tippen auf die Gebäude nahe der Mitte | **dazu: eine Karte, die keine Hauskarte ist, vor dem nächsten Versuch schließen** | Vor dem ersten Gebäude steht jetzt eine Figur; das Tippen öffnet richtig ihre Personenkarte, die am Handy alle weiteren Ziele verdeckte (`werkzeug/s4_debug_tippen.cjs`, nur zur Untersuchung). Die Prüfung „Hauskarte per Tippen offen“ bleibt |

### 6.3 Läufe

- Einzeln: `browser1.txt` (Version 10: p6migration, techfrueh, befunde_v9, t1_xss, browser_ki), `browser2.txt` (die 7 aus 6.2 + p6migration):
  danach alle grün.
- **Frische Kopie** (`E/werkzeug/s4_frisch.sh`, `cp -r stadt frisch_tests`, `mess/schritt4/frisch/`): `PORT=9093 bash tests/alle.sh`,
  00:30–00:59 UTC, **32 von 32 grün, ALLES GRÜN**, 534 OK-Prüfungen, dazu `basis.cjs`. Der Dienst auf 11434 lief schon (KI-Nachbau
  „test-modell“) und blieb unberührt; der Seitenserver auf 9093 wurde von `alle.sh` per PID beendet.
- Nach diesem Lauf habe ich nur noch `tools/simtest.mjs` geändert (Abschnitt 9, Punkt 1); `stadt.html` und alle Dateien unter `tests/`
  sind im zweiten frischen Lauf byte-gleich (Vergleich der sha256-Listen `frisch/kopie.txt` und `frisch2/kopie.txt`).

## 7. `simtest_alle` aus einer frischen Kopie

- `frisch/` (00:25–00:30 UTC): 23 von 23.
- `frisch2/` (00:59–01:05 UTC, nach der letzten Änderung, Endstand `simtest.mjs` `bfb99a34…`): **23 von 23 Läufen mit Exit 0.**
  `--gate`: „Gate Phase 0: BESTANDEN“, T 1.231 / 596 / 550 ms (in `frisch/` 1.233 / 580 / 568 ms), Gate 7 in allen drei Seeds nicht gewertet
  (n = 13 / 7 / 13, Entscheidung 8, wie VERBLASSEN.md B.5).
- Rechner: kein fremder Rechenprozess, Last 2,7–3,9 (die eigenen 2 Prozesse), `lauf.txt`.

## 8. Seeds 1–80 (Gates) mit dem Endstand

`E/werkzeug/vb_gates.sh E/frisch_tests 1 80 mess/schritt4/gates_1_80 2` (01:04:42–01:05:58 UTC, 2 Prozesse, kein fremder Rechenprozess):

- Gates 1, 2, 3, 5, 6, T, B je **80/80**; **Gate 4 80/80** (Faktor 1,02–1,11, Median 1,06); **Gate 7: 55 gewertet, alle bestanden** (kleinster
  Abstand 20,2), **25 nicht gewertet** (Seeds 1, 2, 3, 4, 6, 7, 9, 10, 17, 20, 25, 27, 32, 34, 35, 36, 46, 55, 56, 64, 67, 68, 71, 74, 77);
  kleinstes Budget 1.741; 0 Abstürze; T 401–1.851 ms (2 Prozesse gleichzeitig).
- **Je Seed gleich** der Messung aus VERBLASSEN.md (`mess/verblassen/kand/gate_h180/`) bis auf die Wandzeit: 0 von 80 verschieden
  (`werkzeug/s4_gate_vergleich.py`).
- Kasse und Gründungen gepaart gegen `R.GED = 0` (Bezug: `mess/verblassen/kand/gate_ged0/`, **nicht neu gemessen**): Einwohner Tag 365
  +22 ± 9 (+1,7 %), Tag 730 −0 ± 8; Kasse Tag 365 −48.330 ± 10.226 (−4,7 %), Tag 730 −162.364 ± 21.940 (−17,1 %); Gründungen bis Tag 365
  −49 ± 8 (−15,5 %), bis Tag 730 −59 ± 17 (−11,9 %) — gleich VERBLASSEN.md B.7 (`gates_1_80/wirtschaft_gegen_ged0.txt`).

## 9. Befunde und offene Punkte

1. **Nachträglich korrigiert (nach dem ersten, vor dem zweiten frischen Lauf):** In `--gedaechtnis` F zählte die Namensprüfung zuerst alle
   Erinnerungen mit einem Bezug, der nicht mehr lebt, also auch Gebäude und Ziele (5.320). Sie zählt jetzt nur Bezüge auf Personen (169),
   prüft zusätzlich den Klartext des alten Namens und hat eine Gegenprobe (6c1741e nennt alle 169 mit Namen). Die Prüfung war vorher schon
   grün, nur Zahl und Umfang waren falsch. (Denselben Fehler hatte E im Bau; dort war die Prüfung deshalb rot und ist vor dem ersten frischen
   Lauf korrigiert.)
2. **Entscheidungen, die du prüfen solltest:**
   - `p8tech` prüft jetzt die größte Tech-Firma **ohne** Autowerk. Alternative wäre, den Test auch für Autowerke zu erweitern (ihre Leute
     stehen auf dem Gelände, nicht am Gebäude).
   - `browser_ki` prüft den Ablauf mit einer **umgeschriebenen Kopie** der Version-9-Testdatei (Stadt-Version 10, gleiche Gewichte). Eine
     echte Policy für Version 10 gibt es erst nach dem neuen Training in Etappe 3; dann sollte sie die Kopie ersetzen.
   - Die Grenzen für die Länge der Übernahme-Meldung (befunde_v9, p6migration) sind um genau „; Bewohner mit Erfahrung und Plänen“
     gewachsen.
3. **Nicht angepasst:** die Zweige `--alt <datei>` in `--wachstum` und `--techfrueh` (Vergleich mit Zwischenständen von Version 9). Sie laufen
   nicht in `simtest_alle` und vergleichen alle Arrays samt `memName`/`PF_GED`; mit Version 10 wären sie rot. Nicht ausgeführt.
4. **`ki/policies.json`** nennt weiter `policy_v9_lokal_1.json` (Simversion 9); deshalb zeigt das Spiel die Ablehnung mit Grund
   (SCHRITT2.md 8). Unverändert gelassen.
5. **Nicht geprüft:** Firefox und Safari; die Browser-Tests laufen nur in Chromium (SwiftShader). Die neuen Momente hängen an der Stadt; jede
   weitere Verhaltensänderung verlangt wieder eine neue Suche (die Skripte liegen in `E/werkzeug/s4_*`).
6. **Rechner:** nie mehr als zwei eigene Rechenprozesse. Ein eigener Seitenserver auf 9093 (zum Untersuchen von `otest/befunde`) blieb nach dem
   ersten Beenden stehen, weil ich die PID der Subshell gemerkt hatte; ich habe ihn per PID 18406 beendet (an der Befehlszeile als meiner
   erkannt). 8000 und 11434 habe ich nicht angefasst, kein `pkill`/`killall`.
7. **Vorsicht beim Ändern laufender Skripte:** Während eines Laufs von `tests/alle.sh` hatte ich `tests/alle.sh` geändert; bash liest Skripte
   stückweise. Ich habe die Datei nach Sekunden auf den Stand des Laufs zurückgesetzt und erst danach geändert; der Lauf lief normal zu Ende.
   Gezählt habe ich nur Läufe, die mit einem festen Stand begannen und endeten.

## 10. Nachprüfen

```bash
E=$SP/ml/e2bau
SP=<arbeitsordner>
cd $E/stadt
node tools/simtest.mjs --gedaechtnis --git <repo>                 # 39 Prüfungen, etwa 40 s
node tools/simtest.mjs --kipolicy --git <repo> --rev 09083f5 --policy ki/policy_v9_lokal_1.json --tage 120
TMPDIR=$E/tmp/t4 STADT_GIT=<repo> JOBS=2 bash tools/simtest_alle.sh
PORT=9093 THREE_DIR=$SP/three/package STADT_GIT=<repo> TMPDIR=$E/tmp/t4 AUSGABE=$E/mess/x bash tests/alle.sh
bash $E/werkzeug/s4_frisch.sh $E/mess/x beides                                  # frische Kopie, beides
bash $E/werkzeug/vb_gates.sh $E/frisch_tests 1 80 $E/mess/x/gates 2
python3 $E/werkzeug/s4_gate_vergleich.py $E/mess/verblassen/kand/gate_h180/auswertung.txt $E/mess/x/gates/auswertung.txt
```
