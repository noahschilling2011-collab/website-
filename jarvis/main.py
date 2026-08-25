"""Einstiegspunkt.

    python -m uvicorn main:app --reload

`python main.py` geht auch - dann gelten JARVIS_HOST und JARVIS_PORT aus der
`.env`. Voreinstellung ist 127.0.0.1 (0.4.3), nicht 0.0.0.0.
"""

from __future__ import annotations

import logging

from api.app import create_app
from core.config import get_settings

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

app = create_app()


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()
    uvicorn.run(app, host=settings.jarvis_host, port=settings.jarvis_port)
