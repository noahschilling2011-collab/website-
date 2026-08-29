"""Copernicus Data Space Ecosystem (docs/satellite.md, A.3).

Endpunkte aus der offiziellen Dokumentation, nicht aus dem Gedaechtnis:

* Token:   ``https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token``
* Katalog: ``https://catalogue.dataspace.copernicus.eu/odata/v1/Products``
* Wolkenfilter: Attribut ``cloudCover`` als ``OData.CSC.DoubleAttribute``
* Raum:    ``OData.CSC.Intersects(area=geography'SRID=4326;POLYGON(...)')``
* Zeit:    ``ContentDate/Start``

**Geklaert am 29.08.2026** (vorher stand hier UNSICHER): Es sind ZWEI
verschiedene Wege, nicht zwei Varianten desselben.

* ``grant_type=client_credentials`` mit einem im Sentinel-Hub-Dashboard
  angelegten OAuth-Client - das ist der Weg fuer die Process-API. Gemessen
  gegen den echten Endpunkt: mit erfundenen Zugangsdaten antwortet er
  ``invalid_client`` (HTTP 401), mit einem erfundenen grant_type dagegen
  ``unsupported_grant_type`` (HTTP 400). Der Unterschied ist der Beleg,
  dass client_credentials unterstuetzt wird.
* ``grant_type=password`` mit dem festen oeffentlichen Client
  ``cdse-public`` - das ist der Weg zum Herunterladen von Produkten aus
  dem OData-Katalog, mit Kontoname und Kontopasswort.

Sie sind nicht austauschbar: das client_secret funktioniert nicht mit
password, das Kontopasswort nicht mit client_credentials.

Gefiltert wird **serverseitig** (A.4): erst 200 Szenen holen und dann lokal
zu filtern ist bei Kontingenten die falsche Reihenfolge.
"""

from __future__ import annotations

import logging
import math
import time
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
# Am 29.08.2026 auf die dokumentierte NEUE Pfadform umgestellt. CDSE hat am
# 09.03.2026 angekuendigt (Rollout ab 17.03.2026): aus
# /api/<version>/<service> wird /<service>/<version>. Die Altform antwortet
# heute noch, ist aber fuer die Abkuendigung vorgemerkt - und ein Endpunkt,
# der irgendwann still verschwindet, ist genau die Art Zeitbombe, die man
# nicht in einem Projekt haben will, das nur gelegentlich laeuft.
#
# Selbst nachgemessen, nicht aus der Ankuendigung geschlossen:
#
#     POST /process/v1            -> 401   (geroutet, Token fehlt)
#     POST /api/v1/process        -> 401   (Altform, noch geroutet)
#     POST /statistics/v1         -> 401   (geroutet - die Statistical API)
#     POST /gibtesnicht/v9        -> 503   (nicht geroutet)
#
# Die 503 auf dem erfundenen Pfad ist der Beleg, dass die 401 etwas heisst:
# ohne sie koennte die 401 auch von einem Torwaechter vor dem Nichts kommen.
PROCESS_URL = "https://sh.dataspace.copernicus.eu/process/v1"

# Noch nicht benutzt, aber geroutet und im selben Kontingent: liefert
# Kennzahlen (min/max/mean/stDev/Histogramm) statt eines Rasters. Fuer
# `satellite_compare` reicht das NICHT - aus einem Mittelwert folgt nicht,
# WELCHE Flaeche sich veraendert hat. Steht hier, damit der Pfad beim
# naechsten Mal nicht wieder gesucht werden muss.
STATISTICS_URL = "https://sh.dataspace.copernicus.eu/statistics/v1"

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
        # Wann der zwischengespeicherte Token ungueltig wird (monotone Uhr).
        # 0.0 heisst: keiner da.
        self._token_bis: float = 0.0

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
        # Frueher stand hier `if self._token: return self._token` - ohne
        # jedes Ablaufdatum. Ein Keycloak-Token lebt nicht ewig: das
        # Beispiel-Token im CDSE-Beginners-Guide hat exp - iat = 600
        # Sekunden. Ein Server, der laenger laeuft als das, haette ab dann
        # bei JEDEM Bild eine 401 bekommen - und die Fehlermeldung unten
        # haette faelschlich nach falschen Zugangsdaten geklungen.
        #
        # Die Lebensdauer kommt aus `expires_in` der Antwort, nicht aus
        # einer geratenen Zahl. 60 Sekunden Sicherheitsabstand, damit ein
        # Token nicht mitten im Aufruf abläuft.
        if self._token and time.monotonic() < self._token_bis:
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
        nutzlast = antwort.json()
        self._token = str(nutzlast.get("access_token") or "")
        if not self._token:
            raise CDSEFehler("CDSE lieferte kein access_token.")
        try:
            lebt_s = float(nutzlast.get("expires_in") or 0)
        except (TypeError, ValueError):
            lebt_s = 0.0
        if lebt_s <= 0:
            # Fehlt `expires_in`, wird nicht gerechnet, sondern kurz
            # behalten. Ein Aufruf zu viel ist billiger als eine Stunde 401.
            self._token_bis = time.monotonic() + 30.0
        else:
            # 60 s Sicherheitsabstand, damit ein Token nicht mitten im
            # Aufruf abläuft - aber nie mehr als die Haelfte der Laufzeit.
            # Ohne diese zweite Haelfte waere ein kurzlebiger Token (60 s
            # oder weniger) sofort abgelaufen und wuerde bei JEDEM Aufruf
            # neu geholt. Genau das ist meine erste Fassung geworden, und
            # der Test hat es gefunden.
            self._token_bis = time.monotonic() + max(lebt_s - 60.0, lebt_s / 2)
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
        # KEIN Token an den Katalog. Gemessen am 29.08.2026 gegen den echten
        # Endpunkt, nicht aus der Doku geschlossen:
        #
        #   GET .../odata/v1/Products?$top=1  ohne Header        -> HTTP 200
        #   dieselbe URL mit "Authorization: Bearer nicht-echt"  -> HTTP 403
        #
        # Der Katalog ist offen. Ein Header, den er nicht akzeptiert, macht
        # aus einer funktionierenden Suche eine 403 - und die liest sich wie
        # "Kontingent erschoepft", ist aber ein selbstgemachter Fehler.
        # Der Token gehoert nur an die Process-API (sh.dataspace...), die
        # ihn wirklich verlangt. Ausserdem spart das den Token-Aufruf bei
        # jeder Suche: `satellite_search` laeuft damit auch dann, wenn gar
        # keine Zugangsdaten eingetragen sind.
        params = {
            "$filter": baue_filter(bbox, start, end, max_cloud_pct),
            "$orderby": "ContentDate/Start desc",
            "$top": str(max(1, min(limit, 50))),
            "$expand": "Attributes",
        }
        async with httpx.AsyncClient(timeout=self.timeout,
                                     transport=self.transport) as client:
            antwort = await client.get(KATALOG_URL, params=params)
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
