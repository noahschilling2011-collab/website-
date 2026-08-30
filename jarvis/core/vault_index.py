"""Der abgeleitete Index ueber den Vault.

Nichts hier ist autoritativ. `reindex()` darf jederzeit alles wegwerfen und
aus den Markdown-Dateien neu bauen - das ist der Vertrag aus
`docs/MIGRATION-VAULT.md`, und `test_vault.py` prueft ihn: zweimal neu
indexieren muss byte-gleiche Zeilen liefern.

Aktuell gehalten wird er an zwei Stellen und sonst nirgends (FIX-04 Schritt 3):
beim Start durch `reindex()`, und bei jedem Lesen durch
`core.gedaechtnis.frisch_halten`, das die Zeitstempel vergleicht. Ueberwacht
wird nichts - eine Dateiueberwachung stand hier frueher und ist entfallen,
siehe den Kommentar weiter unten.

Der Schluessel ist `id` aus dem Frontmatter, nie der Dateiname. Deshalb
ueberlebt ein Fakt das Umbenennen und das Verschieben in Obsidian - der Fall,
den man vergisst, und der dort staendig passiert.
"""

from __future__ import annotations

import logging
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
    """NUR fuer Tests. Im Betrieb ruft das niemand - und das ist richtig so.

    `frisch_halten()` vergleicht die Zeitstempel im selben Durchgang, in dem
    es ohnehin ueber alle Notizen laeuft; ein zweiter Einzelabruf je Notiz
    waere dort eine Abfrage pro Datei statt einer fuer alle.

    Sie steht hier trotzdem, statt als rohes SQL im Test: so haengt
    tests/test_vault.py am Modul und nicht am Tabellenschema. Wer die Spalte
    umbenennt, aendert eine Stelle.

    Bei der Verknuepfungspruefung am 30.08.2026 wurde sie als "toter Code"
    gemeldet. Das stimmt nicht - sie hat einen Benutzer. Irrefuehrend war
    nur, dass man ihr das nicht ansah.
    """
    with session(db_path) as conn:
        zeile = conn.execute("SELECT mtime FROM vault_notizen WHERE id = ?",
                             (notiz_id,)).fetchone()
    return zeile[0] if zeile else None


# --- Frischhalten ohne Ueberwachung -----------------------------------------
#
# Hier stand die Klasse `Beobachter`: ein watchdog-Observer, der den Vault im
# Hintergrund beobachtete. Sie ist mit FIX-04 entfallen.
#
# Der Grund ist nicht Geschmack, sondern dass sie nichts mehr tut, was jemand
# merkt. FIX-04 Schritt 3 verlangt "Start plus Befehl plus Zeitstempel-Pruefung"
# und verbietet ausdruecklich Dateiueberwachung, Hintergrund-Dienst und
# Polling-Schleife. Seit `core.gedaechtnis.frisch_halten` bei JEDEM Lesen die
# Zeitstempel prueft - und seit es auch geloeschte Dateien aus dem Index wirft -
# ist jede Beobachtung, die vor einem Lesen passiert, unsichtbar: wer nicht
# liest, merkt den Unterschied nicht, und wer liest, bekommt den frischen Stand.
#
# Was sie dafuer kostete: eine Abhaengigkeit ausserhalb des festgelegten Stacks
# (`watchdog`, CLAUDE.md:31 nennt sie nicht), einen Thread ueber die ganze
# Laufzeit, 141 Zeilen - und BUGS-01 Fund 20, wo sie bei 3000 Dateien 2848
# Threads startete und 333 Notizen still aus dem Index verlor.
#
# `reindex()` oben ist der Befehl, `frisch_halten` die Zeitstempel-Pruefung.
