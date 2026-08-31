"""Tests des Werkzeugsystems (Phase 2).

Kein echter Modellaufruf, kein echter Netzzugriff: der Tool-Loop laeuft gegen
`FakeLLMProvider` mit geskripteten Zuegen, die Websuche gegen einen
`httpx.MockTransport`.
"""

from __future__ import annotations

import asyncio
import re
from datetime import datetime

import httpx
import pytest

from core.abbruch import LaufBeendet
from core.contracts import Permission, Tool, ToolResult
from core.llm import FakeLLMProvider, FakeTurn, LLMMessage, ToolUse
from core.tools import registry
from core.tools.builtin import UnsichererAusdruck, rechne
from core.tools.dispatch import run_tool
from core.tools.loop import run_tool_loop
from core.tools.search import WebSearch
from core.tools.validate import pruefe
from tests.conftest import run


@pytest.fixture
def eigene_registry():
    """Erlaubt es, Test-Tools zu registrieren, ohne die echten zu verlieren."""
    zustand = registry._snapshot()
    yield registry
    registry._restore(zustand)


# --- Registry -------------------------------------------------------------


def test_die_drei_werkzeuge_aus_phase_2_sind_da():
    assert set(registry.names()) >= {"clock", "calculator", "web_search"}


def test_registry_liefert_json_schemas_fuers_modell():
    schemas = {s["name"]: s for s in registry.schemas_for()}
    assert schemas["calculator"]["input_schema"]["type"] == "object"
    assert "expression" in schemas["calculator"]["input_schema"]["properties"]
    assert schemas["calculator"]["description"].strip()


def test_registry_lehnt_kaputten_namen_ab(eigene_registry):
    with pytest.raises(ValueError, match="Tool-Name"):
        @registry.register
        class Kaputt(Tool):
            name = "Groß Und Falsch"
            description = "x"
            parameters = {"type": "object"}
            permission = Permission.INFO


def test_registry_lehnt_fehlende_beschreibung_ab(eigene_registry):
    with pytest.raises(ValueError, match="Beschreibung"):
        @registry.register
        class Stumm(Tool):
            name = "stumm"
            description = "   "
            parameters = {"type": "object"}
            permission = Permission.INFO


def test_registry_lehnt_doppelten_namen_ab(eigene_registry):
    with pytest.raises(ValueError, match="schon registriert"):
        @registry.register
        class NochmalClock(Tool):
            name = "clock"
            description = "x"
            parameters = {"type": "object"}
            permission = Permission.INFO


def test_registry_erzwingt_bestaetigung_ab_external(eigene_registry):
    """0.4.6 - ohne Ausnahme."""
    with pytest.raises(ValueError, match="requires_confirmation"):
        @registry.register
        class Heimlich(Tool):
            name = "heimlich_senden"
            description = "schickt etwas nach draussen"
            parameters = {"type": "object"}
            permission = Permission.EXTERNAL
            requires_confirmation = False


def test_schemas_bieten_nichts_ueber_der_obergrenze_an():
    namen = {s["name"] for s in registry.schemas_for(max_permission=Permission.INFO)}
    assert "web_search" not in namen
    assert {"clock", "calculator"} <= namen


# --- Rechner --------------------------------------------------------------


def test_dod_1_siebzehn_prozent_von_4380():
    assert rechne("4380 * 0.17") == pytest.approx(744.6)


@pytest.mark.parametrize("boese", [
    '__import__("os").system("ls")',
    'open("/etc/passwd").read()',
    "[1, 2, 3][0]",
    "x + 1",
    "(lambda: 1)()",
    "9**9**9",
])
def test_rechner_lehnt_alles_ab_was_kein_rechnen_ist(boese: str):
    """Kein eval, kein exec - der Baum wird geprueft, nicht der Text."""
    with pytest.raises(UnsichererAusdruck):
        rechne(boese)


def test_rechner_meldet_division_durch_null_als_ergebnis_nicht_als_absturz():
    ergebnis = run(run_tool("calculator", {"expression": "1/0"}))
    assert ergebnis.ok is False and "null" in (ergebnis.error or "")


def test_rechner_kann_die_erlaubten_funktionen():
    assert rechne("round(3.14159, 2)") == 3.14
    assert rechne("max(3, 7, 2)") == 7
    assert rechne("abs(-5) + min(2, 9)") == 7


# --- Uhr ------------------------------------------------------------------


def test_dod_2_clock_liefert_die_lokale_zeit():
    ergebnis = run(run_tool("clock"))
    assert ergebnis.ok is True
    jetzt = datetime.now().astimezone()
    assert jetzt.strftime("%d.%m.%Y") in ergebnis.display
    assert abs(
        (datetime.fromisoformat(ergebnis.data["iso"]) - jetzt).total_seconds()
    ) < 5


def test_clock_mit_zeitzone():
    ergebnis = run(run_tool("clock", {"timezone": "Europe/Berlin"}))
    assert ergebnis.ok is True and "Berlin" in ergebnis.data["timezone"]


def test_clock_meldet_unbekannte_zeitzone_statt_zu_raten():
    ergebnis = run(run_tool("clock", {"timezone": "Mars/Olympus"}))
    assert ergebnis.ok is False and "Mars/Olympus" in (ergebnis.error or "")


# --- Websuche -------------------------------------------------------------


def test_dod_3_websuche_liefert_quellen_urls():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["X-Subscription-Token"] == "test-such-key"
        assert "gravity bike" in request.url.params["q"].lower()
        return httpx.Response(200, json={"web": {"results": [
            {"title": "Helmtest 2026", "url": "https://example.org/helme",
             "description": "Vergleich von Fullface-Helmen."},
            {"title": "Preisvergleich", "url": "https://example.net/preise",
             "description": "Aktuelle Preise."},
        ]}})

    tool = WebSearch()
    tool.api_key = "test-such-key"
    tool.transport = httpx.MockTransport(handler)
    ergebnis = run(tool.execute(query="gravity bike helm"))

    assert ergebnis.ok is True
    assert ergebnis.sources == ["https://example.org/helme", "https://example.net/preise"]
    assert "Helmtest 2026" in ergebnis.display


def test_websuche_ohne_key_sagt_das_statt_zu_tun_als_haette_sie_gesucht():
    tool = WebSearch()
    tool.api_key = ""
    ergebnis = run(tool.execute(query="egal"))
    assert ergebnis.ok is False and "SEARCH_API_KEY" in ergebnis.display


def test_websuche_meldet_abgelehnten_key():
    def handler(request):
        return httpx.Response(401, json={"error": "nope"})

    tool = WebSearch()
    tool.api_key = "falsch"
    tool.transport = httpx.MockTransport(handler)
    ergebnis = run(tool.execute(query="egal"))
    assert ergebnis.ok is False and "401" in (ergebnis.error or "")


# --- Dispatcher -----------------------------------------------------------


def test_unbekanntes_werkzeug_ist_ein_ergebnis_keine_ausnahme():
    ergebnis = run(run_tool("gibt_es_nicht"))
    assert ergebnis.ok is False and "gibt_es_nicht" in (ergebnis.error or "")


def test_permission_wird_im_dispatcher_verweigert():
    """0.7: Die Pruefung passiert im Dispatcher, nicht im Agent."""
    ergebnis = run(run_tool(
        "web_search", {"query": "x"}, max_permission=Permission.INFO
    ))
    assert ergebnis.ok is False
    assert "READ" in (ergebnis.error or "") and "INFO" in (ergebnis.error or "")


def test_werkzeug_ausserhalb_der_agentenliste_wird_verweigert():
    ergebnis = run(run_tool("clock", erlaubt=["calculator"]))
    assert ergebnis.ok is False and "nicht freigegeben" in (ergebnis.error or "")


def test_kaputtes_tool_json_wird_abgefangen():
    """Modelle liefern regelmaessig Argumente, die nicht zum Schema passen."""
    ergebnis = run(run_tool("calculator", {"ausdruck": "1+1"}))
    assert ergebnis.ok is False and "expression" in (ergebnis.error or "")


def test_falscher_argumenttyp_wird_abgefangen():
    ergebnis = run(run_tool("calculator", {"expression": 42}))
    assert ergebnis.ok is False and "string" in (ergebnis.error or "")


def test_argument_ausserhalb_der_grenzen_wird_abgefangen():
    ergebnis = run(run_tool("web_search", {"query": "x", "count": 99}))
    assert ergebnis.ok is False and "maximum" not in (ergebnis.error or "").lower()
    assert "groesser" in (ergebnis.error or "")


def test_dod_4_langsames_werkzeug_wird_nach_seinem_timeout_abgebrochen(eigene_registry):
    @registry.register
    class Schnecke(Tool):
        name = "schnecke"
        description = "braucht absichtlich 40 Sekunden"
        parameters = {"type": "object", "additionalProperties": False}
        permission = Permission.INFO
        timeout_s = 1

        async def execute(self) -> ToolResult:
            await asyncio.sleep(40)
            return ToolResult(ok=True, display="nie erreicht")

    ergebnis = run(run_tool("schnecke"))
    assert ergebnis.ok is False
    assert "Zeitueberschreitung" in (ergebnis.error or "")
    assert ergebnis.duration_ms < 5000, "haette nach 1 s abbrechen muessen"


def test_ein_werkzeug_das_wirft_reisst_nichts_um(eigene_registry):
    @registry.register
    class Bombe(Tool):
        name = "bombe"
        description = "wirft"
        parameters = {"type": "object", "additionalProperties": False}
        permission = Permission.INFO

        async def execute(self) -> ToolResult:
            raise RuntimeError("bumm")

    ergebnis = run(run_tool("bombe"))
    assert ergebnis.ok is False and "bumm" in (ergebnis.error or "")


def test_ein_werkzeug_ohne_toolresult_wird_als_vertragsbruch_gemeldet(eigene_registry):
    @registry.register
    class Schlampig(Tool):
        name = "schlampig"
        description = "gibt einen String zurueck"
        parameters = {"type": "object", "additionalProperties": False}
        permission = Permission.INFO

        async def execute(self):
            return "einfach ein String"

    ergebnis = run(run_tool("schlampig"))
    assert ergebnis.ok is False and "ToolResult" in (ergebnis.error or "")


# --- Schema-Pruefer -------------------------------------------------------


def test_pruefer_erkennt_boolean_als_keine_zahl():
    assert pruefe({"type": "integer"}, True) is not None


def test_pruefer_geht_in_verschachtelte_objekte():
    schema = {"type": "object", "properties": {
        "a": {"type": "object", "properties": {"b": {"type": "integer"}}}}}
    assert pruefe(schema, {"a": {"b": "nein"}}) is not None
    assert pruefe(schema, {"a": {"b": 1}}) is None


# --- Tool-Loop ------------------------------------------------------------


def test_loop_fuehrt_das_werkzeug_aus_und_gibt_das_ergebnis_zurueck_ans_modell():
    provider = FakeLLMProvider(replies=[
        FakeTurn(text="Ich rechne das aus.",
                 tool_uses=(ToolUse("t1", "calculator", {"expression": "4380 * 0.17"}),)),
        "17 % von 4380 sind 744,6.",
    ])
    antwort, aufrufe, _ = run(run_tool_loop(
        provider, [LLMMessage("user", "Was ist 17 % von 4380?")], system="S",
    ))

    assert antwort == "17 % von 4380 sind 744,6."
    assert [a.name for a in aufrufe] == ["calculator"]
    assert aufrufe[0].result is not None and aufrufe[0].result.ok

    # Das Modell hat das Ergebnis wirklich zu sehen bekommen.
    letzter_aufruf = provider.calls[-1]["messages"]
    tool_result = letzter_aufruf[-1].content[0]
    assert tool_result["type"] == "tool_result"
    assert "744.6" in tool_result["content"]


def test_loop_haengt_die_assistenten_bloecke_unveraendert_an():
    provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
        "fertig",
    ])
    run(run_tool_loop(provider, [LLMMessage("user", "Wie spät?")], system="S"))
    verlauf = provider.calls[-1]["messages"]
    assistent = verlauf[-2]
    assert assistent.role == "assistant"
    assert assistent.content[0]["type"] == "tool_use"
    assert assistent.content[0]["id"] == "t1"


def test_loop_haelt_max_tool_calls_ein_und_erhoeht_sie_nicht():
    """0.5: Budgets werden nicht stillschweigend erhoeht."""
    provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("a", "clock", {}),)),
        FakeTurn(tool_uses=(ToolUse("b", "clock", {}),)),
        FakeTurn(tool_uses=(ToolUse("c", "clock", {}),)),
        "Ich musste aufhoeren.",
    ])
    antwort, aufrufe, _ = run(run_tool_loop(
        provider, [LLMMessage("user", "x")], system="S", max_tool_calls=2,
    ))
    assert len(aufrufe) == 2
    assert antwort == "Ich musste aufhoeren."


def test_loop_reicht_einen_fehlgeschlagenen_aufruf_als_is_error_weiter():
    provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("t1", "calculator", {"expression": "1/0"}),)),
        "Das geht nicht.",
    ])
    _, aufrufe, _ = run(run_tool_loop(
        provider, [LLMMessage("user", "1/0?")], system="S",
    ))
    assert aufrufe[0].result is not None and aufrufe[0].result.ok is False
    block = provider.calls[-1]["messages"][-1].content[0]
    assert block.get("is_error") is True


def test_loop_bietet_nur_erlaubte_werkzeuge_an():
    provider = FakeLLMProvider(replies=["ok"])
    run(run_tool_loop(
        provider, [LLMMessage("user", "x")], system="S",
        erlaubt=["clock"], max_permission=Permission.INFO,
    ))
    angeboten = {t["name"] for t in provider.calls[0]["tools"]}
    assert angeboten == {"clock"}


def test_loop_ohne_werkzeugvorschlag_antwortet_direkt():
    provider = FakeLLMProvider(replies=["Direkt geantwortet."])
    antwort, aufrufe, antworten = run(run_tool_loop(
        provider, [LLMMessage("user", "x")], system="S",
    ))
    assert antwort == "Direkt geantwortet." and aufrufe == []
    assert len(antworten) == 1


# --- Verknuepfungspruefung 31.08.2026, Gruppe schleife ---------------------
#
# Zwei Funde am Teilergebnis der Werkzeugrunde. Beide sitzen an derselben
# Stelle: dort, wo `pruefpunkt()` eine `LaufBeendet` wirft und der Loop noch
# schnell `ende.teiltext` fuellt, bevor die Ausnahme nach oben laeuft.
#
#   Fund 1: der teiltext trug nur den Text des letzten Modellzuges. Die
#           bereits gelaufenen Werkzeugergebnisse (`aufrufe`) wurden
#           weggeworfen.
#   Fund 2: die Endnotiz lautete immer '[Budget des Auftrags aufgebraucht:
#           ...]', auch bei einem Nutzerabbruch.
#
# Die Tests pruefen die Ursache, nicht den Wortlaut der Oberflaeche: dass die
# Werkzeugertraege ueberhaupt eingesammelt werden, und dass die Notiz aus
# `LaufBeendet.status` kommt und nicht aus dem Grundtext.


def _pruefpunkt_der_beim_n_ten_ruf_wirft(n: int, grund: str, status: str):
    """Ein Pruefpunkt wie der aus `core.abbruch`, nur vorhersagbar.

    Der Loop ruft ihn vor jedem bezahlten Zug UND vor jedem Werkzeug. Ueber
    `n` laesst sich damit genau bestimmen, an welcher der beiden Stellen der
    Lauf endet.
    """
    zaehler = {"i": 0}

    def pruefpunkt() -> None:
        zaehler["i"] += 1
        if zaehler["i"] >= n:
            raise LaufBeendet(grund, status=status)

    return pruefpunkt


def _lauf_bis_zum_ende(replies, n: int, grund: str, status: str):
    """Laesst den Loop laufen, bis der Pruefpunkt wirft. Gibt (Ausnahme, Aufrufe)."""
    gesehen: list = []

    async def on_call(aufruf):
        gesehen.append(aufruf)

    provider = FakeLLMProvider(replies=replies)
    with pytest.raises(LaufBeendet) as ende:
        run(run_tool_loop(
            provider, [LLMMessage("user", "Wie spaet?")], system="S",
            on_call=on_call,
            pruefpunkt=_pruefpunkt_der_beim_n_ten_ruf_wirft(n, grund, status),
        ))
    return ende.value, gesehen


def test_fund1_teiltext_traegt_das_werkzeugergebnis_nicht_nur_das_geplauder():
    """Der clock-Ertrag darf beim Abbruch nicht verlorengehen.

    Vorher stand im teiltext nur 'Ich hole die Uhrzeit.' - der Fuellsatz des
    Modells - waehrend die bezahlte und erfolgreich gelaufene Uhrzeit
    weggeworfen wurde. Pruefreihenfolge: erst wird belegt, dass clock wirklich
    etwas geliefert hat, dann dass genau das im teiltext steht.
    """
    ende, gesehen = _lauf_bis_zum_ende(
        [FakeTurn(text="Ich hole die Uhrzeit.",
                  tool_uses=(ToolUse("t1", "clock", {}),)),
         "wird nie erreicht"],
        n=3, grund="Vom Nutzer abgebrochen.", status="cancelled",
    )

    assert len(gesehen) == 1, "clock muss vor dem Abbruch gelaufen sein"
    ertrag = gesehen[0].result.display
    assert ertrag.strip(), "Vorbedingung: clock liefert einen display-Text"

    assert ertrag in ende.teiltext
    assert "Ich hole die Uhrzeit." in ende.teiltext


def test_fund1_teiltext_bleibt_ohne_modelltext_nicht_leer():
    """Der haeufige Fall: ein reiner tool_use-Zug ohne Text.

    Da griff der alte Code auf einen leeren String zu und der Nutzer bekam
    nichts als die Endnotiz - obwohl das Werkzeug geliefert hatte.
    """
    ende, gesehen = _lauf_bis_zum_ende(
        [FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
         "wird nie erreicht"],
        n=3, grund="Vom Nutzer abgebrochen.", status="cancelled",
    )

    ertrag = gesehen[0].result.display
    assert ertrag.strip()
    assert ertrag in ende.teiltext
    # Ohne die Reparatur bleibt exakt die nackte Notiz uebrig.
    assert ende.teiltext.strip() != "[Vom Nutzer abgebrochen.]"


def test_fund1_auch_der_pruefpunkt_vor_dem_werkzeug_rettet_die_ertraege():
    """Die zweite Abbruchstelle im Loop - die zwischen zwei Werkzeugen.

    Zwei Zuege, im zweiten wirft der Pruefpunkt vor dem Werkzeug. Der Ertrag
    des ersten Zuges muss trotzdem im teiltext stehen.
    """
    ende, gesehen = _lauf_bis_zum_ende(
        [FakeTurn(tool_uses=(ToolUse("t1", "clock", {}),)),
         FakeTurn(text="Noch mal nachsehen.",
                  tool_uses=(ToolUse("t2", "clock", {}),)),
         "wird nie erreicht"],
        n=4, grund="Vom Nutzer abgebrochen.", status="cancelled",
    )

    assert len(gesehen) == 1, "der zweite clock-Aufruf darf nicht mehr laufen"
    assert gesehen[0].result.display in ende.teiltext
    assert "Noch mal nachsehen." in ende.teiltext


def test_fund1_ein_fehlgeschlagener_aufruf_wandert_nicht_ins_teilergebnis():
    """Gegenprobe zu Fund 1: eingesammelt wird nur, was wirklich gelang.

    Sonst waere die Reparatur ein 'alles anhaengen' und der Nutzer bekaeme
    Fehlermeldungen als Teilergebnis serviert.
    """
    ende, gesehen = _lauf_bis_zum_ende(
        [FakeTurn(text="Ich rechne.",
                  tool_uses=(ToolUse("t1", "calculator", {"expression": "1/0"}),)),
         "wird nie erreicht"],
        n=3, grund="Vom Nutzer abgebrochen.", status="cancelled",
    )

    assert gesehen[0].result.ok is False, "Vorbedingung: 1/0 scheitert"
    assert gesehen[0].result.error
    assert gesehen[0].result.error not in ende.teiltext
    assert "Ich rechne." in ende.teiltext


def test_fund2_die_endnotiz_kommt_aus_dem_status_nicht_aus_dem_grundtext():
    """Ein Nutzerabbruch darf nicht als aufgebrauchtes Budget erklaert werden.

    Der Kern des Fundes: `LaufBeendet.status` traegt die Unterscheidung, wurde
    im Loop aber nicht gelesen. Deshalb laeuft hier DERSELBE Grundtext einmal
    als 'cancelled' und einmal als 'aborted_budget' durch - wer die Notiz am
    Text statt am Status festmacht, bekommt zweimal dasselbe und faellt hier.
    """
    grund = "Vom Nutzer abgebrochen."
    zuege = [FakeTurn(text="Zwischenstand.",
                      tool_uses=(ToolUse("t1", "clock", {}),)),
             "wird nie erreicht"]

    abgebrochen, _ = _lauf_bis_zum_ende(zuege, 3, grund, "cancelled")
    budget, _ = _lauf_bis_zum_ende(zuege, 3, grund, "aborted_budget")

    assert abgebrochen.status == "cancelled"
    assert "Budget" not in abgebrochen.teiltext
    assert grund in abgebrochen.teiltext

    assert budget.status == "aborted_budget"
    assert "[Budget des Auftrags aufgebraucht: " + grund + "]" in budget.teiltext

    assert abgebrochen.teiltext != budget.teiltext


def test_fund2_auch_vor_dem_werkzeug_wird_der_abbruch_richtig_benannt():
    """Beide Abbruchstellen im Loop muessen dieselbe Unterscheidung treffen."""
    ende, _ = _lauf_bis_zum_ende(
        [FakeTurn(text="Ich hole die Uhrzeit.",
                  tool_uses=(ToolUse("t1", "clock", {}),)),
         "wird nie erreicht"],
        n=2, grund="Vom Nutzer abgebrochen.", status="cancelled",
    )

    assert "Budget" not in ende.teiltext
    assert "Vom Nutzer abgebrochen." in ende.teiltext
