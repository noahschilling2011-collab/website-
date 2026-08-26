"""Den Index aus dem Vault neu aufbauen (FIX-04 Schritt 3).

    python -m scripts.reindex [--db PFAD] [--vault PFAD]

Der Vault ist die Wahrheit, die Datenbank nur ein Index. Dieser Befehl ist der
Beweis dafuer: er leert die Tabelle und baut sie vollstaendig aus `vault/*.md`
neu auf. Schluessel ist die `id` aus dem Frontmatter, nicht der Dateiname -
deshalb ueberlebt ein Fakt das Umbenennen in Obsidian.

Wer nach `rm data/jarvis.db` diesen Befehl laufen laesst, muss dieselbe Anzahl
und dieselben `id`s zurueckbekommen. Das ist der Pruefstein aus dem Auftrag.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from core.config import get_settings
from core.db import connect, init_db
from core.vault_index import reindex


def main() -> int:
    parser = argparse.ArgumentParser(description="Baut den Vault-Index neu auf.")
    parser.add_argument("--db", default=None, help="abweichender Datenbankpfad")
    parser.add_argument("--vault", default=None, help="abweichender Vault-Pfad")
    args = parser.parse_args()

    settings = get_settings()
    db_pfad = Path(args.db) if args.db else Path(settings.db_path)
    vault = args.vault if args.vault is not None else settings.vault_pfad

    if not str(vault).strip():
        print("VAULT_PFAD ist nicht gesetzt - ohne Vault gibt es nichts zu "
              "indexieren. Die Tabelle `facts` IST dann der Speicher.",
              file=sys.stderr)
        return 1

    wurzel = Path(str(vault)).expanduser()
    if not wurzel.exists():
        print(f"Der Vault {wurzel} existiert nicht.", file=sys.stderr)
        return 1

    # Die Datenbank darf fehlen - genau das ist der Sinn der Uebung.
    db_pfad.parent.mkdir(parents=True, exist_ok=True)
    conn = connect(db_pfad)
    try:
        init_db(conn)
    finally:
        conn.close()

    dateien = len(list(wurzel.rglob("*.md")))
    anzahl = reindex(db_pfad, wurzel)
    print(f"Vault:      {wurzel}")
    print(f"Datenbank:  {db_pfad}")
    print(f".md-Dateien:      {dateien}")
    print(f"indexierte Notizen: {anzahl}")
    if anzahl < dateien:
        print(f"\n{dateien - anzahl} Datei(en) wurden uebersprungen - sie haben "
              f"kein 'id' im Frontmatter oder sind nicht lesbar. Das Log oben "
              f"nennt jede einzeln.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
