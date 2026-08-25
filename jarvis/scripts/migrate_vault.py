"""Migriert `facts` in den Vault (docs/MIGRATION-VAULT.md, Schritt 4).

    python -m scripts.migrate_vault            # nur schreiben und zaehlen
    python -m scripts.migrate_vault --abschluss  # zusaetzlich facts -> facts_alt

Loescht nichts. `facts` wird hoechstens umbenannt, und auch das erst, wenn
Zaehlung und Stichprobe stimmen. Weicht etwas ab, bricht der Lauf ab.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.config import get_settings                      # noqa: E402
from core.db import session                               # noqa: E402
from core.vault import Notiz, schreibe, sicherstellen     # noqa: E402
from core.vault_index import alle, reindex                # noqa: E402

GRUEN, ROT, GRAU, AUS = "\033[32m", "\033[31m", "\033[90m", "\033[0m"


def fakten(db_path) -> list[dict]:
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT id, text, category, created_at, confirmed FROM facts ORDER BY id"
        ).fetchall()
    return [dict(z) for z in zeilen]


def als_notiz(zeile: dict) -> Notiz:
    """Die bisherige ID wandert mit - sie ist ab jetzt der Schluessel."""
    return Notiz(
        id=f"f_{zeile['id']}",
        text=zeile["text"],
        typ="fakt",
        quelle="gespraech",
        erfasst=(zeile["created_at"] or "")[:10],
        tags=[t for t in [zeile["category"]] if t and t != "allgemein"],
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--abschluss", action="store_true",
                   help="nach erfolgreicher Pruefung facts in facts_alt umbenennen")
    args = p.parse_args()

    settings = get_settings()
    if not settings.vault_pfad:
        print(f"{ROT}VAULT_PFAD ist leer.{AUS} Trag ihn in die .env ein.")
        return 1

    wurzel = sicherstellen(Path(settings.vault_pfad))
    quelle = fakten(settings.db_path)
    print(f"[0] Bestand: {GRUEN}{len(quelle)}{AUS} Zeilen in facts")

    print("[1] schreiben")
    for zeile in quelle:
        ziel = schreibe(wurzel, als_notiz(zeile), unterordner="fakten")
        print(f"    {GRAU}{zeile['id']:>4} -> {ziel.name}{AUS}")

    print("[2] neu indexieren")
    anzahl = reindex(settings.db_path, wurzel)
    print(f"    {anzahl} Notizen im Index")

    print("[3] zaehlen und vergleichen")
    im_vault = [t for t in alle(settings.db_path) if t.typ == "fakt"]
    if len(im_vault) != len(quelle):
        print(f"    {ROT}✗ {len(im_vault)} im Vault, {len(quelle)} in facts. "
              f"Nichts geloescht, nichts umbenannt.{AUS}")
        return 1
    print(f"    {GRUEN}✓{AUS} {len(im_vault)} == {len(quelle)}")

    print("[4] Stichprobe, Zeichen fuer Zeichen")
    nach_id = {t.id: t for t in im_vault}
    for zeile in quelle[:3]:
        t = nach_id.get(f"f_{zeile['id']}")
        gleich = t is not None and t.text.strip() == zeile["text"].strip()
        zeichen = f"{GRUEN}✓{AUS}" if gleich else f"{ROT}✗{AUS}"
        print(f"    {zeichen} f_{zeile['id']}: {zeile['text'][:60]!r}")
        if not gleich:
            print(f"      {ROT}Vault: {t.text[:60]!r}{AUS}" if t else f"      {ROT}fehlt{AUS}")
            return 1
    if not quelle:
        print(f"    {GRAU}keine Zeilen - nichts zu vergleichen{AUS}")

    if args.abschluss:
        print("[5] facts -> facts_alt")
        with session(settings.db_path) as conn:
            da = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='facts_alt'"
            ).fetchone()
            if da:
                print(f"    {GRAU}facts_alt existiert schon - nichts getan{AUS}")
            else:
                conn.execute("ALTER TABLE facts RENAME TO facts_alt")
                print(f"    {GRUEN}✓{AUS} umbenannt. NICHT geloescht - "
                      f"loeschen fruehestens in zwei Wochen.")
    else:
        print(f"[5] {GRAU}uebersprungen (--abschluss setzen){AUS}")

    print(f"\n{GRUEN}Migration durchgelaufen.{AUS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
