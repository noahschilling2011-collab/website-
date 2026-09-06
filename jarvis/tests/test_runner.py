"""Runner-Tests der Verknuepfungspruefung vom 31.08.2026, Gruppe runner.

Zwei Funde stehen hier fest:

* Fund 1 - ein Plan mit genau `max_steps` Schritten endete auf
  `aborted_budget`, obwohl alles durchlief.
* Fund 2 - ein Agentenname, den es nicht gibt, fiel still auf `jarvis`
  zurueck; die Oberflaeche zeigte weiter den falschen Namen.

Die Tests pruefen die URSACHE, nicht die Oberflaeche: bei Fund 1 die Stelle
im Runner, die nach dem letzten Schritt noch einmal `max_steps` pruefte, bei
Fund 2 die Stelle, die den Fehlgriff verschluckte.
"""

from __future__ import annotations

import json
import logging

import pytest

from core.contracts import StepStatus, TaskBudget
from core.llm import FakeLLMProvider
from core.runner import fuehre_task_aus
from tests.conftest import run

OHNE_KOSTEN = lambda a, b: 0.0  # noqa: E731


def _plan(n: int, agent: str | None = None) -> str:
    """JSON-Plan mit n Schritten, wie der Planner ihn liefern wuerde."""
    return json.dumps(
        {"steps": [{"description": f"S{i}", "agent": agent} for i in range(1, n + 1)]}
    )


# --- Fund 1: max_steps reisst nach dem letzten Schritt ----------------------


def test_fund1_plan_mit_genau_max_steps_schritten_endet_auf_done():
    """Der Fund selbst: 12 von 12 Schritten, alle durch - und trotzdem abgebrochen.

    Vor der Reparatur lief nach dem 12. Schritt noch einmal die volle
    Budgetpruefung. `max_steps` zaehlt Schritte mit `attempts > 0`, also
    12 >= 12 - die Grenze riss, obwohl kein Schritt mehr ausstand.
    PLAN_MAX_STEPS und BUDGET_MAX_STEPS sind beide 12; der Fall war mit der
    Standardkonfiguration erreichbar.
    """
    p = FakeLLMProvider(replies=(
        [_plan(12)] + [f"S{i} erledigt." for i in range(1, 13)] + ["Zusammenfassung."]
    ))
    t = run(fuehre_task_aus(p, "Zwoelf Schritte", budget=TaskBudget(max_steps=12),
                            kosten=OHNE_KOSTEN))

    assert [s.status for s in t.steps] == [StepStatus.DONE] * 12
    assert not [s for s in t.steps if s.status is StepStatus.SKIPPED]
    # Das ist der Kern: kein Schritt uebersprungen, also auch keine gerissene
    # Grenze zu melden.
    assert t.abort_reason is None
    assert t.status == "done"


def test_fund1_gilt_auch_fuer_einen_einschrittigen_plan():
    """Derselbe Fehler in seiner kleinsten Form: max_steps=1, ein Schritt."""
    p = FakeLLMProvider(replies=[_plan(1), "S1 erledigt.", "Zusammenfassung."])
    t = run(fuehre_task_aus(p, "Ein Schritt", budget=TaskBudget(max_steps=1),
                            kosten=OHNE_KOSTEN))
    assert t.status == "done"
    assert t.abort_reason is None


def test_fund1_max_steps_greift_weiterhin_wenn_noch_schritte_ausstehen():
    """Gegenprobe: die Grenze darf nicht verschwunden sein.

    Vier geplante Schritte, Budget 3 - der 4. darf nicht mehr starten, und
    der Nutzer muss die Begruendung sehen (0.5: eine Grenze, die man nicht
    benennen kann, ist keine Grenze). Nicht 13 gegen 12 geprueft: der Planner
    kuerzt jeden Plan vorher auf PLAN_MAX_STEPS = 12, der Fall kaeme also gar
    nicht bis zur Budgetpruefung.
    """
    p = FakeLLMProvider(replies=(
        [_plan(4)] + [f"S{i} erledigt." for i in range(1, 4)] + ["Zusammenfassung."]
    ))
    t = run(fuehre_task_aus(p, "Vier Schritte", budget=TaskBudget(max_steps=3),
                            kosten=OHNE_KOSTEN))
    assert t.status == "aborted_budget"
    assert t.abort_reason == "max_steps erreicht (3/3)"
    assert t.steps[3].status is StepStatus.SKIPPED
    assert t.steps[3].attempts == 0


def test_fund1_verbrauchsgrenzen_reissen_nach_dem_letzten_schritt_weiterhin():
    """Gegenprobe zu BUGS-01 Fund 4, das die Nachpruefung ueberhaupt einbaute.

    Nach dem letzten Schritt duerfen nur die STRUKTURgrenzen (`max_steps`,
    `max_depth`) ausfallen. Ein Ein-Schritt-Plan, der Kosten ueberzogen hat,
    muss sich weiterhin als `aborted_budget` melden - sonst waere aus der
    Reparatur ein neuer Fehler geworden.
    """
    p = FakeLLMProvider(replies=[_plan(1), "S1 erledigt.", "Zusammenfassung."])
    t = run(fuehre_task_aus(p, "Ein teurer Schritt",
                            budget=TaskBudget(max_steps=1, max_cost_eur=0.5),
                            kosten=lambda a, b: 1.0))
    assert t.status == "aborted_budget"
    assert "max_cost_eur" in (t.abort_reason or "")


# --- Fund 2: unbekannter Agentenname ---------------------------------------


def test_fund2_unbekannter_agent_wird_gemeldet_und_der_name_korrigiert(caplog):
    """Der Fund selbst: der Planner nennt "Recherche", das es nicht gibt.

    Vorher lief der Schritt kommentarlos auf jarvis, waehrend `schritt.agent`
    den Fantasienamen behielt - der so gespeichert und an die Oberflaeche
    gemeldet wurde. Geprueft wird die Ursache an beiden Enden: es muss eine
    Warnung geben, und der Name muss der des Agenten sein, der wirklich lief.
    """
    p = FakeLLMProvider(replies=[
        _plan(1, agent="Recherche"),
        "S1 erledigt.",
        "Zusammenfassung.",
    ])
    with caplog.at_level(logging.WARNING, logger="jarvis"):
        t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))

    assert t.steps[0].agent == "jarvis", "der Name muss dem Agenten folgen"
    warnungen = [r.getMessage() for r in caplog.records
                 if r.levelno >= logging.WARNING]
    assert any("Recherche" in m and "gibt es nicht" in m for m in warnungen), (
        f"kein Log zum Rueckfall: {warnungen}"
    )


def test_fund2_ein_echter_agentenname_bleibt_unangetastet():
    """Gegenprobe: der Regelfall darf nicht umgeschrieben werden.

    Waere die Reparatur zu grob, wuerde sie jeden Namen ueberschreiben - und
    die Quellenregel in core/verify.py, die auf `step.agent == "research"`
    schaut, griffe nie wieder.
    """
    p = FakeLLMProvider(replies=[
        _plan(1, agent="research"),
        # Ohne Quelle: die Verifikation muss diesen Schritt als
        # Rechercheschritt beurteilen.
        "Die Zahl ist 400 %.",
    ])
    t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.steps[0].agent == "research"
    assert "ohne Quelle" in (t.steps[0].note or "")


def test_fund2_ein_leerer_agent_bleibt_leer(caplog):
    """Kein Agent ist kein Fehlgriff - "jarvis macht es selbst" bleibt leer."""
    p = FakeLLMProvider(replies=[_plan(1), "S1 erledigt.", "Zusammenfassung."])
    with caplog.at_level(logging.WARNING, logger="jarvis"):
        t = run(fuehre_task_aus(p, "x", budget=TaskBudget(), kosten=OHNE_KOSTEN))
    assert t.steps[0].agent is None
    assert not [r for r in caplog.records if "gibt es nicht" in r.getMessage()]
