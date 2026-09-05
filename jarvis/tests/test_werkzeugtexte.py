"""Die Werkzeugbeschreibungen (FIX-10 Schritt B, nach EasyTool).

Diese Texte gehen bei JEDEM Modellaufruf mit, der Werkzeuge anbietet. Sie
sind - gemessen an der Haeufigkeit, mit der sie gesendet werden - der
teuerste Text im ganzen System, und sie entscheiden, ob das richtige
Werkzeug gegriffen wird.

Die Methode kommt aus EasyTool (arXiv 2401.06201, microsoft/JARVIS). Ihr
Kern ist nicht "kuerzer", sondern **einheitlich und abgegrenzt**: RestBench
nennt bei 28 von 54 Werkzeugen den Vorgaenger namentlich. Vorher taten das
von Noahs 18 Beschreibungen genau drei.

Was diese Tests NICHT pruefen: ob die Texte gut sind. Das kann nur die
Messstrecke (`scripts/plantest.py`), und dafuer braucht es ein echtes
Modell. Hier steht die Form.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from core.tools import registry

VORHER = Path(__file__).resolve().parent / "plandaten" / "werkzeugtexte-vorher.json"
NACHHER = Path(__file__).resolve().parent / "plandaten" / "werkzeugtexte-nachher.json"

# Jedes Paar muss auf BEIDEN Seiten aufeinander zeigen. Einseitig hilft
# nicht: das Modell liest die Beschreibung des Werkzeugs, das es gerade
# erwaegt - nicht die des richtigen.
PAARE = [
    ("wiki_lokal", "wiki_live"),
    ("wiki_lokal", "web_search"),
    ("wiki_live", "web_search"),
    ("recall", "web_search"),
    ("satellite_search", "satellite_passes"),
    ("datei_suchen", "datei_lesen"),
    ("kalender", "clock"),
    ("wikidata", "wiki_lokal"),
]


def _texte() -> dict[str, str]:
    return {t.name: t.description for t in registry.all_tools()}


def test_alle_achtzehn_haben_das_gleiche_format():
    """Vier Teile, immer in derselben Reihenfolge. Die Einheitlichkeit ist
    der Punkt - EasyTool nennt uneinheitliche Formate als Kernproblem."""
    fehlt = []
    for name, text in sorted(_texte().items()):
        zeilen = text.split("\n")
        if len(zeilen) < 4:
            fehlt.append(f"{name}: nur {len(zeilen)} Zeilen")
            continue
        if not zeilen[1].startswith("Nimm es fuer:"):
            fehlt.append(f"{name}: Zeile 2 ist kein 'Nimm es fuer:'")
        if not zeilen[2].startswith("Nimm es NICHT fuer:"):
            fehlt.append(f"{name}: Zeile 3 ist kein 'Nimm es NICHT fuer:'")
        if not zeilen[3].startswith("Beispiel:"):
            fehlt.append(f"{name}: Zeile 4 ist kein 'Beispiel:'")
    assert fehlt == [], "\n".join(fehlt)


def test_der_erste_satz_sagt_was_es_tut():
    """Kein Text faengt mit einer Bedingung an. Wer "Wenn du..." liest,
    muss erst den halben Satz lesen, um zu wissen, worum es geht."""
    schlecht = [n for n, t in _texte().items()
                if re.match(r"^\s*(Wenn|Falls|Nur|Bevor|Sobald)\b", t)]
    assert schlecht == [], schlecht


@pytest.mark.parametrize("a,b", PAARE)
def test_jedes_verwechslungspaar_zeigt_beidseitig(a, b):
    """Das Herzstueck. `wiki_lokal` muss `wiki_live` nennen UND umgekehrt -
    und zwar in der NICHT-fuer-Zeile, nicht irgendwo im Text."""
    texte = _texte()
    for x, y in ((a, b), (b, a)):
        zeilen = texte[x].split("\n")
        nicht = next((z for z in zeilen if z.startswith("Nimm es NICHT fuer:")), "")
        assert y in nicht, f"{x} nennt {y} nicht in seiner NICHT-fuer-Zeile: {nicht!r}"


def test_die_datenkanten_stehen_in_beide_richtungen():
    """Wo ein Werkzeug die Eingabe eines anderen liefert, sagen es beide:
    das konsumierende nennt den Vorgaenger, das produzierende sagt, was bei
    ihm anfaellt. So macht es RestBench, und genau diese Kanten misst
    `edge-F1`."""
    texte = _texte()
    kanten = [
        ("web_search", "fetch_url"),
        ("find_place", "satellite_search"),
        ("find_place", "satellite_passes"),
        ("datei_suchen", "datei_lesen"),
        ("clock", "kalender"),
    ]
    fehlt = []
    for produzent, konsument in kanten:
        if konsument not in texte[produzent]:
            fehlt.append(f"{produzent} sagt nicht, dass {konsument} das braucht")
        if produzent not in texte[konsument]:
            fehlt.append(f"{konsument} nennt {produzent} nicht als Vorgaenger")
    assert fehlt == [], "\n".join(fehlt)


def test_jedes_beispiel_benutzt_nur_echte_parameter():
    """Ein erfundener Parameter im Beispiel ist schlimmer als kein Beispiel:
    das Modell wuerde ihn benutzen, und der Aufruf schluege fehl."""
    schlecht = []
    for t in registry.all_tools():
        zeile = next((z for z in t.description.split("\n")
                      if z.startswith("Beispiel:")), "")
        echte = set((t.parameters or {}).get("properties", {}))
        # `name=` im Beispielaufruf einsammeln
        for arg in re.findall(r"(\w+)\s*=", zeile.split("Beispiel:")[-1]):
            if arg not in echte:
                schlecht.append(f"{t.name}: {arg!r} gibt es nicht "
                                f"(echte: {sorted(echte)})")
    assert schlecht == [], "\n".join(schlecht)


def test_keine_umlaute():
    """Der Rest des Projekts schreibt diese Strings ohne Umlaute. Ein
    gemischter Satz sieht nach Zufall aus."""
    schlecht = [n for n, t in _texte().items() if re.search("[äöüßÄÖÜ]", t)]
    assert schlecht == [], schlecht


def test_die_archivierten_staende_stimmen_mit_dem_code_ueberein():
    """`scripts/plantest.py --texte nachher` muss dasselbe messen, was der
    Code sendet - sonst vergleicht der Vorher/Nachher-Lauf zwei Dinge, von
    denen eines gar nicht in Betrieb ist."""
    nachher = json.loads(NACHHER.read_text(encoding="utf-8"))
    assert nachher == _texte()


def test_der_vorher_stand_ist_noch_da_und_ist_ein_anderer():
    """Ohne ihn laesst sich Schritt B nicht belegen, sondern nur behaupten."""
    vorher = json.loads(VORHER.read_text(encoding="utf-8"))
    # Der Vorher-Stand ist die Messung vom 30.08.2026 ueber die 18 Werkzeuge,
    # die es damals gab. Werkzeuge, die spaeter dazukamen (FIX-09: wetter,
    # erinnerung_anlegen), haben kein "vorher" - sie duerfen fehlen, aber
    # kein damals gemessenes Werkzeug darf verschwinden.
    assert set(vorher) <= set(_texte())
    assert {k: v for k, v in _texte().items() if k in vorher} != vorher
    # Der dokumentierte Ausgangswert.
    assert sum(len(v) for v in vorher.values()) == 4601


def test_der_preis_der_aenderung_steht_fest():
    """Die Kontextkosten sind messbar und werden nicht schoengeredet: der
    Text hat sich mehr als verdoppelt. Ob er es wert ist, entscheidet die
    Messstrecke - nicht dieser Test."""
    vorher = sum(len(v) for v in json.loads(VORHER.read_text(encoding="utf-8")).values())
    nachher = sum(len(v) for v in _texte().values())
    assert nachher > vorher, "die Texte sind kuerzer geworden - Zahlen im Bericht anpassen"
    # Ein Deckel, damit es nicht unbemerkt weiterwaechst.
    assert nachher < 12000, f"{nachher} Zeichen sind zu viel fuer jeden Aufruf"
