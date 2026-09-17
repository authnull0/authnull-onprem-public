-- SSH public keys registered against a user, in each ORGANISATION database.
--
-- This table is the SSH proxy's entire notion of identity, so most of what follows is about
-- why it has to be, rather than about the columns.
--
-- WHY A KEY AND NOT THE USERNAME
--
-- The SSH protocol gives a proxy no identity channel. The username field carries the TARGET
-- (`account@host`, the CyberArk PSM convention), and everything a client asserts about itself
-- there is attacker-chosen. The only thing a client proves before a session exists is
-- possession of a private key, so possession of a private key whose public half is in this
-- table is the anchor -- the SSH counterpart to resolving an AD principal through did.ad_users.
--
-- The consequence that matters: the principal is resolved HERE and nowhere else. In particular
-- it is never taken from did.jump_servers_connections.user_id, because on a shared account like
-- `oracle` that column holds whoever last checked the account out. Pushing to that person's
-- phone for a session somebody else opened is the precise failure this design exists to
-- prevent.
--
-- A key alone still cannot authenticate. It is the first factor; the proxy chains it to a push
-- approval and refuses the session if either half is missing.
--
-- FINGERPRINT IS THE LOOKUP KEY
--
-- SHA256 in OpenSSH's own presentation -- `SHA256:` followed by unpadded standard base64,
-- exactly what ssh.FingerprintSHA256 and `ssh-keygen -lf` produce. Stored rather than derived
-- at query time so the lookup is an index hit on a connection that has not authenticated yet.
--
-- MD5 fingerprints are not accepted anywhere. They collide, and a collision here is an
-- impersonation.
--
-- WHY THE UNIQUE INDEX IS PARTIAL
--
-- Two live keys with the same fingerprint in one org would make resolution ambiguous, and the
-- only safe answer to an ambiguous identity is to refuse the connection -- so this makes the
-- state unreachable instead. It is scoped `WHERE revoked_at IS NULL` so that revoking a key and
-- registering it again later works, which is ordinary laptop-replacement housekeeping and would
-- otherwise fail against a total unique constraint with no way for an administrator to see why.
--
-- The resolver still refuses duplicates on its own rather than trusting this index, because the
-- index does not cover revoked rows and because a resolver that assumes at most one row is one
-- schema change away from silently picking an arbitrary user.
--
-- REVOCATION IS A TIMESTAMP, NOT A DELETE
--
-- last_used_at on a deleted row is gone, and after an incident the question is always "what did
-- that key reach, and when did it stop". Revoked rows are also what make re-registration of a
-- previously withdrawn key visible instead of looking like a first registration.
--
-- WHO WRITES last_used_at
--
-- The proxy, once per successful authentication, from verifiedPublicKeyCallback -- the callback
-- that runs on the key the client actually signed with. NOT from the offer callback, which fires
-- speculatively as the client's agent asks "would you take this one?" about every key it holds,
-- several times per connection, only one of which is real.
--
-- Nullable on purpose: NULL means "registered and never used", which is a different fact from
-- "used at the epoch" and is the one stale-key review actually asks about.
--
-- Numbered 015, following 014_license_documents.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.user_ssh_keys (
    id           bigserial PRIMARY KEY,

    -- Denormalised copy of the owning organisation. Every org already has its own database, so
    -- this is redundant for isolation -- it is here because did.users carries org_id too, and
    -- because it lets the unique index below say what it means without a join.
    org_id       integer NOT NULL,

    -- did.users.user_id. No foreign key: did.users has no unique constraint this could
    -- reference, and the rest of the PAM schema does not use them either (see
    -- did.jump_server_recordings). The resolver joins and refuses a key whose user has gone.
    user_id      integer NOT NULL,

    -- `SHA256:<unpadded base64>`, as ssh.FingerprintSHA256 renders it. 128 is generous: a
    -- SHA-256 fingerprint is 50 characters including the prefix.
    fingerprint  varchar(128) NOT NULL,

    -- The key in authorized_keys form, kept so an administrator can see what was registered and
    -- so the fingerprint can be recomputed if the format ever changes. Not used for matching.
    public_key   text NOT NULL,

    -- ssh-ed25519, ecdsa-sha2-nistp256, ssh-rsa, ... Display and policy only.
    key_type     varchar(64) NOT NULL DEFAULT '',

    -- Operator-supplied, e.g. "work laptop". Free text, never interpreted.
    label        varchar(255) NOT NULL DEFAULT '',

    created_at   timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- NULL until the key authenticates a session. Written only by the proxy.
    last_used_at timestamp without time zone,

    -- NULL while the key is live. Set on revocation; the row is never deleted.
    revoked_at   timestamp without time zone
);

-- The proxy's hot path: one index hit, on an unauthenticated connection, before anything else
-- happens. Partial so that revoking and re-registering the same key is possible -- see above.
CREATE UNIQUE INDEX IF NOT EXISTS user_ssh_keys_active_fingerprint_idx
    ON did.user_ssh_keys (org_id, fingerprint)
    WHERE revoked_at IS NULL;

-- Listing a user's keys in the console, and finding every key to revoke when a person leaves.
CREATE INDEX IF NOT EXISTS user_ssh_keys_user_idx
    ON did.user_ssh_keys (org_id, user_id);
