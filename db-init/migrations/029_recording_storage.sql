-- Recording storage, in each ORGANISATION database: where an organisation's SSH
-- session recordings are kept, and how each recording got there.
--
-- WHY
--
-- Ingest (018) writes every recording to the control plane's own volume. That
-- is one disk, sized by whoever installed the service, holding evidence that
-- grows without bound. Customers keep evidence in their own object store --
-- S3 (or anything that speaks its API: MinIO, Wasabi, Ceph) or Google Cloud
-- Storage -- under their own retention, locks and encryption.
--
-- HOW A RECORDING MOVES
--
--   1. Ingest writes it to the local volume, as before, and marks it
--      offload_state = 'pending' when the organisation stores elsewhere.
--   2. The offloader uploads it, checks the stored size, and points the row at
--      the object (storage_backend, storage_bucket, storage_object). Only then
--      is the local copy deleted; local_delete_pending covers a crash between
--      the two, so a copy is never orphaned on the volume.
--   3. A failed upload is retried, 30s doubling to 5 minutes, without limit: a
--      bucket that is down for a day loses nothing, it only delays.
--   4. A local copy that no longer matches its ingest digest is never uploaded
--      ('held'): copying altered evidence into the archive would launder it.
--
-- storage_key keeps its meaning -- <org>/<jump server>/<recording>.cast, the
-- recording's identity and the key ingest's upsert matches on -- whichever
-- backend holds the bytes.
--
-- CREDENTIALS
--
-- Never in this table. Either the service's own cloud identity is used
-- ('ambient': an instance role, workload identity, environment), or the
-- credential is sealed in the vault (022) as kind 'storage_credential', at
-- endpoint 0 -- it belongs to the organisation, not to an endpoint.
--
-- Numbered 029, following 028_endpoint_decommission.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.recording_storage (
    org_id               integer     PRIMARY KEY,
    provider             text        NOT NULL DEFAULT 'local'
                         CHECK (provider IN ('local', 's3', 'gcs')),
    bucket               text,
    region               text,
    endpoint             text,
    prefix               text        NOT NULL DEFAULT '',
    path_style           boolean     NOT NULL DEFAULT false,
    sse                  text        NOT NULL DEFAULT ''
                         CHECK (sse IN ('', 'AES256', 'aws:kms')),
    kms_key_id           text,
    credential_mode      text        NOT NULL DEFAULT 'ambient'
                         CHECK (credential_mode IN ('ambient', 'static')),
    credential_secret_id uuid,
    revision             integer     NOT NULL DEFAULT 1,
    updated_by           integer,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    last_test_at         timestamptz,
    last_test_ok         boolean,
    last_test_error      text
);

ALTER TABLE did.jump_server_recordings
    ADD COLUMN IF NOT EXISTS storage_bucket       text,
    ADD COLUMN IF NOT EXISTS storage_object       text,
    ADD COLUMN IF NOT EXISTS offload_state        text
                             CHECK (offload_state IN ('pending', 'done', 'held')),
    ADD COLUMN IF NOT EXISTS offload_attempts     integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS offload_next_at      timestamptz,
    ADD COLUMN IF NOT EXISTS offload_error        text,
    ADD COLUMN IF NOT EXISTS offloaded_at         timestamptz,
    ADD COLUMN IF NOT EXISTS local_delete_pending boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS jump_server_recordings_offload_due
    ON did.jump_server_recordings (offload_next_at)
    WHERE offload_state = 'pending';

CREATE INDEX IF NOT EXISTS jump_server_recordings_local_delete
    ON did.jump_server_recordings (id)
    WHERE local_delete_pending;

-- The vault holds the organisation's storage credential.
ALTER TABLE did.vault_secrets DROP CONSTRAINT IF EXISTS vault_secrets_kind_check;
ALTER TABLE did.vault_secrets ADD CONSTRAINT vault_secrets_kind_check
    CHECK (kind IN ('reconcile_key', 'grant_password', 'grant_key', 'storage_credential'));
