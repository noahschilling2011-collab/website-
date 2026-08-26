"""Die Definition of Done aus `docs/FIX-03.md`.

Drei Reparaturen, die von aussen ausloesbar waren:

* `wiki_live` setzte den Zielhost aus einem Modellparameter zusammen und
  schickte den `Authorization`-Header damit an einen fremden Server.
* `fetch_url` folgte Weiterleitungen automatisch - die Adresspruefung lief nur
  auf der ersten Station.
* Abbruch und Budget griffen nur zwischen Schritten.

Jeder Test hier hat einen Negativtest. Ein Fix, der nur den Gutfall zeigt,
ist nicht nachgewiesen (Regel 2 des Auftrags).
"""

from __future__ import annotations

import re
from pathlib import Path

import httpx
import pytest

from tests.conftest import run

WURZEL = Path(__file__).resolve().parent.parent


# --- Werkzeug: ein Transport, der jede Anfrage mitschreibt ----------------


class Mitschnitt:
    """Laesst nichts durch und merkt sich alles."""

    def __init__(self) -> None:
        self.anfragen: list[httpx.Request] = []

    def transport(self) -> httpx.MockTransport:
        def behandeln(request: httpx.Request) -> httpx.Response:
            self.anfragen.append(request)
            return httpx.Response(200, json={"pages": []})

        return httpx.MockTransport(behandeln)

    @property
    def hosts(self) -> list[str]:
        return [r.url.host for r in self.anfragen]

    @property
    def autorisierungen(self) -> list[str]:
        return [r.headers[k] for r in self.anfragen
                for k in r.headers if k.lower() == "authorization"]


def _wiki_live(mitschnitt: Mitschnitt, *, kontakt="noah@example.org", token="GEHEIM"):
    from core.tools.wissen_tools import WikiLive

    w = WikiLive()
    w.transport = mitschnitt.transport()
    w.cache_an = False
    w.kontakt = kontakt
    w.token = token
    return w


# --- SCHRITT 1a: der Host kommt aus einer Konstante -----------------------


@pytest.mark.parametrize("sprache", [
    "evil.com/",            # der Fund aus dem Audit
    "evil.com",
    "de.evil.com",
    "127.0.0.1",
    "..",
    "de/../..",
])
def test_dod1_ein_boeser_sprachcode_erzeugt_keinen_ausgehenden_aufruf(sprache):
    """DoD 1: abgelehnt, und im Mitschnitt steht nichts."""
    m = Mitschnitt()
    ergebnis = run(_wiki_live(m).execute(begriff="Bergisel", sprache=sprache))

    assert ergebnis.ok is False, ergebnis.display
    assert m.anfragen == [], f"es ging etwas raus: {m.hosts}"


def test_schritt1a_ein_unbekannter_sprachcode_wird_abgelehnt_nicht_geraten():
    """Ein Sprachcode, der wie einer aussieht, aber nicht in der Zuordnung steht.

    Das ist der Unterschied zwischen der alten Reparatur und dem, was FIX-03
    verlangt: ein regulaerer Ausdruck laesst 'xx' durch und baut daraus
    'xx.wikipedia.org'. Eine feste Zuordnung tut das nicht.
    """
    m = Mitschnitt()
    ergebnis = run(_wiki_live(m).execute(begriff="Bergisel", sprache="xx"))

    assert ergebnis.ok is False, ergebnis.display
    assert m.anfragen == [], f"es ging etwas raus: {m.hosts}"
    assert "de" in (ergebnis.error or ""), (
        "Die Ablehnung soll sagen, welche Sprachen es gibt."
    )


def test_schritt1a_der_gutfall_geht_weiterhin_an_wikipedia():
    """Eine Sperre, die auch das Erlaubte abweist, ist keine Sperre."""
    m = Mitschnitt()
    ergebnis = run(_wiki_live(m).execute(begriff="Bergisel", sprache="de"))

    assert ergebnis.ok is True, ergebnis.error
    assert m.hosts == ["de.wikipedia.org"], m.hosts


def test_schritt1a_die_zuordnung_enthaelt_nur_wikipedia_hosts():
    """Waechter: wer die Zuordnung erweitert, faengt sich hier einen Fehler ein."""
    from core.tools.wissen_tools import WIKI_HOSTS

    assert WIKI_HOSTS, "leere Zuordnung waere eine Sperre gegen alles"
    for code, basis in WIKI_HOSTS.items():
        assert basis.startswith("https://"), (code, basis)
        assert basis.endswith(".wikipedia.org"), (code, basis)
        assert basis == "https://" + code + ".wikipedia.org", (
            f"{code!r} zeigt auf {basis!r} - das passt nicht zusammen"
        )


# --- DoD 2: nirgends ein Parameter im Host-Teil ---------------------------


# Ein Schema, zwei Schraegstriche, und dann irgendwo vor dem naechsten
# Schraegstrich eine geschweifte Klammer: genau das ist Interpolation in den
# Host-Teil. Im Pfad dahinter ist sie harmlos.
HOST_INTERPOLATION = re.compile(r"https?://[^/\s\"']*\{")


def _quelldateien() -> list[Path]:
    return [p for p in WURZEL.rglob("*.py")
            if "tests" not in p.parts
            and ".venv" not in p.parts
            and "__pycache__" not in p.parts]


def test_dod2_kein_parameter_im_hostteil_einer_url():
    """Der grep aus DoD 2 darf im Produktivcode nichts finden.

    Auch nicht im Docstring: eine URL-Vorlage mit Platzhalter im Host ist
    genau die Bauanleitung, die hier nicht mehr gelten soll.
    """
    treffer: list[str] = []
    for datei in _quelldateien():
        for nummer, zeile in enumerate(
            datei.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if HOST_INTERPOLATION.search(zeile):
                treffer.append(f"{datei.relative_to(WURZEL)}:{nummer}: {zeile.strip()}")

    assert treffer == [], "Parameter im Host-Teil:\n" + "\n".join(treffer)


def test_dod2_der_waechter_findet_so_eine_stelle_ueberhaupt():
    """Gegenprobe zum Test darueber - sonst prueft er nur sein eigenes Regex."""
    assert HOST_INTERPOLATION.search('f"https://' + '{sprache}.wikipedia.org/w/rest.php"')
    assert HOST_INTERPOLATION.search("url = f'http://{ziel}:{port}/api/health'")
    # Im PFAD ist eine Klammer harmlos und darf NICHT anschlagen.
    assert not HOST_INTERPOLATION.search('f"https://de.wikipedia.org/wiki/{titel}"')
    assert not HOST_INTERPOLATION.search('"https://query.wikidata.org/sparql"')


# --- SCHRITT 1b: zwei Klienten -------------------------------------------


def test_schritt1b_der_klient_nach_draussen_verweigert_anmeldedaten():
    from core.netz import AnmeldedatenNachDraussen, nach_draussen

    m = Mitschnitt()

    async def versuch(kopf: dict[str, str]):
        async with nach_draussen(timeout=5, transport=m.transport()) as client:
            return await client.get("https://fremd.test/x", headers=kopf)

    for kopf in ({"Authorization": "Bearer X"}, {"Cookie": "sid=1"},
                 {"X-Api-Key": "X"}, {"X-Jarvis-Token": "X"}):
        with pytest.raises(AnmeldedatenNachDraussen):
            run(versuch(kopf))
    assert m.anfragen == [], "die Sperre greift erst hinter dem Transport"

    # Gutfall: ohne Anmeldedaten geht es durch.
    antwort = run(versuch({}))
    assert antwort.status_code == 200 and len(m.anfragen) == 1


def test_schritt1b_der_dienstklient_verweigert_fremde_hosts():
    from core.netz import FalscherDienst, fuer_dienst

    m = Mitschnitt()

    async def versuch(url: str):
        async with fuer_dienst({"de.wikipedia.org"}, timeout=5,
                               transport=m.transport()) as client:
            return await client.get(url, headers={"Authorization": "Bearer X"})

    with pytest.raises(FalscherDienst):
        run(versuch("https://evil.com/x"))
    assert m.anfragen == []

    antwort = run(versuch("https://de.wikipedia.org/x"))
    assert antwort.status_code == 200
    assert m.autorisierungen == ["Bearer X"], (
        "an den eigenen Dienst darf die Anmeldung sehr wohl"
    )


def test_schritt1b_beide_klienten_folgen_keiner_weiterleitung_von_selbst():
    """Wer folgen will, prueft jede Station selbst (Schritt 2 Punkt 4)."""
    from core.netz import fuer_dienst, nach_draussen

    stationen: list[str] = []

    def umleiter(request: httpx.Request) -> httpx.Response:
        stationen.append(request.url.host)
        if request.url.host == "start.test":
            return httpx.Response(302, headers={"location": "http://127.0.0.1/admin"})
        return httpx.Response(200, text="geheim")

    async def hole(client):
        async with client:
            return await client.get("http://start.test/")

    for client in (nach_draussen(timeout=5, transport=httpx.MockTransport(umleiter)),
                   fuer_dienst({"start.test"}, timeout=5,
                               transport=httpx.MockTransport(umleiter))):
        stationen.clear()
        antwort = run(hole(client))
        assert antwort.status_code == 302
        assert stationen == ["start.test"], stationen


# --- DoD 3: ein fremder Server sieht nie einen Authorization-Header -------


def test_dod3_ein_fremder_server_sieht_nie_einen_authorization_header():
    """Kein MockTransport: ein echter Server, der jede Kopfzeile mitschreibt.

    Es wird versucht, `wiki_live` ueber den einzigen Hebel, den ein Modell
    hat - den Parameter `sprache` -, auf diesen Server zu lenken.
    """
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    aufzeichnung: list[dict[str, str]] = []

    class Lauscher(BaseHTTPRequestHandler):
        def do_GET(self):                      # noqa: N802
            aufzeichnung.append({k.lower(): v for k, v in self.headers.items()})
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"pages": []}')

        def log_message(self, *_):             # noqa: A003
            pass

    server = HTTPServer(("127.0.0.1", 0), Lauscher)
    port = server.server_port
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        from core.tools.wissen_tools import WikiLive

        for sprache in (f"127.0.0.1:{port}", "127.0.0.1", "localhost",
                        f"evil.com:{port}/", "xx"):
            w = WikiLive()
            w.cache_an = False
            w.kontakt = "noah@example.org"
            w.token = "GEHEIM-123"
            ergebnis = run(w.execute(begriff="Bergisel", sprache=sprache))
            assert ergebnis.ok is False, f"{sprache!r} wurde durchgelassen"
    finally:
        server.shutdown()

    assert aufzeichnung == [], (
        f"der fremde Server hat {len(aufzeichnung)} Anfrage(n) gesehen: {aufzeichnung}"
    )


def test_schritt1b_die_zweite_schicht_traegt_auch_wenn_die_erste_faellt(monkeypatch):
    """1a schuetzt eine Stelle, 1b jede - das ist der Satz aus FIX-03.

    Hier wird die erste Schicht absichtlich untergraben: jemand traegt einen
    fremden Host in `WIKI_HOSTS` ein. Der Sprachcode wird damit akzeptiert.
    Der Dienst-Klient laesst die Anfrage trotzdem nicht raus, weil seine
    erlaubte Menge beim Import festgelegt wurde und nicht mitwaechst.
    """
    from core.netz import FalscherDienst
    from core.tools import wissen_tools

    monkeypatch.setitem(wissen_tools.WIKI_HOSTS, "xx", "https://evil.com")

    m = Mitschnitt()
    with pytest.raises(FalscherDienst) as fehler:
        run(_wiki_live(m).execute(begriff="Bergisel", sprache="xx"))

    assert "evil.com" in str(fehler.value)
    assert m.anfragen == [], f"es ging etwas raus: {m.hosts}"


# --- Schritt 1a auch dort, wo der Wert nicht aus einem Modell kommt -------


def test_schritt1a_der_healthcheck_baut_keinen_host_aus_der_umgebung(monkeypatch):
    """`nirgends` heisst nirgends.

    `JARVIS_HOST` setzt derjenige, der den Container startet - kein Modell und
    kein Suchtreffer. Trotzdem wird der Wert geprueft statt geglaubt: eine
    Regel mit einer Ausnahme ist eine Regel, der niemand traut.
    """
    from scripts import healthcheck

    versuche: list[str] = []

    def kein_netz(url, timeout=None):          # noqa: ANN001
        versuche.append(url)
        raise AssertionError(f"es haette kein Aufruf passieren duerfen: {url}")

    monkeypatch.setattr(healthcheck.urllib.request, "urlopen", kein_netz)

    for boese in ("evil.com/x", "127.0.0.1/@evil.com", "127.0.0.1 evil.com",
                  "http://evil.com"):
        monkeypatch.setenv("JARVIS_HOST", boese)
        assert healthcheck.main() == 1, boese
    monkeypatch.setenv("JARVIS_HOST", "127.0.0.1")
    monkeypatch.setenv("JARVIS_PORT", "achtzig")
    assert healthcheck.main() == 1

    assert versuche == [], versuche


def test_schritt1a_der_healthcheck_fragt_den_eigenen_server_weiterhin(monkeypatch):
    """Gegenprobe: die Pruefung darf den Normalfall nicht mitnehmen."""
    from scripts import healthcheck

    gesehen: list[str] = []

    def merken(url, timeout=None):             # noqa: ANN001
        gesehen.append(url)

        class Antwort:
            pass

        return Antwort()

    monkeypatch.setattr(healthcheck.urllib.request, "urlopen", merken)
    monkeypatch.setenv("JARVIS_HOST", "0.0.0.0")
    monkeypatch.setenv("JARVIS_PORT", "8000")

    assert healthcheck.main() == 0
    assert gesehen == ["http://127.0.0.1:8000/api/health"], gesehen


# --- SCHRITT 2: fetch_url ------------------------------------------------


def _fetch(url: str, **felder):
    from core.tools.dispatch import run_tool

    return run(run_tool("fetch_url", {"url": url, **felder}))


@pytest.mark.parametrize("url", [
    "http://127.0.0.1:8080/admin",
    "http://169.254.169.254/",              # Metadaten der Cloud-Anbieter
    "http://[::1]/",
    "http://[fe80::1]/",                    # Link-Local, IPv6
    "http://10.0.0.1/",
    "http://192.168.1.1/",
    "http://172.16.0.1/",
    "file:///etc/passwd",
    "gopher://127.0.0.1:70/",
    "ftp://127.0.0.1/",
    "data:text/plain;base64,aGFsbG8=",
])
def test_dod4_interne_adressen_und_fremde_schemata_werden_abgewiesen(url):
    ergebnis = _fetch(url)
    assert ergebnis.ok is False, f"{url} wurde geholt: {(ergebnis.display or '')[:120]}"


def test_dod4_die_ablehnung_nennt_den_grund_und_nicht_den_inhalt():
    """Ein Fehler, den niemand lesen kann, ist keiner."""
    ergebnis = _fetch("http://169.254.169.254/latest/meta-data/")
    assert "169.254.169.254" in (ergebnis.error or "")
    assert ergebnis.data.get("text") is None if ergebnis.data else True


# --- DoD 5: die Weiterleitung ist der Standardweg um die Pruefung herum ---


class _Server:
    """Ein echter HTTP-Server auf 127.0.0.1.

    `/um` leitet auf `ziel` weiter, alles andere liefert den Geheimtext. So
    laesst sich eine Kette aus zwei Stationen bauen, ohne irgendetwas zu
    erfinden - beide Stationen sind echte Server, die wirklich antworten.
    """

    def __init__(self) -> None:
        import threading
        from http.server import BaseHTTPRequestHandler, HTTPServer

        self.gesehen: list[str] = []
        self.ziel = ""
        eigen = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):                  # noqa: N802
                eigen.gesehen.append(self.path)
                if self.path.startswith("/um"):
                    self.send_response(302)
                    self.send_header("location", eigen.ziel)
                    self.end_headers()
                    return
                koerper = b"GEHEIMES INTERNES DASHBOARD hunter2"
                self.send_response(200)
                self.send_header("content-type", "text/html")
                self.send_header("content-length", str(len(koerper)))
                self.end_headers()
                self.wfile.write(koerper)

            def log_message(self, *_):         # noqa: A003
                pass

        self._server = HTTPServer(("127.0.0.1", 0), Handler)
        self.port = self._server.server_port
        self.basis = f"http://127.0.0.1:{self.port}"
        self.marke = f"127.0.0.1:{self.port}"
        threading.Thread(target=self._server.serve_forever, daemon=True).start()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self._server.shutdown()


def test_dod5_eine_weiterleitung_auf_einen_internen_host_wird_gestoppt():
    """Der Standardweg um eine Eingangspruefung herum.

    Station 1 ist freigegeben, Station 2 nicht. Beide sind echte Server, die
    wirklich antworten - waere Station 2 tot, wuerde der Test aus dem falschen
    Grund gruen.
    """
    from core.tools.search import ERLAUBT_INTERN

    with _Server() as erlaubt, _Server() as verboten:
        erlaubt.ziel = f"{verboten.basis}/admin"
        ERLAUBT_INTERN.add(erlaubt.marke)
        try:
            ergebnis = _fetch(f"{erlaubt.basis}/um")
        finally:
            ERLAUBT_INTERN.discard(erlaubt.marke)

        gesehen_verboten = list(verboten.gesehen)
        gesehen_erlaubt = list(erlaubt.gesehen)

    assert ergebnis.ok is False, (ergebnis.display or "")[:200]
    assert "GEHEIM" not in (ergebnis.display or "")
    assert "GEHEIM" not in str(ergebnis.data or {})
    fehler = ergebnis.error or ""
    assert "Station" in fehler, f"die Station fehlt in der Meldung: {fehler}"
    assert str(verboten.port) in fehler, fehler
    assert gesehen_erlaubt == ["/um"], gesehen_erlaubt
    assert gesehen_verboten == [], (
        f"die zweite Station wurde trotzdem geholt: {gesehen_verboten}"
    )


def test_dod5_eine_weiterleitung_auf_einen_erlaubten_host_wird_verfolgt():
    """Gegenprobe: die Sperre darf nicht jede Weiterleitung abwuergen."""
    from core.tools.search import ERLAUBT_INTERN

    with _Server() as server:
        server.ziel = f"{server.basis}/seite"
        ERLAUBT_INTERN.add(server.marke)
        try:
            ergebnis = _fetch(f"{server.basis}/um")
        finally:
            ERLAUBT_INTERN.discard(server.marke)
        gesehen = list(server.gesehen)

    assert ergebnis.ok is True, ergebnis.error
    assert "GEHEIMES INTERNES DASHBOARD" in (ergebnis.display or "")
    assert gesehen == ["/um", "/seite"], gesehen


def test_dod5_eine_endlose_weiterleitungskette_endet():
    """Ohne Deckel dreht sich die Handkette ewig."""
    from core.tools.search import ERLAUBT_INTERN

    with _Server() as server:
        server.ziel = f"{server.basis}/um"     # auf sich selbst
        ERLAUBT_INTERN.add(server.marke)
        try:
            ergebnis = _fetch(f"{server.basis}/um")
        finally:
            ERLAUBT_INTERN.discard(server.marke)
        gesehen = list(server.gesehen)

    assert ergebnis.ok is False
    assert "eiterleitung" in (ergebnis.error or ""), ergebnis.error
    assert len(gesehen) <= 7, f"{len(gesehen)} Stationen - der Deckel greift nicht"


# --- Schritt 2 Punkt 5: die Antwortgroesse ist begrenzt -------------------


def test_schritt2_eine_riesige_antwort_wird_nicht_ganz_geladen():
    """Sonst flutet eine grosse Datei den Modellkontext - und den Speicher.

    Der Server schickt absichtlich mehr, als der Deckel erlaubt, und zaehlt
    mit, wie viel er wirklich losgeworden ist.
    """
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    from core.tools.search import ERLAUBT_INTERN, FetchUrl

    gesendet = {"bytes": 0}
    block = b"A" * 64_000

    class Riese(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):                      # noqa: N802
            self.send_response(200)
            self.send_header("content-type", "text/plain")
            self.send_header("transfer-encoding", "chunked")
            self.end_headers()
            try:
                for _ in range(200):           # 12,8 MB, wenn niemand abbricht
                    self.wfile.write(b"%x\r\n" % len(block) + block + b"\r\n")
                    self.wfile.flush()
                    gesendet["bytes"] += len(block)
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):             # noqa: A003
            pass

    server = HTTPServer(("127.0.0.1", 0), Riese)
    marke = f"127.0.0.1:{server.server_port}"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    ERLAUBT_INTERN.add(marke)
    try:
        ergebnis = _fetch(f"http://127.0.0.1:{server.server_port}/gross")
    finally:
        ERLAUBT_INTERN.discard(marke)
        server.shutdown()

    # Der Sender hat, als abgebrochen wurde, schon in die Socket-Puffer
    # geschrieben - das laesst sich nicht verhindern und ist auch nicht der
    # Punkt. Der Punkt ist, dass die Uebertragung frueh endet statt bis zum
    # letzten Byte zu laufen.
    voll = 200 * len(block)
    assert gesendet["bytes"] < voll // 2, (
        f"{gesendet['bytes']} von {voll} Bytes gingen raus - "
        "die Uebertragung wurde nicht abgebrochen"
    )
    assert ergebnis.ok is True, ergebnis.error
    assert (ergebnis.data or {}).get("truncated") is True, ergebnis.data


def test_schritt2_die_gepruefte_kette_haelt_den_bytedeckel_genau_ein():
    """Praezise gemessen, wo es zaehlt: was der Klient wirklich behaelt."""
    import httpx as _httpx

    from core.netz import nach_draussen
    from core.tools.search import hole_gepruefte_kette

    riesig = b"B" * 5_000_000

    def geben(request: _httpx.Request) -> _httpx.Response:
        return _httpx.Response(200, content=riesig,
                               headers={"content-type": "text/plain"})

    from core.tools.search import ERLAUBT_INTERN

    # Der Transport antwortet, aber die Adresspruefung loest den Namen
    # wirklich auf - deshalb eine Adresse, die es gibt, plus Freigabe.
    ziel = "http://127.0.0.1:1/x"

    async def holen(deckel: int):
        async with nach_draussen(timeout=5,
                                 transport=_httpx.MockTransport(geben)) as client:
            return await hole_gepruefte_kette(client, ziel, max_bytes=deckel)

    ERLAUBT_INTERN.add("127.0.0.1:1")
    try:
        for deckel in (1_000, 100_000, 2_000_000):
            _, roh, stationen = run(holen(deckel))
            assert len(roh) == deckel, (deckel, len(roh))
            assert stationen == [ziel]
    finally:
        ERLAUBT_INTERN.discard("127.0.0.1:1")


def test_schritt2_der_bekannte_restfehler_steht_im_code():
    """TOCTOU zwischen Aufloesen und Verbinden.

    FIX-03 verlangt ausdruecklich, dass diese Luecke als Kommentar im Code
    steht und nicht stillschweigend als geloest behandelt wird.
    """
    quelle = (WURZEL / "core" / "tools" / "search.py").read_text(encoding="utf-8")
    assert "TOCTOU" in quelle or "zwischen Aufloesen und Verbinden" in quelle, (
        "der bekannte Restfehler ist nirgends vermerkt"
    )


# --- Schritt 2 Punkt 3: welche Adressen gelten als intern ----------------


@pytest.mark.parametrize("adresse,intern", [
    ("127.0.0.1", True),
    ("10.0.0.1", True),
    ("192.168.1.1", True),
    ("172.16.0.1", True),
    ("169.254.169.254", True),       # Metadaten der Cloud-Anbieter
    ("100.64.0.1", True),            # CGNAT - nur is_global faengt die
    ("224.0.0.1", True),             # Multicast - is_global faengt die NICHT
    ("240.0.0.1", True),             # reserviert
    ("0.0.0.0", True),
    ("::1", True),
    ("fe80::1", True),
    ("fc00::1", True),
    ("ff02::1", True),               # Multicast, IPv6
    ("::ffff:127.0.0.1", True),      # IPv4 in IPv6 verpackt
    ("::ffff:10.0.0.1", True),
    ("8.8.8.8", False),
    ("1.1.1.1", False),
    ("2606:4700::1111", False),
    ("::ffff:8.8.8.8", False),
])
def test_schritt2_intern_und_oeffentlich_sind_gemessen_nicht_geraten(adresse, intern):
    """Waechter gegen eine Vereinfachung, die die Sperre schwaecher macht.

    Gemessen mit Pythons `ipaddress`: `is_global` allein laesst Multicast
    durch, `is_private` allein laesst CGNAT durch. Wer hier auf eine der
    beiden Pruefungen zusammenstreicht, faengt sich diesen Test ein.
    """
    import ipaddress

    from core.tools.search import _ist_intern

    assert _ist_intern(ipaddress.ip_address(adresse)) is intern, adresse


def test_schritt2_eine_ipv4_in_ipv6_adresse_kommt_nicht_durch():
    """`::ffff:127.0.0.1` ist dieselbe Maschine, nur anders geschrieben."""
    ergebnis = _fetch("http://[::ffff:127.0.0.1]:8080/admin")
    assert ergebnis.ok is False, (ergebnis.display or "")[:120]


def test_schritt2_verpackte_und_blanke_adressen_werden_gleich_beurteilt():
    """Die Annahme hinter dem fehlenden Auspacken in `_ist_intern`.

    Auf Python 3.11 beantwortet `ipaddress` `::ffff:10.0.0.1` genauso wie
    `10.0.0.1`. Sollte das auf einer neueren Version nicht mehr gelten, faellt
    dieser Test - und dann gehoert das Auspacken zurueck in den Code.
    """
    import ipaddress

    from core.tools.search import _ist_intern

    for blank in ("127.0.0.1", "10.0.0.1", "169.254.169.254", "100.64.0.1",
                  "224.0.0.1", "240.0.0.1", "8.8.8.8", "1.1.1.1"):
        verpackt = f"::ffff:{blank}"
        assert _ist_intern(ipaddress.ip_address(blank)) == \
            _ist_intern(ipaddress.ip_address(verpackt)), (
            f"{blank} und {verpackt} werden verschieden beurteilt - "
            "das Auspacken von ipv4_mapped gehoert zurueck in _ist_intern"
        )


# --- Schritt 2 Punkt 4 gilt auch fuer das Quellbild ----------------------


def test_schritt2_das_quellbild_folgt_keiner_weiterleitung_ins_eigene_netz():
    """Derselbe Fehler an einer zweiten Stelle.

    `hole_quellbild` holt eine Verlagsseite, deren URL aus dem Modell kommt.
    Die Adresspruefung lief dort auf der ersten Station - und danach stand
    `follow_redirects=True`.
    """
    from core.tools.search import ERLAUBT_INTERN
    from core.weltlage import hole_quellbild

    with _Server() as erlaubt, _Server() as verboten:
        erlaubt.ziel = f"{verboten.basis}/seite"
        ERLAUBT_INTERN.add(erlaubt.marke)
        try:
            bild = run(hole_quellbild(f"{erlaubt.basis}/um", medium="Test"))
        finally:
            ERLAUBT_INTERN.discard(erlaubt.marke)
        gesehen_verboten = list(verboten.gesehen)

    assert bild is None
    assert gesehen_verboten == [], (
        f"die zweite Station wurde geholt: {gesehen_verboten}"
    )
