"""Copernicus Data Space Ecosystem (docs/satellite.md, A.3).

Endpunkte aus der offiziellen Dokumentation, nicht aus dem Gedaechtnis:

* Token:   ``https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token``
* Katalog: ``https://catalogue.dataspace.copernicus.eu/odata/v1/Products``
* Wolkenfilter: Attribut ``cloudCover`` als ``OData.CSC.DoubleAttribute``
* Raum:    ``OData.CSC.Intersects(area=geography'SRID=4326;POLYGON(...)')``
* Zeit:    ``ContentDate/Start``

**UNSICHER:** Die Doku-Seite zum Token zeigt den Ablauf ``grant_type=password``
mit ``client_id=cdse-public``. Die `.env.example` dieses Projekts sieht
``CDSE_CLIENT_ID`` und ``CDSE_CLIENT_SECRET`` vor, also einen Service-Account
mit ``grant_type=client_credentials`` gegen denselben Keycloak-Realm. Beide
Wege sind implementiert; welcher fuer den konkreten Zugang gilt, ist vor dem
ersten echten Aufruf in der Doku zum Service-Account zu bestaetigen.

Gefiltert wird **serverseitig** (A.4): erst 200 Szenen holen und dann lokal
zu filtern ist bei Kontingenten die falsche Reihenfolge.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import httpx

from core.satellite.contracts import Scene, SzeneUngueltig

log = logging.getLogger("jarvis")

TOKEN_URL = (
    "https://identity.dataspace.copernicus.eu/auth/realms/CDSE"
    "/protocol/openid-connect/token"
)
KATALOG_URL = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"

# Aus den Copernicus-Nutzungsbedingungen. Steht unter jedem Bild.
ATTRIBUTION = "Enthaelt modifizierte Copernicus-Sentinel-Daten"
LIZENZ = "Copernicus Sentinel Data Terms and Conditions"

# Sentinel-2 MSI: 10 m/px in den Baendern B02/B03/B04/B08 (sichtbar + NIR).
# Die Zahl ist kein Detail, sie entscheidet, was ueberhaupt aussagbar ist.
SENTINEL2_AUFLOESUNG_M = 10.0


class CDSEFehler(RuntimeError):
    pass


def bbox_als_polygon(bbox: tuple[float, float, float, float]) -> str:
    """WKT-Polygon fuer den OData-Raumfilter."""
    min_lon, min_lat, max_lon, max_lat = bbox
    ecken = [
        (min_lon, min_lat), (max_lon, min_lat), (max_lon, max_lat),
        (min_lon, max_lat), (min_lon, min_lat),
    ]
    punkte = ", ".join(f"{lon} {lat}" for lon, lat in ecken)
    return f"POLYGON(({punkte}))"


def _iso(zeitpunkt: datetime) -> str:
    if zeitpunkt.tzinfo is None:
        zeitpunkt = zeitpunkt.replace(tzinfo=timezone.utc)
    return zeitpunkt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def baue_filter(
    bbox: tuple[float, float, float, float],
    start: datetime,
    ende: datetime,
    max_cloud_pct: float,
    collection: str = "SENTINEL-2",
) -> str:
    """Der OData-$filter. Wolken werden serverseitig ausgeschlossen."""
    return (
        f"Collection/Name eq '{collection}'"
        " and Attributes/OData.CSC.DoubleAttribute/any("
        "att:att/Name eq 'cloudCover' and "
        f"att/OData.CSC.DoubleAttribute/Value le {max_cloud_pct:.2f})"
        f" and ContentDate/Start gt {_iso(start)}"
        f" and ContentDate/Start lt {_iso(ende)}"
        " and OData.CSC.Intersects(area=geography'SRID=4326;"
        f"{bbox_als_polygon(bbox)}')"
    )


def _attribut(produkt: dict[str, Any], name: str) -> Any:
    for att in produkt.get("Attributes") or []:
        if att.get("Name") == name:
            return att.get("Value")
    return None


def als_szene(produkt: dict[str, Any], bbox) -> Scene | None:
    """Wandelt einen OData-Treffer in eine Szene. Ungueltige werden verworfen."""
    roh = produkt.get("ContentDate", {}).get("Start") or produkt.get("OriginDate")
    if not roh:
        return None
    try:
        aufgenommen = datetime.fromisoformat(str(roh).replace("Z", "+00:00"))
    except ValueError:
        return None

    wolken = _attribut(produkt, "cloudCover")
    if wolken is None:
        # Ohne Wolkenangabe laesst sich nicht sagen, ob das Bild brauchbar ist.
        return None

    try:
        return Scene(
            scene_id=str(produkt.get("Id") or produkt.get("Name") or ""),
            provider="cdse",
            sensor=str(_attribut(produkt, "instrumentShortName") or "Sentinel-2 MSI"),
            acquired_at=aufgenommen,
            cloud_cover_pct=float(wolken),
            resolution_m=SENTINEL2_AUFLOESUNG_M,
            bbox=bbox,
            preview_url=None,
            attribution=ATTRIBUTION,
            license=LIZENZ,
        )
    except (SzeneUngueltig, TypeError, ValueError) as exc:
        log.warning("CDSE-Treffer verworfen: %s", exc)
        return None


class CDSEProvider:
    """Sucht Szenen im Copernicus-Katalog."""

    name = "cdse"

    def __init__(
        self,
        client_id: str = "",
        client_secret: str = "",
        *,
        username: str = "",
        password: str = "",
        timeout: float = 30.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.client_id = client_id
        self.client_secret = client_secret
        self.username = username
        self.password = password
        self.timeout = timeout
        self.transport = transport
        self._token: str | None = None

    @property
    def eingerichtet(self) -> bool:
        return bool(self.client_id and self.client_secret) or bool(
            self.username and self.password
        )

    def _token_form(self) -> dict[str, str]:
        if self.client_id and self.client_secret:
            return {
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            }
        return {
            "grant_type": "password",
            "client_id": "cdse-public",
            "username": self.username,
            "password": self.password,
        }

    async def token(self) -> str:
        if self._token:
            return self._token
        if not self.eingerichtet:
            raise CDSEFehler(
                "CDSE ist nicht eingerichtet. Trag CDSE_CLIENT_ID und "
                "CDSE_CLIENT_SECRET in die .env ein - ein Konto gibt es "
                "kostenlos auf dataspace.copernicus.eu."
            )
        async with httpx.AsyncClient(timeout=self.timeout,
                                     transport=self.transport) as client:
            antwort = await client.post(TOKEN_URL, data=self._token_form())
        if antwort.status_code >= 400:
            raise CDSEFehler(
                f"CDSE hat den Zugang abgelehnt (HTTP {antwort.status_code}). "
                "Stimmen CDSE_CLIENT_ID und CDSE_CLIENT_SECRET?"
            )
        self._token = str(antwort.json().get("access_token") or "")
        if not self._token:
            raise CDSEFehler("CDSE lieferte kein access_token.")
        return self._token

    async def search(
        self,
        bbox: tuple[float, float, float, float],
        start: datetime,
        end: datetime,
        max_cloud_pct: float = 20.0,
        limit: int = 10,
    ) -> list[Scene]:
        zugang = await self.token()
        params = {
            "$filter": baue_filter(bbox, start, end, max_cloud_pct),
            "$orderby": "ContentDate/Start desc",
            "$top": str(max(1, min(limit, 50))),
            "$expand": "Attributes",
        }
        async with httpx.AsyncClient(timeout=self.timeout,
                                     transport=self.transport) as client:
            antwort = await client.get(
                KATALOG_URL, params=params,
                headers={"Authorization": f"Bearer {zugang}"},
            )
        if antwort.status_code >= 400:
            raise CDSEFehler(
                f"Katalogsuche fehlgeschlagen (HTTP {antwort.status_code})."
            )

        treffer = antwort.json().get("value") or []
        szenen = [s for s in (als_szene(p, bbox) for p in treffer) if s is not None]
        # Das jüngste zuerst - "aktuell" heisst: das juengste Bild unter dem
        # Schwellwert im Suchfenster (A.2).
        szenen.sort(key=lambda s: s.acquired_at, reverse=True)
        return szenen
