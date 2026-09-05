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
import re
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
    # FIX-04 Schritt 4
    ("vault_notizen", "widerspruch", "TEXT"),
    ("vault_notizen", "bestaetigt", "INTEGER NOT NULL DEFAULT 0"),
    # FIX-09
    ("zeitplaene", "fehlschlaege", "INTEGER NOT NULL DEFAULT 0"),
    ("zeitplaene", "art", "TEXT NOT NULL DEFAULT 'auftrag'"),
]


# (FTS-Tabelle, Quelltabelle, rowid-Spalte, [(FTS-Spalte, Quellspalte), ...])
#
# BUGS-01 Fund 17: `init_db` legt die FTS-Tabellen an, aber der Index ueber die
# BESTEHENDEN Zeilen bleibt leer. Neue Zeilen holen die Trigger ab; die alte
# Historie war danach fuer `recall` unsichtbar - gemessen:
#
#     Zeilen in messages    : 3
#     Eintraege im FTS-Index: 0
#     Volltextsuche nach 'santa': []
#
# Befuellt wird von Hand statt mit dem eingebauten `'rebuild'`. Der geht bei
# `messages_fts` naemlich nicht: die FTS-Spalte heisst `content_text`, die
# Quellspalte `content`, und FTS5 verlangt fuer eine `content=`-Tabelle gleiche
# Namen. Ausgefuehrt:
#
#     rebuild messages_fts   -> OperationalError: no such column: T.content_text
#     rebuild facts_fts      -> ok
#     rebuild vault_fts      -> ok
#
# Das ist der "Reparaturbefehl, der selbst kaputt ist" aus dem Bericht. Die
# Spalten anzugleichen hiesse, den Index in jeder bestehenden Datenbank neu
# aufzubauen - dafuer ist der Gewinn zu klein. Ein Test haelt die Annahme fest.
FTS_INDIZES = [
    ("messages_fts", "messages", "id", [("content_text", "content")]),
    ("facts_fts", "facts", "id", [("text", "text")]),
    ("vault_fts", "vault_notizen", "rowid", [("text", "text"), ("tags", "tags")]),
]


def _tabellen(conn: sqlite3.Connection) -> set[str]:
    return {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}


def fts_nachziehen(conn: sqlite3.Connection) -> list[str]:
    """Fuellt leere Volltextindizes aus ihren Quelltabellen.

    Nur wenn der Index wirklich leer ist und die Quelle Zeilen hat. Sonst
    entstuenden beim zweiten Lauf Doppelte - und das Modul verspricht
    ausdruecklich, dass zweimal Laufen nicht schadet.

    Die Leerpruefung geht ueber die Schattentabelle `<fts>_docsize`. `SELECT
    count(*) FROM <fts>` waere der naheliegende Weg, liest aber die
    Quelltabelle - und scheitert bei `messages_fts` an derselben
    Namensabweichung wie `'rebuild'`.
    """
    getan: list[str] = []
    vorhanden = _tabellen(conn)
    for fts, quelle, rowid, spalten in FTS_INDIZES:
        if fts not in vorhanden or quelle not in vorhanden:
            continue
        if f"{fts}_docsize" not in vorhanden:
            continue
        im_index = conn.execute(f"SELECT count(*) FROM {fts}_docsize").fetchone()[0]
        in_quelle = conn.execute(f"SELECT count(*) FROM {quelle}").fetchone()[0]
        if im_index or not in_quelle:
            continue
        ziel = ", ".join(z for z, _ in spalten)
        her = ", ".join(q for _, q in spalten)
        befehl = (f"INSERT INTO {fts}(rowid, {ziel}) "
                  f"SELECT {rowid}, {her} FROM {quelle}")
        conn.execute(befehl)
        getan.append(f"{befehl}   -- {in_quelle} Zeile(n)")
    return getan


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


def zeitplan_laeufe_nachziehen(conn: sqlite3.Connection, *, dry_run: bool) -> list[str]:
    """FIX-08, zweite Pruefrunde: `zeitplan_laeufe.zeitplan_id` war NOT NULL
    mit ON DELETE CASCADE - beim Loeschen eines Plans verschwand sein
    Protokoll, und mit ihm der Verbrauch aus dem Tagesdeckel. Jetzt wird die
    Spalte NULL. SQLite kann einen Fremdschluessel nicht aendern, also wird
    die Tabelle neu gebaut und der Inhalt kopiert."""
    zeile = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='zeitplan_laeufe'"
    ).fetchone()
    sql = (zeile[0] if zeile else "") or ""
    alt_ = "CASCADE" in sql or re.search(r"zeitplan_id\s+TEXT\s+NOT\s+NULL", sql)
    if zeile is None or not alt_:
        return []
    befehl = "zeitplan_laeufe neu bauen (zeitplan_id: ON DELETE CASCADE -> SET NULL)"
    if dry_run:
        return [befehl]
    conn.execute("ALTER TABLE zeitplan_laeufe RENAME TO zeitplan_laeufe_alt")
    db.init_db(conn)                       # legt die neue Tabelle an
    conn.execute(
        "INSERT INTO zeitplan_laeufe (id, zeitplan_id, task_id, gestartet_am, ausloeser) "
        "SELECT id, zeitplan_id, task_id, gestartet_am, ausloeser FROM zeitplan_laeufe_alt"
    )
    conn.execute("DROP TABLE zeitplan_laeufe_alt")   # nimmt den alten Index mit
    db.init_db(conn)                       # ... und der Index kommt neu
    return [befehl]


def migriere(db_pfad: Path, *, dry_run: bool = False) -> list[str]:
    getan: list[str] = []
    with db.session(db_pfad) as conn:
        getan.extend(zeitplan_laeufe_nachziehen(conn, dry_run=dry_run))
        # Erst das Schema anwenden: neue Tabellen, Indizes und Trigger
        # entstehen dadurch von selbst.
        if not dry_run:
            db.init_db(conn)

        for tabelle, spalte, definition in fehlende_spalten(conn):
            befehl = f"ALTER TABLE {tabelle} ADD COLUMN {spalte} {definition}"
            getan.append(befehl)
            if not dry_run:
                conn.execute(befehl)

        # BUGS-01 Fund 17: die Tabellen sind jetzt da, der Index ueber die
        # alten Zeilen noch nicht.
        if not dry_run:
            getan.extend(fts_nachziehen(conn))
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
