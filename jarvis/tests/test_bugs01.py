"""Die Funde aus `docs/BUGS-01.md`, jeder zuerst als roter Test.

Reihenfolge wie im Bericht: erst die schweren. Jeder Test nennt die
Fundnummer, damit man vom Bericht in den Test und zurueck findet.
"""

from __future__ import annotations

import asyncio
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import httpx
import pytest
from fastapi.testclient import TestClient

import api.app  # noqa: F401  - registriert die Werkzeuge
from api.app import create_app
from core.config import Settings
from core.db import connect, init_db
from core.tools import registry
from core.tools.dispatch import run_tool
from tests.conftest import run


@pytest.fixture
def db(tmp_path):
    pfad = tmp_path / "b.db"
    conn = connect(pfad); init_db(conn); conn.close()
    return pfad


# --- Fund 3: Nicht-ASCII im Token-Header --------------------------------


# HTTP-Header sind latin-1, nicht UTF-8. Ein Client kann "🔑" gar nicht erst
# senden - httpx wirft vorher. Was den Server WIRKLICH erreicht, sind
# latin-1-Zeichen wie "é": Starlette dekodiert sie zu einem str mit
# Nicht-ASCII, und genau daran ist compare_digest gestorben.
@pytest.mark.parametrize("token", ["tokén", "täuschung", "paß"])
def test_fund3_nicht_ascii_token_gibt_401_statt_500(settings, token):
    with TestClient(create_app(settings)) as c:
        antwort = c.get("/api/health",
                        headers={"X-Jarvis-Token": token.encode("latin-1")})
    assert antwort.status_code == 401, antwort.text


def test_fund3_auch_ueber_einen_rohen_socket_kommt_401(settings):
    """Ohne Client-Bibliothek dazwischen - so wie es ein Angreifer schickt."""
    import socket as _socket
    import threading as _threading
    import time as _time

    import uvicorn

    with _socket.socket() as s_:
        s_.bind(("127.0.0.1", 0))
        port = s_.getsockname()[1]

    app = create_app(settings)
    srv = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port,
                                        log_level="warning"))
    faden = _threading.Thread(target=srv.run, daemon=True)
    faden.start()
    frist = _time.monotonic() + 20
    while not srv.started and _time.monotonic() < frist:
        _time.sleep(0.05)
    assert srv.started

    try:
        roh = ("GET /api/health HTTP/1.1\r\n"
               "Host: 127.0.0.1\r\n"
               "X-Jarvis-Token: tok\xe9n\r\n"
               "Connection: close\r\n\r\n").encode("latin-1")
        with _socket.create_connection(("127.0.0.1", port), timeout=10) as verbindung:
            verbindung.sendall(roh)
            antwort = b""
            while True:
                stueck = verbindung.recv(4096)
                if not stueck:
                    break
                antwort += stueck
        erste = antwort.split(b"\r\n", 1)[0].decode("latin-1")
        assert "401" in erste, erste
        assert "500" not in erste, erste
    finally:
        srv.should_exit = True
        faden.join(timeout=10)


@pytest.mark.parametrize("token", ["schlüssel-🔑", "пароль-123", "日本語-token"])
def test_fund3_ein_nicht_sendbarer_token_faellt_beim_start_auf(tmp_path, token):
    """HTTP-Header sind latin-1. Was da nicht hineinpasst, ist unbenutzbar.

    Vorher startete JARVIS damit klaglos und gab bei JEDEM Request 500 - der
    Nutzer haette nie erfahren, dass sein Token das Problem ist.
    """
    st = Settings(_env_file=None, db_path=tmp_path / "u.db", jarvis_token=token)
    with pytest.raises(ValueError, match="HTTP-Header"):
        create_app(st)


def test_fund3_ein_umlaut_token_wird_gewarnt_aber_nicht_abgelehnt(tmp_path, caplog):
    """"gehaeim" mit ae passt in latin-1 - curl kann es senden, httpx nicht.

    Ablehnen waere zu streng, schweigen zu wenig: es wird gewarnt.
    """
    import logging

    st = Settings(_env_file=None, db_path=tmp_path / "w.db", jarvis_token="gehäim-123")
    with caplog.at_level(logging.WARNING, logger="jarvis"):
        create_app(st)
    assert any("nicht jeder Client" in r.message or "ASCII" in r.message
               for r in caplog.records), [r.message for r in caplog.records]


def test_fund3_ein_normaler_token_geht_weiterhin(tmp_path):
    st = Settings(_env_file=None, db_path=tmp_path / "n.db", jarvis_token="normal-123")
    with TestClient(create_app(st)) as c:
        assert c.get("/api/health", headers={"X-Jarvis-Token": "normal-123"}).status_code == 200
        assert c.get("/api/health", headers={"X-Jarvis-Token": "falsch"}).status_code == 401


# --- Fund 6: wiki_live baut den Hostnamen aus einem Modellparameter -----


@pytest.mark.parametrize("sprache", [
    "evil.com/", "de/../..", "//evil.com", "de?x=", "de#", "de:8080", "de@evil.com",
])
def test_fund6_der_token_geht_nie_an_einen_fremden_host(db, monkeypatch, sprache):
    gesehen = {}

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen["host"] = anfrage.url.host
        gesehen["auth"] = anfrage.headers.get("authorization")
        return httpx.Response(200, json={"pages": []})

    w = registry.get("wiki_live")
    monkeypatch.setattr(w, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(w, "token", "GEHEIM", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)

    ergebnis = run(run_tool("wiki_live", {"begriff": "x", "sprache": sprache}))

    if gesehen:
        assert gesehen["host"].endswith("wikipedia.org"), \
            f"{sprache!r} -> {gesehen['host']!r}, Token dabei: {bool(gesehen['auth'])}"
    else:
        assert ergebnis.ok is False, "ohne Anfrage muss das Werkzeug es sagen"


def test_fund6_ein_normaler_sprachcode_geht_weiterhin(db, monkeypatch):
    """Gegenprobe: die Sperre darf den Normalfall nicht mitnehmen."""
    gesehen = {}

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen["host"] = anfrage.url.host
        return httpx.Response(200, json={"pages": [
            {"title": "Orbit", "key": "Orbit", "excerpt": "x", "description": "y"}]})

    w = registry.get("wiki_live")
    monkeypatch.setattr(w, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)
    for sprache in ("de", "en", "als", "zh-yue"):
        gesehen.clear()
        ergebnis = run(run_tool("wiki_live", {"begriff": f"x{sprache}", "sprache": sprache}))
        assert ergebnis.ok, (sprache, ergebnis.error)
        assert gesehen["host"] == f"{sprache}.wikipedia.org"


# --- Fund 7: fetch_url ohne SSRF-Sperre ---------------------------------


class Intern(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        koerper = b"GEHEIMES INTERNES DASHBOARD hunter2"
        self.send_response(200)
        self.send_header("content-type", "text/html")
        self.send_header("content-length", str(len(koerper)))
        self.end_headers()
        self.wfile.write(koerper)

    def log_message(self, *_):
        return


@pytest.fixture
def intern():
    server = HTTPServer(("127.0.0.1", 0), Intern)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/admin"
    finally:
        server.shutdown(); server.server_close()


def test_fund7_fetch_url_greift_nicht_ins_eigene_netz(intern):
    """Die URL kommt aus dem Modell. Sie darf nicht auf localhost zeigen."""
    ergebnis = run(run_tool("fetch_url", {"url": intern}))
    assert ergebnis.ok is False, ergebnis.data
    assert "hunter2" not in str(ergebnis.data) + str(ergebnis.display)


@pytest.mark.parametrize("url", [
    "http://127.0.0.1:8000/api/health",
    "http://localhost:8000/",
    "http://169.254.169.254/latest/meta-data/",
    "http://10.0.0.1/",
    "http://192.168.1.1/",
    "http://172.16.0.1/",
    "http://[::1]/",
    "http://0.0.0.0/",
    "file:///etc/passwd",
])
def test_fund7_interne_ziele_werden_abgelehnt(url):
    ergebnis = run(run_tool("fetch_url", {"url": url}))
    assert ergebnis.ok is False, f"{url} haette abgelehnt werden muessen"


def test_fund7_auch_hole_quellbild_greift_nicht_ins_eigene_netz(intern):
    """Die quell_url kommt genauso aus dem Modell wie die von fetch_url."""
    from core.weltlage import hole_quellbild

    assert run(hole_quellbild(intern, medium="X")) is None


def test_fund7_oeffentliche_ziele_bleiben_erlaubt():
    """Gegenprobe: die Sperre darf das Netz nicht ganz zumachen."""
    from core.tools.search import oeffentliches_ziel

    assert oeffentliches_ziel("https://example.com/a") is None
    assert oeffentliches_ziel("http://example.org:8080/b") is None


def test_fund7_die_ausnahmeliste_ist_im_auslieferungszustand_leer():
    """Eine Sperre mit dauerhafter Hintertuer waere keine Sperre.

    Testfixtures duerfen sich eintragen - aber nur fuer ihre Laufzeit, und
    dieser Test laeuft ohne so ein Fixture.
    """
    from core.tools.search import ERLAUBT_INTERN

    assert ERLAUBT_INTERN == set(), ERLAUBT_INTERN


# --- Fund 1: der Abbrechen-Knopf ----------------------------------------


def _langsam(replies):
    """Ein Anbieter, der lange genug braucht, dass man abbrechen kann."""
    from core.llm import FakeLLMProvider

    class Langsam(FakeLLMProvider):
        async def complete(self, messages, *, system, tools=None):
            await asyncio.sleep(1.2)
            return await super().complete(messages, system=system, tools=tools)

    return Langsam(replies=replies)


def _warte(client, tid, sekunden=25.0):
    import time as _t

    frist = _t.monotonic() + sekunden
    while _t.monotonic() < frist:
        d = client.get(f"/api/tasks/{tid}",
                       headers={"X-Jarvis-Token": "test-token-123"}).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        _t.sleep(0.05)
    raise AssertionError(f"Task {tid} wurde nicht fertig")


def test_fund1b_abbruch_beim_einzigen_schritt_wirkt(settings):
    """Ein Ein-Schritt-Plan ist der Normalfall - dort war der Knopf wirkungslos."""
    import json as _json
    import time as _t

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = _langsam([
            _json.dumps({"steps": [{"description": "A", "agent": None}]}),
            "A erledigt.", "Zusammengefasst.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Ein Schritt"},
                     headers=TOKEN).json()["task_id"]
        _t.sleep(1.6)                       # der Schritt laeuft
        c.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)
        daten = _warte(c, tid)

    assert daten["status"] == "cancelled", daten
    assert daten["abort_reason"] == "Vom Nutzer abgebrochen."


def test_fund1b_nach_dem_abbruch_kommt_kein_weiterer_modellaufruf(settings):
    """Vorher liefen noch zwei bezahlte Zuege nach dem Abbruch."""
    import json as _json
    import time as _t

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    app = create_app(settings)
    with TestClient(app) as c:
        provider = _langsam([
            _json.dumps({"steps": [{"description": "A", "agent": None}]}),
            "A erledigt.", "Zusammengefasst.",
        ])
        app.state.provider = provider
        tid = c.post("/api/tasks", json={"goal": "Ein Schritt"},
                     headers=TOKEN).json()["task_id"]
        _t.sleep(1.6)
        c.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)
        vorher = len(provider.calls)
        daten = _warte(c, tid)
        nachher = len(provider.calls)

    assert daten["status"] == "cancelled"
    assert nachher - vorher <= 1, f"{nachher - vorher} Aufrufe nach dem Abbruch"


def test_fund1b_das_teilergebnis_bleibt_erhalten(settings):
    """0.5 verlangt ein Teilergebnis - nur eben ohne neuen Modellaufruf."""
    import json as _json
    import time as _t

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = _langsam([
            _json.dumps({"steps": [{"description": "A", "agent": None},
                                   {"description": "B", "agent": None}]}),
            "A ist fertig.", "B ist fertig.", "Zusammengefasst.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Zwei Schritte"},
                     headers=TOKEN).json()["task_id"]
        _t.sleep(2.8)                       # Schritt A ist durch
        c.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)
        daten = _warte(c, tid)

    assert daten["status"] == "cancelled"
    assert "Abgebrochen" in (daten["result"] or "")


def test_fund1a_abbruch_bei_offener_rueckfrage_sendet_die_mail_nicht(settings, tmp_path):
    """Der schwerste Teil von Fund 1.

    Vorher: `/cancel` setzte nur das Abbruch-Flag. Der Task hing weiter in
    `wait_for` auf die Rueckfrage, die Oberflaeche zeigte sie weiter an - und
    ein Klick auf "Ausfuehren" liess das EXTERNAL-Werkzeug trotz Abbruch
    laufen. Die Mail ging raus, nachdem der Nutzer abgebrochen hatte.
    """
    import time as _t

    from core.llm import FakeLLMProvider, FakeTurn, ToolUse

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    postausgang = tmp_path / "outbox.jsonl"
    settings.outbox_path = postausgang
    registry.get("send_email").outbox = postausgang

    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"Krankmeldung schicken"}]}',
            FakeTurn(tool_uses=(ToolUse("t1", "send_email", {
                "to": "chef@firma.de", "subject": "Krankmeldung",
                "body": "Ich bin heute nicht da.",
            }),)),
            "Erledigt.", "Erledigt.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Melde mich krank"},
                     headers=TOKEN).json()["task_id"]

        frist = _t.monotonic() + 10.0
        while _t.monotonic() < frist:
            daten = c.get(f"/api/tasks/{tid}", headers=TOKEN).json()
            if daten.get("confirmation"):
                break
            _t.sleep(0.02)
        else:
            raise AssertionError(f"keine Rueckfrage, zuletzt: {daten}")

        assert not postausgang.exists()          # noch nichts passiert

        c.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)

        # Der Nutzer drueckt danach trotzdem "Ausfuehren" - der Knopf steht
        # in einer schon gerenderten Seite noch da.
        spaet = c.post(f"/api/tasks/{tid}/confirm", json={"approve": True},
                       headers=TOKEN)
        daten = _warte(c, tid)

    assert spaet.status_code == 409, spaet.text
    assert daten["status"] == "cancelled", daten
    assert not postausgang.exists(), postausgang.read_text(encoding="utf-8")


def test_fund1a_der_abbruch_weckt_die_rueckfrage_sofort(settings, tmp_path):
    """Ohne Wecker haengt der Task bis zum Bestaetigungs-Timeout (600 s)."""
    import time as _t

    from api.tasks import BESTAETIGUNG_TIMEOUT_S
    from core.llm import FakeLLMProvider, FakeTurn, ToolUse

    assert BESTAETIGUNG_TIMEOUT_S >= 60, (
        "Der Test lebt davon, dass der Timeout laenger ist als seine Frist - "
        "sonst beweist er nichts."
    )

    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    settings.outbox_path = tmp_path / "outbox.jsonl"
    registry.get("send_email").outbox = settings.outbox_path

    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"Mail schicken"}]}',
            FakeTurn(tool_uses=(ToolUse("t1", "send_email", {
                "to": "a@b.de", "subject": "s", "body": "b"}),)),
            "Erledigt.", "Erledigt.",
        ])
        tid = c.post("/api/tasks", json={"goal": "Mail"},
                     headers=TOKEN).json()["task_id"]

        frist = _t.monotonic() + 10.0
        while _t.monotonic() < frist:
            if c.get(f"/api/tasks/{tid}", headers=TOKEN).json().get("confirmation"):
                break
            _t.sleep(0.02)
        else:
            raise AssertionError("keine Rueckfrage")

        begonnen = _t.monotonic()
        c.post(f"/api/tasks/{tid}/cancel", headers=TOKEN)
        daten = _warte(c, tid, sekunden=20.0)
        gedauert = _t.monotonic() - begonnen

    assert daten["status"] == "cancelled", daten
    assert gedauert < 15.0, f"Der Abbruch brauchte {gedauert:.1f} s"


# --- Fund 4: Das Budget wird nur zwischen Schritten geprueft -------------


def _plan_mit_werkzeugrunden(runden: int):
    """Ein Ein-Schritt-Plan, dessen Schritt `runden` Mal ein Werkzeug ruft.

    Bewusst nicht als feste `replies`-Liste: wie viele Zuege wirklich
    verbraucht werden, haengt genau an dem Verhalten, das hier geprueft wird.
    Eine feste Liste waere danach verschoben, und die Zusammenfassung bekaeme
    einen Werkzeugzug statt eines Textes. Unterschieden wird an den echten
    Markern aus dem Produktivcode, nicht an geratenen Zeichenketten.
    """
    from core.llm import FakeLLMProvider, FakeTurn, ToolUse
    from core.planner import PLANNER_MARKER
    from core.runner import ABSCHLUSS_PROMPT

    class Werkzeugschleife(FakeLLMProvider):
        def __init__(self) -> None:
            super().__init__()
            self.werkzeugzuege = 0

        async def complete(self, messages, *, system, tools=None):
            if system.startswith(PLANNER_MARKER):
                self._replies = ['{"steps":[{"description":"A"}]}']
            elif system.startswith(ABSCHLUSS_PROMPT):
                self._replies = ["Zusammengefasst."]
            elif self.werkzeugzuege < runden:
                self.werkzeugzuege += 1
                self._replies = [FakeTurn(tool_uses=(
                    ToolUse(f"t{self.werkzeugzuege}", "clock", {}),
                ))]
            else:
                self._replies = ["Fertig."]
            return await super().complete(messages, system=system, tools=tools)

    return Werkzeugschleife()


def test_fund4_max_tool_calls_gilt_auch_innerhalb_eines_schritts():
    """BUGS-01 Fund 4 - ein Ein-Schritt-Plan hatte praktisch kein Budget.

    `budget_verletzung()` lief nur in der Schleife ueber `task.steps`.
    Innerhalb eines Schritts konnte der Werkzeug-Loop beliebig viele
    Werkzeuge rufen; der Task endete danach auf "done".
    """
    from core.contracts import TaskBudget
    from core.runner import fuehre_task_aus

    p = _plan_mit_werkzeugrunden(6)
    t = run(fuehre_task_aus(p, "Ein Schritt, viele Werkzeuge",
                            budget=TaskBudget(max_tool_calls=2),
                            kosten=lambda a, b: 0.0))

    assert t.spent_tool_calls <= 2, (
        f"{t.spent_tool_calls} Werkzeugaufrufe bei max_tool_calls=2"
    )
    assert t.status == "aborted_budget", t.status
    assert "max_tool_calls" in (t.abort_reason or "")


def test_fund4_max_tokens_gilt_auch_innerhalb_eines_schritts():
    from core.contracts import TaskBudget
    from core.runner import fuehre_task_aus

    # Erst messen, wieviel ein Zug wirklich kostet - eine geratene Zahl waere
    # entweder wirkungslos oder wuerde schon den Planner erschlagen.
    mess = _plan_mit_werkzeugrunden(6)
    gemessen = run(fuehre_task_aus(mess, "Messlauf", budget=TaskBudget(),
                                   kosten=lambda a, b: 0.0))
    assert gemessen.status == "done", gemessen.status
    grenze = gemessen.spent_tokens // 2

    p = _plan_mit_werkzeugrunden(6)
    t = run(fuehre_task_aus(p, "Ein Schritt, viele Werkzeuge",
                            budget=TaskBudget(max_tokens=grenze),
                            kosten=lambda a, b: 0.0))

    assert t.status == "aborted_budget", t.status
    assert "max_tokens" in (t.abort_reason or "")
    assert t.spent_tokens < gemessen.spent_tokens, (
        f"{t.spent_tokens} statt hoechstens {gemessen.spent_tokens} - "
        "der Task ist trotz Grenze voll durchgelaufen"
    )


def test_fund4_nach_der_grenze_laeuft_nur_noch_der_abschluss():
    """Genau ein Zug darf noch - der, den 0.5 verlangt.

    Der Werkzeugzug, der die Grenze reisst, laeuft zu Ende. Danach kommt
    kein weiterer Werkzeugzug mehr, sondern nur noch die Zusammenfassung:
    0.5 verlangt ausdruecklich ein Teilergebnis. Ohne den Fix liefen alle
    sechs Werkzeugrunden durch.
    """
    from core.contracts import TaskBudget
    from core.runner import fuehre_task_aus

    p = _plan_mit_werkzeugrunden(6)
    t = run(fuehre_task_aus(p, "Ein Schritt, viele Werkzeuge",
                            budget=TaskBudget(max_tool_calls=2),
                            kosten=lambda a, b: 0.0))

    assert t.status == "aborted_budget"
    # Plan + zwei Werkzeugrunden + Zusammenfassung. Mehr nicht.
    assert len(p.calls) == 4, f"{len(p.calls)} Modellaufrufe: {t.abort_reason}"
    assert p.werkzeugzuege == 2, f"{p.werkzeugzuege} Werkzeugzuege statt 2"
    assert t.result, "Ohne Teilergebnis waere 0.5 verletzt."


def test_fund4_der_wiederholversuch_prueft_das_budget_ebenfalls():
    """Ein nicht bestandener Schritt wird wiederholt - auch ueber die Grenze.

    Die Grenze wird nicht geraten, sondern gemessen: sie liegt exakt auf dem
    Stand nach Plan plus erstem Versuch. Eine geratene Zahl wuerde entweder
    schon den Planner erschlagen oder gar nichts pruefen.
    """
    from core.contracts import TaskBudget
    from core.llm import FakeLLMProvider
    from core.runner import Laufzeit, fuehre_task_aus

    def anbieter():
        # Ein research-Schritt ohne Quelle besteht die Verifikation nie.
        return FakeLLMProvider(replies=[
            '{"steps":[{"description":"Etwas belegen","agent":"research"}]}',
            "Die Zahl ist 400 %.",
        ])

    zuege: list[int] = []

    async def mitzaehlen(reply):
        zuege.append(reply.usage.in_tokens + reply.usage.out_tokens)

    gemessen = run(fuehre_task_aus(anbieter(), "Beleg", budget=TaskBudget(),
                                   kosten=lambda a, b: 0.0,
                                   laufzeit=Laufzeit(on_reply=mitzaehlen)))
    assert gemessen.steps[0].attempts == 2, (
        f"Der Messlauf soll zweimal versuchen, versuchte {gemessen.steps[0].attempts}"
    )
    grenze = sum(zuege[:2])          # Plan + erster Versuch

    t = run(fuehre_task_aus(anbieter(), "Beleg",
                            budget=TaskBudget(max_tokens=grenze),
                            kosten=lambda a, b: 0.0))

    assert t.status == "aborted_budget", t.status
    assert t.steps[0].attempts == 1, (
        f"{t.steps[0].attempts} Versuche, obwohl das Budget nach dem ersten weg war"
    )


def test_fund4_mehrere_werkzeuge_in_einem_zug_laufen_nicht_alle_durch():
    """Ein Modell darf mehrere Werkzeuge auf einmal anfordern.

    Die Pruefung am Rundenanfang reicht dafuer nicht: die Grenze faellt
    mitten im Zug. Was danach kommt, darf nicht mehr laufen.
    """
    from core.contracts import TaskBudget
    from core.llm import FakeLLMProvider, FakeTurn, ToolUse
    from core.planner import PLANNER_MARKER
    from core.runner import ABSCHLUSS_PROMPT, fuehre_task_aus

    class DreiAufEinmal(FakeLLMProvider):
        async def complete(self, messages, *, system, tools=None):
            if system.startswith(PLANNER_MARKER):
                self._replies = ['{"steps":[{"description":"A"}]}']
            elif system.startswith(ABSCHLUSS_PROMPT):
                self._replies = ["Zusammengefasst."]
            elif not self.calls or all(
                c["system"].startswith(PLANNER_MARKER) for c in self.calls
            ):
                self._replies = [FakeTurn(tool_uses=(
                    ToolUse("a", "clock", {}),
                    ToolUse("b", "clock", {}),
                    ToolUse("c", "clock", {}),
                ))]
            else:
                self._replies = ["Fertig."]
            return await super().complete(messages, system=system, tools=tools)

    p = DreiAufEinmal()
    t = run(fuehre_task_aus(p, "Drei auf einmal",
                            budget=TaskBudget(max_tool_calls=1),
                            kosten=lambda a, b: 0.0))

    assert t.spent_tool_calls == 1, (
        f"{t.spent_tool_calls} Werkzeuge gelaufen, erlaubt war 1"
    )
    assert t.status == "aborted_budget", t.status
