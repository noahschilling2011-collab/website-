"""Der Ereignisstrom darf den Server nicht festhalten.

Verknuepfungspruefung 31.08.2026, Gruppe shutdown, Fund 1.

DER FUND
`strom()` in api/events.py laeuft absichtlich in `while True` und endet nur,
wenn der Client geht. Beim Herunterfahren schickt uvicorn einer schon
laufenden Antwort aber kein `http.disconnect`, sondern setzt nur
`cycle.keep_alive = False` - `request.is_disconnected` bleibt also False und
der Strom laeuft weiter. Weil `timeout_graceful_shutdown` nirgends gesetzt
war, wartete uvicorn in `Server._wait_tasks_to_complete()` UNBEGRENZT darauf.
Ein einziger offener Browser-Tab auf dem Command Center reichte.

Gemessen wurde vor der Reparatur, echtes SIGTERM an einen echten Prozess:

    leser=False warten=1.0s -> HAENGT (>25s) | 'Waiting for connections' im Log: True
    leser=True  warten=1.0s -> HAENGT (>25s) | 'Waiting for connections' im Log: True
    leser=True  warten=3.0s -> HAENGT (>25s) | 'Waiting for connections' im Log: True

WAS DIESE DATEI PRUEFT
Nicht die Oberflaeche ("steht der Schalter im Dockerfile"), sondern die
Ursache und ihre Wirkung:

1. Der Wert, den main.py WIRKLICH an `uvicorn.run` uebergibt - die Datei wird
   dafuer als `__main__` ausgefuehrt, `uvicorn.run` ist abgefangen.
2. Der Wert im CMD des Dockerfiles, und dass beide uebereinstimmen.
3. Ein echter uvicorn mit genau diesem Wert, ein echter offener /api/events,
   ein echtes Herunterfahren - der Server MUSS gehen, und der finally-Block
   des lifespan (`tasks.stop_alle()`, `provider.aclose()`) MUSS dabei laufen.
   Der lief vorher nie, weil uvicorn den lifespan-Shutdown erst NACH dem
   Warten auf die Verbindungen ausfuehrt.

Punkt 3 ist der eigentliche Test. Punkt 1 und 2 halten fest, WO der Wert
herkommen muss, damit der Nutzer ihn auch bekommt - in der Konsole wie im
Container.
"""

from __future__ import annotations

import json
import runpy
import socket
import threading
import time
from pathlib import Path

import httpx
import uvicorn

from api.app import create_app
from core.config import PROJECT_ROOT

# Laenger als jede vertretbare Wartezeit beim Herunterfahren, aber endlich -
# ein Test, der bei einem Rueckfall ewig haengt, ist kein Test.
WARTEGRENZE = 20.0

# Docker schiesst nach `stop_grace_period` (Voreinstellung 10 s) per SIGKILL.
# Wartet uvicorn laenger als das, hilft die Begrenzung im Container nichts:
# der lifespan-Shutdown kaeme dann trotzdem nie dran.
OBERGRENZE_SEKUNDEN = 10


def _freier_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _cmd_aus_dockerfile(pfad: Path) -> list[str]:
    """Der Startbefehl des Dockerfiles als Liste - mit Zeilenfortsetzung.

    Zwei Fallen, die dieser Parser bewusst beachtet:

    * Das `CMD` im HEALTHCHECK-Block gehoert zu HEALTHCHECK, nicht zum Start.
      Es ist eingerueckt - deshalb wird hier NICHT mit `lstrip()` gesucht,
      sondern nur eine Anweisung am Zeilenanfang genommen. (Der erste Anlauf
      dieses Tests fiel genau darauf herein und las
      `['python', '-m', 'scripts.healthcheck']`.)
    * Docker nimmt das LETZTE CMD einer Datei. Also auch hier das letzte.
    """
    bloecke: list[list[str]] = []
    laufend: list[str] | None = None
    for zeile in pfad.read_text(encoding="utf-8").splitlines():
        if laufend is None:
            if not zeile.startswith("CMD"):
                continue
            laufend = []
        fortsetzung = zeile.rstrip().endswith("\\")
        laufend.append(zeile.rstrip().rstrip("\\"))
        if not fortsetzung:
            bloecke.append(laufend)
            laufend = None
    assert bloecke, "Das Dockerfile hat gar kein CMD am Zeilenanfang."

    text = " ".join(bloecke[-1])
    assert "[" in text and "]" in text, f"CMD ist keine Exec-Form: {text!r}"
    return json.loads(text[text.index("["): text.rindex("]") + 1])


def _wert_nach(argumente: list[str], schalter: str) -> str | None:
    """Der Wert hinter einem Schalter, egal ob getrennt oder mit '='."""
    for i, stueck in enumerate(argumente):
        if stueck == schalter and i + 1 < len(argumente):
            return argumente[i + 1]
        if stueck.startswith(schalter + "="):
            return stueck.split("=", 1)[1]
    return None


def _uvicorn_kwargs_von_main() -> dict:
    """Fuehrt main.py als `__main__` aus und faengt den `uvicorn.run`-Aufruf.

    Bewusst kein Textvergleich auf der Datei: geprueft wird, was der
    Einstiegspunkt tatsaechlich an uvicorn uebergibt.
    """
    gefangen: dict = {}
    echt = uvicorn.run

    def faenger(*args, **kwargs):  # noqa: ANN001, ANN202
        gefangen["args"] = args
        gefangen["kwargs"] = kwargs

    uvicorn.run = faenger
    try:
        runpy.run_path(str(PROJECT_ROOT / "main.py"), run_name="__main__")
    finally:
        uvicorn.run = echt
    assert gefangen, "main.py hat als __main__ gar kein uvicorn.run aufgerufen"
    return gefangen["kwargs"]


def _grenze_aus_main() -> int:
    """Der Wert, den main.py wirklich uebergibt - mit lesbarer Meldung.

    Ohne diese Huelle bekaeme ein Rueckfall nur einen nackten KeyError zu
    sehen, und der sagt dem naechsten Leser nichts.
    """
    wert = _uvicorn_kwargs_von_main().get("timeout_graceful_shutdown")
    assert wert is not None, (
        "main.py uebergibt kein timeout_graceful_shutdown. Dann wartet uvicorn "
        "beim Herunterfahren unbegrenzt auf den offenen Ereignisstrom "
        "(api/events.py) - Verknuepfungspruefung 31.08.2026, Gruppe shutdown."
    )
    return wert


def _herunterfahren_mit_offenem_strom(settings, timeout_graceful) -> dict:
    """Echter Server, echter offener SSE-Strom, echtes Herunterfahren.

    Gibt zurueck, ob der Server ueberhaupt gegangen ist, wie lange er dafuer
    gebraucht hat, und ob der finally-Block des lifespan dabei lief.
    """
    port = _freier_port()
    app = create_app(settings)
    zusatz = {}
    if timeout_graceful is not None:
        zusatz["timeout_graceful_shutdown"] = timeout_graceful
    server = uvicorn.Server(uvicorn.Config(
        app, host="127.0.0.1", port=port, log_level="warning", **zusatz,
    ))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    ende = time.monotonic() + 15
    while not server.started and time.monotonic() < ende:
        time.sleep(0.02)
    assert server.started, "uvicorn ist nicht hochgekommen"

    # Der Beweis-Haken fuer den finally-Block in api/app.py. `stop_alle` ist
    # dort die erste Zeile nach dem `yield`; laeuft sie, ist der Block betreten
    # und `provider.aclose()` kommt unmittelbar danach.
    gesehen: list[str] = []
    echt_stop = app.state.tasks.stop_alle

    async def haken() -> None:
        gesehen.append("stop_alle")
        await echt_stop()

    app.state.tasks.stop_alle = haken

    strom = httpx.stream(
        "GET", f"http://127.0.0.1:{port}/api/events",
        headers={"X-Jarvis-Token": settings.jarvis_token}, timeout=WARTEGRENZE + 10,
    )
    antwort = strom.__enter__()
    try:
        zeilen = antwort.iter_lines()
        # Erst wenn die erste Zeile da ist, haelt der Generator wirklich eine
        # Verbindung offen - vorher waere der Test blind.
        erste = next(zeilen)
        assert erste == "event: hello", f"unerwarteter Stromanfang: {erste!r}"

        t0 = time.monotonic()
        server.should_exit = True
        thread.join(timeout=WARTEGRENZE)
        dauer = time.monotonic() - t0
        # JETZT ablesen, nicht spaeter. Das `finally` unten setzt zum
        # Aufraeumen `force_exit` und wartet noch einmal - danach ist der
        # Thread auch dann tot, wenn der Server gehangen hat. Genau darauf ist
        # der erste Anlauf dieses Tests hereingefallen: er meldete gruen,
        # obwohl der Server 20 s stand.
        beendet = not thread.is_alive()
    finally:
        if thread.is_alive():
            # Aufraeumen, damit ein roter Test nicht einen Server und einen
            # Port im Prozess zuruecklaesst.
            server.force_exit = True
            thread.join(timeout=10)
        try:
            strom.__exit__(None, None, None)
        except Exception:
            pass

    return {"beendet": beendet, "dauer": dauer, "lifespan_finally": bool(gesehen)}


def test_main_py_begrenzt_das_herunterfahren() -> None:
    """main.py muss uvicorn eine ENDLICHE Wartezeit mitgeben.

    Ohne sie ist `timeout_graceful_shutdown` None und uvicorn wartet ewig.
    """
    wert = _grenze_aus_main()

    assert isinstance(wert, int) and wert > 0, f"unbrauchbarer Wert: {wert!r}"
    assert wert <= OBERGRENZE_SEKUNDEN, (
        f"{wert}s ist laenger als Dockers Gnadenfrist von "
        f"{OBERGRENZE_SEKUNDEN}s - dann kommt der lifespan-Shutdown nie dran."
    )


def test_dockerfile_begrenzt_das_herunterfahren() -> None:
    """Und der Container muss denselben Wert bekommen.

    Das CMD ist der einzige Startbefehl im Image; steht der Schalter dort
    nicht, nuetzt die Begrenzung in main.py nichts, denn `python -m uvicorn`
    fuehrt den `__main__`-Block gar nicht aus.
    """
    cmd = _cmd_aus_dockerfile(PROJECT_ROOT / "Dockerfile")
    assert "uvicorn" in cmd, f"unerwartetes CMD: {cmd}"

    roh = _wert_nach(cmd, "--timeout-graceful-shutdown")
    assert roh is not None, (
        "Dem CMD im Dockerfile fehlt --timeout-graceful-shutdown. `docker stop` "
        "wartet dann seine vollen 10s ab und schiesst per SIGKILL, sobald ein "
        "Browser-Tab den Ereignisstrom haelt."
    )
    wert = int(roh)
    assert 0 < wert <= OBERGRENZE_SEKUNDEN, f"unbrauchbarer Wert: {roh!r}"

    aus_main = _grenze_aus_main()
    assert wert == aus_main, (
        f"Dockerfile sagt {wert}s, main.py sagt {aus_main}s. Zwei Startwege, "
        "zwei Verhalten - das faellt genau dann auf, wenn es weh tut."
    )


def test_server_geht_trotz_offenem_ereignisstrom(settings) -> None:
    """Der Kern des Fundes, am laufenden Server gemessen.

    Ein offener /api/events darf das Herunterfahren nicht aufhalten, und der
    finally-Block des lifespan MUSS dabei laufen - dort werden laufende Tasks
    beendet und der Anbieter geschlossen, damit keine bezahlten Modellaufrufe
    in der Luft haengen bleiben.
    """
    # BEWUSST ohne `_grenze_aus_main()`: hier wird der Wert genommen, den
    # main.py uebergibt, auch wenn das gar keiner ist. Sonst wuerde dieser Test
    # bei einem Rueckfall schon an der Zusicherung scheitern und die Wirkung
    # nie zeigen - und dann pruefte er nur noch dasselbe wie der Test darueber.
    # So faehrt er den Server wirklich in den Zustand von vor der Reparatur.
    wert = _uvicorn_kwargs_von_main().get("timeout_graceful_shutdown")
    erg = _herunterfahren_mit_offenem_strom(settings, wert)

    assert erg["beendet"], (
        f"Der Server stand nach {WARTEGRENZE:.0f}s immer noch, mit einem "
        f"einzigen offenen Ereignisstrom (timeout_graceful_shutdown={wert!r}). "
        "Genau das war Fund 1 der Gruppe shutdown."
    )
    assert wert is not None and erg["dauer"] < wert + 10, (
        f"Herunterfahren dauerte {erg['dauer']:.1f}s bei einer Grenze von "
        f"{wert}s - da wartet noch etwas anderes."
    )
    assert erg["lifespan_finally"], (
        "Der Server ging, aber der finally-Block in api/app.py lief nicht: "
        "tasks.stop_alle() und provider.aclose() wurden uebersprungen. uvicorn "
        "fuehrt den lifespan-Shutdown erst NACH dem Warten auf die "
        "Verbindungen aus - wartet es unbegrenzt, kommt der Block nie dran."
    )
