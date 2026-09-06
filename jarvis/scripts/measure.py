"""Misst, ob SQLite reicht (Phase 10).

`docs/decisions.md` sagt zu Postgres/pgvector: "Migration ist spaeter ein
Nachmittag" - und der Phasenauftrag erlaubt den Wechsel nur, "wenn SQLite
nachweislich limitiert" ist. Nachweislich heisst: gemessen.

    python -m scripts.measure [--messages 20000] [--facts 5000]

Die Zahlen landen in STATUS.md. Ohne sie bleibt SQLite.
"""

from __future__ import annotations

import argparse
import random
import shutil
import statistics
import tempfile
import time
from pathlib import Path

from core import db, memory

WOERTER = (
    "rad santa cruz downhill helm bremse gabel daempfer kette reifen "
    "kaffee tee morgen abend termin rechnung steuer angebot vertrag "
    "norwegen schweden alpen tour wetter regen sonne schnee wind "
    "python fastapi sqlite index abfrage server test fehler antwort"
).split()


def satz(zufall: random.Random, laenge: int = 18) -> str:
    return " ".join(zufall.choice(WOERTER) for _ in range(laenge))


def miss(funktion, wiederholungen: int = 30) -> dict[str, float]:
    zeiten = []
    for _ in range(wiederholungen):
        start = time.perf_counter()
        funktion()
        zeiten.append((time.perf_counter() - start) * 1000)
    zeiten.sort()
    return {
        "median_ms": statistics.median(zeiten),
        "p95_ms": zeiten[int(len(zeiten) * 0.95) - 1],
        "max_ms": zeiten[-1],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Misst SQLite unter Last.")
    parser.add_argument("--messages", type=int, default=20_000)
    parser.add_argument("--facts", type=int, default=5_000)
    args = parser.parse_args()

    zufall = random.Random(42)   # feste Saat: die Messung ist wiederholbar
    tmp = Path(tempfile.mkdtemp(prefix="jarvis-measure-"))
    pfad = tmp / "last.db"

    try:
        with db.session(pfad) as conn:
            db.init_db(conn)

        print(f"Schreibe {args.messages} Nachrichten und {args.facts} Fakten…")
        start = time.perf_counter()
        with db.session(pfad) as conn:
            conn.executemany(
                "INSERT INTO messages (role, content, created_at) VALUES (?, ?, ?)",
                [
                    ("user" if i % 2 == 0 else "assistant", satz(zufall),
                     f"2026-01-01T00:00:{i % 60:02d}Z")
                    for i in range(args.messages)
                ],
            )
            conn.executemany(
                "INSERT INTO facts (text, category, created_at) VALUES (?, ?, ?)",
                [
                    (satz(zufall, 10), zufall.choice(["hobby", "arbeit", "ausruestung"]),
                     "2026-01-01T00:00:00Z")
                    for _ in range(args.facts)
                ],
            )
        schreibdauer = time.perf_counter() - start

        groesse = pfad.stat().st_size / 1_048_576
        print(f"  {schreibdauer:.1f} s, Datei {groesse:.1f} MB")
        print()

        anfragen = ["santa cruz rad", "kaffee morgen termin", "norwegen tour wetter",
                    "python fastapi index", "helm bremse gabel"]

        def fakten_suche() -> None:
            memory.search_facts(pfad, zufall.choice(anfragen))

        def nachrichten_suche() -> None:
            memory.search_messages(pfad, zufall.choice(anfragen))

        def kontext() -> None:
            memory.kontextblock(pfad, zufall.choice(anfragen))

        def verlauf() -> None:
            memory.search_messages(pfad, "rad")

        for name, funktion in [
            ("FTS5 ueber facts", fakten_suche),
            ("FTS5 ueber messages", nachrichten_suche),
            ("Kontextblock (Suche + Format)", kontext),
            ("Wiederholte gleiche Anfrage", verlauf),
        ]:
            werte = miss(funktion)
            print(f"{name:<32} median {werte['median_ms']:6.2f} ms   "
                  f"p95 {werte['p95_ms']:6.2f} ms   max {werte['max_ms']:6.2f} ms")

        print()
        print("Urteil: solange p95 deutlich unter 50 ms liegt, ist die Suche nicht")
        print("der Engpass - ein Modellaufruf dauert das Tausendfache. Postgres")
        print("oder pgvector wuerden hier nichts loesen, was kaputt waere.")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
