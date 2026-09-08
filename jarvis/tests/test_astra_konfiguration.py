"""Gemeinsame Konfiguration ohne Zugangsdaten oder externe Aufrufe."""

import json
import os
import stat

import pytest
from fastapi.testclient import TestClient

from api.app import create_app
from api.security import ensure_token
from core.config import Settings
from core.konfig_pruefung import integrationen
from scripts.konfiguration import initialisiere, main


def test_init_erzeugt_einen_dauerhaften_token_ohne_ausgabe(tmp_path, capsys):
    ziel = tmp_path / ".env"
    assert main(["--init", "--env", str(ziel)]) == 0
    s = Settings(_env_file=ziel)
    assert len(s.jarvis_token) >= 32
    assert ensure_token(s.jarvis_token) == (s.jarvis_token, False)
    assert s.jarvis_token not in capsys.readouterr().out
    assert not s.llm_provider and not s.llm_api_key
    assert not s.datei_wurzeln and not s.kalender_quelle and not s.jarvis_ort
    assert stat.S_IMODE(ziel.stat().st_mode) == 0o600 if os.name == "posix" else True
    # Zweiter Start verwendet denselben Wert; zweite Initialisierung ersetzt nichts.
    vorher = ziel.read_bytes()
    assert main(["--init", "--env", str(ziel)]) == 1
    assert ziel.read_bytes() == vorher


def test_init_folgt_keinem_symlink(tmp_path):
    original = tmp_path / "bestehend.env"
    original.write_text("unveraendert")
    link = tmp_path / ".env"
    link.symlink_to(original)
    with pytest.raises(FileExistsError):
        initialisiere(link)
    assert original.read_text() == "unveraendert"


@pytest.mark.parametrize("token", ["abc\r\ndef", "abc\x00def", "abc\tdef",
                                    "bitte-hier-einen-langen-zufallswert-eintragen", "abc🔑def"])
def test_tokenfehler_verraet_den_wert_nicht(token):
    with pytest.raises(ValueError) as exc:
        ensure_token(token)
    assert token not in str(exc.value)
    assert "JARVIS_TOKEN" in str(exc.value)


def test_diagnose_unterscheidet_fehlende_und_kaputte_ordner(settings, tmp_path):
    settings.datei_wurzeln = ""
    assert integrationen(settings)["dateien"]["status"] == "nicht_eingerichtet"
    settings.datei_wurzeln = str(tmp_path / "fehlt")
    assert integrationen(settings)["dateien"]["status"] == "ungueltig"
    settings.datei_wurzeln += os.pathsep + str(tmp_path)
    stand = integrationen(settings)
    assert stand["dateien"]["status"] == "teilweise"
    assert str(tmp_path) not in json.dumps(stand)


def test_lokale_ics_und_ort_werden_geprueft_ohne_sie_auszugeben(settings, tmp_path):
    ics = tmp_path / "privat.ics"
    ics.write_text("BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n", encoding="utf-8")
    settings.kalender_quelle = str(ics)
    settings.jarvis_ort = "PRIVATER_ORT"
    stand = integrationen(settings)
    assert stand["kalender"]["status"] == "konfiguriert"
    assert stand["wetter"]["status"] == "konfiguriert"
    assert str(ics) not in json.dumps(stand)
    assert "PRIVATER_ORT" not in json.dumps(stand)
    ics.write_text("<html>Anmelden</html>")
    assert integrationen(settings)["kalender"]["status"] == "ungueltig"


def test_secrets_und_abo_url_stehen_weder_in_diagnose_noch_health(settings):
    settings.llm_provider = "groq"
    settings.llm_api_key = "LLM_TESTGEHEIMNIS_123456789"
    settings.llm_model = ""  # Konfigurationsfehler, kein Client/Modellaufruf.
    settings.cdse_client_id = "CDSE_TEST_ID"
    settings.cdse_client_secret = "CDSE_TEST_SECRET"
    settings.kalender_quelle = "https://calendar.example/ABO_TESTGEHEIMNIS/basic.ics"
    with TestClient(create_app(settings)) as client:
        assert client.get("/api/health").status_code == 401
        health = client.get("/api/health", headers={"X-Jarvis-Token": settings.jarvis_token}).json()
    assert health["integrationen"] == integrationen(settings)
    assert health["integrationen"]["satellitenbilder"]["status"] == "konfiguriert"
    for geheim in (settings.llm_api_key, settings.cdse_client_id,
                   settings.cdse_client_secret, settings.kalender_quelle,
                   "ABO_TESTGEHEIMNIS"):
        assert geheim not in json.dumps(health)


@pytest.mark.parametrize("feld", ["cdse_client_id", "cdse_client_secret"])
def test_halbe_cdse_einrichtung_ist_keine_bereite_integration(settings, feld):
    settings.cdse_client_id = "test-id"
    settings.cdse_client_secret = "test-secret"
    setattr(settings, feld, "")
    stand = integrationen(settings)
    assert stand["satellitenbilder"]["status"] == "nicht_eingerichtet"
    assert "CDSE-Zugangsdaten fehlen" in stand["satellitenbilder"]["hinweis"]
    assert stand["satellitenkatalog"]["status"] == "ohne_key"
    assert stand["ndvi"]["status"] == "blockiert"


def test_falscher_datentyp_in_env_verraet_den_input_nicht(tmp_path, capsys):
    env = tmp_path / ".env"
    env.write_text("JARVIS_PORT=VERIRRTES_TEST_SECRET\n")
    assert main(["--env", str(env)]) == 1
    ausgabe = capsys.readouterr().out
    assert "jarvis_port" in ausgabe
    assert "VERIRRTES_TEST_SECRET" not in ausgabe


def test_diagnose_json_ohne_llm_ist_ein_kontrollierter_zustand(tmp_path, capsys):
    assert main(["--env", str(tmp_path / "fehlt.env"), "--json"]) == 0
    stand = json.loads(capsys.readouterr().out)
    assert stand["llm"]["status"] == "nicht_eingerichtet"
    assert stand["weltlage"]["status"] == "nicht_eingerichtet"
    assert stand["erinnerungen"]["status"] == "bereit"
