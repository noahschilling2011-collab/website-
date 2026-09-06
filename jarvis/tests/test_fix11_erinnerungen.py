"""FIX-11 Punkt 3: Erinnerungen fuer Menschen (Vorschlaege 2, 3, 13).

Der Befund (docs/FIX-11.md), jeder Satz mit einem Test hier:

- Das Formular konnte nur Auftraege anlegen: `ZeitplanAnlegen` hatte kein
  Feld `art`. "einmal ... 11:23" wurde ein Modell-Auftrag mit drei
  Aufrufen, ohne Key gar nichts.
- "In 20 Minuten" musste das Modell mit clock aus UTC rechnen (E8). Jetzt
  sind "in N minuten" und "in N stunden" Eingabeformen, die `lies_regel`
  in `einmal JJJJ-MM-TT HH:MM` uebersetzt - aufgerundet, in Ortszeit,
  gespeichert wird nur die einmal-Form.
- Erinnerungen zaehlten in denselben Laeufe-Topf wie Auftraege (FIX-09 E9):
  "alle 1 stunden" buchte 24 von 24, die Morgenlage wurde still
  uebersprungen. Jetzt ein eigener Topf (ZEITPLAN_MAX_ERINNERUNGEN_24H).
- Ein unbeaufsichtigter Zeitplan-Lauf durfte `remember` und
  `erinnerung_anlegen` rufen (PERMISSION_DECKEL = LOCAL). Jetzt READ.
- Eine Erinnerung kam stumm an. Jetzt Ton, Benachrichtigung, Vorlesen -
  jede Reaktion einzeln abschaltbar, Erlaubnis nur aus der Nutzergeste.

Alles gegen FakeLLMProvider; die Browser-Tests laufen gegen den
Live-Server aus tests/conftest.py mit gestubbten Browser-Schnittstellen.
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.zeitplan import hindernis, pruefe_einmal, vorlagen
from core import db, zeitplan
from core.contracts import Permission
from core.db import session
from core.llm import FakeLLMProvider, FakeTurn, ToolUse
from core.planner import PLANNER_MARKER
from core.runner import ABSCHLUSS_PROMPT
from core.tools import registry

TOKEN = {"X-Jarvis-Token": "test-token-123"}
WURZEL = Path(__file__).resolve().parent.parent
UTC = timezone.utc


@pytest.fixture(autouse=True)
def ohne_schleife(settings):
    """Die Runde rufen die Tests selbst (wie in tests/test_zeitplan.py)."""
    settings.zeitplan_takt_s = 0


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


@pytest.fixture(params=["UTC", "Europe/Berlin", "America/Los_Angeles", "Asia/Kolkata"])
def ortszeit(request, monkeypatch):
    if not hasattr(time, "tzset"):
        pytest.fail("Dieser Test braucht time.tzset (Unix).")
    monkeypatch.setenv("TZ", request.param)
    time.tzset()
    yield request.param
    monkeypatch.delenv("TZ", raising=False)
    time.tzset()


def _init(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)


def _faellig_seit(db_path, plan_id: str, sekunden: int) -> None:
    soll = datetime.now(UTC) - timedelta(seconds=sekunden)
    with session(db_path) as conn:
        conn.execute("UPDATE zeitplaene SET naechster_lauf = ? WHERE id = ?",
                     (zeitplan._als_z(soll), plan_id))


def _warte_bis(bedingung, sekunden: float = 8.0):
    frist = time.monotonic() + sekunden
    while time.monotonic() < frist:
        if bedingung():
            return True
        time.sleep(0.02)
    return bedingung()


def _termin(regel: zeitplan.Regel) -> datetime:
    return zeitplan._aus_z(zeitplan.naechster_lauf(regel))


# --- "in N minuten" / "in N stunden": Eingabeformen, keine Regeln ----------


def test_in_n_minuten_wird_zur_einmal_regel_und_rundet_auf(ortszeit):
    """jetzt + N, auf die volle Minute AUFgerundet - in jeder Zeitzone."""
    jetzt = datetime(2026, 9, 6, 10, 0, 30, tzinfo=UTC)
    r = zeitplan.lies_regel("in 2 minuten", jetzt)
    assert r.art == "einmal" and r.einmalig and r.text.startswith("einmal ")
    assert _termin(r) == datetime(2026, 9, 6, 10, 3, tzinfo=UTC)          # 10:02:30 -> 10:03
    # Volle Minute: nichts zu runden.
    r = zeitplan.lies_regel("in 2 minuten", jetzt.replace(second=0))
    assert _termin(r) == datetime(2026, 9, 6, 10, 2, tzinfo=UTC)
    # Ein Mikrosekundenbruchteil rundet trotzdem auf.
    r = zeitplan.lies_regel("in 1 minute", jetzt.replace(second=0, microsecond=1))
    assert _termin(r) == datetime(2026, 9, 6, 10, 2, tzinfo=UTC)
    # Stunden, Gross-/Kleinschreibung, Singular, doppelte Leerzeichen.
    assert _termin(zeitplan.lies_regel("In  2  Stunden", jetzt)) == datetime(2026, 9, 6, 12, 1, tzinfo=UTC)
    assert _termin(zeitplan.lies_regel("in 1 stunde", jetzt)) == datetime(2026, 9, 6, 11, 1, tzinfo=UTC)
    assert _termin(zeitplan.lies_regel("in 90 minuten", jetzt)) == datetime(2026, 9, 6, 11, 31, tzinfo=UTC)
    # Die Grenzen sind eine Woche.
    assert _termin(zeitplan.lies_regel("in 10080 minuten", jetzt)) == jetzt.replace(second=0) + timedelta(days=7, minutes=1)
    assert _termin(zeitplan.lies_regel("in 168 stunden", jetzt)) == jetzt.replace(second=0) + timedelta(days=7, minutes=1)
    # Die gespeicherte Form ist die Ortszeit dieses Rechners.
    lokal = _termin(zeitplan.lies_regel("in 2 minuten", jetzt)).astimezone()
    assert zeitplan.lies_regel("in 2 minuten", jetzt).text == f"einmal {lokal:%Y-%m-%d %H:%M}"


@pytest.mark.parametrize("roh", [
    "in 0 minuten", "in 10081 minuten", "in 99999 minuten", "in 0 stunden",
    "in 169 stunden", "in zwei minuten", "in 5 tagen", "in minuten", "in 3",
])
def test_in_n_ausserhalb_oder_unverstanden_ist_ein_fehler_mit_den_formen(roh):
    with pytest.raises(zeitplan.RegelUngueltig) as info:
        zeitplan.lies_regel(roh)
    text = str(info.value)
    # Die Absage nennt, was erlaubt ist - sonst raet der Nutzer weiter.
    assert "in " in text and "einmal" in text
    if "minuten" in roh and roh[3].isdigit():
        assert str(zeitplan.MAX_MINUTEN) in text
    if "stunden" in roh and roh[3].isdigit():
        assert str(zeitplan.MAX_STUNDEN) in text


def test_die_vergangenheit_ist_unmoeglich(settings):
    """Aufgerundet plus mindestens eine Minute: kein 'liegt in der
    Vergangenheit', egal wie spaet in der Minute man tippt."""
    _init(settings)
    for sekunde in (0, 1, 30, 59):
        jetzt = datetime.now(UTC).replace(second=sekunde, microsecond=999_999)
        r = zeitplan.lies_regel("in 1 minute", jetzt)
        assert _termin(r) > jetzt
        plan = zeitplan.anlegen(settings.db_path, name="x", ziel="y",
                                regel_text="in 1 minute", art="erinnerung", jetzt=jetzt)
        assert plan["regel"].startswith("einmal ") and plan["art"] == "erinnerung"
        assert zeitplan._aus_z(plan["naechster_lauf"]) > jetzt


def test_zeitumstellung_luecke_und_doppelte_stunde(settings, monkeypatch):
    """E7 fuer die relative Form: in UTC gerechnet gibt es die Uhrzeit auch
    am Tag der Umstellung. Die doppelte Stunde im Herbst wird abgelehnt
    statt eine Stunde zu frueh zugestellt."""
    if not hasattr(time, "tzset"):
        pytest.fail("braucht time.tzset (Unix)")
    monkeypatch.setenv("TZ", "Europe/Berlin")
    time.tzset()
    try:
        _init(settings)
        # 28.03.2027: 02:00 CET springt auf 03:00 CEST. Um 01:30 "in 60 minuten"
        # heisst 03:30 - nicht die Luecke 02:30, an der `anlegen` abbricht.
        jetzt = datetime(2027, 3, 28, 0, 30, tzinfo=UTC)          # 01:30 CET
        r = zeitplan.lies_regel("in 60 minuten", jetzt)
        assert r.text == "einmal 2027-03-28 03:30"
        assert _termin(r) == datetime(2027, 3, 28, 1, 30, tzinfo=UTC)
        plan = zeitplan.anlegen(settings.db_path, name="x", ziel="y",
                                regel_text="in 60 minuten", art="erinnerung", jetzt=jetzt)
        assert plan["naechster_lauf"] == zeitplan._als_z(datetime(2027, 3, 28, 1, 30, tzinfo=UTC))
        # 25.10.2026: 03:00 CEST faellt auf 02:00 CET zurueck - 02:30 gibt es
        # zweimal. Die erste laesst sich speichern, die zweite nicht.
        erste = zeitplan.lies_regel("in 30 minuten", datetime(2026, 10, 25, 0, 0, tzinfo=UTC))
        assert erste.text == "einmal 2026-10-25 02:30"
        assert _termin(erste) == datetime(2026, 10, 25, 0, 30, tzinfo=UTC)
        with pytest.raises(zeitplan.RegelUngueltig) as info:
            zeitplan.lies_regel("in 30 minuten", datetime(2026, 10, 25, 1, 0, tzinfo=UTC))
        assert "Zeitumstellung" in str(info.value)
    finally:
        monkeypatch.delenv("TZ", raising=False)
        time.tzset()


def test_in_1_minute_endet_bei_takt_300_nicht_als_verpasst(settings):
    """Die Schleife sieht alle 300 s nach. Eine Erinnerung 'in 1 minute'
    ist dann bis zu 5 Minuten faellig, bevor jemand hinsieht - und darf
    deshalb nicht als verpasst enden (toleranz_fuer folgt dem Takt)."""
    settings.zeitplan_takt_s = 300
    jetzt = datetime.now(UTC)
    with TestClient(create_app(settings)) as c:
        plan = zeitplan.anlegen(settings.db_path, name="Wasser", ziel="Wasser trinken",
                                regel_text="in 1 minute", art="erinnerung", jetzt=jetzt)
        termin = zeitplan._aus_z(plan["naechster_lauf"])
        assert timedelta(minutes=1) <= termin - jetzt <= timedelta(minutes=2)
        # Die Runde davor lag knapp vor dem Termin; die naechste kommt einen
        # Takt spaeter, plus die Sekunde, die die Runde selbst braucht -
        # der schlechteste Fall.
        runde = termin + timedelta(seconds=settings.zeitplan_takt_s + 1)
        assert zeitplan.ist_verpasst(plan, runde) is True             # mit fester 2-min-Toleranz waere es weg
        assert zeitplan.toleranz_fuer(settings.zeitplan_takt_s, settings.budget_max_seconds) \
            >= timedelta(seconds=settings.zeitplan_takt_s + 1)
        assert c.portal.call(pruefe_einmal, c.app, runde) == [(plan["id"], "erinnert")]
        danach = zeitplan.hole(settings.db_path, plan["id"])
        assert danach["verpasst"] == 0 and danach["letzter_status"] == "done"
        [m] = c.get("/api/messages", headers=TOKEN).json()
        assert m["content"] == "Erinnerung: Wasser trinken"


# --- ueber HTTP: art und die neuen Formen ------------------------------------


def test_post_zeitplan_mit_art_erinnerung_und_in_2_minuten(client, settings):
    vorher = datetime.now(UTC)
    antwort = client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "Wasser", "ziel": "Wasser trinken", "regel": "in 2 minuten",
        "art": "erinnerung"})
    assert antwort.status_code == 201, antwort.text
    p = antwort.json()
    assert p["art"] == "erinnerung"
    assert p["regel"].startswith("einmal ")                       # gespeichert wird die einmal-Form
    termin = zeitplan._aus_z(p["naechster_lauf"])
    assert termin.second == 0 and termin.microsecond == 0
    assert vorher + timedelta(minutes=2) <= termin <= vorher + timedelta(minutes=3)
    # Ohne `art` bleibt es ein Auftrag - additiv.
    ohne = client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "Lage", "ziel": "Sag hallo.", "regel": "in 2 stunden"})
    assert ohne.status_code == 201 and ohne.json()["art"] == "auftrag"
    assert client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "x", "ziel": "y", "regel": "taeglich 07:00", "art": "cron"}).status_code == 422

    # Faellig: Nachricht mit Herkunft, kein Task, kein Modellaufruf.
    _faellig_seit(settings.db_path, p["id"], 10)
    fake = client.app.state.provider
    assert client.portal.call(pruefe_einmal, client.app) == [(p["id"], "erinnert")]
    assert fake.calls == []
    assert db.list_task_rows(settings.db_path) == []
    with session(settings.db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM llm_calls").fetchone()[0] == 0
    [m] = client.get("/api/messages", headers=TOKEN).json()
    assert m["content"] == "Erinnerung: Wasser trinken"
    assert m["herkunft"]["art"] == "erinnerung" and m["herkunft"]["task_id"] is None
    danach = zeitplan.hole(settings.db_path, p["id"])
    assert danach["aktiv"] == 0 and danach["naechster_lauf"] is None and danach["letzter_status"] == "done"


@pytest.mark.parametrize("regel", ["in 0 minuten", "in 99999 minuten", "in 0 stunden", "in 200 stunden"])
def test_in_n_ausserhalb_gibt_422_mit_den_erlaubten_formen(client, regel):
    antwort = client.post("/api/zeitplaene", headers=TOKEN, json={
        "name": "x", "ziel": "y", "regel": regel, "art": "erinnerung"})
    assert antwort.status_code == 422, antwort.text
    detail = antwort.json()["detail"]
    assert "in 1 " in detail and "einmal" in detail
    assert client.get("/api/zeitplaene", headers=TOKEN).json()["zeitplaene"] == []


# --- Der eigene Topf ----------------------------------------------------------


def test_deckel_erreicht_prueft_nur_die_mitgegebenen_toepfe():
    voll_e = zeitplan.Verbrauch(0, 0, erinnerungen=24)
    voll_a = zeitplan.Verbrauch(24, 0, erinnerungen=0)
    # Erinnerungen halten keinen Auftrag auf ...
    assert zeitplan.deckel_erreicht(voll_e, max_laeufe=24, max_token=50_000) is None
    # ... und Auftraege keine Erinnerung.
    assert zeitplan.deckel_erreicht(voll_a, max_erinnerungen=24) is None
    grund = zeitplan.deckel_erreicht(voll_e, max_erinnerungen=24)
    assert grund and "Erinnerungs-Deckel" in grund and "ZEITPLAN_MAX_ERINNERUNGEN_24H" in grund
    assert zeitplan.deckel_erreicht(zeitplan.Verbrauch(0, 0, 23), max_erinnerungen=24) is None
    assert zeitplan.deckel_erreicht(zeitplan.Verbrauch(0, 0, 0), max_erinnerungen=0)
    # Die alte Form der Aufrufe bleibt, wie sie war.
    assert "Laeufen" in zeitplan.deckel_erreicht(voll_a, max_laeufe=24, max_token=50_000)
    # Und ein Token-Deckel von 0 sperrt keine Erinnerung (sie kostet nichts).
    assert zeitplan.deckel_erreicht(zeitplan.Verbrauch(0, 0, 1), max_erinnerungen=24) is None


def test_verbrauch_trennt_erinnerungen_von_auftraegen(settings):
    _init(settings)
    auftrag = zeitplan.anlegen(settings.db_path, name="Lage", ziel="Lage", regel_text="alle 6 stunden")
    erinnerung = zeitplan.anlegen(settings.db_path, name="Wasser", ziel="Wasser",
                                  regel_text="alle 1 stunde", art="erinnerung")
    jetzt = datetime.now(UTC)
    for i in range(3):
        zeitplan.verbuche_erinnerung(settings.db_path, erinnerung, ausloeser="zeitplan",
                                     jetzt=jetzt - timedelta(hours=i))
    from core.contracts import Task, TaskBudget
    t = Task(goal="x", budget=TaskBudget()); t.spent_tokens = 700
    db.save_task(settings.db_path, t)
    zeitplan.verbuche_start(settings.db_path, auftrag, t.id, ausloeser="zeitplan", jetzt=jetzt)
    # Eine zu alte Erinnerung zaehlt nicht mehr.
    zeitplan.verbuche_erinnerung(settings.db_path, erinnerung, ausloeser="zeitplan",
                                 jetzt=jetzt - timedelta(hours=25))
    v = zeitplan.verbrauch_24h(settings.db_path, jetzt)
    assert v == zeitplan.Verbrauch(laeufe=1, token=700, erinnerungen=3)
    assert v.laeufe == 1 and v.erinnerungen == 3


def test_24_erinnerungen_halten_keinen_auftrag_auf_und_umgekehrt(client, settings):
    """Der Kern von E9: 'alle 1 stunden' als Erinnerung buchte 24 von 24
    Laeufen, die Morgenlage wurde still uebersprungen."""
    stuendlich = zeitplan.anlegen(settings.db_path, name="Wasser", ziel="Wasser trinken",
                                  regel_text="alle 1 stunde", art="erinnerung")
    for i in range(settings.zeitplan_max_erinnerungen_24h):
        zeitplan.verbuche_erinnerung(settings.db_path, stuendlich, ausloeser="zeitplan",
                                     jetzt=datetime.now(UTC) - timedelta(minutes=i))
    assert zeitplan.verbrauch_24h(settings.db_path).erinnerungen == 24
    morgenlage = zeitplan.anlegen(settings.db_path, name="Morgenlage", ziel="Lage",
                                  regel_text="taeglich 07:00")
    assert hindernis(client.app, morgenlage) is None                 # der Auftrag darf

    # Der Erinnerungs-Topf ist voll: die Erinnerung wird uebersprungen, eine
    # einmalige dabei nicht verbraucht.
    spaeter = datetime.now().astimezone() + timedelta(hours=1)
    einmal = zeitplan.anlegen(settings.db_path, name="Zahnarzt", ziel="Zahnarzt anrufen",
                              regel_text=f"einmal {spaeter:%Y-%m-%d %H:%M}", art="erinnerung")
    _faellig_seit(settings.db_path, einmal["id"], 10)
    [(pid, was)] = client.portal.call(pruefe_einmal, client.app)
    assert pid == einmal["id"] and was.startswith("uebersprungen: Erinnerungs-Deckel")
    danach = zeitplan.hole(settings.db_path, einmal["id"])
    assert danach["aktiv"] == 1 and danach["naechster_lauf"] is not None
    assert client.get("/api/messages", headers=TOKEN).json() == []
    antwort = client.post(f"/api/zeitplaene/{einmal['id']}/jetzt", headers=TOKEN)
    assert antwort.status_code == 409 and "Erinnerungs-Deckel" in antwort.json()["detail"]
    # Die Uebersicht zeigt beide Toepfe getrennt.
    d = client.get("/api/zeitplaene", headers=TOKEN).json()
    assert d["verbrauch"]["erinnerungen"] == 24 and d["verbrauch"]["laeufe"] == 0
    assert d["verbrauch"]["max_erinnerungen"] == settings.zeitplan_max_erinnerungen_24h
    assert d["erinnerungs_deckel"] and "Erinnerungs-Deckel" in d["erinnerungs_deckel"]
    assert d["deckel"] is None and d["gesperrt"] is None
    # Der Auftrag laeuft trotzdem - von Hand ...
    assert client.post(f"/api/zeitplaene/{morgenlage['id']}/jetzt", headers=TOKEN).status_code == 202
    assert _warte_bis(lambda: not client.app.state.zeitplan_tasks)

    # ... und umgekehrt: ein voller Auftrags-Topf verschluckt keine Erinnerung.
    settings.zeitplan_max_laeufe_24h = 0
    settings.zeitplan_max_token_24h = 0
    settings.zeitplan_max_erinnerungen_24h = 25
    _faellig_seit(settings.db_path, einmal["id"], 10)
    _faellig_seit(settings.db_path, morgenlage["id"], 10)
    ergebnis = dict(client.portal.call(pruefe_einmal, client.app))
    assert ergebnis[einmal["id"]] == "erinnert"
    assert ergebnis[morgenlage["id"]].startswith("uebersprungen: Tagesdeckel")
    # Davor stehen Frage und Antwort des Handlaufs; zuletzt die Erinnerung.
    letzte = client.get("/api/messages", headers=TOKEN).json()[-1]
    assert letzte["content"] == "Erinnerung: Zahnarzt anrufen"
    assert letzte["herkunft"]["art"] == "erinnerung"


# --- Regel 1: unbeaufsichtigt heisst lesen -----------------------------------


class _ZeitplanLauf(FakeLLMProvider):
    """Planer -> ein Schritt; im Schritt ruft das Modell recall (READ) und
    remember (LOCAL); Abschluss. Merkt sich, welche Werkzeuge angeboten
    wurden."""

    def __init__(self) -> None:
        super().__init__()
        self.werkzeugzug = False
        self.angeboten: list[str] | None = None

    async def complete(self, messages, *, system, tools=None):  # noqa: ANN001, ANN201
        if system.startswith(PLANNER_MARKER):
            self._replies = ['{"steps":[{"description":"Merk dir, dass Noah Kaffee mag."}]}']
        elif system.startswith(ABSCHLUSS_PROMPT):
            self._replies = ["Fertig."]
        elif not self.werkzeugzug:
            self.werkzeugzug = True
            self.angeboten = [t["name"] for t in (tools or [])]
            self._replies = [FakeTurn(tool_uses=(
                ToolUse("t1", "recall", {"query": "Kaffee"}),
                ToolUse("t2", "remember", {"text": "Noah mag Kaffee"}),
            ))]
        else:
            self._replies = ["Erledigt."]
        return await super().complete(messages, system=system, tools=tools)


def test_regel_1_ein_zeitplan_lauf_darf_sich_nichts_merken(settings):
    """Der Nachweis aus dem Befund als Regression: ein Zeitplan-Lauf ruft
    remember - abgewiesen (tool_calls ok=0), keine Fakten. recall (READ)
    geht weiter durch. Mutation: Deckel zurueck auf LOCAL -> rot."""
    settings.max_permission = Permission.SENSITIVE.value
    with TestClient(create_app(settings)) as c:
        fake = _ZeitplanLauf()
        c.app.state.provider = fake
        plan = zeitplan.anlegen(settings.db_path, name="Lage", regel_text="taeglich 07:00",
                                ziel="Merk dir, dass Noah Kaffee mag. Ruf remember auf.")
        antwort = c.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
        assert antwort.status_code == 202, antwort.text
        tid = antwort.json()["task_id"]
        assert _warte_bis(lambda: c.app.state.tasks.get(tid) is None)
        assert _warte_bis(lambda: (db.get_task_row(settings.db_path, tid) or {}).get("status") == "done")
        aufrufe = {a["name"]: a for m in c.get("/api/messages", headers=TOKEN).json()
                   for a in m["tool_calls"]}
        assert aufrufe["recall"]["ok"] is True
        assert aufrufe["remember"]["ok"] is False
        assert "READ" in aufrufe["remember"]["display"]
        assert sum(1 for a in aufrufe.values() if a["ok"]) == 1
        assert c.get("/api/memory", headers=TOKEN).json() == []            # keine Fakten
        # Angeboten wurde nur, was lesen darf.
        assert fake.angeboten is not None
        assert {"recall", "wetter", "kalender", "clock"} <= set(fake.angeboten)
        assert not {"remember", "erinnerung_anlegen", "send_email"} & set(fake.angeboten)
        assert c.get("/api/zeitplaene", headers=TOKEN).json()["obergrenze"] == "READ"
    assert zeitplan.PERMISSION_DECKEL is Permission.READ


def test_die_vorlage_morgenlage_braucht_nur_read(settings):
    from core import agents
    settings.jarvis_ort = "Berlin"
    settings.kalender_quelle = "/tmp/k.ics"
    [v] = vorlagen(settings)
    for name in ("wetter", "kalender", "recall"):
        assert f"Werkzeug {name}" in v["ziel"]
        assert registry.get(name).permission <= Permission.READ, name
    alle = agents.baue_agenten(FakeLLMProvider(), max_permission=zeitplan.PERMISSION_DECKEL)
    namen = {s["name"] for s in registry.schemas_for(alle["jarvis"].tools, zeitplan.PERMISSION_DECKEL)}
    assert {"wetter", "kalender", "recall", "clock"} <= namen
    assert not namen & {"remember", "erinnerung_anlegen", "send_email"}
    # Und die Vorlage laeuft unter dem Deckel durch.
    with TestClient(create_app(settings)) as c:
        plan = c.post("/api/zeitplaene", headers=TOKEN, json={
            "name": v["name"], "regel": v["regel"], "ziel": v["ziel"]}).json()
        antwort = c.post(f"/api/zeitplaene/{plan['id']}/jetzt", headers=TOKEN)
        assert antwort.status_code == 202, antwort.text
        tid = antwort.json()["task_id"]
        assert _warte_bis(lambda: (db.get_task_row(settings.db_path, tid) or {}).get("status") == "done")
        assert _warte_bis(lambda: zeitplan.hole(settings.db_path, plan["id"])["letzter_status"] == "done")


def test_erinnerung_anlegen_aus_dem_chat_bleibt_erlaubt(settings):
    """Der Chat-Pfad ist LOCAL, der Nutzer liest mit: 'taeglich 08:00' und
    'in 20 minuten' gehen - und das Modell rechnet dafuer nichts um."""
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            FakeTurn(tool_uses=(ToolUse("t1", "erinnerung_anlegen",
                                        {"text": "Wasser trinken", "wann": "taeglich 08:00"}),)),
            FakeTurn(tool_uses=(ToolUse("t2", "erinnerung_anlegen",
                                        {"text": "Zahnarzt anrufen", "wann": "in 20 minuten"}),)),
            "Angelegt.",
        ])
        antwort = c.post("/api/chat", json={"message": "Erinnere mich."}, headers=TOKEN)
        assert antwort.status_code == 200, antwort.text
        aufrufe = antwort.json()["tool_calls"]
        assert [a["name"] for a in aufrufe] == ["erinnerung_anlegen", "erinnerung_anlegen"]
        assert [a["ok"] for a in aufrufe] == [True, True], aufrufe
        assert "einmalig" in aufrufe[1]["display"]
        plaene = {p["ziel"]: p for p in zeitplan.alle(settings.db_path)}
        assert plaene["Wasser trinken"]["regel"] == "taeglich 08:00"
        assert plaene["Wasser trinken"]["art"] == "erinnerung"
        assert plaene["Zahnarzt anrufen"]["regel"].startswith("einmal ")
        termin = zeitplan._aus_z(plaene["Zahnarzt anrufen"]["naechster_lauf"])
        assert timedelta(minutes=20) <= termin - datetime.now(UTC) <= timedelta(minutes=21)


def test_das_werkzeug_nennt_die_neuen_formen_und_verlangt_kein_rechnen():
    w = registry.get("erinnerung_anlegen")
    wann = w.parameters["properties"]["wann"]["description"]
    assert "in N minuten" in wann and "in N stunden" in wann
    assert "10080" in wann and "168" in wann
    assert "Rechne die Uhrzeit vorher" not in w.description
    assert "nicht umrechnen" in w.description


# --- Die Oberflaeche, ohne Browser ------------------------------------------


def test_ui_umschalter_und_meldeschalter_stehen_im_block(client):
    html = client.get("/").text
    start = html.index("function zeitplanBlock")
    block = html[start:html.index("COMMAND CENTER (FIX-06", start)]
    assert "Erinnerung (nur Nachricht, 0 Token)" in block and "Auftrag (Modell)" in block
    assert "art: artGewaehlt()" in block                      # das Feld geht mit
    assert "in 20 minuten" in block and "in 2 stunden" in block   # der Platzhalter nennt die Formen
    assert "erinnerungErlaubnisHolen(" in block
    assert "höchstens lesen" in block and "höchstens lokal" not in html
    zustellung = html[html.index("Erinnerungen fuer Menschen (FIX-11)"):html.index("function zustellungStarten")]
    assert "Notification.requestPermission()" in zustellung
    assert "Notification.permission === 'granted'" in zustellung
    assert "lieseVor(" in zustellung and "createOscillator" in zustellung
    assert "localStorage" in zustellung and "try {" in zustellung
    assert "herkunft.art === 'erinnerung'" in html[html.index("function zustellungStarten"):]
    for stueck in (block, zustellung):
        assert "innerHTML" not in stueck
    # Kein zweiter Strom: nur stromAbonnieren oeffnet den rohen Strom, die
    # Zustellung haengt am geteilten (der CC-Test zaehlt genau eine Verbindung).
    assert html.count("ereignisStrom(function") == 1
    assert "stromAbonnieren(function" in html[html.index("function zustellungStarten"):html.index("function loadHealth")]


# --- Die Oberflaeche, mit Browser -------------------------------------------

# Zaehlende Stuebe fuer die drei Reaktionen. `Notification.permission` kommt
# weiter vom echten Browser - so misst derselbe Stub mit und ohne Erlaubnis.
STUBS_JS = """
window.__stubs = { ton: [], meldung: [], vorlesen: [], erlaubnis: 0 };
(function () {
  var echt = window.Notification;
  function StubNotification(titel, opts) {
    window.__stubs.meldung.push({ titel: titel, body: (opts && opts.body) || '' });
  }
  Object.defineProperty(StubNotification, 'permission', {
    get: function () { return echt ? echt.permission : 'denied'; }
  });
  StubNotification.requestPermission = function () {
    window.__stubs.erlaubnis += 1;
    return Promise.resolve(echt ? echt.permission : 'denied');
  };
  window.Notification = StubNotification;

  function StubAudio() { this.currentTime = 0; this.destination = {}; }
  StubAudio.prototype.createOscillator = function () {
    return { type: '', frequency: { value: 0 }, onended: null,
             connect: function () {},
             start: function () { window.__stubs.ton.push(this.frequency.value); },
             stop: function () {} };
  };
  StubAudio.prototype.createGain = function () { return { gain: { value: 0 }, connect: function () {} }; };
  StubAudio.prototype.resume = function () { return Promise.resolve(); };
  StubAudio.prototype.close = function () { return Promise.resolve(); };
  window.AudioContext = StubAudio;
  window.webkitAudioContext = StubAudio;

  if (!window.SpeechSynthesisUtterance) {
    window.SpeechSynthesisUtterance = function (t) { this.text = t; };
  }
  if (!window.speechSynthesis) {
    Object.defineProperty(window, 'speechSynthesis', { value: {}, configurable: true });
  }
  window.speechSynthesis.speak = function (u) { window.__stubs.vorlesen.push(u.text); };
})();
"""


def _browser(pw, erlaubnis: bool):
    from tests.conftest import CHROMIUM
    br = pw.chromium.launch(executable_path=CHROMIUM,
                            args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    kontext = br.new_context(viewport={"width": 1440, "height": 900}, reduced_motion="reduce")
    if erlaubnis:
        kontext.grant_permissions(["notifications"])
    seite = kontext.new_page()
    seite.add_init_script(STUBS_JS)
    return br, seite


def _oeffne(seite, basis, gerufen, fehler):
    seite.on("request", lambda r: gerufen.append(r.url))
    seite.on("pageerror", lambda e: fehler.append(str(e)))
    seite.on("console", lambda m: fehler.append(m.text) if m.type == "error" else None)
    seite.goto(basis + "/", wait_until="domcontentloaded")
    seite.wait_for_selector("#view-cc .cc", timeout=20000)
    # Der Strom steht, sobald sein `hello` im Command Center steht.
    seite.wait_for_function(
        "() => document.querySelectorAll('#view-cc .cc-strom div').length >= 1", timeout=20000)


def _erinnerung_zustellen(basis: str, text: str) -> None:
    """Per API anlegen und zustellen - derselbe Weg wie die Runde
    (`erinnere`), nur ohne auf den Termin zu warten."""
    r = httpx.post(f"{basis}/api/zeitplaene", headers=TOKEN, timeout=10, json={
        "name": text[:40], "ziel": text, "regel": "in 5 minuten", "art": "erinnerung"})
    assert r.status_code == 201, r.text
    j = httpx.post(f"{basis}/api/zeitplaene/{r.json()['id']}/jetzt", headers=TOKEN, timeout=10)
    assert j.status_code == 202 and j.json()["status"] == "erinnert", j.text


def _stuebe(seite) -> dict:
    return seite.evaluate("() => window.__stubs")


def test_ui_der_umschalter_folgt_der_regel(live_server):
    playwright = pytest.importorskip("playwright.sync_api")
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, erlaubnis=False)
        gerufen: list[str] = []
        fehler: list[str] = []
        try:
            _oeffne(seite, live_server, gerufen, fehler)
            seite.click("#tab-tasks")
            seite.wait_for_selector(".zeitplan-form")
            assert seite.is_visible(".zeitplan-art input[value=erinnerung]")
            assert seite.is_visible(".zeitplan-art input[value=auftrag]")
            assert seite.is_checked(".zeitplan-art input[value=auftrag]")       # leer: Auftrag
            for regel, erwartet in (("in 20 minuten", "erinnerung"), ("taeglich 07:00", "auftrag"),
                                    ("einmal 2030-01-01 08:00", "erinnerung"),
                                    ("2030-01-01 08:00", "erinnerung"), ("alle 6 stunden", "auftrag")):
                seite.fill(".zeitplan-form input[name=regel]", regel)
                assert seite.is_checked(f".zeitplan-art input[value={erwartet}]"), regel
            # Von Hand umgestellt bleibt umgestellt.
            seite.check(".zeitplan-art input[value=erinnerung]")
            seite.fill(".zeitplan-form input[name=regel]", "taeglich 09:00")
            assert seite.is_checked(".zeitplan-art input[value=erinnerung]")
            assert "erinnern" in seite.get_attribute(".zeitplan-form input[name=ziel]", "placeholder")
            # Anlegen: art geht mit, die Karte zeigt die Pille.
            seite.fill(".zeitplan-form input[name=name]", "Wasser")
            seite.fill(".zeitplan-form input[name=regel]", "in 20 minuten")
            seite.fill(".zeitplan-form input[name=ziel]", "Wasser trinken")
            seite.click(".zeitplan-form button[type=submit]")
            seite.wait_for_selector(".zeitplan")
            assert "Erinnerung" in seite.locator(".zeitplan-meldung").text_content()
            pillen = seite.locator(".zeitplan .zustand").all_text_contents()
            assert "Erinnerung" in pillen and "einmalig" in pillen, pillen
            assert seite.locator(".zeitplan-regel").first.text_content().startswith("einmal ")
            [p] = httpx.get(f"{live_server}/api/zeitplaene", headers=TOKEN, timeout=10).json()["zeitplaene"]
            assert p["art"] == "erinnerung"
            # Die drei Schalter und der Knopf fuer die Erlaubnis.
            assert seite.locator(".zeitplan-melden input[type=checkbox]").count() == 3
            knopf = seite.locator("[data-aktion=erinnerungen-melden]")
            assert knopf.text_content() == "Erinnerungen melden" and knopf.is_enabled()
            knopf.click()
            seite.wait_for_timeout(200)
            assert _stuebe(seite)["erlaubnis"] == 1                    # nur aus der Geste heraus
            # Ein Schalter aus - und nach dem Neuladen noch aus (localStorage).
            seite.uncheck(".zeitplan-melden input[name=erinnerung-ton]")
            seite.reload(wait_until="domcontentloaded")
            seite.wait_for_selector("#view-cc .cc", timeout=20000)
            seite.click("#tab-tasks")
            seite.wait_for_selector(".zeitplan-melden")
            assert not seite.is_checked(".zeitplan-melden input[name=erinnerung-ton]")
            assert seite.is_checked(".zeitplan-melden input[name=erinnerung-vorlesen]")
            assert fehler == [], fehler
        finally:
            br.close()


def test_ui_eine_erinnerung_macht_ton_meldung_und_vorlesen(live_server):
    playwright = pytest.importorskip("playwright.sync_api")
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, erlaubnis=True)
        gerufen: list[str] = []
        fehler: list[str] = []
        try:
            _oeffne(seite, live_server, gerufen, fehler)
            assert seite.evaluate("() => Notification.permission") == "granted"
            _erinnerung_zustellen(live_server, "Zahnarzt anrufen")
            seite.wait_for_function(
                "() => window.__stubs.ton.length && window.__stubs.meldung.length "
                "&& window.__stubs.vorlesen.length", timeout=15000)
            seite.wait_for_timeout(300)                                # nichts kommt doppelt
            st = _stuebe(seite)
            assert len(st["ton"]) == 1 and len(st["meldung"]) == 1 and len(st["vorlesen"]) == 1, st
            [meldung] = st["meldung"]
            assert meldung == {"titel": "Mehmet", "body": "Zahnarzt anrufen"}    # nur der Text
            assert "Zahnarzt anrufen" in st["vorlesen"][0]
            [p] = httpx.get(f"{live_server}/api/zeitplaene", headers=TOKEN, timeout=10).json()["zeitplaene"]
            assert p["id"] not in meldung["body"] and p["id"] not in st["vorlesen"][0]
            # Der Knopf weiss, dass die Erlaubnis da ist.
            seite.click("#tab-tasks")
            seite.wait_for_selector("[data-aktion=erinnerungen-melden]")
            knopf = seite.locator("[data-aktion=erinnerungen-melden]")
            assert knopf.text_content() == "Erinnerungen werden gemeldet" and knopf.is_disabled()
            # Genau EIN Strom je Seite - auch mit der Zustellung.
            assert len([u for u in gerufen if "/api/events" in u]) == 1
            assert fehler == [], fehler
        finally:
            br.close()


def test_ui_ohne_erlaubnis_und_mit_schaltern_aus_bleibt_es_still(live_server):
    playwright = pytest.importorskip("playwright.sync_api")
    with playwright.sync_playwright() as pw:
        br, seite = _browser(pw, erlaubnis=False)
        gerufen: list[str] = []
        fehler: list[str] = []
        try:
            _oeffne(seite, live_server, gerufen, fehler)
            assert seite.evaluate("() => Notification.permission") == "default"
            _erinnerung_zustellen(live_server, "Wasser trinken")
            seite.wait_for_function("() => window.__stubs.ton.length && window.__stubs.vorlesen.length",
                                    timeout=15000)
            seite.wait_for_timeout(300)
            st = _stuebe(seite)
            assert st["meldung"] == []                                  # ohne Erlaubnis: keine
            assert len(st["ton"]) == 1 and len(st["vorlesen"]) == 1
            # Alle drei Schalter aus: die naechste Erinnerung macht nichts.
            seite.click("#tab-tasks")
            seite.wait_for_selector(".zeitplan-melden")
            for name in ("ton", "melden", "vorlesen"):
                seite.uncheck(f".zeitplan-melden input[name=erinnerung-{name}]")
            _erinnerung_zustellen(live_server, "Fenster schliessen")
            seite.wait_for_function(
                "() => [...document.querySelectorAll('.zeitplan')].length >= 2", timeout=15000)
            seite.wait_for_timeout(500)
            st = _stuebe(seite)
            assert len(st["ton"]) == 1 and len(st["vorlesen"]) == 1 and st["meldung"] == [], st
            assert len([u for u in gerufen if "/api/events" in u]) == 1
            assert fehler == [], fehler
        finally:
            br.close()
