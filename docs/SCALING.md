# Skalierung auf 10 M+ Nutzer

Der Code ist von Anfang an horizontal skalierbar gebaut: die API ist
zustandslos (JWT statt Sessions, Uploads über Storage-Keys, Rate-Limits
in Redis) — Skalierung heißt Pods hinzufügen.

## Stufenplan

| Stufe | Nutzer | Setup |
|---|---|---|
| 1 | bis ~50 k | Docker Compose auf 1 VM oder 3 Pods + verwaltete DB |
| 2 | bis ~1 M | EKS + HPA (3→30 Pods), RDS PostgreSQL mit Read-Replicas, ElastiCache Redis, S3 für Dateien, CloudFront vor Web-Build |
| 3 | 10 M+ | Multi-AZ, PgBouncer, Partitionierung (unten), dedizierte Worker-Deployments für `ai_jobs`, SQS-Queue, Sharding nach `user_id` falls nötig |

## Datenbank

- **Connection Pooling:** PgBouncer (transaction mode) vor RDS; Pool pro
  Pod klein halten (`PG_POOL_SIZE=10`).
- **Read/Write-Split:** GraphQL-Read-Layer und Listen-Endpunkte auf
  Replicas lenken.
- **Partitionierung:** `messages` und `analytics_events` nach Monat
  (`PARTITION BY RANGE (created_at)`) — beide wachsen unbegrenzt.
- **Indexe:** alle Hot-Paths sind indiziert (siehe `migrations/001_init.sql`);
  `EXPLAIN ANALYZE` in CI für kritische Queries.
- **Archivierung:** `analytics_events` nach 90 Tagen zu S3/Parquet
  (Athena für Langzeit-Analysen).

## Caching & Echtzeit

- Redis: Rate-Limits, Session-Widerruf, Hot-Cache für Dashboards
  (`GET /api/admin/dashboard` mit 60-s-TTL cachen).
- Socket.IO mit `@socket.io/redis-adapter`: Events erreichen Nutzer auf
  allen Pods; Sticky-Sessions am ALB aktivieren.

## KI-Last

- KI-Aufrufe sind der teuerste Pfad → eigene HPA-Metrik (Requests/s statt
  nur CPU), Timeouts + Circuit-Breaker pro Provider, Fallback auf einen
  anderen Provider bei 5xx.
- Media-Jobs (`ai_jobs`) in dedizierte Worker-Deployments auslagern
  (gleicher Code, `WORKER=1`), Queue via SQS/BullMQ statt Fire-and-Forget.
- Antwort-Caching für deterministische Tools (Übersetzung identischer
  Texte) über Redis-Hash des Inputs.

## Auslieferung

- **Web:** `flutter build web` → S3 + CloudFront (global, praktisch
  kostenlos skalierend).
- **Mobile:** Stores; Push über FCM (Gerätetokens in `devices`).
- **API:** ALB → NGINX-Ingress → Pods; SSE/WebSocket-Timeouts erhöht
  (siehe `infra/k8s/ingress.yaml`).

## Beobachtbarkeit unter Last

- Prometheus + Grafana (RPS, p95-Latenz, DB-Pool-Auslastung,
  Provider-Fehlerraten), Alerts auf p95 > 500 ms und 5xx > 1 %.
- OpenTelemetry-Tracing (ein Trace pro Request bis in den Provider-Call).
- pino-Logs als JSON → CloudWatch/Loki; `redact` verhindert Token-Leaks.

## Kostenkontrolle

- Token-Verbrauch pro Nutzer wird in `messages.tokens_in/out` erfasst →
  Quotas pro Plan im Rate-Limiter durchsetzbar.
- Spot-Instances für Worker-Nodes, Reserved für die Grundlast.
