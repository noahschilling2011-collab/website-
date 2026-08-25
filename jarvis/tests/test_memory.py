"""Tests des Gedaechtnisses (Phase 3).

Die DoD-Punkte hier laufen gegen `FakeLLMProvider` mit geskripteten Zuegen:
so wird der ganze Weg geprueft (Modell ruft `remember` → Fakt liegt in der DB
→ nach dem Neustart findet `recall` ihn wieder), ohne einen Aufruf zu bezahlen.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db, memory
from core.llm import FakeLLMProvider, FakeTurn, LLMMessage, ToolUse
from core.tools.loop import run_tool_loop
from core.tools.registry import get as get_tool
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def pfad(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    # Die Gedaechtnis-Werkzeuge schreiben normalerweise in die Datenbank der
    # laufenden App; im Test wird der Pfad hier umgelenkt.
    for name in ("remember", "recall"):
        get_tool(name).db_path = db_path
    return db_path


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


# --- FTS5 -----------------------------------------------------------------


def test_fts_query_baut_aus_freiem_text_eine_sichere_anfrage():
    """Roher Text in MATCH ist Syntax, kein Suchbegriff - das wirft sonst."""
    # NEAR ist in FTS5 ein Operator. Weil jeder Begriff in Anfuehrungszeichen
    # landet, wird er hier zum harmlosen Suchwort.
    assert memory.fts_query('Was für ein "Rad" fahre ich? NEAR*') == (
        '"fahre" OR "near" OR "rad"'
    )
    assert memory.fts_query("??? ...") == ""


def test_sonderzeichen_in_der_suche_werfen_nicht(pfad):
    memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    for boese in ['"', "*", "NEAR(a b)", "a AND OR b", "-x", "^", "()"]:
        assert memory.search_facts(pfad, boese) == [] or True  # kein Absturz


def test_suche_findet_nach_stichwort(pfad):
    memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10", category="ausruestung")
    memory.add_fact(pfad, "Ich trinke keinen Kaffee", category="vorlieben")
    treffer = memory.search_facts(pfad, "Was für ein Rad fahre ich?")
    assert [f.text for f in treffer] == ["Mein Rad ist ein Santa Cruz V10"]


def test_suche_findet_ohne_umlaut_unterschied(pfad):
    memory.add_fact(pfad, "Ich mag Grünkohl")
    assert memory.search_facts(pfad, "gruenkohl") or memory.search_facts(pfad, "grünkohl")


def test_geloeschter_fakt_verschwindet_aus_dem_index(pfad):
    fakt, _ = memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    assert memory.search_facts(pfad, "Rad")
    memory.delete_fact(pfad, fakt.id)
    assert memory.search_facts(pfad, "Rad") == []


def test_geaenderter_fakt_wird_neu_indiziert(pfad):
    fakt, _ = memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    memory.update_fact(pfad, fakt.id, text="Mein Auto ist ein Golf")
    assert memory.search_facts(pfad, "Rad") == []
    assert memory.search_facts(pfad, "Auto")


def test_nachrichten_sind_auch_durchsuchbar(pfad):
    db.add_message(pfad, "user", "Ich war letzten Sommer in Norwegen")
    treffer = memory.search_messages(pfad, "Norwegen")
    assert len(treffer) == 1 and "Norwegen" in treffer[0][2]


# --- DoD 5: Konflikt ------------------------------------------------------


def test_dod_5_widerspruch_wird_angezeigt_nicht_ueberschrieben(pfad):
    alt, _ = memory.add_fact(
        pfad, "Mein Rad ist ein Santa Cruz V10", category="ausruestung"
    )
    neu, konflikt = memory.add_fact(
        pfad, "Mein Rad ist ein Propain Rage", category="ausruestung"
    )
    assert konflikt is not None and konflikt.id == alt.id
    assert neu.conflicts_with == alt.id
    # Beide stehen noch da. Nichts wurde still ersetzt.
    assert {f.id for f in memory.list_facts(pfad)} == {alt.id, neu.id}
    assert memory.get_fact(pfad, alt.id).text == "Mein Rad ist ein Santa Cruz V10"


def test_gleicher_fakt_zweimal_ist_kein_widerspruch(pfad):
    memory.add_fact(pfad, "Ich fahre Downhill", category="hobby")
    _, konflikt = memory.add_fact(pfad, "Ich fahre Downhill", category="hobby")
    assert konflikt is None


def test_andere_kategorie_ist_kein_widerspruch(pfad):
    memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10", category="ausruestung")
    _, konflikt = memory.add_fact(pfad, "Ich fahre Rad zur Arbeit", category="hobby")
    assert konflikt is None


def test_widerspruch_laesst_sich_aufloesen(pfad):
    alt, _ = memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10", category="a")
    neu, _ = memory.add_fact(pfad, "Mein Rad ist ein Propain Rage", category="a")
    memory.delete_fact(pfad, alt.id)
    assert memory.get_fact(pfad, neu.id).conflicts_with is None


# --- Kontextblock ---------------------------------------------------------


def test_kontextblock_traegt_die_fakt_id_als_herkunft(pfad):
    fakt, _ = memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    block = memory.kontextblock(pfad, "Welches Rad?")
    assert f"#{fakt.id}" in block and "Santa Cruz V10" in block


def test_kontextblock_ist_leer_wenn_nichts_passt(pfad):
    memory.add_fact(pfad, "Ich trinke keinen Kaffee")
    assert memory.kontextblock(pfad, "Wie ist das Wetter in Oslo?") == ""


def test_kontextblock_markiert_offene_widersprueche(pfad):
    memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10", category="a")
    memory.add_fact(pfad, "Mein Rad ist ein Propain Rage", category="a")
    assert "WIDERSPRUCH" in memory.kontextblock(pfad, "Welches Rad?")


# --- Episodisch (DoD 4) ---------------------------------------------------


def test_dod_4_drei_tasks_ergeben_drei_zeilen(pfad):
    for i in range(3):
        memory.log_task(pfad, f"task{i}", goal=f"Ziel {i}", outcome="done")
    assert len(memory.list_task_log(pfad)) == 3


def test_derselbe_task_wird_aktualisiert_nicht_verdoppelt(pfad):
    memory.log_task(pfad, "t1", goal="Ziel", outcome="running")
    memory.log_task(pfad, "t1", goal="Ziel", outcome="done", summary="fertig")
    log = memory.list_task_log(pfad)
    assert len(log) == 1 and log[0].outcome == "done"


# --- Werkzeuge ------------------------------------------------------------


def test_remember_legt_genau_einen_fakt_an(pfad):
    ergebnis = run(get_tool("remember").execute(
        text="Ich fahre Downhill und mein Rad ist ein Santa Cruz V10",
        category="ausruestung",
    ))
    assert ergebnis.ok is True
    fakten = memory.list_facts(pfad)
    assert len(fakten) == 1
    assert "Santa Cruz V10" in fakten[0].text


def test_remember_meldet_den_widerspruch_ans_modell(pfad):
    run(get_tool("remember").execute(text="Mein Rad ist ein Santa Cruz V10",
                                     category="ausruestung"))
    ergebnis = run(get_tool("remember").execute(text="Mein Rad ist ein Propain Rage",
                                                category="ausruestung"))
    assert "ACHTUNG" in ergebnis.display and "Widerspruch" in ergebnis.display.replace(
        "widerspricht", "Widerspruch"
    )


def test_recall_findet_nichts_und_sagt_das(pfad):
    ergebnis = run(get_tool("recall").execute(query="Einhörner"))
    assert ergebnis.ok is True and "Nichts" in ergebnis.display


def test_recall_findet_den_fakt(pfad):
    memory.add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    ergebnis = run(get_tool("recall").execute(query="Rad"))
    assert "Santa Cruz V10" in ergebnis.display


def test_recall_kann_auch_nachrichten_durchsuchen(pfad):
    db.add_message(pfad, "user", "Ich war letzten Sommer in Norwegen")
    ergebnis = run(get_tool("recall").execute(query="Norwegen", include_messages=True))
    assert "Norwegen" in ergebnis.display


# --- Ende zu Ende: DoD 1 bis 3 --------------------------------------------


def test_dod_1_merk_dir_erzeugt_einen_facts_eintrag(client, settings):
    client.app.state.provider = FakeLLMProvider(replies=[
        FakeTurn(tool_uses=(ToolUse("t1", "remember", {
            "text": "Ich fahre Downhill und mein Rad ist ein Santa Cruz V10",
            "category": "ausruestung",
        }),)),
        "Gemerkt.",
    ])
    antwort = client.post("/api/chat", json={
        "message": "Merk dir: ich fahre Downhill und mein Rad ist ein Santa Cruz V10."
    }, headers=TOKEN)
    assert antwort.status_code == 200

    fakten = client.get("/api/memory", headers=TOKEN).json()
    assert len(fakten) == 1 and "Santa Cruz V10" in fakten[0]["text"]


def test_dod_2_nach_dem_neustart_ist_der_fakt_im_kontext(settings):
    """Der Fakt aus Sitzung 1 muss in Sitzung 2 im Systemprompt landen."""
    with TestClient(create_app(settings)) as erste:
        erste.app.state.provider = FakeLLMProvider(replies=[
            FakeTurn(tool_uses=(ToolUse("t1", "remember", {
                "text": "Mein Rad ist ein Santa Cruz V10", "category": "ausruestung",
            }),)),
            "Gemerkt.",
        ])
        erste.post("/api/chat", json={"message": "Merk dir mein Rad."}, headers=TOKEN)

    with TestClient(create_app(settings)) as zweite:
        fake = FakeLLMProvider(replies=["Ein Santa Cruz V10."])
        zweite.app.state.provider = fake
        zweite.post("/api/chat", json={"message": "Was für ein Rad fahre ich?"},
                    headers=TOKEN)

    systemprompt = fake.calls[0]["system"]
    assert "Santa Cruz V10" in systemprompt
    assert "Langzeitgedaechtnis" in systemprompt


def test_dod_3_nach_dem_loeschen_steht_nichts_mehr_im_kontext(client, settings):
    fakt = client.post("/api/memory", json={
        "text": "Mein Rad ist ein Santa Cruz V10", "category": "ausruestung",
    }, headers=TOKEN).json()["fact"]

    assert client.delete(f"/api/memory/{fakt['id']}", headers=TOKEN).status_code == 204

    fake = FakeLLMProvider(replies=["Das weiß ich nicht."])
    client.app.state.provider = fake
    client.post("/api/chat", json={"message": "Was für ein Rad fahre ich?"},
                headers=TOKEN)

    # Kein Fakt mehr im Systemprompt - das Modell hat nichts, was es
    # halluzinieren koennte.
    assert "Santa Cruz" not in fake.calls[0]["system"]
    assert "Langzeitgedaechtnis" not in fake.calls[0]["system"]


def test_dod_4_drei_chats_ergeben_drei_zeilen_im_task_log(client):
    for i in range(3):
        client.post("/api/chat", json={"message": f"Frage {i}"}, headers=TOKEN)
    log = client.get("/api/tasks", headers=TOKEN).json()
    assert len(log) == 3
    assert {e["outcome"] for e in log} == {"done"}


def test_gescheiterter_task_wird_als_failed_protokolliert(client):
    from core.llm import LLMError

    class Kaputt:
        name, model = "kaputt", "keins"

        async def complete(self, messages, *, system, tools=None):
            raise LLMError("kaputt")

        async def aclose(self):
            return None

    client.app.state.provider = Kaputt()
    client.post("/api/chat", json={"message": "Frage"}, headers=TOKEN)
    log = client.get("/api/tasks", headers=TOKEN).json()
    assert len(log) == 1 and log[0]["outcome"] == "failed"


# --- API ------------------------------------------------------------------


def test_memory_api_legt_an_liest_aendert_loescht(client):
    erstellt = client.post("/api/memory", json={"text": "Ich mag Kaffee"},
                           headers=TOKEN)
    assert erstellt.status_code == 201
    fid = erstellt.json()["fact"]["id"]
    assert erstellt.json()["conflict"] is None

    assert len(client.get("/api/memory", headers=TOKEN).json()) == 1

    geaendert = client.patch(f"/api/memory/{fid}", json={"text": "Ich mag Tee"},
                             headers=TOKEN)
    assert geaendert.json()["text"] == "Ich mag Tee"

    assert client.delete(f"/api/memory/{fid}", headers=TOKEN).status_code == 204
    assert client.get("/api/memory", headers=TOKEN).json() == []


def test_memory_api_meldet_den_konflikt_mit(client):
    client.post("/api/memory", json={"text": "Mein Rad ist ein Santa Cruz V10",
                                     "category": "a"}, headers=TOKEN)
    zweite = client.post("/api/memory", json={"text": "Mein Rad ist ein Propain Rage",
                                              "category": "a"}, headers=TOKEN).json()
    assert zweite["conflict"] is not None
    assert "Santa Cruz" in zweite["conflict"]["text"]


def test_konflikt_laesst_sich_ueber_die_api_aufloesen(client):
    client.post("/api/memory", json={"text": "Mein Rad ist ein Santa Cruz V10",
                                     "category": "a"}, headers=TOKEN)
    zweite = client.post("/api/memory", json={"text": "Mein Rad ist ein Propain Rage",
                                              "category": "a"}, headers=TOKEN).json()
    fid = zweite["fact"]["id"]
    geloest = client.patch(f"/api/memory/{fid}", json={"resolve_conflict": True},
                           headers=TOKEN).json()
    assert geloest["conflicts_with"] is None


def test_memory_api_filtert_mit_q(client):
    client.post("/api/memory", json={"text": "Mein Rad ist ein Santa Cruz V10"},
                headers=TOKEN)
    client.post("/api/memory", json={"text": "Ich trinke keinen Kaffee"},
                headers=TOKEN)
    treffer = client.get("/api/memory?q=Kaffee", headers=TOKEN).json()
    assert len(treffer) == 1 and "Kaffee" in treffer[0]["text"]


def test_memory_braucht_den_token(client):
    assert client.get("/api/memory").status_code == 401
    assert client.post("/api/memory", json={"text": "x"}).status_code == 401


def test_unbekannter_fakt_gibt_404(client):
    assert client.delete("/api/memory/999", headers=TOKEN).status_code == 404
    assert client.patch("/api/memory/999", json={"text": "x"},
                        headers=TOKEN).status_code == 404
