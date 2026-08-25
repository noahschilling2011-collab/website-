"""Die Verträge aus docs/contracts.md, ausgeführt.

0.7 sagt: "Nachfolgend als Spezifikation gemeint — beim Bauen ausführen und
testen." Genau das passiert hier.
"""

from __future__ import annotations

import time

import pytest

from core.config import Settings
from core.contracts import (
    Agent,
    Permission,
    Step,
    StepStatus,
    Task,
    TaskBudget,
    Tool,
    ToolResult,
)


def test_permission_ist_geordnet():
    """Der Dispatcher vergleicht Stufen - dafür muss die Ordnung stimmen."""
    assert Permission.INFO < Permission.READ < Permission.LOCAL
    assert Permission.LOCAL < Permission.EXTERNAL < Permission.SENSITIVE
    assert int(Permission.INFO) == 0 and int(Permission.SENSITIVE) == 4


def test_toolresult_hat_die_felder_aus_dem_vertrag():
    r = ToolResult(ok=True)
    assert (r.data, r.error, r.display, r.sources, r.duration_ms) == (
        None, None, "", [], 0,
    )


def test_toolresult_sources_werden_nicht_geteilt():
    a, b = ToolResult(ok=True), ToolResult(ok=True)
    a.sources.append("https://example.org")
    assert b.sources == []


def test_tool_execute_muss_implementiert_werden():
    with pytest.raises(NotImplementedError):
        import asyncio
        asyncio.run(Tool().execute())


def test_tool_ist_ohne_bestaetigung_voreingestellt_und_hat_30s_timeout():
    assert Tool.requires_confirmation is False
    assert Tool.timeout_s == 30


def test_step_startet_pending_mit_zwei_versuchen():
    s = Step(id="s1", description="etwas tun")
    assert s.status is StepStatus.PENDING
    assert s.attempts == 0 and s.max_attempts == 2


def test_task_id_ist_zwoelf_hexzeichen():
    ids = {Task().id for _ in range(50)}
    assert len(ids) == 50
    assert all(len(i) == 12 and all(c in "0123456789abcdef" for c in i) for i in ids)


def test_task_hat_immer_ein_budget():
    """Ein Task ohne Budget existiert nicht (0.5)."""
    assert isinstance(Task().budget, TaskBudget)


def test_budget_defaults_stehen_so_in_der_env_example():
    b = TaskBudget()
    assert (b.max_steps, b.max_depth, b.max_tool_calls) == (12, 2, 20)
    assert (b.max_tokens, b.max_seconds, b.max_cost_eur) == (60_000, 180, 0.50)


def test_budget_kommt_aus_den_settings():
    s = Settings(_env_file=None, budget_max_steps=3, budget_max_cost_eur=0.05)
    b = TaskBudget.from_settings(s)
    assert b.max_steps == 3 and b.max_cost_eur == 0.05


def test_frischer_task_verletzt_nichts():
    assert Task(budget=TaskBudget()).budget_verletzung() is None


@pytest.mark.parametrize("feld,wert,erwartet", [
    ("spent_tokens", 60_000, "max_tokens"),
    ("spent_tool_calls", 20, "max_tool_calls"),
    ("spent_cost_eur", 0.50, "max_cost_eur"),
    ("depth", 3, "max_depth"),
])
def test_jede_grenze_wird_benannt(feld: str, wert, erwartet: str):
    """Eine Grenze, die man nicht benennen kann, ist keine Grenze."""
    t = Task(budget=TaskBudget())
    setattr(t, feld, wert)
    verletzung = t.budget_verletzung()
    assert verletzung is not None and erwartet in verletzung


def test_max_steps_greift():
    t = Task(budget=TaskBudget(max_steps=2))
    t.steps = [Step(id="a", description="x"), Step(id="b", description="y")]
    assert "max_steps" in (t.budget_verletzung() or "")


def test_max_seconds_greift():
    t = Task(budget=TaskBudget(max_seconds=180))
    assert "max_seconds" in (t.budget_verletzung(jetzt=t.created_at + 181) or "")
    assert t.budget_verletzung(jetzt=t.created_at + 5) is None


def test_task_status_kennt_aborted_budget():
    t = Task()
    t.status = "aborted_budget"
    assert t.status == "aborted_budget"


def test_agent_run_muss_implementiert_werden():
    with pytest.raises(NotImplementedError):
        import asyncio
        asyncio.run(Agent().run(Task(), Step(id="s", description="d")))


def test_agent_kann_ohne_unteragenten():
    assert Agent.can_call_agents == []
