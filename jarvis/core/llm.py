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

# Wiederholbar laut Fehlertabelle des Anbieters. Alles andere ist ein Fehler
# in der Anfrage und wird durch Wiederholen nicht besser.
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 529})


@dataclass(frozen=True)
class ToolUse:
    """Ein Werkzeugaufruf, den das Modell vorschlaegt."""

    id: str
    name: str
    input: dict[str, Any]


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


class AnthropicProvider(LLMProvider):
    """Spricht mit der Messages-API.

    `transport` existiert fuer Tests: ein `httpx.MockTransport` laesst die
    Anfrage vollstaendig pruefen, ohne dass ein Byte das Geraet verlaesst.
    """

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
        self.model = model
        self.max_tokens = max_tokens
        self.max_retries = max_retries
        self._sleep = sleep or asyncio.sleep
        self._client = httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            transport=transport,
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

    async def aclose(self) -> None:
        await self._client.aclose()


# Genau ein echter Anbieter in Phase 1. Ein weiterer kommt hier dazu, wenn er
# gebraucht wird - nicht auf Verdacht.
PROVIDERS: dict[str, type[LLMProvider]] = {"anthropic": AnthropicProvider}


def build_provider(settings: Any) -> LLMProvider:
    """Baut den in `.env` eingestellten Anbieter.

    Ohne `LLM_PROVIDER` laeuft der Fake - so startet JARVIS auch ohne Konto,
    und man sieht die Oberflaeche, bevor man Geld ausgibt.
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
    return AnthropicProvider(
        settings.llm_api_key,
        model=settings.llm_model,
        max_tokens=settings.llm_max_tokens,
        timeout=settings.llm_timeout_seconds,
        max_retries=settings.llm_max_retries,
    )
