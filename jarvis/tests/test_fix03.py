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
