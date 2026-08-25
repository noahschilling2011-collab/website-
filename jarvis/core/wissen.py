"""Nachschlagen statt raten - und der Cache dazu.

`docs/wissensquellen.md` stellt drei Dinge auseinander, die gern verwechselt
werden: Nachschlagen, Memory und Training. Hier steht nur das Erste.

**Der Gewinn ist nicht, dass JARVIS mehr weiss, sondern dass seine Antworten
pruefbar werden.** Deshalb tragen alle Treffer hier zwei Pflichtfelder:
`titel` (die Herkunft) und `snapshot` (wie alt das Wissen ist). Eine Antwort
ohne Herkunft ist eine Behauptung.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from core.db import session


@dataclass(frozen=True)
class Wissen:
    begriff: str
    titel: str
    text: str
    quelle: str
    snapshot: str | None = None
    url: str = ""

    @property
    def herkunft(self) -> str:
        teile = [self.titel or self.begriff]
        if self.snapshot:
            teile.append(f"Stand {self.snapshot}")
        teile.append(self.quelle)
        return " · ".join(teile)


# Kiwix haengt das Datum als _YYYY-MM an den Dateinamen. Das ist laut
# kiwix-serve-Doku (Option --nodatealiases) das erwartete Format - deshalb
# darf man es lesen, statt es zu raten.
ZIM_DATUM = re.compile(r"_(\d{4}-\d{2})$")


def snapshot_aus_zimname(name: str) -> str | None:
    treffer = ZIM_DATUM.search(name.removesuffix(".zim"))
    return treffer.group(1) if treffer else None


# --- Cache ------------------------------------------------------------------


def _jetzt() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def aus_cache(db_path: Path | str, begriff: str, quelle: str) -> Wissen | None:
    with session(db_path) as conn:
        zeile = conn.execute(
            "SELECT begriff, titel, text, quelle, snapshot FROM lookups "
            "WHERE begriff = ? AND quelle = ?",
            (begriff.strip().lower(), quelle),
        ).fetchone()
    if zeile is None:
        return None
    return Wissen(begriff=zeile[0], titel=zeile[1], text=zeile[2],
                  quelle=zeile[3], snapshot=zeile[4])


def in_cache(db_path: Path | str, treffer: Wissen) -> None:
    with session(db_path) as conn:
        conn.execute(
            "INSERT INTO lookups (begriff, quelle, text, titel, snapshot, geholt_am) "
            "VALUES (?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(begriff, quelle) DO UPDATE SET text=excluded.text, "
            "titel=excluded.titel, snapshot=excluded.snapshot, geholt_am=excluded.geholt_am",
            (treffer.begriff.strip().lower(), treffer.quelle, treffer.text,
             treffer.titel, treffer.snapshot, _jetzt()),
        )


def cache_zaehler(db_path: Path | str) -> int:
    with session(db_path) as conn:
        return conn.execute("SELECT count(*) FROM lookups").fetchone()[0]
