-- Reconcile the live schema with what the code expects.
--
-- WHY THIS FILE EXISTS
--
-- Four directories under internal/*/db/migrations hold 21 SQL files that nothing has ever
-- replayed -- there is no migration runner that reads them. Only this directory executes, via
-- the loop at docker-compose.yml:144-165, which applies every file here to the master database
-- and to every org database on each boot.
--
-- Some of those 21 were applied by hand to individual org databases and never transcribed.
-- The result is schema drift in both directions: the alpha org database has objects the master
-- does not, the master has objects alpha does not, and several objects exist in neither while
-- the code that needs them is deployed and mounted. A newly created organisation gets whatever
-- 01_schema.sql plus this directory produces -- so anything only ever hand-applied is simply
-- absent for every future tenant.
--
-- WHY THE FILES WERE NOT JUST MOVED HERE
--
-- Tried, and it fails. Relocating them was verified against both live databases inside a
-- transaction and aborted twice:
--
--   * did.gateway_domain_mappings' migration INSERTs from did.ad_gateways.gateway_id and then
--     DROPs did.ad_gateways.domain_id. Master has no gateway_id, so the INSERT fails there; and
--     on a second pass the DROP has already removed the column the INSERT selects, so it is not
--     re-runnable at all -- which this directory requires, since every file is replayed on
--     every boot.
--   * did.db_hosts' migration is CREATE TABLE IF NOT EXISTS followed by an INSERT naming
--     hostgroup_id. db_hosts already exists on alpha WITHOUT that column, so the CREATE
--     no-oped and the INSERT failed.
--
-- That is the general trap: CREATE TABLE IF NOT EXISTS is idempotent but NOT convergent. When
-- the table already exists in a different shape -- because 01_schema.sql created its own
-- version independently -- the migration silently does nothing and every later statement that
-- depends on its columns fails.
--
-- So this file carries only ADD COLUMN / CREATE TABLE for objects PROVEN missing by querying
-- information_schema on both live databases. No data backfills, no DROP COLUMN, nothing whose
-- correctness depends on the order it ran in relative to 01_schema.sql. Shapes for tables that
-- already exist on alpha are taken from alpha's live definition, because what is running today
-- is a better source of truth than a file written against a different starting schema.
--
-- Every statement is IF NOT EXISTS. Re-running this file must always be a no-op.

-- ---------------------------------------------------------------------------
-- 1. did.auth_logs -- the decision log that has never recorded a row
-- ---------------------------------------------------------------------------
-- THIS IS THE IMPORTANT ONE. policy/repo/auth_decision_repository.go LogAuthDecision writes
-- decision, policy_id, policy_name, match_reason, session_id and mfa_outcome. None of those
-- columns exist, so every insert fails and did.auth_logs holds 0 rows in every database while
-- did.auth_log (singular, a different table) holds the sensor's own events. That is why the
-- policy decision log has always looked empty.
--
-- challenge_id is uuid to match the original migration, but note that ad_mfa_challenges.id is
-- a bigserial -- ad_challenge_id below is the column that actually links a decision to its
-- challenge. challenge_id is kept only because ListAuthDecisions selects it.
ALTER TABLE did.auth_logs
    ADD COLUMN IF NOT EXISTS policy_id        uuid,
    ADD COLUMN IF NOT EXISTS policy_name      text,
    ADD COLUMN IF NOT EXISTS match_reason     text,
    ADD COLUMN IF NOT EXISTS decision         text,
    ADD COLUMN IF NOT EXISTS mfa_outcome      text,
    ADD COLUMN IF NOT EXISTS challenge_id     uuid,
    ADD COLUMN IF NOT EXISTS session_id       text,
    -- Present on alpha, absent on master: monitor-mode context.
    ADD COLUMN IF NOT EXISTS applied_decision text,
    ADD COLUMN IF NOT EXISTS enforcement_mode text,
    ADD COLUMN IF NOT EXISTS ad_challenge_id  bigint;

-- Serves the correlation lookup in ad/src/repository/challenge_context.go, which finds the
-- decision row that caused a challenge, and the decision list in the console.
CREATE INDEX IF NOT EXISTS auth_logs_org_ts_idx
    ON did.auth_logs (org_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS auth_logs_challenge_idx
    ON did.auth_logs (org_id, ad_challenge_id) WHERE ad_challenge_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. did.blocked_principals -- table missing, endpoints mounted
-- ---------------------------------------------------------------------------
-- /ad/BlockPrincipal, /ad/UnblockPrincipal and /ad/GetBlockedPrincipals are all registered in
-- internal/ad/routes.go and this table exists in no database, so all three fail.
CREATE TABLE IF NOT EXISTS did.blocked_principals (
    id          bigserial    PRIMARY KEY,
    tenant_id   int          NOT NULL,
    org_id      int          NOT NULL,
    principal   text         NOT NULL,   -- always stored lowercase (sAMAccountName)
    domain      text         NOT NULL,   -- always stored lowercase FQDN, e.g. "test.lab"
    reason      text         NOT NULL DEFAULT '',
    blocked_by  text         NOT NULL DEFAULT '',
    blocked_at  timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, principal, domain)
);

CREATE INDEX IF NOT EXISTS blocked_principals_lookup_idx
    ON did.blocked_principals (org_id, domain, principal);

-- ---------------------------------------------------------------------------
-- 3. did.gateway_auth_events -- absent everywhere
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS did.gateway_auth_events (
    id                  bigserial   PRIMARY KEY,
    org_id              integer     NOT NULL,
    tenant_id           integer     NOT NULL,
    gateway_id          text        NOT NULL,
    correlation_id      text        NOT NULL,
    protocol            text        NOT NULL,
    principal           text        NOT NULL,
    realm               text        NOT NULL,
    service_spn         text        NOT NULL DEFAULT '',
    client_ip           text        NOT NULL,
    decision            text        NOT NULL,
    reason              text        NOT NULL DEFAULT '',
    upstream_error_code integer     NOT NULL DEFAULT 0,
    challenge_id        text        NOT NULL DEFAULT '',
    ts_unix_ms          bigint      NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gae_org_ts_idx      ON did.gateway_auth_events (org_id, ts_unix_ms DESC);
CREATE INDEX IF NOT EXISTS gae_correlation_idx ON did.gateway_auth_events (org_id, correlation_id);

-- ---------------------------------------------------------------------------
-- 4. Tables alpha has and master does not
-- ---------------------------------------------------------------------------
-- Shapes copied from alpha's live definition. Without these, a NEW organisation's database is
-- created without them and AD policy matching fails for that tenant while working on alpha --
-- the failure mode that is hardest to diagnose, because the feature demonstrably works.

-- Nested group membership, for AD group policy matching.
CREATE TABLE IF NOT EXISTS did.ad_group_nesting (
    child_group_id  integer     NOT NULL,
    parent_group_id integer     NOT NULL,
    ad_id           bigint,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (child_group_id, parent_group_id)
);

CREATE INDEX IF NOT EXISTS ad_group_nesting_parent_idx ON did.ad_group_nesting (parent_group_id);

-- Audit of who was added to or removed from an enrolled set.
CREATE TABLE IF NOT EXISTS did.enrolled_set_changes (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    tenant_id  integer     NOT NULL,
    action     text        NOT NULL,
    logoname   text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS enrolled_set_changes_org_idx
    ON did.enrolled_set_changes (org_id, tenant_id, created_at DESC);

-- Gateway-to-domain junction. Deliberately WITHOUT the original migration's INSERT backfill
-- and its DROP of ad_gateways.domain_id: that pair is what made the file non-re-runnable, and
-- alpha still carries domain_id today, so dropping it now would break whatever still reads it.
CREATE TABLE IF NOT EXISTS did.gateway_domain_mappings (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    gateway_id text        NOT NULL,
    domain_id  integer     NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (gateway_id, domain_id)
);

CREATE INDEX IF NOT EXISTS gdm_gateway_idx ON did.gateway_domain_mappings (gateway_id);
CREATE INDEX IF NOT EXISTS gdm_domain_idx  ON did.gateway_domain_mappings (domain_id);

-- ---------------------------------------------------------------------------
-- 5. did.ad_gateways -- columns alpha has and master does not
-- ---------------------------------------------------------------------------
-- gateway_id and last_seen carry DEFAULTs even though alpha declares them NOT NULL without
-- one: adding a NOT NULL column to a table that already has rows requires a default, and
-- master's ad_gateways may not be empty.
ALTER TABLE did.ad_gateways
    ADD COLUMN IF NOT EXISTS gateway_id  text        NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS last_seen   timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS dc_hostname text,
    ADD COLUMN IF NOT EXISTS mode        text        NOT NULL DEFAULT 'monitor',
    ADD COLUMN IF NOT EXISTS fallback    text        NOT NULL DEFAULT 'allow';

-- ---------------------------------------------------------------------------
-- 6. did.ad_groups -- group discovery hints, absent everywhere
-- ---------------------------------------------------------------------------
ALTER TABLE did.ad_groups
    ADD COLUMN IF NOT EXISTS is_privileged_hint bool NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS member_count       int  NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 7. Multi-host database support -- columns absent everywhere
-- ---------------------------------------------------------------------------
-- The tables exist; these columns do not. As with everything above, the backfill that the
-- original migration paired with them is omitted: it INSERTed into did.db_hosts naming
-- hostgroup_id, which is precisely the column that was missing, so it could never have run.
-- Populating these is an application concern, not a boot-loop one.
ALTER TABLE did.db_hosts
    ADD COLUMN IF NOT EXISTS hostgroup_id INT;

ALTER TABLE did.db_synchronization
    ADD COLUMN IF NOT EXISTS host_id      INT,
    ADD COLUMN IF NOT EXISTS hostgroup_id INT,
    ADD COLUMN IF NOT EXISTS agent_vm_ip  VARCHAR(255);

ALTER TABLE did.db_user
    ADD COLUMN IF NOT EXISTS host_id           INT,
    ADD COLUMN IF NOT EXISTS default_hostgroup INT,
    ADD COLUMN IF NOT EXISTS default_schema    VARCHAR(255);

ALTER TABLE did.database_job_queue
    ADD COLUMN IF NOT EXISTS agent_vm_ip    VARCHAR(255),
    ADD COLUMN IF NOT EXISTS host_vm_ip     VARCHAR(255),
    ADD COLUMN IF NOT EXISTS hostgroup_id   INT,
    ADD COLUMN IF NOT EXISTS default_schema VARCHAR(255);

-- ---------------------------------------------------------------------------
-- 8. Policy JSON defaults -- data, and naturally idempotent
-- ---------------------------------------------------------------------------
-- Both are plain UPDATEs whose WHERE clause stops matching once applied, so replaying them on
-- every boot is free.

-- Give every existing policy the authTypes / policyMode keys the evaluator now reads.
UPDATE did.auth_policy_json
   SET policy_json = policy_json || jsonb_build_object(
           'authTypes',  COALESCE(policy_json->'authTypes',  '["ad"]'::jsonb),
           'policyMode', COALESCE(policy_json->>'policyMode', 'online'))
 WHERE policy_json IS NOT NULL
   AND (policy_json->'authTypes' IS NULL OR policy_json->'policyMode' IS NULL);

-- Retire the "notify" action. Nothing behind it ever sent a notification -- no mail, no alert,
-- no webhook -- so a policy set to notify silently allowed. Rewriting it to allow makes the
-- stored intent match the behaviour that was already happening.
UPDATE did.auth_policy_json
   SET policy_json = jsonb_set(policy_json, '{policyFlow}', '"allow"'::jsonb),
       updated_at  = now()
 WHERE lower(policy_json->>'policyFlow') = 'notify';
