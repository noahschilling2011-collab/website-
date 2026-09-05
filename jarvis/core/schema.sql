-- Schema von JARVIS, Phase 1 (Walking Skeleton).
--
-- Die Spalten stehen so in docs/phases/PHASE-01.md. Sie werden hier nicht
-- "verbessert" - spaetere Phasen bauen darauf auf.
--
-- Zeitstempel sind UTC in ISO-8601 mit 'Z'. Sortierbar als Text und beim
-- Draufschauen lesbar, anders als ein Unix-Integer.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    role        TEXT    NOT NULL CHECK (role IN ('user', 'assistant')),
    content     TEXT    NOT NULL,
    created_at  TEXT    NOT NULL
);

-- Jeder Modellaufruf wird protokolliert (0.6): Zeit, Modell, Token, Dauer,
-- Kosten, Erfolg. Auch der fehlgeschlagene - sonst faellt eine Retry-Schleife,
-- die Geld verbrennt, erst auf der Rechnung auf.
CREATE TABLE IF NOT EXISTS llm_calls (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    model        TEXT    NOT NULL,
    -- 0.6 verlangt den Prompt-Hash im Log. PHASE-01 nannte die Spalten ohne
    -- ihn; auf Nachfrage aufgenommen. Nicht der Prompt selbst - der kann
    -- Privates enthalten und gehoert nicht ins Kostenprotokoll.
    prompt_hash  TEXT    NOT NULL DEFAULT '',
    in_tokens    INTEGER NOT NULL DEFAULT 0,
    out_tokens   INTEGER NOT NULL DEFAULT 0,
    cost_eur     REAL    NOT NULL DEFAULT 0.0,
    duration_ms  INTEGER NOT NULL DEFAULT 0,
    ok           INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT    NOT NULL
);

-- Phase 2: welches Werkzeug lief zu welcher Antwort, mit welchen Argumenten.
-- Ohne diese Tabelle kann die Oberflaeche nicht zeigen, was tatsaechlich
-- passiert ist - und man muesste dem Modell glauben.
CREATE TABLE IF NOT EXISTS tool_calls (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id   INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    name         TEXT    NOT NULL,
    arguments    TEXT    NOT NULL DEFAULT '{}',   -- JSON
    ok           INTEGER NOT NULL DEFAULT 1,
    display      TEXT    NOT NULL DEFAULT '',
    error        TEXT,
    sources      TEXT    NOT NULL DEFAULT '[]',   -- JSON-Array
    duration_ms  INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tool_calls_message ON tool_calls(message_id);
CREATE INDEX IF NOT EXISTS idx_messages_id ON messages(id);
CREATE INDEX IF NOT EXISTS idx_llm_calls_created ON llm_calls(created_at DESC);


-- ---------------------------------------------------------------------------
-- Phase 3: Gedaechtnis.
--
-- Vier Schichten, aber nur zwei brauchen Tabellen:
--   Short-Term  = die letzten N Zeilen aus `messages`
--   Working     = Zwischenergebnisse im Task-Objekt, nicht persistent
--   Long-Term   = `facts`
--   Episodic    = `task_log`
--
-- Gesucht wird mit FTS5, nicht mit Embeddings. Ein Vektorindex kommt erst,
-- wenn eine Messung zeigt, dass FTS5 nicht reicht - nicht auf Verdacht.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS facts (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    text               TEXT    NOT NULL,
    category           TEXT    NOT NULL DEFAULT 'allgemein',
    source_message_id  INTEGER REFERENCES messages(id) ON DELETE SET NULL,
    created_at         TEXT    NOT NULL,
    confirmed          INTEGER NOT NULL DEFAULT 0,
    -- Nicht in der Spaltenliste des Phasenauftrags, aber DoD 5 verlangt, dass
    -- ein widersprechender Fakt als Konflikt sichtbar wird statt still
    -- ueberschrieben zu werden. Ohne Spalte waere der Konflikt nach dem
    -- Neuladen weg.
    conflicts_with     INTEGER REFERENCES facts(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_facts_created ON facts(created_at DESC);

CREATE TABLE IF NOT EXISTS task_log (
    task_id     TEXT    PRIMARY KEY,
    goal        TEXT    NOT NULL,
    outcome     TEXT    NOT NULL,
    summary     TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_task_log_created ON task_log(created_at DESC);

-- --- Volltextsuche ---------------------------------------------------------
-- `content=` haelt den Index als reinen Zeiger auf die Quelltabelle: der Text
-- liegt nicht doppelt in der Datei.

CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
    text,
    content='facts',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TRIGGER IF NOT EXISTS facts_ai AFTER INSERT ON facts BEGIN
    INSERT INTO facts_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS facts_ad AFTER DELETE ON facts BEGIN
    INSERT INTO facts_fts(facts_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS facts_au AFTER UPDATE ON facts BEGIN
    INSERT INTO facts_fts(facts_fts, rowid, text) VALUES('delete', old.id, old.text);
    INSERT INTO facts_fts(rowid, text) VALUES (new.id, new.text);
END;

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content_text,
    content='messages',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content_text) VALUES (new.id, new.content);
END;
CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content_text)
        VALUES('delete', old.id, old.content);
END;
CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content_text)
        VALUES('delete', old.id, old.content);
    INSERT INTO messages_fts(rowid, content_text) VALUES (new.id, new.content);
END;


-- ---------------------------------------------------------------------------
-- Phase 4: Tasks und Schritte.
--
-- `task_log` aus Phase 3 bleibt, was es ist: die kurze Chronik. Hier steht
-- die Struktur eines laufenden Auftrags, Schritt fuer Schritt. Ein Schritt
-- wird persistiert, BEVOR er laeuft - sonst ist nach einem Absturz nicht
-- nachvollziehbar, was gerade passierte.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tasks (
    id                TEXT    PRIMARY KEY,
    goal              TEXT    NOT NULL,
    status            TEXT    NOT NULL,
    depth             INTEGER NOT NULL DEFAULT 0,
    parent_task_id    TEXT    REFERENCES tasks(id) ON DELETE CASCADE,
    budget            TEXT    NOT NULL DEFAULT '{}',   -- JSON
    spent_tokens      INTEGER NOT NULL DEFAULT 0,
    spent_cost_eur    REAL    NOT NULL DEFAULT 0.0,
    spent_tool_calls  INTEGER NOT NULL DEFAULT 0,
    result            TEXT,
    abort_reason      TEXT,
    created_at        TEXT    NOT NULL,
    finished_at       TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_parent  ON tasks(parent_task_id);

CREATE TABLE IF NOT EXISTS steps (
    id            TEXT    PRIMARY KEY,
    task_id       TEXT    NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    idx           INTEGER NOT NULL,
    description   TEXT    NOT NULL,
    prompt        TEXT    NOT NULL DEFAULT '',
    agent         TEXT,
    status        TEXT    NOT NULL,
    result        TEXT,                                -- JSON eines ToolResult
    note          TEXT,                                -- Begruendung der Pruefung
    attempts      INTEGER NOT NULL DEFAULT 0,
    max_attempts  INTEGER NOT NULL DEFAULT 2,
    created_at    TEXT    NOT NULL,
    updated_at    TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_steps_task ON steps(task_id, idx);


-- ---------------------------------------------------------------------------
-- Phase 5: Audit-Log.
--
-- "Jede Aktion ab EXTERNAL wird unveraenderlich protokolliert."
--
-- Unveraenderlich heisst hier nicht "wir aendern es halt nicht", sondern:
-- die Datenbank laesst UPDATE und DELETE auf dieser Tabelle nicht zu. Wer
-- eine Zeile loswerden will, muss die Datei anfassen - und das sieht man.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id      TEXT,
    step_id      TEXT,
    tool         TEXT    NOT NULL,
    arguments    TEXT    NOT NULL DEFAULT '{}',   -- JSON
    permission   TEXT    NOT NULL,
    decision     TEXT    NOT NULL,                -- approved | denied | timeout | auto
    executed     INTEGER NOT NULL DEFAULT 0,
    ok           INTEGER,
    detail       TEXT,
    created_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);

CREATE TRIGGER IF NOT EXISTS audit_log_kein_update
BEFORE UPDATE ON audit_log BEGIN
    SELECT RAISE(ABORT, 'audit_log ist unveraenderlich');
END;

CREATE TRIGGER IF NOT EXISTS audit_log_kein_delete
BEFORE DELETE ON audit_log BEGIN
    SELECT RAISE(ABORT, 'audit_log ist unveraenderlich');
END;


-- ---------------------------------------------------------------------------
-- Vault-Index (docs/MIGRATION-VAULT.md)
--
-- ABGELEITET, NIE AUTORITATIV. Diese Tabellen duerfen jederzeit geleert und
-- aus den Markdown-Dateien neu gebaut werden. Deshalb steht hier ausdruecklich
-- KEIN Indexier-Zeitstempel: zweimal neu indexieren muss byte-gleiche Zeilen
-- liefern, sonst steckt Zustand im Index, der nicht im Vault steht - und genau
-- das waere der gebrochene Vertrag.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS vault_notizen (
    id        TEXT PRIMARY KEY,          -- aus dem Frontmatter, nicht der Dateiname
    pfad      TEXT NOT NULL,             -- relativ zur Vault-Wurzel
    typ       TEXT NOT NULL DEFAULT 'fakt',
    quelle    TEXT NOT NULL DEFAULT 'gespraech',
    erfasst   TEXT NOT NULL DEFAULT '',
    snapshot  TEXT,
    tags      TEXT NOT NULL DEFAULT '',  -- kommasepariert, fuer die Anzeige
    text      TEXT NOT NULL,
    mtime     REAL NOT NULL,             -- aus der Datei, nicht aus der Uhr
    -- FIX-04 Schritt 4: beide stehen im Frontmatter der Notiz und damit in der
    -- WAHRHEIT. Hier sind sie nur abgeleitet - `rm data/jarvis.db` und ein
    -- reindex holen sie vollstaendig zurueck.
    widerspruch TEXT,                    -- id der aelteren, widersprechenden Notiz
    bestaetigt  INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS vault_notizen_pfad ON vault_notizen(pfad);

CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(
    text,
    tags,
    content='vault_notizen',
    content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TRIGGER IF NOT EXISTS vault_fts_ai AFTER INSERT ON vault_notizen BEGIN
    INSERT INTO vault_fts(rowid, text, tags) VALUES (new.rowid, new.text, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS vault_fts_ad AFTER DELETE ON vault_notizen BEGIN
    INSERT INTO vault_fts(vault_fts, rowid, text, tags)
    VALUES ('delete', old.rowid, old.text, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS vault_fts_au AFTER UPDATE ON vault_notizen BEGIN
    INSERT INTO vault_fts(vault_fts, rowid, text, tags)
    VALUES ('delete', old.rowid, old.text, old.tags);
    INSERT INTO vault_fts(rowid, text, tags) VALUES (new.rowid, new.text, new.tags);
END;


-- ---------------------------------------------------------------------------
-- Nachschlage-Cache (docs/wissensquellen.md Abschnitt 4)
--
-- Dieselbe Frage zweimal kostet einmal. Nebeneffekt, der wichtiger ist als die
-- Ersparnis: Antworten werden konsistent, weil sie aus derselben gespeicherten
-- Quelle kommen.
--
-- `snapshot` ist Pflichtfeld der Quelle, nicht des Caches: es sagt, wie alt das
-- Wissen ist. `geholt_am` sagt, wann WIR es geholt haben. Zwei verschiedene
-- Dinge, die man nicht verwechseln darf.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS lookups (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    begriff    TEXT NOT NULL,
    quelle     TEXT NOT NULL,          -- wiki_lokal | wiki_live | wikidata
    text       TEXT NOT NULL,
    titel      TEXT NOT NULL DEFAULT '',
    snapshot   TEXT,                   -- Stand des Wissens, NULL bei Live-Quellen
    geholt_am  TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS lookups_begriff_quelle
    ON lookups(begriff, quelle);


-- ---------------------------------------------------------------------------
-- Weltlage (docs/phases/PHASE-11.md)
--
-- Cache je Land, TTL 60 Minuten. Ohne den kostet ein zweiter Klick auf
-- Deutschland einen zweiten Auftrag - und 195 Laender live zu halten waere
-- kein Dashboard, sondern ein Abo.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS weltlage_cache (
    land_iso   TEXT PRIMARY KEY,
    nutzlast   TEXT NOT NULL,          -- JSON: Meldungen + Zaehler
    geholt_am  TEXT NOT NULL
);

-- Getrennt vom Cache, weil der geleert werden darf und die Zaehlung nicht.
CREATE TABLE IF NOT EXISTS weltlage_zaehler (
    tag        TEXT PRIMARY KEY,       -- YYYY-MM-DD
    treffer    INTEGER NOT NULL DEFAULT 0,   -- aus dem Cache bedient
    abfragen   INTEGER NOT NULL DEFAULT 0,   -- echte Auftraege
    verworfen  INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- FIX-08: Zeitplaene - Auftraege, die JARVIS von selbst wiederholt.
--
-- Zwei Tabellen, beide NEU (kein ALTER TABLE noetig, CREATE IF NOT EXISTS
-- reicht fuer alte wie frische Datenbanken).
--
-- `zeitplaene` ist der Plan, `zeitplan_laeufe` das Protokoll. Getrennt,
-- weil das Tagesbudget ueber das Protokoll gerechnet wird - ueber die
-- tatsaechlich gestarteten Tasks der letzten 24 Stunden, nicht ueber eine
-- Zahl, die jemand von Hand hochzaehlt.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zeitplaene (
    id              TEXT    PRIMARY KEY,
    name            TEXT    NOT NULL,
    ziel            TEXT    NOT NULL,          -- der Auftragstext, woertlich
    regel           TEXT    NOT NULL,          -- 'taeglich 07:00' | 'alle 6 stunden'
    aktiv           INTEGER NOT NULL DEFAULT 1,
    erstellt_am     TEXT    NOT NULL,          -- UTC, 'Z'
    naechster_lauf  TEXT,                      -- UTC, 'Z'. NULL = pausiert
    letzter_lauf    TEXT,                      -- UTC, 'Z'
    letzter_task_id TEXT    REFERENCES tasks(id) ON DELETE SET NULL,
    letzter_status  TEXT,                      -- 'done' | 'failed' | 'uebersprungen: ...'
    verpasst        INTEGER NOT NULL DEFAULT 0 -- Laeufe, die nicht nachgeholt wurden
);

CREATE TABLE IF NOT EXISTS zeitplan_laeufe (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    -- NULL nach dem Loeschen des Plans, NICHT mitgeloescht: sonst liesse
    -- sich der Tagesdeckel durch Loeschen und Neuanlegen zuruecksetzen
    -- (zweite Pruefrunde FIX-08). Alte Datenbanken zieht scripts/migrate.py nach.
    zeitplan_id   TEXT    REFERENCES zeitplaene(id) ON DELETE SET NULL,
    task_id       TEXT    REFERENCES tasks(id) ON DELETE SET NULL,
    gestartet_am  TEXT    NOT NULL,            -- UTC, 'Z'
    ausloeser     TEXT    NOT NULL             -- 'zeitplan' | 'hand'
);
CREATE INDEX IF NOT EXISTS zeitplan_laeufe_zeit ON zeitplan_laeufe(gestartet_am);
