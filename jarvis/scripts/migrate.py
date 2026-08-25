"""Migration bestehender Datenbanken (Phase 10).

    python -m scripts.migrate [--dry-run]

`core/schema.sql` legt alles mit `CREATE TABLE IF NOT EXISTS` an - das
genuegt fuer neue Dateien, aber nicht fuer eine, die schon in Phase 1
entstanden ist. Spaetere Phasen haben Spalten dazugelegt:

    Phase 2  llm_calls.prompt_hash
    Phase 6  facts.conflicts_with
    Phase 7  steps.prompt

Diese Migration ist idempotent: sie schaut nach, was fehlt, und legt nur das
an. Zweimal laufen lassen schadet nicht.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from core import db
from core.config import get_settings

# (Tabelle, Spalte, Definition) - Reihenfolge ist die der Phasen.
SPALTEN = [
    ("llm_calls", "prompt_hash", "TEXT NOT NULL DEFAULT ''"),
    ("facts", "conflicts_with", "INTEGER"),
    ("steps", "prompt", "TEXT NOT NULL DEFAULT ''"),
]


def fehlende_spalten(conn: sqlite3.Connection) -> list[tuple[str, str, str]]:
    fehlt = []
    tabellen = {
        r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    for tabelle, spalte, definition in SPALTEN:
        if tabelle not in tabellen:
            continue   # legt schema.sql beim naechsten Start an
        vorhanden = {r[1] for r in conn.execute(f"PRAGMA table_info({tabelle})")}
        if spalte not in vorhanden:
            fehlt.append((tabelle, spalte, definition))
    return fehlt


def migriere(db_pfad: Path, *, dry_run: bool = False) -> list[str]:
    getan: list[str] = []
    with db.session(db_pfad) as conn:
        # Erst das Schema anwenden: neue Tabellen, Indizes und Trigger
        # entstehen dadurch von selbst.
        if not dry_run:
            db.init_db(conn)

        for tabelle, spalte, definition in fehlende_spalten(conn):
            befehl = f"ALTER TABLE {tabelle} ADD COLUMN {spalte} {definition}"
            getan.append(befehl)
            if not dry_run:
                conn.execute(befehl)
    return getan


def main() -> int:
    parser = argparse.ArgumentParser(description="Migriert die JARVIS-Datenbank.")
    parser.add_argument("--dry-run", action="store_true",
                        help="nur anzeigen, was passieren wuerde")
    parser.add_argument("--db", default=None, help="abweichender Pfad")
    args = parser.parse_args()

    pfad = Path(args.db) if args.db else Path(get_settings().db_path)
    if not pfad.exists():
        print(f"Es gibt noch keine Datenbank unter {pfad} - "
              "sie entsteht beim ersten Start.")
        return 0

    getan = migriere(pfad, dry_run=args.dry_run)
    if not getan:
        print(f"{pfad} ist aktuell. Nichts zu tun.")
        return 0

    for befehl in getan:
        print(("[dry-run] " if args.dry_run else "ausgefuehrt: ") + befehl)
    return 0


if __name__ == "__main__":
    sys.exit(main())
