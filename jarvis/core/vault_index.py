"""Der abgeleitete Index ueber den Vault.

Nichts hier ist autoritativ. `reindex()` darf jederzeit alles wegwerfen und
aus den Markdown-Dateien neu bauen - das ist der Vertrag aus
`docs/MIGRATION-VAULT.md`, und `test_vault.py` prueft ihn: zweimal neu
indexieren muss byte-gleiche Zeilen liefern.

Der Beobachter haengt an `watchdog`. Vier Ereignisse zaehlen: angelegt,
geaendert, geloescht, **verschoben**. Verschieben ist der Fall, den man
vergisst - und in Obsidian passiert er staendig.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from core.db import session
from core.vault import IGNORIERT, Notiz, dateien, lies

log = logging.getLogger("jarvis")

# Editoren schreiben mehrfach hintereinander. Ohne Entprellung indexiert man
# dieselbe Datei fuenfmal.
ENTPRELLUNG_S = 0.8


@dataclass(frozen=True)
class Treffer:
    id: str
    text: str
    pfad: str
    typ: str
    quelle: str
    erfasst: str
    snapshot: str | None
    tags: list[str]
    widerspruch: str | None = None
    bestaetigt: bool = False

    @property
    def herkunft(self) -> str:
        """Was unter einer Antwort steht. Auch bei lokaler Quelle Pflicht."""
        woher = f"{self.pfad}"
        if self.snapshot:
            woher += f" (Stand {self.snapshot})"
        return woher


def _relativ(wurzel: Path, pfad: Path) -> str:
    return str(Path(pfad).resolve().relative_to(Path(wurzel).expanduser().resolve()))


def _ignoriert(wurzel: Path, pfad: Path) -> bool:
    try:
        teile = Path(pfad).resolve().relative_to(Path(wurzel).expanduser().resolve()).parts
    except ValueError:
        return True
    return any(t in IGNORIERT for t in teile) or any(t.startswith(".") for t in teile)


# --- Schreiben in den Index -------------------------------------------------


def _eintrag(conn, wurzel: Path, pfad: Path) -> str | None:
    try:
        notiz = lies(pfad)
    except (ValueError, OSError) as exc:
        log.warning("Vault: %s uebersprungen - %s", pfad.name, exc)
        return None
    conn.execute(
        "INSERT INTO vault_notizen (id, pfad, typ, quelle, erfasst, snapshot, tags, "
        "text, mtime, widerspruch, bestaetigt) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET pfad=excluded.pfad, typ=excluded.typ, "
        "quelle=excluded.quelle, erfasst=excluded.erfasst, snapshot=excluded.snapshot, "
        "tags=excluded.tags, text=excluded.text, mtime=excluded.mtime, "
        "widerspruch=excluded.widerspruch, bestaetigt=excluded.bestaetigt",
        (notiz.id, _relativ(wurzel, pfad), notiz.typ, notiz.quelle, notiz.erfasst,
         notiz.snapshot, ",".join(notiz.tags), notiz.text, pfad.stat().st_mtime,
         notiz.widerspruch, int(notiz.bestaetigt)),
    )
    return notiz.id


def reindex(db_path, wurzel: Path) -> int:
    """Baut den Index von null neu. Idempotent, per Vertrag."""
    wurzel = Path(wurzel).expanduser()
    with session(db_path) as conn:
        conn.execute("DELETE FROM vault_notizen")
        anzahl = 0
        for pfad in dateien(wurzel):
            if _eintrag(conn, wurzel, pfad) is not None:
                anzahl += 1
    return anzahl


def aktualisiere(db_path, wurzel: Path, pfad: Path) -> None:
    pfad = Path(pfad)
    if _ignoriert(wurzel, pfad) or pfad.suffix != ".md":
        return
    if not pfad.exists():
        entferne(db_path, wurzel, pfad)
        return
    with session(db_path) as conn:
        # Ein Pfad kann die Notiz gewechselt haben (Datei ueberschrieben).
        conn.execute("DELETE FROM vault_notizen WHERE pfad = ?", (_relativ(wurzel, pfad),))
        _eintrag(conn, wurzel, pfad)


def entferne(db_path, wurzel: Path, pfad: Path) -> None:
    """Geloescht heisst geloescht. Kein Papierkorb - der Vault liegt in git."""
    with session(db_path) as conn:
        try:
            conn.execute("DELETE FROM vault_notizen WHERE pfad = ?",
                         (_relativ(wurzel, Path(pfad)),))
        except ValueError:
            return


def verschiebe(db_path, wurzel: Path, alt: Path, neu: Path) -> None:
    """Umbenennen in Obsidian. Der Fakt ueberlebt, weil `id` der Schluessel ist."""
    entferne(db_path, wurzel, alt)
    aktualisiere(db_path, wurzel, neu)


# --- Lesen ------------------------------------------------------------------


def suche(db_path, frage: str, limit: int = 5) -> list[Treffer]:
    """FTS5 ueber den Index. Nie den ganzen Vault - hoechstens `limit` Notizen."""
    worte = [w for w in "".join(c if c.isalnum() else " " for c in frage).split() if len(w) > 2]
    if not worte:
        return []
    ausdruck = " OR ".join(f'"{w}"' for w in worte)
    with session(db_path) as conn:
        try:
            zeilen = conn.execute(
                "SELECT n.id, n.text, n.pfad, n.typ, n.quelle, n.erfasst, n.snapshot, n.tags, n.widerspruch, n.bestaetigt "
                "FROM vault_fts f JOIN vault_notizen n ON n.rowid = f.rowid "
                "WHERE vault_fts MATCH ? ORDER BY rank LIMIT ?",
                (ausdruck, limit),
            ).fetchall()
        except Exception as exc:            # noqa: BLE001 - FTS-Syntax des Nutzers
            log.warning("Vault-Suche fehlgeschlagen: %s", exc)
            return []
    return [
        Treffer(id=z[0], text=z[1], pfad=z[2], typ=z[3], quelle=z[4], erfasst=z[5],
                snapshot=z[6], tags=[t for t in (z[7] or "").split(",") if t],
                widerspruch=z[8], bestaetigt=bool(z[9]))
        for z in zeilen
    ]


def alle(db_path) -> list[Treffer]:
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT id, text, pfad, typ, quelle, erfasst, snapshot, tags, "
            "widerspruch, bestaetigt FROM vault_notizen ORDER BY pfad"
        ).fetchall()
    return [
        Treffer(id=z[0], text=z[1], pfad=z[2], typ=z[3], quelle=z[4], erfasst=z[5],
                snapshot=z[6], tags=[t for t in (z[7] or "").split(",") if t],
                widerspruch=z[8], bestaetigt=bool(z[9]))
        for z in zeilen
    ]


def mtime_von(db_path, notiz_id: str) -> float | None:
    with session(db_path) as conn:
        zeile = conn.execute("SELECT mtime FROM vault_notizen WHERE id = ?",
                             (notiz_id,)).fetchone()
    return zeile[0] if zeile else None


# --- Beobachter -------------------------------------------------------------


class Beobachter:
    """Haelt den Index aktuell, waehrend jemand in Obsidian arbeitet."""

    def __init__(self, db_path, wurzel: Path, entprellung: float = ENTPRELLUNG_S) -> None:
        self.db_path = db_path
        self.wurzel = Path(wurzel).expanduser()
        self.entprellung = entprellung
        self._observer = None
        # BUGS-01 Fund 20: hier stand `dict[str, threading.Timer]` - EIN
        # OS-Thread je geaenderter Datei. Bei einem git-Checkout oder einem
        # Obsidian-Sync mit ein paar tausend Notizen liefen die alle
        # gleichzeitig und schrieben gleichzeitig in dieselbe SQLite-Datei.
        # Gemessen:
        #
        #     N=  200  indexiert=  200  FEHLEND=   0   Threads +200
        #     N= 1000  indexiert= 1000  FEHLEND=   0   Threads +1000
        #     N= 3000  indexiert= 2667  FEHLEND= 333   Threads +2848
        #        Ausnahme x333: OperationalError: database is locked
        #
        # Der Verlust war still: die Ausnahme starb im Timer-Thread, ohne
        # Retry und ohne Logeintrag. Und die Tabelle wurde nur beim
        # Neu-Planen aufgeraeumt, nie beim Feuern - 3000 Dateien liessen
        # 3000 Eintraege zurueck.
        #
        # Jetzt: eine Faelligkeitstabelle und EIN langlebiger Arbeiter. Damit
        # gibt es genau einen Schreiber, das Locking-Problem verschwindet
        # ohne hoeheren Busy-Timeout - und der Speicher waechst nicht mehr.
        self._faellig: dict[str, tuple[float, object]] = {}
        self._sperre = threading.Condition()
        self._laeuft = False
        self._arbeiter: threading.Thread | None = None

    def offene_arbeiten(self) -> int:
        """Wieviel noch aussteht. Fuer Tests und fuer die Fehlersuche."""
        with self._sperre:
            return len(self._faellig)

    def _spaeter(self, schluessel: str, arbeit) -> None:
        """Plant `arbeit` ein - und setzt die Frist zurueck, wenn sie schon steht.

        Das Zuruecksetzen ist die Entprellung: ein Editor schreibt mehrfach
        hintereinander, und gewinnen soll die letzte Fassung.
        """
        with self._sperre:
            self._faellig[schluessel] = (time.monotonic() + self.entprellung, arbeit)
            self._arbeiter_sicherstellen()
            self._sperre.notify_all()

    def _arbeiter_sicherstellen(self) -> None:
        """Der Arbeiter startet beim ersten Ereignis, nicht schon beim Bauen.

        Aufrufer haelt `self._sperre`.
        """
        if self._arbeiter is not None and self._arbeiter.is_alive():
            return
        self._laeuft = True
        self._arbeiter = threading.Thread(
            target=self._arbeiten, name="jarvis-vault-index", daemon=True
        )
        self._arbeiter.start()

    def _arbeiten(self) -> None:
        """Schlaeft bis zur fruehesten Faelligkeit und arbeitet dann seriell ab."""
        while True:
            with self._sperre:
                if not self._laeuft:
                    return
                if not self._faellig:
                    self._sperre.wait(timeout=1.0)
                    continue
                jetzt = time.monotonic()
                dran = [s for s, (wann, _) in self._faellig.items() if wann <= jetzt]
                if not dran:
                    naechste = min(wann for wann, _ in self._faellig.values())
                    self._sperre.wait(timeout=max(0.01, naechste - jetzt))
                    continue
                # pop, damit die Tabelle schrumpft - genau das fehlte vorher.
                arbeiten = [self._faellig.pop(s)[1] for s in dran]

            for arbeit in arbeiten:
                try:
                    arbeit()
                except Exception as exc:      # noqa: BLE001
                    # Ein Fehler an einer Datei darf die anderen nicht
                    # mitnehmen - und er darf nicht still verpuffen.
                    log.warning("Vault-Beobachter: Arbeit fehlgeschlagen - %s", exc)

    def start(self) -> "Beobachter":
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer

        beobachter = self

        class Handler(FileSystemEventHandler):
            def on_created(self, ereignis):
                if not ereignis.is_directory:
                    beobachter._spaeter(str(ereignis.src_path),
                                        lambda p=ereignis.src_path: aktualisiere(
                                            beobachter.db_path, beobachter.wurzel, Path(p)))

            def on_modified(self, ereignis):
                self.on_created(ereignis)

            def on_deleted(self, ereignis):
                if not ereignis.is_directory:
                    beobachter._spaeter(str(ereignis.src_path),
                                        lambda p=ereignis.src_path: entferne(
                                            beobachter.db_path, beobachter.wurzel, Path(p)))

            def on_moved(self, ereignis):
                # Der vergessene Fall. In Obsidian passiert er staendig.
                if ereignis.is_directory:
                    return
                alt, neu = ereignis.src_path, ereignis.dest_path
                beobachter._spaeter(str(neu), lambda: verschiebe(
                    beobachter.db_path, beobachter.wurzel, Path(alt), Path(neu)))

        self.wurzel.mkdir(parents=True, exist_ok=True)
        self._observer = Observer()
        self._observer.schedule(Handler(), str(self.wurzel), recursive=True)
        self._observer.start()
        return self

    def stop(self) -> None:
        with self._sperre:
            self._laeuft = False
            self._faellig.clear()
            self._sperre.notify_all()
        arbeiter, self._arbeiter = self._arbeiter, None
        if arbeiter is not None:
            arbeiter.join(timeout=5)
        if self._observer is not None:
            self._observer.stop()
            self._observer.join(timeout=5)
            self._observer = None

    def __enter__(self) -> "Beobachter":
        return self.start()

    def __exit__(self, *_) -> None:
        self.stop()
