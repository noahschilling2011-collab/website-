# Skalierung für Millionen Nutzer

## Traffic-Charakteristik
- **Kacheln** dominieren das Volumen (95 %+ der Requests) → statisch, cachebar, CDN.
- **Routing/Suche/KI** sind rechenintensiv, aber cachebar (viele identische Anfragen).
- **Realtime** (Verkehr/Sync) ist Fan-out-lastig → WebSocket + Pub/Sub.

## Prinzipien
1. **Statisches an den Edge.** Vektor-/Sat-Tiles, PMTiles, Styles: immutable,
   `Cache-Control: public, max-age=31536000, immutable`, über CDN (CloudFront/Fastly).
   Nur Delta-Updates neu ausrollen.
2. **Zustandslose Dienste, horizontal skaliert.** Gateway & Services als k8s
   Deployments mit **HPA** (CPU + RPS + Latenz-SLO). Keine lokale Sessionhaltung
   (Redis).
3. **Aggressives Caching.** Redis-Cache für Routing/Suche/Wetter mit
   geokodierten Cache-Keys (gerundete Koordinaten + Parameter). Hit-Rate 60–80 %
   bei Ballungsräumen.
4. **Routing-Sharding nach Geografie.** Valhalla/OSRM-Tiles regional; Requests per
   Bounding-Box an die richtige Region geroutet. Beliebte Regionen mehr Replicas.
5. **Lesereplikate + Sharding.** PostGIS Read-Replicas für POI/Suche; Nutzerdaten
   nach `user_id` gesharded (Citus/Vitess-Muster). TimescaleDB mit Continuous
   Aggregates & Retention.
6. **Streaming statt Polling.** Verkehr-Ingest über Kafka/NATS; Consumer skalieren
   nach Partitionen. Sync-Push über WebSocket-Gateway mit Redis-Pub/Sub-Fan-out.

## Kapazitäts-Skizze (Größenordnung)
| Ebene | Technik | Ziel |
| --- | --- | --- |
| Tiles | CDN + Object Storage | ~unbegrenzt, >99 % Edge-Hit |
| Gateway | k8s HPA 3→300 Pods | 50–100 k RPS |
| Routing | Valhalla-Pool je Region | p95 < 300 ms (gecacht < 20 ms) |
| Suche | ES-Cluster + Cache | p95 < 150 ms |
| DB | PG primär + N Replicas + Shards | Millionen Nutzer, Sharding by user |
| Verkehr | Kafka N Partitionen | Mio. Sonden/min |

## Resilienz
- **Circuit-Breaker** je Upstream; **Fallbacks** (Luftlinie/Demo-POI) statt Fehler.
- **Multi-AZ**, später **Multi-Region** (aktiv/aktiv für Reads, Konten geo-pinned).
- **Graceful Degradation:** Bei Überlast zuerst KI-Reranking & Live-Extras abschalten,
  Kernrouting bleibt.
- **Backpressure & Load-Shedding** am Gateway; Prioritäts-Queues (Navigation >
  Vorschau).

## Beobachtbarkeit
- OpenTelemetry Traces (Client→Gateway→Service), RED-Metriken, SLO-Dashboards,
  Fehlerbudget-basiertes Alerting. Structured Logs mit PII-Redaction.

## Kostenkontrolle
- CDN-Offload maximieren, teure externe APIs (Traffic/Sat) cachen & aggregieren,
  On-Device-Verarbeitung reduziert Serverlast (Suche/Guidance).
