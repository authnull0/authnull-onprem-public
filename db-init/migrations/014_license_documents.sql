-- Uploaded licence files, in the master database.
--
-- WHY THE DATABASE AND NOT A FILE
--
-- The console lets an administrator upload their licence, and that upload has to survive:
--
--   * a container restart or image upgrade -- a container filesystem is recreated, so a licence
--     written to a path inside it disappears and the deployment looks unlicensed again;
--   * a read-only mount -- the packaged compose mounts the licence path read-only, which is correct
--     for a file an operator drops in, and unwritable by an upload handler;
--   * more than one replica -- an upload only ever reaches the container that served the request, so
--     the other replicas would still believe the licence was missing.
--
-- The database has none of those problems and is already the thing customers back up.
--
-- The file at LICENSE_FILE stays supported as the BOOTSTRAP path: an air-gapped operator can drop a
-- licence beside the compose file before first boot without touching the console. The loader prefers
-- this table and falls back to that file.
--
-- HISTORY RATHER THAN ONE ROW
--
-- Every upload inserts. The newest row wins, decided by uploaded_at, and nothing is deleted.
--
-- Deliberately not an `active` boolean: two rows both marked active is a state somebody eventually
-- reaches, and then which licence applies depends on query order. "Most recent" cannot be ambiguous.
--
-- Keeping history also makes the obvious mistake recoverable. An administrator renewing a licence can
-- upload the wrong file -- last year's, or another deployment's -- and without history that would
-- overwrite a perfectly good licence with no way back except asking Authnull to reissue.
--
-- customer, license_id and expires_at are DENORMALISED COPIES, extracted after the signature verified
-- and stored only so the console and support can read them without re-verifying. They are display
-- data. Every authorisation decision re-verifies the document itself -- see pkg/license.Verify.
--
-- Numbered 014, following 013_license_state.sql. See the note there about the 011 collision with
-- PR #14. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.license_documents (
    id          bigserial PRIMARY KEY,
    -- The signed licence exactly as uploaded. Verified before it was written, and re-verified on
    -- every read, so this column is never trusted on its own.
    document    text NOT NULL,
    license_id  text NOT NULL DEFAULT '',
    customer    text NOT NULL DEFAULT '',
    expires_at  timestamptz,
    -- did.users.user_id of the administrator who uploaded it. 0 when it arrived by any path without a
    -- session behind it.
    uploaded_by_user_id integer NOT NULL DEFAULT 0,
    uploaded_at timestamptz NOT NULL DEFAULT now()
);

-- The only read this table serves on the hot path: "give me the newest licence". Indexed so it stays
-- a single index lookup however many renewals accumulate.
CREATE INDEX IF NOT EXISTS license_documents_newest_idx
    ON did.license_documents (uploaded_at DESC);
