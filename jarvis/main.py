"""Einstiegspunkt.

    python -m uvicorn main:app --reload --timeout-graceful-shutdown 5

`python main.py` geht auch - dann gelten JARVIS_HOST und JARVIS_PORT aus der
`.env`. Voreinstellung ist 127.0.0.1 (0.4.3), nicht 0.0.0.0.
"""

from __future__ import annotations

import logging

from api.app import create_app
from core.config import get_settings

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

app = create_app()

# Wie lange uvicorn beim Herunterfahren auf noch laufende Antworten wartet.
#
# WAS WAR FALSCH
# Dieser Wert wurde nirgends gesetzt. Dann ist `timeout_graceful_shutdown`
# None, und uvicorn wartet in `Server._wait_tasks_to_complete()` UNBEGRENZT
# auf offene Verbindungen (uvicorn 0.52.4, server.py: `asyncio.wait_for(...,
# timeout=self.config.timeout_graceful_shutdown)`).
#
# WARUM DAS FALSCH IST
# `strom()` in api/events.py laeuft absichtlich in `while True` und endet nur,
# wenn der Client geht - so soll ein Ereignisstrom sein. Beim Herunterfahren
# ruft uvicorn zwar `connection.shutdown()` auf, das setzt fuer eine schon
# laufende Antwort aber nur `cycle.keep_alive = False` (httptools_impl.py).
# Es kommt KEIN `http.disconnect`, also bleibt `request.is_disconnected`
# False, der Herzschlag-Zweig kehrt nicht zurueck, und der Generator laeuft
# weiter. Ein einziger offener Browser-Tab auf dem Command Center haelt den
# Server damit fest: Strg-C braucht ein zweites Strg-C, `docker stop` wartet
# seine vollen 10 s ab und schiesst dann per SIGKILL.
#
# Schlimmer als das Warten ist die Reihenfolge: `await self.lifespan.shutdown()`
# steht in server.py NACH dem Warten auf die Verbindungen. Der finally-Block
# in api/app.py lief also nie - `tasks.stop_alle()` und `provider.aclose()`
# wurden uebersprungen. Genau die sollen verhindern, dass bezahlte
# Modellaufrufe in der Luft haengen.
#
# WOHER DER BEFUND
# Verknuepfungspruefung 31.08.2026, Gruppe shutdown, Fund 1. Nachgemessen mit
# echtem SIGTERM an einem echten Prozess und einem offenen /api/events:
#
#   timeout_graceful_shutdown=None -> beendet=False nach 25.0s | lifespan-finally lief=False
#   timeout_graceful_shutdown=5    -> beendet=True  nach  5.2s | lifespan-finally lief=True
#
# WARUM 5 UND NICHT MEHR
# docker-compose.yml setzt kein `stop_grace_period`, es gilt also Dockers
# Voreinstellung von 10 s bis zum SIGKILL. 5 s Warten laesst dem
# lifespan-Shutdown danach noch Luft, statt ihn vom SIGKILL abschneiden zu
# lassen. Derselbe Wert steht im CMD des Dockerfiles; tests/test_events.py
# haelt beide Stellen zusammen.
#
# NICHT GEMACHT
# Das `asyncio.Event`, das der Pruefer zusaetzlich vorgeschlagen hat (der
# lifespan setzt es beim Verlassen, `strom` wartet daneben darauf). Es kann
# nicht funktionieren: der lifespan-Shutdown laeuft erst NACH dem Warten auf
# die Verbindungen. Das Event wuerde also genau dann gesetzt, wenn niemand
# mehr darauf wartet - die Messung oben zeigt es, `lifespan-finally lief` war
# nach 25 s Warten immer noch False.
HERUNTERFAHREN_SEKUNDEN = 5


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()
    uvicorn.run(
        app,
        host=settings.jarvis_host,
        port=settings.jarvis_port,
        timeout_graceful_shutdown=HERUNTERFAHREN_SEKUNDEN,
    )
