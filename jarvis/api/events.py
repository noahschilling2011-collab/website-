"""Ereignisstrom (Phase 7).

Der Phasenauftrag ist deutlich: "live, nicht Polling im Sekundentakt". Also
Server-Sent Events.

Kein Broker, keine Bibliothek - ein Bus im Prozess mit einer Queue je
Zuhoerer. Es gibt genau einen Nutzer und einen Prozess; alles andere waere
Aufwand ohne Gegenwert.

Ein langsamer Zuhoerer darf den Auftrag nicht ausbremsen: ist seine Queue
voll, wird das aelteste Ereignis verworfen und er bekommt einen Hinweis. Ein
Dashboard, das haengt, ist kein Grund, einen Task anzuhalten.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, AsyncIterator, Awaitable, Callable

log = logging.getLogger("jarvis")

QUEUE_GROESSE = 256


class EventBus:
    def __init__(self) -> None:
        self._zuhoerer: set[asyncio.Queue] = set()

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=QUEUE_GROESSE)
        self._zuhoerer.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._zuhoerer.discard(queue)

    @property
    def anzahl(self) -> int:
        return len(self._zuhoerer)

    def publish(self, typ: str, daten: dict[str, Any]) -> None:
        """Nicht-blockierend. Wird aus dem Task-Lauf heraus aufgerufen."""
        ereignis = {"type": typ, "data": daten}
        for queue in list(self._zuhoerer):
            try:
                queue.put_nowait(ereignis)
            except asyncio.QueueFull:
                self._verdraengen(queue, ereignis)

    @staticmethod
    def _verdraengen(queue: asyncio.Queue, ereignis: dict[str, Any]) -> None:
        """Aeltestes weg, damit das NEUE hineinpasst - und ein Hinweis dazu.

        BUGS-01 Fund 19. Vorher machte diese Stelle EINEN Platz frei, stellte
        den Hinweis hinein - und fuer das eigentliche Ereignis war wieder
        keiner da. Der zweite `put_nowait` warf `QueueFull`, das `except`
        verschluckte es, und weg war es. Gemessen:

            Puffer voll: 256/256
            nach dem final-Ereignis: 256
            'final' ueberhaupt enthalten: False
            letztes Ereignis im Puffer: dropped

        Ausgerechnet `final` faellt so am haeufigsten heraus, weil es zuletzt
        kommt - und die Oberflaeche bleibt auf "Plan laeuft" stehen, weil sie
        seit Phase 7 bewusst nicht mehr pollt.

        Jetzt werden ZWEI Plaetze frei gemacht, einer fuer den Hinweis und
        einer fuer das Ereignis. Bleibt trotzdem keiner (zweiter Zuhoerer,
        Nebenlaeufigkeit), hat das Ereignis Vorrang vor dem Hinweis: der
        Hinweis ist Beiwerk, das Ereignis ist die Nachricht.
        """
        # Zwei Plaetze, weil zwei Dinge hineinsollen: der Hinweis und das
        # Ereignis. Genau das war der Fehler - es wurde nur einer frei.
        for _ in range(2):
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                break

        # Danach ist Platz. Dazwischen kann nichts passieren: `publish` ist
        # synchron und `await`-frei, es gibt also keinen Punkt, an dem ein
        # anderer Zuhoerer dazwischenkaeme.
        for stueck in ({"type": "dropped", "data": {}}, ereignis):
            try:
                queue.put_nowait(stueck)
            except asyncio.QueueFull:      # nur bei QUEUE_GROESSE < 2 moeglich
                log.warning("Ereignis %r ging verloren - Puffer zu klein.",
                            stueck["type"])


def sse(ereignis: dict[str, Any]) -> str:
    """Ein Ereignis im SSE-Format."""
    return (
        f"event: {ereignis['type']}\n"
        f"data: {json.dumps(ereignis['data'], ensure_ascii=False, default=str)}\n\n"
    )


async def strom(
    bus: EventBus,
    herzschlag: float = 20.0,
    getrennt: Callable[[], Awaitable[bool]] | None = None,
) -> AsyncIterator[str]:
    """Der Generator hinter `GET /api/events`.

    Der Herzschlag ist kein Schmuck: ohne ihn merkt weder der Browser noch ein
    Proxy, dass die Verbindung noch steht, und schliesst sie irgendwann.

    `getrennt` wird bei jedem Herzschlag gefragt. Ohne diese Pruefung haengt
    der Generator nach einem weggegangenen Client bis zum naechsten Ereignis -
    und haelt so lange einen Zuhoerer-Platz besetzt.
    """
    queue = bus.subscribe()
    try:
        yield sse({"type": "hello", "data": {"listeners": bus.anzahl}})
        while True:
            try:
                ereignis = await asyncio.wait_for(queue.get(), timeout=herzschlag)
            except asyncio.TimeoutError:
                if getrennt is not None and await getrennt():
                    return
                yield ": herzschlag\n\n"
                continue
            yield sse(ereignis)
    finally:
        bus.unsubscribe(queue)
