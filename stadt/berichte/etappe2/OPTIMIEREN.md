# STADT – Etappe 2: Optimieren (Noahs Entscheidung 7: schneller, bitgleich)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

Stand 30.09.2026, 15:10 UTC. `SP` = Arbeitsordner der Sitzung (nicht im Repo), `E` = `SP/ml/e2bau`.
Baukopie `E/stadt`, Sicherung davor `E/sicherung_optimieren` (kalibrierter Stand: `stadt.html` sha256 `50adf8fd1de8bf03…`, Sim-Hash
`5475aede423a0000`). **Endstand** `E/stadt/stadt.html` sha256 `0e1667c8a79e57c9…`, Sim-Hash `5eae81848b5e6552`. Rohdaten `E/mess/optimieren/`,
Werkzeuge `E/werkzeug/opt_*`. **Im Repo ist nichts geändert, nichts angelegt, nichts committet** (`git status` leer, HEAD `6c1741e`).

Alle Zahlen sind gemessen, außer wo „Vermutung“ oder „gerechnet“ steht. Der Rechner war in dieser Phase ruhig (kein anderer Agent); vor jedem
Lauf stehen Uhrzeit, Last und fremde Rechenprozesse (node/python über 20 % CPU) in den Logs. Zeitmessungen liefen einzeln, Beweisläufe zu zweit.
Ausnahme: Während der Stufenmessung (Abschnitt 3, gegen 14:22) liefen zweimal kurze Prüfprozesse von je etwa 2 s nebenher; die Profile unter
„nachher“ sind allein gemessen.

## 0. Ergebnis

- **Gate T ist grün, mit viel Abstand.** `simtest --gate --seeds 1`, 8 Runden im Wechsel (Reihenfolge je Runde verschoben), 14:56–15:02 UTC:

  | Fassung | T (365 Tage Seed 1), Median | Spanne | T < 5000 ms | CPU des ganzen simtest-Prozesses, Median |
  |---|---|---|---|---|
  | **neu** (Endstand `0e1667c8…`) | **1.470 ms** | 1.413–1.785 | **8 von 8** | 6.030 ms |
  | sich (Sicherung `50adf8fd…`, unverändert) | 5.640,5 ms | 5.321–6.086 | 0 von 8 | 22.080,5 ms |
  | basis (6c1741e) | 4.446,5 ms | 4.281–4.958 | 8 von 8 | 19.640 ms |

  neu/sich **0,261 (−73,9 %)**, neu/basis 0,331; CPU (process.cpuUsage, Nutzer + System, alle Threads) neu/sich 0,273. Alle anderen Gates in
  allen 24 Läufen grün bzw. wie vorher (Gate Phase 0: neu 8 von 8 bestanden, basis 8 von 8, sich 0 von 8 nur wegen T).
- **Jedes Ergebnis bleibt gleich:** Der ganze Zustand ist Tag für Tag bitgleich zur Sicherung (Seeds 1–6, je 730 Tage stündlich und in
  Tagesschritten, R.GED = 1, R.GED = 0 und alle Schalter aus; große Stadt Seed 2 mit UMLAND 300000 bis Tag 750; Speichern und Laden um 13 Uhr),
  mit Schaltern aus Tag für Tag gleich 6c1741e (Seeds 1–6), und `simtest_alle` gibt ohne Zeitangaben dasselbe aus (4 erklärte Unterschiede,
  Abschnitt 6).
- **Große Stadt** (Seed 2, UMLAND 300000, 750 Tage): 65,8 s → 9,6 s im vm-Kontext (−85,4 %), 31,0 s → 10,2 s als gewöhnliches Skript wie im
  Browser (−67,2 %). **Seed 1 als gewöhnliches Skript** (wie im Browser, ohne vm): 3.285,5 → 1.475,5 ms (−55,1 %).
- Geändert sind nur Schreibweisen, die V8 langsam macht (vier Änderungen, Abschnitt 3). Keine Regel, keine Schwelle, kein Speicherformat, keine
  Oberfläche, kein Test und kein Werkzeug der Tests ist geändert. Harte Grenze: kein neues Feld, keine Änderung liest oder speichert Namen,
  Geschlecht, Herkunft, Eltern oder Einzugstag; die Namenstausch-Prüfungen in `simtest_alle` geben dieselbe Ausgabe wie vorher.
- Ein zusätzlicher Versuch (neuePerson mit `fill`) brachte 0,0 % und ist verworfen. Weiter habe ich nicht optimiert: Das Profil ist jetzt flach,
  der nächste Gewinn bräuchte Umbauten an `stunde`/`entscheide` (Abschnitt 4 und 8).

## 1. Ablauf (erster Durchgang und Fortsetzung)

- Erster Durchgang (etwa 13:10–14:15 UTC, vom Orchestrator für Entscheidung 8 angehalten, nicht wegen eines Fehlers): Profil, die vier Änderungen
  in `E/stadt/stadt.html` (gespeichert 13:39:58), der ganze Bitgleich-Beweis auf genau dieser Datei (13:41–13:52, `mess/optimieren/gleich/`, alles
  „ok“), `simtest_alle` für die Sicherung (13:52–14:12, `mess/optimieren/simtest_alle/sich/`). Angehalten während `simtest_alle` für neu.
- Fortsetzung (14:15–15:10 UTC), nichts neu begonnen:
  1. Stand geprüft: `stadt.html` hat noch sha256 `0e1667c8…` (= `mess/optimieren/stadt_html.sha256` des ersten Durchgangs), alle Beweisläufe
     des ersten Durchgangs nennen Sim-Hash `5eae81848b5e6552` und sind grün. Kurz nachgemessen (2 Runden, vm und direkt), dann gemessen, welche
     Änderung wie viel bringt (Abschnitt 3, `mess/optimieren/stufen/`).
  2. Profil des Stands, Allokationen, Wörterbuch-Prüfung, globale Namen (statisch und zur Laufzeit), Zeit nach dem Laden.
  3. Ein weiterer Ansatz (neuePerson) gemessen: kein Gewinn, verworfen. Die Datei ist danach unverändert geblieben.
  4. Den **ganzen Bitgleich-Beweis neu** gerechnet (14:34–14:48, `mess/optimieren/beweis/`), `simtest_alle` für neu (14:48–14:54), Profile
     nachher, Gate T im Wechsel (14:56–15:02).
- Ein Fehlstart, der Vollständigkeit halber: Mein erster Aufruf von `opt_gate_t.sh` (14:54) bekam den Ausgabeordner relativ; das Skript wechselt vor
  simtest in den Stadtordner, darum liefen die simtest-Läufe nicht. Gültig davon sind nur die 8 `opt_zeit`-Runden (neu 1.407 ms, sich 5.456,5 ms
  Median); liegt mit Vermerk in `mess/optimieren/gate_t_fehlstart/`. Danach mit absolutem Pfad vollständig gelaufen (`mess/optimieren/gate_t/`).

## 2. Profil vorher (Sicherung)

`opt_profil.mjs` (node:inspector, Abtastung alle 100 µs, stündlich wie Gate T, `kennzahlen` je Tag), vom ersten Durchgang; Zeilennummern sind
Zeilen im sim-Block (Datei = sim-Zeile + 921). Der Profiler selbst macht den Lauf langsamer (Abtastzeit 7.461 ms statt etwa 5.500 ms ohne).

Seed 1, Tag 0–365 (`mess/optimieren/profil/vorher_seed1.txt`):

| Funktion | selbst ms | selbst % | inklusive ms |
|---|---|---|---|
| stunde | 788 | 10,6 | 6.821 (91 %) |
| zufZiel | 528 | 7,1 | 528 |
| wirtschaft | 486 | 6,5 | 1.751 |
| zufall | 386 | 5,2 | 386 |
| entscheide | 356 | 4,8 | 1.737 |
| (Garbage Collector) | 293 | 3,9 | |
| kleinkind | 258 | 3,5 | 258 |
| einkauf | 257 | 3,4 | 257 |
| tagesabschluss | 240 | 3,2 | 3.759 (50 %) |
| kistenVerteilen | 236 | 3,2 | 238 |

Große Stadt Seed 2, UMLAND 300000, Tag 600–750 (6.141 → 7.236 Einwohner, `vorher_gross.txt`, Abtastzeit 43.088 ms): kistenVerteilen 7.920 ms
selbst (18,4 %), zufZiel 2.827, wirtschaft 2.677, stunde 2.220, entscheide 2.008, zufall 2.003, ladenZuordnen 1.621, kleinkind 1.381.

Was daran auffiel: Winzige, rein rechnende Funktionen waren teuer – `zufall` (vier Zeilen mit `Math.imul`) 5,2 %, `kistenVerteilen` (eine
Schleife mit `Math.abs`) 18 % in der großen Stadt, `kleinkind` (eine Schleife über die Bewohner eines Hauses) 3,5 %. Das sprach für Kosten der
Umgebung (V8, vm-Kontext), nicht für zu viel Arbeit der Regeln. Die Ursachen stehen in Abschnitt 3.

## 3. Ursachen und Änderungen

Vier Änderungen, alle im sim-Block, zusammen 118 Diff-Zeilen (`mess/optimieren/diff_stadt_html.txt`). Beitrag je Änderung mit `opt_ab.mjs`
(zwei Fassungen im Wechsel a b / b a, je Lauf ein eigener Prozess, 6 Runden, Seed 1, 365 Tage wie Gate T, Median; `mess/optimieren/stufen/`):

| Stufe | vm-Kontext (wie simtest, Gate T) | gewöhnliches Skript (wie im Browser) |
|---|---|---|
| S0 → S1: `felderObjekt` (3.1) | 5.491 → 4.238 ms (−22,8 %) | 3.123,5 → 1.903,5 ms (−39,1 %) |
| S1 → S2: eingebaute Objekte lokal (3.2) | 4.142,5 → 1.804,5 ms (−56,4 %) | 1.827,5 → 1.934,5 ms (+5,9 %, im Rauschen*) |
| S2 → S3: Schleifen mit Index (3.3) | 1.891 → 1.437,5 ms (−24,0 %) | 1.940 → 1.463 ms (−24,6 %) |
| S3 → S4: Kopie in `importZustand` (3.4) | 1.441 → 1.422,5 ms (−1,3 %, im Rauschen) | 1.473,5 → 1.532 ms (+4,0 %, im Rauschen*) |
| **S0 → S4 (Endstand)** | **5.387 → 1.446,5 ms (−73,1 %)** | **3.285,5 → 1.475,5 ms (−55,1 %)** |
| große Stadt, 750 Tage, S0 → S4 (2 Runden) | 65.827 → 9.578,5 ms (−85,4 %) | 31.046,5 → 10.169 ms (−67,2 %) |

\* Spannen überlappen stark (S1 1.713–2.243, S2 1.663–2.062 ms; S3 1.354–1.536, S4 1.502–1.592 ms). Erwartet ist dort kein Unterschied: Außerhalb
des vm-Kontexts ist ein globaler Name billig (3.2), und 3.4 wirkt erst nach dem Laden. In allen Läufen war der Fingerabdruck am Ende gleich
(`28e8b2d3b130a118` bzw. `221f300a6590d7d2` in der großen Stadt).

### 3.1 `S.p` und `S.g` als fertiges Objekt (`felderObjekt`)

- **Ursache (gemessen):** `S.p = {}` und `S.g = {}` bekamen ihre 109 bzw. 53 Felder einzeln mit berechnetem Namen (`S.p[n] = new T(…)`). V8
  stellt ein solches Objekt auf ein Wörterbuch um; dann ist jeder Zugriff wie `P.lebt[p]` eine Suche statt eines festen Versatzes.
  `%HasFastProperties` (`opt_woerterbuch.mjs`, `opt_schnell_pruefen.mjs`): in der Sicherung sind `S.p` und `S.g` Wörterbücher, im Endstand schnell.
- **Änderung:** `function felderObjekt(liste)` legt das Objekt mit allen Namen der Liste (PF bzw. GF) in derselben Reihenfolge und dem Wert
  `null` auf einmal an (`Object.fromEntries`); benutzt in `leererZustand` und `importZustand`. Danach werden die Arrays wie bisher eingesetzt.
- **Warum bitgleich:** gleiche Schlüssel in gleicher Reihenfolge; vor dem Anlegen der Arrays `null` statt „fehlt“ – beides falsy, und nichts im
  sim-Block oder in der Oberfläche fragt, ob ein Feld existiert (gesucht nach `in S.p`, `hasOwnProperty`, `Object.keys(S.p)`; die Tests nehmen
  `Object.keys(S.p)` nur mit `ArrayBuffer.isView`). Die Speicherung läuft über PF/GF, nicht über die Schlüssel.

### 3.2 Eingebaute Objekte als lokale Namen

- **Ursache (gemessen):** `tools/simtest.mjs` und `tools/simkern.mjs` führen den sim-Block in einem vm-Kontext aus. Dort geht jeder Zugriff auf
  einen globalen Namen über den Kontext (`opt_vm_zugriff.mjs`, `mess/optimieren/fortsetzung/vm_zugriff.txt`): `Math.round` über den globalen
  Namen 259,8 ns je Aufruf, über einen lokalen Namen 9,9 ns; `Infinity` 232,2 ns; `Number.isInteger` 228,5 ns; `undefined` 6,9 ns (V8 behandelt
  es gesondert). Ohne vm kosten alle 7–14 ns. Der sim-Block benutzte `Math` an 384 Stellen, `Uint8Array` 71, `Array` 59 usw. (statisch mit
  ESLint gezählt, `opt_globale.cjs`).
- **Änderung:** Eine Zeile am Anfang des sim-Blocks: `const { Math, Object, Array, Number, String, Boolean, JSON, Error, Map, Set, Infinity,
  NaN, ArrayBuffer, DataView, Uint8Array, …, Float64Array } = G;` (G ist das `globalThis`, das der Block schon bisher bekam).
- **Warum bitgleich:** Es sind dieselben Objekte, nur über einen lokalen Namen. Auch `Math.random` bleibt gesperrt (dasselbe `Math`, simkern
  ersetzt `random` vor dem Laden des Blocks).
- **Geprüft, dass nichts übrig ist:** statisch (`opt_globale.cjs` auf dem Endstand) bleiben nur `undefined` (33 Stellen, billig, siehe oben) und
  `globalThis` (einmal, Aufruf des Blocks); zur Laufzeit (neu: `opt_globale_namen.mjs`, zählt über einen Proxy jeden Namen, nach dem der
  Kontext fragt) in 730 Tagen Seed 1 **kein einziger** Zugriff (Sicherung in 30 Tagen: `Math` 32.770-mal, `Infinity` 305, `Map` 210, …).

### 3.3 Schleifen mit Index statt `for … of` in heißen Funktionen

- **Ursache (gemessen):** Allokationsprofil (`opt_alloc.mjs`, Seed 1, Tag 0–365, `mess/optimieren/fortsetzung/alloc_*_seed1.txt`): Die
  Sicherung legt 1.032 MB an, davon mindestens 826 MB (Summe der 30 größten Posten) Ergebnisobjekte des Array-Iterators (`next`), angerechnet
  bei `elternzeitMoeglich`, `kennzahlenRechnen`, `autoKennzahlen`, `betreuer`, `entscheide` (Vermutung: dort eingebettet sind `kleinkind`,
  `hhHatAuto`, `gebunden` …, deren Schleifen das sind). S1 und S2 legen ebenso 1.041 MB an, S3 nur 179 MB, davon `next` 6 MB. Warum V8 die
  Iterator-Objekte hier nicht wegoptimiert, habe ich nicht geklärt.
- **Änderung:** 18 Schleifen in 11 Funktionen – `neuePerson` (über PF), `ladenZuordnen`, `mangelRechnen`, `hhHatAuto`, `wirtschaft` (7),
  `kistenVerteilen` (2), `kleinkind`, `gemeinZahl`, `verdientImHaushalt`, `haushaltLage`, `gebunden` – von `for (const x of L)` auf
  `for (let i = 0; i < L.length; i++) { const x = L[i]; … }`, die Liste vorher in einer Konstante, wo sie ein Ausdruck war. Maschinell mit
  `opt_schleifen.py` (jede Stelle genau einmal, neue Namen kamen in der Funktion vorher nicht vor).
- **Warum bitgleich:** gleiche Reihenfolge und gleiche Elemente; die Länge wird wie beim Array-Iterator in jedem Schritt neu gelesen (falls der
  Rumpf die Liste ändert, verhalten sich beide gleich); die Liste wird wie bei `for … of` einmal zu Beginn genommen; `continue`, `break`, `return`
  wirken gleich. Die übrigen `for … of` im Block (135 Zeilen) laufen selten und sind unverändert.

### 3.4 `importZustand` gibt eine Kopie von S zurück

- **Ursache (gemessen):** Beim Laden bekommt S seine 83 Schlüssel einzeln mit berechnetem Namen (`Object.assign`, `S[k] = …`) und wird ein
  Wörterbuch (`opt_woerterbuch_laden.mjs`: Sicherung nach dem Laden `S`, `S.p`, `S.g` Wörterbuch; Endstand: keins).
- **Änderung:** `return { ...S };` statt `return S;` am Ende von `importZustand` (mit Kommentar).
- **Warum bitgleich:** dieselben eigenen Schlüssel in derselben Reihenfolge mit denselben Werten (flach; die Teilobjekte sind dieselben). Das alte
  S wird danach nirgends mehr benutzt (kein Modul-Zustand hält es; die Oberfläche nimmt den Rückgabewert, `stadt.html` Zeile 8945; alle Tests
  und Werkzeuge ebenso). Der Beweis lädt mitten am Tag und vergleicht danach Tag für Tag (Abschnitt 5).
- **Wirkung:** Im Wechsel S3/S4 nach Laden an Tag 1 (5 Läufe je): Median 1.852 → 1.727 ms (−6,7 %). Eine nur geladene Stadt (neu:
  `opt_ladezeit2.mjs`, an Tag 0 laden, dann 365 Tage nur die geladene) rechnet so schnell wie eine frische: 1.362 / 1.415 / 1.694 ms gegen
  1.717 / 1.431 / 1.421 ms (Sicherung 6.056 / 6.301 gegen 5.625 / 5.889 ms), mit gleichem Fingerabdruck `28e8b2d3b130a118`.

### 3.5 Verworfen

- `neuePerson`: `P[n].fill(0, …)` statt Element für Element (im Profil 2 % selbst). Im Wechsel 8 Runden: 1.513,5 gegen 1.513,5 ms (0,0 %),
  CPU −0,1 %. Kein Gewinn, nicht übernommen (`mess/optimieren/fortsetzung/ab_neuePerson_vm.jsonl`, Kandidat `E/tmp/opt2/k_neuePerson.html`).
- `undefined` lokal machen: nicht nötig, 6,9 ns im vm-Kontext (3.2).

## 4. Profil nachher (Endstand, allein gemessen, 14:54 UTC)

Seed 1, Tag 0–365 (`mess/optimieren/fortsetzung/nachher_seed1.txt`, Abtastzeit **1.624 ms** statt 7.461 ms):

| Funktion | selbst ms | selbst % | inklusive ms |
|---|---|---|---|
| stunde | 244 | 15,0 | 1.465 (90 %) |
| entscheide | 131 | 8,1 | 345 (21 %) |
| tagesabschluss | 130 | 8,0 | 823 (51 %) |
| (Garbage Collector) | 110 | 6,8 | |
| wirtschaft | 95 | 5,8 | 249 (15 %) |
| zufZiel | 41 | 2,5 | 41 |
| kitaTag | 38 | 2,3 | 47 |
| menschenTag | 36 | 2,2 | 98 |
| neuePerson | 34 | 2,1 | 35 |
| kennzahlenRechnen | 29 | 1,8 | 44 |

`zufall` (vorher 386 ms), `kleinkind` (258), `einkauf` (257), `kistenVerteilen` (236 → 13) sind aus der Spitze verschwunden.

Große Stadt, Tag 600–750 (`nachher_gross.txt`, Abtastzeit **4.947 ms** statt 43.088 ms): entscheide 776 ms selbst (15,7 %), `tag` des
Werkzeugs 664 (13,4 %; Vermutung: dort eingebetteter Code von `stunde`), stunde 538 (10,9 %), wirtschaft 229, zufZiel 226, menschenTag 146,
ladenZuordnen 140, kistenVerteilen 136 (vorher 7.920), kennzahlenRechnen 131.

Das Profil ist jetzt flach: Der Rest ist die Arbeit der Regeln selbst (die Schleife über alle Erwachsenen jede Stunde, zwei Entscheidungen je
Person und Tag, der Tagesabschluss). Allokationen: 181 MB in 365 Tagen (vorher 1.032 MB); größte Posten `entscheide` 31 MB, `zufZiel` 22 MB, `aktFreunde` 16 MB (Vermutung:
Kommazahlen, die V8 als eigenes Objekt anlegt, z. B. der Rückgabewert von `zufZiel`). Deoptimierungen (`--trace-deopt`, 365 Tage): 367, davon 66 in `autosTag` an derselben Stelle (fehlende Rückmeldung
für einen Namenszugriff); `autosTag` kostet selbst 16 ms, das lohnt nicht.

## 5. Bitgleich-Beweis (Endstand `0e1667c8…`, Sim-Hash `5eae81848b5e6552`)

Neu gerechnet 14:34–14:48 UTC (`mess/optimieren/beweis/`, Warteschlange mit 2 Plätzen, Log `schlange.log`), alle Befehle in `jobs.txt`.
`opt_gleich.mjs`: nach **jedem** Spieltag Fingerabdruck des ganzen Zustands (SHA-256 über alle Arrays nach Namen, Einzelwerte und JSON-Teile wie
`tools/tagvergleich.mjs`) und die Schlüssel von S, a = Sicherung, b = Endstand, Schalter in beiden gleich; Tabellen je Tag in den `.tsv`.

| Lauf | Ergebnis |
|---|---|
| R.GED = 1 (kalibriert), Seeds 1–3 und 4–6, je 730 Tage stündlich, Laden an Tag 365 um 13 Uhr | 6 × 730 von 730 Tagen bitgleich; geladen a = b an 365 Tagen, b geladen = b ohne Laden an allen Tagen |
| dieselben in Tagesschritten (`tagSchritt`) | 6 × 730 von 730 bitgleich |
| R.GED = 0, Seeds 1–6, stündlich (mit Laden) und in Tagesschritten | 12 × 730 von 730 bitgleich, Laden wie oben |
| alle Schalter aus (GED, OPFER_FREI, HAFT_EROEFFNUNG = 0), Seeds 1–6, beide Wege | 12 × 730 von 730 bitgleich |
| große Stadt Seed 2, UMLAND 300000, 750 Tage stündlich, Laden an Tag 600 um 13 Uhr | 750 von 750 bitgleich (7.236 Einwohner); geladen a = b an 150 Tagen, b geladen = b ohne Laden |
| große Stadt in Tagesschritten | 750 von 750 bitgleich (7.231 Einwohner) |
| Schalter aus gegen **6c1741e** direkt (`aus_gleich.mjs`: alle Arrays Byte für Byte, Einzelwerte, JSON, Schlüssel; neue Felder 0), Seeds 1–6, stündlich und in Tagesschritten | 12 × 730 von 730 Tagen gleich |

Die Ausgaben und die Tabellen je Tag (`.tsv`) der acht `opt_gleich`-Läufe sind Byte für Byte dieselben wie im ersten Durchgang (`gleich/`).
Dazu: In allen `opt_zeit`-Läufen (Stufen, Runden von Gate T) war der Fingerabdruck an Tag 365 in allen Fassungen `28e8b2d3b130a118`; Speichern
an Tag 0 und danach nur die geladene Stadt rechnen ebenfalls auf ihn (`opt_ladezeit2.mjs`).

Werkzeuge, die den sim-Block per Text-Ersetzung ändern, finden ihre Stellen im Endstand noch genau einmal: `varianten.mjs` (alle 6 Varianten),
`probe8.mjs`, `folgen.mjs`, `opfer_wirkung.mjs` laufen kurz ohne Fehler (`mess/optimieren/fortsetzung/werkzeug_anker.txt`); die Stellen von
`tools/simtest.mjs` prüft `simtest_alle` mit.

## 6. simtest_alle ohne Zeitangaben

`STADT_GIT=<repo> bash tools/simtest_alle.sh` (2 gleichzeitig): Sicherung 13:52–14:12 (erster Durchgang,
`mess/optimieren/simtest_alle/sich/`), Endstand 14:48–14:54 (`mess/optimieren/simtest_alle2/neu/`). Vergleich mit `opt_vergleich_alle.sh`
(entfernt nur Wandzeiten): **19 von 23 Dateien Zeichen für Zeichen gleich**, die 4 übrigen (`simtest_alle2/diff/`):

1. `gate.txt`: `✗ T` → `✓ T` für Seed 1 und 3, „NICHT BESTANDEN“ → „BESTANDEN“ – das ist das Ziel dieser Phase.
2. `status.txt`: `--gate` Exit 1 → 0, dadurch 12 → **13 von 22** Läufen mit Exit 0. Die übrigen 9 roten Läufe sind dieselben wie bei der
   Sicherung, mit Zeichen für Zeichen gleicher Ausgabe: die 8 erwarteten Vergleiche mit alten Fassungen und `--haushalt` C (SCHRITT1.md,
   Tabelle zu `simtest_alle`; die Anpassung der Tests ist Schritt 4).
3. `autos.txt`: „Abschnitt „Autos“ (432 Zeilen)“ → „(433 Zeilen)“. Der Test zählt die Zeilen des Abschnitts (Zeile 3853–4285); darin liegt
   `hhHatAuto`, dessen Schleife jetzt zwei statt einer Zeile hat. Die Prüfung selbst (Zufall nur aus dem eigenen Strom) ist grün wie vorher.
4. `kipolicy_datei_…txt`: nur der Pfad der Policy-Datei (Sicherungsordner statt Baukopie).

Dauer der Läufe als Nebenwirkung: `--autos` 528 s → 123 s, `--sicherheit` 239 → 48 s, alle 22 zusammen etwa 20 → 5,5 Minuten.

## 7. Gate T im Wechsel mit Sicherung und Basis (Einzelheiten)

`opt_gate_t.sh 8` (`mess/optimieren/gate_t/`, Auswertung `auswertung.txt`), je Runde `simtest --gate --seeds 1` für neu, sich und basis in
wechselnder Reihenfolge, CPU per `process.cpuUsage` beim Beenden (`opt_cpu_hook.mjs`), dazu je Runde `opt_zeit.mjs` (genau die 365 Tage, Wand
und CPU). Vor allen 24 simtest-Läufen: kein fremder Rechenprozess; Last (1 min) 1,15–1,96, das sind die gemessenen Prozesse selbst.

- T je Runde neu: 1.491, 1.449, 1.440, 1.413, 1.600, 1.785, 1.589, 1.420 ms.
- T je Runde sich: 5.850, 5.321, 5.659, 5.589, 6.086, 5.742, 5.536, 5.622 ms. basis: 4.281, 4.448, 4.445, 4.958, 4.442, 4.523, 4.321, 4.839 ms.
- opt_zeit (365 Tage): neu Median 1.458,5 ms Wand, 3.676 ms CPU; sich 5.727,5 ms Wand, 8.788,5 ms CPU → Wand 0,255, **CPU 0,418**. Die CPU
  sinkt weniger als die Wandzeit, weil die Arbeit neben der Hauptschleife weniger stark sinkt: CPU minus Wandzeit neu 2.218 ms, sich 3.061 ms
  (Vermutung: vor allem V8-Übersetzer und GC in Hintergrund-Threads). Gate T misst die Wandzeit der Hauptschleife.

## 8. Offen, nicht geprüft, Hinweise

- **Browser-Tests (`tests/alle.sh`) nicht gelaufen:** Für diese Phase ist kein Port angegeben. Geprüft ist der sim-Block als gewöhnliches Skript
  im Hauptkontext (`opt_zeit.mjs … direkt`, wie im Browser ohne vm): gleicher Fingerabdruck. Das Modul-Skript ist unverändert und nimmt den
  Rückgabewert von `importZustand`. Vor dem nächsten Browserlauf sollte `tests/alle.sh` einmal laufen.
- Nur in Werkzeugen, die in einem Prozess erst eine frische und dann eine geladene Stadt rechnen (`opt_ladezeit.mjs`), ist die geladene etwa
  26 % langsamer (Vermutung: V8 sieht dann zwei Formen derselben Objekte). Eine nur geladene Stadt ist so schnell wie eine frische (3.4). Für Gate T
  ohne Belang.
- Weiterer Gewinn wäre nur mit Umbauten zu haben (z. B. Werte, die sich nur täglich ändern, in `stunde`/`entscheide` zwischenspeichern). Das habe
  ich nicht gemacht: Das Ziel ist mit Abstand erreicht, das Profil ist flach, und jeder solche Zwischenspeicher braucht eine eigene Regel, wann er
  ungültig wird (Risiko für die Bitgleichheit ohne messbaren Nutzen für Gate T).
- Für spätere Phasen (Entscheidung 7): Gate T im Wechsel mit der Basis weiter messen, wenn sie den sim-Block ändern; die Werkzeuge dafür sind
  `opt_gate_t.sh <runden> <ABSOLUTER Ausgabeordner>` und `opt_ab.mjs`. Neue Schleifen in heißen Funktionen besser mit Index, neue Felder von
  S.p/S.g nur über PF/GF (dann bleibt `felderObjekt` richtig), neue eingebaute Namen (z. B. `Int8Array`) in die Zeile aus 3.2 aufnehmen –
  `opt_globale_namen.mjs` zeigt, ob noch einer über den Kontext geht.

## 9. Dateien und Werkzeuge

- Endstand `E/stadt/stadt.html` (einzige geänderte Datei der Baukopie; `diff -rq` gegen die Sicherung: nur `stadt.html`). Zwischenstufen
  `E/tmp/opt/stufe1.html` (S1), `stufe2.html` (S2), `versuch4.html` (S3), `stufe4.html` (S4 = Endstand).
- Messungen: `E/mess/optimieren/` – `profil/` (erster Durchgang), `gleich/` (Beweis erster Durchgang), `beweis/` (Beweis Endstand), `stufen/`,
  `fortsetzung/` (Profile nachher, Allokationen, Wörterbuch, globale Namen, Ladezeit, neuePerson), `simtest_alle/sich`, `simtest_alle2/neu`
  und `diff/`, `gate_t/`, `gate_t_fehlstart/`.
- Werkzeuge des ersten Durchgangs: `opt_profil.mjs`, `opt_alloc.mjs`, `opt_zeit.mjs`, `opt_ab.mjs`, `opt_gleich.mjs`, `opt_gate_t.sh`,
  `opt_gate_auswertung.mjs`, `opt_cpu_hook.mjs`, `opt_vergleich_alle.sh`, `opt_vm_zugriff.mjs`, `opt_globale.cjs`, `opt_woerterbuch*.mjs`,
  `opt_schleifen.py`, `opt_stufen.sh`, `opt_ladezeit.mjs`, `opt_micro_zufziel.mjs`. Neu in der Fortsetzung: `opt_stufen_vorarbeit.sh` (Stufen mit
  eingefrorenem S4), `opt_schnell_pruefen.mjs`, `opt_globale_namen.mjs`, `opt_ladezeit2.mjs`.
