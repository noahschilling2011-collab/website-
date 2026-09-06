# ANHANG A — SATELLITE INTELLIGENCE AGENT (korrigierte Spezifikation)

## A.1 Was der alte Prompt falsch annimmt

Der alte Abschnitt zeigt als Beispielausgabe:

> `BEOBACHTET: Neue Struktur auf Bild B sichtbar.` → `INTERPRETATION: Möglicherweise neu errichtetes Gebäude.`

Das geht mit frei verfügbaren Satellitendaten **in aller Regel nicht**. Grund:

| Quelle | Bodenauflösung | Ein Einfamilienhaus (~10 × 10 m) ist … |
|---|---|---|
| Sentinel-2 (optisch, RGB/NIR) | 10 m/px | **1 Pixel** |
| Landsat 8/9 (multispektral) | 30 m/px | ein Drittel Pixel |
| Landsat 8/9 (panchromatisch) | 15 m/px | unter einem Pixel |
| MODIS / VIIRS (NASA GIBS, tägl.) | 250 m – 1 km/px | unsichtbar |

Ein Fußballfeld (105 × 68 m) sind bei Sentinel-2 etwa **10 × 7 Pixel**. Gebäudeerkennung braucht sub-metrische Auflösung, und die ist kommerziell und teuer.

**Konsequenz für den Agent:** Er muss die Bodenauflösung bei jeder Aussage mitführen und Aussagen ablehnen, die unterhalb seiner Auflösung liegen. Das ist ein Feature, kein Mangel — ein Agent, der bei 10 m/px "neues Gebäude" behauptet, halluziniert.

**Was bei 10 m/px realistisch geht:**
Abholzung · Überschwemmungsflächen · große Baustellen und Erdbewegungen · Tagebau und Steinbrüche · Solarparks · landwirtschaftliche Veränderungen · Brandflächen · Schneebedeckung · Algenblüten · Gewässerstände · neue Straßentrassen.

**Was nicht geht:**
Einzelne Gebäude · Fahrzeuge · Personen · Objekte kleiner ~30 m · "Live"-Bilder · Bilder auf Zuruf für einen beliebigen Zeitpunkt.

## A.2 Der zweite Denkfehler: "aktuelles Satellitenbild"

Sentinel-2 hat eine Wiederholrate von etwa 3–5 Tagen. <cite index="3-1">Sentinel-2 liefert bei 10 m Auflösung eine Wiederkehrzeit von 3–5 Tagen</cite>. Dazu kommt Bewölkung: in Süddeutschland ist ein erheblicher Teil der Aufnahmen unbrauchbar.

"Aktuell" heißt in der Praxis: **das jüngste Bild unter einem Wolken-Schwellwert innerhalb eines Suchfensters**. Der Agent muss das so formulieren und nie den Eindruck von Echtzeit erwecken.

Ausnahme: NASA GIBS liefert tägliche MODIS/VIIRS-Übersichten <cite index="24-1">in Nahe-Echtzeit, etwa drei Stunden nach dem Überflug</cite> — aber bei 250 m bis 1 km Auflösung. Gut für Wetter, Rauch, Brände, Sturmsysteme. Nutzlos für "zeig mir meine Straße".

## A.3 Datenquellen

> **Stand prüfen.** Endpunkte, Auth-Verfahren und Kontingente ändern sich. Vor dem Schreiben von Integrationscode die aktuelle offizielle Doku öffnen. Keine Endpunkt-URLs aus dem Gedächtnis erfinden.

| Zweck | Quelle | Zugang | Anmerkung |
|---|---|---|---|
| Sentinel-1/2/3/5P Archiv + neue Aufnahmen | Copernicus Data Space Ecosystem (`dataspace.copernicus.eu`) | Registrierung, OAuth-Token; kostenlos mit Kontingent | <cite index="7-1">Alle Funktionen sind für allgemeine Nutzer kostenlos mit vordefinierten Kontingenten; für große Download-/Verarbeitungsmengen gelten kommerzielle Bedingungen</cite> |
| Katalogsuche (Szenen finden, Wolken filtern) | CDSE-Katalog | mehrere REST-Protokolle, u. a. STAC und OData | <cite index="9-1">Der Katalog lässt sich über vier verschiedene REST-Protokolle abfragen; Filter erlauben es, stark bewölkte Tage auszuschließen</cite> |
| Verarbeitung ohne Download | Sentinel Hub / openEO im CDSE | OAuth-Client | Für Web-Anzeige besser als GeoTIFFs von 700 MB herunterzuladen |
| Tägliche Übersichtsbilder, Nahe-Echtzeit | NASA GIBS (`gibs.earthdata.nasa.gov`) | **kein Key**, WMTS/WMS/TWMS | <cite index="22-1">GIBS bietet Zugang über WMTS, WMS, TWMS und GDAL; viele Produkte sind 3–5 Stunden nach der Beobachtung verfügbar</cite> |
| Aktive Brände | NASA FIRMS | <cite index="26-1">kostenloser MAP_KEY erforderlich</cite> | WMS-Layer für VIIRS/MODIS |
| Bahndaten (TLE/GP) | CelesTrak | öffentlich | Nutzungsregeln beachten, nicht im Sekundentakt pollen |
| Überflugberechnung | Python `skyfield` (nutzt `sgp4`) | Bibliothek | <cite index="17-1">`find_events(topos, t0, t1, altitude_degrees)` liefert Aufgangs-, Kulminations- und Untergangszeiten für Überflüge über einem Standort</cite> |
| Wetter/Bewölkung | Open-Meteo o. ä. | prüfen | Für die Frage "lohnt sich morgen ein Bild?" |

**Bahnmechanik nicht selbst rechnen.** <cite index="15-1">TLE-Daten sind zum Epochenzeitpunkt auf etwa einen Kilometer genau und verlieren danach schnell an Genauigkeit</cite> — deshalb TLEs regelmäßig neu holen und mit `skyfield` propagieren, nicht mit selbstgeschriebenen Kepler-Formeln.

**Attribution:** Copernicus-Daten haben Attributionspflichten in den Nutzungsbedingungen. Die konkrete geforderte Formulierung nachschlagen und im UI unter jedem Bild anzeigen.

## A.4 Provider-Interface

```python
@dataclass
class Scene:
    scene_id: str
    provider: str
    sensor: str                 # "Sentinel-2 MSI L2A"
    acquired_at: datetime       # UTC, Aufnahmezeit — nicht Abrufzeit
    cloud_cover_pct: float
    resolution_m: float         # Meter pro Pixel — Pflichtfeld
    bbox: tuple[float,float,float,float]
    preview_url: str | None
    attribution: str            # Pflichtfeld, nicht optional
    license: str


class SatelliteProvider(Protocol):
    name: str
    async def search(self, bbox, start: datetime, end: datetime,
                     max_cloud_pct: float = 20.0) -> list[Scene]: ...
    async def render(self, scene_id: str, bbox, bands: str = "TRUE_COLOR",
                     width: int = 1024) -> bytes: ...
    async def metadata(self, scene_id: str) -> dict: ...
```

Zwei Details, die in v1 fehlen und in der Praxis alles entscheiden:

- `resolution_m` und `attribution` sind **Pflichtfelder**. Eine `Scene` ohne beides ist ungültig und wird verworfen.
- `search` filtert nach Wolken **serverseitig**. Erst 200 Szenen holen und dann lokal filtern ist bei Kontingenten die falsche Reihenfolge.

## A.5 Change Detection — ehrlich implementiert

Nicht: "zwei Bilder ans Vision-Modell, frag was sich geändert hat." Das produziert selbstbewussten Unsinn.

Stattdessen:

1. **Geometrisch abgleichen.** Beide Szenen auf dieselbe Bounding Box und dasselbe Raster bringen. Ohne Ko-Registrierung vergleichst du Versatz, nicht Veränderung.
2. **Vergleichbarkeit prüfen.** Ähnlicher Sonnenstand, ähnliche Jahreszeit, beide unter dem Wolken-Schwellwert. Sommer vs. Winter ist kein Change, das ist Vegetation. Ist die Bedingung verletzt: melden, nicht rechnen.
3. **Numerisch rechnen, bevor ein Modell schaut.** NDVI-Differenz (Vegetation), NDWI (Wasser), NBR (Brandflächen) — das sind einfache Bandarithmetiken und liefern reproduzierbare Zahlen statt Sprachmodell-Meinungen.
4. **Erst dann das Vision-Modell**, und zwar mit hartem Kontext im Prompt: Sensor, m/px, beide Aufnahmedaten, Wolkenanteil, Bildausschnitt in km, und der expliziten Anweisung, keine Objekte unterhalb von etwa 3× der Bodenauflösung zu benennen.
5. **Ausgabeformat erzwingen:**

```
BEOBACHTET
  NDVI-Rückgang > 0.3 auf ca. 4,2 ha im nordwestlichen Bildviertel.
INTERPRETATION
  Vegetationsverlust. Kahlschlag, Ernte oder Trockenschaden — nicht unterscheidbar
  auf Basis dieser beiden Aufnahmen.
KONFIDENZ  mittel
GRUNDLAGE  Sentinel-2 L2A, 10 m/px, 2026-04-12 (2 % Wolken) vs. 2026-07-30 (4 % Wolken)
GRENZE     Objekte unter 30 m sind bei dieser Auflösung nicht beurteilbar.
```

Die Zeile `GRENZE` ist Pflicht. Sie ist der Unterschied zwischen einem Werkzeug und einem Bullshit-Generator.

## A.6 Grenzen des Agents

Der Satellite Agent hat `max_permission = READ`. Er darf ausschließlich öffentliche und autorisierte Datenquellen im Rahmen ihrer Nutzungsbedingungen abfragen.

Zusätzlich, und das fehlt im alten Prompt komplett: **Der Agent baut kein Überwachungswerkzeug.** Wiederholte, terminierte Beobachtung eines einzelnen privaten Grundstücks oder einer bestimmten Person ist kein Anwendungsfall, auch wenn die Daten öffentlich sind. Umweltmonitoring, Katastrophenlage, Landnutzung, Bildung: ja. Nachbarn beobachten: nein. Der Agent lehnt solche Anfragen ab und erklärt kurz warum.

Rate-Limits sind kein Vorschlag. Kontingent-Verbrauch wird pro Provider geloggt und im Dashboard angezeigt.
