"""FIX-11 Punkt 4: Wenn ein Auftrag stirbt.

Vier Befunde, vier Schutzmassnahmen - jede mit einem Test, der kippt, wenn
man sie entfernt:

a) Der rohe Ausnahmetext ging als Antwort in den Chat. Ein `OSError` haengt
   den vollen Pfad an, httpx die volle URL - und das landete in
   `tasks.result`, im Verlauf, im `task_log` und beim naechsten Zug als
   Verlauf beim Modellanbieter.
b) Im `finally` standen der letzte `save_task` und das `publish`
   ungeschuetzt VOR `registry.remove`. Scheiterte der Schreibvorgang, blieb
   der Task fuer immer in der Registry: 50.000 Token reserviert, jeder
   Zeitplan 409 - bis zum Neustart.
c) Ein GETIPPTER Auftrag, der beim Absturz lief, blieb nach dem Neustart
   fuer immer 'running' - `core/zeitplan.abgleich` joint nur ueber
   `zeitplaene`.
d) Eine Stoerung (kein Netz, 5xx, Ratenlimit) zaehlte wie ein Fehlschlag:
   dreimal kein Netz und die Morgenlage pausierte.

Alles gegen FakeLLMProvider - kein Modellaufruf, kein Netz.
"""

from __future__ import annotations

import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.tasks import STOERUNG_GRUND
from core import db, zeitplan
from core.contracts import Step, StepStatus, Task, TaskBudget
from core.db import session
from core.fehlertexte import ist_verdaechtig
from core.llm import FakeLLMProvider, LLMError

TOKEN = {"X-Jarvis-Token": "test-token-123"}
WURZEL = Path(__file__).resolve().parent.parent

# Ein Pfad, wie ihn ein OSError anhaengt - und ein Wort, das nur in ihm
# vorkommt. Beides darf nirgends auftauchen, wo ein Modell mitliest.
GEHEIM_PFAD = "C:\\Users\\Noah\\Dokumente\\kontoauszug.txt"
GEHEIMNISSE = [GEHEIM_PFAD, "kontoauszug"]


@pytest.fixture(autouse=True)
def ohne_schleife(settings):
    """Die Tests hier loesen selbst aus. Liefe die Schleife nebenher, wuerde
    sie denselben Plan starten und dem Test den Lauf wegnehmen."""
    settings.zeitplan_takt_s = 0


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


class KaputterFake(FakeLLMProvider):
    """Ein Anbieter, der beim ersten Zug aussteigt - ohne Netz, ohne Kosten."""

    def __init__(self, exc: BaseException) -> None:
        super().__init__(replies=["ungenutzt"])
        self._exc = exc

    async def complete(self, messages, *, system, tools=None):  # noqa: ANN001
        raise self._exc


def _warte_auf_ende(client, task_id: str, sekunden: float = 10.0) -> dict:
    frist = time.monotonic() + sekunden
    while time.monotonic() < frist:
        d = client.get(f"/api/tasks/{task_id}", headers=TOKEN).json()
        if d["status"] in ("done", "failed", "aborted_budget", "cancelled"):
            return d
        time.sleep(0.02)
    raise AssertionError(f"Task {task_id} wurde nicht fertig")


def _warte_bis(bedingung, sekunden: float = 10.0) -> bool:
    frist = time.monotonic() + sekunden
    while time.monotonic() < frist:
        if bedingung():
            return True
        time.sleep(0.02)
    return bedingung()


def _plan(db_path, name="Morgenlage", regel="taeglich 07:00"):
    return zeitplan.anlegen(db_path, name=name, ziel="Erstelle meine Morgenlage.",
                            regel_text=regel)


# --- a) Der rohe Ausnahmetext ---------------------------------------------


def test_ein_pfad_aus_einer_ausnahme_kommt_nirgends_an(client, settings):
    """Der Nachweis aus dem Befund als Regression: der Pfad darf weder im
    Verlauf noch am Task noch im episodischen Gedaechtnis stehen."""
    client.app.state.provider = KaputterFake(
        OSError(f"[Errno 13] Permission denied: '{GEHEIM_PFAD}'"))
    tid = client.post("/api/tasks", json={"goal": "Lies meine Datei"},
                      headers=TOKEN).json()["task_id"]
    fertig = _warte_auf_ende(client, tid)

    assert fertig["status"] == "failed"
    verlauf = client.get("/api/messages", headers=TOKEN).text
    task_json = client.get(f"/api/tasks/{tid}", headers=TOKEN).text
    log = client.get("/api/task-log", headers=TOKEN).text
    for text in (verlauf, task_json, log):
        assert ist_verdaechtig(text, GEHEIMNISSE) == []


def test_der_abbruch_bleibt_trotzdem_erklaerbar(client):
    """Ohne Geheimnis heisst nicht ohne Information: der Typ steht drin und
    der Hinweis, wo der Rest zu finden ist."""
    client.app.state.provider = KaputterFake(OSError(f"nicht lesbar: {GEHEIM_PFAD}"))
    tid = client.post("/api/tasks", json={"goal": "Lies meine Datei"},
                      headers=TOKEN).json()["task_id"]
    fertig = _warte_auf_ende(client, tid)
    assert "OSError" in fertig["result"]
    assert "Serverlog" in fertig["result"]


def test_der_rohe_ausnahmetext_steht_nicht_mehr_im_code():
    """Waechter: wer die Formatierung zurueckbaut, sieht es hier."""
    quelle = (WURZEL / "api" / "tasks.py").read_text(encoding="utf-8")
    assert 'task.result = f"{type(exc).__name__}: {exc}"' not in quelle
    assert "ohne_geheimnis(exc, \"Der Auftrag ist abgebrochen\")" in quelle


# --- b) Der Nachlauf raeumt auf, auch wenn er scheitert --------------------


@pytest.fixture
def schreiben_scheitert_am_ende(monkeypatch):
    """Der letzte `save_task` (der mit dem Endzustand) wirft - so wie eine
    volle Platte oder eine gesperrte Datenbank es taeten."""
    echt = db.save_task

    def wackelig(pfad, task, **kw):  # noqa: ANN001
        if task.status in ("done", "failed", "aborted_budget", "cancelled"):
            raise RuntimeError("database or disk is full")
        return echt(pfad, task, **kw)

    monkeypatch.setattr("api.tasks.db.save_task", wackelig)


def test_registry_und_zeitplan_bleiben_frei(settings, schreiben_scheitert_am_ende):
    """Befund b: vorher blieb der Task in der Registry, `laufende(app)`
    reservierte sein Budget, und der naechste Zeitplan bekam 409."""
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"A"}]}', "A erledigt.", "Fertig."])
        a = _plan(settings.db_path, name="A", regel="taeglich 07:00")
        b = _plan(settings.db_path, name="B", regel="taeglich 08:00")

        tid = c.post(f"/api/zeitplaene/{a['id']}/jetzt",
                     headers=TOKEN).json()["task_id"]
        assert _warte_bis(lambda: c.app.state.tasks.get(tid) is None)
        assert c.app.state.tasks.get(tid) is None
        from api.zeitplan import laufende

        assert laufende(c.app) == {}
        zweite = c.post(f"/api/zeitplaene/{b['id']}/jetzt", headers=TOKEN)
        assert zweite.status_code == 202


def test_die_antwort_steht_trotzdem_im_verlauf(settings, schreiben_scheitert_am_ende):
    """Der Verlauf wird VOR dem Endzustand geschrieben - genau deshalb
    ueberlebt die Antwort einen gescheiterten letzten Schreibvorgang."""
    with TestClient(create_app(settings)) as c:
        c.app.state.provider = FakeLLMProvider(replies=[
            '{"steps":[{"description":"A"}]}', "A erledigt.", "Die Antwort."])
        tid = c.post("/api/tasks", json={"goal": "Die Frage"},
                     headers=TOKEN).json()["task_id"]
        assert _warte_bis(lambda: c.app.state.tasks.get(tid) is None)
        rollen = [(m["role"], m["content"])
                  for m in c.get("/api/messages", headers=TOKEN).json()]
    assert rollen == [("user", "Die Frage"), ("assistant", "Die Antwort.")]


# --- c) Was nach einem Neustart tot ist -----------------------------------


def _toter_task(db_path, *, goal="Getippt", status="running",
                herkunft=None, schritte=()) -> str:
    t = Task(goal=goal, budget=TaskBudget())
    t.status = status
    db.save_task(db_path, t)
    for i, zustand in enumerate(schritte):
        s = Step(id=f"{t.id}-{i}", description=f"Schritt {i}", status=zustand)
        db.save_step(db_path, t.id, i, s)
    db.add_message(db_path, "user", goal,
                   dict(herkunft, task_id=t.id) if herkunft else None)
    return t.id


def test_der_start_beendet_einen_getippten_task_und_sagt_es(settings):
    """Befund c: vorher stand er fuer immer auf 'running', und im Chat
    blieb eine Frage ohne Antwort."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    tid = _toter_task(settings.db_path,
                      schritte=(StepStatus.DONE, StepStatus.RUNNING,
                                StepStatus.NEEDS_CONFIRMATION))

    with TestClient(create_app(settings)) as c:
        row = c.get(f"/api/tasks/{tid}", headers=TOKEN).json()
        verlauf = c.get("/api/messages", headers=TOKEN).json()

    assert row["status"] == "failed"
    assert row["finished_at"]
    assert "Neustart" in row["abort_reason"]
    assert [s["status"] for s in row["steps"]] == ["done", "skipped", "skipped"]
    assert [m["role"] for m in verlauf] == ["user", "assistant"]
    assert "neu gestartet" in verlauf[-1]["content"]
    assert verlauf[-1]["herkunft"] is None


def test_die_absage_traegt_die_herkunft_ihrer_frage(settings):
    """Ein Zeitplan-Auftrag steht mit Herkunft im Verlauf - die Absage
    gehoert zur selben Zeile, sonst sieht sie aus wie etwas, das der Nutzer
    ausgeloest hat."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    tid = _toter_task(settings.db_path, goal="Morgenlage",
                      herkunft={"art": "zeitplan", "zeitplan_id": "p1",
                                "zeitplan_name": "Morgenlage"})
    assert db.tote_tasks_beenden(settings.db_path, set()) == [tid]
    letzte = db.list_messages(settings.db_path)[-1]
    assert letzte.role == "assistant"
    assert letzte.herkunft["art"] == "zeitplan"
    assert letzte.herkunft["zeitplan_name"] == "Morgenlage"
    assert letzte.herkunft["task_id"] == tid


def test_ein_laufender_task_wird_nicht_fuer_tot_erklaert(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    tid = _toter_task(settings.db_path)
    assert db.tote_tasks_beenden(settings.db_path, {tid}) == []
    assert db.get_task_row(settings.db_path, tid)["status"] == "running"
    assert len(db.list_messages(settings.db_path)) == 1


def test_zweimal_aufraeumen_schreibt_nicht_zweimal(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    _toter_task(settings.db_path)
    assert len(db.tote_tasks_beenden(settings.db_path, set())) == 1
    assert db.tote_tasks_beenden(settings.db_path, set()) == []
    assert len(db.list_messages(settings.db_path)) == 2


def test_alte_leichen_fluten_den_chat_nicht(settings):
    """Der Fund des Richters: eine alte Datenbank mit vielen Leichen ergab
    auf einen Schlag viele 'Abgebrochen'-Zeilen im Chat. Alt heisst: keine
    Zeile (die Auftragsliste zeigt es), viele frische heissen: eine
    Sammelzeile mit der Zahl."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    alte = [_toter_task(settings.db_path, goal=f"Alt {i}") for i in range(5)]
    with session(settings.db_path) as conn:
        conn.execute(
            "UPDATE tasks SET created_at = '2026-01-01T00:00:00Z' "
            f"WHERE id IN ({','.join('?' * len(alte))})", alte)
    vorher = len(db.list_messages(settings.db_path))

    assert len(db.tote_tasks_beenden(settings.db_path, set())) == 5
    assert len(db.list_messages(settings.db_path)) == vorher   # keine einzige Zeile

    frisch = [_toter_task(settings.db_path, goal=f"Neu {i}") for i in range(5)]
    assert len(db.tote_tasks_beenden(settings.db_path, set())) == len(frisch)
    neu = db.list_messages(settings.db_path)[vorher + len(frisch):]
    assert len(neu) == 1
    assert "5 Auftraege" in neu[0].content


def test_drei_frische_bekommen_jede_ihre_eigene_zeile(settings):
    with session(settings.db_path) as conn:
        db.init_db(conn)
    for i in range(db.NEUSTART_MAX_EINZELN):
        _toter_task(settings.db_path, goal=f"Auftrag {i}")
    db.tote_tasks_beenden(settings.db_path, set())
    absagen = [m for m in db.list_messages(settings.db_path)
               if m.role == "assistant"]
    assert len(absagen) == db.NEUSTART_MAX_EINZELN
    assert all(m.content == db.NEUSTART_TEXT for m in absagen)


def test_der_abgleich_nutzt_dieselbe_funktion_und_nicht_seinen_eigenen_join():
    """Waechter: das Beenden steht an EINER Stelle (core/db.py). Wer in
    core/zeitplan.py wieder selbst an `tasks` schreibt, sieht es hier."""
    quelle = (WURZEL / "core" / "zeitplan.py").read_text(encoding="utf-8")
    assert "tote_tasks_beenden(" in quelle
    assert "UPDATE tasks SET" not in quelle
    start = (WURZEL / "api" / "app.py").read_text(encoding="utf-8")
    assert "tote_tasks_beenden" in start


def test_der_abgleich_fasst_getippte_auftraege_nicht_an(settings):
    """Die Zeitplan-Schleife kennt nur ihre eigenen laufenden Tasks. Wuerde
    `abgleich` alles beenden, was nicht in dieser Menge steht, waere jeder
    getippte Auftrag nach zehn Sekunden 'failed' - mitten im Lauf."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    getippt = _toter_task(settings.db_path, goal="Laeuft gerade")
    plan = _plan(settings.db_path)
    tot = Task(goal="Zeitplan", budget=TaskBudget())
    db.save_task(settings.db_path, tot)
    zeitplan.verbuche_start(settings.db_path, plan, tot.id, ausloeser="zeitplan")

    assert zeitplan.abgleich(settings.db_path, set()) == [plan["id"]]
    assert db.get_task_row(settings.db_path, tot.id)["status"] == "failed"
    assert db.get_task_row(settings.db_path, getippt)["status"] == "running"
    # Und im laufenden Betrieb keine falsche Zeile im Chat.
    assert [m.role for m in db.list_messages(settings.db_path)] == ["user"]


# --- d) Stoerung ist kein Fehlschlag --------------------------------------


def _dreimal_ausloesen(client, db_path, plan_id: str) -> None:
    """Dreimal von Hand ausloesen - und jedes Mal warten, bis der Ausgang am
    PLAN steht. Auf `zeitplan_tasks == {}` zu warten reicht nicht: `am_ende`
    nimmt den Task aus der Tabelle, BEVOR es `nachtrag_ergebnis` schreibt.
    Der naechste Lauf wuerde dann `letzter_task_id` ueberschreiben, und der
    Fehlschlag ginge verloren (einmal in drei Laeufen gesehen)."""
    for _ in range(zeitplan.MAX_FEHLSCHLAEGE):
        antwort = client.post(f"/api/zeitplaene/{plan_id}/jetzt", headers=TOKEN)
        assert antwort.status_code == 202, antwort.text
        _warte_auf_ende(client, antwort.json()["task_id"])
        assert _warte_bis(lambda: zeitplan.hole(db_path, plan_id)["letzter_status"]
                          not in ("laeuft", "startet"))


def test_dreimal_kein_netz_pausiert_die_morgenlage_nicht(client, settings):
    """Befund d: `LLMError(retryable=True)` zaehlte wie ein Fehlschlag."""
    client.app.state.provider = KaputterFake(LLMError(
        "Verbindung zum Modellanbieter fehlgeschlagen: [Errno -3] Temporary "
        "failure in name resolution", kind="connection", retryable=True))
    plan = _plan(settings.db_path)

    _dreimal_ausloesen(client, settings.db_path, plan["id"])

    stand = zeitplan.hole(settings.db_path, plan["id"])
    assert stand["aktiv"] == 1
    assert stand["fehlschlaege"] == 0
    assert stand["letzter_status"].startswith("Stoerung")
    verlauf = client.get("/api/messages", headers=TOKEN).json()
    antworten = [m["content"] for m in verlauf if m["role"] == "assistant"]
    assert antworten and all("LLMError" not in a for a in antworten)
    assert "nicht erreichbar" in antworten[-1]


def test_die_stoerung_steht_am_task_als_grund(client, settings):
    client.app.state.provider = KaputterFake(LLMError(
        "Ratenlimit erreicht (429).", status=429, kind="api_error", retryable=True))
    tid = client.post("/api/tasks", json={"goal": "Ziel"},
                      headers=TOKEN).json()["task_id"]
    fertig = _warte_auf_ende(client, tid)
    assert fertig["status"] == "failed"
    assert fertig["abort_reason"] == STOERUNG_GRUND
    assert "LLMError" not in fertig["result"]


def test_ein_einrichtungsfehler_behaelt_seinen_hinweis(client):
    """Nicht jeder LLMError ist eine Stoerung: die Texte aus core/llm.py
    enthalten keinen Key und sagen, was zu tun ist. Sie bleiben."""
    client.app.state.provider = KaputterFake(LLMError(
        "Der API-Key wurde nicht akzeptiert (401). Stimmt LLM_API_KEY?",
        status=401, kind="api_error", retryable=False))
    tid = client.post("/api/tasks", json={"goal": "Ziel"},
                      headers=TOKEN).json()["task_id"]
    fertig = _warte_auf_ende(client, tid)
    assert "Stimmt LLM_API_KEY?" in fertig["result"]
    assert fertig["abort_reason"] != STOERUNG_GRUND


def test_echte_fehlschlaege_pausieren_und_sagen_es_im_verlauf(client, settings):
    """Die Bremse aus FIX-09 bleibt - und meldet sich jetzt dort, wo der
    Nutzer hinsieht."""
    client.app.state.provider = FakeLLMProvider(replies=["kein JSON"])
    plan = _plan(settings.db_path)

    _dreimal_ausloesen(client, settings.db_path, plan["id"])

    stand = zeitplan.hole(settings.db_path, plan["id"])
    assert stand["aktiv"] == 0
    assert stand["fehlschlaege"] == zeitplan.MAX_FEHLSCHLAEGE
    assert stand["letzter_status"].startswith("pausiert")
    verlauf = client.get("/api/messages", headers=TOKEN).json()
    gemeldet = [m for m in verlauf if "pausiert" in m["content"]]
    assert len(gemeldet) == 1
    assert gemeldet[0]["role"] == "assistant"
    assert gemeldet[0]["herkunft"]["art"] == "zeitplan"
    assert gemeldet[0]["herkunft"]["zeitplan_name"] == "Morgenlage"


def test_eine_stoerung_loescht_den_zaehler_nicht(settings):
    """Weder hoch noch zurueck: zwei echte Fehlschlaege, dann eine Stoerung -
    der Plan steht danach immer noch bei zwei."""
    with session(settings.db_path) as conn:
        db.init_db(conn)
    plan = _plan(settings.db_path)
    for _ in range(2):
        t = Task(goal="x", budget=TaskBudget())
        db.save_task(settings.db_path, t)
        zeitplan.verbuche_start(settings.db_path, plan, t.id, ausloeser="hand")
        zeitplan.nachtrag_ergebnis(settings.db_path, t.id, "failed")
    assert zeitplan.hole(settings.db_path, plan["id"])["fehlschlaege"] == 2

    t = Task(goal="x", budget=TaskBudget())
    db.save_task(settings.db_path, t)
    zeitplan.verbuche_start(settings.db_path, plan, t.id, ausloeser="hand")
    zeitplan.nachtrag_ergebnis(settings.db_path, t.id, "failed", stoerung=True)

    stand = zeitplan.hole(settings.db_path, plan["id"])
    assert stand["fehlschlaege"] == 2
    assert stand["aktiv"] == 1
    assert stand["letzter_status"].startswith("Stoerung")
