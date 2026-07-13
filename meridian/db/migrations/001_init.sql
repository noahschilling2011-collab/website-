-- Meridian — Kern-Schema (PostgreSQL 16 + PostGIS 3 [+ TimescaleDB optional])
-- Ausführen: psql "$POSTGRES_URL" -f db/migrations/001_init.sql

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;      -- gen_random_uuid()
-- CREATE EXTENSION IF NOT EXISTS timescaledb; -- optional, für traffic_edges

-- ---------------------------------------------------------------------------
-- Nutzer & Geräte
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         CITEXT UNIQUE,                 -- optional: anonyme Nutzung erlaubt
  password_hash TEXT,                          -- Argon2id
  display_name  TEXT,
  locale        TEXT NOT NULL DEFAULT 'de',
  prefs         JSONB NOT NULL DEFAULT '{}',   -- Routing-Präferenzen, Einheiten …
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

CREATE TABLE devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform      TEXT NOT NULL,                 -- ios | android | web | tablet
  push_token    TEXT,
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user ON devices(user_id);

-- ---------------------------------------------------------------------------
-- Sammlungen & Favoriten (Geodaten)
-- ---------------------------------------------------------------------------
CREATE TABLE collections (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  icon        TEXT,
  color       TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);
CREATE INDEX idx_collections_user ON collections(user_id, updated_at);

CREATE TABLE favorites (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  collection_id UUID REFERENCES collections(id) ON DELETE SET NULL,
  label         TEXT NOT NULL,                 -- "Zuhause", "Café Central" …
  note          TEXT,
  category      TEXT,
  geom          geography(Point,4326) NOT NULL,
  ciphertext    BYTEA,                         -- E2E-Chiffrat sensibler Felder
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);
CREATE INDEX idx_favorites_user ON favorites(user_id, updated_at);
CREATE INDEX idx_favorites_geom ON favorites USING GIST (geom);

-- ---------------------------------------------------------------------------
-- Gespeicherte Routen
-- ---------------------------------------------------------------------------
CREATE TABLE saved_routes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT,
  mode         TEXT NOT NULL,                  -- auto | bicycle | pedestrian | transit
  preference   TEXT NOT NULL DEFAULT 'fastest',
  waypoints    JSONB NOT NULL,                 -- [[lon,lat], ...]
  geometry     geography(LineString,4326),     -- optionaler Cache der Polyline
  summary      JSONB,                          -- distance, duration …
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);
CREATE INDEX idx_saved_routes_user ON saved_routes(user_id, updated_at);

-- ---------------------------------------------------------------------------
-- POI-Cache (aus OSM/Overpass; für schnelle Korridor-Suche)
-- ---------------------------------------------------------------------------
CREATE TABLE pois (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  osm_id      BIGINT,
  name        TEXT,
  category    TEXT NOT NULL,                   -- fuel | charging | restaurant | hotel …
  tags        JSONB NOT NULL DEFAULT '{}',
  geom        geography(Point,4326) NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pois_geom ON pois USING GIST (geom);
CREATE INDEX idx_pois_cat  ON pois (category);

-- ---------------------------------------------------------------------------
-- Verkehr: Zeitreihen je Kante  (TimescaleDB-Hypertable, sonst normale Tabelle)
-- ---------------------------------------------------------------------------
CREATE TABLE traffic_edges (
  edge_id     BIGINT NOT NULL,                 -- OSM-Way/Segment-ID
  ts          TIMESTAMPTZ NOT NULL,
  speed_kmh   REAL NOT NULL,
  free_kmh    REAL,
  source      TEXT NOT NULL,                   -- tomtom | here | mdm | fcd
  sample_n    INT  NOT NULL DEFAULT 1,         -- k-Anonymität
  PRIMARY KEY (edge_id, ts)
);
-- SELECT create_hypertable('traffic_edges','ts');  -- wenn TimescaleDB aktiv

CREATE TABLE incidents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        TEXT NOT NULL,                   -- jam | roadworks | accident | closure
  severity    INT  NOT NULL DEFAULT 1,
  geom        geography(Geometry,4326) NOT NULL,
  starts_at   TIMESTAMPTZ,
  ends_at     TIMESTAMPTZ,
  source      TEXT NOT NULL,
  props       JSONB NOT NULL DEFAULT '{}',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_incidents_geom ON incidents USING GIST (geom);
CREATE INDEX idx_incidents_time ON incidents (starts_at, ends_at);

-- ---------------------------------------------------------------------------
-- Sync-Log (Delta-Sync, Vektoruhr)
-- ---------------------------------------------------------------------------
CREATE TABLE sync_log (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity      TEXT NOT NULL,                   -- favorites | collections | saved_routes
  entity_id   UUID NOT NULL,
  op          TEXT NOT NULL,                   -- upsert | delete
  version     BIGINT NOT NULL,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_user ON sync_log(user_id, id);

-- ---------------------------------------------------------------------------
-- Row-Level-Security: Nutzer sieht nur eigene Zeilen
-- (App setzt:  SET app.user_id = '<uuid>';)
-- ---------------------------------------------------------------------------
ALTER TABLE favorites    ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections  ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_fav  ON favorites    USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_col  ON collections  USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_rte  ON saved_routes USING (user_id = current_setting('app.user_id', true)::uuid);

COMMIT;
