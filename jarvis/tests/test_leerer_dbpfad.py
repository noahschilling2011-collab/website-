"""Ein leerer Datenbankpfad muss knallen, nicht schweigen.

`sqlite3.connect("")` wirft nicht. Es legt eine private, namenlose Datenbank
an, die beim Schliessen der Verbindung verschwindet. Ein `remember`, das so
laeuft, meldet Erfolg — und der gemerkte Satz ist weg. Genau diese Falle stand
in `core/tools/memory_tools.py` als Vorgabewert `db_path = ""`.
"""

from __future__ import annotations

import sqlite3

import pytest

import api.app  # noqa: F401  - registriert die Werkzeuge
from core.db import connect
from core.tools import registry
from tests.conftest import run


def test_sqlite_wuerde_wirklich_schweigen():
    """Die Gegenprobe: ohne Wache passiert genau das Beschriebene."""
    conn = sqlite3.connect("")
    conn.execute("CREATE TABLE t (x)")
    conn.execute("INSERT INTO t VALUES (1)")
    assert conn.execute("SELECT count(*) FROM t").fetchone()[0] == 1
    conn.close()
    # Die naechste Verbindung sieht davon nichts - es war eine Wegwerf-DB.
    zweite = sqlite3.connect("")
    with pytest.raises(sqlite3.OperationalError):
        zweite.execute("SELECT count(*) FROM t")
    zweite.close()


@pytest.mark.parametrize("pfad", ["", "   "])
def test_connect_lehnt_leeren_pfad_ab(pfad):
    with pytest.raises(ValueError, match="Leerer Datenbankpfad"):
        connect(pfad)


def test_memory_speicher_bleibt_erlaubt():
    """Gegenprobe: `:memory:` ist ein gueltiger Pfad und darf nicht mitgefangen werden."""
    conn = connect(":memory:")
    conn.execute("CREATE TABLE t (x)")
    conn.close()


@pytest.mark.parametrize("name", ["remember", "recall"])
def test_werkzeug_ohne_verdrahtung_meldet_das(name, monkeypatch):
    tool = registry.get(name)
    assert tool is not None
    monkeypatch.setattr(tool, "db_path", "", raising=False)
    with pytest.raises(ValueError, match="db_path ist leer"):
        tool.pfad()


def test_ueber_den_dispatcher_wird_daraus_ein_ordentlicher_fehler(monkeypatch):
    """Kein Absturz nach oben: der Dispatcher macht ein ToolResult daraus."""
    from core.tools.dispatch import run_tool

    tool = registry.get("remember")
    monkeypatch.setattr(tool, "db_path", "", raising=False)
    ergebnis = run(run_tool("remember", {"text": "geht verloren"}))
    assert ergebnis.ok is False
    assert "db_path ist leer" in (ergebnis.error or "")
