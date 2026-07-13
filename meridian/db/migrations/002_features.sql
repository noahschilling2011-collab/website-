-- Meridian — Erweiterte Funktionen (Assistent, Reiseplanung, Gemeinschaft, Gewohnheiten)
-- Ausführen nach 001_init.sql.

BEGIN;

-- ---------------------------------------------------------------------------
-- Gemeinschaft: Gefahrenmeldungen mit Glaubwürdigkeit
-- (der Gateway-Service nutzt v1 einen In-Memory-Store; diese Tabelle ist die
--  Produktions-Persistenz inkl. Korroboration & Ablauf)
-- ---------------------------------------------------------------------------
CREATE TABLE community_reports (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind          TEXT NOT NULL,                    -- accident|animal|closure|roadworks|jam|hazard
  geom          geography(Point,4326) NOT NULL,
  note          TEXT,
  reporter_id   UUID REFERENCES users(id) ON DELETE SET NULL,
  credibility   REAL NOT NULL DEFAULT 0.4,        -- 0..1 (KI-Prüfung)
  confirmations INT  NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'pending',  -- pending|confirmed|expired
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ
);
CREATE INDEX idx_reports_geom ON community_reports USING GIST (geom);
CREATE INDEX idx_reports_live ON community_reports (status, expires_at);

-- Reputation je Melder (fließt in die Glaubwürdigkeit ein)
CREATE TABLE reporter_reputation (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  score       REAL NOT NULL DEFAULT 0.5,          -- 0..1
  reports     INT  NOT NULL DEFAULT 0,
  confirmed   INT  NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Gewohnheiten: gelernte Ziele/Strecken/Zeiten (on-device bevorzugt, Server-Sync opt-in)
-- ---------------------------------------------------------------------------
CREATE TABLE travel_habits (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label         TEXT,                             -- "Arbeit", "Fitnessstudio"
  origin        geography(Point,4326),
  destination   geography(Point,4326) NOT NULL,
  mode          TEXT NOT NULL DEFAULT 'auto',
  dow_mask      INT  NOT NULL DEFAULT 0,          -- Bitmaske Wochentage
  typical_hour  INT,                              -- übliche Abfahrtsstunde
  count         INT  NOT NULL DEFAULT 1,          -- Häufigkeit
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_habits_user ON travel_habits (user_id, count DESC);

-- ---------------------------------------------------------------------------
-- Fahrzeugprofil: Fahrstil, Verbrauch, Antrieb (für Eco-/EV-Routing)
-- ---------------------------------------------------------------------------
CREATE TABLE vehicle_profiles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT,
  drivetrain    TEXT NOT NULL DEFAULT 'combustion', -- combustion|ev|hybrid
  consumption   REAL,                               -- l/100km bzw. kWh/100km
  battery_kwh   REAL,
  driving_style TEXT,                               -- calm|normal|sporty (gelernt)
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_vehicles_user ON vehicle_profiles (user_id);

-- ---------------------------------------------------------------------------
-- Gespeicherte Reisepläne (KI-Reiseplanung)
-- ---------------------------------------------------------------------------
CREATE TABLE trip_plans (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT,
  waypoints     JSONB NOT NULL,
  items         JSONB NOT NULL,                   -- TripItem[]
  summary       JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_trips_user ON trip_plans (user_id, created_at DESC);

ALTER TABLE travel_habits    ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_plans       ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_habits   ON travel_habits    USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_vehicles ON vehicle_profiles USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_trips    ON trip_plans        USING (user_id = current_setting('app.user_id', true)::uuid);

COMMIT;
