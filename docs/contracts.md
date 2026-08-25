# Verträge

Diese Typen sind der Kern von JARVIS. Sie werden **nicht umbenannt und nicht
umgebaut**. Wenn ein Vertrag nicht passt: erst melden, dann ändern — nie
danebenbauen.

Die Spalte *ab Phase* sagt, wann der Typ als Code existiert. Vorher ist er
nur hier beschrieben. Das ist Absicht: Der Vertrag steht fest, bevor der
erste Aufrufer existiert.

| Typ | ab Phase | Modul |
|---|---|---|
| `Tool`, `ToolResult` | 4 | `core/tools.py` |
| `Permission` | 4 | `core/permissions.py` |
| `Task`, `Step`, `TaskBudget` | 5 | `core/tasks.py` |
| `Agent` | 6 | `core/agents.py` |

---

## Tool

Eine Fähigkeit, die JARVIS ausführen kann. Ein Tool ist reiner Code — es
kennt kein Modell, keine Konversation und keinen Nutzer.

| Feld | Typ | Bedeutung |
|---|---|---|
| `name` | `str` | eindeutig, `^[a-z][a-z0-9_]{2,47}$`. Geht so an die Modell-API. |
| `description` | `str` | Was es tut und wann man es nimmt. Das Modell liest nur das. |
| `input_schema` | `dict` | JSON-Schema, `type: "object"`. Wird vor dem Aufruf validiert. |
| `permission` | `Permission` | Wie viel Freigabe der Aufruf braucht. |
| `run` | `Callable[[dict], ToolResult]` | Die Ausführung. Synchron. Wirft nicht — Fehler gehen als `ToolResult(ok=False)` zurück. |

Regeln:

- Ein Tool, das schreibt, löscht oder Geld ausgibt, ist niemals
  `Permission.ALLOW`.
- Ein Tool bekommt nur validierte Eingaben. Die Validierung passiert im
  Aufrufer, nicht im Tool.
- Kein Tool führt Zeichenketten aus, die aus dem Modell kommen. Kein `eval`,
  kein `exec`, kein `shell=True`.

## ToolResult

Was ein Tool zurückgibt. Immer dieses Objekt — nie ein nackter String, nie
eine Exception nach oben.

| Feld | Typ | Bedeutung |
|---|---|---|
| `ok` | `bool` | Hat es funktioniert. |
| `content` | `str` | Was das Modell zu sehen bekommt. Bei `ok=False` die Fehlerursache in Klartext. |
| `data` | `dict \| None` | Strukturiertes Ergebnis für die Oberfläche. Geht **nicht** ans Modell. |
| `duration_ms` | `int` | Gemessen, nicht geschätzt. |

`content` ist für das Modell da und wird deshalb kurz gehalten. Wenn ein Tool
20 000 Zeichen produziert, kürzt es selbst und sagt im `content`, dass es
gekürzt hat.

## Permission

Wie viel Freigabe ein Tool-Aufruf braucht.

| Wert | Bedeutung |
|---|---|
| `ALLOW` | Läuft ohne Rückfrage. Nur für lesende, folgenlose Tools. |
| `ASK` | Der Nutzer bestätigt jeden einzelnen Aufruf, mit sichtbaren Argumenten. |
| `DENY` | Abgeschaltet. Das Tool wird dem Modell gar nicht erst angeboten. |

Die Voreinstellung eines neuen Tools ist `ASK`. Eine Freigabe gilt für einen
Aufruf, nicht für eine Sitzung.

## Task

Ein mehrschrittiger Auftrag, der einen Anfang, ein Ende und ein Budget hat.
Eine Konversation ist **kein** Task.

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | `int` | |
| `goal` | `str` | Wortlaut des Auftrags. |
| `status` | `"pending" \| "running" \| "done" \| "failed" \| "cancelled"` | |
| `budget` | `TaskBudget` | |
| `steps` | `list[Step]` | in Ausführungsreihenfolge. |
| `result` | `str \| None` | Endergebnis, sobald `done`. |
| `created_at`, `finished_at` | `datetime \| None` | UTC. |

Ein Task ohne Budget existiert nicht.

## Step

Ein einzelner Schritt in einem Task. Wird persistiert, bevor er läuft — sonst
ist nach einem Absturz nicht nachvollziehbar, was passiert ist.

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | `int` | |
| `task_id` | `int` | |
| `index` | `int` | 0-basiert, lückenlos. |
| `kind` | `"think" \| "tool" \| "answer"` | |
| `tool_name` | `str \| None` | nur bei `kind="tool"`. |
| `input` | `dict \| None` | |
| `result` | `ToolResult \| None` | |
| `tokens_in`, `tokens_out` | `int` | gemessen. |

## TaskBudget

Die harte Grenze eines Tasks. Wird **nicht stillschweigend erhöht**, um etwas
grün zu bekommen.

| Feld | Typ | Bedeutung |
|---|---|---|
| `max_steps` | `int` | |
| `max_tokens` | `int` | Ein- und Ausgabe zusammen. |
| `max_seconds` | `int` | Wanduhr. |
| `max_cost_usd` | `float` | aus Tokens und Modellpreis gerechnet. |

Wird eine Grenze erreicht, endet der Task mit `status="failed"` und einer
Begründung, die die verletzte Grenze benennt. Er läuft nicht weiter und
fragt auch nicht nach mehr.

## Agent

Ein benanntes Bündel aus Systemprompt, Werkzeugen und Modell. JARVIS selbst
ist der erste Agent.

| Feld | Typ | Bedeutung |
|---|---|---|
| `name` | `str` | eindeutig. |
| `system_prompt` | `str` | |
| `tools` | `list[str]` | Namen aus der Tool-Registry. Ein Agent sieht nur diese. |
| `model` | `str` | Modell-ID des Providers. |
| `max_tokens` | `int` | |

Ein Agent, der einen anderen aufruft, gibt sein eigenes Budget anteilig ab.
Es entsteht kein neues.
