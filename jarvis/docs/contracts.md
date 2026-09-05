# Verträge, Regeln, Budgets (Langfassung)

> Wörtlich aus `docs/MASTER-PROMPT-v2.md`, Block 0, Abschnitte 0.4 bis 0.7.
> Die Datei im ursprünglichen Setup-Zip war nach 67 Bytes abgeschnitten —
> das Split-Skript ist an einem Backtick abgebrochen. Hier steht der
> vollständige Text. **Diese Typen werden nicht umbenannt und nicht umgebaut.**

## 0.4 Sicherheit — nicht verhandelbar

1. **Der LLM-API-Key darf niemals im Frontend landen.** Kein `fetch` vom Browser direkt an einen Modellanbieter. Jeder Modellaufruf geht über das eigene Backend. Wenn du Frontend-Code schreibst, der einen Key enthält, hast du die Phase nicht bestanden.
2. `.env` steht in `.gitignore`. Es gibt eine `.env.example` ohne echte Werte.
3. Die API bindet standardmäßig an `127.0.0.1`, nicht `0.0.0.0`.
4. Jeder API-Request braucht einen Header `X-Jarvis-Token`, verglichen mit einem Wert aus `.env`. Auch lokal. Kostet fünf Zeilen und verhindert, dass ein beliebiges Skript im Browser deinen Assistenten fernsteuert.
5. Kein `eval`, kein `exec`, kein `shell=True` mit Nutzereingaben — nirgends, in keiner Phase.
6. Bestätigung ist Pflicht ab `EXTERNAL` (3) aufwärts, plus bei jeder **löschenden oder
   überschreibenden** lokalen Operation. Rein anhängende lokale Schreibvorgänge
   (`remember`) brauchen keine.

   > **Geändert am 25.08.2026.** Vorher stand hier: *Ein Tool, das schreibt, löscht,
   > sendet oder Geld ausgibt, ist `requires_confirmation = True`. Ohne Ausnahme.*
   > Das widersprach der Definition von `Permission.LOCAL` weiter unten, die
   > ausdrücklich *lokal schreiben: Notiz, Memory-Eintrag* nennt — also ein Schreiben
   > ohne Rückfrage. Nach der alten Regel hätte jedes `remember` eine Rückfrage
   > ausgelöst, was das Gedächtnis unbenutzbar macht. Die Spec war falsch, nicht der
   > Code: `remember` bleibt `LOCAL` mit `requires_confirmation = False`.

## 0.5 Budget & Kill-Switch — die Sektion, die in v1 komplett fehlte

Ein Agent, der Agents ruft, die Tools rufen, ist eine Maschine, die Geld und Zeit in unbestimmter Menge verbraucht. Deshalb bekommt **jeder Task** ein hartes Budget, das vor dem Start feststeht:

```python
@dataclass
class TaskBudget:
    max_steps: int = 12          # Gesamtschritte über alle Agents
    max_depth: int = 2           # Agent ruft Agent — nicht tiefer
    max_tool_calls: int = 20
    max_tokens: int = 60_000     # kumuliert über den ganzen Task
    max_seconds: int = 180
    max_cost_eur: float = 0.50   # Wert aus .env, Preise selbst eintragen
```

Regeln:
- Jede Grenze wird **vor** jedem Schritt geprüft, nicht danach.
- Bei Überschreitung: Task-Status `ABORTED_BUDGET`, Teilergebnis zurückgeben, Nutzer fragen, ob er das Budget erhöhen will. **Nicht** stillschweigend weiterlaufen.
- `max_depth = 2` heißt: Hermes → Research Agent → Tool. Ein Agent, der einen Agent ruft, der einen Agent ruft, ist ein Bug.
- Kosten werden pro LLM-Call aus Tokenanzahl × Preis aus `.env` berechnet und im Task mitgeführt.
- Es gibt `POST /api/tasks/{id}/cancel`. Ein laufender Task muss sich abbrechen lassen.

## 0.6 LLM-Robustheit — die zweite Sektion, die fehlte

Modelle geben regelmäßig kaputtes JSON zurück. Das ist kein Randfall, das ist der Normalfall bei hoher Last.

- Strukturierte Antworten werden gegen ein Pydantic-Schema geparst.
- Bei Parse-Fehler: **maximal zwei** Reparaturversuche (Fehlermeldung + Original zurück ans Modell), danach harter Fehler mit sichtbarem Log.
- Nie stillschweigend Defaults einsetzen, wenn das Parsing scheitert.
- Jeder LLM-Call wird geloggt: Zeitstempel, Modell, Prompt-Hash, Input-/Output-Tokens, Dauer, Kosten, Erfolg/Fehler.
- Timeout pro LLM-Call: 60 s. Timeout pro Tool: im Tool definiert, Default 30 s.

## 0.7 Verbindliche Verträge

Diese Datentypen ändert man nicht. Alle Phasen bauen darauf auf.
*(Nachfolgend als Spezifikation gemeint — beim Bauen ausführen und testen.)*

```python
# core/contracts.py
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal
import time, uuid


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


@dataclass
class Task:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    goal: str = ""
    steps: list[Step] = field(default_factory=list)
    status: Literal["pending","running","done","failed","aborted_budget","cancelled"] = "pending"
    budget: "TaskBudget" = field(default_factory=lambda: TaskBudget())
    spent_tokens: int = 0
    spent_cost_eur: float = 0.0
    created_at: float = field(default_factory=time.time)
    depth: int = 0


class Agent:
    name: str
    description: str
    system_prompt: str
    tools: list[str]              # Tool-Namen, nicht Instanzen
    max_permission: Permission    # Obergrenze, unabhängig von den Tools
    can_call_agents: list[str] = []

    async def run(self, task: Task, step: Step) -> ToolResult:
        raise NotImplementedError
```

**Wichtige Eigenschaft:** Ein Agent kann nie mehr Rechte haben als `max_permission`, selbst wenn ihm ein mächtigeres Tool zugewiesen wird. Die Prüfung passiert im Tool-Dispatcher, nicht im Agent.

