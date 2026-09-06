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

---

# ERGEBNIS — gebaut am 25.08.2026

## Was existiert

| Datei | wofür |
|---|---|
| `core/vault.py` | Notiz, Frontmatter hin und zurück, atomares Schreiben, Konflikterkennung |
| `core/vault_index.py` | abgeleiteter Index, FTS5, Beobachter mit 800-ms-Entprellung |
| `scripts/reindex.py` | `python -m scripts.reindex` — baut den Index von null neu |
| `scripts/migrate_vault.py` | Schritt 4, bricht ab statt zu löschen |
| `tests/test_vault.py` | 24 Tests |
| Tabellen `vault_notizen` + `vault_fts` | in `core/schema.sql`, ausdrücklich **ohne** Indexier-Zeitstempel |

`VAULT_PFAD` leer heißt: nichts ändert sich, nichts wird angelegt, JARVIS bleibt
bei der Datenbank. Nachgewiesen mit `test_ohne_vault_bleibt_alles_beim_alten`.

## Schritt 0 — Bestand

```
$ python3 -c "... select count(*) from facts"
facts: 0
```

**Die Messlatte ist 0.** Die produktive Datenbank enthält keine Fakten, die Migration
kann dort also nichts beweisen. Deshalb ist sie zusätzlich gegen eine geseedete
Datenbank gelaufen — dieselbe Datei, dieselben Schritte:

```
[0] Bestand: 3 Zeilen in facts
[1] schreiben
       1 -> Noah-fahrt-Downhill-f_1.md
       2 -> Der-Kaffee-wird-schwarz-getrunken-f_2.md
       3 -> Wohnort-ist-Schwabisch-Gmund-f_3.md
[2] neu indexieren        3 Notizen im Index
[3] zaehlen und vergleichen   ✓ 3 == 3
[4] Stichprobe, Zeichen fuer Zeichen
    ✓ f_1: 'Noah fährt Downhill. Sein Rad ist ein Santa Cruz V10.'
    ✓ f_2: 'Der Kaffee wird schwarz getrunken.'
    ✓ f_3: 'Wohnort ist Schwäbisch Gmünd.'
[5] facts -> facts_alt    ✓ umbenannt. NICHT geloescht.
```

## Definition of Done

| # | Kriterium | Stand | BELEG |
|---|---|---|---|
| 1 | Anzahl Fakten im Vault == Anzahl aus Schritt 0 | ✓ | `pytest -q tests/test_vault.py::test_dod_1_jeder_fakt_wird_eine_notiz` — ruft `scripts/migrate_vault.py` als echten Unterprozess auf |
| 2 | Neue Notiz in Obsidian → in unter 3 s gefunden, mit Zeitstempeln | ✓, aber **anders erfüllt** | Ursprünglich mit einem `watchdog`-Beobachter: `geschrieben -> im Index: 0.31 s`. Der ist mit **FIX-04 Schritt 3** entfallen — dort steht *Ausdrücklich nicht bauen: Dateiüberwachung*. Jetzt zieht `core.gedaechtnis.frisch_halten` beim Lesen nach; `test_dod_2_eine_neue_notiz_ist_beim_naechsten_lesen_da` misst dasselbe. Der Unterschied ist unsichtbar: wer nicht liest, merkt ihn nicht; wer liest, bekommt den frischen Stand |
| 3 | Geänderte Notiz → neuer Inhalt | ✓ | `test_dod_3_geaenderte_notiz_liefert_den_neuen_inhalt` |
| 4 | **Umbenennen → der Fakt überlebt** | ✓ | `test_dod_4_umbenennen_ueberlebt_der_fakt`. Gegenprobe: Schlüssel auf den Dateinamen umgestellt → Test rot |
| 5 | Löschen → Fakt weg, keine Halluzination | ✓ | `test_dod_5_geloeschte_notiz_ist_weg` + `test_das_loeschen_wird_beim_naechsten_lesen_bemerkt`. Dazu seit FIX-04 `test_eine_ausserhalb_geloeschte_notiz_verschwindet_auch_aus_dem_index`: `frisch_halten` wirft verwaiste Einträge raus — das fehlte zuerst und wurde vom Beobachter verdeckt |
| 6 | Index wegwerfen, `reindex`, identischer Zustand — zweimal | ✓ | `test_dod_6_zweimal_neu_indexieren_gibt_dasselbe`. Gegenprobe: Uhr statt `mtime` in den Index → *„im Index steckt Zustand, der nicht im Vault steht"* |
| 7 | Datei öffnet in Obsidian sauber, Frontmatter als Eigenschaften, Wikilinks klickbar | **NICHT AUSGEFÜHRT** | Obsidian ist hier nicht installiert. Das Format entspricht dem, was `docs/MIGRATION-VAULT.md` Schritt 1 vorgibt, und geht in `test_frontmatter_geht_hin_und_zurueck` verlustfrei hin und zurück — **den Screenshot musst du selbst machen** |
| 8 | Konfliktfall → keine stille Überschreibung, `-konflikt`-Datei | ◐ | `test_dod_8_fremde_aenderung_wird_nicht_still_ueberschrieben` prüft Datei und Ausnahme. Die **Meldung im UI** fehlt: der Konflikt kommt als `ToolResult(ok=False)` zurück und erscheint in der Werkzeug-Ansicht, es gibt aber keinen eigenen Dialog |
| 9 | Kein Eintrag aus `.obsidian/` oder `.git/` | ✓ | `test_dod_9_obsidian_und_git_bleiben_draussen` — prüft zusätzlich mit einer SQL-Abfrage auf `pfad LIKE '.obsidian%'` |
| 10 | `pytest` grün, Tests für Umbenennen, Löschen, Verschieben, Idempotenz | ✓ | `443 passed`; alle vier Fälle einzeln als Test |

## Was nicht gebaut wurde — und warum

- **Keine Zwei-Wege-Synchronisation, kein Merge.** Der Index ist abgeleitet; damit
  entfällt der Konfliktfall zwischen zwei Wahrheiten. Es gab keine Stelle, an der ein
  Merge nötig gewesen wäre.
- **Kein MCP-Server, kein Obsidian-Plugin.** Nur Dateien.
- **Keine Embeddings.** FTS5 ist ungemessen, aber es gibt noch nichts zu messen.

## Offen

- DoD 7 braucht dich mit einem echten Obsidian.
- DoD 8 braucht eine sichtbare Konfliktmeldung im UI, wenn das mehr sein soll als eine
  Zeile im Werkzeug-Log.
- Die Migration auf der produktiven Datenbank ist mit 0 Fakten trivial. Sobald echte
  Fakten da sind, gehört sie wiederholt — `--abschluss` nicht vergessen.
