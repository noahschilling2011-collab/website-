# Cockpit

Persönliches Dashboard als **eine** HTML-Datei. Doppelklick genügt, kein Build,
kein npm, keine externe Bibliothek. Läuft genauso im Artifact-Preview.

```
cockpit/index.html    50 KB, alles drin
```

## Was drinsteht

Drei Spalten (ab 900px gestapelt): links Projekte, Mitte heute, rechts Ziele.

- **Projekte** — eine Karte je Projekt mit Statuspunkt und „zuletzt angefasst vor
  X Tagen", aus dem Datum gerechnet. Was länger als 30 Tage nicht angefasst
  wurde, wird abgesenkt dargestellt und mit „liegt seit X Tagen" beschriftet.
  Kein Rot, kein Ausrufezeichen — nur sichtbar. Unten „X aktiv · Y liegen".
- **Heute** — Uhr im Sekundentakt, der heutige Tagesplan als Zeitleiste
  (laufender Block hervorgehoben, vergangene gedimmt, Restzeit am laufenden
  Block), darunter Aufgaben (Enter legt an, Klick hakt ab, X löscht).
- **Ziele** — Titel, Zieldatum, verbleibende Tage und ein dünner Balken über die
  **verstrichene Zeit** seit Anlage. Keine geschätzte Fertigstellung.

Das Eingabefeld unten in der Mitte spricht echt mit der Anthropic-API
(`POST /v1/messages`). Der komplette Zustand wird als JSON in den Prompt
serialisiert. Kein API-Key in der Datei — den setzt die Umgebung serverseitig.
Ausserhalb einer solchen Umgebung zeigt das Panel eine lesbare Fehlermeldung.

## Daten eintragen

Alles Inhaltliche steht in **einem** `const DATA` am Anfang des `<script>`.
Nichts wird woanders erfunden: Was dort fehlt, zeigt das Cockpit als
„nicht eingetragen" an.

```js
name: "Noah",
stundenplan: { mo: [{ von:"07:45", bis:"13:00", was:"Schule" }], … },
termine:     [{ tag:"di", von:"18:00", bis:"20:00", was:"Flag-Football-Training" },
              { tag:"sa", was:"Bikepark", notiz:"nach Wetter" }],
projekte:    [{ name:"…", notiz:"…", status:"aktiv|liegt|fertig", datum:"2026-08-20" }],
ziele:       [{ titel:"…", angelegt:"2026-06-01", faellig:"2027-03-01" }]
```

Gefüllt sind `name`, `projekte` und ein `ziel`. Die Projektliste stammt aus den
Branches und Pull Requests dieses Repos (Name, letzter Commit je Branch, Stand
2026-08-23) — nicht geraten, aber prüf sie trotzdem. Beim Ziel steht „März 2027"
als `2027-03-01`, die übliche BewO-Frist; ein anderer Tag ist eine Zahl.

`stundenplan` und `termine` sind **leer** — die Schulzeiten trägst du selbst
nach. Solange sie fehlen, sagt der Tagesplan das offen, statt etwas zu erfinden.

## Persistenz

Bewusst **kein** `localStorage`/`sessionStorage` — in manchen Sandboxes sind die
APIs nicht verfügbar und die Seite stirbt an der ersten Zeile. Zustand lebt in
JS-Variablen. Stattdessen:

- **Export** legt den kompletten State als JSON in die Zwischenablage. Wenn die
  Zwischenablage nicht erreichbar ist, erscheint das JSON zum Selbstkopieren.
- **Import** nimmt es zurück, prüft Feld für Feld und meldet Fehler im UI.
  Der Rundlauf Export → Import → Export ergibt denselben String.

## Geprüft

Die Harnische liegen dabei und laufen gegen die echte Datei:

```bash
pip install playwright && playwright install chromium
python3 cockpit/tests/verhalten.py      # 60 Prüfungen
python3 cockpit/tests/mitternacht.py    # 3 Fälle gegen gefälschte Uhr
```

Abgedeckt: Aufgaben anlegen, abhaken und löschen samt Fokusverbleib; Chat-Request
und -Fehlerpfad; dass eine Rückfrage den bisherigen Verlauf mitträgt;
Import-Validierung Feld für Feld; Export → Import → Export byte-identisch;
Zeitleisten-Zustände inklusive Blöcken über Mitternacht; die 30-Tage-Regel; der
Zielbalken; 360px ohne horizontales Scrollen; Fokusringe; Tastatur-Scrollen der
Spalten ab 901px; `prefers-reduced-motion`; und ein Lauf mit absichtlich
werfendem `localStorage`/`sessionStorage`.

Dazu ein Kontrast- und Overflow-Sweep in drei Breiten: 0 Fehler, 0 Warnungen.

**Nicht geprüft:** eine echte Antwort der Anthropic-API. Im Test war der Endpunkt
abgefangen — Request-Form, Prompt-Inhalt und Rendering der Antwort sind belegt,
der Netzweg selbst nicht. Die Tests laufen auch nicht in CI: der Workflow dieses
Repos hat keinen Browser-Schritt, und einen dafür einzuziehen wäre eine eigene
Entscheidung.

## Bewusste Grenzen

- Blöcke hängen am Wochentag. Um 03:00 am Dienstag zeigt ein Dienstag-Block
  22:00–02:00 „kommt heute Abend", nicht den Ausläufer von Montagnacht.
- Ein Block mit `von`, aber ohne `bis` bleibt ab seinem Beginn „laufend" — ohne
  Ende gibt es keine Restzeit, und es wird auch keine erfunden.
- In den Prompt geht der Stundenplan **von heute**, nicht die ganze Woche. So
  steht es in der Vorgabe. „Was habe ich morgen?" beantwortet der Planer deshalb
  mit „steht nicht in den Daten" — eine Zeile in `snapshot()` ändert das.
