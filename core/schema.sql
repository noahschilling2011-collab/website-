-- Schema von JARVIS, Phase 1.
--
-- Zwei Tabellen, mehr braucht diese Phase nicht. Spaetere Phasen fuegen
-- Tabellen hinzu (facts, tasks, steps, tool_calls); diese hier werden
-- dabei nicht umgebaut.
--
-- Zeitstempel sind UTC in ISO-8601 mit 'Z'. SQLite kennt keinen Datumstyp;
-- ein sortierbarer Text ist die ehrlichere Loesung als ein Unix-Integer,
-- den man beim Draufschauen nicht lesen kann.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS conversations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL
                    REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT    NOT NULL CHECK (role IN ('user', 'assistant')),
    content         TEXT    NOT NULL,
    -- Modell und Token stehen nur an Assistenten-Zeilen. Sie werden hier
    -- schon mitgeschrieben, damit Phase 2 die Kosten rueckwirkend rechnen
    -- kann statt erst ab Umstellung.
    model           TEXT,
    input_tokens    INTEGER NOT NULL DEFAULT 0,
    output_tokens   INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT    NOT NULL
);

-- Der Verlauf wird immer je Konversation in Reihenfolge gelesen.
CREATE INDEX IF NOT EXISTS idx_messages_conversation
    ON messages(conversation_id, id);

-- Die Seitenleiste zeigt zuletzt benutzte zuerst.
CREATE INDEX IF NOT EXISTS idx_conversations_updated
    ON conversations(updated_at DESC);
