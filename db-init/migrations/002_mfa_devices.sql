-- Unified push-MFA device registry.
--
-- WHY: push MFA is needed for AD/domain login AND for platform (console/SSC)
-- login, but each flow had its own device store, its own enrollment token store
-- and its own invite email:
--
--   AD        did.ad_mfa_enrollments  -> did.ad_user_devices.expo_push_token
--   platform  did.mfa_methods.method_data.enrollment_token
--                                     -> did.mfa_methods.method_data.expo_push_token
--
-- One phone therefore had to enrol twice, and when Expo reported the token dead
-- only whichever flow noticed deactivated its own copy -- the other kept pushing
-- into the void indefinitely.
--
-- WHY THESE TABLES ARE KEYED ON THE DEVICE, NOT THE USER: the two sides do not
-- share a user identity. did.ad_users (email_id / mail / user_principal_name,
-- often a non-routable UPN like user@corp.local) and did.users (email_address,
-- the console signup address) are separate tables in the same id space, and the
-- same human can legitimately have different addresses in each. Keying a shared
-- registry on user_id would be wrong and keying it on email would silently
-- create two rows again.
--
-- The physical device is the join key: the Expo push token is issued by the app
-- on the phone and is identical no matter which flow enrolled it. So
-- mfa_devices holds one row per (org, push token), and mfa_device_identities
-- links any number of identities to it. When the same phone enrols from the
-- second flow the device row already exists and only a link is added -- one
-- device, one push, and one deactivation that covers every identity.
--
-- Deep links are deliberately NOT unified here: installed apps still open
-- authnull://ad-enroll and authnull://mfa-push-enroll. Both now resolve to the
-- same token store, so the app can move to a single scheme whenever it ships
-- without a server change.
--
-- Idempotent: this file is replayed against the master and every org database on
-- every boot (see docker-compose.yml). Every statement is CREATE IF NOT EXISTS
-- or an ON CONFLICT DO NOTHING backfill.

-- ── device registry ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_devices (
    id             bigserial   PRIMARY KEY,
    org_id         integer     NOT NULL,
    -- push_transport is NOT cosmetic: the legacy React Native app registers Expo
    -- tokens and the Flutter app registers FCM tokens, and both are live during
    -- the transition. The sender is chosen from this column per device.
    push_transport text        NOT NULL DEFAULT 'expo',   -- 'expo' | 'fcm'
    push_token     text        NOT NULL,
    platform       text        NOT NULL DEFAULT '',
    device_name    text        NOT NULL DEFAULT '',
    -- Public half of the keypair the app generates in the Secure Enclave /
    -- Android Keystore at enrollment, base64 DER SubjectPublicKeyInfo. Used to
    -- verify approve/deny responses -- see internal/mfapush/signing.go. NULL for
    -- devices enrolled before response signing existed.
    public_key     text,
    public_key_alg text,
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    last_used_at   timestamptz
);

-- A token identifies a device only within its transport, so the triple is the
-- key. This is the constraint CompleteEnrollment upserts against to collapse a
-- second enrolment of the same phone onto the existing row.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_devices_org_transport_token_uq
    ON did.mfa_devices (org_id, push_transport, push_token);

-- ── identity links ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_device_identities (
    id            bigserial   PRIMARY KEY,
    device_id     bigint      NOT NULL REFERENCES did.mfa_devices(id) ON DELETE CASCADE,
    org_id        integer     NOT NULL,
    tenant_id     integer     NOT NULL DEFAULT 0,
    -- 'ad_user'       -> identity_id is did.ad_users.id
    -- 'platform_user' -> identity_id is did.users.user_id
    identity_kind text        NOT NULL,
    identity_id   integer     NOT NULL,
    -- Address the invite was sent to. Kept for display and for the AD challenge
    -- path, which only knows the email. NOT a join key across identity kinds.
    email         text        NOT NULL DEFAULT '',
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- One identity points at exactly one device: re-enrolling on a new phone
-- re-points the link rather than accumulating stale devices.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_device_identities_uq
    ON did.mfa_device_identities (org_id, identity_kind, identity_id);

CREATE INDEX IF NOT EXISTS mfa_device_identities_email_idx
    ON did.mfa_device_identities (org_id, lower(email));

CREATE INDEX IF NOT EXISTS mfa_device_identities_device_idx
    ON did.mfa_device_identities (device_id);

-- ── enrollment tokens ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_device_enrollments (
    id            bigserial   PRIMARY KEY,
    org_id        integer     NOT NULL,
    tenant_id     integer     NOT NULL DEFAULT 0,
    identity_kind text        NOT NULL,
    identity_id   integer     NOT NULL,
    email         text        NOT NULL,
    token         text        NOT NULL,
    used          boolean     NOT NULL DEFAULT false,
    expires_at    timestamptz NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS mfa_device_enrollments_token_uq
    ON did.mfa_device_enrollments (token);

CREATE INDEX IF NOT EXISTS mfa_device_enrollments_pending_idx
    ON did.mfa_device_enrollments (org_id, lower(email))
    WHERE used = false;

-- ── backfill: AD devices ───────────────────────────────────────────────────
-- Existing on-prem installs have live rows in both old stores. Both backfills
-- are ON CONFLICT DO NOTHING so replaying this file is harmless.

DO $$
BEGIN
    IF to_regclass('did.ad_user_devices') IS NULL THEN
        RAISE NOTICE '002_mfa_devices: did.ad_user_devices absent, skipping AD backfill';
        RETURN;
    END IF;

    INSERT INTO did.mfa_devices (org_id, push_transport, push_token, platform, device_name, is_active, created_at, last_used_at)
    SELECT d.org_id,
           'expo',
           d.expo_push_token,
           COALESCE(d.platform, ''),
           COALESCE(d.device_name, ''),
           d.is_active,
           COALESCE(d.created_at, now()),
           d.last_used_at
    FROM did.ad_user_devices d
    WHERE d.expo_push_token IS NOT NULL AND d.expo_push_token <> ''
    ON CONFLICT (org_id, push_transport, push_token) DO NOTHING;

    INSERT INTO did.mfa_device_identities (device_id, org_id, tenant_id, identity_kind, identity_id, email, created_at)
    SELECT nd.id,
           d.org_id,
           COALESCE(d.tenant_id, 0),
           'ad_user',
           d.user_id,
           COALESCE(d.email, ''),
           COALESCE(d.created_at, now())
    FROM did.ad_user_devices d
    JOIN did.mfa_devices nd
      ON nd.org_id = d.org_id AND nd.push_transport = 'expo' AND nd.push_token = d.expo_push_token
    WHERE d.expo_push_token IS NOT NULL AND d.expo_push_token <> ''
    ON CONFLICT (org_id, identity_kind, identity_id) DO NOTHING;
END $$;

-- ── backfill: platform devices ─────────────────────────────────────────────
-- The token lives in did.mfa_methods.method_data JSON. org_id is not on that
-- table, so it comes from did.users. Rows whose user has no org_id are skipped
-- rather than defaulted, since a wrong org would leak a push across tenants.

DO $$
BEGIN
    IF to_regclass('did.mfa_methods') IS NULL OR to_regclass('did.users') IS NULL THEN
        RAISE NOTICE '002_mfa_devices: did.mfa_methods or did.users absent, skipping platform backfill';
        RETURN;
    END IF;

    INSERT INTO did.mfa_devices (org_id, push_transport, push_token, platform, device_name, is_active, created_at, last_used_at)
    SELECT u.org_id,
           'expo',
           m.method_data->>'expo_push_token',
           COALESCE(m.method_data->>'platform', ''),
           COALESCE(m.method_data->>'device_name', ''),
           m.enabled,
           COALESCE(m.created_at, now()),
           m.last_used_at
    FROM did.mfa_methods m
    JOIN did.users u ON u.user_id = m.user_id
    WHERE m.method_type = 'push'
      AND u.org_id IS NOT NULL
      AND COALESCE(m.method_data->>'expo_push_token', '') <> ''
    ON CONFLICT (org_id, push_transport, push_token) DO NOTHING;

    INSERT INTO did.mfa_device_identities (device_id, org_id, tenant_id, identity_kind, identity_id, email, created_at)
    SELECT nd.id,
           u.org_id,
           0,
           'platform_user',
           m.user_id,
           COALESCE(u.email_address, ''),
           COALESCE(m.created_at, now())
    FROM did.mfa_methods m
    JOIN did.users u ON u.user_id = m.user_id
    JOIN did.mfa_devices nd
      ON nd.org_id = u.org_id AND nd.push_transport = 'expo' AND nd.push_token = m.method_data->>'expo_push_token'
    WHERE m.method_type = 'push'
      AND u.org_id IS NOT NULL
      AND COALESCE(m.method_data->>'expo_push_token', '') <> ''
    ON CONFLICT (org_id, identity_kind, identity_id) DO NOTHING;
END $$;

-- NOTE: the old columns are intentionally left in place. did.ad_user_devices and
-- did.mfa_methods.method_data.expo_push_token are no longer read -- the Go code
-- reads did.mfa_devices only -- but dropping them here would make this migration
-- irreversible against a running install. Retire them in a later migration once
-- the unified registry has been verified in the field.
