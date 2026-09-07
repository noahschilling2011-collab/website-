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
import logging
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Iterable

import httpx

from core.netz import GEHEIME_KOEPFE

log = logging.getLogger("jarvis")

ANTHROPIC_VERSION = "2023-06-01"
# Groq spricht das OpenAI-Format unter einem eigenen Praefix.
# console.groq.com/docs/api-reference: POST /openai/v1/chat/completions
GROQ_BASIS = "https://api.groq.com"

# Wiederholbar laut Fehlertabelle des Anbieters. Alles andere ist ein Fehler
# in der Anfrage und wird durch Wiederholen nicht besser.
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 529})

# Deckel fuer den Antwortrumpf. Ein Zug mit `max_tokens=4096` sind rund 16 KB
# Text, selbst 100.000 Token blieben unter 500 KB. Was darueber liegt, ist
# kaputt oder boesartig - und wanderte ungebremst in `text`, von dort in die
# Datenbank, in den naechsten Prompt und damit zurueck zum Anbieter. Gleiche
# Groessenordnung wie `core/tools/search.FetchUrl.MAX_BYTES` fuer fremde
# Seiten: was von aussen kommt, hat eine Obergrenze.
MAX_ANTWORT_BYTES = 2_000_000

# Wieviel vom zitierten Fehlertext des Anbieters in die Meldung darf. Der
# Nicht-JSON-Zweig in `_error_from` kappte laengst bei 300 Zeichen, der
# JSON-Zweig gar nicht: ein Gateway mit 3 MB in `error.message` schickte
# 3 MB durch `str(exc)` in den Chat, in `tasks.result`, in die Datenbank und
# im naechsten Zug als Verlauf zurueck zum Anbieter. Derselbe Weg, den
# MAX_ANTWORT_BYTES fuer die geglueckte Antwort schliesst.
MAX_FEHLERTEXT_ZEICHEN = 300


def _zahl(wert: Any) -> int:
    """Eine Tokenzahl aus der Antwort - oder 0, wenn dort Unsinn steht.

    `int(None)` und `int("viel")` werfen. Vorher schlug dieser Wurf durch
    `complete()` hindurch bis in den Aufrufer: ein `usage`-Feld mit `null`
    riss den ganzen Zug ab, obwohl der Text schon da war. Eine kaputte
    Zaehlung ist kein Grund, eine fertige Antwort wegzuwerfen - sie wird wie
    ein fehlendes Feld behandelt (0) und im Serverlog vermerkt.
    """
    try:
        return int(wert)
    except (TypeError, ValueError):
        # Nur der Typ, nicht der Wert: der Wert kommt vom Anbieter.
        log.warning("Tokenzahl des Anbieters unbrauchbar (%s) - als 0 gezaehlt",
                    type(wert).__name__)
        return 0


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

    Ein Eintrag darf auch ein `LLMError` sein - dann wirft dieser Zug, statt
    zu antworten (FIX-12). Damit laesst sich ein Ausfall des Anbieters bis in
    `api/tasks.py` durchspielen, ohne HTTP nachzubauen. Der Aufruf steht
    trotzdem in `calls`: ein verschluckter Aufruf waere eine Luege ueber das,
    was das Backend getan hat.

    `calls` protokolliert jeden Aufruf - Tests pruefen damit, was das Backend
    tatsaechlich hochgeschickt haette.
    """

    name = "fake"

    def __init__(
        self,
        replies: Iterable[str | FakeTurn | LLMError] | None = None,
        model: str = "fake-echo-1",
    ) -> None:
        self._replies: list[str | FakeTurn | LLMError] = (
            list(replies) if replies is not None else []
        )
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
            if isinstance(zug, LLMError):
                raise zug
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
        # Negativ waere `range(0)`: die Schleife unten liefe kein einziges
        # Mal, und der `assert` am Ende flog als AssertionError durch jeden
        # Modellaufruf. Ein Tippfehler in der .env (LLM_MAX_RETRIES=-1) darf
        # kein Absturz sein - er heisst "gar nicht wiederholen".
        self.max_retries = max(0, max_retries)
        self._sleep = sleep or asyncio.sleep
        # Was in den Kopfzeilen an Anmeldedaten steht, darf in keinem Text
        # wieder auftauchen - siehe `_ohne_key`. Laengste zuerst, damit das
        # Ersetzen keine Reste stehen laesst.
        self._geheimnisse = tuple(sorted(
            {
                teil
                for name, wert in headers.items()
                if name.lower() in GEHEIME_KOEPFE
                for teil in (wert, wert.removeprefix("Bearer ").strip())
                if len(teil) >= 8
            },
            key=len,
            reverse=True,
        ))
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
                    f"Zeitueberschreitung beim Modellaufruf: "
                    f"{self._ohne_key(str(exc))}",
                    kind="timeout",
                    retryable=True,
                )
            except httpx.HTTPError as exc:
                # Der Text einer httpx-Ausnahme enthaelt die URL, aber keine
                # Header. `_ohne_key` steht trotzdem davor: ein Proxy-Fehler
                # kann die Anfrage zitieren, und diese Annahme haelt nur, bis
                # sie einmal nicht haelt.
                last_error = LLMError(
                    f"Verbindung zum Modellanbieter fehlgeschlagen: "
                    f"{self._ohne_key(str(exc))}",
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

        if last_error is None:  # pragma: no cover - nur ohne jeden Versuch
            # Frueher ein `assert`. Unter `python -O` faellt der weg, und
            # `raise None` waere ein TypeError statt einer Meldung.
            last_error = LLMError(
                "Der Modellaufruf wurde gar nicht erst versucht.",
                kind="connection",
                retryable=True,
            )
        raise last_error

    def _delay(self, attempt: int, response: httpx.Response | None) -> float:
        if response is not None:
            header = response.headers.get("retry-after")
            if header:
                try:
                    wert = float(header)
                except ValueError:
                    pass
                else:
                    # `float("nan")` wirft nicht, und jeder Vergleich damit
                    # ist False - `min(60.0, nan)` ergibt 60.0. Ein kaputter
                    # Kopf holte damit die laengstmoegliche Wartezeit heraus.
                    # `nan != nan` ist die Probe, die ohne Import auskommt.
                    if wert == wert:
                        return max(0.0, min(60.0, wert))
        return float(2**attempt)

    def _ohne_key(self, text: str) -> str:
        """Kein Anmeldedatum in einem Text, den Noah oder das Modell sieht.

        OpenAI-kompatible Dienste schicken den geschickten Key in der
        401-Meldung woertlich zurueck ("Incorrect API key provided: ..."), und
        ein Proxy davor zitiert im 500er gern die ganze Anfrage. Dieser Text
        geht von hier in den Chat, in `tasks.result`, in die Datenbank und im
        naechsten Zug als Verlauf zurueck zum Anbieter. Deshalb faellt der
        Key hier raus, bevor irgendjemand ihn zu sehen bekommt.
        """
        for geheim in self._geheimnisse:
            text = text.replace(geheim, "***")
        return text

    def _error_from(self, response: httpx.Response) -> LLMError:
        status = response.status_code
        detail = ""
        rumpf = response.content
        if len(rumpf) > MAX_ANTWORT_BYTES:
            # Nicht einmal lesen: ein Fehlerrumpf dieser Groesse ist selbst
            # der Fehler, und `json()` darauf kostet nur Speicher. Der Status
            # allein sagt genug.
            log.warning("Fehlerrumpf des Anbieters ist %d Bytes gross - "
                        "nicht ausgewertet", len(rumpf))
            payload = None
        else:
            try:
                payload = response.json()
            except ValueError:
                payload = None
                detail = response.text[:MAX_FEHLERTEXT_ZEICHEN].strip()
        if payload is not None:
            # `error` ist laut Doku ein Objekt mit `message` - aber ein
            # Gateway dazwischen haelt sich nicht an die Doku. Frueher rief
            # der Code `.get` auf allem, was dort stand: bei `"error": "text"`
            # schlug ein AttributeError durch, waehrend gerade ein Fehler
            # behandelt wurde.
            fehler = payload.get("error") if isinstance(payload, dict) else None
            if isinstance(fehler, dict):
                detail = str(fehler.get("message", "")).strip()
            elif isinstance(fehler, str):
                detail = fehler.strip()
        # Erst schwaerzen, dann kappen - umgekehrt bliebe ein halber Key
        # stehen, den `_ohne_key` nicht mehr wiedererkennt.
        detail = self._ohne_key(detail)[:MAX_FEHLERTEXT_ZEICHEN].strip()

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

    def _payload(self, response: httpx.Response, duration_ms: int) -> dict[str, Any]:
        """Der Rumpf als Objekt - oder ein sauberer Fehler statt eines Absturzes.

        Beide Anbieter brauchen dieselben drei Pruefungen, und beide hatten
        sie vorher nur halb: der Deckel fehlte ganz, und `payload.get(...)`
        lief auf allem, was `json()` zurueckgab - eine Liste oder eine
        Zeichenkette als Antwort war ein AttributeError, kein Fehlertext.
        """
        rumpf = response.content
        if len(rumpf) > MAX_ANTWORT_BYTES:
            raise LLMError(
                f"Die Antwort des Anbieters war unerwartet gross "
                f"({len(rumpf) // 1000} KB, mehr als {MAX_ANTWORT_BYTES // 1000} KB "
                f"nimmt JARVIS nicht an) und wurde verworfen.",
                kind="bad_response",
                duration_ms=duration_ms,
            )
        try:
            payload = response.json()
        except ValueError as exc:
            # Der Text von json enthaelt Zeile, Spalte und ein Stueck des
            # Rumpfs. Das ist Innenleben und gehoert ins Serverlog, nicht in
            # den Chat und schon gar nicht zurueck zum Anbieter.
            log.warning("Antwort des Anbieters war kein JSON: %s", exc)
            raise LLMError(
                "Die Antwort des Anbieters war kein JSON.",
                kind="bad_response",
                duration_ms=duration_ms,
            ) from exc
        if not isinstance(payload, dict):
            log.warning("Antwort des Anbieters ist ein %s statt eines Objekts",
                        type(payload).__name__)
            raise LLMError(
                "Die Antwort des Anbieters hatte nicht die erwartete Form.",
                kind="bad_response",
                duration_ms=duration_ms,
            )
        return payload

    @staticmethod
    def _tokens(payload: dict[str, Any], ein: str, aus: str) -> LLMUsage:
        """Die Tokenzahlen, egal was im `usage`-Feld steht.

        `usage` fehlt bei Groq manchmal ganz und ist bei einem kaputten
        Gateway auch mal eine Zeichenkette - beides darf den Zug nicht
        abreissen, denn die Antwort selbst ist da.
        """
        usage = payload.get("usage")
        if not isinstance(usage, dict):
            usage = {}
        return LLMUsage(
            in_tokens=_zahl(usage.get(ein, 0)),
            out_tokens=_zahl(usage.get(aus, 0)),
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
            return self._parse(
                response, int((time.monotonic() - begonnen) * 1000), fingerabdruck
            )
        except LLMError as exc:
            # Auch `_parse` liegt in diesem `try`: sonst trug ein Fehler aus
            # der Antwortform (kein JSON, leer, unbekannte Form) keinen
            # `prompt_hash`, und die Zeile, die `api/routes.py` mit
            # `ok=False` nach `llm_calls` schreibt, wusste nicht, zu welchem
            # Prompt sie gehoert.
            exc.duration_ms = int((time.monotonic() - begonnen) * 1000)
            exc.prompt_hash = fingerabdruck
            raise

    def _parse(
        self, response: httpx.Response, duration_ms: int, fingerabdruck: str
    ) -> LLMReply:
        payload = self._payload(response, duration_ms)

        stop_reason = payload.get("stop_reason")
        if stop_reason == "refusal":
            # stop_details ist laut Doku nur bei genau diesem stop_reason gefuellt.
            details = payload.get("stop_details")
            if not isinstance(details, dict):
                details = {}
            raise LLMError(
                f"Das Modell hat die Anfrage abgelehnt "
                f"({details.get('category') or 'ohne Kategorie'}).",
                kind="refusal",
                duration_ms=duration_ms,
            )

        blocks = [b for b in (payload.get("content") or []) if isinstance(b, dict)]
        # Nur Textbloecke in den Text. Denk-Bloecke kommen mit leerem Text und
        # haben in der Konversation nichts verloren.
        #
        # `isinstance` ist nicht Zierde: bei `{"type": "text", "text": 42}`
        # warf `"".join` einen rohen TypeError mitten durch `complete()` -
        # der Auftrag brach mit "Der Auftrag ist abgebrochen" ab, statt zu
        # sagen, was los war. Gleiche Regel wie im Groq-Zweig: was keine
        # Zeichenkette ist, ist kein Text.
        text = "".join(
            block["text"] for block in blocks
            if block.get("type") == "text" and isinstance(block.get("text"), str)
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

        return LLMReply(
            text=text,
            model=str(payload.get("model") or self.model),
            usage=self._tokens(payload, "input_tokens", "output_tokens"),
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
            return self._parse(
                response, int((time.monotonic() - begonnen) * 1000), fingerabdruck
            )
        except LLMError as exc:
            # Wie bei Anthropic: `_parse` gehoert mit in den Block, damit
            # auch ein Formfehler seinen `prompt_hash` fuer `llm_calls` hat.
            exc.duration_ms = int((time.monotonic() - begonnen) * 1000)
            exc.prompt_hash = fingerabdruck
            raise

    # --- zurueck: OpenAI-Form -> Anthropic-Form ---------------------------

    def _parse(
        self, response: httpx.Response, duration_ms: int, fingerabdruck: str
    ) -> LLMReply:
        payload = self._payload(response, duration_ms)

        auswahl = payload.get("choices")
        # `isinstance` zuerst: bei `"choices": {...}` war `auswahl[0]` frueher
        # ein KeyError, bei `"choices": "text"` ein Zeichen statt einer Wahl.
        if (not isinstance(auswahl, list) or not auswahl
                or not isinstance(auswahl[0], dict)):
            raise LLMError(
                "Die Antwort enthielt kein 'choices'.",
                kind="bad_response",
                duration_ms=duration_ms,
            )
        nachricht = auswahl[0].get("message")
        if not isinstance(nachricht, dict):
            nachricht = {}
        stop_reason = auswahl[0].get("finish_reason")

        roh_text = nachricht.get("content")
        text = roh_text.strip() if isinstance(roh_text, str) else ""
        bloecke: list[dict[str, Any]] = []
        if text:
            bloecke.append({"type": "text", "text": text})

        tool_uses: list[ToolUse] = []
        aufrufe = nachricht.get("tool_calls")
        if not isinstance(aufrufe, list):
            # Eine Zeichenkette waere frueher Zeichen fuer Zeichen
            # durchlaufen worden - und jedes Zeichen ein AttributeError.
            aufrufe = []
        for aufruf in aufrufe:
            if not isinstance(aufruf, dict):
                raise LLMError(
                    "Die Antwort enthielt einen Werkzeugaufruf in unbekannter Form.",
                    kind="bad_response",
                    duration_ms=duration_ms,
                )
            funktion = aufruf.get("function")
            if not isinstance(funktion, dict):
                funktion = {}
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

        return LLMReply(
            text=text,
            model=str(payload.get("model") or self.model),
            # OpenAI-Namen, nicht input_tokens/output_tokens.
            usage=self._tokens(payload, "prompt_tokens", "completion_tokens"),
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
