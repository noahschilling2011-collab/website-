"""Modellanbindung.

Ein Protokoll, zwei Implementierungen. Der Rest des Programms kennt nur das
Protokoll und weiss nicht, ob gerade ein echtes Modell antwortet.

`FakeLLMProvider` geht nicht ins Netz und kostet nichts. Tests laufen
ausschliesslich dagegen.

`AnthropicProvider` spricht per httpx mit `POST /v1/messages`. Header, Body
und Fehlerformen folgen der Anbieter-Dokumentation - nichts davon ist
geraten. Ausdruecklich *nicht* gesendet werden `temperature`, `top_p`,
`top_k` und `thinking.budget_tokens`: auf den aktuellen Opus-Modellen ist
jedes davon ein 400.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, Literal, Protocol

import httpx

ANTHROPIC_VERSION = "2023-06-01"

# Wiederholbar laut Fehlertabelle des Anbieters. Alles andere ist ein Fehler
# in der Anfrage und wird durch Wiederholen nicht besser.
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 529})

Role = Literal["user", "assistant"]


@dataclass(frozen=True)
class LLMMessage:
    role: Role
    content: str


@dataclass(frozen=True)
class LLMUsage:
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_input_tokens: int = 0
    cache_creation_input_tokens: int = 0


@dataclass(frozen=True)
class LLMReply:
    text: str
    model: str
    stop_reason: str | None = None
    usage: LLMUsage = field(default_factory=LLMUsage)


class LLMError(RuntimeError):
    """Ein Fehler, der aus dem Modellaufruf kommt.

    Traegt genug Information, damit die HTTP-Schicht daraus eine ehrliche
    Meldung machen kann - und keinen Stacktrace.
    """

    def __init__(
        self,
        message: str,
        *,
        status: int | None = None,
        kind: str = "api_error",
        retryable: bool = False,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.kind = kind
        self.retryable = retryable


class LLMProvider(Protocol):
    """Was der Rest des Programms von einem Anbieter erwartet."""

    name: str
    model: str

    def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        max_tokens: int | None = None,
    ) -> LLMReply: ...

    def close(self) -> None: ...


# --- Fake -----------------------------------------------------------------


class FakeLLMProvider:
    """Deterministischer Anbieter ohne Netz.

    Zwei Betriebsarten:

    * ohne `replies`: antwortet mit einem festen Muster, das die letzte
      Nutzernachricht enthaelt. Gleiche Eingabe, gleiche Ausgabe.
    * mit `replies`: gibt die Liste der Reihe nach aus. Ist sie leer, wird
      der letzte Eintrag wiederholt.

    `calls` protokolliert jeden Aufruf. Tests pruefen damit, was das Backend
    tatsaechlich hochgeschickt haette.
    """

    name = "fake"

    def __init__(
        self, replies: Iterable[str] | None = None, model: str = "fake-echo-1"
    ) -> None:
        self._replies: list[str] = list(replies) if replies is not None else []
        self.model = model
        self.calls: list[dict[str, Any]] = []

    def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        max_tokens: int | None = None,
    ) -> LLMReply:
        history = list(messages)
        self.calls.append(
            {"system": system, "messages": history, "max_tokens": max_tokens}
        )

        if self._replies:
            text = self._replies.pop(0) if len(self._replies) > 1 else self._replies[0]
        else:
            last_user = next(
                (m.content for m in reversed(history) if m.role == "user"), ""
            )
            text = (
                f"[fake] Ich habe {len(history)} Nachricht(en) im Kontext. "
                f'Zuletzt sagtest du: "{last_user}"'
            )

        # Kein echtes Tokenizing - das waere geraten. Woerter sind als Zahl
        # ehrlicher, weil offensichtlich ist, dass sie nicht stimmen.
        return LLMReply(
            text=text,
            model=self.model,
            stop_reason="end_turn",
            usage=LLMUsage(
                input_tokens=sum(len(m.content.split()) for m in history)
                + len(system.split()),
                output_tokens=len(text.split()),
            ),
        )

    def close(self) -> None:  # nichts zu schliessen
        return None


# --- Anthropic ------------------------------------------------------------


class AnthropicProvider:
    """Spricht mit der Messages-API.

    `transport` existiert fuer Tests: ein `httpx.MockTransport` laesst die
    Anfrage komplett pruefen, ohne dass ein Byte das Geraet verlaesst.
    """

    name = "anthropic"

    def __init__(
        self,
        api_key: str,
        *,
        model: str,
        max_tokens: int = 16000,
        effort: str = "high",
        base_url: str = "https://api.anthropic.com",
        timeout: float = 120.0,
        max_retries: int = 2,
        transport: httpx.BaseTransport | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if not api_key:
            raise LLMError(
                "Kein API-Key gesetzt. Trag ANTHROPIC_API_KEY in die .env ein "
                "oder stell JARVIS_PROVIDER auf 'fake'.",
                kind="missing_api_key",
            )
        self.model = model
        self.max_tokens = max_tokens
        self.effort = effort
        self.max_retries = max_retries
        self._sleep = sleep
        self._client = httpx.Client(
            base_url=base_url,
            timeout=timeout,
            transport=transport,
            headers={
                "content-type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": ANTHROPIC_VERSION,
            },
        )

    # -- Anfrage

    def _body(
        self, messages: list[LLMMessage], system: str, max_tokens: int
    ) -> dict[str, Any]:
        return {
            "model": self.model,
            "max_tokens": max_tokens,
            "system": system,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "output_config": {"effort": self.effort},
        }

    def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        max_tokens: int | None = None,
    ) -> LLMReply:
        history = list(messages)
        if not history:
            raise LLMError("Leere Nachrichtenliste.", kind="invalid_request")
        if history[0].role != "user":
            raise LLMError(
                "Die erste Nachricht muss von 'user' sein.", kind="invalid_request"
            )

        body = self._body(history, system, max_tokens or self.max_tokens)
        response = self._post_with_retries("/v1/messages", body)
        return self._parse(response)

    def _post_with_retries(self, url: str, body: dict[str, Any]) -> httpx.Response:
        last_error: LLMError | None = None
        for attempt in range(self.max_retries + 1):
            failed_response: httpx.Response | None = None
            try:
                response = self._client.post(url, json=body)
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
                self._sleep(self._delay(attempt, failed_response))

        assert last_error is not None
        raise last_error

    def _delay(self, attempt: int, response: httpx.Response | None) -> float:
        """Wartezeit vor dem naechsten Versuch. Retry-After schlaegt alles."""
        if response is not None:
            header = response.headers.get("retry-after")
            if header:
                try:
                    return max(0.0, min(60.0, float(header)))
                except ValueError:
                    pass
        return float(2**attempt)

    # -- Antwort

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
            401: "Der API-Key wurde nicht akzeptiert (401). Stimmt ANTHROPIC_API_KEY?",
            403: "Der API-Key darf dieses Modell nicht benutzen (403).",
            404: f"Modell oder Endpunkt unbekannt (404). Modell-ID: {self.model!r}.",
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

    def _parse(self, response: httpx.Response) -> LLMReply:
        try:
            payload = response.json()
        except ValueError as exc:
            raise LLMError(
                f"Antwort des Anbieters war kein JSON: {exc}", kind="bad_response"
            ) from exc

        stop_reason = payload.get("stop_reason")
        if stop_reason == "refusal":
            # stop_details ist laut Dokumentation nur bei genau diesem
            # stop_reason gefuellt.
            details = payload.get("stop_details") or {}
            category = details.get("category") or "ohne Kategorie"
            raise LLMError(
                f"Das Modell hat die Anfrage abgelehnt ({category}).",
                kind="refusal",
            )

        blocks = payload.get("content") or []
        # Nur Textbloecke. Denk-Bloecke kommen bei den aktuellen Modellen mit
        # leerem Text und haben in der Konversation nichts verloren.
        text = "".join(
            block.get("text", "")
            for block in blocks
            if isinstance(block, dict) and block.get("type") == "text"
        ).strip()

        if not text:
            raise LLMError(
                f"Die Antwort enthielt keinen Text (stop_reason={stop_reason!r}).",
                kind="empty_response",
            )

        usage = payload.get("usage") or {}
        return LLMReply(
            text=text,
            model=payload.get("model", self.model),
            stop_reason=stop_reason,
            usage=LLMUsage(
                input_tokens=int(usage.get("input_tokens", 0)),
                output_tokens=int(usage.get("output_tokens", 0)),
                cache_read_input_tokens=int(usage.get("cache_read_input_tokens", 0)),
                cache_creation_input_tokens=int(
                    usage.get("cache_creation_input_tokens", 0)
                ),
            ),
        )

    def close(self) -> None:
        self._client.close()


class UnavailableProvider:
    """Platzhalter, wenn der konfigurierte Anbieter nicht gebaut werden konnte.

    Existiert, damit die App trotzdem startet. Ein fehlender API-Key ist ein
    Einrichtungsfehler - der Nutzer soll die Oberflaeche oeffnen und dort
    lesen koennen, was fehlt, statt einen Stacktrace im Terminal zu bekommen.
    """

    def __init__(self, error: LLMError, *, name: str, model: str) -> None:
        self.error = error
        self.name = name
        self.model = model

    @property
    def reason(self) -> str:
        return str(self.error)

    def complete(
        self,
        messages: Iterable[LLMMessage],
        *,
        system: str,
        max_tokens: int | None = None,
    ) -> LLMReply:
        raise self.error

    def close(self) -> None:
        return None


def build_provider(settings: Any) -> LLMProvider:
    """Baut den in der Konfiguration eingestellten Anbieter."""
    if settings.provider == "anthropic":
        return AnthropicProvider(
            settings.anthropic_api_key,
            model=settings.model,
            max_tokens=settings.max_tokens,
            effort=settings.effort,
            base_url=settings.anthropic_base_url,
            timeout=settings.request_timeout_seconds,
            max_retries=settings.max_retries,
        )
    return FakeLLMProvider()
