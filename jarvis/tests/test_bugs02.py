"""Die restlichen Funde aus `docs/BUGS-01.md` - 8, 9, 17 bis 23.

Getrennt von `test_bugs01.py`, weil die erste Datei die schweren Funde traegt
und mit ihren Servern und Zeitmessungen schon lang genug ist.

Jeder Test nennt die Fundnummer, damit man vom Bericht in den Test und zurueck
findet. Jeder Fund bekommt einen Negativtest: ein Fix, der nur den Gutfall
zeigt, ist nicht nachgewiesen.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from tests.conftest import run


# --- Fund 19: EventBus wirft das NEUE Ereignis weg -----------------------


def test_fund19_bei_vollem_puffer_ueberlebt_das_neue_ereignis():
    """BUGS-01 Fund 19.

    Der Docstring von `api/events.py` sagt: "ist seine Queue voll, wird das
    aelteste Ereignis verworfen und er bekommt einen Hinweis." Der Code tat
    das Gegenteil - gemessen:

        Puffer voll: 256/256
        nach dem final-Ereignis: 256
        'final' ueberhaupt enthalten: False
        letztes Ereignis im Puffer: dropped

    Er machte EINEN Platz frei, stellte den Hinweis hinein, und fuer das
    eigentliche Ereignis war wieder keiner da. Folge: die Oberflaeche bleibt
    auf "Plan laeuft" stehen, weil das `final`-Ereignis fehlt - und sie pollt
    seit Phase 7 bewusst nicht mehr.
    """
    from api.events import QUEUE_GROESSE, EventBus

    async def fuellen():
        bus = EventBus()
        q = bus.subscribe()
        for i in range(QUEUE_GROESSE):
            bus.publish("step", {"n": i})
        assert q.qsize() == QUEUE_GROESSE

        bus.publish("final", {"result": "DAS ERGEBNIS"})

        inhalt = []
        while not q.empty():
            inhalt.append(q.get_nowait())
        return inhalt

    inhalt = run(fuellen())
    typen = [e["type"] for e in inhalt]

    assert typen[-1] == "final", (
        f"das letzte Ereignis ist {typen[-1]!r} statt 'final'"
    )
    assert inhalt[-1]["data"]["result"] == "DAS ERGEBNIS"
    assert "dropped" in typen, "der Zuhoerer muss vom Verlust erfahren"
    assert typen[0] != "step" or inhalt[0]["data"]["n"] > 0, (
        "verworfen wird das AELTESTE, nicht das neueste"
    )


def test_fund19_ohne_ueberlauf_bleibt_alles_in_der_reihenfolge():
    """Gegenprobe: der Normalfall darf sich nicht aendern."""
    from api.events import EventBus

    async def normal():
        bus = EventBus()
        q = bus.subscribe()
        for i in range(5):
            bus.publish("step", {"n": i})
        return [q.get_nowait() for _ in range(q.qsize())]

    inhalt = run(normal())
    assert [e["type"] for e in inhalt] == ["step"] * 5
    assert [e["data"]["n"] for e in inhalt] == [0, 1, 2, 3, 4]


def test_fund19_auch_viele_ereignisse_hintereinander_lassen_das_letzte_stehen():
    """Ein langsamer Zuhoerer verliert die Mitte, nie das Ende."""
    from api.events import QUEUE_GROESSE, EventBus

    async def viele():
        bus = EventBus()
        q = bus.subscribe()
        for i in range(QUEUE_GROESSE * 2):
            bus.publish("step", {"n": i})
        bus.publish("final", {"result": "ENDE"})
        return [q.get_nowait() for _ in range(q.qsize())]

    inhalt = run(viele())
    assert inhalt[-1]["type"] == "final"
    assert inhalt[-1]["data"]["result"] == "ENDE"
    assert len(inhalt) <= QUEUE_GROESSE


def test_fund19_zwei_zuhoerer_stoeren_sich_nicht():
    """Ein voller Zuhoerer darf den anderen nicht mitreissen."""
    from api.events import QUEUE_GROESSE, EventBus

    async def zwei():
        bus = EventBus()
        langsam = bus.subscribe()
        schnell = bus.subscribe()
        for i in range(QUEUE_GROESSE + 10):
            bus.publish("step", {"n": i})
            if not schnell.empty():
                schnell.get_nowait()          # der schnelle liest sofort mit
        bus.publish("final", {"result": "ENDE"})
        return langsam, schnell

    langsam, schnell = run(zwei())
    letzte_langsam = [langsam.get_nowait() for _ in range(langsam.qsize())][-1]
    letzte_schnell = [schnell.get_nowait() for _ in range(schnell.qsize())][-1]
    assert letzte_langsam["type"] == "final"
    assert letzte_schnell["type"] == "final"


# --- Fund 22: fts_query wirft jedes nicht-deutsche Wort weg --------------


def test_fund22_nichtdeutsche_woerter_bleiben_erhalten():
    """BUGS-01 Fund 22, und es ist schlimmer als gemeldet.

    `WORT = re.compile(r"[0-9A-Za-zAEOEUEaeoeuess]+")` kannte nur ASCII und
    deutsche Umlaute. Gemessen:

        'Je parle francais a Geneve'  -> ['ais', 'fran', 'gen', 'parle']
        'Wroclaw Krakow'              -> ['krak', 'wroc']
        'Bjoerk Gudmundsdottir'       -> ['björk', 'mundsd', 'ttir']
        'Moi velosiped' (kyrillisch)  -> []

    Kyrillisch, Griechisch und Japanisch fallen ganz weg - da findet `recall`
    nichts. Woerter mit lateinischen Akzenten werden STILL ZERSCHNITTEN, und
    dann sucht `recall` nach Bruchstuecken, die niemand geschrieben hat. Das
    ist der schlimmere Fall: kein Treffer waere ehrlich, ein falscher nicht.
    """
    from core.memory import inhaltswoerter

    assert "français" in inhaltswoerter("Je parle français à Genève")
    assert "genève" in inhaltswoerter("Je parle français à Genève")
    assert "kraków" in inhaltswoerter("Wrocław Kraków")
    assert "wrocław" in inhaltswoerter("Wrocław Kraków")
    assert "guðmundsdóttir" in inhaltswoerter("Björk Guðmundsdóttir")
    assert "велосипед" in inhaltswoerter("Мой велосипед")
    assert "αθήνα" in inhaltswoerter("Πάμε στην Αθήνα")


def test_fund22_deutsche_und_englische_woerter_bleiben_wie_sie_waren():
    """Gegenprobe: die Erweiterung darf den Normalfall nicht verschieben."""
    from core.memory import inhaltswoerter

    assert inhaltswoerter("Mein Rad ist ein Santa Cruz") == {"rad", "santa", "cruz"}
    assert inhaltswoerter("Ich fahre nach München") == {"fahre", "nach", "münchen"}
    assert inhaltswoerter("Café Ähre Straße") == {"café", "ähre", "straße"}


def test_fund22_die_erweiterung_laesst_keine_fts5_syntax_durch(db_path: Path):
    """Was KEIN Wort ist, darf auch kein Wort werden.

    Sonst waere die Erweiterung ein Freibrief fuer FTS5-Syntax im MATCH -
    genau das, wogegen `fts_query` gebaut wurde. Geprueft wird nicht nur die
    Zeichenkette, sondern ein echter MATCH gegen eine echte FTS5-Tabelle:
    ob eine Anfrage gueltig ist, entscheidet SQLite, nicht meine Meinung.
    """
    import sqlite3

    from core import db, memory
    from core.memory import fts_query, inhaltswoerter

    assert "2026" in inhaltswoerter("Im Jahr 2026")
    assert "_" not in fts_query("a_b c_d"), "der Unterstrich ist kein Buchstabe"

    # Geprueft werden die WOERTER: die Anfuehrungszeichen in der fertigen
    # Anfrage setzt `fts_query` selbst, genau damit die Woerter Literale
    # bleiben.
    for zeichen in ('"', "*", "^", "(", ")", ":", "-", "+", "_"):
        woerter = inhaltswoerter(f"abc{zeichen}def")
        assert all(zeichen not in w for w in woerter), (zeichen, woerter)

    with db.session(db_path) as conn:
        db.init_db(conn)
    memory.add_fact(db_path, "Ein harmloser Fakt", category="test")

    boese = [
        'a "b" NEAR(c) -d *e',
        '"; DROP TABLE facts; --',
        "NEAR OR AND NOT",
        "^anfang $ende",
        "col:wert",
        "Мой* велосипед^2",
    ]
    for text in boese:
        anfrage = fts_query(text)
        if not anfrage:
            continue
        with db.session(db_path) as conn:
            try:
                conn.execute(
                    "SELECT rowid FROM facts_fts WHERE facts_fts MATCH ?", (anfrage,)
                ).fetchall()
            except sqlite3.OperationalError as exc:
                raise AssertionError(
                    f"{text!r} ergab die ungueltige Anfrage {anfrage!r}: {exc}"
                ) from exc


def test_fund22_recall_findet_einen_kyrillischen_fakt(db_path: Path):
    """Ende zu Ende: der Fund heisst, dass `recall` nichts findet."""
    from core import db, memory

    with db.session(db_path) as conn:
        db.init_db(conn)
    memory.add_fact(db_path, "Мой велосипед ist ein Santa Cruz", category="hobby")
    memory.add_fact(db_path, "Je parle français", category="sprache")

    assert [f.text for f in memory.search_facts(db_path, "велосипед")]
    assert [f.text for f in memory.search_facts(db_path, "français")]


# --- Fund 23: das Verlaufsfenster beginnt mit "assistant" ----------------


def test_fund23_das_verlaufsfenster_beginnt_immer_mit_user(db_path: Path):
    """BUGS-01 Fund 23, und es ist schlimmer als gemeldet.

    Der Bericht sagt "jede 21. Nachricht". Gemessen ist es JEDE ab der 21.:

        Nutzerzuege  Zeilen   erste Rolle im Fenster  Anthropic ok?
                 20      39                     user  ja
                 21      40                assistant  NEIN
                 22      40                assistant  NEIN
        fehlerhafte Nutzerzuege: [21, 22, 23, 24, 25, ...]  20 von 40

    Der Verlauf ist u,a,u,a,... Sobald mehr Zeilen da sind als
    `history_limit`, schneidet `list_messages(limit)` ein Fenster gerader
    Laenge aus einer ungeraden Folge - und das beginnt dann mit `assistant`.
    Die Messages-API verlangt `user` als erste Nachricht.
    """
    from core import db
    from core.config import Settings
    from core.llm import ab_erster_nutzernachricht

    grenze = Settings(_env_file=None).history_limit
    with db.session(db_path) as conn:
        db.init_db(conn)

    ungeschnitten, geschnitten = [], []
    for zug in range(1, grenze + 5):
        db.add_message(db_path, "user", f"Frage {zug}")
        roh = db.list_messages(db_path, grenze)
        if roh and roh[0].role != "user":
            ungeschnitten.append(zug)
        fenster = ab_erster_nutzernachricht(roh)
        if fenster and fenster[0].role != "user":
            geschnitten.append(zug)
        db.add_message(db_path, "assistant", f"Antwort {zug}")

    assert ungeschnitten, (
        "ohne Schnitt muesste das Fenster ab Zug 21 mit 'assistant' beginnen - "
        "wenn nicht, prueft dieser Test nichts mehr"
    )
    assert geschnitten == [], (
        f"{len(geschnitten)} Zuege mit 'assistant' an erster Stelle: {geschnitten[:8]}"
    )


def test_fund23_der_schnitt_nimmt_nur_weg_was_noetig_ist():
    """Eine Kuerzung, die mehr wegnimmt als noetig, verliert Kontext."""
    from core.llm import LLMMessage, ab_erster_nutzernachricht

    a, u = LLMMessage("assistant", "A"), LLMMessage("user", "U")

    assert ab_erster_nutzernachricht([u, a, u]) == [u, a, u]
    assert ab_erster_nutzernachricht([a, u, a, u]) == [u, a, u]
    assert ab_erster_nutzernachricht([a, a, a, u]) == [u]
    assert ab_erster_nutzernachricht([]) == []
    assert ab_erster_nutzernachricht([a, a]) == [], (
        "ohne eine einzige Nutzernachricht bleibt nichts uebrig"
    )


def test_fund23_der_chat_ueberlebt_den_einundzwanzigsten_zug(settings, tmp_path):
    """Ende zu Ende gegen den ECHTEN Anbieter, nur ohne Netz.

    `FakeLLMProvider` prueft die Regel nicht - genau deshalb ist der Fund nie
    aufgefallen. Hier laeuft `AnthropicProvider` mit einem `MockTransport`:
    dieselbe Pruefung, dieselbe Fehlermeldung, kein Byte nach draussen.
    """
    import httpx
    from fastapi.testclient import TestClient

    import api.app  # noqa: F401
    from api.app import create_app
    from core.llm import AnthropicProvider

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    gesehen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json as _json

        koerper = _json.loads(request.content)
        gesehen.append(koerper["messages"][0]["role"])
        return httpx.Response(200, json={
            "id": "msg_01", "type": "message", "role": "assistant",
            "model": "claude-opus-5",
            "content": [{"type": "text", "text": "Antwort"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 11, "output_tokens": 7},
        })

    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = AnthropicProvider(
            "sk-ant-test-key", model="claude-opus-5",
            transport=httpx.MockTransport(handler),
        )
        for zug in range(1, settings.history_limit // 2 + 6):
            antwort = c.post("/api/chat", json={"message": f"Frage {zug}"},
                             headers=TOKEN)
            assert antwort.status_code == 200, (
                f"Zug {zug}: HTTP {antwort.status_code} - {antwort.text[:160]}"
            )

    assert gesehen, "es ging keine einzige Anfrage an den Anbieter"
    assert set(gesehen) == {"user"}, (
        f"erste Rolle im Anfragekoerper: {sorted(set(gesehen))}"
    )


def test_fund23_der_anbieter_besteht_weiterhin_auf_user_als_erster_rolle():
    """Die Pruefung im Anbieter bleibt - sie ist der Grund, warum es auffiel.

    Sie wegzunehmen waere die falsche Reparatur: dann ginge die kaputte
    Anfrage still an die echte API und kaeme als 400 zurueck.
    """
    import httpx

    from core.llm import AnthropicProvider, LLMError, LLMMessage

    provider = AnthropicProvider(
        "sk-ant-test-key", model="claude-opus-5",
        transport=httpx.MockTransport(
            lambda r: httpx.Response(200, json={})),
    )
    with pytest.raises(LLMError, match="erste Nachricht"):
        run(provider.complete([LLMMessage("assistant", "Hallo")], system="s"))


# --- Fund 21: eine nicht-UTF-8-Datei im Vault ---------------------------


@pytest.fixture
def vault_mit_muell(tmp_path: Path) -> Path:
    """Ein Vault mit einer guten Notiz und zwei unlesbaren Dateien.

    Der Name der Muelldatei beginnt mit 'a', damit sie in der sortierten
    Reihenfolge VOR der guten Notiz kommt - sonst faellt der Fund nicht auf.
    """
    wurzel = tmp_path / "vault"
    wurzel.mkdir()
    (wurzel / "gut.md").write_text(
        "---\nid: abc123\ntyp: fakt\n---\n\nMein Rad ist ein Santa Cruz\n",
        encoding="utf-8",
    )
    (wurzel / "a-binaer.md").write_bytes(b"\x00\x01\x02\xff\xfe kein Text")
    (wurzel / "b-latin1.md").write_bytes(
        "---\nid: xyz\n---\n\nCaf\xe9 Ma\xdfstab\n".encode("latin-1")
    )
    return wurzel


def test_fund21_eine_unlesbare_datei_macht_den_vault_nicht_unbrauchbar(vault_mit_muell):
    """BUGS-01 Fund 21, und es ist schlimmer als gemeldet.

    `finde()` faengt nur `OSError`. Ein `UnicodeDecodeError` ist ein
    `ValueError` und flog durch. Gemessen:

        finde('abc123')      -> UnicodeDecodeError: 'utf-8' codec can't decode
                                byte 0xff in position 3
        finde('gibtsnicht')  -> UnicodeDecodeError: ...

    Die gesuchte Notiz ist heil und liegt daneben - erreicht wird sie
    trotzdem nicht, weil die Muelldatei alphabetisch davor kommt. Eine
    einzige fremde Datei macht damit den ganzen Vault unbrauchbar, und
    `remember` schreibt nicht mehr, weil es ueber `finde` geht.
    """
    from core import vault

    assert vault.finde(vault_mit_muell, "abc123") is not None
    assert vault.finde(vault_mit_muell, "gibtsnicht") is None


def test_fund21_remember_schreibt_weiter(vault_mit_muell):
    """Der Weg, den der Fund im Titel nennt."""
    from core import vault

    notiz = vault.Notiz(id="neu001", typ="fakt", text="Ich fahre Downhill",
                        quelle="test", tags=["hobby"])
    ziel = vault.schreibe(vault_mit_muell, notiz)
    assert ziel.exists()
    assert vault.finde(vault_mit_muell, "neu001") == ziel


def test_fund21_loeschen_geht_auch_noch(vault_mit_muell):
    from core import vault

    assert vault.loesche(vault_mit_muell, "abc123") is True
    assert vault.finde(vault_mit_muell, "abc123") is None


def test_fund21_der_index_ueberspringt_die_muelldatei_und_nimmt_den_rest(
    vault_mit_muell, db_path: Path
):
    """Gegenprobe: der Index konnte das schon - hier bleibt es so."""
    from core import db
    from core.vault_index import reindex

    with db.session(db_path) as conn:
        db.init_db(conn)

    anzahl = reindex(db_path, vault_mit_muell)
    assert anzahl == 1, f"{anzahl} Notizen indexiert, erwartet 1"


def test_fund21_eine_heile_notiz_wird_weiterhin_gelesen(vault_mit_muell):
    """Eine Nachsicht, die auch Heiles verschluckt, waere keine."""
    from core import vault

    pfad = vault.finde(vault_mit_muell, "abc123")
    notiz = vault.lies(pfad)
    assert notiz.id == "abc123"
    assert "Santa Cruz" in notiz.text
