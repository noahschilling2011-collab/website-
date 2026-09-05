"""Konfiguration.

Namen und Aufteilung folgen `.env.example`. Nichts davon wird geraten - die
Modell-ID und die Preise traegt der Nutzer aus der Doku des Anbieters ein.

Preise sind bewusst optional: ein leerer Wert heisst "unbekannt", nicht "null
Euro". Wer nichts eintraegt, bekommt keine erfundene Kostenrechnung, sondern
eine sichtbare Luecke.
"""

from __future__ import annotations

from functools import lru_cache
import re
from pathlib import Path

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# {name} wird beim Gebrauch durch ASSISTENT_NAME ersetzt (FIX-09): der
# Assistent heisst, wie der Nutzer ihn nennt - das Projekt heisst JARVIS.
DEFAULT_SYSTEM_PROMPT = (
    "Du bist {name}, ein persoenliches Assistenzsystem. Du antwortest auf "
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

    # --- Ab Phase 2 ---
    search_api_key: str = ""

    # --- Wissensquellen (docs/wissensquellen.md) ---
    # kiwix-serve laeuft lokal; WIKI_ZIM ist der Slug der ZIM-Datei.
    # Leer = wiki_lokal meldet das beim Aufruf, statt still nichts zu finden.
    wiki_kiwix_basis: str = Field(
        default="http://127.0.0.1:8080",
        validation_alias=AliasChoices("WIKI_KIWIX_BASIS", "KIWIX_URL"),
    )
    wiki_zim: str = Field(default="", validation_alias=AliasChoices("WIKI_ZIM"))
    # Pflicht laut Wikimedia-User-Agent-Richtlinie: eine Kontaktangabe.
    wiki_kontakt: str = Field(default="", validation_alias=AliasChoices("WIKI_KONTAKT"))
    # Optional. Hebt 500 Anfragen/Stunde auf 5.000/Stunde.
    wiki_token: str = Field(default="", validation_alias=AliasChoices("WIKI_API_TOKEN"))

    # Wie lange ein Nachschlage-Treffer im Cache gilt, in Stunden.
    # 0 = nie verfallen (das war bis zum 30.08.2026 das einzige
    # Verhalten - `geholt_am` wurde geschrieben und nie gelesen).
    #
    # 24 Stunden ist die Voreinstellung und keine gemessene Zahl,
    # sondern eine Abwaegung zwischen zwei Zusagen aus
    # docs/wissensquellen.md: DoD 6 verlangt, dass eine zweite
    # identische Anfrage den Cache trifft (haelt bei jeder Dauer ueber
    # ein paar Sekunden), DoD 4, dass wiki_live bei veralteten Staenden
    # wirklich greift (haelt bei keiner unendlichen Dauer). Wer es
    # anders will, stellt es hier - still erhoeht wird es nicht.
    wissen_cache_stunden: float = 24.0

    # --- Vault (docs/MIGRATION-VAULT.md) ---
    # Leer = kein Vault. Dann bleibt JARVIS bei der Datenbank, und nichts an
    # diesem Pfad wird angelegt. AliasChoices, weil der Feldname sonst still
    # VAULT_PATH lesen wuerde - derselbe Fehler wie frueher bei db_path.
    vault_pfad: str = Field(
        default="", validation_alias=AliasChoices("VAULT_PFAD", "VAULT_PATH")
    )

    # --- Lokaler Zugriff (docs/FIX-07.md) ---
    # Leer = kein Dateizugriff. JARVIS sieht dann NICHTS vom Dateisystem.
    # Getrennt durch os.pathsep (":" unter Linux/macOS, ";" unter Windows).
    #
    # NICHT das Benutzerverzeichnis als Ganzes eintragen. Dort liegen .ssh,
    # Browserprofile, Passwortspeicher und die .env-Dateien anderer
    # Projekte. Wer die Wurzel zu weit setzt, hat die Allowlist umsonst.
    datei_wurzeln: str = Field(
        default="", validation_alias=AliasChoices("DATEI_WURZELN", "FILE_ROOTS")
    )
    # Obergrenze je Datei. Groesseres wird nicht gelesen, mit Nennung der
    # Grenze - eine 400-MB-Logdatei gehoert nicht in einen Prompt.
    datei_max_kb: int = Field(
        default=512, validation_alias=AliasChoices("DATEI_MAX_KB")
    )
    # Leer = kein Kalender. Dateipfad ODER https-Adresse eines ICS-Abos.
    # Die Abo-Adresse ist ein Geheimnis wie ein Passwort: wer sie hat, liest
    # den ganzen Kalender mit.
    kalender_quelle: str = Field(
        default="", validation_alias=AliasChoices("KALENDER_QUELLE", "CALENDAR_SOURCE")
    )

    # Phase 5: send_email schreibt hierhin statt zu senden. Ein echter Versand
    # waere ein eigenes Werkzeug mit eigenem Anbieter und eigenem Key.
    outbox_path: Path = Field(
        default=PROJECT_ROOT / "data" / "outbox.jsonl",
        validation_alias=AliasChoices("JARVIS_OUTBOX_PATH", "OUTBOX_PATH"),
    )
    # Obergrenze fuer den Chat-Agenten. 3 = EXTERNAL.
    #
    # Bis Phase 4 stand hier LOCAL, weil es keinen Schutz gab: ein Werkzeug mit
    # Aussenwirkung waere einfach gelaufen. Seit Phase 5 ist jedes Werkzeug ab
    # EXTERNAL bestaetigungspflichtig - die Registry laesst gar nichts anderes
    # zu -, und der Mensch sieht vor der Ausfuehrung genau, was passieren
    # wuerde. Damit ist die Bestaetigung der Schutz, nicht die Decke.
    #
    # SENSITIVE (loeschen, bezahlen, Konto aendern) bleibt zu. Das aufzumachen
    # waere eine eigene Entscheidung, keine Voreinstellung.
    max_permission: int = 3

    # --- Ab Phase 8 (Satellit) ---
    # Hier stand FIRMS_MAP_KEY. Kein Code hat es je gelesen - es stand nur in
    # der Vorlage und forderte den Nutzer auf, sich bei NASA einen Zugang zu
    # besorgen, der nichts bewirkt. Der Plan dafuer bleibt in
    # docs/satellite.md (aktive Braende ueber NASA FIRMS); wenn das gebaut
    # wird, kommt das Feld mit dem Code zurueck, der es liest.
    cdse_client_id: str = ""
    cdse_client_secret: str = ""

    # --- Budgets (0.5) ---
    budget_max_steps: int = 12
    budget_max_depth: int = 2
    budget_max_tool_calls: int = 20
    budget_max_tokens: int = 60_000
    budget_max_seconds: int = 180
    budget_max_cost_eur: float = 0.50

    # --- FIX-08: Zeitplaene ---
    # Ein Deckel ueber ALLE Zeitplaene zusammen, rollierend ueber 24 Stunden.
    # Ein Zeitplan laeuft, waehrend niemand hinsieht - deshalb ist das hier
    # kein Komfort, sondern die Bremse. Die Vorgaben sind absichtlich klein:
    # 50.000 Token sind ein Viertel der freien Groq-Stufe (200.000 am Tag),
    # 24 Laeufe sind einer je Stunde. Wer mehr will, stellt es hier ein -
    # still erhoeht wird es nicht (CLAUDE.md, Regel 6).
    zeitplan_max_laeufe_24h: int = 24
    zeitplan_max_token_24h: int = 50_000
    # Wie oft die Schleife nachsieht, in Sekunden. Nicht unter 10: die
    # Schleife weckt den Prozess, und bei 1 Sekunde waere das ein Poller.
    zeitplan_takt_s: int = 60

    # --- FIX-09 ---
    # Wie der Assistent heisst. Noah, 05.09.2026: "nenn ihn Mehmet". Der
    # Name steht in der Oberflaeche und in jedem Systemprompt; der Code und
    # die Doku heissen weiter JARVIS.
    assistent_name: str = "Mehmet"
    # Der Ort fuer das Wetter-Werkzeug, wenn keiner genannt wird, und fuer
    # die Vorlage "Morgenlage". Leer = das Werkzeug fragt nach einem Ort.
    jarvis_ort: str = ""


    # --- Betrieb ---
    # 0.6: Timeout pro LLM-Call 60 s.
    llm_timeout_seconds: float = 60.0
    llm_max_retries: int = 2
    llm_max_tokens: int = 4096
    history_limit: int = 40
    # Phase 7: wie oft der Ereignisstrom ein Lebenszeichen schickt. In Tests
    # klein, damit ein weggegangener Client sofort auffaellt.
    sse_heartbeat_seconds: float = 20.0
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

    @field_validator("db_path", "outbox_path")
    @classmethod
    def _absoluter_pfad(cls, value: Path) -> Path:
        return value if value.is_absolute() else PROJECT_ROOT / value

    @field_validator("max_permission")
    @classmethod
    def _stufe_gibt_es(cls, value: int) -> int:
        """MAX_PERMISSION=9 fiel bis FIX-08 erst beim ersten Auftrag auf -
        als 500 im Browser. Ein Einrichtungsfehler gehoert an den Start."""
        from core.contracts import Permission

        if value not in {p.value for p in Permission}:
            raise ValueError(
                f"MAX_PERMISSION={value} ist keine Stufe. Erlaubt: "
                + ", ".join(f"{p.value} ({p.name})" for p in Permission)
            )
        return value

    @field_validator("zeitplan_max_laeufe_24h", "zeitplan_max_token_24h")
    @classmethod
    def _nicht_negativ(cls, value: int) -> int:
        if value < 0:
            raise ValueError("Zeitplan-Werte sind 0 oder groesser.")
        return value

    @field_validator("assistent_name", mode="before")
    @classmethod
    def _leerer_name_ist_die_vorgabe(cls, value: object) -> object:
        """ASSISTENT_NAME= (leer) in der .env heisst Vorgabe, nicht Startabbruch."""
        return "Mehmet" if isinstance(value, str) and not value.strip() else value

    @field_validator("assistent_name")
    @classmethod
    def _name_passt_in_die_seite(cls, value: str) -> str:
        """Der Name wird roh in HTML und JavaScript eingesetzt. Buchstaben,
        Ziffern, Leerzeichen, Punkt und Bindestrich - kein Anfuehrungszeichen,
        keine spitze Klammer, hoechstens 40 Zeichen. Vorher in NFC gebracht:
        ein Umlaut aus Basisbuchstabe plus Kombinationszeichen (macOS,
        manche Zwischenablagen) sieht gleich aus und wuerde sonst abgelehnt."""
        import unicodedata

        wert = unicodedata.normalize("NFC", " ".join(str(value or "").split()))
        if not wert or len(wert) > 40 or not re.fullmatch(r"[\w .\-]+", wert):
            raise ValueError("ASSISTENT_NAME: 1 bis 40 Zeichen, nur Buchstaben, Ziffern, "
                             "Leerzeichen, Punkt und Bindestrich.")
        return wert

    @field_validator("zeitplan_takt_s")
    @classmethod
    def _takt_im_rahmen(cls, value: int) -> int:
        """0 (aus) oder 10 bis 300 Sekunden. Die Toleranz fuer 'verpasst'
        haengt am Takt (core/zeitplan.toleranz_fuer); ein Takt von einer
        Stunde machte daraus ein Nachholen - genau das, was Regel 3
        verbietet (zweite Pruefrunde FIX-08)."""
        if value != 0 and not 10 <= value <= 300:
            raise ValueError("ZEITPLAN_TAKT_S ist 0 (aus) oder 10 bis 300 Sekunden.")
        return value

    @property
    def system_prompt_mit_name(self) -> str:
        """Der Systemprompt mit dem eingesetzten Namen des Assistenten."""
        return self.system_prompt.replace("{name}", self.assistent_name)

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
    try:
        return Settings()
    except UnicodeDecodeError as exc:
        # FIX-09: die ersten .env-Werte mit Umlauten (ASSISTENT_NAME, JARVIS_ORT).
        # Ein Windows-Editor speichert "ANSI", python-dotenv liest UTF-8, und
        # der Start endete in einem nackten Traceback ohne das Wort ".env".
        raise SystemExit(
            "Die .env ist nicht als UTF-8 gespeichert (Umlaut in einem Wert?). "
            "Im Editor 'Speichern unter' -> Kodierung UTF-8 waehlen und neu starten."
        ) from exc
