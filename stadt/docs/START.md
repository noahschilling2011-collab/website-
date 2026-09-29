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

## Entscheidungen der Bewohner: Regeln oder trainierte Policy

Standard sind die **Regeln**. Die trainierte Policy ist experimentell (Auswertung nicht bestanden, `docs/GRENZEN.md`).

1. Zahnrad unten rechts → unten der Knopf **„Entscheidungen: Regeln ›“**. Es öffnet sich das Fenster „Entscheidungen der Bewohner“.
2. **„Trainierte Policy (experimentell)“** wählen. Das Spiel holt jetzt `ki/policies.json` und die Policy-Dateien daneben, prüft sie und
   nimmt die erste passende. Unter „Policy“ steht dann `v9_lokal_1 (experimentell)`, darüber der Stand („Es entscheidet die Policy …“ mit
   Herkunft, Trainingsschritten und Zählern), darunter „Auswertung laut Datei: nicht bestanden“ und was die Messung ergab.
3. Fenster schließen. Der Knopf heißt jetzt „Entscheidungen: Policy ›“.
4. Zurück: im selben Fenster „Regeln (Standard)“.

Was dabei gilt:
- Die Policy entscheidet nur für Erwachsene unter 67, die keine Hauptfigur und nicht Bürgermeister sind, an ihren normalen
  Entscheidungszeitpunkten (7 und 18 Uhr, nach Ereignissen, auch beim Aufholen). Alles andere bleibt bei den Regeln.
- **Sie verändert die ganze Stadt.** Mit `v9_lokal_1` für alle wuchs eine neue Stadt in der Auswertung deutlich langsamer: an Tag 90 45–53
  statt 107–128 Einwohner (4 Seeds, `berichte/v9_lokal_1/abschluss_stadt.txt`), mit weniger Gründungen und Geburten.
- Im Spielstand steht nur ein Verweis (Name, Hash, Schema). Beim nächsten Start holt das Spiel dieselbe Policy (gleicher Hash) wieder aus
  `ki/`, bevor die Stadt weiterläuft. Fehlt sie oder passt sie nicht, entscheiden die Regeln, und eine Meldung sagt warum. Danach speichert
  das Spiel die Regeln als Wahl: Liegt die Policy später wieder in `ki/`, sie im Fenster neu wählen (von selbst schaltet das Spiel nicht zurück).
- Eine andere Policy-Datei: im Fenster „Policy-Datei laden …“. Ob sie angenommen oder mit welchem Grund sie abgelehnt wurde, steht oben im
  Fenster. Sie bleibt in diesem Browser gespeichert, nicht im Spielstand; „Geladene Datei entfernen“ löscht sie wieder.
- Rechnet die Policy einmal keine gültige Zahl, schaltet das Spiel sofort auf die Regeln und meldet es.

Schneller Check (10 Sekunden): Nach Schritt 2 steht im Fenster „Es entscheidet die Policy „v9_lokal_1“ …“ und keine Warnung. Läuft die
Seite als `file://`, steht dort stattdessen der Hinweis, dass der Ordner `ki/` nicht lesbar ist.

## Tests

- Simulation: `bash tools/simtest_alle.sh` (alle 20 simtest-Modi und die KI-Prüfung, rund 12 min mit 2 Läufen gleichzeitig, `JOBS=3` rund 8 min).
  `--gate` enthält eine Zeitgrenze (365 Tage in weniger als 5 s) und läuft deshalb allein am Ende. Rechnet nebenher etwas anderes, kann nur
  diese Grenze rot werden; dann einzeln wiederholen: `bash tools/simtest_alle.sh gate`.
- Browser: `bash tests/alle.sh` (30 Tests in echtem Chromium, rund 25 min; Voraussetzungen in `tests/LIESMICH.md`). Geht auch in einem
  Terminal mit aktiver Trainings-Umgebung (`.venv`).
- Beide brauchen die Git-Geschichte des Repos (alte Fassungen per `git show`): im Repo einfach so, sonst `STADT_GIT=<repo>` setzen.
