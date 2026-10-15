-- 049: per-domain credentials for the AD DC sensor.
--
-- Lives in each org's database, like 021_gateway_credentials, and follows the same scheme: a
-- client id and secret are issued when an admin downloads sensor.yml for a domain, the secret is
-- stored only as a SHA-256 hash, and the sensor trades the pair for a short-lived bearer token
-- at /ad/sensor/token.
--
-- A domain may hold several live credentials: it usually has several domain controllers, each
-- running its own sensor with the file downloaded for it. A credential stops working when its
-- domain is deleted or when revoked_at is set.
--
-- Separate from did.gateway_credentials on purpose: those are bound to a PAM jump server, and
-- the PAM gateway auth path stays untouched.
--
-- Replayed on every start (see docker-compose.yml): everything here is IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS did.ad_sensor_credentials (
    id            serial PRIMARY KEY,
    org_id        integer     NOT NULL,
    ad_domain_id  integer     NOT NULL,
    client_id     text        NOT NULL UNIQUE,
    secret_hash   text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    integer,
    last_used_at  timestamptz,
    revoked_at    timestamptz
);

CREATE INDEX IF NOT EXISTS ad_sensor_credentials_domain
    ON did.ad_sensor_credentials (org_id, ad_domain_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS did.ad_sensor_tokens (
    token_hash     text        PRIMARY KEY,
    credential_id  integer     NOT NULL REFERENCES did.ad_sensor_credentials (id),
    org_id         integer     NOT NULL,
    ad_domain_id   integer     NOT NULL,
    issued_at      timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS ad_sensor_tokens_expiry ON did.ad_sensor_tokens (expires_at);
