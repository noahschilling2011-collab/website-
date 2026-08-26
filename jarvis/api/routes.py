"""Endpunkte.

Zwei Grundsaetze:

* Der Modellaufruf passiert **ausserhalb** jeder offenen Transaktion. Er
  dauert Sekunden; solange eine Schreibsperre zu halten, blockiert alles.
* Jeder Modellaufruf wird protokolliert - auch der fehlgeschlagene. Sonst
  faellt eine Retry-Schleife, die Geld verbrennt, erst auf der Rechnung auf.
"""

from __future__ import annotations

import asyncio
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, Response, StreamingResponse

from api.schemas import (
    ChatRequest,
    ChatResponse,
    FactCreate,
    FactCreated,
    FactOut,
    FactUpdate,
    HealthOut,
    MessageOut,
    SpendOut,
    TaskLogOut,
    ToolCallOut,
)
from api.events import strom
from api.security import require_token
from core import db, gedaechtnis, memory
from core.satellite import bilder
from core.abbruch import LaufBeendet, baue_pruefpunkt
from core.contracts import Permission, Task, TaskBudget
from core.llm import (
    LLMError,
    LLMMessage,
    LLMReply,
    ab_erster_nutzernachricht,
)
from core.tools import registry
from core.tools.dispatch import ToolCall
from core.tools.loop import run_tool_loop

log = logging.getLogger("jarvis")

router = APIRouter()
api = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


def _settings(request: Request):
    return request.app.state.settings


@api.get("/health", response_model=HealthOut)
async def health(request: Request) -> HealthOut:
    settings = _settings(request)
    provider = request.app.state.provider

    try:
        anzahl = await asyncio.to_thread(db.count_messages, settings.db_path)
        totals = await asyncio.to_thread(db.llm_call_totals, settings.db_path)
        database = "ok"
    except Exception as exc:  # die Meldung soll die Ursache zeigen
        anzahl, totals, database = 0, {}, f"fehler: {exc}"

    provider_error = getattr(provider, "reason", None)
    return HealthOut(
        status="ok" if database == "ok" and provider_error is None else "degraded",
        phase=2,
        provider=provider.name,
        model=provider.model,
        api_key_configured=bool(settings.llm_api_key),
        api_key_hint=settings.masked_api_key(),
        provider_error=provider_error,
        database=database,
        messages=anzahl,
        spend=SpendOut(
            calls=int(totals.get("calls", 0)),
            in_tokens=int(totals.get("in_tokens", 0)),
            out_tokens=int(totals.get("out_tokens", 0)),
            cost_eur=float(totals.get("cost_eur", 0.0)),
            prices_configured=settings.prices_configured,
        ),
    )


@api.get("/messages", response_model=list[MessageOut])
async def get_messages(request: Request) -> list[MessageOut]:
    settings = _settings(request)
    messages = await asyncio.to_thread(db.list_messages, settings.db_path)
    gruppen = await asyncio.to_thread(db.tool_calls_by_message, settings.db_path)
    return [MessageOut.of(m, gruppen.get(m.id, [])) for m in messages]


@api.post("/chat", response_model=ChatResponse)
async def post_chat(request: Request, body: ChatRequest) -> ChatResponse:
    settings = _settings(request)
    provider = request.app.state.provider

    text = body.message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Die Nachricht ist leer.")

    task_id = uuid.uuid4().hex[:12]

    # 1. Nutzernachricht festschreiben, Verlauf lesen.
    await asyncio.to_thread(db.add_message, settings.db_path, "user", text)
    history = await asyncio.to_thread(
        db.list_messages, settings.db_path, settings.history_limit
    )
    # BUGS-01 Fund 23: das Fenster darf nicht mit `assistant` beginnen.
    history = ab_erster_nutzernachricht(history)

    # Werkzeugaufrufe werden geschrieben, sobald sie passieren - noch ohne
    # message_id, die Antwort gibt es ja noch nicht. Sonst waere nach einem
    # Absturz mitten in der Schleife nicht nachvollziehbar, was schon lief.
    aufruf_ids: list[int] = []
    aufrufe: list[ToolCall] = []

    # BUGS-01 Fund 16: der Chat hatte kein Budget. Begrenzt war nur die Zahl
    # der Werkzeugrunden - keine Token-, Kosten- oder Zeitschranke. Ein
    # Chat-Zug konnte damit mehr kosten als ein ganzer Auftrag, fuer den 0.5
    # ein hartes Budget vorschreibt. Der Zug bekommt hier dieselbe Buchhaltung
    # wie ein Task, mit denselben Werten aus der .env.
    zug = Task(goal=text, budget=TaskBudget.from_settings(settings))
    # FIX-03 Schritt 3a: derselbe Pruefpunkt wie im Runner. Einen Abbruch gibt
    # es im Chat nicht - ein Zug ist kurz und hat keine Auftrags-ID, die man
    # abbrechen koennte -, die Verbrauchsgrenzen gelten aber genauso.
    pruefpunkt = baue_pruefpunkt(zug, abgebrochen=lambda: False)

    async def merke_aufruf(aufruf: ToolCall) -> None:
        zug.spent_tool_calls += 1
        aufrufe.append(aufruf)
        ergebnis = aufruf.result
        zeile = await asyncio.to_thread(
            db.add_tool_call,
            settings.db_path,
            message_id=None,
            name=aufruf.name,
            arguments=aufruf.arguments,
            ok=bool(ergebnis and ergebnis.ok),
            display=(ergebnis.display if ergebnis else ""),
            error=(ergebnis.error if ergebnis else None),
            sources=(list(ergebnis.sources) if ergebnis else []),
            duration_ms=(ergebnis.duration_ms if ergebnis else 0),
        )
        aufruf_ids.append(zeile.id)
        log.info(
            "task %s: Werkzeug %s(%s) -> ok=%s in %d ms",
            task_id, aufruf.name, aufruf.arguments,
            bool(ergebnis and ergebnis.ok),
            ergebnis.duration_ms if ergebnis else 0,
        )

    async def protokolliere_modellaufruf(reply: LLMReply) -> None:
        kosten = settings.cost_eur(reply.usage.in_tokens, reply.usage.out_tokens)
        zug.spent_tokens += reply.usage.in_tokens + reply.usage.out_tokens
        zug.spent_cost_eur += kosten
        await asyncio.to_thread(
            db.log_llm_call,
            settings.db_path,
            model=reply.model,
            prompt_hash=reply.prompt_hash,
            in_tokens=reply.usage.in_tokens,
            out_tokens=reply.usage.out_tokens,
            cost_eur=kosten,
            duration_ms=reply.duration_ms,
            ok=True,
        )

    # Passende Fakten in den Systemprompt heben. Jede Zeile traegt ihre
    # Fakt-ID, damit die Herkunft sichtbar bleibt (Phase 3).
    # FIX-04: derselbe Leseweg wie das Panel und wie `recall`. Vorher las
    # diese Zeile nur `facts` - mit gesetztem VAULT_PFAD kam hier IMMER ein
    # leerer Block heraus, und Phase-3-DoD 2 war still kaputt.
    gedaechtnis_block = await asyncio.to_thread(
        gedaechtnis.kontextblock, settings.db_path, settings.vault_pfad, text
    )
    systemprompt = (
        f"{settings.system_prompt}\n\n{gedaechtnis_block}"
        if gedaechtnis_block
        else settings.system_prompt
    )
    if gedaechtnis_block:
        # Gezaehlt werden die Zeilen, die wirklich ein Fakt sind - die erste
        # Zeile ist die Ueberschrift. Ein "+1" auf die Trennzeichen zaehlt sie
        # mit und meldet dann einen Fakt zuviel.
        anzahl = sum(1 for z in gedaechtnis_block.splitlines()
                     if z.startswith("- "))
        log.info("task %s: %d Fakten in den Kontext gehoben", task_id, anzahl)

    # 2. Modell fragen, Werkzeuge laufen lassen. Keine Transaktion offen.
    try:
        antwort, _, _ = await run_tool_loop(
            provider,
            [LLMMessage(role=m.role, content=m.content) for m in history],
            system=systemprompt,
            max_permission=Permission(settings.max_permission),
            max_tool_calls=settings.budget_max_tool_calls,
            on_call=merke_aufruf,
            on_reply=protokolliere_modellaufruf,
            pruefpunkt=pruefpunkt,
        )
    except LaufBeendet as ende:
        # Das Budget ist aufgebraucht. Der Nutzer bekommt trotzdem, was bis
        # dahin da war - stillschweigend abbrechen waere schlimmer als eine
        # kurze Antwort mit Hinweis.
        log.warning("chat %s: %s", task_id, ende.grund)
        antwort = ende.teiltext or f"[Budget aufgebraucht: {ende.grund}]"
    except LLMError as exc:
        await asyncio.to_thread(
            db.log_llm_call,
            settings.db_path,
            model=provider.model or "unbekannt",
            prompt_hash=exc.prompt_hash,
            in_tokens=0,
            out_tokens=0,
            cost_eur=0.0,
            duration_ms=exc.duration_ms,
            ok=False,
        )
        await asyncio.to_thread(
            memory.log_task, settings.db_path, task_id,
            goal=text, outcome="failed", summary=str(exc)[:500],
        )
        log.warning("task %s: Modellaufruf fehlgeschlagen - %s", task_id, exc)
        raise

    # 3. Antwort festschreiben und die Aufrufe daranhaengen.
    nachricht = await asyncio.to_thread(
        db.add_message, settings.db_path, "assistant", antwort
    )
    await asyncio.to_thread(
        db.attach_tool_calls, settings.db_path, aufruf_ids, nachricht.id
    )

    # Episodisches Gedaechtnis: was war der Auftrag, wie ging er aus.
    await asyncio.to_thread(
        memory.log_task, settings.db_path, task_id,
        goal=text, outcome="done",
        summary=antwort if len(antwort) <= 500 else antwort[:499] + "…",
    )

    return ChatResponse(
        reply=antwort,
        task_id=task_id,
        tool_calls=[
            ToolCallOut(
                name=a.name,
                arguments=a.arguments,
                ok=bool(a.result and a.result.ok),
                display=(a.result.display if a.result else ""),
                error=(a.result.error if a.result else None),
                sources=(list(a.result.sources) if a.result else []),
                duration_ms=(a.result.duration_ms if a.result else 0),
            )
            for a in aufrufe
        ],
    )


@api.get("/memory", response_model=list[FactOut])
async def get_memory(request: Request, q: str = "") -> list[FactOut]:
    """Alles, was JARVIS ueber dich weiss. Mit `q` gefiltert.

    FIX-04: liest ueber `core.gedaechtnis` - denselben Weg wie `recall`.
    """
    settings = _settings(request)
    eintraege = await asyncio.to_thread(
        gedaechtnis.liste, settings.db_path, settings.vault_pfad, q
    )
    if not eintraege and not q.strip():
        # Eine leere Liste sieht aus wie "noch nichts gemerkt". Wenn der Vault
        # aber voll ist, ist sie ein Fehler und muss als Fehler dastehen.
        schaden = await asyncio.to_thread(
            gedaechtnis.fehlbestand, settings.db_path, settings.vault_pfad
        )
        if schaden:
            log.error("Gedaechtnis: %s", schaden)
            raise HTTPException(status_code=500, detail=schaden)
    return [FactOut.of(e) for e in eintraege]


@api.post("/memory", response_model=FactCreated, status_code=201)
async def post_memory(request: Request, body: FactCreate) -> FactCreated:
    """FIX-04 Schritt 2: mit Vault entsteht zuerst die DATEI, dann der Index."""
    settings = _settings(request)
    try:
        neu, konflikt = await asyncio.to_thread(
            gedaechtnis.anlegen, settings.db_path, settings.vault_pfad,
            body.text, category=body.category, quelle="mensch",
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except OSError as exc:
        raise HTTPException(
            status_code=507, detail=f"Vault nicht beschreibbar: {exc}"
        ) from exc
    return FactCreated(
        fact=FactOut.of(neu),
        conflict=FactOut.of(konflikt) if konflikt else None,
    )


@api.patch("/memory/{fact_id}", response_model=FactOut)
async def patch_memory(
    request: Request, fact_id: str, body: FactUpdate
) -> FactOut:
    """`fact_id` ist ein String: mit Vault heisst er `f_395043`, ohne Vault `7`."""
    settings = _settings(request)
    try:
        geaendert = await asyncio.to_thread(
            gedaechtnis.aendern,
            settings.db_path,
            settings.vault_pfad,
            fact_id,
            text=body.text,
            category=body.category,
            confirmed=body.confirmed,
            widerspruch_aufloesen=body.resolve_conflict,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if geaendert is None:
        raise HTTPException(status_code=404, detail="Fakt nicht gefunden.")
    return FactOut.of(geaendert)


@api.delete("/memory/{fact_id}", status_code=204)
async def delete_memory(request: Request, fact_id: str) -> None:
    """Mit Vault verschwindet die DATEI, danach der Indexeintrag."""
    settings = _settings(request)
    if not await asyncio.to_thread(
        gedaechtnis.loeschen, settings.db_path, settings.vault_pfad, fact_id
    ):
        raise HTTPException(status_code=404, detail="Fakt nicht gefunden.")


@api.get("/task-log", response_model=list[TaskLogOut])
async def get_task_log(request: Request) -> list[TaskLogOut]:
    """Das episodische Gedaechtnis: was wurde wann beauftragt, wie ging es aus.

    Nicht zu verwechseln mit `GET /api/tasks` aus Phase 4 - das ist die
    Struktur laufender Auftraege, das hier die kurze Chronik."""
    rows = await asyncio.to_thread(memory.list_task_log, _settings(request).db_path)
    return [TaskLogOut.of(r) for r in rows]


@api.get("/audit")
async def get_audit(request: Request) -> list[dict]:
    """Das Audit-Log: jede Aktion ab EXTERNAL, unveraenderlich (Phase 5).

    Die Tabelle laesst UPDATE und DELETE nicht zu - das ist ein Trigger in
    `core/schema.sql`, keine Absprache.
    """
    rows = await asyncio.to_thread(db.list_audit, _settings(request).db_path)
    return [
        {
            "id": r.id, "task_id": r.task_id, "step_id": r.step_id,
            "tool": r.tool, "arguments": r.arguments, "permission": r.permission,
            "decision": r.decision, "executed": r.executed, "ok": r.ok,
            "detail": r.detail, "created_at": r.created_at,
        }
        for r in rows
    ]


@api.get("/events")
async def get_events(request: Request) -> StreamingResponse:
    """Live-Strom der Task-Ereignisse (Phase 7, DoD 1).

    Kein Polling im Sekundentakt. Der Browser liest das mit fetch und einem
    Reader statt mit EventSource - so bleibt der Token im Header und landet
    nicht in der URL und damit im Log.
    """
    return StreamingResponse(
        strom(
            request.app.state.events,
            herzschlag=_settings(request).sse_heartbeat_seconds,
            getrennt=request.is_disconnected,
        ),
        media_type="text/event-stream",
        headers={
            "cache-control": "no-cache",
            # Falls je ein Reverse-Proxy davorkommt: nicht puffern.
            "x-accel-buffering": "no",
        },
    )


@api.get("/tool-calls")
async def get_tool_calls(request: Request, limit: int = 100) -> list[dict]:
    """Das Werkzeug-Log ueber alle Antworten hinweg."""
    pfad = _settings(request).db_path

    def lesen() -> list[dict]:
        with db.session(pfad) as conn:
            rows = conn.execute(
                "SELECT * FROM tool_calls ORDER BY id DESC LIMIT ?",
                (max(1, min(limit, 1000)),),
            ).fetchall()
        return [db.ToolCallRow.from_row(r).__dict__ for r in rows]

    return await asyncio.to_thread(lesen)


@api.get("/bild/{kennung}")
async def get_bild(request: Request, kennung: str) -> Response:
    """Ein Satellitenbild als PNG.

    Liegt bewusst hinter demselben `X-Jarvis-Token` wie alles unter `/api/`.
    Ein `<img src>` kann diesen Header nicht schicken - deshalb holt das
    Frontend die Bytes per fetch() und macht daraus eine Blob-URL. Der
    Umweg ist der Punkt: die Alternative waere der Token in der Adresszeile,
    im Verlauf, im Referrer und in jedem Log.
    """
    pfad = _settings(request).db_path
    try:
        daten = await asyncio.to_thread(bilder.lade, kennung, db_path=pfad)
    except bilder.BildFehler as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if daten is None:
        raise HTTPException(status_code=404, detail="Bild nicht gefunden.")
    return Response(
        content=daten,
        media_type="image/png",
        # Inhaltsadressiert: dieselbe ID sind immer dieselben Bytes.
        headers={"Cache-Control": "private, max-age=86400, immutable"},
    )


@api.get("/stats")
async def get_stats(request: Request) -> dict:
    """Kosten je Tag, Fehlerrate, Modellverbrauch (Phase 7).

    Alles direkt aus `llm_calls` gerechnet - nicht geschaetzt und nicht
    nebenher mitgezaehlt. Wenn die Zahl hier von der Summe abweicht, ist die
    Zahl falsch, nicht die Tabelle.
    """
    pfad = _settings(request).db_path

    def rechnen() -> dict:
        with db.session(pfad) as conn:
            pro_tag = [
                dict(r) for r in conn.execute(
                    "SELECT substr(created_at, 1, 10) AS tag, COUNT(*) AS calls, "
                    "SUM(in_tokens) AS in_tokens, SUM(out_tokens) AS out_tokens, "
                    "ROUND(SUM(cost_eur), 6) AS cost_eur, "
                    "SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS fehler "
                    "FROM llm_calls GROUP BY tag ORDER BY tag DESC LIMIT 30"
                )
            ]
            pro_modell = [
                dict(r) for r in conn.execute(
                    "SELECT model, COUNT(*) AS calls, SUM(in_tokens) AS in_tokens, "
                    "SUM(out_tokens) AS out_tokens, ROUND(SUM(cost_eur), 6) AS cost_eur "
                    "FROM llm_calls GROUP BY model ORDER BY calls DESC"
                )
            ]
            gesamt = dict(conn.execute(
                "SELECT COUNT(*) AS calls, "
                "COALESCE(SUM(in_tokens), 0) AS in_tokens, "
                "COALESCE(SUM(out_tokens), 0) AS out_tokens, "
                "ROUND(COALESCE(SUM(cost_eur), 0), 6) AS cost_eur, "
                "SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS fehler "
                "FROM llm_calls"
            ).fetchone())
            werkzeuge = [
                dict(r) for r in conn.execute(
                    "SELECT name, COUNT(*) AS calls, "
                    "SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS fehler, "
                    "ROUND(AVG(duration_ms)) AS ms "
                    "FROM tool_calls GROUP BY name ORDER BY calls DESC"
                )
            ]
            tasks = dict(conn.execute(
                "SELECT COUNT(*) AS gesamt, "
                "SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) AS done, "
                "SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed, "
                "SUM(CASE WHEN status = 'aborted_budget' THEN 1 ELSE 0 END) "
                "AS aborted_budget, "
                "SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled "
                "FROM tasks"
            ).fetchone())

        calls = gesamt["calls"] or 0
        fehler = gesamt["fehler"] or 0
        return {
            "total": {**gesamt, "fehler": fehler,
                      "fehlerrate": round(fehler / calls, 4) if calls else 0.0},
            "per_day": pro_tag,
            "per_model": pro_modell,
            "per_tool": werkzeuge,
            "tasks": tasks,
        }

    return await asyncio.to_thread(rechnen)


@router.get("/", include_in_schema=False)
async def index(request: Request) -> HTMLResponse:
    """Liefert die Oberflaeche.

    Der JARVIS-Token wird beim Ausliefern eingesetzt, damit die Seite die API
    aufrufen kann. Das ist kein Leck: eine fremde Seite kann die Antwort von
    127.0.0.1 wegen CORS nicht lesen, und auf der Platte steht nur der
    Platzhalter. Der **LLM**-Key kommt hier niemals hin (0.4.1).
    """
    html = request.app.state.index_path.read_text(encoding="utf-8")
    return HTMLResponse(html.replace("__JARVIS_TOKEN__", request.app.state.token))


@router.get("/weltlage", include_in_schema=False)
async def weltlage_seite(request: Request) -> HTMLResponse:
    """Die Globus-Ansicht (Phase 11).

    Eigene Seite statt fuenfter Tab in `index.html`: der Phasenauftrag
    verlangt Vollbild ohne Scrollbalken, und der Globus haelt sich nicht an
    das Raster der Chat-Oberflaeche. Kein Build-Step, wie ueberall sonst.

    Der Token wird wie bei `/` beim Ausliefern eingesetzt, der LLM-Key
    niemals (0.4.1).
    """
    seite = request.app.state.weltlage_path
    if not seite.exists():
        raise HTTPException(status_code=404, detail="weltlage.html fehlt.")
    html = seite.read_text(encoding="utf-8")
    return HTMLResponse(html.replace("__JARVIS_TOKEN__", request.app.state.token))
