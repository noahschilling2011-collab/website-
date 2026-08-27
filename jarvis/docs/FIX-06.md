# FIX-06 — COMMAND CENTER

> Auftrag von Noah, 27.08.2026. Setzt FIX-05 voraus (A6 und B6 sind
> abgenommen, siehe `STATUS.md`). Vier Abschnitte, nach jedem ein Halt:
> **5 Design-System → 6 COMMAND CENTER → 7 WELT-NETZ → 8 MÄRKTE.**
>
> Diese Datei hält fest, was ich **nachgeprüft** habe — nicht den Auftrag
> selbst. Der Auftrag sagt bei seiner Inventur ausdrücklich: *„Prüf jede
> Zeile selbst nach, bevor du baust. Wenn eine nicht stimmt: melden."*

## Die Inventur aus Abschnitt 2 — nachgeprüft

Dreizehn Zeilen, jede einzeln gegen den Code gehalten. **Elf stimmen.**

### Zwei stimmen nicht

**Zeile 11 — „Sprache rein und raus → `index.html:1697-1820`".**
Die Zeilenangabe ist falsch. Gemessen vor den Änderungen dieses
Abschnitts: der Sprachblock ging von **1711** (`// --- Sprache (Phase 9)
---`) bis **1845**, ab 1847 begann die Weltansicht. Zeile 1697 war
`e.preventDefault();` im Gedächtnis-Formular und gehörte gar nicht dazu.
Und 1820 schnitt mitten in den Mikrofon-Listenern ab — es ließ
ausgerechnet das „raus" draußen.

**Nach Abschnitt 5 lautet der Bereich `index.html:1680-1814`** (der
`:root`-Block ist weggefallen, das verschiebt alles darunter um 31
Zeilen). `docs/FIX-05-sprachtest.md` hatte die falsche Angabe von mir
übernommen und ist korrigiert.

*Lehre fürs nächste Mal: Zeilennummern in Dokumenten altern mit dem ersten
Commit. Ein `grep`-Anker wie `// --- Sprache (Phase 9)` überlebt.*

**Zeile 13 — „Euro-Beträge → existiert nicht".**
Euro-Beträge gibt es an mindestens zehn Stellen: `core/schema.sql:30`
(`cost_eur`), `api/routes.py:454/461/469` (`ROUND(SUM(cost_eur), 6)`),
`api/weltlage.py:180`, `core/db.py:387` (`spent_cost_eur`) und in der
Oberfläche mit €-Zeichen bei `index.html:1239, 1424, 2015, 2108, 2126,
2143`. Die Zeile widerspricht damit **Zeile 8 derselben Inventur**
(„Kosten- und Token-Zähler → `GET /api/stats`"), die genau diese Beträge
meint.

Gemeint ist vermutlich, was Abschnitt 6.2 sagt: die **Euro-Beträge aus dem
Video**, deren Herkunft unbekannt ist. So gelesen stimmt es. So
geschrieben, wie es dasteht, nicht.

### Zwei Präzisierungen, keine Fehler

**Zeile 6 — „Laufende Aufträge / Schritte → `GET /api/tasks`".**
`GET /api/tasks` liefert **keine Schritte**. `core/db.py:383-391`
(`list_task_rows`) selektiert nur id, goal, status, depth, parent_task_id,
spent_tokens, spent_cost_eur, spent_tool_calls, created_at, finished_at.
Schritte kommen aus `GET /api/tasks/{task_id}` oder live aus dem
SSE-Ereignis `step` (`api/tasks.py:110`). **Wichtig für Abschnitt 6,
Zone 3** — wer dort Schritte aus `/api/tasks` erwartet, bekommt sie nicht.

Zweitens: der Endpunkt `GET /api/events` steht in `api/routes.py:373`; in
`api/events.py` liegt nur der Generator `strom()`.

**Abschnitt 7.3 — „Höchstens `visual`".**
Stimmt als Obergrenze, ist aber unvollständig: `GRUPPEN`
(`core/satellite/ueberflug.py:47-50`) hat **zwei** Einträge, `visual`
(~157) und `stations` (~21). `active` mit rund 10.000 ist bewusst nicht
drin, mit Begründung im Code.

### Drei Einzelbehauptungen, alle bestätigt

| Behauptung | Ergebnis |
|---|---|
| `GET /api/stats/verlauf` existiert nicht | ✓ — Live-Dump der App zeigt 18 Pfade, keiner davon |
| kein Endpunkt gruppiert `llm_calls` nach Stunde | ✓ — es gibt nur `GROUP BY tag` und `GROUP BY model` |
| `grep -c 'setTimeout(weiter, pause)' index.html` → 0 | ✓ — ausgeführt, Ausgabe `0` |

---

## Abschnitt 5 — was ich gebaut und was ich dabei gemessen habe

### Die Kontraste aus 5.1 stimmen — alle sieben

Eigenes Skript, WCAG-2-Formel mit sRGB-Linearisierung. Keine einzige
Abweichung auf zwei Nachkommastellen:

| Farbe | auf `--grund` | auf `--ebene-1` |
|---|---|---|
| `--akzent` `#f0b45c` | 10,73 | 10,06 |
| `--akzent-satt` `#e09a3e` | 8,35 | 7,83 |
| `--text-laut` `#f4f4f7` | 18,02 | 16,89 |
| `--text` `#e8e8ec` | 16,19 | 15,18 |
| `--text-leise` `#8b8b95` | 5,86 | 5,50 |
| `--auf` `#6ee7a8` | 12,87 | 12,06 |
| `--ab` `#f6836f` | 7,91 | 7,41 |

Auch die Warnung stimmt: `#7a7a84` fällt auf `--ebene-1` auf **4,37** und
reißt die Grenze.

**Zwei Zahlen, die im Auftrag nicht stehen und die man kennen sollte:**

* `--text-leise` auf `--ebene-3` ist **4,56** — der knappste Punkt im
  ganzen System, 0,06 Reserve. Wer `--ebene-3` je aufhellt, muss
  `--text-leise` mit aufhellen. Die Grenze liegt bei etwa `#282830`.
* Der aktive Tab (`--akzent` auf `--akzent-glut` über Glas) liegt bei
  **9,59** über `--grund` bzw. **8,77** über `--ebene-1`. Die Glut kostet
  gut einen Kontrastpunkt, mehr nicht.

### Der Kontrastfehler war ein Messfehler — und ist trotzdem behoben

Vor FIX-06 meldete `web-selfcheck` auf `index.html` dreimal denselben
Fehler: *Kontrast 1,69:1 — „Chat" `rgb(242,181,68)` auf
`rgb(253,245,229)`*. Ein heller Hintergrund auf einer dunklen Seite.

Die Ursache steckt im Prüfskript, nicht in der Seite. `bgOf()` sucht die
erste undurchsichtige Fläche nach oben, und `over()` setzt dabei `a: 1`
**fest** — die untere Schicht wird immer als deckend behandelt. Die Kette
lautet: aktiver Tab `rgba(242,181,68,.14)` → `nav.tabs` ohne Hintergrund →
`header.glass` `rgba(255,255,255,.04)`. Beim Glas greift `over()` zum
zweiten Mal, rechnet gegen **reines Weiß**, meldet `a: 1` und bricht ab.
Der `body` darunter wird nie erreicht.

Gerechnet: 242·0,14 + 255·0,86 = 253,18 — genau die gemeldete Zahl.
Tatsächlich gemalt wurde `rgb(51,42,28)`, echter Kontrast **7,68:1**.

**Behoben, ohne das Skript anzufassen:** der aktive Tab bekommt eine
deckende Fläche (`--akzent-glut-fest`, dieselbe Farbe vorkomponiert).
Optisch identisch, aber jetzt misst das Skript dasselbe, was das Auge
sieht. Ergebnis: **0 Kontrastbefunde** auf beiden Seiten und in beiden
Tabs.

Das ist mehr als Kosmetik: ein dauerhaft roter Befund macht die Prüfung
wertlos, weil man den nächsten, echten übersieht.

### Die Falle, an der Abschnitt 5 fast gescheitert wäre

Ein `<link>` allein hätte am Globus **nichts** geändert.
`static/globus.js` deklarierte alle neun Variablen — darunter ein zweites,
blaues `--akzent` — noch einmal auf `.globus-wurzel` selbst. Eine
Deklaration **auf** einem Element verdrängt den geerbten Wert, ganz ohne
Spezifitätsstreit: `:root` ist `html`, `.globus-wurzel` ist ein `div`.

Ergebnis wäre gewesen: die App bernsteinfarben, der Globus blau — in
`weltlage.html` **und** im fünften Tab. Der Block ist deshalb ersatzlos
weg. `tests/test_designsystem.py::test_der_globus_deklariert_keine_eigene_palette`
hält das fest.

Zwei der neun Variablen waren zusätzlich schon vorher tot: `--flaeche` und
`--land` hatten null Nutzungen.

### `--schrift` war eine Farbe

In `globus.js` war `--schrift` die **Textfarbe** (`#e8eaef`), in Abschnitt
5.3 des Auftrags ist `--schrift` die **Schriftfamilie**. Derselbe Name,
zwei Typen — und CSS meldet das nicht: eine Deklaration mit falschem Typ
fällt still auf `unset` zurück.

Deshalb heißt die Familie in `system.css` **`--schriftfamilie`**, und die
Textfarbe heißt `--text`. Abweichung vom Auftrag, bewusst, hier notiert.

### Ein echter Fund, den das Prüfwerkzeug durchgewinkt hat

Das Ortssuchfeld im Globus (`#ort-eingabe`) hatte `outline:none` und beim
Fokus nur eine gefärbte Rahmenlinie. `web-selfcheck` meldete keinen
Befund — sein `FOCUS_JS` zählt **jeden** Rahmen und **jeden** Schatten als
Fokusring, auch einen, den das Element im Ruhezustand ohnehin trägt.

Gefunden hat es erst ein Test, der die Umrandung selbst misst: Stil,
Breite und Farbe, nach jedem Tab-Druck. Das Feld hat jetzt einen echten
Ring in `--akzent`.

### Was `--dim` war

`index.html:700` und `:702` lasen `var(--dim, #9aa)`. **`--dim` ist in
keiner Datei definiert** — die Farbe kam immer aus dem Ersatzwert. Eine
Variable, die es nicht gibt, ist eine Falle: wer sie eines Tages anlegt,
ändert stillschweigend diese zwei Zeilen. Beide zeigen jetzt auf
`--text-leise`.

### Der Backtick, der den Globus zweimal still zerlegt hat

`STIL` und `MARKUP` in `globus.js` sind Template-Zeichenketten. Ein
Backtick in einem CSS-Kommentar darin schließt die Zeichenkette mittendrin.
**`node --check` meldet nichts**, weil der Rest zufällig wieder als
gültiger Ausdruck durchgeht — die Seite lädt dann einfach nicht mehr
fertig. Passiert bei FIX-05 einmal und hier noch einmal.
`test_kein_backtick_in_den_eingebetteten_bloecken` schließt das ab.

### Abweichungen vom Auftragstext — vollständig

| Auftrag | Gebaut | Warum |
|---|---|---|
| `--schrift` = Schriftfamilie | `--schriftfamilie` | `--schrift` war in `globus.js` eine Farbe; stiller Typkonflikt |
| nur die genannten Variablen | zusätzlich `--akzent-glut-fest`, `--auf-akzent`, `--dauer-*`, `--s-7`, `--kenngroesse` / `--normal` / `--etikett` | 5.3, 5.4 und 5.6 nennen Werte, aber keine Namen dafür |
| — | die alten englischen Namen bleiben als **Zeiger** | rund 400 Regeln in `index.html`; Aliase halten sie gültig, ohne die Werte zu verdoppeln |
| — | `.glas` **und** `.glass` in einer Regel | `.glass` steht dreimal im Markup von `index.html` |
| — | `--ease` zeigt jetzt auf `--kurve-rein` | 5.6 legt die Kurven fest; die alte war `cubic-bezier(.4,0,.2,1)`, sichtbar in allen Hover-Übergängen |


---

# Abschnitt 6 — COMMAND CENTER

## Die Inventur, bevor gebaut wurde

Der Auftrag nennt in 6.1 für jede Zone eine Quelle. Jede einzeln nachgesehen:

| Zone | Quelle laut Auftrag | Nachgeprüft |
|---|---|---|
| 1 | `GET /api/health` | existiert, `api/routes.py:60` |
| 2 | dieselbe Szene wie 7 | `static/globus.js`, ein Renderer, ein Canvas |
| 3 | `GET /api/tasks` + SSE | existiert — **liefert aber keine Schritte** (in Abschnitt 5 gemessen und dort vermerkt) |
| 4 | SSE aus `api/events.py` | existiert; Ereignistypen `task`, `step`, `tool`, `confirmation`, `hello` |
| 5 | `GET /api/stats` | existiert, `api/routes.py:438` |
| 6 | `GET /api/tool-calls` | existiert, `api/routes.py:397` |
| 7 | `GET /api/stats/verlauf` | **gab es nicht** — gebaut, siehe unten |
| 8 | `GET /api/weltlage/WELT` | existiert; liefert ohne Zwischenspeicher `auftrag_noetig: true` |

Alle acht Zonen haben damit eine echte Quelle. Der Auftrag sagt: *„Gibt es
keine, wird sie nicht gebaut."* — es musste keine wegfallen.

## `GET /api/stats/verlauf` — der eine neue Endpunkt

Aggregation über `llm_calls`, gruppiert nach `substr(created_at, 1, 13)`
(`YYYY-MM-DDTHH`). `created_at` ist UTC mit `Z` (`core/db.utcnow`), damit ist
die Gruppe eindeutig und braucht keine Zeitzonenrechnung in SQL. Fenster
1 bis 168 Stunden, Vorgabe 24. Dieselbe Token-Prüfung wie überall
(`dependencies=[Depends(require_token)]` am Router), acht Tests dagegen.

**Zwei Entscheidungen, die man sehen muss:**

**Lücken werden mit Nullen gefüllt, nicht ausgelassen.** Eine Stunde ohne
Aufruf ist eine Stunde mit null Token — das ist eine Messung. Ließe man sie
weg, rücken die Punkte zusammen und das Flächendiagramm behauptet eine
Dichte, die es nicht gab.

**`cost_eur` kommt roh aus der Tabelle.** Stehen keine Preise in der `.env`,
schreibt `core/llm.py` dort `0.0`, und dann steht hier `0.0`. Nicht
geschätzt — das steht seit dem 25.08. so im Entscheidungslog.

## Zone 2 — ein Canvas, zwei Orte

Der Auftrag verbietet einen zweiten WebGL-Kontext, und zwar mit Grund:
Browser begrenzen die Zahl gleichzeitiger Kontexte und verwerfen den älteren
ohne Vorwarnung.

Gelöst durch **Umhängen statt Kopieren**: `globus.js` bekam `miniAn(behaelter)`
und `miniAus()`. Beide verschieben dasselbe `<canvas>` im Dokument —
`miniAus()` setzt es mit `insertBefore` an genau die Stelle zurück, an der es
stand. Beide Ansichten sind Tabs und nie gleichzeitig sichtbar, also reicht
ein Canvas. Gemessen im Browser:

```
Canvas liegt in: cc-globus-platz
WebGL-Kontexte (canvas-Elemente gesamt): 1
nach Tabwechsel liegt Canvas in: view globus-wurzel is-active
```

**Three.js wird trotzdem nicht beim Start geladen.** Das COMMAND CENTER ist
die Startansicht — würde Zone 2 den Globus holen, hingen die 2,0 MB aus
FIX-05 B-2 wieder an jedem Seitenaufruf. Stattdessen steht dort ein Satz mit
der Zahl und ein Knopf. `test_die_startansicht_laedt_three_js_nicht` hält das
fest.

## Zwei Funde beim Bauen

**1. Ein `<canvas>` lässt sich nicht mit `inset` aufspannen.** Es ist ein
ersetztes Element: steht `width: auto`, nimmt CSS die intrinsische Größe
(300×150) und ignoriert eine der beiden Kanten. Gemessen: `canvasW` blieb
`300px`, obwohl `left` **und** `right` gesetzt waren. Behoben mit
ausdrücklicher `width: calc(100% - 20px)`.

**2. Der sechste Tab hat die Kopfzeile bei 360 px aufgerissen.** Gemessen:
`scrollWidth` 404 bei `innerWidth` 360, Täter `#tab-welt`. Mit fünf Tabs
passte die Reihe gerade noch — mit dem sechsten nicht mehr. `.tabs` bekommt
`flex-wrap: wrap`; danach `scrollWidth` 360.

**3. Spezifität:** `.cc > .zone` sind zwei Klassen und schlagen `.cc-kopf`.
Die Kopfzeile stand als Spalte statt als Zeile, bis der Selektor
`.cc > .zone.cc-kopf` hieß.

## Eine Folge, die man kennen muss: die Seite wird nie „network idle"

Das COMMAND CENTER ist die Startansicht und hängt an SSE. Damit hält
`index.html` ab dem ersten Bild eine offene HTTP-Verbindung — und
`wait_until="networkidle"` tritt dort nie ein. Drei bestehende Browsertests
liefen deshalb in den Timeout und warten jetzt auf `domcontentloaded` plus
einen Selektor. Das ist keine Bequemlichkeit, sondern die richtige Bedingung:
„Netzwerk still" ist bei einer Ansicht mit Live-Strom kein erreichbarer
Zustand.

## Abweichungen vom Auftragstext

| Abweichung | Begründung |
|---|---|
| `.app` wird für diese Ansicht auf 1500 px verbreitert (`is-weit`) | Zwölf Spalten in einer 900-px-Spalte sind kein Dashboard, sondern eine Liste. Nur diese Ansicht; Chat und die anderen Tabs bleiben bei 900 px. |
| Die Uhr steht auf `--step-1`, nicht auf `--kenngroesse` | `--kenngroesse` ist die Größe für **eine** Heldenzahl. Als Uhr war sie 64 px hoch und hat die Kopfzeile erschlagen. |
| Die vier Kennzahlen stehen eine Stufe unter `--kenngroesse` | Vier davon nebeneinander fraßen ein Drittel der Höhe — und DoD 1 verlangt, dass alles in 900 px passt. |
| Zone 8 löst **keinen** POST aus | `GET /api/weltlage/WELT` liefert ohne Zwischenspeicher `auftrag_noetig`. Ein automatischer POST wäre ein Modellaufruf und Geld, ausgelöst vom bloßen Öffnen der Startansicht. |
| Bei frischer Datenbank steht in den Kennzahlen `—`, nicht `0` | 6.3 verbietet Nullen, die wie Daten aussehen. Ausnahme sind die Kosten: DoD 5 verlangt dort ausdrücklich `0,0000 €` mit dem Hinweis. |

## Was nicht gebaut wurde — wie beauftragt

Die Euro-Beträge aus dem Video (Herkunft unbekannt), der Arc-Reactor-Ring
(zeigt nichts), der Countdown auf ein unbekanntes Ereignis. Alle drei stehen
in 6.2 unter „wird ausdrücklich nicht gebaut".
