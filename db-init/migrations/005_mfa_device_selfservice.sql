-- Device self-service for the AuthNull Authenticator: the columns the app's Home,
-- Account Details and Settings screens read and write, plus the stable key identity
-- its signed API calls authenticate with.
--
-- Extends did.mfa_devices / did.mfa_device_identities from 002_mfa_devices.sql.
--
-- Numbered 005 because 003 and 004 are taken (003_ad_gateways, 004_ad_enforcement_mode).
-- The loop in docker-compose.yml replays every file in this directory against the master
-- AND every org database on each boot, so a duplicate number would either lose a file in
-- a merge or apply two different things under one name.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS or guarded.

-- ---------------------------------------------------------------------------
-- did.mfa_devices
-- ---------------------------------------------------------------------------
ALTER TABLE did.mfa_devices
    -- key_id: lowercase hex sha256 over the raw DER SPKI of public_key. This is what
    -- the device presents to authenticate a self-service call.
    --
    -- Keyed on the KEY, not the push token or the device id, deliberately:
    --   * push tokens rotate, so authenticating pushToken/refresh with the push token
    --     would need the old token to authorise replacing that same token -- which
    --     fails exactly when it is needed, after the OS has already rotated it;
    --   * device ids are sequential per org, so they are enumerable and leak fleet size.
    -- A key id is stable across app reinstall, 256-bit, and derivable in SQL below.
    ADD COLUMN IF NOT EXISTS key_id text NOT NULL DEFAULT '',

    -- A SECOND keypair whose keystore ACL demands user verification
    -- (kSecAccessControlBiometryCurrentSet / setUserAuthenticationRequired(true)).
    -- The device physically cannot sign with it unless Face ID / fingerprint succeeded,
    -- which is what makes "require biometric" an assurance rather than a client-side
    -- preference. A self-reported uv=1 flag proves nothing: a repackaged APK sets it
    -- without ever prompting.
    ADD COLUMN IF NOT EXISTS biometric_public_key text,
    ADD COLUMN IF NOT EXISTS biometric_key_id text NOT NULL DEFAULT '',

    -- Device-wide push kill switch, distinct from the per-account toggle below.
    ADD COLUMN IF NOT EXISTS push_enabled boolean NOT NULL DEFAULT true,

    -- Reported at enrollment and on refresh; the only way to tell a stale app build
    -- from a server-side problem when a device stops responding.
    ADD COLUMN IF NOT EXISTS app_version text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS os_version text NOT NULL DEFAULT '',

    -- Separate from last_used_at: distinguishes "the OS rotated the token" from "this
    -- device answered a challenge", which are different diagnoses when push stops.
    ADD COLUMN IF NOT EXISTS token_updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Backfill key_id from any key already on record.
--
-- Wrapped and guarded because decode() raises on malformed base64: without this a single
-- bad row would abort the whole file, and since the loop applies it to every org database
-- one broken tenant would block the migration for all of them. Devices that fail to
-- decode keep key_id = '' and simply cannot use the self-service API until re-enrolled.
DO $$
BEGIN
    UPDATE did.mfa_devices
       SET key_id = encode(sha256(decode(public_key, 'base64')), 'hex')
     WHERE key_id = ''
       AND public_key IS NOT NULL
       AND public_key <> '';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'mfa_devices.key_id backfill skipped: %', SQLERRM;
END $$;

-- Partial index: legacy rows and any row whose key failed to decode all hold '', and
-- must not collide with each other on it. A plain unique index would reject the second
-- keyless device in an org.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_devices_org_keyid_uq
    ON did.mfa_devices (org_id, key_id) WHERE key_id <> '';

-- ---------------------------------------------------------------------------
-- did.mfa_device_identities
-- ---------------------------------------------------------------------------
-- One phone can answer for several identities (an AD account and a console account,
-- or several orgs). These preferences are per identity, not per device, because the
-- app's Account Details screen is per account.
ALTER TABLE did.mfa_device_identities
    -- Per-account push toggle. NOTE: with the Codes tab client-side only there is no
    -- fallback factor, so turning this off genuinely disables MFA for that account on
    -- this device. The challenge path reports push_disabled rather than
    -- no_device_registered so the login surface can say something true.
    ADD COLUMN IF NOT EXISTS push_enabled boolean NOT NULL DEFAULT true,

    -- Enforced server-side against biometric_public_key above. A client-side-only
    -- version of this flag would have no security value whatsoever.
    ADD COLUMN IF NOT EXISTS require_biometric boolean NOT NULL DEFAULT false,

    -- User-chosen label for this account in the app.
    ADD COLUMN IF NOT EXISTS display_name text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Deliberately NO sort_order column. Home-screen ordering spans organisations and each
-- org lives in its own database, so a per-org integer cannot express a global order.
-- Ordering stays client-side.

-- Serves the app's account list, which is always scoped to one device.
CREATE INDEX IF NOT EXISTS mfa_device_identities_device_push_idx
    ON did.mfa_device_identities (device_id, push_enabled);
