"""Jede registrierte Route braucht einen Nutzer.

Im Audit vom 25.08.2026 fiel auf, dass `/api/events` gebaut, getestet und
dokumentiert war — und von der Oberfläche nie geöffnet wurde. Das ist die Art
Fehler, die kein Test findet, weil jede Hälfte für sich funktioniert.

Dieser Test verlangt für jede Route eine von zwei Antworten:
  1. `index.html` ruft sie auf, oder
  2. sie steht in `NUR_API` — mit Begründung, warum das so gewollt ist.

Ein neuer Endpunkt, den niemand ruft, fällt damit sofort auf statt erst beim
nächsten Audit.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from api.app import create_app
from core.config import Settings

# Absichtlich nur über die API erreichbar. Wer hier etwas einträgt, sagt damit:
# "das soll die Oberfläche nicht aufrufen" - und traegt es in der README unter
# "nur API, kein UI" ein.
NUR_API = {
    "/api/audit": "Revisionsspur. Wird gelesen, wenn jemand nachsehen will, nicht laufend.",
    "/api/task-log": "Eine Zeile je Auftrag, fuer Auswertung von aussen.",
    "/api/chat": "Rest aus Phase 1. Der einzige Pfad, der Verlauf und "
                 "settings.system_prompt ans Modell gibt - siehe docs/FIX-01.md, "
                 "Befund zu Schritt 7. Die Oberflaeche benutzt ihn nicht.",
    "/openapi.json": "Von FastAPI erzeugt.",
    "/docs": "Von FastAPI erzeugt.",
    "/docs/oauth2-redirect": "Von FastAPI erzeugt.",
    "/redoc": "Von FastAPI erzeugt.",
}

WURZEL = Path(__file__).resolve().parent.parent


def routen() -> list[str]:
    """Alle Pfade, die die App wirklich bedient.

    Nicht ueber `app.routes` laufen: eingebundene Router stecken dort als
    `_IncludedRouter` ohne eigenen Pfad. Das OpenAPI-Schema ist die Liste,
    die auch ein Client sieht - und genau darum geht es hier.
    """
    app = create_app(Settings(_env_file=None, jarvis_token="t"))
    pfade = set(app.openapi().get("paths", {}))
    for r in app.routes:
        pfad = getattr(r, "path", None)
        if pfad:
            pfade.add(pfad)
    return sorted(pfade)


# Alle ausgelieferten Seiten, nicht nur die erste. Als Phase 11 dazukam,
# schlug dieser Test an - zu Recht: er kannte weltlage.html noch nicht.
SEITEN = ("index.html", "weltlage.html")


def seite() -> str:
    return "\n".join((WURZEL / name).read_text(encoding="utf-8")
                     for name in SEITEN if (WURZEL / name).exists())


def wird_gerufen(pfad: str, html: str) -> bool:
    if pfad == "/":
        return True                       # die Seite selbst
    # /api/tasks/{task_id}/cancel -> /api/tasks/ ... /cancel
    teile = [t for t in re.split(r"\{[^}]+\}", pfad) if t]
    return all(t in html for t in teile)


def test_es_gibt_ueberhaupt_routen():
    assert len(routen()) >= 10


@pytest.mark.parametrize("pfad", routen())
def test_jede_route_hat_einen_nutzer(pfad: str):
    html = seite()
    if pfad in NUR_API:
        return
    assert wird_gerufen(pfad, html), (
        f"{pfad} wird in index.html nirgends aufgerufen und steht nicht in NUR_API.\n"
        f"Entweder die Oberflaeche ruft sie auf, oder trag sie in NUR_API ein "
        f"(mit Begruendung) und in die README unter 'nur API, kein UI'."
    )


def test_nur_api_enthaelt_keine_leichen():
    """Was nicht mehr existiert, hat in der Ausnahmeliste nichts zu suchen."""
    vorhanden = set(routen())
    verwaist = sorted(set(NUR_API) - vorhanden)
    assert not verwaist, f"NUR_API nennt Routen, die es nicht mehr gibt: {verwaist}"


def test_die_regel_greift_ueberhaupt():
    """Gegenprobe: eine erfundene Route wuerde auffallen."""
    assert not wird_gerufen("/api/gibtesnicht", seite())


def test_alle_ausgelieferten_seiten_existieren():
    """Sonst waere der Test oben gruen, weil er nichts zu lesen fand."""
    for name in SEITEN:
        assert (WURZEL / name).exists(), f"{name} fehlt - der Routentest liefe ins Leere"


def test_readme_nennt_die_eigenen_api_routen():
    """Die Ausnahmen stehen auch dort, wo ein Mensch sie sucht."""
    readme = (WURZEL / "README.md").read_text(encoding="utf-8")
    assert "nur API, kein UI" in readme
    for pfad in ("/api/audit", "/api/task-log"):
        assert pfad in readme, f"{pfad} fehlt in der README-Tabelle"
