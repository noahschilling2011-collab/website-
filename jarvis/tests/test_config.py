import pytest

from core.config import Settings, get_settings


def test_ohne_env_laeuft_der_fake():
    s = Settings(_env_file=None)
    assert s.llm_provider == ""
    assert s.llm_model == ""
    assert s.jarvis_host == "127.0.0.1"   # 0.4.3: nicht 0.0.0.0
    assert s.jarvis_port == 8000


def test_env_namen_aus_der_env_example(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("JARVIS_TOKEN", "geheim")
    monkeypatch.setenv("LLM_PROVIDER", "anthropic")
    monkeypatch.setenv("LLM_API_KEY", "sk-ant-beispiel-1234567890")
    monkeypatch.setenv("LLM_MODEL", "claude-opus-5")
    s = Settings(_env_file=None)
    assert s.jarvis_token == "geheim"
    assert s.llm_provider == "anthropic"
    assert s.llm_api_key == "sk-ant-beispiel-1234567890"
    assert s.llm_model == "claude-opus-5"


def test_budgets_haben_die_werte_aus_der_env_example():
    s = Settings(_env_file=None)
    assert s.budget_max_steps == 12
    assert s.budget_max_depth == 2
    assert s.budget_max_tool_calls == 20
    assert s.budget_max_tokens == 60_000
    assert s.budget_max_seconds == 180
    assert s.budget_max_cost_eur == 0.50


def test_llm_timeout_ist_60s_laut_abschnitt_0_6():
    assert Settings(_env_file=None).llm_timeout_seconds == 60.0


def test_leerer_preis_ist_unbekannt_nicht_null(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("LLM_PRICE_IN_PER_MTOK", "")
    monkeypatch.setenv("LLM_PRICE_OUT_PER_MTOK", "")
    s = Settings(_env_file=None)
    assert s.llm_price_in_per_mtok is None
    assert s.prices_configured is False


def test_ohne_preise_wird_keine_kostenzahl_erfunden():
    s = Settings(_env_file=None)
    assert s.cost_eur(1_000_000, 1_000_000) == 0.0
    assert s.prices_configured is False


def test_kosten_rechnung():
    s = Settings(_env_file=None, llm_price_in_per_mtok=4.6, llm_price_out_per_mtok=23.0)
    assert s.prices_configured is True
    # 1000 * 4,6/1e6 + 500 * 23/1e6 = 0,0046 + 0,0115
    assert s.cost_eur(1000, 500) == pytest.approx(0.0161)


def test_key_wird_maskiert():
    s = Settings(_env_file=None, llm_api_key="sk-ant-geheim-abcdefgh")
    hint = s.masked_api_key()
    assert "geheim" not in hint
    assert hint.endswith("efgh")


def test_get_settings_ist_zwischengespeichert():
    get_settings.cache_clear()
    assert get_settings() is get_settings()


def test_jarvis_db_path_wirkt_wirklich(monkeypatch: pytest.MonkeyPatch, tmp_path):
    """Ohne Alias hiesse die Variable DB_PATH - und JARVIS_DB_PATH waere still
    wirkungslos. Genau das ist beim ersten Live-Lauf passiert."""
    ziel = tmp_path / "woanders.db"
    monkeypatch.setenv("JARVIS_DB_PATH", str(ziel))
    assert Settings(_env_file=None).db_path == ziel
