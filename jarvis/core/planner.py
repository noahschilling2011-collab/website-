"""Planner (Phase 4).

Zerlegt ein Ziel in `Step`s. Die wichtigste Regel steht im Phasenauftrag und
ist im Prompt die erste Zeile:

> **Wenn ein Ziel in einem Schritt loesbar ist, erzeugt der Planner genau
> einen Schritt.**

`docs/decisions.md` erklaert warum: ein Beispielplan mit zehn Schritten
bringt Modelle dazu, jede Frage in zehn Schritte zu zerlegen. "Wie spaet ist
es?" wird dann zu einem Rechercheprojekt.

**JSON-Robustheit (0.6):** die Antwort wird gegen ein Pydantic-Schema
geparst. Bei einem Parse-Fehler gibt es hoechstens **zwei**
Reparaturversuche - Fehlermeldung und Original zurueck ans Modell -, danach
ein harter Fehler mit sichtbarem Log. Es wird nie stillschweigend ein Default
eingesetzt.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Callable

from pydantic import BaseModel, Field, ValidationError

from core.contracts import Step
from core.llm import LLMMessage, LLMProvider

log = logging.getLogger("jarvis")

MAX_REPARATUREN = 2

# Woran ein Anbieter erkennt, dass gerade ein Plan verlangt wird - ohne den
# Prompt zu zerlegen. Der FakeLLMProvider haengt daran; deshalb steht der
# Marker hier und wird nicht dort noch einmal getippt.
# Der Marker ist namensfrei: der Name des Assistenten (ASSISTENT_NAME,
# core/agents.mit_name) folgt erst danach. So gilt fuer jeden Namen
# `system.startswith(PLANNER_MARKER)` - die Tests haengen daran.
PLANNER_MARKER = "Du bist der Planner"

# Der Umschlag, in dem das Ziel zum Modell geht. Auch das teilen sich
# Planner und Fake, statt es zweimal zu kennen.
ZIEL_PRAEFIX = "Ziel: "

SYSTEM = PLANNER_MARKER + """ von {name}. Du zerlegst ein Ziel in Schritte.

DIE WICHTIGSTE REGEL: Wenn das Ziel mit einem einzigen Schritt zu erledigen
ist, gibst du GENAU EINEN Schritt zurueck. Die meisten Ziele sind das.
"Wie spaet ist es?" ist ein Schritt. "Was ist 17 % von 4380?" ist ein Schritt.
Zerlege nichts, nur damit es nach Arbeit aussieht.

Mehrere Schritte nur, wenn ein spaeterer Schritt wirklich das Ergebnis eines
frueheren braucht.

Verfuegbare Agenten:
<<AGENTEN>>

Ein Schritt bekommt einen Agenten, wenn er dessen Faehigkeiten braucht.
Sonst bleibt "agent" leer - dann erledigt {name} den Schritt selbst mit
seinen Werkzeugen.

Antworte AUSSCHLIESSLICH mit JSON in genau dieser Form, ohne Text davor oder
danach, ohne Markdown-Codeblock:

{"steps": [{"description": "was zu tun ist", "agent": null}]}

Hoechstens <<MAX_STEPS>> Schritte."""


class PlanStep(BaseModel):
    description: str = Field(min_length=1, max_length=500)
    agent: str | None = None


class Plan(BaseModel):
    steps: list[PlanStep] = Field(min_length=1)


class PlanungFehlgeschlagen(RuntimeError):
    pass


def _json_aus_text(text: str) -> str:
    """Holt das JSON-Objekt aus der Antwort.

    Modelle packen JSON gern in einen Markdown-Block oder schreiben einen Satz
    davor. Das ist kein Grund, den Versuch wegzuwerfen - aber es wird
    ausdruecklich gesucht und nicht geraten.
    """
    text = text.strip()
    block = re.search(r"```(?:json)?\s*(.+?)```", text, re.DOTALL)
    if block:
        text = block.group(1).strip()
    start, ende = text.find("{"), text.rfind("}")
    return text[start : ende + 1] if start != -1 and ende > start else text


async def erstelle_plan(
    provider: LLMProvider,
    ziel: str,
    *,
    agenten: dict[str, str] | None = None,
    max_steps: int = 12,
    pruefpunkt: Callable[[], None] | None = None,
) -> list[Step]:
    """Fragt das Modell nach einem Plan und gibt ihn als `Step`s zurueck.

    `pruefpunkt` ist die Funktion aus `core/abbruch.py`; sie wirft
    `LaufBeendet`, wenn der Nutzer abgebrochen hat oder eine Verbrauchsgrenze
    gerissen ist. Ohne sie ist der Parameter None und nichts aendert sich -
    die Planner-Tests rufen `erstelle_plan` direkt.
    """
    beschreibung = (
        "\n".join(f"- {name}: {zweck}" for name, zweck in (agenten or {}).items())
        or "- (keine)"
    )
    # Kein %-Formatieren und kein .format(): der Prompt enthaelt sowohl
    # Prozentzeichen ("17 % von 4380") als auch geschweifte Klammern (das
    # JSON-Beispiel). Beides wuerde dort zur Formatanweisung.
    from core.agents import mit_name

    system = mit_name(SYSTEM).replace("<<AGENTEN>>", beschreibung).replace(
        "<<MAX_STEPS>>", str(max_steps)
    )
    verlauf: list[LLMMessage] = [LLMMessage("user", ZIEL_PRAEFIX + ziel)]

    letzter_fehler = ""
    for versuch in range(MAX_REPARATUREN + 1):
        # Verknuepfungspruefung 31.08.2026, Fund 3 - hier fehlte etwas:
        # WAS war falsch: zwischen den bis zu MAX_REPARATUREN + 1 = 3
        #   Planungszuegen stand kein einziger Pruefpunkt. Der Runner prueft
        #   einmal VOR der Planung, danach lief diese Schleife blind durch.
        # WARUM ist das falsch: jeder dieser Zuege ist ein bezahlter
        #   Modellaufruf. Wer waehrend des ersten Planungszuges auf Abbrechen
        #   drueckt, bezahlte gemessen noch zwei weitere - der Abbruch-Wunsch
        #   wurde erst nach der Planung wieder angesehen. Dieselbe Regel wie
        #   in core/tools/loop.py: vor jedem bezahlten Zug wird geprueft, und
        #   der Pruefpunkt wirft, statt etwas zurueckzugeben, das jemand
        #   vergessen kann auszuwerten.
        # WIE repariert: den Pruefpunkt des Runners durchreichen und am Kopf
        #   der Schleife rufen. Der Zug, der gerade laeuft, laeuft zu Ende;
        #   der naechste faellt aus. Der Runner faengt `LaufBeendet` an der
        #   Aufrufstelle und beendet den Task ordentlich.
        if pruefpunkt is not None:
            pruefpunkt()

        reply = await provider.complete(verlauf, system=system)
        roh = _json_aus_text(reply.text)

        try:
            plan = Plan.model_validate_json(roh)
        except (ValidationError, ValueError) as exc:
            letzter_fehler = str(exc)[:400]
            log.warning(
                "Planner: Antwort nicht verwertbar (Versuch %d/%d) - %s",
                versuch + 1, MAX_REPARATUREN + 1, letzter_fehler,
            )
            if versuch == MAX_REPARATUREN:
                break
            # Fehlermeldung UND Original zurueck ans Modell (0.6).
            verlauf.append(LLMMessage("assistant", reply.text))
            verlauf.append(LLMMessage(
                "user",
                f"Das war kein gueltiges JSON fuer das verlangte Schema.\n"
                f"Fehler: {letzter_fehler}\n"
                f"Antworte nur mit dem JSON-Objekt, nichts sonst.",
            ))
            continue

        if len(plan.steps) > max_steps:
            log.warning("Planner: %d Schritte, gekuerzt auf %d",
                        len(plan.steps), max_steps)
            plan.steps = plan.steps[:max_steps]

        return [
            Step(
                id=uuid.uuid4().hex[:12],
                description=s.description.strip(),
                agent=(s.agent or None) or None,
            )
            for s in plan.steps
        ]

    # Kein stillschweigender Default - das waere die Stelle, an der aus einem
    # kaputten Plan ein falsches Ergebnis wird.
    raise PlanungFehlgeschlagen(
        f"Der Planner hat nach {MAX_REPARATUREN + 1} Versuchen kein gueltiges "
        f"JSON geliefert. Letzter Fehler: {letzter_fehler}"
    )


