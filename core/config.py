"""Konfiguration.

Alles, was sich zwischen zwei Rechnern unterscheidet, steht hier und kommt
aus der Umgebung oder aus `.env`. Der API-Key ist bewusst ein eigenes Feld
ohne Praefix, damit die uebliche Variable `ANTHROPIC_API_KEY` funktioniert.

Der Key wird nirgends geloggt und nirgends ausgegeben. `masked_api_key()`
ist die einzige Stelle, an der ueberhaupt etwas davon sichtbar wird.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Preise in US-Dollar je eine Million Token, Stand der Modell-Dokumentation.
# Wird in Phase 2 fuer die Kostenanzeige gebraucht; hier steht sie schon,
# damit /api/health ehrlich sagen kann, was ein Aufruf kostet.
MODEL_PRICES_USD_PER_MTOK: dict[str, tuple[float, float]] = {
    "claude-opus-5": (5.0, 25.0),
    "claude-sonnet-5": (2.0, 10.0),
    "claude-haiku-4-5": (1.0, 5.0),
}

DEFAULT_SYSTEM_PROMPT = (
    "Du bist JARVIS, ein persoenliches Assistenzsystem. Du antwortest auf "
    "Deutsch und duzt. Du fasst dich kurz und sagst klar, wenn du etwas nicht "
    "weisst, statt zu raten. Erfinde keine Fakten, keine Quellen und keine "
    "Zahlen. Wenn eine Frage eine Information braucht, die du nicht hast, "
    "sag welche."
)


class Settings(BaseSettings):
    """Laufzeit-Konfiguration. Wird einmal gelesen und dann zwischengespeichert."""

    model_config = SettingsConfigDict(
        env_prefix="JARVIS_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Welcher Anbieter antwortet. "fake" kostet nichts und geht nicht ins Netz.
    provider: Literal["fake", "anthropic"] = "fake"

    anthropic_api_key: str = Field(
        default="",
        validation_alias=AliasChoices("ANTHROPIC_API_KEY", "JARVIS_ANTHROPIC_API_KEY"),
    )
    anthropic_base_url: str = "https://api.anthropic.com"

    # Modell-ID des Anbieters. Nicht raten - Liste siehe README.
    model: str = "claude-opus-5"
    # Nicht-streamende Anfragen bleiben unter dem HTTP-Timeout, wenn max_tokens
    # nicht zu gross ist. 16000 ist der dokumentierte Richtwert.
    max_tokens: int = 16000
    effort: Literal["low", "medium", "high", "xhigh", "max"] = "high"
    request_timeout_seconds: float = 120.0
    max_retries: int = 2

    # Wie viele vorherige Nachrichten mitgeschickt werden. Ein echtes
    # Gedaechtnis kommt in Phase 3; bis dahin ist das ein hartes Fenster.
    history_limit: int = 40

    db_path: Path = PROJECT_ROOT / "data" / "jarvis.db"
    system_prompt: str = DEFAULT_SYSTEM_PROMPT

    @field_validator("db_path")
    @classmethod
    def _absolute_db_path(cls, value: Path) -> Path:
        return value if value.is_absolute() or str(value) == ":memory:" else PROJECT_ROOT / value

    @property
    def price_per_mtok(self) -> tuple[float, float] | None:
        """(Eingabe, Ausgabe) in USD je Million Token, oder None wenn unbekannt."""
        return MODEL_PRICES_USD_PER_MTOK.get(self.model)

    def masked_api_key(self) -> str:
        """Genug, um zwei Keys zu unterscheiden. Zu wenig, um einen zu benutzen."""
        key = self.anthropic_api_key
        if not key:
            return ""
        return f"{key[:7]}…{key[-4:]}" if len(key) > 14 else "…"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
