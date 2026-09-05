"""Zeitplaene ueber HTTP und die Schleife, die sie ausloest (FIX-08).

Die Regeln stehen in `core/zeitplan.py`. Hier steht nur, WANN sie greifen:

- Die Schleife laeuft alle ZEITPLAN_TAKT_S Sekunden (0 schaltet sie ab) und
  ruft `pruefe_einmal`. Die Funktion ist getrennt, damit ein Test sie mit
  einer festen Uhrzeit aufrufen kann, statt 60 Sekunden zu warten.
- Ein faelliger Plan wird GENAU EINMAL angefasst: verpasst, uebersprungen,
  gescheitert oder gestartet - und in jedem Fall bekommt er einen neuen
  Termin. Sonst bliebe er faellig und stuende in der naechsten Runde
  wieder an.
- Gestartet wird ueber `api.tasks.starte_task`, denselben Weg wie ein
  getippter Auftrag. Es gibt keinen zweiten Runner fuer Zeitplaene.

Zwei Dinge, die die erste Pruefrunde gefunden hat (docs/FIX-08.md):

- Schleife und "Jetzt"-Knopf konnten denselben Plan gleichzeitig starten:
  beide lasen den Plan, beide sahen "kein Hindernis", beide starteten.
  Deshalb `versuche_start`: ein Plan wird ERST beansprucht (synchron, ohne
  await dazwischen - auf einer Event-Loop ist das atomar), DANN frisch
  gelesen, geprueft und gestartet. Wer den Anspruch nicht bekommt, startet
  nicht.
- Der Token-Deckel zaehlte laufende Tasks mit 0, weil ihre Token erst am
  Ende in der Datenbank stehen. Drei gleichzeitig faellige Plaene konnten
  ihn so um das Dreifache reissen. Deshalb `reserviert`: was laufende
  Zeitplan-Tasks noch ausgeben DUERFEN, zaehlt schon - und jeder neue Lauf
  bekommt hoechstens das, was vom Tagesdeckel noch uebrig ist.
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
from core.contracts import Task, TaskBudget
from core.fehlertexte import ohne_geheimnis

log = logging.getLogger("jarvis")

zeitplan_router = APIRouter(prefix="/api/zeitplaene",
                            dependencies=[Depends(require_token)])


class ZeitplanAnlegen(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    ziel: str = Field(min_length=1, max_length=10_000)
    # Keine Obergrenze hier: `lies_regel` lehnt selbst ab und nennt dabei die
    # zwei erlaubten Formen. pydantic wuerde nur "string_too_long" sagen.
    regel: str = Field(min_length=1)


class Schalten(BaseModel):
    aktiv: bool


# --- Zustand im Prozess -----------------------------------------------------


def _beansprucht(app: FastAPI) -> set[str]:
    """Plaene, die gerade gestartet werden. Lebt in app.state, damit Tests
    mit einer frischen App auch einen frischen Zustand bekommen."""
    menge = getattr(app.state, "zeitplan_beansprucht", None)
    if menge is None:
        menge = app.state.zeitplan_beansprucht = set()
    return menge


def _zeitplan_tasks(app: FastAPI) -> dict[str, str]:
    """task_id -> plan_id fuer Tasks, die ein Zeitplan gestartet hat."""
    tabelle = getattr(app.state, "zeitplan_tasks", None)
    if tabelle is None:
        tabelle = app.state.zeitplan_tasks = {}
    return tabelle


def reserviert(app: FastAPI) -> int:
    """Token, die laufende Zeitplan-Tasks noch ausgeben duerfen.

    Ein Task, der laeuft, hat in der Datenbank noch (fast) keine Token -
    die kommen erst am Ende. Gezaehlt wird deshalb, was er noch darf:
    Budget minus bisher verbraucht. Fertige Tasks fallen hier heraus, ihre
    Token stehen dann in `tasks` und werden von `verbrauch_24h` gezaehlt.
    """
    tabelle = _zeitplan_tasks(app)
    summe = 0
    for task_id in list(tabelle):
        eintrag = app.state.tasks.get(task_id)
        if eintrag is None:
            tabelle.pop(task_id, None)      # fertig - steht in der Datenbank
            continue
        t = eintrag.task
        summe += max(0, t.budget.max_tokens - t.spent_tokens)
    return summe


def verbrauch(app: FastAPI, jetzt: datetime | None = None) -> zeitplan.Verbrauch:
    """Regel 2 mit Reservierung: Datenbank plus laufende Tasks."""
    v = zeitplan.verbrauch_24h(app.state.settings.db_path, jetzt)
    return zeitplan.Verbrauch(laeufe=v.laeufe, token=v.token + reserviert(app))


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
    Blockierend - der Aufrufer legt es in einen Thread.
    """
    settings = app.state.settings
    if _laeuft_noch(app, plan):
        return "uebersprungen: der vorige Lauf dieses Zeitplans laeuft noch."
    if _anbieter_fehlt(app):
        return "uebersprungen: kein Anbieter eingerichtet (LLM_API_KEY fehlt)."
    grund = zeitplan.deckel_erreicht(
        verbrauch(app, jetzt),
        max_laeufe=settings.zeitplan_max_laeufe_24h,
        max_token=settings.zeitplan_max_token_24h,
    )
    return f"uebersprungen: {grund}" if grund else None


async def starte_plan(app: FastAPI, plan: dict[str, Any], *, ausloeser: str,
                      jetzt: datetime | None = None) -> Task:
    """Startet den Auftrag eines Plans - mit LOCAL als harter Obergrenze und
    hoechstens dem Token-Rest des Tagesdeckels als Budget.

    Der Aufrufer hat `hindernis` schon gefragt und den Plan beansprucht.
    Hier wird gestartet und gebucht; `am_ende` traegt den Ausgang nach,
    wenn der Task fertig ist.
    """
    settings = app.state.settings
    pfad = settings.db_path

    # Regel 2, zweite Haelfte: kein Lauf darf mehr kosten, als vom Tag
    # uebrig ist. `starte_task` laesst nur nach unten aendern.
    rest = settings.zeitplan_max_token_24h - verbrauch(app, jetzt).token
    budget = TaskBudget.from_settings(settings)
    budget.max_tokens = max(1, min(budget.max_tokens, rest))

    async def am_ende(task: Task) -> None:
        _zeitplan_tasks(app).pop(task.id, None)
        await asyncio.to_thread(zeitplan.nachtrag_ergebnis, pfad, task.id,
                                task.status)

    task = await starte_task(app, plan["ziel"],
                             max_permission=zeitplan.PERMISSION_DECKEL,
                             budget=budget, am_ende=am_ende)
    _zeitplan_tasks(app)[task.id] = plan["id"]
    await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, task.id,
                            ausloeser=ausloeser, status="laeuft", jetzt=jetzt)
    # War der Task schneller fertig als diese Buchung, hat `am_ende` ins
    # Leere geschrieben (die Buchung kannte die task_id noch nicht). Dann
    # jetzt nachtragen - sonst steht "laeuft" fuer immer am Plan.
    if app.state.tasks.get(task.id) is None:
        await asyncio.to_thread(zeitplan.nachtrag_ergebnis, pfad, task.id,
                                task.status)
    log.info("zeitplan %s (%s): Auftrag %s gestartet (%s)",
             plan["id"], plan["name"], task.id, ausloeser)
    return task


STARTET_GERADE = "uebersprungen: dieser Zeitplan startet gerade."
GELOESCHT = "geloescht"


async def versuche_start(app: FastAPI, plan_id: str, *, ausloeser: str,
                         jetzt: datetime | None = None
                         ) -> tuple[Task | None, str | None]:
    """Der EINE Weg, einen Plan zu starten - fuer Schleife und Knopf.

    Beanspruchen, frisch lesen, pruefen, starten, freigeben. Das
    Beanspruchen passiert ohne await dazwischen; auf einer Event-Loop kann
    sich deshalb kein zweiter Aufrufer dazwischenschieben.
    """
    beansprucht = _beansprucht(app)
    if plan_id in beansprucht:
        return None, STARTET_GERADE
    beansprucht.add(plan_id)
    try:
        pfad = app.state.settings.db_path
        plan = await asyncio.to_thread(zeitplan.hole, pfad, plan_id)
        if plan is None:
            return None, GELOESCHT
        grund = await asyncio.to_thread(hindernis, app, plan, jetzt)
        if grund:
            return None, grund
        return await starte_plan(app, plan, ausloeser=ausloeser, jetzt=jetzt), None
    finally:
        beansprucht.discard(plan_id)


async def pruefe_einmal(app: FastAPI,
                        jetzt: datetime | None = None) -> list[tuple[str, str]]:
    """Eine Runde der Schleife. Gibt (plan_id, was_passiert_ist) zurueck,
    damit ein Test nachsehen kann, ohne die Datenbank zu lesen.

    Jeder Plan fuer sich: ein Fehler bei Plan A kostet Plan B nicht seinen
    Lauf, und A bekommt den Fehler als Status plus einen neuen Termin.
    """
    settings = app.state.settings
    pfad = settings.db_path
    jetzt = jetzt or datetime.now(timezone.utc)
    toleranz = zeitplan.toleranz_fuer(settings.zeitplan_takt_s)
    protokoll: list[tuple[str, str]] = []
    for plan in await asyncio.to_thread(zeitplan.faellige, pfad, jetzt):
        pid, name = plan["id"], plan["name"]
        try:
            if zeitplan.ist_verpasst(plan, jetzt, toleranz):
                await asyncio.to_thread(zeitplan.verbuche_verpasst, pfad, plan, jetzt)
                log.warning("zeitplan %s (%s): Termin %s verpasst, nicht nachgeholt",
                            pid, name, plan["naechster_lauf"])
                protokoll.append((pid, "verpasst"))
                continue
            if pid in _beansprucht(app):
                # Der Knopf ist gerade dabei. Nichts buchen - die naechste
                # Runde sieht, was daraus geworden ist.
                protokoll.append((pid, STARTET_GERADE))
                continue
            task, grund = await versuche_start(app, pid, ausloeser="zeitplan",
                                               jetzt=jetzt)
            if task is not None:
                protokoll.append((pid, "gestartet"))
                continue
            if grund in (GELOESCHT, STARTET_GERADE):
                protokoll.append((pid, grund))
                continue
            # task_id=None: kein Lauf im Protokoll, aber ein neuer Termin -
            # sonst steht der Plan in einer Minute wieder hier.
            await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, None,
                                    ausloeser="zeitplan", status=grund, jetzt=jetzt)
            log.warning("zeitplan %s (%s): %s", pid, name, grund)
            protokoll.append((pid, grund or ""))
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - ein Plan darf die Runde nicht reissen
            log.exception("zeitplan %s (%s): Start fehlgeschlagen", pid, name)
            grund = ohne_geheimnis(exc, "Start fehlgeschlagen",
                                   "Der Plan bekommt einen neuen Termin")
            try:
                await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, None,
                                        ausloeser="zeitplan", status=grund, jetzt=jetzt)
            except Exception:  # noqa: BLE001
                log.exception("zeitplan %s: nicht einmal die Buchung ging", pid)
            protokoll.append((pid, grund))
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
    v = verbrauch(app)
    return {
        "zeitplaene": zeitplan.alle(settings.db_path),
        "verbrauch": {
            "laeufe": v.laeufe,
            "token": v.token,
            "max_laeufe": settings.zeitplan_max_laeufe_24h,
            "max_token": settings.zeitplan_max_token_24h,
        },
        "deckel": zeitplan.deckel_erreicht(
            v, max_laeufe=settings.zeitplan_max_laeufe_24h,
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
    """Von Hand ausloesen - ein Probelauf. Dieselben Grenzen wie die Schleife
    (LOCAL, Deckel, kein Doppellauf), der Termin des Plans bleibt, wie er
    ist. Geht auch bei einem ausgeschalteten Plan: "aus" heisst "laeuft
    nicht von selbst", nicht "darf nie laufen"."""
    task, grund = await versuche_start(request.app, zeitplan_id, ausloeser="hand")
    if task is not None:
        return {"id": zeitplan_id, "task_id": task.id, "status": "laeuft"}
    if grund == GELOESCHT:
        raise HTTPException(status_code=404, detail="Zeitplan nicht gefunden.")
    raise HTTPException(status_code=409, detail=grund)
