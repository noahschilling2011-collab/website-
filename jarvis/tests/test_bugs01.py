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
