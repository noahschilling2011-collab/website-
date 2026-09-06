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
    """Gegenprobe: die Sperre darf den Normalfall nicht mitnehmen.

    Der Vertrag hat sich mit FIX-03 Schritt 1a bewusst verengt. Vorher liess
    ein regulaerer Ausdruck jeden BCP-47-foermigen Code durch und baute daraus
    einen Host. Jetzt entscheidet die Zuordnung `WIKI_HOSTS`: was dort steht,
    geht durch; was nicht, wird abgelehnt statt geraten.

    Deshalb steht hier beides - der Normalfall UND die Codes, die es bei
    Wikipedia zwar gibt ('als', 'zh-yue'), die aber nicht eingerichtet sind.
    Das ist kein Fehler, sondern die Entscheidung aus FIX-03: lieber ein
    fehlgeschlagener Schritt als ein ungeprueftes Ziel. Wer sie braucht,
    traegt sie in WIKI_HOSTS ein - eine Zeile, sichtbar im Produktivcode.
    """
    from core.tools.wissen_tools import WIKI_HOSTS

    gesehen = {}

    def spion(anfrage: httpx.Request) -> httpx.Response:
        gesehen["host"] = anfrage.url.host
        return httpx.Response(200, json={"pages": [
            {"title": "Orbit", "key": "Orbit", "excerpt": "x", "description": "y"}]})

    w = registry.get("wiki_live")
    monkeypatch.setattr(w, "kontakt", "noah@example.org", raising=False)
    monkeypatch.setattr(w, "db_path", db, raising=False)
    monkeypatch.setattr(w, "transport", httpx.MockTransport(spion), raising=False)

    for sprache in ("de", "en"):
        gesehen.clear()
        ergebnis = run(run_tool("wiki_live", {"begriff": f"x{sprache}", "sprache": sprache}))
        assert ergebnis.ok, (sprache, ergebnis.error)
        assert gesehen["host"] == WIKI_HOSTS[sprache].removeprefix("https://")

    for sprache in ("als", "zh-yue"):
        assert sprache not in WIKI_HOSTS, (
            f"{sprache!r} ist jetzt eingerichtet - dann gehoert er nach oben"
        )
        gesehen.clear()
        ergebnis = run(run_tool("wiki_live", {"begriff": f"x{sprache}", "sprache": sprache}))
        assert ergebnis.ok is False, sprache
        assert gesehen == {}, f"es ging etwas an {gesehen.get('host')!r}"


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


def test_fund4_nach_der_grenze_kommt_kein_bezahlter_zug_mehr():
    """Nach der Grenze wird nichts mehr bezahlt - auch keine Zusammenfassung.

    Der Werkzeugzug, der die Grenze reisst, laeuft zu Ende. Danach ist Schluss.
    Ohne den Fix aus Fund 4 liefen alle sechs Werkzeugrunden durch.

    Diese Zahl ist mit FIX-03 Schritt 3a von vier auf drei gesunken, und zwar
    absichtlich: vorher stand vor der Zusammenfassung kein Pruefpunkt, also
    lief sie noch als vierter bezahlter Aufruf. Das Teilergebnis, das 0.5
    verlangt, gibt es weiterhin - es wird jetzt aus den fertigen Schritten
    zusammengesetzt statt vom Modell gekauft.
    """
    from core.contracts import TaskBudget
    from core.runner import fuehre_task_aus

    p = _plan_mit_werkzeugrunden(6)
    t = run(fuehre_task_aus(p, "Ein Schritt, viele Werkzeuge",
                            budget=TaskBudget(max_tool_calls=2),
                            kosten=lambda a, b: 0.0))

    assert t.status == "aborted_budget"
    # Plan + zwei Werkzeugrunden. Mehr nicht - die Zusammenfassung faellt weg.
    assert len(p.calls) == 3, f"{len(p.calls)} Modellaufrufe: {t.abort_reason}"
    assert p.werkzeugzuege == 2, f"{p.werkzeugzuege} Werkzeugzuege statt 2"
    assert t.result, "Ohne Teilergebnis waere 0.5 verletzt."
    assert "Abgebrochen" in t.result, t.result


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


# --- Fund 14: Rechner-Bombe ----------------------------------------------


def test_fund14_eine_multiplikationskette_blockiert_den_server_nicht():
    """BUGS-01 Fund 14, mit korrigiertem Mechanismus.

    Der Bericht nennt `(10**15)**1000` und eine nicht greifende
    30-Sekunden-Schranke. Nachgemessen rechnet dieser Ausdruck in 0,2 ms -
    einfrieren tut da nichts. Was WIRKLICH einfriert, ist eine Kette von
    Multiplikationen: die Potenzgrenze deckelt nur `**`, nicht `*`.

        n= 50  Ausdruck   847 Zeichen   0.540 s
        n=100  Ausdruck  1697 Zeichen   2.163 s
        n=200  Ausdruck  3397 Zeichen   8.514 s
        n=400  Ausdruck  6797 Zeichen  34.555 s

    6797 Zeichen kann jedes Modell schreiben, und `rechne()` laeuft synchron
    im Event-Loop: 34 s lang antwortet der ganze Server nicht mehr.
    """
    import time as _t

    from core.tools.builtin import UnsichererAusdruck, rechne

    ausdruck = " * ".join(["(10**15)**1000"] * 400)
    begonnen = _t.monotonic()
    with pytest.raises(UnsichererAusdruck):
        rechne(ausdruck)
    gedauert = _t.monotonic() - begonnen
    assert gedauert < 1.0, f"{gedauert:.1f} s - der Server haengt so lange"


def test_fund14_ein_unausdruckbares_ergebnis_ist_ein_sauberer_fehler():
    """`(10**15)**1000` hat 15001 Stellen.

    Python weigert sich ab 4300 Stellen, daraus einen String zu machen. Der
    ValueError flog aus `execute` heraus - er entsteht erst beim Formatieren
    der Antwort, also NACH dem try-Block. Was ankam, war der Python-Interna-
    Text ueber `sys.set_int_max_str_digits`.
    """
    from core.tools.dispatch import run_tool as _run_tool

    ergebnis = run(_run_tool("calculator", {"expression": "(10**15)**1000"}))
    assert ergebnis.ok is False
    assert "set_int_max_str_digits" not in (ergebnis.error or ""), ergebnis.error
    assert "gross" in (ergebnis.error or "").lower(), ergebnis.error


def test_fund14_normales_rechnen_bleibt_normales_rechnen():
    """Eine Grenze, die richtige Rechnungen abweist, ist keine Grenze."""
    from core.tools.builtin import rechne

    assert rechne("4380 * 0.17") == pytest.approx(744.6)
    assert rechne("2**64") == 2**64
    assert rechne("10**100") == 10**100
    assert rechne("round(3.14159, 2)") == 3.14


def test_fund14_die_bitgrenze_passt_genau_auf_die_stellengrenze():
    """Geprueft wird die Bitlaenge, gemeint sind Stellen - das muss stimmen.

    Eine Grenze, die man nur ungefaehr ausrechnet, ist entweder zu streng
    (richtige Rechnungen fliegen raus) oder zu lasch (der Fehler von vorhin
    kommt zurueck).
    """
    from core.tools.builtin import MAX_BITS, MAX_STELLEN

    groesste = 2**MAX_BITS - 1
    assert len(str(groesste)) == MAX_STELLEN, (
        "die groesste erlaubte Zahl muss sich noch hinschreiben lassen"
    )
    with pytest.raises(ValueError, match="4300 digits"):
        str(2 ** (MAX_BITS + 1))


def test_die_erlaubten_funktionen_koennen_keine_zahl_wachsen_lassen():
    """Waechter zu Fund 14.

    Der Groessendeckel steht nur an `BinOp`, weil das die einzige Stelle ist,
    an der eine Zahl waechst. Wer `FUNKTIONEN` erweitert, muss diesen Test
    ansehen: `factorial` oder `pow` wuerden die Annahme kippen und den
    Deckel unterlaufen.
    """
    from core.tools.builtin import FUNKTIONEN

    assert set(FUNKTIONEN) == {"abs", "round", "min", "max", "sum",
                               "int", "float"}, (
        "Neue Funktion in FUNKTIONEN - kann sie eine Zahl groesser machen? "
        "Dann gehoert _im_rahmen auch an den Call-Zweig."
    )


# --- Fund 15: can_call_agents wird nirgends geprueft ---------------------


def test_fund15_hermes_erreicht_ueber_ask_agent_nur_seine_eigene_liste():
    """BUGS-01 Fund 15 - die Liste war Deko.

    `hermes` traegt `can_call_agents = ['research', 'satellite']`. Geprueft
    hat das niemand: ueber `ask_agent` erreichte er auch `jarvis` (der
    `send_email` in den Werkzeugen hat) und sich selbst. Der Weg laeuft
    hier ueber den echten Runner, nicht ueber einen von Hand gesetzten
    Kontext - sonst prueft der Test seine eigene Verdrahtung.
    """
    import json as _json

    from core.contracts import Permission, TaskBudget
    from core.llm import FakeLLMProvider, FakeTurn, ToolUse
    from core.planner import PLANNER_MARKER
    from core.runner import ABSCHLUSS_PROMPT, fuehre_task_aus

    aufrufe: list = []

    class HermesRuftJarvis(FakeLLMProvider):
        """Hermes versucht genau einmal, jarvis zu rufen."""

        def __init__(self) -> None:
            super().__init__()
            self.delegiert = False

        async def complete(self, messages, *, system, tools=None):
            if system.startswith(PLANNER_MARKER):
                self._replies = [_json.dumps({"steps": [
                    {"description": "Delegieren", "agent": "hermes"}]})]
            elif system.startswith(ABSCHLUSS_PROMPT):
                self._replies = ["Zusammengefasst."]
            elif not self.delegiert:
                self.delegiert = True
                self._replies = [FakeTurn(tool_uses=(ToolUse(
                    "d1", "ask_agent",
                    {"agent": "jarvis", "task": "Schick eine Mail"}),))]
            else:
                self._replies = ["Fertig."]
            return await super().complete(messages, system=system, tools=tools)

    from core.runner import Laufzeit

    async def mitschreiben(aufruf):
        aufrufe.append(aufruf)

    run(fuehre_task_aus(HermesRuftJarvis(), "Delegiere an jarvis",
                        budget=TaskBudget(), kosten=lambda a, b: 0.0,
                        max_permission=Permission.LOCAL,
                        laufzeit=Laufzeit(on_call=mitschreiben)))

    delegationen = [a for a in aufrufe if a.name == "ask_agent"]
    assert len(delegationen) == 1, [a.name for a in aufrufe]
    ergebnis = delegationen[0].result
    assert ergebnis is not None and ergebnis.ok is False, (
        "hermes hat jarvis erreicht, obwohl der nicht in can_call_agents steht"
    )
    assert "jarvis" in (ergebnis.error or "")


def test_fund15_die_erlaubten_agenten_gehen_weiterhin_durch(suche_ohne_netz=None):
    """Eine Grenze, die auch das Erlaubte abweist, ist keine Grenze."""
    from core.contracts import Permission, Task, TaskBudget
    from core.delegation import DelegationsKontext, kontext
    from core.agents import baue_agenten
    from core.llm import FakeLLMProvider
    from core.tools.dispatch import run_tool as _run_tool

    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)
    assert agenten["hermes"].can_call_agents == ["research", "satellite"]

    haupt = Task(goal="x", budget=TaskBudget(max_depth=2), depth=0)
    marke = kontext.set(DelegationsKontext(
        task=haupt, agenten=agenten, max_depth=2, rufer="hermes"))
    try:
        ergebnis = run(_run_tool("ask_agent",
                                 {"agent": "research", "task": "Helme"}))
    finally:
        kontext.reset(marke)

    # Hier stand `assert ergebnis.ok is True`. Das war ein STELLVERTRETER
    # fuer "die Grenze hat ihn durchgelassen" - und er traegt nicht mehr,
    # seit `ask_agent` die Unterantwort verifiziert
    # (Verknuepfungspruefung 31.08.2026: auf dem Delegationspfad griff die
    # Verifikation vorher ueberhaupt nicht). `research` liefert unter
    # FakeLLMProvider keine Quelle, also faellt der Unterauftrag jetzt zu
    # Recht durch die Quellenregel - aus einem Grund, der mit der
    # Agenten-Freigabeliste nichts zu tun hat.
    #
    # Der Test wird deshalb NICHT aufgeweicht, sondern praezisiert: gemessen
    # wird ab jetzt genau das, was im Docstring steht. Die Freigabeliste ist
    # die Grenze, um die es geht - und die hat den Ruf durchgelassen.
    fehler = ergebnis.error or ""
    assert "nicht rufen" not in fehler, (
        f"die Freigabeliste hat 'research' abgewiesen: {fehler}")
    assert "darf" not in fehler, fehler
    # Und der Unterauftrag ist wirklich gelaufen - sonst waere "durchgelassen"
    # nur die Abwesenheit einer Fehlermeldung.
    assert ergebnis.data.get("agent") == "research", ergebnis.data
    assert ergebnis.data.get("subtask_id"), ergebnis.data
    # Der einzige Grund, aus dem er scheitern DARF, ist die Quellenregel.
    if not ergebnis.ok:
        assert "Quelle" in fehler, fehler


# --- Fund 16: /api/chat hat kein Budget ----------------------------------


def _chat_mit_werkzeugrunden(runden: int):
    """Ein Anbieter, der im Chat `runden` Mal ein Werkzeug ruft."""
    from core.llm import FakeLLMProvider, FakeTurn, ToolUse

    class Schleife(FakeLLMProvider):
        def __init__(self) -> None:
            super().__init__()
            self.werkzeugzuege = 0

        async def complete(self, messages, *, system, tools=None):
            if self.werkzeugzuege < runden:
                self.werkzeugzuege += 1
                self._replies = [FakeTurn(tool_uses=(
                    ToolUse(f"c{self.werkzeugzuege}", "clock", {}),
                ))]
            else:
                self._replies = ["Fertig."]
            return await super().complete(messages, system=system, tools=tools)

    return Schleife()


def test_fund16_chat_haelt_das_kostenbudget_ein(settings):
    """BUGS-01 Fund 16 - im Chat war nur die Rundenzahl begrenzt.

    Keine Token-, Kosten- oder Zeitschranke. Ein Chat-Zug konnte damit mehr
    kosten als ein ganzer Auftrag, fuer den 0.5 ein hartes Budget vorschreibt.
    Der Preis wird hier auf 1 EUR je Aufruf gesetzt, damit die Grenze nach dem
    ersten Zug faellt - geraten wird nichts.
    """
    TOKEN = {"X-Jarvis-Token": "test-token-123"}
    settings.budget_max_cost_eur = 1.5
    settings.llm_price_in_per_mtok = 1_000_000.0
    settings.llm_price_out_per_mtok = 1_000_000.0

    app = create_app(settings)
    with TestClient(app) as c:
        anbieter = _chat_mit_werkzeugrunden(6)
        app.state.provider = anbieter
        antwort = c.post("/api/chat", json={"message": "Wie spaet?"}, headers=TOKEN)

    assert antwort.status_code == 200, antwort.text
    assert anbieter.werkzeugzuege < 6, (
        f"{anbieter.werkzeugzuege} Runden trotz max_cost_eur=1.5"
    )


def test_fund16_chat_haelt_das_tokenbudget_ein(settings):
    """Die Grenze, die im Chat bisher gar nicht existierte."""
    TOKEN = {"X-Jarvis-Token": "test-token-123"}

    # Erst messen, was ein Lauf ohne Grenze verbraucht.
    from core.db import llm_call_totals

    settings.budget_max_tool_calls = 20
    app = create_app(settings)
    with TestClient(app) as c:
        app.state.provider = _chat_mit_werkzeugrunden(6)
        assert c.post("/api/chat", json={"message": "Wie spaet?"},
                      headers=TOKEN).status_code == 200
    ohne_grenze = llm_call_totals(settings.db_path)
    assert ohne_grenze["calls"] == 7, ohne_grenze

    verbraucht = ohne_grenze["in_tokens"] + ohne_grenze["out_tokens"]
    settings.budget_max_tokens = verbraucht // 3

    app = create_app(settings)
    with TestClient(app) as c:
        p = _chat_mit_werkzeugrunden(6)
        app.state.provider = p
        antwort = c.post("/api/chat", json={"message": "Wie spaet?"}, headers=TOKEN)

    assert antwort.status_code == 200, antwort.text
    assert p.werkzeugzuege < 6, (
        f"{p.werkzeugzuege} Runden trotz Tokengrenze {settings.budget_max_tokens}"
    )
    assert antwort.json()["reply"], "auch ein gedeckelter Zug antwortet"
