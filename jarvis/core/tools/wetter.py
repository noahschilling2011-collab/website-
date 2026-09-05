"""Wetter ohne Key (FIX-09): Open-Meteo.

Nachgeschlagen am 05.09.2026 (CLAUDE.md Regel 1), nicht aus dem Gedaechtnis:

- Geokodierung: https://open-meteo.com/en/docs/geocoding-api
  GET https://geocoding-api.open-meteo.com/v1/search?name=...&count=1&language=de&format=json
  Antwort: {"results": [{"name", "latitude", "longitude", "country",
  "country_code", "admin1", "timezone", ...}]} - "results" fehlt, wenn
  nichts gefunden wurde ("Empty fields are not returned").
- Vorhersage: https://open-meteo.com/en/docs
  GET https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..
  &current=temperature_2m,weather_code
  &daily=temperature_2m_max,temperature_2m_min,precipitation_sum,
         precipitation_probability_max,weather_code,wind_speed_10m_max,sunrise,sunset
  &timezone=auto&forecast_days=N   (N 0..16, Vorgabe 7)
  Antwort: {"timezone", "current": {...}, "daily": {"time": [...], ...},
  "daily_units": {...}}
- Kein API-Key fuer nicht-kommerzielle Nutzung; Einheiten: Celsius, mm, km/h.
- Wettercodes (WMO) laut Doku-Tabelle: 0 klar; 1-3 ueberwiegend klar bis
  bedeckt; 45, 48 Nebel; 51-55 Niesel; 56-57 gefrierender Niesel; 61-65
  Regen; 66-67 gefrierender Regen; 71-75 Schnee; 77 Schneegriesel; 80-82
  Regenschauer; 85-86 Schneeschauer; 95 Gewitter; 96, 99 Gewitter mit Hagel.

Warum ein eigenes Werkzeug und nicht web_search: Websuche braucht einen
Key, den es hier nicht gibt - und ein Wetterbericht ist eine Zahl, keine
Meinung. Ergebnisse werden eine Stunde gecacht (Tabelle `lookups`), damit
eine Morgenlage, die zweimal fragt, nur einmal ins Netz geht.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx

from core.contracts import Permission, Tool, ToolResult
from core.fehlertexte import ohne_geheimnis
from core.netz import nach_draussen
from core.tools.registry import register

log = logging.getLogger("jarvis")

GEO_URL = "https://geocoding-api.open-meteo.com/v1/search"
VORHERSAGE_URL = "https://api.open-meteo.com/v1/forecast"
QUELLE = "https://open-meteo.com/"

WMO = {
    0: "klar", 1: "ueberwiegend klar", 2: "teils bewoelkt", 3: "bedeckt",
    45: "Nebel", 48: "Nebel mit Reif",
    51: "leichter Nieselregen", 53: "Nieselregen", 55: "starker Nieselregen",
    56: "gefrierender Nieselregen", 57: "starker gefrierender Nieselregen",
    61: "leichter Regen", 63: "Regen", 65: "starker Regen",
    66: "gefrierender Regen", 67: "starker gefrierender Regen",
    71: "leichter Schneefall", 73: "Schneefall", 75: "starker Schneefall",
    77: "Schneegriesel",
    80: "leichte Regenschauer", 81: "Regenschauer", 82: "starke Regenschauer",
    85: "leichte Schneeschauer", 86: "starke Schneeschauer",
    95: "Gewitter", 96: "Gewitter mit leichtem Hagel", 99: "Gewitter mit starkem Hagel",
}


def wetter_text(code: Any) -> str:
    try:
        return WMO.get(int(code), f"Wettercode {int(code)}")
    except (TypeError, ValueError):
        return "unbekannt"


def _de(zahl: Any, stellen: int = 0) -> str:
    """12,5 statt 12.5 - und keine Nachkommastelle, wo keine gebraucht wird."""
    try:
        wert = float(zahl)
    except (TypeError, ValueError):
        return "?"
    text = f"{wert:.{stellen}f}".replace(".", ",")
    return text


def _uhr(iso: str) -> str:
    """'2026-09-05T06:31' -> '06:31'."""
    return iso[11:16] if isinstance(iso, str) and len(iso) >= 16 else "?"


def _tag(iso: str) -> str:
    """'2026-09-05' -> '05.09.'."""
    if not isinstance(iso, str) or len(iso) < 10:
        return "?"
    return f"{iso[8:10]}.{iso[5:7]}."


@register
class Wetter(Tool):
    name = "wetter"
    description = (
        "Aktuelles Wetter und Vorhersage fuer einen Ort - Temperatur, Regen, Wind, Sonnenauf- und -untergang, bis zu drei Tage.\n"
        "Nimm es fuer: \"wie wird das Wetter?\", \"brauche ich einen Schirm?\", eine Morgenlage - und immer, wenn nach Wetter gefragt wird; rate es nie.\n"
        "Nimm es NICHT fuer: vergangenes Wetter, Klima, Unwetterwarnungen - das kann es nicht.\n"
        "Beispiel: wetter(ort=\"Berlin\", tage=2)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "ort": {
                "type": "string",
                "description": (
                    "Stadt oder Ort, z. B. 'Berlin' oder 'Garmisch-Partenkirchen'. "
                    "Weglassen fuer den Standardort des Nutzers (JARVIS_ORT)."
                ),
            },
            "tage": {
                "type": "integer",
                "description": "Wie viele Tage ab heute, 1 bis 3. Vorgabe 2.",
            },
        },
        "additionalProperties": False,
    }
    permission = Permission.READ

    # Werden beim App-Start gesetzt (api/app.py), nicht importiert.
    standard_ort: str = ""
    db_path: Path | str = ""
    timeout_s: float = 10.0
    cache_stunden: float = 1.0
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, ort: str | None = None, tage: int | None = None) -> ToolResult:
        begonnen = time.monotonic()
        ort = (ort or self.standard_ort or "").strip()
        if not ort:
            hinweis = ("Kein Ort angegeben, und JARVIS_ORT ist leer. Nenn einen Ort "
                       "oder trag JARVIS_ORT in die .env ein.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)
        try:
            tage = int(tage) if tage is not None else 2
        except (TypeError, ValueError):
            tage = 2
        tage = max(1, min(3, tage))

        gecached = self._aus_cache(ort, tage)
        if gecached is not None:
            return ToolResult(ok=True, data={"cache": True}, display=gecached,
                              sources=[QUELLE],
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        try:
            async with nach_draussen(timeout=self.timeout_s,
                                     transport=self.transport) as client:
                geo = await client.get(GEO_URL, params={
                    "name": ort, "count": 1, "language": "de", "format": "json"})
                geo.raise_for_status()
                treffer = (geo.json() or {}).get("results") or []
                if not treffer:
                    text = f"Den Ort {ort!r} kennt der Wetterdienst nicht."
                    return ToolResult(ok=False, error=text, display=text,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                platz = treffer[0]
                antwort = await client.get(VORHERSAGE_URL, params={
                    "latitude": platz["latitude"], "longitude": platz["longitude"],
                    "current": "temperature_2m,weather_code",
                    "daily": ("temperature_2m_max,temperature_2m_min,precipitation_sum,"
                              "precipitation_probability_max,weather_code,"
                              "wind_speed_10m_max,sunrise,sunset"),
                    "timezone": "auto", "forecast_days": tage})
                antwort.raise_for_status()
                daten = antwort.json() or {}
        except httpx.HTTPError as exc:
            text = ohne_geheimnis(exc, "Wetterdienst nicht erreichbar",
                                  "Spaeter noch einmal versuchen")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except (KeyError, TypeError, ValueError) as exc:
            text = ohne_geheimnis(exc, "Wetterdienst hat unerwartet geantwortet")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        try:
            anzeige = self._formatiere(platz, daten)
        except (KeyError, TypeError, ValueError, IndexError) as exc:
            text = ohne_geheimnis(exc, "Wetterdaten unvollstaendig")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        self._merken(ort, tage, platz, anzeige)
        return ToolResult(
            ok=True,
            data={"ort": platz.get("name"), "land": platz.get("country_code"),
                  "latitude": platz.get("latitude"), "longitude": platz.get("longitude"),
                  "aktuell": daten.get("current"), "tage": daten.get("daily"),
                  "cache": False},
            display=anzeige,
            sources=[QUELLE],
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )

    # --- Text -----------------------------------------------------------

    @staticmethod
    def _formatiere(platz: dict[str, Any], daten: dict[str, Any]) -> str:
        wo = platz.get("name", "?")
        region = ", ".join(x for x in (platz.get("country_code"), platz.get("admin1")) if x)
        zeilen = []
        jetzt = daten.get("current") or {}
        if jetzt:
            zeilen.append(f"{wo} ({region}): jetzt {_de(jetzt.get('temperature_2m'))} °C, "
                          f"{wetter_text(jetzt.get('weather_code'))}.")
        else:
            zeilen.append(f"{wo} ({region}):")
        tag = daten.get("daily") or {}
        namen = ["Heute", "Morgen", "Uebermorgen"]
        for i, datum in enumerate(tag.get("time") or []):
            zeilen.append(
                f"{namen[i] if i < len(namen) else datum} ({_tag(datum)}): "
                f"{_de(tag['temperature_2m_min'][i])} bis {_de(tag['temperature_2m_max'][i])} °C, "
                f"{wetter_text(tag['weather_code'][i])}, "
                f"Regen {_de(tag['precipitation_sum'][i], 1)} mm "
                f"(Wahrscheinlichkeit {_de(tag['precipitation_probability_max'][i])} %), "
                f"Wind bis {_de(tag['wind_speed_10m_max'][i])} km/h, "
                f"Sonne {_uhr(tag['sunrise'][i])} bis {_uhr(tag['sunset'][i])}."
            )
        stand = datetime.now().astimezone().strftime("%d.%m.%Y %H:%M")
        zeilen.append(f"Quelle: Open-Meteo, Stand {stand}.")
        return "\n".join(zeilen)

    # --- Cache (Tabelle lookups, wie die Wissensquellen) ------------------

    def _aus_cache(self, ort: str, tage: int) -> str | None:
        if not self.db_path:
            return None
        from core.wissen import aus_cache

        treffer = aus_cache(self.db_path, f"{ort.lower()}|{tage}", "wetter",
                            max_alter_stunden=self.cache_stunden)
        return treffer.text if treffer else None

    def _merken(self, ort: str, tage: int, platz: dict[str, Any], text: str) -> None:
        if not self.db_path:
            return
        from core.wissen import Wissen, in_cache

        try:
            in_cache(self.db_path, Wissen(begriff=f"{ort.lower()}|{tage}",
                                          titel=str(platz.get("name") or ort),
                                          text=text, quelle="wetter", url=QUELLE))
        except Exception:  # noqa: BLE001 - der Cache ist Beiwerk
            log.exception("wetter: Cache nicht geschrieben")
