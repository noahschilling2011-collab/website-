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
import math
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

# Sentinel Hub Process API - der Dienst, der ein anzeigbares Bild liefert.
# Der Katalog oben liefert nur Metadaten; das war der Grund, warum
# `preview_url` bis hierher immer None war.
#
# Gemessen am 26.08.2026, nicht aus der Erinnerung. Beide Pfade sind
# geroutet, ein erfundener nicht:
#
#     POST /api/v1/process        -> 401   (existiert, Token fehlt)
#     POST /process/v1            -> 401   (existiert auch)
#     POST /gibtesnicht/quatsch   -> 503   (existiert nicht)
#
# Die 503 auf dem erfundenen Pfad ist der Beleg, dass die 401 etwas heisst.
PROCESS_URL = "https://sh.dataspace.copernicus.eu/api/v1/process"

# Echtfarbe aus den sichtbaren Baendern. Der Faktor 2.5 steht so im
# Beispiel der CDSE-Doku - Sentinel-2-Reflektanzen sind sonst sehr dunkel.
EVALSCRIPT_ECHTFARBE = (
    "//VERSION=3\n"
    "function setup() {\n"
    '  return { input: ["B02", "B03", "B04"], '
    'output: { bands: 3, sampleType: "AUTO" } }\n'
    "}\n"
    "function evaluatePixel(s) {\n"
    "  return [2.5 * s.B04, 2.5 * s.B03, 2.5 * s.B02]\n"
    "}"
)

# Sentinel Hub rechnet nach Flaeche ab (Processing Units). Ein 8000er-Bild
# waere ein Kontingent-Loch, das niemand bemerkt, bis der Monat leer ist.
MAX_KANTE_PX = 2500

# Aus den Copernicus-Nutzungsbedingungen. Steht unter jedem Bild.
ATTRIBUTION = "Enthaelt modifizierte Copernicus-Sentinel-Daten"
LIZENZ = "Copernicus Sentinel Data Terms and Conditions"

# Sentinel-2 MSI: 10 m/px in den Baendern B02/B03/B04/B08 (sichtbar + NIR).
# Die Zahl ist kein Detail, sie entscheidet, was ueberhaupt aussagbar ist.
SENTINEL2_AUFLOESUNG_M = 10.0

# Ein Grad Breite in Metern. Fuer die Laenge kommt der Kosinus der
# Breite dazu - siehe effektive_aufloesung_m.
GRAD_M = 111_320.0


class CDSEFehler(RuntimeError):
    pass


def effektive_aufloesung_m(
    bbox: tuple[float, float, float, float], breite: int, hoehe: int
) -> float:
    """Meter je Bildpixel - und zwar die WAHRE Zahl, nicht die des Sensors.

    Der Unterschied ist der ganze Punkt. Sentinel-2 liefert 10 m/px. Ein
    512-Pixel-Bild von ganz Deutschland hat rund 1,3 KILOMETER je Pixel -
    zwei Groessenordnungen daneben. Bis hierher stand ueberall die
    Konstante 10.0, unabhaengig vom Ausschnitt. Ein Agent, dem man das
    sagt, haelt sich fuer scharfsichtig und benennt Dinge, die auf dem
    Bild ein Zehntel Pixel gross sind - genau das, was `SATELLIT_PROMPT`
    als Halluzination verbietet.

    Die Breitengradstauchung geht mit ein: ein Grad Laenge ist bei 60 Grad
    Nord halb so lang wie am Aequator. Ohne den Kosinus liegt man in
    Nordeuropa um ein Drittel daneben.

    Nach unten gedeckelt auf die Sensoraufloesung: mehr Pixel erfinden
    keine Schaerfe.
    """
    min_lon, min_lat, max_lon, max_lat = bbox
    mitte = math.radians((min_lat + max_lat) / 2.0)
    breite_m = abs(max_lon - min_lon) * GRAD_M * math.cos(mitte)
    hoehe_m = abs(max_lat - min_lat) * GRAD_M
    je_pixel = max(
        breite_m / max(1, breite),
        hoehe_m / max(1, hoehe),
    )
    return max(SENTINEL2_AUFLOESUNG_M, je_pixel)


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

    async def render(
        self,
        bbox: tuple[float, float, float, float],
        von: str,
        bis: str,
        *,
        breite: int = 512,
        hoehe: int = 512,
    ) -> bytes:
        """Ein anzeigbares PNG aus der Sentinel Hub Process API.

        `von` und `bis` sind ISO-Zeitpunkte in UTC. Eng gewaehlt - am besten
        der Aufnahmetag der Szene, die `search` gefunden hat: dann zeigt das
        Bild genau diese Szene und nicht irgendeine aus dem Zeitraum.

        Bewusst KEIN `maxCloudCoverage` im dataFilter: gefiltert wird schon
        serverseitig im Katalog. Ein Feld, das ich nicht in einem
        ausgefuehrten Beispiel gesehen habe, kommt hier nicht rein.
        """
        zugang = await self.token()
        kante_b = max(1, min(breite, MAX_KANTE_PX))
        kante_h = max(1, min(hoehe, MAX_KANTE_PX))
        koerper = {
            "input": {
                "bounds": {
                    "properties": {
                        "crs": "http://www.opengis.net/def/crs/OGC/1.3/CRS84"
                    },
                    "bbox": list(bbox),
                },
                "data": [{
                    "type": "sentinel-2-l2a",
                    "dataFilter": {"timeRange": {"from": von, "to": bis}},
                }],
            },
            "output": {
                "width": kante_b,
                "height": kante_h,
                "responses": [
                    {"identifier": "default", "format": {"type": "image/png"}}
                ],
            },
            "evalscript": EVALSCRIPT_ECHTFARBE,
        }
        async with httpx.AsyncClient(timeout=self.timeout,
                                     transport=self.transport) as client:
            antwort = await client.post(
                PROCESS_URL, json=koerper,
                headers={"Authorization": f"Bearer {zugang}"},
            )
        if antwort.status_code >= 400:
            # Bewusst ohne den Antworttext: er kann die Anfrage spiegeln,
            # und in der steht nichts Geheimes - aber das Secret steckt im
            # Klienten, und eine Fehlermeldung ist der falsche Ort, um sich
            # darauf zu verlassen.
            raise CDSEFehler(
                f"Das Bild konnte nicht erzeugt werden "
                f"(HTTP {antwort.status_code}). Bei 403 ist meist das "
                f"Kontingent erschoepft (10.000 Processing Units je Monat)."
            )

        typ = antwort.headers.get("content-type", "")
        if not typ.startswith("image/"):
            # Sentinel Hub antwortet bei manchen Fehlern mit 200 und JSON.
            # Wer das als Bild ablegt, speichert eine kaputte Datei und
            # zeigt sie an.
            raise CDSEFehler(
                f"Die Antwort war kein Bild, sondern {typ!r}. "
                "Wahrscheinlich gibt es fuer diesen Ausschnitt und Zeitraum "
                "keine Aufnahme."
            )
        if not antwort.content:
            raise CDSEFehler("Die Antwort war ein leeres Bild.")
        return antwort.content

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
