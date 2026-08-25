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
