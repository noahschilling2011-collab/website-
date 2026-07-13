# Meridian — Softwarearchitektur

## 1. Leitprinzipien

1. **Offene Daten zuerst.** Kern (Karte, Routing, Suche, Offline) funktioniert
   vollständig mit OpenStreetMap & offenen Formaten. Proprietäre Dienste sind
   optionale, austauschbare Adapter — nie ein harter Abhängigkeitspunkt.
2. **On-Device-first für Privatsphäre.** Standort, Suchverlauf und Favoriten
   werden möglichst lokal verarbeitet; Server sieht nur, was er braucht.
3. **Microservices hinter einem Gateway.** Jede Domäne (Routing, Suche, KI,
   Verkehr) skaliert unabhängig; das Gateway bündelt Auth, Rate-Limiting, Cache.
4. **Graceful Degradation.** Fällt ein Datendienst aus, liefert der Service
   einen sinnvollen Fallback statt eines Fehlers.
5. **Edge/CDN für alles Statische.** Kacheln, Styles, PMTiles über CDN.

## 2. Systemüberblick (C4 – Container)

```
                        ┌───────────────────────────────────────────────┐
   Clients              │                 Edge / CDN                     │
 ┌──────────┐  HTTPS    │  Vektorkacheln · Sat-Tiles · PMTiles · Styles  │
 │ Web      │──────────▶│  (CloudFront/Fastly, immutable, cache-control) │
 │ iOS      │           └───────────────────────────────────────────────┘
 │ Android  │                          │
 │ Tablet   │        HTTPS/WSS         ▼
 └────┬─────┘   ┌──────────────────────────────────────┐
      └────────▶│           API-Gateway (Fastify)       │  Auth · Rate-Limit
                │  /route /search /ai /poi /weather …    │  Cache · Aggregation
                └───┬───────┬───────┬───────┬───────┬────┘
                    │       │       │       │       │
        ┌───────────┘  ┌────┘   ┌───┘   ┌───┘   ┌───┴──────────┐
        ▼              ▼        ▼       ▼       ▼               ▼
   ┌─────────┐   ┌─────────┐ ┌──────┐ ┌──────┐ ┌───────────┐ ┌──────────┐
   │ Routing │   │ Search  │ │ AI   │ │ POI  │ │ Traffic   │ │ Sync/    │
   │(Valhalla│   │(Photon/ │ │Router│ │Overp.│ │ Ingest    │ │ Account  │
   │ +OTP)   │   │ Nomin.) │ │      │ │ +OCM │ │ (Kafka)   │ │          │
   └────┬────┘   └────┬────┘ └──┬───┘ └──┬───┘ └────┬──────┘ └────┬─────┘
        │             │         │        │          │             │
        ▼             ▼         ▼        ▼          ▼             ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Datenschicht                                                          │
  │  PostgreSQL/PostGIS (POI, User, Routen)  ·  Redis (Cache/Session/RT)   │
  │  TimescaleDB (Verkehr-Zeitreihen)  ·  Elasticsearch (Suche)            │
  │  Object Storage (Tiles/PMTiles/Imagery)  ·  ClickHouse (Analytics)     │
  └──────────────────────────────────────────────────────────────────────┘
```

## 3. Komponenten im Detail

### 3.1 Client (Web/Mobile)
- **Rendering:** MapLibre GL (Web: JS/WebGL2, Mobile: MapLibre Native).
- **Karten-Style:** MapLibre Style Spec (JSON), Layer für Basiskarte, 3D-Extrusion
  (`fill-extrusion` aus OSM `height`), Satellit (Raster), Verkehr (Vektor-Overlay).
- **Standort:** Fusion aus GNSS + Beschleunigung/Kompass + Kartenzuordnung
  (Map-Matching), Kalman-Filter zur Glättung; SBAS/Dual-Frequency wenn verfügbar.
- **Offline:** Regionen als PMTiles + Routing-Tiles; Suche über lokalen Index.
- **State:** UI-State lokal; Konto-Daten via Sync-Service repliziert.

### 3.2 API-Gateway (`services/gateway`)
Fastify/TypeScript. Verantwortlich für:
- Authentifizierung (JWT Access + Refresh), Rate-Limiting (Redis Token-Bucket).
- Request-Aggregation (z. B. Route + Wetter + POIs in einem Aufruf).
- Response-Cache (Redis) mit ETag; Circuit-Breaker zu Upstreams.
- Einheitliche Fehler- & Telemetrie-Schicht.

### 3.3 Routing-Engine
- **Valhalla** als primäre Engine: Auto/Rad/Fuß mit Kosten-Modellen (costing),
  Turn-by-Turn (`/route`), Isochronen (`/isochrone`), Map-Matching
  (`/trace_attributes`), Matrix (`/sources_to_targets`).
- **OpenTripPlanner 2 (OTP)** oder Valhalla-`multimodal` für **ÖPNV** aus GTFS +
  GTFS-Realtime.
- **KI-Reranking:** Kandidatenrouten (alternates) werden vom `ai-router` bewertet
  (schnellste vs. angenehmste — s. `docs/AI.md`).
- Historischer & Echtzeitverkehr fließt als Kanten-Geschwindigkeiten in Valhalla
  (traffic tile updates) ein.

### 3.4 Suche / Geocoding
- **Photon** (Elasticsearch, OSM) für Autocomplete/Typeahead (schnell, tolerant).
- **Nominatim** für strukturiertes Geocoding & Reverse-Geocoding.
- Eigene Ranking-Schicht: Persönliche Orte, Nähe zum Nutzer, Popularität.
- Optionale LLM-NLU für natürliche Anfragen („Café mit WLAN in der Nähe“).

### 3.5 Verkehr-Ingest
- Kafka/NATS Stream: Provider-Feeds (TomTom/HERE/MDM) + eigenes Floating-Car-Data
  (anonymisiert, differential-private Aggregation).
- Map-Matching der Sonden auf OSM-Kanten → Geschwindigkeiten pro Kante/Zeit.
- Persistenz in TimescaleDB; Ableitung von Staus/Baustellen/Unfällen als Events.
- Publiziert Traffic-Tiles + Incident-Layer an CDN und Valhalla.

### 3.6 KI-Module (`ai-router` + NLU/ETA)
Siehe [`docs/AI.md`](AI.md). Route-Ranking, NL-Suche/Sprachbefehle, ETA-Prognose,
Zusammenfassung/Erklärung von Routen.

### 3.7 Sync / Account
- Konten, Geräte, Favoriten, Sammlungen, Suchverlauf, gespeicherte Routen.
- Delta-Sync über REST (Pull) + WebSocket (Push). Konfliktlösung LWW mit
  Vektoruhr; große/geteilte Objekte optional CRDT.

## 4. Datenfluss: „Navigiere nach X“

1. Client → `POST /v1/route` mit Start/Ziel/Modus/Präferenzen.
2. Gateway ruft Routing (Valhalla) → N Alternativrouten.
3. Gateway parallel: Verkehr (Traffic), Wetter (Open-Meteo), POIs im Korridor.
4. `ai-router` bewertet Alternativen (Zeit, Komfort, Wetter, Komplexität) →
   wählt Empfehlung + Erklärung.
5. Gateway aggregiert + cached → Client rendert Route, Ansagen, ETA.
6. Während der Fahrt: Client streamt (opt-in, anonymisiert) Sonden → Traffic-Ingest.

## 5. Technologiewahl (Begründung)

| Schicht | Technologie | Warum |
| --- | --- | --- |
| Rendering | MapLibre GL | Offen, WebGL2/Native, Mapbox-kompatibler Style |
| Kacheln | OpenMapTiles/Planetiler, Martin/PMTiles | Aus OSM generierbar, CDN-freundlich |
| Routing | Valhalla, OTP2 | Multimodal, dynamischer Verkehr, offene Lizenz |
| Geocoding | Photon + Nominatim | Schnelles Typeahead + präzises Geocoding |
| Gateway | Fastify/TS | Hoher Durchsatz, Schema-Validierung, Plugins |
| Hot Paths | Go/Rust (optional) | Tile-Serving, Matching, Ingest bei Bedarf |
| RDBMS | PostgreSQL + PostGIS | Geodaten-Standard, ausgereift |
| Zeitreihen | TimescaleDB | Verkehr/Telemetrie effizient |
| Cache/RT | Redis | Cache, Rate-Limit, Pub/Sub |
| Suche-Index | Elasticsearch | Photon-Backend, Volltext |
| Streaming | Kafka/NATS | Verkehr-Ingest, Entkopplung |
| Orchestrierung | Kubernetes | HPA, Rolling, Multi-Region |

## 6. Umgebungen & Deployment
- **local**: docker-compose (dieses Repo).
- **staging/prod**: k8s (`infra/k8s`), GitOps, Blue/Green für Gateway,
  Canary für Routing. Tiles/PMTiles auf Object Storage + CDN.
