"""Verknuepfungspruefung 31.08.2026 - Gruppe delegation.

Zwei Funde, beide an der Grenze zwischen `ask_agent` und dem Rest:

* Fund 1: `core/verify.py` wurde im Produktivcode nur aus der Schrittschleife
  des Runners gerufen. Ein Unterauftrag ueber `ask_agent` laeuft nicht durch
  diese Schleife - fuer delegierte Schritte fiel die Verifikation komplett aus.
* Fund 2: `LaufBeendet` ist eine gewoehnliche Exception. Der Dispatcher fing
  sie mit seinem allgemeinen `except Exception` ab und machte aus dem Abbruch
  einen Werkzeugfehler.

Die Tests hier pruefen die Ursache, nicht die Oberflaeche: sie vergleichen das
Ergebnis von `ask_agent` mit dem, was `verifiziere()` fuer denselben Schritt
sagt, und sie fahren den Abbruch ueber den echten Pruefpunkt aus
`core/abbruch.py` durch den echten Dispatcher.
"""

from __future__ import annotations

import pytest

from core.abbruch import LaufBeendet, baue_pruefpunkt
from core.agents import baue_agenten
from core.contracts import (
    Permission,
    Step,
    StepStatus,
    Task,
    TaskBudget,
    Tool,
    ToolResult,
)
from core.delegation import DelegationsKontext, kontext
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.tools import registry
from core.tools.dispatch import run_tool
from core.verify import verifiziere
from tests.conftest import run


def _delegiere(agenten, haupt, *, agent: str, auftrag: str = "Was kostet das?"):
    """Ruft `ask_agent` durch den echten Dispatcher.

    Absichtlich ueber `run_tool` und nicht direkt ueber `AskAgent.execute`:
    fuer Fund 2 ist genau der Dispatcher die Stelle, an der die Ausnahme
    frueher verschwand.
    """
    gesehen: list[tuple[str, str]] = []

    async def merken(unterauftrag: Task, parent_id: str | None) -> None:
        gesehen.append((unterauftrag.id, unterauftrag.status))

    ctx = DelegationsKontext(task=haupt, agenten=agenten, max_depth=2,
                             on_subtask=merken)
    marke = kontext.set(ctx)
    try:
        return run(run_tool("ask_agent", {"agent": agent, "task": auftrag})), gesehen
    finally:
        kontext.reset(marke)


# --- Fund 1: die Verifikation gilt auch fuer delegierte Schritte -----------


def test_fund1_research_ohne_quelle_faellt_auch_als_unterauftrag_durch():
    """Derselbe Text, der als Planschritt FAILED ist, darf hier nicht DONE sein.

    Vor der Reparatur stand in `core/delegation.py` nur
    `status = DONE if ergebnis.ok else FAILED`, und `ergebnis.ok` ist in
    `ToolAgent._run` bloss `bool(text.strip())`.
    """
    antwort = "Der Helm kostet 249 Euro."
    agenten = baue_agenten(FakeLLMProvider(replies=[antwort]),
                           max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget())

    ergebnis, gesehen = _delegiere(agenten, haupt, agent="research")

    # Die Ursache: `verifiziere()` sagt Nein - und genau das muss ankommen.
    erwartet = verifiziere(
        Step(id="x", description="Was kostet das?", agent="research"),
        ToolResult(ok=True, display=antwort),
    )
    assert erwartet[0] is False, "Der Fund selbst stimmt nicht mehr"
    assert ergebnis.ok is False
    assert ergebnis.error == erwartet[1]

    # ...und der Unterauftrag steht nicht als erledigt in der Tabelle.
    assert [status for _, status in gesehen] == ["running", "failed"]


def test_fund1_die_begruendung_erreicht_den_rufer_im_display():
    """`run_tool_loop` reicht `display` ans Modell und nur ersatzweise `error`.

    Stuende die Begruendung nur in `error`, saehe hermes weiter allein den
    quellenlosen Text - die Pruefung waere ohne Wirkung.
    """
    agenten = baue_agenten(FakeLLMProvider(replies=["Der Helm kostet 249 Euro."]),
                           max_permission=Permission.LOCAL)
    ergebnis, _ = _delegiere(agenten, Task(goal="x", budget=TaskBudget()),
                             agent="research")
    assert "Quelle" in ergebnis.display
    # Die Herkunft bleibt trotzdem gekennzeichnet.
    assert ergebnis.display.startswith("[research] ")


def test_fund1_die_preisregel_gilt_auf_dem_delegationspfad_ebenfalls():
    """Nicht nur die Quellenpflicht - die ganze Pruefung aus `core/verify.py`.

    `jarvis` ist kein research-Agent, die Quellenregel greift hier also
    nicht. Was greift, ist die Preisregel: eine Zahl mit Waehrung ohne Beleg.
    """
    agenten = baue_agenten(FakeLLMProvider(replies=["Kostet 249 EUR."]),
                           max_permission=Permission.LOCAL)
    ergebnis, gesehen = _delegiere(agenten, Task(goal="x", budget=TaskBudget()),
                                   agent="jarvis")
    assert ergebnis.ok is False
    assert "Preis" in (ergebnis.error or "")
    assert [status for _, status in gesehen] == ["running", "failed"]


def test_fund1_der_schritt_traegt_die_begruendung_als_note():
    """Ohne `note` steht im UI zwar FAILED, aber nicht warum."""
    agenten = baue_agenten(FakeLLMProvider(replies=["Ohne Beleg."]),
                           max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget())

    gesehene_tasks: list[Task] = []

    async def merken(unterauftrag: Task, parent_id: str | None) -> None:
        gesehene_tasks.append(unterauftrag)

    marke = kontext.set(DelegationsKontext(
        task=haupt, agenten=agenten, max_depth=2, on_subtask=merken))
    try:
        run(run_tool("ask_agent", {"agent": "research", "task": "such was"}))
    finally:
        kontext.reset(marke)

    schritt = gesehene_tasks[-1].steps[0]
    assert schritt.status is StepStatus.FAILED
    assert "Quelle" in schritt.note


def test_fund1_ein_belegter_unterauftrag_geht_weiterhin_durch():
    """Gegenprobe: eine Pruefung, die alles abweist, waere keine Pruefung.

    Der research-Agent holt hier eine echte Quelle ueber `wiki_lokal` - das
    Werkzeug liefert `sources`, und damit besteht der Schritt.
    """

    class QuelleLiefern(Tool):
        name = "quelle_liefern"
        description = "Testwerkzeug: liefert eine Quelle."
        parameters = {"type": "object", "properties": {}, "additionalProperties": False}
        permission = Permission.READ

        async def execute(self) -> ToolResult:
            return ToolResult(ok=True, display="Steht auf der Seite.",
                              sources=["https://example.org/helme"])

    zustand = registry._snapshot()
    try:
        registry.register(QuelleLiefern)
        provider = FakeLLMProvider(replies=[
            FakeTurn(tool_uses=(ToolUse("t1", "quelle_liefern", {}),)),
            "Der Helm kostet 249 Euro.",
        ])
        agenten = baue_agenten(provider, max_permission=Permission.LOCAL)
        agenten["research"].tools = list(agenten["research"].tools) + ["quelle_liefern"]
        ergebnis, gesehen = _delegiere(agenten, Task(goal="x", budget=TaskBudget()),
                                       agent="research")
    finally:
        registry._restore(zustand)

    assert ergebnis.ok is True, ergebnis.error
    assert ergebnis.sources == ["https://example.org/helme"]
    assert [status for _, status in gesehen] == ["running", "done"]


# --- Fund 2: der Abbruch geht durch den Dispatcher hindurch ----------------


def _abbruch_nach_dem_ersten_zug(agenten, haupt) -> None:
    """Der Nutzer bricht ab, waehrend der Unteragent schon gearbeitet hat.

    Der erste Pruefpunkt (vor dem Modellzug) laesst durch, der zweite (vor dem
    Werkzeug) wirft. So entsteht ein echter Teiltext an der Ausnahme.
    """
    zaehler = {"n": 0}

    def abgebrochen() -> bool:
        zaehler["n"] += 1
        return zaehler["n"] > 1

    agenten["research"].budget_pruefung = baue_pruefpunkt(
        haupt, abgebrochen=abgebrochen)


def test_fund2_der_abbruch_wird_vom_dispatcher_nicht_geschluckt():
    """`LaufBeendet` ist kein Werkzeugfehler, sondern das Ende des Laufs."""
    provider = FakeLLMProvider(replies=[FakeTurn(
        text="Zwischenstand.",
        tool_uses=(ToolUse("t1", "wiki_lokal", {"titel": "Helm"}),),
    )])
    agenten = baue_agenten(provider, max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget())
    _abbruch_nach_dem_ersten_zug(agenten, haupt)

    with pytest.raises(LaufBeendet) as ende:
        _delegiere(agenten, haupt, agent="research")

    assert ende.value.status == "cancelled"
    # Der Teiltext des Unteragenten darf nicht verlorengehen - er ist das
    # Teilergebnis, das der Runner an den Schritt haengt.
    assert "Zwischenstand." in ende.value.teiltext


def test_fund2_der_unterauftrag_bleibt_nach_dem_abbruch_nicht_auf_running():
    """Sonst steht der Unterauftrag fuer immer als laufend in der Tabelle.

    `api/tasks.py` persistiert Unterauftrag und Unterschritt ausschliesslich
    ueber `on_subtask`. Wird der zweite Ruf uebersprungen, bleibt der letzte
    gespeicherte Zustand "running".
    """
    provider = FakeLLMProvider(replies=[FakeTurn(
        text="Zwischenstand.",
        tool_uses=(ToolUse("t1", "wiki_lokal", {"titel": "Helm"}),),
    )])
    agenten = baue_agenten(provider, max_permission=Permission.LOCAL)
    haupt = Task(goal="x", budget=TaskBudget())
    _abbruch_nach_dem_ersten_zug(agenten, haupt)

    gesehen: list[Task] = []

    async def merken(unterauftrag: Task, parent_id: str | None) -> None:
        # Der Zustand muss zum Zeitpunkt des Rufs festgehalten werden -
        # `db.save_task` sieht auch nur den. Beim ersten Ruf hat der
        # Unterauftrag noch keinen Schritt, deshalb die Abfrage.
        gesehen.append((
            unterauftrag.status,
            unterauftrag.steps[0].status if unterauftrag.steps else None,
        ))

    marke = kontext.set(DelegationsKontext(
        task=haupt, agenten=agenten, max_depth=2, on_subtask=merken))
    try:
        with pytest.raises(LaufBeendet):
            run(run_tool("ask_agent", {"agent": "research", "task": "such was"}))
    finally:
        kontext.reset(marke)

    assert len(gesehen) == 2, gesehen
    assert gesehen[-1][0] == "cancelled"
    assert gesehen[-1][1] is not StepStatus.RUNNING


def test_fund2_gewoehnliche_werkzeugfehler_faengt_der_dispatcher_weiterhin_ab():
    """Gegenprobe: der Dispatcher darf nur `LaufBeendet` durchlassen.

    Ein `except Exception: raise` wuerde Fund 2 auch "loesen" - und dabei die
    Zusage des Dispatchers brechen, dass ein Tool nie den Task umreisst.
    """

    class Kaputt(Tool):
        name = "kaputtes_testwerkzeug"
        description = "Testwerkzeug: wirft immer."
        parameters = {"type": "object", "properties": {}, "additionalProperties": False}
        permission = Permission.INFO

        async def execute(self) -> ToolResult:
            raise ValueError("kaputt")

    zustand = registry._snapshot()
    try:
        registry.register(Kaputt)
        ergebnis = run(run_tool("kaputtes_testwerkzeug", {}))
    finally:
        registry._restore(zustand)

    assert ergebnis.ok is False
    assert "ValueError" in (ergebnis.error or "")
