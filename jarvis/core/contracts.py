"""Verbindliche Verträge (docs/contracts.md, Abschnitte 0.5 und 0.7).

Diese Datentypen ändert man nicht. Alle Phasen bauen darauf auf.

Die Spezifikation steht in `docs/contracts.md`; hier ist sie ausgeführt und
getestet - so wie es dort verlangt ist ("beim Bauen ausführen und testen").

Ergänzt sind ausschließlich Dinge, die nichts umbenennen und nichts umbauen:
`TaskBudget.from_settings`, `Task.remaining_*` und `Task.budget_verletzung` -
Hilfsfunktionen, damit die Budgetprüfung an einer Stelle steht statt in jeder
Schleife neu.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal


class Permission(int, Enum):
    INFO = 0        # nur reden, keine Außenwirkung
    READ = 1        # lesen: Websuche, Datei lesen, Kalender lesen
    LOCAL = 2       # lokal schreiben: Notiz, Memory-Eintrag
    EXTERNAL = 3    # nach außen: Mail senden, Termin anlegen, API-POST
    SENSITIVE = 4   # irreversibel: löschen, bezahlen, Konto ändern


@dataclass
class ToolResult:
    ok: bool
    data: Any = None
    error: str | None = None
    # Was der Nutzer sehen soll, wenn er das Tool-Ergebnis aufklappt:
    display: str = ""
    # Woher kommt das? Pflicht bei allem, was aus dem Netz kommt.
    sources: list[str] = field(default_factory=list)
    duration_ms: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "data": self.data,
            "error": self.error,
            "display": self.display,
            "sources": list(self.sources),
            "duration_ms": self.duration_ms,
        }


class Tool:
    name: str
    description: str          # was das Tool tut, in einem Satz, für das Modell
    parameters: dict          # JSON-Schema
    permission: Permission
    requires_confirmation: bool = False
    timeout_s: int = 30

    async def execute(self, **kwargs) -> ToolResult:
        raise NotImplementedError


class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    SKIPPED = "skipped"
    NEEDS_CONFIRMATION = "needs_confirmation"


@dataclass
class Step:
    id: str
    description: str
    agent: str | None = None
    status: StepStatus = StepStatus.PENDING
    result: ToolResult | None = None
    attempts: int = 0
    max_attempts: int = 2
    # ERGAENZT gegenueber docs/contracts.md: die Begruendung der Verifikation.
    # Ohne sie steht im UI zwar FAILED, aber nicht warum - und der naechste
    # Versuch bekommt nicht gesagt, was gefehlt hat. Rein additiv, mit
    # Default; nichts wurde umbenannt. In STATUS.md unter "Abweichungen".
    note: str = ""


@dataclass
class TaskBudget:
    max_steps: int = 12          # Gesamtschritte über alle Agents
    max_depth: int = 2           # Agent ruft Agent — nicht tiefer
    max_tool_calls: int = 20
    max_tokens: int = 60_000     # kumuliert über den ganzen Task
    max_seconds: int = 180
    max_cost_eur: float = 0.50   # Wert aus .env, Preise selbst eintragen

    @classmethod
    def from_settings(cls, settings: Any) -> "TaskBudget":
        """Die Werte aus `.env`. Kein Default wird hier stillschweigend erhöht."""
        return cls(
            max_steps=settings.budget_max_steps,
            max_depth=settings.budget_max_depth,
            max_tool_calls=settings.budget_max_tool_calls,
            max_tokens=settings.budget_max_tokens,
            max_seconds=settings.budget_max_seconds,
            max_cost_eur=settings.budget_max_cost_eur,
        )


@dataclass
class Task:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    goal: str = ""
    steps: list[Step] = field(default_factory=list)
    status: Literal[
        "pending", "running", "done", "failed", "aborted_budget", "cancelled"
    ] = "pending"
    budget: TaskBudget = field(default_factory=lambda: TaskBudget())
    spent_tokens: int = 0
    spent_cost_eur: float = 0.0
    created_at: float = field(default_factory=time.time)
    depth: int = 0
    # ERGAENZT gegenueber docs/contracts.md, beides rein additiv mit Default:
    #   result       - das Endergebnis. Ohne das Feld muesste der Runner es
    #                  neben dem Task herreichen.
    #   abort_reason - welche Grenze gerissen hat. 0.5 verlangt, dass die
    #                  Ueberschreitung benannt wird; ein Task, der nur
    #                  "aborted_budget" sagt, sagt zu wenig.
    result: str | None = None
    abort_reason: str | None = None

    # --- Budget ---------------------------------------------------------
    # 0.5: "Jede Grenze wird VOR jedem Schritt geprüft, nicht danach."

    spent_tool_calls: int = 0

    def elapsed_seconds(self, jetzt: float | None = None) -> float:
        return (jetzt if jetzt is not None else time.time()) - self.created_at

    def budget_verletzung(self, jetzt: float | None = None) -> str | None:
        """Benennt die *erste* verletzte Grenze, oder None.

        Der Rückgabewert ist die Begründung, die der Nutzer zu sehen bekommt.
        Eine Grenze, die man nicht benennen kann, ist keine Grenze.
        """
        b = self.budget
        # Gezaehlt wird, was wirklich gelaufen ist - nicht, was geplant wurde.
        # Sonst reisst die Grenze, bevor ein einziger Schritt lief, und es
        # gaebe nie ein Teilergebnis.
        gestartet = sum(1 for s in self.steps if s.attempts > 0)
        if gestartet >= b.max_steps:
            return f"max_steps erreicht ({gestartet}/{b.max_steps})"
        if self.depth > b.max_depth:
            return f"max_depth überschritten ({self.depth}/{b.max_depth})"
        if self.spent_tool_calls >= b.max_tool_calls:
            return (
                f"max_tool_calls erreicht "
                f"({self.spent_tool_calls}/{b.max_tool_calls})"
            )
        if self.spent_tokens >= b.max_tokens:
            return f"max_tokens erreicht ({self.spent_tokens}/{b.max_tokens})"
        verstrichen = self.elapsed_seconds(jetzt)
        if verstrichen >= b.max_seconds:
            return f"max_seconds erreicht ({verstrichen:.0f}/{b.max_seconds} s)"
        if self.spent_cost_eur >= b.max_cost_eur:
            return (
                f"max_cost_eur erreicht "
                f"({self.spent_cost_eur:.4f}/{b.max_cost_eur:.2f} EUR)"
            )
        return None


class Agent:
    name: str
    description: str
    system_prompt: str
    tools: list[str]              # Tool-Namen, nicht Instanzen
    max_permission: Permission    # Obergrenze, unabhängig von den Tools
    can_call_agents: list[str] = []

    async def run(self, task: Task, step: Step) -> ToolResult:
        raise NotImplementedError
