# Architektur

Eine Wahrheit: der sim-Block in `stadt.html`. Spiel, Tests, Trainingsumgebung und Auswertung rechnen alle mit genau diesem Code.
Python rechnet nichts von der Stadt nach; es lernt nur.

## Die Teile

| Teil | Wo | Was es tut |
|---|---|---|
| Simulation | `stadt.html`, `<script id="sim">` → `globalThis.StadtSim` | Die ganze Stadt, stündlich und in Tagesschritten. Rein und deterministisch: kein DOM, kein `fetch`, kein `Math.random`, kein `Date` (simtest und `tools/simkern.mjs` prüfen das statisch). Zufall nur aus Strömen im Zustand `S`. |
| Darstellung und Oberfläche | `stadt.html`, `<script type="module">` | Three.js 0.186.0 per Import-Map, Karten, Fenster, Speichern im Browser, Ollama für Hauptfiguren. Liest den Zustand, ändert ihn nur über die Funktionen von `StadtSim`. |
| KI-Schnittstelle | im sim-Block, Abschnitt „KI-Policy (Etappe 1)“, nach außen `StadtSim.KI` | Beobachtung (`kiEingabe`, 57 Merkmale, Schema 2), Maske (`kiMaske` = `erlaubteAktionen` der Regeln), Prüfen und Rechnen einer Policy (`kiPolicyPruefen`, `kiPolicyHash`, `kiPolicyRechnen`), Haken in der ersten Zeile von `entscheide` und `entferne`, Fokusperson fürs Training. Der Zustand der KI (`KIP`) liegt außerhalb von `S`: Ist keine Policy an, rechnet die Stadt wie ohne diesen Abschnitt (geprüft gegen 09083f5 mit ausgeschaltetem Gedächtnis, `simtest --kipolicy`). |
| Gedächtnis, Erfahrung, Plan (Etappe 2) | im sim-Block, Abschnitt „Etappe 2“ (hinter `erinnere`), Schalter `R.GED` | Gedächtnis mit Kurz- und Langzeit, Fakt und Verweis je Erinnerung, Erfahrung je Handlung und Lage, offene Handlung, Plan, letzte Entscheidung; Summanden in `entscheide`; `Sim.warum`, Beobachter. Andockstellen unten. |
| Personenkarte, „Warum?“, Liste | `<script type="module">`, Abschnitt „Etappe 2 (Schritt 3)“ | Abschnitt „Erfahrung und Plan“ der Personenkarte (liest `Sim.gedInfo`, `Sim.warum`), Lebenslauf in Langzeit und Kurzzeit, Liste „Heute anders entschieden“ (setzt `Sim.beobachter`, sammelt je Spieltag höchstens 50 Einträge ohne Namen) |
| Policy-Wahl im Spiel | `<script type="module">`, Fenster `#ki-dialog` | Holt `ki/policies.json` und die Dateien per `fetch` (relativ), Datei-Import (Ergebnis im Fenster) und „Geladene Datei entfernen“, zeigt die Auswertung laut Datei, Verweis im Spielstand (`ui.entscheidungen`), sichtbarer Rückfall. |
| Gemeinsamer Loader | `tools/simkern.mjs` | Zieht den sim-Block aus `stadt.html`, prüft ihn statisch und führt ihn in einem leeren `vm`-Kontext aus. |
| Episoden | `tools/kiepisode.mjs` | Eine lernende Fokusperson je Episode, die übrige Stadt nach Regeln. Schritt = 1 Spielstunde; aktiv nur an Entscheidungszeitpunkten, sonst „warten“. Szenario `stabil` (Stadt nach 150–230 Tagen, 30 Tage lang), 5 Gruppen, Belohnung v1/v2, Enden (Zeitlimit, Tod, Wegzug), Invarianten, Schnappschuss. |
| Env-Server | `tools/kiumgebung.mjs` | Dauerhafter Node-Prozess, JSONL-Protokoll v1 über stdin/stdout: `hallo`, `reset`, `observe`, `actionMask`, `step`, `snapshot`, `restore`, `freigeben`, `protokoll`, `close`. |
| Trainer | `training/stadt_env.py`, `training/trainiere.py` | `gymnasium.Env` um den Node-Prozess (Normalisierung, `action_masks` für sb3-contrib). MaskablePPO mit MLP 2 × 64, Profile aus `training/konfig.json`, Seeds aus `training/seeds.json`, Validierung → `bester.zip`, dazu `letzter.zip` und `manifest.json` je Lauf. |
| Export | `training/exportiere.py`, `tools/ki_liste.mjs` | Checkpoint → `ki/policy_<name>.json` (Format 2: Gewichte als float32-Werte, Bias, Aktivierung, Normalisierung, Aktionen, Schema, Inhalts-Hash wie im JS). Liste `ki/policies.json`. |
| Parität | `training/paritaet.py`, `tools/paritaet.mjs` | Dieselben 644 Fälle durch PyTorch und durch `StadtSim.KI.policyRechnen`: Eingaben, Logits (Toleranz 1e-4), gewählte Aktion. |
| Auswertung | `tools/werte_aus.mjs`, `tools/ki_stadtwirkung.mjs`, `tools/kandidat_waehlen.mjs`, `tools/auswertung.sh` | Gepaarter Vergleich Regeln ↔ Policy auf getrennten Seeds, Stadtwirkung (Policy für alle), Kandidatenwahl; Kriterien in `training/AUSWERTUNG_V9.md`. |
| Belohnungs-Audit | `tools/ki_fallen.mjs` | Erzwungene Tricks gegen die Regeln (Kündigen im Kreis, Dauerumzug, leere Treffen, Dauer-Freinehmen …). |
| Tests | `tools/simtest.mjs` (+ `tools/simtest_alle.sh`), `tests/` | 21 Modi der Simulation (seit Version 10 mit `--gedaechtnis`) und `--kipolicy`; 32 Browser-Tests in Chromium (`berichte/etappe2/SCHRITT4.md`). |
| Messwerkzeuge Etappe 2 | `tools/gate_auswertung.mjs`, `tools/wiedergruendung.mjs`, `tools/wiedergruendung_auswertung.mjs`, `tools/gate_t_wechsel.sh` | Gates über viele Seeds zählen (Gate 7 nach Noahs Entscheidung 8), Wiedergründung nach einer Pleite, Gate T im Wechsel mit 6c1741e (`berichte/etappe2/LIESMICH.md`). |

## Datenfluss

```
Spiel (Browser)                                    Training (Node + Python)

stadt.html                                         training/trainiere.py  (MaskablePPO)
 ├ <script id="sim">  StadtSim ◄───── gleicher ────── tools/simkern.mjs ◄─ tools/kiepisode.mjs ◄─ tools/kiumgebung.mjs
 │   entscheide(): KI an? → Policy     Block                                                         ▲ JSONL (stdin/stdout)
 │                  sonst  → Regeln                                            training/stadt_env.py ┘
 └ <script type="module">                                                            │
     Zahnrad → „Entscheidungen“ ──fetch──► ki/policies.json ◄── tools/ki_liste.mjs   ▼
                                           ki/policy_*.json ◄── training/exportiere.py ◄── training/laeufe/<lauf>/bester.zip
     Spielstand: ui.entscheidungen = { art, name, hash, schema }        │
                                                                         └─► Parität (paritaet.py ↔ paritaet.mjs), Auswertung → berichte/<lauf>/
```

## Was eine Entscheidung durchläuft

1. Die Stadt ruft `entscheide(S, p, h)` für eine Person an einem Entscheidungszeitpunkt (7 und 18 Uhr, nach Ereignissen, auch beim Aufholen).
2. Erste Zeile: Ist die KI an (`KIP.an`), prüft der Haken, ob diese Person zum Trainingsbereich gehört (erwachsen, unter 67, keine
   Hauptfigur, nicht Bürgermeister, nicht in Haft). Wenn ja: Beobachtung und Maske → `kiPolicyRechnen` → größter Logit unter den
   erlaubten Aktionen. Sonst, oder bei einem Fehler, die Regeln (bei einem Fehler schaltet die Sim die Policy ab und die Oberfläche meldet es).
3. Die Regeln bewerten jede erlaubte Handlung (Lage und Charakter, Zielbonus, Gedächtnis, Zufall ±5); seit Version 10 kommen Erfahrung und
   Plan als Summanden dazu (unten). Entscheidet die Policy, wirken diese Summanden nicht, denn der Haken kehrt vorher zurück.
4. Die gewählte Aktion läuft durch `ausfuehren` wie bei den Regeln; die Policy kann nichts erzeugen oder umgehen, was die Regeln nicht
   auch dürften. `ausfuehren` merkt sich seit Version 10 die letzte Entscheidung mit ihrer Quelle und beginnt die Beobachtung der Folge,
   egal wer entschieden hat; gelernt wird also auch aus Handlungen der Policy und des Sprachmodells.
5. Im Training liefert die Umgebung statt der Policy die Aktion der Fokusperson. Die Fokusperson zieht ihren Zufall aus einem eigenen
   Strom, damit ihre Wahl den Zufall der übrigen Stadt nicht verschiebt. Die Aktion wird dort am Ende der Stunde ausgeführt, im Spiel sofort
   (bekannter Unterschied, `docs/GRENZEN.md`).

## Versionen, die zusammenpassen müssen

- `StadtSim.VERSION` (Spielstand-Version, seit Etappe 2 10) = `simVersion` in jeder Policy-Datei. Die Policy aus Etappe 1 hat 9 und wird
  deshalb abgelehnt („neu trainieren“).
- Beobachtungsschema 2, Hash `e85eca0c` (FNV-1a über Version, Merkmale, Skalen, Aktionen) = `schemaHash` in Policy und Lauf.
- Protokoll der Umgebung 1, Belohnung `belohnung_v2`, Format der Policy-Datei 2.
Ändert sich eines davon, lehnt das Spiel alte Policies mit Grund ab; neu trainieren. Schema 2 enthält weder Erfahrung noch Plan; ein Schema 3
mit diesen Merkmalen ist für Etappe 3 vorgesehen (`docs/EXPERIMENTE.md`).

## Gedächtnis, Erfahrung und Pläne (Etappe 2): wo sie andocken

Alles im sim-Block, Abschnitt „Etappe 2“, eingeschaltet mit `R.GED = 1` (Standard). Feste Plätze je Person (`PF_GED`, 10 Felder), kein
Zufall, keine Arbeit je Person und Stunde: Geschrieben wird nur bei Ereignissen, bei Handlungen und einmal in der Nacht; gewirkt wird nur als
Summand in `entscheide` und `zielWaehlen`. Keine dieser Funktionen liest Namen, Geschlecht, Herkunft, Eltern oder den Einzugstag
(`simtest --gedaechtnis` H prüft die Leseliste statisch und mit einem Namenstausch).

| Andockstelle | Was dort passiert |
|---|---|
| `erinnere(S, p, code, ref)` | Das Ereignis kommt in die Kurzzeit (Ring aus `R.MEM_KURZ = 3` Plätzen). Was dabei herausfällt und mindestens `R.MEM_SCHWELLE = 30` bedeutet (`M_BED` je Code), übernimmt `memBehalten` in die Langzeit (5 Plätze; es verdrängt den Eintrag mit der kleinsten Bedeutung − Alter × `R.MEM_VERBLASSEN`, bei Gleichstand bleibt der alte). Dazu der Fakt (`memFakt`). Ist eine Handlung offen, prüft `erfFolge`, ob das Ereignis ihre schlechte Folge ist (Pleite nach der Gründung, Stelle weg nach dem Wechsel, Trennung nach dem Zusammenziehen); dann lernt `erfLernen` und setzt den Verweis `memVon` auf die Ursache. |
| `ausfuehren(S, p, a, quelle)` | Nach jeder Handlung, egal wer entschieden hat (Regeln, Policy, Sprachmodell, Fokusperson der Trainingsumgebung): `erfHandlung` erkennt eine Umkehr (nach der Kündigung wieder Arbeit gesucht: schlecht) und merkt eine neue offene Handlung mit Frist (`offen`, `offRest`); dazu die letzte Entscheidung (`entA`, `entArt` = Quelle und „geklappt“, `entZeit`). Der Renteneintritt wird nicht gelernt, die Kündigung für die Elternzeit schon (Noahs Entscheidung 3). |
| `menschenTag(S)` | In der Nacht je lebendem Erwachsenen, in dieser Reihenfolge: `erfVerblassen` (alle `R.ERF_HALB / 15` = 12 Tage, je Person versetzt, jede Erfahrung einen Punkt zur 0 hin; bei 0 vergessen), `erfTag` (Frist abgelaufen: gute Erfahrung, wenn das Ergebnis noch besteht, sonst verworfen), `zielPruefen` (Planschritt aus dem Zustand mit `planSchrittVon`, Abbruch mit `planAbbruch`, Ende mit Grund in `planEnde`). |
| `entscheide(S, p, h, probe)` | Je geprüfter Handlung zwei Summanden: `dE` (Erfahrung der heutigen Lage × Sicherheit) und `dP` (Plan: fehlende Rücklage −`R.PLAN_BREMSE` beim Gründen, Sparen −`R.PLAN_SPAREN` beim Kündigen), beide × `R.GED_STAERKE`. Ob die Rücklage gilt, sagt `ruecklageGilt` (`R.PLAN_RUECKLAGE`). `probe` ≠ 0 wählt nur und führt nichts aus (Bit 2: ohne Erfahrung, Bit 4: ohne Plan, Bit 8: Summanden merken); das ist die Gegenprobe zu Punkt 8. Mit Beobachter rechnet dieselbe Schleife die Wahl ohne die Summanden mit („Spur“), ohne eine Zufallszahl zu ziehen. |
| `zielWaehlen`, `zielVonAussen`, `haftAntritt` | Die Gründungserfahrung zählt bei der Wahl des Ziels „eigener Laden“ mit (während der Sperre nach einer Pleite nie dieses Ziel). Ein Ziel von außen (Gespräch, Sprachmodell) beendet den alten Plan („anderes Ziel“). Der Haftantritt verwirft einen offenen Wechsel (`erfHaft`): Die Haft kostet die Stelle, nicht der Wechsel. |
| `Sim.warum(S, p, h, rs)` | Nur lesend, `S.rs` wird gesichert und zurückgesetzt. Je geprüfter Handlung Lage und Charakter (wie Version 9, mit Zielbonus), Erfahrung, Plan, Zufall und Summe; dazu die Wahl mit allem, ohne Erfahrung, ohne Plan und ohne beides, mit `art` „direkt“ oder „zufall“, und je Vergleich mit anderer Wahl dessen eigene Rechnung (`rechnung.erfahrung`, `.plan`, `.beides`: Zeilen wie `aktionen`, sonst `null`; ohne die Summanden liegen andere Handlungen vorn, darum andere Zufallszahlen). Mit `rs` (dem Zufallsstand vor der Entscheidung, den der Beobachter mitgibt) erklärt es genau diese Entscheidung, ohne `rs` eine neue Wahl ab dem jetzigen Zufallsstand. Für Kinder nur `{ kind: true }`. |
| Beobachter (`Sim.beobachter = fn`) | `fn(p, gen, tag, stunde, mit, ohne, grund, rsVor)`, nur wenn die Wahl ohne Erfahrung und Plan direkt anders wäre (gewählte oder verdrängte Handlung ist Gründen, Kündigen, Wechseln oder Zusammenziehen); `grund` ist „erfahrung“, „plan“, „erfahrung und plan“ oder „zufall“. Er liegt nicht in `S` und wird nicht gespeichert; die Oberfläche setzt ihn für die Liste. Wirft er, schaltet die Simulation ihn ab (`Sim.beobachterFehler`) und rechnet die Stunde zu Ende. Mit und ohne Beobachter rechnet die Stadt gleich (`simtest --gedaechtnis` A). Er gilt für das ganze Modul (`BEOB`), nicht je Stadt: Rechnen zwei Städte im selben Kontext, meldet er beide. Die Oberfläche rechnet nur eine Stadt und filtert nach Tag und Generation (`erfBeobachten`); ein Werkzeug mit mehreren Städten beobachtet je Kontext nur eine (oder setzt keinen). |
| `Sim.gedInfo(S, p)` | Nur Zahlen und Codes für die Karte: Erfahrung je Handlung und Lage, offene Handlung, Plan mit Hindernis und Frist, letzter Plan mit Grund, letzte Entscheidung, Gedächtnis mit Fakt und Verweis. |
| Speichern | `PF_GED` und `S.stat.ged` laufen über `exportZustand`/`importZustand` mit (Speicherformat 10). `migriereGed` übernimmt Stände bis Version 9 (Gedächtnis neu auf Kurz- und Langzeit verteilt, neue Felder leer), `gedPruefen` lehnt beschädigte Stände ab. |

Schalter in `R`: `GED` (0 = aus), `GED_STAERKE` (1,5), `PLAN_RUECKLAGE` (1 = Rücklage für jeden Gründer ab der Stufe Stadt; 0 = immer und
2 = nur nach eigener Pleite oder schlechter Gründungserfahrung sind nur für Messungen da), `ERF_HALB` (180; 0 = kein Verblassen). Dazu zwei Korrekturen aus Version 9 mit eigenem
Schalter: `OPFER_FREI` (ein Haushaltsvorstand in Haft ist kein Einbruchsopfer) und `HAFT_EROEFFNUNG` (wer in Haft ist, fängt erst nach der
Entlassung im eigenen neuen Betrieb an). Mit allen drei auf 0 rechnet die Stadt Tag für Tag wie 6c1741e, bis auf `memName` und die
Versionsnummer (`simtest --gedaechtnis` B, `berichte/etappe2/mess/schritt4/frisch2/simtest_alle/gedaechtnis.txt`).

Kosten: Je Personentag rechnete die Stadt in Schritt 1 so schnell wie 6c1741e (30,77 gegen 30,66 µs; `berichte/etappe2/SCHRITT1.md`
Abschnitt 0.5); länger rechnet sie, weil sie größer wird. Der Beobachter kostet stündlich nichts Messbares (×0,993) und beim Aufholen etwa
3–5 % (Node ×1,028, Browser ×1,054), weil die Spur dann für alle Tage mitläuft (`berichte/etappe2/SCHRITT3.md` Abschnitt 8).

