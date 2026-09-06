"""Jeder Agent weiss, welcher Tag heute ist.

Anlass, gemessen am 26.08.2026 im ersten Lauf mit einem echten Modell. Der
Werkzeug-Tab zeigte:

    18:58:45  web_search  count=10, query="Deutschland aktuelle Meldungen
                                          26. August 2024"          ✗

Zwei Jahre daneben, und zwar nicht aus Nachlaessigkeit: `research` und
`weltlage` haben kein `clock`, und in keinem Prompt stand ein Datum. Ein
Modell, das nach "aktuell" gefragt wird und den Tag nicht kennt, nimmt das
Jahr seines Trainingsstands. Jede Suche nach Nachrichten ging damit ins
falsche Jahr - ohne dass es jemandem auffiel, weil die Suche mangels
SEARCH_API_KEY ohnehin fehlschlug.
"""

from __future__ import annotations

import time

from core.agents import baue_agenten, heute_zeile
from core.contracts import Permission
from core.llm import FakeLLMProvider


def _agenten():
    return baue_agenten(FakeLLMProvider(), max_permission=Permission.SENSITIVE)


def test_jeder_agent_kennt_das_heutige_datum():
    heute = time.strftime("%Y-%m-%d", time.gmtime())
    ohne = [n for n, a in _agenten().items() if heute not in a.system_prompt]
    assert ohne == [], f"Diese Agenten wissen nicht, welcher Tag ist: {ohne}"


def test_auch_die_weltlage_bekommt_es():
    """Sie laeuft bewusst ohne Sprachstil, weil ihre Antwort JSON ist - das
    Datum darf dabei nicht mit verloren gehen. Gerade eine Nachrichtenlage
    ohne heutiges Datum ist wertlos."""
    welt = _agenten()["weltlage"]
    assert time.strftime("%Y-%m-%d", time.gmtime()) in welt.system_prompt
    # Der eigentliche Prompt steht weiterhin drin, nicht ersetzt.
    assert "JSON" in welt.system_prompt or "Meldung" in welt.system_prompt


def test_die_zeile_nennt_das_jahr_und_warnt_vor_dem_training():
    zeile = heute_zeile()
    assert time.strftime("%Y", time.gmtime()) in zeile
    # Ohne diesen Hinweis nimmt ein Modell gern trotzdem sein Trainingsjahr.
    assert "Training" in zeile


def test_das_datum_steht_vorne_nicht_hinten():
    """Am Ende eines langen Prompts geht ein Satz unter. Vorne nicht."""
    for name, agent in _agenten().items():
        anfang = agent.system_prompt[:120]
        assert "Heute ist" in anfang, f"{name}: Datum nicht am Anfang"


def test_der_antwortstil_ueberlebt_das_datum():
    """Im Sprachmodus haengt der Kuerzungsstil hinten dran. Das Datum davor
    darf ihn nicht verdraengen."""
    mit_stimme = baue_agenten(
        FakeLLMProvider(),
        max_permission=Permission.READ,
        antwortstil="\n\nSPRACHSTIL: hoechstens drei Saetze.",
    )
    hermes = mit_stimme["hermes"]
    assert "Heute ist" in hermes.system_prompt
    assert "SPRACHSTIL" in hermes.system_prompt
