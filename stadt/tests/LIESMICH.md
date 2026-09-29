# Browser-Tests von STADT

Die Tests öffnen `stadt.html` in einem echten Chromium (Playwright), klicken wie ein Mensch und prüfen, was die Seite zeigt und was die
Simulation rechnet. Sie laufen aus einer frischen Kopie des Repos: nur relative Pfade (Basis ist dieser Ordner `tests/` und der Ordner
`stadt/` darüber), Temp-Dateien unter `os.tmpdir()`, Bilder und Logs in `tests/ausgabe/` (per `tests/.gitignore` ausgeschlossen).

## Starten

```bash
cd stadt
bash tests/alle.sh                      # alle 30 Tests nacheinander, am Ende eine Zusammenfassung
bash tests/alle.sh p3test otest/handy   # nur diese (Namen wie in der Liste unten)
```

`alle.sh` macht der Reihe nach:

1. prüft die Umgebung (`node tests/umgebung.cjs`: Playwright, Chromium, Three.js, Git);
2. startet den Seitenserver `python3 -m http.server $PORT --bind 127.0.0.1 --directory stadt/` (Standard-Port 8716);
3. fragt `http://localhost:11434/api/tags`. Antwortet dort nichts, startet es den KI-Nachbau `tests/mockollama.mjs` (kein Sprachmodell,
   Antworten im Format der Ollama-Doku). Antwortet dort schon ein KI-Nachbau, bleibt er unberührt. Antwortet ein echtes Ollama, warnt es:
   `p4test` braucht den Nachbau (Modell `test-modell:latest`, Umschalten per `POST /modus`) und wird dann rot;
4. erzeugt den Teststand für `t1_xss`, `befunde_v9` und `techfrueh` (`tests/basis.cjs`, etwa 20 s);
5. lässt die Tests **einzeln nacheinander** laufen (je höchstens 25 min), Log je Test in `tests/ausgabe/logs/`;
6. beendet den Seitenserver per PID, dann läuft `browser_ki` mit einem eigenen Server auf demselben Port (ebenfalls per PID beendet);
7. beendet den KI-Nachbau per PID, falls es ihn gestartet hat.

Ein Test ist grün, wenn er mit 0 endet, keine Zeile `FEHL…`/`Testfehler` schreibt und **genau** die Soll-Zahl an OK-Prüfungen erreicht
(Tabelle unten, in `alle.sh` bei `soll()` gepflegt; wer eine Prüfung hinzufügt, erhöht dort die Zahl). Exit-Code von `alle.sh`: 0 nur,
wenn alle grün sind, sonst 1; 2 bei unvollständiger Umgebung, belegtem Port oder unbekanntem Testnamen.

Einzelne Tests am einfachsten über `alle.sh` (siehe oben). Ohne `alle.sh`: erst den Server (`python3 -m http.server 8716 --bind 127.0.0.1 --directory .` im Ordner
`stadt/`), dann `node tests/p3test.cjs`. `t1_xss`, `befunde_v9` und `techfrueh` brauchen vorher einmal `node tests/basis.cjs`.

## Umgebungsvariablen

| Variable | Standard | Wofür |
|---|---|---|
| `PORT` | 8716 | Seitenserver (und Server von `browser_ki`) |
| `PLAYWRIGHT` | `require('playwright')` über `node_modules` bzw. `NODE_PATH`, sonst `$(npm root -g)/playwright` | Ordner des npm-Pakets `playwright` |
| `PLAYWRIGHT_BROWSERS_PATH` | Playwright-Standard (Linux-Container: `/opt/pw-browsers`, Mac: `~/Library/Caches/ms-playwright`) | wo Chromium liegt |
| `THREE_DIR` | `node_modules/three` neben Playwright, sonst keines | Ordner des npm-Pakets `three@0.186.0`; die Tests liefern es unter der CDN-Adresse aus, die das Spiel lädt. Ohne lokales Paket lädt Chromium Three.js aus dem Netz (`cdn.jsdelivr.net`); im Linux-Container scheitert das am Zertifikat des Proxys (`ERR_CERT_AUTHORITY_INVALID`, ausprobiert), dort ist `THREE_DIR` also nötig |
| `STADT_GIT` | das Git-Repo, in dem `stadt/` liegt | für alte Fassungen per `git show` (siehe unten) |
| `AUSGABE` | `tests/ausgabe` | Bilder, Logs, erzeugte Spielstände |
| `KI_ORDNER` | `tests/ki_testdaten` | Ordner mit `policies.json` und Policy für `browser_ki`, relativ zum Ordner `stadt/` (`KI_ORDNER=ki`: die echte Policy); die Version-8-Datei kommt immer aus `tests/ki_testdaten/v8/` |
| `KI_PORT` | 11434 | nur zum Prüfen von `alle.sh` selbst: das Spiel fragt immer 11434 |

## Was installiert sein muss

Gemessen und benutzt hier (Linux-Container): Node 22.22.2, Playwright **1.56.1** (Chromium 141.0.7390.37, Build 1194), Python 3.11.15
(nur für den Seitenserver `http.server`, keine Pakete), Git, curl, bash. Three.js 0.186.0 als npm-Paket. Pillow braucht es nicht mehr:
`otest/breit` liest die Pixel seines Bildschirmfotos seit dem 29.09.2026 in Node. Die Tests laufen deshalb auch in einem Terminal mit
aktiver Trainings-Umgebung (`source .venv/bin/activate`), dort war `python3` vorher ohne Pillow und `otest/breit` rot.

### Linux-Container (wie hier)

Playwright liegt global (`/opt/node22/lib/node_modules/playwright`, gefunden über `npm root -g`), Chromium unter `/opt/pw-browsers`
(`PLAYWRIGHT_BROWSERS_PATH` ist gesetzt). Nötig sind noch das Paket `three@0.186.0` (`THREE_DIR`, z. B. aus
`npm i --prefix <werkzeug> three@0.186.0` → `<werkzeug>/node_modules/three`) und die Git-Geschichte:

```bash
cd stadt                                                  # in einer vollständigen Git-Kopie (nicht --depth 1)
THREE_DIR=/pfad/zu/three PORT=8716 bash tests/alle.sh      # THREE_DIR = Ordner mit package.json von three 0.186.0
```

Liegen die Tests nicht in einer Git-Kopie (z. B. eine kopierte Stufe), zusätzlich `STADT_GIT=/pfad/zum/repo`.

### Mac

Die Werkzeuge kommen in einen eigenen Ordner außerhalb des Spiels (das Spiel bleibt eine einzelne HTML-Datei ohne Abhängigkeiten):

```bash
mkdir -p ~/stadt-werkzeug && cd ~/stadt-werkzeug
npm init -y
npm i -D playwright@1.56.1 three@0.186.0                  # dieselben Versionen wie hier
npx playwright install chromium                           # lädt das zu 1.56.1 passende Chromium
```

Dann im Repo:

```bash
cd <repo>/stadt
PLAYWRIGHT=~/stadt-werkzeug/node_modules/playwright bash tests/alle.sh
```

`three` wird neben Playwright gefunden (`~/stadt-werkzeug/node_modules/three`). Außerdem nötig: Node 18 oder neuer (Playwright 1.56.1
verlangt `>=18`; hier 22), `python3` 3.7 oder neuer (`http.server --directory`), `git`, `curl` und `perl` (`alle.sh` nimmt `perl`, wo es
kein `timeout` gibt). `curl` und `perl` bringt macOS mit, `git` und `python3` kommen mit den Xcode-Befehlszeilenwerkzeugen
(`xcode-select --install`).
Läuft die Ollama-App, vor den Tests beenden (sie belegt 11434, `p4test` braucht den Nachbau). **Nicht auf einem Mac geprüft**: Die
Anleitung folgt aus den hier benutzten Versionen; Chromium läuft mit SwiftShader (`--use-angle=swiftshader`), Bildwerte und Zeiten können
auf dem Mac anders ausfallen.

## Alte Fassungen und erzeugte Daten (nichts davon liegt als Kopie im Repo)

Übernahmetests brauchen alte Fassungen von `stadt/stadt.html`. `tests/umgebung.cjs` holt sie zur Laufzeit per `git show <commit>:stadt/stadt.html`
in einen Temp-Ordner, prüft den Git-Blob und liefert sie per Playwright-Route unter `stadt.orig.html` aus (gleiche Herkunft, also derselbe
Spielstand-Speicher):

| Fassung | Commit | Spielstand-Version | benutzt von |
|---|---|---|---|
| v2 | 39c405b | 2 | `p6migration` (Spielstand in Node gerechnet, wie früher `v2save.mjs`) |
| v4tech | 797107a | 4 | `basis.cjs` (Grundstand Seed 2, Tag 420) |
| v4 | 96f6dc4 | 4 | `p6migration` |
| v5 | 414ebab | 5 | `p6migration`, `befunde_s2`, `basis.cjs` |
| v6 | bc7247a | 6 | `p6migration`, `befunde_s2`, `basis.cjs` |
| v7 | ffa1d88 | 7 | `p6migration`, `basis.cjs` |
| v8 | 31ce452 | 8 | `p6migration`, `basis.cjs`; Vergleichsstand `stadt.orig.html` in `haushalt`, `rathaus`, `schule`, `techfrueh` |

Erzeugt statt eingecheckt (die alten Dateien waren 0,26 bis 1,4 MB):

- **Spielstand Version 2** (`U.v2Spielstand()`): Sim-Block der Fassung v2 in Node, Seed 1 bis Tag 150, 13 Uhr, mit Baustelle. Nachgeprüft
  gleich der früheren `v2save.json` bis auf den Zeitstempel `zuletztGelaufen`.
- **Teststand Seed 2, Tag 420** (`tests/basis.cjs` → `tests/ausgabe/basis/`): Grundstand mit 797107a (Hauptfigur: eine Programmierkraft der
  größten Tech-Firma), dann „Stadt übernehmen“ mit 414ebab, bc7247a, ffa1d88, 31ce452 und zuletzt der `stadt.html` dieses Ordners.
  Nachgeprüft (`node tests/basis.cjs --vergleich <ordner>`): Versionen 4, 5 und 6 gleich den früheren Dateien bis auf `zuletztGelaufen`; ab
  Version 7 steht in einer Stadtbuch-Zeile „näher als 18 Felder“ statt „16 Felder“ (die frühere Datei stammte aus einem Bau von Version 7 vor
  dem Commit ffa1d88), in Version 9 kommt `ui.entscheidungen` der KI-Policy dazu. Kein Test prüft diese Zeile.

## Die Tests

Dauer: gemessen in zwei Läufen aus je einer frischen Kopie (Linux-Container, 4 Kerne, keine GPU, SwiftShader). Lauf 1 lief neben einem
Training eines anderen Prozesses; die Last während Lauf 2 ist nicht festgehalten.

| Test | OK (Soll) | Dauer Lauf 1 / 2 | prüft |
|---|---|---|---|
| `p3test` | 12 | 19 s / 16 s | Hausklick → Bewohner, Personenkarte, Namen durchklicken, Zurück, Enkel über das Stadtbuch |
| `p5neu` | 10 | 28 s / 24 s | Korrekturen aus dem Spec-Abgleich |
| `p6migration` | 39 | 275 s / 205 s | Übernahme alter Spielstände der Versionen 2, 4, 5, 6, 7, 8: Dialog, Import, Meldung, Neues ab dem Übernahmetag |
| `p7figuren` | 6 | 7 s / 7 s | Figuren bei der Arbeit stehen dort, wo die Simulation die Person hat (8–17 Uhr) |
| `p8tech` | 15 | 23 s / 19 s | Tech-Firmen: Glasbau, Bildschirme, Figuren, Karten, Code-Tagebuch (Ollama-Attrappe per Route), Draw Calls |
| `raute_klick` | 8 | 12 s / 11 s | Klick auf die Raute einer Hauptfigur öffnet sie |
| `ereignis` | 21 | 20 s / 18 s | Ereignis-Zeichen auf der Karte (wann ja, wann nicht, höchstens 3 je Stunde) |
| `t1_xss` | 5 | 20 s / 19 s | HTML/Script in KI-Antworten nur als Text, Code-Zäune, kaputte Antworten, einmal am Tag (Teststand aus basis.cjs) |
| `p4test` | 29 | 47 s / 44 s | Hauptfiguren mit dem KI-Nachbau auf 11434: Anfragen, Tagebuch, Gespräch, Hauptfigur an/aus, Fristen bei 20× und 100×, Ausfall |
| `s2karten` | 22 | 59 s / 46 s | Stadtregierung Schritt 2: Fenster, Personen- und Hauskarte (Wohneigentum, Rente) |
| `kita` | 22 | 35 s / 31 s | Kitas: Zeichnung, Personal, Hauskarte, Kinder und Eltern |
| `befunde_s2` | 27 | 66 s / 56 s | Versionsdialog von Version 5 und 6 (Git) am Handy und breit, Fenster Stadtregierung am Handy, Kita-Karten |
| `erweiterung` | 20 | 33 s / 33 s | Die Karte wächst mitten im Spiel |
| `sicherheit` | 12 | 14 s / 13 s | Wache, Anstalt, Polizei, Karten |
| `militaer` | 16 | 43 s / 37 s | Kaserne, Dienststelle, Wehrdienst, Karten |
| `autos` | 9 | 19 s / 19 s | Tech-Stufen bis zum Hochhaus, Autowerk, Autos in den Daten |
| `autos_bild` | 20 | 130 s / 103 s | Autos im Bild: Fahrt nur bei echtem Ortswechsel, Rechtsverkehr, Licht, Campus |
| `rathaus` | 15 | 46 s / 43 s | Rathaus und Bürgermeister, echter Klick, Ausbaustufen, Draw Calls gegen Version 8 |
| `schule` | 8 | 40 s / 36 s | Schule: Bild, Hauskarte, Personenkarte, Stadtregierung, Draw Calls gegen Version 8 |
| `haushalt` | 18 | 31 s / 29 s | Haushalt: Zeile „Budget“, Fenster, Lohnsteuer, Maße und Draw Calls gegen Version 8 |
| `wachstum` | 29 | 253 s / 259 s | Wachstum, Tempo bis 100×, KI bei jedem Tempo (Ollama per Route), Leistungsmessung |
| `techfrueh` | 17 | 42 s / 38 s | Tech-Firmen früher, Umland und Welt, Übernahme eines Stands von Version 8 (basis.cjs) |
| `befunde_v9` | 20 | 31 s / 31 s | Befunde der Schlussprüfung von Version 9 (Leiste, Karten, Übernahme nach 40 Tagen Abwesenheit) |
| `otest/befunde` | 21 | 64 s / 52 s | Fokusring, Legende, Dialoge am Handy |
| `otest/handy` | 11 | 26 s / 20 s | Handy: echtes Antippen (Touch), Karte, „Zeigen“, Auf- und Einklappen |
| `otest/breit` | 12 | 49 s / 44 s | Desktop: erster Hinweis, Hilfe, Tab-Reihenfolge, Fokusringe, Kontrast (Pixel des Bildschirmfotos in Node gelesen) |
| `otest/tastatur` | 4 | 12 s / 10 s | Schmal mit Tastatur |
| `otest/breiten` | 20 | 52 s / 45 s | Breiten 360, 400, 768, 1280 und quer |
| `otest/hilfehoehe` | 1 | 5 s / 5 s | Hilfe bei 1280 × 800 ohne Scrollen |
| `browser_ki` | 30 | 30 s / 29 s | KI-Policy aus ki/, Speichern als Verweis, Rückfall, Import (Ergebnis sichtbar im Fenster), Datei entfernen, Auswertung laut Datei, file:// (eigener Server, siehe unten; bis 28.09. 24 Prüfungen) |

Dazu `basis.cjs` (Teststand) 20 s. Ganzer Lauf: **25 bzw. 22 min** (30 Tests, damals 493 OK-Prüfungen, beide Läufe alle grün; seit den
6 neuen Prüfungen in `browser_ki` sind es 499).

Nicht in `alle.sh` (Werkzeuge, alte Stände): `blick.cjs` (Bildschirmfotos Tag/Abend/Nacht nach `tests/ausgabe/blick/`),
`kennzahlen_hoehe.cjs` (Messung gegen `stadt.orig.html` = Version 8), `pruef_v5.cjs` (veraltet: erwartet Version 8, lief schon in Version 9
nicht mehr; die Übernahme eines V5-Stands prüft `p6migration`). Hilfsdateien: `umgebung.cjs` (gemeinsame Umgebung), `hilfe.cjs`
(Ollama-Attrappe per Route für `t1_xss`), `otest/h.cjs`, `leer.html` (Seite derselben Herkunft ohne Stadt), `mockollama.mjs`, `basis.cjs`.

## KI-Test (`browser_ki`)

Prüft das Laden einer trainierten Policy aus `ki/` neben der Seite, Speichern/Laden als Verweis (Name, Hash, Schema), Rückfall auf die
Regeln bei fehlender, fremder oder beschädigter Policy, Datei-Import (Ergebnis im Fenster sichtbar: `elementFromPoint` in der Mitte des
Status trifft den Status selbst; die Meldung unten liegt hinter den offenen Fenstern), „Geladene Datei entfernen“, „Auswertung laut
Datei“, Texte ohne Doppelungen, `file://`. `KI_ORDNER=ki bash tests/alle.sh browser_ki` prüft dasselbe mit der echten Policy aus `ki/`
(bis 29.09.2026 ging das nicht: der Test suchte die Version-8-Datei in `KI_ORDNER` und löste den Pfad gegen `tests/` auf). Er baut in einem
Temp-Ordner eine Seite aus einer Kopie von `stadt.html` und `ki/` aus `tests/ki_testdaten/`: `policy_smoke_v9_2_bester.json` (Smoke-Lauf auf
Version 9, Status experimentell, **kein Qualitätsbeleg**, nur für den Ablauf) und `v8/policy_lokal_1_bester.json` (Policy für Version 8, muss abgelehnt werden).
