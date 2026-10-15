-- 048: Authenticator enrollment campaigns.
--
-- Per-org database. Replayed on every start (see docker-compose.yml): everything here is
-- IF NOT EXISTS.
--
-- A campaign mails an Authenticator invite to a set of users who have no device yet -- every AD
-- or platform user, the members of some groups, or a list -- and, when it has a deadline, re-sends
-- the invite on the chosen days before it to whoever still has not enrolled.
--
-- mfa_campaign_recipients is both the record of what was sent and the guard against sending it
-- twice: a send happens only after its (campaign, user, stage) row was inserted, so two replicas
-- running the daily reminder job cannot both mail the same person.

CREATE TABLE IF NOT EXISTS did.mfa_enrollment_campaigns (
    id             serial      PRIMARY KEY,
    org_id         integer     NOT NULL,
    identity_kind  text        NOT NULL,             -- ad_user | platform_user
    scope          text        NOT NULL,             -- all | groups | users
    target_ids     jsonb       NOT NULL DEFAULT '[]', -- group ids or user ids, per scope
    tenant_id      integer     NOT NULL DEFAULT 0,    -- 0: every tenant
    deadline       timestamptz,
    reminder_days  jsonb       NOT NULL DEFAULT '[]', -- days before the deadline
    status         text        NOT NULL DEFAULT 'running', -- running | done
    targets        integer     NOT NULL DEFAULT 0,
    invited        integer     NOT NULL DEFAULT 0,
    skipped        integer     NOT NULL DEFAULT 0,
    failed         integer     NOT NULL DEFAULT 0,
    created_by     integer,
    created_at     timestamptz NOT NULL DEFAULT now(),
    finished_at    timestamptz
);

CREATE INDEX IF NOT EXISTS mfa_enrollment_campaigns_deadline
    ON did.mfa_enrollment_campaigns (deadline) WHERE deadline IS NOT NULL;

CREATE TABLE IF NOT EXISTS did.mfa_campaign_recipients (
    id           serial      PRIMARY KEY,
    campaign_id  integer     NOT NULL REFERENCES did.mfa_enrollment_campaigns (id),
    identity_id  integer     NOT NULL,
    tenant_id    integer     NOT NULL DEFAULT 0,
    email        text        NOT NULL,
    stage        text        NOT NULL, -- invite | reminder:<days before deadline>
    sent_at      timestamptz NOT NULL DEFAULT now(),
    error        text
);

CREATE UNIQUE INDEX IF NOT EXISTS mfa_campaign_recipients_once
    ON did.mfa_campaign_recipients (campaign_id, identity_id, stage);