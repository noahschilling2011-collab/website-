# Start

## Spiel starten

```bash
cd stadt
python3 -m http.server 8000 --bind 127.0.0.1      # nur auf diesem Rechner erreichbar (ohne --bind: im ganzen Netz)
```

Dann `http://localhost:8000/stadt.html` öffnen. Immer Port 8000 und `localhost`: Der Spielstand hängt an der Adresse. Per Doppelklick
(`file://`) lädt Three.js nicht, und der Ordner `ki/` ist dann auch nicht lesbar. Mehr Schalter (`?neu`, `?seed=7`, `?debug`) stehen im
README unter „Starten“.

Das Spiel ist eine einzige Datei ohne Installation. Python braucht es nur für den kleinen Server; Node, Python-Pakete und Playwright
brauchst du nur fürs Training und die Tests.

## Ollama (optional)

Ohne Ollama läuft alles; die Hauptfiguren und der Bürgermeister entscheiden dann mit den Regeln, oben rechts steht „KI nicht erreichbar“.
Mit Ollama: installieren, `ollama serve` (oder die App), `ollama pull <modell>`, Seite neu laden. Das Spiel fragt
`http://localhost:11434/api/tags` und nimmt das erste Modell; wechseln im Zahnrad unter „KI für die Hauptfiguren“. Einzelheiten im README
unter „Ollama für die Hauptfiguren“. Gegen ein echtes Sprachmodell ist das noch nicht getestet, nur gegen einen Nachbau.

## Erfahrung und Pläne der Bewohner ansehen (seit Version 10)

Die Bewohner lernen aus den Folgen ihrer Entscheidungen (README, Abschnitt „Gedächtnis, Erfahrung und Pläne (Etappe 2)“). So sieht man es
(die Beispiele stammen aus dem Browser-Test, `berichte/etappe2/SCHRITT3.md` Abschnitte 2–4 und 6):

1. **Personenkarte:** eine Figur in der Stadt oder einen Namen im Stadtbuch anklicken. Bei Erwachsenen steht vor dem Lebenslauf der Abschnitt
   **„Erfahrung und Plan“**:
   - *Plan:* Ziel, Schritt („Schritt 1 von 2: Rücklage ansparen“), Hindernis (z. B. „spart: 1.448 von 1.700 Talern“ oder „wartet nach der
     Pleite bis Tag 461“) und Frist; darunter der *letzte Plan* und warum er endete.
   - *Erfahrung:* je Handlung ein Satz, z. B. „Gründen: 1-mal, Pleite nach 39 Tagen (Tag 163) → zählt −9,75 (wenn das Geld reicht – so ist
     es gerade)“. Die Zahl ist genau der Summand, den die Regeln dazurechnen.
   - *Offene Folge:* welche Handlung gerade beobachtet wird und wie lange noch.
   - *Letzte Entscheidung, etwas zu tun:* Tag, Uhrzeit, Handlung, wer entschieden hat (Regeln, Policy oder Sprachmodell) und ob es geklappt
     hat. „Nichts tun“ steht dort nie.
   - Der *Lebenslauf* ist geteilt in „Bleibt im Gedächtnis (Langzeit)“ und „Zuletzt erlebt (Kurzzeit, die letzten 3)“; unter einer
     Erinnerung stehen leise Fakt und Ursache („bestand 39 Tage · weil: Gründung vor 39 Tagen“).
2. **„Warum?“** (Knopf unter „Erfahrung und Plan“) klappt die Rechnung auf: je Handlung die Summe und ihre Teile („Lage und Charakter +71 ·
   Plan −45 · Erfahrung −9,75 · Zufall –“), die Wahl, und z. B. „Ohne diese Erfahrung hätte Anna einen Betrieb gegründet (in dieser Rechnung:
   einen Betrieb gründen: Lage und Charakter +71 · Plan −45 · Zufall +0,4 = +26,4)“. Die Klammer ist die Rechnung dieses Vergleichs: Ohne
   Erfahrung liegen andere Handlungen vorn, darum wird dort eine eigene Zufallszahl gezogen. Steht die Person
   heute oder gestern in der Liste (Punkt 3), erklärt der Knopf genau diese Entscheidung; sonst, was die Regeln jetzt mit einer neuen
   Zufallszahl wählen würden. Was gilt, steht neben dem Knopf. Kinder entscheiden noch nicht und haben den Abschnitt nicht; bei Menschen in
   Haft steht statt der Rechnung ein Satz.
3. **Liste „Heute anders entschieden“:** Knopf im Kopf des Stadtbuchs rechts (Weichen-Symbol, die Zahl von heute, „anders“; am Handy nur
   Symbol und Zahl, die Hilfe erklärt ihn dort; am Handy quer in der Zeile der Hauptfiguren). Die Liste zeigt die Entscheidungen von heute und
   vom Vortag, die ohne Erfahrung und Plan anders ausgefallen wären und an denen Gründen, Kündigen, Stelle wechseln oder Zusammenziehen beteiligt
   ist (etwa 9 von 10 solcher Entscheidungen): Uhrzeit, Name, Grund (Erfahrung, Plan oder beides), „statt „einen Betrieb gründen“ → „nichts
   tun““, die Summanden und ein eigenes „Warum?“. Ein Klick auf den Namen öffnet die Personenkarte, „‹ zurück“ führt zur Liste. Höchstens 50
   Einträge je Tag, neueste oben, nur nach der Uhrzeit geordnet. Sie lebt nur im offenen Fenster: Neuladen der Seite, eine neue Stadt, Laden und
   „Stadt übernehmen“ leeren sie, und sie sagt dann, seit wann sie zählt. Läuft die Zeit, bleibt der Eintrag, den du liest, an seiner Stelle. In Seed 1 kamen zwischen Tag 250 und 400 im Mittel 14,8
   Einträge am Tag dazu, höchstens 52 (`berichte/etappe2/mess/schritt3b/faelle.txt`).
4. **Tastatur:** Tab erreicht den Knopf im Stadtbuch, Enter öffnet die Liste, Tab und Enter öffnen Namen und „Warum?“, Escape schließt.

Die Werte dahinter (wie viel eine Pleite zählt, wie lange eine Erfahrung hält) sind Annahmen der Stadt, keine Messung an echten Menschen; das
steht auch in der Karte (`docs/GRENZEN.md`). Geprüft im Browser von `tests/gedaechtnis.cjs` an einem echten Fall (Seed 1, Tag 370:
`bash tests/alle.sh gedaechtnis`, 17 Prüfungen; `berichte/etappe2/mess/fix/frisch/browser/logs/gedaechtnis.log`).

## Entscheidungen der Bewohner: Regeln oder trainierte Policy

Standard sind die **Regeln**. Die trainierte Policy ist experimentell (Auswertung nicht bestanden, `docs/GRENZEN.md`).

**Seit Version 10 gibt es keine gültige trainierte Policy:** `v9_lokal_1` ist auf Stadt-Version 9 trainiert und wird abgelehnt (Noahs
Entscheidung 5). Wählt man im Fenster „Trainierte Policy (experimentell)“, steht dort „Abgelehnt: ki/policy_v9_lokal_1.json: Policy
ungültig: trainiert auf Stadt-Version 9, diese Stadt ist Version 10 (neu trainieren)“, und es entscheiden weiter die Regeln
(`berichte/etappe2/SCHRITT2.md` Abschnitt 7). Dasselbe gilt für einen alten Spielstand, der diese Policy gewählt hatte. Die Schritte unten
gelten wieder, sobald eine Policy für Version 10 trainiert ist (`docs/EXPERIMENTE.md`); die Beispiele darin stammen aus Version 9.

1. Zahnrad unten rechts → unten der Knopf **„Entscheidungen: Regeln ›“**. Es öffnet sich das Fenster „Entscheidungen der Bewohner“.
2. **„Trainierte Policy (experimentell)“** wählen. Das Spiel holt jetzt `ki/policies.json` und die Policy-Dateien daneben, prüft sie und
   nimmt die erste passende. Unter „Policy“ steht dann `v9_lokal_1 (experimentell)`, darüber der Stand („Es entscheidet die Policy …“ mit
   Herkunft, Trainingsschritten und Zählern), darunter „Auswertung laut Datei: nicht bestanden“ und was die Messung ergab.
3. Fenster schließen. Der Knopf heißt jetzt „Entscheidungen: Policy ›“.
4. Zurück: im selben Fenster „Regeln (Standard)“.

Was dabei gilt:
- Die Policy entscheidet nur für Erwachsene unter 67, die keine Hauptfigur und nicht Bürgermeister sind, an ihren normalen
  Entscheidungszeitpunkten (7 und 18 Uhr, nach Ereignissen, auch beim Aufholen). Alles andere bleibt bei den Regeln.
- **Sie verändert die ganze Stadt.** Mit `v9_lokal_1` für alle (auf Version 9) wuchs eine neue Stadt in der Auswertung deutlich langsamer: an Tag 90 45–53
  statt 107–128 Einwohner (4 Seeds, `berichte/v9_lokal_1/abschluss_stadt.txt`), mit weniger Gründungen und Geburten.
- Im Spielstand steht nur ein Verweis (Name, Hash, Schema). Beim nächsten Start holt das Spiel dieselbe Policy (gleicher Hash) wieder aus
  `ki/`, bevor die Stadt weiterläuft. Fehlt sie oder passt sie nicht, entscheiden die Regeln, und eine Meldung sagt warum. Danach speichert
  das Spiel die Regeln als Wahl: Liegt die Policy später wieder in `ki/`, sie im Fenster neu wählen (von selbst schaltet das Spiel nicht zurück).
  Ein übernommener oder importierter Stand der Version 9 mit Policy bekommt stattdessen „stammt aus Version 9 und gilt in Version 10 nicht mehr
  (neu trainieren)“: Neu wählen hilft dann nicht, erst eine auf Version 10 trainierte Policy.
- Eine andere Policy-Datei: im Fenster „Policy-Datei laden …“. Ob sie angenommen oder mit welchem Grund sie abgelehnt wurde, steht oben im
  Fenster. Sie bleibt in diesem Browser gespeichert, nicht im Spielstand; „Geladene Datei entfernen“ löscht sie wieder.
- Rechnet die Policy einmal keine gültige Zahl, schaltet das Spiel sofort auf die Regeln und meldet es.

Schneller Check (10 Sekunden): Nach Schritt 2 steht im Fenster seit Version 10 die Ablehnung mit „neu trainieren“ (bis Version 9: „Es
entscheidet die Policy „v9_lokal_1“ …“ und keine Warnung). Läuft die Seite als `file://`, steht dort stattdessen der Hinweis, dass der
Ordner `ki/` nicht lesbar ist.

## Tests

- Simulation: `bash tools/simtest_alle.sh` (alle 21 simtest-Modi, seit Version 10 mit `--gedaechtnis`, und die KI-Prüfung; gut 5 min mit 2
  Läufen gleichzeitig, `berichte/etappe2/mess/schritt4/frisch2/lauf.txt`; mehr gleichzeitig mit `JOBS=3`).
  `--gate` enthält eine Zeitgrenze (365 Tage in weniger als 5 s) und läuft deshalb allein am Ende. Rechnet nebenher etwas anderes, kann nur
  diese Grenze rot werden; dann einzeln wiederholen: `bash tools/simtest_alle.sh gate`.
- Browser: `bash tests/alle.sh` (32 Tests in echtem Chromium, rund 28 min, `berichte/etappe2/mess/schritt4/frisch/browser.txt`;
  Voraussetzungen in `tests/LIESMICH.md`). Geht auch in einem
  Terminal mit aktiver Trainings-Umgebung (`.venv`).
- Beide brauchen die Git-Geschichte des Repos (alte Fassungen per `git show`): im Repo einfach so, sonst `STADT_GIT=<repo>` setzen.
