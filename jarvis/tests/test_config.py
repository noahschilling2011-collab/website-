import re
from pathlib import Path

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


# --- Kein Feld, das niemand liest ------------------------------------------
#
# Inbetriebnahme-Befund, Schritt 5d: FIRMS_MAP_KEY stand in `.env.example`
# und in `Settings` - und wurde nirgends gelesen. Das ist schlimmer als ein
# fehlendes Feld: es steht in der Vorlage und fordert den Nutzer auf, sich
# einen Zugang zu besorgen, der nichts bewirkt.
#
# Der Test ist statisch, nicht dynamisch: er sucht `.<feldname>` im Quelltext
# ausserhalb von `core/config.py` und - fuer Felder, die nur die Konfiguration
# selbst auswertet (die Preise) - `self.<feldname>` innerhalb, aber ohne die
# Zeilen der Felddeklaration. Ein Feld, das nur sich selbst kennt, faellt
# durch.


def test_jedes_settings_feld_wird_irgendwo_gelesen():
    wurzel = Path(__file__).resolve().parent.parent
    konfig = wurzel / "core" / "config.py"

    quellen = [
        p for p in wurzel.rglob("*.py")
        if "__pycache__" not in p.parts
        and "tests" not in p.relative_to(wurzel).parts
        and p != konfig
    ]
    fremder_text = "\n".join(p.read_text(encoding="utf-8") for p in quellen)

    # config.py ohne die Deklarationszeilen: sonst belegt jedes Feld sich selbst.
    eigener_text = "\n".join(
        zeile for zeile in konfig.read_text(encoding="utf-8").splitlines()
        if not re.match(r"\s{4}[a-z_]+\s*:\s", zeile)
    )

    ungelesen = [
        name for name in Settings.model_fields
        if not re.search(rf"\.{name}\b", fremder_text)
        and not re.search(rf"\bself\.{name}\b", eigener_text)
    ]
    assert ungelesen == [], (
        f"Diese Felder liest niemand: {ungelesen}. Entweder benutzen oder "
        f"aus Settings und .env.example entfernen - ein Feld, das nur in der "
        f"Vorlage steht, verspricht eine Wirkung, die es nicht hat."
    )


def test_env_example_nennt_keine_unbekannte_variable():
    """Was in der Vorlage steht, muss auch ein Feld sein.

    Sonst traegt der Nutzer etwas ein, das `extra=ignore` still verschluckt.
    """
    wurzel = Path(__file__).resolve().parent.parent
    vorlage = (wurzel / ".env.example").read_text(encoding="utf-8")
    genannt = {
        zeile.split("=", 1)[0].strip().lower()
        for zeile in vorlage.splitlines()
        if "=" in zeile and not zeile.lstrip().startswith("#")
    }
    felder = set(Settings.model_fields)
    # Alias-Namen zaehlen mit: VAULT_PFAD, WIKI_API_TOKEN, JARVIS_DB_PATH ...
    for feld in Settings.model_fields.values():
        quelle = getattr(feld, "validation_alias", None)
        for kandidat in getattr(quelle, "choices", []) or []:
            felder.add(str(kandidat).lower())

    unbekannt = sorted(genannt - felder)
    assert unbekannt == [], (
        f".env.example nennt Variablen, die Settings nicht kennt: {unbekannt}"
    )


def test_status_md_schreibt_keine_feldzahl_von_hand():
    """Eine Zahl, die man in Prosa pflegt, verrottet.

    Gefunden am 30.08.2026 und im selben Lauf zweimal bestaetigt: STATUS.md
    behauptete viermal woertlich "alle 32 Settings-Felder". Es waren 34. Die
    Korrektur auf 34 war wenige Stunden spaeter wieder falsch, weil
    `wissen_cache_stunden` dazukam - also 35.

    Der Test verbietet die Zahl nicht, er verlangt nur, dass sie stimmt.
    Wer sie hinschreibt, muss sie pflegen; wer "jedes Feld" schreibt, nicht.

    Und er zaehlt Prosa mit, auch ein Zitat des alten Fehlers - genau das
    ist beim ersten Lauf passiert. Das ist Absicht, nicht Nachlaessigkeit:
    ein Waechter mit einer Ausnahme fuer "aber das ist ja nur zitiert"
    laesst sich mit derselben Ausrede immer umgehen. Wer den Fehler
    beschreiben will, nennt die Zahl nicht woertlich neben dem Wort
    "Settings-Felder".
    """
    import re

    from core.config import Settings

    wurzel = Path(__file__).resolve().parent.parent
    echt = len(Settings.model_fields)
    schlecht = []
    for datei in sorted(wurzel.glob("*.md")) + sorted((wurzel / "docs").glob("*.md")):
        for nr, zeile in enumerate(datei.read_text(encoding="utf-8").splitlines(), 1):
            for zahl in re.findall(r"(\d+)\s+Settings-Felder", zeile):
                if int(zahl) != echt:
                    schlecht.append(
                        f"{datei.name}:{nr}: behauptet {zahl} Settings-Felder, "
                        f"es sind {echt} -> {zeile.strip()[:70]}")
    assert schlecht == [], (
        "handgeschriebene Feldzahl stimmt nicht mehr:\n  " + "\n  ".join(schlecht))
