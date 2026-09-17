-- Bring did.ad_gateways up to the shape the AD gateway / DC sensor code expects, and
-- create the gateway↔domain junction table.
--
-- WHY THIS IS NEEDED: /ad/registerGateway inserts (org_id, tenant_id, gateway_id,
-- last_seen, created_at) with ON CONFLICT ON CONSTRAINT ad_gateways_unique, but the table
-- created by db-init/01_schema.sql has none of gateway_id, last_seen or that constraint.
-- So gateway registration -- the first step of the whole AD MFA flow -- fails outright.
--
-- The intended DDL already existed in internal/ad/db/migrations/{002,003,006}, but that
-- directory is applied by NOTHING (see db/README.md). Worse, 002 is written as
-- CREATE TABLE IF NOT EXISTS, so even if it were applied it would be a silent no-op
-- against the table 01_schema.sql already created. Hence ALTERs here, in
-- db-init/migrations/, which the did-schema-init pass actually replays.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS or guarded.

-- ---------------------------------------------------------------------------
-- ad_gateways: columns the code writes
-- ---------------------------------------------------------------------------
ALTER TABLE did.ad_gateways
    ADD COLUMN IF NOT EXISTS gateway_id  text,
    ADD COLUMN IF NOT EXISTS last_seen   timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS dc_hostname text,
    -- mode: 'monitor' logs without blocking, 'enforce' applies the verdict. The
    -- monitor-first rollout depends on this.
    ADD COLUMN IF NOT EXISTS mode        text NOT NULL DEFAULT 'monitor',
    -- fallback: what the sensor does when the backend is unreachable. 'allow' fails open
    -- (logins keep working, MFA is skipped), 'deny' fails closed. Defaulting to 'allow'
    -- so an outage cannot lock an entire domain out of Active Directory.
    ADD COLUMN IF NOT EXISTS fallback    text NOT NULL DEFAULT 'allow';

-- gateway_id must be NOT NULL for the unique constraint below to be meaningful. Applied
-- as a separate guarded step because ALTER ... SET NOT NULL is not idempotent and fails
-- if any row still holds a NULL.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'did' AND table_name = 'ad_gateways'
           AND column_name = 'gateway_id' AND is_nullable = 'YES'
    ) AND NOT EXISTS (
        SELECT 1 FROM did.ad_gateways WHERE gateway_id IS NULL
    ) THEN
        ALTER TABLE did.ad_gateways ALTER COLUMN gateway_id SET NOT NULL;
    END IF;
END $$;

-- The constraint named by registerGateway's ON CONFLICT clause. Without it that upsert
-- errors rather than updating last_seen on re-registration.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ad_gateways_unique') THEN
        ALTER TABLE did.ad_gateways
            ADD CONSTRAINT ad_gateways_unique UNIQUE (org_id, gateway_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ad_gateways_org_idx ON did.ad_gateways (org_id);

-- ---------------------------------------------------------------------------
-- gateway_domain_mappings: which domains a gateway serves
-- ---------------------------------------------------------------------------
-- One gateway can front several AD domains, which a single ad_gateways.domain_id cannot
-- express. domain_id is deliberately LEFT IN PLACE rather than dropped as
-- internal/ad/db/migrations/006 does: dropping a column is irreversible and the code may
-- still read it. Retire it separately once nothing does.
CREATE TABLE IF NOT EXISTS did.gateway_domain_mappings (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    gateway_id text        NOT NULL,
    domain_id  integer     NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT gateway_domain_mappings_unique UNIQUE (org_id, gateway_id, domain_id)
);

CREATE INDEX IF NOT EXISTS gateway_domain_mappings_gateway_idx
    ON did.gateway_domain_mappings (org_id, gateway_id);

-- Backfill from any pre-existing single-domain assignment.
INSERT INTO did.gateway_domain_mappings (org_id, gateway_id, domain_id)
SELECT org_id, gateway_id, domain_id
  FROM did.ad_gateways
 WHERE gateway_id IS NOT NULL AND domain_id IS NOT NULL
ON CONFLICT ON CONSTRAINT gateway_domain_mappings_unique DO NOTHING;
