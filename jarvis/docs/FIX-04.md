# REPARATURAUFTRAG 04 — EIN GEDÄCHTNIS, NICHT ZWEI

> **Reihenfolge:** FIX-03 zuerst. Der hier hängt nicht daran und ist unabhängig testbar —
> aber wenn du beides gleichzeitig anfängst, weißt du hinterher nicht, was welchen Fehler
> verursacht hat.

## Befund

Aus dem Audit, Fund 7: Mit gesetztem `VAULT_PFAD` zeigt das Panel **0 Fakten** von dem, was
sich das Modell gemerkt hat, und `recall` findet nicht, was der Mensch im Vault einträgt.
Es existieren zwei Speicher, die sich gegenseitig nicht sehen. Zusätzlich ist die
Konflikterkennung aus Phase 3 spurlos verschwunden.

Das ist die schlimmere Sorte Fehler als ein Absturz: das System vergisst still und behauptet
dabei nichts Falsches. Es zeigt einfach eine leere Liste, und eine leere Liste sieht aus wie
„noch nichts gemerkt", nicht wie „kaputt".

## Das Prinzip, an dem gemessen wird

```
vault/*.md    = WAHRHEIT.  Menschenlesbar, in Obsidian editierbar, in git versioniert.
SQLite + FTS5 = INDEX.     Abgeleitet. Jederzeit löschbar und aus dem Vault neu baubar.
```

Daraus folgt der Prüfstein für jede Änderung in diesem Auftrag: **Wenn du die Datenbank
löschst und neu aufbaust, darf kein einziger Fakt fehlen.** Kommt dir während der Umsetzung
ein Merge-Algorithmus oder eine Zwei-Wege-Synchronisation in den Sinn, hast du das Prinzip
verletzt — dann anhalten und melden.

## Regeln für diese Session

1. Ein Schritt nach dem anderen, jeder mit ausgeführter Ausgabe, dann committen.
2. **Nichts löschen**, bis Schritt 4 die Vollständigkeit bewiesen hat. Weder Zeilen in der
   Datenbank noch Dateien im Vault.
3. Kein Obsidian-Plugin, kein MCP-Server, keine Obsidian-API. Nur Dateien.
4. Eine leere Liste ist nie ein akzeptables Ergebnis, solange nicht bewiesen ist, dass sie
   leer sein soll.
5. Wenn ein Schritt etwas Unerwartetes aufdeckt: melden und stoppen.

---

## SCHRITT 0 — Bestand aufnehmen, nichts ändern

```bash
grep -n "VAULT_PFAD" .env
ls -la "$VAULT_PFAD" 2>/dev/null || echo "VAULT-VERZEICHNIS FEHLT"
find "$VAULT_PFAD" -name "*.md" | wc -l
find "$VAULT_PFAD" -name "*.md" -exec grep -l "^id:" {} \; | wc -l
git -C "$VAULT_PFAD" log --oneline | head -5 || echo "KEIN GIT IM VAULT"
sqlite3 data/jarvis.db "select count(*) from facts;"
sqlite3 data/jarvis.db "select id, typ, quelle from facts limit 5;"
```

Zu berichten:

- **Die drei Zahlen nebeneinander:** Dateien im Vault, Dateien mit `id` im Frontmatter,
  Zeilen in `facts`. Weichen sie ab, ist die Differenz der Schaden. Beziffere ihn.
- Existiert der Vault überhaupt? Wenn nein, ist die Migration nie gelaufen und Fund 7 hat
  eine andere Ursache als angenommen — dann melden und stoppen.
- Steht `id` im Frontmatter oder wird der Dateiname als Schlüssel benutzt? Der Dateiname
  ist kein Schlüssel; Obsidian benennt beim Umbenennen um.

**Zu Obsidian, einmal und dann nie wieder:** ob die App installiert ist, ist für diesen
Auftrag ohne Belang. Sie öffnet einen Ordner. Nimm es einmal auf (`ls ~/JARVIS-Vault/.obsidian`
existiert oder nicht) und lass es aus jeder weiteren Überlegung raus. Wenn JARVIS nur mit
installiertem Obsidian funktioniert, ist etwas falsch gebaut.

Abnahme: Bericht mit den drei Zahlen. Nichts repariert.

---

## SCHRITT 1 — Den Riss lokalisieren

Für **jeden** Weg, auf dem ein Fakt entsteht oder gelesen wird, mit Datei und Zeilennummer:

| Weg | Schreibt wohin | Liest woher |
|---|---|---|
| Modell merkt sich etwas | ? | — |
| `POST /api/memory` | ? | — |
| `GET /api/memory` (Panel) | — | ? |
| `recall` im Werkzeugaufruf | — | ? |
| Mensch legt `.md` im Vault an | Vault | ? |

Die Frage, die alles entscheidet: **Gibt es einen Schreibweg, der die Datenbank anfasst,
ohne vorher eine Datei im Vault zu schreiben?** Wenn ja, ist genau das der Riss.

Nichts reparieren. Nur berichten.

---

## SCHRITT 2 — Ein Schreibweg

Jeder Fakt entsteht **zuerst als Datei im Vault**, atomar geschrieben wie in
MIGRATION-VAULT Schritt 2 festgelegt. Erst danach wird der Index nachgezogen.

Kein Codepfad schreibt mehr direkt in `facts`. Wenn ein Aufrufer das versucht, soll es
scheitern, nicht stillschweigend funktionieren — die Funktion, die direkt in die Datenbank
schreibt, wird privat und nur vom Indexer aufgerufen.

---

## SCHRITT 3 — Ein Leseweg, und der Index ist wegwerfbar

- `recall` und das Panel lesen **beide** aus dem Index. Nicht einer aus dem Vault und einer
  aus der Datenbank — dann hast du den Riss nur verschoben.
- Ein Befehl `reindex`, der die Tabelle leert und komplett aus `vault/*.md` neu aufbaut,
  Schlüssel ist `id` aus dem Frontmatter.
- `reindex` läuft **beim Start** automatisch. Damit sieht JARVIS, was du zwischendurch in
  Obsidian getippt hast, ohne dass irgendwas überwacht werden muss.
- Beim Lesen zusätzlich die Änderungszeit der Datei gegen den Index prüfen und bei
  Abweichung diesen einen Eintrag neu einlesen.

**Ausdrücklich nicht bauen:** Dateiüberwachung, Hintergrund-Dienst, Polling-Schleife.
Start plus Befehl plus Zeitstempel-Prüfung deckt den Alltag ab. Wenn das nicht reicht,
melden — nicht heimlich einen Watcher nachrüsten.

---

## SCHRITT 4 — Konflikterkennung zurück

Phase 3, Definition of Done Punkt 5: ein Fakt, der einem älteren widerspricht, wird als
**Konflikt angezeigt**, nicht stumm überschrieben. Die Prüfung ist verschwunden — finde
heraus, wann und wodurch, und stell sie im neuen Schreibweg wieder her.

Im Vault heißt das: der alte Fakt bleibt als Datei bestehen, der neue kommt dazu, und beide
sind im Panel als Konfliktpaar sichtbar, bis ein Mensch entscheidet. Kein automatisches
Auflösen.

---

## Definition of Done

Jeder Punkt mit ausgeführtem Befehl und echter Ausgabe.

1. „Merk dir: ich fahre Downhill und mein Rad ist ein Santa Cruz V10." → **eine** neue
   `.md`-Datei im Vault **und** eine Zeile im Index. Beide Pfade gezeigt.
2. Prozess neu starten, „Was für ein Rad fahre ich?" → korrekte Antwort, Memory-Lookup im
   Log sichtbar.
3. Eine `.md` von Hand im Vault anlegen, JARVIS neu starten → `recall` findet sie **und**
   sie steht im Panel. Das ist der Fund, der repariert werden sollte; er wird hier bewiesen.
4. Einen Fakt im Panel löschen, erneut fragen → das Modell sagt, dass es das nicht weiß.
   Es halluziniert die Antwort nicht.
5. **Der Prüfstein:** `rm data/jarvis.db`, dann `reindex`, dann die Zahl aus Schritt 0
   vergleichen. Gleiche Anzahl, gleiche `id`s. Nachgezählt, nicht geschätzt.
6. Eine Datei in Obsidian umbenennen, `reindex` → derselbe Fakt, dieselbe `id`, kein
   Duplikat.
7. Widersprechender Fakt → als Konflikt sichtbar, alter Fakt noch vorhanden.
8. `git -C "$VAULT_PFAD" status` ist sauber, nachdem JARVIS geschrieben hat — oder die
   Änderungen sind bewusst committet. Kein halbes Schreiben.

## Was du nicht tun sollst

- Eine Zwei-Wege-Synchronisation bauen. Der Vault gewinnt, immer.
- Den Index als Wahrheit behandeln, weil er schneller ist.
- Fehlende Fakten stillschweigend anlegen, um die Zahlen aus Schritt 0 zum Stimmen zu
  bringen. Die Differenz ist der Befund und gehört gemeldet, nicht geglättet.
- Eine leere Liste im Panel als „noch nichts da" anzeigen. Wenn der Index leer ist und der
  Vault nicht, ist das ein Fehler und muss als Fehler dastehen.
- Etwas löschen, bevor Punkt 5 durch ist.

---

## BEFUND SCHRITT 0 — ausgeführt am 26.08.2026

### Die drei Zahlen — in *diesem* Klon

```
$ grep -n "VAULT_PFAD" .env          -> .env: No such file or directory
$ echo $VAULT_PFAD                   -> (leer)
$ ls -la "$VAULT_PFAD"               -> VAULT-VERZEICHNIS FEHLT
$ data/jarvis.db                     -> existiert nicht
$ ls ~/JARVIS-Vault/.obsidian        -> existiert nicht
```

**Dateien im Vault: 0 · Dateien mit `id`: 0 · Zeilen in `facts`: 0.**

Das ist **kein Befund über deinen Rechner.** Dieser Klon ist frisch aus git; `.env`
(Zeile 1 der `.gitignore`) und `data/` (Zeile 8) sind bewusst nicht im Repository. Hier hat
JARVIS nie gelaufen. Die drei Zahlen von deinem Rechner kann nur dein Rechner liefern:

```bash
grep -n "VAULT_PFAD\|WIKI_KONTAKT" .env
find "$VAULT_PFAD" -name "*.md" | wc -l
find "$VAULT_PFAD" -name "*.md" -exec grep -l "^id:" {} \; | wc -l
sqlite3 data/jarvis.db "select count(*) from facts;"
```

### Der Abbruchgrund aus Schritt 0 greift nicht — und das ist gemessen

Der Auftrag sagt: *„Existiert der Vault überhaupt? Wenn nein, ist die Migration nie gelaufen
und Fund 7 hat eine andere Ursache als angenommen — dann melden und stoppen."*

Diese Schlussfolgerung hält nicht. Der Riss hängt **an keiner Migration**. Nachgestellt auf
einer frischen Datenbank und einem frisch angelegten, leeren Vault — keine Altlast, nichts
umbenannt, nichts migriert:

```
frischer Vault: /tmp/tmpu3msezlu/Vault   frische DB: /tmp/tmpu3msezlu/jarvis.db

[1] Das Modell merkt sich etwas (Werkzeug remember)
    remember ok=True -> Gemerkt in fakten/Mein-Rad-ist-ein-Santa-Cruz-V10-f_395043.md
    GET /api/memory -> 200 []
    Panel zeigt: 0 Fakten

[2] Der Mensch traegt im Panel etwas ein
    POST /api/memory -> 201
    recall findet es: Nichts zu 'Schwaebisch' im Vault.

[3] Eine .md von Hand im Vault
    recall: Nichts zu 'Downhill' im Vault.
    Panel: [{'id': 1, 'text': 'Noah spricht Schwaebisch.', ...}]

[4] Die drei Zahlen: facts=1  vault_notizen=1  .md im Vault=2

[5] Steht der gemerkte Fakt im Systemprompt? (Phase-3-DoD 2)
    memory.kontextblock -> ''
```

Drei Zahlen, drei verschiedene Wahrheiten, auf einem System, das seit fünf Minuten
existiert. Deshalb wird hier **nicht** gestoppt: der Befund ist strukturell, nicht
historisch.

### Was dabei zusätzlich auffiel

Punkt [5] steht in keinem Fund und ist der stillste Teil: `memory.kontextblock` liest nur
`facts`. Mit gesetztem `VAULT_PFAD` landet **nichts** von dem, was sich das Modell merkt,
je wieder im Systemprompt. **Phase-3-DoD 2 ist damit still kaputt** — und niemand sieht es,
weil das Modell einfach antwortet, als hätte es nie etwas gehört.

### Obsidian

`~/JARVIS-Vault/.obsidian` existiert nicht. Einmal aufgenommen, ab hier ohne Belang.

### `id` im Frontmatter, nicht der Dateiname

`core/vault.py:56-60` sagt es selbst: *„`id` ist der Schlüssel, **nicht** der Dateiname.
Obsidian benennt Dateien beim Umbenennen um und zieht Wikilinks nach; wer den Dateinamen als
Schlüssel nimmt, verliert den Fakt beim ersten Umbenennen."* `finde()` sucht an der `id`.
Das ist bereits richtig gebaut.

---

## BEFUND SCHRITT 1 — der Riss, mit Zeilennummern

| Weg | Schreibt wohin | Liest woher |
|---|---|---|
| Modell merkt sich etwas (`remember`) | **Vault** → `memory_tools.py:106` `schreibe(...)`, dann `:115` `aktualisiere(...)` → `vault_notizen` | — |
| `POST /api/memory` | **`facts`** → `routes.py:274` → `memory.py:176` `INSERT INTO facts` | — |
| `PATCH /api/memory/{id}` | **`facts`** → `routes.py:291` → `memory.py:235` `UPDATE facts` | — |
| `DELETE /api/memory/{id}` | **`facts`** → `routes.py:309` → `memory.py:250` `DELETE FROM facts` | — |
| `GET /api/memory` (Panel) | — | **`facts`** → `routes.py:264/265` |
| `recall` (mit Vault) | — | **`vault_notizen`** → `memory_tools.py:189` `suche(...)` |
| `recall` (ohne Vault) | — | **`facts`** → `memory_tools.py:225` |
| Systemprompt | — | **`facts`** → `routes.py:178` `memory.kontextblock` |
| Mensch legt `.md` an | Vault | **niemand** — bis zum nächsten Start oder bis der Beobachter zuschlägt |

### Die Frage, die alles entscheidet

> **Gibt es einen Schreibweg, der die Datenbank anfasst, ohne vorher eine Datei im Vault zu
> schreiben?**

**Ja, drei — und sie sind genau der Riss:**

1. `POST /api/memory` → `memory.add_fact` (`api/routes.py:274`)
2. `PATCH /api/memory/{id}` → `memory.update_fact` (`api/routes.py:291`)
3. `DELETE /api/memory/{id}` → `memory.delete_fact` (`api/routes.py:309`)

Alle drei kennen `vault_pfad` überhaupt nicht. `core/tools/memory_tools.py:41` hat die
Weiche `vault_an()`; die vier Endpunkte und der Systemprompt haben sie nie bekommen.
`docs/MIGRATION-VAULT.md` Schritt 5 hat den Lesepfad des **Werkzeugs** umgestellt und dort
aufgehört.

### Etwas, das der Auftrag ausdrücklich nicht will — und das es schon gibt

Schritt 3 sagt: *„**Ausdrücklich nicht bauen:** Dateiüberwachung, Hintergrund-Dienst,
Polling-Schleife."*

Eine Dateiüberwachung **existiert bereits**: `core/vault_index.py`, Klasse `Beobachter`,
gestartet in `api/app.py:135`. Sie stammt aus der Vault-Migration und wurde gerade erst für
BUGS-01 Fund 20 umgebaut (ein Arbeiter statt tausend Timer).

Ich baue keine neue und ich lasse den neuen Entwurf **nicht** von ihr abhängen: Start,
Befehl und Zeitstempel-Prüfung tragen den Alltag allein — genau wie der Auftrag es verlangt.
Die bestehende bleibt vorerst stehen; sie zu entfernen wäre eine Verhaltensänderung, die
dieser Auftrag nicht verlangt. **Sag Bescheid, wenn sie rausfliegen soll.**
