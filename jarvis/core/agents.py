"""Agenten (Phase 4).

Ein Agent ist ein benanntes Buendel aus Systemprompt, Werkzeugen, Modell und
einer **Obergrenze an Rechten**. Die Obergrenze ist der Punkt: sie gilt
unabhaengig davon, welche Werkzeuge in der Liste stehen, und durchgesetzt wird
sie im Dispatcher - nicht hier (0.7).
"""

from __future__ import annotations

import logging

import time
from typing import Awaitable, Callable, Iterable

from core.fehlertexte import ohne_geheimnis
from core.abbruch import LaufBeendet
from core.contracts import Agent, Permission, Step, Task, ToolResult
from core.belege import belegte_urls, ohne_unbelegte_links
from core.satellite.policy import pruefe_anfrage
from core.llm import LLMMessage, LLMProvider, LLMReply
from core.tools.dispatch import Audit, Bestaetigung, ToolCall
from core.tools.loop import run_tool_loop

log = logging.getLogger("jarvis")

SPRACHSTIL = """

SPRACHMODUS: Deine Antwort wird VORGELESEN, nicht gelesen.

- Hoechstens drei Saetze. Wer zuhoert, kann nicht ueberfliegen.
- Keine Aufzaehlungen, keine Ueberschriften, keine URLs im Fliesstext - das
  klingt vorgelesen wie Kauderwelsch.
- Zahlen ausschreiben, wo es die Verstaendlichkeit erhoeht.
- Wenn die vollstaendige Antwort laenger waere: gib die Kernaussage und sag,
  dass die Einzelheiten im Text stehen."""

RECHERCHE_PROMPT = """Du bist der Research Agent von {name}.

Du beantwortest genau den Arbeitsschritt, den du bekommst - nicht mehr.

REIHENFOLGE DER QUELLEN - von billig nach teuer, nie umgekehrt:
1. wiki_lokal zuerst. Kostet nichts, braucht kein Netz, kein Ratenlimit.
   Treffer -> fertig. Nenn den Artikeltitel UND das Snapshot-Datum, und sag
   dem Nutzer, aus welchem Stand du antwortest.
2. wiki_live nur, wenn wiki_lokal nichts hat ODER die Frage etwas betrifft,
   das nach dem Snapshot-Datum passiert ist.
3. wikidata, wenn du eine ZAHL oder ein Datum brauchst statt eines Absatzes.
4. web_search erst danach.

REGELN, die deine Arbeit ungueltig machen, wenn du sie brichst:
1. Jede Tatsachenbehauptung braucht eine Quelle. Such erst, lies die Seite mit
   fetch_url, und nenn die URL. Eine Behauptung ohne Quelle ist ein
   fehlgeschlagener Schritt. Auch bei lokaler Quelle: Artikeltitel und
   Snapshot-Datum sind die Quelle.
2. Erfinde keine Zahlen, keine Daten, keine URLs. Wenn du etwas nicht findest,
   schreib das hin.
3. Nenn zu jeder Zahl, wann sie erhoben wurde, wenn die Quelle das hergibt.
   Preise und Steuersaetze ohne Datum sind wertlos.

Antworte knapp und in Prosa. Am Ende eine Zeile "Quellen:" mit den URLs."""

WELTLAGE_PROMPT = """Du bist der Weltlage-Agent von {name}.

Du lieferst hoechstens 5 belegte Meldungen zu einem Land oder zur Weltlage.

WAS "KRASS" HEISST: Dichte an belegten Einzelheiten. NICHT Tonfall.

    Nicht krass, nur laut          Krass, weil belegt
    "ESKALATION IM PAZIFIK"        "Reuters, 14:20 MEZ - dritter Vorfall in 9 Tagen"
    "Massive Bauarbeiten"          "20 Std./Tag, 7 Tage, Bauherr nennt 65 % fertig"
    "Die Lage spitzt sich zu"      (streichen - keine Aussage)

REGELN FUER DIE MELDUNG:
1. Jede Zahl braucht ihre Quelle in derselben Meldung. Zahl ohne Quelle -> Meldung raus.
2. Keine Superlative, die nicht in der Quelle stehen.
3. Keine Vergleiche zum Mittelwert ("mehr als sonst"), ausser die Quelle nennt den Mittelwert.
4. Keine Prognose. Was passiert ist, nicht was passieren wird.
5. Zwei Saetze pro Meldung. Kuerze zwingt zu Substanz.
6. Bei duenner Quellenlage: WENIGER Meldungen, nicht ausgeschmueckte.

PFLICHTFELDER je Meldung - fehlt eins, wird die Meldung verworfen:
    schlagzeile, kurz (max 2 Saetze), medium, veroeffentlicht (ISO-Zeitstempel),
    quell_url, land_iso

DIE EINORDNUNG IST EIN ZWEITER, GETRENNTER BLOCK.
Sie kommt von dir, nicht aus der Quelle, und das steht auch dran.
- Beantwortet GENAU EINE von drei Fragen: Warum ist das wichtig? Was war vorher?
  Was muesste man wissen, um das einzuordnen?
- Hoechstens drei Saetze.
- KEINE Prognose.
- Unsicherheit wird ausgesprochen, nicht weggelassen.
- Hast du keinen Kontext, sagst du das in EINEM Satz und laesst die Einordnung leer.
  Du fuellst sie nicht.

SCHWEIGEN IST EIN GUELTIGER ZUSTAND.
Passiert nichts Grosses, sagst du das kurz - und erfindest nichts dazu.
Erlaubt:  "Drei belegte Meldungen aus Moskau. Juengste um 14:20."
          "Zwei Meldungen verworfen, keine Quelle."
          "Zu Namibia finde ich heute nichts."
Verboten: "Die Lage bleibt angespannt." / "Es entwickelt sich weiter."
          Die Schlagzeile in anderen Worten wiederholen.

ZU BILDERN SAGST DU NICHTS. Das Bild kommt aus der Quelle, die Bildbeschreibung
auch. Du beschreibst kein Foto, das du nicht gesehen hast - und du hast keins
gesehen.

Antworte AUSSCHLIESSLICH mit JSON in genau dieser Form:
{"meldungen": [{"schlagzeile": "", "kurz": "", "medium": "", "veroeffentlicht": "",
"quell_url": "", "land_iso": "", "einordnung": "", "einordnung_fehlt": ""}],
"gesagt": "ein Satz fuer die Statusleiste"}"""


SATELLIT_PROMPT = """Du bist der Satellite Agent von {name}.

Du arbeitest mit frei verfuegbaren Erdbeobachtungsdaten. Deine wichtigste
Eigenschaft ist, dass du weisst, was du NICHT sehen kannst.

HARTE REGELN:
0. **Rate NIE Koordinaten.** Der Nutzer sagt einen Ortsnamen; du rufst
   `find_place` und bekommst Koordinaten und einen fertigen `bbox`. Erst
   damit gehst du in `satellite_search` oder `satellite_passes`. Eine
   selbst ausgedachte Bounding Box liegt schnell im falschen Land - und
   das Bild, das zurueckkommt, sieht trotzdem plausibel aus.
1. **Fuehr die Bodenaufloesung bei jeder Aussage mit - die des BILDES.**
   Der Sensor hat 10 m je Pixel, das gelieferte Bild aber nur 512 Pixel
   Kante: bei einem Stadtausschnitt sind das rund 23 m, bei einem ganzen
   Land ueber 1000 m. Die wahre Zahl steht im Werkzeugergebnis unter
   `bild_aufloesung_m` - benutze DIESE. Benenne kein Objekt, das kleiner
   als etwa das Dreifache davon ist. Wer bei 23 m/px "neues Gebaeude"
   sagt, halluziniert; bei 1000 m/px gilt das schon fuer "Stadtteil".
2. **Es gibt keine Live-Bilder.** "Aktuell" heisst: das juengste Bild unter
   dem Wolken-Schwellwert im Suchfenster. Sentinel-2 ueberfliegt einen Ort
   alle 3 bis 5 Tage, und viele Aufnahmen sind bewoelkt. Sag das so.
3. **Findest du kein Bild unter dem Schwellwert, sag das.** Liefere nie
   ersatzweise ein bewoelktes Bild ohne Hinweis.
4. **Rechne, bevor du interpretierst.** Erst NDVI/NDWI-Zahlen aus
   satellite_compare, dann eine Deutung - nie umgekehrt.
5. **Nenn Aufnahmedatum, Sensor, m/px und Wolkenanteil** zu jedem Bild, und
   die Attribution der Datenquelle.

Realistisch beurteilbar sind: Abholzung, Ueberschwemmungen, grosse Baustellen
und Erdbewegungen, Tagebau, Solarparks, landwirtschaftliche Veraenderungen,
Brandflaechen, Schneebedeckung, Gewaesserstaende, neue Strassentrassen.

AUSGABEFORMAT bei jeder Veraenderungsanalyse - die letzte Zeile ist Pflicht:

BEOBACHTET
  <was die Zahlen sagen>
INTERPRETATION
  <was das heissen koennte, mit den Alternativen>
KONFIDENZ  niedrig | mittel | hoch
GRUNDLAGE  <Sensor, m/px, beide Aufnahmedaten mit Wolkenanteil>
GRENZE     <was bei dieser Aufloesung nicht beurteilbar ist>

Du beobachtest keine Grundstuecke und keine Personen. Wenn danach gefragt
wird, lehnst du ab und erklaerst kurz warum."""

HERMES_PROMPT = """Du bist Hermes, der Orchestrator von {name}.

Du erledigst deinen Schritt, indem du Teilauftraege an andere Agenten gibst -
mit `ask_agent`. Du recherchierst nicht selbst; dafuer gibt es `research`.

REGELN:
1. Ein Teilauftrag pro `ask_agent`-Aufruf, vollstaendig ausformuliert. Der
   Agent sieht dein Gespraech nicht.
2. Wenn du Teilergebnisse zusammenfasst, **kennzeichne, welcher Teil von
   welchem Agenten kam** - in eckigen Klammern, z. B. "[research] ...".
3. Jeder Preis und jede Zahl braucht die Quelle, die der Agent geliefert hat.
   Eine Zahl ohne Quelle laesst du weg oder markierst sie als unbelegt.
4. Wenn du keinen weiteren Agenten rufen darfst, sag das und arbeite mit dem,
   was du hast. Versuch es nicht noch einmal.

Antworte knapp und in Prosa."""

# FIX-09: wie der Assistent heisst. Wird beim App-Start aus ASSISTENT_NAME
# gesetzt (api/app.py) und in jeden Prompt eingesetzt, in dem {name} steht.
# Modulweit statt als Parameter, damit keine der Signaturen hier wandert.
ASSISTENT_NAME = "JARVIS"


def mit_name(prompt: str) -> str:
    return prompt.replace("{name}", ASSISTENT_NAME)


STANDARD_PROMPT = """Du bist {name} und erledigst genau einen Arbeitsschritt.

Benutze deine Werkzeuge, statt zu raten. Rechne nie im Kopf - dafuer gibt es
calculator. Rate keine Uhrzeit - dafuer gibt es clock.

Antworte knapp und nur zu diesem Schritt."""


class ToolAgent(Agent):
    """Ein Agent, der seinen Schritt mit Werkzeugen erledigt."""

    def __init__(
        self,
        provider: LLMProvider,
        *,
        name: str,
        description: str,
        system_prompt: str,
        tools: Iterable[str],
        max_permission: Permission,
        can_call_agents: Iterable[str] = (),
        max_tool_calls: int = 8,
        on_reply: Callable[[LLMReply], Awaitable[None]] | None = None,
        on_call: Callable[[ToolCall], Awaitable[None]] | None = None,
        bestaetigung: Bestaetigung | None = None,
        audit: Audit | None = None,
        vorpruefung: Callable[[str], None] | None = None,
        links_pruefen: bool = True,
        budget_pruefung: Callable[[], None] | None = None,
    ) -> None:
        self.provider = provider
        self.name = name
        self.description = description
        self.system_prompt = system_prompt
        self.tools = list(tools)
        self.max_permission = max_permission
        self.can_call_agents = list(can_call_agents)
        self.max_tool_calls = max_tool_calls
        self._on_reply = on_reply
        self._on_call = on_call
        self._bestaetigung = bestaetigung
        self._audit = audit
        # Laeuft vor dem ersten Modellaufruf. Wirft, wenn der Auftrag gar nicht
        # erst bearbeitet werden soll - eine Ablehnung, die vom Tagesform eines
        # Modells abhaengt, ist keine Regel.
        self._vorpruefung = vorpruefung
        self._links_pruefen = links_pruefen
        # BUGS-01 Fund 4 und FIX-03 Schritt 3a: der Pruefpunkt des Auftrags.
        # Er steht vor jedem bezahlten Zug und vor jedem Werkzeug und wirft
        # `LaufBeendet`. Ohne ihn gaelte weder Abbruch noch Budget innerhalb
        # eines Schritts, und ein Ein-Schritt-Plan haette praktisch beides
        # nicht.
        self.budget_pruefung = budget_pruefung

    async def run(self, task: Task, step: Step) -> ToolResult:
        begonnen = time.monotonic()

        # BUGS-01 Fund 15: ab hier ist bekannt, WER ruft - sonst laesst sich
        # `can_call_agents` in ask_agent nicht durchsetzen. Der Kontext wird
        # kopiert statt veraendert: `abgelehnt` und `task` bleiben dieselben
        # Objekte, aber zwei Agenten treten sich nicht gegenseitig auf den
        # Rufer-Eintrag.
        from dataclasses import replace

        from core.delegation import kontext as _kontext

        _ctx = _kontext.get()
        _marke = None
        if _ctx is not None and _ctx.rufer != self.name:
            _marke = _kontext.set(replace(_ctx, rufer=self.name))
        try:
            return await self._run(task, step, begonnen)
        finally:
            if _marke is not None:
                _kontext.reset(_marke)

    async def _run(self, task: Task, step: Step, begonnen: float) -> ToolResult:

        if self._vorpruefung is not None:
            try:
                self._vorpruefung(f"{task.goal}\n{step.description}")
            except Exception as exc:  # noqa: BLE001 - die Begruendung ist die Antwort
                return ToolResult(
                    ok=False,
                    error=type(exc).__name__,
                    display=str(exc),
                    duration_ms=int((time.monotonic() - begonnen) * 1000),
                )

        vorher = [
            f"- {s.description}: {(s.result.display or '')[:400]}"
            for s in task.steps
            if s.result is not None and s.result.ok and s is not step
        ]
        auftrag = f"Ziel des Nutzers: {task.goal}\n\nDein Schritt: {step.description}"
        if vorher:
            auftrag += "\n\nWas frühere Schritte ergeben haben:\n" + "\n".join(vorher)

        # Genau das, was an das Modell geht - damit Phase 7 den Schritt
        # nachlesen kann, ohne dass man es rekonstruieren muss.
        step.prompt = f"[system]\n{self.system_prompt}\n\n[auftrag]\n{auftrag}"

        try:
            text, aufrufe, _ = await run_tool_loop(
                self.provider,
                [LLMMessage("user", auftrag)],
                system=self.system_prompt,
                erlaubt=self.tools,
                max_permission=self.max_permission,
                max_tool_calls=self.max_tool_calls,
                on_call=self._on_call,
                on_reply=self._on_reply,
                bestaetigung=self._bestaetigung,
                audit=self._audit,
                pruefpunkt=self.budget_pruefung,
            )
        except LaufBeendet:
            # FIX-03 Schritt 3a: das ist kein Schrittfehler, sondern das Ende
            # des Laufs. Wer das hier in ein ToolResult verwandelt, macht aus
            # dem Abbruch einen misslungenen Schritt - und der Task laeuft
            # weiter.
            raise
        except Exception as exc:  # noqa: BLE001 - ein Schritt reisst nie den Task um
            return ToolResult(
                ok=False,
                error=ohne_geheimnis(exc, "Schritt abgebrochen"),
                display=ohne_geheimnis(exc, "Schritt abgebrochen"),
                duration_ms=int((time.monotonic() - begonnen) * 1000),
            )

        # Quellen aus allen Werkzeugergebnissen einsammeln, Reihenfolge
        # erhalten, Doppelte raus.
        quellen: list[str] = []
        for aufruf in aufrufe:
            if aufruf.result is None:
                continue
            for url in aufruf.result.sources:
                if url not in quellen:
                    quellen.append(url)

        # Erfundene Links raus. Der Agent hier hat oft gar kein Werkzeug mit
        # Netzzugang - was er dann an Adressen anhaengt, kommt aus dem
        # Gedaechtnis des Modells, nicht von einer Seite.
        #
        # `links_pruefen=False` gibt es fuer genau einen Fall: einen Agenten,
        # dessen Ausgabe kein Mensch liest, sondern ein Parser. Siehe die
        # Begruendung bei `weltlage` in `baue_agenten`.
        if self._links_pruefen:
            belegt = belegte_urls(
                quellen,
                [(a.result.display or "") for a in aufrufe if a.result],
            )
            text, erfunden = ohne_unbelegte_links(text, belegt)
            if erfunden:
                log.warning(
                    "Agent %s: %d Link(e) entfernt - kein Werkzeug hat sie "
                    "geliefert.", self.name, erfunden,
                )

        return ToolResult(
            ok=bool(text.strip()),
            data={
                "tool_calls": [a.to_dict() for a in aufrufe],
                # Verknuepfungspruefung 31.08.2026: `core/verify.py` bekommt
                # nur `Step` und `ToolResult` - nicht den Agenten und nicht den
                # Task. Es konnte deshalb bisher nur am NAMEN des Agenten
                # haengen ("research"), und genau daran ist die Quellenregel am
                # `weltlage`-Agenten vorbeigelaufen.
                #
                # Hier stehen deshalb die zwei TATSACHEN, die die Regel
                # braucht. Bewusst Tatsachen und kein fertiges Urteil: ein
                # Agent, der selbst entscheidet, ob er geprueft werden muss,
                # ist derselbe Selbstbeleg, gegen den `core/belege.py`
                # geschrieben wurde. Entschieden wird in `core/verify.py`.
                #
                # `links_gefiltert=False` heisst: was das Modell an Adressen
                # erfunden hat, steht unveraendert im `display` - und damit
                # auch im Schritt-Display, das `core/runner.py` als Beleg
                # weiterreicht.
                "links_gefiltert": self._links_pruefen,
                "ziel": task.goal,
            },
            error=None if text.strip() else "Der Agent hat nichts geliefert.",
            display=text,
            sources=quellen,
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )


def heute_zeile() -> str:
    """Der eine Satz, den jeder Agent vorneweg bekommt."""
    # Nur ISO, bewusst. Eine zweite Darstellung ("Wednesday, 26. August")
    # waere in einem deutschen Prompt halb englisch - %A und %B haengen an
    # der Locale des Servers - und ein zweiter Ausdruck desselben Datums ist
    # eine zweite Stelle, die falsch sein kann.
    # FIX-09: dazu das Datum in Ortszeit - Zeitplaene und Erinnerungen
    # ("einmal 2026-09-06 08:00") rechnen in Ortszeit, und zwischen
    # Mitternacht und 02:00 Sommerzeit nennt UTC noch den Vortag.
    lokal = time.strftime('%Y-%m-%d %H:%M', time.localtime())
    return (
        f"Heute ist der {time.strftime('%Y-%m-%d', time.gmtime())} (UTC), "
        f"in Ortszeit {lokal}. "
        f"Rechne nicht mit einem anderen Jahr, auch wenn dein Training "
        f"aelter ist. Brauchst du die Uhrzeit genauer, nimm das Werkzeug "
        f"clock, falls du es hast."
    )


def baue_agenten(
    provider: LLMProvider,
    *,
    max_permission: Permission,
    antwortstil: str = "",
    on_reply: Callable[[LLMReply], Awaitable[None]] | None = None,
    on_call: Callable[[ToolCall], Awaitable[None]] | None = None,
    bestaetigung: Bestaetigung | None = None,
    audit: Audit | None = None,
    budget_pruefung: Callable[[], None] | None = None,
) -> dict[str, ToolAgent]:
    """Die Agenten, die es in dieser Phase gibt.

    `research` ist bewusst auf READ gedeckelt: er soll lesen und belegen,
    nichts schreiben und nichts nach aussen schicken. Selbst wenn ihm jemand
    ein maechtigeres Werkzeug in die Liste schreibt, laesst der Dispatcher es
    nicht durch.
    """
    def mit_stil(prompt: str) -> str:
        """Setzt das heutige Datum davor und haengt den Antwortstil an.

        Das Datum ist kein Schmuck. Gemessen am 26.08.2026, erster Lauf mit
        einem echten Modell: der Agent suchte nach "Deutschland aktuelle
        Meldungen 26. August 2024" - zwei Jahre daneben. Er hatte keine
        Moeglichkeit, es besser zu wissen. `research` und `weltlage` haben
        kein `clock` (`tools=[...]` weiter unten), und nirgends stand ein
        Datum in einem Prompt. Ein Modell, das nach "aktuell" gefragt wird,
        raet dann aus seinem Training - und trifft das Jahr seines
        Trainingsstands.

        Als Satz im Prompt statt als Werkzeug, weil ein Werkzeug gerufen
        werden MUSS und ein Satz einfach dasteht. Dieselbe Ueberlegung wie
        in `core/satellite/policy.py`: eine Regel, die vom Tagesform eines
        Modells abhaengt, ist keine Regel.
        """
        return f"{heute_zeile()}\n\n{mit_name(prompt)}{antwortstil}"

    hermes = ToolAgent(
        provider,
        name="hermes",
        description=(
            "Zerlegt einen groesseren Auftrag, gibt Teilauftraege an andere "
            "Agenten und fuehrt deren Ergebnisse zusammen."
        ),
        system_prompt=mit_stil(HERMES_PROMPT),
        tools=["ask_agent", "calculator", "clock"],
        max_permission=Permission.LOCAL,
        can_call_agents=["research", "satellite"],
        max_tool_calls=12,
        on_reply=on_reply,
        on_call=on_call,
        audit=audit,
    )

    alle = {
        "hermes": hermes,
        "satellite": ToolAgent(
            provider,
            name="satellite",
            description=(
                "Beantwortet Fragen zu Erdbeobachtungsdaten - Abholzung, "
                "Ueberschwemmungen, Baustellen, Brandflaechen. Kennt seine "
                "Aufloesungsgrenze und behauptet nichts darunter."
            ),
            system_prompt=mit_stil(SATELLIT_PROMPT),
            tools=["find_place", "satellite_search", "satellite_compare",
                   "satellite_passes", "calculator", "clock"],
            max_permission=Permission.READ,
            vorpruefung=pruefe_anfrage,
            on_reply=on_reply,
            on_call=on_call,
            audit=audit,
        ),
        # FIX-02 Schritt 2: die Weltlage ist ein AGENT, kein eigener Datenweg.
        # Vorher rief api/weltlage.py den Provider direkt - vorbei an Budget,
        # Audit und llm_calls. Als Agent gilt fuer sie, was fuer jeden anderen
        # Schritt gilt.
        "weltlage": ToolAgent(
            provider,
            name="weltlage",
            description=(
                "Liefert belegte Meldungen zu einem Land oder zur Weltlage. "
                "Jede Meldung braucht Medium, Datum und Quell-URL; ohne die "
                "wird sie verworfen. Antwortet als JSON."
            ),
            # Ohne Sprachstil (die Antwort ist JSON), aber MIT Datum -
            # eine Nachrichtenlage ohne heutiges Datum ist wertlos.
            system_prompt=f"{heute_zeile()}\n\n{mit_name(WELTLAGE_PROMPT)}",  # ohne Sprachstil:
                                                # die Antwort ist JSON, kein Fliesstext
            tools=["wiki_lokal", "wiki_live", "wikidata", "web_search", "fetch_url"],
            max_permission=Permission.READ,
            max_tool_calls=12,
            # Der einzige Agent ohne Link-Filter, und zwar aus zwei Gruenden:
            #
            # 1. Seine Ausgabe ist JSON fuer einen Parser, kein Fliesstext fuer
            #    einen Menschen. Eine URL da rauszuschneiden zerstoert den
            #    Datensatz, statt eine Behauptung zu entschaerfen - gemessen:
            #    der Filter liess 21 Weltlage-Tests fallen, weil jede Meldung
            #    ohne quell_url verworfen wird.
            # 2. Er hat eine eigene, schaerfere Pruefung. `core/weltlage.py`
            #    verwirft jede Meldung ohne gueltige quell_url (`_url_gueltig`),
            #    dedupliziert darueber, und `api/weltlage.py` HOLT die
            #    Quellseite anschliessend wirklich. Eine erfundene URL faellt
            #    dort durch - nicht weil jemand sie fuer echt haelt, sondern
            #    weil sie nicht antwortet.
            #
            # NACHTRAG, Verknuepfungspruefung 31.08.2026: Grund 2 gilt NUR auf
            # dem Weg ueber `api/weltlage.py`. Der Planner bietet `weltlage`
            # aber jedem Auftrag an (`core/runner.py` nimmt nur `jarvis` aus
            # der Liste), und auf dem Weg /api/tasks laeuft weder der Parser
            # noch die Nachpruefung. Dort war die erfundene Adresse damit
            # ungeprueft im Schritt-Display - und weil `core/runner.py` genau
            # diese Displays an `belegte_urls()` gibt, hat sie sich selbst
            # belegt und stand woertlich in der Endantwort.
            #
            # Der Filter bleibt trotzdem aus - er wuerde den Datensatz
            # zerstoeren (siehe Grund 1). Stattdessen traegt der Agent seither
            # `links_gefiltert` und `ziel` in `ToolResult.data` ein, und die
            # Quellenregel in `core/verify.py` entscheidet damit: ohne Quelle
            # geht so ein Schritt nur durch, wenn er fuer die Weltlage-Seite
            # laeuft - also dort, wo die quell_url wirklich geholt wird.
            links_pruefen=False,
            on_reply=on_reply,
            on_call=on_call,
            audit=audit,
        ),
        "research": ToolAgent(
            provider,
            name="research",
            description=(
                "Recherchiert im Web und belegt jede Behauptung mit einer Quelle."
            ),
            system_prompt=mit_stil(RECHERCHE_PROMPT),
            tools=["wiki_lokal", "wiki_live", "wikidata", "web_search", "fetch_url"],
            max_permission=Permission.READ,
            on_reply=on_reply,
            on_call=on_call,
            audit=audit,
        ),
        "jarvis": ToolAgent(
            provider,
            name="jarvis",
            description="Erledigt einen Schritt mit den eigenen Werkzeugen.",
            system_prompt=mit_stil(STANDARD_PROMPT),
            # FIX-07: datei_suchen, datei_lesen und kalender kommen dazu.
            # `max_permission` bleibt unveraendert - die drei sind READ, und
            # SENSITIVE bleibt zu.
            # FIX-09: wetter (READ, ohne Key) und erinnerung_anlegen (LOCAL).
            tools=["clock", "calculator", "recall", "remember", "send_email",
                   "datei_suchen", "datei_lesen", "kalender",
                   "wetter", "erinnerung_anlegen"],
            max_permission=max_permission,
            on_reply=on_reply,
            on_call=on_call,
            bestaetigung=bestaetigung,
            audit=audit,
        ),
    }

    # BUGS-01 Fund 4: an EINER Stelle gesetzt, nicht fuenfmal einzeln - sonst
    # bekommt der naechste Agent die Budgetpruefung nicht und faellt still aus
    # dem Budget heraus.
    for agent in alle.values():
        agent.budget_pruefung = budget_pruefung
    return alle
