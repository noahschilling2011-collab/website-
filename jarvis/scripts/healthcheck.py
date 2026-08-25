"""Healthcheck fuer den Container (Phase 10).

    python -m scripts.healthcheck

Gesund heisst hier: der Server **antwortet**. Ein 401 ist eine gueltige
Antwort - `/api/health` ist tokenpflichtig (0.4.4), und der Container kennt
den Token nicht unbedingt. Ungesund ist nur, wenn gar nichts kommt.
"""

from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request


def main() -> int:
    host = os.environ.get("JARVIS_HOST", "127.0.0.1")
    # 0.0.0.0 ist eine Bind-Adresse, keine Zieladresse.
    ziel = "127.0.0.1" if host in ("0.0.0.0", "::") else host
    port = os.environ.get("JARVIS_PORT", "8000")
    url = f"http://{ziel}:{port}/api/health"

    try:
        urllib.request.urlopen(url, timeout=3)
    except urllib.error.HTTPError as fehler:
        # 401 = der Server steht und weist uns korrekt ab. Das ist gesund.
        if fehler.code in (401, 403):
            return 0
        print(f"HTTP {fehler.code} von {url}", file=sys.stderr)
        return 1
    except Exception as fehler:  # noqa: BLE001 - jeder andere Fehler ist ungesund
        print(f"{type(fehler).__name__}: {fehler}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
