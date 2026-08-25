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
    in_tokens    INTEGER NOT NULL DEFAULT 0,
    out_tokens   INTEGER NOT NULL DEFAULT 0,
    cost_eur     REAL    NOT NULL DEFAULT 0.0,
    duration_ms  INTEGER NOT NULL DEFAULT 0,
    ok           INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_id ON messages(id);
CREATE INDEX IF NOT EXISTS idx_llm_calls_created ON llm_calls(created_at DESC);
