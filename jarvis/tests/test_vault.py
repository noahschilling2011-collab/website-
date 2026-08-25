"""Die Definition of Done aus `docs/MIGRATION-VAULT.md`, als Tests.

Das Prinzip, an dem alles haengt:

    vault/*.md    = WAHRHEIT
    SQLite + FTS5 = INDEX, abgeleitet, jederzeit neu baubar

Deshalb prueft hier nichts eine Zwei-Wege-Synchronisation: die gibt es nicht,
und wenn ein Test eine braeuchte, waere das Prinzip verletzt.
"""

from __future__ import annotations

import sqlite3
import time
from pathlib import Path

import pytest

from core.db import connect, init_db, session
from core.vault import (
    IGNORIERT,
    Notiz,
    VaultKonflikt,
    dateien,
    dateiname,
    finde,
    lies,
    neue_id,
    schreibe,
    serialisiere,
    sicherstellen,
    trenne,
)
from core.vault_index import (
    aktualisiere,
    alle,
    entferne,
    mtime_von,
    reindex,
    suche,
    verschiebe,
)


@pytest.fixture
def vault(tmp_path: Path) -> Path:
    return sicherstellen(tmp_path / "Vault")


@pytest.fixture
def db(tmp_path: Path) -> Path:
    pfad = tmp_path / "index.db"
    conn = connect(pfad)
    init_db(conn)
    conn.close()
    return pfad


def notiz(text: str, **kw) -> Notiz:
    return Notiz(id=kw.pop("id", neue_id()), text=text, **kw)


# --- Dateiformat ------------------------------------------------------------


def test_frontmatter_geht_hin_und_zurueck(vault):
    n = notiz("Noah faehrt Downhill.", tags=["mtb", "ausruestung"],
              quelle="wiki_lokal", snapshot="2026-03-01")
    pfad = schreibe(vault, n)
    zurueck = lies(pfad)
    assert zurueck.id == n.id
    assert zurueck.text == n.text
    assert zurueck.tags == ["mtb", "ausruestung"]
    assert zurueck.quelle == "wiki_lokal"
    assert zurueck.snapshot == "2026-03-01"


def test_datei_ohne_id_ist_keine_jarvis_notiz(vault):
    fremd = vault / "fakten" / "handnotiz.md"
    fremd.write_text("# Einkaufszettel\n\nMilch", encoding="utf-8")
    with pytest.raises(ValueError, match="kein 'id'"):
        lies(fremd)


def test_offener_frontmatter_wird_nicht_geraten():
    kopf, koerper = trenne("---\nid: f_1\n\nkein Ende")
    assert kopf == {}
    assert "kein Ende" in koerper


def test_dateiname_ist_kosmetisch_die_id_steht_im_text(vault):
    n = notiz("Äußerst schöne Straße in Schwäbisch Gmünd!")
    name = dateiname(n)
    assert name.endswith(f"{n.id}.md")
    assert " " not in name and "ä" not in name


def test_schreiben_ist_atomar_keine_halben_dateien(vault):
    n = notiz("Ein Satz.")
    schreibe(vault, n)
    # Keine Temporaerdateien uebrig - Obsidian wuerde sie sonst anzeigen.
    assert not [p for p in vault.rglob(".*") if p.is_file() and p.name.endswith(".tmp")]


# --- DoD 1: Migration vollstaendig ------------------------------------------


def test_dod_1_jeder_fakt_wird_eine_notiz(db, vault):
    import subprocess
    import sys

    with session(db) as conn:
        conn.executemany(
            "INSERT INTO facts (text, category, created_at) VALUES (?, ?, ?)",
            [("Fakt eins.", "a", "2026-01-01T00:00:00Z"),
             ("Fakt zwei.", "b", "2026-01-02T00:00:00Z")],
        )
        vorher = conn.execute("SELECT count(*) FROM facts").fetchone()[0]

    import os
    umgebung = {**os.environ, "JARVIS_DB_PATH": str(db),
                "VAULT_PFAD": str(vault), "JARVIS_TOKEN": "t"}
    lauf = subprocess.run([sys.executable, "-m", "scripts.migrate_vault"],
                          capture_output=True, text=True, env=umgebung,
                          cwd=str(Path(__file__).resolve().parent.parent))
    assert lauf.returncode == 0, lauf.stdout + lauf.stderr
    assert len([t for t in alle(db) if t.typ == "fakt"]) == vorher


# --- DoD 2/3: Aenderungen von aussen ----------------------------------------


def test_dod_2_neue_notiz_wird_gefunden(db, vault):
    pfad = schreibe(vault, notiz("Der Hund heisst Bruno."))
    aktualisiere(db, vault, pfad)
    assert [t.text for t in suche(db, "Bruno")] == ["Der Hund heisst Bruno."]


def test_dod_3_geaenderte_notiz_liefert_den_neuen_inhalt(db, vault):
    n = notiz("Der Hund heisst Bruno.")
    pfad = schreibe(vault, n)
    aktualisiere(db, vault, pfad)

    # Von Hand in Obsidian geaendert:
    n.text = "Der Hund heisst Emil."
    pfad.write_text(serialisiere(n), encoding="utf-8")
    aktualisiere(db, vault, pfad)

    assert not suche(db, "Bruno")
    assert [t.text for t in suche(db, "Emil")] == ["Der Hund heisst Emil."]


# --- DoD 4: der Test, der die Schluesselwahl beweist ------------------------


def test_dod_4_umbenennen_ueberlebt_der_fakt(db, vault):
    n = notiz("Mein Rad ist ein Santa Cruz V10.")
    alt = schreibe(vault, n)
    aktualisiere(db, vault, alt)

    neu = alt.with_name("ganz-anderer-name.md")
    alt.rename(neu)
    verschiebe(db, vault, alt, neu)

    treffer = suche(db, "Santa Cruz")
    assert len(treffer) == 1
    assert treffer[0].id == n.id, "die id im Frontmatter ist der Schluessel"
    assert treffer[0].pfad.endswith("ganz-anderer-name.md")


def test_verschieben_in_einen_anderen_ordner(db, vault):
    n = notiz("Ein Projektfakt.")
    alt = schreibe(vault, n)
    aktualisiere(db, vault, alt)

    neu = vault / "projekte" / alt.name
    alt.rename(neu)
    verschiebe(db, vault, alt, neu)

    treffer = suche(db, "Projektfakt")
    assert len(treffer) == 1 and treffer[0].pfad.startswith("projekte")


# --- DoD 5: loeschen ist loeschen -------------------------------------------


def test_dod_5_geloeschte_notiz_ist_weg(db, vault):
    pfad = schreibe(vault, notiz("Ein fluechtiger Fakt."))
    aktualisiere(db, vault, pfad)
    assert suche(db, "fluechtiger")

    pfad.unlink()
    entferne(db, vault, pfad)
    assert suche(db, "fluechtiger") == []


# --- DoD 6: Idempotenz ------------------------------------------------------


def _abzug(db_path) -> list[tuple]:
    with session(db_path) as conn:
        return conn.execute(
            "SELECT id, pfad, typ, quelle, erfasst, snapshot, tags, text, mtime "
            "FROM vault_notizen ORDER BY id"
        ).fetchall()


def test_dod_6_zweimal_neu_indexieren_gibt_dasselbe(db, vault):
    for i in range(4):
        schreibe(vault, notiz(f"Fakt Nummer {i}."))

    reindex(db, vault)
    erster = [tuple(z) for z in _abzug(db)]
    reindex(db, vault)
    zweiter = [tuple(z) for z in _abzug(db)]

    assert erster == zweiter, "im Index steckt Zustand, der nicht im Vault steht"
    assert len(erster) == 4


def test_index_ist_wegwerfbar(db, vault):
    schreibe(vault, notiz("Ueberlebt das Wegwerfen."))
    reindex(db, vault)
    with session(db) as conn:
        conn.execute("DELETE FROM vault_notizen")
    assert suche(db, "Ueberlebt") == []
    reindex(db, vault)
    assert [t.text for t in suche(db, "Ueberlebt")] == ["Ueberlebt das Wegwerfen."]


# --- DoD 8: Konflikte -------------------------------------------------------


def test_dod_8_fremde_aenderung_wird_nicht_still_ueberschrieben(db, vault):
    n = notiz("Erster Stand.")
    pfad = schreibe(vault, n)
    aktualisiere(db, vault, pfad)
    bekannt = mtime_von(db, n.id)

    # Ein Mensch aendert die Datei in Obsidian.
    time.sleep(0.01)
    pfad.write_text(serialisiere(Notiz(id=n.id, text="Von Hand geaendert.")),
                    encoding="utf-8")

    n.text = "JARVIS will ueberschreiben."
    with pytest.raises(VaultKonflikt) as fehler:
        schreibe(vault, n, bekannt_bis=bekannt)

    assert "Von Hand geaendert." in pfad.read_text(encoding="utf-8"), \
        "der Stand des Menschen wurde ueberschrieben"
    assert fehler.value.konfliktdatei.exists()
    assert "konflikt" in fehler.value.konfliktdatei.name


def test_ohne_bekannt_bis_wird_normal_geschrieben(vault):
    """Der Konfliktschutz greift nur, wenn ein Index-Stand bekannt ist."""
    n = notiz("Erster Stand.")
    schreibe(vault, n)
    n.text = "Zweiter Stand."
    pfad = schreibe(vault, n)
    assert "Zweiter Stand." in pfad.read_text(encoding="utf-8")


# --- DoD 9: Obsidians und gits eigene Ordner --------------------------------


def test_dod_9_obsidian_und_git_bleiben_draussen(db, vault):
    (vault / ".obsidian").mkdir(exist_ok=True)
    (vault / ".obsidian" / "workspace.md").write_text(
        "---\nid: nicht_indexieren\n---\n\nObsidian-Konfiguration", encoding="utf-8")
    (vault / ".git").mkdir(exist_ok=True)
    (vault / ".git" / "COMMIT_EDITMSG.md").write_text(
        "---\nid: auch_nicht\n---\n\nCommit", encoding="utf-8")
    schreibe(vault, notiz("Echter Fakt."))

    reindex(db, vault)
    ids = {t.id for t in alle(db)}
    assert "nicht_indexieren" not in ids
    assert "auch_nicht" not in ids
    assert len(ids) == 1

    with session(db) as conn:
        aus_verboten = conn.execute(
            "SELECT count(*) FROM vault_notizen WHERE pfad LIKE '.obsidian%' "
            "OR pfad LIKE '.git%'"
        ).fetchone()[0]
    assert aus_verboten == 0


def test_die_ignorierliste_greift_ueberhaupt():
    """Gegenprobe: die Namen stimmen mit dem, was Obsidian wirklich anlegt."""
    assert ".obsidian" in IGNORIERT and ".git" in IGNORIERT


# --- Schritt 5: nie den ganzen Vault in einen Prompt -------------------------


def test_abruf_ist_gedeckelt(db, vault):
    for i in range(20):
        schreibe(vault, notiz(f"Fakt ueber Fahrrad Nummer {i}."))
    reindex(db, vault)
    assert len(suche(db, "Fahrrad", limit=5)) == 5


def test_recall_nennt_immer_die_quelldatei(db, vault, monkeypatch):
    import api.app  # noqa: F401
    from core.tools import registry
    from tests.conftest import run
    from core.tools.dispatch import run_tool

    pfad = schreibe(vault, notiz("Der Kaffee wird schwarz getrunken."))
    aktualisiere(db, vault, pfad)

    werkzeug = registry.get("recall")
    monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
    monkeypatch.setattr(werkzeug, "vault_pfad", str(vault), raising=False)

    ergebnis = run(run_tool("recall", {"query": "Kaffee"}))
    assert ergebnis.ok
    assert ergebnis.sources, "Antwort ohne Herkunft ist eine Behauptung"
    assert ergebnis.sources[0].endswith(".md")
    assert ergebnis.sources[0] in ergebnis.display


def test_ohne_vault_bleibt_alles_beim_alten(db, monkeypatch):
    """Leerer VAULT_PFAD heisst: nichts aendert sich, nichts wird angelegt."""
    import api.app  # noqa: F401
    from core.tools import registry
    from core.tools.dispatch import run_tool
    from tests.conftest import run

    for name in ("remember", "recall"):
        werkzeug = registry.get(name)
        monkeypatch.setattr(werkzeug, "db_path", db, raising=False)
        monkeypatch.setattr(werkzeug, "vault_pfad", "", raising=False)

    assert run(run_tool("remember", {"text": "Alter Weg."})).ok
    ergebnis = run(run_tool("recall", {"query": "Alter"}))
    assert ergebnis.ok and "Fakt #" in ergebnis.display


def test_dateien_uebersieht_versteckte(vault):
    (vault / "fakten" / ".versteckt.md").write_text("---\nid: x\n---\n\nx", encoding="utf-8")
    schreibe(vault, notiz("Sichtbar."))
    assert all(not p.name.startswith(".") for p in dateien(vault))


# --- DoD 2, mit dem laufenden Beobachter ------------------------------------


def test_dod_2_beobachter_findet_eine_neue_notiz_in_unter_3_sekunden(db, vault):
    """Mit Zeitstempeln, wie die DoD es verlangt."""
    from core.vault_index import Beobachter

    with Beobachter(db, vault, entprellung=0.3):
        time.sleep(0.4)                       # Beobachter hochfahren lassen
        geschrieben = time.monotonic()
        schreibe(vault, notiz("Ein Fakt ueber Zugvoegel."))

        gefunden = None
        while time.monotonic() - geschrieben < 3.0:
            if suche(db, "Zugvoegel"):
                gefunden = time.monotonic()
                break
            time.sleep(0.05)

    assert gefunden is not None, "nach 3 s nicht im Index"
    dauer = gefunden - geschrieben
    assert dauer < 3.0
    print(f"\n    geschrieben -> im Index: {dauer:.2f} s")


def test_beobachter_bemerkt_auch_das_loeschen(db, vault):
    from core.vault_index import Beobachter

    pfad = schreibe(vault, notiz("Verschwindet gleich."))
    reindex(db, vault)
    assert suche(db, "Verschwindet")

    with Beobachter(db, vault, entprellung=0.3):
        time.sleep(0.4)
        pfad.unlink()
        frist = time.monotonic() + 3.0
        while time.monotonic() < frist and suche(db, "Verschwindet"):
            time.sleep(0.05)

    assert suche(db, "Verschwindet") == []


def test_entprellung_indexiert_nicht_fuenfmal(db, vault):
    """Editoren schreiben mehrfach hintereinander. Einmal reicht."""
    from core.vault_index import Beobachter

    n = notiz("Mehrfach gespeichert.")
    with Beobachter(db, vault, entprellung=0.4):
        time.sleep(0.4)
        for i in range(5):
            n.text = f"Mehrfach gespeichert, Fassung {i}."
            schreibe(vault, n)
            time.sleep(0.05)
        time.sleep(1.2)

    treffer = suche(db, "Mehrfach")
    assert len(treffer) == 1, "eine Datei, ein Eintrag"
    assert "Fassung 4" in treffer[0].text, "der letzte Stand muss gewinnen"
