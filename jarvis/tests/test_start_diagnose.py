"""Die Startmeldung muss sagen, WAS gefehlt hat - nicht nur DASS etwas fehlt.

Anlass, 27.08.2026: Noahs Server startete mit

    ERROR: Anbieter nicht verfuegbar - Kein LLM_API_KEY gesetzt.
    INFO: JARVIS bereit - Anbieter groq, Modell openai/gpt-oss-120b

Zwei Zeilen, die sich zu widersprechen scheinen: Anbieter und Modell sind da,
der Key nicht. Beides stand in derselben `.env`. Wer das liest, weiss nicht,
ob die Datei gefunden wurde, ob die richtige gefunden wurde, oder ob nur eine
Zeile leer blieb - und faengt an zu raten.

Eine Fehlermeldung, die zum Raten zwingt, ist eine halbe Fehlermeldung.
"""

from __future__ import annotations

import logging

import pytest
from fastapi.testclient import TestClient

from api.app import create_app


def _start(settings, caplog):
    caplog.set_level(logging.INFO, logger="jarvis")
    with TestClient(create_app(settings)):
        pass
    return "\n".join(r.getMessage() for r in caplog.records)


def test_ohne_key_sagt_die_meldung_welche_werte_ankamen(settings, caplog):
    settings.llm_provider = "groq"
    settings.llm_model = "openai/gpt-oss-120b"
    settings.llm_api_key = ""
    text = _start(settings, caplog)

    # Der Kern: die Meldung nennt alle drei Werte einzeln.
    assert "LLM_PROVIDER" in text and "groq" in text
    assert "LLM_MODEL" in text and "openai/gpt-oss-120b" in text
    assert "LLM_API_KEY" in text
    # Und sagt, welche Datei sie gelesen hat.
    assert ".env" in text and "Konfigurationsdatei" in text


def test_der_key_selbst_steht_nie_im_log(settings, caplog):
    """Logs landen in Dateien, in Terminals und in Screenshots, die Noah mir
    schickt. Der Key gehoert in keins davon.

    Damit die Diagnose ueberhaupt laeuft, muss der Start scheitern - also
    fehlt hier das Modell und NICHT der Key. Sonst prueft der Test nichts:
    bei gueltigem Key und gueltigem Modell startet der Anbieter, und dann
    gibt es zu Recht gar keine Diagnose.
    """
    settings.llm_provider = "groq"
    settings.llm_model = ""
    settings.llm_api_key = "gsk_streng_geheim_1234567890"
    text = _start(settings, caplog)

    assert "LLM_API_KEY ist gesetzt" in text, "die Diagnose lief gar nicht"
    assert "gsk_streng_geheim_1234567890" not in text
    assert "streng_geheim" not in text


def test_mit_key_wird_die_laenge_gemeldet_statt_des_werts(settings, caplog):
    """Damit sich ein halb eingefuegter Key erkennen laesst, ohne ihn zu zeigen."""
    settings.llm_provider = "groq"
    settings.llm_model = ""          # der Ausloeser, siehe oben
    settings.llm_api_key = "x" * 56
    text = _start(settings, caplog)
    assert "56 Zeichen" in text


def test_bei_erfolgreichem_start_gibt_es_keine_diagnose(settings, caplog):
    """Die Gegenprobe. Wer laeuft, braucht keine Selbstauskunft ueber seinen
    Key - auch nicht die Laenge."""
    settings.llm_provider = "groq"
    settings.llm_model = "openai/gpt-oss-120b"
    settings.llm_api_key = "gsk_" + "z" * 52
    text = _start(settings, caplog)
    assert "LLM_API_KEY" not in text
    assert "Anbieter nicht verfuegbar" not in text


def test_ohne_anbieter_gibt_es_die_meldung_gar_nicht(settings, caplog):
    """Wer bewusst ohne Anbieter faehrt, braucht keine Diagnose - der
    FakeLLMProvider ist dann kein Fehler, sondern die Absicht."""
    settings.llm_provider = ""
    settings.llm_api_key = ""
    settings.llm_model = ""
    text = _start(settings, caplog)
    assert "LLM_PROVIDER=" not in text


@pytest.mark.parametrize("fehlt", ["llm_api_key", "llm_model"])
def test_die_diagnose_kommt_bei_jedem_fehlenden_pflichtfeld(settings, caplog, fehlt):
    settings.llm_provider = "groq"
    settings.llm_model = "openai/gpt-oss-120b"
    settings.llm_api_key = "gsk_" + "y" * 52
    setattr(settings, fehlt, "")
    text = _start(settings, caplog)
    assert "LLM_PROVIDER" in text, fehlt
