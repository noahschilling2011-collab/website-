"""Baut den Vault-Index von null neu.

    python -m scripts.reindex

Der Index ist abgeleitet: ihn wegzuwerfen kostet nichts. Wenn dieser Befehl
zweimal hintereinander unterschiedliche Ergebnisse liefert, steckt Zustand im
Index, der nicht im Vault steht - und dann ist das Prinzip gebrochen.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.config import get_settings          # noqa: E402
from core.vault_index import alle, reindex    # noqa: E402


def main() -> int:
    settings = get_settings()
    wurzel = settings.vault_pfad
    if not wurzel:
        print("VAULT_PFAD ist leer - kein Vault eingerichtet. Nichts zu tun.")
        return 0

    anzahl = reindex(settings.db_path, wurzel)
    print(f"{anzahl} Notizen aus {wurzel} indexiert.")
    for t in alle(settings.db_path)[:5]:
        print(f"  {t.id}  {t.pfad}")
    if anzahl > 5:
        print(f"  ... und {anzahl - 5} weitere")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
