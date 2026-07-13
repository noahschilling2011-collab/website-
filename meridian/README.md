# Meridian — Offene Karten- & Navigationsplattform

> Eine vollständige, selbst-hostbare Alternative zu Apple Karten und Google Maps —
> aufgebaut auf offenen Daten (OpenStreetMap), offenem Rendering (MapLibre) und
> moderner KI für Routenplanung, Suche und Sprachsteuerung.

Meridian ist bewusst **daten- und anbieterunabhängig** entworfen: Alle Kernfunktionen
(Karte, Routing, Suche, Offline) laufen ohne einen einzigen proprietären Dienst.
Wo eigene Daten (noch) fehlen — z. B. Echtzeitverkehr oder Satellitenbilder —
dokumentieren wir konkrete, einbindbare Datenquellen und APIs (siehe
[`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md)).

---

## Funktionsumfang

| Bereich | Umsetzung in Meridian |
| --- | --- |
| Eigene interaktive Weltkarte | MapLibre GL + Vektorkacheln aus OpenStreetMap (OpenMapTiles/Planetiler) |
| Extrem präzises GPS | Client-Sensorfusion + Map-Matching (Valhalla `trace_attributes`), SBAS/RTK-fähig |
| KI-Routenplanung (Auto/Rad/Fuß/ÖPNV) | Valhalla (multimodal) + OpenTripPlanner (GTFS) + KI-Reranking |
| Echtzeit-Verkehr, Staus, Baustellen, Unfälle | Ingest-Pipeline für TomTom/HERE/MDM + eigenes Floating-Car-Data |
| 3D-Städte & realistische Gebäude | OSM `building`+`height` Extrusion, optional Google Photorealistic 3D Tiles |
| Satellitenansicht | Esri World Imagery / Sentinel-2 / MapTiler Satellite (Layer-Umschalter) |
| Street-View-ähnlich | Mapillary (offene, crowdgesourcte Straßenbilder) |
| Offline-Karten | PMTiles/MBTiles-Regionen, MapLibre Offline, Routing-Tiles lokal |
| Sprachsteuerung & -führung | STT (Whisper) → NLU (LLM) → Intent; TTS-Ansagen |
| KI wählt schnellste/angenehmste Route | Learned-Ranking + LLM-Erklärung (`ai-router`) |
| Live-Ankunftszeiten | ETA-Modell auf Verkehrs-Zeitreihen (TimescaleDB) |
| Tankstellen/Restaurants/Hotels/Ladesäulen an der Route | Overpass-POIs + Open Charge Map, Korridor-Suche |
| Wetter auf der Strecke | Open-Meteo Sampling entlang der Polyline |
| Tempolimits & Warnungen | OSM `maxspeed` + clientseitige Warnlogik |
| Favoriten & Sammlungen | PostGIS + geräteübergreifende Sync |
| Sync Smartphone/Tablet/PC | Konto-basiert, WebSocket + REST, Last-Writer-Wins/CRDT |
| Design auf Apple-Niveau | Design-Tokens, reduziertes UI, Dark/Light, Haptik |
| Hohe Datenschutzstandards | On-Device-first, E2E für Privatdaten, DSGVO, Differential Privacy |

## Monorepo-Struktur

```
meridian/
├── apps/
│   ├── web/                # React + Vite + MapLibre GL (Karten-Frontend)
│   └── mobile/             # Flutter/React-Native (MapLibre Native) — Struktur & Plan
├── services/
│   └── gateway/            # API-Gateway (Fastify/TS): Routing, Suche, KI, POI, Wetter …
├── packages/
│   └── shared/             # Geteilte TypeScript-Typen & Utilities
├── db/
│   └── migrations/         # PostGIS-Schema (SQL)
├── infra/
│   └── k8s/                # Kubernetes-Manifeste
├── docs/                   # Architektur, Datenquellen, DB, API, Security, Scaling, Roadmap, KI
└── docker-compose.yml      # Lokale Umgebung: Gateway, Postgres/PostGIS, Redis, Valhalla, Photon, Martin
```

## Schnellstart (lokal)

```bash
# 1. Umgebung starten (DB, Cache, Routing, Geocoding, Tile-Server, Gateway)
cd meridian
cp services/gateway/.env.example services/gateway/.env
docker compose up --build

# 2. Web-App
cd apps/web
npm install
npm run dev            # http://localhost:5173  (spricht mit Gateway auf :8090)
```

Das Gateway läuft **auch ohne** externe Routing/Geocoding-Dienste: Fehlt Valhalla
oder Photon, liefern die Services deterministische Fallback-Daten (Luftlinie,
Demo-POIs), sodass die App sofort startklar ist. Für Produktionsdaten die in
[`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md) beschriebenen Extrakte laden.

## Dokumentation

- [Architektur](docs/ARCHITECTURE.md) · [Datenquellen & APIs](docs/DATA_SOURCES.md)
- [Datenbank](docs/DATABASE.md) · [API](docs/API.md) · [KI-Module](docs/AI.md)
- [Sicherheit & Datenschutz](docs/SECURITY.md) · [Skalierung](docs/SCALING.md)
- [Entwicklungsplan v1.0 → v10.0](docs/ROADMAP.md)

## Lizenz & Datenlizenzen

Code: MIT. Kartendaten: © OpenStreetMap-Mitwirkende (ODbL) — Namensnennung
erforderlich. Weitere Quellen mit ihren jeweiligen Lizenzen in `docs/DATA_SOURCES.md`.
