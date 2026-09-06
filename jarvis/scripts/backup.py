"""Backup und Restore von Hand (Phase 10, seit FIX-11 eine Huelle).

    python -m scripts.backup sichern  [ziel.db]
    python -m scripts.backup einspielen [quelle.db] [--force]
    python -m scripts.backup pruefen  datei.db

Die Arbeit steht in `core/sicherung.py` - dort, weil der Start sie seit
FIX-11 selbst erledigt (einmal je 24 Stunden, vor jeder Migration, hoechstens
sieben Staende in `<Datenbank>/../sicherungen/`). Dieses Skript ist der Weg
fuer die Hand: eine Sicherung sofort, eine pruefen, eine einspielen.

`einspielen` ohne Datei nimmt die juengste eigene Sicherung - das ist der
Befehl, den der Startabbruch bei einer beschaedigten Datenbank nennt.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path

from core.config import get_settings
from core.sicherung import (  # noqa: F401 - Huelle: alte Importpfade bleiben
    einspielen,
    juengste_datei,
    pruefen,
    sichern,
    tabellen,
    zaehle,
    ziel_pfad,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Backup und Restore von JARVIS.")
    unter = parser.add_subparsers(dest="befehl", required=True)

    b = unter.add_parser("sichern", help="Datenbank sichern")
    b.add_argument("ziel", nargs="?", default=None)

    e = unter.add_parser("einspielen", help="Backup einspielen")
    e.add_argument("quelle", nargs="?", default=None,
                   help="Sicherungsdatei; ohne Angabe die juengste eigene")
    e.add_argument("--force", action="store_true",
                   help="ohne Sicherheitskopie der bisherigen Datenbank")

    p = unter.add_parser("pruefen", help="Backup pruefen")
    p.add_argument("datei")

    args = parser.parse_args()
    settings = get_settings()
    db_pfad = Path(settings.db_path)

    if args.befehl == "sichern":
        ziel = (Path(args.ziel) if args.ziel
                else ziel_pfad(db_pfad, datetime.now(timezone.utc)))
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

    quelle = Path(args.quelle) if args.quelle else juengste_datei(db_pfad)
    if quelle is None:
        print("Es gibt keine eigene Sicherung neben der Datenbank - "
              "bitte eine Datei angeben.", file=sys.stderr)
        return 1
    vorher = zaehle(db_pfad) if db_pfad.exists() else {}
    einspielen(quelle, db_pfad, force=args.force)
    nachher = zaehle(db_pfad)
    print(f"Eingespielt: {quelle.name} nach {db_pfad}")
    for tabelle, anzahl in nachher.items():
        print(f"  {tabelle:<12} {vorher.get(tabelle, 0)} -> {anzahl}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
