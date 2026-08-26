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
