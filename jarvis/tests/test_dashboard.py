"""Tests von Ereignisstrom, Statistik und Werkzeug-Log (Phase 7)."""

from __future__ import annotations

import asyncio
import json
import threading
import time

import httpx

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.events import EventBus, sse, strom
from core import db
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def warte_auf_ende(client, tid: str, sekunden: float = 10.0) -> dict:
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{tid}", headers=TOKEN).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        time.sleep(0.02)
    raise AssertionError("Task wurde nicht fertig")


# --- Bus ------------------------------------------------------------------


def test_ereignisse_erreichen_alle_zuhoerer():
    bus = EventBus()

    async def lauf():
        a, b = bus.subscribe(), bus.subscribe()
        bus.publish("task", {"id": "1"})
        return await a.get(), await b.get()

    erstes, zweites = run(lauf())
    assert erstes == zweites == {"type": "task", "data": {"id": "1"}}


def test_ein_langsamer_zuhoerer_bremst_den_task_nicht():
    """Voll heisst: aeltestes weg, weiter. Ein haengendes Dashboard ist kein
    Grund, einen Auftrag anzuhalten."""
    from api import events

    bus = EventBus()

    async def lauf():
        queue = bus.subscribe()
        for i in range(events.QUEUE_GROESSE + 20):
            bus.publish("task", {"i": i})
        return queue.qsize()

    groesse = run(lauf())
    assert groesse <= events.QUEUE_GROESSE


def test_verworfene_ereignisse_werden_gemeldet_nicht_verschwiegen():
    from api import events

    bus = EventBus()

    async def lauf():
        queue = bus.subscribe()
        for i in range(events.QUEUE_GROESSE + 5):
            bus.publish("task", {"i": i})
        gesehen = []
        while not queue.empty():
            gesehen.append(queue.get_nowait()["type"])
        return gesehen

    assert "dropped" in run(lauf())


def test_abmelden_entfernt_den_zuhoerer():
    bus = EventBus()
    q = bus.subscribe()
    assert bus.anzahl == 1
    bus.unsubscribe(q)
    assert bus.anzahl == 0


def test_sse_format():
    text = sse({"type": "step", "data": {"id": "s1", "status": "done"}})
    assert text.startswith("event: step\ndata: {")
    assert text.endswith("\n\n")
    assert json.loads(text.split("data: ", 1)[1].strip())["status"] == "done"


def test_der_strom_beginnt_mit_hello_und_haelt_sich_am_leben():
    bus = EventBus()

    async def lauf():
        gen = strom(bus, herzschlag=0.05)
        erstes = await gen.__anext__()
        zweites = await gen.__anext__()   # nichts passiert -> Herzschlag
        await gen.aclose()
        return erstes, zweites

    erstes, zweites = run(lauf())
    assert erstes.startswith("event: hello")
    assert zweites.startswith(":")


# --- Endpunkt -------------------------------------------------------------


def test_events_brauchen_den_token(client):
    assert client.get("/api/events").status_code == 401


def test_der_strom_antwortet_als_event_stream(live_server):
    with httpx.stream("GET", f"{live_server}/api/events", headers=TOKEN,
                      timeout=10.0) as antwort:
        assert antwort.status_code == 200
        assert antwort.headers["content-type"].startswith("text/event-stream")
        assert antwort.headers["cache-control"] == "no-cache"
        assert next(antwort.iter_lines()).startswith("event: hello")


def test_dod_1_ein_laufender_task_meldet_sich_von_selbst(live_server, settings):
    """Kein Polling: die Ereignisse kommen, ohne dass jemand fragt."""
    # Derselbe App-Zustand, den der Thread bedient.
    live_server.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Uhrzeit holen"}]}',
        "Es ist spät.", "Es ist spät.",
    ])

    gesehen: list[str] = []
    fertig = threading.Event()

    def mitlesen() -> None:
        try:
            with httpx.stream("GET", f"{live_server}/api/events", headers=TOKEN,
                              timeout=20.0) as antwort:
                for zeile in antwort.iter_lines():
                    if zeile.startswith("event: "):
                        gesehen.append(zeile[len("event: "):])
                    if '"final": true' in zeile.lower():
                        break
        except Exception:  # noqa: BLE001 - der Test haengt sonst am Strom
            pass
        finally:
            fertig.set()

    leser = threading.Thread(target=mitlesen, daemon=True)
    leser.start()
    for _ in range(200):
        if gesehen:
            break
        time.sleep(0.02)
    assert gesehen and gesehen[0] == "hello", "der Strom kam nicht zustande"

    tid = httpx.post(f"{live_server}/api/tasks", json={"goal": "Wie spät ist es?"},
                     headers=TOKEN, timeout=10.0).json()["task_id"]

    ende = time.monotonic() + 20
    while time.monotonic() < ende:
        d = httpx.get(f"{live_server}/api/tasks/{tid}", headers=TOKEN,
                      timeout=10.0).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            break
        time.sleep(0.05)

    fertig.wait(timeout=10)
    assert "task" in gesehen, f"nur gesehen: {gesehen}"
    assert "step" in gesehen


# --- DoD 2: Schritt nachlesen ---------------------------------------------


def test_dod_2_ein_alter_task_laesst_prompt_und_antwort_nachlesen(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Etwas ausrechnen"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "calculator", {"expression": "6*7"}),)),
        "Das Ergebnis ist 42.", "Das Ergebnis ist 42.",
    ])
    tid = client.post("/api/tasks", json={"goal": "6 mal 7?"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)

    schritt = client.get(f"/api/tasks/{tid}", headers=TOKEN).json()["steps"][0]
    assert "[system]" in schritt["prompt"]
    assert "Etwas ausrechnen" in schritt["prompt"]
    assert "6 mal 7?" in schritt["prompt"]
    assert schritt["result"]["display"] == "Das Ergebnis ist 42."
    aufrufe = schritt["result"]["data"]["tool_calls"]
    assert aufrufe[0]["name"] == "calculator"
    assert aufrufe[0]["result"]["display"] == "6*7 = 42"


# --- DoD 3: Kosten nachgerechnet ------------------------------------------


def test_dod_3_die_kostenanzeige_stimmt_mit_llm_calls_ueberein(client, settings):
    settings.llm_price_in_per_mtok = 4.6
    settings.llm_price_out_per_mtok = 23.0
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Ziel"},
                     headers=TOKEN).json()["task_id"]
        warte_auf_ende(c, tid)

        stats = c.get("/api/stats", headers=TOKEN).json()
        health = c.get("/api/health", headers=TOKEN).json()
        aufrufe = db.list_llm_calls(settings.db_path)

    summe = round(sum(a.cost_eur for a in aufrufe), 6)
    assert stats["total"]["cost_eur"] == pytest.approx(summe)
    assert health["spend"]["cost_eur"] == pytest.approx(summe)
    assert stats["total"]["in_tokens"] == sum(a.in_tokens for a in aufrufe)
    assert stats["total"]["calls"] == len(aufrufe)


def test_statistik_zaehlt_pro_tag_modell_und_werkzeug(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Uhrzeit"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
        "Es ist spät.", "Es ist spät.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Wie spät?"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)

    stats = client.get("/api/stats", headers=TOKEN).json()
    assert stats["per_day"] and stats["per_day"][0]["calls"] > 0
    assert stats["per_model"][0]["model"] == "fake-echo-1"
    assert any(w["name"] == "clock" for w in stats["per_tool"])
    assert stats["tasks"]["done"] == 1


def test_fehlerrate_wird_gerechnet_nicht_geschaetzt(client, settings):
    with db.session(settings.db_path) as conn:
        db.init_db(conn)
    for ok in (True, True, False, True):
        db.log_llm_call(settings.db_path, model="m", in_tokens=1, out_tokens=1,
                        cost_eur=0.0, duration_ms=1, ok=ok)
    stats = client.get("/api/stats", headers=TOKEN).json()
    assert stats["total"]["calls"] == 4
    assert stats["total"]["fehler"] == 1
    assert stats["total"]["fehlerrate"] == 0.25


def test_leere_datenbank_ergibt_keine_division_durch_null(client):
    stats = client.get("/api/stats", headers=TOKEN).json()
    assert stats["total"]["fehlerrate"] == 0.0
    assert stats["total"]["cost_eur"] == 0


# --- Werkzeug-Log ---------------------------------------------------------


def test_das_werkzeug_log_ist_abrufbar(client):
    client.app.state.provider = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Uhrzeit"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
        "Es ist spät.", "Es ist spät.",
    ])
    tid = client.post("/api/tasks", json={"goal": "Wie spät?"},
                      headers=TOKEN).json()["task_id"]
    warte_auf_ende(client, tid)

    log = client.get("/api/tool-calls", headers=TOKEN).json()
    assert log and log[0]["name"] == "clock" and log[0]["ok"] is True


def test_werkzeug_log_und_statistik_brauchen_den_token(client):
    assert client.get("/api/tool-calls").status_code == 401
    assert client.get("/api/stats").status_code == 401


# --- DoD 4: Abbruch stoppt wirklich ---------------------------------------


def test_dod_4_abbruch_stoppt_den_task_wirklich(client):
    """Der Task muss danach im Endzustand cancelled stehen, nicht nur
    'wurde gebeten'.

    Abgebrochen wird hier, NACHDEM der Plan steht - sonst gibt es keine
    Schritte, die man ueberspringen koennte. Der Fall davor hat seit FIX-03
    Schritt 3a einen eigenen Test.
    """
    import time as _t

    langsam = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"},{"description":"C"}]}',
        "A erledigt.", "B erledigt.", "C erledigt.", "Fertig.",
    ])
    client.app.state.provider = langsam
    tid = client.post("/api/tasks", json={"goal": "Langes Ziel"},
                      headers=TOKEN).json()["task_id"]

    frist = _t.monotonic() + 10
    while _t.monotonic() < frist:
        d = client.get(f"/api/tasks/{tid}", headers=TOKEN).json()
        if d["steps"]:
            break
        _t.sleep(0.01)
    else:
        raise AssertionError("der Plan stand nie")

    client.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)
    fertig = warte_auf_ende(client, tid)
    assert fertig["status"] == "cancelled"
    assert fertig["abort_reason"]
    assert any(s["status"] == "skipped" for s in fertig["steps"])


def test_ein_abbruch_vor_dem_plan_bezahlt_den_planungszug_nicht(client):
    """FIX-03 Schritt 3a: auch der Planungszug ist ein bezahlter Aufruf.

    Wer sofort nach dem Absenden abbricht, soll ihn nicht mehr bezahlen.
    Vorher lief er durch, weil die erste Abbruchpruefung erst vor dem ersten
    SCHRITT stand - und Schritte gibt es ohne Plan nicht.
    """
    import asyncio as _asyncio

    class LangsamerPlaner(FakeLLMProvider):
        async def complete(self, messages, *, system, tools=None):
            await _asyncio.sleep(0.8)
            return await super().complete(messages, system=system, tools=tools)

    anbieter = LangsamerPlaner(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    client.app.state.provider = anbieter
    tid = client.post("/api/tasks", json={"goal": "Langes Ziel"},
                      headers=TOKEN).json()["task_id"]
    client.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)

    fertig = warte_auf_ende(client, tid)
    assert fertig["status"] == "cancelled", fertig
    assert fertig["steps"] == [], fertig["steps"]
    assert len(anbieter.calls) == 0, (
        f"{len(anbieter.calls)} Modellaufruf(e) nach dem Abbruch"
    )
    assert fertig["result"], "auch hier gehoert eine Antwort hin"
