# Auswertung Version 9: vorab festgelegt (lokaler Lauf `v9_lokal_1`)

Festgelegt am 29.09.2026 um 02:50 UTC, **bevor** der Lauf `v9_lokal_1` gestartet wurde. Teil A ändere ich danach nicht mehr. Eine eingefrorene
Kopie liegt in `training/AUSWERTUNG_V9_vorab.md`, ihr sha256 steht in `training/AUSWERTUNG_V9_vorab.sha256`. Die Ergebnisse kommen in
Teil B unter die Trennlinie. Grundlage: Master-Prompt Abschnitt 8, die Kriterien von Etappe 1 (`training/AUSWERTUNG.md`, übernommen) und
dazu Zahlen für die Toleranzen, die dort fehlten.

## Teil A – Festlegung

### A1. Stand, auf dem gemessen wird

| Was | Wert |
|---|---|
| Stadt | `stadt.html` gepatcht auf 09083f5 (Version 9), sha256 `48732527492d47f0`, sim-Block `3b1a95e0e5ae9ea5` |
| Beobachtung / Aktionen | Schema 2, 57 Merkmale, Hash `e85eca0c`; Aktionen `warten` und die 12 aus `AKTIONSNAMEN` |
| Werkzeuge (sha256, erste 16 Zeichen) | `tools/werte_aus.mjs` 76061234edf27e37, `tools/kiepisode.mjs` 9681a1e82f624a80, `tools/ki_stadtwirkung.mjs` 499f7c8dd9f939fc, `tools/kandidat_waehlen.mjs` a9cdbc4cdad02e9b, `training/trainiere.py` c6b1aabcb7af36c8, `training/seeds.json` 514fef837677192d, `training/konfig.json` cc602de64c9b92d5 |
| Änderungen an den Werkzeugen vor dem Lauf | `kiepisode.mjs` zählt jetzt nur zusätzlich mit: ausgeführte Aktionen je Art sowie Betrieb am Anfang und am Ende der Episode. Die Umgebung selbst ist unverändert: 15 Paare × 3 Arme (270 Werte) sind gleich wie vorher, und ein Smoke-Lauf ergibt dieselben Gewichte wie `smoke_v9_2` (L2 1,7266). `werte_aus.mjs`: jede Person höchstens einmal je Gruppe, t-Quantil, Nebenprüfungen wie unten. `trainiere.py`: Wandzeitgrenze `--wand-min` und Lernkurve im Manifest |

### A2. Training (ein Lauf, ein Trainingsseed)

- Profil `lokal_v9` aus `training/konfig.json`: MaskablePPO (sb3-contrib 2.9.0) mit MLP 2 × 64 und tanh, `n_steps` 1024, `batch_size` 128,
  `n_epochs` 6, Lernrate 3e-4, γ 0,99, λ 0,95, clip 0,2, `ent_coef` 0,01, Seed 1, 1 torch-Thread, Ziel 155.648 Schritte.
- **Belohnung v2**, wie es der Auftrag verlangt. Bekanntes Risiko: v2 besteht das Belohnungs-Audit auf V9 nicht (2 von 8 Prüfungen,
  `UEBERTRAG.md` 8.1). Treffen jeden Abend lohnt sich in der Gruppe `ohne_arbeit`, und leere Treffen sind in 20,5 % der Fälle netto
  positiv. Deshalb gibt es unten die Nebenprüfung „leere Treffen“. Die Belohnung ändere ich in dieser Runde nicht.
- Die Normalisierung wird neu aus 128 Regel-Episoden auf den Trainingsseeds 10000–10063 gerechnet und im Lauf gespeichert
  (`normalisierung.json`). Im Browser gilt sie identisch, das belegt die Parität der normalisierten Eingaben.
- Trainingsseeds 10000–10063. Validierung während des Trainings alle 8.192 Schritte mit 16 Episoden auf 20000–20015 (Gruppe `alle`).
  Daraus kommt der Checkpoint `bester`, getrennt von `letzter`.
- Wandzeit höchstens 30 min, gemessen vom Aufruf bis zum fertigen Manifest: `--wand-min 30`. Das Training endet spätestens 28,5 min nach
  Programmstart, 1,5 min bleiben als Reserve für die Abschlussvalidierung und das Manifest.

### A3. Daten und Vergleich

- Seeds aus `training/seeds.json` (Version 1), disjunkt: Training ab 10000, Validierung ab 20000, Abschluss ab 30000.
- **Kandidatenwahl (Validierung):** Seeds 20016–20031 (`--versatz 16`), also nicht die Seeds, mit denen das Training `bester` gewählt hat.
  32 Paare je Gruppe. Arme: `regeln`, `policy` (`bester` und `letzter`, je ein Lauf von `werte_aus.mjs`) und einmal `zufall` zur
  Plausibilität.
- **Abschluss:** Seeds 30000–30031, 32 Paare je Gruppe, **einmal**, nur für den gewählten Kandidaten und die Regeln (dazu `zufall`), ohne
  jede Änderung am Kandidaten.
- Gepaart: Beide Arme rechnen je Paar von derselben Ausgangslage (Seed, Szenario `stabil`, Start Tag 150–230 um 6 Uhr, 30 Tage) mit
  derselben Fokusperson (Auswahl nach Seed und Nummer) und demselben eigenen Zufallsstrom. Die übrige Stadt entscheidet nach Regeln.
  Jede Person (Seed, ID, Generation) zählt je Gruppe höchstens einmal.
- Fünf Gruppen, nur nach Lage und Persönlichkeit: `ohne_arbeit`, `mit_kind`, `wenig_kontakt`, `gruendungsnah`, `rentennah`.
  Mindestens 20 Paare je Gruppe, sonst gibt es kein Urteil.
- Die Policy rechnet wie im Browser (`Sim.KI.policyRechnen`, maskiert, deterministisch). Ein Fehler führt wie im Spiel zu den Regeln und
  wird als Rückfall gezählt.

### A4. Hauptmetrik und Kriterium je Gruppe

- Hauptmetrik (aus dem Prototyp): das integrierte Bedürfnisdefizit. Gemeint ist das mittlere `100 − Zufriedenheit` je Stunde der
  Fokusperson über die Episode. Nach einem Wegzug zählt jede fehlende Stunde mit 100. Kleiner ist besser.
- Gepaarte Differenz d = Regeln − Policy. Die relative Verbesserung ist Mittel(d) / Mittel(Regeln).
- Eine Gruppe **zählt als verbessert**, wenn drei Bedingungen gelten: relativ ≥ 10 %, die Untergrenze des 95-%-Intervalls von Mittel(d)
  liegt über 0 (t-Quantil mit n − 1 Freiheitsgraden) und Mittel(d) ≥ 0,5 Punkte. Die 0,5 Punkte sind die absolute Schwelle nahe null auf
  der Skala 0–100. Sie verhindern, dass ein großer Prozentwert auf winziger Basis zählt.

### A5. Harte Invarianten (nie verletzt)

In Training, Validierung und Abschluss: keine Maskenverletzung, kein Rückfall der Policy und keine verletzte Invariante der Umgebung.
Die Invarianten sind: Zahlen endlich, Arbeit, Wohnung und Partner in beide Richtungen eingetragen. Dazu besteht
`simtest --kipolicy --policy <Kandidat> --tage 120` im Spielpfad alle Prüfungen: Maske, Namenstausch bitgleich, Bürgermeister,
Hauptfiguren und Personen ab 67 nach Regeln, deterministisch, Speichern und Laden. In der Stadtwirkung (Policy für alle) gibt es 0 Rückfälle.

### A6. Nebenmetriken mit Toleranz (alle müssen gelten)

Summen über alle Paare einer Seed-Art, außer wo „je Gruppe“ steht.

| Prüfung | Toleranz |
|---|---|
| Notstand (Stunden mit Zufriedenheit unter 20, fehlende Stunden nach Wegzug mitgezählt), je Gruppe | Policy ≤ Regeln + 2 Prozentpunkte |
| Wegzüge, je Gruppe | Policy ≤ Regeln |
| Ziele erreicht | Policy ≥ 0,8 × Regeln |
| Gründungen (ausgeführte `laden_gruenden` der Fokusperson) | bei Regeln ≥ 4: Policy zwischen 0,5 × und 2 × Regeln; bei Regeln < 4: \|Policy − Regeln\| ≤ 3 |
| Fehlgründungen (in der Episode gegründet, am Ende kein Betrieb) | Policy ≤ Regeln + 2 |
| Kinder (ausgeführte `kind_bekommen`) | wie Gründungen: 0,5 × bis 2 ×, bei Regeln < 4: ±3 |
| Leere Treffen (ohne Gegenüber + ohne Bedarf, Zählung aus Belohnung v2) | Policy ≤ 1,5 × Regeln + 5 |
| Persönlichkeit (Pearson r zwischen Merkmal und Anteil passender Aktionen an allen Entscheidungen; gesellig ~ Treffen + Partnersuche, ehrgeizig ~ Wechsel + Gründung, fleißig ~ Freinehmen, Heimatliebe ~ Wegziehen, sparsam ~ Kündigen) | wo die Regeln \|r\| ≥ 0,1 zeigen: gleiches Vorzeichen und \|r\| ≥ die Hälfte des Betrags der Regeln |
| Stadtwirkung: Policy für alle im Trainingsbereich, (a) neue Stadt bis Tag 90, (b) Regeln bis Tag 200, dann 60 Tage; Summe über 4 Seeds (Validierung 20016–20019, Abschluss 30000–30003) | je (a) und (b): Einwohner ≥ 0,9 × Regeln; Kasse (`S.budget`) ≥ Regeln − 20 % des Betrags; Gründungen im Zeitraum ≥ 0,5 × Regeln |

Nur berichtet, nicht geprüft: Ablehnungen, „ohne Erfolg“, Umkehrfälle, aufgegebene Ziele, Aktionsverteilung, Bedürfnisse einzeln,
Rückgabe (Belohnung v2), Betrieb am Ende und die Kontrollmessung Herkunft (Defizit „ohne Eltern in der Stadt“ gegen „hier geboren“, nur
gemessen, die Policy sieht es nicht). Dazu kommen Laufzeit und Speicher der Auswertung. Erholung nach Jobverlust ist in dieser Runde
nicht gemessen.

### A7. Kandidatenwahl (nur Validierung, `tools/kandidat_waehlen.mjs`)

Kandidaten sind `bester` und `letzter`. Die Regeln der Reihe nach:
1. nur Kandidaten ohne verletzte harte Invariante;
2. mehr Gruppen, die als verbessert zählen;
3. mehr Nebenprüfungen in Toleranz, einschließlich der Stadtwirkung auf 20016–20019;
4. kleineres mittleres Defizit über alle 160 Paare;
5. `bester` vor `letzter`.

Beide Kandidaten müssen dieselben Paare und denselben Regelarm haben, das Skript prüft es. Die Wahl steht fest, bevor ein Abschlussseed
benutzt wird.

### A8. Urteil

- **BESTANDEN** (Freigabe als Standard möglich) nur dann, wenn auf den Abschlussseeds alles zugleich gilt: ≥ 3 von 5 Gruppen zählen als
  verbessert, keine harte Invariante verletzt, alle Nebenprüfungen in Toleranz, ≥ 20 Paare je Gruppe und **≥ 3 Trainingsläufe mit
  verschiedenen Seeds**.
- Mit einem Trainingslauf, wie in dieser Runde, heißt das beste mögliche Ergebnis **„VORLÄUFIG BESTANDEN“**. Die Regeln bleiben dann
  Standard, und die Policy bleibt „experimentell“. Für Etappe 3 braucht es drei Trainingsseeds.
- Andernfalls **NICHT BESTANDEN**. Die Regeln bleiben Standard, Pipeline, Checkpoint und Auswertung werden trotzdem geliefert.
- Ein Smoke-Lauf ist kein Qualitätsbeleg. Nach Sicht auf Ergebnisse ändere ich an diesen Kriterien nichts.

---

## Teil B – Ergebnis

Stand 29.09.2026, 03:25 UTC. Alle Zahlen stammen aus den Läufen dieser Sitzung; die Rohausgaben liegen in `ausgaben/lokal_v9/`, der Lauf in
`training/laeufe/v9_lokal_1/`. Teil A ist unverändert (gleich `AUSWERTUNG_V9_vorab.md`, sha256 `eabd58aa…`, festgelegt 02:50 UTC,
Trainingsstart 02:50:57 UTC).

### B0. Urteil

**NICHT BESTANDEN** (Abschlussseeds 30000–30031, 32 Paare je Gruppe, ein Trainingslauf). Die Hauptmetrik ist in **5 von 5 Gruppen**
um 16–31 % besser. Das Intervall liegt überall über 0, harte Invarianten sind nicht verletzt. Aber nur **16 von 26 Nebenprüfungen** liegen
in Toleranz. Durchgefallen sind:
- Ziele erreicht 60 statt ≥ 89,6
- Gründungen 2 gegen 15
- Kinder 0 gegen 5
- ein Wegzug mehr in `wenig_kontakt`
- Charakter „gesellig“ umgekehrt
- Stadtwirkung, 5 von 6 Prüfungen

Die **Regeln bleiben Standard**, die Policy `v9_lokal_1` bleibt „experimentell“. Auch mit bestandenen Nebenmetriken wäre es mit einem
Trainingsseed nur „vorläufig“ gewesen.

### B1. Der Lauf `v9_lokal_1` (Manifest `training/laeufe/v9_lokal_1/manifest.json`)

| Kennzahl | Wert |
|---|---|
| Wandzeit | **25,0 min** (1.502 s von außen gemessen, Manifest 1.499,8 s): 02:50:57–03:15:59 UTC; Grenze 30 min (`--wand-min 30`), nicht erreicht |
| Vorlauf | Normalisierung aus 128 Regel-Episoden (7.564 Beobachtungen, Seeds 10000–10063) und Regelarm auf 16 Validierungsepisoden: ≈ 100 s |
| Training | **155.648 Schritte** (Ziel erreicht; 152 Rollouts à 1.024 mit je 6 Epochen, `n_updates` 912) in 1.399 s = 111,3 Schritte/s |
| Rechner | 4 vCPU Xeon 2,1 GHz, keine GPU, 1 torch-Thread; Last beim Start 1,1, am Ende 5,5 (paralleler Agent mit Browser-Tests) |
| Stand | sim `3b1a95e0e5ae9ea5` (Version 9), stadt.html `48732527492d47f0`, Schema 2 `e85eca0c`, Protokoll 1, Belohnung v2; Code-Hashes wie in A1 (trainiere.py `c6b1aabc…`, kiepisode.mjs `9681a1e8…`) |
| Versionen | torch 2.14.0+cpu, numpy 2.4.6, gymnasium 1.3.0, stable-baselines3 2.9.0, sb3-contrib 2.9.0 |
| Normalisierung | `normalisierung.json`: konstant 5 Merkmale (`gemeinnuetzig`, `im_dienst`, `verpflichtet`, `trauer`, `ziel_wohnung`), an der Untergrenze 0,05 sechs; zahlengleich mit dem Messlauf `mess_lokal_v9` (gleiche Seeds, deterministisch); in der Policy-Datei identisch übernommen (geprüft) |
| Episoden | 2.658 (2.580 Zeitlimit, 78 Wegzug); je Episode 720 Stunden, gelebt Ø 707,4; Entscheidungen Ø 58,5 (1–69) |
| Belohnungsteile je Episode (Ø) | Zufriedenheit +20,31, Notstand −0,27, Umkehr −0,69, Wegzug −0,39, Treffen −1,09; Summe Ø 17,82 (−24,0 … 27,3) |
| Aktionsverteilung im Training | warten 83.735, freunde_treffen 34.676, freinehmen 22.246, kuendigen 3.819, job_suchen 3.777, job_wechseln 3.133, partner_suchen 2.855, laden_gruenden 434, zusammenziehen 391, kind_bekommen 317, wohnung_suchen 128, trennen 85, wegziehen 52 |
| PPO am Ende (letztes Update) | approx_kl 0,0050, clip_fraction 0,028, entropy_loss −0,535 (erstes Update −1,006), explained_variance 0,956, value_loss 1,24; ep_rew_mean 20,18, ep_len_mean 60,1 |
| Parameteränderung (L2 zum Anfang) | gesamt 14,49; Policy-Netz `policy_net.0` 3,24, `policy_net.2` 4,00, `action_net` 2,57 |
| Checkpoints | `bester.zip` sha256 `aecd97d4c6c4a087` und `letzter.zip` `8509b211c7239ae6`, beide bei 155.648 gesammelten Schritten. `bester` ist der Stand **vor** dem letzten PPO-Update (sb3-contrib ruft `on_rollout_end` vor `train()` auf, `ppo_mask.py` Z. 282/465), `letzter` der danach. L2 zum Anfang 14,48 bzw. 14,49 |

Lernkurve (Manifest `lernkurve`, je 8.192 Schritte; Validierung = 16 Episoden auf 20000–20015, Regeln dort 42,59):

| bis Schritt | Trainingsepisoden | Belohnung Ø | Defizit Ø (Training) | Wegzüge | Umkehr | Validierung Defizit (Streuung) | bester |
|---|---|---|---|---|---|---|---|
| 8.192 | 141 | 13,66 | 39,49 | 10 | 1.544 | 42,46 (24,6) | ja |
| 16.384 | 143 | 13,67 | 41,37 | 9 | 933 | 36,36 (26,7) | ja |
| 32.768 | 140 | 15,62 | 36,66 | 6 | 744 | 39,47 (21,1) | |
| 49.152 | 141 | 17,17 | 32,31 | 5 | 478 | 33,21 (20,4) | ja |
| 65.536 | 139 | 17,84 | 32,27 | 5 | 320 | 33,51 (21,5) | |
| 81.920 | 139 | 19,57 | 27,38 | 3 | 350 | 31,03 (19,0) | ja |
| 98.304 | 141 | 17,80 | 32,60 | 6 | 280 | 29,84 (18,4) | ja |
| 114.688 | 138 | 18,11 | 32,44 | 3 | 267 | 27,85 (19,7) | ja |
| 131.072 | 140 | 19,62 | 29,58 | 1 | 130 | 29,02 (19,6) | |
| 147.456 | 139 | 20,34 | 27,42 | 1 | 108 | 28,75 (19,7) | |
| 155.648 | 137 | 20,84 | 26,97 | 0 | 109 | 27,84 (20,4) | ja |

Die Umgebung ist deterministisch: Normalisierung und die ersten drei Validierungen (42,46; 36,36; 38,13) sind zahlengleich mit dem Messlauf `mess_lokal_v9`, obwohl `kiepisode.mjs` inzwischen mitzählt.

### B2. Kandidatenwahl auf Validierungsseeds 20016–20031 (`ausgaben/lokal_v9/val_*.md|json`, `kandidatenwahl.txt`)

Jeweils 160 Paare (32 je Gruppe; 7 doppelte Personen übersprungen), dieselben Paare und derselbe Regelarm für beide Kandidaten (vom Skript geprüft).

| Kandidat | Hash | Invarianten | Gruppen verbessert | Nebenprüfungen in Toleranz | Defizit Ø (160 Paare) |
|---|---|---|---|---|---|
| `bester` | `28385759bed1db02` | ok | 5/5 | 16/26 | **24,80** |
| `letzter` | `4654c8bc3689895c` | ok | 5/5 | 16/26 | 25,17 |

Regeln auf denselben Paaren: 33,46. Nach Regel A7 fällt die Wahl erst beim 4. Kriterium: **`bester`** (kleineres Defizit). Die Wahl stand um
03:18:52 UTC fest, die Abschlussseeds liefen danach (03:19:04).

Validierung `bester` je Gruppe (Regeln / Policy / Zufall, Differenz ±95 %, relativ): `ohne_arbeit` 28,7 / 22,0 / 40,4, +6,79 ± 4,90, 23,6 %;
`mit_kind` 34,8 / 27,7 / 40,1, +7,04 ± 3,80, 20,2 %; `wenig_kontakt` 40,1 / 28,0 / 57,8, +12,09 ± 6,33, 30,1 %; `gruendungsnah` 35,1 / 24,5 / 40,3,
+10,69 ± 4,00, 30,4 %; `rentennah` 28,5 / 21,8 / 28,9, +6,68 ± 2,87, 23,4 %. Durchgefallene Nebenprüfungen wie beim Abschluss (Ziele, Gründungen,
Kinder, gesellig, dazu Heimatliebe ~ Wegziehen, Stadtwirkung 5 von 6), Wegzüge in Toleranz.

### B3. Abschluss 30000–30031, einmal (`ausgaben/lokal_v9/abschluss.md|json`)

160 Paare (32 je Gruppe, keine doppelten), Arme Regeln, Policy `bester` (Hash `28385759bed1db02`) und Zufall. Laufzeit 120,9 s, CPU 124,2 s, max. RSS 185 MiB.

| Gruppe | Paare | Defizit Regeln (Streuung) | Defizit Policy (Streuung) | Zufall | Differenz R − P (Streuung; ±95 %) | relativ (95 %) | besser/schlechter | zählt |
|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | 32 | 32,8 (19,1) | 24,5 (12,4) | 34,6 | 8,26 (13,49; ±4,86) | 25,2 % (10,4 … 40,0 %) | 21/11 | ja |
| mit_kind | 32 | 38,8 (23,0) | 30,3 (23,8) | 41,3 | 8,58 (10,21; ±3,68) | 22,1 % (12,6 … 31,6 %) | 29/3 | ja |
| wenig_kontakt | 32 | 36,2 (15,9) | 25,1 (16,7) | 50,7 | 11,13 (15,92; ±5,74) | 30,7 % (14,9 … 46,6 %) | 26/6 | ja |
| gruendungsnah | 32 | 39,0 (14,1) | 27,8 (16,4) | 46,0 | 11,29 (11,54; ±4,16) | 28,9 % (18,3 … 39,6 %) | 27/5 | ja |
| rentennah | 32 | 29,3 (19,7) | 24,7 (19,5) | 34,7 | 4,64 (10,06; ±3,63) | 15,8 % (3,4 … 28,2 %) | 20/12 | ja |
| alle | 160 | 35,24 | 26,46 | – | 8,78 (12,52) | 24,9 % | 123/37 | – |

Woher die Verbesserung kommt (mittlere Bedürfnisdefizite Geld / Wohnen / Kontakt / Freizeit, Regeln → Policy): vor allem **Freizeit**
(z. B. `mit_kind` 34,5 → 15,1, `rentennah` 27,7 → 8,8) und **Kontakt** (`wenig_kontakt` 23,5 → 14,6, `gruendungsnah` 24,7 → 14,0).
Geld und Wohnen bleiben nahezu gleich, in `rentennah` wird Kontakt schlechter (15,7 → 19,4). Aktionen über alle Paare (gewählt, Regeln / Policy):
`freinehmen` 342 / 1.310, `freunde_treffen` 2.165 / 1.895, `job_suchen` 229 / 56, `kuendigen` 209 / 34, `job_wechseln` 118 / 35,
`partner_suchen` 48 / 126, `laden_gruenden` 15 / 2, `kind_bekommen` 5 / 0, `wegziehen` 2 / 0. Umkehrfälle 467 / 37.

Harte Invarianten: Maskenverletzungen 0, Rückfälle 0, keine Invariante der Umgebung verletzt (Training: 0, Validierung: 0, Abschluss: 0);
`simtest --kipolicy --policy ki/policy_v9_lokal_1.json --tage 120` 27 von 27 (A5, Abschnitt B6).

Nebenprüfungen (A6), Abschluss:

| Prüfung | Regeln | Policy | Toleranz | in Toleranz |
|---|---|---|---|---|
| Notstand je Gruppe (ohne_arbeit / mit_kind / wenig_kontakt / gruendungsnah / rentennah) | 1,9 / 6,7 / 0,7 / 0,2 / 3,1 % | 0,9 / 3,4 / 2,1 / 1,3 / 3,6 % | ≤ Regeln + 2 pp | ja (5/5) |
| Wegzüge je Gruppe | 1 / 1 / 0 / 0 / 1 | 1 / 0 / **1** / 0 / 0 | ≤ Regeln | **nein** (`wenig_kontakt`) |
| Ziele erreicht | 112 | **60** | ≥ 89,6 | **nein** |
| Gründungen | 15 | **2** | 7,5 … 30 | **nein** |
| Fehlgründungen | 0 | 0 | ≤ 2 | ja |
| Kinder | 5 | **0** | 2,5 … 10 | **nein** |
| Leere Treffen (ohne Gegenüber + ohne Bedarf) | 409 (5 + 404) | 217 (22 + 195) | ≤ 618,5 | ja |
| Charakter (5 Paare) | siehe B4 | | | **nein** (gesellig) |
| Stadtwirkung (6 Prüfungen) | siehe B5 | | | **nein** (5 von 6) |

Die leeren Treffen liegen insgesamt unter den Regeln. Treffen **ohne Gegenüber** macht die Policy aber öfter: 22 gegen 5 im Abschluss,
51 gegen 36 in der Validierung. Genau diese Lücke hatte das Belohnungs-Audit von v2 auf V9 gezeigt (`UEBERTRAG.md` 8.1).

Kontrollmessung Herkunft (nur gemessen): Die Gruppe „ohne Eltern in der Stadt“ hat 159 Paare, Defizit Regeln 35,2, Policy 26,3. „In der
Stadt geboren“ gibt es nur 1 Paar (47,0 / 47,0), zu wenig für eine Aussage.

### B4. Charakter: Persönlichkeitskorrelationen (Pearson r, alle 160 Episoden)

| Merkmal ~ Aktionen | Regeln (Validierung / Abschluss) | Policy `bester` (Validierung / Abschluss) | Zufall (Abschluss) |
|---|---|---|---|
| gesellig ~ Treffen + Partnersuche | +0,24 / **+0,32** | −0,10 / **−0,11** | +0,05 |
| ehrgeizig ~ Wechsel + Gründung | +0,07 / +0,01 | −0,06 / −0,03 | −0,24 |
| fleißig ~ Freinehmen | +0,05 / −0,04 | −0,08 / −0,12 | −0,14 |
| Heimatliebe ~ Wegziehen | −0,16 / −0,04 | 0,00 / 0,00 (wegziehen nie) | −0,01 |
| sparsam ~ Kündigen | −0,11 / −0,08 | −0,10 / +0,06 | +0,17 |

Wie im Prototyp **kehrt sich „gesellig“ um**: gesellige Bewohner treffen sich unter der Policy anteilig nicht mehr öfter als andere.
Im Prototyp war es +0,28 zu −0,22, auf V9 ist es +0,32 zu −0,11. Die übrigen Paare zeigen bei den Regeln im Abschluss |r| < 0,1 und sind
dort frei.

### B5. Stadtwirkung: Policy für alle im Trainingsbereich (`ausgaben/lokal_v9/abschluss_stadt.*`, `val_stadt_*.*`)

Summen über 4 Seeds, Regeln → Policy. Rückfälle der Policy: 0.

| Teil | Seeds | Einwohner | Kasse (Taler) | Gründungen im Zeitraum | Zufriedenheit Ø |
|---|---|---|---|---|---|
| (a) neue Stadt, Tag 90 | Abschluss 30000–30003 | 471 → **203** (−57 %) | 212.050 → **112.491** (−47 %) | 108 → **14** | 61,0 → 73,4 |
| (b) Tag 200 + 60 Tage | Abschluss 30000–30003 | 3.197 → **2.412** (−25 %) | 2.017.316 → 2.060.096 (+2 %) | 224 → **4** | 69,7 → 82,1 |
| (a) neue Stadt, Tag 90 | Validierung 20016–20019 | 471 → 130 | 176.182 → 89.833 | 102 → 3 | 60,3 → 72,3 |
| (b) Tag 200 + 60 Tage | Validierung 20016–20019 | 2.877 → 2.320 | 1.998.318 → 2.077.713 | 276 → 6 | 69,6 → 81,6 |

Je Seed im Abschluss (Einwohner Regeln/Policy): (a) 127/53, 128/53, 107/45, 109/52; (b) ab 503/470/374/442 Einwohnern 884/668, 816/626,
728/528, 769/590. Die Bewohner sind mit der Policy zufriedener, aber die Stadt wächst deutlich langsamer. Es gibt kaum Gründungen, in (b)
292 Geburten weniger in den 60 Tagen (kumuliert seit Tag 0: 324 gegen 616), und in der neuen Stadt ist die Kasse kleiner. Von den 6 Prüfungen besteht nur „Kasse (b)“.

### B6. Export, Parität, Spielpfad

- `ki/policy_v9_lokal_1.json`: **106.880 Byte**, Format `stadt-policy` 2, `simVersion` 9, Schema `e85eca0c`, Status `experimentell`,
  Hash `28385759bed1db02`. Das ist derselbe Hash und dasselbe Netz wie der ausgewertete Kandidat
  (`training/laeufe/v9_lokal_1/export/policy_v9_lokal_1_bester.json`, geprüft). Herkunft: Lauf `v9_lokal_1`, `bester.zip` (sha256 `aecd97d4c6c4a087`),
  155.648 Schritte, Belohnung v2.
- Die Normalisierung in der Datei ist identisch mit `normalisierung.json` des Laufs.
- **Parität** Trainer ↔ JS (`ausgaben/lokal_v9/paritaet.txt`), 644 Fälle (240 echt, 150 künstlich, 10 nur warten, 244 Randfälle):
  - normalisierte Eingaben Abweichung 0
  - Logits höchstens 9,58e-7 (Toleranz 1e-4)
  - Aktion 644/644 gleich, 0 Gleichstände
  - `tanhK` ≤ 3,33e-16
- `ki/policies.json` neu geschrieben (`tools/ki_liste.mjs`). Sie nennt jetzt `policy_smoke_v9_2_bester.json` und `policy_v9_lokal_1.json`, beide
  angenommen. An erster Stelle steht weiter die Smoke-Policy, auf die sich `tools/browser_ki.cjs` stützt.
- `simtest --kipolicy --policy ki/policy_v9_lokal_1.json --tage 120` besteht **27 von 27** Prüfungen (25 s), darunter:
  - Namenstausch mit Policy für alle bitgleich, auch in der gewachsenen Stadt mit 104.278 Policy-Entscheidungen
  - Maske nie verletzt
  - deterministisch
- Nebenbefund aus `simtest --kipolicy`: Neue Stadt mit Policy für alle hat an Tag 120 nur 32 Einwohner, mit Regeln 170.

### B7. Einordnung (gemessen) und Grenzen

- Die Policy lernt, was Belohnung v2 belohnt, also die eigene Zufriedenheit. Sie nimmt viel öfter frei, kündigt und wechselt kaum und
  vermeidet Umkehr. Das senkt das Defizit der Fokusperson auf getrennten Seeds deutlich und stabil (Validierung 25,9 %, Abschluss 24,9 %
  über alle Paare).
- Gründen, Kinder und Wegziehen wählt sie fast nie. Dazu erreicht sie weniger Ziele, und „gesellig“ wirkt nicht mehr. Für alle
  eingeschaltet bremst sie das Wachstum der Stadt. Das ist dasselbe Muster wie beim Prototyp auf V8 mit Belohnung v1; der Abzug für leere
  Treffen in v2 hat daran nichts geändert.
- Das sind Befunde. Eine Ursache ist nicht getrennt gemessen, etwa dass die Belohnung Gründen, Kinder und Stadtwirkung nicht abbildet.
  Vorschläge für Etappe 3, ungeprüft:
  - Belohnung v3 auf V9 kalibrieren (Audit 8.1)
  - Stadtwirkung als Nebenbedingung
  - Lehrplanstufe 6 mit vielen Policy-Personen
  - Charakter-Regularisierung
  - drei Trainingsseeds
- Grenzen dieser Runde:
  - ein Trainingsseed, keine Streuung zwischen Läufen
  - nur Szenario `stabil` (Tag 150–230, 30 Tage)
  - Konfidenzintervalle mit Normal- bzw. t-Näherung
  - Stadtwirkung nur 4 Seeds je Art und nur die Policy für alle
  - Erholung nach Jobverlust, Gedächtnis/Planung und Ollama-Kombination nicht gemessen
  - `letzter` wurde im Training nicht validiert: Die Abschlussvalidierung in `trainiere.py` prüft nur die Schrittzahl, und `bester` hatte
    dieselbe. In der Kandidatenwahl habe ich beide auf 20016–20031 verglichen.
  - Im Repo ist nichts geändert.

### B8. Befehle (aus `SP/ml/v9`)

```bash
../venv/bin/python training/trainiere.py --profil lokal_v9 --name v9_lokal_1 --wand-min 30     # Log: ausgaben/lokal_v9/training.log
bash tools/v9_lokal_auswertung.sh validierung       # Export bester/letzter, Stadtwirkung 20016–20019, werte_aus 20016–20031, Kandidatenwahl
bash tools/v9_lokal_auswertung.sh abschluss bester  # einmal: Stadtwirkung 30000–30003, werte_aus 30000–30031 (--abschluss-freigegeben)
bash tools/v9_lokal_auswertung.sh export bester     # ki/policy_v9_lokal_1.json, Parität, ki_liste, simtest --kipolicy
```

### B9. Ablage im Repo (Nachtrag beim Einräumen, 29.09.2026)

Die Befehle in B8 liefen im Arbeitsordner. Im Repo liegen die Rohausgaben aus `ausgaben/lokal_v9/` und Manifest, Normalisierung und
Validierung aus `training/laeufe/v9_lokal_1/` in `berichte/v9_lokal_1/`; die Checkpoints (`bester.zip`, `letzter.zip`) und die Paritätsdaten
(1,5 MB) nicht. `tools/v9_lokal_auswertung.sh` heißt hier allgemein `tools/auswertung.sh <schritt> <lauf> [k]` und schreibt nach
`berichte/<lauf>/`. `UEBERTRAG.md` liegt in `berichte/v9_uebertrag/`. In `ki/policy_v9_lokal_1.json` stehen seit dem Einräumen das Urteil
(`auswertung`) und ein neuer `hinweis`; Netz, Normalisierung und Inhalts-Hash `28385759bed1db02` sind unverändert. Teil A und die Zahlen
oben sind nicht geändert.

Beim Einräumen gefunden und behoben: Endet eine Episode schon im `reset` (die Fokusperson zieht vor ihrer ersten Entscheidung weg, z. B.
Seed 10023, `nr` 1151 in der Normalisierung des Profils `langlauf`), brach die Python-Seite mit „step: Episode ist vorbei“ ab. Jetzt nimmt
`training/stadt_env.py` beim Training die nächste Episode, und `trainiere.py` (Normalisierung, Validierung), `paritaet.py` und `durchsatz.py`
zählen sie als beendete Episode ohne Schritt, wie `tools/werte_aus.mjs` schon vorher. Die Code-Hashes in A1 und im Manifest von
`v9_lokal_1` gelten für den Stand davor. Im Lauf `v9_lokal_1` kam der Fall nicht vor (sonst wäre er abgebrochen); mit dem neuen Code ergibt
der Smoke-Lauf dieselben Gewichte und die Normalisierung von `lokal_v9` dieselben Bytes wie vorher.

### B10. Nachtrag nach der unabhängigen Prüfung (29.09.2026)

Teil A und die Zahlen in B0–B8 sind nicht geändert. Geändert hat sich nur, was um die Auswertung herum liegt:

- **Belohnungs-Audit:** Die Prüfung fand einen Trick, den das Audit nicht kannte: jeden Morgen freinehmen, sonst Regeln. Er schlägt in der
  Gruppe `alle` die Regeln (Rückgabe 17,23 gegen 17,00, Geldbedarf 34,1 gegen 20,0). `tools/ki_fallen.mjs` prüft ihn jetzt mit
  (`frei_sonst_regel`, `frei_sonst_warten`); Belohnung v2 besteht damit 5 statt 6 von 8 Prüfungen
  (`berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt`). Das passt zum gemessenen Hauptmuster der Policy (freinehmen 1.310 gegen 342).
- **`ki/policy_v9_lokal_1.json`:** neuer `hinweis` mit der gemessenen Stadtwirkung (neue Stadt an Tag 90: 45–53 statt 107–128 Einwohner, aus
  B5); das Spiel zeigt ihn samt `auswertung.urteil` im Fenster. Netz, Normalisierung und Inhalts-Hash `28385759bed1db02` sind unverändert.
- **Stoppen und Manifest (`trainiere.py`), Export (`exportiere.py`):** Strg+C beim Fortsetzen ließ das Manifest auf einem alten Stand, und der
  Export übernahm die Schritte daraus. Jetzt stoppt Strg+C/SIGTERM geordnet, das Manifest wird nach jedem Rollout geschrieben, und der Export
  nimmt die Schritte aus dem Checkpoint. Ein neuer Export von `bester.zip` des Laufs `v9_lokal_1` mit dem neuen Code ergibt bis auf `hinweis`
  und `auswertung` dieselbe Datei (gleicher Inhalts-Hash, gleiche Herkunft mit 155.648 Schritten). Das Rechnen des Trainings ist gleich
  (Smoke-Lauf: dieselben Validierungen und L2 1,7266).
- **`stadt.html`:** Nur die Oberfläche im `<script type="module">` und im Fenster „Entscheidungen der Bewohner“ ist geändert (Rückmeldung beim
  Datei-Import, „Geladene Datei entfernen“, Auswertung laut Datei, Texte, Kommentare). Die Datei hat deshalb eine neue sha256 (`0b453bf1…`
  statt `48732527…` in A1); der sim-Block, auf dem trainiert und ausgewertet wurde, ist bytegleich (`3b1a95e0e5ae9ea5`).
