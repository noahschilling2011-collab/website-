"""Werkzeuge des Satellite Agents (Phase 8).

Alles hier ist READ. Der Agent liest oeffentliche Daten und behauptet nichts,
was seine Bodenaufloesung nicht hergibt.

**Nicht gebaut:** ein Geocoder. Die Werkzeuge nehmen eine Bounding Box in
Grad, keinen Ortsnamen. Einen Ortsnamen in Koordinaten aufzuloesen ist ein
eigener Dienst mit eigenen Nutzungsbedingungen; ihn aus dem Gedaechtnis zu
erfinden waere genau der Fehler, den Regel 1 verbietet.
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

from core.contracts import Permission, Tool, ToolResult
from core.satellite.analysis import grenzsatz, vergleichbar, vergleiche_raster
from core.satellite.cdse import CDSEFehler, CDSEProvider
from core.tools.registry import register

BBOX_SCHEMA = {
    "type": "array",
    "description": (
        "Bounding Box in Grad: [min_lon, min_lat, max_lon, max_lat]. "
        "Ortsnamen kann ich nicht aufloesen - gib Koordinaten."
    ),
    "items": {"type": "number"},
}


def _bbox(werte) -> tuple[float, float, float, float]:
    if not isinstance(werte, list) or len(werte) != 4:
        raise ValueError("bbox braucht genau vier Zahlen.")
    min_lon, min_lat, max_lon, max_lat = (float(w) for w in werte)
    if not (-180 <= min_lon < max_lon <= 180 and -90 <= min_lat < max_lat <= 90):
        raise ValueError(
            "bbox ist ungueltig: erwartet [min_lon, min_lat, max_lon, max_lat] "
            "mit min < max."
        )
    return (min_lon, min_lat, max_lon, max_lat)


@register
class SatelliteSearch(Tool):
    name = "satellite_search"
    description = (
        "Sucht das juengste wolkenarme Sentinel-2-Bild fuer eine Bounding Box. "
        "WICHTIG: 'aktuell' heisst das juengste Bild unter dem Wolken-"
        "Schwellwert im Suchfenster - es gibt keine Live-Bilder. Sentinel-2 "
        "ueberfliegt einen Ort etwa alle 3 bis 5 Tage, und ein Teil der "
        "Aufnahmen ist bewoelkt. Die Bodenaufloesung ist 10 m je Pixel; "
        "Objekte unter etwa 30 m sind damit nicht beurteilbar."
    )
    parameters = {
        "type": "object",
        "properties": {
            "bbox": BBOX_SCHEMA,
            "days_back": {
                "type": "integer",
                "description": "Wie weit zurueck gesucht wird, 1 bis 365.",
                "minimum": 1,
                "maximum": 365,
            },
            "max_cloud_pct": {
                "type": "number",
                "description": "Hoechster erlaubter Wolkenanteil in Prozent.",
                "minimum": 0,
                "maximum": 100,
            },
        },
        "required": ["bbox"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 60

    provider: CDSEProvider | None = None

    async def execute(
        self, bbox, days_back: int = 30, max_cloud_pct: float = 20.0
    ) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            box = _bbox(bbox)
        except ValueError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        if self.provider is None or not self.provider.eingerichtet:
            return ToolResult(
                ok=False,
                error="CDSE nicht eingerichtet.",
                display=(
                    "Satellitensuche nicht eingerichtet: CDSE_CLIENT_ID und "
                    "CDSE_CLIENT_SECRET fehlen in der .env. Ein Konto gibt es "
                    "kostenlos auf dataspace.copernicus.eu."
                ),
                duration_ms=dauer(),
            )

        ende = datetime.now(timezone.utc)
        start = ende - timedelta(days=days_back)
        try:
            szenen = await self.provider.search(
                box, start, ende, max_cloud_pct=max_cloud_pct
            )
        except CDSEFehler as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        if not szenen:
            # DoD 2: sagen, dass nichts da ist - und nicht ersatzweise ein
            # wolkiges Bild ohne Hinweis liefern.
            return ToolResult(
                ok=True,
                data={"scenes": [], "max_cloud_pct": max_cloud_pct,
                      "days_back": days_back},
                display=(
                    f"Kein Sentinel-2-Bild unter {max_cloud_pct:.0f} % Wolken in "
                    f"den letzten {days_back} Tagen fuer diesen Ausschnitt.\n\n"
                    "Das ist kein Fehler: Sentinel-2 ueberfliegt einen Ort alle "
                    "3 bis 5 Tage, und in Mitteleuropa ist ein grosser Teil der "
                    "Aufnahmen bewoelkt. Moeglichkeiten: Suchfenster "
                    "vergroessern oder den Wolken-Schwellwert anheben - dann "
                    "aber mit dem Hinweis, dass das Bild bewoelkt ist."
                ),
                duration_ms=dauer(),
            )

        zeilen = [s.steckbrief() for s in szenen[:5]]
        return ToolResult(
            ok=True,
            data={"scenes": [s.als_dict() for s in szenen[:5]]},
            display=(
                f"{len(szenen)} Szene(n) gefunden, juengste zuerst:\n\n"
                + "\n\n".join(zeilen)
                + f"\n\n{grenzsatz(szenen[0].resolution_m)}"
            ),
            sources=["https://dataspace.copernicus.eu/"],
            duration_ms=dauer(),
        )


@register
class SatelliteCompare(Tool):
    name = "satellite_compare"
    description = (
        "Vergleicht zwei Vegetationsraster (NDVI) desselben Ausschnitts "
        "numerisch und meldet, auf wie vielen Hektar sich etwas geaendert hat. "
        "Rechnet erst und interpretiert danach - nie umgekehrt. Lehnt den "
        "Vergleich ab, wenn die Aufnahmen zu weit im Jahreslauf "
        "auseinanderliegen: was man dann sieht, ist die Jahreszeit."
    )
    parameters = {
        "type": "object",
        "properties": {
            "before": {"type": "array", "items": {"type": "number"},
                       "description": "NDVI-Werte der aelteren Aufnahme."},
            "after": {"type": "array", "items": {"type": "number"},
                      "description": "NDVI-Werte der juengeren Aufnahme."},
            "before_date": {"type": "string", "description": "ISO-Datum, aeltere Aufnahme."},
            "after_date": {"type": "string", "description": "ISO-Datum, juengere Aufnahme."},
            "before_cloud_pct": {"type": "number", "minimum": 0, "maximum": 100},
            "after_cloud_pct": {"type": "number", "minimum": 0, "maximum": 100},
            "resolution_m": {"type": "number", "description": "Meter je Pixel.",
                             "minimum": 0.1},
        },
        "required": ["before", "after", "before_date", "after_date"],
        "additionalProperties": False,
    }
    permission = Permission.READ

    async def execute(
        self,
        before: list[float],
        after: list[float],
        before_date: str,
        after_date: str,
        before_cloud_pct: float = 0.0,
        after_cloud_pct: float = 0.0,
        resolution_m: float = 10.0,
    ) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            a = datetime.fromisoformat(before_date.replace("Z", "+00:00"))
            b = datetime.fromisoformat(after_date.replace("Z", "+00:00"))
        except ValueError as exc:
            return ToolResult(ok=False, error=f"Datum unlesbar: {exc}",
                              display=f"Datum unlesbar: {exc}", duration_ms=dauer())

        passt, grund = vergleichbar(a, b, before_cloud_pct, after_cloud_pct)
        if not passt:
            # Melden, nicht rechnen (A.5, Schritt 2).
            return ToolResult(ok=False, error=grund, display=grund,
                              duration_ms=dauer())

        try:
            ergebnis = vergleiche_raster(
                list(before), list(after), aufloesung_m=resolution_m
            )
        except ValueError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        richtung = "Rueckgang" if ergebnis.mittlere_aenderung < 0 else "Zunahme"
        return ToolResult(
            ok=True,
            data=ergebnis.als_dict(),
            display=(
                f"NDVI-{richtung} ueber dem Schwellwert auf "
                f"{ergebnis.hektar:.2f} ha ({ergebnis.veraendert_pixel} von "
                f"{ergebnis.pixel} Pixeln).\n"
                f"Mittlere Aenderung {ergebnis.mittlere_aenderung:+.3f}, "
                f"groesste Abnahme {ergebnis.groesste_abnahme:+.3f}, "
                f"groesste Zunahme {ergebnis.groesste_zunahme:+.3f}.\n"
                f"{grenzsatz(resolution_m)}"
            ),
            duration_ms=dauer(),
        )
