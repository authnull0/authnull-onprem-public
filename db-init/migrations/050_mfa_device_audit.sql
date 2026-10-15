-- 050: audit trail for Authenticator devices and AD sensor credentials.
--
-- Per-org database. Replayed on every start (see docker-compose.yml): everything here is
-- IF NOT EXISTS.
--
-- One row per event that changes who can approve sign-ins: a phone enrolled, a phone revoked (by
-- the user from another phone, or by an admin), an enrollment approved, a sensor credential
-- revoked. did.audit_log is a sign-in session log (browser, session length) and does not fit.

CREATE TABLE IF NOT EXISTS did.mfa_device_audit (
    id               bigserial   PRIMARY KEY,
    org_id           integer     NOT NULL,
    action           text        NOT NULL, -- enroll | revoke | approve | sensor_credential_revoke
    device_id        integer,              -- the phone acted on
    credential_id    integer,              -- the sensor credential acted on
    actor_kind       text        NOT NULL, -- admin | device | system
    actor_user_id    integer,              -- did.users.user_id, when an admin acted
    actor_device_id  integer,              -- the phone that acted, when a device acted
    ip               text,
    user_agent       text,
    reason           text,
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mfa_device_audit_org_time ON did.mfa_device_audit (org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS mfa_device_audit_device ON did.mfa_device_audit (device_id) WHERE device_id IS NOT NULL;