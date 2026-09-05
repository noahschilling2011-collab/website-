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
from datetime import datetime, timedelta, timezone
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


def aus_cache(db_path: Path | str, begriff: str, quelle: str,
              max_alter_stunden: float | None = None) -> Wissen | None:
    """Ein Treffer aus dem Cache - oder None, wenn er zu alt ist.

    `max_alter_stunden=None` heisst "kein Verfall". Genau das war bis zum
    30.08.2026 das EINZIGE Verhalten: `geholt_am` wurde geschrieben und nie
    gelesen. Gefunden bei der Verknuepfungspruefung, von drei Skeptikern
    bestaetigt.

    Der Fehler war nicht kosmetisch. `docs/wissensquellen.md` DoD 4 sagt:
    "Eine Frage zu einem Ereignis nach dem Snapshot-Datum geht nachweislich
    auf `wiki_live` ueber, statt aus dem veralteten Stand zu antworten."
    Wenn `wiki_live` seinerseits aus einem Cache antwortet, der nie
    abläuft, ist der Uebergang wertlos: nach dem ersten Nachschlagen eines
    Begriffs bekommt man denselben Text bis in alle Ewigkeit.

    Verglichen werden Zeichenketten, nicht Zeitobjekte. `_jetzt()` schreibt
    `%Y-%m-%dT%H:%M:%SZ` - dieses Format ist lexikografisch sortierbar, und
    ein Vergleich ohne Parsen kann nicht an einer Zeitzone scheitern.
    """
    frage = ("SELECT begriff, titel, text, quelle, snapshot FROM lookups "
             "WHERE begriff = ? AND quelle = ?")
    werte: list = [begriff.strip().lower(), quelle]
    if max_alter_stunden is not None:
        grenze = datetime.now(timezone.utc) - timedelta(hours=max_alter_stunden)
        frage += " AND geholt_am >= ?"
        werte.append(grenze.strftime("%Y-%m-%dT%H:%M:%SZ"))
    with session(db_path) as conn:
        zeile = conn.execute(frage, tuple(werte)).fetchone()
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
