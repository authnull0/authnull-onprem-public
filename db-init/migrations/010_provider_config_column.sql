-- Make did.ad_mfa_provider_config.config storable, and make one row per org enforceable.
--
-- WHY: SAVING A PROVIDER HAS NEVER WORKED
--
-- The column is jsonb. ProviderConfigStore.Save marshals the config to JSON and then ENCRYPTS it,
-- so the value written is AES-GCM base64(nonce||ciphertext) -- not JSON. Postgres rejects it:
--
--   INSERT INTO did.ad_mfa_provider_config (provider, config, ...)
--        VALUES ('authnull', 'eZ8/Pu7/kncyuTGI3TtzpjdJQ7xdhj8NG3+UpMiD', ...)
--   ERROR: invalid input syntax for type json (SQLSTATE 22P02)
--
-- Every attempt to select an MFA provider in the console has failed with a 500 for as long as the
-- encryption has been there, and both databases hold zero rows to prove it. The consequence is not
-- an error anybody chased: GetProviderForOrg falls back to MFA_PROVIDER when no row exists, so the
-- product kept working on the deployment default and nothing said the choice had not been saved.
--
-- That fallback is what made this invisible, and it is also why it matters. On the env default a
-- vendor provider inherits the DEPLOYMENT's credentials too (okta.go falls back to OKTA_DOMAIN /
-- OKTA_API_TOKEN), so a second tenant onboarded onto the same box has its users looked up in the
-- first tenant's Okta org.
--
-- The value is ciphertext, so the column is text. Nothing reads it with jsonb operators -- the only
-- reference anywhere is the CREATE TABLE in 01_schema.sql -- so nothing is lost by the change.
--
-- Numbered 010: 001-009 are taken. Safe to run repeatedly.

-- 1. jsonb -> text.
--
-- Guarded rather than a bare ALTER: this directory is replayed on every boot, and an unconditional
-- ALTER COLUMN TYPE rewrites the whole table each time even when the type already matches. jsonb to
-- text needs no USING clause -- Postgres renders the existing value as its text form -- and both
-- databases are empty here anyway.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'did' AND table_name = 'ad_mfa_provider_config'
           AND column_name = 'config' AND data_type <> 'text'
    ) THEN
        ALTER TABLE did.ad_mfa_provider_config ALTER COLUMN config TYPE text;
        RAISE NOTICE 'ad_mfa_provider_config.config converted to text';
    END IF;
END $$;

-- 2. One row per org.
--
-- The table's PRIMARY KEY is `id`, a bare sequence, and there is no constraint on org_id at all --
-- but every read is First() by org_id and Save is a FirstOrCreate on org_id. So two concurrent
-- saves could leave two rows for one organisation and reads would pick whichever the planner
-- returned, meaning an admin could set a provider, see it saved, and have the old one still served.
--
-- Safe to add now precisely because saving has never worked: there are no rows, so there are no
-- duplicates to reconcile first.
CREATE UNIQUE INDEX IF NOT EXISTS ad_mfa_provider_config_org_uq
    ON did.ad_mfa_provider_config (org_id);
