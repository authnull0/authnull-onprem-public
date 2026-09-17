-- Add did.mfa_devices.public_key and .public_key_alg.
--
-- WHY THIS IS A SEPARATE FILE
--
-- 002_mfa_devices.sql already DECLARES both columns. It has declared them for a while. They do not
-- exist on the alpha org database, and they never will, because that file is
--
--     CREATE TABLE IF NOT EXISTS did.mfa_devices (...)
--
-- and the table already existed when the columns were added to the file. IF NOT EXISTS made the
-- whole statement a no-op, so the edit has been inert on every database that had already run it.
-- Nothing errored. Nothing warned. The file and the schema simply disagree, and reading the file
-- tells you the wrong thing.
--
-- That is the same trap 007 documents: CREATE TABLE IF NOT EXISTS is idempotent but NOT convergent.
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS is both, which is why the fix lives here instead of as
-- another edit to 002.
--
-- WHAT WAS BROKEN
--
-- These two columns hold the device's ECDSA public key. Without them:
--
--   * CompleteEnrollment writes public_key, so enrollment fails outright -- no device can register;
--   * VerifyRequest and VerifyResponse read device.PublicKey, so every signed call under
--     /api/v1/device/* and every challenge response fails.
--
-- In other words the entire Authenticator flow, on a database where every other table looked
-- correct. It surfaced only as a NOTICE from 005's guarded key_id backfill --
-- "column public_key does not exist" -- which is the one place anything in the system mentioned it.
--
-- Safe to run repeatedly.

ALTER TABLE did.mfa_devices
    -- base64 DER SPKI of the device's signing key, and the algorithm label ("ecdsa-p256").
    -- Nullable with no default: a legacy row genuinely has no key, and '' would be
    -- indistinguishable from one that does, which the signature paths check for explicitly.
    ADD COLUMN IF NOT EXISTS public_key     text,
    ADD COLUMN IF NOT EXISTS public_key_alg text;

-- Backfill key_id for any device that already carries a key.
--
-- 005 tried this and skipped, because public_key did not exist yet -- its EXCEPTION handler caught
-- the failure and logged a NOTICE, which is exactly why the whole file did not abort for every
-- other tenant. Now that the column exists, the backfill can actually run.
--
-- Same guard for the same reason: decode() raises on malformed base64, and this directory is
-- replayed against every org database, so one bad row must not block the file for all of them.
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
