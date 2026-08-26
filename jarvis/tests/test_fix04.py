"""Die Definition of Done aus `docs/FIX-04.md`.

Das Prinzip, an dem hier alles gemessen wird:

    vault/*.md    = WAHRHEIT.  Menschenlesbar, in Obsidian editierbar.
    SQLite + FTS5 = INDEX.     Abgeleitet, jederzeit wegwerfbar.

Der Pruefstein steht in `test_dod5_...`: Datenbank loeschen, neu aufbauen,
kein Fakt darf fehlen. Wer diesen Test rot macht, hat das Prinzip verletzt.
"""

from __future__ import annotations

import asyncio
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import api.app  # noqa: F401  - registriert die Werkzeuge
from api.app import create_app
from core.config import Settings
from core.tools import registry
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}
WURZEL = Path(__file__).resolve().parent.parent


@pytest.fixture
def welt(tmp_path: Path):
    """Eine frische Datenbank und ein frisch angelegter, leerer Vault."""
    from core import db

    vault = tmp_path / "Vault"
    vault.mkdir()
    pfad = tmp_path / "jarvis.db"
    with db.session(pfad) as conn:
        db.init_db(conn)
    einstellungen = Settings(
        _env_file=None,
        db_path=pfad,
        vault_pfad=str(vault),
        jarvis_token="test-token-123",
    )
    return einstellungen, vault


def _klient(einstellungen):
    return TestClient(create_app(einstellungen))


def _werkzeug(name):
    return registry.get(name)


def _zahlen(einstellungen, vault: Path) -> tuple[int, int, list[str]]:
    """(.md im Vault, Zeilen im Index, ids im Index)"""
    con = sqlite3.connect(einstellungen.db_path)
    try:
        anzahl = con.execute("SELECT count(*) FROM vault_notizen").fetchone()[0]
        ids = sorted(r[0] for r in con.execute("SELECT id FROM vault_notizen"))
    finally:
        con.close()
    return len(list(vault.rglob("*.md"))), anzahl, ids


# --- DoD 1: ein Schreibweg -----------------------------------------------


def test_dod1_merken_erzeugt_eine_datei_und_eine_zeile_im_index(welt):
    """Und das Panel sieht sie sofort - das war der Fund."""
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        ergebnis = run(_werkzeug("remember").execute(
            text="Ich fahre Downhill und mein Rad ist ein Santa Cruz V10",
            category="ausruestung"))
        assert ergebnis.ok, ergebnis.error

        md, im_index, ids = _zahlen(einstellungen, vault)
        assert md == 1, "genau eine neue .md-Datei"
        assert im_index == 1, "und genau eine Zeile im Index"

        panel = c.get("/api/memory", headers=TOKEN).json()
    assert len(panel) == 1, panel
    assert panel[0]["id"] == ids[0]
    assert "Santa Cruz V10" in panel[0]["text"]
    assert panel[0]["pfad"].endswith(".md"), panel[0]
    assert (vault / panel[0]["pfad"]).exists(), "der Pfad im Panel muss stimmen"


def test_dod1_das_panel_schreibt_zuerst_in_den_vault(welt):
    """FIX-04 Schritt 2: kein Schreibweg fasst die Datenbank zuerst an."""
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        antwort = c.post("/api/memory",
                         json={"text": "Noah spricht Schwaebisch", "category": "sprache"},
                         headers=TOKEN)
        assert antwort.status_code == 201, antwort.text
        kennung = antwort.json()["fact"]["id"]

    assert isinstance(kennung, str) and kennung.startswith("f_"), kennung
    md, im_index, ids = _zahlen(einstellungen, vault)
    assert md == 1 and im_index == 1 and ids == [kennung]

    # und recall - der andere Leser - findet es auch
    ergebnis = run(_werkzeug("recall").execute(query="Schwaebisch"))
    assert "Schwaebisch" in ergebnis.display, ergebnis.display


def test_dod1_kein_endpunkt_schreibt_mehr_direkt_in_facts(welt):
    """Der Riss war genau das. Mit Vault bleibt `facts` leer."""
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        c.post("/api/memory", json={"text": "Noah wohnt in Innsbruck",
                                    "category": "ort"}, headers=TOKEN)
        run(_werkzeug("remember").execute(text="Noah faehrt Downhill",
                                          category="hobby"))

    con = sqlite3.connect(einstellungen.db_path)
    try:
        in_facts = con.execute("SELECT count(*) FROM facts").fetchone()[0]
        im_vault = con.execute("SELECT count(*) FROM vault_notizen").fetchone()[0]
    finally:
        con.close()
    assert in_facts == 0, f"{in_facts} Zeile(n) in facts - jemand schreibt vorbei"
    assert im_vault == 2


# --- DoD 2: der Fakt steht im Systemprompt -------------------------------


def test_dod2_der_gemerkte_fakt_steht_im_systemprompt(welt):
    """Phase-3-DoD 2, mit Vault. War still kaputt: der Block blieb IMMER leer."""
    from core import gedaechtnis

    einstellungen, vault = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Santa Cruz V10", category="ausruestung"))

    block = gedaechtnis.kontextblock(
        einstellungen.db_path, einstellungen.vault_pfad, "Was fuer ein Rad fahre ich?"
    )
    assert "Santa Cruz V10" in block, repr(block)


def test_dod2_ohne_treffer_bleibt_der_block_leer(welt):
    """Gegenprobe: ein Block, der immer etwas liefert, ist wertlos."""
    from core import gedaechtnis

    einstellungen, vault = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz",
                                          category="ausruestung"))
    block = gedaechtnis.kontextblock(
        einstellungen.db_path, einstellungen.vault_pfad, "Quantenchromodynamik"
    )
    assert block == "", repr(block)


# --- DoD 3: der Fund selbst ----------------------------------------------


def test_dod3_eine_von_hand_angelegte_datei_finden_recall_und_panel(welt):
    """Der Fund, der repariert werden sollte - hier wird er bewiesen."""
    einstellungen, vault = welt
    (vault / "fakten").mkdir()
    (vault / "fakten" / "von-hand.md").write_text(
        "---\nid: f_handarbeit\ntyp: fakt\nquelle: mensch\ntags: [sprache]\n---\n\n"
        "Noah spricht Schwaebisch\n", encoding="utf-8")

    with _klient(einstellungen) as c:
        ergebnis = run(_werkzeug("recall").execute(query="Schwaebisch"))
        panel = c.get("/api/memory", headers=TOKEN).json()

    assert "Schwaebisch" in ergebnis.display, ergebnis.display
    assert [p["id"] for p in panel] == ["f_handarbeit"], panel


def test_dod3_eine_aenderung_in_obsidian_wird_beim_lesen_bemerkt(welt):
    """Schritt 3: Zeitstempel gegen den Index, ohne Ueberwachung."""
    import os
    import time as _t

    einstellungen, vault = welt
    (vault / "fakten").mkdir()
    datei = vault / "fakten" / "von-hand.md"
    datei.write_text(
        "---\nid: f_hand\ntyp: fakt\n---\n\nNoah spricht Schwaebisch\n",
        encoding="utf-8")

    with _klient(einstellungen) as c:
        assert len(c.get("/api/memory", headers=TOKEN).json()) == 1

        _t.sleep(0.01)
        datei.write_text(
            "---\nid: f_hand\ntyp: fakt\n---\n\nNoah spricht Bairisch\n",
            encoding="utf-8")
        os.utime(datei, (datei.stat().st_atime, datei.stat().st_mtime + 5))

        panel = c.get("/api/memory", headers=TOKEN).json()
    assert panel[0]["text"] == "Noah spricht Bairisch", panel


# --- DoD 4: loeschen loescht die Wahrheit --------------------------------


def test_dod4_loeschen_im_panel_entfernt_die_datei_und_den_eintrag(welt):
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        angelegt = c.post("/api/memory",
                          json={"text": "Noah spricht Schwaebisch", "category": "sprache"},
                          headers=TOKEN).json()["fact"]
        datei = vault / angelegt["pfad"]
        assert datei.exists()

        weg = c.delete(f"/api/memory/{angelegt['id']}", headers=TOKEN)
        assert weg.status_code == 204, weg.text

        assert not datei.exists(), "die Datei ist die Wahrheit - sie muss weg"
        assert c.get("/api/memory", headers=TOKEN).json() == []
        ergebnis = run(_werkzeug("recall").execute(query="Schwaebisch"))
    assert "Nichts" in ergebnis.display, ergebnis.display


def test_dod4_ein_unbekannter_schluessel_gibt_404(welt):
    einstellungen, _ = welt
    with _klient(einstellungen) as c:
        assert c.delete("/api/memory/f_gibtsnicht", headers=TOKEN).status_code == 404


# --- DoD 5: DER PRUEFSTEIN ------------------------------------------------


def test_dod5_datenbank_weg_reindex_kein_fakt_fehlt(welt):
    """Der Pruefstein: der Index ist wegwerfbar, der Vault ist die Wahrheit.

    Wer diesen Test rot macht, hat irgendwo Zustand in die Datenbank gelegt,
    der nicht in einer Datei steht.
    """
    import os

    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz V10",
                                          category="ausruestung"))
        c.post("/api/memory", json={"text": "Noah spricht Schwaebisch",
                                    "category": "sprache"}, headers=TOKEN)
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Propain Rage",
                                          category="ausruestung"))

    md_vorher, index_vorher, ids_vorher = _zahlen(einstellungen, vault)
    assert md_vorher == 3 and index_vorher == 3

    # Auch der Widerspruch muss den Neuaufbau ueberleben.
    con = sqlite3.connect(einstellungen.db_path)
    widersprueche_vorher = sorted(
        con.execute("SELECT id, widerspruch FROM vault_notizen "
                    "WHERE widerspruch IS NOT NULL").fetchall())
    con.close()
    assert widersprueche_vorher, "ohne Widerspruch prueft dieser Test zu wenig"

    Path(einstellungen.db_path).unlink()
    for anhang in ("-wal", "-shm"):
        rest = Path(str(einstellungen.db_path) + anhang)
        if rest.exists():
            rest.unlink()
    assert not Path(einstellungen.db_path).exists()

    umgebung = dict(os.environ,
                    JARVIS_DB_PATH=str(einstellungen.db_path),
                    VAULT_PFAD=str(vault),
                    JARVIS_TOKEN="test-token-123",
                    PYTHONPATH=str(WURZEL))
    lauf = subprocess.run([sys.executable, "-m", "scripts.reindex"],
                          cwd=str(WURZEL), env=umgebung,
                          capture_output=True, text=True)
    assert lauf.returncode == 0, lauf.stderr

    md_nachher, index_nachher, ids_nachher = _zahlen(einstellungen, vault)
    assert index_nachher == index_vorher, f"{index_vorher} -> {index_nachher}"
    assert ids_nachher == ids_vorher, (ids_vorher, ids_nachher)

    con = sqlite3.connect(einstellungen.db_path)
    widersprueche_nachher = sorted(
        con.execute("SELECT id, widerspruch FROM vault_notizen "
                    "WHERE widerspruch IS NOT NULL").fetchall())
    con.close()
    assert widersprueche_nachher == widersprueche_vorher, (
        "der Widerspruch hat den Neuaufbau nicht ueberlebt - dann steht er in "
        "der Datenbank statt in der Datei"
    )


# --- DoD 6: umbenennen ----------------------------------------------------


def test_dod6_umbenennen_behaelt_die_id_und_erzeugt_kein_duplikat(welt):
    from core.vault_index import reindex

    einstellungen, vault = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz V10",
                                          category="ausruestung"))
    _, index_vorher, ids_vorher = _zahlen(einstellungen, vault)

    eine = sorted(vault.rglob("*.md"))[0]
    eine.rename(eine.with_name("Ganz-anders-benannt.md"))
    reindex(einstellungen.db_path, vault)

    _, index_nachher, ids_nachher = _zahlen(einstellungen, vault)
    assert ids_nachher == ids_vorher, (ids_vorher, ids_nachher)
    assert index_nachher == index_vorher, "kein Duplikat"


# --- DoD 7: Konflikterkennung --------------------------------------------


def test_dod7_ein_widersprechender_fakt_wird_als_konflikt_sichtbar(welt):
    """Phase-3-DoD 5, mit Vault. War mit gesetztem VAULT_PFAD verschwunden."""
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        erst = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Santa Cruz V10", category="ausruestung"))
        zweit = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Propain Rage", category="ausruestung"))

        assert "ACHTUNG" in zweit.display, zweit.display
        assert erst.data["id"] in zweit.display

        panel = {p["id"]: p for p in c.get("/api/memory", headers=TOKEN).json()}

    assert len(panel) == 2, "der alte Fakt bleibt stehen"
    neuer = panel[zweit.data["id"]]
    assert neuer["conflicts_with"] == erst.data["id"], neuer
    assert panel[erst.data["id"]]["conflicts_with"] is None, "der alte bleibt unberuehrt"

    # Und der Widerspruch steht in der WAHRHEIT, nicht nur im Index.
    datei = vault / neuer["pfad"]
    assert f"widerspruch: {erst.data['id']}" in datei.read_text(encoding="utf-8")


def test_dod7_der_widerspruch_laesst_sich_im_panel_aufloesen(welt):
    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        erst = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Santa Cruz V10", category="ausruestung"))
        zweit = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Propain Rage", category="ausruestung"))

        antwort = c.patch(f"/api/memory/{zweit.data['id']}",
                          json={"resolve_conflict": True}, headers=TOKEN)
        assert antwort.status_code == 200, antwort.text
        assert antwort.json()["conflicts_with"] is None

        panel = {p["id"]: p for p in c.get("/api/memory", headers=TOKEN).json()}
    assert panel[zweit.data["id"]]["conflicts_with"] is None
    assert len(panel) == 2, "aufloesen heisst nicht loeschen"
    assert erst.data["id"] in panel


def test_dod7_ein_gleichlautender_fakt_ist_kein_widerspruch(welt):
    """Sonst widerspraeche sich jede Wiederholung selbst."""
    einstellungen, _ = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz V10",
                                          category="ausruestung"))
        zweit = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Santa Cruz V10", category="ausruestung"))
    assert "ACHTUNG" not in zweit.display, zweit.display


def test_dod7_eine_andere_kategorie_widerspricht_nicht(welt):
    einstellungen, _ = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz",
                                          category="ausruestung"))
        zweit = run(_werkzeug("remember").execute(
            text="Mein Rad war ein Geschenk", category="erinnerung"))
    assert "ACHTUNG" not in zweit.display, zweit.display


# --- DoD 8: kein halbes Schreiben ----------------------------------------


def test_dod8_es_bleiben_keine_halben_dateien_liegen(welt):
    einstellungen, vault = welt
    with _klient(einstellungen):
        for i in range(5):
            run(_werkzeug("remember").execute(text=f"Fakt Nummer {i}",
                                              category="test"))
    reste = [p.name for p in vault.rglob("*") if p.is_file()
             and not p.name.endswith(".md")]
    assert reste == [], f"halb geschriebene Dateien: {reste}"


# --- Was du nicht tun sollst ---------------------------------------------


def test_eine_leere_liste_versteckt_keinen_kaputten_index(welt):
    """FIX-04: "Wenn der Index leer ist und der Vault nicht, ist das ein Fehler."

    Der Fall ist konstruiert - im Alltag zieht `frisch_halten` die Dateien
    beim Lesen nach. Aber wenn er je eintritt, darf das Panel nicht "noch
    nichts gemerkt" anzeigen.
    """
    from core import gedaechtnis

    einstellungen, vault = welt
    (vault / "fakten").mkdir()
    (vault / "fakten" / "a.md").write_text(
        "---\nid: f_eins\ntyp: fakt\n---\n\nEin Fakt\n", encoding="utf-8")

    schaden = gedaechtnis.fehlbestand(einstellungen.db_path, einstellungen.vault_pfad)
    assert schaden and "1" in schaden and "reindex" in schaden, schaden


def test_ein_leerer_vault_ist_kein_schaden(welt):
    """Gegenprobe: eine Warnung, die immer kommt, liest niemand."""
    from core import gedaechtnis

    einstellungen, vault = welt
    assert gedaechtnis.fehlbestand(einstellungen.db_path, einstellungen.vault_pfad) is None

    # Eine fremde Datei ohne `id` ist keine JARVIS-Notiz und fehlt nicht.
    (vault / "einkaufszettel.md").write_text("Milch\nBrot\n", encoding="utf-8")
    assert gedaechtnis.fehlbestand(einstellungen.db_path, einstellungen.vault_pfad) is None


def test_ohne_vault_bleibt_alles_beim_alten(settings, db_path: Path):
    """Ohne VAULT_PFAD ist `facts` sowohl Wahrheit als auch Index."""
    from core import db, gedaechtnis

    with db.session(db_path) as conn:
        db.init_db(conn)

    assert settings.vault_pfad == ""
    neu, konflikt = gedaechtnis.anlegen(db_path, "", "Mein Rad ist ein Santa Cruz",
                                        category="ausruestung")
    assert isinstance(neu.id, int) and konflikt is None
    zweit, konflikt = gedaechtnis.anlegen(db_path, "", "Mein Rad ist ein Propain Rage",
                                          category="ausruestung")
    assert konflikt is not None and konflikt.id == neu.id
    assert [e.id for e in gedaechtnis.liste(db_path, "")] == [zweit.id, neu.id]
    assert gedaechtnis.loeschen(db_path, "", neu.id) is True
    assert [e.id for e in gedaechtnis.liste(db_path, "")] == [zweit.id]


# --- Schritt 2: der direkte Schreibweg ist privat ------------------------


def test_schritt2_memory_hat_keine_oeffentlichen_schreibfunktionen_mehr():
    """FIX-04 Schritt 2: *die Funktion, die direkt in die Datenbank schreibt,
    wird privat und nur vom Indexer aufgerufen.*

    Wer `memory.add_fact` ruft, umgeht den Vault. Nach dem Umbenennen bekommt
    er einen AttributeError statt eines zweiten Gedaechtnisses - scheitern
    statt stillschweigend funktionieren.
    """
    from core import memory

    for name in ("add_fact", "update_fact", "delete_fact"):
        assert not hasattr(memory, name), (
            f"core.memory.{name} ist wieder oeffentlich - damit gibt es einen "
            f"zweiten Schreibweg an core.gedaechtnis vorbei"
        )
        assert hasattr(memory, f"_{name}"), f"_{name} fehlt"


def test_schritt2_nur_gedaechtnis_ruft_die_privaten_schreibfunktionen():
    """Ein Waechter ueber den Produktivcode, nicht ueber die Tests."""
    treffer: list[str] = []
    for datei in WURZEL.rglob("*.py"):
        if "tests" in datei.parts or "__pycache__" in datei.parts:
            continue
        if datei.name in ("memory.py", "gedaechtnis.py"):
            continue
        text = datei.read_text(encoding="utf-8")
        for name in ("_add_fact", "_update_fact", "_delete_fact"):
            if name in text:
                treffer.append(f"{datei.relative_to(WURZEL)}: {name}")
    assert treffer == [], "am Vordereingang vorbei:\n" + "\n".join(treffer)


# --- Das Frontmatter bleibt fuer fremde Leser lesbar ---------------------


def test_das_frontmatter_ist_gueltiges_yaml_fuer_einen_fremden_parser(welt):
    """Der Vault ist die WAHRHEIT - sie darf nicht davon abhaengen, wer liest.

    Geprueft mit PyYAML, also einem Parser, der nichts von JARVIS weiss.
    Booleans stehen klein: YAML 1.1 liest `True` und `true` beide als
    Boolean, YAML 1.2 kennt nur die Kleinschreibung - dort waere `True` die
    Zeichenkette "True". Die Kleinschreibung ist unter beiden richtig.
    """
    yaml = pytest.importorskip("yaml")

    from core.vault import lies

    einstellungen, vault = welt
    with _klient(einstellungen) as c:
        erst = run(_werkzeug("remember").execute(
            text="Mein Rad ist ein Santa Cruz V10", category="ausruestung"))
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Propain Rage",
                                          category="ausruestung"))
        # Eine Notiz auf `true`, eine auf `false` - sonst prueft der Test nur
        # die Haelfte der Schreibweisen.
        c.patch(f"/api/memory/{erst.data['id']}", json={"confirmed": True},
                headers=TOKEN)

    gesehen = {True: 0, False: 0}
    geprueft = 0
    for datei in sorted(vault.rglob("*.md")):
        roh = datei.read_text(encoding="utf-8")
        kopf_text = roh.split("---")[1]
        kopf = yaml.safe_load(kopf_text)
        notiz = lies(datei)

        assert isinstance(kopf["bestaetigt"], bool), (
            f"{datei.name}: bestaetigt ist {kopf['bestaetigt']!r}, kein Boolean"
        )
        assert kopf["bestaetigt"] == notiz.bestaetigt
        assert (kopf["widerspruch"] or None) == notiz.widerspruch
        assert kopf["id"] == notiz.id
        assert f"bestaetigt: {str(notiz.bestaetigt).lower()}" in roh, (
            f"{datei.name}: Boolean nicht klein geschrieben - "
            f"{[z for z in roh.splitlines() if 'bestaetigt' in z]}"
        )
        for gross in ("bestaetigt: True", "bestaetigt: False"):
            assert gross not in roh, f"{datei.name}: {gross}"
        gesehen[notiz.bestaetigt] += 1
        geprueft += 1

    assert geprueft == 2, geprueft
    assert gesehen[True] == 1 and gesehen[False] == 1, (
        f"beide Schreibweisen muessen vorkommen, gesehen: {gesehen}"
    )


def test_das_log_zaehlt_die_fakten_richtig(welt, caplog):
    """Ein Log, das falsch zaehlt, ist schlimmer als keins.

    Die erste Zeile des Kontextblocks ist die Ueberschrift, kein Fakt.
    """
    import logging

    from core.llm import FakeLLMProvider

    einstellungen, vault = welt
    with _klient(einstellungen):
        run(_werkzeug("remember").execute(text="Mein Rad ist ein Santa Cruz V10",
                                          category="ausruestung"))

    with _klient(einstellungen) as c:
        c.app.state.provider = FakeLLMProvider()
        with caplog.at_level(logging.INFO, logger="jarvis"):
            antwort = c.post("/api/chat",
                             json={"message": "Was fuer ein Rad fahre ich?"},
                             headers=TOKEN)
        assert antwort.status_code == 200, antwort.text
        prompt = c.app.state.provider.calls[-1]["system"]

    assert "Santa Cruz V10" in prompt, "der Fakt muss im Systemprompt stehen"
    zeilen = [e.getMessage() for e in caplog.records
              if "Fakten in den Kontext" in e.getMessage()]
    assert zeilen, [e.getMessage() for e in caplog.records]
    assert "1 Fakten" in zeilen[-1], zeilen[-1]
