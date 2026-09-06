"""Migration von Hand (Phase 10, seit FIX-11 eine Huelle).

    python -m scripts.migrate [--dry-run] [--db pfad]

Die Arbeit steht in `core/migration.py` - dort, weil der Start sie seit
FIX-11 selbst erledigt (nach `quick_check` und Sicherung, eine Log-Zeile je
Befehl). Dieses Skript bleibt fuer den Trockenlauf und fuer eine Datenbank,
die nicht die aus der `.env` ist.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from core.config import get_settings
from core.migration import (  # noqa: F401 - Huelle: alte Importpfade bleiben
    FTS_INDIZES,
    SPALTEN,
    ausstehend,
    fehlende_spalten,
    fts_nachziehen,
    migriere,
    zeitplan_laeufe_nachziehen,
)


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
