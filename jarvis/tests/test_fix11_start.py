"""FIX-11 Punkt 1 - Start: Sicherung, Pruefung, Migration, Host-Sperre.

Befund (docs/FIX-11.md), jeder Punkt vor dem Bauen reproduziert:

  * `GET /` mit `Host: evil.example` -> 200 MIT Token im Body.
  * Datenbank von vor FIX-09 (ohne `fehlschlaege`/`art`) -> `POST
    /api/zeitplaene` 500, Health sagt trotzdem `ok`.
  * Muell-Datei als `db_path` -> `sqlite3.DatabaseError` schon beim
    `connect` (PRAGMA journal_mode), Traceback bis core/db.py.
  * `DROP TABLE messages` zur Laufzeit -> `health.database` =
    'fehler: no such table: messages' - der Tabellenname geht an die
    Oberflaeche.
  * `scripts/backup.py` rief niemand.

Alle Tests laufen gegen den FakeLLMProvider (Settings ohne Anbieter) und
gegen eigene Datenbankdateien unter tmp_path.
"""

from __future__ import annotations

import logging
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import create_app, datenbank_start, erlaubte_hosts, ist_loopback
from core import db, migration, sicherung
from core.config import Settings
from core.fehlertexte import ist_verdaechtig

TOKEN = {"X-Jarvis-Token": "test-token-123"}
JETZT = datetime(2026, 9, 6, 12, 0, tzinfo=timezone.utc)


def _einstellungen(db_path: Path, **mehr) -> Settings:
    # Die Schleife bleibt aus: hier geht es um den Start, nicht um Zeitplaene.
    return Settings(_env_file=None, db_path=db_path, jarvis_token="test-token-123",
                    zeitplan_takt_s=0, **mehr)


def _neue_datenbank(pfad: Path) -> Path:
    with db.session(pfad) as conn:
        db.init_db(conn)
    return pfad


def _fix08_datenbank(pfad: Path) -> Path:
    """Wie FIX-08 sie hinterlassen hat: `zeitplaene` ohne `fehlschlaege` und
    ohne `art` - die Spalten kamen mit FIX-09."""
    _neue_datenbank(pfad)
    with db.session(pfad) as conn:
        conn.executescript("""
            DROP TABLE zeitplan_laeufe;
            DROP TABLE zeitplaene;
            CREATE TABLE zeitplaene (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, ziel TEXT NOT NULL,
                regel TEXT NOT NULL, aktiv INTEGER NOT NULL DEFAULT 1,
                erstellt_am TEXT NOT NULL, naechster_lauf TEXT, letzter_lauf TEXT,
                letzter_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                letzter_status TEXT, verpasst INTEGER NOT NULL DEFAULT 0);
        """)
    return pfad


def _sicherungen(db_path: Path) -> list[Path]:
    return sorted(sicherung.ordner(db_path).glob("backup-*.db"))


def _lege_sicherung(db_path: Path, zeit: datetime) -> Path:
    """Eine echte, heile Sicherung mit gestelltem Zeitstempel im Namen."""
    return sicherung.sichern(db_path, sicherung.ziel_pfad(db_path, zeit))


# --- Migration beim Start ------------------------------------------------------


def test_dod_fix08_datenbank_laeuft_ohne_handmigration(tmp_path: Path):
    """Vorher: 500 `no such column: fehlschlaege`, Health `ok`."""
    pfad = _fix08_datenbank(tmp_path / "alt.db")
    with TestClient(create_app(_einstellungen(pfad))) as c:
        antwort = c.post("/api/zeitplaene", headers=TOKEN,
                         json={"name": "Morgen", "ziel": "Wetter", "regel": "taeglich 07:00"})
        assert antwort.status_code == 201, antwort.text
        health = c.get("/api/health", headers=TOKEN).json()
    assert health["schema"] == "aktuell"
    assert health["status"] == "ok"
    with db.session(pfad) as conn:
        spalten = {r[1] for r in conn.execute("PRAGMA table_info(zeitplaene)")}
    assert {"fehlschlaege", "art"} <= spalten


def test_der_start_schreibt_eine_logzeile_je_migrationsbefehl(tmp_path: Path, caplog):
    pfad = _fix08_datenbank(tmp_path / "alt.db")
    caplog.set_level(logging.INFO, logger="jarvis")
    with TestClient(create_app(_einstellungen(pfad))):
        pass
    zeilen = [r.getMessage() for r in caplog.records if r.getMessage().startswith("Migration: ")]
    assert any("ADD COLUMN fehlschlaege" in z for z in zeilen), zeilen
    assert any("ADD COLUMN art" in z for z in zeilen), zeilen


def test_migriere_auf_einer_verbindung_committet(tmp_path: Path):
    """Der lifespan gibt seine offene Verbindung weiter (sie hat schon den
    quick_check gemacht). Was darauf migriert wird, muss eine ZWEITE
    Verbindung sehen - sonst waere es beim Schliessen weg."""
    pfad = _fix08_datenbank(tmp_path / "alt.db")
    conn = db.connect(pfad)
    try:
        assert migration.ausstehend(conn)
        getan = migration.migriere(conn)
        assert any("fehlschlaege" in g for g in getan)
        assert migration.ausstehend(conn) == []
    finally:
        conn.close()
    with sqlite3.connect(pfad) as andere:
        spalten = {r[1] for r in andere.execute("PRAGMA table_info(zeitplaene)")}
    assert "fehlschlaege" in spalten
    # ... und ueber den Pfad geht es weiter wie bisher (Skript, alte Tests).
    assert migration.migriere(pfad) == []


def test_scheitert_die_migration_startet_jarvis_mit_schema_veraltet(tmp_path: Path, monkeypatch):
    """Eine Datenbank, die nicht nachgezogen werden konnte, ist ein
    degradierter Zustand - kein Grund, gar nicht zu starten, aber Health
    muss es sagen. Vorher sagte Health `ok` und die Route gab 500."""
    pfad = _neue_datenbank(tmp_path / "test.db")

    def kaputt(*_, **__):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(migration, "migriere", kaputt)
    with TestClient(create_app(_einstellungen(pfad))) as c:
        health = c.get("/api/health", headers=TOKEN).json()
    assert health["schema"] == "veraltet"
    assert health["status"] == "degraded"


# --- Beschaedigte Datei --------------------------------------------------------


def test_dod_muell_datei_endet_in_einem_satz_ohne_pfad(tmp_path: Path):
    """Vorher: `sqlite3.DatabaseError: file is not a database` als
    Traceback bis core/db.py. Jetzt SystemExit mit EINEM Satz, ohne Pfad.

    Geprueft an `datenbank_start`, wo der Satz entsteht: Starlettes
    TestClient laesst eine SystemExit aus dem lifespan nicht durch, sein
    anyio-Portal macht daraus einen CancelledError. Unter uvicorn heisst
    dasselbe "Application startup failed. Exiting." - mit dem Satz als
    letzter Zeile.
    """
    muell = tmp_path / "jarvis.db"
    muell.write_bytes(b"das ist keine datenbank " * 50)
    with pytest.raises(SystemExit) as info:
        datenbank_start(_einstellungen(muell))
    satz = str(info.value)
    assert "beschaedigt" in satz
    assert "keine Sicherung" in satz
    assert ist_verdaechtig(satz, [str(tmp_path), str(muell), "jarvis.db"]) == []
    # Kein zweiter Satz: der Punkt am Ende ist der einzige.
    assert satz.count(". ") == 0 and satz.endswith(".")
    # Die Ursache haengt dran (fuer `raise ... from`), ist aber nicht der Text.
    assert isinstance(info.value.__cause__, sqlite3.DatabaseError)

    # Und die App kommt damit nicht hoch - der lifespan reicht den Abbruch
    # durch, statt mit einer kaputten Datei "bereit" zu melden.
    with pytest.raises(BaseException) as app_info:
        with TestClient(create_app(_einstellungen(muell))):
            raise AssertionError("die App ist mit einer Muell-Datei gestartet")
    assert not isinstance(app_info.value, AssertionError)
    assert muell.read_bytes().startswith(b"das ist keine datenbank"), "Datei angefasst"


def test_der_satz_nennt_die_juengste_sicherung_und_den_befehl(tmp_path: Path):
    """Auch wenn die Datenbank kaputt ist, sind die Sicherungen lesbar - der
    Zeitpunkt kommt aus dem Dateinamen, nicht aus der Datei."""
    heil = _neue_datenbank(tmp_path / "jarvis.db")
    _lege_sicherung(heil, datetime(2026, 9, 5, 7, 30, tzinfo=timezone.utc))
    _lege_sicherung(heil, datetime(2026, 9, 6, 7, 30, tzinfo=timezone.utc))
    heil.write_bytes(b"kaputt " * 100)
    for anhang in ("-wal", "-shm"):
        Path(str(heil) + anhang).unlink(missing_ok=True)
    with pytest.raises(SystemExit) as info:
        datenbank_start(_einstellungen(heil))
    satz = str(info.value)
    assert "2026-09-06 07:30" in satz, satz
    assert "python -m scripts.backup einspielen" in satz
    assert ist_verdaechtig(satz, [str(tmp_path), "backup-2026"]) == []


def test_quick_check_faengt_auch_eine_lesbare_aber_kaputte_datei(tmp_path: Path, monkeypatch):
    """`connect` geht durch, `quick_check` meldet etwas anderes als `ok`."""
    pfad = _neue_datenbank(tmp_path / "test.db")
    echt = db.connect

    class Verbindung:
        def __init__(self, conn):
            self._c = conn

        def execute(self, sql, *a):
            if "quick_check" in sql:
                class Z:
                    @staticmethod
                    def fetchone():
                        return ("*** in database main *** Page 3: btree page corrupted",)
                return Z()
            return self._c.execute(sql, *a)

        def __getattr__(self, name):
            return getattr(self._c, name)

    monkeypatch.setattr("api.app.connect", lambda p: Verbindung(echt(p)))
    with pytest.raises(SystemExit) as info:
        datenbank_start(_einstellungen(pfad))
    assert "beschaedigt" in str(info.value)


# --- Sicherung beim Start --------------------------------------------------------


def test_dod_erster_start_sichert_genau_einmal_zweiter_binnen_24h_nicht(tmp_path: Path, monkeypatch):
    """Abnahme FIX-11: die Uhr wird gestellt. Zwei echte Starts liegen in
    derselben Sekunde, und der Dateiname traegt nur Sekunden - eine zweite
    Sicherung haette die erste ueberschrieben und die Zaehlung waere trotzdem
    1 gewesen (Mutation "immer sichern" blieb gruen). Jetzt liegt der zweite
    Start eine Stunde spaeter, und die Zaehlung sagt die Wahrheit."""
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    db.add_message(pfad, "user", "vor der Sicherung")
    uhr = {"jetzt": JETZT}

    class Uhr(datetime):
        @classmethod
        def now(cls, tz=None):
            return uhr["jetzt"] if tz else uhr["jetzt"].replace(tzinfo=None)

    monkeypatch.setattr("api.app.datetime", Uhr)

    with TestClient(create_app(_einstellungen(pfad))) as c:
        health = c.get("/api/health", headers=TOKEN).json()
    uhr["jetzt"] = JETZT + timedelta(hours=1)
    dateien = _sicherungen(pfad)
    assert len(dateien) == 1, dateien
    heil, meldung, zeilen = sicherung.pruefen(dateien[0])
    assert heil and meldung == "ok" and zeilen["messages"] == 1
    assert health["letzte_sicherung"] is not None
    # ISO-Zeit, kein Pfad.
    datetime.fromisoformat(health["letzte_sicherung"])
    assert ist_verdaechtig(health["letzte_sicherung"], [str(tmp_path), "backup-", ".db"]) == []

    with TestClient(create_app(_einstellungen(pfad))) as c:
        health2 = c.get("/api/health", headers=TOKEN).json()
    assert _sicherungen(pfad) == dateien, "zweiter Start binnen 24 h: keine zweite"
    assert health2["letzte_sicherung"] == health["letzte_sicherung"]


def test_eine_neue_datenbank_wird_nicht_gesichert(tmp_path: Path):
    """Nichts da, nichts zu verlieren - und die Testsuite startet die App
    ein paar hundert Mal auf frischen Dateien."""
    pfad = tmp_path / "neu.db"
    assert not pfad.exists()
    with TestClient(create_app(_einstellungen(pfad))) as c:
        health = c.get("/api/health", headers=TOKEN).json()
    assert health["letzte_sicherung"] is None
    assert not sicherung.ordner(pfad).exists()
    assert pfad.exists()


def test_vor_einer_migration_wird_immer_gesichert(tmp_path: Path):
    """Auch wenn die letzte Sicherung juenger als 24 h ist: eine Migration
    aendert die Datei, und davor will man den Stand haben."""
    pfad = _fix08_datenbank(tmp_path / "alt.db")
    frisch = _lege_sicherung(pfad, datetime.now(timezone.utc) - timedelta(hours=1))
    with TestClient(create_app(_einstellungen(pfad))):
        pass
    dateien = _sicherungen(pfad)
    assert len(dateien) == 2, dateien
    assert frisch in dateien
    # Die neue Sicherung hat noch den ALTEN Stand - das ist ihr Sinn.
    neue = [d for d in dateien if d != frisch][0]
    with sqlite3.connect(neue) as conn:
        spalten = {r[1] for r in conn.execute("PRAGMA table_info(zeitplaene)")}
    assert "fehlschlaege" not in spalten


def test_dod_sichern_wirft_die_app_startet_trotzdem(tmp_path: Path, monkeypatch, caplog):
    pfad = _neue_datenbank(tmp_path / "jarvis.db")

    def platte_voll(*_, **__):
        raise OSError(28, "No space left on device", str(tmp_path / "geheim"))

    monkeypatch.setattr(sicherung, "sichern", platte_voll)
    caplog.set_level(logging.WARNING, logger="jarvis")
    with TestClient(create_app(_einstellungen(pfad))) as c:
        health = c.get("/api/health", headers=TOKEN).json()
    assert health["letzte_sicherung"] is None
    assert health["database"] == "ok"
    assert _sicherungen(pfad) == []
    assert any("Sicherung fehlgeschlagen" in r.getMessage() for r in caplog.records)


# --- sichere_taeglich, ohne App ----------------------------------------------------


def test_dod_neun_vorhandene_sieben_bleiben_die_juengsten(tmp_path: Path):
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    # Neun Sicherungen, die aelteste 10 Tage, die juengste 2 Tage her.
    zeiten = [JETZT - timedelta(days=n) for n in range(2, 11)]
    for z in zeiten:
        _lege_sicherung(pfad, z)
    assert len(_sicherungen(pfad)) == 9

    juengste = sicherung.sichere_taeglich(pfad, JETZT)

    assert juengste == JETZT
    bleiben = _sicherungen(pfad)
    assert len(bleiben) == 7
    erwartet = sorted([JETZT] + zeiten[:6])
    assert [n.name for n in bleiben] == [sicherung.ziel_pfad(pfad, z).name for z in erwartet]


def test_juenger_als_24h_heisst_keine_neue(tmp_path: Path):
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    alt = _lege_sicherung(pfad, JETZT - timedelta(hours=23, minutes=59))
    assert sicherung.sichere_taeglich(pfad, JETZT) == JETZT - timedelta(hours=23, minutes=59)
    assert _sicherungen(pfad) == [alt]
    # Eine Minute spaeter sind es 24 h - dann ja.
    sicherung.sichere_taeglich(pfad, JETZT + timedelta(minutes=1))
    assert len(_sicherungen(pfad)) == 2


def test_die_rotation_fasst_nur_eigene_dateien_im_eigenen_ordner_an(tmp_path: Path):
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    ordner = sicherung.ordner(pfad)
    for n in range(1, 10):
        _lege_sicherung(pfad, JETZT - timedelta(days=n))
    fremd = ordner / "meine-notiz.db"
    fremd.write_bytes(b"gehoert mir")
    daneben = tmp_path / "backup-20200101T000000Z.db"    # Muster, aber falscher Ordner
    daneben.write_bytes(b"auch meins")

    sicherung.sichere_taeglich(pfad, JETZT)

    assert fremd.exists() and fremd.read_bytes() == b"gehoert mir"
    assert daneben.exists()
    assert pfad.exists() and sicherung.pruefen(pfad)[0]
    assert len(_sicherungen(pfad)) == 7


def test_eine_unbrauchbare_sicherung_bleibt_nicht_liegen(tmp_path: Path, monkeypatch):
    """Sonst zaehlt sie beim naechsten Start als 'juenger als 24 h' und
    verhindert die naechste, die vielleicht gelingen wuerde."""
    pfad = _neue_datenbank(tmp_path / "jarvis.db")

    def schreibt_muell(quelle, ziel):
        ziel.parent.mkdir(parents=True, exist_ok=True)
        ziel.write_bytes(b"nicht sqlite")
        return ziel

    monkeypatch.setattr(sicherung, "sichern", schreibt_muell)
    with pytest.raises(RuntimeError, match="nicht brauchbar"):
        sicherung.sichere_taeglich(pfad, JETZT)
    assert _sicherungen(pfad) == []
    assert sicherung.juengste(pfad) is None


def test_der_zeitstempel_im_namen_ist_utc_und_lesbar(tmp_path: Path):
    pfad = tmp_path / "jarvis.db"
    ziel = sicherung.ziel_pfad(pfad, JETZT)
    assert ziel == tmp_path / "sicherungen" / "backup-20260906T120000Z.db"
    # Naiv heisst UTC, nicht Ortszeit.
    assert sicherung.ziel_pfad(pfad, JETZT.replace(tzinfo=None)) == ziel
    assert sicherung.MUSTER.match(ziel.name)


# --- Health ---------------------------------------------------------------------


def test_dod_drop_table_zur_laufzeit_health_nennt_keinen_tabellennamen(tmp_path: Path):
    """Vorher: 'fehler: no such table: messages'."""
    pfad = tmp_path / "test.db"
    with TestClient(create_app(_einstellungen(pfad))) as c:
        with db.session(pfad) as conn:
            conn.execute("DROP TABLE messages")
        health = c.get("/api/health", headers=TOKEN).json()
    assert health["status"] == "degraded"
    assert health["database"] != "ok"
    assert ist_verdaechtig(health["database"], ["messages", "no such table", str(tmp_path)]) == []
    assert "OperationalError" in health["database"]
    assert "Serverlog" in health["database"]


def test_health_ist_additiv(tmp_path: Path):
    """Die alten Felder bleiben, zwei kommen dazu - und keins traegt einen Pfad."""
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    with TestClient(create_app(_einstellungen(pfad))) as c:
        antwort = c.get("/api/health", headers=TOKEN)
    body = antwort.json()
    assert {"status", "phase", "provider", "model", "api_key_configured", "api_key_hint",
            "provider_error", "database", "messages", "spend"} <= set(body)
    assert body["schema"] in ("aktuell", "veraltet")
    assert body["letzte_sicherung"] is None or isinstance(body["letzte_sicherung"], str)
    assert ist_verdaechtig(antwort.text, [str(tmp_path), "sicherungen/", "backup-"]) == []


# --- Host-Sperre ----------------------------------------------------------------


def test_dod_fremder_host_bekommt_400_ohne_token(tmp_path: Path):
    """Vorher: 200 mit Token - DNS-Rebinding aus dem Browser war ein Weg
    zum Token."""
    with TestClient(create_app(_einstellungen(tmp_path / "t.db"))) as c:
        seite = c.get("/", headers={"Host": "evil.example"})
        assert seite.status_code == 400
        assert "test-token-123" not in seite.text
        assert ist_verdaechtig(seite.text, [str(tmp_path), "index.html"]) == []
        # Mit Token, aber fremdem Host: die Sperre sitzt VOR der Token-Pruefung.
        api = c.get("/api/messages", headers={"Host": "evil.example", **TOKEN})
        assert api.status_code == 400
        assert api.text == seite.text


@pytest.mark.parametrize("host", ["127.0.0.1:8000", "localhost:8000", "127.0.0.1", "localhost"])
def test_dod_eigener_rechner_bekommt_die_seite_mit_token(tmp_path: Path, host: str):
    with TestClient(create_app(_einstellungen(tmp_path / "t.db"))) as c:
        seite = c.get("/", headers={"Host": host})
        assert seite.status_code == 200, host
        assert "test-token-123" in seite.text
        assert c.get("/api/messages", headers={"Host": host, **TOKEN}).status_code == 200


def test_jarvis_host_und_erlaubte_hosts_zaehlen_mit(tmp_path: Path):
    s = _einstellungen(tmp_path / "t.db", jarvis_host="0.0.0.0",
                       jarvis_erlaubte_hosts="Container, rechner.fritz.box:8000,,")
    with TestClient(create_app(s)) as c:
        for host in ("container", "container:8000", "rechner.fritz.box", "rechner.fritz.box:9"):
            assert c.get("/", headers={"Host": host}).status_code == 200, host
        assert c.get("/", headers={"Host": "rechner.fritz.box.evil.example"}).status_code == 400
        assert c.get("/", headers={"Host": "evil.example"}).status_code == 400


def test_erlaubte_hosts_ohne_port_ohne_leere_ohne_doppelte(tmp_path: Path):
    """Starlette 1.6 vergleicht ohne Port (`split(":")[0]`): ein Eintrag mit
    Port traefe nie. Deshalb wird er hier abgeschnitten."""
    s = _einstellungen(tmp_path / "t.db", jarvis_host="127.0.0.1",
                       jarvis_erlaubte_hosts=" testserver , Rechner:9000,, localhost:8000")
    assert erlaubte_hosts(s) == ["127.0.0.1", "localhost", "[::1]", "testserver", "rechner"]
    leer = _einstellungen(tmp_path / "t.db", jarvis_erlaubte_hosts="")
    assert erlaubte_hosts(leer) == ["127.0.0.1", "localhost", "[::1]"]


def test_ein_stern_allein_schaltet_die_sperre_aus_und_sagt_es(tmp_path: Path, caplog):
    """Abnahme FIX-11: Starlette liest `*` als "jeder Host". Das darf Noah
    einstellen - aber nicht, ohne dass das Log es sagt. Vorher: 200 fuer
    evil.example und kein Wort davon."""
    caplog.set_level(logging.WARNING, logger="jarvis")
    s = _einstellungen(tmp_path / "t.db", jarvis_erlaubte_hosts="*")
    with TestClient(create_app(s)) as c:
        assert c.get("/", headers={"Host": "evil.example"}).status_code == 200
    warnungen = [r.getMessage() for r in caplog.records if "Host-Sperre" in r.getMessage()]
    assert len(warnungen) == 1, warnungen
    assert "AUS" in warnungen[0]


def test_ein_stern_mitten_im_namen_wird_uebersprungen_statt_abzubrechen(tmp_path: Path, caplog):
    """Abnahme FIX-11: Starlette 1.6 prueft `assert "*" not in pattern[1:]`
    beim Bauen der Middleware - ein Tippfehler wie `rech*ner` in der .env
    war ein AssertionError-Traceback beim Start. `*.fritz.box` bleibt
    erlaubt, das ist Starlettes Domain-Wildcard."""
    caplog.set_level(logging.WARNING, logger="jarvis")
    s = _einstellungen(tmp_path / "t.db", jarvis_erlaubte_hosts="rech*ner, *.fritz.box")
    assert erlaubte_hosts(s) == ["127.0.0.1", "localhost", "[::1]", "*.fritz.box"]
    assert any("rech*ner" in r.getMessage() for r in caplog.records)
    with TestClient(create_app(s)) as c:
        assert c.get("/", headers={"Host": "pc.fritz.box"}).status_code == 200
        assert c.get("/", headers={"Host": "evil.example"}).status_code == 400


def test_die_testsuite_bekommt_ihren_host_aus_der_umgebung():
    """tests/conftest.py setzt JARVIS_ERLAUBTE_HOSTS - fuer alle Tests, auch
    die, die ihre Settings selbst bauen."""
    assert "testserver" in erlaubte_hosts(Settings(_env_file=None))


@pytest.mark.parametrize("host,erwartet", [
    ("127.0.0.1", True), ("localhost", True), ("::1", True), ("[::1]", True),
    ("127.0.0.5", True), ("0.0.0.0", False), ("::", False), ("192.168.1.5", False),
    ("rechner.fritz.box", False), ("", False),
])
def test_ist_loopback(host: str, erwartet: bool):
    assert ist_loopback(host) is erwartet


def test_startwarnung_wenn_jarvis_host_kein_loopback_ist(tmp_path: Path, caplog):
    caplog.set_level(logging.WARNING, logger="jarvis")
    with TestClient(create_app(_einstellungen(tmp_path / "t.db", jarvis_host="0.0.0.0"))):
        pass
    warnungen = [r.getMessage() for r in caplog.records if "kein Loopback" in r.getMessage()]
    assert len(warnungen) == 1, warnungen
    assert "Token" in warnungen[0]

    caplog.clear()
    with TestClient(create_app(_einstellungen(tmp_path / "t2.db", jarvis_host="127.0.0.1"))):
        pass
    assert not [r for r in caplog.records if "kein Loopback" in r.getMessage()]


# --- Skripte sind Huellen ------------------------------------------------------


def test_die_skripte_sind_huellen_um_core():
    from scripts import backup, migrate

    assert backup.sichern is sicherung.sichern
    assert backup.pruefen is sicherung.pruefen
    assert backup.zaehle is sicherung.zaehle
    assert backup.einspielen is sicherung.einspielen
    assert migrate.migriere is migration.migriere
    assert migrate.fehlende_spalten is migration.fehlende_spalten
    assert migrate.fts_nachziehen is migration.fts_nachziehen
    assert migrate.zeitplan_laeufe_nachziehen is migration.zeitplan_laeufe_nachziehen


def test_backup_einspielen_ohne_datei_nimmt_die_juengste(tmp_path: Path, monkeypatch, capsys):
    """Der Befehl, den der Startabbruch nennt."""
    from core.config import get_settings
    from scripts import backup

    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    db.add_message(pfad, "user", "steht in der Sicherung")
    _lege_sicherung(pfad, JETZT - timedelta(days=2))
    juengste = _lege_sicherung(pfad, JETZT - timedelta(days=1))
    with db.session(pfad) as conn:
        conn.execute("DELETE FROM messages")
    assert sicherung.zaehle(pfad)["messages"] == 0

    monkeypatch.setenv("JARVIS_DB_PATH", str(pfad))
    get_settings.cache_clear()
    monkeypatch.setattr("sys.argv", ["backup", "einspielen", "--force"])
    assert backup.main() == 0
    assert juengste.name in capsys.readouterr().out
    assert sicherung.zaehle(pfad)["messages"] == 1


def test_einspielen_legt_auch_eine_kaputte_datenbank_beiseite(tmp_path: Path):
    """Der Weg, den der Startabbruch nennt, muss auch OHNE --force gehen.

    Nachgewiesen vor dem Bau: `einspielen(sicherung, kaputte_db)` scheiterte
    mit `DatabaseError: file is not a database`, weil die Sicherheitskopie
    ueber die Backup-API lief - und die kann eine Muell-Datei nicht lesen.
    """
    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    db.add_message(pfad, "user", "wichtig")
    kopie = _lege_sicherung(pfad, JETZT)
    pfad.write_bytes(b"kaputt " * 100)
    Path(str(pfad) + "-wal").write_bytes(b"rest im wal")

    sicherung.einspielen(kopie, pfad)

    assert sicherung.zaehle(pfad)["messages"] == 1
    beiseite = list(tmp_path.glob("*.vor-restore-*.db"))
    assert len(beiseite) == 1, beiseite
    assert beiseite[0].read_bytes().startswith(b"kaputt "), "die kaputte Datei ist weg"
    assert Path(str(beiseite[0]) + "-wal").read_bytes() == b"rest im wal"


def test_backup_sichern_von_hand_landet_im_selben_ordner(tmp_path: Path, monkeypatch, capsys):
    from core.config import get_settings
    from scripts import backup

    pfad = _neue_datenbank(tmp_path / "jarvis.db")
    monkeypatch.setenv("JARVIS_DB_PATH", str(pfad))
    get_settings.cache_clear()
    monkeypatch.setattr("sys.argv", ["backup", "sichern"])
    assert backup.main() == 0
    assert len(_sicherungen(pfad)) == 1
    assert "Integritaet: ok" in capsys.readouterr().out


# --- Nachtrag aus der Abnahme (Claude, 06.09.2026) ---------------------------


def test_main_prueft_die_datenbank_bevor_die_app_gebaut_wird():
    """Gemessen: im lifespan wickelt Starlette den `SystemExit` in eine
    ExceptionGroup samt Traceback - der Nutzer sieht eine Wand statt eines
    Satzes. Auf Modulebene von main.py laeuft die Pruefung auf BEIDEN
    Startwegen (`uvicorn main:app` und `python main.py`) davor.

    Echte Ausgabe von `python -m uvicorn main:app` mit einer Muell-Datei
    nach dieser Aenderung, zwei Zeilen, kein Traceback, kein Pfad:

        ERROR: Datenbank nicht lesbar: DatabaseError: file is not a database
        Die Datenbank ist beschaedigt und es gibt keine Sicherung (...)
    """
    quelle = (Path(__file__).resolve().parent.parent / "main.py").read_text("utf-8")
    ohne_kommentar = "\n".join(
        z for z in quelle.splitlines() if not z.lstrip().startswith("#")
    )
    assert "datenbank_start(get_settings())" in ohne_kommentar
    assert ohne_kommentar.index("datenbank_start(get_settings())") < \
        ohne_kommentar.index("app = create_app()"), \
        "Die Pruefung muss VOR create_app stehen, sonst kommt sie erst im lifespan."
