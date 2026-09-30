-- Session recordings for the SSH proxy: where a recording came from, what it is of,
-- where its bytes live, and how long it is kept.
--
-- WHY
--
-- did.jump_server_recordings was built for the Guacamole web-terminal flow, where a
-- recording belongs to a row in did.jump_servers_connections -- a provisioned credential
-- carrying an epm_user_id, a hashed_password, a protocol and a port. An SSH proxy session
-- has none of those. It has no provisioned credential at all, which is the point of the
-- design: authority is a certificate minted per session and gone in five minutes.
--
-- So an SSH recording arrives with nothing to put in jump_server_connection_id, it takes
-- the column default of 0, and the only route from a recording back to the proxy that
-- made it does not exist. "Show me what happened on this jump server" is unanswerable.
-- These columns make the recording describe itself instead of borrowing a description
-- from a connection record that no longer models anything.
--
-- WHY target_account AND target_host RATHER THAN endpoint
--
-- endpoint is a free-text string and has been used for whatever the caller had. The two
-- questions an audit actually asks are "what did this person do" and "who touched this
-- host", and the second needs the host as a column you can filter and index, not a
-- substring. They are separate columns because they are separate facts: on a shared
-- account, ten people are 'oracle' and the host is what distinguishes what they reached.
--
-- WHY storage_backend AND storage_key RATHER THAN A URL
--
-- recording_url holds a PRESIGNED S3 URL today. That is a credential with an expiry
-- stored as data: anyone who can read the API response can forward it, it goes stale, and
-- the refresh path that exists to renew it parses X-Amz-Date out of the stored string and
-- fails the whole listing when a row is not an S3 URL. It also cannot express an on-prem
-- deployment with no object store at all.
--
-- A backend plus a key says where the bytes are without granting anyone access to them.
-- Access is then authorised per request, against the caller's session, by whatever serves
-- the content -- so revoking somebody's access actually revokes it.
--
-- recording_url stays, and Guacamole rows keep using it. New SSH rows leave it empty.
--
-- WHY hmac AND size_bytes
--
-- The proxy writes an HMAC sidecar next to every recording, and sshproxy.VerifyRecording
-- already checks a file against it. Carrying the digest here is what lets the console say
-- verified / altered / no sidecar rather than asking people to trust the database.
-- size_bytes is for capacity: recordings are unbounded today and the fail-closed default
-- means a full disk on a jump box stops SSH for everyone.
--
-- WHY expires_at
--
-- There is no retention anywhere in the product. A retention control in the console with
-- nothing enforcing it would be a promise the software does not keep, so the column comes
-- before the control does.
--
-- WHY identity_method AND presence_method
--
-- The recorder currently stamps the literal string "publickey+mfa-push" into every
-- recording header. That is true today and will not always be: identity may come from a
-- verifiable credential rather than a registered key, and presence may come from a signed
-- presentation rather than an Okta push. Two small columns now mean that is a new VALUE
-- later rather than a migration against live evidence. They are also what a decision log
-- will join on when it arrives.
--
-- Everything is NULLABLE. A Guacamole row has no honest value for any of it, and a
-- default would assert something untrue about a recording that is evidence.

ALTER TABLE did.jump_server_recordings
    ADD COLUMN IF NOT EXISTS jump_server_id   integer      NULL,
    ADD COLUMN IF NOT EXISTS target_account   varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS target_host      varchar(255) NULL,
    ADD COLUMN IF NOT EXISTS storage_backend  varchar(16)  NULL,
    ADD COLUMN IF NOT EXISTS storage_key      varchar(512) NULL,
    ADD COLUMN IF NOT EXISTS hmac             varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS size_bytes       bigint       NULL,
    ADD COLUMN IF NOT EXISTS expires_at       timestamptz  NULL,
    ADD COLUMN IF NOT EXISTS identity_method  varchar(32)  NULL,
    ADD COLUMN IF NOT EXISTS presence_method  varchar(32)  NULL;

-- Backfill the Guacamole rows through the connection they were created against, so one
-- query answers "recordings for this jump server" for both flows. Rows whose connection
-- has gone, or which never had one, keep NULL -- there is no jump server to name.
UPDATE did.jump_server_recordings r
   SET jump_server_id = c.jump_server_id
  FROM did.jump_servers_connections c
 WHERE r.jump_server_connection_id = c.id
   AND r.jump_server_id IS NULL
   AND c.jump_server_id <> 0;

-- The per-proxy recordings list, newest first. session_recording_time is a varchar on
-- this table and sorts lexically; it is included so the index still serves the ORDER BY
-- the existing listing does, rather than leaving it to a sort of the whole partition.
CREATE INDEX IF NOT EXISTS jump_server_recordings_jump_server_idx
    ON did.jump_server_recordings (jump_server_id, session_recording_time DESC);

-- Filtering a proxy's recordings by which machine was reached.
CREATE INDEX IF NOT EXISTS jump_server_recordings_target_host_idx
    ON did.jump_server_recordings (jump_server_id, target_host);

-- The retention sweeper's only query: rows whose bytes are due for deletion.
CREATE INDEX IF NOT EXISTS jump_server_recordings_expires_at_idx
    ON did.jump_server_recordings (expires_at)
    WHERE expires_at IS NOT NULL;


-- ---------------------------------------------------------------------------
-- did.user_ssh_keys: two columns that are cheap now and expensive later.
-- ---------------------------------------------------------------------------
--
-- subject_did binds a registered key to a decentralised identifier, so a key can be
-- something a credential asserts rather than something an administrator typed. Nothing
-- reads it yet. It is here because adding an identity column to a key registry that is
-- already the sole source of truth for production SSH access, with rows that predate it,
-- is materially worse than adding it while the table is young.
--
-- status is the same argument for self-service enrolment. Today an administrator
-- registers every key by hand, which does not survive two hundred operators. The flow
-- that fixes it needs a key to exist in a state that grants nothing yet, and retrofitting
-- that onto live rows means every existing row needs a defensible default and every read
-- needs a filter that did not exist when it was written.
--
-- DEFAULT 'active' is correct for every row that exists: they were all registered by an
-- administrator, which is precisely what approval will mean.

ALTER TABLE did.user_ssh_keys
    ADD COLUMN IF NOT EXISTS subject_did varchar(255) NULL,
    ADD COLUMN IF NOT EXISTS status      varchar(16)  NOT NULL DEFAULT 'active';

-- Resolution must never return a key that is pending approval. The partial index matches
-- the shape the resolver filters on, so the guard stays cheap once the flow exists.
CREATE INDEX IF NOT EXISTS user_ssh_keys_pending_idx
    ON did.user_ssh_keys (org_id, status)
    WHERE status <> 'active';
