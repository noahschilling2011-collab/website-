"""Sicherung der Datenbank - Backup, Pruefung, Restore, taegliche Rotation.

FIX-11 Punkt 1. Bis dahin lag alles in `scripts/backup.py`, und das Skript
rief niemand: eine Sicherung, die nur auf Zuruf entsteht, gibt es im Alltag
nicht. Jetzt macht der Start sie selbst (`api/app.py`, lifespan), das Skript
bleibt als Huelle fuer die Hand.

Gesichert wird ueber `sqlite3.Connection.backup()`, nicht ueber `cp`. Das ist
der Unterschied: bei eingeschaltetem WAL liegen die letzten Schreibvorgaenge
in `-wal`, und eine kopierte `.db` allein ist unvollstaendig oder kaputt.
Die Backup-API sperrt sauber und schreibt einen konsistenten Stand - auch
waehrend JARVIS laeuft.

Ein Restore, der nie eingespielt wurde, ist kein Backup. `pruefen` oeffnet
die Datei, laesst SQLite den Integritaetscheck laufen und zaehlt die Zeilen.

Wo die Sicherungen liegen
-------------------------

`<Datenbank>.parent/sicherungen/backup-<UTC-Zeit>.db`. Ein eigener
Unterordner, ein festes Namensmuster - und NUR dort und NUR nach diesem
Muster wird rotiert (`MAX_SICHERUNGEN`). Eine Datei, die Noah von Hand
daneben legt, oder die Datenbank selbst, fasst die Rotation nie an.

Die Zeit fuer "juenger als 24 h" kommt als Parameter (`jetzt=`), damit Tests
sie stellen koennen, statt die echte Uhr zu drehen.
"""

from __future__ import annotations

import re
import shutil
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

ORDNER = "sicherungen"
MUSTER = re.compile(r"^backup-(\d{8}T\d{6})Z\.db$")
STEMPEL = "%Y%m%dT%H%M%S"
# Deckel, kein Komfortwert: 7 Staende decken eine Woche taeglicher Starts,
# und jede Sicherung ist so gross wie die Datenbank.
MAX_SICHERUNGEN = 7
ABSTAND = timedelta(hours=24)
# Die ersten 16 Bytes jeder SQLite-Datei (sqlite.org/fileformat.html).
SQLITE_KOPF = b"SQLite format 3\x00"


def ist_sqlite_datei(pfad: Path) -> bool:
    """Traegt die Datei den SQLite-Kopf? Ohne sie ueber sqlite3 zu oeffnen -
    das loescht bei einer Muell-Datei die daneben liegende -wal."""
    try:
        with open(pfad, "rb") as f:
            return f.read(len(SQLITE_KOPF)) == SQLITE_KOPF
    except OSError:
        return False


# Keine Liste von Hand mehr. Die gab es bis FIX-08 - und sie kannte weder
# `lookups` noch `vault_notizen` noch die zwei Weltlage-Tabellen, alle
# spaeter dazugekommen. "pruefen" meldete also Zeilenzahlen fuer acht
# Tabellen und schwieg zu vier. Jetzt zaehlt es, was in der Datei IST:
# jede eigene Tabelle ausser den abgeleiteten Volltextindizes (*_fts und
# ihre Schattentabellen) und SQLites eigenen (sqlite_*).
def tabellen(conn: sqlite3.Connection) -> list[str]:
    namen = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    return [n for n in namen
            if not n.startswith("sqlite_") and "_fts" not in n]


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
        return {
            t: conn.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            for t in tabellen(conn)
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
        #
        # BUGS-01 Fund 2: das lief frueher ueber `shutil.copy2` - also nur
        # die `.db`. Bei eingeschaltetem WAL steht der letzte Stand aber in
        # der `-wal`-Datei, und die wurde unmittelbar danach geloescht. Der
        # Restore zerstoerte damit sein eigenes Sicherheitsnetz und meldete
        # Erfolg. Ueber die Backup-API kommt der WAL-Inhalt mit - genau
        # dafuer benutzt `sichern` sie.
        stempel = datetime.now(timezone.utc).strftime(STEMPEL + "Z")
        beiseite = ziel.with_suffix(f".vor-restore-{stempel}.db")
        if ist_sqlite_datei(ziel):
            sichern(ziel, beiseite)
        else:
            # FIX-11: die bisherige Datei ist keine Datenbank mehr - genau
            # der Fall, in den der Startabbruch ("Die Datenbank ist
            # beschaedigt ... einspielen mit ...") fuehrt. Die Backup-API
            # kann sie nicht lesen, und schon das OEFFNEN ueber sqlite3
            # loescht eine daneben liegende -wal (gemessen). Deshalb wird
            # hier gar nicht erst geoeffnet: die rohen Bytes wandern
            # beiseite, samt -wal und -shm - auch eine kaputte Datei wird
            # nicht geloescht.
            for anhang in ("", "-wal", "-shm"):
                quelle_roh = Path(str(ziel) + anhang)
                if quelle_roh.exists():
                    shutil.copy2(quelle_roh, Path(str(beiseite) + anhang))
        print(f"Bisherige Datenbank gesichert nach {beiseite}")

    ziel.parent.mkdir(parents=True, exist_ok=True)
    if ziel.exists() and not ist_sqlite_datei(ziel):
        # In eine Muell-Datei kann die Backup-API nicht schreiben. Ohne
        # --force liegt sie schon beiseite, mit --force hat der Nutzer auf
        # die Kopie verzichtet. Weg damit, samt -wal und -shm.
        for anhang in ("", "-wal", "-shm"):
            Path(str(ziel) + anhang).unlink(missing_ok=True)

    src = sqlite3.connect(quelle)
    dst = sqlite3.connect(ziel)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    return ziel


# --- Taegliche Sicherung beim Start ------------------------------------------


def ordner(db_path: Path) -> Path:
    return Path(db_path).parent / ORDNER


def _utc(zeit: datetime) -> datetime:
    """Naive Zeiten gelten als UTC - die Dateinamen sind UTC."""
    return zeit if zeit.tzinfo else zeit.replace(tzinfo=timezone.utc)


def ziel_pfad(db_path: Path, jetzt: datetime) -> Path:
    return ordner(db_path) / f"backup-{_utc(jetzt).strftime(STEMPEL)}Z.db"


def vorhandene(db_path: Path) -> list[tuple[datetime, Path]]:
    """Alle eigenen Sicherungen, juengste zuerst.

    Nur Dateien nach dem Muster im eigenen Unterordner. Was anders heisst,
    gehoert nicht uns - und wird weder gezaehlt noch geloescht.
    """
    verz = ordner(db_path)
    if not verz.is_dir():
        return []
    treffer = []
    for pfad in verz.iterdir():
        m = MUSTER.match(pfad.name)
        if m is None or not pfad.is_file():
            continue
        zeit = datetime.strptime(m.group(1), STEMPEL).replace(tzinfo=timezone.utc)
        treffer.append((zeit, pfad))
    return sorted(treffer, key=lambda t: t[0], reverse=True)


def juengste(db_path: Path) -> datetime | None:
    """Wann die juengste Sicherung entstand - aus dem Dateinamen, ohne die
    Datenbank zu oeffnen. Deshalb geht das auch, wenn sie kaputt ist."""
    alle = vorhandene(db_path)
    return alle[0][0] if alle else None


def juengste_datei(db_path: Path) -> Path | None:
    alle = vorhandene(db_path)
    return alle[0][1] if alle else None


def rotieren(db_path: Path, *, behalten: int = MAX_SICHERUNGEN) -> list[Path]:
    """Loescht die aeltesten eigenen Sicherungen, bis hoechstens `behalten`
    bleiben. Gibt zurueck, was weg ist."""
    verz = ordner(db_path).resolve()
    weg = []
    for _, pfad in vorhandene(db_path)[behalten:]:
        # Doppelt genaeht: nur im eigenen Ordner, nur nach dem Muster.
        # `vorhandene` garantiert beides schon - aber ein Loeschbefehl
        # bekommt seine Bedingung noch einmal direkt davor.
        if pfad.resolve().parent != verz or MUSTER.match(pfad.name) is None:
            continue
        pfad.unlink()
        weg.append(pfad)
    return weg


def sichere_taeglich(db_path: Path, jetzt: datetime, *,
                     erzwingen: bool = False) -> datetime | None:
    """Sichert, wenn keine Sicherung juenger als 24 h ist (oder `erzwingen`),
    prueft die neue Datei und rotiert. Gibt die Zeit der juengsten Sicherung
    zurueck - die neue oder die, die den Gang erspart hat.

    Wirft bei jedem Fehler. Der Aufrufer (lifespan) faengt das und startet
    trotzdem: eine gescheiterte Sicherung ist eine Warnung, kein Grund, den
    Nutzer ohne JARVIS dastehen zu lassen.
    """
    db_path = Path(db_path)
    jetzt = _utc(jetzt)
    letzte = juengste(db_path)
    if not erzwingen and letzte is not None and jetzt - letzte < ABSTAND:
        return letzte

    ziel = ziel_pfad(db_path, jetzt)
    sichern(db_path, ziel)
    heil, meldung, _ = pruefen(ziel)
    if not heil:
        # Eine Sicherung, die den Integritaetscheck nicht besteht, ist
        # keine. Weg damit, sonst zaehlt sie beim naechsten Start als
        # "juenger als 24 h" und verhindert die naechste.
        ziel.unlink(missing_ok=True)
        raise RuntimeError(f"Die Sicherung ist nicht brauchbar - {meldung}")
    rotieren(db_path)
    return juengste(db_path)


def beschaedigt_satz(db_path: Path) -> str:
    """EIN Satz fuer den Startabbruch, ohne Pfad. Vorbild: `get_settings()`
    in core/config.py bei einer nicht-UTF-8-.env."""
    zeit = juengste(db_path)
    if zeit is None:
        return ("Die Datenbank ist beschaedigt und es gibt keine Sicherung "
                "(Ordner 'sicherungen' neben der Datenbank ist leer) - pruefen "
                "mit: python -m scripts.backup pruefen <Datei>.")
    return (f"Die Datenbank ist beschaedigt - juengste Sicherung vom "
            f"{zeit:%Y-%m-%d %H:%M} UTC, einspielen mit: "
            "python -m scripts.backup einspielen")
