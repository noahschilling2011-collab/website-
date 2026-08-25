# MIGRATION — OBSIDIAN-VAULT ALS GEDÄCHTNIS

> **Das ist keine neue Phase, das ist eine Umstellung.** Phase 3 existiert und enthält
> echte Daten. Es wird nichts danebengebaut und nichts verloren.
>
> Reihenfolge: FIX-01 bleibt Priorität. Diese Migration hängt nicht am Planner und ist
> deshalb unabhängig davon testbar — aber wenn du beides gleichzeitig anfängst, weißt du
> hinterher nicht, was welchen Fehler verursacht hat.

---

## Das Prinzip, von dem alles abhängt

```
vault/*.md    = WAHRHEIT.  Menschenlesbar, in Obsidian editierbar, in git versioniert.
SQLite + FTS5 = INDEX.     Abgeleitet. Jederzeit löschbar und aus dem Vault neu baubar.
```

Weil die Datenbank **nie** autoritativ ist, gibt es keine Zwei-Wege-Synchronisation und
keine Konfliktauflösung zu bauen. Wenn dir während der Umsetzung auffällt, dass du einen
Merge-Algorithmus brauchst, hast du das Prinzip verletzt — dann anhalten und melden.

Es gibt keine „Obsidian-Integration". Obsidian öffnet einen Ordner. JARVIS schreibt in
denselben Ordner. Das ist alles.

---

## Regeln für diese Session

1. Ein Schritt nach dem anderen, jeder mit ausgeführter Ausgabe, dann committen.
2. **Keine Daten löschen**, bis Schritt 4 die Vollständigkeit bewiesen hat.
3. Kein Obsidian-Plugin, kein MCP-Server, keine Obsidian-API. Nur Dateien.
4. Wenn ein Schritt etwas Unerwartetes aufdeckt: melden und stoppen.

---

## SCHRITT 0 — Bestand aufnehmen

```bash
sqlite3 data/jarvis.db "select count(*) from facts;"
sqlite3 data/jarvis.db ".schema facts"
sqlite3 data/jarvis.db "select * from facts limit 3;"
```

Diese Zahl ist ab jetzt die Messlatte. Notier sie im Protokoll.
Danach: Backup der Datenbank anlegen, Pfad nennen.

---

## SCHRITT 1 — Vault anlegen

Pfad aus `.env`: `VAULT_PFAD=~/JARVIS-Vault`

```
JARVIS-Vault/
├── fakten/
├── projekte/
├── auftraege/          # task_log als Markdown
└── nachgeschlagen/     # Cache aus wiki_lokal
```

Dateiformat, verbindlich:

```markdown
---
id: f_7a3c91                 # stabil, aendert sich NIE
typ: fakt
quelle: gespraech            # gespraech | wiki_lokal | web | manuell
erfasst: 2026-08-25
snapshot: null               # bei nachgeschlagenem Wissen Pflicht
tags: [mtb, ausruestung]
---

Noah fährt Downhill. Sein Rad ist ein Santa Cruz V10.

Siehe [[projekte/JARVIS]]
```

**`id` im Frontmatter ist der Schlüssel, nicht der Dateiname.** Obsidian benennt Dateien
beim Umbenennen um und zieht Wikilinks nach. Wer den Dateinamen als Schlüssel nimmt,
verliert beim ersten Umbenennen den Fakt.

`git init` im Vault. Das ist gleichzeitig Versionierung und deine Synchronisation —
der bezahlte Obsidian-Sync wird dafür nicht gebraucht.

---

## SCHRITT 2 — Schreiben

`core/vault.py`:

- **Atomar schreiben**: in eine Temporärdatei, dann `os.replace()`. Obsidian darf nie
  eine halbe Datei lesen.
- Dateiname aus dem ersten Satz abgeleitet, entschärft, plus Kurz-ID. Rein kosmetisch.
- Wikilinks setzen, wo ein Bezug existiert. Das ist die Auszahlung: die Graphenansicht
  in Obsidian zeigt dir dann, was JARVIS über dich weiß.
- **Nie eine Datei überschreiben, deren `mtime` neuer ist als der letzte Index.**
  In dem Fall: neue Datei mit `-konflikt` im Namen anlegen und im UI melden. Nicht still
  gewinnen, nicht mergen.

---

## SCHRITT 3 — Indexieren

`core/vault_index.py`, `watchdog` 6.0.0 (geprüft vorhanden auf PyPI):

- Beobachtet `VAULT_PFAD` rekursiv.
- **`.obsidian/` und `.git/` werden ignoriert.**
- **Entprellen: 800 ms.** Editoren schreiben mehrfach hintereinander.
- Ereignisse: angelegt / geändert / gelöscht / **verschoben**. Verschieben ist der Fall,
  den man vergisst — und in Obsidian passiert er ständig.
- Gelöschte Datei → Eintrag aus dem Index raus. Kein Papierkorb, der Vault ist in git.
- `python -m scripts.reindex` baut den Index von null neu.

**Idempotenz ist die Kernanforderung:** Zweimal komplett neu indexieren muss byte-gleiche
Ergebnisse liefern. Wenn nicht, steckt Zustand im Index, der nicht im Vault steht — und
dann ist das Prinzip gebrochen.

---

## SCHRITT 4 — Migration

1. Alle Zeilen aus `facts` als Markdown in `fakten/` schreiben, `id` aus der bisherigen ID.
2. Neu indexieren.
3. **Zählen und vergleichen.** Anzahl Dateien im Vault == Anzahl Zeilen in `facts` aus
   Schritt 0. Weicht es ab: anhalten, nichts löschen, melden.
4. Stichprobe: drei Fakten Zeichen für Zeichen vergleichen, Ausgabe zeigen.
5. Erst wenn 3 und 4 stimmen: `facts` in `facts_alt` umbenennen. **Nicht löschen.**
   Löschen darfst du nach zwei Wochen, wenn nichts fehlt.

---

## SCHRITT 5 — Lesepfad umstellen

- Das Memory-Tool sucht ab jetzt über den Vault-Index, nicht über `facts`.
- Jede Antwort nennt die Quelldatei — auch bei lokaler Quelle. Herkunft ist Pflicht.
- **Nie den ganzen Vault in einen Prompt kippen.** Abruf heißt: passende Notizen finden
  und nur diese mitgeben.
- Obergrenze: höchstens 5 Notizen oder 2.000 Token pro Anfrage, je nachdem was zuerst greift.

---

## Definition of Done

1. Anzahl Fakten im Vault == Anzahl aus Schritt 0. Beide Zahlen im Protokoll.
2. Ich schreibe in Obsidian eine neue Notiz → innerhalb von 3 Sekunden findet JARVIS sie.
   Mit Zeitstempeln nachgewiesen.
3. Ich ändere eine Notiz in Obsidian → JARVIS antwortet mit dem neuen Inhalt.
4. Ich **benenne eine Notiz in Obsidian um** → der Fakt überlebt, weil `id` im
   Frontmatter steht. Das ist der Test, der die Schlüsselwahl beweist.
5. Ich lösche eine Notiz → der Fakt ist weg, und JARVIS halluziniert ihn nicht.
6. `rm -rf` auf den Index, dann `python -m scripts.reindex` → identischer Zustand.
   Zweimal ausgeführt, Ergebnisse verglichen.
7. JARVIS legt einen neuen Fakt an → die Datei öffnet in Obsidian sauber, Frontmatter
   erscheint als Eigenschaften, Wikilinks sind klickbar. Screenshot.
8. Konfliktfall: Datei von Hand ändern, JARVIS zum Aktualisieren zwingen → **keine**
   stille Überschreibung, `-konflikt`-Datei entsteht, Meldung im UI.
9. Kein einziger Eintrag aus `.obsidian/` oder `.git/` im Index. Geprüft mit einer Abfrage.
10. `pytest` grün, neue Tests für Umbenennen, Löschen, Verschieben und Idempotenz.

---

## Was du nicht bauen sollst

- Zwei-Wege-Synchronisation mit Konfliktauflösung. Brauchst du nicht, wenn der Index
  abgeleitet ist. Wenn du glaubst, du brauchst sie: melden statt bauen.
- Einen MCP-Server für Dateien, die auf derselben Platte liegen.
- Automatisches Einspeisen des Vaults in Prompts.
- Ein Obsidian-Plugin. Obsidian muss von JARVIS nichts wissen.
- Vektor-Einbettungen. Erst FTS5 messen. Embeddings kommen, wenn FTS5 nachweislich zu
  schlecht ist — das ist eine Messung, keine Annahme.
