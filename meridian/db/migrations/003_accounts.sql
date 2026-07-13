-- Meridian — Konten & Sicherheit (Produktions-Persistenz für den Auth-Service)
-- Der Gateway-Service nutzt v1 einen In-Memory-Store; diese Tabellen sind das
-- swap-fähige Backing-Modell. Ausführen nach 001_init.sql.

BEGIN;

-- users.password_hash existiert bereits (001). Ergänzende Sicherheitsfelder:
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_color   TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret    TEXT;      -- verschlüsselt speichern (KMS)
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled   BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS backup_codes   TEXT[]  NOT NULL DEFAULT '{}';
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_attempts INT    NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until   TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest       BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS permissions    JSONB   NOT NULL DEFAULT
  '{"location":true,"camera":false,"microphone":false,"notifications":true,"analytics":false,"personalization":false}';

-- Verknüpfte Social-Logins (Google/Apple/Microsoft)
CREATE TABLE oauth_identities (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider    TEXT NOT NULL,                    -- google|apple|microsoft
  subject     TEXT NOT NULL,                    -- provider "sub"
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, subject)
);
CREATE INDEX idx_oauth_user ON oauth_identities (user_id);

-- Passkeys / WebAuthn-Anmeldedaten
CREATE TABLE webauthn_credentials (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id  BYTEA NOT NULL UNIQUE,
  public_key     BYTEA NOT NULL,
  sign_count     BIGINT NOT NULL DEFAULT 0,
  transports     TEXT[],
  device_label   TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at   TIMESTAMPTZ
);
CREATE INDEX idx_webauthn_user ON webauthn_credentials (user_id);

-- Sitzungen / Geräte (Refresh-Token-Familie, Rotation, Fernabmeldung)
CREATE TABLE auth_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_hash  TEXT NOT NULL,                  -- Hash des aktuellen Refresh-Tokens
  device        TEXT,
  ip            INET,
  user_agent    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked       BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX idx_sessions_user ON auth_sessions (user_id) WHERE NOT revoked;
CREATE INDEX idx_sessions_refresh ON auth_sessions (refresh_hash);

-- Verbrauchte (rotierte) Refresh-Hashes -> Reuse-Detection
CREATE TABLE auth_used_refresh (
  session_id   UUID NOT NULL REFERENCES auth_sessions(id) ON DELETE CASCADE,
  refresh_hash TEXT NOT NULL,
  used_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, refresh_hash)
);

-- Sicherheitsprotokoll (alle Kontoaktivitäten, unveränderlich)
CREATE TABLE security_events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,                    -- login|login_failed|new_device_login|...
  at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip          INET,
  device      TEXT,
  detail      TEXT
);
CREATE INDEX idx_events_user ON security_events (user_id, at DESC);

-- E2E-Vault: Server speichert ausschließlich Chiffrat
CREATE TABLE e2e_vault (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key         TEXT NOT NULL,
  ciphertext  BYTEA NOT NULL,                   -- AES-256-GCM, Schlüssel nur auf dem Gerät
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);

-- Familienkonten (geteilte Gruppe, Rollen)
CREATE TABLE families (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  owner_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE family_members (
  family_id   UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        TEXT NOT NULL DEFAULT 'member',   -- owner|adult|child
  PRIMARY KEY (family_id, user_id)
);

ALTER TABLE auth_sessions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE e2e_vault       ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_sessions ON auth_sessions   USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_events   ON security_events USING (user_id = current_setting('app.user_id', true)::uuid);
CREATE POLICY p_vault    ON e2e_vault        USING (user_id = current_setting('app.user_id', true)::uuid);

COMMIT;
