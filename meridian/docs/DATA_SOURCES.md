# Datenquellen & externe APIs

Meridian braucht **keine** eigenen Kartendaten, um zu starten — alles Nötige gibt es
offen. Diese Seite listet je Funktion die empfohlene Quelle, Lizenz und **wie sie
eingebunden wird**. Proprietäre Optionen sind als Upgrade markiert.

> Prinzip: Jede Quelle sitzt hinter einem **Adapter** im Gateway
> (`services/gateway/src/services/*`). Ein Umschalten der Quelle ändert nur den
> Adapter, nie die API zum Client.

## 1. Basiskarte & Vektorkacheln
- **OpenStreetMap** (Rohdaten, Lizenz ODbL). Bezug: regionale/planet Extrakte von
  **Geofabrik** (`download.geofabrik.de`) als `.osm.pbf`.
- **Vektorkacheln erzeugen:** [Planetiler](https://github.com/onthegomap/planetiler)
  oder [OpenMapTiles](https://openmaptiles.org) → `.mbtiles`/`.pmtiles`.
  ```bash
  java -Xmx8g -jar planetiler.jar --download --area=germany --output=germany.pmtiles
  ```
- **Servieren:** [Martin](https://martin.maplibre.org) (Postgres/PMTiles) oder
  TileServer-GL. Client bezieht Kacheln direkt vom CDN.

## 2. Satellitenansicht (Upgrade / offen)
- **Offen:** **Sentinel-2** (ESA, Copernicus, kostenlos) über AWS Open Data oder
  Sentinel Hub; Auflösung 10 m.
- **Kommerziell:** Esri World Imagery, MapTiler Satellite, Mapbox Satellite,
  Bing Maps Imagery, Maxar/Planet (0,3–0,5 m).
- **Einbindung:** Als Raster-Source im MapLibre-Style (`type: raster`,
  `tiles: [...]`), Layer-Umschalter im Client. Adapter cached & proxied Tiles.

## 3. Street-View-ähnliche Ansicht
- **Mapillary** (offen, crowdgesourct, viele Millionen Bilder). Kostenlose API mit
  Token. Bilder + Sequenzen + Detektionen (Schilder!).
- **Einbindung:** Mapillary JS Viewer im Client; Positions-Overlay auf der Karte.
  Alternative offene Quelle: **KartaView**. Kommerziell: Google Street View
  (Streetview Static/Embed), Cyclomedia.

## 4. Routing (Auto/Rad/Fuß)
- **Valhalla** (selbst gehostet, Open Source) — Tiles aus OSM `.pbf` bauen:
  ```bash
  valhalla_build_config --mjolnir-tile-dir /tiles > valhalla.json
  valhalla_build_tiles -c valhalla.json germany.osm.pbf
  ```
- Alternativen: **OSRM** (schnellstes Auto-Routing), **GraphHopper**.
- **Einbindung:** `services/gateway/src/services/valhalla.ts` (HTTP `/route`,
  `/trace_attributes`, `/isochrone`, `/sources_to_targets`).

## 5. ÖPNV (Transit)
- **GTFS** (Fahrpläne) + **GTFS-Realtime** (Verspätungen). Öffentliche Feeds:
  Deutschland **gtfs.de** / **DELFI**, Europa **Transitous**, weltweit
  **Mobility Database** (`database.mobilitydata.org`), TransitLand.
- **Routing:** **OpenTripPlanner 2** aus OSM + GTFS(-RT), oder Valhalla-`multimodal`.
- **Einbindung:** OTP-Adapter; GTFS-RT-Ingest aktualisiert Verspätungen.

## 6. Echtzeit-Verkehr, Staus, Baustellen, Unfälle
Eigene Daten fehlen anfangs → drei kombinierbare Wege:
1. **Offene Behördenfeeds:** Deutschland **MDM** (Mobilitäts Daten Marktplatz,
   `mdm-portal.de`) — Baustellen/Verkehrslagen als DATEX II; viele Städte per
   511/DATEX II/Open Data.
2. **Kommerzielle APIs (Upgrade):** **TomTom Traffic** (Flow + Incidents),
   **HERE Traffic**, **Google Roads/Routes** (Traffic-aware). Reines HTTP,
   Bounding-Box/Tile-basiert.
3. **Eigenes Floating-Car-Data:** Anonyme, differential-private Sonden der eigenen
   Nutzer (opt-in) → Map-Matching → Kanten-Geschwindigkeiten.
- **Einbindung:** `traffic-ingest` normalisiert alle Feeds nach OSM-Kanten,
  schreibt TimescaleDB und speist Valhalla-Traffic-Tiles + Incident-Layer.

## 7. POIs: Tankstellen, Restaurants, Hotels, Ladesäulen
- **OSM/Overpass** für Tankstellen (`amenity=fuel`), Restaurants
  (`amenity=restaurant`), Hotels (`tourism=hotel`) usw.
- **Ladesäulen:** **Open Charge Map** (offene API, weltweit) — Live-Verfügbarkeit
  teils über **OCPI**-Feeds der Betreiber.
- **Preise:** Tankstellen DE über **Tankerkönig** (MTS-K); Ladepreise via CPO/OCPI.
- **Einbindung:** `poi.ts` — Korridor-Suche entlang der Route (Buffer um Polyline).

## 8. Wetter auf der Strecke
- **Open-Meteo** (offen, kostenlos, keine Key-Pflicht) — Punktprognosen.
  Alternativen: OpenWeatherMap, MET Norway, DWD (Deutschland).
- **Einbindung:** `weather.ts` — Polyline in Zeit-/Distanzintervalle sampeln,
  je Punkt Prognose zur voraussichtlichen Ankunftszeit abrufen.

## 9. Tempolimits & Warnungen
- **OSM `maxspeed`** (+ `maxspeed:conditional`); Valhalla liefert je Kante das
  Limit über `trace_attributes`. Radar/Blitzer: rechtlich je Land prüfen (in DE
  Warn-Apps während der Fahrt verboten) → nur statische Gefahrenstellen.

## 10. Adresssuche / Geocoding
- **Photon** (Autocomplete) + **Nominatim** (strukturiert), beide OSM-basiert,
  selbst hostbar. Upgrade: Pelias, Mapbox/Google Geocoding.

## 11. Höhen / 3D-Gelände
- **Terrain:** Copernicus DEM / SRTM / Mapzen Terrarium-Tiles (offen) →
  MapLibre `terrain`/`hillshade`.
- **Gebäudehöhen:** OSM `height`/`building:levels`; realistisch: Google
  Photorealistic 3D Tiles (3D Tiles/Cesium) oder eigene Photogrammetrie.

## Lizenz-Hinweise
OSM = **ODbL** (Namensnennung „© OpenStreetMap-Mitwirkende“ + Share-Alike auf
abgeleitete Datenbanken). Sentinel = frei mit Attribution. Mapillary/OCM = eigene,
i. d. R. großzügige Lizenzen. Kommerzielle APIs unterliegen ihren Nutzungsbedingungen
(Caching-/Anzeige-Restriktionen beachten).
