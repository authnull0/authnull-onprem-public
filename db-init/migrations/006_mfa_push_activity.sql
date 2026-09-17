-- Unified push-MFA activity: one row per challenge across both flows, for the app's
-- Activity tab, the admin audit trail, and the risk-scoring lookback.
--
-- This is a MIRROR, not authoritative state. AD challenge status stays in
-- did.ad_mfa_challenges and platform status stays in Redis; neither moves. Anything that
-- must be correct reads the authoritative store — this table is for history, which those
-- two cannot provide: Redis challenges evaporate after 90 seconds, and the AD table has no
-- source IP, resource or geo.
--
-- Numbered 006: 001-005 are taken.
-- Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.mfa_push_activity (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    tenant_id  integer     NOT NULL DEFAULT 0,

    -- 'ad' | 'platform'. The two flows key their challenges differently (a sequential
    -- integer vs a UUID), so challenge_ref is text and the pair is what identifies a row.
    flow          text NOT NULL,
    challenge_ref text NOT NULL,

    -- Who was challenged. email is the account the push went to; ad_user is the AD
    -- principal the gateway named, which can differ from it.
    email         text    NOT NULL DEFAULT '',
    identity_kind text    NOT NULL DEFAULT '',
    identity_id   integer NOT NULL DEFAULT 0,
    device_id     bigint,
    ad_user       text    NOT NULL DEFAULT '',

    -- What was being accessed, derived from the SPN / destination the gateway sent.
    resource_name text NOT NULL DEFAULT '',
    resource_type text NOT NULL DEFAULT '',
    resource_id   text NOT NULL DEFAULT '',
    protocol      text NOT NULL DEFAULT '',

    binding_message text NOT NULL DEFAULT '',
    gateway_id      text NOT NULL DEFAULT '',
    session_id      text NOT NULL DEFAULT '',

    -- text, not inet: every access is an equality comparison, and '' is not a valid inet
    -- so an unknown IP would need a NULL and a three-way condition everywhere.
    client_ip text NOT NULL DEFAULT '',

    geo_city         text NOT NULL DEFAULT '',
    geo_region       text NOT NULL DEFAULT '',
    geo_country      text NOT NULL DEFAULT '',
    geo_country_code text NOT NULL DEFAULT '',
    geo_lat          double precision,
    geo_lon          double precision,
    -- 'private' | 'cache' | 'mmdb' | 'api' | '' — so a missing location can be told apart
    -- from a location that resolved to nothing.
    geo_source text NOT NULL DEFAULT '',

    risk_level text NOT NULL DEFAULT '',
    -- jsonb so tuning the rule set never needs a schema change.
    risk_reasons jsonb,

    provider       text NOT NULL DEFAULT '',
    push_transport text NOT NULL DEFAULT '',
    push_error     text NOT NULL DEFAULT '',

    -- pending | approved | denied | expired, matching the existing vocabulary.
    status text NOT NULL DEFAULT 'pending',
    -- 'device' | 'provider_poll' | 'ttl' — how the verdict was reached, which is the
    -- difference between "the user denied it" and "nobody answered".
    resolution_source text NOT NULL DEFAULT '',

    -- sha256 of the token the pushed device must present to read this challenge's full
    -- context. Only the hash is stored: a leaked table must not grant read access.
    fetch_token_sha256 text NOT NULL DEFAULT '',

    -- Set when a fraud alert has been sent, which is also the cooldown claim.
    alerted_at timestamptz,

    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz,
    responded_at timestamptz
);

-- Idempotent writes: the AD gateway polls every ~5s and both flows can retry, so Create
-- uses ON CONFLICT DO NOTHING against this.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_push_activity_challenge_uq
    ON did.mfa_push_activity (org_id, flow, challenge_ref);

-- Activity tab, and the risk lookback.
CREATE INDEX IF NOT EXISTS mfa_push_activity_email_idx
    ON did.mfa_push_activity (org_id, lower(email), created_at DESC);

-- The app's own history, scoped to one device.
CREATE INDEX IF NOT EXISTS mfa_push_activity_device_idx
    ON did.mfa_push_activity (device_id, created_at DESC) WHERE device_id IS NOT NULL;

-- Serves the "have we seen this IP / country approved before" risk rules without scanning
-- a user's whole history.
CREATE INDEX IF NOT EXISTS mfa_push_activity_approved_origin_idx
    ON did.mfa_push_activity (org_id, lower(email), client_ip, geo_country_code)
    WHERE status = 'approved';

-- The sweeper's reap query. Both flows only expire a challenge when someone polls, so a
-- crashed gateway otherwise leaves rows pending forever and the Activity tab lies.
CREATE INDEX IF NOT EXISTS mfa_push_activity_pending_idx
    ON did.mfa_push_activity (expires_at) WHERE status = 'pending';

-- Retention purge.
CREATE INDEX IF NOT EXISTS mfa_push_activity_created_idx
    ON did.mfa_push_activity (created_at);
