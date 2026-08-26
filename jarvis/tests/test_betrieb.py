"""Tests von Backup, Migration und Healthcheck (Phase 10)."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from core import db, memory
from scripts.backup import einspielen, pruefen, sichern, zaehle
from scripts.migrate import fehlende_spalten, migriere


@pytest.fixture
def gefuellt(db_path: Path) -> Path:
    with db.session(db_path) as conn:
        db.init_db(conn)
    db.add_message(db_path, "user", "Mein Rad ist ein Santa Cruz V10")
    db.add_message(db_path, "assistant", "Gemerkt.")
    db.log_llm_call(db_path, model="m", prompt_hash="abc", in_tokens=10,
                    out_tokens=4, cost_eur=0.001, duration_ms=12, ok=True)
    memory._add_fact(db_path, "Ich fahre Downhill", category="hobby")
    memory.log_task(db_path, "t1", goal="Ziel", outcome="done")
    db.log_audit(db_path, tool="send_email", arguments={"to": "a@b.de"},
                 permission="EXTERNAL", decision="approved", executed=True)
    return db_path


# --- Backup ---------------------------------------------------------------


def test_das_backup_enthaelt_alle_zeilen(gefuellt: Path, tmp_path: Path):
    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    assert zaehle(ziel) == zaehle(gefuellt)
    assert zaehle(ziel)["messages"] == 2


def test_das_backup_nimmt_auch_mit_was_noch_im_wal_steht(gefuellt: Path, tmp_path: Path):
    """Deshalb die Backup-API und nicht `cp`.

    Bei eingeschaltetem WAL liegen die letzten Schreibvorgaenge in der
    -wal-Datei; eine kopierte .db allein waere unvollstaendig.
    """
    # Eine Verbindung offen halten, damit der WAL-Inhalt nicht eingecheckt wird.
    offen = db.connect(gefuellt)
    offen.execute(
        "INSERT INTO messages (role, content, created_at) "
        "VALUES ('user', 'ganz frisch', '2026-08-25T12:00:00Z')"
    )
    offen.commit()

    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    offen.close()

    with sqlite3.connect(ziel) as conn:
        texte = [r[0] for r in conn.execute("SELECT content FROM messages")]
    assert "ganz frisch" in texte


def test_pruefen_erkennt_eine_heile_datei(gefuellt: Path, tmp_path: Path):
    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    heil, meldung, zeilen = pruefen(ziel)
    assert heil is True and meldung == "ok"
    assert zeilen["facts"] == 1


def test_pruefen_erkennt_muell(tmp_path: Path):
    kaputt = tmp_path / "kaputt.db"
    kaputt.write_bytes(b"das ist keine datenbank")
    heil, meldung, _ = pruefen(kaputt)
    assert heil is False and "SQLite" in meldung


def test_pruefen_meldet_eine_fehlende_datei(tmp_path: Path):
    heil, meldung, _ = pruefen(tmp_path / "gibtsnicht.db")
    assert heil is False and "gibt es nicht" in meldung


def test_dod_4_ein_backup_laesst_sich_einspielen_und_ist_vollstaendig(
    gefuellt: Path, tmp_path: Path
):
    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    vorher = zaehle(gefuellt)

    # Schaden anrichten: alles weg.
    with db.session(gefuellt) as conn:
        conn.execute("DELETE FROM messages")
        conn.execute("DELETE FROM facts")
    assert zaehle(gefuellt)["messages"] == 0

    einspielen(ziel, gefuellt, force=True)

    assert zaehle(gefuellt) == vorher
    assert [m.content for m in db.list_messages(gefuellt)][0].startswith("Mein Rad")
    assert memory.list_facts(gefuellt)[0].text == "Ich fahre Downhill"


def test_der_restore_legt_die_bisherige_datenbank_beiseite(gefuellt: Path, tmp_path: Path):
    """Ein Restore, der das Vorherige unwiederbringlich loescht, ist eine Falle."""
    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    einspielen(ziel, gefuellt)
    beiseite = list(gefuellt.parent.glob("*.vor-restore-*.db"))
    assert len(beiseite) == 1
    assert zaehle(beiseite[0])["messages"] == 2


def test_ein_kaputtes_backup_wird_nicht_eingespielt(gefuellt: Path, tmp_path: Path):
    kaputt = tmp_path / "kaputt.db"
    kaputt.write_bytes(b"nein")
    with pytest.raises(ValueError, match="nicht brauchbar"):
        einspielen(kaputt, gefuellt)
    # Die bestehende Datenbank ist unangetastet.
    assert zaehle(gefuellt)["messages"] == 2


def test_das_audit_log_ueberlebt_den_restore(gefuellt: Path, tmp_path: Path):
    ziel = tmp_path / "sicherung.db"
    sichern(gefuellt, ziel)
    einspielen(ziel, gefuellt, force=True)
    assert len(db.list_audit(gefuellt)) == 1


# --- Migration ------------------------------------------------------------


@pytest.fixture
def alte_datenbank(tmp_path: Path) -> Path:
    """Eine Datenbank, wie sie Phase 1 hinterlassen hat."""
    pfad = tmp_path / "alt.db"
    conn = sqlite3.connect(pfad)
    conn.executescript("""
        CREATE TABLE messages (id INTEGER PRIMARY KEY, role TEXT, content TEXT,
                               created_at TEXT);
        CREATE TABLE llm_calls (id INTEGER PRIMARY KEY, model TEXT, in_tokens INT,
                                out_tokens INT, cost_eur REAL, duration_ms INT,
                                ok INT, created_at TEXT);
        INSERT INTO messages (role, content, created_at)
            VALUES ('user', 'alte Nachricht', '2026-01-01T00:00:00Z');
    """)
    conn.commit()
    conn.close()
    return pfad


def test_die_migration_erkennt_was_fehlt(alte_datenbank: Path):
    with db.session(alte_datenbank) as conn:
        fehlt = fehlende_spalten(conn)
    assert ("llm_calls", "prompt_hash", "TEXT NOT NULL DEFAULT ''") in fehlt


def test_dry_run_aendert_nichts(alte_datenbank: Path):
    befehle = migriere(alte_datenbank, dry_run=True)
    assert befehle
    with sqlite3.connect(alte_datenbank) as conn:
        spalten = {r[1] for r in conn.execute("PRAGMA table_info(llm_calls)")}
    assert "prompt_hash" not in spalten


def test_die_migration_ergaenzt_die_fehlenden_spalten(alte_datenbank: Path):
    migriere(alte_datenbank)
    with sqlite3.connect(alte_datenbank) as conn:
        spalten = {r[1] for r in conn.execute("PRAGMA table_info(llm_calls)")}
        tabellen = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
    assert "prompt_hash" in spalten
    # Die Tabellen der spaeteren Phasen entstehen dabei ebenfalls.
    assert {"facts", "task_log", "tasks", "steps", "tool_calls", "audit_log"} <= tabellen


def test_die_migration_ist_idempotent(alte_datenbank: Path):
    migriere(alte_datenbank)
    assert migriere(alte_datenbank) == []


def test_die_migration_verliert_keine_daten(alte_datenbank: Path):
    migriere(alte_datenbank)
    with sqlite3.connect(alte_datenbank) as conn:
        texte = [r[0] for r in conn.execute("SELECT content FROM messages")]
    assert texte == ["alte Nachricht"]


def test_nach_der_migration_laeuft_die_app_auf_der_alten_datei(alte_datenbank, settings):
    from fastapi.testclient import TestClient

    from api.app import create_app

    migriere(alte_datenbank)
    settings.db_path = alte_datenbank
    with TestClient(create_app(settings)) as c:
        antwort = c.get("/api/health", headers={"X-Jarvis-Token": "test-token-123"})
    assert antwort.status_code == 200
    assert antwort.json()["database"] == "ok"
    assert antwort.json()["messages"] == 1


# --- Healthcheck ----------------------------------------------------------


def test_healthcheck_wertet_401_als_gesund(live_server, monkeypatch):
    """/api/health ist tokenpflichtig - der Container kennt den Token nicht."""
    from scripts import healthcheck

    monkeypatch.setenv("JARVIS_PORT", live_server.rsplit(":", 1)[1])
    monkeypatch.setenv("JARVIS_HOST", "127.0.0.1")
    assert healthcheck.main() == 0


def test_healthcheck_meldet_einen_toten_server(monkeypatch):
    from scripts import healthcheck

    monkeypatch.setenv("JARVIS_PORT", "9")   # discard, antwortet nie
    monkeypatch.setenv("JARVIS_HOST", "127.0.0.1")
    assert healthcheck.main() == 1


def test_healthcheck_uebersetzt_die_bindadresse(monkeypatch):
    """0.0.0.0 ist eine Bind-Adresse, keine Zieladresse."""
    from scripts import healthcheck

    monkeypatch.setenv("JARVIS_HOST", "0.0.0.0")
    monkeypatch.setenv("JARVIS_PORT", "9")
    assert healthcheck.main() == 1   # kein Absturz beim Aufloesen


def test_fund2_die_sicherheitskopie_enthaelt_auch_den_wal_inhalt(
    gefuellt: Path, tmp_path: Path
):
    """BUGS-01 Fund 2 - der Restore machte sich selbst rueckgaengig.

    Der reale Fall: JARVIS laeuft, seine Verbindung ist offen, die letzten
    Nachrichten stehen noch im `-wal`. Wer jetzt ein aelteres Backup
    einspielt, bekommt eine Sicherheitskopie per `shutil.copy2` - also nur
    die `.db` ohne den WAL - und direkt danach wird das `-wal` geloescht.
    Was seit dem letzten Checkpoint geschrieben wurde, ist damit weg, und
    `einspielen` meldet trotzdem Erfolg.
    """
    sicherung = tmp_path / "sicherung.db"
    sichern(gefuellt, sicherung)                    # Stand: 2 Nachrichten

    # JARVIS laeuft weiter und schreibt. Die Verbindung bleibt offen, also
    # bleibt der Schreibvorgang im WAL.
    offen = db.connect(gefuellt)
    offen.execute(
        "INSERT INTO messages (role, content, created_at) "
        "VALUES ('user', 'nur im wal', '2026-08-26T12:00:00Z')"
    )
    offen.commit()
    assert Path(str(gefuellt) + "-wal").exists(), (
        "Ohne WAL-Datei prueft der Test nichts - dann ist die Voraussetzung falsch."
    )

    try:
        einspielen(sicherung, gefuellt)
    finally:
        offen.close()

    beiseite = list(gefuellt.parent.glob("*.vor-restore-*.db"))
    assert len(beiseite) == 1, beiseite
    with sqlite3.connect(beiseite[0]) as conn:
        texte = [r[0] for r in conn.execute("SELECT content FROM messages")]
    assert "nur im wal" in texte, (
        f"Die Sicherheitskopie hat den WAL-Inhalt verloren: {texte}"
    )


def test_fund2_auch_nach_einem_absturz_geht_nichts_verloren(
    gefuellt: Path, tmp_path: Path
):
    """Der stille Fall - und deshalb der schlimmere.

    Wenn JARVIS abgestuerzt ist, liegt das `-wal` unbeachtet auf der Platte.
    Frueher lief `einspielen` in diesem Fall ohne Fehler durch, gab 0 zurueck
    und hatte den letzten Stand trotzdem geloescht. Wichtig: die Zieldatei
    zwischendurch NICHT oeffnen - jedes Oeffnen checkpointet den WAL in die
    `.db` und heilt die Voraussetzung des Tests weg.
    """
    import shutil

    sicherung = tmp_path / "sicherung.db"
    sichern(gefuellt, sicherung)

    offen = db.connect(gefuellt)
    offen.execute(
        "INSERT INTO messages (role, content, created_at) "
        "VALUES ('user', 'nur im wal', '2026-08-26T12:00:00Z')"
    )
    offen.commit()

    # Der Zustand auf der Platte nach einem Kill: .db, -wal und -shm, ohne
    # sauberes Schliessen.
    nach_absturz = tmp_path / "nach-absturz"
    nach_absturz.mkdir()
    for anhang in ("", "-wal", "-shm"):
        quelle = Path(str(gefuellt) + anhang)
        if quelle.exists():
            shutil.copy2(quelle, nach_absturz / quelle.name)
    offen.close()

    ziel = nach_absturz / gefuellt.name
    assert Path(str(ziel) + "-wal").exists(), "Ohne WAL prueft der Test nichts."

    einspielen(sicherung, ziel)

    beiseite = list(nach_absturz.glob("*.vor-restore-*.db"))
    assert len(beiseite) == 1, beiseite
    with sqlite3.connect(beiseite[0]) as conn:
        texte = [r[0] for r in conn.execute("SELECT content FROM messages")]
    assert "nur im wal" in texte, (
        f"Stillschweigend verloren, Rueckgabe war trotzdem ok: {texte}"
    )
