"""FIX-06 Abschnitt 6, Zone 7: GET /api/stats/verlauf."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from core import db

TOKEN = {"X-Jarvis-Token": "test-token-123"}


def _stunde(vor_stunden: int) -> str:
    t = datetime.now(timezone.utc) - timedelta(hours=vor_stunden)
    return t.replace(minute=0, second=0, microsecond=0).isoformat(
        timespec="seconds").replace("+00:00", "Z")


def _schreibe(pfad, wann: str, in_t: int, out_t: int, kosten: float, ok: bool = True):
    with db.session(pfad) as conn:
        conn.execute(
            "INSERT INTO llm_calls (model, prompt_hash, in_tokens, out_tokens, "
            "cost_eur, duration_ms, ok, created_at) VALUES (?,?,?,?,?,?,?,?)",
            ("fake-echo-1", "h", in_t, out_t, kosten, 10, int(ok), wann),
        )


@pytest.fixture
def klient(settings):
    app = create_app(settings)
    with TestClient(app) as c:
        yield c, settings.db_path


def test_der_endpunkt_existiert_und_will_den_token(klient):
    c, _ = klient
    assert c.get("/api/stats/verlauf").status_code == 401
    assert c.get("/api/stats/verlauf", headers=TOKEN).status_code == 200


def test_leer_heisst_lauter_nullen_und_nicht_nichts(klient):
    """Zone 7 muss ein Diagramm zeichnen koennen, auch wenn nie etwas lief.

    Eine leere Liste waere kein Diagramm; 24 ehrliche Nullen sind eins.
    """
    c, _ = klient
    d = c.get("/api/stats/verlauf?stunden=24", headers=TOKEN).json()
    assert d["fenster_h"] == 24
    assert len(d["stunden"]) == 24
    assert all(p["tokens"] == 0 and p["calls"] == 0 for p in d["stunden"])
    assert d["summe"]["tokens"] == 0


def test_aufrufe_landen_in_ihrer_stunde(klient):
    c, pfad = klient
    _schreibe(pfad, _stunde(0), 100, 50, 0.001)
    _schreibe(pfad, _stunde(0), 10, 5, 0.0005)
    _schreibe(pfad, _stunde(3), 7, 3, 0.0)
    d = c.get("/api/stats/verlauf?stunden=6", headers=TOKEN).json()
    punkte = {p["stunde"]: p for p in d["stunden"]}
    jetzt = _stunde(0)[:13]
    vor3 = _stunde(3)[:13]
    assert punkte[jetzt]["calls"] == 2
    assert punkte[jetzt]["tokens"] == 165
    assert punkte[jetzt]["in_tokens"] == 110
    assert punkte[vor3]["calls"] == 1
    assert punkte[vor3]["tokens"] == 10
    assert d["summe"]["calls"] == 3
    assert d["summe"]["tokens"] == 175


def test_die_stunden_kommen_aufsteigend(klient):
    c, pfad = klient
    _schreibe(pfad, _stunde(2), 1, 1, 0.0)
    d = c.get("/api/stats/verlauf?stunden=5", headers=TOKEN).json()
    folge = [p["stunde"] for p in d["stunden"]]
    assert folge == sorted(folge), folge
    assert folge[-1] == _stunde(0)[:13]


def test_was_aelter_ist_als_das_fenster_faellt_raus(klient):
    c, pfad = klient
    _schreibe(pfad, _stunde(50), 999, 999, 9.0)
    d = c.get("/api/stats/verlauf?stunden=6", headers=TOKEN).json()
    assert d["summe"]["tokens"] == 0, "ein Aufruf von vor 50 Stunden zaehlt im 6-Stunden-Fenster mit"


def test_fehler_werden_getrennt_gezaehlt(klient):
    c, pfad = klient
    _schreibe(pfad, _stunde(0), 5, 5, 0.0, ok=True)
    _schreibe(pfad, _stunde(0), 5, 5, 0.0, ok=False)
    d = c.get("/api/stats/verlauf?stunden=3", headers=TOKEN).json()
    jetzt = [p for p in d["stunden"] if p["stunde"] == _stunde(0)[:13]][0]
    assert jetzt["calls"] == 2 and jetzt["fehler"] == 1
    assert d["summe"]["fehler"] == 1


def test_das_fenster_hat_grenzen(klient):
    c, _ = klient
    assert len(c.get("/api/stats/verlauf?stunden=0", headers=TOKEN).json()["stunden"]) == 1
    assert len(c.get("/api/stats/verlauf?stunden=9999", headers=TOKEN).json()["stunden"]) == 168


def test_kosten_kommen_als_zahl_und_werden_nicht_geschaetzt(klient):
    """Ohne Preise in der .env schreibt core/llm.py 0.0 - das muss hier
    ankommen und nicht durch eine Schaetzung ersetzt werden."""
    c, pfad = klient
    _schreibe(pfad, _stunde(1), 1000, 1000, 0.0)
    d = c.get("/api/stats/verlauf?stunden=3", headers=TOKEN).json()
    assert d["summe"]["cost_eur"] == 0.0
    assert d["summe"]["tokens"] == 2000
