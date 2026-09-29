# Architektur

Eine Wahrheit: der sim-Block in `stadt.html`. Spiel, Tests, Trainingsumgebung und Auswertung rechnen alle mit genau diesem Code.
Python rechnet nichts von der Stadt nach; es lernt nur.

## Die Teile

| Teil | Wo | Was es tut |
|---|---|---|
| Simulation | `stadt.html`, `<script id="sim">` → `globalThis.StadtSim` | Die ganze Stadt, stündlich und in Tagesschritten. Rein und deterministisch: kein DOM, kein `fetch`, kein `Math.random`, kein `Date` (simtest und `tools/simkern.mjs` prüfen das statisch). Zufall nur aus Strömen im Zustand `S`. |
| Darstellung und Oberfläche | `stadt.html`, `<script type="module">` | Three.js 0.186.0 per Import-Map, Karten, Fenster, Speichern im Browser, Ollama für Hauptfiguren. Liest den Zustand, ändert ihn nur über die Funktionen von `StadtSim`. |
| KI-Schnittstelle | im sim-Block, Abschnitt „KI-Policy (Etappe 1)“, nach außen `StadtSim.KI` | Beobachtung (`kiEingabe`, 57 Merkmale, Schema 2), Maske (`kiMaske` = `erlaubteAktionen` der Regeln), Prüfen und Rechnen einer Policy (`kiPolicyPruefen`, `kiPolicyHash`, `kiPolicyRechnen`), Haken in der ersten Zeile von `entscheide` und `entferne`, Fokusperson fürs Training. Der Zustand der KI (`KIP`) liegt außerhalb von `S`: Ist keine Policy an, läuft die Stadt bitgleich wie Version 9 ohne diesen Abschnitt. |
| Policy-Wahl im Spiel | `<script type="module">`, Fenster `#ki-dialog` | Holt `ki/policies.json` und die Dateien per `fetch` (relativ), Datei-Import (Ergebnis im Fenster) und „Geladene Datei entfernen“, zeigt die Auswertung laut Datei, Verweis im Spielstand (`ui.entscheidungen`), sichtbarer Rückfall. |
| Gemeinsamer Loader | `tools/simkern.mjs` | Zieht den sim-Block aus `stadt.html`, prüft ihn statisch und führt ihn in einem leeren `vm`-Kontext aus. |
| Episoden | `tools/kiepisode.mjs` | Eine lernende Fokusperson je Episode, die übrige Stadt nach Regeln. Schritt = 1 Spielstunde; aktiv nur an Entscheidungszeitpunkten, sonst „warten“. Szenario `stabil` (Stadt nach 150–230 Tagen, 30 Tage lang), 5 Gruppen, Belohnung v1/v2, Enden (Zeitlimit, Tod, Wegzug), Invarianten, Schnappschuss. |
| Env-Server | `tools/kiumgebung.mjs` | Dauerhafter Node-Prozess, JSONL-Protokoll v1 über stdin/stdout: `hallo`, `reset`, `observe`, `actionMask`, `step`, `snapshot`, `restore`, `freigeben`, `protokoll`, `close`. |
| Trainer | `training/stadt_env.py`, `training/trainiere.py` | `gymnasium.Env` um den Node-Prozess (Normalisierung, `action_masks` für sb3-contrib). MaskablePPO mit MLP 2 × 64, Profile aus `training/konfig.json`, Seeds aus `training/seeds.json`, Validierung → `bester.zip`, dazu `letzter.zip` und `manifest.json` je Lauf. |
| Export | `training/exportiere.py`, `tools/ki_liste.mjs` | Checkpoint → `ki/policy_<name>.json` (Format 2: Gewichte als float32-Werte, Bias, Aktivierung, Normalisierung, Aktionen, Schema, Inhalts-Hash wie im JS). Liste `ki/policies.json`. |
| Parität | `training/paritaet.py`, `tools/paritaet.mjs` | Dieselben 644 Fälle durch PyTorch und durch `StadtSim.KI.policyRechnen`: Eingaben, Logits (Toleranz 1e-4), gewählte Aktion. |
| Auswertung | `tools/werte_aus.mjs`, `tools/ki_stadtwirkung.mjs`, `tools/kandidat_waehlen.mjs`, `tools/auswertung.sh` | Gepaarter Vergleich Regeln ↔ Policy auf getrennten Seeds, Stadtwirkung (Policy für alle), Kandidatenwahl; Kriterien in `training/AUSWERTUNG_V9.md`. |
| Belohnungs-Audit | `tools/ki_fallen.mjs` | Erzwungene Tricks gegen die Regeln (Kündigen im Kreis, Dauerumzug, leere Treffen, Dauer-Freinehmen …). |
| Tests | `tools/simtest.mjs` (+ `tools/simtest_alle.sh`), `tests/` | 20 Modi der Simulation und `--kipolicy`; 30 Browser-Tests in Chromium. |

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
3. Die gewählte Aktion läuft durch `ausfuehren` wie bei den Regeln; die Policy kann nichts erzeugen oder umgehen, was die Regeln nicht
   auch dürften.
4. Im Training liefert die Umgebung statt der Policy die Aktion der Fokusperson. Die Fokusperson zieht ihren Zufall aus einem eigenen
   Strom, damit ihre Wahl den Zufall der übrigen Stadt nicht verschiebt. Die Aktion wird dort am Ende der Stunde ausgeführt, im Spiel sofort
   (bekannter Unterschied, `docs/GRENZEN.md`).

## Versionen, die zusammenpassen müssen

- `StadtSim.VERSION` (Spielstand-Version, 9) = `simVersion` in jeder Policy-Datei.
- Beobachtungsschema 2, Hash `e85eca0c` (FNV-1a über Version, Merkmale, Skalen, Aktionen) = `schemaHash` in Policy und Lauf.
- Protokoll der Umgebung 1, Belohnung `belohnung_v2`, Format der Policy-Datei 2.
Ändert sich eines davon, lehnt das Spiel alte Policies mit Grund ab; neu trainieren.
