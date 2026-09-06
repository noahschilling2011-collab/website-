"""FIX-11 Punkt 2: Grenzen an Modell-Argumenten (Vorschlag 14).

Der Nachweis vom 06.09.2026, gegen den FakeLLMProvider:

    remember(text='x' * 100_000)  -> ok=True, facts=1
    naechster Chat-Systemprompt    -> 100.703 Zeichen
    memory.kontextblock            -> 120.563 Zeichen bei sechs alten Fakten
    datei_suchen('../**/*.txt')    -> listet Dateien AUSSERHALB der Wurzeln
    datei_suchen('/tmp/*.txt')     -> NotImplementedError aus rglob
    Symlink in der Wurzel          -> steht mit Namen und Groesse in der Liste

Drei Grenzen, jede an EINER Stelle: `memory.MAX_FAKT_TEXT` fuer beide
Schreibwege (Tabelle und Vault), `memory.MAX_KONTEXTBLOCK` fuer beide
Kontextbloecke, und `dateien.pruefe_muster` plus die aufgeloeste Pruefung je
Treffer fuer die Suche. Die Zahlen 100.000 und 6.000 stehen FEST in den
Tests - eine hochgesetzte Grenze macht sie rot, nicht nur "MAX + 1".
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import api.app  # noqa: F401 - registriert die Werkzeuge
from api.app import create_app
from core import db, gedaechtnis, memory
from core.dateien import PfadAbgelehnt, suche
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.tools import registry
from core.tools.datei_tools import DateiLesen, DateiSuchen
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}


@pytest.fixture
def pfad(db_path):
    with db.session(db_path) as conn:
        db.init_db(conn)
    registry.get("remember").db_path = db_path
    return db_path


@pytest.fixture
def welt(tmp_path: Path):
    """Frische Datenbank plus leerer Vault - der zweite Schreibweg."""
    vault = tmp_path / "Vault"
    vault.mkdir()
    pfad = tmp_path / "jarvis.db"
    with db.session(pfad) as conn:
        db.init_db(conn)
    return pfad, vault


# --- remember: die Laengengrenze -------------------------------------------


def test_remember_mit_100000_zeichen_wird_abgelehnt(pfad):
    """Der Fund. Die Zahl steht fest, damit eine hochgesetzte Grenze den Test
    wieder rot macht - nicht nur "MAX + 1"."""
    assert memory.MAX_FAKT_TEXT <= 1_000, memory.MAX_FAKT_TEXT
    e = run(registry.get("remember").execute(text="x" * 100_000, category="a"))
    assert e.ok is False
    assert "zu lang" in e.display and str(memory.MAX_FAKT_TEXT) in e.display
    assert "100000" in e.display, e.display
    assert "zu lang" in (e.error or "")
    assert memory.list_facts(pfad) == []


def test_remember_an_der_grenze_geht_noch_und_darueber_nicht(pfad):
    """Gegenprobe gegen eine Grenze, die alles ablehnt - und gegen den
    Zaunpfahlfehler."""
    werkzeug = registry.get("remember")
    assert run(werkzeug.execute(text="x" * memory.MAX_FAKT_TEXT, category="a")).ok is True
    assert len(memory.list_facts(pfad)) == 1
    e = run(werkzeug.execute(text="x" * (memory.MAX_FAKT_TEXT + 1), category="a"))
    assert e.ok is False
    assert len(memory.list_facts(pfad)) == 1


def test_remember_mit_vault_hat_dieselbe_grenze(welt, tmp_path):
    """Beide Wege, EINE Grenze: mit Vault entsteht keine Datei, kein
    Indexeintrag - und der Hinweis nennt weder Pfad noch Vault-Ordner."""
    pfad, vault = welt
    werkzeug = registry.get("remember")
    werkzeug.db_path = pfad
    werkzeug.vault_pfad = str(vault)
    e = run(werkzeug.execute(text="x" * 100_000, category="a"))
    assert e.ok is False
    assert "zu lang" in e.display
    assert str(tmp_path) not in e.display and str(tmp_path) not in (e.error or "")
    assert list(vault.rglob("*.md")) == []
    assert gedaechtnis.liste(pfad, str(vault)) == []


def test_ueber_den_chat_bleibt_das_gedaechtnis_leer(settings):
    """Ende zu Ende: das Modell ruft remember mit 100.000 Zeichen. Kein 500,
    der Aufruf steht als ok=False im Protokoll, kein Fakt."""
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            FakeTurn(tool_uses=(ToolUse("t1", "remember", {
                "text": "x" * 100_000, "category": "a",
            }),)),
            "Das war zu lang.",
        ])
        antwort = c.post("/api/chat", json={"message": "Merk dir das alles."},
                         headers=TOKEN)
        assert antwort.status_code == 200, antwort.text
        aufrufe = antwort.json()["tool_calls"]
        assert len(aufrufe) == 1 and aufrufe[0]["ok"] is False
        assert "zu lang" in aufrufe[0]["display"]
        assert c.get("/api/memory", headers=TOKEN).json() == []


# --- Die API bildet den ValueError als 422 ab, nicht als 500 ---------------


def test_post_memory_mit_1500_zeichen_gibt_422_und_legt_nichts_an(settings):
    """Seit der Abnahme nennt `FactCreate` dieselbe Zahl wie der Pruefpunkt
    (MAX_FAKT_TEXT) - 1.500 faellt also schon an der Schema-Grenze durch,
    mit derselben Zahl im Text. Wichtig bleibt: 422, kein 500, kein Fakt."""
    with TestClient(create_app(settings)) as c:
        r = c.post("/api/memory", json={"text": "x" * 1_500}, headers=TOKEN)
        assert r.status_code == 422, r.text
        assert str(memory.MAX_FAKT_TEXT) in r.text
        assert c.get("/api/memory", headers=TOKEN).json() == []


def test_der_kern_lehnt_auch_ab_wenn_das_schema_es_durchliesse(settings):
    """Der Pruefpunkt sitzt im Kern, nicht nur an der API: ein Fakt knapp
    ueber der Grenze faellt in `gedaechtnis.anlegen` durch, mit Klartext.
    (Der Weg, den das Werkzeug `remember` nimmt.)"""
    with db.session(settings.db_path) as conn:
        db.init_db(conn)
    with pytest.raises(ValueError) as fehler:
        gedaechtnis.anlegen(settings.db_path, settings.vault_pfad,
                            "x" * (memory.MAX_FAKT_TEXT + 1))
    text = str(fehler.value)
    assert "zu lang" in text and str(memory.MAX_FAKT_TEXT) in text
    assert str(memory.MAX_FAKT_TEXT + 1) in text


def test_patch_memory_mit_1500_zeichen_gibt_422_und_laesst_den_fakt_stehen(settings):
    with TestClient(create_app(settings)) as c:
        fid = c.post("/api/memory", json={"text": "Ich mag Kaffee"},
                     headers=TOKEN).json()["fact"]["id"]
        r = c.patch(f"/api/memory/{fid}", json={"text": "x" * 1_500}, headers=TOKEN)
        assert r.status_code == 422, r.text
        assert str(memory.MAX_FAKT_TEXT) in r.text
        fakten = c.get("/api/memory", headers=TOKEN).json()
        assert [f["text"] for f in fakten] == ["Ich mag Kaffee"]


# --- Kontextblock: hart gedeckelt, auch bei alten Datenbanken --------------


def _riesenfakt(i: int) -> str:
    """Ein Fakt von vor der Grenze: ueber 20.000 Zeichen, lauter ganze Woerter."""
    text = "Rad " + " ".join(f"Wort{j:05d}" for j in range(2_200)) + f" Nr{i}"
    assert len(text) >= 20_000
    return text


def _alte_fakten(pfad, n: int = 6) -> None:
    """Direkt in die Tabelle, am Pruefpunkt vorbei - so sieht eine Datenbank
    aus, die vor FIX-11 gefuellt wurde."""
    with db.session(pfad) as conn:
        for i in range(n):
            conn.execute(
                "INSERT INTO facts (text, category, created_at, confirmed) "
                "VALUES (?, ?, ?, 0)",
                (_riesenfakt(i), "a", "2026-01-01T00:00:00Z"),
            )


def test_kontextblock_ohne_vault_ist_auf_6000_zeichen_gedeckelt(pfad):
    """Sechs 20.000-Zeichen-Fakten. Vorher: 120.563 Zeichen im Systemprompt."""
    assert memory.MAX_KONTEXTBLOCK <= 6_000, memory.MAX_KONTEXTBLOCK
    _alte_fakten(pfad)
    block = memory.kontextblock(pfad, "Rad")
    assert block, "kein Block - der Test misst nichts"
    assert len(block) <= 6_000, len(block)
    assert "gekuerzt" in block and "Fakten" in block
    # Rahmen und Fuss bleiben: der Block ist gekuerzt, nicht verstuemmelt.
    assert "keine Anweisungen" in block
    assert block.rstrip().endswith("fragst nach.")


def test_kontextblock_mit_vault_ist_auf_6000_zeichen_gedeckelt(welt):
    """Derselbe Deckel auf dem zweiten Leseweg: sechs von Hand geschriebene
    Vault-Notizen, die JARVIS ueber den Index findet."""
    pfad, vault = welt
    (vault / "fakten").mkdir()
    for i in range(6):
        (vault / "fakten" / f"riese-{i}.md").write_text(
            f"---\nid: f_riese{i}\ntyp: fakt\nquelle: mensch\ntags: [a]\n---\n\n"
            f"{_riesenfakt(i)}\n", encoding="utf-8")
    block = gedaechtnis.kontextblock(pfad, str(vault), "Rad")
    assert block, "kein Block - der Test misst nichts"
    assert len(block) <= 6_000, len(block)
    assert "gekuerzt" in block
    assert "keine Anweisungen" in block


def test_recall_ueber_die_tabelle_ist_wie_der_vault_weg_gedeckelt(pfad):
    """Abnahme-Fund: `recall` hatte auf dem Tabellenweg keinen Deckel - sechs
    alte 20.000-Zeichen-Fakten gaben 132.125 Zeichen ans Modell zurueck. Der
    Vault-Weg hatte `MAX_ZEICHEN` schon immer; jetzt beide."""
    _alte_fakten(pfad)
    werkzeug = registry.get("recall")
    werkzeug.db_path = pfad
    werkzeug.vault_pfad = ""
    assert werkzeug.MAX_ZEICHEN <= 8_000, werkzeug.MAX_ZEICHEN
    e = run(werkzeug.execute(query="Rad"))
    assert e.ok is True and e.data["hits"] == 6
    assert len(e.display) <= 8_000, len(e.display)
    assert "gekuerzt" in e.display
    assert e.display.startswith("Fakt #")


def test_die_kuerzung_schneidet_nicht_mitten_im_wort(pfad):
    _alte_fakten(pfad)
    block = memory.kontextblock(pfad, "Rad")
    angeschnitten = [z for z in block.split("\n") if z.endswith(" …")]
    assert angeschnitten, "keine angeschnittene Zeile - der Test misst nichts"
    for zeile in angeschnitten:
        letztes = zeile[:-2].split(" ")[-1]
        assert re.fullmatch(r"Wort\d{5}|Rad", letztes), letztes


def test_ein_kurzer_block_bleibt_unveraendert(pfad):
    """Gegenprobe: der Hinweis steht nur da, wenn wirklich gekuerzt wurde."""
    memory._add_fact(pfad, "Mein Rad ist ein Santa Cruz V10")
    block = memory.kontextblock(pfad, "Welches Rad?")
    assert "Santa Cruz V10" in block
    assert "gekuerzt" not in block and "…" not in block


def test_kappe_block_haelt_den_deckel_in_jedem_fall():
    """Direkt an der Funktion, mit den Faellen, die eine Rechnung kippen:
    ein Riesenwort ohne Leerzeichen, viele mittlere Zeilen, sehr viele kurze."""
    kopf, fuss = "Kopf\n", "\n\nFuss."
    for zeilen in (["y" * 20_000], ["Wort " * 50] * 100, ["a b c"] * 5_000):
        block = memory.kappe_block(kopf, zeilen, fuss, deckel=500)
        assert len(block) <= 500, len(block)
        assert "gekuerzt" in block
        assert block.startswith(kopf) and block.endswith(fuss)
    # Ein Riesenwort wird nie zerschnitten - dann fehlt es ganz, mit Hinweis.
    assert "yyyy" not in memory.kappe_block(kopf, ["y" * 20_000], fuss, deckel=500)
    # Und was passt, bleibt wortgleich.
    assert memory.kappe_block(kopf, ["a", "b"], fuss, deckel=500) == "Kopf\na\nb\n\nFuss."


# --- datei_suchen: kein Weg aus der Wurzel hinaus --------------------------


@pytest.fixture
def wurzel(tmp_path: Path) -> Path:
    w = tmp_path / "Dokumente"
    w.mkdir()
    (w / "a.txt").write_text("drinnen", encoding="utf-8")
    # Das Ziel, das vorher in der Trefferliste stand.
    (tmp_path / "geheim.txt").write_text("draussen", encoding="utf-8")
    return w


def _suchwerkzeug(wurzel: Path) -> DateiSuchen:
    t = DateiSuchen()
    t.datei_wurzeln = str(wurzel)
    return t


@pytest.mark.parametrize("muster", ["../*.txt", "../**/*.txt", "*/../../*.txt"])
def test_ein_muster_mit_punkt_punkt_wird_abgewiesen(wurzel, tmp_path, muster):
    """Der Fund: `..` war in Z. 145 ausdruecklich erlaubt und ging roh an
    rglob. Jetzt: klare Absage, ohne Pfad, ohne Treffer."""
    with pytest.raises(PfadAbgelehnt):
        suche(muster, [wurzel])
    e = run(_suchwerkzeug(wurzel).execute(muster=muster))
    assert e.ok is False
    assert "freigegebenen Ordner" in e.display
    for feld in (e.display or "", e.error or ""):
        assert "geheim" not in feld and str(tmp_path) not in feld, feld
    assert not e.data


def test_ein_absolutes_muster_wird_abgewiesen_statt_zu_platzen(wurzel, tmp_path):
    """Vorher flog `rglob` mit NotImplementedError ("Non-relative patterns
    are unsupported") - und ein Muster mit dem echten Pfad haette den Pfad
    in der Fehlermeldung gehabt."""
    for muster in (str(tmp_path / "*.txt"), "/etc/*", "C:\\Users\\*.txt",
                   "\\\\server\\freigabe\\*"):
        e = run(_suchwerkzeug(wurzel).execute(muster=muster))
        assert e.ok is False, muster
        assert "absoluter Pfad" in e.display, muster
        for feld in (e.display or "", e.error or ""):
            assert str(tmp_path) not in feld and "/etc" not in feld, feld


def test_ein_laufwerksrelatives_muster_wird_abgewiesen(wurzel):
    """Abnahme-Fund: `C:*.txt` ist fuer `is_absolute()` nicht absolut, unter
    Windows laesst es `rglob` aber mit NotImplementedError platzen. Absage."""
    for muster in ("C:*.txt", "D:Dokumente\\*.md"):
        with pytest.raises(PfadAbgelehnt):
            suche(muster, [wurzel])
        e = run(_suchwerkzeug(wurzel).execute(muster=muster))
        assert e.ok is False and "absoluter Pfad" in e.display, muster
        assert "C:" not in e.display and "D:" not in e.display


def test_die_inhaltssuche_darf_punkte_enthalten(wurzel):
    """Bei inhalt=True ist das Muster ein Suchwort und beruehrt keinen Pfad -
    "dann..." ist dort kein Ausbruchsversuch."""
    (wurzel / "b.txt").write_text("Und dann... nichts\n", encoding="utf-8")
    e = run(_suchwerkzeug(wurzel).execute(muster="dann...", inhalt=True))
    assert e.ok is True and e.data["anzahl"] == 1
    assert e.data["treffer"][0]["pfad"] == "Dokumente/b.txt"


@pytest.mark.skipif(os.name == "nt", reason="Symlinks brauchen unter Windows Rechte")
def test_ein_symlink_nach_draussen_wird_nicht_gelistet(wurzel, tmp_path):
    """Dieselbe Pruefung wie `pruefe()`: zuerst aufloesen, dann vergleichen.
    Vorher stand der Symlink mit Namen und Groesse in der Trefferliste."""
    bruecke = wurzel / "harmlos.txt"
    bruecke.symlink_to(tmp_path / "geheim.txt")
    assert bruecke.is_symlink() and bruecke.exists(), "Symlink nicht angelegt"

    assert [f.pfad for f in suche("*", [wurzel])] == ["Dokumente/a.txt"]
    e = run(_suchwerkzeug(wurzel).execute(muster="harmlos"))
    assert e.ok is True and e.data["treffer"] == []


@pytest.mark.skipif(os.name == "nt", reason="Symlinks brauchen unter Windows Rechte")
def test_ein_ordner_symlink_nach_draussen_wird_nicht_durchsucht(wurzel, tmp_path):
    """rglob steigt in 3.11 nicht in verlinkte Ordner ab - aber ein Muster
    mit dem Linknamen davor ("ordnerlink/*.txt") liest den Ordner direkt.
    Die aufgeloeste Pruefung je Treffer faengt auch das."""
    draussen = tmp_path / "draussen"
    draussen.mkdir()
    (draussen / "z.txt").write_text("z", encoding="utf-8")
    (wurzel / "ordnerlink").symlink_to(draussen)

    assert [f.pfad for f in suche("ordnerlink/*.txt", [wurzel])] == []
    assert [f.pfad for f in suche("*.txt", [wurzel])] == ["Dokumente/a.txt"]


def test_normale_suche_und_lesen_bleiben_wie_sie_sind(wurzel):
    e = run(_suchwerkzeug(wurzel).execute(muster="*.txt"))
    assert e.ok is True
    assert [t["pfad"] for t in e.data["treffer"]] == ["Dokumente/a.txt"]
    # datei_lesen bleibt unveraendert - der Pfad aus dem Treffer geht.
    l = DateiLesen()
    l.datei_wurzeln = str(wurzel)
    gelesen = run(l.execute(pfad="Dokumente/a.txt"))
    assert gelesen.ok is True and "drinnen" in gelesen.data["ausschnitt"]


# --- Nachtrag aus der Abnahme (Claude, 06.09.2026) ---------------------------


def test_ein_abgelehntes_riesenargument_wird_gekuerzt_gespeichert(db_path):
    """Fund der Abnahme: das Werkzeug lehnt 100.000 Zeichen ab, aber der
    Aufruf selbst stand vollstaendig in tool_calls und ging ueber
    /api/messages an die Oberflaeche - also genau der Ballast, den die
    Grenze verhindern sollte, nur an anderer Stelle."""
    with db.session(db_path) as conn:
        db.init_db(conn)
    zeile = db.add_tool_call(
        db_path, message_id=None, name="remember",
        arguments={"text": "x" * 100_000, "category": "allgemein"}, ok=False,
    )
    gespeichert = zeile.arguments["text"]
    assert len(gespeichert) < 3_000, len(gespeichert)
    assert gespeichert.startswith("x" * 100)
    assert "gekuerzt" in gespeichert and "98000" in gespeichert
    # Kurze Argumente bleiben unangetastet - Wort fuer Wort.
    assert zeile.arguments["category"] == "allgemein"
    # Und so steht es auch wirklich in der Datenbank, nicht nur im Rueckgabewert.
    with db.session(db_path) as conn:
        [roh] = conn.execute("SELECT arguments FROM tool_calls").fetchall()
    assert len(roh["arguments"]) < 3_000


def test_die_openapi_grenze_ist_dieselbe_zahl_wie_der_pruefpunkt():
    """Sonst verspricht die Beschreibung 2.000 Zeichen und der Kern lehnt
    bei 1.001 ab - der Nutzer sieht einen 422, den das Schema ausschliesst."""
    from api.schemas import FactCreate, FactUpdate
    from core.memory import MAX_FAKT_TEXT

    for modell in (FactCreate, FactUpdate):
        [grenze] = [
            m.max_length for m in modell.model_fields["text"].metadata
            if hasattr(m, "max_length")
        ]
        assert grenze == MAX_FAKT_TEXT, modell.__name__
