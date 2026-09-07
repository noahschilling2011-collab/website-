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


# So lang darf ein Ortsname hoechstens sein - hin wie zurueck. Hin: ein
# 5.000 Zeichen langer Name aus dem Modell wuerde ungeprueft in die Abfrage
# wandern. Zurueck: der Name aus der fremden Antwort steht in `display` und
# geht damit ins Modell - gemessen kamen 200.000 Zeichen ungekuerzt an.
# Dieselbe Zahl wie in core/orte.py.
ORT_MAX = 120

# Mehr Tage, als angefragt wurden, werden nicht ausgegeben. Open-Meteo
# haelt sich an `forecast_days`, aber `display` ist genau der Text, der ins
# Modell geht: eine Antwort mit 50.000 Tagen ergab 5,9 MB Bericht.
TAGE_MAX = 3


def _objekt(wert: Any) -> dict[str, Any]:
    """Nur ein Objekt ist ein Objekt. Alles andere wird zu {}.

    Gemessen: eine Antwort, die eine JSON-Liste statt eines Objekts
    schickte, liess `.get()` mit AttributeError fliegen - und AttributeError
    faengt hier niemand ab.
    """
    return wert if isinstance(wert, dict) else {}


def _liste(wert: Any) -> list[Any]:
    return wert if isinstance(wert, list) else []


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
    # Ortsname und Region kommen aus der Geokodierung eines fremden
    # Dienstes und stehen unveraendert im Bericht.
    fremder_text = True

    # Werden beim App-Start gesetzt (api/app.py), nicht importiert.
    standard_ort: str = ""
    db_path: Path | str = ""
    timeout_s: float = 10.0
    cache_stunden: float = 1.0
    transport: httpx.AsyncBaseTransport | None = None

    async def execute(self, ort: str | None = None, tage: int | None = None) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        # `str(...)`, nicht `ort or ...`: kommt eine Zahl statt eines Namens
        # an, flog hier bisher AttributeError ('int' has no 'strip') roh nach
        # oben. Der Dispatcher prueft das Schema zwar - aber das Werkzeug
        # soll auch ohne ihn nicht platzen.
        ort = (str(ort if ort is not None else "").strip()
               or str(self.standard_ort or "").strip())
        if not ort:
            hinweis = ("Kein Ort angegeben, und JARVIS_ORT ist leer. Nenn einen Ort "
                       "oder trag JARVIS_ORT in die .env ein.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)
        if len(ort) > ORT_MAX:
            hinweis = "Der Ortsname ist unsinnig lang. Nenn nur den Ort."
            return ToolResult(ok=False, error=hinweis, display=hinweis,
                              duration_ms=dauer())
        try:
            tage = int(tage) if tage is not None else 2
        except (TypeError, ValueError):
            tage = 2
        tage = max(1, min(TAGE_MAX, tage))

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
                treffer = _liste(_objekt(geo.json()).get("results"))
                if not treffer:
                    text = f"Den Ort {ort!r} kennt der Wetterdienst nicht."
                    return ToolResult(ok=False, error=text, display=text,
                                      duration_ms=int((time.monotonic() - begonnen) * 1000))
                platz = _objekt(treffer[0])
                antwort = await client.get(VORHERSAGE_URL, params={
                    "latitude": platz["latitude"], "longitude": platz["longitude"],
                    "current": "temperature_2m,weather_code",
                    "daily": ("temperature_2m_max,temperature_2m_min,precipitation_sum,"
                              "precipitation_probability_max,weather_code,"
                              "wind_speed_10m_max,sunrise,sunset"),
                    "timezone": "auto", "forecast_days": tage})
                antwort.raise_for_status()
                daten = _objekt(antwort.json())
        except httpx.HTTPError as exc:
            text = ohne_geheimnis(exc, "Wetterdienst nicht erreichbar",
                                  "Spaeter noch einmal versuchen")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        except (KeyError, TypeError, ValueError) as exc:
            text = ohne_geheimnis(exc, "Wetterdienst hat unerwartet geantwortet")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=int((time.monotonic() - begonnen) * 1000))

        jetzt = _objekt(daten.get("current"))
        vorhersage = self._nur_angefragte_tage(daten, tage)
        if not jetzt and not vorhersage.get("time"):
            # Weder ein Jetzt noch ein Morgen: das ist kein Bericht, sondern
            # eine leere Antwort. Bisher kam sie als ok=True heraus, mit dem
            # Ortsnamen und sonst nichts.
            text = ("Der Wetterdienst hat zu diesem Ort keine Wetterdaten "
                    "geliefert. Spaeter noch einmal versuchen.")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=dauer())

        try:
            anzeige = self._formatiere(platz, jetzt, vorhersage)
        except (KeyError, TypeError, ValueError, IndexError) as exc:
            text = ohne_geheimnis(exc, "Wetterdaten unvollstaendig")
            return ToolResult(ok=False, error=text, display=text,
                              duration_ms=dauer())
        self._merken(ort, tage, platz, anzeige)
        return ToolResult(
            ok=True,
            data={"ort": self._name(platz), "land": platz.get("country_code"),
                  "latitude": platz.get("latitude"), "longitude": platz.get("longitude"),
                  "aktuell": jetzt or None, "tage": vorhersage or None,
                  "cache": False},
            display=anzeige,
            sources=[QUELLE],
            duration_ms=dauer(),
        )

    # --- Text -----------------------------------------------------------

    @staticmethod
    def _name(platz: dict[str, Any]) -> str:
        """Der Ortsname aus der fremden Antwort - gekuerzt.

        Er steht in `display` und geht damit woertlich ins Modell. Gemessen:
        ein Name mit 200.000 Zeichen kam ungekuerzt durch.
        """
        return str(platz.get("name") or "?")[:ORT_MAX]

    @staticmethod
    def _nur_angefragte_tage(daten: dict[str, Any], tage: int) -> dict[str, Any]:
        """Die Vorhersage auf so viele Tage kuerzen, wie angefragt wurden.

        `forecast_days` steht in der Anfrage; was darueber hinaus
        zurueckkommt, ist nicht bestellt. Gemessen: eine Antwort mit 50.000
        Tagen ergab einen Bericht von 5,9 MB - und `display` ist genau der
        Text, der ins Modell geht.
        """
        tag = _objekt(daten.get("daily"))
        return {schluessel: _liste(werte)[:tage] for schluessel, werte in tag.items()}

    @classmethod
    def _formatiere(cls, platz: dict[str, Any], jetzt: dict[str, Any],
                    tag: dict[str, Any]) -> str:
        wo = cls._name(platz)
        region = ", ".join(str(x)[:ORT_MAX] for x in
                           (platz.get("country_code"), platz.get("admin1")) if x)
        zeilen = []
        if jetzt:
            zeilen.append(f"{wo} ({region}): jetzt {_de(jetzt.get('temperature_2m'))} °C, "
                          f"{wetter_text(jetzt.get('weather_code'))}.")
        else:
            zeilen.append(f"{wo} ({region}):")
        namen = ["Heute", "Morgen", "Uebermorgen"]
        for i, datum in enumerate(_liste(tag.get("time"))):
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

        try:
            treffer = aus_cache(self.db_path, f"{ort.lower()}|{tage}", "wetter",
                                max_alter_stunden=self.cache_stunden)
        except Exception:  # noqa: BLE001 - der Cache ist Beiwerk, wie beim Schreiben
            # Gemessen: eine Datenbank, die es nicht gibt oder in der die
            # Tabelle fehlt, liess sqlite3.OperationalError roh nach oben
            # fliegen - und damit fiel der ganze Wetterbericht aus, obwohl
            # die Antwort aus dem Netz in Ordnung war. Beim SCHREIBEN war
            # das schon abgefangen, beim LESEN nicht.
            log.exception("wetter: Cache nicht gelesen")
            return None
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
