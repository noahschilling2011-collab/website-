"""FIX-09: was ein JARVIS wirklich braucht.

- Der Assistent heisst, wie der Nutzer ihn nennt (ASSISTENT_NAME, Vorgabe
  "Mehmet"); das Projekt heisst weiter JARVIS.
- Herkunft im Verlauf: was ein Zeitplan angestossen hat, sieht nicht aus
  wie getippt - und die Antwort kommt an (Ereignis, Zaehler am Chat-Tab).
- Einmalige Erinnerungen, auch aus dem Gespraech heraus (erinnerung_anlegen).
- Die Bremse: nach MAX_FEHLSCHLAEGE Fehlschlaegen in Folge pausiert ein Plan.
- Wetter ohne Key (Open-Meteo), gecacht.
- Vorlage Morgenlage aus Bausteinen, die wirklich eingerichtet sind.

Alles gegen FakeLLMProvider und httpx.MockTransport - kein Netz.
"""

from __future__ import annotations

import asyncio
import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.zeitplan import pruefe_einmal, vorlagen
from core import db, zeitplan
from core.config import Settings
from core.contracts import Task, TaskBudget
from core.db import session
from core.tools import registry

TOKEN = {"X-Jarvis-Token": "test-token-123"}
WURZEL = Path(__file__).resolve().parent.parent


@pytest.fixture(autouse=True)
def ohne_schleife(settings):
    settings.zeitplan_takt_s = 0


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def _warte_bis(bedingung, sekunden: float = 5.0):
    frist = time.monotonic() + sekunden
    while time.monotonic() < frist:
        if bedingung():
            return True
        time.sleep(0.02)
    return bedingung()


def _plan(db_path, regel="alle 6 stunden", ziel="Sag guten Morgen.", name="Morgen"):
    return zeitplan.anlegen(db_path, name=name, ziel=ziel, regel_text=regel)


def _faellig_seit(db_path, plan_id: str, sekunden: int) -> None:
    soll = datetime.now(timezone.utc) - timedelta(seconds=sekunden)
    with session(db_path) as conn:
        conn.execute("UPDATE zeitplaene SET naechster_lauf = ? WHERE id = ?",
                     (zeitplan._als_z(soll), plan_id))


# --- Der Name -------------------------------------------------------------


def test_der_assistent_heisst_mehmet_und_die_seite_weiss_es(client, settings):
    assert settings.assistent_name == "Mehmet"
    html = client.get("/").text
    assert "__ASSISTENT_NAME__" not in html
    assert "<title>Mehmet</title>" in html
    assert 'class="brand-name">Mehmet</h1>' in html
    assert "var NAME = 'Mehmet';" in html
    assert "__ASSISTENT_NAME__" not in client.get("/weltlage").text
    # Der Projektname bleibt, wo er hingehoert: in Code und Doku.
    assert "JARVIS" in (WURZEL / "README.md").read_text(encoding="utf-8")


def test_der_name_steht_in_jedem_prompt(settings):
    from core import agents
    from core.llm import FakeLLMProvider
    settings.assistent_name = "Mehmet"
    alt = agents.ASSISTENT_NAME
    agents.ASSISTENT_NAME = "Mehmet"
    try:
        alle = agents.baue_agenten(FakeLLMProvider(), max_permission=zeitplan.Permission.LOCAL)
        for name, agent in alle.items():
            assert "{name}" not in agent.system_prompt, name
            assert "Mehmet" in agent.system_prompt, name
            assert "JARVIS" not in agent.system_prompt.split("\n\n")[1][:80], name
    finally:
        agents.ASSISTENT_NAME = alt
    assert "Mehmet" in settings.system_prompt_mit_name
    assert "{name}" not in settings.system_prompt_mit_name


def test_die_app_setzt_den_namen_beim_start(settings):
    from core import agents
    settings.assistent_name = "Aylin"
    with TestClient(create_app(settings)) as c:
        assert agents.ASSISTENT_NAME == "Aylin"
        assert "<title>Aylin</title>" in c.get("/").text


@pytest.mark.parametrize("wert", ["", "<b>x</b>", "a'b", "x" * 41, "Name\"", "a\\nb"])
def test_ein_name_der_die_seite_bricht_wird_abgelehnt(wert):
    with pytest.raises(ValueError):
        Settings(_env_file=None, assistent_name=wert)


@pytest.mark.parametrize("wert", ["Mehmet", "J.A.R.V.I.S", "Frau Müller-Lüdenscheid", "R2 D2"])
def test_gewoehnliche_namen_gehen(wert):
    assert Settings(_env_file=None, assistent_name=wert).assistent_name == wert


# --- Herkunft im Verlauf --------------------------------------------------


def test_ein_zeitplan_auftrag_traegt_seine_herkunft(client, settings):
    plan = _plan(settings.db_path, name="Morgenlage")
    antwort = client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
    assert antwort.status_code == 202
    task_id = antwort.json()["task_id"]
    assert _warte_bis(lambda: (db.get_task_row(settings.db_path, task_id) or {}).get("status") == "done")
    nachrichten = client.get("/api/messages", headers=TOKEN).json()
    assert [m["role"] for m in nachrichten] == ["user", "assistant"]
    for m in nachrichten:
        assert m["herkunft"] == {"art": "zeitplan", "zeitplan_id": plan["id"],
                                 "zeitplan_name": "Morgenlage", "task_id": task_id}
    # Getippt bleibt ohne Herkunft.
    client.post("/api/tasks", json={"goal": "Hallo"}, headers=TOKEN)
    assert _warte_bis(lambda: len(client.get("/api/messages", headers=TOKEN).json()) == 4)
    assert client.get("/api/messages", headers=TOKEN).json()[-2]["herkunft"] is None


def test_das_letzte_ereignis_traegt_die_herkunft(client, settings):
    """Die Zustellung haengt daran: der Chat holt den Verlauf nur neu, wenn
    das Ereignis sagt, dass ein Zeitplan dahintersteckt."""
    import queue as _q
    plan = _plan(settings.db_path, name="Abendlage")
    ereignisse = client.portal.call(client.app.state.events.subscribe)
    assert client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN).status_code == 202
    gesehen = None
    frist = time.monotonic() + 5
    while time.monotonic() < frist:
        try:
            e = ereignisse.get_nowait()
        except asyncio.QueueEmpty:
            time.sleep(0.02)
            continue
        if e["type"] == "task" and e["data"].get("final"):
            gesehen = e["data"]
            break
    assert gesehen and gesehen["herkunft"]["zeitplan_name"] == "Abendlage"


def test_alte_verlaeufe_bleiben_lesbar(db_path):
    """Nachrichten ohne Herkunft kommen unveraendert - und Suche ueber den
    Verlauf (search_messages) bricht nicht an den neuen Spalten."""
    with session(db_path) as conn:
        db.init_db(conn)
    m = db.add_message(db_path, "user", "eins")
    [gelesen] = db.list_messages(db_path)
    assert gelesen.herkunft is None and gelesen.content == "eins"
    db.set_herkunft(db_path, m.id, art="zeitplan", zeitplan_id="p1", zeitplan_name="P", task_id="t")
    [gelesen] = db.list_messages(db_path, limit=5)
    assert gelesen.herkunft == {"art": "zeitplan", "zeitplan_id": "p1",
                                "zeitplan_name": "P", "task_id": "t"}


def test_die_oberflaeche_zeigt_herkunft_und_zaehlt_ungelesenes(client):
    html = client.get("/").text
    assert "herkunft.zeitplan_name" in html
    assert "zustellungStarten()" in html
    assert "jarvis.gelesenBis" in html
    assert "daten.herkunft" in html


# --- Einmalige Erinnerungen -----------------------------------------------


def test_einmal_regel_wird_gelesen_und_endet_nach_dem_lauf(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    morgen = (datetime.now().astimezone() + timedelta(days=1)).replace(hour=8, minute=0)
    text = f"einmal {morgen:%Y-%m-%d} 08:00"
    r = zeitplan.lies_regel(text)
    assert r.einmalig and r.text == text
    assert zeitplan.lies_regel(f"{morgen:%Y-%m-%d} 8:00").text == text     # ohne "einmal"
    plan = zeitplan.anlegen(settings.db_path, name="Zahnarzt", ziel="Erinnere mich", regel_text=text)
    lokal = zeitplan._aus_z(plan["naechster_lauf"]).astimezone()
    assert (lokal.hour, lokal.minute) == (8, 0)
    # Der Lauf verbraucht den Termin: danach aus, kein naechster.
    _faellig_seit(settings.db_path, plan["id"], 5)
    f = zeitplan.hole(settings.db_path, plan["id"])
    assert zeitplan.termin_weiter(settings.db_path, f, "startet") is True
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["aktiv"] == 0 and danach["naechster_lauf"] is None
    # Wieder einschalten geht nicht - der Zeitpunkt ist vorbei.
    zeitplan.schalten(settings.db_path, plan["id"], True)
    # (der Termin lag 5 s zurueck, aber "morgen 08:00" als Regel ist noch
    # in der Zukunft - also geht Einschalten hier sehr wohl:)
    assert zeitplan.hole(settings.db_path, plan["id"])["aktiv"] == 1


def test_einmal_in_der_vergangenheit_wird_abgelehnt(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    with pytest.raises(zeitplan.RegelUngueltig) as info:
        zeitplan.anlegen(settings.db_path, name="x", ziel="y", regel_text="einmal 2020-01-01 10:00")
    assert "Vergangenheit" in str(info.value)
    with pytest.raises(zeitplan.RegelUngueltig):
        zeitplan.lies_regel("einmal 2026-02-30 10:00")


def test_einmal_verpasst_heisst_aus(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    spaeter = datetime.now().astimezone() + timedelta(hours=2)
    plan = zeitplan.anlegen(settings.db_path, name="x", ziel="y",
                            regel_text=f"einmal {spaeter:%Y-%m-%d %H:%M}")
    _faellig_seit(settings.db_path, plan["id"], 3600)
    [f] = zeitplan.faellige(settings.db_path)
    assert zeitplan.verbuche_verpasst(settings.db_path, f) is True
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["verpasst"] == 1 and danach["aktiv"] == 0 and danach["naechster_lauf"] is None
    # Einschalten: Zeitpunkt vorbei -> bleibt aus, mit Grund.
    with session(settings.db_path) as conn:
        conn.execute("UPDATE zeitplaene SET regel = ? WHERE id = ?",
                     ("einmal 2020-01-01 10:00", plan["id"]))
    wieder = zeitplan.schalten(settings.db_path, plan["id"], True)
    assert wieder["aktiv"] == 0 and "vorbei" in wieder["letzter_status"]


def test_die_schleife_fuehrt_eine_erinnerung_genau_einmal_aus(client, settings):
    spaeter = datetime.now().astimezone() + timedelta(hours=1)
    plan = zeitplan.anlegen(settings.db_path, name="Zahnarzt", ziel="Erinnere mich: Zahnarzt",
                            regel_text=f"einmal {spaeter:%Y-%m-%d %H:%M}")
    _faellig_seit(settings.db_path, plan["id"], 10)
    assert client.portal.call(pruefe_einmal, client.app) == [(plan["id"], "gestartet")]
    assert _warte_bis(lambda: zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] == "done")
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["aktiv"] == 0 and danach["naechster_lauf"] is None
    assert client.portal.call(pruefe_einmal, client.app) == []
    assert len(db.list_task_rows(settings.db_path)) == 1


# --- Das Werkzeug erinnerung_anlegen --------------------------------------


def test_erinnerung_anlegen_legt_einen_plan_an(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    werkzeug = registry.get("erinnerung_anlegen")
    werkzeug.db_path = settings.db_path
    morgen = datetime.now().astimezone() + timedelta(days=1)
    ergebnis = asyncio.run(werkzeug.execute(text="Zahnarzt anrufen",
                                            wann=f"einmal {morgen:%Y-%m-%d} 08:00"))
    assert ergebnis.ok, ergebnis.error
    assert "Zahnarzt anrufen" in ergebnis.display and "einmalig" in ergebnis.display
    [plan] = zeitplan.alle(settings.db_path)
    assert plan["name"] == "Zahnarzt anrufen"
    assert plan["regel"].startswith("einmal ")
    assert "Zahnarzt anrufen" in plan["ziel"] and "ohne Werkzeuge" in plan["ziel"]
    assert ergebnis.data["id"] == plan["id"]
    # Wiederkehrend geht auch.
    assert asyncio.run(werkzeug.execute(text="Morgenlage", wann="taeglich 07:00")).ok


def test_erinnerung_anlegen_lehnt_unbrauchbares_ab(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    werkzeug = registry.get("erinnerung_anlegen")
    werkzeug.db_path = settings.db_path
    e = asyncio.run(werkzeug.execute(text="x", wann="morgen frueh"))
    assert not e.ok and "drei Formen" in e.error
    e = asyncio.run(werkzeug.execute(text="x", wann="einmal 2020-01-01 10:00"))
    assert not e.ok and "Vergangenheit" in e.error
    e = asyncio.run(werkzeug.execute(text="   ", wann="taeglich 07:00"))
    assert not e.ok
    werkzeug.db_path = ""
    e = asyncio.run(werkzeug.execute(text="x", wann="taeglich 07:00"))
    assert not e.ok and "nicht eingerichtet" in e.error
    assert zeitplan.alle(settings.db_path) == []


def test_hoechstens_max_plaene(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    for i in range(zeitplan.MAX_PLAENE):
        _plan(settings.db_path, name=f"p{i}")
    with pytest.raises(ValueError) as info:
        _plan(settings.db_path, name="einer zu viel")
    assert str(zeitplan.MAX_PLAENE) in str(info.value)
    werkzeug = registry.get("erinnerung_anlegen")
    werkzeug.db_path = settings.db_path
    e = asyncio.run(werkzeug.execute(text="noch einer", wann="taeglich 07:00"))
    assert not e.ok and "Loesche" in e.error


def test_erinnerung_anlegen_ist_local_und_beim_chat_agenten(settings):
    from core import agents
    from core.contracts import Permission
    from core.llm import FakeLLMProvider
    werkzeug = registry.get("erinnerung_anlegen")
    assert werkzeug.permission is Permission.LOCAL
    alle = agents.baue_agenten(FakeLLMProvider(), max_permission=Permission.LOCAL)
    assert "erinnerung_anlegen" in alle["jarvis"].tools and "wetter" in alle["jarvis"].tools


# --- Die Bremse -----------------------------------------------------------


def _fertig(db_path, plan, status):
    t = Task(goal="x", budget=TaskBudget()); t.status = status
    db.save_task(db_path, t)
    zeitplan.verbuche_start(db_path, plan, t.id, ausloeser="zeitplan")
    zeitplan.nachtrag_ergebnis(db_path, t.id, status)
    return zeitplan.hole(db_path, plan["id"])


def test_nach_drei_fehlschlaegen_pausiert_der_plan(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    assert _fertig(settings.db_path, plan, "failed")["fehlschlaege"] == 1
    assert _fertig(settings.db_path, plan, "done")["fehlschlaege"] == 0        # done setzt zurueck
    assert _fertig(settings.db_path, plan, "failed")["fehlschlaege"] == 1
    assert _fertig(settings.db_path, plan, "aborted_budget")["fehlschlaege"] == 2
    danach = _fertig(settings.db_path, plan, "failed")
    assert danach["fehlschlaege"] == 3 and danach["aktiv"] == 0 and danach["naechster_lauf"] is None
    assert danach["letzter_status"].startswith("pausiert nach 3 Fehlschlaegen")
    assert zeitplan.faellige(settings.db_path) == []
    # "An" ist der Weg zurueck - mit Zaehler auf null.
    wieder = zeitplan.schalten(settings.db_path, plan["id"], True)
    assert wieder["aktiv"] == 1 and wieder["fehlschlaege"] == 0 and wieder["naechster_lauf"]


def test_die_bremse_greift_ueber_den_echten_lauf(settings, monkeypatch):
    async def scheitert(provider, ziel, *, task, **_):  # noqa: ANN001
        task.status = "failed"
        task.result = "kaputt"

    monkeypatch.setattr("api.tasks.fuehre_task_aus", scheitert)
    with TestClient(create_app(settings)) as c:
        plan = _plan(settings.db_path)
        for _ in range(zeitplan.MAX_FEHLSCHLAEGE):
            _faellig_seit(settings.db_path, plan["id"], 5)
            with session(settings.db_path) as conn:
                conn.execute("UPDATE zeitplaene SET aktiv = 1 WHERE id = ?", (plan["id"],))
            assert c.portal.call(pruefe_einmal, c.app) == [(plan["id"], "gestartet")]
            assert _warte_bis(lambda: not c.app.state.zeitplan_tasks)
            assert _warte_bis(lambda: zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] != "laeuft")
        danach = zeitplan.hole(settings.db_path, plan["id"])
        assert danach["aktiv"] == 0 and "pausiert" in danach["letzter_status"]


def test_migration_ergaenzt_die_fehlschlaege_spalte(db_path):
    from scripts.migrate import migriere
    with session(db_path) as conn:
        db.init_db(conn)
        # Eine Datenbank von vor FIX-09: dieselbe Tabelle ohne die Spalte.
        conn.executescript("""
            DROP TABLE zeitplan_laeufe;
            DROP TABLE zeitplaene;
            CREATE TABLE zeitplaene (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, ziel TEXT NOT NULL,
                regel TEXT NOT NULL, aktiv INTEGER NOT NULL DEFAULT 1,
                erstellt_am TEXT NOT NULL, naechster_lauf TEXT, letzter_lauf TEXT,
                letzter_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                letzter_status TEXT, verpasst INTEGER NOT NULL DEFAULT 0);
        """)
    getan = migriere(db_path)
    assert any("fehlschlaege" in g for g in getan)
    with session(db_path) as conn:
        spalten = {r[1] for r in conn.execute("PRAGMA table_info(zeitplaene)")}
    assert "fehlschlaege" in spalten


# --- Wetter ----------------------------------------------------------------


GEO = {"results": [{"id": 2950159, "name": "Berlin", "latitude": 52.52437, "longitude": 13.41053,
                    "country": "Deutschland", "country_code": "DE", "admin1": "Berlin",
                    "timezone": "Europe/Berlin"}]}
VORHERSAGE = {
    "timezone": "Europe/Berlin",
    "current": {"time": "2026-09-05T18:00", "temperature_2m": 18.4, "weather_code": 3},
    "daily_units": {"precipitation_sum": "mm", "wind_speed_10m_max": "km/h"},
    "daily": {
        "time": ["2026-09-05", "2026-09-06"],
        "temperature_2m_max": [22.1, 19.0], "temperature_2m_min": [13.6, 11.2],
        "precipitation_sum": [0.2, 4.5], "precipitation_probability_max": [20, 80],
        "weather_code": [3, 61], "wind_speed_10m_max": [25.3, 31.0],
        "sunrise": ["2026-09-05T06:31", "2026-09-06T06:33"],
        "sunset": ["2026-09-05T19:45", "2026-09-06T19:43"],
    },
}


def _wetter_transport(aufrufe: list, geo=GEO, vorhersage=VORHERSAGE, status=200):
    def handler(request: httpx.Request) -> httpx.Response:
        aufrufe.append(request)
        assert "Authorization" not in request.headers
        if request.url.host == "geocoding-api.open-meteo.com":
            assert request.url.path == "/v1/search"
            assert request.url.params["name"] and request.url.params["count"] == "1"
            return httpx.Response(status, json=geo)
        if request.url.host == "api.open-meteo.com":
            assert request.url.path == "/v1/forecast"
            p = request.url.params
            assert p["timezone"] == "auto" and "temperature_2m_max" in p["daily"]
            assert p["current"] == "temperature_2m,weather_code"
            return httpx.Response(status, json=vorhersage)
        return httpx.Response(404)
    return httpx.MockTransport(handler)


def test_wetter_liefert_einen_deutschen_bericht(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    w = registry.get("wetter")
    aufrufe: list = []
    w.transport = _wetter_transport(aufrufe)
    w.db_path = settings.db_path
    e = asyncio.run(w.execute(ort="Berlin", tage=2))
    assert e.ok, e.error
    # Grade ohne Nachkommastelle (18,4 -> 18), Regen mit einer (0,2 mm).
    assert e.display.startswith("Berlin (DE, Berlin): jetzt 18 °C, bedeckt.")
    assert "Heute (05.09.): 14 bis 22 °C, bedeckt, Regen 0,2 mm (Wahrscheinlichkeit 20 %), Wind bis 25 km/h, Sonne 06:31 bis 19:45." in e.display
    assert "Morgen (06.09.): 11 bis 19 °C, leichter Regen, Regen 4,5 mm (Wahrscheinlichkeit 80 %)" in e.display
    assert "Quelle: Open-Meteo" in e.display and e.sources == ["https://open-meteo.com/"]
    assert e.data["cache"] is False and len(aufrufe) == 2
    assert aufrufe[1].url.params["forecast_days"] == "2"
    # Zweiter Aufruf: aus dem Cache, kein Netz.
    e2 = asyncio.run(w.execute(ort="berlin", tage=2))
    assert e2.ok and e2.data["cache"] is True and len(aufrufe) == 2 and e2.display == e.display


def test_wetter_ohne_ort_braucht_den_standardort(settings):
    w = registry.get("wetter")
    w.standard_ort = ""
    e = asyncio.run(w.execute())
    assert not e.ok and "JARVIS_ORT" in e.error
    aufrufe: list = []
    w.transport = _wetter_transport(aufrufe)
    w.standard_ort = "Berlin"
    w.db_path = ""
    assert asyncio.run(w.execute()).ok and aufrufe[0].url.params["name"] == "Berlin"


def test_wetter_unbekannter_ort_und_kaputter_dienst(settings):
    w = registry.get("wetter")
    w.db_path = ""
    w.transport = _wetter_transport([], geo={"generationtime_ms": 0.1})   # keine results
    e = asyncio.run(w.execute(ort="Nirgendwo-Xyz"))
    assert not e.ok and "kennt der Wetterdienst nicht" in e.display
    w.transport = _wetter_transport([], status=503)
    e = asyncio.run(w.execute(ort="Berlin"))
    assert not e.ok and "Wetterdienst nicht erreichbar" in e.display
    assert "503" not in e.display and "open-meteo" not in e.display.lower()

    def bricht(request):  # noqa: ANN001
        raise httpx.ConnectError("/geheim/pfad")
    w.transport = httpx.MockTransport(bricht)
    e = asyncio.run(w.execute(ort="Berlin"))
    assert not e.ok and "/geheim" not in e.display and "ConnectError" in e.display


def test_wetter_tage_werden_begrenzt(settings):
    w = registry.get("wetter")
    w.db_path = ""
    aufrufe: list = []
    w.transport = _wetter_transport(aufrufe)
    assert asyncio.run(w.execute(ort="Berlin", tage=9)).ok
    assert aufrufe[-1].url.params["forecast_days"] == "3"
    assert asyncio.run(w.execute(ort="Berlin", tage=0)).ok
    assert aufrufe[-1].url.params["forecast_days"] == "1"


def test_wettercodes_sind_die_aus_der_doku():
    from core.tools.wetter import wetter_text
    assert wetter_text(0) == "klar" and wetter_text(3) == "bedeckt"
    assert wetter_text(61) == "leichter Regen" and wetter_text(95) == "Gewitter"
    assert wetter_text(42) == "Wettercode 42" and wetter_text(None) == "unbekannt"


def test_wetter_ist_read_und_die_app_setzt_ort_und_datenbank(settings):
    from core.contracts import Permission
    assert registry.get("wetter").permission is Permission.READ
    settings.jarvis_ort = "Hamburg"
    with TestClient(create_app(settings)):
        w = registry.get("wetter")
        assert w.standard_ort == "Hamburg" and w.db_path == settings.db_path
        assert registry.get("erinnerung_anlegen").db_path == settings.db_path


# --- Vorlage ----------------------------------------------------------------


def test_vorlage_besteht_nur_aus_eingerichteten_bausteinen(settings):
    settings.jarvis_ort = ""
    settings.kalender_quelle = ""
    [v] = vorlagen(settings)
    assert v["name"] == "Morgenlage" and v["regel"] == "taeglich 07:00"
    assert "wetter" not in v["ziel"] and "kalender" not in v["ziel"] and "recall" in v["ziel"]
    assert "JARVIS_ORT" in v["hinweis"] and "KALENDER_QUELLE" in v["hinweis"]
    settings.jarvis_ort = "Berlin"
    settings.kalender_quelle = "/tmp/k.ics"
    [v] = vorlagen(settings)
    assert "Berlin" in v["ziel"] and "kalender" in v["ziel"]
    assert "Fehlt" not in v["hinweis"]
    zeitplan.lies_regel(v["regel"])                       # die Regel ist gueltig


def test_vorlage_ueber_http_und_die_oberflaeche_ruft_sie(client):
    antwort = client.get("/api/zeitplaene/vorlagen", headers=TOKEN)
    assert antwort.status_code == 200 and antwort.json()[0]["name"] == "Morgenlage"
    assert client.get("/api/zeitplaene/vorlagen").status_code == 401
    assert "/api/zeitplaene/vorlagen" in client.get("/").text
