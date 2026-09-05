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

Was zwei Pruefrunden dazu gebracht haben (docs/FIX-08.md):

- DER TERMIN IST DIE SPERRE. Vor dem Start schiebt `termin_weiter` den
  Termin in einer Anweisung weiter - nur, wenn er noch der gelesene ist.
  Wer False bekommt, startet nicht. Das gilt in diesem Prozess, in einem
  zweiten Prozess und nach einem Absturz zwischen Buchung und Start.
- GEBUCHT WIRD VOR DEM START. Task-Zeile, Protokoll, `letzter_task_id` -
  alles steht, bevor der Runner den ersten Modellzug macht. Stirbt der
  Prozess dazwischen, findet `abgleich` den Rest beim naechsten Start.
- ZEITPLAENE LAUFEN NACHEINANDER. Zwei Plaene auf derselben Minute
  starten in einer Runde, der zweite nach dem Ende des ersten. So zaehlt
  der Deckel echten Verbrauch statt einer Reservierung, die den ganzen
  Tagesrest fuellt - und kein Plan verhungert, weil ein anderer gerade
  gestartet ist.
- NIEMAND BESTAETIGT. Ein Zeitplan-Lauf ist `unbeaufsichtigt`: ein
  Werkzeug, das nachfragen muesste, bekommt sofort Nein - statt 600
  Sekunden in einer Rueckfrage zu haengen, die keiner sieht.
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
from core import db, zeitplan
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


STARTET_GERADE = "uebersprungen: dieser Zeitplan startet gerade."
ANDERER_LAEUFT = "uebersprungen: ein anderer Zeitplan laeuft gerade."
AUSGESCHALTET = "uebersprungen: ausgeschaltet."
GELOESCHT = "geloescht"


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


def laufende(app: FastAPI) -> dict[str, int]:
    """Laufende Zeitplan-Tasks mit ihrem Token-Budget - das ist, was sie
    noch ausgeben duerfen, und damit das, was der Deckel reservieren muss.
    Fertige fallen heraus; ihre Token stehen dann in `tasks`."""
    tabelle = _zeitplan_tasks(app)
    ergebnis: dict[str, int] = {}
    for task_id in list(tabelle):
        eintrag = app.state.tasks.get(task_id)
        if eintrag is None:
            tabelle.pop(task_id, None)
            continue
        ergebnis[task_id] = int(eintrag.task.budget.max_tokens)
    return ergebnis


def verbrauch(app: FastAPI, jetzt: datetime | None = None) -> zeitplan.Verbrauch:
    """Regel 2 mit Reservierung: Datenbank plus laufende Tasks."""
    return zeitplan.verbrauch_24h(app.state.settings.db_path, jetzt,
                                  reserviert=laufende(app))


# --- Entscheidung je Plan ---------------------------------------------------


def _anbieter_fehlt(app: FastAPI) -> bool:
    # Spaeter Import: api.app importiert dieses Modul.
    from api.app import UnavailableProvider

    return isinstance(app.state.provider, UnavailableProvider)


def _laeuft_noch(app: FastAPI, plan: dict[str, Any]) -> bool:
    """Der vorige Lauf dieses Plans ist noch nicht fertig."""
    letzter = plan.get("letzter_task_id")
    return bool(letzter) and app.state.tasks.get(letzter) is not None


def _anderer_laeuft(app: FastAPI, plan_id: str) -> bool:
    """Laeuft oder startet gerade ein anderer Zeitplan-Auftrag? Zeitplaene
    laufen nacheinander - auch der Knopf wartet, bis der Vorige fertig ist."""
    if laufende(app):
        return True
    return bool(_beansprucht(app) - {plan_id})


def hindernis(app: FastAPI, plan: dict[str, Any],
              jetzt: datetime | None = None) -> str | None:
    """Warum dieser Plan JETZT nicht starten darf - oder None.

    Die Reihenfolge ist Absicht: erst das Billige (laeuft ein anderer?),
    dann der Anbieter, dann der Deckel, der eine Datenbankabfrage kostet.
    Blockierend - der Aufrufer legt es in einen Thread.
    """
    settings = app.state.settings
    if _laeuft_noch(app, plan):
        return "uebersprungen: der vorige Lauf dieses Zeitplans laeuft noch."
    if _anderer_laeuft(app, plan["id"]):
        return ANDERER_LAEUFT
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
    """Startet den Auftrag eines Plans - gebucht VOR dem Start, LOCAL als
    harte Obergrenze, hoechstens der Token-Rest des Tages als Budget,
    unbeaufsichtigt (keine Rueckfrage, die niemand beantwortet).

    Der Aufrufer hat `hindernis` schon gefragt und den Plan beansprucht.
    """
    settings = app.state.settings
    pfad = settings.db_path

    # Regel 2, zweite Haelfte: kein Lauf darf mehr kosten, als vom Tag
    # uebrig ist. `starte_task` laesst nur nach unten aendern.
    rest = settings.zeitplan_max_token_24h - verbrauch(app, jetzt).token
    budget = TaskBudget.from_settings(settings)
    budget.max_tokens = max(1, min(budget.max_tokens, rest))
    task = Task(goal=plan["ziel"], budget=budget)

    # Erst die Zeile, dann die Buchung, DANN der Start. Stirbt der Prozess
    # zwischendrin, steht "laeuft" mit einem Task, den `abgleich` beim
    # naechsten Start als "abgebrochen: Neustart" auflöst - und der Termin
    # ist schon weitergeschoben, also gibt es keinen zweiten Start.
    await asyncio.to_thread(db.save_task, pfad, task)
    await asyncio.to_thread(zeitplan.verbuche_start, pfad, plan, task.id,
                            ausloeser=ausloeser, jetzt=jetzt)
    _zeitplan_tasks(app)[task.id] = plan["id"]

    async def am_ende(fertig: Task) -> None:
        _zeitplan_tasks(app).pop(fertig.id, None)
        await asyncio.to_thread(zeitplan.nachtrag_ergebnis, pfad, fertig.id,
                                fertig.status)

    try:
        await starte_task(app, plan["ziel"], task=task,
                          max_permission=zeitplan.PERMISSION_DECKEL,
                          am_ende=am_ende, unbeaufsichtigt=True)
    except Exception:
        _zeitplan_tasks(app).pop(task.id, None)
        raise
    log.info("zeitplan %s (%s): Auftrag %s gestartet (%s)",
             plan["id"], plan["name"], task.id, ausloeser)
    return task


async def versuche_start(app: FastAPI, plan_id: str, *, ausloeser: str,
                         jetzt: datetime | None = None
                         ) -> tuple[Task | None, str | None]:
    """Der EINE Weg, einen Plan zu starten - fuer Schleife und Knopf.

    Beanspruchen (im Prozess, ohne await dazwischen), frisch lesen, Termin
    weiterschieben (die Sperre in der Datenbank - nur fuer die Schleife;
    der Knopf laesst den Termin), pruefen, starten, freigeben. Ein Fehler
    beim Start wird am Plan vermerkt und als Grund zurueckgegeben - der
    Termin ist dann schon weiter, der Plan haengt nicht.
    """
    beansprucht = _beansprucht(app)
    if plan_id in beansprucht:
        return None, STARTET_GERADE
    beansprucht.add(plan_id)
    pfad = app.state.settings.db_path
    try:
        plan = await asyncio.to_thread(zeitplan.hole, pfad, plan_id)
        if plan is None:
            return None, GELOESCHT
        if ausloeser == "zeitplan":
            if not plan["aktiv"]:
                return None, AUSGESCHALTET
            if not await asyncio.to_thread(zeitplan.termin_weiter, pfad, plan,
                                           "startet", jetzt):
                return None, STARTET_GERADE
        try:
            grund = await asyncio.to_thread(hindernis, app, plan, jetzt)
            if grund:
                if ausloeser == "zeitplan":
                    await asyncio.to_thread(zeitplan.setze_status, pfad, plan_id, grund)
                return None, grund
            return await starte_plan(app, plan, ausloeser=ausloeser, jetzt=jetzt), None
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - der Plan bekommt den Fehler, nicht die Schleife
            log.exception("zeitplan %s (%s): Start fehlgeschlagen", plan_id, plan["name"])
            grund = ohne_geheimnis(exc, "Start fehlgeschlagen",
                                   "Der Plan bekommt einen neuen Termin")
            try:
                await asyncio.to_thread(zeitplan.setze_status, pfad, plan_id, grund)
            except Exception:  # noqa: BLE001
                log.exception("zeitplan %s: nicht einmal der Status ging", plan_id)
            return None, grund
    finally:
        beansprucht.discard(plan_id)


async def _warte_auf(app: FastAPI, task_id: str, sekunden: float) -> None:
    """Auf das Ende eines Zeitplan-Laufs warten - hoechstens so lange, wie
    der Runner selbst erlaubt (BUDGET_MAX_SECONDS) plus Luft. Danach
    laeuft der Runner ohnehin in seinen eigenen Abbruch."""
    eintrag = app.state.tasks.get(task_id)
    if eintrag is None or eintrag.future is None:
        return
    await asyncio.wait({eintrag.future}, timeout=sekunden)


async def pruefe_einmal(app: FastAPI,
                        jetzt: datetime | None = None) -> list[tuple[str, str]]:
    """Eine Runde der Schleife. Gibt (plan_id, was_passiert_ist) zurueck,
    damit ein Test nachsehen kann, ohne die Datenbank zu lesen.

    Jeder Plan fuer sich, nacheinander: ein Fehler bei Plan A kostet Plan B
    nicht seinen Lauf, und B startet erst, wenn A fertig ist. `jetzt` ist
    der Rundenbeginn - wer waehrend der Runde auf A gewartet hat, wird
    dadurch nicht "verpasst".
    """
    settings = app.state.settings
    pfad = settings.db_path
    jetzt = jetzt or datetime.now(timezone.utc)
    toleranz = zeitplan.toleranz_fuer(settings.zeitplan_takt_s,
                                      settings.budget_max_seconds)
    protokoll: list[tuple[str, str]] = []

    # Erst aufraeumen: Plaene, die 'laeuft' sagen, obwohl ihr Task tot ist.
    for pid in await asyncio.to_thread(zeitplan.abgleich, pfad,
                                       set(laufende(app))):
        log.warning("zeitplan %s: Ausgang nach Neustart nachgetragen", pid)
        protokoll.append((pid, "abgeglichen"))

    for plan in await asyncio.to_thread(zeitplan.faellige, pfad, jetzt):
        pid, name = plan["id"], plan["name"]
        if zeitplan.ist_verpasst(plan, jetzt, toleranz):
            try:
                if await asyncio.to_thread(zeitplan.verbuche_verpasst, pfad, plan, jetzt):
                    log.warning("zeitplan %s (%s): Termin %s verpasst, nicht nachgeholt",
                                pid, name, plan["naechster_lauf"])
                    protokoll.append((pid, "verpasst"))
                else:
                    protokoll.append((pid, STARTET_GERADE))
            except Exception as exc:  # noqa: BLE001
                log.exception("zeitplan %s: Verpasst-Buchung fehlgeschlagen", pid)
                grund = ohne_geheimnis(exc, "Verpasst-Buchung fehlgeschlagen")
                protokoll.append((pid, grund))
            continue
        if pid in _beansprucht(app):
            # Der Knopf ist gerade dabei. Nichts buchen - die naechste
            # Runde sieht, was daraus geworden ist.
            protokoll.append((pid, STARTET_GERADE))
            continue
        task, grund = await versuche_start(app, pid, ausloeser="zeitplan", jetzt=jetzt)
        if task is not None:
            protokoll.append((pid, "gestartet"))
            # Nacheinander: der naechste Plan wartet, bis dieser fertig ist.
            await _warte_auf(app, task.id, settings.budget_max_seconds + 30)
            continue
        if grund not in (GELOESCHT, STARTET_GERADE, AUSGESCHALTET):
            log.warning("zeitplan %s (%s): %s", pid, name, grund)
        protokoll.append((pid, grund or ""))
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
    """Was die Oberflaeche zeigt. `verbrauch` ist der ECHTE Verbrauch aus der
    Datenbank; ein laufender Auftrag steht getrennt in `laeuft_gerade` mit
    dem, was er noch ausgeben darf. `deckel` rechnet beides zusammen - das
    ist der Grund, warum "Jetzt" gerade nicht geht. Vorher stand waehrend
    jedes Laufs "Tagesdeckel erreicht: 50.000 von 50.000" in der Liste, und
    das war eine Reservierung, kein Verbrauch."""
    settings = app.state.settings
    echt = zeitplan.verbrauch_24h(settings.db_path)
    laufend = laufende(app)
    mit_reserve = zeitplan.verbrauch_24h(settings.db_path, reserviert=laufend)
    deckel = zeitplan.deckel_erreicht(
        mit_reserve, max_laeufe=settings.zeitplan_max_laeufe_24h,
        max_token=settings.zeitplan_max_token_24h)
    deckel_echt = zeitplan.deckel_erreicht(
        echt, max_laeufe=settings.zeitplan_max_laeufe_24h,
        max_token=settings.zeitplan_max_token_24h)
    return {
        "zeitplaene": zeitplan.alle(settings.db_path),
        "verbrauch": {
            "laeufe": echt.laeufe,
            "token": echt.token,
            "max_laeufe": settings.zeitplan_max_laeufe_24h,
            "max_token": settings.zeitplan_max_token_24h,
        },
        "laeuft_gerade": [{"task_id": tid, "reserviert": budget}
                          for tid, budget in laufend.items()],
        # Der echte Deckel (rot) - und der Grund, warum "Jetzt" gerade nicht
        # geht, wenn nur ein Lauf im Weg steht (Hinweis, nicht rot).
        "deckel": deckel_echt,
        "gesperrt": deckel if deckel and not deckel_echt else None,
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
    (LOCAL, Deckel, nacheinander), der Termin des Plans bleibt, wie er
    ist. Geht auch bei einem ausgeschalteten Plan: "aus" heisst "laeuft
    nicht von selbst", nicht "darf nie laufen"."""
    task, grund = await versuche_start(request.app, zeitplan_id, ausloeser="hand")
    if task is not None:
        return {"id": zeitplan_id, "task_id": task.id, "status": "laeuft"}
    if grund == GELOESCHT:
        raise HTTPException(status_code=404, detail="Zeitplan nicht gefunden.")
    raise HTTPException(status_code=409, detail=grund)
