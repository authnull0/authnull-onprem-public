-- Work the control plane hands to SSH gateways, in each ORGANISATION database.
--
-- WHY A NEW TABLE
--
-- Gateways sit behind NAT and the control plane cannot call them, so work is
-- queued here and a gateway collects it: its heartbeat answer says how many jobs
-- wait, and it claims them over its own authenticated channel. The older
-- did.jump_server_endpoint_jobs table is a Guacamole-era leftover nothing reads;
-- it is left alone rather than repurposed.
--
-- A JOB'S LIFE
--
--   queued   -> claimed  a gateway took it; lease_expires_at bounds how long it
--                        may hold it. A gateway that goes quiet loses the claim
--                        when the lease runs out and the job can be claimed again.
--   claimed  -> done     reported finished, with a result.
--   claimed  -> queued   reported failed with attempts left.
--   claimed  -> failed   reported failed on its last attempt.
--   any open -> expired  not finished by not_after.
--
-- The vault releases a job's secret only while the job is claimed, by the
-- gateway that holds the claim, inside its lease -- which is what "a reconcile
-- key is only ever in a gateway's hands for one job" rests on. A finished job's
-- secret can never be released again.
--
-- ONE OPEN JOB PER ENDPOINT AND KIND
--
-- Pressing Rescan twice queues one scan, not two: the partial unique index makes
-- a second open job for the same endpoint and kind unrepresentable.
--
-- Numbered 023, following 022_vault.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.gateway_jobs (
    id               uuid        PRIMARY KEY,
    org_id           integer     NOT NULL,
    jump_server_id   integer     NOT NULL,
    endpoint_id      bigint      NOT NULL,
    kind             text        NOT NULL
                     CHECK (kind IN ('scan_accounts', 'rotate_credential')),
    payload          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    status           text        NOT NULL DEFAULT 'queued'
                     CHECK (status IN ('queued', 'claimed', 'done', 'failed', 'expired')),
    attempts         integer     NOT NULL DEFAULT 0,
    max_attempts     integer     NOT NULL DEFAULT 3,
    lease_expires_at timestamptz,
    claimed_at       timestamptz,
    completed_at     timestamptz,
    not_after        timestamptz NOT NULL DEFAULT (now() + interval '1 day'),
    result           jsonb,
    error            text,
    created_by       integer,
    created_at       timestamptz NOT NULL DEFAULT now()
);

-- did-schema-init replays every migration on each `up`. 024 replaces this index
-- with a per-account one and allows two open jobs per endpoint and kind, so
-- recreating it on a replay would fail on that data and stop the stack. Only
-- create it while 024's index does not exist yet.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                   WHERE schemaname = 'did' AND indexname = 'gateway_jobs_one_open_per_account') THEN
        CREATE UNIQUE INDEX IF NOT EXISTS gateway_jobs_one_open
            ON did.gateway_jobs (org_id, endpoint_id, kind) WHERE status IN ('queued', 'claimed');
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS gateway_jobs_for_gateway
    ON did.gateway_jobs (org_id, jump_server_id, status, created_at);