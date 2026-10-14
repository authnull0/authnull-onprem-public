-- Endpoint self-enrolment, in each ORGANISATION database.
--
-- An administrator creates an enrolment token for one gateway. A machine that
-- can reach that gateway runs one command, the same on every machine; the
-- gateway passes the token, the machine's hostname and the address it OBSERVED
-- to the control plane, which creates the endpoint (or finds it, for a re-run),
-- issues its own reconcile key and returns the setup script. The first account
-- scan is queued with it. Hundreds of machines then enrol through whatever
-- already runs commands on them -- Ansible, cloud-init, SSM -- with nobody in
-- the console per machine.
--
-- Only the token's SHA-256 is stored. A token is bound to its gateway, expires,
-- has a use limit and can be revoked. Every use is recorded below.
--
-- The gateway's host PUBLIC key is kept on did.jump_server so the console can
-- print the command with the key pinned: the script arrives over SSH, and a
-- pinned host key is what stops anyone between the machine and the gateway
-- from substituting their own.
--
-- Numbered 027, following 026_gateway_job_backoff.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.endpoint_enrol_tokens (
    id             uuid        PRIMARY KEY,
    org_id         integer     NOT NULL,
    jump_server_id integer     NOT NULL,
    name           text,
    token_hash     text        NOT NULL UNIQUE,
    expires_at     timestamptz NOT NULL,
    max_uses       integer     NOT NULL CHECK (max_uses > 0),
    uses           integer     NOT NULL DEFAULT 0,
    created_by     integer,
    created_at     timestamptz NOT NULL DEFAULT now(),
    revoked_at     timestamptz
);

CREATE INDEX IF NOT EXISTS endpoint_enrol_tokens_by_gateway ON did.endpoint_enrol_tokens (org_id, jump_server_id);

CREATE TABLE IF NOT EXISTS did.endpoint_enrolments (
    id             bigserial   PRIMARY KEY,
    org_id         integer     NOT NULL,
    token_id       uuid        NOT NULL,
    jump_server_id integer     NOT NULL,
    machine_id     bigint      NOT NULL,
    hostname       text,
    address        text        NOT NULL,
    created        boolean     NOT NULL,
    at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS endpoint_enrolments_by_token ON did.endpoint_enrolments (org_id, token_id, at DESC);

ALTER TABLE did.jump_server ADD COLUMN IF NOT EXISTS host_public_key text;