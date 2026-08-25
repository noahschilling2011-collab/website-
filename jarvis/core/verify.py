"""Verifikation eines Schritts (Phase 4).

Der Phasenauftrag ist hier ungewoehnlich deutlich:

> Verifikation ist ein eigener, **billiger** Schritt, nicht dasselbe Modell,
> das sich selbst auf die Schulter klopft: pruefe konkrete Bedingungen
> (Datei existiert? Ergebnis hat das erwartete Feld? Quelle vorhanden?),
> nicht "sieht gut aus".

Deshalb steht hier Code und kein Modellaufruf. Das ist nicht nur billiger,
es ist auch das einzige Verfahren, das nicht mit dem Ding befangen ist, das
es pruefen soll.
"""

from __future__ import annotations

import re

from core.contracts import Step, ToolResult

# Formulierungen, mit denen ein Modell sein Nichtwissen einraeumt. Ein Schritt,
# der damit endet, hat sein Ziel nicht erreicht - auch wenn technisch alles
# geklappt hat.
AUFGEGEBEN = re.compile(
    r"\b(konnte nichts|nichts gefunden|keine (?:quelle|informationen|angaben|daten)"
    r"|nicht heraus(?:finden|gefunden)|kann ich nicht beantworten"
    r"|liegen mir nicht vor)\b",
    re.IGNORECASE,
)


def verifiziere(step: Step, ergebnis: ToolResult | None) -> tuple[bool, str]:
    """Gibt (bestanden, Begruendung) zurueck.

    Die Begruendung geht bei einem Fehlschlag in den Retry-Prompt und ins UI -
    sie muss also benennen, was fehlt, nicht nur dass etwas fehlt.
    """
    if ergebnis is None:
        return False, "Kein Ergebnis."

    if not ergebnis.ok:
        return False, ergebnis.error or "Das Werkzeug hat einen Fehler gemeldet."

    text = (ergebnis.display or "").strip()
    # Nur wirklich leer zaehlt. Eine Mindestlaenge waere geraten: "42" ist ein
    # vollstaendiges Schrittergebnis.
    if not text:
        return False, "Das Ergebnis ist leer."

    # Der Phasenauftrag: "eine Behauptung ohne Quelle gilt als
    # fehlgeschlagener Schritt."
    if step.agent == "research" and not ergebnis.sources:
        return False, (
            "Rechercheschritt ohne Quelle. Jede Tatsachenbehauptung braucht "
            "eine URL - such und lies die Seite, statt aus dem Gedaechtnis zu "
            "antworten."
        )

    if AUFGEGEBEN.search(text):
        return False, (
            "Der Schritt endet damit, dass nichts gefunden wurde. Versuch eine "
            "andere Suchanfrage oder eine andere Quelle."
        )

    return True, "ok"
