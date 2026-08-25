from pathlib import Path

import pytest

from core.config import DEFAULT_SYSTEM_PROMPT, Settings, get_settings


def test_voreinstellung_ist_der_fake_anbieter():
    s = Settings(_env_file=None)
    assert s.provider == "fake"
    assert s.model == "claude-opus-5"
    assert s.system_prompt == DEFAULT_SYSTEM_PROMPT


def test_umgebung_setzt_anbieter_und_key(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("JARVIS_PROVIDER", "anthropic")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-beispiel-1234567890")
    s = Settings(_env_file=None)
    assert s.provider == "anthropic"
    assert s.anthropic_api_key == "sk-ant-beispiel-1234567890"


def test_key_wird_maskiert():
    s = Settings(_env_file=None, anthropic_api_key="sk-ant-geheim-abcdefgh")
    hint = s.masked_api_key()
    assert "geheim" not in hint
    assert hint.startswith("sk-ant-")
    assert hint.endswith("efgh")


def test_kein_key_ergibt_leeren_hinweis():
    assert Settings(_env_file=None, anthropic_api_key="").masked_api_key() == ""


def test_relativer_db_pfad_wird_absolut():
    s = Settings(_env_file=None, db_path=Path("data/x.db"))
    assert s.db_path.is_absolute()


def test_preis_zum_modell():
    assert Settings(_env_file=None, model="claude-opus-5").price_per_mtok == (5.0, 25.0)
    assert Settings(_env_file=None, model="gibt-es-nicht").price_per_mtok is None


def test_get_settings_ist_zwischengespeichert():
    get_settings.cache_clear()
    assert get_settings() is get_settings()
