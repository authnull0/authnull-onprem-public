-- The second factor a user chose as their default (POST /mfa/default). Without a row, the
-- default is the first enrolled factor in the tenant's order, as before.
--
-- Idempotent: replayed against the master and every org database on every boot
-- (see docker-compose.yml).
CREATE TABLE IF NOT EXISTS did.user_mfa_default (
    user_id    integer     NOT NULL,
    tenant_id  integer     NOT NULL,
    factor_id  integer     NOT NULL, -- did.mfa_config.id
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, tenant_id)
);
