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

(noch leer: wird nach Training, Validierung und Abschluss gefüllt)
