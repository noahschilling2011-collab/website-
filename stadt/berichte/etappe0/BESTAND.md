# STADT – Etappe 0: Ausgangsstand (Version 8, 31ce452)

Stand 28.09.2026, 14:20–14:35 Uhr (UTC). Alle Zahlen hier stammen aus Läufen dieser Etappe. Die Ausgaben liegen in
`ml/etappe0/ausgaben/`. Im Repo ist nichts geändert, nichts committet. Der Rechner war die ganze Zeit mit dem V9-Bau geteilt:
vier `mess9w.mjs`-Prozesse belegten die 4 Kerne, die Last lag bei 4,8 bis 5,6. Laufzeiten sind deshalb Obergrenzen.

Pfadkürzel: `SP` = `/tmp/claude-0/-home-user-website-/584133fa-a5fc-563e-807a-2feca85efaf0/scratchpad`, `E0` = `SP/ml/etappe0`.
Zeilennummern beziehen sich auf `stadt/stadt.html`, `stadt/README.md` bzw. `stadt/tools/simtest.mjs` in 31ce452.

## 0. Kurzfassung

- Branch `claude/build-stadt-simulation-58kqh0`, HEAD `31ce452` (Version 8). Das Arbeitsverzeichnis entspricht HEAD. Beim ersten `git status` um 14:20:32 lagen dort zwei
  fremde, leere und unversionierte Dateien `k5_a1.txt` und `k5_e2.txt` (angelegt 14:16). Ich habe sie nicht angefasst; meine Befehle im Repo
  haben nur gelesen. **Um 14:41 waren sie weg** (Änderungszeit des Repo-Ordners 14:20:54, `git status` danach leer). Wer sie entfernt hat, weiß ich
  nicht, vermutlich der Prozess, der sie angelegt hat. Es gibt weder `AGENTS.md` noch `CLAUDE.md`.
- Alle sieben verlangten Basistests liefen auf der Kopie von 31ce452 ohne Fehler: `--gate` (alle Gates, Seeds 1–3),
  `--speichertest` (bitgleich, Fingerabdruck `0cdd15796669ff3a` wie im README, Z. 2738), `--kitest`, `--aufholtest` (nur Vergleich),
  `--migrationstest` (324 ok), `--erweiterung` und `--autos`. Ein zusätzlicher Rauchtest im Browser lief ohne Server und fand keine Seitenfehler.
- **Aufholen in Stücken:** Das README beschreibt die Ursache richtig. Ich habe sie gemessen und genauer eingegrenzt. Beginnen die Stücke
  mitten am Tag, ist 1 × 90 in 10 von 10 Seeds nicht gleich 3 × 30. Die Einwohner weichen um −7,4 % bis +8,1 % ab. Beginnen die Stücke um
  Mitternacht, ist das Ergebnis in 10 von 10 Seeds bitgleich. Rein stündlich gerechnet ist die Stückelung immer bitgleich. Die Ursache:
  `tagSchritt` rechnet nicht dasselbe wie 24 × `stunde`, und jedes Stück rechnet einen angebrochenen Tag stündlich statt im Tagesschritt.
- **Eine Trainingspipeline gibt es nicht.** torch, stable-baselines3 und sb3-contrib sind nicht installiert. PyPI und download.pytorch.org
  sind erreichbar: sb3-contrib 2.9.0, SB3 2.9.0, gymnasium 1.3.0 und das CPU-Rad torch 2.14.0 für cp311 (196 MB). Die Namen in der
  MaskablePPO-Schnittstelle habe ich im Quelltext des Rads 2.9.0 nachgesehen (Abschnitt 6).
- **Ollama:** Es ist nicht installiert, lässt sich aber herunterladen: v0.34.4 für linux-amd64 als `.tar.zst` mit 1,43 GB, per HEAD
  bestätigt. Zum Entpacken fehlt `zstd`. Kleine Modelle sind ebenfalls erreichbar, etwa qwen2.5:0.5b mit 398 MB (Blob per HEAD
  bestätigt). Die Aussage im README (Z. 3269), es gebe „keinen Download dafür“, stimmt heute nicht mehr.
- **Wichtigster Befund für Etappe 1:** `entscheide()` wählt, führt aus und zieht dabei Zufall aus dem gemeinsamen Strom `S.rs`. Trifft die
  Policy die Entscheidung einer einzelnen Person, verschiebt sich dadurch der Zufall der ganzen Stadt. Der Patch braucht deshalb einen
  eigenen Zufallsstrom für die Fokusperson. Außerdem darf der Zustand `S` keine neuen Schlüssel bekommen, solange die Policy aus ist.
  Nur so bleibt die Stadt bitgleich zu 31ce452.

## 1. Repo, Arbeitsverzeichnis, Vorgaben

| Prüfung | Ergebnis |
|---|---|
| Branch / HEAD | `claude/build-stadt-simulation-58kqh0` / `31ce45210703530551d90e7e76a459f68636c847` („STADT: Version 8 – Tech-Firmen bis zum Hochhaus, Autowerke und Autos“) |
| `git status` | 14:20:32: nur `?? k5_a1.txt`, `?? k5_e2.txt` (je 0 Byte, 28.09. 14:16, fremd, nicht angefasst). 14:41: leer, beide Dateien sind verschwunden (Änderungszeit des Ordners 14:20:54, nicht durch mich). `git diff --stat HEAD` ist leer, HEAD unverändert `31ce452` |
| Dateien STADT | `stadt/stadt.html` 1.064.795 B, 13.658 Z., sha256 `bd2926fb…683b77`, identisch mit `git show 31ce452:stadt/stadt.html` und mit `SP/ml/basis/stadt.html`; `stadt/README.md` 412.328 B, 3.410 Z.; `stadt/tools/simtest.mjs` 305.937 B, 3.528 Z. |
| AGENTS.md / CLAUDE.md | keine, gesucht im Repo, in `/root`, in `/home/user` und in `~/.claude` |
| CI | `.github/workflows/ci.yml` testet nur `blitzerwarner/`. **STADT läuft in keiner CI** |
| Kopie für die Tests | `git archive 31ce452 stadt` nach `E0/kopie/stadt`; das Repo bleibt dabei unberührt |
| Spec `SP/SPEC_voll.md` | Feste Entscheidung 1 lautet „Jeder Bewohner hat ein eigenes Gehirn, aber ohne KI“, weil ein Sprachmodell zu langsam ist. Noahs Master-Prompt vom 28.09. verlangt jetzt eine trainierte Policy. Das ist kein Widerspruch in der Sache: Ein MLP braucht Mikrosekunden, und die Regeln bleiben Standard, bis die Auswertung besteht. Es ist aber eine bewusste Änderung einer festen Entscheidung und gehört so ins README. Weitere Spec-Punkte: „Aufholen mit Tages- statt Stundenschritten, gleiche Regeln“; „keine neuen Aktionen für Bewohner“. Die explizite Warteaktion ist keine neue Aktion, sie ist das bisherige „nichts über der Schwelle“ (`entscheide` gibt 0 zurück, Z. 2248) |

## 2. Verifizierte Tabelle zu Abschnitt 1 des Master-Prompts

| # | Punkt des Master-Prompts | Urteil | Befund und Beleg |
|---|---|---|---|
| 1 | stadt.html über 1 MB, schrittweise entflechten | **stimmt** | 1.064.795 B. Kopf, CSS und HTML 1–837, Import-Map 592–599 (Three.js 0.186.0 vom CDN jsdelivr), `<script id="sim">` 838–6363 (5.526 Z.), `<script type="module">` 6365–13656 (7.292 Z.). Entflechten heißt hier: Das Spiel bleibt eine Datei. Werkzeuge, Training, Tests und Berichte kommen in eigene Dateien, und der sim-Block wird über einen gemeinsamen Loader herausgezogen (wie `simtest.mjs` 64–99) |
| 2 | sim-Block rein halten | **stimmt** | Kommentar 838–845. `simtest` prüft statisch auf verbotene Namen (simtest 72–80) und führt den Block im vm-Kontext aus, in dem Math.random, Date und Intl gesperrt sind (84–99). Alle 7 Läufe kamen durch diese Prüfung |
| 3 | typisierte Arrays erhalten | **stimmt** | Personen als Struct-of-Arrays `PF` 1185–1244 (Index = Personen-ID, Kapazität wächst durch Verdoppeln, `kapazitaet` 1385), Gebäude `GF` 1246–1287. Gespeichert wird als Base64 (6466–6490) |
| 4 | entscheide / erlaubteAktionen / ausfuehren als Vergleich und Rückfall | **stimmt, aber anders gebaut als für eine Policy nötig** | `entscheide` 2151–2250 wählt **und** führt aus (`ausfuehren` in 2249). Zufall aus `S.rs` zieht es nur, wenn eine Aktion die Schwelle erreichen kann (2178–2245). `erlaubteAktionen` 2638–2664 kommt ohne Zufall aus; `--kitest` fand 0 Abweichungen „Gehirn ⊆ erlaubt“ (10.223 / 8.587 / 10.449 Entscheidungen). `ausfuehren` 2252–2272 prüft die Voraussetzungen **nicht erneut**, und die `akt*`-Funktionen tun es nur teilweise (`aktKuendigen` 2309 ohne Stellenprüfung, `aktKind` 2424 prüft nur den Partner). Beim Trennen ist die Maske weiter als die Regel: Die Regel verlangt zusätzlich `zufall(S) < 0.03` (2224, Maske 2657). Aufrufstellen von `entscheide`: 2720 (Frist), 2746/2752 (KI-Antwort), 2761 (verworfen), 2879 (stündlich), 5527 (Tagesschritt) |
| 5 | Ollama-Hauptfiguren | **stimmt** | Anfragen stellt `kiFragen` 2697–2710: höchstens `KI_PRO_TAG` 3 je Figur und Tag, Frist `KI_FRIST` 2 Spielstunden (1104–1107), 5 Figuren zum Start, höchstens 10. Die Oberfläche schickt einen Aufruf zur Zeit (Takt 400 ms, 12103), Timeout 30 s (11735). Bei 20× gibt es keine Entscheidungen, nur Gespräche (12035) |
| 6 | JSON-Validierung weiterentwickeln | **stimmt, noch ausbaufähig** | `format: 'json'` statt eines JSON-Schemas (11782; Kommentar 11733: „Schema … nicht getestet“). Die Prüfung `pruefeEntscheidung` 11927 verlangt, dass die Aktion in der Liste steht, einen Gedanken bis 300 Zeichen, ein gültiges Ziel und dass `verdachtFrei` besteht (11963, Wortlisten). Die Sim prüft noch einmal gegen `erlaubteAktionen` zur `antwortStunde` (2741–2756). Späte Antworten erkennt sie an der Nummer (`anfrageRaus` 2728). Die Anfrage hat **keine Welt- oder Sitzungsversion und keine Ablaufzeit in Echtzeit** (2707: nr, id, gen, tag, stunde, frist, erlaubt); die Oberfläche schützt nur mit `S !== stadt` |
| 7 | Keine Trainingspipeline → echtes Lernverfahren ergänzen | **stimmt** | Im Repo liegen nur stadt.html, README und simtest.mjs. Es gibt keine Gewichte, keine Checkpoints und kein Python. Im System fehlen torch, SB3 und sb3-contrib; vorhanden ist nur numpy 2.4.6 |
| 8 | Echte Modelltests nachholen, getrennt ausweisen | **stimmt, eine Begründung ist überholt** | Getestet ist nur gegen einen Nachbau (README 27, 3269, 3230). README 3269 sagt „kein Ollama und keinen Download dafür“. Der Download geht heute (Abschnitt 6) |
| 9 | Spielstände schützen, Migration testen | **stimmt** | localStorage-Schlüssel `stadt-save-v1` (6464), `VERSION = 8` (848), `MIGRIERBAR = [2..7]` (5560), Prüfungen in `importZustand` 5567–5632. Ein Stand, der nicht lesbar ist, wird nicht überschrieben (`speichernErlaubt = false`, 6546). `--migrationstest`: 324 ok, 0 FEHL. `--speichertest`: bitgleich über 60 Tage, drei Stände |
| 10 | Gates erhalten | **stimmt** | `--gate` mit Seeds 1–3 BESTANDEN. Einwohner an Tag 365: 928 / 982 / 954. Gate 4 Faktor 1,07 / 1,07 / 1,06. Gate 6 +20,4 / +20,8 / +22,3. Gate 7 −27,1 (n = 30) / −25,3 (n = 14) / −29,4 (n = 26). T 3,8 / 3,1 / 1,5 s unter Last |
| 11 | Browserprüfungen reproduzierbar ins Projekt | **stimmt (nicht im Repo)** | README 3067: „Nur `tools/simtest.mjs` liegt im Repo.“ Die Tests liegen z. B. in `SP/v8/bau/tests/` (`alle.sh`, 17 Tests plus otest). Sie enthalten feste scratchpad-Pfade (20 Treffer), setzen Server-Port 8714 und den KI-Nachbau auf 11434 voraus. Mein Rauchtest `E0/browser_rauch.cjs` zeigt, dass es ohne Server geht: Seite und Three.js kommen per `page.route` aus Dateien |
| 12 | Kartengrenze 256 ernst nehmen | **stimmt, ungemessen** | `KARTE_MAX: 256` (1016), `g.x`/`g.y` als `Uint8Array` (1247), der Import prüft das (5582). Die größte Karte in meinen Läufen war 104 (Seed 2, `--erweiterung`), laut README hat die große Stadt 120 (3332). Wie sich die Stadt an der Grenze verhält, ist nicht gemessen |
| 13 | Geld- und Warenflüsse nachvollziehbar | **stimmt (fehlt)** | Es gibt kein Transaktionsjournal (0 Treffer für „journal“). Im sim-Block ändern 29 Stellen `geld[...]`, 20 Stellen `S.budget` und 8 Stellen `kasse[...]`. Nachvollziehbar sind nur Summen in `S.stat` (z. B. `stat.regierung`, `stat.auto`). README 3244: „Geld von außen ohne Gegenfinanzierung“. README 3219ff.: Die Werkstätten machen etwa fünfmal so viele Kisten, wie die Läden brauchen |
| 14 | Autos springen, Parks ohne Besucher → an echte Zustände binden | **stimmt** | **Parks** wirken nur passiv: Wer einen Park in bis zu 5 Feldern hat (`parksZuordnen` 1934, `REICH_PARK` 954), bekommt je Abendstunde +0,3 Freizeit (2867) und +12 Wohnwert (1950). `ortZurStunde` (3410–3418) kennt keinen Parkbesuch; Figuren gehen nur quer durch Parks (7683). **Autos:** In der Sim zählte `--autos` 32 Sprünge ohne Fahrt in 12 × 730 Tagen (30 bei Umzug, 2 bei neuer Stelle). In der Darstellung fährt laut README 2974 in der großen Stadt um 8 und 17 Uhr knapp die Hälfte der Fahrten nicht sichtbar (`FAHR_MAX` 1500, 6461). Die Darstellung habe ich nicht selbst gemessen |
| 15 | Aufholen-Semantik klären, Regressionstest | **stimmt, Ursache gemessen** | README 3401 und Annahme 43 (3118). Messung in Abschnitt 5. Die Spec verlangt Tagesschritte, der Master-Prompt „exakt oder ein gekennzeichneter Näherungsmodus“ |

## 3. Architektur: Datenfluss Sim ↔ Darstellung ↔ KI

```
stadt.html
├─ <script id="sim">  (838–6363)  → globalThis.StadtSim (6324–6362)
│    Zustand S: typisierte Arrays S.p.* (Personen), S.g.* (Gebäude), Felder; JSON-Teile (stat, ki, regierung, erweiterung …)
│    Zufall: S.rs (Stadt), S.rsSich (Taten), S.rsAuto (Autos) – mulberry32, im Zustand gespeichert
│    stunde(S) 2838:  kiFristen → je erwachsener Person: Bedürfnisse, Zufriedenheit →
│                     um 7/18 Uhr oder nach Ereignis (P.jetzt): Hauptfigur & ki.an → kiFragen (Anfrage in S.ki.anfragen)
│                                                              sonst entscheide → ausfuehren → akt*
│                     7 Uhr bauEinteilen; 24 Uhr tagesabschluss 2910 (Wirtschaft, Kitas, Menschen, Sicherheit, Zuzug, Bauamt, Bund …)
│    tagSchritt(S) 5488: Aufholen: alle entscheiden um 7 und 18, Bedürfnisse im Block, dann tagesabschluss
│    exportZustand 5544 / importZustand 5567 (+ Migration 2…7 → 8)
│    Hauptfiguren: kiEntscheidung / kiVerwerfen / kiGespraech / kiTagebuch / kiCode (prüfen erneut, entscheiden sonst mit Regeln)
│
├─ <script type="module">  (6365–13656)  Darstellung, Oberfläche, Speichern, Ollama
│    Start: localStorage 'stadt-save-v1' → importZustand, sonst neueStadt(seed) (6533ff.)
│    frame (requestAnimationFrame) → simTakt 12281: 1× = 60 s je Spielstunde, höchstens 3 Stunden je Bild → Sim.stunde
│    nachSchritten → Three.js-Szene (G.stadt, Figuren), Panels, Karten (liest S, schreibt nie direkt)
│    kiTakt alle 400 ms → ollamaChat (localhost:11434/api/chat, format:'json') → pruefeEntscheidung → Sim.kiEntscheidung
│    speichern alle 30 s und bei pagehide (6502); Aufholen beim Öffnen/Sichtbarwerden (12342): stündlich bis 0 Uhr, Tagesschritte, stündlich bis zur Zielstunde
│
└─ tools/simtest.mjs: zieht den sim-Block heraus, statische Prüfung, vm-Kontext → dieselbe Simulation in Node

Geplanter Weg (Etappe 1):
  sim-Block (gepatcht, Policy aus = bitgleich) ──gemeinsamer Loader──▶ training/umgebung.mjs (Node, JSONL v1)
        ▲                                                               │ reset/observe/actionMask/step/snapshot/restore
        │ Policy-Haken am Anfang von entscheide                         ▼
  Browser: Policy-JSON importiert, Inferenz in JS ◀── Export (JSON) ◀── Python: gymnasium.Env + MaskablePPO (sb3-contrib 2.9.0)
```

Zuständigkeiten heute: Den Zustand ändert nur die Sim. Die Oberfläche ruft nur StadtSim-Funktionen auf (README 2995–2998). Das
Sprachmodell macht Vorschläge, die Sim prüft sie erneut. Beim Aufholen und bei 20× entscheiden die Regeln.

Entscheidungen einer Person, die nicht in `entscheide` fallen und deshalb Regeln bleiben: Ziele (`zielPruefen`/`zielWaehlen`,
aus `menschenTag` 4213, mit Zufall), Wohnungskauf (`wohnungKaufen` 2002, nachts), Geräte- und Softwarekäufe (`techKauf` 3606),
Autokauf (`autosTag` 3624), Taten (`sicherheit`, eigener Strom), Wehr- oder Ersatzdienst (`dienstWahl`), Einteilung im Bauhof.

## 4. Basistests auf der Kopie von 31ce452 (ausgeführt)

Aufgerufen über `E0/basistests.sh` in zwei Ketten, höchstens zwei Prozesse gleichzeitig, mit Node v22.22.2.

| Befehl | Ergebnis | Dauer | Ausgabe |
|---|---|---|---|
| `--gate` | **BESTANDEN**, Seeds 1–3, alle Gates (Zahlen in Tabelle 2, Zeile 10) | 29 s | `ausgaben/gate.txt` |
| `--speichertest` | bitgleich: `0cdd15796669ff3a` (wie README 2738), Haft/Obhut `e4b73877b3e467f7`/`5d385fd960857369`, Bund `a3e921eeaffeb5bc`/`8e22519fde0bead2` | 13 s | `ausgaben/speichertest.txt` |
| `--kitest` | „Alle KI-Prüfungen bestanden“ (je Seed 15 Prüfungen, dazu 2 zur Sicherheit). 613 / 605 / 608 Anfragen in 60 Tagen | 14 s | `ausgaben/kitest.txt` |
| `--aufholtest` | nur ein Vergleich: Seed 1, Tag 200→290, stündlich 1.145 ms gegen 728 ms in Tagesschritten (1,6×), Einwohner 473 gegen 518 | 3 s | `ausgaben/aufholtest.txt` |
| `--migrationstest --git /home/user/website-` | „Alle Migrations-Prüfungen bestanden“: 324 ok, 0 FEHL (Versionen 2 bis 7 aus 39c405b, 2b821c2, 1c8d40b, 414ebab, bc7247a, ffa1d88) | 62 s | `ausgaben/migrationstest_git__home_user_website.txt` |
| `--erweiterung --git /home/user/website-` | „Alle Prüfungen zu ‚Stadt erweitern‘ bestanden“ (Seeds 1–3 je 730 Tage jeden Tag wie Version 6; ohne `--gross`) | 64 s | `ausgaben/erweiterung_git__home_user_website.txt` |
| `--autos` | „Alle Auto-Prüfungen bestanden“ (Seeds 1–3, Grundregel auf Seeds 1–12, 11 beschädigte Stände) | 237 s | `ausgaben/autos.txt` |
| `node E0/browser_rauch.cjs` (eigener Test) | Chromium 141.0.7390.37, WebGL mit ANGLE/SwiftShader. Bei 20× vergingen in 8 s 2 Spielstunden (4,6 fps, Frame Ø 30,8 ms, 19 Draw Calls, unter Last). Speichern und Neuladen ergaben denselben Tag, dieselbe Stunde und denselben Seed. 0 Seitenfehler. Die 2 Konsolenfehler sind die absichtlich abgebrochenen Anfragen an 11434 | 13,5 s | `ausgaben/browser_rauch.txt` |

Nicht ausgeführt, weil nicht verlangt: `--bau`, `--waren`, `--tech`, `--regierung`, `--kita`, `--sicherheit`, `--militaer`,
`--erweiterung --gross` und die V8-Browsersuite (`SP/v8/bau/tests/alle.sh`). Das kommt spätestens in der Regression von Etappe 1 dazu.

**Ausgangswerte für die Trainingsumgebung** (`E0/mess_durchsatz.mjs`, Seed 1, unter Last, `ausgaben/durchsatz.txt`):

| Zeitraum | Einwohner | Stundenschritt (ganze Stadt) | gewählte Aktionen je Spieltag | Schnappschuss (Export + Import im Speicher) |
|---|---|---|---|---|
| Tag 60–70 | 35 | 0,07 ms | 22 | 2,0 ms |
| Tag 200–210 | 212 | 0,27 ms | 129 | 5,7 ms |
| Tag 400–410 | 955 | 0,48 ms | 528 | 4,8 ms |
| Tag 700–710 | 1.195 | 0,64 ms | 738 | 6,4 ms |

In einer mittelgroßen Stadt schafft ein Prozess also 1.500 bis 3.600 Spielstunden pro Sekunde, noch ohne Protokollkosten. Ein Schnappschuss für
`snapshot`/`restore` kostet einige Millisekunden, er gehört deshalb an den Episodenstart und nicht in jeden Schritt.

## 5. Aufholen: 1 × 90 gegen 3 × 30 Tage – Messung und Ursache

`E0/mess_aufholen.mjs` bildet `aufholen()` der Oberfläche (12342–12376) ohne DOM nach: stündlich bis Mitternacht, dann Tagesschritte bis
zum Zieltag, dann stündlich bis zur Zielstunde, mit `kiSchalten(false)`. Start ist Tag 150; die Stadt wird bis dahin stündlich gerechnet
und über Export und Import kopiert. Ausgabe: `ausgaben/aufholen_messung.txt`.

| Seed | 1×90 (24 h stündlich + 89 Tagesschritte) | 3×30 (72 h + 87) | 90×1 (2.160 h, 0) | nur stündlich | 3×30 gegen 1×90 | Start 0 Uhr: 1×90 = 3×30 |
|---|---|---|---|---|---|---|
| 1 | 278 | 293 | 292 | 292 | +5,4 % | bitgleich (301) |
| 2 | 368 | 379 | 417 | 417 | +3,0 % | bitgleich (360) |
| 3 | 335 | 362 | 381 | 381 | +8,1 % | bitgleich (349) |
| 4 | 279 | 275 | 273 | 273 | −1,4 % | bitgleich (270) |
| 5 | 323 | 323 | 316 | 316 | 0,0 % (nicht bitgleich) | bitgleich (297) |
| 6 | 292 | 273 | 317 | 317 | −6,5 % | bitgleich (313) |
| 7 | 324 | 327 | 344 | 344 | +0,9 % | bitgleich (339) |
| 8 | 275 | 278 | 248 | 248 | +1,1 % | bitgleich (288) |
| 9 | 315 | 312 | 342 | 342 | −1,0 % | bitgleich (321) |
| 10 | 337 | 312 | 335 | 335 | −7,4 % | bitgleich (326) |

Einwohner bei Start um 13 Uhr. Im Mittel +0,2 % (−7,4 % bis +8,1 %). Bitgleich ist das Ergebnis in 0 von 10 Seeds, bei Start um
0 Uhr in 10 von 10.

Kontrollen (Seed 1):
- Rein stündlich ist 1 × 2.160 h dasselbe wie 3 × 720 h: **bitgleich**.
- 3 × 30 mit Speichern und Laden zwischen den Stücken gegen 3 × 30 ohne: **bitgleich**. Speichern ist also nicht die Ursache.
- Ein einzelner Tag ab Mitternacht (Tag 150): `tagSchritt` gegen 24 × `stunde` ist **nicht bitgleich**. Die Einwohner sind gleich (117), die
  Zufriedenheit liegt bei 53,60 gegen 53,17, es wurden 70 gegen 73 Aktionen gewählt. `S.rs` stand nach diesem Tag zufällig gleich.

**Ursache.** `tagSchritt` (5488–5541) ist eine Näherung von 24 Stundenschritten, und das mit Absicht (Annahme 43, README 3118):
- Entschieden wird nur um 7 und 18 Uhr. Ein Ereignis (`P.jetzt`) löst keine zusätzliche Entscheidung aus.
- Alle entscheiden vor den Bedürfnissen, nicht verschränkt je Person.
- Bedürfnisse und Zufriedenheit laufen in zwei Blöcken mit ±`ZUF_MAX_TAG/2`.

`aufholen()` rechnet angebrochene Tage stündlich: vom Start bis Mitternacht und von Mitternacht bis zur Zielstunde. Startet ein Stück
mitten am Tag, rechnet jedes Stück einen ganzen Tag stündlich statt im Tagesschritt. Bei 3 × 30 sind das 3 × 24 h und 87 Tagesschritte,
bei 1 × 90 nur 24 h und 89 Tagesschritte. Zwei Tage laufen also nach anderen Regeln. Die kleinen Unterschiede wachsen danach über Zuzug,
Gründungen und Pleiten zu ±8 % Einwohnern an. Das Ergebnis hängt so davon ab, wie oft Noah den Tab schließt: Bei 90 × 1 Tag ab 13 Uhr
rechnet `aufholen` sogar rein stündlich (2.160 h, 0 Tagesschritte).

**Optionen für Etappe 1 bzw. 5, noch nicht umgesetzt:**
- (A) **Exakt:** Aufholen rechnet immer mit `Sim.stunde`, also wie im laufenden Spiel. Gemessen kostet das 1,6× so viel Zeit wie heute
  (90 Tage bei rund 470 Einwohnern: 1,15 s statt 0,73 s), und 1 × 90 = 3 × 30 gilt dann bitgleich. Für die große Stadt mit etwa 5.850
  Einwohnern ist die Zeit ungemessen, das muss vor der Umstellung gemessen werden.
- (B) **Gekennzeichnete Näherung:** Tagesschritte bleiben wie heute. Die Karte „Während du weg warst“ nennt den Modus, und ein Test prüft
  die Stückelungsfestigkeit bei Grenzen um Mitternacht (dort gilt sie heute schon).
- Der Regressionstest ist in beiden Fällen derselbe: `mess_aufholen.mjs` wird zum `simtest`-Modus. Für (A) ist die Erwartung
  „bitgleich“, für (B) „bitgleich bei Grenzen um 0 Uhr, sonst gekennzeichnet“.

## 6. Umgebung (geprüft, nichts installiert)

| Punkt | Ergebnis |
|---|---|
| Rechner | 4 vCPU Intel Xeon 2,1 GHz mit AVX2 und AVX-512F, **keine GPU**, 15 GB RAM, 26 GB frei auf `/`, Ubuntu 24.04.4, glibc 2.39. Geteilt mit dem V9-Bau (Last 4,8–5,6) |
| Python | `/usr/local/bin/python3` → `/usr/bin/python3.11` (3.11.15); pip 24.0 (System, `/usr/lib/python3/dist-packages`); `venv` geht. Daneben gibt es 3.10, 3.12 und 3.13. Installiert ist nur **numpy 2.4.6**. **torch, stable-baselines3, sb3-contrib, gymnasium und playwright (Python) fehlen** |
| PyPI | erreichbar (pypi.org und files.pythonhosted.org stehen in `no_proxy`). Neueste Versionen: **sb3-contrib 2.9.0** (braucht `stable_baselines3<3.0,>=2.9.0`, Python ≥ 3.10), **stable-baselines3 2.9.0** (braucht `gymnasium<2.0,>=0.29.1`, `numpy<3.0,>=1.20`, `torch<3.0,>=2.8`, `cloudpickle`), **gymnasium 1.3.0**. Dateien: `ausgaben/umgebung_pypi.txt`, `umgebung_pakete.txt` |
| download.pytorch.org (CPU) | erreichbar. Index `whl/cpu` bis **torch 2.14.0+cpu**. Das Rad `torch-2.14.0+cpu-cp311-cp311-manylinux_2_28_x86_64.whl` antwortet per HEAD mit 200 und 196.227.330 B |
| sb3-contrib-API (im Quelltext des Rads 2.9.0 nachgesehen, `E0/pakete/sb3c`, nicht installiert) | `sb3_contrib.MaskablePPO(policy, env, learning_rate=3e-4, n_steps=2048, batch_size=64, n_epochs=10, gamma=0.99, gae_lambda=0.95, clip_range=0.2, ent_coef=0.0, …, policy_kwargs, seed, device)`; `policy="MlpPolicy"` ist `MaskableActorCriticPolicy`, Standard `net_arch=dict(pi=[64, 64], vf=[64, 64])`, `activation_fn=nn.Tanh`; `predict(observation, …, deterministic, action_masks=None)`; Maske über eine Env-Methode **`action_masks`** (`EXPECTED_METHOD_NAME`, `sb3_contrib/common/maskable/utils.py`) oder `sb3_contrib.common.wrappers.ActionMasker(env, action_mask_fn)`; `sb3_contrib.common.maskable.evaluation.evaluate_policy(model, env, n_eval_episodes=10, deterministic=True, …, use_masking=True)`; `sb3_contrib.common.maskable.callbacks.MaskableEvalCallback`. Die Teile aus SB3 selbst (`MlpExtractor`, Speichern und Laden) prüfe ich nach der Installation im Quelltext |
| Node / npm | Node v22.22.2 (`/opt/node22`), npm 10.9.7 |
| Playwright / Chromium | Node-Paket **playwright 1.56.1** global (`/opt/node22/lib/node_modules/playwright`); Browser `/opt/pw-browsers/chromium-1194` = **Chromium 141.0.7390.37**, dazu headless_shell-1194 und ffmpeg-1011. WebGL: ANGLE mit Vulkan auf SwiftShader, also reine Software-Grafik |
| Three.js lokal | `SP/three/package`, `three 0.186.0` (package.json), passt zur Import-Map |
| Ollama | **nicht installiert.** `https://ollama.com/install.sh` ist erreichbar. Es lädt `ollama-linux-amd64.tar.zst` (die `.tgz` gibt 404) und verlangt dafür `zstd`, **das fehlt** (apt-Kandidat 1.5.5, nicht installiert). Die Weiterleitung führt auf **v0.34.4**, 1.427.703.051 B, HEAD 200. Modell-Manifeste aus registry.ollama.ai: qwen2.5:0.5b 398 MB, qwen3:0.6b 523 MB, gemma3:1b 815 MB, qwen2.5:1.5b 986 MB, llama3.2:1b 1.321 MB, qwen3:1.7b 1.359 MB. Das Blob von qwen2.5:0.5b antwortet per HEAD mit 200 und 397.807.936 B. Die GitHub-API ist in dieser Sitzung gesperrt. Dateien: `ausgaben/umgebung_ollama*.txt`, `ollama_install.sh` |
| Fremde Dienste (nicht angefasst) | `python3 -m http.server 8000` (PID 7425), `python3 -m http.server 8715` (PID 4633), `node mockollama.mjs` auf 11434 (PID 7427). Der Rauchtest hat 11434 per `route.abort()` abgefangen, es ging keine Anfrage hinaus |

## 7. Vorhandene Probleme (mit Beleg)

Die Probleme sind nach Bedeutung für den Auftrag geordnet. Ich habe keines davon behoben; Etappe 0 ändert nichts.

1. **Der Zufall ist an die Entscheidung gekoppelt.** `entscheide` zieht bedingt aus `S.rs` (2178–2245), `aktKind` (2428ff.) und `aktFreunde` (2329) ebenfalls.
   Trifft die Policy die Entscheidung einer einzelnen Person, ändert sich die Folge der Zufallszahlen für alle, die danach dran sind. Ein
   Vergleich Regeln gegen Policy misst dann auch Rauschen. *Beleg:* Code; im sim-Block gibt es 54 Aufrufe von `zufall(S)` oder `zInt(S, …)`.
2. **Das Aufholen ist nicht stückelungsfest.** Gemessen in Abschnitt 5, Abweichung −7,4 % bis +8,1 % der Einwohner.
3. **Beim Ausführen wird nicht erneut geprüft.** `ausfuehren` (2252) prüft nicht; `aktKuendigen` (2309) tritt auch ohne Stelle aus und
   meldet Erfolg; `aktKind` (2424) prüft nur, ob es einen Partner gibt. Heute schützt davor nur die Maske vorher bzw. `kiEntscheidung`.
   Master-Prompt A verlangt die erneute Prüfung.
4. **Die Maske verrät mehr, als die Person weiß (indirektes Wissen).** `erlaubteAktionen` liest globale Marktdaten: `S.freieStellen`
   (2648), `besterFreierLohn` (2649), `S.freieWohnungen` (2644), `ladenFehlt`/`werkstattLohnt`/`kannGruenden` (2661). Sie liest außerdem
   **private Werte des Partners**: `P.zuf[pa] > 60` (2658), `P.unzuf[pa]` (2657), `P.haftBis[pa]` (2654). Das muss im Beobachtungsschema
   dokumentiert werden; in die Beobachtung selbst gehört davon nichts.
5. **Der Aktionskatalog hat Stellen, an denen sich die Belohnung ausnutzen lässt.** Jedes Kind bringt 383 Taler Willkommensprämie von außen
   (`R.PRAEMIE` 981, `aktKind` 2445ff.). `freunde_treffen` gibt sofort +6 Freizeit (`aktFreunde` 2325). Kündigen und wieder Stelle suchen
   lässt sich im Kreis spielen (Kündigen ab `geld ≥ 20 × tageskosten`, 2650). Beim Trennen ist die Maske weiter als die Regel (dort nur
   3 %, 2224). Das braucht Belohnungs-Audit und Fälle in Etappe 3.
6. **Herkunfts- und Einzugsmerkmale liegen im Zustand.** `einzug` bedeutet Geburt **oder Zuzug** (2439, 4311), `sparSeit` beginnt beim Zuzug
   (4311). Zugezogene haben `elternA/elternB = −1`. Die Namenslisten (1131–1143) enthalten Namen, die auf eine Herkunft schließen lassen
   (z. B. Mehmet, Yılmaz, Kowalski). Aus den Beobachtungen der Policy ausgeschlossen werden müssen deshalb: `vor`, `nach`, `weib`, `gen`,
   die Personen-ID, `elternA/B` mit ihren Gen- und Namensfeldern, `memRef`, `memGen`, `memName`, `einzug`, `sparSeit` und rohe
   Gebäude-IDs. Eine Vorlage für den Nachweis gibt es schon: Der „Namenstausch bitgleich“-Test in `--autos` lässt sich auf die Policy
   übertragen.
7. **Das Gedächtnis ist dünn.** Es hat 8 Plätze als Ringpuffer (`R.MEM` 970) mit Code, Tag, Bezug, Generation und Name (1202, 1209).
   Es wirkt nur über feste Regeln: Jobverlust in 30 Tagen zählt Geld 1,5-fach (2158); nach einer Trennung 30 Tage keine Partnersuche; nach
   einem Kind 30 Tage kein weiteres; Trauer; nach aufgegebenem Ziel −40 (2125); nach einer Pleite 180 Tage keine Gründung. Es trennt nicht
   zwischen Fakt, Vermutung und Modelltext, kennt keine Bedeutung und keine verdichtete Erfahrung.
8. **Die KI-Anfrage hat keine Versionen und keine Echtzeit-Frist.** Siehe Tabelle 2, Zeile 6. Außerdem `format: 'json'` statt eines Schemas,
   und getestet ist nur gegen einen Nachbau.
9. **Es gibt kein Transaktionsjournal.** Siehe Tabelle 2, Zeile 13.
10. **Parks haben keine Besucher, Autos springen.** Siehe Tabelle 2, Zeile 14.
11. **Browsertests liegen nicht im Repo, und STADT hat keine CI.** Siehe Tabelle 2, Zeile 11 und Abschnitt 1.
12. **Die Browser-Inferenz wird nicht über alle Browser bitgleich sein.** ECMAScript lässt `Math.tanh` und `Math.exp` von der
    Implementierung annähern. Eine Tanh-MLP im Browser rechnet deshalb nicht in jeder Engine bitgleich zu Node oder PyTorch. Für die Parität
    gilt eine Toleranz plus gleiche Aktion; für Replays in derselben Engine gilt es nicht. Wer bitgleiche Replays über Browser will, braucht
    eine eigene Aktivierung nur aus Grundrechenarten (`+ − × ÷`). *Beleg:* das ist Wissen über die Sprachspezifikation, hier nicht gemessen;
    der Paritätstest in Etappe 1 misst es.
13. **Die Generation läuft theoretisch über.** `gen` ist ein `Uint16Array` und wird mit `(gen + 1) & 0xffff` gezählt (1411). Nach 65.536
    Wiederverwendungen derselben ID gilt eine alte Anfrage wieder als gültig. Praktisch ist das unerheblich, gehört aber als Grenze in die Doku.
14. **Der Spielstand ist durch localStorage begrenzt.** Ab 4 MB warnt das Spiel (6507), der Browser speichert etwa 5 MB je Seite. Gewichte
    der Policy gehören deshalb nicht in den Spielstand, nur ein Verweis (Name, Version, Hash).
15. **Three.js kommt nur vom CDN.** Ohne Netz startet die 3D-Ansicht nicht (6566–6576), die Sim läuft trotzdem weiter. Die Tests brauchen
    deshalb die lokale Kopie über `route`.
16. **Kleinigkeiten in der Doku.** Der Kommentar in `erlaubteAktionen` (2635) nennt `simtest --ki`, der Schalter heißt `--kitest`. README 3269
    ist beim Ollama-Download überholt.

## 8. Anker für spätere Patches und ihr Stand in V9

Die Regeln für Patches am sim-Block: jede Ersetzung genau einmal, wiederholbar per Skript (Muster wie `ladeSimMit` in simtest 84–99).
**Solange die Policy aus ist, bekommt `S` keine neuen Schlüssel.** `exportZustand` nimmt alle Schlüssel mit, und der Fingerabdruck würde
sich ändern. Modellwahl und Version gehören in den `ui`-Teil des Spielstands (`uiZustand`, 6490), neben `kiModell`.

Ich habe `E0/anker_vergleich.mjs` gegen einen Schnappschuss des laufenden V9-Baus laufen lassen (`E0/v9_schnappschuss.html`, sha256
`48112fe7…`, 14:29 Uhr, VERSION 9; die Datei ändert sich noch). Ausgabe: `ausgaben/anker_v9.txt`.

| Anker (Text genau einmal vorhanden, in V8 und im V9-Schnappschuss) | V8 | V9 | Zweck |
|---|---|---|---|
| `function entscheide(S, p, h) {` + nächste Zeile `  if (S.p.haftBis[p]) return 0; …` | 2151 | vorhanden; der Rumpf ist geändert (Bürgermeister: `fest = … \|\| istBm(S, p)`), die ersten zwei Zeilen sind gleich | Policy-Haken als erste Anweisung. Deckt alle 6 Aufrufstellen ab (stündlich, Tagesschritt, Frist, KI-Rückfall) |
| `function ausfuehren(S, p, a) {` | 2252 | **gleich** | erneute Prüfung für den Policy-Pfad (Hülle, der Regelpfad bleibt unverändert) |
| `function erlaubteAktionen(S, p, h) {` | 2638 | geändert (`istBm`) | nur lesen: Maske = [WARTEN] + erlaubteAktionen |
| `G.StadtSim = {` / Zeile `  neueStadt, stunde, tagSchritt, exportZustand, importZustand, …` | 6324 / 6328 | vorhanden (7699) | Export der neuen Funktionen (`beobachtung`, `maske`, `policySetzen`) |
| `function uiZustand() { return { kiModell: ki.modell, kiMessung: ki.messung }; }` (Modul) | 6490 | vorhanden | Verweis auf die Policy im Spielstand |
| `S.ki.anfragen.length = 0;  // beim Aufholen …` (tagSchritt) | 5490 | vorhanden (V9 ergänzt danach eine Zeile) | falls das Aufholen umgestellt wird |
| unverändert in V9: `ausfuehren`, `kiFristen`, `kiEntscheidung`, `kiVerwerfen`, `erinnere`, `erinnertSeit`, `neuePerson`, `zielWaehlen`, `zielPruefen`, `zufZiel`, `exportZustand`, `menschenTag`, `aktWohnung`, `aktJob`, `aktWegziehen`, `zufall` | | | |
| geändert in V9: `entscheide`, `erlaubteAktionen`, `stunde` (`mitHaupt` statt `K.haupt.length`, Bürgermeister-Rangfolge), `tagSchritt`, `tagesabschluss`, `kiFragen` (`K.fristStunden`), `entferne`, `leererZustand`, `neueStadt`, `importZustand`, `jsonPruefen`, `personInfo`, `kennzahlen`, `zuzug`, `aktGruenden` | | | Keine Patches innerhalb dieser Rümpfe. Nur an den ersten Zeilen ansetzen oder eigene Funktionen danebenstellen |

Folgerung: Der Haken gehört an den Anfang von `entscheide`, nicht an die Aufrufzeile in `stunde`, denn diese Zeile ist in V9 anders.
Beobachtung und Maske kommen als neue Funktionen hinzu, die nur lesen. Sie hängen an `erlaubteAktionen` und an den `PF`-Feldern.
V9 fügt Personenfelder hinzu; das Beobachtungsschema braucht deshalb eine eigene Version und eine Liste der benutzten Felder.

## 9. Priorisierte Umsetzung Etappe 1–6

**Vorab und vor jedem Training festzulegen** (Master-Prompt 8, gehört in eine versionierte Datei in Etappe 1):

- **Seed-Listen:** Training ab 10000, Validierung ab 20000, Abschluss ab 30000. Die alten Seeds 1–3 (und 1–160) dienen nur der Regression.
- **Hauptmetrik (Vorschlag):** das integrierte Bedürfnisdefizit der Fokusperson je Episode. Das ist das Mittel über alle Stunden von
  100 − Zufriedenheit. Eine Episode, die durch Wegzug endet, wird nicht besser bewertet: Wer wegzieht, zählt für den Rest mit dem letzten
  Wert oder mit dem Schlechtesten.
- **Fünf Gruppen nach Ausgangslage (Vorschlag):** ohne Arbeit; erwerbstätig mit Kind; allein und mit wenig Kontakt; gründungsnah
  (Ehrgeiz ≥ 70); rentennah.
- **Freigabe:** in mindestens 3 von 5 Gruppen mindestens 10 % relative Verbesserung; harte Invarianten werden nie verletzt; die Nebenmetriken
  bleiben in der Toleranz; die Charakterwirkung bleibt erhalten (Gate 6 und 7 auf den Abschlussseeds).

**Etappe 1 – Durchstich lernende KI** (zuerst, weil sie den verbindlichen Kern trägt)

1. **Gemeinsamer Loader** `tools/simlader.mjs`: zieht den sim-Block heraus und macht dieselbe statische Prüfung und denselben vm-Kontext wie
   simtest. simtest selbst bleibt unverändert.
2. **Patch-Skript** `ml/patch/policy.mjs` mit Ersetzungen, die genau einmal treffen; ein Lauf zeigt jede Ersetzung und ihren Anker an:
   - Haken am Anfang von `entscheide`: Nur wenn ein Policy-Haken gesetzt ist **und** `p` die Fokusperson bzw. eine Person im Policy-Modus
     ist, entscheidet die Policy. Der Haken liegt als Modulvariable im sim-Block, nicht in `S`.
   - Eigener Zufallsstrom für die Fokusperson: Für ihre Entscheidung wird `S.rs` gegen einen eigenen Strom getauscht, in beiden Armen, also
     auch wenn sie nach Regeln entscheidet. Die Stadt zieht dann dieselben Zahlen wie ohne Fokus; Unterschiede entstehen nur über die Folgen.
     Der Zustand wird nur im Fokus-Modus angelegt.
   - `beobachtung(S, p, h)`: ein `Float32Array` mit versioniertem Schema, ohne die Felder aus Problem 6.
   - `maske(S, p, h)`: WARTEN plus die 12 Aktionen aus `erlaubteAktionen`, in fester Reihenfolge nach `AKTIONSNAMEN`.
   - Ausführen mit erneuter Prüfung: nur wenn die Aktion zu diesem Zeitpunkt in `erlaubteAktionen` steht. Sonst gilt sie als Ablehnung,
     wird protokolliert und bleibt ohne Wirkung.
3. **Regression:** Seeds 1–3 × 730 Tage, gepatcht mit ausgeschalteter Policy gegen 31ce452. Verglichen wird **jeden Tag** der Fingerabdruck
   (wie `spurRelativ` und `fingerabdruck` in simtest). Dazu alle Basistests aus Abschnitt 4 und der Namenstausch-Test.
4. **Node-Umgebung** `training/umgebung.mjs`, JSONL-Protokoll v1 über stdin/stdout mit den Befehlen `reset`, `observe`, `actionMask`,
   `step`, `snapshot`, `restore` und `close`. Eine Fokusperson je Episode, ausgewählt nach Seed und Ausgangslage; sie ist keine Hauptfigur
   und `ki.an = false`. Ein Schritt ist eine Spielstunde. Zu Entscheidungszeiten (7 und 18 Uhr oder nach einem Ereignis) gilt die volle
   Maske, sonst nur WARTEN. Tod, Wegzug, Zeitlimit und technischer Fehler sind getrennte Endgründe; `id` und `gen` werden geprüft.
   Den Durchsatz messen.
   Offen ist die Frage, ob Schritte, in denen nur WARTEN erlaubt ist, in Python übersprungen werden. Das Belohnungssignal wird dann über
   die übersprungenen Stunden summiert. Das ergibt dasselbe MDP mit weniger PPO-Stichproben; die Entscheidung wird begründet dokumentiert.
5. **Python:** Umgebung `training/stadt_env.py` (`gymnasium.Env` mit Methode `action_masks`), dazu `MaskablePPO("MlpPolicy")` mit dem
   Standard `net_arch` pi/vf [64, 64] und Tanh. Dazu eine Belohnung v1, dokumentiert (Abschnitt 6 des Master-Prompts), und ein Run-Manifest.
   **Nur ein Smoke-Lauf** von wenigen Minuten, getrennte Checkpoints „letzter“ und „bester“. Der Smoke-Lauf belegt keine Qualität.
   Installiert wird in einem venv unter `SP/ml/venv`: torch 2.14.0+cpu aus `download.pytorch.org/whl/cpu`, sb3-contrib 2.9.0 mit
   stable-baselines3 2.9.0 und gymnasium 1.3.0.
6. **Export** als JSON mit Gewichten, Biases, Aktivierungen, Normalisierung (nur aus Trainingsdaten), Aktionsreihenfolge, Schema-Version
   und Hash. Dazu ein Validator, der NaN, Form, Version und Hash prüft, und die Inferenz in JS (dieselbe Funktion für Node und Browser).
   **Paritätstest** auf N gespeicherten Beobachtungen: Logit-Differenz unter Toleranz und dieselbe Aktion; die Toleranz vorher festlegen
   (Problem 12).
7. **Browser-Import (minimal):** Datei importieren, prüfen, in einem eigenen localStorage-Schlüssel ablegen, im Spielstand nur den Verweis
   speichern. Fehlt die Policy oder passt sie nicht, zeigt das Spiel sichtbar „Regeln“ als Rückfall. Standard bleibt: Regeln.
   Dazu ein Rauchtest nach dem Muster von `browser_rauch.cjs`.
8. **Aufholen:** den Modus kennzeichnen (Option B) und den Regressionstest aus Abschnitt 5 als simtest-Modus aufnehmen. Die Entscheidung
   über exaktes Aufholen (Option A) fällt in Etappe 5, nach einer Messung in der großen Stadt.

**Etappe 2 – Gedächtnis, Erfahrungen, Pläne.** Strukturierte Erinnerungen in neuen typisierten Feldern (Fakt, Vermutung, Modelltext, Bedeutung,
Verweis auf das Ereignis) mit festen Grenzen und deterministischer Auswahl. Eine Erfahrungstabelle je Situation × Handlung mit Ergebnis, Zahl der
Beobachtungen und begrenzter Sicherheit, erst nach einer beobachteten Folge. Pläne mit ID, Zielbedingung, Schritten, Status, Frist und
Abbruchgrund. Ein dünnes Beziehungsnetz mit Obergrenze (heute feste 5 Freundesplätze, 1200). Alles hinter einem Schalter und bis zur Auswertung
aus, damit die Regression bitgleich bleibt. Neues Speicherformat mit Migration von V8 und V9. Tests: Gedächtnisgrenzen, Planabbruch,
ID-Wiederverwendung (`gen`).

**Etappe 3 – Belastbares Training.** Szenarien nach Lehrplan 1–6. Ein Belohnungs-Audit mit Fällen für jede Falle aus Problem 5 (Kündigen und
Wiedereinstellen, Dauerumzug, wiederholtes Gründen, Kind wegen der Prämie, leere Treffen). Invarianten als harte Fehler. Drei Trainingsseeds,
Validierung zur Kandidatenwahl, danach Abschluss auf den Seeds ab 30000 mit mindestens 20 Episoden je Gruppe, Streuung und Unsicherheit, und
ein Bericht. Nur ein lokaler Lauf von höchstens 30 Minuten pro Runde, solange der Rechner geteilt ist.

**Etappe 4 – Hauptfiguren mit echten Modellen.** Ollama v0.34.4 installieren. Dafür wird `zstd` gebraucht oder ein Entpacken in Python, das mit
Noah abzustimmen ist, weil es 1,43 GB sind. Dazu ein kleines Modell, z. B. qwen2.5:0.5b mit 398 MB; die Wahl trifft Noah (Spec Phase 4).
`format` mit JSON-Schema (in der Doku von v0.34.4 nachschlagen), Anfrage-ID, Welt- und Sitzungsversion, Person plus Generation, Ablaufzeit,
begrenzte Warteschlange. Eine Testreihe über 7 Spieltage mit Persönlichkeiten, p50/p95, Schemaerfolg, und Timeouts, ungültige, veraltete und
abgelehnte Antworten getrennt gezählt. Die Ergebnisse stehen getrennt von denen des Nachbaus.

**Etappe 5 – Stadtleben und Produktqualität.** Parkbesuche als echter Zustand (Entscheidung, Weg, Aufenthalt, Wirkung, Rückkehr) mit eigenem
Zufallsstrom. Ein Transaktionsjournal mit Flusskonten (außen, intern, Kosten, Produktion). Verkehr mit Warteschlange oder Folgeabstand, und
eine klare Aussage, ob Verkehr nur Darstellung ist oder Reisezeit kostet. Die Personenkarte mit Entscheidungsart und „Warum?“ aus belegten
Eingaben. Die KI-Werkstatt, die nur echte Prozessdaten zeigt. Die Entscheidung über exaktes Aufholen (Option A).

**Etappe 6 – Auslieferung.** Tests mit relativen Pfaden ins Repo (`stadt/tests/`, eigener Port, KI-Nachbau als Datei). Eine CI für
`simtest`, wenn Noah das will. Kurze Einstiegsdokumente: Start, Architektur, Training, Auswertung, Modellwechsel, Grenzen. Eine Demo mit
3–5 echten Bewohnergeschichten. Große Artefakte (Checkpoints, Modelle) nicht unkontrolliert in Git.

## 10. Dateien dieser Etappe

| Datei | Inhalt |
|---|---|
| `E0/BESTAND.md` | dieses Dokument |
| `E0/kopie/stadt/` | 31ce452 per `git archive` (stadt.html, README.md, tools/simtest.mjs) |
| `E0/basistests.sh` | Aufruf der sieben Basistests, zwei Ketten |
| `E0/mess_aufholen.mjs` | Messung 1×90 / 3×30 / 90×1 / stündlich, Start 13 Uhr und 0 Uhr, mit Kontrollen |
| `E0/mess_durchsatz.mjs` | Stundenschritt und Schnappschuss nach Stadtgröße |
| `E0/browser_rauch.cjs` | Rauchtest im Browser ohne Server (route), 11434 abgefangen |
| `E0/anker_vergleich.mjs`, `E0/fdiff.mjs` | Vergleich der Anker V8 gegen den V9-Schnappschuss |
| `E0/v9_schnappschuss.html` | Kopie von `SP/v9/bau/stadt.html` um 14:29 Uhr (nur gelesen, Zwischenstand) |
| `E0/pakete/` | Rad `sb3_contrib-2.9.0-py3-none-any.whl` und entpackter Quelltext (nur zum Nachsehen, nicht installiert) |
| `E0/ausgaben/` | alle Ausgaben: `gate.txt`, `speichertest.txt`, `kitest.txt`, `aufholtest.txt`, `migrationstest_git__home_user_website.txt`, `erweiterung_git__home_user_website.txt`, `autos.txt`, `status.txt`, `aufholen_messung.txt`, `durchsatz.txt`, `browser_rauch.txt`, `anker_v9.txt`, `umgebung_*.txt`, `ollama_install.sh` (nur heruntergeladen, nicht ausgeführt); `basistests.log` ist leer, weil keine Meldungen außerhalb der Einzeldateien kamen |
