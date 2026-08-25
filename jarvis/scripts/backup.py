"""Backup und Restore (Phase 10).

    python -m scripts.backup sichern  [ziel.db]
    python -m scripts.backup einspielen quelle.db [--force]
    python -m scripts.backup pruefen  datei.db

Gesichert wird ueber `sqlite3.Connection.backup()`, nicht ueber `cp`. Das ist
der Unterschied: bei eingeschaltetem WAL liegen die letzten Schreibvorgaenge
in `-wal`, und eine kopierte `.db` allein ist unvollstaendig oder kaputt.
Die Backup-API sperrt sauber und schreibt einen konsistenten Stand - auch
waehrend JARVIS laeuft.

Ein Restore, der nie eingespielt wurde, ist kein Backup. `pruefen` oeffnet
die Datei, laesst SQLite den Integritaetscheck laufen und zaehlt die Zeilen.
"""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from core.config import get_settings

TABELLEN = ("messages", "llm_calls", "tool_calls", "facts", "task_log",
            "tasks", "steps", "audit_log")


def sichern(quelle: Path, ziel: Path) -> Path:
    if not quelle.exists():
        raise FileNotFoundError(f"Es gibt keine Datenbank unter {quelle}.")
    ziel.parent.mkdir(parents=True, exist_ok=True)

    src = sqlite3.connect(quelle)
    dst = sqlite3.connect(ziel)
    try:
        # Die Backup-API kopiert Seiten unter Sperre - inklusive allem, was
        # noch im WAL steht.
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    return ziel


def zaehle(datei: Path) -> dict[str, int]:
    conn = sqlite3.connect(datei)
    try:
        vorhanden = {
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        return {
            t: conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            for t in TABELLEN if t in vorhanden
        }
    finally:
        conn.close()


def pruefen(datei: Path) -> tuple[bool, str, dict[str, int]]:
    if not datei.exists():
        return False, f"{datei} gibt es nicht.", {}
    conn = sqlite3.connect(datei)
    try:
        ergebnis = conn.execute("PRAGMA integrity_check").fetchone()[0]
    except sqlite3.DatabaseError as exc:
        return False, f"Keine lesbare SQLite-Datei: {exc}", {}
    finally:
        conn.close()
    if ergebnis != "ok":
        return False, f"Integritaetscheck: {ergebnis}", {}
    return True, "ok", zaehle(datei)


def einspielen(quelle: Path, ziel: Path, *, force: bool = False) -> Path:
    heil, meldung, _ = pruefen(quelle)
    if not heil:
        raise ValueError(f"Das Backup ist nicht brauchbar - {meldung}")

    if ziel.exists() and not force:
        # Vor dem Ueberschreiben die alte Datei beiseitelegen. Ein Restore,
        # der das Vorherige unwiederbringlich loescht, ist eine Falle.
        stempel = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        beiseite = ziel.with_suffix(f".vor-restore-{stempel}.db")
        shutil.copy2(ziel, beiseite)
        print(f"Bisherige Datenbank gesichert nach {beiseite}")

    ziel.parent.mkdir(parents=True, exist_ok=True)
    for anhang in ("-wal", "-shm"):
        rest = Path(str(ziel) + anhang)
        if rest.exists():
            rest.unlink()

    src = sqlite3.connect(quelle)
    dst = sqlite3.connect(ziel)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    return ziel


def main() -> int:
    parser = argparse.ArgumentParser(description="Backup und Restore von JARVIS.")
    unter = parser.add_subparsers(dest="befehl", required=True)

    b = unter.add_parser("sichern", help="Datenbank sichern")
    b.add_argument("ziel", nargs="?", default=None)

    e = unter.add_parser("einspielen", help="Backup einspielen")
    e.add_argument("quelle")
    e.add_argument("--force", action="store_true",
                   help="ohne Sicherheitskopie der bisherigen Datenbank")

    p = unter.add_parser("pruefen", help="Backup pruefen")
    p.add_argument("datei")

    args = parser.parse_args()
    settings = get_settings()
    db_pfad = Path(settings.db_path)

    if args.befehl == "sichern":
        stempel = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        ziel = Path(args.ziel) if args.ziel else db_pfad.parent / f"backup-{stempel}.db"
        sichern(db_pfad, ziel)
        heil, meldung, zeilen = pruefen(ziel)
        print(f"Gesichert nach {ziel} ({ziel.stat().st_size / 1024:.0f} KB)")
        print(f"Integritaet: {meldung}")
        for tabelle, anzahl in zeilen.items():
            print(f"  {tabelle:<12} {anzahl}")
        return 0 if heil else 1

    if args.befehl == "pruefen":
        heil, meldung, zeilen = pruefen(Path(args.datei))
        print(f"Integritaet: {meldung}")
        for tabelle, anzahl in zeilen.items():
            print(f"  {tabelle:<12} {anzahl}")
        return 0 if heil else 1

    vorher = zaehle(db_pfad) if db_pfad.exists() else {}
    einspielen(Path(args.quelle), db_pfad, force=args.force)
    nachher = zaehle(db_pfad)
    print(f"Eingespielt nach {db_pfad}")
    for tabelle, anzahl in nachher.items():
        print(f"  {tabelle:<12} {vorher.get(tabelle, 0)} -> {anzahl}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
