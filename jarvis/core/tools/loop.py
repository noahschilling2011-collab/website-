"""Die Runde Modell → Werkzeug → Modell.

Laeuft hoechstens `max_tool_calls` Runden. Wird die Grenze erreicht, bekommt
das Modell das gesagt und muss mit dem antworten, was es hat - der Loop
bricht nicht stumm ab und erhoeht die Grenze auch nicht selbst (0.5).
"""

from __future__ import annotations

import logging
from typing import Any, Awaitable, Callable, Iterable

from core.abbruch import LaufBeendet
from core.contracts import Permission
from core.llm import LLMMessage, LLMProvider, LLMReply
from core.tools import registry
from core.tools.dispatch import Audit, Bestaetigung, ToolCall, run_tool

log = logging.getLogger("jarvis")

BUDGET_HINWEIS = (
    "Du hast das Werkzeug-Budget dieses Auftrags aufgebraucht. Antworte jetzt "
    "mit dem, was du hast, und sag klar, was dadurch offen bleibt. Ruf kein "
    "weiteres Werkzeug."
)


def _mit_endnotiz(text: str, ende: LaufBeendet) -> str:
    """Haengt an, warum hier Schluss ist - statt stumm abzubrechen (0.5).

    WAS WAR FALSCH: die Funktion hiess `_mit_budgetnotiz` und haengte fest
    '[Budget des Auftrags aufgebraucht: {grund}]' an - fuer JEDE
    `LaufBeendet`, also auch fuer die mit status='cancelled', die
    `core/abbruch.py` wirft, wenn der Nutzer den Abbrechen-Knopf drueckt.

    WARUM IST DAS FALSCH: der Nutzer bricht ab und liest
    '[Budget des Auftrags aufgebraucht: Vom Nutzer abgebrochen.]' - zwei
    sich widersprechende Ursachen in einem Satz. Wer danach stutzt, sucht
    ein Budgetproblem, das es gar nicht gibt. Die richtige Unterscheidung
    liegt greifbar daneben: `LaufBeendet.status` (core/abbruch.py) ist
    entweder 'cancelled' oder 'aborted_budget' - gelesen wurde das Feld
    hier nicht. Deshalb bekommt die Funktion jetzt die ganze Ausnahme und
    nicht nur den Grund.

    WOHER: Verknuepfungspruefung 31.08.2026, Gruppe schleife, Fund 2.

    Beim Abbruch steht der Grund fuer sich ('Vom Nutzer abgebrochen.') - ein
    zusaetzliches 'Abgebrochen:' davor wuerde ihn nur doppeln, so wie es
    core/runner.py mit seinem 'Abgebrochen - ' schon tut.
    """
    if ende.status == "cancelled":
        notiz = f"[{ende.grund.strip() or 'Vom Nutzer abgebrochen.'}]"
    else:
        notiz = f"[Budget des Auftrags aufgebraucht: {ende.grund}]"
    return f"{text.strip()}\n\n{notiz}" if text.strip() else notiz


async def run_tool_loop(
    provider: LLMProvider,
    verlauf: list[LLMMessage],
    *,
    system: str,
    erlaubt: Iterable[str] | None = None,
    max_permission: Permission = Permission.SENSITIVE,
    max_tool_calls: int = 20,
    on_call: Callable[[ToolCall], Awaitable[None]] | None = None,
    on_reply: Callable[[LLMReply], Awaitable[None]] | None = None,
    bestaetigung: Bestaetigung | None = None,
    audit: Audit | None = None,
    pruefpunkt: Callable[[], None] | None = None,
) -> tuple[str, list[ToolCall], list[LLMReply]]:
    """Gibt (Antworttext, ausgefuehrte Aufrufe, alle Modellantworten) zurueck.

    `pruefpunkt` ist die Pruefung aus `core.abbruch`. Sie steht vor jedem
    bezahlten Zug und vor jedem Werkzeug und WIRFT `LaufBeendet`, wenn der
    Auftrag abgebrochen wurde oder eine Verbrauchsgrenze gerissen ist. Was bis
    dahin an Text zusammengekommen ist, haengt an der Ausnahme.

    BUGS-01 Fund 4: `max_tool_calls` hier ist die Grenze des *Agenten*, nicht
    die des Auftrags. Die des Auftrags wurde frueher nur zwischen den
    Schritten geprueft - innerhalb eines Schritts waren `max_tokens`,
    `max_cost_eur`, `max_tool_calls` und `max_seconds` beliebig
    ueberschreitbar. Bei einem Ein-Schritt-Plan hatte der Auftrag damit
    praktisch kein Budget.
    """
    schemas = registry.schemas_for(erlaubt, max_permission)
    nachrichten = list(verlauf)
    aufrufe: list[ToolCall] = []
    antworten: list[LLMReply] = []
    budget_gemeldet = False

    def _bisher(text: str) -> str:
        """Was bis hierher wirklich erarbeitet wurde - Text UND Werkzeugertrag.

        WAS WAR FALSCH: hier stand nur `antworten[-1].text`, also der Text des
        letzten Modellzuges. Die Liste `aufrufe` mit allen bis dahin
        gelaufenen Werkzeugergebnissen liegt zwei Zeilen darueber in derselben
        Funktion und wurde nicht angefasst.

        WARUM IST DAS FALSCH: das ist genau das Gegenteil dessen, was 0.5 mit
        dem Teilergebnis will. Der clock-Aufruf lieferte
        'Montag, 31.08.2026, 10:36:32 (UTC)', der Nutzer bekam
        'Ich hole die Uhrzeit.' - bezahlte und erfolgreich gelaufene
        Werkzeugarbeit wurde weggeworfen, ein inhaltsleerer Fuellsatz
        durchgereicht. War der letzte Zug ein reiner tool_use-Zug (Text leer,
        der haeufige Fall), blieb sogar gar nichts uebrig und der Nutzer sah
        nur noch die Endnotiz.

        WOHER: Verknuepfungspruefung 31.08.2026, Gruppe schleife, Fund 1.

        Nur `ok`-Ergebnisse kommen mit: ein fehlgeschlagener Aufruf hat nichts
        erarbeitet, was man dem Nutzer als Teilergebnis hinlegen koennte.
        Reihenfolge: erst der Modelltext, dann die Ertraege in Laufreihenfolge.
        """
        teile = [text.strip()] if text.strip() else []
        for aufruf in aufrufe:
            ergebnis = aufruf.result
            if ergebnis is not None and ergebnis.ok and ergebnis.display.strip():
                teile.append(ergebnis.display.strip())
        return "\n\n".join(teile)

    while True:
        # Vor jedem bezahlten Zug. Der Zug, der die Grenze reisst, laeuft zu
        # Ende - danach wird hier nichts mehr ausgegeben.
        if pruefpunkt is not None:
            try:
                pruefpunkt()
            except LaufBeendet as ende:
                log.warning("Lauf endet in der Werkzeugrunde - %s", ende.grund)
                letzter_text = antworten[-1].text if antworten else ""
                ende.teiltext = _mit_endnotiz(_bisher(letzter_text), ende)
                raise

        reply = await provider.complete(
            nachrichten,
            system=system,
            tools=schemas if schemas and not budget_gemeldet else None,
        )
        antworten.append(reply)
        if on_reply is not None:
            await on_reply(reply)

        if not reply.tool_uses:
            return reply.text, aufrufe, antworten

        # Die Assistenten-Bloecke muessen unveraendert zurueck, sonst kann das
        # Modell die tool_result-Zeile nicht zuordnen.
        nachrichten.append(
            LLMMessage(role="assistant", content=list(reply.content_blocks))
        )

        ergebnisbloecke: list[dict[str, Any]] = []
        for tool_use in reply.tool_uses:
            # Auch zwischen zwei Werkzeugen desselben Zuges. Ein Modell darf
            # mehrere auf einmal anfordern; die duerfen nicht alle noch
            # durchlaufen, nachdem die Grenze weg ist.
            if pruefpunkt is not None:
                try:
                    pruefpunkt()
                except LaufBeendet as ende:
                    log.warning("Lauf endet vor %s - %s", tool_use.name, ende.grund)
                    ende.teiltext = _mit_endnotiz(_bisher(reply.text), ende)
                    raise

            if len(aufrufe) >= max_tool_calls:
                ergebnisbloecke.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use.id,
                    "content": BUDGET_HINWEIS,
                    "is_error": True,
                })
                budget_gemeldet = True
                log.warning(
                    "Werkzeug-Budget erreicht (%d), %s wird nicht ausgefuehrt",
                    max_tool_calls, tool_use.name,
                )
                continue

            ergebnis = await run_tool(
                tool_use.name,
                tool_use.input,
                max_permission=max_permission,
                erlaubt=erlaubt,
                bestaetigung=bestaetigung,
                audit=audit,
            )
            aufruf = ToolCall(
                name=tool_use.name, arguments=tool_use.input, result=ergebnis
            )
            aufrufe.append(aufruf)
            if on_call is not None:
                await on_call(aufruf)

            inhalt = ergebnis.display or ergebnis.error or (
                "ok" if ergebnis.ok else "fehlgeschlagen"
            )
            if ergebnis.ok and ergebnis.sources:
                inhalt += "\n\nQuellen:\n" + "\n".join(ergebnis.sources)

            ergebnisbloecke.append({
                "type": "tool_result",
                "tool_use_id": tool_use.id,
                "content": inhalt,
                **({"is_error": True} if not ergebnis.ok else {}),
            })

        nachrichten.append(LLMMessage(role="user", content=ergebnisbloecke))
