"""Weltlage-Endpunkte (docs/phases/PHASE-11.md).

Drei Grundsaetze, die hier als Code stehen und nicht als Bitte:

* **Ein Klick = ein Auftrag.** Geladen wird nur das angewaehlte Land. Wer 195
  Laender gleichzeitig live haelt, hat kein Dashboard gebaut, sondern ein Abo.
* **Cache je Land, TTL 60 Minuten.** Der zweite Klick innerhalb der Stunde
  kostet null neue Auftraege - im Zaehler nachpruefbar.
* **Ohne Medium und Datum wird die Meldung verworfen**, und die Zahl der
  verworfenen steht sichtbar in der Statusleiste.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request

from api.security import require_token
from api.tasks import LaufenderTask, baue_laufzeit
from core import db
from core.fehlertexte import ohne_geheimnis
from core.db import session
from core.weltlage import (
    CACHE_TTL_MINUTEN,
    Meldung,
    cache_lesen,
    cache_schreiben,
    hole_quellbild,
    siebe,
)

log = logging.getLogger("jarvis")

weltlage_router = APIRouter(prefix="/api/weltlage", dependencies=[Depends(require_token)])

MAX_KARTEN = 5          # Abschnitt 5: hoechstens 5 Karten gleichzeitig
WELTWEIT = "WELT"       # Abschnitt 3: beim Start 6 Ereignisse, nicht 195


def _settings(request: Request):
    return request.app.state.settings


def _heute() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _zaehle(conn, *, treffer: int = 0, abfragen: int = 0, verworfen: int = 0) -> None:
    conn.execute(
        "INSERT INTO weltlage_zaehler (tag, treffer, abfragen, verworfen) "
        "VALUES (?, ?, ?, ?) ON CONFLICT(tag) DO UPDATE SET "
        "treffer = treffer + excluded.treffer, "
        "abfragen = abfragen + excluded.abfragen, "
        "verworfen = verworfen + excluded.verworfen",
        (_heute(), treffer, abfragen, verworfen),
    )


def _meldung_aus_modell(roh: dict, land_iso: str) -> Meldung | None:
    """Baut eine Meldung aus dem, was das Modell geliefert hat.

    Was sich nicht in den Vertrag fuegt, wird hier zu None und spaeter
    gezaehlt - nicht zurechtgebogen.
    """
    wann = str(roh.get("veroeffentlicht") or "").strip()
    zeitpunkt = None
    for form in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M",
                 "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            zeitpunkt = datetime.strptime(wann, form)
            break
        except ValueError:
            continue
    if zeitpunkt is None:
        return None
    if zeitpunkt.tzinfo is None:
        zeitpunkt = zeitpunkt.replace(tzinfo=timezone.utc)

    return Meldung(
        schlagzeile=str(roh.get("schlagzeile") or "").strip(),
        kurz=str(roh.get("kurz") or "").strip(),
        medium=str(roh.get("medium") or "").strip(),
        veroeffentlicht=zeitpunkt,
        quell_url=str(roh.get("quell_url") or "").strip(),
        land_iso=str(roh.get("land_iso") or land_iso).strip().upper(),
        einordnung=str(roh.get("einordnung") or "").strip(),
        einordnung_fehlt=str(roh.get("einordnung_fehlt") or "").strip(),
    )


async def baue_nutzlast(
    request: Request, land_iso: str, roh_meldungen: list[dict], gesagt: str
) -> dict:
    """Vom Modellergebnis zur Anzeige - mit Sieb und Bildregel."""
    kandidaten: list[Meldung] = []
    unlesbar = 0
    for eintrag in roh_meldungen:
        m = _meldung_aus_modell(eintrag, land_iso)
        if m is None:
            unlesbar += 1
        else:
            kandidaten.append(m)

    weltweit = land_iso == WELTWEIT
    gut, gruende = siebe(kandidaten, weltweit=weltweit)
    if unlesbar:
        gruende.extend(["unlesbares Datum"] * unlesbar)

    # Das Bild wird serverseitig geholt, weil der Browser an CORS scheitert.
    # Kein og:image heisst: kein Bild. Nie ein Ersatz.
    async def schmuecke(m: Meldung) -> None:
        # Ein Verlag kann alles zurueckgeben. Was hier schiefgeht, kostet
        # dieses eine Bild - nicht die ganze Antwort.
        try:
            bild = await hole_quellbild(m.quell_url, medium=m.medium)
        except Exception as exc:                      # noqa: BLE001
            log.warning("Quellbild von %s nicht geholt: %s", m.quell_url, exc)
            return
        if bild is not None:
            m.bild_url = bild.url
            m.bild_herkunft = bild.herkunft
            m.bild_beschreibung = bild.beschreibung

    if gut:
        await asyncio.gather(*(schmuecke(m) for m in gut[:MAX_KARTEN * 2]))

    # Zweiter Durchgang: ein Bild ohne Herkunft faellt raus (Abschnitt 7).
    # Erst JETZT wird gekappt - sonst ruecken gueltige Kandidaten nicht nach,
    # wenn eine der ersten fuenf am Bild scheitert (BUGS-01 Fund 13).
    gut, nochmal = siebe(gut, weltweit=weltweit)
    gruende.extend(nochmal)
    gut = gut[:MAX_KARTEN]

    if not gut:
        gesagt = gesagt or f"Zu {land_iso} finde ich heute nichts."

    # Die Gruende stehen namentlich in der Antwort, nicht nur als Zahl.
    # "verworfen 3" sagt nichts; "2x doppelte Schlagzeile, 1x kein Medium"
    # sagt, was schiefgelaufen ist.
    haeufigkeit: dict[str, int] = {}
    for grund in gruende:
        haeufigkeit[grund] = haeufigkeit.get(grund, 0) + 1

    return {
        "land_iso": land_iso,
        "meldungen": [m.als_dict() for m in gut],
        "verworfen": len(gruende),
        "verworfen_gruende": haeufigkeit,
        "gesagt": gesagt,
        "cache": False,
    }


@weltlage_router.get("/zaehler")
async def get_zaehler(request: Request) -> dict:
    """Cache-Treffer gegen echte Abfragen, plus die Kosten des Tages.

    Die Kosten kommen aus `llm_calls`, nicht aus einer eigenen Zaehlung -
    sonst haette man zwei Wahrheiten.
    """
    pfad = _settings(request).db_path

    def lesen() -> dict:
        with session(pfad) as conn:
            zeile = conn.execute(
                "SELECT treffer, abfragen, verworfen FROM weltlage_zaehler WHERE tag = ?",
                (_heute(),),
            ).fetchone()
            treffer, abfragen, verworfen = (zeile if zeile else (0, 0, 0))
            kosten = conn.execute(
                "SELECT COALESCE(SUM(cost_eur), 0), COUNT(*) FROM llm_calls "
                "WHERE substr(created_at, 1, 10) = ?",
                (_heute(),),
            ).fetchone()
            laender = conn.execute("SELECT COUNT(*) FROM weltlage_cache").fetchone()[0]
        gesamt = treffer + abfragen
        return {
            "treffer": treffer,
            "abfragen": abfragen,
            "quote": round(treffer / gesamt, 3) if gesamt else 0.0,
            "verworfen": verworfen,
            "kosten_eur": round(kosten[0], 6),
            "modellaufrufe": kosten[1],
            "laender_im_cache": laender,
            "ttl_minuten": CACHE_TTL_MINUTEN,
        }

    return await asyncio.to_thread(lesen)


@weltlage_router.get("/{land_iso}")
async def get_weltlage(request: Request, land_iso: str) -> dict:
    """Cache-Treffer oder Auftrag. Nie beides, nie stillschweigend beides."""
    land_iso = land_iso.strip().upper()[:8]
    if not land_iso.isalnum():
        raise HTTPException(status_code=422, detail="Ungueltiger Laendercode.")
    pfad = _settings(request).db_path

    def aus_cache() -> dict | None:
        with session(pfad) as conn:
            treffer = cache_lesen(conn, land_iso)
            if treffer is not None:
                _zaehle(conn, treffer=1)
            return treffer

    gecached = await asyncio.to_thread(aus_cache)
    if gecached is not None:
        return gecached

    return {"land_iso": land_iso, "cache": False, "auftrag_noetig": True,
            "meldungen": [], "verworfen": 0,
            "gesagt": f"Ich schaue nach {land_iso}."}


@weltlage_router.post("/{land_iso}")
async def post_weltlage(request: Request, land_iso: str) -> dict:
    """Legt genau EINEN Auftrag an und schreibt das Ergebnis in den Cache."""
    land_iso = land_iso.strip().upper()[:8]
    if not land_iso.isalnum():
        raise HTTPException(status_code=422, detail="Ungueltiger Laendercode.")

    settings = _settings(request)
    pfad = settings.db_path

    def cache_pruefen() -> dict | None:
        with session(pfad) as conn:
            treffer = cache_lesen(conn, land_iso)
            if treffer is not None:
                _zaehle(conn, treffer=1)
            return treffer

    gecached = await asyncio.to_thread(cache_pruefen)
    if gecached is not None:
        return gecached

    from core.contracts import Permission, Task, TaskBudget
    from core.runner import fuehre_task_aus

    # FIX-02 Schritt 2: KEIN eigener Datenweg neben JARVIS.
    #
    # Vorher rief diese Route provider.complete() direkt auf. Das ging am
    # Runner vorbei - und damit an Budget, Audit UND an db.log_llm_call. Genau
    # daher kam die Kachel "heute 0,0000 EUR": die Aufrufe fanden statt, nur
    # protokolliert hat sie niemand.
    #
    # Jetzt laeuft die Weltlage als ganz normaler Auftrag durch denselben
    # Runner. Alles, was fuer /api/tasks gilt, gilt hier automatisch mit.
    ziel = ("Weltlage: sechs belegte Ereignisse weltweit, je zwei Saetze."
            if land_iso == WELTWEIT
            else f"Weltlage {land_iso}: was ist dort passiert? "
                 f"Hoechstens fuenf belegte Meldungen.")

    task = Task(goal=ziel, budget=TaskBudget.from_settings(settings))
    eintrag = LaufenderTask(task=task)
    request.app.state.tasks.add(eintrag)
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
    except Exception as exc:                      # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail=ohne_geheimnis(exc, "Die Weltlage liess sich nicht holen"),
        ) from exc
    finally:
        await asyncio.to_thread(db.save_task, settings.db_path, task)
        request.app.state.tasks.remove(task.id)

    if task.status != "done":
        raise HTTPException(
            status_code=502,
            detail=f"Der Auftrag endete auf {task.status}: "
                   f"{task.result or task.abort_reason or 'ohne Begruendung'}",
        )

    # Das JSON steht im SCHRITT, nicht in der Zusammenfassung: der Runner
    # formuliert am Ende Prosa, und Prosa ist kein Vertrag.
    roh_text = ""
    for schritt in reversed(task.steps):
        if schritt.result is not None and schritt.result.display:
            roh_text = schritt.result.display
            break
    roh_text = roh_text or (task.result or "")

    # FIX-02 Schritt 1: kein except, der eine Ausnahme in Inhalt verwandelt.
    # Unbrauchbares Modell-JSON ist ein Fehler und wird als Fehler gemeldet -
    # nicht als leere, erfolgreiche Antwort. Eine leere Antwort mit HTTP 200
    # sieht aus wie "heute ist nichts passiert"; das ist eine Behauptung, die
    # niemand geprueft hat.
    try:
        daten = json.loads(_json_aus(roh_text))
    except (ValueError, TypeError) as exc:
        raise HTTPException(
            status_code=502,
            detail=ohne_geheimnis(
                exc, "Das Modell hat kein verwertbares JSON geliefert"),
        ) from exc
    if not isinstance(daten, dict):
        raise HTTPException(
            status_code=502,
            detail=f"Das Modell hat {type(daten).__name__} statt eines Objekts geliefert.",
        )
    roh = daten.get("meldungen")
    if roh is not None and not isinstance(roh, list):
        raise HTTPException(
            status_code=502,
            detail=f"'meldungen' ist {type(roh).__name__}, erwartet wird eine Liste.",
        )

    nutzlast = await baue_nutzlast(request, land_iso, roh or [],
                                   str(daten.get("gesagt") or ""))

    def schreiben() -> None:
        with session(pfad) as conn:
            # Nur ein Ergebnis wird gecacht. Ein Lauf ohne Meldung koennte ein
            # echtes "heute nichts" sein oder eine gescheiterte Recherche - das
            # eine Stunde lang als Ergebnis auszuliefern waere geraten.
            if nutzlast["meldungen"]:
                cache_schreiben(conn, land_iso, nutzlast)
            _zaehle(conn, abfragen=1, verworfen=nutzlast["verworfen"])

    await asyncio.to_thread(schreiben)
    return nutzlast


def _json_aus(text: str) -> str:
    import re

    text = (text or "").strip()
    block = re.search(r"```(?:json)?\s*(.+?)```", text, re.DOTALL)
    if block:
        return block.group(1).strip()
    start, ende = text.find("{"), text.rfind("}")
    return text[start:ende + 1] if start != -1 and ende > start else text
