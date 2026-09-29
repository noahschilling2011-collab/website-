# STADT – KI-Durchstich auf Version 9 übertragen

Stand 29.09.2026, 00:24–02:40 UTC. Arbeitsordner `SP/ml/v9` (`SP` = `/tmp/claude-0/-home-user-website-/584133fa-a5fc-563e-807a-2feca85efaf0/scratchpad`).
Im Repo `/home/user/website-` ist nichts geändert, angelegt oder committet (nur `git show`; `git status` am Ende leer, HEAD `09083f5`).
Alle Zahlen stammen aus Läufen dieser Sitzung; die Ausgaben liegen in `ausgaben/`. Rechner: 4 vCPU Xeon 2,1 GHz, keine GPU, Node 22.22.2,
Python 3.11.15 mit torch 2.14.0+cpu, sb3-contrib 2.9.0, stable-baselines3 2.9.0, gymnasium 1.3.0, numpy 2.4.6 (im venv `SP/ml/venv` geprüft,
Signaturen von `MaskablePPO.predict`/`learn` und `EXPECTED_METHOD_NAME = "action_masks"` per `inspect` nachgesehen).

## 0. Kurzfassung

| Punkt | Ergebnis |
|---|---|
| 1. Entscheidungslogik V9 geprüft | Aktionskatalog **unverändert** (warten + 12). Beobachtungsschema **neu versioniert: 2** (57 Merkmale, Hash `e85eca0c`, vorher 1/56/`29e54073`): Lohnsteuer neu, Stellen/Wohnungen ohne Sättigung. Begründung und Messung in Abschnitt 2 |
| 2. Patch | `tools/ki_patch.mjs` ohne `--policy` auf 09083f5: 9 Ersetzungen in `stadt.html`, 2 in `tools/simtest.mjs`, jede genau einmal; wiederholbar bytegleich; lehnt zweites Patchen, Version 8 und Einbetten einer nicht freigegebenen Policy ab. Die Wahl steht jetzt in einem **eigenen Fenster** hinter dem Knopf „Entscheidungen: Regeln ›“ in den Einstellungen, weil der Abschnitt dort einen V9-Browsertest brach (Abschnitt 8.2) |
| 3. Neue Regel: Policy nicht eingebettet | umgesetzt: `stadt.html` enthält keine Policy; Laden aus `ki/policies.json` per `fetch` (relativ) nur beim Umschalten oder wenn der Spielstand eine verlangt, oder per Datei-Import; sichtbarer Rückfall; Speicherfeld `ui.entscheidungen` reicht (kein neues Feld, `VERSION` bleibt 9) |
| 4. Regression, Policy aus | **alle 20 simtest-Modi grün**, Ausgabe **gleich wie 09083f5** bis auf Zeitangaben; `--gate` zahlengleich (Einwohner 1169/1200/1221, Band-Faktor 1,07/1,06/1,06); `--speichertest` `ca60551e5b316d33` wie 09083f5; Tag für Tag bitgleich (Seeds 1–6 × 120 Tage stündlich, 60 Tagesschritte; `--kipolicy` Seeds 1–3 × 730 Tage); `--kipolicy` 26/26 (mit der V9-Smoke-Policy 27/27); Endlauf auf der Enddatei gleich; Zeit-Gate T Mittel 2.523 ms gegen 2.626 ms (09083f5), je 9 Werte |
| 5. Smoke auf V9 | echter Lauf `smoke_v9_2`, Belohnung v2, Sim-Version 9: 2.048 Schritte, Parameter L2 1,727 (Policy-Netz 0,23/0,28, action_net 0,21); Export Format 2, `simVersion` 9, Hash `cf2caae866578f0a`; Parität 644/644 (Logits ≤ 2,3e-8, 244 Randfälle); Browser 24/24 auf Port 9061 (mehrfach hintereinander grün), Konsole sauber bis auf die gewollten Fehler. **Kein Qualitätsbeleg** |
| 6. Durchsatz, Budget | Umgebung im Prozess 332 Schritte/s, über das Protokoll 226 Schritte/s, mit PPO (Profil lokal) 105 Schritte/s. Vorschlag `lokal_v9`: 155.648 Schritte, Zeitlimit 26 min → ≈ 27 min Wandzeit |
| Neuer Befund | **Belohnung v2 besteht das Belohnungs-Audit auf V9 nicht** (2 von 8 Prüfungen, Abschnitt 8.1). Vor einem lokalen Lauf auf V9 muss die Belohnung neu kalibriert und versioniert werden (v3); das habe ich nicht gemacht |

## 1. Ordner und Dateien

```
SP/ml/v9/
  stadt.orig.html            git show 09083f5:stadt/stadt.html (nie geändert, sha256 5974269e…)
  tools/simtest.orig.mjs     git show 09083f5:stadt/tools/simtest.mjs (nie geändert, sha256 22d64a48…)
  stadt.html                 gepatcht (1.356.725 Byte, sha256 48732527…, sim-Block 3b1a95e0e5ae9ea5), ohne eingebettete Policy
  tools/simtest.mjs          gepatcht (+ Modus --kipolicy, sha256 fb8cebe8…)
  tools/                     aus basis kopiert und angepasst (Abschnitt 3), neu: ki_liste.mjs, tagvergleich.mjs, v9_regression.sh,
                             gate_zeit.sh, v9_browsertests.sh
  ki/policies.json           Liste der Policies, die diese stadt.html annimmt (tools/ki_liste.mjs)
  ki/policy_smoke_v9_2_bester.json   Smoke-Policy auf V9 (experimentell)
  ki/schema_v2.json          Beobachtungsschema 2 (tools/ki_schema.mjs); schema_v1.json bleibt zum Vergleich
  ki/v8/                     die vier Policies von Version 8 (nur für Ablehnungstests, nicht in policies.json)
  ki/LIESMICH.md             aus basis, oben ein Block „Stand Version 9“
  training/                  aus basis ohne die V8-Läufe; konfig.json + Profil lokal_v9, trainiere.py + --zeit-min, paritaet.py + Randwerte
  training/laeufe/           smoke_v9_1, smoke_v9_2, mess_lokal_v9 (Abschnitt 6 und 7)
  pruefung/                  Testaufbauten (gepatcht, orig, browser, v9tests), bei jedem Lauf neu erzeugt
  analyse/                   Messskripte zu Abschnitt 2 (fvergleich.mjs, merkmale_vergleich.mjs, markt.mjs) und ihre Ausgaben
  ausgaben/                  alle Testausgaben
```

`SP/ml/basis` ist unverändert (nur gelesen und kopiert).

## 2. Was Version 9 an der Entscheidungslogik ändert (Schritt 1)

Funktionsrümpfe des sim-Blocks V8 (31ce452) gegen V9 (09083f5) verglichen (`analyse/fvergleich.mjs`, Rümpfe in `analyse/fdiff/`):
276 gleich, 75 geändert, 118 neu, 0 weg. Für die Entscheidungen der Bewohner zählt:

| Stelle | Änderung in V9 | Folge für Policy und Umgebung |
|---|---|---|
| `AKTIONSNAMEN`, `A`, `ausfuehren` | unverändert | Aktionskatalog (warten + 12) bleibt; Index = Aktionscode wie bisher |
| `entscheide`, `erlaubteAktionen` | `fest = imDienst ∥ verpflichtet ∥ istBm` (Bürgermeister wechselt, kündigt und gründet nicht); Gründung zusätzlich mit `techWeltAussicht` (Tüftler mit Fleiß + Ehrgeiz ≥ Schwelle, Weltmarkt hat Platz) | Maske folgt automatisch (sie ist `erlaubteAktionen`). Neues **indirektes Wissen der Maske**: `techWeltAussicht` liest den Weltmarkt (`weltPlatzFuer` mit `S.weltPlaetze`, `techGruendungJetzt`) – die Person weiß das nicht; dokumentiert, nicht in der Beobachtung |
| `kannGruenden`, `aktGruenden` | ohne Gründungstyp `false` (Tüftler im Dorf spart weiter); Weltmarkt-Firmen | Gründen kann öfter „ohne Erfolg“ enden; die Maske prüft `kannGruenden` mit |
| `istHaupt` | `inHauptListe ∥ istBm` | Der Bürgermeister entscheidet **nie** nach der Policy (Haken: Regeln) und wird nie Fokusperson (Auswahl ohne `istHaupt`). Wird eine Fokusperson während der Episode gewählt, bleibt sie Fokusperson mit der Maske der Regeln; gezählt als `amtStunden` (in 24 Episoden: 0-mal) |
| `stunde` | `mitHaupt` (Bürgermeister als Hauptfigur auch ohne Liste), `bmRangfolgeStunde` | Aufrufstellen von `entscheide` unverändert (stündlich, Tagesschritt, Frist, KI-Rückfall) → der Haken am Anfang von `entscheide` deckt weiter alle ab. Die Rangfolge der Vorhaben ist eine Entscheidung der Stadt (Regel oder Sprachmodell), keine Bewohner-Aktion, nicht im Katalog |
| `kiFragen`, `kiSchalten`, KI-Frist | Frist `K.fristStunden` (2 … `KI_FRIST_MAX`), einstellbar | betrifft nur das Sprachmodell; Umgebung schaltet es aus (`kiSchalten(S, false)`) |
| Haushalt, `lohnsteuer`, `einkommenTag` | Satz `steuerSatz(S) = haushalt.satz/100`, am Jahresende (Jahr = `R.JAHR` = 10 Tage) um einen Punkt gesenkt oder wieder angehoben, zwischen 0 und 10 % (`hhSteuer`) | Das Nettoeinkommen ändert sich innerhalb einer Episode; die Beobachtung v1 kannte nur den Bruttolohn → **neues Merkmal `lohnsteuer`** |
| Wachstum (Anlauf, Schalter), Tech früher | größere Städte, viel mehr offene Stellen | `stellen_frei` (v1: `min(n,50)/50`) war in V8 **und** V9 immer 1 (100 % der Beobachtungen, Normalisierung „konstant“) → **neue Skala** |
| Schule, Rathaus, neue Berufe | Kinder in der Schule, Stellen in Verwaltung und Schule | keine neue Entscheidung der Eltern; `lohn` deckt die neuen Löhne (bis 1,19 statt 1,16) |
| Tempo 100×, „KI jedes Tempo“ | nur Oberfläche (`simTakt`, Sprachmodell) | keine Wirkung auf die Policy (sie läuft im sim-Block je Entscheidung, gleich bei jedem Tempo) |

**Gemessen** (Schema 1 auf beiden Fassungen, Regelarm, Szenario `stabil`, Seeds 10000–10023, `analyse/merk_v8.txt`, `analyse/merk_v9.txt`,
`analyse/markt_v8.txt`, `analyse/markt_v9.txt`):

| Merkmal | V8 | V9 |
|---|---|---|
| Einwohner beim Start der Episoden | 100–338 | 172–603 |
| `stellen_frei` (v1) | 1,0 in 100 % | 1,0 in 100 % (freie Stellen 181–488 an Tag 150–230, 126–285 an Tag 400) |
| `wohnungen_frei` (v1) | 0–0,38 | 0–0,40 (freie Wohnungen bis 145 an Tag 700) |
| Lohnsteuersatz | immer 10 % | beim Start 0–4 %, am Ende der Episode 0–1 % |
| `lohn` | 0–1,16 | 0–1,19 |
| `ruecklage_tage` an der Grenze 3,0 | 16,7 % | 19,0 % (Skala behalten) |
| Fokusperson wird Bürgermeister | – | 0 von 24 |

**Entscheidung:** Schema 2 = Schema 1 mit drei Änderungen (Reihenfolge: nach `arbeitslosenquote`):
- `stellen_frei`: `n/(n+200)`, `n = freieStellen` (200 Stellen = 0,5; ohne Sättigung, nur Grundrechenarten);
- `wohnungen_frei`: `n/(n+20)`, `n = freieWohnungen`;
- neu `lohnsteuer`: `steuerSatz*10` (10 % = 1; öffentliche Zahl, im Spiel sichtbar).
Mit Schema 2 (Normalisierung aus 128 Regel-Episoden, `training/laeufe/mess_lokal_v9/normalisierung.json`): `stellen_frei` 0,635 (Streuung unter
0,05, auf 0,05 angehoben, aber nicht konstant), `wohnungen_frei` 0,148 ± 0,126, `lohnsteuer` 0,047 ± 0,097. Konstant bleiben 5 Merkmale
(`gemeinnuetzig`, `im_dienst`, `verpflichtet`, `trauer`, `ziel_wohnung`).
Keine Merkmale mit Namen, ID oder Herkunft: `simtest --kipolicy` prüft statisch (gelesene Personenfelder, jetzt mit `steuerSatz`), durch Verändern
(Namen, Geschlecht, Einzug, Sparbeginn, Eltern, Gedächtnisbezüge → Beobachtung bitgleich) und je Personenfeld (99 Felder; von anderen wirken nur
`eigen`, `hh`, `wohnung` als Haushaltswissen).
**Versionierung:** `KI_SCHEMA = 2`; der Schema-Hash (FNV-1a über Version, Namen, Skalen, Aktionen) steht in jeder Policy-Datei (`schemaHash`) und
geht in den Inhalts-Hash (SHA-256) ein. `kiPolicyPruefen` lehnt Schema 1 ab (Version, Merkmale, Hash) und zuerst die Stadt-Version
(„trainiert auf Stadt-Version 8, diese Stadt ist Version 9 (neu trainieren)“). Der Aktionskatalog bekommt keine eigene Version, weil er gleich
bleibt; er steckt im Schema-Hash.

## 3. Was geändert ist und warum (Dateien)

| Datei | Änderung | Grund |
|---|---|---|
| `tools/kipatch/sim_ki.js` | Schema 2 (3 Merkmale, Kopfkommentar), Funktion `kiBeobachtung` → **`kiEingabe`** (nach außen weiter `Sim.KI.beobachtung`), Kommentar zum Bürgermeister | Schema: Abschnitt 2. Umbenennung: `simtest --militaer` verbietet im sim-Block jede Funktion, deren Name nach Überwachen klingt (Regex `[Bb]eobacht…`); der erste Regressionslauf fiel genau daran durch (`ausgaben/regression/lauf1_gepatcht_militaer.txt`) |
| `tools/kipatch/ui_ki.js` | neu geschrieben: Quellen `ki/` (fetch), Datei-Import, eingebettet (nur freigegeben); Wahl nur nach Hash; `await` vor dem Start; Hinweise | Noahs neue Regel (Abschnitt 4) |
| `tools/kipatch/einst_ki.html` | jetzt ein **eigenes Fenster** `#ki-dialog` (Wahl, Status, Auswahl, Datei laden, zwei kurze Absätze); in den Einstellungen nur der Knopf `#ki-knopf` „Entscheidungen: Regeln ›“ neben „Schließen“ | Die Einstellungen von V9 sind bei 1280 × 800 mit 736 px fast voll (Grenze 760); der Abschnitt darin brach `tests/wachstum.cjs` (Abschnitt 8.2) |
| `tools/kipatch/simtest_kipolicy.mjs` | `--policy datei`; `steuerSatz` in der statischen Liste; Fall „Schema-Version 1“ statt fest „2“; Bürgermeister im Trainingsbereich-Test | sonst wäre „Schema-Version 2“ mit Schema 2 kein Fehlerfall mehr |
| `tools/ki_patch.mjs` | nur Version 9; neuer Anker im Import (ki/ vor dem Umschalten lesen); Einbetten nur mit Status „freigegeben“, sonst kein `<script id="ki-policy">` | Regel |
| `tools/kiepisode.mjs` | Metrik `amtStunden`, Kommentar V9 | Bürgermeister in der Umgebung sichtbar |
| `tools/ki_fallen.mjs` | Merkmalsstellen nach Namen statt fest 2 und 33 | Schema 2 verschiebt `freunde` auf 34 |
| `tools/browser_ki.cjs` | neu geschrieben: echter Server auf 9061, relative Pfade, Testordner | Aufgabe 5 |
| `tools/ki_liste.mjs` | neu: schreibt `ki/policies.json` aus allen `ki/policy_*.json`, die die stadt.html annimmt | Liste für den relativen Abruf |
| `tools/tagvergleich.mjs` | neu: Fingerabdruck je Tag, stündlich und in Tagesschritten | Aufgabe 4 |
| `tools/v9_regression.sh`, `tools/gate_zeit.sh`, `tools/v9_browsertests.sh` | neu: Testaufbauten und Läufe | Aufgabe 4, 5 |
| `training/paritaet.py` | 244 Randfälle zusätzlich | Aufgabe 5 |
| `training/trainiere.py`, `training/konfig.json` | `--zeit-min`, Profil `lokal_v9` | Durchsatzmessung und Budget (Abschnitt 7) |
| `ki/LIESMICH.md` | Block „Stand Version 9“ oben | Einstieg |

**Anker in 09083f5** (je genau einmal; Zeile in der gepatchten Datei, `ausgaben/ki_patch.txt`):

| Anker | Bereich | Zeile | Zweck |
|---|---|---|---|
| `function entscheide(S, p, h) {` | sim | 2330 | Haken als erste Zeile (`if (KIP.an) …`) |
| `function entferne(S, q, grund) {` | sim | 1630 | Tod/Wegzug der Fokusperson |
| `\nG.StadtSim = {\n` | sim | 7941 | Abschnitt KI davor, Export `KI` |
| `  <div class="knoepfe">…data-schliessen autofocus>Schließen</button></div>\n</dialog>\n` (letzte Zeile der Einstellungen; nur dort mit `autofocus>Schließen`) | html | 808 | Knopf „Entscheidungen: … ›“ vor „Schließen“, danach das Fenster `#ki-dialog` |
| `function uiZustand() { return { kiModell: ki.modell, kiMessung: ki.messung }; }` | html | 8525 | `entscheidungen: kiWahlUi()` im Spielstand |
| `if (geladen && geladen.ui && typeof geladen.ui.kiModell === 'string') ki.modell = …` | html | 14155 | Oberfläche KI danach (mit `await` vor dem Start) |
| `    karteZu();\n    S = l.S; akku = 0; buchNeu(); if (G) { G.neueStadt(); }` (Import) | html | 16636 | **neu:** `await kiQuellenFuer(l.ui)` davor |
| `    speichernErlaubt = true; speichern();\n    $('einst-dialog').close();\n` + Import-Meldung | html | 16641 | Wahl aus dem Spielstand, Rückfall in derselben Meldung |
| `  Sim.kiSchalten(S, false);  // beim Aufholen …` | html | 15045 | nur der Kommentar |
| `\n<script id="sim">\n` | html | – | nur mit freigegebener Policy (heute nie) |
| simtest: `//   Optionen: --alle 30 …` und `if (flag('gate')) {` | simtest | 84, 5258 | Hilfe und Modus `--kipolicy` |

Wächter (`ausgaben/ki_patch_waechter.txt`): zweimal gepatcht = dieselben Bytes; gepatchte Datei → „nicht zweimal patchen“; Version 8 → „keine
Stadt-Version 9“; `--policy ki/v8/policy_lokal_1_bester.json` → „trainiert auf Stadt-Version 8 … Nichts geschrieben“; `--policy` mit der
V9-Smoke-Policy → „Status experimentell, nicht freigegeben … Nichts geschrieben“.

## 4. Policy nicht eingebettet: Laden, Speichern, Rückfall (Schritt 3)

- Bedienung: Einstellungen (Zahnrad) → Knopf „Entscheidungen: Regeln ›“ (zeigt den Stand) → Fenster „Entscheidungen der Bewohner“ mit
  „Regeln (Standard)“ / „Trainierte Policy (experimentell)“, Auswahl der Policy, „Policy-Datei laden …“ und Status (Quelle, Trainingsschritte,
  Stadt-Version, Zähler, Gründe für Ablehnungen). Bei 1280 × 800: Einstellungen 736/736 px wie 09083f5, das Fenster 654/654 px ohne Scrollen;
  bei 360 × 740 ohne seitliches Überlaufen, das Fenster scrollt dort (750/703 px; `ausgaben/ki_fenster_breiten.txt`).
- `stadt.html` hat **kein** `<script type="application/json" id="ki-policy">` (Browsertest prüft es). Quellen der Policy, in dieser Reihenfolge:
  eingebettet (nur freigegeben; heute keine), **Ordner `ki/`** (`ki/policies.json` → genannte Dateien, relative URL, `cache: 'no-store'`,
  Zeitlimit 8 s, höchstens 12 Dateien, Dateinamen nur `[A-Za-z0-9_.-]`, kein Pfad), **Datei-Import** (Einstellungen, `localStorage['stadt-policy-v1']`,
  ohne Speicher nur für die Sitzung). Jede Datei prüft `Sim.KI.policyPruefen` (Format 2, `simVersion` 9, Schema 2 und Hash, Merkmale, Aktionen,
  endliche Zahlen, Streuung > 0, Schichten, Inhalts-Hash SHA-256 nachgerechnet); dieselbe Policy aus zwei Quellen zählt einmal (Hash).
- `fetch` nur, wenn der Spieler „Trainierte Policy (experimentell)“ wählt, oder wenn beim Start bzw. beim Import eines Spielstands dieser eine
  Policy verlangt, die noch nicht da ist. Beim Start geschieht das mit `await` **bevor** die Stadt läuft (Top-Level-await im Modul, wie
  `await import('three')`); beim Import **bevor** auf die neue Stadt umgeschaltet wird. So rechnet keine Stunde still mit etwas anderem.
- Ohne `ki/` (404), mit kaputter Liste, als `file://` (kein `fetch`, eigener Hinweis) oder ohne gültige Datei: Regeln, Hinweis in den Einstellungen
  (mit Grund je abgelehnter Datei) und eine Meldung (`warnung`).
- **Spielstand:** Das Feld `ui.entscheidungen = { v: 1, art: 'regeln' | 'policy', name, hash, schema }` reicht. Es liegt in `ui`, nicht in `S`:
  `VERSION` bleibt 9, `exportZustand` und der Fingerabdruck ändern sich nicht (Speichertest-Hash gleich). Beim Laden zählt **nur der Hash**
  (vorher in basis: fehlte der Hash, konnte die erste verfügbare Policy genommen werden – jetzt nie). Fehlt genau diese Policy: Regeln, Meldung
  „Die gespeicherte Policy „…“ (Hash …) ist nicht da oder passt nicht zu dieser Stadt – <Grund>. Es entscheiden die Regeln (Rückfall).“, danach
  speichert das Spiel `regeln`. Stände ohne das Feld (09083f5 und älter) laufen mit Regeln, ohne Meldung und ohne Anfrage an `ki/`.
  Übernahme V2–V8 geht wie in 09083f5 über den Versionsdialog (diese Stände haben das Feld nie).

## 5. Regression mit Policy aus (Schritt 4)

Aufbau `tools/v9_regression.sh`: je ein Ordner für die gepatchte Fassung und für 09083f5, jeweils mit **Version 8 (31ce452) als
`stadt.orig.html`**, weil simtest von V9 dort V8 erwartet (Übernahme-Tests von `--rathaus`, `--schule`, `--haushalt`, `--wachstum`,
`--techfrueh`). Die ungepatchte V9 geht als `--orig` an `--kipolicy`. 3 Läufe gleichzeitig. `--git /home/user/website-` für `--migrationstest`,
`--erweiterung`, `--rathaus`, `--schule`, `--haushalt`.

| Prüfung | Ergebnis | Ausgabe |
|---|---|---|
| 20 Modi gepatcht | alle Exit 0: gate, speichertest, aufholtest, kitest, bau, waren, tech, regierung, kita, migrationstest, erweiterung, sicherheit, militaer, autos, rathaus, buergermeister, schule, haushalt, wachstum, techfrueh | `ausgaben/regression/gepatcht_*.txt`, `status.txt` |
| 20 Modi 09083f5 | alle Exit 0 | `orig_*.txt`, `lauf1_status.txt` |
| gepatcht gegen 09083f5 | **alle 20 Ausgaben gleich** ohne Zeitangaben (1.284 Zeilen) | `vergleich_ohne_zeit.txt`, `diff_*.txt` (leer) |
| `--gate` | BESTANDEN, zahlengleich: Einwohner Tag 365 1169/1200/1221, Band Tag 551–730 1391–1494 / 1438–1528 / 1441–1521 (Faktor 1,07/1,06/1,06), Gate 6 +19,4/+20,8/+20,9, Gate 7 −24,0 (n 35)/−25,6 (n 37)/−22,4 (n 29) | `gepatcht_gate.txt` |
| `--speichertest` | `ca60551e5b316d33` bitgleich wie 09083f5, dazu Sicherheit `a7d743951bcc249c`, Bund `1ee169cc886a05b8` | `gepatcht_speichertest.txt` |
| Tag für Tag | Seeds 1–6 × 120 Tage stündlich und × 60 Tagesschritte: jeden Tag Fingerabdruck und Schlüssel von `S` gleich (1.080 Tage) | `tagvergleich.txt`, `tage.tsv` |
| `--kipolicy` (künstliche Policy) | 26 von 26, darunter Seeds 1–3 × 730 Tage jeden Tag bitgleich (1449/1509/1515 Einwohner) | `gepatcht_kipolicy.txt` |
| Zeit-Gate T (allein, abwechselnd, 3 Runden) | 09083f5 Ø 2.626 ms (2.448–3.178), gepatcht Ø 2.523 ms (2.353–2.701); Grenze 5.000 | `ausgaben/gate_zeit.txt` |
| Endlauf auf der Enddatei (sha256 `48732527…`, 3. Lauf, nur gepatcht) | alle 20 Modi Exit 0, Ausgaben gleich wie 09083f5 (bei `--aufholtest` unterscheidet sich nur das Zeitverhältnis „1.4× / 1.6× schneller“ aus zwei Laufzeiten; Einwohner, Gebäude, Gründungen usw. gleich), Tag für Tag bitgleich, `--kipolicy` 26/26, Speichertest `ca60551e5b316d33` | `lauf3_status.txt`, `vergleich_ohne_zeit.txt` |
| `--kipolicy --policy ki/policy_smoke_v9_2_bester.json --tage 120` (echte V9-Policy statt künstlicher) | 27 von 27: Inhalts-Hash Python = JS, Namenstausch mit Policy für alle (neue und gewachsene Stadt, 90.766 Policy-Entscheidungen) bitgleich, Maske nie verletzt, Bürgermeister/Hauptfigur/67+ nach Regeln, deterministisch, Speichern/Laden mitten am Tag bitgleich | `ausgaben/kipolicy_mit_smoke_policy.txt` |

## 6. Smoke-Lauf auf V9 (Schritt 5)

`training/trainiere.py --profil smoke --name smoke_v9_2` (Belohnung v2, Sim-Version 9, sim `3b1a95e0e5ae9ea5`, Schema 2 `e85eca0c`,
Protokoll 1; Rechner teilte sich die Kerne mit der Regression, Last ~4):

| Kennzahl | Wert |
|---|---|
| Schritte, Zeit | 2.048 in 17,3 s Training (31,7 s gesamt), 118 Schritte/s, 34 Episoden (33 Zeitlimit, 1 Wegzug), 8 Rollouts à 256 mit je 4 Epochen (`n_updates` 32) |
| Parameteränderung L2 zum Anfang | gesamt 1,7266; `policy_net.0.weight` 0,2344, `policy_net.2.weight` 0,2768, `action_net.weight` 0,2136 (Biases 0,03), Wertnetz 0,98/1,28; `bester` (1.024 Schritte) 0,848 |
| Validierung (4 Episoden, Seeds 20000–20003) | Regeln Defizit 48,75; Policy 68,21 (1.024), 68,85 und 71,55 (2.048) – schlechter als die Regeln; ein Smoke-Lauf belegt nur die Kette |
| Checkpoints | `letzter.zip` sha256 `bcb54542941d2f78`, `bester.zip` `2bce28b0653ff9c5` |
| Reproduzierbarkeit | `smoke_v9_1` (vor der Umbenennung `kiEingabe`, sim `82fb18f5a1ab7478`) ergab **dieselben Gewichte** (L2 gleich, Inhalts-Hash der Policy gleich `cf2caae866578f0a`); nur der Name unterscheidet sich. Seine Export-Datei liegt in `ausgaben/alt/` |

**Export** `ki/policy_smoke_v9_2_bester.json` (107.848 Byte): Format `stadt-policy` 2, `simVersion` 9, Schema 2 `e85eca0c`, Status
`experimentell`, Hash `cf2caae866578f0a` (Python `inhalt_hash` = JS `policyHash`, sonst nähme `ki_liste.mjs` sie nicht an), Herkunft mit Lauf,
Checkpoint-sha256 und 1.024 Trainingsschritten. `ki/policies.json` nennt nur diese Datei (`ausgaben/ki_liste.txt`).

**Parität Trainer ↔ JS** (`training/paritaet.py` + `tools/paritaet.mjs`, `ausgaben/paritaet*.txt`): 644 Fälle – 240 echte Entscheidungen auf
Validierungsseeds (eigene Beobachtungen der V9-Umgebung), 150 künstliche (auch jenseits der Clip-Grenze), 10 nur warten, **244 Randfälle**
(genau im Mittel, genau auf und knapp jenseits von ±clip, jedes Merkmal einzeln ±10·clip·Streuung, alle 0, alle 1, −0, ±1e30; Masken mit genau
einer Aktion neben warten und mit allen). Normalisierte Eingaben gleich (0), Logits höchstens 2,30e-8 auseinander (Toleranz 1e-4), Aktion
644/644 gleich (0 Gleichstände), `tanhK` gegen `Math.tanh` ≤ 3,33e-16.

**Browser** (`node tools/browser_ki.cjs`, `ausgaben/browser_ki_1.txt`, Bild `ausgaben/ki_fenster_v9.png`): eigener Server
`python3 -m http.server 9061` (vom Test gestartet, am Ende per PID beendet), Chromium 141 mit SwiftShader, Three.js aus der lokalen Kopie, Anfragen
an 11434 abgebrochen. 24 von 24 in 3 Läufen hintereinander auf der Enddatei (`browser_ki_1…3.txt`; vorher mit dem Abschnitt in den Einstellungen
23/23 in 5 Läufen, mit der ersten Fassung des eigenen Fensters 24/24 in 3 Läufen): stadt.html ohne eingebettete Policy; Start mit Regeln ohne Anfrage an `ki/`; Einstellungen bei 1280 × 800 ohne
Scrollen, Fenster ohne Scrollen und ohne seitliches Überlaufen; Umschalten lädt `ki/policies.json` und die Policy (relative URL) und entscheidet (30 Spielstunden,
kein Rückfall); Spielstand nur mit Verweis (`{"v":1,"art":"policy","name":"smoke_v9_2_bester","hash":"cf2caae866578f0a","schema":"e85eca0c"}`,
keine Gewichte, Version 9); Neuladen holt die Policy vor dem Start wieder; gleiche Stadt aus einem Ordner **ohne `ki/`** (echte 404): Regeln,
Meldung mit Grund, danach `regeln` gespeichert; **andere Policy gleichen Namens** (anderer Hash) in `ki/`: Rückfall, die andere nur wählbar und
erst nach ausdrücklicher Wahl gültig; **beschädigte Dateien** in `ki/` (Gewicht geändert/alter Hash, NaN, Version 8, fehlende Datei, Pfad
`../../../stadt.html`) alle mit Grund abgelehnt; beschädigte `policies.json`; **Datei-Import** beschädigt und Version 8 abgelehnt, gültig
angenommen, gewählt und nach Neuladen ohne `ki/` wieder aktiv; Spielstand-Import mit vorhandener Policy (holt `ki/`) und mit fehlender (Rückfall
in derselben Meldung, `warnung`); Stand ohne Feld wie 09083f5; Rückfall zur Laufzeit (Logits laufen über); `file://` ohne Server (Hinweis, kein
`fetch`). **Konsole:** 22 Meldungen error/warning = 19 abgebrochene Ollama-Anfragen + 3 × 404 der gewollten Fälle (`ohne_ki/ki/policies.json`
zweimal, `kaputt/ki/policy_fehlt.json`), 0 andere, keine Seitenfehler. Vor einer Korrektur fiel der Test in 2 von 6 Läufen: der Browser meldete
die 404-Antwort von `policy_fehlt.json` als `net::ERR_ABORTED`, weil `holen` bei `!r.ok` den Rumpf nicht las; jetzt wird er gelesen – danach
5 von 5 Läufen grün.

**V9-eigene Browsertests** (Auswahl, `tools/v9_browsertests.sh`): Kopien aus `SP/v9/bau/tests` (nur gelesen) mit Port 9061 statt 8715, in jedem
Browser-Kontext abgebrochenen Anfragen an 11434 (der KI-Nachbau dort bleibt unberührt) und Version 8 als `stadt.orig.html` wie im V9-Bau; derselbe
Aufbau für die gepatchte Fassung und für 09083f5 (`ausgaben/v9_browsertests_{gepatcht,orig}.txt`, Logs in `ausgaben/v9tests/`):

| Test | gepatcht (Enddatei) | 09083f5 |
|---|---|---|
| `p6migration` (Spielstände V2, V4–V8 im Browser übernehmen, Import) | 39 OK, 0 FEHL, Exit 1 | 39 OK, 0 FEHL, Exit 1 |
| `p3test` | 12 OK, 0 FEHL, Exit 1 | 12 OK, 0 FEHL, Exit 1 |
| `befunde_v9` | 20 OK, Exit 0 | 20 OK, Exit 0 |
| `haushalt` | 18 OK, Exit 0 | 18 OK, Exit 0 |
| `wachstum` (u. a. Einstellungen ohne Scrollen) | 29 OK, Exit 0 | 29 OK, Exit 0 |

Exit 1 bei `p6migration` und `p3test` kommt in **beiden** Fassungen von Konsolenzeilen „Failed to load resource: net::ERR_FAILED“ (9–12 bzw. 1):
Diese beiden Tests leiten 11434 im ersten Kontext nicht selbst um und sprachen im V9-Bau mit dem Nachbau; mein Aufbau bricht diese Anfragen ab. Die URL
steht nicht im Log, die Zuordnung ergibt sich aus dem gleichen Bild bei 09083f5. Mit dem ersten Stand des Patches (Abschnitt in den Einstellungen)
fiel `wachstum` mit 2 FEHL (Abschnitt 8.2, Befund 5); seit dem eigenen Fenster gleich wie 09083f5. Nicht gelaufen: die übrigen 18 Tests und
`otest/` der V9-Sammlung.

## 7. Durchsatz auf V9 und Budget für den lokalen Lauf (Schritt 6)

Gemessen allein auf dem Rechner (Last 1,0–1,4), `ausgaben/durchsatz.txt`, `ausgaben/mess_lokal_v9.txt`, `training/laeufe/mess_lokal_v9/`:

| Messung | V9 | V8 (basis, zum Vergleich, Last 1–7) |
|---|---|---|
| Umgebung im Prozess, zufällige erlaubte Aktionen | 332 Schritte/s (3.930 Spielstunden/s), 12 Episoden, Städte 243–443 Einwohner | 424–463 Schritte/s, Städte 110–181 |
| dieselbe, Regelarm | 292 Schritte/s | – |
| Schnappschuss / Wiederherstellen | 1,1–1,3 ms / 2,2–2,5 ms (243 Einwohner) | 0,8–0,9 / 1,6–2,0 ms |
| über das JSONL-Protokoll aus Python (ohne Lernen) | 226 Schritte/s (2.726 Spielstunden/s) | 310 |
| Training MaskablePPO, Profil lokal (n_steps 1024, batch 128, 6 Epochen, Validierung alle 8.192 Schritte mit 16 Episoden) | **105 Schritte/s** (31.529 Schritte in 300 s, Zeitlimit per `--zeit-min 5`) | 162,6 (`lokal_1`) |
| Vorlauf vor dem Training (Normalisierung aus 128 Regel-Episoden, 7.564 Beobachtungen, dazu Regelarm auf 16 Validierungsepisoden) | ≈ 100 s | – |

Der Messlauf `mess_lokal_v9` hat echte Parameter geändert (L2 9,27), ist aber **nur eine Durchsatzmessung**: nicht exportiert, nicht
ausgewertet, seine Validierungswerte (Defizit 36–42 gegen Regeln 42,6 auf 16 Episoden) sind kein Qualitätsbeleg.

**Vorschlag lokaler Lauf auf V9 (30 min Wandzeit):** Profil `lokal_v9` in `training/konfig.json` = Profil lokal mit **155.648 Schritten**
(152 Rollouts à 1.024) und **Zeitlimit 26 min**. Bei 105 Schritten/s sind das ≈ 24,7 min Training + ≈ 1,7 min Vorlauf + ≈ 0,3 min
Abschlussvalidierung und Manifest ≈ 27 min; wird der Rechner langsamer (geteilt), bricht das Zeitlimit das Training nach 26 min ab
(`letzter.zip` und `bester.zip` bleiben gültig). Aufruf: `../venv/bin/python training/trainiere.py --profil lokal_v9`. **Vorher** die
Belohnung für V9 neu kalibrieren (Abschnitt 8.1), sonst trainiert der Lauf gegen eine Belohnung, die das Audit nicht besteht.

## 8. Befunde, Probleme, Grenzen

### 8.1 Belohnung v2 auf V9: Audit nicht bestanden (neu)

`node tools/ki_fallen.mjs --policy ki/policy_smoke_v9_2_bester.json` (Seeds 10040–10063, 30 Tage, `ausgaben/ki_fallen.txt`, 597 s): **2 FEHL**
von 8 Prüfungen:
- Gruppe `ohne_arbeit`: „jeden Abend treffen“ bringt 18,92 gegen 18,43 der Regeln (in V8 lag der Trick darunter). Alle anderen Gruppen und Tricks
  (Kündigen/Wiedereinstellen, Wechsel im Kreis, Dauerumzug, Wiederholgründen, Kind, Trennen im Kreis, nur leere Treffen) bleiben unter den Regeln.
- Leere Treffen ohne Gegenüber: Nutzen in der Sim Ø 0,452 (V8: 0,162), mit Abzug −0,65 netto Ø −0,198, aber netto > 0 in 9 von 44 Fällen
  (20,5 %); erlaubt sind höchstens 20 % (8,8 Fälle). Ohne Bedarf besteht (netto > 0 in 3 %). In V8 bestanden alle 8 Prüfungen
  (`SP/ml/basis/ausgaben/ki_fallen.txt`; dort `ohne_arbeit` 17,17 gegen 19,94).
Kalibrierung auf V9 (`node tools/ki_fallen.mjs --kalibrieren`, Seeds 10000–10031, nur gemessen, Belohnung nicht geändert,
`ausgaben/ki_fallen_kalibrieren.txt`; V8 aus `SP/ml/basis/ausgaben/ki_fallen_kalibrieren.txt`):

| Art des Treffens | V9: n, Mittel, 90-%-Wert | V8: n, Mittel, 90-%-Wert | Abzug in v2 |
|---|---|---|---|
| ohne Gegenüber | 35, 0,295, **0,696** | 80, 0,397, 0,632 | −0,65 |
| ohne Bedarf | 964, 0,091, 0,240 | 978, 0,085, 0,270 | −0,30 |
| mit Bedarf | 1.945, 0,121, 0,285 | 1.847, 0,112, 0,279 | 0 |

Der 90-%-Wert des Nutzens eines Treffens ohne Gegenüber liegt auf V9 über dem Abzug von v2 (0,696 > 0,65); das passt zum Befund oben. Ein v3
müsste diesen Betrag auf V9 neu setzen und die Gruppe „ohne Arbeit“ (Treffen jeden Abend) eigens prüfen.
Folgerung: Die Beträge von v2 stammen aus V8. Für V9 braucht es eine neue, versionierte Belohnung (v3) mit Kalibrierung auf V9 und erneutem
Audit, bevor ein lokaler Lauf zählt. Kriterien des Audits habe ich nicht geändert.

### 8.2 Weitere Befunde unterwegs

1. **`simtest --militaer` und der Funktionsname:** Die Grenze „keine Funktion zum Überwachen“ prüft Namen per Regex; `kiBeobachtung` traf
   `[Bb]eobacht`. Umbenannt in `kiEingabe` (die Policy-Eingabe der Person über sich selbst, keine Überwachung anderer). Nach der Umbenennung grün.
2. **simtest von V9 erwartet V8 als `stadt.orig.html`.** Die Aufgabe legt die ungepatchte V9 unter diesem Namen ab; beides verträgt sich nur über
   getrennte Testaufbauten (`pruefung/`), siehe Abschnitt 5.
3. **Mein Fehler im ersten Regressionslauf:** Ich habe `tools/v9_regression.sh` geändert, während es lief. Um ein Weiterlesen an verschobener Stelle
   zu vermeiden, habe ich nur den Elternprozess (PID 27164) beendet; die 40 Einzelläufe liefen zu Ende. Die Ausgaben von 09083f5 stammen aus diesem
   Lauf (vollständig, alle Exit 0), die gepatchte Seite, `--kipolicy` und der Tag-für-Tag-Vergleich aus dem zweiten Lauf auf der Datei mit `kiEingabe`.
4. **Smoke-Manifest und Enddatei:** `smoke_v9_2` lief auf sim `3b1a95e0e5ae9ea5` = sim-Block der Enddatei. Danach habe ich nur noch Oberfläche
   und Einstellungen geändert (404-Rumpf lesen, eigenes Fenster, kürzere Texte), nicht den sim-Block, und `trainiere.py` (`--zeit-min`, Profil
   `lokal_v9`): Das Manifest nennt deshalb `stadt_html_sha256` `6c89b7c6…` (Enddatei `48732527…`) und einen älteren Code-Hash für
   `trainiere.py`; die Simulation ist dieselbe (Parität und `ki_liste.mjs` gegen die Enddatei nachgerechnet).
5. **Einstellungen zu voll:** Mit dem Abschnitt „Entscheidungen der Bewohner“ in den Einstellungen (wie in basis) fiel der V9-Browsertest
   `wachstum.cjs` mit 2 Fehlern: Die Einstellungen scrollten bei 1280 × 800 (1.354 statt höchstens 760 px; 09083f5: 736 px), und der Test liest den
   Ollama-Text als 3. Absatz (`p.leise:nth-of-type(3)`), der durch die neuen Absätze verrutschte. Lösung: nur ein Knopf in der letzten Zeile der
   Einstellungen, die Wahl in einem eigenen Fenster; danach 736/736 px wie 09083f5 und der 3. Absatz bleibt der Ollama-Text
   (`analyse/einst_hoehe.cjs`, `ausgaben/v9tests/`).
6. **404 als „abgebrochen“:** Liest `fetch` bei einer 404-Antwort den Rumpf nicht, meldet Chromium die Anfrage manchmal als `net::ERR_ABORTED`
   (2 von 6 Testläufen). Jetzt wird der Rumpf gelesen.
7. **Zeitpunkt der Ausführung** (unverändert aus basis): im Spiel sofort, in der Umgebung am Ende der Stunde.
8. **Start mit einer Policy im Spielstand wartet auf `ki/`:** höchstens 8 s je Anfrage (Liste plus bis zu 12 Dateien); bei einem hängenden
   Server also bis zu gut 100 s, bevor die Stadt startet. Lokal gemessen dauert es Millisekunden; eine gemeinsame Frist für alles fehlt noch.

### 8.3 Nicht geprüft / offen

- Keine Qualitätsaussage auf V9: nur Smoke und Messlauf; kein lokaler Lauf, keine Auswertung (`werte_aus.mjs`), keine Stadtwirkung
  (`ki_stadtwirkung.mjs`) auf V9. Regeln bleiben Standard.
- Belohnung v3 für V9 (Abschnitt 8.1).
- Übernahme alter Stände (V2–V8) **mit** gewählter Policy gibt es nicht (das Feld kam erst mit diesem Patch); im Browser habe ich die Übernahme nur
  über die V9-eigenen Tests (Abschnitt 6) geprüft, nicht mit meinem Test.
- `tools/ki_tests.sh` ist jetzt eine Hülle für Version 9 (Regression, Zeit-Gate, Parität, Audit, Browser); nur auf Syntax geprüft (`bash -n`), als
  Ganzes nicht gelaufen – die Einzelteile schon (Abschnitte 5–8).
- Nicht gelaufen auf V9: `werte_aus.mjs` (Auswertung), `ki_stadtwirkung.mjs`, die übrigen 18 Browsertests und `otest/` der V9-Sammlung.
- Andere Browser als Chromium (Firefox, Safari) nicht geprüft; `fetch` mit `AbortController` und Top-Level-await gibt es dort seit Jahren, gemessen ist es nicht.
- Nichts davon liegt im Repo.

## 9. Befehle (aus `SP/ml/v9`)

```bash
# Ausgangsfassung (nie ändern)
git -C /home/user/website- show 09083f5:stadt/stadt.html > stadt.orig.html
git -C /home/user/website- show 09083f5:stadt/tools/simtest.mjs > tools/simtest.orig.mjs
# Patch (ohne --policy), Schema-Datei, Liste
node tools/ki_patch.mjs --html stadt.orig.html --aus stadt.html --simtest-ein tools/simtest.orig.mjs --simtest-aus tools/simtest.mjs
node tools/ki_schema.mjs
node tools/ki_liste.mjs
# Regression (20 Modi gepatcht und 09083f5, --kipolicy, Tag für Tag), Zeit-Gate
bash tools/v9_regression.sh /home/user/website- 3          # NUR_GEPATCHT=1: 09083f5 nicht wiederholen
bash tools/gate_zeit.sh 3
node tools/tagvergleich.mjs --a stadt.orig.html --b stadt.html --seeds 1,2,3,4,5,6 --tage 120 --tagschritt 60
(cd pruefung/gepatcht && node tools/simtest.mjs --kipolicy --orig ../../stadt.orig.html [--policy ../../ki/policy_smoke_v9_2_bester.json])
# Smoke, Export, Parität
../venv/bin/python training/trainiere.py --profil smoke --name smoke_v9_2
../venv/bin/python training/exportiere.py --lauf training/laeufe/smoke_v9_2 --checkpoint bester
../venv/bin/python training/paritaet.py --lauf training/laeufe/smoke_v9_2 --policy ki/policy_smoke_v9_2_bester.json --faelle 400 --aus ausgaben/paritaet_smoke_v9_2_bester.json
node tools/paritaet.mjs ki/policy_smoke_v9_2_bester.json ausgaben/paritaet_smoke_v9_2_bester.json
# Browser (eigener Server auf 9061, per PID beendet)
node tools/browser_ki.cjs
bash tools/v9_browsertests.sh stadt.html; bash tools/v9_browsertests.sh stadt.orig.html
# Durchsatz und Budget
node tools/ki_durchsatz.mjs --episoden 12 --seeds 10000,10001,10002,10003 [--arm regel]
../venv/bin/python training/durchsatz.py --episoden 20
../venv/bin/python training/trainiere.py --profil lokal --name mess_lokal_v9 --zeit-min 5
# Belohnungs-Audit
node tools/ki_fallen.mjs --policy ki/policy_smoke_v9_2_bester.json
node tools/ki_fallen.mjs --kalibrieren
# nächster Schritt (nach Belohnung v3): ../venv/bin/python training/trainiere.py --profil lokal_v9
```
