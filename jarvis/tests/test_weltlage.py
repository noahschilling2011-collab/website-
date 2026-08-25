"""Die Definition of Done aus `docs/phases/PHASE-11.md`.

Zwei Regeln entscheiden diese Phase, und beide stehen als Code, nicht als
Bitte im Prompt:

**Das Bild kommt aus der Quelle, oder es gibt kein Bild.**
**Ohne Medium und Datum wird die Meldung verworfen.**

Der Fixture-Verlag unten liefert echte HTML-Seiten mit und ohne `og:image`,
mit und ohne `og:image:alt` - so laesst sich beides pruefen, ohne je eine
fremde Nachrichtenseite anzufassen.
"""

from __future__ import annotations

import json
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core.config import Settings
from core.db import connect, init_db, session
from core.llm import FakeLLMProvider
from core.weltlage import Meldung, bild_aus_seite, hole_quellbild, pruefe, siebe
from tests.conftest import run

TOKEN = {"X-Jarvis-Token": "test-token-123"}

MIT_BILD = """<!doctype html><html><head>
<meta property="og:image" content="/bilder/echt.jpg">
<meta property="og:image:alt" content="Ein Kran vor einem halbfertigen Gebaeude.">
<title>Mit Bild</title></head><body><p>Text</p></body></html>"""

OHNE_ALT = """<!doctype html><html><head>
<meta property="og:image" content="https://verlag.example/bilder/ohne-alt.jpg">
<title>Ohne Alt</title></head><body><p>Text</p></body></html>"""

OHNE_BILD = """<!doctype html><html><head>
<title>Ohne Bild</title></head><body><p>Nur Text, kein og:image.</p></body></html>"""

MIT_FIGCAPTION = """<!doctype html><html><head>
<meta property="og:image" content="/bilder/fig.jpg"></head><body>
<figure><img src="/bilder/fig.jpg"><figcaption>Aufnahme vom <b>3. Mai</b>.</figcaption></figure>
</body></html>"""

ROBOTS_ERLAUBT = "User-agent: *\nAllow: /\n"
ROBOTS_VERBOTEN = "User-agent: *\nDisallow: /\n"


class Verlag(BaseHTTPRequestHandler):
    robots = ROBOTS_ERLAUBT
    seiten = {
        "/mit-bild": MIT_BILD,
        "/ohne-alt": OHNE_ALT,
        "/ohne-bild": OHNE_BILD,
        "/figcaption": MIT_FIGCAPTION,
    }

    def do_GET(self):  # noqa: N802
        if self.path == "/robots.txt":
            return self._sende(type(self).robots, "text/plain")
        seite = type(self).seiten.get(self.path.split("?")[0])
        if seite is None:
            self.send_response(404); self.end_headers(); return
        self._sende(seite, "text/html; charset=utf-8")

    def _sende(self, koerper, typ):
        roh = koerper.encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", typ)
        self.send_header("content-length", str(len(roh)))
        self.end_headers()
        self.wfile.write(roh)

    def log_message(self, *_):
        return


@pytest.fixture
def verlag():
    Verlag.robots = ROBOTS_ERLAUBT
    server = HTTPServer(("127.0.0.1", 0), Verlag)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown(); server.server_close()


@pytest.fixture
def db(tmp_path):
    pfad = tmp_path / "welt.db"
    conn = connect(pfad); init_db(conn); conn.close()
    return pfad


def _meldungen_json(eintraege, gesagt=""):
    return json.dumps({"meldungen": eintraege, "gesagt": gesagt}, ensure_ascii=False)


def _eintrag(verlag_url="http://127.0.0.1:0/ohne-bild", **kw):
    basis = {
        "schlagzeile": "Dritter Vorfall in neun Tagen",
        "kurz": "Reuters meldet einen dritten Zwischenfall. Die Behoerde bestaetigt zwei davon.",
        "medium": "Reuters",
        "veroeffentlicht": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "quell_url": verlag_url,
        "land_iso": "DEU",
        "einordnung": "",
        "einordnung_fehlt": "",
    }
    basis.update(kw)
    return basis


@pytest.fixture
def client(db, settings, verlag):
    """Haengt am Fixture-Verlag: der Bildpfad laeuft in jedem Test wirklich."""
    settings.db_path = db
    app = create_app(settings)
    with TestClient(app) as c:
        c.verlag = verlag
        yield c


def eintrag_fuer(client, **kw):
    return _eintrag(verlag_url=f"{client.verlag}/ohne-bild", **kw)


def setze_antwort(client, roh_json):
    client.app.state.provider = FakeLLMProvider(replies=[roh_json])


# --- Datenvertrag (Abschnitt 7) ---------------------------------------------


def test_der_vertrag_verwirft_ohne_medium():
    m = Meldung(schlagzeile="S", kurz="K", medium="", veroeffentlicht=datetime.now(timezone.utc),
                quell_url="https://x.example/a", land_iso="DEU")
    assert pruefe(m) == "kein Medium"


def test_der_vertrag_verwirft_kaputte_quell_url():
    m = Meldung(schlagzeile="S", kurz="K", medium="Reuters",
                veroeffentlicht=datetime.now(timezone.utc),
                quell_url="keine-url", land_iso="DEU")
    assert pruefe(m) == "Quell-URL ungueltig"


def test_der_vertrag_verwirft_bild_ohne_herkunft():
    m = Meldung(schlagzeile="S", kurz="K", medium="Reuters",
                veroeffentlicht=datetime.now(timezone.utc),
                quell_url="https://x.example/a", land_iso="DEU",
                bild_url="https://x.example/b.jpg")
    assert pruefe(m) == "Bild ohne Herkunft"


def test_siebe_zaehlt_die_gruende():
    gueltig = Meldung(schlagzeile="S", kurz="K", medium="Reuters",
                      veroeffentlicht=datetime.now(timezone.utc),
                      quell_url="https://x.example/a", land_iso="DEU")
    kaputt = Meldung(schlagzeile="S", kurz="K", medium="",
                     veroeffentlicht=datetime.now(timezone.utc),
                     quell_url="https://x.example/a", land_iso="DEU")
    gut, gruende = siebe([gueltig, kaputt, kaputt])
    assert len(gut) == 1 and gruende == ["kein Medium", "kein Medium"]


# --- DoD 4: Bildtest --------------------------------------------------------


def test_dod_4_artikel_mit_og_image_liefert_genau_dieses_bild(verlag):
    bild = run(hole_quellbild(f"{verlag}/mit-bild", medium="Verlag"))
    assert bild is not None
    assert bild.url == f"{verlag}/bilder/echt.jpg", "relative og:image muss aufgeloest werden"
    assert bild.herkunft == "Verlag", "Herkunft ist Pflicht, sobald ein Bild da ist"


def test_dod_4_artikel_ohne_og_image_liefert_KEIN_bild(verlag):
    """Kein Ersatz. Kein Stockfoto. Nichts."""
    assert run(hole_quellbild(f"{verlag}/ohne-bild", medium="Verlag")) is None


def test_dod_4_kein_fallback_auf_irgendein_img_tag():
    """Ein <img> im Text ist nicht das Vorschaubild des Verlags."""
    seite = '<html><body><img src="/zufall.jpg" alt="irgendwas"></body></html>'
    assert bild_aus_seite(seite, "https://x.example/a", "X") is None


def test_twitter_image_ist_die_zweite_wahl():
    seite = '<html><head><meta name="twitter:image" content="https://x.example/t.jpg"></head></html>'
    bild = bild_aus_seite(seite, "https://x.example/a", "X")
    assert bild is not None and bild.url == "https://x.example/t.jpg"


def test_robots_txt_wird_respektiert(verlag):
    Verlag.robots = ROBOTS_VERBOTEN
    assert run(hole_quellbild(f"{verlag}/mit-bild", medium="Verlag")) is None


def test_unerreichbare_robots_heisst_nicht_holen():
    """Ein Verlag, dessen robots.txt nicht antwortet, hat nicht zugestimmt."""
    assert run(hole_quellbild("http://127.0.0.1:1/a", medium="X")) is None


# --- DoD 11: Captiontest ----------------------------------------------------


def test_dod_11_mit_og_image_alt_kommt_die_caption_aus_der_quelle(verlag):
    bild = run(hole_quellbild(f"{verlag}/mit-bild", medium="Verlag"))
    assert bild.beschreibung == "Ein Kran vor einem halbfertigen Gebaeude."


def test_dod_11_ohne_caption_bleibt_sie_leer(verlag):
    """JARVIS sagt zum Bild dann NICHTS. Kein 'vermutlich', kein 'offenbar'."""
    bild = run(hole_quellbild(f"{verlag}/ohne-alt", medium="Verlag"))
    assert bild is not None and bild.beschreibung is None


def test_figcaption_zaehlt_auch_als_quelle(verlag):
    bild = run(hole_quellbild(f"{verlag}/figcaption", medium="Verlag"))
    assert bild.beschreibung == "Aufnahme vom 3. Mai."


# --- DoD 1 und 2: ein Auftrag, dann Cache -----------------------------------


def test_dod_1_ein_klick_ist_genau_ein_auftrag(client, db):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client)]))
    antwort = client.post("/api/weltlage/DEU", headers=TOKEN)
    assert antwort.status_code == 200, antwort.text
    assert len(antwort.json()["meldungen"]) == 1

    with session(db) as conn:
        zeile = conn.execute("SELECT treffer, abfragen FROM weltlage_zaehler").fetchone()
    assert tuple(zeile) == (0, 1), "genau eine Abfrage, kein Cache-Treffer"


def test_dod_2_zweiter_klick_kostet_null_neue_auftraege(client, db):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client)]))
    client.post("/api/weltlage/DEU", headers=TOKEN)

    # Provider abwuergen: was jetzt noch geht, kam aus dem Cache.
    class Verweigert(FakeLLMProvider):
        async def complete(self, *a, **kw):
            raise AssertionError("es haette kein Modellaufruf passieren duerfen")

    client.app.state.provider = Verweigert()
    zweite = client.get("/api/weltlage/DEU", headers=TOKEN)
    assert zweite.status_code == 200
    assert zweite.json()["cache"] is True
    assert len(zweite.json()["meldungen"]) == 1

    with session(db) as conn:
        treffer, abfragen = conn.execute(
            "SELECT treffer, abfragen FROM weltlage_zaehler").fetchone()
    assert (treffer, abfragen) == (1, 1), "der zweite Klick darf keine Abfrage sein"


def test_cache_laeuft_nach_der_ttl_ab(db):
    from core.weltlage import cache_lesen, cache_schreiben

    with session(db) as conn:
        cache_schreiben(conn, "DEU", {"meldungen": []})
        conn.execute(
            "UPDATE weltlage_cache SET geholt_am = ? WHERE land_iso = 'DEU'",
            ((datetime.now(timezone.utc) - timedelta(minutes=61))
             .strftime("%Y-%m-%dT%H:%M:%SZ"),))
        assert cache_lesen(conn, "DEU") is None


# --- DoD 3: Medium und Datum, sonst raus ------------------------------------


def test_dod_3_meldung_ohne_medium_wird_verworfen_und_gezaehlt(client, db):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client), eintrag_fuer(client, medium='')]))
    daten = client.post("/api/weltlage/DEU", headers=TOKEN).json()

    assert len(daten["meldungen"]) == 1
    assert daten["verworfen"] == 1

    zaehler = client.get("/api/weltlage/zaehler", headers=TOKEN).json()
    assert zaehler["verworfen"] == 1, "die Zahl gehoert sichtbar in die Statusleiste"


def test_dod_3_meldung_ohne_datum_wird_verworfen(client):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client, veroeffentlicht="")]))
    daten = client.post("/api/weltlage/DEU", headers=TOKEN).json()
    assert daten["meldungen"] == [] and daten["verworfen"] == 1


def test_jede_gelieferte_meldung_traegt_medium_und_datum(client):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client)]))
    for m in client.post("/api/weltlage/DEU", headers=TOKEN).json()["meldungen"]:
        assert m["medium"] and m["veroeffentlicht"]


# --- DoD 5 und 13: Negativtest und Schweigen --------------------------------


def test_dod_5_ohne_belegbare_treffer_null_meldungen_und_keine_karte(client):
    setze_antwort(client, _meldungen_json([], gesagt=""))
    daten = client.post("/api/weltlage/XXX", headers=TOKEN).json()
    assert daten["meldungen"] == []
    assert "nichts" in daten["gesagt"].lower(), daten["gesagt"]


def test_dod_13_schweigetest_kein_fuellsatz(client):
    setze_antwort(client, _meldungen_json([], gesagt="Zu Namibia finde ich heute nichts."))
    daten = client.post("/api/weltlage/NAM", headers=TOKEN).json()
    assert daten["meldungen"] == []
    assert daten["gesagt"] == "Zu Namibia finde ich heute nichts."


def test_unbrauchbares_modell_json_ist_ein_fehler(client):
    """FIX-02 Schritt 1: ein Fehler bleibt ein Fehler.

    Vorher wurde daraus eine leere, erfolgreiche Antwort - die sieht aus wie
    "heute ist nichts passiert" und ist damit eine Behauptung, die niemand
    geprueft hat.
    """
    client.app.state.provider = FakeLLMProvider(replies=["Das ist kein JSON."])
    antwort = client.post("/api/weltlage/DEU", headers=TOKEN)
    assert antwort.status_code == 502, antwort.text
    assert "kein verwertbares JSON" in antwort.json()["detail"]


def test_modell_json_das_kein_objekt_ist_gibt_502_statt_500(client):
    client.app.state.provider = FakeLLMProvider(replies=['["a", "b"]'])
    antwort = client.post("/api/weltlage/DEU", headers=TOKEN)
    assert antwort.status_code == 502, antwort.text
    assert "statt eines Objekts" in antwort.json()["detail"]


def test_meldungen_die_keine_liste_sind_geben_502(client):
    client.app.state.provider = FakeLLMProvider(replies=['{"meldungen": "keine Liste"}'])
    antwort = client.post("/api/weltlage/DEU", headers=TOKEN)
    assert antwort.status_code == 502
    assert "erwartet wird eine Liste" in antwort.json()["detail"]


def test_ein_lauf_ohne_meldung_wird_nicht_gecacht(client, db):
    """Sonst wird eine gescheiterte Recherche 60 Minuten lang als Ergebnis ausgeliefert."""
    setze_antwort(client, _meldungen_json([], gesagt="Dazu finde ich nichts."))
    client.post("/api/weltlage/NAM", headers=TOKEN)
    with session(db) as conn:
        zeilen = conn.execute(
            "SELECT count(*) FROM weltlage_cache WHERE land_iso = 'NAM'").fetchone()[0]
    assert zeilen == 0, "ein leeres Ergebnis darf nicht als Ergebnis gelten"


# --- DoD 14: Kontextluecke --------------------------------------------------


def test_dod_14_leere_einordnung_traegt_einen_hinweis(client):
    setze_antwort(client, _meldungen_json([
        eintrag_fuer(client, einordnung="", einordnung_fehlt="Dazu habe ich keinen Kontext.")]))
    m = client.post("/api/weltlage/DEU", headers=TOKEN).json()["meldungen"][0]
    assert m["einordnung"] == ""
    assert m["einordnung_fehlt"] == "Dazu habe ich keinen Kontext."


def test_einordnung_bleibt_getrennt_von_der_meldung(client):
    setze_antwort(client, _meldungen_json([
        eintrag_fuer(client, einordnung="Der Vorfall ist der dritte seit Mai.")]))
    m = client.post("/api/weltlage/DEU", headers=TOKEN).json()["meldungen"][0]
    assert m["einordnung"] not in m["kurz"], "Einordnung darf nicht in die Meldung sickern"


# --- DoD 8 und 12: Kosten und kein Vision-Aufruf ----------------------------


def test_dod_8_zaehler_liest_die_kosten_aus_llm_calls(client, db):
    from core import db as datenbank

    setze_antwort(client, _meldungen_json([eintrag_fuer(client)]))
    client.post("/api/weltlage/DEU", headers=TOKEN)
    datenbank.log_llm_call(db, model="m", in_tokens=10, out_tokens=5,
                           cost_eur=0.25, duration_ms=1, ok=True)

    zaehler = client.get("/api/weltlage/zaehler", headers=TOKEN).json()
    with session(db) as conn:
        summe = conn.execute("SELECT COALESCE(SUM(cost_eur),0) FROM llm_calls").fetchone()[0]
    assert zaehler["kosten_eur"] == pytest.approx(summe), \
        "die Anzeige muss aus llm_calls kommen, nicht aus einer zweiten Zaehlung"


def test_dod_12_kein_modellaufruf_traegt_eine_externe_bild_url(client, verlag):
    """Kein Vision-Modell auf fremde Nachrichtenfotos."""
    fake = FakeLLMProvider(replies=[_meldungen_json([
        _eintrag(verlag_url=f"{verlag}/mit-bild", medium="Verlag")])])
    client.app.state.provider = fake
    daten = client.post("/api/weltlage/DEU", headers=TOKEN).json()
    assert daten["meldungen"][0]["bild_url"], "das Bild sollte geholt worden sein"

    fuer_das_modell = json.dumps(
        [[str(m.content) for m in ruf["messages"]] + [ruf["system"]] for ruf in fake.calls],
        ensure_ascii=False)
    assert ".jpg" not in fuer_das_modell, "keine Bild-URL ist je an das Modell gegangen"
    assert verlag not in fuer_das_modell or "bilder" not in fuer_das_modell


def test_der_prompt_verbietet_bildbeschreibungen():
    from core.agents import WELTLAGE_PROMPT

    assert "ZU BILDERN SAGST DU NICHTS" in WELTLAGE_PROMPT


# --- Abschnitt 4: die Regeln stehen im Prompt -------------------------------


@pytest.mark.parametrize("regel", [
    "Zahl ohne Quelle",
    "Keine Superlative",
    "Keine Prognose",
    "Zwei Saetze pro Meldung",
    "WENIGER Meldungen",
    "SCHWEIGEN IST EIN GUELTIGER ZUSTAND",
])
def test_die_regeln_stehen_im_prompt(regel):
    from core.agents import WELTLAGE_PROMPT

    assert regel in WELTLAGE_PROMPT


def test_hoechstens_fuenf_karten(client):
    setze_antwort(client, _meldungen_json([eintrag_fuer(client) for _ in range(9)]))
    daten = client.post("/api/weltlage/DEU", headers=TOKEN).json()
    assert len(daten["meldungen"]) == 5, "Abschnitt 5: hoechstens 5 Karten"


def test_der_zaehler_braucht_einen_token(client):
    assert client.get("/api/weltlage/zaehler").status_code == 401
    assert client.post("/api/weltlage/DEU").status_code == 401
