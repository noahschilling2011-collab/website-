"""Tests der Delegation (Phase 6)."""

from __future__ import annotations

import time

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.agents import baue_agenten
from core.contracts import Permission, Step, Task, TaskBudget, ToolResult
from core.delegation import DelegationsKontext, kontext
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.tools import registry
from core.tools.dispatch import run_tool
from core.verify import verifiziere
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def suche_ohne_netz(settings):
    suche, holen = registry.get("web_search"), registry.get("fetch_url")
    alt = (suche.api_key, suche.transport, holen.transport)
    # Der App-Start setzt den Key aus den Settings - sonst ueberschreibt er
    # den hier gesetzten wieder mit dem leeren Wert.
    settings.search_api_key = "test-key"
    suche.api_key = "test-key"
    suche.transport = httpx.MockTransport(lambda r: httpx.Response(200, json={
        "web": {"results": [
            {"title": "Helmtest 2026", "url": "https://example.org/helme",
             "description": "Drei Fullface-Helme im Vergleich."}]}}))
    holen.transport = httpx.MockTransport(lambda r: httpx.Response(
        200, headers={"content-type": "text/html"},
        text="<p>Modell A 199 €, Modell B 229 €, Modell C 245 €.</p>"))
    yield
    suche.api_key, suche.transport, holen.transport = alt


def warte_auf_ende(client, task_id: str, sekunden: float = 15.0) -> dict:
    ende = time.monotonic() + sekunden
    while time.monotonic() < ende:
        d = client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        time.sleep(0.02)
    raise AssertionError("Task wurde nicht fertig")


# --- Aufbau ---------------------------------------------------------------


def test_hermes_ruft_agenten_und_recherchiert_nicht_selbst():
    hermes = baue_agenten(FakeLLMProvider(), max_permission=Permission.EXTERNAL)["hermes"]
    assert "ask_agent" in hermes.tools
    assert "web_search" not in hermes.tools
    assert hermes.can_call_agents == ["research"]


def test_hermes_prompt_verlangt_die_kennzeichnung_der_herkunft():
    hermes = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)["hermes"]
    assert "welcher Teil von" in hermes.system_prompt
    assert "eckigen Klammern" in hermes.system_prompt


# --- DoD 5: Tiefengrenze --------------------------------------------------


def test_dod_5_aus_tiefe_2_wird_kein_weiterer_agent_gerufen():
    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)
    tief = Task(goal="x", budget=TaskBudget(max_depth=2), depth=2)
    ctx = DelegationsKontext(task=tief, agenten=agenten, max_depth=2)

    marke = kontext.set(ctx)
    try:
        ergebnis = run(run_tool("ask_agent", {"agent": "research", "task": "such was"}))
    finally:
        kontext.reset(marke)

    assert ergebnis.ok is False
    assert "max_depth=2" in (ergebnis.error or "")
    # ...und geloggt.
    assert len(ctx.abgelehnt) == 1
    assert ctx.abgelehnt[0]["agent"] == "research"
    assert ctx.abgelehnt[0]["depth"] == 2


def test_aus_tiefe_0_darf_delegiert_werden(suche_ohne_netz):
    provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("t1", "web_search", {"query": "Helme"}),)),
        "Drei Helme gefunden.",
    ])
    agenten = baue_agenten(provider, max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget(max_depth=2), depth=0)
    marke = kontext.set(DelegationsKontext(task=haupt, agenten=agenten, max_depth=2))
    try:
        ergebnis = run(run_tool("ask_agent", {"agent": "research", "task": "Helme"}))
    finally:
        kontext.reset(marke)
    assert ergebnis.ok is True


def test_unbekannter_agent_wird_gemeldet():
    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)
    marke = kontext.set(DelegationsKontext(
        task=Task(goal="x", budget=TaskBudget()), agenten=agenten, max_depth=2))
    try:
        ergebnis = run(run_tool("ask_agent", {"agent": "gibtsnicht", "task": "x"}))
    finally:
        kontext.reset(marke)
    assert ergebnis.ok is False and "gibtsnicht" in (ergebnis.error or "")


def test_ask_agent_ausserhalb_eines_auftrags_tut_nichts():
    ergebnis = run(run_tool("ask_agent", {"agent": "research", "task": "x"}))
    assert ergebnis.ok is False


# --- Herkunft und Budget --------------------------------------------------


def test_das_teilergebnis_traegt_den_namen_des_agenten(suche_ohne_netz):
    provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("t1", "web_search", {"query": "Helme"}),)),
        "Modell A kostet 199 €.",
    ])
    agenten = baue_agenten(provider, max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget())
    marke = kontext.set(DelegationsKontext(task=haupt, agenten=agenten, max_depth=2))
    try:
        ergebnis = run(run_tool("ask_agent", {"agent": "research", "task": "Helme"}))
    finally:
        kontext.reset(marke)
    assert ergebnis.display.startswith("[research] ")
    assert ergebnis.sources == ["https://example.org/helme"]


def test_der_unterauftrag_bekommt_kein_eigenes_budget():
    agenten = baue_agenten(FakeLLMProvider(replies=["ok"]),
                           max_permission=Permission.LOCAL)
    budget = TaskBudget(max_cost_eur=0.05)
    haupt = Task(goal="x", budget=budget)
    gesehen: list[Task] = []

    async def merken(unterauftrag, parent_id):
        gesehen.append(unterauftrag)

    marke = kontext.set(DelegationsKontext(
        task=haupt, agenten=agenten, max_depth=2, on_subtask=merken))
    try:
        run(run_tool("ask_agent", {"agent": "research", "task": "x"}))
    finally:
        kontext.reset(marke)

    assert gesehen and gesehen[0].budget is budget
    assert gesehen[0].depth == haupt.depth + 1


# --- DoD 2: Preise brauchen Quellen ---------------------------------------


@pytest.mark.parametrize("text", [
    "Der Helm kostet 249 €.", "Preis: EUR 199", "199 Euro", "Ab 89,90 €",
])
def test_dod_2_ein_preis_ohne_quelle_laesst_den_schritt_scheitern(text: str):
    bestanden, grund = verifiziere(
        Step(id="1", description="x"), ToolResult(ok=True, display=text)
    )
    assert bestanden is False and "Quelle" in grund


def test_ein_preis_mit_quelle_besteht():
    bestanden, _ = verifiziere(Step(id="1", description="x"), ToolResult(
        ok=True, display="Der Helm kostet 249 €.",
        sources=["https://example.org/helme"]))
    assert bestanden is True


def test_eine_zahl_ohne_waehrung_ist_kein_preis():
    bestanden, _ = verifiziere(Step(id="1", description="x"),
                               ToolResult(ok=True, display="Der Helm wiegt 1250 Gramm."))
    assert bestanden is True


# --- Ende zu Ende: der Referenz-Task --------------------------------------


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def test_dod_1_3_4_referenz_task_mit_baum_und_kosten(client, settings, suche_ohne_netz):
    settings.llm_price_in_per_mtok = 4.6
    settings.llm_price_out_per_mtok = 23.0

    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"Drei Helme unter 250 € finden und vergleichen",'
            '"agent":"hermes"}]}',
            # Hermes delegiert an research.
            FakeTurn(tool_uses=(ToolUse("t1", "ask_agent", {
                "agent": "research",
                "task": "Finde drei Gravity-Bike-Helme unter 250 € mit Preis und Quelle",
            }),)),
            # Der Research-Agent sucht.
            FakeTurn(tool_uses=(ToolUse("t2", "web_search", {"query": "Gravity Bike Helm"}),)),
            "Modell A 199 €, Modell B 229 €, Modell C 245 €.",
            # Hermes fasst zusammen, mit Kennzeichnung.
            "[research] Modell A 199 €, B 229 €, C 245 €. Ich empfehle Modell B: "
            "bester Kompromiss aus Gewicht und Preis.",
            # Abschluss.
            "Ich empfehle Modell B (229 €) — bester Kompromiss aus Gewicht und Preis.",
        ])
        tid = c.post("/api/tasks", json={
            "goal": "Finde mir drei Gravity-Bike-Helme unter 250 €, vergleiche sie "
                    "und sag mir, welchen ich nehmen soll."
        }, headers=TOKEN).json()["task_id"]
        fertig = warte_auf_ende(c, tid)

        # DoD 1: laeuft durch, mit Empfehlung.
        assert fertig["status"] == "done"
        assert "empfehle" in (fertig["result"] or "").lower()

        # DoD 2: Quelle mit Abrufdatum unter der Antwort.
        assert "https://example.org/helme" in fertig["result"]
        assert "abgerufen am" in fertig["result"]

        # DoD 3: der Baum ist da - Hermes hat einen Unterauftrag.
        assert fertig["children"], "kein Unterauftrag persistiert"
        kind = c.get(f"/api/tasks/{fertig['children'][0]}", headers=TOKEN).json()
        assert kind["depth"] == 1
        assert kind["steps"][0]["agent"] == "research"

        # DoD 4: Gesamtkosten und Gesamttokens.
        assert fertig["spent_tokens"] > 0
        assert fertig["spent_cost_eur"] > 0

        # DoD 6: unter dem Default-Budget geblieben.
        assert fertig["status"] != "aborted_budget"
