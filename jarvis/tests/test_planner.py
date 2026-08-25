"""Tests von Planner, Verifikation und Runner (Phase 4)."""

from __future__ import annotations

import asyncio
import time

import httpx
import pytest

from core.contracts import Permission, Step, StepStatus, Task, TaskBudget, ToolResult
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.planner import PlanungFehlgeschlagen, erstelle_plan
from core.runner import Laufzeit, fuehre_task_aus
from core.tools import registry
from core.verify import verifiziere
from tests.conftest import run

OHNE_KOSTEN = lambda a, b: 0.0  # noqa: E731


@pytest.fixture
def suche_ohne_netz():
    """web_search und fetch_url gegen MockTransport statt gegen das Internet."""
    suche, holen = registry.get("web_search"), registry.get("fetch_url")
    alt = (suche.api_key, suche.transport, holen.transport)
    suche.api_key = "test-key"
    suche.transport = httpx.MockTransport(lambda r: httpx.Response(200, json={
        "web": {"results": [{"title": "Quelle", "url": "https://example.org/q",
                             "description": "Ein Auszug."}]}}))
    holen.transport = httpx.MockTransport(lambda r: httpx.Response(
        200, headers={"content-type": "text/html"},
        text="<p>Der Hebesatz liegt bei 400 %.</p>"))
    yield
    suche.api_key, suche.transport, holen.transport = alt


# --- Planner --------------------------------------------------------------


def test_dod_4_ein_einfaches_ziel_ergibt_genau_einen_schritt():
    p = FakeLLMProvider(replies=['{"steps":[{"description":"Uhrzeit holen"}]}'])
    schritte = run(erstelle_plan(p, "Wie spät ist es?"))
    assert len(schritte) == 1
    assert schritte[0].agent is None


def test_planner_findet_json_im_markdown_block():
    p = FakeLLMProvider(replies=[
        'Hier:\n```json\n{"steps":[{"description":"A"},{"description":"B"}]}\n```'
    ])
    assert len(run(erstelle_plan(p, "x"))) == 2


def test_planner_repariert_hoechstens_zweimal_und_gibt_dann_auf():
    """0.6: maximal zwei Reparaturversuche, danach harter Fehler."""
    p = FakeLLMProvider(replies=["kein json", "auch nicht", "immer noch nicht"])
    with pytest.raises(PlanungFehlgeschlagen):
        run(erstelle_plan(p, "x"))
    assert len(p.calls) == 3, "ein Versuch plus zwei Reparaturen"


def test_planner_setzt_niemals_stillschweigend_einen_default():
    p = FakeLLMProvider(replies=["kaputt", "kaputt", "kaputt"])
    with pytest.raises(PlanungFehlgeschlagen):
        run(erstelle_plan(p, "x"))


def test_planner_bekommt_den_fehler_zurueck():
    p = FakeLLMProvider(replies=["kaputt", '{"steps":[{"description":"ok"}]}'])
    run(erstelle_plan(p, "x"))
    zweiter = p.calls[1]["messages"]
    assert any("kein gueltiges JSON" in m.content for m in zweiter
               if isinstance(m.content, str))


def test_planner_kuerzt_einen_zu_langen_plan():
    viele = ",".join(f'{{"description":"S{i}"}}' for i in range(30))
    p = FakeLLMProvider(replies=['{"steps":[' + viele + ']}'])
    assert len(run(erstelle_plan(p, "x", max_steps=5))) == 5


def test_planner_prompt_verbietet_kuenstliche_zerlegung():
    p = FakeLLMProvider(replies=['{"steps":[{"description":"A"}]}'])
    run(erstelle_plan(p, "x"))
    system = p.calls[0]["system"]
    assert "GENAU EINEN Schritt" in system
    assert "nur damit es nach Arbeit aussieht" in system


# --- Verifikation ---------------------------------------------------------


def test_verifikation_ist_code_und_kein_modellaufruf():
    """Der Auftrag verlangt konkrete Bedingungen, nicht 'sieht gut aus'."""
    import inspect

    import core.verify

    quelle = inspect.getsource(core.verify)
    assert "provider" not in quelle and "complete(" not in quelle


def test_rechercheschritt_ohne_quelle_gilt_als_fehlgeschlagen():
    schritt = Step(id="1", description="x", agent="research")
    bestanden, grund = verifiziere(
        schritt, ToolResult(ok=True, display="Die Steuer liegt bei 400 %.")
    )
    assert bestanden is False and "ohne Quelle" in grund


def test_eine_kurze_aber_vollstaendige_antwort_besteht():
    """Eine Mindestlaenge waere geraten - "42" ist ein Ergebnis."""
    bestanden, _ = verifiziere(Step(id="1", description="x"),
                               ToolResult(ok=True, display="42"))
    assert bestanden is True


def test_rechercheschritt_mit_quelle_besteht():
    schritt = Step(id="1", description="x", agent="research")
    bestanden, _ = verifiziere(schritt, ToolResult(
        ok=True, display="400 %", sources=["https://example.org"]))
    assert bestanden is True


@pytest.mark.parametrize("ergebnis,teil", [
    (None, "Kein Ergebnis"),
    (ToolResult(ok=False, error="kaputt"), "kaputt"),
    (ToolResult(ok=True, display="   "), "leer"),
    (ToolResult(ok=True, display="Ich konnte nichts finden."), "nichts gefunden"),
])
def test_verifikation_benennt_was_fehlt(ergebnis, teil: str):
    bestanden, grund = verifiziere(Step(id="1", description="x"), ergebnis)
    assert bestanden is False and teil.lower() in grund.lower()


# --- Runner ---------------------------------------------------------------


def test_runner_laeuft_einen_einschrittigen_task_durch():
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Uhrzeit holen"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
        "Es ist 12:00 Uhr.",
        "Es ist 12:00 Uhr.",
    ])
    t = run(fuehre_task_aus(p, "Wie spät?", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.status == "done"
    assert [s.status for s in t.steps] == [StepStatus.DONE]
    assert t.spent_tool_calls == 1
    assert t.spent_tokens > 0


def test_dod_5_budget_greift_und_liefert_ein_teilergebnis():
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"},'
        '{"description":"C"},{"description":"D"}]}',
        "A erledigt.", "B erledigt.", "A und B sind fertig, C und D nicht.",
    ])
    t = run(fuehre_task_aus(p, "Großes Ziel", budget=TaskBudget(max_steps=2),
                            kosten=OHNE_KOSTEN))
    assert t.status == "aborted_budget"
    assert "max_steps erreicht (2/2)" == t.abort_reason
    assert [s.status.value for s in t.steps] == ["done", "done", "skipped", "skipped"]
    assert t.result and "fertig" in t.result


def test_budget_wird_vor_dem_schritt_geprueft_nicht_danach():
    """0.5 - sonst laeuft der Schritt, der die Grenze reisst, noch durch."""
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"}]}',
        "A erledigt.", "Zusammenfassung.",
    ])
    t = run(fuehre_task_aus(p, "x", budget=TaskBudget(max_steps=1),
                            kosten=OHNE_KOSTEN))
    assert t.steps[0].attempts == 1
    assert t.steps[1].attempts == 0, "Schritt B haette nicht starten duerfen"


def test_das_budget_wird_nicht_selbst_erhoeht():
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"},{"description":"C"}]}',
        "A.", "Zusammenfassung.",
    ])
    budget = TaskBudget(max_steps=1)
    t = run(fuehre_task_aus(p, "x", budget=budget, kosten=OHNE_KOSTEN))
    assert t.budget.max_steps == 1 and budget.max_steps == 1


@pytest.mark.parametrize("budget,erwartet", [
    (TaskBudget(max_tokens=1), "max_tokens"),
    (TaskBudget(max_cost_eur=0.0), "max_cost_eur"),
    (TaskBudget(max_tool_calls=0), "max_tool_calls"),
])
def test_jede_budgetgrenze_stoppt_den_task(budget: TaskBudget, erwartet: str):
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"}]}',
        "A.", "B.", "Zusammenfassung.",
    ])
    t = run(fuehre_task_aus(p, "x", budget=budget,
                            kosten=lambda a, b: 1.0))
    assert t.status == "aborted_budget"
    assert erwartet in (t.abort_reason or "")


def test_dod_3_fehlgeschlagener_schritt_wird_wiederholt_und_scheitert_dann_sauber():
    """Kein Endlos-Loop: nach max_attempts ist Schluss."""
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Etwas recherchieren","agent":"research"}]}',
        # Der Agent antwortet ohne Quelle - Verifikation schlaegt fehl.
        "Die Zahl ist 400 %.",
    ])
    t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.steps[0].status is StepStatus.FAILED
    assert t.steps[0].attempts == 2, "genau max_attempts Versuche, dann Schluss"
    assert "ohne Quelle" in (t.steps[0].note or "")
    assert t.status == "failed"


def test_der_zweite_versuch_bekommt_gesagt_was_gefehlt_hat():
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Recherche","agent":"research"}]}',
        "Ohne Quelle.",
    ])
    run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    zweiter_agentenaufruf = p.calls[2]["messages"][0].content
    assert "nicht bestanden" in zweiter_agentenaufruf


def test_dod_2_quellen_haengen_unter_der_endantwort(suche_ohne_netz):
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"Hebesatz suchen","agent":"research"}]}',
        FakeTurn(tool_uses=(ToolUse("t1", "web_search", {"query": "Hebesatz"}),)),
        "Der Hebesatz liegt bei 400 %.",
        "Der Hebesatz liegt bei 400 %.",
    ])
    t = run(fuehre_task_aus(p, "Wie hoch ist die Grundsteuer?",
                            budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.status == "done"
    assert "https://example.org/q" in (t.result or "")
    assert t.steps[0].result.sources == ["https://example.org/q"]


def test_research_agent_ist_auf_read_gedeckelt():
    """Auch wenn ihm jemand ein maechtigeres Werkzeug in die Liste schreibt."""
    from core.agents import baue_agenten

    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.SENSITIVE)
    assert agenten["research"].max_permission is Permission.READ


def test_research_agent_darf_nicht_ins_gedaechtnis_schreiben():
    from core.agents import baue_agenten
    from core.tools.dispatch import run_tool

    agent = baue_agenten(FakeLLMProvider(), max_permission=Permission.SENSITIVE)["research"]
    ergebnis = run(run_tool("remember", {"text": "x"},
                            max_permission=agent.max_permission,
                            erlaubt=agent.tools))
    assert ergebnis.ok is False


def test_planungsfehler_beendet_den_task_sauber():
    p = FakeLLMProvider(replies=["kaputt", "kaputt", "kaputt"])
    t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.status == "failed" and "kein gueltiges JSON" in (t.result or "")


def test_abbruch_stoppt_vor_dem_naechsten_schritt():
    """0.5: Ein laufender Task muss sich abbrechen lassen."""
    abbruch = asyncio.Event()
    abbruch.set()
    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"},{"description":"B"}]}', "A.", "Fertig.",
    ])
    t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN,
                            laufzeit=Laufzeit(abbruch=abbruch)))
    assert t.status == "cancelled"
    assert all(s.attempts == 0 for s in t.steps)


def test_fortschritt_wird_gemeldet():
    ereignisse: list[str] = []

    async def on_step(task, i, schritt):
        ereignisse.append(f"{i}:{schritt.status.value}")

    p = FakeLLMProvider(replies=[
        '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig.",
    ])
    run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN,
                        laufzeit=Laufzeit(on_step=on_step)))
    assert "0:pending" in ereignisse and "0:running" in ereignisse
    assert ereignisse[-1] == "0:done"
