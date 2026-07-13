# Datenbankstruktur

Meridian nutzt mehrere Speicher, je nach Zugriffsmuster:

| Speicher | Zweck |
| --- | --- |
| **PostgreSQL + PostGIS** | Nutzer, Geräte, Favoriten, Sammlungen, gespeicherte Routen, POI-Cache (Geodaten) |
| **TimescaleDB** (PG-Extension) | Verkehrs-Zeitreihen (Geschwindigkeit je Kante/Zeit), Telemetrie |
| **Redis** | Response-Cache, Sessions, Rate-Limit-Buckets, Pub/Sub für Sync |
| **Elasticsearch** | Volltext-/Geo-Suche (Photon-Backend + eigene POIs) |
| **Object Storage (S3)** | Vektor-/Satelliten-Tiles, PMTiles, Offline-Pakete |
| **ClickHouse** (optional) | Produkt-Analytics, aggregiert & anonymisiert |

Das relationale Kern-Schema liegt in [`../db/migrations/001_init.sql`](../db/migrations/001_init.sql).

## Kern-Entitäten (PostGIS)

```
users ──1:N── devices                 (Geräte pro Konto, für Sync/Push)
  │
  ├─1:N── collections ──1:N── favorites   (Sammlungen: „Reise Rom“, „Lieblingscafés“)
  ├─1:N── favorites                        (Ort, Geometrie, Notiz, Icon)
  ├─1:N── saved_routes                     (Start/Ziel, Modus, Polyline, Präferenzen)
  ├─1:N── search_history                   (opt-in, on-device bevorzugt)
  └─1:N── sync_log                         (Delta-Sync, Vektoruhr)

pois                                        (Cache aus OSM/Overpass; Geo-Index)
traffic_edges (Timescale Hypertable)        (edge_id, ts, speed_kmh, source)
incidents                                   (Baustelle/Unfall/Stau, Geometrie, Zeitfenster)
```

### Wichtige Design-Entscheidungen
- **UUID-PKs** (v7, zeitgeordnet) für Sharding & Sync ohne Kollisionen.
- **`geometry(Point,4326)`** bzw. `geography` mit **GiST-Index** für Nähe-Suchen
  (`ST_DWithin`) und Korridor-Suchen (`ST_DWithin(route_buffer, poi)`).
- **Soft-Delete + `updated_at`** überall → Delta-Sync (`WHERE updated_at > cursor`).
- **Row-Level-Security**: Nutzer sieht nur eigene Zeilen (`user_id = current_setting`).
- **Verkehr als Hypertable** in TimescaleDB mit Retention & Continuous Aggregates
  (5-Min-Buckets für ETA-Modell).

## Beispiel: POI-Korridor-Suche entlang einer Route
```sql
-- $1 = route als GeoJSON LineString, $2 = Puffer in Metern, $3 = Kategorie
SELECT id, name, category, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon
FROM pois
WHERE category = $3
  AND ST_DWithin(
        geom,
        ST_Buffer(ST_GeogFromGeoJSON($1), $2),
        0)
ORDER BY ST_Distance(geom, ST_StartPoint(ST_GeomFromGeoJSON($1))::geography)
LIMIT 50;
```

## Beispiel: Delta-Sync (Pull)
```sql
SELECT * FROM favorites
WHERE user_id = $1 AND updated_at > $2   -- $2 = letzter Sync-Cursor
ORDER BY updated_at ASC
LIMIT 500;
```

Retention/Partitionierung, Indizes und RLS-Policies sind in der Migration
kommentiert.
