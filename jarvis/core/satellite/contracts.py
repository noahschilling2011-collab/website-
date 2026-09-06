"""Die Szene (docs/satellite.md, A.4).

Zwei Felder sind **Pflicht**, nicht optional: `resolution_m` und
`attribution`. Eine Szene ohne beides ist ungueltig und wird verworfen.

Der Grund steht in A.1: ein Agent, der bei 10 m/px "neues Gebaeude" behauptet,
halluziniert. Die Bodenaufloesung muss deshalb bei jeder Aussage mitlaufen -
und ohne Attribution darf ein Copernicus-Bild gar nicht angezeigt werden.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


class SzeneUngueltig(ValueError):
    pass


@dataclass(frozen=True)
class Scene:
    scene_id: str
    provider: str
    sensor: str                              # "Sentinel-2 MSI L2A"
    acquired_at: datetime                    # UTC, Aufnahmezeit - nicht Abrufzeit
    cloud_cover_pct: float
    resolution_m: float                      # Meter je Pixel - Pflichtfeld
    bbox: tuple[float, float, float, float]  # min_lon, min_lat, max_lon, max_lat
    preview_url: str | None
    attribution: str                         # Pflichtfeld, nicht optional
    license: str

    def __post_init__(self) -> None:
        if not self.scene_id or not self.sensor:
            raise SzeneUngueltig("Szene ohne ID oder Sensor.")
        if not self.resolution_m or self.resolution_m <= 0:
            raise SzeneUngueltig(
                f"Szene {self.scene_id!r} ohne Bodenaufloesung. Ohne m/px laesst "
                "sich nicht sagen, was auf dem Bild ueberhaupt beurteilbar ist."
            )
        if not self.attribution.strip():
            raise SzeneUngueltig(
                f"Szene {self.scene_id!r} ohne Attribution. Copernicus-Daten "
                "haben Attributionspflichten - ohne den Text darf das Bild "
                "nicht angezeigt werden."
            )
        if not 0.0 <= self.cloud_cover_pct <= 100.0:
            raise SzeneUngueltig(
                f"Wolkenanteil {self.cloud_cover_pct} liegt ausserhalb 0..100."
            )
        if self.acquired_at.tzinfo is None:
            raise SzeneUngueltig("acquired_at braucht eine Zeitzone (UTC).")

    @property
    def alter_tage(self) -> float:
        return (datetime.now(timezone.utc) - self.acquired_at).total_seconds() / 86400

    def als_dict(self) -> dict:
        return {
            "scene_id": self.scene_id,
            "provider": self.provider,
            "sensor": self.sensor,
            "acquired_at": self.acquired_at.isoformat(),
            "cloud_cover_pct": round(self.cloud_cover_pct, 2),
            "resolution_m": self.resolution_m,
            "bbox": list(self.bbox),
            "preview_url": self.preview_url,
            "attribution": self.attribution,
            "license": self.license,
            "age_days": round(self.alter_tage, 1),
        }

    def steckbrief(self) -> str:
        """Die Zeile, die unter jedem Bild stehen muss."""
        return (
            f"{self.sensor}, {self.resolution_m:g} m/px, aufgenommen "
            f"{self.acquired_at.strftime('%Y-%m-%d %H:%M UTC')} "
            f"({self.cloud_cover_pct:.0f} % Wolken, vor {self.alter_tage:.0f} Tagen)\n"
            f"{self.attribution}"
        )
