"""Die Backup-Pruefung zaehlt JEDE Tabelle - abgeleitet, nicht gepflegt.

Bis FIX-08 stand in scripts/backup.py eine Liste von Hand. Sie hatte acht
Eintraege; das Schema hatte zwoelf eigene Tabellen. Vier fehlten still.
Dieser Test haelt die Zaehlung gegen das Schema selbst.
"""

from __future__ import annotations

import re
from pathlib import Path

from core import db
from scripts import backup

WURZEL = Path(__file__).resolve().parent.parent


def _tabellen_im_schema() -> set[str]:
    sql = (WURZEL / "core" / "schema.sql").read_text(encoding="utf-8")
    alle = set(re.findall(r"CREATE (?:VIRTUAL )?TABLE IF NOT EXISTS (\w+)", sql))
    return {t for t in alle if "_fts" not in t}


def test_zaehle_kennt_jede_tabelle_des_schemas(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    gezaehlt = backup.zaehle(db_path)
    erwartet = _tabellen_im_schema()
    assert erwartet, "Schema ohne Tabellen? Regex pruefen."
    assert set(gezaehlt) == erwartet
    assert {"zeitplaene", "zeitplan_laeufe", "lookups", "vault_notizen"} <= set(gezaehlt)
    assert all(n == 0 for n in gezaehlt.values())


def test_zaehle_zaehlt_wirklich(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    db.add_message(db_path, "user", "eins")
    db.add_message(db_path, "assistant", "zwei")
    assert backup.zaehle(db_path)["messages"] == 2
