"""Konfiguration.

Namen und Aufteilung folgen `.env.example`. Nichts davon wird geraten - die
Modell-ID und die Preise traegt der Nutzer aus der Doku des Anbieters ein.

Preise sind bewusst optional: ein leerer Wert heisst "unbekannt", nicht "null
Euro". Wer nichts eintraegt, bekommt keine erfundene Kostenrechnung, sondern
eine sichtbare Luecke.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parent.parent

DEFAULT_SYSTEM_PROMPT = (
    "Du bist JARVIS, ein persoenliches Assistenzsystem. Du antwortest auf "
    "Deutsch und duzt. Du fasst dich kurz und sagst klar, wenn du etwas nicht "
    "weisst, statt zu raten. Erfinde keine Fakten, keine Quellen und keine "
    "Zahlen."
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # --- Zugang zu JARVIS selbst (0.4) ---
    jarvis_token: str = ""
    jarvis_host: str = "127.0.0.1"
    jarvis_port: int = 8000

    # --- LLM-Provider ---
    # Leer = kein echter Anbieter eingerichtet. Dann laeuft der FakeLLMProvider,
    # der nicht ins Netz geht und nichts kostet.
    llm_provider: str = ""
    llm_api_key: str = ""
    llm_model: str = ""

    # Preise in EUR je 1.000.000 Token. Leer lassen ist erlaubt und ehrlich.
    llm_price_in_per_mtok: float | None = None
    llm_price_out_per_mtok: float | None = None

    # --- Budgets (0.5). In Phase 1 nur eingelesen, noch nicht durchgesetzt. ---
    budget_max_steps: int = 12
    budget_max_depth: int = 2
    budget_max_tool_calls: int = 20
    budget_max_tokens: int = 60_000
    budget_max_seconds: int = 180
    budget_max_cost_eur: float = 0.50

    # --- Betrieb ---
    # 0.6: Timeout pro LLM-Call 60 s.
    llm_timeout_seconds: float = 60.0
    llm_max_retries: int = 2
    llm_max_tokens: int = 4096
    history_limit: int = 40
    # Alias, damit JARVIS_DB_PATH das tut, was der Name verspricht. Ohne ihn
    # hiesse die Variable DB_PATH und ein JARVIS_DB_PATH waere still wirkungslos.
    db_path: Path = Field(
        default=PROJECT_ROOT / "data" / "jarvis.db",
        validation_alias=AliasChoices("JARVIS_DB_PATH", "DB_PATH"),
    )
    system_prompt: str = DEFAULT_SYSTEM_PROMPT

    @field_validator("llm_price_in_per_mtok", "llm_price_out_per_mtok", mode="before")
    @classmethod
    def _leerer_preis_ist_unbekannt(cls, value: object) -> object:
        return None if isinstance(value, str) and not value.strip() else value

    @field_validator("db_path")
    @classmethod
    def _absoluter_pfad(cls, value: Path) -> Path:
        return value if value.is_absolute() else PROJECT_ROOT / value

    @property
    def prices_configured(self) -> bool:
        return (
            self.llm_price_in_per_mtok is not None
            and self.llm_price_out_per_mtok is not None
        )

    def cost_eur(self, in_tokens: int, out_tokens: int) -> float:
        """Kosten eines Aufrufs. 0.0, solange keine Preise eingetragen sind."""
        if not self.prices_configured:
            return 0.0
        return (
            in_tokens * (self.llm_price_in_per_mtok or 0.0)
            + out_tokens * (self.llm_price_out_per_mtok or 0.0)
        ) / 1_000_000

    def masked_api_key(self) -> str:
        """Genug, um zwei Keys zu unterscheiden. Zu wenig, um einen zu benutzen."""
        key = self.llm_api_key
        if not key:
            return ""
        return f"{key[:7]}…{key[-4:]}" if len(key) > 14 else "…"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
