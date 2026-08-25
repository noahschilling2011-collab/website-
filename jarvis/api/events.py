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
                # Aeltestes wegwerfen, damit der Strom weiterlaeuft. Der
                # Zuhoerer erfaehrt davon - stiller Verlust waere schlimmer.
                try:
                    queue.get_nowait()
                    queue.put_nowait({"type": "dropped", "data": {}})
                    queue.put_nowait(ereignis)
                except (asyncio.QueueEmpty, asyncio.QueueFull):
                    pass


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
