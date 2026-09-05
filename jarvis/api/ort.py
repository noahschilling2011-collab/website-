"""Ein Ort auf dem Globus: hinfliegen, Bild holen, etwas dazu sagen.

Der Globus konnte bisher nur Länder, und nur die, deren Mittelpunkt als
Marke auf der Kugel sitzt. Hier wird daraus „schreib einen Ort":

    POST /api/ort  {"name": "Schwäbisch Gmünd"}

    1. Name -> Koordinate über Wikidata (`core/orte.py`), kein neuer Dienst
    2. Ausschnitt um den Punkt -> `satellite_search` -> Bild + Metadaten
    3. Ein Auftrag durch den normalen Runner -> zwei, drei Sätze dazu

**Warum Schritt 3 ein Auftrag ist und kein `provider.complete()`.**
Genau daran ist die Weltlage schon einmal gescheitert (`api/weltlage.py`,
FIX-02 Schritt 2): ein eigener Datenweg neben JARVIS geht am Runner vorbei
und damit an Budget, Audit **und** an `db.log_llm_call`. Daher kam die
Kachel „heute 0,0000 EUR" - die Aufrufe fanden statt, protokolliert hat sie
niemand. Der Fehler wird hier nicht wiederholt.

Schritt 2 läuft über `run_tool` und damit über den Dispatcher: auch ein
Werkzeugaufruf ohne Modell gehört ins Audit.

**Was das Modell hier NICHT tut: das Bild anschauen.** Es bekommt die
Metadaten - Aufnahmedatum, Wolkenanteil, Bodenauflösung - und den Ort. Wer
bei 23 m je Pixel „ein rotes Auto" sagt, halluziniert; das steht im
Systemprompt des Satelliten-Agenten und gilt hier genauso.
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from api.security import require_token
from api.tasks import LaufenderTask, baue_laufzeit
from core import db
from core.contracts import Permission, Task, TaskBudget
from core.orte import Ort, OrtFehler, aus_tabelle, bbox_um, finde_ort
from core.tools.dispatch import run_tool

log = logging.getLogger("jarvis")

ort_router = APIRouter(
    prefix="/api/ort", tags=["ort"], dependencies=[Depends(require_token)]
)

# 12 km Kante ergeben auf 512 Bildpixeln rund 23 m je Pixel - nahe an der
# Sentinel-2-Sensorgrenze. Mehr Ausschnitt heisst gruendlich weniger zu
# sehen, nicht mehr.
KANTE_KM = 12.0


class OrtAnfrage(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    kante_km: float = Field(default=KANTE_KM, gt=0.5, le=400.0)


def _bild_aus(ergebnis) -> dict | None:
    daten = ergebnis.data or {}
    pfad = daten.get("preview_url")
    if not pfad:
        return None
    return {
        "url": pfad,
        "aufloesung_m": daten.get("bild_aufloesung_m"),
        "kante_px": daten.get("bild_kante_px"),
        "attribution": daten.get("attribution", ""),
    }


def _szene_aus(ergebnis) -> dict | None:
    szenen = (ergebnis.data or {}).get("scenes") or []
    if not szenen:
        return None
    s = szenen[0]
    return {
        "aufgenommen": s.get("acquired_at"),
        "sensor": s.get("sensor"),
        "wolken_pct": s.get("cloud_cover_pct"),
    }


@ort_router.post("")
async def post_ort(request: Request, anfrage: OrtAnfrage) -> dict:
    """Ort suchen, Bild holen, etwas dazu sagen."""
    from core.runner import fuehre_task_aus

    settings = request.app.state.settings

    # --- 1. Name -> Koordinate ------------------------------------------
    try:
        ort: Ort | None = await finde_ort(anfrage.name, kontakt=settings.wiki_kontakt)
    except OrtFehler as exc:
        # Ohne WIKI_KONTAKT wirft die Live-Abfrage. Die eingebaute Tabelle
        # (jedes Land, jede Hauptstadt) geht trotzdem - erst wenn auch die
        # nichts hat, ist es ein Fehler.
        ort = aus_tabelle(anfrage.name)
        if ort is None:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
    if ort is None:
        raise HTTPException(
            status_code=404,
            detail=f"Kein Ort namens {anfrage.name!r} gefunden. "
                   "Wikidata kennt ihn nicht - vielleicht anders geschrieben?",
        )

    box = bbox_um(ort.lat, ort.lon, kante_km=anfrage.kante_km)

    # --- 2. Bild ---------------------------------------------------------
    # Ueber den Dispatcher, nicht am Werkzeug vorbei: auch ein Aufruf ohne
    # Modell gehoert ins Audit.
    bild = szene = None
    bild_hinweis = ""
    ergebnis = await run_tool(
        "satellite_search",
        {"bbox": list(box), "days_back": 30, "max_cloud_pct": 20.0},
        max_permission=Permission.READ,
        erlaubt=["satellite_search"],
    )
    if ergebnis.ok:
        bild = _bild_aus(ergebnis)
        szene = _szene_aus(ergebnis)
        if bild is None:
            bild_hinweis = "Zu diesem Ausschnitt kam kein Bild zurueck."
    else:
        bild_hinweis = ergebnis.display or ergebnis.error or "Kein Bild."

    # --- 3. Zwei, drei Saetze -------------------------------------------
    fakten = [f"Ort: {ort.name} ({ort.lat:.4f}, {ort.lon:.4f})"]
    if ort.einwohner:
        fakten.append(f"Einwohner laut Wikidata: {ort.einwohner}")
    if szene:
        fakten.append(
            f"Satellitenaufnahme vom {szene['aufgenommen']}, "
            f"{szene['sensor']}, {szene['wolken_pct']} % Wolken"
        )
    if bild:
        fakten.append(
            f"Bodenaufloesung des Bildes: {bild['aufloesung_m']} m je Pixel"
        )
    if bild_hinweis:
        fakten.append(f"Kein Bild verfuegbar: {bild_hinweis}")

    ziel = (
        "Sag in hoechstens drei Saetzen etwas ueber diesen Ort. "
        "Du siehst das Bild NICHT - beschreibe also nichts darauf, sondern "
        "sag, was der Ort ist und was bei dieser Bodenaufloesung ueberhaupt "
        "erkennbar waere. Keine Quellen erfinden.\n\n" + "\n".join(fakten)
    )

    # Genau wie die Weltlage: als LaufenderTask registriert, damit der
    # Auftrag waehrend seiner Laufzeit sichtbar und abbrechbar ist.
    task = Task(goal=ziel, budget=TaskBudget.from_settings(settings))
    eintrag = LaufenderTask(task=task)
    request.app.state.tasks.add(eintrag)
    text = ""
    try:
        await fuehre_task_aus(
            request.app.state.provider,
            ziel,
            budget=task.budget,
            kosten=settings.cost_eur,
            max_permission=Permission(settings.max_permission),
            task=task,
            laufzeit=baue_laufzeit(request.app, eintrag),
        )
        text = task.result or ""
    except Exception as exc:                      # noqa: BLE001
        # Der Ort und das Bild sind trotzdem etwas wert. Ohne Text, aber
        # mit Hinweis - nicht der ganze Aufruf faellt.
        log.warning("Ort %s: Text nicht erzeugt - %s", ort.name, exc)
        bild_hinweis = (bild_hinweis + " " if bild_hinweis else "") + (
            f"Kein Text erzeugt: {type(exc).__name__}"
        )
    finally:
        await asyncio.to_thread(db.save_task, settings.db_path, task)
        request.app.state.tasks.remove(task.id)

    return {
        "ort": ort.als_dict(),
        "bbox": list(box),
        "bild": bild,
        "szene": szene,
        "text": text,
        "hinweis": bild_hinweis,
    }
