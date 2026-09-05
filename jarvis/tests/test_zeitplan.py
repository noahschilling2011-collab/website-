"""FIX-08: Zeitplaene - JARVIS wiederholt eigene Auftraege.

Drei Regeln aus core/zeitplan.py, jede mit einem Test, der kippt, wenn man
sie entfernt:

1. Obergrenze LOCAL, egal was MAX_PERMISSION sagt.
2. Ein Deckel ueber ALLE Plaene, ueber 24 Stunden, in Laeufen und Token.
3. Verpasste Laeufe werden gezaehlt, nicht nachgeholt.

Dazu: Regel-Parser, Terminberechnung, HTTP, Schleife im Lebenszyklus.
Alles gegen FakeLLMProvider - kein Modellaufruf, kein Netz.
"""

from __future__ import annotations

import asyncio
import os
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import UnavailableProvider, create_app
from api.tasks import LaufenderTask
from api.zeitplan import hindernis, pruefe_einmal
from core import db, zeitplan
from core.contracts import Permission, Task, TaskBudget
from core.db import session
from core.llm import LLMError

TOKEN = {"X-Jarvis-Token": "test-token-123"}
WURZEL = Path(__file__).resolve().parent.parent


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


def _plan(db_path, regel="alle 6 stunden", ziel="Sag guten Morgen.", name="Morgen"):
    return zeitplan.anlegen(db_path, name=name, ziel=ziel, regel_text=regel)


def _faellig_seit(db_path, plan_id: str, sekunden: int) -> None:
    """Den Termin von Hand in die Vergangenheit legen - so, wie er nach
    einem ausgeschalteten Rechner aussieht."""
    soll = datetime.now(timezone.utc) - timedelta(seconds=sekunden)
    with session(db_path) as conn:
        conn.execute("UPDATE zeitplaene SET naechster_lauf = ? WHERE id = ?",
                     (zeitplan._als_z(soll), plan_id))


def _task(db_path, token: int = 0) -> str:
    """Ein gespeicherter Task. Die Fremdschluessel in zeitplan_laeufe und
    zeitplaene sind Absicht: ein Lauf ohne Task ist eine Luege."""
    t = Task(goal="x", budget=TaskBudget())
    t.spent_tokens = token
    db.save_task(db_path, t)
    return t.id


def _warte_bis(bedingung, sekunden: float = 5.0):
    frist = time.monotonic() + sekunden
    while time.monotonic() < frist:
        if bedingung():
            return True
        time.sleep(0.02)
    return bedingung()


# --- Regeln ---------------------------------------------------------------


@pytest.mark.parametrize("roh,erwartet", [
    ("taeglich 07:00", "taeglich 07:00"),
    ("täglich 7:05", "taeglich 07:05"),
    ("  TAEGLICH   23:59 ", "taeglich 23:59"),
    ("alle 6 stunden", "alle 6 stunden"),
    ("Alle 1 Stunde", "alle 1 stunden"),
    ("alle 168 stunden", "alle 168 stunden"),
])
def test_die_zwei_erlaubten_formen(roh, erwartet):
    assert zeitplan.lies_regel(roh).text == erwartet


@pytest.mark.parametrize("roh", [
    "", "jeden Morgen", "*/6 * * * *", "taeglich 24:00", "taeglich 07:60",
    "alle 0 stunden", "alle 169 stunden", "alle sechs stunden", "taeglich",
    "montags 07:00",
])
def test_alles_andere_ist_ein_fehler_kein_ratespiel(roh):
    with pytest.raises(zeitplan.RegelUngueltig) as info:
        zeitplan.lies_regel(roh)
    # Die Absage nennt die erlaubten Formen - sonst raet der Nutzer weiter.
    if roh and "24:00" not in roh and "07:60" not in roh and "0 stunden" not in roh \
            and "169" not in roh:
        assert "taeglich 07:00" in str(info.value) and "alle 6 stunden" in str(info.value)


# --- Naechster Lauf -------------------------------------------------------


@pytest.fixture(params=["UTC", "Europe/Berlin", "America/Los_Angeles", "Asia/Kolkata"])
def ortszeit(request, monkeypatch):
    """'taeglich 07:00' meint die Ortszeit des Rechners - in jeder Zone."""
    if not hasattr(time, "tzset"):
        pytest.fail("Dieser Test braucht time.tzset (Unix).")
    monkeypatch.setenv("TZ", request.param)
    time.tzset()
    yield request.param
    monkeypatch.delenv("TZ", raising=False)
    time.tzset()


def test_taeglich_trifft_die_ortszeit_und_liegt_in_der_zukunft(ortszeit):
    ab = datetime(2026, 9, 5, 12, 0, tzinfo=timezone.utc)
    regel = zeitplan.lies_regel("taeglich 07:30")
    naechster = zeitplan._aus_z(zeitplan.naechster_lauf(regel, ab=ab))
    lokal = naechster.astimezone()
    assert (lokal.hour, lokal.minute, lokal.second) == (7, 30, 0)
    assert timedelta(0) < naechster - ab <= timedelta(hours=24)


def test_taeglich_heute_wenn_die_uhrzeit_noch_kommt(ortszeit):
    jetzt_lokal = datetime.now().astimezone().replace(second=0, microsecond=0)
    spaeter = jetzt_lokal + timedelta(minutes=5)
    if spaeter.date() != jetzt_lokal.date():
        spaeter = jetzt_lokal   # kurz vor Mitternacht: dann eben morgen
    regel = zeitplan.lies_regel(f"taeglich {spaeter.hour:02d}:{spaeter.minute:02d}")
    naechster = zeitplan._aus_z(zeitplan.naechster_lauf(regel, ab=jetzt_lokal))
    assert naechster - jetzt_lokal <= timedelta(minutes=5)


def test_stundentakt_zaehlt_ab_dem_letzten_lauf_und_holt_nicht_nach():
    regel = zeitplan.lies_regel("alle 6 stunden")
    ab = datetime(2026, 9, 5, 12, 0, tzinfo=timezone.utc)
    # Rechner war 13 Stunden aus: zwei Takte (6 h, 12 h) sind vorbei.
    letzter = ab - timedelta(hours=13)
    naechster = zeitplan._aus_z(zeitplan.naechster_lauf(regel, ab=ab, letzter=letzter))
    assert naechster == letzter + timedelta(hours=18)      # der naechste Takt DANACH
    assert naechster > ab
    # Ohne letzten Lauf: ab jetzt.
    assert zeitplan._aus_z(zeitplan.naechster_lauf(regel, ab=ab)) == ab + timedelta(hours=6)


def test_termine_stehen_im_format_von_utcnow():
    text = zeitplan.naechster_lauf(zeitplan.lies_regel("alle 2 stunden"))
    assert text.endswith("Z") and len(text) == len(db.utcnow())


# --- Datenbank ------------------------------------------------------------


def test_anlegen_lesen_schalten_loeschen(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path, regel="täglich 7:00", name="  Morgen   lage ")
    assert plan["name"] == "Morgen lage"
    assert plan["regel"] == "taeglich 07:00"
    assert plan["aktiv"] == 1 and plan["naechster_lauf"] > db.utcnow()
    assert [p["id"] for p in zeitplan.alle(settings.db_path)] == [plan["id"]]

    aus = zeitplan.schalten(settings.db_path, plan["id"], False)
    assert aus["aktiv"] == 0 and aus["naechster_lauf"] is None
    assert zeitplan.faellige(settings.db_path) == []

    an = zeitplan.schalten(settings.db_path, plan["id"], True)
    assert an["aktiv"] == 1 and an["naechster_lauf"] > db.utcnow()

    assert zeitplan.loeschen(settings.db_path, plan["id"]) is True
    assert zeitplan.loeschen(settings.db_path, plan["id"]) is False
    assert zeitplan.hole(settings.db_path, plan["id"]) is None
    assert zeitplan.schalten(settings.db_path, "gibtsnicht", True) is None


@pytest.mark.parametrize("name,ziel", [("", "x"), ("x", ""), ("   ", "x")])
def test_ohne_name_oder_auftrag_kein_plan(settings, name, ziel):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    with pytest.raises(ValueError):
        zeitplan.anlegen(settings.db_path, name=name, ziel=ziel, regel_text="alle 1 stunde")
    assert zeitplan.alle(settings.db_path) == []


def test_einschalten_rechnet_den_termin_neu_statt_sofort_zu_feuern(settings):
    """Regel 3 an der Stelle, an der man sie am leichtesten vergisst."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    zeitplan.schalten(settings.db_path, plan["id"], False)
    # Waehrend "aus" vergeht Zeit - simuliert: der alte Termin liegt zurueck.
    with session(settings.db_path) as conn:
        conn.execute("UPDATE zeitplaene SET naechster_lauf = ? WHERE id = ?",
                     ("2020-01-01T00:00:00Z", plan["id"]))
    an = zeitplan.schalten(settings.db_path, plan["id"], True)
    assert an["naechster_lauf"] > db.utcnow()
    assert zeitplan.faellige(settings.db_path) == []


def test_faellig_und_verpasst(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    assert zeitplan.faellige(settings.db_path) == []
    _faellig_seit(settings.db_path, plan["id"], 30)
    [f] = zeitplan.faellige(settings.db_path)
    assert f["id"] == plan["id"]
    assert zeitplan.ist_verpasst(f) is False           # 30 s: noch im Rahmen
    _faellig_seit(settings.db_path, plan["id"], 121)   # > TOLERANZ (2 min)
    [f] = zeitplan.faellige(settings.db_path)
    assert zeitplan.ist_verpasst(f) is True


def test_regel_3_verpasst_wird_gezaehlt_nicht_nachgeholt(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path, regel="taeglich 07:00")
    _faellig_seit(settings.db_path, plan["id"], 3 * 3600)
    [f] = zeitplan.faellige(settings.db_path)
    zeitplan.verbuche_verpasst(settings.db_path, f)
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["verpasst"] == 1
    assert danach["naechster_lauf"] > db.utcnow()
    assert "verpasst" in danach["letzter_status"] and "nicht nachgeholt" in danach["letzter_status"]
    assert danach["letzter_task_id"] is None            # kein Lauf entstanden
    assert zeitplan.verbrauch_24h(settings.db_path).laeufe == 0


def test_verbuche_start_schreibt_protokoll_und_neuen_termin(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path, regel="alle 6 stunden")
    _faellig_seit(settings.db_path, plan["id"], 10)
    [f] = zeitplan.faellige(settings.db_path)
    jetzt = datetime.now(timezone.utc)
    tid = _task(settings.db_path)
    zeitplan.verbuche_start(settings.db_path, f, tid, ausloeser="zeitplan",
                            status="laeuft", jetzt=jetzt)
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["letzter_task_id"] == tid
    assert danach["letzter_status"] == "laeuft"
    assert danach["letzter_lauf"] == zeitplan._als_z(jetzt)
    assert zeitplan._aus_z(danach["naechster_lauf"]) == (
        zeitplan._aus_z(zeitplan._als_z(jetzt)) + timedelta(hours=6))
    assert zeitplan.verbrauch_24h(settings.db_path).laeufe == 1


def test_uebersprungen_bekommt_neuen_termin_aber_keinen_lauf(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    _faellig_seit(settings.db_path, plan["id"], 10)
    [f] = zeitplan.faellige(settings.db_path)
    zeitplan.verbuche_start(settings.db_path, f, None, ausloeser="zeitplan",
                            status="uebersprungen: Test")
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["naechster_lauf"] > db.utcnow()
    assert danach["letzter_task_id"] is None and danach["letzter_lauf"] is None
    assert danach["letzter_status"] == "uebersprungen: Test"
    assert zeitplan.verbrauch_24h(settings.db_path).laeufe == 0
    assert zeitplan.faellige(settings.db_path) == []


def test_ein_handlauf_verschiebt_den_termin_nicht(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path, regel="taeglich 07:00")
    vorher = zeitplan.hole(settings.db_path, plan["id"])["naechster_lauf"]
    tid = _task(settings.db_path)
    zeitplan.verbuche_start(settings.db_path, plan, tid, ausloeser="hand",
                            status="laeuft")
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["naechster_lauf"] == vorher
    assert danach["letzter_task_id"] == tid
    assert zeitplan.verbrauch_24h(settings.db_path).laeufe == 1   # zaehlt trotzdem


def test_nachtrag_ergebnis(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    tid = _task(settings.db_path)
    zeitplan.verbuche_start(settings.db_path, plan, tid, ausloeser="hand", status="laeuft")
    zeitplan.nachtrag_ergebnis(settings.db_path, tid, "failed")
    assert zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] == "failed"
    zeitplan.nachtrag_ergebnis(settings.db_path, "unbekannt", "done")     # kein Fehler
    assert zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] == "failed"


def test_ein_lauf_ohne_task_wird_abgelehnt(settings):
    """Die Fremdschluessel sind kein Zufall: was in zeitplan_laeufe steht,
    ist ueber tasks nachpruefbar - oder es steht nicht drin."""
    import sqlite3
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    with pytest.raises(sqlite3.IntegrityError):
        zeitplan.verbuche_start(settings.db_path, plan, "erfunden",
                                ausloeser="hand", status="laeuft")
    assert zeitplan.hole(settings.db_path, plan["id"])["letzter_task_id"] is None


# --- Regel 2: der Deckel --------------------------------------------------


def test_verbrauch_zaehlt_alle_plaene_ueber_24_stunden(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    a = _plan(settings.db_path, name="A")
    b = _plan(settings.db_path, name="B")
    jetzt = datetime.now(timezone.utc)
    for plan, token, vor in ((a, 1000, timedelta(hours=1)),
                             (b, 2000, timedelta(hours=23)),
                             (a, 4000, timedelta(hours=25))):    # zu alt
        tid = _task(settings.db_path, token)
        zeitplan.verbuche_start(settings.db_path, plan, tid, ausloeser="zeitplan",
                                status="laeuft", jetzt=jetzt - vor)
    v = zeitplan.verbrauch_24h(settings.db_path, jetzt)
    assert v == zeitplan.Verbrauch(laeufe=2, token=3000)


def test_deckel_in_laeufen_und_in_token():
    assert zeitplan.deckel_erreicht(zeitplan.Verbrauch(2, 100), max_laeufe=3, max_token=1000) is None
    assert "Laeufen" in zeitplan.deckel_erreicht(zeitplan.Verbrauch(3, 100), max_laeufe=3, max_token=1000)
    assert "Token" in zeitplan.deckel_erreicht(zeitplan.Verbrauch(1, 1000), max_laeufe=3, max_token=1000)
    # Der Grund nennt die Stellschraube - sonst sucht der Nutzer.
    assert "ZEITPLAN_MAX_LAEUFE_24H" in zeitplan.deckel_erreicht(
        zeitplan.Verbrauch(3, 0), max_laeufe=3, max_token=1)
    assert "ZEITPLAN_MAX_TOKEN_24H" in zeitplan.deckel_erreicht(
        zeitplan.Verbrauch(0, 9), max_laeufe=3, max_token=9)


def test_der_deckel_ist_nicht_stillschweigend_erhoeht_worden():
    """CLAUDE.md Regel 6. Die Vorgaben sind die aus .env.example."""
    from core.config import Settings
    s = Settings(_env_file=None)
    beispiel = (WURZEL / ".env.example").read_text(encoding="utf-8")
    assert f"ZEITPLAN_MAX_LAEUFE_24H={s.zeitplan_max_laeufe_24h}" in beispiel
    assert f"ZEITPLAN_MAX_TOKEN_24H={s.zeitplan_max_token_24h}" in beispiel
    assert f"ZEITPLAN_TAKT_S={s.zeitplan_takt_s}" in beispiel
    assert s.zeitplan_max_token_24h <= 200_000     # unter dem Groq-Tageskontingent


# --- Regel 1: LOCAL, immer ------------------------------------------------


def test_regel_1_die_obergrenze_ist_local_egal_was_die_env_sagt(settings, monkeypatch):
    """Ein Zeitplan darf nicht mailen, auch wenn MAX_PERMISSION=4 steht."""
    settings.max_permission = Permission.SENSITIVE.value
    gesehen: list[Permission] = []

    async def stub(provider, ziel, *, task, max_permission, **_):  # noqa: ANN001
        gesehen.append(max_permission)
        task.status = "done"
        task.result = "ok"

    monkeypatch.setattr("api.tasks.fuehre_task_aus", stub)
    with TestClient(create_app(settings)) as c:
        plan = _plan(settings.db_path)
        _faellig_seit(settings.db_path, plan["id"], 5)
        protokoll = c.portal.call(pruefe_einmal, c.app)
        assert protokoll == [(plan["id"], "gestartet")]
        assert _warte_bis(lambda: gesehen != [])
        # Erst wenn der Lauf aus der Registry ist - sonst sagt /jetzt zu
        # Recht "laeuft noch" (409).
        tid = zeitplan.hole(settings.db_path, plan["id"])["letzter_task_id"]
        assert _warte_bis(lambda: c.app.state.tasks.get(tid) is None)
        # Und von Hand genauso.
        antwort = c.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
        assert antwort.status_code == 202, antwort.text
        assert _warte_bis(lambda: len(gesehen) == 2)
    assert gesehen == [Permission.LOCAL, Permission.LOCAL]
    assert zeitplan.PERMISSION_DECKEL is Permission.LOCAL


def test_getippte_auftraege_behalten_ihre_obergrenze(settings, monkeypatch):
    """Gegenprobe: die Kappung gilt fuer Zeitplaene, nicht fuer den Nutzer."""
    settings.max_permission = Permission.EXTERNAL.value
    gesehen: list[Permission] = []

    async def stub(provider, ziel, *, task, max_permission, **_):  # noqa: ANN001
        gesehen.append(max_permission)
        task.status = "done"

    monkeypatch.setattr("api.tasks.fuehre_task_aus", stub)
    with TestClient(create_app(settings)) as c:
        c.post("/api/tasks", json={"goal": "Mail an Noah"}, headers=TOKEN)
        assert _warte_bis(lambda: gesehen != [])
    assert gesehen == [Permission.EXTERNAL]


def test_die_regel_steht_an_einer_stelle():
    """Kein zweiter Runner fuer Zeitplaene: api/zeitplan.py startet ueber
    starte_task und gibt den Deckel mit. Wer das aendert, sieht es hier."""
    quelle = (WURZEL / "api" / "zeitplan.py").read_text(encoding="utf-8")
    assert "fuehre_task_aus" not in quelle
    assert "max_permission=zeitplan.PERMISSION_DECKEL" in quelle
    assert quelle.count("starte_task(") == 1


# --- Hindernisse ----------------------------------------------------------


def test_hindernis_ohne_anbieter(client, settings):
    plan = _plan(settings.db_path)
    assert hindernis(client.app, plan) is None
    client.app.state.provider = UnavailableProvider(
        LLMError("kein Key", kind="missing_api_key"), name="groq", model="m")
    grund = hindernis(client.app, plan)
    assert grund and "Anbieter" in grund
    antwort = client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
    assert antwort.status_code == 409 and "Anbieter" in antwort.json()["detail"]


def test_hindernis_wenn_der_vorige_lauf_noch_laeuft(client, settings):
    plan = _plan(settings.db_path)
    laufend = LaufenderTask(task=Task(goal="alt", budget=TaskBudget()))
    db.save_task(settings.db_path, laufend.task)
    client.app.state.tasks.add(laufend)
    zeitplan.verbuche_start(settings.db_path, plan, laufend.task.id,
                            ausloeser="zeitplan", status="laeuft")
    plan = zeitplan.hole(settings.db_path, plan["id"])
    grund = hindernis(client.app, plan)
    assert grund and "laeuft noch" in grund
    client.app.state.tasks.remove(laufend.task.id)
    assert hindernis(client.app, plan) is None


def test_hindernis_deckel(client, settings):
    plan = _plan(settings.db_path)
    settings.zeitplan_max_laeufe_24h = 0
    grund = hindernis(client.app, plan)
    assert grund and "Tagesdeckel" in grund
    antwort = client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
    assert antwort.status_code == 409 and "Tagesdeckel" in antwort.json()["detail"]
    assert db.list_task_rows(settings.db_path) == []


# --- Die Schleife ---------------------------------------------------------


def test_runde_startet_faellige_und_bucht_verpasste(client, settings):
    sofort = _plan(settings.db_path, name="sofort")
    spaet = _plan(settings.db_path, name="spaet")
    ruhig = _plan(settings.db_path, name="ruhig")
    _faellig_seit(settings.db_path, sofort["id"], 20)
    _faellig_seit(settings.db_path, spaet["id"], 15 * 60)
    protokoll = dict(client.portal.call(pruefe_einmal, client.app))
    assert protokoll == {sofort["id"]: "gestartet", spaet["id"]: "verpasst"}
    assert ruhig["id"] not in protokoll

    s = zeitplan.hole(settings.db_path, sofort["id"])
    assert s["letzter_task_id"] and s["naechster_lauf"] > db.utcnow()
    assert _warte_bis(lambda: client.app.state.tasks.get(s["letzter_task_id"]) is None)
    zeile = db.get_task_row(settings.db_path, s["letzter_task_id"])
    assert zeile["status"] == "done" and zeile["goal"] == "Sag guten Morgen."
    assert _warte_bis(lambda: zeitplan.hole(settings.db_path, sofort["id"])["letzter_status"] == "done")

    v = zeitplan.hole(settings.db_path, spaet["id"])
    assert v["verpasst"] == 1 and v["letzter_task_id"] is None
    assert [t["id"] for t in db.list_task_rows(settings.db_path)] == [s["letzter_task_id"]]

    # Die zweite Runde findet nichts mehr: jeder Plan hat einen neuen Termin.
    assert client.portal.call(pruefe_einmal, client.app) == []


def test_runde_ueberspringt_am_deckel_und_bleibt_nicht_haengen(client, settings):
    settings.zeitplan_max_token_24h = 0
    plan = _plan(settings.db_path)
    _faellig_seit(settings.db_path, plan["id"], 20)
    [(pid, was)] = client.portal.call(pruefe_einmal, client.app)
    assert pid == plan["id"] and was.startswith("uebersprungen: Tagesdeckel")
    assert db.list_task_rows(settings.db_path) == []
    danach = zeitplan.hole(settings.db_path, plan["id"])
    assert danach["letzter_status"] == was and danach["naechster_lauf"] > db.utcnow()
    assert client.portal.call(pruefe_einmal, client.app) == []


def test_ein_fehler_in_einer_runde_toetet_die_schleife_nicht(settings, monkeypatch):
    settings.zeitplan_takt_s = 1
    aufrufe = {"n": 0}

    async def kaputt(app, jetzt=None):  # noqa: ANN001
        aufrufe["n"] += 1
        raise RuntimeError("bumm")

    monkeypatch.setattr("api.zeitplan.pruefe_einmal", kaputt)
    with TestClient(create_app(settings)) as c:
        assert _warte_bis(lambda: aufrufe["n"] >= 2, sekunden=5)
        assert not c.app.state.zeitplan_task.done()


def test_die_schleife_lebt_mit_der_app_und_stirbt_mit_ihr(settings):
    with TestClient(create_app(settings)) as c:
        schleife = c.app.state.zeitplan_task
        assert isinstance(schleife, asyncio.Task) and not schleife.done()
    assert schleife.cancelled()


def test_takt_null_schaltet_die_schleife_ab(settings):
    settings.zeitplan_takt_s = 0
    with TestClient(create_app(settings)) as c:
        assert c.app.state.zeitplan_task is None
        # Von Hand geht es trotzdem.
        plan = _plan(settings.db_path)
        antwort = c.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
        assert antwort.status_code == 202
        assert c.get("/api/zeitplaene", headers=TOKEN).json()["schleife"] is False


# --- HTTP -----------------------------------------------------------------


@pytest.mark.parametrize("methode,pfad", [
    ("get", "/api/zeitplaene"), ("post", "/api/zeitplaene"),
    ("delete", "/api/zeitplaene/x"), ("post", "/api/zeitplaene/x/schalten"),
    ("post", "/api/zeitplaene/x/jetzt"),
])
def test_ohne_token_401(client, methode, pfad):
    assert client.request(methode, pfad, json={"aktiv": True}).status_code == 401


def test_anlegen_listen_schalten_loeschen_ueber_http(client, settings):
    antwort = client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "Morgenlage", "ziel": "Fasse den Kalender zusammen.",
        "regel": "täglich 07:00"})
    assert antwort.status_code == 201, antwort.text
    plan = antwort.json()
    assert plan["regel"] == "taeglich 07:00" and plan["aktiv"] == 1

    liste = client.get("/api/zeitplaene", headers=TOKEN).json()
    assert [p["id"] for p in liste["zeitplaene"]] == [plan["id"]]
    assert liste["obergrenze"] == "LOCAL"
    assert liste["deckel"] is None
    assert liste["verbrauch"] == {"laeufe": 0, "token": 0,
                                  "max_laeufe": settings.zeitplan_max_laeufe_24h,
                                  "max_token": settings.zeitplan_max_token_24h}
    assert liste["schleife"] is True

    aus = client.post(f"/api/zeitplaene/{plan['id']}/schalten", headers=TOKEN,
                      json={"aktiv": False})
    assert aus.status_code == 200 and aus.json()["aktiv"] == 0
    assert aus.json()["naechster_lauf"] is None

    assert client.delete(f"/api/zeitplaene/{plan['id']}", headers=TOKEN).json() == {
        "id": plan["id"], "geloescht": True}
    assert client.delete(f"/api/zeitplaene/{plan['id']}", headers=TOKEN).status_code == 404
    assert client.post(f"/api/zeitplaene/{plan['id']}/schalten", headers=TOKEN,
                       json={"aktiv": True}).status_code == 404
    assert client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN).status_code == 404


@pytest.mark.parametrize("body", [
    {"name": "x", "ziel": "y", "regel": "jeden Morgen"},
    {"name": "x", "ziel": "y", "regel": "taeglich 25:00"},
    {"name": "", "ziel": "y", "regel": "alle 6 stunden"},
    {"name": "x", "ziel": "", "regel": "alle 6 stunden"},
    {"name": "x", "ziel": "y"},
])
def test_unbrauchbare_eingaben_geben_422(client, settings, body):
    antwort = client.post("/api/zeitplaene", headers=TOKEN, json=body)
    assert antwort.status_code == 422
    if body.get("regel") == "jeden Morgen":
        assert "alle 6 stunden" in antwort.json()["detail"]
    assert client.get("/api/zeitplaene", headers=TOKEN).json()["zeitplaene"] == []


def test_jetzt_startet_einen_auftrag_und_traegt_den_ausgang_nach(client, settings):
    plan = client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "Test", "ziel": "Sag hallo.", "regel": "alle 6 stunden"}).json()
    antwort = client.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
    assert antwort.status_code == 202, antwort.text
    task_id = antwort.json()["task_id"]
    assert _warte_bis(lambda: (db.get_task_row(settings.db_path, task_id) or {})
                      .get("status") == "done")
    assert _warte_bis(lambda: zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] == "done")
    danach = client.get("/api/zeitplaene", headers=TOKEN).json()
    [p] = danach["zeitplaene"]
    assert p["letzter_task_id"] == task_id
    assert p["naechster_lauf"] == plan["naechster_lauf"]      # Hand verschiebt nicht
    assert danach["verbrauch"]["laeufe"] == 1
    assert danach["verbrauch"]["token"] == db.get_task_row(settings.db_path, task_id)["spent_tokens"]
    assert client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()["goal"] == "Sag hallo."


def test_die_oberflaeche_ruft_jede_route(client):
    html = client.get("/").text
    for stueck in ("/api/zeitplaene'", "/schalten'", "/jetzt'", "{ method: 'DELETE' }"):
        assert stueck in html, stueck
    assert "Zeitpläne" in html
