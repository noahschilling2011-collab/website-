"""Modellanbindung.

`LLMProvider` ist abstrakt. Dahinter steht in Phase 1 genau **ein** echter
Anbieter - austauschbar, aber nicht spekulativ. `FakeLLMProvider` ist kein
zweiter Anbieter, sondern der Testdoppelgaenger aus CLAUDE.md: Tests laufen
ausschliesslich dagegen, damit sie nichts kosten.

httpx wird async benutzt, passend zu FastAPI. Timeout je Aufruf: 60 s (0.6).

Ausdruecklich **nicht** gesendet werden `temperature`, `top_p`, `top_k` und
`thinking.budget_tokens`. Auf den aktuellen Opus-Modellen ist jedes davon ein
400. Die Anfrageform stammt aus der Anbieter-Dokumentation, nicht aus dem
Gedaechtnis.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Iterable

import httpx

ANTHROPIC_VERSION = "2023-06-01"
# Groq spricht das OpenAI-Format unter einem eigenen Praefix.
# console.groq.com/docs/api-reference: POST /openai/v1/chat/completions
GROQ_BASIS = "https://api.groq.com"

# Wiederholbar laut Fehlertabelle des Anbieters. Alles andere ist ein Fehler
# in der Anfrage und wird durch Wiederholen nicht besser.
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 529})


@dataclass(frozen=True)
class ToolUse:
    """Ein Werkzeugaufruf, den das Modell vorschlaegt."""

    id: str
    name: str
    input: dict[str, Any]


def ab_erster_nutzernachricht(verlauf: list):
    """Schneidet vorne weg, bis die erste Nachricht von `user` ist.

    BUGS-01 Fund 23. Die Messages-API verlangt `user` als erste Rolle. Der
    Verlauf ist u,a,u,a,... - sobald mehr Zeilen da sind als `history_limit`,
    schneidet ein Fenster gerader Laenge aus einer ungeraden Folge, und das
    beginnt mit `assistant`. Gemessen war ab dem 21. Zug JEDE Anfrage
    betroffen, nicht nur jede 21.:

        Zug 21: HTTP 502 - "Die erste Nachricht muss von 'user' sein."

    Der Anbieter faengt es ab und meldet es sauber - deshalb wird hier
    geschnitten und nicht dort die Pruefung entfernt. Eine Antwort des
    Assistenten ohne die Frage davor ist ohnehin Kontext ohne Anker.

    Arbeitet auf allem, was `.role` hat: `LLMMessage` genauso wie die
    `Message`-Zeilen aus der Datenbank.
    """
    for i, nachricht in enumerate(verlauf):
        if getattr(nachricht, "role", None) == "user":
            return verlauf[i:]
    return []


@dataclass(frozen=True)
class LLMMessage:
    role: str
    # Entweder Text oder rohe Inhaltsbloecke. Bloecke braucht der Tool-Loop:
    # die Assistenten-Antwort mit tool_use und die Nutzerzeile mit tool_result
    # muessen unveraendert zurueckgeschickt werden.
    content: str | list[dict[str, Any]]


@dataclass(frozen=True)
class LLMUsage:
    in_tokens: int = 0
    out_tokens: int = 0


@dataclass(frozen=True)
class LLMReply:
    text: str
    model: str
    usage: LLMUsage = field(default_factory=LLMUsage)
    duration_ms: int = 0
    stop_reason: str | None = None
    prompt_hash: str = ""
    tool_uses: tuple[ToolUse, ...] = ()
    # Die Bloecke der Assistenten-Antwort, wortwoertlich. Gehen im naechsten
    # Zug unveraendert zurueck - sonst verliert das Modell den Faden.
    content_blocks: tuple[dict[str, Any], ...] = ()


def prompt_hash(system: str, messages: Iterable[LLMMessage]) -> str:
    """Kurzer Fingerabdruck des Prompts fuer das Aufruf-Log (0.6).

    Der Prompt selbst wird **nicht** gespeichert - er kann Privates enthalten
    und hat im Kostenprotokoll nichts verloren. Der Hash reicht, um zwei
    Aufrufe als denselben Prompt zu erkennen.
    """
    payload = json.dumps(
        {"system": system, "messages": [[m.role, m.content] for m in messages]},
        ensure_ascii=False,
        sort_keys=True,
        default=str,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


class LLMError(RuntimeError):
    """Fehler aus dem Modellaufruf, mit genug Information fuer eine ehrliche
    HTTP-Antwort - und ohne den API-Key darin."""

    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        kind: str = "api_error",
        retryable: bool = False,
        duration_ms: int = 0,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.kind = kind
        self.retryable = retryable
        self.duration_ms = duration_ms
        self.prompt_hash = ""


class LLMProvider(ABC):
    """Was der Rest des Programms von einem Anbieter erwartet."""

    name: str = "abstract"
    model: str = ""

    @abstractmethod
    async def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMReply: ...

    async def aclose(self) -> None:
        return None


# --- Fake -----------------------------------------------------------------


@dataclass
class FakeTurn:
    """Ein geskripteter Zug des Fake-Anbieters.

    Damit lassen sich Tool-Schleifen testen, ohne einen echten Aufruf zu
    bezahlen: erst ein Zug mit `tool_uses`, dann einer mit Text.
    """

    text: str = ""
    tool_uses: tuple[ToolUse, ...] = ()

    @property
    def stop_reason(self) -> str:
        return "tool_use" if self.tool_uses else "end_turn"


def _ist_planungsanfrage(system: str) -> bool:
    """Erkennt am Rollen-Marker, dass ein Plan verlangt wird.

    Bewusst kein Blick auf den Inhalt des Ziels: der Fake soll dumm bleiben.
    Er weiss, WER fragt, nicht WAS gefragt wird.
    """
    from core.planner import PLANNER_MARKER   # spaet: planner importiert llm

    # Der Marker ist namensfrei und steht am Anfang; der Name des
    # Assistenten kommt erst danach.
    return system.startswith(PLANNER_MARKER)


def _fake_plan(history: list[LLMMessage]) -> str:
    """Ein Plan mit genau einem Schritt: dem Ziel selbst, ohne Agenten.

    Das JSON entsteht aus dem Pydantic-Modell des Planners, nicht aus einer
    abgetippten Beispielzeile. Aendert sich das Schema, aendert sich diese
    Antwort mit - oder der Import bricht, was ebenfalls auffaellt.
    """
    from core.planner import ZIEL_PRAEFIX, Plan, PlanStep

    erste_frage = next(
        (m.content for m in history
         if m.role == "user" and isinstance(m.content, str)),
        "",
    )
    ziel = erste_frage
    if ziel.startswith(ZIEL_PRAEFIX):
        ziel = ziel[len(ZIEL_PRAEFIX):]
    ziel = ziel.strip()

    feld = PlanStep.model_fields["description"]
    grenzen = {art.__class__.__name__: art for art in feld.metadata}
    hoechstens = getattr(grenzen.get("MaxLen"), "max_length", 500)
    if len(ziel) > hoechstens:
        ziel = ziel[:hoechstens]
    if not ziel:
        # min_length=1: ein leeres Ziel wuerde das Schema verletzen. Dann
        # lieber ehrlich benennen, dass nichts ankam.
        ziel = "(kein Ziel uebermittelt)"

    return Plan(steps=[PlanStep(description=ziel, agent=None)]).model_dump_json()


class FakeLLMProvider(LLMProvider):
    """Deterministischer Anbieter ohne Netz.

    Ohne `replies` antwortet er mit einem festen Muster, das die letzte
    Nutzernachricht enthaelt. Mit `replies` gibt er die Liste der Reihe nach
    aus und wiederholt danach den letzten Eintrag.

    `calls` protokolliert jeden Aufruf - Tests pruefen damit, was das Backend
    tatsaechlich hochgeschickt haette.
    """

    name = "fake"

    def __init__(
        self,
        replies: Iterable[str | FakeTurn] | None = None,
        model: str = "fake-echo-1",
    ) -> None:
        self._replies: list[str | FakeTurn] = list(replies) if replies is not None else []
        self.model = model
        self.calls: list[dict[str, Any]] = []

    async def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMReply:
        history = list(messages)
        self.calls.append({"system": system, "messages": history, "tools": tools})

        tool_uses: tuple[ToolUse, ...] = ()
        if self._replies:
            zug = self._replies.pop(0) if len(self._replies) > 1 else self._replies[0]
            if isinstance(zug, FakeTurn):
                text, tool_uses = zug.text, zug.tool_uses
            else:
                text = zug
        elif _ist_planungsanfrage(system):
            text = _fake_plan(history)
        else:
            last_user = next(
                (m.content for m in reversed(history)
                 if m.role == "user" and isinstance(m.content, str)),
                "",
            )
            text = (
                f"[fake] Ich habe {len(history)} Nachricht(en) im Kontext. "
                f'Zuletzt sagtest du: "{last_user}"'
            )

        # Kein echtes Tokenizing - das waere geraten. Woerter sind als Zahl
        # ehrlicher, weil offensichtlich ist, dass sie nicht stimmen.
        bloecke: list[dict[str, Any]] = []
        if text:
            bloecke.append({"type": "text", "text": text})
        bloecke.extend(
            {"type": "tool_use", "id": t.id, "name": t.name, "input": t.input}
            for t in tool_uses
        )

        return LLMReply(
            text=text,
            model=self.model,
            usage=LLMUsage(
                in_tokens=sum(
                    len(m.content.split()) if isinstance(m.content, str) else 8
                    for m in history
                )
                + len(system.split()),
                out_tokens=len(text.split()) + 8 * len(tool_uses),
            ),
            duration_ms=0,
            stop_reason="tool_use" if tool_uses else "end_turn",
            prompt_hash=prompt_hash(system, history),
            tool_uses=tool_uses,
            content_blocks=tuple(bloecke),
        )


# --- Anthropic ------------------------------------------------------------


class _HTTPAnbieter(LLMProvider):
    """Was jeder Anbieter ueber HTTP gleich macht.

    Wiederholung, Retry-After, Fehlertexte und das Schliessen des Klienten
    haengen nicht am Format der Anfrage, sondern am Protokoll. Sie stehen
    deshalb hier und nicht zweimal darunter.

    `transport` existiert fuer Tests: ein `httpx.MockTransport` laesst die
    Anfrage vollstaendig pruefen, ohne dass ein Byte das Geraet verlaesst.
    """

    def __init__(
        self,
        *,
        model: str,
        max_tokens: int,
        base_url: str,
        timeout: float,
        max_retries: int,
        headers: dict[str, str],
        transport: httpx.AsyncBaseTransport | None = None,
        sleep: Callable[[float], Awaitable[None]] | None = None,
    ) -> None:
        self.model = model
        self.max_tokens = max_tokens
        self.max_retries = max_retries
        self._sleep = sleep or asyncio.sleep
        self._client = httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            transport=transport,
            headers=headers,
        )

    @staticmethod
    def _pflichtfelder(api_key: str, model: str) -> None:
        if not api_key:
            raise LLMError(
                "Kein LLM_API_KEY gesetzt. Trag ihn in die .env ein - "
                "ohne Key kann JARVIS kein echtes Modell fragen.",
                kind="missing_api_key",
            )
        if not model:
            raise LLMError(
                "Kein LLM_MODEL gesetzt. Die Modell-ID gehoert in die .env und "
                "wird aus der Doku des Anbieters uebernommen, nicht geraten.",
                kind="missing_model",
            )

    async def _post_with_retries(
        self, url: str, body: dict[str, Any]
    ) -> httpx.Response:
        last_error: LLMError | None = None
        for attempt in range(self.max_retries + 1):
            failed_response: httpx.Response | None = None
            try:
                response = await self._client.post(url, json=body)
            except httpx.TimeoutException as exc:
                last_error = LLMError(
                    f"Zeitueberschreitung beim Modellaufruf: {exc}",
                    kind="timeout",
                    retryable=True,
                )
            except httpx.HTTPError as exc:
                # Der Text einer httpx-Ausnahme enthaelt die URL, aber keine
                # Header - der Key kann hier nicht durchsickern.
                last_error = LLMError(
                    f"Verbindung zum Modellanbieter fehlgeschlagen: {exc}",
                    kind="connection",
                    retryable=True,
                )
            else:
                if response.status_code < 400:
                    return response
                last_error = self._error_from(response)
                if not last_error.retryable:
                    raise last_error
                failed_response = response

            # Nur warten, wenn danach wirklich noch ein Versuch kommt. Sonst
            # verschenkt der letzte Fehlschlag ein volles Retry-After.
            if attempt < self.max_retries:
                await self._sleep(self._delay(attempt, failed_response))

        assert last_error is not None
        raise last_error

    def _delay(self, attempt: int, response: httpx.Response | None) -> float:
        if response is not None:
            header = response.headers.get("retry-after")
            if header:
                try:
                    return max(0.0, min(60.0, float(header)))
                except ValueError:
                    pass
        return float(2**attempt)

    def _error_from(self, response: httpx.Response) -> LLMError:
        status = response.status_code
        detail = ""
        try:
            payload = response.json()
            if isinstance(payload, dict):
                detail = str(payload.get("error", {}).get("message", "")).strip()
        except ValueError:
            detail = response.text[:300].strip()

        readable = {
            400: "Der Anbieter hat die Anfrage abgelehnt (400).",
            401: "Der API-Key wurde nicht akzeptiert (401). Stimmt LLM_API_KEY?",
            403: "Der API-Key darf dieses Modell nicht benutzen (403).",
            404: f"Modell oder Endpunkt unbekannt (404). LLM_MODEL: {self.model!r}.",
            413: "Die Anfrage ist zu gross (413). Kuerze den Verlauf.",
            429: "Ratenlimit erreicht (429).",
            500: "Der Anbieter hat einen internen Fehler gemeldet (500).",
            529: "Der Anbieter ist ueberlastet (529).",
        }.get(status, f"Der Modellaufruf ist mit HTTP {status} fehlgeschlagen.")

        return LLMError(
            f"{readable} {detail}".strip(),
            status=status,
            kind="api_error",
            retryable=status in RETRYABLE_STATUS,
        )

    async def aclose(self) -> None:
        await self._client.aclose()


class AnthropicProvider(_HTTPAnbieter):
    """Spricht mit der Messages-API."""

    name = "anthropic"

    def __init__(
        self,
        api_key: str,
        *,
        model: str,
        max_tokens: int = 4096,
        base_url: str = "https://api.anthropic.com",
        timeout: float = 60.0,
        max_retries: int = 2,
        transport: httpx.AsyncBaseTransport | None = None,
        sleep: Callable[[float], Awaitable[None]] | None = None,
    ) -> None:
        self._pflichtfelder(api_key, model)
        super().__init__(
            model=model,
            max_tokens=max_tokens,
            base_url=base_url,
            timeout=timeout,
            max_retries=max_retries,
            transport=transport,
            sleep=sleep,
            headers={
                "content-type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": ANTHROPIC_VERSION,
            },
        )

    def _body(
        self,
        messages: list[LLMMessage],
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "system": system,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
        }
        if tools:
            body["tools"] = tools
        return body

    async def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMReply:
        history = list(messages)
        if not history:
            raise LLMError("Leere Nachrichtenliste.", kind="invalid_request")
        if history[0].role != "user":
            raise LLMError(
                "Die erste Nachricht muss von 'user' sein.", kind="invalid_request"
            )

        fingerabdruck = prompt_hash(system, history)
        begonnen = time.monotonic()
        try:
            response = await self._post_with_retries(
                "/v1/messages", self._body(history, system, tools)
            )
        except LLMError as exc:
            exc.duration_ms = int((time.monotonic() - begonnen) * 1000)
            exc.prompt_hash = fingerabdruck
            raise
        return self._parse(
            response, int((time.monotonic() - begonnen) * 1000), fingerabdruck
        )

    def _parse(
        self, response: httpx.Response, duration_ms: int, fingerabdruck: str
    ) -> LLMReply:
        try:
            payload = response.json()
        except ValueError as exc:
            raise LLMError(
                f"Antwort des Anbieters war kein JSON: {exc}",
                kind="bad_response",
                duration_ms=duration_ms,
            ) from exc

        stop_reason = payload.get("stop_reason")
        if stop_reason == "refusal":
            # stop_details ist laut Doku nur bei genau diesem stop_reason gefuellt.
            details = payload.get("stop_details") or {}
            raise LLMError(
                f"Das Modell hat die Anfrage abgelehnt "
                f"({details.get('category') or 'ohne Kategorie'}).",
                kind="refusal",
                duration_ms=duration_ms,
            )

        blocks = [b for b in (payload.get("content") or []) if isinstance(b, dict)]
        # Nur Textbloecke in den Text. Denk-Bloecke kommen mit leerem Text und
        # haben in der Konversation nichts verloren.
        text = "".join(
            block.get("text", "") for block in blocks if block.get("type") == "text"
        ).strip()

        tool_uses = tuple(
            ToolUse(
                id=str(block.get("id", "")),
                name=str(block.get("name", "")),
                input=block.get("input") or {},
            )
            for block in blocks
            if block.get("type") == "tool_use"
        )

        # Bei stop_reason "tool_use" ist ein leerer Text normal - das Modell
        # ruft erst ein Werkzeug und redet danach.
        if not text and not tool_uses:
            raise LLMError(
                f"Die Antwort enthielt keinen Text (stop_reason={stop_reason!r}).",
                kind="empty_response",
                duration_ms=duration_ms,
            )

        usage = payload.get("usage") or {}
        return LLMReply(
            text=text,
            model=payload.get("model", self.model),
            usage=LLMUsage(
                in_tokens=int(usage.get("input_tokens", 0)),
                out_tokens=int(usage.get("output_tokens", 0)),
            ),
            duration_ms=duration_ms,
            stop_reason=stop_reason,
            prompt_hash=fingerabdruck,
            tool_uses=tool_uses,
            content_blocks=tuple(blocks),
        )


class GroqProvider(_HTTPAnbieter):
    """Spricht das OpenAI-Format, das Groq unter /openai/v1 anbietet.

    Warum es diesen Anbieter gibt: Groq hat eine kostenlose Stufe, trainiert
    laut Services Agreement 4.2 nicht auf Eingaben und Ausgaben und hat eine
    eigene Vertragspartei fuer den EWR. Damit kann JARVIS mit echten
    Werkzeugaufrufen laufen, ohne dass Geld fliesst.

    **Nach innen spricht auch dieser Anbieter Anthropic.** `content_blocks`
    kommen als `text`- und `tool_use`-Bloecke zurueck, und `tool_result`
    versteht er in derselben Form, in der `core/tools/loop.py` sie baut.
    Uebersetzt wird ausschliesslich an der Leitung. So merken `loop.py`,
    `agents.py` und `runner.py` von einem zweiten Anbieter nichts - genau
    das ist der Punkt, an dem ein zweiter Anbieter sonst durchs ganze
    Programm sickert.

    Die Form stammt aus console.groq.com/docs/api-reference und /docs/tool-use,
    nicht aus dem Gedaechtnis. Drei Unterschiede zu Anthropic, die man beim
    Abschreiben aus dem Kopf falsch macht:

      * `Authorization: Bearer <key>`, nicht `x-api-key`
      * `max_completion_tokens`, nicht `max_tokens`
      * `arguments` ist ein **JSON-String**, kein Objekt
    """

    name = "groq"
    PFAD = "/openai/v1/chat/completions"

    def __init__(
        self,
        api_key: str,
        *,
        model: str,
        max_tokens: int = 4096,
        base_url: str = GROQ_BASIS,
        timeout: float = 60.0,
        max_retries: int = 2,
        transport: httpx.AsyncBaseTransport | None = None,
        sleep: Callable[[float], Awaitable[None]] | None = None,
    ) -> None:
        self._pflichtfelder(api_key, model)
        super().__init__(
            model=model,
            max_tokens=max_tokens,
            base_url=base_url,
            timeout=timeout,
            max_retries=max_retries,
            transport=transport,
            sleep=sleep,
            headers={
                "content-type": "application/json",
                "authorization": f"Bearer {api_key}",
            },
        )

    # --- hin: Anthropic-Form -> OpenAI-Form -------------------------------

    @staticmethod
    def _werkzeuge(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [
            {
                "type": "function",
                "function": {
                    "name": werkzeug["name"],
                    "description": werkzeug.get("description", ""),
                    "parameters": werkzeug.get("input_schema") or {},
                },
            }
            for werkzeug in tools
        ]

    @staticmethod
    def _als_text(inhalt: Any) -> str:
        return inhalt if isinstance(inhalt, str) else json.dumps(
            inhalt, ensure_ascii=False
        )

    def _nachrichten(
        self, verlauf: list[LLMMessage], system: str
    ) -> list[dict[str, Any]]:
        raus: list[dict[str, Any]] = []
        if system:
            raus.append({"role": "system", "content": system})

        # tool_result kennt nur die id. Den Namen kennt nur der tool_use-Block
        # davor - deshalb im Vorbeigehen mitschreiben.
        namen: dict[str, str] = {}

        for nachricht in verlauf:
            if isinstance(nachricht.content, str):
                raus.append({"role": nachricht.role, "content": nachricht.content})
                continue

            bloecke = [b for b in nachricht.content if isinstance(b, dict)]
            text = "".join(
                b.get("text", "") for b in bloecke if b.get("type") == "text"
            )

            if nachricht.role == "assistant":
                aufrufe = []
                for block in bloecke:
                    if block.get("type") != "tool_use":
                        continue
                    kennung = str(block.get("id", ""))
                    name = str(block.get("name", ""))
                    namen[kennung] = name
                    aufrufe.append({
                        "id": kennung,
                        "type": "function",
                        "function": {
                            "name": name,
                            # JSON-String, kein Objekt. Wer hier das dict
                            # durchreicht, bekommt einen 400.
                            "arguments": json.dumps(
                                block.get("input") or {}, ensure_ascii=False
                            ),
                        },
                    })
                assistent: dict[str, Any] = {"role": "assistant", "content": text}
                if aufrufe:
                    assistent["tool_calls"] = aufrufe
                raus.append(assistent)
                continue

            # Nutzerzeile: die Werkzeugergebnisse werden zu eigenen
            # Nachrichten, ein uebriger Text bleibt eine Nutzernachricht.
            for block in bloecke:
                if block.get("type") != "tool_result":
                    continue
                inhalt = self._als_text(block.get("content", ""))
                if block.get("is_error"):
                    # OpenAI-Form kennt kein is_error. Ohne diesen Zusatz
                    # haelt das Modell einen Fehlschlag fuer ein Ergebnis.
                    inhalt = f"FEHLER: {inhalt}"
                werkzeug: dict[str, Any] = {
                    "role": "tool",
                    "tool_call_id": str(block.get("tool_use_id", "")),
                    "content": inhalt,
                }
                name = namen.get(str(block.get("tool_use_id", "")))
                if name:
                    werkzeug["name"] = name
                raus.append(werkzeug)
            if text:
                raus.append({"role": "user", "content": text})

        return raus

    def _body(
        self,
        verlauf: list[LLMMessage],
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "model": self.model,
            "messages": self._nachrichten(verlauf, system),
            "max_completion_tokens": self.max_tokens,
        }
        # Ein leeres tools: [] ist bei manchen Anbietern ein 400. Weglassen.
        if tools:
            body["tools"] = self._werkzeuge(tools)
        return body

    async def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMReply:
        history = list(messages)
        if not history:
            raise LLMError("Leere Nachrichtenliste.", kind="invalid_request")
        # Das OpenAI-Format erlaubt hier mehr als Anthropic. Die Pruefung
        # bleibt trotzdem: BUGS-01 Fund 23 wird oben in
        # `ab_erster_nutzernachricht` geschnitten, und eine Assistentenantwort
        # ohne die Frage davor ist auch hier Kontext ohne Anker.
        if history[0].role != "user":
            raise LLMError(
                "Die erste Nachricht muss von 'user' sein.", kind="invalid_request"
            )

        fingerabdruck = prompt_hash(system, history)
        begonnen = time.monotonic()
        try:
            response = await self._post_with_retries(
                self.PFAD, self._body(history, system, tools)
            )
        except LLMError as exc:
            exc.duration_ms = int((time.monotonic() - begonnen) * 1000)
            exc.prompt_hash = fingerabdruck
            raise
        return self._parse(
            response, int((time.monotonic() - begonnen) * 1000), fingerabdruck
        )

    # --- zurueck: OpenAI-Form -> Anthropic-Form ---------------------------

    def _parse(
        self, response: httpx.Response, duration_ms: int, fingerabdruck: str
    ) -> LLMReply:
        try:
            payload = response.json()
        except ValueError as exc:
            raise LLMError(
                f"Antwort des Anbieters war kein JSON: {exc}",
                kind="bad_response",
                duration_ms=duration_ms,
            ) from exc

        auswahl = payload.get("choices") or []
        if not auswahl or not isinstance(auswahl[0], dict):
            raise LLMError(
                "Die Antwort enthielt kein 'choices'.",
                kind="bad_response",
                duration_ms=duration_ms,
            )
        nachricht = auswahl[0].get("message") or {}
        stop_reason = auswahl[0].get("finish_reason")

        text = (nachricht.get("content") or "").strip()
        bloecke: list[dict[str, Any]] = []
        if text:
            bloecke.append({"type": "text", "text": text})

        tool_uses: list[ToolUse] = []
        for aufruf in nachricht.get("tool_calls") or []:
            funktion = aufruf.get("function") or {}
            name = str(funktion.get("name", ""))
            roh = funktion.get("arguments")
            if isinstance(roh, str):
                try:
                    eingabe = json.loads(roh or "{}")
                except ValueError as exc:
                    raise LLMError(
                        f"Das Modell hat fuer {name!r} Argumente geschickt, die "
                        f"kein JSON sind: {exc}",
                        kind="bad_response",
                        duration_ms=duration_ms,
                    ) from exc
            else:
                eingabe = roh
            if not isinstance(eingabe, dict):
                raise LLMError(
                    f"Die Argumente fuer {name!r} sind kein Objekt, sondern "
                    f"{type(eingabe).__name__}.",
                    kind="bad_response",
                    duration_ms=duration_ms,
                )
            kennung = str(aufruf.get("id", ""))
            tool_uses.append(ToolUse(id=kennung, name=name, input=eingabe))
            bloecke.append({
                "type": "tool_use", "id": kennung, "name": name, "input": eingabe,
            })

        if not text and not tool_uses:
            raise LLMError(
                f"Die Antwort enthielt keinen Text (finish_reason={stop_reason!r}).",
                kind="empty_response",
                duration_ms=duration_ms,
            )

        usage = payload.get("usage") or {}
        return LLMReply(
            text=text,
            model=payload.get("model", self.model),
            usage=LLMUsage(
                # OpenAI-Namen, nicht input_tokens/output_tokens.
                in_tokens=int(usage.get("prompt_tokens", 0)),
                out_tokens=int(usage.get("completion_tokens", 0)),
            ),
            duration_ms=duration_ms,
            stop_reason=stop_reason,
            prompt_hash=fingerabdruck,
            tool_uses=tuple(tool_uses),
            content_blocks=tuple(bloecke),
        )


# Zwei echte Anbieter. `groq` kam dazu, weil er eine kostenlose Stufe hat und
# laut Services Agreement 4.2 nicht auf Eingaben trainiert - damit laeuft
# JARVIS mit echten Werkzeugaufrufen, ohne dass Geld fliesst.
PROVIDERS: dict[str, type[LLMProvider]] = {
    "anthropic": AnthropicProvider,
    "groq": GroqProvider,
}


def build_provider(settings: Any) -> LLMProvider:
    """Baut den in `.env` eingestellten Anbieter.

    Ohne `LLM_PROVIDER` laeuft der Fake - so startet JARVIS auch ohne Konto,
    und man sieht die Oberflaeche, bevor man Geld ausgibt.

    Hier stand bis zum zweiten Anbieter `return AnthropicProvider(...)` fest
    verdrahtet - der Blick in PROVIDERS war Zierde. Solange es genau einen
    Eintrag gab, fiel das nicht auf; der zweite waere still als Anthropic
    gelaufen und haette mit einem gsk-Key ein 401 von api.anthropic.com
    bekommen. `test_build_provider_baut_wirklich_groq` haelt das fest.
    """
    key = (settings.llm_provider or "").strip().lower()
    if key in ("", "fake"):
        return FakeLLMProvider()
    if key not in PROVIDERS:
        raise LLMError(
            f"Unbekannter LLM_PROVIDER {settings.llm_provider!r}. "
            f"Bekannt sind: {', '.join(sorted([*PROVIDERS, 'fake']))}.",
            kind="unknown_provider",
        )
    return PROVIDERS[key](
        settings.llm_api_key,
        model=settings.llm_model,
        max_tokens=settings.llm_max_tokens,
        timeout=settings.llm_timeout_seconds,
        max_retries=settings.llm_max_retries,
    )
