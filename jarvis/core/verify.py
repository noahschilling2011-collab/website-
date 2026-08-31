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
# Phase 6, DoD 2: "Jeder Preis hat eine Quelle mit Abrufdatum. Preise ohne
# Quelle -> Schritt gilt als fehlgeschlagen." Eine Zahl mit Waehrung ist genau
# die Sorte Behauptung, die man nicht ungeprueft weiterreicht.
PREIS = re.compile(
    r"(?:€|EUR\b|\bEuro\b)\s*\d|\d[\d.,]*\s*(?:€|EUR\b|\bEuro\b)",
    re.IGNORECASE,
)

# Verknuepfungspruefung 31.08.2026, Fund "erfundene URL erreicht den Nutzer".
#
# WAS WAR FALSCH: Die Quellenregel weiter unten hing an `step.agent ==
# "research"`. Der `weltlage`-Agent ist aber der einzige Agent OHNE
# Link-Filter (`links_pruefen=False` in `core/agents.py`) - bei ihm bleibt
# jede erfundene Adresse woertlich im Ergebnis stehen. Ausgerechnet er wurde
# von der Quellenregel nicht erfasst.
#
# WARUM IST DAS FALSCH: Der Planner bietet `weltlage` JEDEM Auftrag an
# (`core/runner.py` nimmt nur `jarvis` aus der Liste). Auf dem Weg
# /api/tasks laeuft dann weder der Parser aus `core/weltlage.py` noch die
# Nachpruefung aus `api/weltlage.py` - beide Stuetzen, mit denen die Ausnahme
# begruendet ist, fallen weg. Gemessen mit demselben Auftrag und derselben
# erfundenen Adresse: ueber `research` scheitert der Schritt, ueber
# `weltlage` stand die Adresse woertlich in der Endantwort, die der Nutzer
# als Beleg liest. Sie ueberlebt sogar den Schlussfilter, weil
# `core/runner.py` die Schritt-Displays an `belegte_urls()` gibt und die
# Adresse sich damit selbst belegt.
#
# Die Regel haengt deshalb jetzt an einem MERKMAL statt an einem Namen: ein
# Agent, dessen Links niemand gefiltert hat, traegt alles weiter, was das
# Modell erfunden hat - so einer braucht eine Quelle. Ein neuer Agent mit
# `links_pruefen=False` ist damit automatisch erfasst und nicht erst, wenn
# jemand daran denkt, hier einen Namen nachzutragen.
#
# Die eine Ausnahme, die bleibt: die Weltlage-SEITE. Nur dort holt
# `api/weltlage.py` die quell_url anschliessend wirklich, und nur dort ist
# die Ausnahme also gedeckt. Erkennbar am Ziel, das `api/weltlage.py` selbst
# baut ("Weltlage: ..." bzw. "Weltlage RUS: ..."). Bewusst am Anfang
# verankert: das Ziel steht im Auftrag ganz vorn, ein Modell kann sich die
# Ausnahme also nicht durch angehaengten Text erschleichen. Und wenn jemand
# die Formulierung dort aendert, faellt die Ausnahme WEG - die Weltlage-Seite
# scheitert dann laut, statt dass hier still eine Luecke aufgeht.
WELTLAGE_SEITE = re.compile(r"^Weltlage(?: [A-Z]{3})?: ")

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

    # Die Quellenregel fuer Agenten ohne Link-Filter - Begruendung oben bei
    # WELTLAGE_SEITE. `data` ist `Any`: nur ein Agent legt dort ein dict mit
    # diesen Schluesseln ab, jedes Werkzeugergebnis faellt auf den Default
    # zurueck und bleibt unberuehrt.
    daten = ergebnis.data if isinstance(ergebnis.data, dict) else {}
    if daten.get("links_gefiltert", True) is False and not ergebnis.sources:
        ziel = daten.get("ziel") or ""
        if not (isinstance(ziel, str) and WELTLAGE_SEITE.match(ziel)):
            return False, (
                "Die Links dieses Schritts hat niemand geprueft, und ein "
                "Werkzeug hat keine einzige Seite geholt. Jede Adresse im "
                "Ergebnis ist damit geraten - such die Seite und lies sie, "
                "statt aus dem Gedaechtnis zu antworten."
            )

    if PREIS.search(text) and not ergebnis.sources:
        return False, (
            "Im Ergebnis stehen Preise, aber keine Quelle. Ein Preis ohne "
            "Beleg ist wertlos - such die Seite, aus der die Zahl stammt, und "
            "nenn sie."
        )

    if AUFGEGEBEN.search(text):
        return False, (
            "Der Schritt endet damit, dass nichts gefunden wurde. Versuch eine "
            "andere Suchanfrage oder eine andere Quelle."
        )

    return True, "ok"
