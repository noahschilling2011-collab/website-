# Etappe 2: Gedächtnis, Erfahrung und Pläne (Version 10) – Berichte und Messtabellen

Belege für alles, was README und `docs/` über Etappe 2 sagen. Die Berichte sind die Arbeitsberichte der einzelnen Phasen, so wie sie entstanden
sind; nachträglich bereinigt sind nur Pfade (der absolute Pfad des Arbeitsordners heißt `SP`, das Repo `<repo>`; sha256 der Originale in
`quellen.sha256`). Jeder Bericht trennt Gemessenes von Annahmen. Zahlen in späteren Berichten ersetzen frühere, wo sich die Simulation geändert
hat; der Endstand steht in `SCHRITT4.md` (Tests) und für die Wirkung in `VERBLASSEN.md` Teil B.

**Endstand, den diese Belege beschreiben:** `stadt.html` sha256 `ac899293429df032…`, Sim-Hash `386c5ec814feb302`, `VERSION = 10`,
`R.GED = 1`, `R.GED_STAERKE = 1.5`, `R.PLAN_RUECKLAGE = 1`, `R.ERF_HALB = 180`, `R.OPFER_FREI = 1`, `R.HAFT_EROEFFNUNG = 1`.
**Danach** die Korrekturen nach der Schlussprüfung (`FIX.md`): `stadt.html` sha256 `e8dc1bc1894d52f5…`, Sim-Hash `0b5f143bb948bcbb`. Im
sim-Block sind nur `warum` (gibt zusätzlich die Rechnung je Vergleich zurück) und ein Kommentar geändert; die Stadt rechnet Tag für Tag gleich
(`FIX.md` 2), Gates 1–80 und probe8 sind je Seed gleich (`FIX.md` 6). Die Zahlen der Belege gelten darum weiter.
**Zuletzt** der Nachtrag nach der Nachprüfung (`FIX.md` 10, nur Oberfläche): `stadt.html` sha256 `aad98691cb689361…`, Sim-Hash
unverändert `0b5f143bb948bcbb`; aus einer frischen Kopie 23 von 23, 32 von 32 (537), Gates 1–80 je Seed gleich.

## Berichte (Reihenfolge der Arbeit)

| Datei | Inhalt |
|---|---|
| `ENTSCHEIDUNGEN_NOAH.md` | Noahs Entscheidungen 1–10 zu Etappe 2, wie sie festgehalten wurden (verbindlich, auch wo sie von den Empfehlungen abweichen) |
| `VERGLEICH.md` | Vergleich der drei Prototypen (A „Erfahrung zuerst“, B „Pläne zuerst“, C „sparsam“), Empfehlung C mit Teilen aus A und B, Bauplan Schritt 0–5; darin die gemessene `localStorage`-Grenze in Chromium (Abschnitt 1.4) |
| `SCHRITT0.md` | Vorarbeiten: `R.OPFER_FREI` (Vorstand in Haft ist kein Einbruchsopfer), strengere Fallauswahl in `--kita`/`--kitest`, float32-Lücke in `policyPruefen` geschlossen |
| `SCHRITT1.md` | Simulation: Gedächtnis kurz/lang mit Fakt und Verweis, Erfahrung, offene Handlung, Plan, Rücklage (`R.PLAN_RUECKLAGE`, Entscheidungen 2 und 6), letzte Entscheidung, Gegenprobe, Beobachter, `Sim.warum`; Punkt 8, Muster über 20 Seeds, Anlauf, Gate T rot |
| `KALIBRIERUNG.md` | Stärke `R.GED_STAERKE` (Entscheidung 4): Teil A/B (vorab festgelegt, Ergebnis Stufe 1), D/E (nach Entscheidung 8, Ergebnis Stufe 4), F (Entscheidung 9: Stufe 1,5), C (Nachmessung nach dem Sim-Fix), G (Kurzfassung Verblassen) |
| `OPTIMIEREN.md` | Entscheidung 7: Simulation bitgleich schneller (Gate T 5.640,5 → 1.470 ms, Tag für Tag bitgleich bewiesen) |
| `SIM_FIX.md` | Korrekturen nach einer Gegenprüfung: Beobachter-Fehler, Haft ist keine Wechselfolge, `warum` für Kinder und mit Zufallsstand; Zerlegung „nach einer Pleite gründet fast niemand mehr“ |
| `SCHRITT2.md` | Speicherformat 10, `memName` gestrichen (Entscheidung 1), Übernahme aus Version 9, `gedPruefen`, Größe, Policy aus Etappe 1 abgelehnt (Entscheidung 5) |
| `VERBLASSEN.md` | Entscheidung 10: Erfahrung verblasst (`R.ERF_HALB`), Teil A vorab festgelegt, Teil B Ergebnisse (H = 180), Zeitskala „1–2 Jahre“ |
| `SCHRITT3.md` | Oberfläche: Personenkarte „Erfahrung und Plan“, Knopf „Warum?“, Liste „Heute anders entschieden“, Browser-Test `gedaechtnis`, Leistung |
| `SCHRITT4.md` | Tests: `simtest --gedaechtnis`, Vergleichsmodi mit `R.GED = 0`, Browser-Tests auf Version 10; aus einer frischen Kopie 23/23 `simtest_alle`, 32/32 Browser-Tests; Gates Seeds 1–80 mit dem Endstand |
| `FIX.md` | Korrekturen nach der Schlussprüfung (Technik, Texte, Bedienung): „Warum?“ nachrechenbar, Policy-Meldung nach Übernahme, Einordnung der Wirkung, Liste beim Auffrischen, Hilfe am Handy und Texte; Tag für Tag gleich gerechnet, Gate T im Wechsel, frische Kopie |

`E/mess/<pfad>` in den Berichten liegt hier als `mess/<pfad>`, soweit es unten aufgeführt ist. Nicht mitgeliefert sind die großen oder nur
lokal nützlichen Rohdaten (Gate-Ausgaben je Seed, `probe8`-Rohdaten, Bildschirmfotos, Browser-Ausgaben, Sicherungen, die Prototypen und die
Arbeitskopien). Die Messwerkzeuge der Phasen (`E/werkzeug/…`) lagen im Arbeitsordner; die, die die Doku braucht, liegen jetzt in `tools/`
(unten).

## Messtabellen (`mess/`)

| Datei(en) | Was | Bericht |
|---|---|---|
| `simtest_alle_1.txt`, `float32_probe.txt`, `opfer_wirkung_an_s1-20_t730.txt`, `tagvergleich_aus_*.txt` | Vorarbeiten: 22/22 `simtest_alle`, float32-Gegenprobe, Wirkung von `R.OPFER_FREI` (Seeds 1–20), Schalter aus = 6c1741e | SCHRITT0 |
| `anlauf/auswertung.txt` | Messung, nach der Noah Entscheidung 6 traf (Rücklage erst ab der Stufe Stadt) | ENTSCHEIDUNGEN_NOAH, SCHRITT1 0.3 |
| `ruecklage/*.txt` | Standard `R.PLAN_RUECKLAGE = 1`: Anlauf, Muster über 20 Seeds, Punkt 8, Rechenzeit, Gate T, Profil, harte Grenze, Schalter aus | SCHRITT1 |
| `kalibrierung/tabelle_nach_bestaetigung.txt`, `nachkal/tabelle_nach_bestaetigung.txt`, `staerke15/schluss/probe8_auswertung.txt` | Stärke: Tabellen je Stufe (Teil B und E), Schlussmessung Stufe 1,5 (Teil F) | KALIBRIERUNG |
| `optimieren/gate_t/auswertung.txt` | Gate T nach der Optimierung, 8 Runden im Wechsel | OPTIMIEREN |
| `simfix/schluss/*.txt` | Punkt 8 nach dem Sim-Fix, Zerlegung „Wiedergründung nach Pleite“, Gates vorher/nachher | SIM_FIX, KALIBRIERUNG Teil C |
| `schritt2/*` | Größe (Seed 1, große Stadt), Aufholen in Stücken (6c1741e und Version 10), Browser-Test `p10speicher`, Schalter aus, Policy abgelehnt, Namen nach der Übernahme, harte Grenze, Gate T | SCHRITT2 |
| `verblassen/kand/tabelle.txt` | alle Kandidaten H = 180 / 360 / 540 mit N1–N5, Wiedergründung, Wirtschaft | VERBLASSEN B.1–B.4 |
| `verblassen/kand/wieder_{ged0,h0,h180}.json`, `folgen_{aus,h180}.json` | Rohdaten der Wiedergründung (Seeds 1–20 × 1.460 Tage) und der Muster (Seeds 1–20 × 730 Tage) für den Bezug `R.GED = 0`, „ohne Verblassen“ und den Standard | VERBLASSEN B.1, B.3 |
| `verblassen/wieder_fenster.txt`, `verblassen/bestaetigung_h180/auswertung.txt`, `verblassen/schluss/*` | Wiedergründung binnen 365 Tagen, Bestätigung Seeds 81–160, Schlussmessung (Punkt 8 über 730 Tage, Gates Seeds 1–3, Gate T, Schalter aus, harte Grenze, Speichern, Aufholen) | VERBLASSEN B.2, B.4, B.5 |
| `schritt3b/*`, `schritt3c/*` | Fälle der Liste je Tag, Leistung in Node und im Browser, Layout in 12 Lagen, Browser-Tests vorher/nachher, Gate T, harte Grenze, Test `gedaechtnis` auf dem Endstand | SCHRITT3 |
| `schritt4/frisch2/simtest_alle/*`, `schritt4/frisch2/simtest_alle.txt` | `simtest_alle` aus einer frischen Kopie mit dem Endstand: 23 von 23, alle Logs (darin `gedaechtnis.txt`, `gate.txt`, `kipolicy*.txt`, `migrationstest.txt`) | SCHRITT4 §7 |
| `schritt4/frisch/browser.txt`, `schritt4/frisch/browser/logs/*.log` | `tests/alle.sh` aus einer frischen Kopie: 32 von 32, „ALLES GRÜN“; Logs von `gedaechtnis`, `p6migration`, `browser_ki`, `p10speicher`, `basis` | SCHRITT4 §6 |
| `schritt4/gates_1_80/*` | Gates Seeds 1–80 mit dem Endstand (Tabelle je Seed) und Wirtschaft gepaart gegen `R.GED = 0` | SCHRITT4 §8 |
| `schritt4/okzahlen_vergleich.txt`, `schritt4/gegenprobe_pfged.txt` | Zahl der Prüfungen je simtest-Modus wie in Schritt 0; Gegenprobe, dass die Ausnahme `PF_GED` nichts verdeckt | SCHRITT4 §2 |
| `schritt5/*` | Schritt 5 (Doku): Prüfung der nach `tools/` übernommenen Werkzeuge und eine Auswertung gespeicherter Rohdaten (unten) | dieses Blatt |
| `fix/gleich_*.txt`, `fix/warum_leser_vorher.txt`, `fix/gegenprobe_*.txt`, `fix/diff_stadt_html.txt` | Tag für Tag gleich und „Warum?“ nachrechenbar (vorher/nachher, mit Gegenproben), Diff von `stadt.html` | FIX 1–2 |
| `fix/gate_t*/wechsel.txt`, `fix/ab_zeit.txt` | Gate T im Wechsel (neu, vorher, Basis), A/B-Zeitmessung | FIX 3 |
| `fix/frisch/*`, `fix/gates_1_80/*`, `fix/probe8.txt` | aus einer frischen Kopie: `simtest_alle` (alle Logs), `tests/alle.sh` (Übersicht und Logs von `gedaechtnis`, `p10speicher`, `p6migration`, `browser_ki`, `basis`), Gates Seeds 1–80 je Seed gegen Schritt 4, probe8 | FIX 6 |
| `fix/nachtrag/*` | Nachtrag (`FIX.md` 10): aus einer frischen Kopie `simtest_alle` (alle Logs), Gates 1–80, `tests/alle.sh` (Übersicht, sechs Logs), Gate T im Wechsel | FIX 10 |

## Werkzeuge in `tools/` (aus den Messwerkzeugen der Etappe 2 übernommen)

| Werkzeug | Herkunft | Geprüft (Schritt 5, 01.10.2026) |
|---|---|---|
| `tools/gate_auswertung.mjs` | `gate_auswertung.mjs` mit dem Leser aus `kal_lese.mjs` (Gate 7 nach Entscheidung 8) | 21 Vergleiche auf 7 gespeicherten Gate-Sätzen (alte und neue Schreibweise von Gate 7, je mit `--tabelle`, `--g7min 0` und ohne): Ausgabe gleich dem alten Werkzeug; für `mess/schritt4/gates_1_80` Byte für Byte gleich `auswertung.txt` (`mess/schritt5/gate_auswertung_vergleich.txt`) |
| `tools/wiedergruendung.mjs`, `tools/wiedergruendung_auswertung.mjs` | `vb_wieder.mjs`, `vb_wieder_auswertung.mjs`; neu `--setze NAME=wert` statt einer Arbeitskopie je Variante | Mit dem Endstand neu gerechnet (Seeds 1–20 × 1.460 Tage): Standard, `--setze GED=0` und `--setze ERF_HALB=0` geben je Seed dieselben Personen, Gründungen und Stände wie die gespeicherten `wieder_h180.json`, `wieder_ged0.json`, `wieder_h0.json`, 3 × 20 von 20 (`mess/schritt5/wieder/lauf.txt`, je etwa 85 s) |
| `tools/gate_t_wechsel.sh` | `gate_wechsel1.sh`; die Basis kommt jetzt per `git archive` aus der Git-Geschichte statt aus einer Kopie | 2 Runden allein: läuft, Basis 6c1741e mit sha256 `0b453bf1…` (`mess/schritt5/gate_t_probe/wechsel.txt`; nur eine Probe des Werkzeugs, keine Gate-T-Messung mit 4 Runden) |

Dazu in Schritt 5:

- `mess/schritt5/folgen_aus_h180.txt`: `folgen_auswertung.mjs` auf den gespeicherten `verblassen/kand/folgen_{aus,h180}.json` (Kündigungen
  nach Art, Wiedergründung binnen 730 Tagen, Charakterabstände, Wirtschaft über 20 Seeds); nur ausgewertet, nichts neu gerechnet. Das
  Werkzeug selbst ist nicht übernommen.
- `mess/schritt5/groesse_gross_endstand.jsonl`, `mess/schritt5/grosse_stadt.txt`: Größe des Spielstands (Seed 1 Tag 365, große Stadt Tag 750)
  und Einwohner und Karte der großen Stadt mit dem Endstand, in Node neu gerechnet (das Größen-Werkzeug ist das aus Schritt 2). Die große
  Stadt hat 7.159 Einwohner und 4.277.378 Zeichen; der Browser-Test `p10speicher` aus Schritt 4 maß dieselbe Stadt mit 4.277.380 Zeichen
  (2 mehr, wie in Schritt 2 zwischen Node und Browser). Die 4.190.777 Zeichen in `SCHRITT2.md` gelten für den Stand vor dem Verblassen.
- `mess/schritt5/ki_v9_ablehnung.txt`: `tools/ki_liste.mjs --nur-pruefen` und `tools/ki_fallen.mjs --policy ki/policy_v9_lokal_1.json` lehnen
  die Policy aus Etappe 1 ab.
- `mess/schritt5/gitignore_pruefung.txt`: `.gitignore` geprüft wie in Etappe 1 (`git init` in einer Kopie mit der Wurzel-`.gitignore` des
  Repos, `git add -A --dry-run`): Alle Dateien dieses Ordners kommen mit, auch die Logs (dafür die Ausnahme `!berichte/**/*.log` in
  `stadt/.gitignore`, sonst fielen 7 Belege unter `*.log`); 12 künstliche Dateien (Läufe, Smoke-Berichte, Ausgaben, Bilder, Logs außerhalb
  von `berichte/`, `stadt.orig.html`, `*.zip`, `*.npz`, `__pycache__`) bleiben draußen; über 1 MB nur `stadt.html`.

Nachrechnen im Ordner `stadt/` einer Git-Kopie (außerhalb: `simtest --gedaechtnis --git <repo>`, `STADT_GIT=<repo> bash tools/gate_t_wechsel.sh`):

```bash
node tools/simtest.mjs --gedaechtnis                    # Punkt 8 (Seeds 1–3, 365 Tage), Schalter aus = 6c1741e, Migration, Grenzen; etwa 45 s
node tools/wiedergruendung_auswertung.mjs ged0=berichte/etappe2/mess/verblassen/kand/wieder_ged0.json \
  h0=berichte/etappe2/mess/verblassen/kand/wieder_h0.json h180=berichte/etappe2/mess/verblassen/kand/wieder_h180.json
node tools/wiedergruendung.mjs --seeds 1-20 --tage 1460 > /tmp/wieder_h180.json        # neu rechnen, etwa 1,5 min
node tools/simtest.mjs --gate --seeds $(seq -s, 1 2 79) > /tmp/g_u.txt &                 # Gates Seeds 1–80 in 2 Prozessen
node tools/simtest.mjs --gate --seeds $(seq -s, 2 2 80) > /tmp/g_g.txt; wait
node tools/gate_auswertung.mjs /tmp/g_u.txt /tmp/g_g.txt --tabelle
bash tools/gate_t_wechsel.sh 4 1                        # Gate T im Wechsel mit 6c1741e, nur allein laufen lassen
```
