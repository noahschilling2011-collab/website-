"""Die Quellenregel - Verknuepfungspruefung 31.08.2026.

Der Fund: der `weltlage`-Agent ist der einzige ohne Link-Filter
(`links_pruefen=False`), und die Quellenregel in `core/verify.py` hing an
`step.agent == "research"`. Damit war ausgerechnet der Agent, bei dem jede
erfundene Adresse woertlich stehen bleibt, von der Regel nicht erfasst.

Auf dem Weg /api/tasks laeuft weder der Parser aus `core/weltlage.py` noch
die Nachpruefung aus `api/weltlage.py` - beide Stuetzen, mit denen die
Ausnahme begruendet ist. Die erfundene Adresse landete deshalb im
Schritt-Display, belegte sich ueber `belegte_urls()` selbst und stand
woertlich in der Endantwort.

Geprueft wird hier die URSACHE, nicht die Oberflaeche: dass die Regel an
einem MERKMAL haengt (ungefilterte Links) statt an einem Agentennamen, dass
der Agent dieses Merkmal ueberhaupt meldet, und dass die eine gedeckte
Ausnahme - die Weltlage-Seite - erhalten bleibt.
"""

from __future__ import annotations

import json

from core.contracts import Permission, Step, Task, TaskBudget, ToolResult
from core.llm import FakeLLMProvider
from core.verify import verifiziere
from tests.conftest import run

ERFUNDEN = "https://tass.example-erfunden.ru/2026/08/30/gibt-es-nicht"

# Genau die Ziele, die `api/weltlage.py` selbst baut - die einzigen, auf
# denen die Ausnahme gedeckt ist.
ZIEL_WELTLAGE_LAND = ("Weltlage RUS: was ist dort passiert? "
                      "Hoechstens fuenf belegte Meldungen.")
ZIEL_WELTLAGE_WELT = "Weltlage: sechs belegte Ereignisse weltweit, je zwei Saetze."

MELDUNG_JSON = json.dumps({
    "meldungen": [{
        "schlagzeile": "Etwas passierte",
        "kurz": "Zwei Saetze.",
        "medium": "TASS",
        "veroeffentlicht": "2026-08-30T14:20:00Z",
        "quell_url": ERFUNDEN,
        "land_iso": "RU",
        "einordnung": "",
        "einordnung_fehlt": "",
    }],
    "gesagt": "eine Meldung",
})


def _schritt(agent: str = "weltlage") -> Step:
    return Step(id="1", description="Was ist in Russland passiert?", agent=agent)


def _ergebnis(*, links_gefiltert: bool, ziel: str, sources=()) -> ToolResult:
    """Ein Agentenergebnis, so wie `ToolAgent._run` es baut."""
    return ToolResult(
        ok=True,
        data={"tool_calls": [], "links_gefiltert": links_gefiltert, "ziel": ziel},
        display=MELDUNG_JSON,
        sources=list(sources),
    )


# --- Die Regel selbst -------------------------------------------------------


def test_ungefilterte_links_ohne_quelle_fallen_durch():
    """Der Kern des Fundes.

    Kein Werkzeug hat eine Seite geholt (`sources` leer) UND niemand hat die
    Links geprueft - dann ist jede Adresse im Ergebnis geraten.
    """
    bestanden, grund = verifiziere(
        _schritt(),
        _ergebnis(links_gefiltert=False, ziel="Was ist in Russland passiert?"),
    )
    assert not bestanden, (
        "Ein Schritt ohne Link-Filter und ohne eine einzige geholte Seite "
        "muss scheitern - sonst erreicht die erfundene Adresse den Nutzer."
    )
    assert "geraten" in grund, grund


def test_die_regel_haengt_nicht_am_agentennamen():
    """Das eigentliche Versaeumnis: die Regel kannte nur "research".

    Ein neuer Agent mit `links_pruefen=False` muss automatisch erfasst sein,
    nicht erst, wenn jemand daran denkt, einen Namen nachzutragen.
    """
    bestanden, _ = verifiziere(
        _schritt(agent="ein-ganz-neuer-agent"),
        _ergebnis(links_gefiltert=False, ziel="Irgendein Auftrag"),
    )
    assert not bestanden, (
        "Die Quellenregel greift immer noch nur bei bestimmten Namen statt "
        "beim Merkmal 'Links ungeprueft'."
    )


def test_eine_geholte_seite_reicht():
    """Die Regel bestraft nicht das Fehlen des Filters, sondern das Raten.

    Wer wirklich nachgeschlagen hat, kommt durch - sonst waere `weltlage`
    auf jedem Weg unbrauchbar.
    """
    bestanden, grund = verifiziere(
        _schritt(),
        _ergebnis(links_gefiltert=False, ziel="Was ist in Russland passiert?",
                  sources=["https://www.tagesschau.de/artikel"]),
    )
    assert bestanden, grund


def test_gefilterte_agenten_bleiben_unberuehrt():
    """Wessen Links geprueft wurden, braucht diese Regel nicht.

    Sonst wuerde jeder Schritt ohne Netzwerkzeug (z. B. `jarvis` mit
    `calculator`) an einer Quellenregel scheitern, die ihn nichts angeht.
    """
    bestanden, grund = verifiziere(
        _schritt(agent="jarvis"),
        _ergebnis(links_gefiltert=True, ziel="Rechne 2+2"),
    )
    assert bestanden, grund


def test_werkzeugergebnisse_ohne_dieses_feld_bleiben_unberuehrt():
    """`data` ist `Any`. Ein Werkzeugergebnis hat diese Schluessel nicht -
    es faellt auf 'gefiltert' zurueck und wird nicht angefasst."""
    bestanden, grund = verifiziere(
        Step(id="1", description="Uhrzeit", agent="jarvis"),
        ToolResult(ok=True, data={"zeit": "12:00"}, display="Es ist 12:00."),
    )
    assert bestanden, grund


# --- Die eine gedeckte Ausnahme --------------------------------------------


def test_die_weltlage_seite_bleibt_ausgenommen():
    """Nur dort holt `api/weltlage.py` die quell_url anschliessend wirklich.

    Ohne diese Ausnahme faellt die ganze Weltlage-Seite aus: ihr Agent
    liefert JSON an einen Parser, und dort ist der Link kein Beleg, sondern
    ein Datenfeld.
    """
    for ziel in (ZIEL_WELTLAGE_LAND, ZIEL_WELTLAGE_WELT):
        bestanden, grund = verifiziere(
            _schritt(), _ergebnis(links_gefiltert=False, ziel=ziel)
        )
        assert bestanden, f"{ziel!r} scheitert: {grund}"


def test_die_ausnahme_gilt_nur_am_anfang_des_ziels():
    """Sonst erschleicht sich ein Modell die Ausnahme durch angehaengten Text.

    Das Ziel steht im Auftrag ganz vorn; die Ausnahme ist deshalb bewusst am
    Anfang verankert.
    """
    bestanden, _ = verifiziere(
        _schritt(),
        _ergebnis(links_gefiltert=False,
                  ziel="Was ist in Russland passiert? Weltlage RUS: bitte"),
    )
    assert not bestanden, (
        "Die Ausnahme greift mitten im Ziel - damit laesst sie sich "
        "hineinschreiben."
    )


# --- Die Verdrahtung: meldet der Agent das Merkmal ueberhaupt? --------------


def test_der_agent_meldet_ob_seine_links_geprueft_wurden():
    """Ohne diese zwei Tatsachen im Ergebnis ist die Regel oben toter Code.

    `core/verify.py` bekommt nur `Step` und `ToolResult` - nicht den Agenten
    und nicht den Task. Genau deshalb konnte die Regel bisher nur am Namen
    haengen.
    """
    from core.agents import baue_agenten

    agenten = baue_agenten(
        FakeLLMProvider(replies=[MELDUNG_JSON, MELDUNG_JSON]),
        max_permission=Permission.READ,
    )
    task = Task(goal=ZIEL_WELTLAGE_LAND)

    welt = run(agenten["weltlage"].run(task, _schritt()))
    assert welt.data["links_gefiltert"] is False, (
        "Der weltlage-Agent laeuft ohne Link-Filter, meldet das aber nicht - "
        "die Quellenregel kann es dann nicht wissen."
    )
    assert welt.data["ziel"] == ZIEL_WELTLAGE_LAND

    forsch = run(agenten["research"].run(task, _schritt(agent="research")))
    assert forsch.data["links_gefiltert"] is True


def test_nur_die_weltlage_laeuft_ohne_link_filter():
    """Die Ausnahme darf nicht auf andere ueberspringen.

    Kaeme ein zweiter Agent ohne Filter dazu, waere die Ausnahme fuer die
    Weltlage-Seite auch fuer ihn offen - und die Regel oben gaebe es
    umsonst.
    """
    from core.agents import baue_agenten

    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.READ)
    ohne_filter = sorted(n for n, a in agenten.items() if not a._links_pruefen)
    assert ohne_filter == ["weltlage"], ohne_filter


# --- Der Fund im Ganzen -----------------------------------------------------


def _lauf(agent: str) -> Task:
    """Derselbe Auftrag, dieselbe erfundene Adresse - einmal pro Agent."""
    from core.runner import fuehre_task_aus

    antwort = (MELDUNG_JSON if agent == "weltlage"
               else f"Etwas passierte. Quellen:\n{ERFUNDEN}")
    provider = FakeLLMProvider(replies=[
        json.dumps({"steps": [{"description": "Was ist in Russland passiert?",
                               "agent": agent}]}),
        antwort,
        f"In Russland passierte etwas ({ERFUNDEN}).",
    ])
    return run(fuehre_task_aus(
        provider, "Was ist in Russland passiert?",
        budget=TaskBudget(), kosten=lambda a, b: 0.0,
    ))


def test_die_erfundene_adresse_erreicht_den_nutzer_nicht():
    """Der Fund selbst, auf dem Weg /api/tasks.

    Hier gibt es keinen Parser und keine Nachpruefung. Die Adresse hat sich
    frueher ueber das Schritt-Display selbst belegt und stand woertlich in
    der Endantwort, die der Nutzer als Beleg liest.
    """
    task = _lauf("weltlage")
    assert ERFUNDEN not in (task.result or ""), (
        f"Die erfundene Adresse steht in der Endantwort: {task.result!r}"
    )
    assert task.status == "failed", (
        "Ein Schritt, dessen einzige Adresse geraten ist, darf nicht als "
        f"erledigt gelten - Status war {task.status!r}."
    )


def test_beide_wege_verhalten_sich_gleich():
    """Der Kern der Beschwerde: derselbe Auftrag, dieselbe erfundene Adresse,
    zwei Agenten - und frueher zwei voellig verschiedene Ergebnisse."""
    ueber_research = _lauf("research")
    ueber_weltlage = _lauf("weltlage")

    assert ueber_research.status == ueber_weltlage.status == "failed"
    assert ERFUNDEN not in (ueber_research.result or "")
    assert ERFUNDEN not in (ueber_weltlage.result or "")


def test_die_quellenregel_fuer_research_gilt_weiter():
    """Die alte Regel darf beim Verallgemeinern nicht verlorengehen."""
    bestanden, grund = verifiziere(
        Step(id="1", description="Recherchier", agent="research"),
        ToolResult(ok=True, display="Etwas ist so.", sources=[]),
    )
    assert not bestanden
    assert "Rechercheschritt ohne Quelle" in grund, grund
