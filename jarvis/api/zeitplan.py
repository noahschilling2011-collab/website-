"""Zeitplaene ueber HTTP und die Schleife, die sie ausloest (FIX-08).

Die Regeln stehen in `core/zeitplan.py`. Hier steht nur, WANN sie greifen:

- Die Schleife laeuft alle ZEITPLAN_TAKT_S Sekunden (0 schaltet sie ab) und
  ruft `pruefe_einmal`. Die Funktion ist getrennt, damit ein Test sie mit
  einer festen Uhrzeit aufrufen kann, statt 60 Sekunden zu warten.
- Ein faelliger Plan wird GENAU EINMAL angefasst: verpasst, uebersprungen
  oder gestartet - und in jedem Fall bekommt er einen neuen Termin. Sonst
  bliebe er faellig und wuerde in der naechsten Runde wieder anstehen.
- Gestartet wird ueber `api.tasks.starte_task`, denselben Weg wie ein
  getippter Auftrag. Es gibt keinen zweiten Runner fuer Zeitplaene.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

from api.security import require_token
from api.tasks import starte_task
from core import zeitplan
from core.contracts import Task

log = logging.getLogger("jarvis")

zeitplan_router = APIRouter(prefix="/api/zeitplaene",
                            dependencies=[Depends(require_token)])


class ZeitplanAnlegen(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    ziel: str = Field(min_length=1, max_length=10_000)
    regel: str = Field(min_length=1, max_length=40)


class Schalten(BaseModel):
    aktiv: bool


# --- Entscheidung je Plan ---------------------------------------------------


def _anbieter_fehlt(app: FastAPI) -> bool:
    # Spaeter Import: api.app importiert dieses Modul.
    from api.app import UnavailableProvider

    return isinstance(app.state.provider, UnavailableProvider)


def _laeuft_noch(app: FastAPI, plan: dict[str, Any]) -> bool:
    """Der vorige Lauf dieses Plans ist noch nicht fertig."""
    letzter = plan.get("letzter_task_id")
    return bool(letzter) and app.state.tasks.get(letzter) is not None


def hindernis(app: FastAPI, plan: dict[str, Any],
              jetzt: datetime | None = None) -> str | None:
    """Warum dieser Plan JETZT nicht starten darf - oder None.

    Die Reihenfolge ist Absicht: erst das Billige (laeuft der vorige noch?),
    dann der Anbieter, dann der Deckel, der eine Datenbankabfrage kostet.
    """
    settings = app.state.settings
    if _laeuft_noch(app, plan):
        return "uebersprungen: der vorige Lauf dieses Zeitplans laeuft noch."
    if _anbieter_fehlt(app):
        return "uebersprungen: kein Anbieter eingerichtet (LLM_API_KEY fehlt)."
    grund = zeitplan.deckel_erreicht(
        zeitplan.verbrauch_24h(settings.db_path, jetzt),
        max_laeufe=settings.zeitplan_max_laeufe_24h,
        max_token=settings.zeitplan_max_token_24h,
    )
    return f"uebersprungen: {grund}" if grund else None


async def starte_plan(app: FastAPI, plan: dict[str, Any], *, ausloeser: str,
                      jetzt: datetime | None = None) -> Task:
    """Startet den Auftrag eines Plans - mit LOCAL als harter Obergrenze.

    Der Aufrufer hat `hindernis` schon gefragt. Hier wird nur noch gestartet
    und gebucht; `am_ende` traegt den Ausgang nach, wenn der Task fertig ist.
    """
    pfad = app.state.settings.db_path

    async def am_ende(task: Task) -> None:
        await asyncio.to_thread(zeitplan.nachtrag_ergebnis, pfad, task.id,
                                task.status)

    task = await starte_task(app, plan["ziel"],
                             max_permission=zeitplan.PERMISSION_DECKEL,
                             am_ende=am_ende)
    await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, task.id,
                            ausloeser=ausloeser, status="laeuft", jetzt=jetzt)
    log.info("zeitplan %s (%s): Auftrag %s gestartet (%s)",
             plan["id"], plan["name"], task.id, ausloeser)
    return task


async def pruefe_einmal(app: FastAPI,
                        jetzt: datetime | None = None) -> list[tuple[str, str]]:
    """Eine Runde der Schleife. Gibt (plan_id, was_passiert_ist) zurueck,
    damit ein Test nachsehen kann, ohne die Datenbank zu lesen."""
    pfad = app.state.settings.db_path
    jetzt = jetzt or datetime.now(timezone.utc)
    protokoll: list[tuple[str, str]] = []
    for plan in await asyncio.to_thread(zeitplan.faellige, pfad, jetzt):
        if zeitplan.ist_verpasst(plan, jetzt):
            await asyncio.to_thread(zeitplan.verbuche_verpasst, pfad, plan, jetzt)
            log.warning("zeitplan %s (%s): Termin %s verpasst, nicht nachgeholt",
                        plan["id"], plan["name"], plan["naechster_lauf"])
            protokoll.append((plan["id"], "verpasst"))
            continue
        grund = hindernis(app, plan, jetzt)
        if grund:
            # task_id=None: kein Lauf im Protokoll, aber ein neuer Termin -
            # sonst steht der Plan in einer Minute wieder hier.
            await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, None,
                                    ausloeser="zeitplan", status=grund, jetzt=jetzt)
            log.warning("zeitplan %s (%s): %s", plan["id"], plan["name"], grund)
            protokoll.append((plan["id"], grund))
            continue
        await starte_plan(app, plan, ausloeser="zeitplan", jetzt=jetzt)
        protokoll.append((plan["id"], "gestartet"))
    return protokoll


async def zeitplan_schleife(app: FastAPI) -> None:
    """Laeuft, bis sie abgebrochen wird. Ein Fehler in einer Runde beendet
    nicht die Schleife - er steht im Log, und die naechste Runde kommt."""
    takt = max(1, int(app.state.settings.zeitplan_takt_s))
    while True:
        try:
            await pruefe_einmal(app)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - die Schleife darf nicht sterben
            log.exception("Zeitplan-Runde ist ausgestiegen")
        await asyncio.sleep(takt)


# --- HTTP -------------------------------------------------------------------


def _uebersicht(app: FastAPI) -> dict[str, Any]:
    settings = app.state.settings
    verbrauch = zeitplan.verbrauch_24h(settings.db_path)
    return {
        "zeitplaene": zeitplan.alle(settings.db_path),
        "verbrauch": {
            "laeufe": verbrauch.laeufe,
            "token": verbrauch.token,
            "max_laeufe": settings.zeitplan_max_laeufe_24h,
            "max_token": settings.zeitplan_max_token_24h,
        },
        "deckel": zeitplan.deckel_erreicht(
            verbrauch, max_laeufe=settings.zeitplan_max_laeufe_24h,
            max_token=settings.zeitplan_max_token_24h),
        "obergrenze": zeitplan.PERMISSION_DECKEL.name,
        "schleife": bool(settings.zeitplan_takt_s > 0),
    }


@zeitplan_router.get("")
async def get_zeitplaene(request: Request) -> dict[str, Any]:
    return await asyncio.to_thread(_uebersicht, request.app)


@zeitplan_router.post("", status_code=201)
async def post_zeitplan(request: Request, body: ZeitplanAnlegen) -> dict[str, Any]:
    pfad = request.app.state.settings.db_path
    try:
        return await asyncio.to_thread(
            zeitplan.anlegen, pfad, name=body.name, ziel=body.ziel,
            regel_text=body.regel)
    except ValueError as exc:      # RegelUngueltig ist ein ValueError
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@zeitplan_router.delete("/{zeitplan_id}")
async def delete_zeitplan(request: Request, zeitplan_id: str) -> dict[str, Any]:
    pfad = request.app.state.settings.db_path
    if not await asyncio.to_thread(zeitplan.loeschen, pfad, zeitplan_id):
        raise HTTPException(status_code=404, detail="Zeitplan nicht gefunden.")
    return {"id": zeitplan_id, "geloescht": True}


@zeitplan_router.post("/{zeitplan_id}/schalten")
async def schalte_zeitplan(request: Request, zeitplan_id: str,
                           body: Schalten) -> dict[str, Any]:
    pfad = request.app.state.settings.db_path
    plan = await asyncio.to_thread(zeitplan.schalten, pfad, zeitplan_id, body.aktiv)
    if plan is None:
        raise HTTPException(status_code=404, detail="Zeitplan nicht gefunden.")
    return plan


@zeitplan_router.post("/{zeitplan_id}/jetzt", status_code=202)
async def zeitplan_jetzt(request: Request, zeitplan_id: str) -> dict[str, Any]:
    """Von Hand ausloesen. Dieselben Grenzen wie die Schleife - LOCAL, Deckel,
    kein Doppellauf. Der Termin des Plans bleibt, wie er ist."""
    app = request.app
    pfad = app.state.settings.db_path
    plan = await asyncio.to_thread(zeitplan.hole, pfad, zeitplan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Zeitplan nicht gefunden.")
    grund = await asyncio.to_thread(hindernis, app, plan)
    if grund:
        raise HTTPException(status_code=409, detail=grund)
    task = await starte_plan(app, plan, ausloeser="hand")
    return {"id": zeitplan_id, "task_id": task.id, "status": "laeuft"}
