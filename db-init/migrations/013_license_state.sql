-- Trial state for the on-premise licence.
--
-- WHY
--
-- The on-premise package is downloaded from a public repository and installed with no involvement
-- from Authnull, so there is nothing to activate: the trial has to start itself. First boot records a
-- timestamp here, and thirty days later the console goes read-only. Enforcement -- EvaluateAuth, the
-- challenge lifecycle, the sensor -- is never affected, so a lapse costs the customer administration
-- rather than authentication. See pkg/license.
--
-- ONE ROW, ENFORCED
--
-- A licence covers the deployment, not an organisation, so the CHECK constraint pins the primary key
-- to 1. Without it, two containers booting simultaneously could each insert a row and later reads
-- would take whichever the planner returned -- meaning the trial length would depend on which row
-- won. That is the same class of bug that migration 010 fixed for ad_mfa_provider_config, and it is
-- cheaper to prevent here than to reconcile later.
--
-- MASTER DATABASE ONLY, IN INTENT
--
-- This directory is replayed against the master database AND every organisation database on each
-- boot, so the table will exist in all of them. Only the master copy is read. Harmless, and better
-- than a migration that has to know which database it is running against.
--
-- WHAT THE SIGNATURE IS FOR, AND WHAT IT IS NOT FOR
--
-- signature is an HMAC-SHA256 over the timestamp, keyed on the deployment's own ENCRYPTION_KEY. It
-- makes a casual UPDATE visible to anyone looking -- a support engineer can distinguish "somebody
-- edited this" from "this install really is 12 days old".
--
-- It is NOT an anti-tamper control and must not be treated as one. The customer owns this database.
-- They can drop the volume and reinstall, or move the clock. That is not preventable, and the usual
-- mitigations (hardware fingerprints, hidden markers, refusing to start when time goes backwards)
-- are all defeatable while breaking legitimate restores, migrations and snapshots for honest users.
-- A mismatched signature is therefore LOGGED and the stored value is honoured, because a restored
-- backup is far more likely than fraud.
--
-- Numbered 013, not 011. PR #14 landed its own 011_user_mfa_config_unique.sql concurrently, so two
-- different migrations briefly shared the number 011. The runner globs and sorts the directory with
-- no ledger, so a duplicate number is harmless at runtime -- but it makes the sequence ambiguous to
-- read and invites the next two people to collide on the same number again. Renumbered rather than
-- left to rot. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.license_state (
    id               smallint PRIMARY KEY DEFAULT 1,
    trial_started_at timestamptz NOT NULL,
    signature        text NOT NULL DEFAULT '',
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT license_state_single_row CHECK (id = 1)
);

-- The constraint is added separately for tables created before this migration existed, so a replay
-- against an older database converges rather than silently skipping it. Guarded because ADD
-- CONSTRAINT is not idempotent.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'license_state_single_row'
           AND conrelid = 'did.license_state'::regclass
    ) THEN
        ALTER TABLE did.license_state
            ADD CONSTRAINT license_state_single_row CHECK (id = 1);
        RAISE NOTICE 'license_state_single_row constraint added';
    END IF;
END $$;
